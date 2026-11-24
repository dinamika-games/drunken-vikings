"""
Draw How to play (see scenes/how_to/how_to.gd) into SVGs, one for each still
of each part of data/how_to/how_to.json, for one rower and for two:

    venv/bin/python dev/how_to/make_svgs.py [--out ~/Downloads/viking/how-to/all_svgs]

Each SVG is a screen of 1920 x 1080: the title and the line of the part, the
players in the camera picture on the left (mirrored, drawn as HowToFigure draws
them, with the same numbers), and on the right what it does: the boat seen
from above with arrows (forward, turning, stopping), the jetty, or the card
with the glove.
"""

import argparse
import json
import math
import pathlib
import sys
from typing import Dict, List, Literal, Optional, Tuple
from xml.sax.saxutils import escape

import pydantic

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
DATA = REPO_ROOT / "data" / "how_to" / "how_to.json"

Vec = Tuple[float, float]

# As in HowTo and HowToFigure (scenes/how_to/).
FRAME = (110.0, 300.0, 720.0, 540.0)
PANEL = (1090.0, 300.0, 720.0, 540.0)
RISE = 0.4
LEAN = 0.8
HIPS_Y = 0.98
TORSO = 0.42
SHOULDER = 0.16
HEAD = 0.095
NECK = 0.07
CRUNCH = 0.07
TILT_DEGREES = 20.0
LOOKS = [
    {"hair": "#e8c25a", "dress": "#2f6f6a", "band": "#b8332a", "sleeve": "#f1e6cc"},
    {"hair": "#c8562a", "dress": "#7a3a6a", "band": "#3a6ea8", "sleeve": "#f1e6cc"},
]
SKIN = "#f0c8a0"
INK = "#2a1e14"
GOLD = "#f2c14e"
PAPER = "#f1e6cc"


class Move(pydantic.BaseModel):
    do: Literal["row", "lean", "brake", "point", "rest"]
    start: float = pydantic.Field(alias="from")
    to: float
    period: Optional[float] = None
    side: Optional[float] = None
    who: int = -1


class Part(pydantic.BaseModel):
    id: str
    players: List[int]
    title: str
    text: str
    seconds: float
    panel: Literal["boat", "jetty", "card"]
    moves: List[Move]
    stills: List[float]
    keep_boat: bool = False


class HowToData(pydantic.BaseModel):
    comment: str
    parts: List[Part]


def smoothstep(x: float) -> float:
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def moves_at(part: Part, t: float, who: int) -> List[Move]:
    return [m for m in part.moves if m.who in (-1, who) and m.start <= t < m.to]


def center_of(players: int, who: int) -> float:
    if players == 1:
        return FRAME[2] / 2.0
    return FRAME[2] * (0.27 if who == 0 else 0.73)


def height_of(players: int) -> float:
    return FRAME[3] * (1.0 if players == 1 else 0.92)


def pose(part: Part, t: float, who: int, players: int) -> Dict:
    """As HowTo.pose."""
    result: Dict = {"lean": 0.0, "tilt": 0.0, "hands": "rest", "up": 0.0}
    for move in moves_at(part, t, who):
        if move.do == "row":
            phase = (t - move.start) / move.period
            result["hands"] = "oar"
            result["lean"] = 0.5 - 0.5 * math.cos(2.0 * math.pi * phase)
        elif move.do == "lean":
            result["hands"] = "oar"
            result["lean"] = 0.15
            result["tilt"] = move.side * min(
                smoothstep((t - move.start) / LEAN), smoothstep((move.to - t) / LEAN)
            )
        elif move.do == "brake":
            result["hands"] = "up"
            result["up"] = smoothstep((t - move.start) / RISE)
        elif move.do == "point":
            result["hands"] = "point"
            result["up"] = smoothstep((t - move.start) / (RISE * 2.0))
            height = height_of(players)
            result["target"] = (center_of(players, who) + 0.3 * height, 0.24 * height)
    return result


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1])


def scale(a: Vec, k: float) -> Vec:
    return (a[0] * k, a[1] * k)


