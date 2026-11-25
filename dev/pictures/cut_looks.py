"""
Cut the looks of the players: the viking boy, and the colour masks with which
the game recolours the skin, the hair and the clothes of every rower.

The paintings were made with ChatGPT from the prompts of
~/Downloads/viking-masks/ (see its README.md). Each is a sheet of 1536 x 1024
pixels on which the pieces sit where the manifest.json of its folder says:

* 02_girl/mask_ylva.png: the mask of Ylva's dress-up (the pieces of
  assets/pictures/dress/, laid out at their size);
* 05_boy_from_scratch/sheet_boy.png and mask_boy.png: the boy's dress-up, in
  the places of Ylva's pieces, and its mask;
* 04_rower_girl/mask_rowers_girls.png: the mask of the rowers of
  assets/pictures/rowboat/ (Ylva pulls both oars, Sigrid one), laid out 1.4
  times their size;
* 03_rower_boy/sheet_rowers_boy.png and mask_rowers_boy.png: the boy in the
  same poses and in the same boxes, and its mask.

A mask paints every area with one flat colour: red the skin, green the hair,
blue the clothes, white what keeps its colour, black the background. ChatGPT
drew it a little off and drew the outlines in black, so every pixel of a
picture takes the area of the nearest pixel of the mask which has one (see
``fit_mask``). The masks are saved next to their pictures as
<name>_mask.png, in the same colours (transparent outside the picture).

The boy's dress-up goes into assets/pictures/dress_boy/ with its dress.json
(the same anchors as cut_dress.py finds for Ylva), and the boy rowing into
assets/pictures/rowboat/ as boy_<pose>.png (both oars, in Ylva's boxes) and
boy_one_<pose>.png (one oar, in Sigrid's boxes), at the size of the girls'
pictures, so that the hands hold the oars where theirs do.

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/pictures/cut_looks.py [<the folder of the prompts, ~/Downloads/viking-masks>]
"""

import pathlib
import sys
from typing import Dict, Tuple

import cv2
import numpy as np
import pydantic
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import cut_dress  # noqa: E402  (the sibling module, after the path)

REPO = pathlib.Path(__file__).resolve().parents[2]
PICTURES = REPO / "assets" / "pictures"
DEFAULT = pathlib.Path.home() / "Downloads" / "viking-masks"

#: The areas of a mask, by their index, and their colours.
AREAS = ["background", "skin", "hair", "clothes", "keep"]
COLORS = np.array([[0, 0, 0], [255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]], dtype=np.float64)

#: A patch of an area smaller than this share of the picture is a speck which
#: ChatGPT left (e.g., white flecks in the hair); it takes the area around it.
SPECK = 0.0015

#: A pixel to keep within this many pixels of the hair, in the colour of the
#: hair, is hair (see ``hair_back``).
HAIR_NEAR = 15

#: The cuff of a fist of the boy is at most this many pixels from his sleeve.
CUFF_PX = 45.0


class Box(pydantic.BaseModel):
    x: int
    y: int
    width: int
    height: int


class DressManifest(pydantic.BaseModel):
    """Where the pieces of the dress-up sit on its sheet (at scale 1)."""

    pieces: Dict[str, Box]


class RowerManifest(pydantic.BaseModel):
    """Where the rowers sit on their sheet, and how much larger than in the game."""

    scale: float
    sprites: Dict[str, Box]


#: Where to look for each piece of the boy's dress-up on his sheet: (left, top,
#: right, bottom). His pieces sit where Ylva's do, but are not as big.
BOY_REGIONS = {
    "skirt": (520, 0, 1290, 470),
    "bodice": (1290, 0, 1536, 400),
    "sleeve": (520, 470, 1290, 690),
    "fist_reach": (520, 690, 900, 1024),
    "fist_pull": (900, 690, 1290, 1024),
}


def load_rgb(path: pathlib.Path) -> np.ndarray:
    if not path.exists():
        sys.exit(f"Missing {path}; see the README.md of the prompts.")
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64)


def load_rgba(path: pathlib.Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)


def areas_of(mask_rgb: np.ndarray) -> np.ndarray:
    """The index of the area of each pixel of a painted mask: the nearest of the colours."""
    distances = np.linalg.norm(mask_rgb[..., None, :] - COLORS[None, None, :, :], axis=3)
    return distances.argmin(axis=2).astype(np.uint8)


