#!/usr/bin/env python3

"""
Check the translations in translations/<language>.po.

Report per language how many messages are translated, how many are still to
be reviewed (fuzzy) and how many are missing; list them with --verbose.

Fail on errors which would break the game (see scenes/languages/grammar.gd):

* a translation which drops, adds or misspells a placeholder (``{place}``),
  or asks for a form which the placeholder does not have (``{place@at}``),
* a choice by a number (``{count|crate|crates}``) of a placeholder which the
  English does not have, or with more forms than the language has,
* a choice for the addressed rowers (``{crew|...}``) with fewer than two or
  more than four forms,
* unbalanced braces.

(Whether the texts fit and the fonts show them, tests/godot/test_text_fit.gd
checks.)

With --language, only the given languages are checked.
"""

import argparse
import pathlib
import re
import sys
from typing import List, Optional, Set, Tuple

import polib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import extract  # noqa: E402  # pylint: disable=wrong-import-position

REPO_ROOT = extract.REPO_ROOT

PLURAL_COUNT_RE = re.compile(r"nplurals=(\d+)")
KEY_RE = re.compile(r"^([a-z_]+)(.*)$", re.DOTALL)

#: The forms which a placeholder may ask for: those of the kinds of names (see
#: extract.FORMS).
KNOWN_FORMS = {form for forms in extract.FORMS.values() for form in forms}


def _where(entry: polib.POEntry) -> str:
    if entry.occurrences:
        path, line = entry.occurrences[0]
        return f"{path}:{line}" if line else path
    return "?"


def _closing(text: str, open_at: int) -> int:
    depth = 0
    for i in range(open_at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _split_forms(inner: str) -> List[str]:
    forms: List[str] = []
    depth = 0
    start = 0
    for i, c in enumerate(inner):
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "|" and depth == 0:
            forms.append(inner[start:i])
            start = i + 1
    forms.append(inner[start:])
    return forms


#: A placeholder as found in a text: (its key, the form it asks for or "", the
#: forms of its choice or None).
Placeholder = Tuple[str, str, Optional[List[str]]]


def placeholders(text: str, errors: List[str], where: str) -> List[Placeholder]:
    """Find the placeholders of the text, also those within the forms of a
    choice."""
    result: List[Placeholder] = []
    i = 0
    while i < len(text):
        if text[i] == "}":
            errors.append(f"{where}: a closing brace without an opening one: {text!r}")
            return result
        if text[i] != "{":
            i += 1
            continue
        close = _closing(text, i)
        if close < 0:
            errors.append(f"{where}: an opening brace without a closing one: {text!r}")
            return result
        inner = text[i + 1 : close]
        match = KEY_RE.match(inner)
        if match is None:
            errors.append(f"{where}: a brace without a placeholder: {inner!r}")
        else:
            key, how = match.groups()
            if how.startswith("|"):
                forms = _split_forms(how[1:])
                result.append((key, "", forms))
                for form in forms:
                    result.extend(placeholders(form, errors, where))
            elif how.startswith("@"):
                result.append((key, how[1:], None))
            elif how == "":
                result.append((key, "", None))
            else:
                errors.append(f"{where}: a misspelled placeholder: {{{inner}}}")
        i = close + 1
    return result


def check_entry(entry: polib.POEntry, plurals: int, language: str) -> List[str]:
    """Check the translation of one message."""
    errors: List[str] = []
    where = f"{language}: {_where(entry)}: {entry.msgid!r}"
    english = placeholders(entry.msgid, errors, where + " (the English)")
    translated = placeholders(entry.msgstr, errors, where)

    expected: Set[str] = {key for key, _, forms in english if forms is None}
    numbers: Set[str] = {key for key, _, forms in english if forms is not None}
    found: Set[str] = set()
    for key, form, forms in translated:
        if key == "crew":
            if forms is None or not 2 <= len(forms) <= 4:
                count = 0 if forms is None else len(forms)
                errors.append(
                    f"{where}: the choice {{crew|...}} has {count} form(s), but needs 2 to 4 "
                    "(one boy, one girl, two rowers, two girls)"
                )
            continue
        if forms is not None:
            if key not in expected and key not in numbers:
                errors.append(f"{where}: a choice by {{{key}}}, which the English does not have")
            if len(forms) > plurals:
                errors.append(
                    f"{where}: the choice by {{{key}}} has {len(forms)} forms, but the "
                    f"language has only {plurals}"
                )
            continue
        if form and form not in KNOWN_FORMS:
            errors.append(f"{where}: the placeholder {{{key}@{form}}} asks for an unknown form")
        found.add(key)
    missing = expected - found
    if missing:
        errors.append(f"{where}: the translation lacks {sorted(missing)}: {entry.msgstr!r}")
    extra = found - expected - numbers
    if extra:
        errors.append(f"{where}: the translation has unknown {sorted(extra)}: {entry.msgstr!r}")
    return errors


def check(language: str, verbose: bool) -> List[str]:
    """Check one language and return the errors."""
    path = extract.TRANSLATIONS_DIR / f"{language}.po"
    if not path.exists():
        return [f"{path.relative_to(REPO_ROOT)} is missing; run dev/translations/extract.py"]

    po = polib.pofile(str(path))
    plural_match = PLURAL_COUNT_RE.search(po.metadata.get("Plural-Forms", ""))
    plurals = int(plural_match.group(1)) if plural_match else 2
    errors: List[str] = []
    missing: List[polib.POEntry] = []
    fuzzy: List[polib.POEntry] = []
    done = 0

    for entry in po:
        if entry.obsolete:
            continue
        if not entry.msgstr:
            if not entry.msgctxt or entry.msgctxt not in KNOWN_FORMS:
                missing.append(entry)
            continue
        if "fuzzy" in entry.flags:
            fuzzy.append(entry)
        else:
            done += 1
        errors.extend(check_entry(entry, plurals, language))

    total = done + len(fuzzy) + len(missing)
    print(
        f"{language}: {done}/{total} translated and reviewed, "
        f"{len(fuzzy)} to review (fuzzy), {len(missing)} missing"
    )
    if verbose:
        for title, entries in (("to review", fuzzy), ("missing", missing)):
            for entry in entries:
                context = f" ({entry.msgctxt})" if entry.msgctxt else ""
                print(f"  {title}: {_where(entry)}: {entry.msgid!r}{context}")

    return errors


def main() -> int:
    """Execute the main routine."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="List the open messages.")
    parser.add_argument("--language", nargs="*", help="Check only these languages, e.g., de fr.")
    args = parser.parse_args()

    errors: List[str] = []
    for language in args.language or extract.LANGUAGES:
        errors.extend(check(language, args.verbose))

    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