def rotate(a: Vec, angle: float) -> Vec:
    c, s = math.cos(angle), math.sin(angle)
    return (a[0] * c - a[1] * s, a[0] * s + a[1] * c)


def lerp(a: Vec, b: Vec, t: float) -> Vec:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def joints(center: float, height: float, p: Dict) -> Dict:
    """As HowToFigure.joints."""
    lean, tilt, up = p["lean"], p["tilt"], p["up"]
    hips = (center, HIPS_Y * height)
    angle = math.radians(TILT_DEGREES) * tilt
    neck = add(hips, rotate((0.0, -(TORSO - CRUNCH * lean) * height), angle))
    across = rotate((SHOULDER * height * (1.0 - 0.08 * lean), 0.0), angle)
    head = add(neck, rotate((0.0, -(NECK + HEAD) * height), angle))
    shoulders = [add(neck, scale(across, -1.0)), add(neck, across)]
    elbows, wrists = [], []
    for i, side in enumerate((-1.0, 1.0)):
        shoulder = shoulders[i]
        rest_elbow = add(shoulder, scale((0.06 * side, 0.22), height))
        rest_wrist = add(hips, scale((0.12 * side, -0.08), height))
        elbow, wrist = rest_elbow, rest_wrist
        if p["hands"] == "oar":
            reach_elbow = add(shoulder, scale((0.04 * side, 0.18), height))
            reach_wrist = add(neck, scale((0.07 * side, 0.12), height))
            pull_elbow = add(shoulder, scale((0.11 * side, 0.2), height))
            pull_wrist = add(hips, scale((0.1 * side, -0.17), height))
            elbow = lerp(reach_elbow, pull_elbow, lean)
            wrist = lerp(reach_wrist, pull_wrist, lean)
        elif p["hands"] == "up":
            elbow = lerp(rest_elbow, add(shoulder, scale((0.05 * side, -0.1), height)), up)
            wrist = lerp(rest_wrist, add(head, scale((0.13 * side, -0.2), height)), up)
        elif p["hands"] == "point" and side > 0.0:
            target = p.get("target", add(shoulder, scale((0.15, -0.12), height)))
            raised = add(lerp(shoulder, target, 0.5), (0.0, 0.05 * height))
            elbow = lerp(rest_elbow, raised, up)
            wrist = lerp(rest_wrist, target, up)
        elbows.append(elbow)
        wrists.append(wrist)
    return {
        "head": head,
        "neck": neck,
        "hips": hips,
        "shoulders": shoulders,
        "elbows": elbows,
        "wrists": wrists,
    }


