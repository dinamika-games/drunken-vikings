"""
Study a recording made with dev/rowing/record_rowing.gd.

Print how well the vision saw the players (how often, how fast, which key
points), and, for each signal of the rowing (see RowingSignals), how much it
moves against its noise and whether it swings in a rhythm (the strokes), over
the whole recording and in windows of a few seconds between the marks.

With --plot, draw the signals over time with the marks into a PNG.

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/rowing/analyze.py <recording.jsonl> [--plot out.png] [--window 10]
"""

import argparse
import collections
import json
import pathlib
import sys

import numpy as np

KEYPOINTS = [
    "nose",
    "left eye",
    "right eye",
    "left ear",
    "right ear",
    "left shoulder",
    "right shoulder",
    "left elbow",
    "right elbow",
    "left wrist",
    "right wrist",
    "left hip",
    "right hip",
    "left knee",
    "right knee",
    "left ankle",
    "right ankle",
]

# NOTE (mristin):
# As in the vision service: a key point counts from this score on.
THRESHOLD = 0.3

# A stroke takes between these many seconds.
MIN_PERIOD = 0.8
MAX_PERIOD = 6.0

# The rate to which we resample the signals, in Hz.
RATE = 20.0


class Player:
    def __init__(self, names):
        self.names = names
        self.t = []
        self.signals = []
        self.scores = []
        self.sources = collections.Counter()

    def finish(self):
        self.t = np.array(self.t)
        self.signals = np.array(self.signals, dtype=float).reshape(-1, len(self.names))
        self.scores = np.array(self.scores, dtype=float).reshape(-1, len(KEYPOINTS))


def load(path):
    start = None
    poses = []
    marks = []
    frames = 0
    for line in pathlib.Path(path).read_text().splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if row["kind"] == "start":
            start = row
        elif row["kind"] == "pose":
            poses.append(row)
        elif row["kind"] == "mark":
            marks.append((row["t"], row["name"]))
        elif row["kind"] == "frame":
            frames += 1
    if start is None:
        raise ValueError(f"The recording {path} has no start line.")
    return start, poses, marks, frames


def players_of(start, poses):
    names = start["signals"]
    players = [Player(names) for _ in range(start["players"])]
    for row in poses:
        for i, player in enumerate(row["players"][: len(players)]):
            if player is None:
                players[i].sources["none"] += 1
                continue
            players[i].sources[player["source"]] += 1
            players[i].t.append(row["t"])
            players[i].signals.append(
                [np.nan if player["signals"].get(n) is None else player["signals"][n] for n in names]
            )
            players[i].scores.append(player["keypoints"][2::3])
    for player in players:
        player.finish()
    return players


def resample(t, y, t0, t1):
    """Resample y(t) at RATE between t0 and t1; NaN where the gaps are longer than 0.5 s."""
    grid = np.arange(t0, t1, 1.0 / RATE)
    good = ~np.isnan(y)
    if good.sum() < 2:
        return grid, np.full_like(grid, np.nan)
    tg, yg = t[good], y[good]
    values = np.interp(grid, tg, yg)
    index = np.clip(np.searchsorted(tg, grid), 1, len(tg) - 1)
    gap = tg[index] - tg[index - 1]
    values[gap > 0.5] = np.nan
    values[(grid < tg[0]) | (grid > tg[-1])] = np.nan
    return grid, values


def rhythm(values):
    """
    The period (in seconds) and the strength (the peak of the autocorrelation,
    in [0, 1]) of the strongest rhythm of the values, or (nan, 0).
    """
    good = ~np.isnan(values)
    if good.sum() < MAX_PERIOD * RATE * 1.5:
        return np.nan, 0.0
    y = values[good] - np.nanmean(values)
    if np.std(y) < 1e-9:
        return np.nan, 0.0
    # NOTE (mristin):
    # The gaps are dropped, which is good enough to find a rhythm.
    correlation = np.correlate(y, y, mode="full")[len(y) - 1 :]
    correlation /= correlation[0]
    low = int(MIN_PERIOD * RATE)
    high = min(int(MAX_PERIOD * RATE), len(correlation) - 1)
    if high <= low:
        return np.nan, 0.0
    lag = low + int(np.argmax(correlation[low:high]))
    return lag / RATE, float(correlation[lag])


def windows(t0, t1, marks, size):
    """The windows between the marks, each cut into pieces of at most size seconds."""
    cuts = [t0] + [t for t, _ in marks if t0 < t < t1] + [t1]
    result = []
    for a, b in zip(cuts[:-1], cuts[1:]):
        pieces = max(1, int(round((b - a) / size)))
        edges = np.linspace(a, b, pieces + 1)
        result.extend(zip(edges[:-1], edges[1:]))
    return result


