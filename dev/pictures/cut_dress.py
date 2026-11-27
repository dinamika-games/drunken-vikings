"""
Cut the painted dress of Ylva for the camera picture out of its paintings.

The paintings were made with ChatGPT from the prompts of
~/Downloads/viking/dress/ (see its README.md): each piece on flat magenta
(#FF00FF), and the hair over the face template of The Steppe Rescue
(face_template.png: the middle between the eyes at 440, 680, the eyes 200
pixels apart). The game dresses the player up with them (see CameraPanel):

* head: the hair, placed by the eyes; cut from the template by what differs
  from it, in the box of OVERLAY_BOX eye distances around the eyes;
* bodice: the dress cut off just below its belt (ChatGPT painted the whole
  dress), laid from the shoulders down to the waist;
* skirt: over the lap, from the waist (under the belt of the bodice) to the
  knees;
* sleeve: from the shoulder (left) to the cuff (right), bent along the arm;
* fist_reach and fist_pull: the left fist on the oar, reaching forward and
  pulled to the chest (mirrored for the right hand); ChatGPT painted the
  sleeves on, so the sleeve and its red cuff are cut off.

Where the game should put each piece (the shoulders, the waist, the wrist,
...) goes into assets/pictures/dress/dress.json, in the pixels of the cut
pictures.

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/pictures/cut_dress.py [<the folder of the prompts, ~/Downloads/viking/dress>]
"""

import pathlib
import sys

import cv2
import numpy as np
import pydantic
from PIL import Image

REPO = pathlib.Path(__file__).resolve().parents[2]
OUT = REPO / "assets" / "pictures" / "dress"
DEFAULT = pathlib.Path.home() / "Downloads" / "viking" / "dress"

# The face template: the middle between the eyes, and the eye distance, in pixels.
TEMPLATE_MIDDLE = (440.0, 680.0)
TEMPLATE_EYES = 200.0

# The box of the head around the middle between the eyes, in eye distances
# (as FrontView.OVERLAY_BOX of The Steppe Rescue), and the pixels per eye
# distance of the cut head.
HEAD_BOX = (-2.2, -3.4, 4.4, 7.6)
HEAD_UNIT = 100

# The other pieces are halved, to keep the game small.
SCALE = 0.5

MAGENTA = np.array([255.0, 0.0, 255.0])


class Point(pydantic.BaseModel):
    x: float
    y: float


class Head(pydantic.BaseModel):
    """The middle between the eyes, and the eye distance, in pixels."""

    eyes: Point
    eye_distance: float


class Bodice(pydantic.BaseModel):
    """The outer corners of the shoulders at the top, and of the waist at the bottom."""

    shoulder_left: Point
    shoulder_right: Point
    waist_left: Point
    waist_right: Point


class Skirt(pydantic.BaseModel):
    """The corners of the waistband at the top, and the hem at the knees."""

    waist_left: Point
    waist_right: Point
    hem_y: float


class Sleeve(pydantic.BaseModel):
    """The shoulder end and the cuff end along the middle, and how thick it is at the elbow."""

    shoulder: Point
    cuff: Point
    thickness: float


class Fist(pydantic.BaseModel):
    """
    The middle of the hand (which the game puts on the hand which the hand
    detector finds), where the wrist goes into the sleeve, how wide the fist
    is (with the oar), and the height of the oar handle.
    """

    hand: Point
    wrist: Point
    width: float
    handle_y: float


class Dress(pydantic.BaseModel):
    head: Head
    bodice: Bodice
    skirt: Skirt
    sleeve: Sleeve
    fist_reach: Fist
    fist_pull: Fist


def load(path: pathlib.Path) -> np.ndarray:
    if not path.exists():
        sys.exit(f"Missing {path}; see the README.md of the prompts.")
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64)


def key_magenta(rgb: np.ndarray) -> np.ndarray:
    """Key out the magenta, and take its tint out of the edges; return RGBA (float)."""
    distance = np.linalg.norm(rgb - MAGENTA, axis=2)
    alpha = np.clip((distance - 60.0) / 90.0, 0.0, 1.0)
    # NOTE: An edge pixel is the paint mixed with the magenta: unmix it.
    safe = np.maximum(alpha, 1e-3)[..., None]
    color = np.clip((rgb - (1.0 - safe) * MAGENTA) / safe, 0.0, 255.0)
    return np.dstack([color, alpha * 255.0])