def figure(center: float, height: float, p: Dict, look: int) -> List[str]:
    """As HowToFigure.draw, in the coordinates of the frame."""
    colors = LOOKS[look]
    at = joints(center, height, p)
    u = height
    out = []
    hx, hy = at["head"]
    for side in (-1.0, 1.0):
        for k in range(5):
            x = hx + (0.075 + 0.004) * side * u
            y = hy + (0.02 + 0.04 * k) * u
            out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{0.026 * u:.1f}" fill="{colors["hair"]}"/>')
    s0, s1 = at["shoulders"]
    hips = at["hips"]
    dress = [s0, s1, add(hips, (0.15 * u, 0.0)), add(hips, (-0.15 * u, 0.0))]
    points = " ".join(f"{x:.1f},{y:.1f}" for x, y in dress)
    out.append(
        f'<polygon points="{points}" fill="{colors["dress"]}" stroke="{INK}" stroke-width="{0.006 * u:.1f}"/>'
    )
    for i in range(2):
        for a, b, w in (
            (at["shoulders"][i], at["elbows"][i], 0.05),
            (at["elbows"][i], at["wrists"][i], 0.045),
        ):
            out.append(
                f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" '
                f'stroke="{colors["sleeve"]}" stroke-width="{w * u:.1f}" stroke-linecap="round"/>'
            )
        ex, ey = at["wrists"][i]
        out.append(f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="{0.032 * u:.1f}" fill="{SKIN}"/>')
    nx, ny = at["neck"]
    out.append(
        f'<line x1="{nx:.1f}" y1="{ny:.1f}" x2="{hx:.1f}" y2="{hy:.1f}" stroke="{SKIN}" '
        f'stroke-width="{0.07 * u:.1f}"/>'
    )
    out.append(f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{HEAD * u:.1f}" fill="{SKIN}"/>')
    r = HEAD * u
    out.append(
        f'<path d="M {hx - r:.1f} {hy - 0.1 * r:.1f} A {r:.1f} {r:.1f} 0 0 1 {hx + r:.1f} {hy - 0.1 * r:.1f}" '
        f'fill="none" stroke="{colors["hair"]}" stroke-width="{0.05 * u:.1f}"/>'
    )
    rb = r * 0.86
    out.append(
        f'<path d="M {hx - rb * 0.93:.1f} {hy - rb * 0.36:.1f} A {rb:.1f} {rb:.1f} 0 0 1 {hx + rb * 0.93:.1f} '
        f'{hy - rb * 0.36:.1f}" fill="none" stroke="{colors["band"]}" stroke-width="{0.022 * u:.1f}"/>'
    )
    for side in (-1.0, 1.0):
        out.append(
            f'<circle cx="{hx + 0.032 * side * u:.1f}" cy="{hy - 0.005 * u:.1f}" r="{0.011 * u:.1f}" fill="{INK}"/>'
        )
    out.append(
        f'<path d="M {hx - 0.033 * u:.1f} {hy + 0.03 * u:.1f} Q {hx:.1f} {hy + 0.07 * u:.1f} '
        f'{hx + 0.033 * u:.1f} {hy + 0.03 * u:.1f}" fill="none" stroke="{INK}" stroke-width="{0.006 * u:.1f}"/>'
    )
    return out


def arrow(points: List[Vec], color: str = GOLD) -> List[str]:
    """A thick arrow along the points, with its head at the last one."""
    path = " ".join(f"{'M' if i == 0 else 'L'} {x:.1f} {y:.1f}" for i, (x, y) in enumerate(points))
    (ax, ay), (bx, by) = points[-2], points[-1]
    angle = math.atan2(by - ay, bx - ax)
    head = [
        (bx + math.cos(angle) * 26, by + math.sin(angle) * 26),
        (bx + math.cos(angle + 2.4) * 30, by + math.sin(angle + 2.4) * 30),
        (bx + math.cos(angle - 2.4) * 30, by + math.sin(angle - 2.4) * 30),
    ]
    tip = " ".join(f"{x:.1f},{y:.1f}" for x, y in head)
    return [
        f'<path d="{path}" fill="none" stroke="{color}" stroke-width="16" stroke-linecap="round" '
        f'stroke-linejoin="round" opacity="0.9"/>',
        f'<polygon points="{tip}" fill="{color}"/>',
    ]


def boat(cx: float, cy: float, players: int, pulls: List[float], braking: bool, golden: bool) -> List[str]:
    """The small boat from above, its bow up, with its rowers and their oars."""
    out = [
        f'<ellipse cx="{cx}" cy="{cy}" rx="34" ry="95" fill="#7a4f28" stroke="#3a2412" stroke-width="5"/>',
        f'<ellipse cx="{cx}" cy="{cy + 4}" rx="24" ry="80" fill="#a8784a"/>',
    ]
    oar = GOLD if golden else "#c8a060"
    for i, side in enumerate((-1.0, 1.0)):
        swing = 0.0 if braking else (-0.5 + pulls[i] * 1.0 if pulls[i] >= 0.0 else -0.3)
        lock = (cx + side * 30, cy)
        blade = (lock[0] + side * math.cos(swing) * 120, lock[1] + math.sin(swing) * 120)
        out.append(
            f'<line x1="{lock[0] - side * 30:.1f}" y1="{lock[1]:.1f}" x2="{blade[0]:.1f}" y2="{blade[1]:.1f}" '
            f'stroke="{oar}" stroke-width="7" stroke-linecap="round"/>'
        )
        out.append(
            f'<ellipse cx="{blade[0]:.1f}" cy="{blade[1]:.1f}" rx="22" ry="9" fill="{oar}" '
            f'transform="rotate({math.degrees(swing):.1f} {blade[0]:.1f} {blade[1]:.1f})"/>'
        )
    seats = [(cx, cy)] if players == 1 else [(cx - 12, cy), (cx + 12, cy)]
    for i, (sx, sy) in enumerate(seats):
        out.append(
            f'<circle cx="{sx}" cy="{sy}" r="16" fill="{LOOKS[i]["hair"]}" stroke="{INK}" stroke-width="2"/>'
        )
    return out


def panel(part: Part, t: float, players: int) -> List[str]:
    x, y, w, h = PANEL
    cx, cy = x + w / 2.0, y + h * 0.62
    out = []
    if part.panel == "card":
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#1b2230"/>')
        point = [m for m in moves_at(part, t, 0) if m.do == "point"]
        since = t - point[0].start if point else -1.0
        progress = min(1.0, max(0.0, (since - 0.8) / 2.0)) if point else 0.0
        kx, ky = x + w / 2.0 - 125, y + h / 2.0 - 95
        lit = progress > 0.0
        out.append(
            f'<rect x="{kx}" y="{ky}" width="250" height="190" rx="14" fill="{PAPER}" '
            f'stroke="{GOLD if lit else "#6a4320"}" stroke-width="{12 if lit else 6}"/>'
        )
        out.append(f'<rect x="{kx + 95}" y="{ky + 30}" width="60" height="60" rx="8" fill="#8a5a2b"/>')
        out.append(
            f'<text x="{kx + 125}" y="{ky + 150}" font-size="30" text-anchor="middle" fill="{INK}" '
            f'font-family="sans-serif">Sell</text>'
        )
        start = (x + w * 0.85, y + h * 0.9)
        end = (x + w / 2.0 + 70, y + h / 2.0 + 50)
        gx, gy = lerp(start, end, smoothstep(since / 0.8)) if point else start
        if progress > 0.0:
            a = 2.0 * math.pi * progress
            large = 1 if a > math.pi else 0
            ex, ey = gx + 54 * math.sin(a), gy - 54 * math.cos(a)
            out.append(
                f'<path d="M {gx:.1f} {gy - 54:.1f} A 54 54 0 {large} 1 {ex:.1f} {ey:.1f}" fill="none" '
                f'stroke="{GOLD}" stroke-width="10"/>'
            )
        out.append(
            f'<circle cx="{gx:.1f}" cy="{gy:.1f}" r="26" fill="#8a5a2b" stroke="{INK}" stroke-width="3"/>'
        )
        return out
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#3d6f9c"/>')
    for k in range(40):
        wx = x + 30 + (k * 137) % (w - 60)
        wy = y + 30 + (k * 89) % (h - 60)
        out.append(
            f'<path d="M {wx} {wy} q 10 -8 20 0" fill="none" stroke="#ffffff" stroke-opacity="0.25" stroke-width="3"/>'
        )
    if part.panel == "jetty":
        out.append(f'<rect x="{cx + 80}" y="{y}" width="{x + w - cx - 80}" height="{h}" fill="#5d6b3a"/>')
        out.append(f'<rect x="{cx + 80}" y="{y}" width="16" height="{h}" fill="#c9b98a"/>')
        out.append(
            f'<rect x="{cx + 30}" y="{cy - 14}" width="60" height="28" fill="#8a6a40" stroke="#5a3a1e" stroke-width="3"/>'
        )
    moves = {m.do for who in range(players) for m in moves_at(part, t, who)}
    rowing = [any(m.do == "row" for m in moves_at(part, t, who)) for who in range(2)]
    pulls = [
        pose(part, t, who, players)["lean"] if rowing[min(who, players - 1)] else -1.0 for who in range(2)
    ]
    if players == 1:
        pulls[1] = pulls[0]
    braking = "brake" in moves
    golden = part.id == "pair"
    if "lean" in moves:
        side = next(m.side for m in moves_at(part, t, 0) if m.do == "lean")
        out += arrow(
            [(cx, cy - 110), (cx, cy - 170), (cx + side * 60, cy - 230), (cx + side * 150, cy - 250)]
        )
    elif part.id == "turn":
        out += arrow([(cx, cy - 110), (cx, cy - 170), (cx + 60, cy - 230), (cx + 150, cy - 250)])
    elif braking:
        out.append(
            f'<rect x="{cx - 90}" y="{cy - 175}" width="180" height="22" rx="10" fill="#b8332a" opacity="0.9"/>'
        )
    elif "row" in moves or part.id == "glide":
        out += arrow([(cx, cy - 110), (cx, cy - 250)], GOLD if "row" in moves else "#ffffff")
    out += boat(cx, cy, players, pulls, braking, golden)
    return out


def screen(part: Part, t: float, players: int) -> str:
    out = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">',
        '<rect width="1920" height="1080" fill="#22293a"/>',
        f'<text x="960" y="100" font-size="56" text-anchor="middle" fill="{GOLD}" font-family="sans-serif" '
        f'font-weight="bold">How to play: {escape(part.title)}</text>',
        f'<text x="960" y="165" font-size="32" text-anchor="middle" fill="{PAPER}" '
        f'font-family="sans-serif">{escape(part.text)}</text>',
    ]
    fx, fy, fw, fh = FRAME
    out.append(f'<rect x="{fx}" y="{fy}" width="{fw}" height="{fh}" fill="#2c3440"/>')
    out.append(f'<g transform="translate({fx} {fy})">')
    for who in range(players):
        out += figure(center_of(players, who), height_of(players), pose(part, t, who, players), who)
    out.append("</g>")
    out += panel(part, t, players)
    for (rx, ry, rw, rh), label in (
        (FRAME, "You, in the camera" if players == 1 else "You two, in the camera"),
        (PANEL, "The screens" if part.panel == "card" else "The lakes"),
    ):
        out.append(
            f'<rect x="{rx - 6}" y="{ry - 6}" width="{rw + 12}" height="{rh + 12}" fill="none" '
            f'stroke="#6a4320" stroke-width="12"/>'
        )
        out.append(
            f'<text x="{rx}" y="{ry - 18}" font-size="30" fill="{PAPER}" font-family="sans-serif">{label}</text>'
        )
    out.append(
        f'<rect x="1560" y="872" width="250" height="190" rx="14" fill="{PAPER}" stroke="#6a4320" stroke-width="6"/>'
    )
    out.append(
        f'<text x="1685" y="985" font-size="34" text-anchor="middle" fill="{INK}" font-family="sans-serif" '
        f'font-weight="bold">Ready!</text>'
    )
    out.append("</svg>")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument(
        "--out", default=str(pathlib.Path.home() / "Downloads" / "viking" / "how-to" / "all_svgs")
    )
    args = parser.parse_args()
    out = pathlib.Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    data = HowToData.model_validate(json.loads(DATA.read_text(encoding="utf-8")))
    written = []
    for players in (1, 2):
        parts = [part for part in data.parts if players in part.players]
        for index, part in enumerate(parts):
            for k, t in enumerate(part.stills):
                suffix = f"_{k + 1}" if len(part.stills) > 1 else ""
                name = f"{players}_rower{'s' if players == 2 else ''}_{index + 1:02d}_{part.id}{suffix}.svg"
                (out / name).write_text(screen(part, t, players), encoding="utf-8")
                written.append((name, part.title, part.text))
    lines = [
        "# How to play",
        "",
        "The screens of How to play (scenes/how_to/how_to.gd), drawn by dev/how_to/make_svgs.py from",
        "data/how_to/how_to.json: the players in the camera picture (mirrored) on the left, what it",
        "does on the right. In the game, they move: the rowers row, and the boat of the game answers.",
        "",
    ]
    lines += [f"* `{name}`: **{title}**: {text}" for name, title, text in written]
    (out / "SVGS.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {len(written)} SVGs into {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