def report(path, window, plot):
    start, poses, marks, frames = load(path)
    if not poses:
        print("The recording has no poses.")
        return 1
    t0 = poses[0]["t"]
    t1 = poses[-1]["t"]
    duration = t1 - t0
    ms = np.array([row["ms"] for row in poses])
    print(f"Recording {path}")
    print(f"  started {start['time']}, note: {start.get('note') or '-'}")
    print(
        f"  {duration:.1f} s, {len(poses)} poses ({len(poses) / max(duration, 1e-9):.1f} a second), "
        f"pose {np.median(ms):.0f} ms median, {np.percentile(ms, 95):.0f} ms 95th percentile, "
        f"{frames} frames saved, {len(marks)} marks"
    )
    for t, name in marks:
        print(f"    mark {name} at {t - t0:.1f} s")

    players = players_of(start, poses)
    for index, player in enumerate(players):
        print()
        print(f"Player {index + 1}")
        total = sum(player.sources.values())
        print(
            "  seen in {:.0f}% of the poses; found by {}".format(
                100.0 * len(player.t) / max(total, 1),
                ", ".join(f"{k} {v}" for k, v in player.sources.most_common()),
            )
        )
        if len(player.t) == 0:
            continue

        print("  key points seen (score >= {:.1f}):".format(THRESHOLD))
        seen = (player.scores >= THRESHOLD).mean(axis=0)
        for k, name in enumerate(KEYPOINTS):
            print(f"    {name:15s} {100 * seen[k]:5.1f}%")

        print()
        print(
            "  {:15s} {:>6s} {:>8s} {:>8s} {:>8s} {:>8s} {:>7s} {:>9s}".format(
                "signal", "known", "median", "p5", "p95", "noise", "swing", "rhythm"
            )
        )
        rhythms = {}
        for s, name in enumerate(player.names):
            y = player.signals[:, s]
            known = ~np.isnan(y)
            if known.sum() < 3:
                print(f"  {name:15s} {100 * known.mean():5.0f}%")
                continue
            values = y[known]
            p5, p50, p95 = np.percentile(values, [5, 50, 95])
            # NOTE (mristin):
            # The noise is the typical jump from one pose to the next; the
            # swing is how many noises the range spans.
            noise = float(np.median(np.abs(np.diff(values)))) * 1.4826
            swing = (p95 - p5) / noise if noise > 0 else np.inf
            grid, resampled = resample(player.t, y, t0, t1)
            period, strength = rhythm(resampled)
            rhythms[name] = (grid, resampled)
            text = f"{period:.1f} s {strength:.2f}" if not np.isnan(period) else "-"
            print(
                f"  {name:15s} {100 * known.mean():5.0f}% {p50:8.3f} {p5:8.3f} {p95:8.3f} "
                f"{noise:8.4f} {swing:7.1f} {text:>9s}"
            )

        print()
        print(f"  The strongest rhythms in windows of about {window:.0f} s (period in s, strength):")
        for a, b in windows(t0, t1, marks, window):
            found = []
            for name, (grid, resampled) in rhythms.items():
                if name == "unit":
                    continue
                inside = (grid >= a) & (grid < b)
                period, strength = rhythm(resampled[inside])
                if strength >= 0.4:
                    found.append((strength, name, period))
            found.sort(reverse=True)
            text = ", ".join(f"{n} {p:.1f} s {s:.2f}" for s, n, p in found[:4]) or "none"
            print(f"    {a - t0:6.1f}-{b - t0:6.1f} s: {text}")

    if plot:
        draw(plot, players, marks, t0)
        print()
        print(f"Plotted into {plot}")
    return 0


def draw(path, players, marks, t0):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    names = [n for n in players[0].names if n != "unit"]
    figure, axes = plt.subplots(len(names), 1, figsize=(18, 2.0 * len(names)), sharex=True)
    colors = ["tab:orange", "tab:blue"]
    for axis, name in zip(axes, names):
        for index, player in enumerate(players):
            if len(player.t) == 0:
                continue
            s = player.names.index(name)
            axis.plot(
                player.t - t0,
                player.signals[:, s],
                color=colors[index % 2],
                linewidth=0.8,
                label=f"player {index + 1}",
            )
        for t, mark in marks:
            axis.axvline(t - t0, color="tab:red", linewidth=0.8, alpha=0.7)
        axis.set_ylabel(name, rotation=0, ha="right", va="center")
        axis.grid(alpha=0.3)
    axes[-1].set_xlabel("seconds")
    if len(players) > 1:
        axes[0].legend(loc="upper right")
    figure.tight_layout()
    figure.savefig(path, dpi=80)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("recording", help="the recording (.jsonl) of dev/rowing/record_rowing.gd")
    parser.add_argument("--plot", help="draw the signals into this PNG")
    parser.add_argument(
        "--window", type=float, default=10.0, help="the length of the windows of the rhythms, in seconds"
    )
    args = parser.parse_args()
    return report(args.recording, args.window, args.plot)


if __name__ == "__main__":
    sys.exit(main())
