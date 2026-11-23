#!/usr/bin/env python3

"""
Cut the painted sheets into the pictures of the game.

The sheets were painted with ChatGPT after the prompts of
~/Downloads/viking/<nn_name>/PROMPT.md, each a grid of pictures on a
transparent background, the cells about equal but not exact. Each cell is
cropped to what is painted in it (its alpha) and saved as
assets/pictures/<sheet>/<name>.png.

Some sheets came with a half-transparent background instead of a transparent
one; for them, the alpha is stretched so that the background vanishes and the
pictures become opaque (see ``Sheet.alpha``). The textures of the ground are
cut edge to edge and made opaque.

The seamless textures of the ground are scaled to 512 x 512, and the painting
of the start screen to 1920 x 1080 (saved as a JPEG).

Run with the development tools (see CONTRIBUTING.md):

  venv/bin/python dev/pictures/cut_sheets.py [<sheet name> ...]
"""

import dataclasses
import pathlib
import sys
from typing import List, Optional, Sequence, Tuple

import numpy as np
from PIL import Image

REPO = pathlib.Path(__file__).resolve().parents[2]
SHEETS_DIR = pathlib.Path.home() / "Downloads" / "viking"
OUT = REPO / "assets" / "pictures"

#: The pictures are at most this many pixels on a side.
MAX_SIDE = 512

#: Leave this many transparent pixels around each picture.
MARGIN = 4

#: A row or a column of a cell belongs to the picture from this many painted
#: pixels on, so that stray specks do not widen the crop.
MIN_PAINTED = 3

#: The textures of the ground are saved with this many pixels on a side.
TEXTURE_SIDE = 256


@dataclasses.dataclass
class Sheet:
    """A sheet of pictures in a grid."""

    #: The file of the sheet, relative to SHEETS_DIR.
    path: str

    #: The names of the pictures, row by row; "" skips a cell.
    names: List[List[str]]

    #: The alpha from which a pixel counts as painted, and the alpha which
    #: counts as fully opaque; the alpha in between is stretched.
    alpha: Tuple[int, int] = (24, 230)

    #: The pictures which are textures, cut edge to edge and made opaque.
    textures: Sequence[str] = ()


SHEETS = {
    "rowboat": Sheet(
        "01_rowboat/sheet_rowboat.png",
        [
            ["hull", "hull_cargo", "oar", "oar_splash"],
            ["ylva_forward", "ylva_middle", "ylva_back", "ylva_wave"],
            ["sigrid_forward", "sigrid_middle", "sigrid_back", "sigrid_wave"],
        ],
    ),
    "longships": Sheet(
        "02_longships/sheet_longships.png",
        [
            ["hull_plain", "hull_wedding", "hull_pirate", "oar"],
            ["sail_plain_full", "sail_plain_slack", "sail_wedding_full", "sail_wedding_slack"],
            ["sail_pirate_full", "sail_pirate_slack", "bride_and_groom", "oar_splash"],
            ["crew_wedding", "crew_plain", "crew_pirate", "pirate_fist"],
        ],
    ),
    "skippers": Sheet(
        "03_skippers/sheet_skippers.png",
        [["ragna", "halvard", "inga"], ["bjorn", "freya_and_liv", "sigvor"]],
    ),
    "faces": Sheet(
        "04_faces/sheet_faces.png",
        [
            ["ylva", "sigrid", "grandmother", "healer"],
            ["ragna", "halvard", "inga", "bjorn"],
            ["freya_and_liv", "sigvor", "market", "inn"],
            ["smith", "chieftain", "weaver", "horse_farm"],
        ],
    ),
    "goods": Sheet(
        "05_goods/sheet_goods.png",
        [
            ["eggs", "flowers", "grain", "hay", "flax"],
            ["wool", "herbs", "cheese", "pots", "fish"],
            ["ale", "honey", "salt", "mead", "cloth"],
            ["tools", "coin", "hacksilver", "scale", "purse"],
        ],
    ),
    "treats": Sheet(
        "06_treats/sheet_treats.png",
        [["wreath", "ribbon", "cake", "apple"], ["bread", "bouquet", "toy_horse", "coin"]],
    ),
    "buildings": Sheet(
        "07_buildings/sheet_buildings.png",
        [
            ["longhouse_turf", "longhouse_shingles", "longhouse_thatch", "barn"],
            ["hall", "market", "smithy", "mill"],
            ["kiln", "inn", "herb_hut", "storehouse"],
            ["jetty_land", "jetty_middle", "jetty_end", "boathouse"],
        ],
    ),
    "farm": Sheet(
        "08_farm/sheet_farm.png",
        [
            ["fence", "fence_corner", "gate", "hen", "rooster"],
            ["sheep", "lamb", "goat", "cow", "calf"],
            ["horse", "foal", "beehive", "fish_rack", "barrels"],
            ["herb_bed", "cloth_line", "garden", "barley_young", "barley_ripe"],
            ["flax_young", "flax_bloom", "hay_meadow", "flower_field", "birds"],
        ],
        alpha=(205, 245),
    ),
    "nature": Sheet(
        "09_nature/sheet_nature.png",
        [
            ["pine", "spruce", "birch", "trees"],
            ["berry_bush", "rock", "rocks", "reeds"],
            ["lilies", "log", "wild_flowers", "mushrooms"],
            ["grass", "sand", "forest_floor", "island"],
        ],
        alpha=(170, 245),
        textures=("grass", "sand", "forest_floor"),
    ),
    "farm_view": Sheet(
        "11_farm_view/sheet_farm_view.png",
        [
            ["soil", "sown", "sprouts", "meadow_young"],
            ["flowers_young", "stubble", "birds_pecking", "scarecrow"],
            ["trough_full", "trough_empty", "water_trough", "hen_house"],
            ["plot_sign", "grandmother", "cat", "store"],
        ],
    ),
    "grass_details": Sheet(
        "12_grass/sheet_grass_details.png",
        [
            ["tall_tuft", "long_grass", "clover", "daisies"],
            ["buttercups", "heather", "moss", "fern"],
            ["mushroom_ring", "stones", "molehill", "bare_earth"],
            ["lush_patch", "dry_patch", "leaves", "path"],
        ],
        alpha=(195, 245),
    ),
    "trees": Sheet(
        "13_trees_bushes/sheet_trees.png",
        [
            ["pine", "spruce", "young_spruce", "birch"],
            ["oak", "linden", "rowan", "apple"],
            ["willow", "alder", "aspen", "maple"],
            ["juniper", "birches", "hazel", "old_pine"],
        ],
    ),
    "bushes": Sheet(
        "13_trees_bushes/sheet_bushes.png",
        [
            ["lingonberry", "blueberry", "raspberry", "wild_rose"],
            ["elder", "hawthorn", "juniper", "fern"],
            ["heather", "broom", "evergreen", "guelder_rose"],
            ["sapling", "tall_grass", "bracken", "meadowsweet"],
        ],
    ),
}

