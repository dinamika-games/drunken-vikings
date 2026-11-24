"""
Study the log of a party played with ``-- --log-pose``.

The vision prints the head and the shoulders of the player and how the meter
steers ("Pose:" lines, see VisionService.LogPose), and the party prints the
boat, the longship and the treats ("Party:" lines, see level.gd), all on the
same clock. Print:

* how well the vision saw the player;
* how the player steered: how long, to which side, by the head or by the
  shoulders, and whether the two agreed;
* each treat: where it fell from the boat, and whether the player picked it;
* whether the player steered towards the next treat (our guess of where they
  meant to go).

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/rowing/analyze_party_log.py <godot.log>
"""

import argparse
import bisect
import math
import pathlib
import re
import sys
from typing import Optional

import pydantic

# The boat picks a treat up within this many metres (see Treats.PICK_RADIUS),
# with a little slack, since the log has the boat only a few times a second.
PICK_RADIUS = 12.0

# Steering counts from this much on.
STEERING = 0.2

# A treat is "to the side" from this bearing on, in degrees.
SIDE_BEARING = 10.0


def number(text: str) -> float:
    return math.nan if text == "nan" else float(text)


class PoseLine(pydantic.BaseModel):
    t: float
    player: int
    source: str
    head_x: float
    head_y: float
    unit: float
    home: float
    shift: float
    tilt: float
    level: float
    steer: float
    head_steer: float
    body_steer: float
    strokes: int
    pull: float


class Seen(pydantic.BaseModel):
    """A treat as seen from the boat."""

    ahead: float
    right: float
    bearing: float


class BoatLine(pydantic.BaseModel):
    t: float
    x: float
    y: float
    heading: float
    speed: float
    steer: float
    strokes: int
    ship_x: float
    ship_y: float
    ship_ahead: float
    coins: int
    treats: int
    next: list[Seen]


class DropLine(pydantic.BaseModel):
    t: float
    x: float
    y: float
    side: int
    ahead: float
    right: float
    bearing: float


class PickLine(pydantic.BaseModel):
    t: float
    picked: int
    coins: int
    x: float
    y: float


NUM = r"(-?[0-9.]+|nan|[+-][0-9.]+)"
POSE = re.compile(
    rf"^Pose: t={NUM} p=(\d) src=(\w+) head=\({NUM},{NUM}\) unit={NUM} home={NUM} shift={NUM}"
    rf" tilt={NUM} level={NUM} steer={NUM} \(head {NUM}, body {NUM}\) strokes=(\d+) pull={NUM}$"
)
BOAT = re.compile(
    rf"^Party: t={NUM} boat=\({NUM},{NUM}\) heading={NUM} speed={NUM} steer={NUM} strokes=(\d+)"
    rf" ship=\({NUM},{NUM}\) ship_ahead={NUM} coins=(\d+) treats=(\d+) next=\[(.*)\]$"
)
SEEN = re.compile(rf"\({NUM},{NUM},{NUM}\)")
DROP = re.compile(
    rf"^Party: t={NUM} drop=\({NUM},{NUM}\) side=([+-]\d) ahead={NUM} right={NUM} bearing={NUM}$"
)
PICK = re.compile(rf"^Party: t={NUM} picked=(\d+) coins=(\d+) boat=\({NUM},{NUM}\)$")


class Log(pydantic.BaseModel):
    poses: list[PoseLine] = []
    boats: list[BoatLine] = []
    drops: list[DropLine] = []
    picks: list[PickLine] = []
    unparsed: int = 0