def clean(rgba: np.ndarray, open_px: int = 0) -> np.ndarray:
    """Keep the big parts of the piece: drop the specks and, with open_px, thin lines."""
    mask = (rgba[..., 3] > 127).astype(np.uint8)
    if open_px > 0:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (open_px, open_px))
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    if count <= 1:
        return rgba
    biggest = stats[1:, cv2.CC_STAT_AREA].max()
    keep = np.zeros(count, dtype=bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= 0.05 * biggest
    near = cv2.dilate(keep[labels].astype(np.uint8), np.ones((5, 5), np.uint8))
    out = rgba.copy()
    out[..., 3] *= near
    return out


def crop(rgba: np.ndarray, margin: int = 4) -> tuple[np.ndarray, tuple[int, int]]:
    """Crop to the opaque part with a margin; return it with the offset of its corner."""
    ys, xs = np.nonzero(rgba[..., 3] > 8)
    top, left = max(0, ys.min() - margin), max(0, xs.min() - margin)
    bottom, right = min(rgba.shape[0], ys.max() + 1 + margin), min(
        rgba.shape[1], xs.max() + 1 + margin
    )
    return rgba[top:bottom, left:right], (left, top)


def save(rgba: np.ndarray, name: str, scale: float = SCALE) -> float:
    """Save the piece scaled; return the scale."""
    image = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    if scale != 1.0:
        image = image.resize(
            (round(image.width * scale), round(image.height * scale)), Image.LANCZOS
        )
    OUT.mkdir(parents=True, exist_ok=True)
    image.save(OUT / f"{name}.png")
    print(f"Wrote {name}.png ({image.width} x {image.height}).")
    return scale


def extent(alpha: np.ndarray, y: int) -> tuple[float, float]:
    xs = np.nonzero(alpha[y] > 127)[0]
    return float(xs.min()), float(xs.max())


def eyes_of(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The centres of the two dark eyes of the template in a painting over it."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dark = (np.abs(r - g) < 14) & (np.abs(g - b) < 14) & (r < 80)
    count, _, stats, centres = cv2.connectedComponentsWithStats(
        dark.astype(np.uint8), 8
    )
    h, w = dark.shape
    found = [
        centres[k]
        for k in range(1, count)
        if 600 < stats[k, cv2.CC_STAT_AREA] < 8000
        and 1.2
        < stats[k, cv2.CC_STAT_WIDTH] / max(1, stats[k, cv2.CC_STAT_HEIGHT])
        < 3.5
        and 0.3 * h < centres[k][1] < 0.6 * h
    ]
    pairs = [
        (abs((a[0] + c[0]) / 2 - w / 2), a, c)
        for a in found
        for c in found
        if abs(c[1] - a[1]) < 8 and 0.12 * w < c[0] - a[0] < 0.35 * w
    ]
    if not pairs:
        sys.exit("Could not find the eyes of the template in the painting of the head.")
    _, left, right = min(pairs, key=lambda p: p[0])
    return np.asarray(left), np.asarray(right)


def cut_head(folder: pathlib.Path) -> Head:
    painting = load(folder / "01_head" / "head.png")
    template = np.asarray(
        Image.open(folder / "01_head" / "face_template.png").convert("RGB")
    ).astype(np.float64)
    left, right = eyes_of(painting)
    t_left, t_right = eyes_of(template)

    # NOTE: Bring the painting onto the template by the eyes (a similarity).
    scale = np.linalg.norm(t_right - t_left) / np.linalg.norm(right - left)
    angle = np.arctan2(*(t_right - t_left)[::-1]) - np.arctan2(*(right - left)[::-1])
    c, s = scale * np.cos(angle), scale * np.sin(angle)
    middle, t_middle = (left + right) / 2, (t_left + t_right) / 2
    matrix = np.array([[c, -s, 0.0], [s, c, 0.0]])
    matrix[:, 2] = t_middle - matrix[:, :2] @ middle
    h, w = template.shape[:2]
    warped = cv2.warpAffine(
        painting,
        matrix,
        (w, h),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_REPLICATE,
    )

    # NOTE: The hair is what differs from the template. The eyes, the nose and
    # the mouth were repainted a little off, so we leave the face out.
    difference = np.abs(warped - template).max(axis=2)
    alpha = np.clip((difference - 30.0) / 40.0, 0.0, 1.0)
    face = np.zeros((h, w), np.uint8)
    cv2.ellipse(
        face, (int(t_middle[0]), int(t_middle[1]) + 120), (150, 230), 0, 0, 360, 1, -1
    )
    hair_over_face = (warped[..., 0] - warped[..., 2] > 60) & (warped[..., 0] > 120)
    alpha[(face > 0) & ~hair_over_face] = 0.0
    # NOTE: The edges of the template (the shoulders, the neck) were repainted
    # a little off, too; they are pale and gray, the hair is not.
    pale_gray = (warped.max(axis=2) - warped.min(axis=2) < 25) & (
        warped.min(axis=2) > 90
    )
    alpha[pale_gray] = 0.0
    head = clean(np.dstack([warped, alpha * 255.0]))

    eye_px = np.linalg.norm(t_right - t_left)
    box = HEAD_BOX
    x0, y0 = t_middle[0] + box[0] * eye_px, t_middle[1] + box[1] * eye_px
    x1, y1 = x0 + box[2] * eye_px, y0 + box[3] * eye_px
    region = head[int(round(y0)) : int(round(y1)), int(round(x0)) : int(round(x1))]
    save(region, "head", HEAD_UNIT / eye_px)
    return Head(
        eyes=Point(x=-box[0] * HEAD_UNIT, y=-box[1] * HEAD_UNIT), eye_distance=HEAD_UNIT
    )


def cut_bodice(folder: pathlib.Path) -> Bodice:
    rgba = clean(key_magenta(load(folder / "02_bodice" / "bodice.png")))
    rgb, alpha = rgba[..., :3], rgba[..., 3]
    teal = (rgb[..., 1] > rgb[..., 0] + 25) & (rgb[..., 2] > rgb[..., 0])
    opaque = alpha > 127
    rows = np.nonzero(opaque.any(axis=1))[0]
    top, bottom = rows.min(), rows.max()

    # NOTE: The belt is the band of rows in the middle with little teal; we
    # cut just below it, with its outline.
    share = np.array(
        [teal[y].sum() / max(1, opaque[y].sum()) for y in range(rgba.shape[0])]
    )
    lo, hi = top + int(0.3 * (bottom - top)), top + int(0.65 * (bottom - top))
    belt = [y for y in range(lo, hi) if share[y] < 0.35]
    if not belt:
        sys.exit("Could not find the belt of the dress.")
    cut = max(belt) + 1
    while cut < bottom and share[cut] < 0.6:
        cut += 1
    cut += 2
    bodice = rgba[:cut].copy()
    bodice, (dx, dy) = crop(bodice)
    s = save(bodice, "bodice")

    a = bodice[..., 3]
    first = int(np.nonzero((a > 127).any(axis=1))[0].min())
    # NOTE: The shoulders: the outer edges a little below the top of the straps.
    shoulder_y = first + int(0.03 * a.shape[0])
    sl, sr = extent(a, shoulder_y)
    last = int(np.nonzero((a > 127).any(axis=1))[0].max()) - 3
    wl, wr = extent(a, last)
    return Bodice(
        shoulder_left=Point(x=sl * s, y=first * s),
        shoulder_right=Point(x=sr * s, y=first * s),
        waist_left=Point(x=wl * s, y=last * s),
        waist_right=Point(x=wr * s, y=last * s),
    )


def cut_skirt(folder: pathlib.Path) -> Skirt:
    rgba, _ = crop(clean(key_magenta(load(folder / "03_skirt" / "skirt.png"))))
    s = save(rgba, "skirt")
    a = rgba[..., 3]
    rows = np.nonzero((a > 127).any(axis=1))[0]
    top = int(rows.min()) + 3
    wl, wr = extent(a, top)
    return Skirt(
        waist_left=Point(x=wl * s, y=top * s),
        waist_right=Point(x=wr * s, y=top * s),
        hem_y=float(rows.max()) * s,
    )


def cut_sleeve(folder: pathlib.Path) -> Sleeve:
    rgba, _ = crop(clean(key_magenta(load(folder / "04_sleeve" / "sleeve.png"))))
    s = save(rgba, "sleeve")
    a = rgba[..., 3] > 127
    cols = np.nonzero(a.any(axis=0))[0]
    left, right = int(cols.min()), int(cols.max())

    def middle(x: int) -> float:
        ys = np.nonzero(a[:, x])[0]
        return (ys.min() + ys.max()) / 2.0

    elbow = (left + right) // 2
    ys = np.nonzero(a[:, elbow])[0]
    return Sleeve(
        shoulder=Point(x=left * s, y=middle(left + 10) * s),
        cuff=Point(x=right * s, y=middle(right - 10) * s),
        thickness=float(ys.max() - ys.min()) * s,
    )


def cut_fists(folder: pathlib.Path) -> tuple[Fist, Fist]:
    rgba = key_magenta(load(folder / "05_fists" / "fists.png"))
    w = rgba.shape[1]
    fists = []
    for name, half in (
        ("fist_reach", rgba[:, : w // 2]),
        ("fist_pull", rgba[:, w // 2 :]),
    ):
        piece = half.copy()
        rgb = piece[..., :3]
        hsv = cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_RGB2HSV).astype(int)
        hue, saturation, value = hsv[..., 0], hsv[..., 1], hsv[..., 2]
        # NOTE: The sleeve is teal; the cuff is a bright red braid (the hue
        # below 9 of OpenCV's 180), which the outline (dark red-brown) and the
        # shaded skin (orange, the hue from 11 on) are not.
        teal = (hue > 70) & (hue < 110) & (saturation > 40)
        red = ((hue < 9) | (hue > 170)) & (saturation > 120) & (value > 110)
        cuff = red & (piece[..., 3] > 127)
        ys, xs = np.nonzero(cuff)
        wrist = (float(xs.mean()), float(ys.mean()))
        # NOTE: Off with the sleeve and its cuff, and with their outlines
        # (thin lines, which the opening takes away).
        removed = (
            cv2.dilate((teal | red).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
        )
        piece[..., 3] *= ~removed
        piece = clean(piece, open_px=11)
        piece, (dx, dy) = crop(piece)
        s = save(piece, name)
        a = piece[..., 3] > 127
        cols = np.nonzero(a.any(axis=0))[0]
        rows = np.nonzero(a.any(axis=1))[0]
        # NOTE: The handle: the light wood which sticks out on both sides of
        # the fist, at its ends.
        wood_y = []
        for x in (cols.min() + 6, cols.max() - 6):
            ys = np.nonzero(a[:, x])[0]
            wood_y.append((ys.min() + ys.max()) / 2.0)
        fists.append(
            Fist(
                hand=Point(
                    x=(cols.min() + cols.max()) / 2.0 * s,
                    y=(rows.min() + rows.max()) / 2.0 * s,
                ),
                wrist=Point(x=(wrist[0] - dx) * s, y=(wrist[1] - dy) * s),
                width=float(cols.max() - cols.min()) * s,
                handle_y=float(np.mean(wood_y)) * s,
            )
        )
    return fists[0], fists[1]


def main() -> int:
    folder = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    reach, pull = cut_fists(folder)
    dress = Dress(
        head=cut_head(folder),
        bodice=cut_bodice(folder),
        skirt=cut_skirt(folder),
        sleeve=cut_sleeve(folder),
        fist_reach=reach,
        fist_pull=pull,
    )
    (OUT / "dress.json").write_text(dress.model_dump_json(indent=2) + "\n")
    print(f"Wrote dress.json:\n{dress.model_dump_json(indent=2)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
