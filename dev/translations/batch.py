#!/usr/bin/env python3

"""
Read and fill the translation of one language in batches, as JSON: for the
translators who work outside a PO editor (e.g., with a script).

    venv/bin/python dev/translations/batch.py dump de [--start 0] [--count 100]
        [--missing] [--context] [--grep TEXT]

prints the messages (all of them, only the untranslated ones with --missing,
only those with a context with --context, or only those whose English or
translation contains TEXT) as a JSON list of {"index", "context", "english",
"comment", "translation", "fuzzy"}, and

    venv/bin/python dev/translations/batch.py apply de translations.json

sets the translations of a JSON list of {"index", "english", "translation"}
(the index and the English as dumped, to make sure they match), marks them as
fuzzy (to be reviewed by a native speaker in the game, see CONTRIBUTING.md),
and checks the language (see check.py). Only translations/<language>.po is
written, so several translators may work at once, each on their language.
"""

import argparse
import json
import pathlib
import sys
from typing import List, Optional

import polib
import pydantic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import check  # noqa: E402  # pylint: disable=wrong-import-position
import extract  # noqa: E402  # pylint: disable=wrong-import-position


class Translated(pydantic.BaseModel):
    """A translation to set, as in the JSON of ``apply``."""

    index: int
    english: str
    translation: str


def _path(language: str) -> pathlib.Path:
    if language not in extract.LANGUAGES:
        raise SystemExit(f"Unknown language {language}; we know {extract.LANGUAGES}.")
    return extract.TRANSLATIONS_DIR / f"{language}.po"


def _entries(po: polib.POFile) -> List[polib.POEntry]:
    return [entry for entry in po if not entry.obsolete]


def dump(language: str, start: int, count: Optional[int], missing: bool, context: bool, grep: str) -> None:
    """Print the messages as JSON."""
    po = polib.pofile(str(_path(language)), wrapwidth=100)
    result = []
    for index, entry in enumerate(_entries(po)):
        if index < start:
            continue
        if missing and entry.msgstr:
            continue
        if context and not entry.msgctxt:
            continue
        if grep and grep not in entry.msgid and grep not in entry.msgstr:
            continue
        result.append(
            {
                "index": index,
                "context": entry.msgctxt or "",
                "english": entry.msgid,
                "comment": entry.comment or "",
                "translation": entry.msgstr,
                "fuzzy": "fuzzy" in entry.flags,
            }
        )
        if count is not None and len(result) >= count:
            break
    print(json.dumps(result, ensure_ascii=False, indent=1))


def apply(language: str, source: pathlib.Path) -> int:
    """Set the translations of the JSON file; return the exit code."""
    path = _path(language)
    po = polib.pofile(str(path), wrapwidth=100)
    entries = _entries(po)
    adapter = pydantic.TypeAdapter(List[Translated])
    translations = adapter.validate_json(source.read_text(encoding="utf-8"))
    problems: List[str] = []
    for translated in translations:
        if not 0 <= translated.index < len(entries):
            problems.append(f"There is no message {translated.index}.")
            continue
        entry = entries[translated.index]
        if entry.msgid != translated.english:
            problems.append(f"The message {translated.index} is {entry.msgid!r}, not {translated.english!r}.")
            continue
        entry.msgstr = translated.translation
        if translated.translation and "fuzzy" not in entry.flags:
            entry.flags.append("fuzzy")
        if not translated.translation and "fuzzy" in entry.flags:
            entry.flags.remove("fuzzy")
    for problem in problems:
        print(problem, file=sys.stderr)
    po.save(str(path))
    print(f"Set {len(translations) - len(problems)} translation(s) of {language}.")
    errors = check.check(language, False)
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if problems or errors else 0


def main() -> int:
    """Execute the main routine."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    dumping = commands.add_parser("dump", help="Print the messages as JSON.")
    dumping.add_argument("language")
    dumping.add_argument("--start", type=int, default=0)
    dumping.add_argument("--count", type=int, default=None)
    dumping.add_argument("--missing", action="store_true")
    dumping.add_argument("--context", action="store_true")
    dumping.add_argument("--grep", default="")
    applying = commands.add_parser("apply", help="Set the translations of a JSON file.")
    applying.add_argument("language")
    applying.add_argument("source", type=pathlib.Path)
    args = parser.parse_args()

    if args.command == "dump":
        dump(args.language, args.start, args.count, args.missing, args.context, args.grep)
        return 0
    return apply(args.language, args.source)


if __name__ == "__main__":
    sys.exit(main())