def parse(path: pathlib.Path) -> Log:
    log = Log()
    for text in path.read_text(errors="replace").splitlines():
        if not text.startswith(("Pose:", "Party:")):
            continue
        if m := POSE.match(text):
            g = m.groups()
            log.poses.append(
                PoseLine(
                    t=number(g[0]),
                    player=int(g[1]),
                    source=g[2],
                    head_x=number(g[3]),
                    head_y=number(g[4]),
                    unit=number(g[5]),
                    home=number(g[6]),
                    shift=number(g[7]),
                    tilt=number(g[8]),
                    level=number(g[9]),
                    steer=number(g[10]),
                    head_steer=number(g[11]),
                    body_steer=number(g[12]),
                    strokes=int(g[13]),
                    pull=number(g[14]),
                )
            )
        elif m := BOAT.match(text):
            g = m.groups()
            log.boats.append(
                BoatLine(
                    t=number(g[0]),
                    x=number(g[1]),
                    y=number(g[2]),
                    heading=number(g[3]),
                    speed=number(g[4]),
                    steer=number(g[5]),
                    strokes=int(g[6]),
                    ship_x=number(g[7]),
                    ship_y=number(g[8]),
                    ship_ahead=number(g[9]),
                    coins=int(g[10]),
                    treats=int(g[11]),
                    next=[
                        Seen(ahead=number(a), right=number(r), bearing=number(b))
                        for a, r, b in SEEN.findall(g[12])
                    ],
                )
            )
        elif m := DROP.match(text):
            g = m.groups()
            log.drops.append(
                DropLine(
                    t=number(g[0]),
                    x=number(g[1]),
                    y=number(g[2]),
                    side=int(g[3]),
                    ahead=number(g[4]),
                    right=number(g[5]),
                    bearing=number(g[6]),
                )
            )
        elif m := PICK.match(text):
            g = m.groups()
            log.picks.append(
                PickLine(t=number(g[0]), picked=int(g[1]), coins=int(g[2]), x=number(g[3]), y=number(g[4]))
            )
        else:
            log.unparsed += 1
    return log


def side(value: float) -> str:
    return "right" if value > 0 else "left" if value < 0 else "straight"


def report_vision(log: Log) -> None:
    poses = [p for p in log.poses if p.player == 0]
    if not poses:
        print("No poses in the log: was the game started with -- --log-pose?")
        return
    seen = [p for p in poses if p.source != "None"]
    span = poses[-1].t - poses[0].t
    print(f"## The vision ({span:.0f} s, {len(poses)} pose lines)")
    print(f"The player was seen in {100 * len(seen) / len(poses):.0f} % of the lines.", end=" ")
    sources: dict[str, int] = {}
    for p in poses:
        sources[p.source] = sources.get(p.source, 0) + 1
    print("Sources: " + ", ".join(f"{k} {100 * v / len(poses):.0f} %" for k, v in sorted(sources.items())))
    tilts = [p for p in seen if not math.isnan(p.tilt)]
    print(
        f"The shoulders were seen in {100 * len(tilts) / max(1, len(seen)):.0f} % of the poses with a player."
    )
    units = sorted(p.unit for p in seen if not math.isnan(p.unit))
    if units:
        print(
            f"The unit (shoulders) was {units[0]:.0f}..{units[-1]:.0f} px, "
            f"median {units[len(units) // 2]:.0f} px."
        )
    gaps = [b.t - a.t for a, b in zip(seen, seen[1:]) if b.t - a.t > 1.0]
    if gaps:
        print(f"The player was lost {len(gaps)} time(s) for over 1 s, the longest {max(gaps):.1f} s.")
    print(f"Strokes: {poses[-1].strokes - poses[0].strokes}.")
    print()


def report_steering(log: Log) -> None:
    poses = [p for p in log.poses if p.player == 0 and p.source != "None"]
    if not poses:
        return
    print("## The steering")
    steering = [p for p in poses if abs(p.steer) >= STEERING]
    print(
        f"The player steered (|steer| >= {STEERING}) in {100 * len(steering) / len(poses):.0f} % of the poses."
    )
    for name, cond in (("left", lambda s: s < 0), ("right", lambda s: s > 0)):
        part = [p for p in steering if cond(p.steer)]
        if part:
            print(
                f"  {name}: {len(part)} poses, mean {sum(abs(p.steer) for p in part) / len(part):.2f}; "
                f"by the head alone {sum(1 for p in part if abs(p.body_steer) < 0.05)}, "
                f"by the shoulders alone {sum(1 for p in part if abs(p.head_steer) < 0.05)}, by both "
                f"{sum(1 for p in part if abs(p.head_steer) >= 0.05 and abs(p.body_steer) >= 0.05)}"
            )
    both = [p for p in poses if abs(p.head_steer) >= 0.05 and abs(p.body_steer) >= 0.05]
    disagree = [p for p in both if p.head_steer * p.body_steer < 0]
    print(
        f"The head and the shoulders both steered in {len(both)} poses and disagreed in {len(disagree)}"
        + (": " + ", ".join(f"{p.t:.1f}s" for p in disagree[:10]) if disagree else ".")
    )

    # NOTE: Episodes of steering to one side, merged over short gaps.
    episodes: list[list[PoseLine]] = []
    for p in steering:
        if episodes and p.t - episodes[-1][-1].t < 0.6 and p.steer * episodes[-1][-1].steer > 0:
            episodes[-1].append(p)
        else:
            episodes.append([p])
    print(f"{len(episodes)} episodes of steering:")
    for e in episodes:
        peak = max(e, key=lambda p: abs(p.steer))
        print(
            f"  {e[0].t:7.1f}..{e[-1].t:7.1f} s {side(peak.steer):5} peak {peak.steer:+.2f} "
            f"(head {peak.head_steer:+.2f}, body {peak.body_steer:+.2f}, shift {peak.shift:+.2f}, "
            f"tilt {peak.tilt:+.1f})"
        )

    # NOTE: Levels which drifted far, or homes which jumped, hint at trouble.
    levels = [p.level for p in poses if not math.isnan(p.level)]
    if levels:
        print(f"The level of the shoulders stayed within {min(levels):+.1f}..{max(levels):+.1f} degrees.")
    print()


