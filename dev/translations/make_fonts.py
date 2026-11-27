#!/usr/bin/env python3

"""
Make the fonts which the font of the game falls back on (see
scenes/languages/languages.gd) in assets/fonts/:

* Noto Naskh Arabic and Noto Sans Devanagari, whole (they are small); the
  Arabic with a smaller descent (see ARABIC_DESCENT);
* Noto Sans CJK in its Chinese (simplified), Japanese and Korean variants,
  cut to the characters of the translations (translations/*.po and
  translations/languages.json), since the whole fonts take some 20 MB each.

Run it after the translations change (the test of the texts fails on a
character which the fonts lack, see tests/godot/test_text_fit.gd). The fonts
come from the Noto fonts of the system (on Debian and Ubuntu, the packages
fonts-noto-core and fonts-noto-cjk), or from --source.
"""

import argparse
import pathlib
import shutil
import sys
from typing import Set

import polib
from fontTools import subset
from fontTools.ttLib import TTCollection, TTFont

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

FONTS_DIR = REPO_ROOT / "assets/fonts"

#: The whole fonts: the file in the system's fonts and in assets/fonts/.
WHOLE = {
    "truetype/noto/NotoNaskhArabic-Regular.ttf": "NotoNaskhArabic-Regular.ttf",
    "truetype/noto/NotoSansDevanagari-Regular.ttf": "NotoSansDevanagari-Regular.ttf",
}

#: The descent of Noto Naskh Arabic (0.63 of its size) makes room for the
#: vowel marks stacked below the letters, which the game does not write; the
#: letters themselves end much higher. The game lays its lines out by the
#: descent of the font, so we give the font this share of its size instead.
ARABIC = "NotoNaskhArabic-Regular.ttf"
ARABIC_DESCENT = 0.4

#: The variants of Noto Sans CJK: the name of the font in the collection, and
#: the file in assets/fonts/.
CJK = {
    "Noto Sans CJK SC": "NotoSansSC-Regular.otf",
    "Noto Sans CJK JP": "NotoSansJP-Regular.otf",
    "Noto Sans CJK KR": "NotoSansKR-Regular.otf",
}
CJK_COLLECTION = "opentype/noto/NotoSansCJK-Regular.ttc"


def _characters() -> Set[str]:
    """All the characters of the translations and of the list of languages."""
    result: Set[str] = set()
    for path in sorted((REPO_ROOT / "translations").glob("*.po")):
        for entry in polib.pofile(str(path)):
            result.update(entry.msgstr)
    result.update(
        (REPO_ROOT / "translations/languages.json").read_text(encoding="utf-8")
    )
    # NOTE (mristin):
    # The marks of the stars of the tasks, and the digits and the Latin letters,
    # so that the numbers and the Swedish names look the same in every language.
    result.update("★☆→·0123456789")
    result.update(chr(code) for code in range(0x20, 0x7F))
    return result


def main() -> int:
    """Execute the main routine."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        default=pathlib.Path("/usr/share/fonts"),
        help="Where the Noto fonts of the system are.",
    )
    args = parser.parse_args()

    FONTS_DIR.mkdir(parents=True, exist_ok=True)
    for source, target in WHOLE.items():
        shutil.copyfile(args.source / source, FONTS_DIR / target)
        print(f"Copied {target}")

    arabic = TTFont(str(FONTS_DIR / ARABIC))
    descent = round(ARABIC_DESCENT * arabic["head"].unitsPerEm)
    arabic["hhea"].descent = -descent
    arabic["OS/2"].sTypoDescender = -descent
    arabic["OS/2"].usWinDescent = descent
    arabic.save(str(FONTS_DIR / ARABIC))
    print(f"Set the descent of {ARABIC} to {ARABIC_DESCENT} of its size")

    characters = "".join(sorted(_characters()))
    collection_path = str(args.source / CJK_COLLECTION)
    # NOTE (mristin):
    # The fonts of a collection share their tables, so we read each one alone
    # before we cut it.
    for number in range(len(TTCollection(collection_path).fonts)):
        font = TTFont(collection_path, fontNumber=number)
        family = font["name"].getDebugName(1)
        if family not in CJK:
            continue
        cmap = font.getBestCmap()
        wanted = [c for c in characters if ord(c) in cmap]
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.name_languages = ["*"]
        options.notdef_outline = True
        options.drop_tables = []
        subsetter = subset.Subsetter(options)
        subsetter.populate(text="".join(wanted))
        subsetter.subset(font)
        target = FONTS_DIR / CJK[family]
        font.save(str(target))
        print(f"Wrote {target.name} with {len(wanted)} characters")
    return 0


if __name__ == "__main__":
    sys.exit(main())