def fit_mask(areas: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """
    Fit the [areas] onto a picture of the same size with the [alpha]: every
    pixel of the picture takes the area of the nearest pixel which has one
    (the outlines, the edges a little off, the specks); return the mask as
    RGBA (uint8).
    """
    inside = alpha > 8
    known = areas.copy()
    known[~inside] = 0
    # NOTE: The specks: small patches of an area within another.
    for index in range(1, len(AREAS)):
        count, labels, stats, _ = cv2.connectedComponentsWithStats((known == index).astype(np.uint8), 8)
        small = np.nonzero(stats[1:, cv2.CC_STAT_AREA] < SPECK * inside.sum())[0] + 1
        known[np.isin(labels, small)] = 0
    unknown = (known == 0).astype(np.uint8)
    if unknown.all():
        sys.exit("A mask has no area within its picture.")
    _, nearest = cv2.distanceTransformWithLabels(unknown, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    # NOTE: The label of a pixel is the index of its nearest known pixel (a
    # zero of the input), numbered along the rows.
    ys, xs = np.nonzero(unknown == 0)
    by_label = np.zeros(nearest.max() + 1, dtype=np.uint8)
    by_label[nearest[ys, xs]] = known[ys, xs]
    filled = by_label[nearest]
    filled[~inside] = 0
    rgba = np.zeros(areas.shape + (4,), dtype=np.uint8)
    rgba[..., :3] = COLORS[filled].astype(np.uint8)
    rgba[..., 3] = np.where(inside, 255, 0)
    return rgba


def save_rgba(rgba: np.ndarray, path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA").save(path)
    print(f"Wrote {path.relative_to(REPO)} ({rgba.shape[1]} x {rgba.shape[0]}).")


def hair_back(areas: np.ndarray, rgb: np.ndarray) -> np.ndarray:
    """
    Give the hair back what the mask marked to keep next to it but is
    painted in the colour of blond hair (ChatGPT drew the bands wider than
    they are): golden (the hue from 28 degrees on, much more red than blue,
    not red), unlike the leather bands (browner), the red ties and the
    linen; return the areas.
    """
    hair = areas == AREAS.index("hair")
    if not hair.any():
        return areas
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hsv = cv2.cvtColor(np.clip(rgb, 0, 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(int)
    golden = (hsv[..., 0] >= 14) & (r - b > 70) & (g > 0.55 * r)
    near_hair = cv2.dilate(hair.astype(np.uint8), np.ones((HAIR_NEAR, HAIR_NEAR), np.uint8)) > 0
    result = areas.copy()
    result[(areas == AREAS.index("keep")) & golden & near_hair] = AREAS.index("hair")
    return result


def save_mask(areas: np.ndarray, picture: pathlib.Path) -> None:
    """Fit the [areas] to the [picture] and save its mask next to it."""
    rgba = load_rgba(picture)
    alpha = rgba[..., 3]
    if areas.shape != alpha.shape:
        areas = cv2.resize(areas, (alpha.shape[1], alpha.shape[0]), interpolation=cv2.INTER_NEAREST)
    areas = hair_back(areas, rgba[..., :3])
    save_rgba(fit_mask(areas, alpha), picture.with_name(picture.stem + "_mask.png"))


def crop_box(image: np.ndarray, box: Box) -> np.ndarray:
    return image[box.y : box.y + box.height, box.x : box.x + box.width]


def resize_rgba(rgba: np.ndarray, size: Tuple[int, int]) -> np.ndarray:
    """Resize with the colours weighted by the alpha, so that the edges keep their colour."""
    alpha = rgba[..., 3:] / 255.0
    premultiplied = np.dstack([rgba[..., :3] * alpha, rgba[..., 3:]]).astype(np.float32)
    resized = cv2.resize(premultiplied, size, interpolation=cv2.INTER_AREA)
    a = np.maximum(resized[..., 3:] / 255.0, 1e-3)
    return np.dstack([np.clip(resized[..., :3] / a, 0, 255), resized[..., 3:]])


def ylva_masks(folder: pathlib.Path) -> None:
    """The masks of Ylva's dress-up: her pieces sit on the sheet at their size."""
    manifest = DressManifest.model_validate_json((folder / "02_girl" / "manifest.json").read_text())
    areas = areas_of(load_rgb(folder / "02_girl" / "mask_ylva.png"))
    for name, box in manifest.pieces.items():
        save_mask(crop_box(areas, box), PICTURES / "dress" / f"{name}.png")


def cut_boy_dress(folder: pathlib.Path) -> None:
    """The boy's dress-up from his sheet, its anchors and its masks."""
    sub = folder / "05_boy_from_scratch"
    manifest = DressManifest.model_validate_json((sub / "manifest.json").read_text())
    sheet = cut_dress.key_magenta(load_rgb(sub / "sheet_boy.png"))
    areas = areas_of(load_rgb(sub / "mask_boy.png"))
    out = PICTURES / "dress_boy"
    cut_dress.OUT = out

    # NOTE: The hair sits in the box of Ylva's hair, by the same eyes.
    head_box = manifest.pieces["head"]
    head = cut_dress.clean(crop_box(sheet, head_box))
    cut_dress.save(head, "head", 1.0)
    save_mask(crop_box(areas, head_box), out / "head.png")
    head_anchor = cut_dress.Head(eyes=cut_dress.Point(x=220.0, y=340.0), eye_distance=100.0)

    pieces = {}
    for name, (left, top, right, bottom) in BOY_REGIONS.items():
        region = sheet[top:bottom, left:right].copy()
        region_areas = areas[top:bottom, left:right].copy()
        if name.startswith("fist"):
            region, wrist = _off_with_the_sleeve(region, region_areas)
        else:
            region = cut_dress.clean(region)
            wrist = None
        piece, (dx, dy) = cut_dress.crop(region)
        cut_dress.save(piece, name, 1.0)
        piece_areas = region_areas[dy : dy + piece.shape[0], dx : dx + piece.shape[1]]
        save_mask(piece_areas, out / f"{name}.png")
        pieces[name] = (piece, None if wrist is None else (wrist[0] - dx, wrist[1] - dy))

    dress = cut_dress.Dress(
        head=head_anchor,
        bodice=_bodice_anchors(pieces["bodice"][0]),
        skirt=_skirt_anchors(pieces["skirt"][0]),
        sleeve=_sleeve_anchors(pieces["sleeve"][0]),
        fist_reach=_fist_anchors(*pieces["fist_reach"]),
        fist_pull=_fist_anchors(*pieces["fist_pull"]),
    )
    (out / "dress.json").write_text(dress.model_dump_json(indent=2) + "\n")
    print(f"Wrote dress_boy/dress.json:\n{dress.model_dump_json(indent=2)}")


def _off_with_the_sleeve(region: np.ndarray, areas: np.ndarray) -> Tuple[np.ndarray, Tuple[float, float]]:
    """
    Take the sleeve and its cuff off a fist (the game draws the sleeve
    along the arm): the clothes of the mask, and the area which keeps its
    colour next to them (the cuff; the oar handle lies apart). Return the
    fist and where its wrist went into the cuff.
    """
    clothes = areas == AREAS.index("clothes")
    # NOTE: The edges of the white in the mask come out bluish here and there:
    # the sleeve is the big part of the clothes, not those.
    count, labels, stats, _ = cv2.connectedComponentsWithStats(clothes.astype(np.uint8), 8)
    if count > 1:
        biggest = stats[1:, cv2.CC_STAT_AREA].max()
        clothes = np.isin(labels, np.nonzero(stats[:, cv2.CC_STAT_AREA] >= 0.2 * biggest)[0][1:])
    keep = areas == AREAS.index("keep")
    # NOTE: The cuff and the handle touch in the mask; the cuff is the band
    # which keeps its colour next to the sleeve, the handle lies farther.
    to_clothes = cv2.distanceTransform((~clothes).astype(np.uint8), cv2.DIST_L2, 5)
    cuff = keep & (to_clothes < CUFF_PX)
    if not cuff.any():
        sys.exit("Could not find the cuff of a fist of the boy.")
    ys, xs = np.nonzero(cuff)
    # NOTE: The wrist is where the cuff meets the hand: the middle of the cuff.
    wrist = (float(xs.mean()), float(ys.mean()))
    removed = cv2.dilate((clothes | cuff).astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
    fist = region.copy()
    fist[..., 3] *= ~removed
    return cut_dress.clean(fist, open_px=11), wrist


def _bodice_anchors(bodice: np.ndarray) -> cut_dress.Bodice:
    a = bodice[..., 3]
    rows = np.nonzero((a > 127).any(axis=1))[0]
    first = int(rows.min())
    shoulder_y = first + int(0.03 * a.shape[0])
    sl, sr = cut_dress.extent(a, shoulder_y)
    # NOTE: The belt of the boy is outlined and rounded at its bottom, so the
    # last rows narrow to a sliver; the waist is the lowest row which is
    # still about as wide as the widest row of the lower quarter (else the
    # game, which fits the waist to the shoulders, blows the bodice up).
    widths = {
        y: np.subtract(*cut_dress.extent(a, y)[::-1])
        for y in rows
        if y >= first + 0.75 * (rows.max() - first)
    }
    widest = max(widths.values())
    last = max(y for y, width in widths.items() if width >= 0.97 * widest)
    wl, wr = cut_dress.extent(a, last)
    return cut_dress.Bodice(
        shoulder_left=cut_dress.Point(x=sl, y=first),
        shoulder_right=cut_dress.Point(x=sr, y=first),
        waist_left=cut_dress.Point(x=wl, y=last),
        waist_right=cut_dress.Point(x=wr, y=last),
    )


def _skirt_anchors(skirt: np.ndarray) -> cut_dress.Skirt:
    a = skirt[..., 3]
    rows = np.nonzero((a > 127).any(axis=1))[0]
    top = int(rows.min()) + 3
    wl, wr = cut_dress.extent(a, top)
    return cut_dress.Skirt(
        waist_left=cut_dress.Point(x=wl, y=top),
        waist_right=cut_dress.Point(x=wr, y=top),
        hem_y=float(rows.max()),
    )


def _sleeve_anchors(sleeve: np.ndarray) -> cut_dress.Sleeve:
    a = sleeve[..., 3] > 127
    cols = np.nonzero(a.any(axis=0))[0]
    left, right = int(cols.min()), int(cols.max())

    def middle(x: int) -> float:
        ys = np.nonzero(a[:, x])[0]
        return (ys.min() + ys.max()) / 2.0

    ys = np.nonzero(a[:, (left + right) // 2])[0]
    return cut_dress.Sleeve(
        shoulder=cut_dress.Point(x=left, y=middle(left + 10)),
        cuff=cut_dress.Point(x=right, y=middle(right - 10)),
        thickness=float(ys.max() - ys.min()),
    )


def _fist_anchors(fist: np.ndarray, wrist: Tuple[float, float]) -> cut_dress.Fist:
    a = fist[..., 3] > 127
    cols = np.nonzero(a.any(axis=0))[0]
    rows = np.nonzero(a.any(axis=1))[0]
    wood_y = []
    for x in (cols.min() + 6, cols.max() - 6):
        ys = np.nonzero(a[:, x])[0]
        wood_y.append((ys.min() + ys.max()) / 2.0)
    return cut_dress.Fist(
        hand=cut_dress.Point(x=(cols.min() + cols.max()) / 2.0, y=(rows.min() + rows.max()) / 2.0),
        wrist=cut_dress.Point(x=wrist[0], y=wrist[1]),
        width=float(cols.max() - cols.min()),
        handle_y=float(np.mean(wood_y)),
    )


def rowers(folder: pathlib.Path) -> None:
    """The masks of the girls rowing, and the boy rowing with his masks."""
    manifest = RowerManifest.model_validate_json((folder / "04_rower_girl" / "manifest.json").read_text())
    girls = areas_of(load_rgb(folder / "04_rower_girl" / "mask_rowers_girls.png"))
    boy = cut_dress.key_magenta(load_rgb(folder / "03_rower_boy" / "sheet_rowers_boy.png"))
    boy_areas = areas_of(load_rgb(folder / "03_rower_boy" / "mask_rowers_boy.png"))
    out = PICTURES / "rowboat"
    for name, box in manifest.sprites.items():
        girl_picture = out / f"{name}.png"
        save_mask(crop_box(girls, box), girl_picture)
        who, pose = name.split("_")
        size = Image.open(girl_picture).size
        boy_picture = out / (f"boy_{pose}.png" if who == "ylva" else f"boy_one_{pose}.png")
        figure = cut_dress.clean(resize_rgba(crop_box(boy, box), size))
        save_rgba(figure, boy_picture)
        save_mask(crop_box(boy_areas, box), boy_picture)


def main() -> int:
    folder = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    ylva_masks(folder)
    cut_boy_dress(folder)
    rowers(folder)
    return 0


if __name__ == "__main__":
    sys.exit(main())