def target(boat: BoatLine) -> Optional[Seen]:
    """The nearest treat ahead of the boat, which we guess the player goes for."""
    ahead = [s for s in boat.next if s.ahead > 0.0]
    return min(ahead, key=lambda s: math.hypot(s.ahead, s.right)) if ahead else None


def report_treats(log: Log) -> None:
    if not log.boats:
        print("No party lines: the log is not of the party, or --log-pose was missing.")
        return
    print(f"## The treats ({len(log.drops)} dropped, {sum(p.picked for p in log.picks)} picked)")
    picks = list(log.picks)
    # NOTE: The last treats which the boat did not pick are still on the water
    # at the end of the log: not missed, only not reached yet.
    floating = log.boats[-1].treats
    unpicked = 0
    outcomes: list[str] = []
    for d in log.drops:
        pick = next(
            (p for p in picks if p.t >= d.t and math.hypot(p.x - d.x, p.y - d.y) <= PICK_RADIUS), None
        )
        if pick is not None:
            picks.remove(pick)
            outcome = f"picked after {pick.t - d.t:5.1f} s"
        else:
            outcome = "missed"
            unpicked += 1
        outcomes.append(outcome)
    still = min(floating, unpicked)
    for i in range(len(outcomes) - 1, -1, -1):
        if still == 0:
            break
        if outcomes[i] == "missed":
            outcomes[i] = "still on the water at the end"
            still -= 1
    for d, outcome in zip(log.drops, outcomes):
        print(
            f"  {d.t:7.1f} s side {d.side:+d}: fell {d.ahead:6.1f} m ahead, {d.right:+6.1f} m right "
            f"(bearing {d.bearing:+4.0f}) -> {outcome}"
        )
    print()

    print("## Did the player steer towards the next treat?")
    times = [p.t for p in log.poses]
    toward = away = straight = 0
    for b in log.boats:
        seen = target(b)
        if seen is None or abs(seen.bearing) < SIDE_BEARING or seen.ahead > 80.0:
            continue
        steer = b.steer
        i = bisect.bisect_left(times, b.t)
        if 0 < i <= len(times) and log.poses[i - 1].source == "None":
            continue
        if abs(steer) < STEERING:
            straight += 1
        elif steer * seen.bearing > 0:
            toward += 1
        else:
            away += 1
    total = toward + away + straight
    if total:
        print(
            f"While the nearest treat ahead was over {SIDE_BEARING:.0f} degrees to the side "
            f"(within 80 m), in {total} party lines the boat steered towards it in "
            f"{100 * toward / total:.0f} %, away in {100 * away / total:.0f} %, "
            f"and straight in {100 * straight / total:.0f} %."
        )
    speeds = [b.speed for b in log.boats]
    print(
        f"The boat went {sum(speeds) / len(speeds):.1f} m/s on average; the longship was "
        f"{sum(b.ship_ahead for b in log.boats) / len(log.boats):.0f} m ahead on average. "
        f"Coins at the end: {log.boats[-1].coins}."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("log", type=pathlib.Path)
    args = parser.parse_args()
    log = parse(args.log)
    if log.unparsed:
        print(f"({log.unparsed} Pose/Party lines did not parse.)", file=sys.stderr)
    report_vision(log)
    report_steering(log)
    report_treats(log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
