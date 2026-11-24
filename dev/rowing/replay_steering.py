"""
Replay the steering of RowingMeter on a recording of the vision.

Take a recording made with dev/rowing/record_rowing.gd or with the party
(``-- --record``), feed the head and the tilt of the shoulders of the first
player into a copy of RowingMeter (scenes/vision/core/RowingMeter.cs), and
print, a few times a second, what the meter saw and how it steered. The meter
of the commit 773dbc1 (the head alone, home in units) runs alongside, so that
we see where the two part.

With --csv, write the samples (the time, the head, the unit and the tilt) as
the replays of the unit tests (tests/DrunkenVikings.Tests/data/).

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/rowing/replay_steering.py <recording.jsonl> [--every 0.25] [--csv out.csv]
"""

import argparse
import math
import pathlib
import sys
from typing import Literal, Optional, Union

import pydantic

# NOTE (mristin):
# As in the vision service: a key point counts from this score on.
THRESHOLD = 0.3

# The key points of the head (nose, eyes, ears) and the shoulders, as in COCO.
HEAD = range(5)
LEFT_SHOULDER = 5
RIGHT_SHOULDER = 6


class Start(pydantic.BaseModel):
    kind: Literal["start"]
    t: float
    width: int
    height: int
    players: int
    note: str = ""


class Player(pydantic.BaseModel):
    keypoints: list[float]
    source: str = ""
    signals: dict[str, Optional[float]] = {}

    def point(self, index: int) -> Optional[tuple[float, float]]:
        x, y, score = self.keypoints[3 * index : 3 * index + 3]
        return (x, y) if score >= THRESHOLD else None


class PoseLine(pydantic.BaseModel):
    kind: Literal["pose"]
    t: float
    label: str = ""
    players: list[Optional[Player]]


class Mark(pydantic.BaseModel):
    kind: Literal["mark"]
    t: float
    name: str


class Frame(pydantic.BaseModel):
    kind: Literal["frame"]
    t: float
    index: int


class Line(pydantic.RootModel[Union[Start, PoseLine, Mark, Frame]]):
    root: Union[Start, PoseLine, Mark, Frame] = pydantic.Field(discriminator="kind")


class Sample(pydantic.BaseModel):
    t: float
    head_x: float
    head_y: float
    unit: float
    tilt: float


def ramp(value: float, start: float, full: float) -> float:
    return min(max((value - start) / (full - start), 0.0), 1.0)


def follow(dt: float, tau: float) -> float:
    return 0.0 if math.isinf(tau) else 1.0 - math.exp(-dt / tau)


def sign(value: float) -> int:
    return (value > 0) - (value < 0)


class OldMeter:
    """The steering of RowingMeter as of the commit 773dbc1: the head alone, home in units."""

    def __init__(self) -> None:
        self.home = math.nan
        self.last = math.nan
        self.shift = 0.0
        self.steer = 0.0

    def observe(self, sample: Sample) -> None:
        if math.isnan(sample.head_x) or math.isnan(sample.unit):
            return
        dt = 0.0 if math.isnan(self.last) else min(max(sample.t - self.last, 0.0), 0.5)
        self.last = sample.t
        x = sample.head_x / sample.unit
        if math.isnan(self.home):
            self.home = x
        self.shift = self.home - x
        away = abs(self.shift)
        self.home += (x - self.home) * follow(dt, 5.0 if away < 0.3 else 30.0)
        self.steer = sign(self.shift) * ramp(away, 0.3, 1.0)