#: The seamless textures of the ground, relative to SHEETS_DIR, and their
#: names in assets/pictures/ground/.
GROUND = {"grass_lush": "12_grass/grass_lush.png", "grass_dry": "12_grass/grass_dry.png"}

#: The textures of the ground are saved with this many pixels on a side.
GROUND_SIDE = 512

#: The painting of the start screen, relative to SHEETS_DIR.
START = "10_start/start.png"


def painted_box(alpha: np.ndarray) -> Optional[Tuple[int, int, int, int]]:
    """Return the box (left, top, right, bottom) of what is painted, if any."""
    rows = np.flatnonzero((alpha > 0).sum(axis=1) >= MIN_PAINTED)
    cols = np.flatnonzero((alpha > 0).sum(axis=0) >= MIN_PAINTED)
    if rows.size == 0 or cols.size == 0:
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1


def cut(name: str, sheet: Sheet) -> int:
    """Cut the [sheet] into assets/pictures/[name]/."""
    image = np.asarray(Image.open(SHEETS_DIR / sheet.path).convert("RGBA")).copy()
    low, high = sheet.alpha
    stretched = (image[..., 3].astype(float) - low) / (high - low)
    image[..., 3] = (np.clip(stretched, 0.0, 1.0) * 255).astype(np.uint8)

    height, width = image.shape[:2]
    rows = len(sheet.names)
    cols = len(sheet.names[0])
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    for r in range(rows):
        for c in range(cols):
            picture_name = sheet.names[r][c]
            if picture_name == "":
                continue
            left, top = c * width // cols, r * height // rows
            right, bottom = (c + 1) * width // cols, (r + 1) * height // rows
            if picture_name in sheet.textures:
                inset = 12
                cell = image[top + inset : bottom - inset, left + inset : right - inset].copy()
                cell[..., 3] = 255
                picture = Image.fromarray(cell).resize((TEXTURE_SIDE, TEXTURE_SIDE), Image.LANCZOS)
            else:
                box = painted_box(image[top:bottom, left:right, 3])
                if box is None:
                    print(f"The cell {picture_name} of {name} is empty.")
                    return 1
                x0, y0, x1, y1 = box
                picture = Image.fromarray(
                    image[
                        max(0, top + y0 - MARGIN) : min(height, top + y1 + MARGIN),
                        max(0, left + x0 - MARGIN) : min(width, left + x1 + MARGIN),
                    ]
                )
                if max(picture.size) > MAX_SIDE:
                    picture.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
            target = out / f"{picture_name}.png"
            picture.save(target, optimize=True)
            print(f"{target.relative_to(REPO)}: {picture.size[0]} x {picture.size[1]}")
    return 0


def cut_start() -> None:
    """Scale the painting of the start screen to the screen."""
    painting = Image.open(SHEETS_DIR / START).convert("RGB").resize((1920, 1080), Image.LANCZOS)
    target = OUT / "start" / "start.jpg"
    target.parent.mkdir(parents=True, exist_ok=True)
    painting.save(target, quality=88, optimize=True)
    print(f"{target.relative_to(REPO)}: 1920 x 1080")


def cut_ground() -> None:
    """Scale the seamless textures of the ground (they stay seamless)."""
    for name, path in GROUND.items():
        if not (SHEETS_DIR / path).exists():
            print(f"Skipping the ground {name}: {path} is not there yet.")
            continue
        texture = Image.open(SHEETS_DIR / path).convert("RGB")
        texture = texture.resize((GROUND_SIDE, GROUND_SIDE), Image.LANCZOS)
        target = OUT / "ground" / f"{name}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        texture.save(target, optimize=True)
        print(f"{target.relative_to(REPO)}: {GROUND_SIDE} x {GROUND_SIDE}")


def main() -> int:
    wanted = sys.argv[1:] or list(SHEETS) + ["ground", "start"]
    for name in wanted:
        if name == "ground":
            cut_ground()
            continue
        if name in SHEETS and not (SHEETS_DIR / SHEETS[name].path).exists() and not sys.argv[1:]:
            print(f"Skipping the sheet {name}: {SHEETS[name].path} is not there yet.")
            continue
        if name == "start":
            cut_start()
        elif name in SHEETS:
            if cut(name, SHEETS[name]) != 0:
                return 1
        else:
            print(f"Unknown sheet {name!r}; the sheets are: {', '.join(list(SHEETS) + ['ground', 'start'])}")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