class NewMeter:
    """The steering of RowingMeter now (see scenes/vision/core/RowingMeter.cs)."""

    DEAD_ZONE = 0.3
    FULL_STEER = 1.0
    TILT_DEAD_ZONE = 10.0
    FULL_TILT = 30.0
    MAX_TILT = 60.0

    def __init__(self) -> None:
        self.home = math.nan
        self.level = 0.0
        self.last = math.nan
        self.shift = 0.0
        self.tilt = math.nan
        self.head_steer = 0.0
        self.tilt_steer = 0.0
        self.steer = 0.0

    def observe(self, sample: Sample) -> None:
        if math.isnan(sample.head_x) or math.isnan(sample.unit):
            return
        dt = 0.0 if math.isnan(self.last) else min(max(sample.t - self.last, 0.0), 0.5)
        self.last = sample.t
        if math.isnan(self.home):
            self.home = sample.head_x

        self.shift = (self.home - sample.head_x) / sample.unit
        away = abs(self.shift)

        leans = False
        if math.isnan(sample.tilt) or abs(sample.tilt) > self.MAX_TILT:
            self.tilt = math.nan
            self.tilt_steer = 0.0
        else:
            self.tilt = sample.tilt - self.level
            leans = abs(self.tilt) >= self.TILT_DEAD_ZONE
            level_tau = 5.0 if not leans else 20.0 if away < self.DEAD_ZONE else math.inf
            self.level += (sample.tilt - self.level) * follow(dt, level_tau)
            self.tilt_steer = sign(self.tilt) * ramp(abs(self.tilt), self.TILT_DEAD_ZONE, self.FULL_TILT)

        if leans:
            tau = math.inf
        elif away < self.DEAD_ZONE:
            tau = 5.0
        elif math.isnan(self.tilt):
            tau = 30.0
        else:
            tau = 10.0
        self.home += (sample.head_x - self.home) * follow(dt, tau)

        self.head_steer = sign(self.shift) * ramp(away, self.DEAD_ZONE, self.FULL_STEER)
        if sign(self.head_steer) * sign(self.tilt_steer) >= 0:
            self.steer = self.head_steer if abs(self.head_steer) >= abs(self.tilt_steer) else self.tilt_steer
        else:
            self.steer = min(max(self.head_steer + self.tilt_steer, -1.0), 1.0)


def load(path: pathlib.Path) -> tuple[list[Sample], list[Mark]]:
    samples: list[Sample] = []
    marks: list[Mark] = []
    broken = 0
    for number, text in enumerate(path.read_text().splitlines(), start=1):
        if not text.strip():
            continue
        try:
            line = Line.model_validate_json(text).root
        except pydantic.ValidationError as error:
            broken += 1
            print(f"Skipping the broken line {number}: {error.errors()[0]['msg']}", file=sys.stderr)
            continue
        if isinstance(line, Mark):
            marks.append(line)
        if not isinstance(line, PoseLine) or not line.players or line.players[0] is None:
            continue
        player = line.players[0]
        heads = [p for p in (player.point(i) for i in HEAD) if p is not None]
        unit = player.signals.get("unit")
        tilt = player.signals.get("shoulder_tilt")
        samples.append(
            Sample(
                t=line.t,
                head_x=sum(p[0] for p in heads) / len(heads) if heads else math.nan,
                head_y=sum(p[1] for p in heads) / len(heads) if heads else math.nan,
                unit=unit if unit is not None else math.nan,
                tilt=tilt if tilt is not None else math.nan,
            )
        )
    if broken:
        print(f"Skipped {broken} broken line(s).", file=sys.stderr)
    return samples, marks


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("recording", type=pathlib.Path)
    parser.add_argument("--every", type=float, default=0.25, help="print a line every this many seconds")
    parser.add_argument("--csv", type=pathlib.Path, help="write the samples for the unit tests")
    args = parser.parse_args()

    samples, marks = load(args.recording)
    if not samples:
        print("No poses of the first player in the recording.", file=sys.stderr)
        return 1

    old = OldMeter()
    new = NewMeter()
    print("     t  head_x   unit   tilt | old: shift steer | new: shift   tilt head  body steer")
    printed = -math.inf
    parted = 0
    for sample in samples:
        old.observe(sample)
        new.observe(sample)
        if abs(old.steer - new.steer) > 0.5:
            parted += 1
        if sample.t - printed >= args.every:
            printed = sample.t
            print(
                f"{sample.t:6.2f} {sample.head_x:7.1f} {sample.unit:6.1f} {sample.tilt:+6.1f} |"
                f"      {old.shift:+5.2f} {old.steer:+5.2f} |"
                f"      {new.shift:+5.2f} {new.tilt:+6.1f} {new.head_steer:+4.1f} {new.tilt_steer:+5.1f} {new.steer:+5.2f}"
            )
    for mark in marks:
        print(f"Mark at {mark.t:.2f} s: {mark.name}")
    print(f"The old and the new steering differ by more than 0.5 in {parted} of {len(samples)} poses.")

    if args.csv is not None:
        with args.csv.open("w") as out:
            out.write(f"# The head and the shoulders of the player in {args.recording.name}.\n")
            out.write("t,head_x,head_y,unit,tilt\n")
            t0 = samples[0].t
            for s in samples:
                values = [s.head_x, s.head_y, s.unit, s.tilt]
                out.write(
                    f"{s.t - t0:.3f}," + ",".join("" if math.isnan(v) else f"{v:.1f}" for v in values) + "\n"
                )
        print(f"Wrote the samples to {args.csv}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
