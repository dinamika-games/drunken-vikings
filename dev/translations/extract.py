#!/usr/bin/env python3

"""
Collect the translatable messages of the game into translations/messages.pot,
and update the translations (translations/<language>.po) with them.

The messages come from the GDScripts and from the data in data/:

* the calls ``Grammar.text("...")``, ``Grammar.phrase("...")``,
  ``Grammar.title("...")``, ``ChoicePanel.card("...")``,
  ``TranslationServer.translate("...")`` and ``tr("...")`` with a literal (or
  literals joined with ``+``) as their first argument; a comment line starting
  with ``# TRANSLATORS:`` right above the literal or the call is passed on to
  the translators;
* the constants right below a comment ``# TRANSLATORS[<field>@<kind or
  context>]: <comment>``: the values of the ``"<field>"`` keys in the constant
  (every value, if the field is left out), as messages of that kind (with its
  forms, see scenes/languages/grammar.gd) or with that context;
* the texts of the data (the places, the goods, the farm, how to play, the
  ships and the missions; see DATA below).

A name which a sentence may need in another grammatical form (a place, a
person, a good, a counted thing) also comes as a message with the context of
each form, e.g., "Kråkhamn" with the context "to" (see Grammar.CONTEXTS).

The existing translations are kept. A new message gets an empty translation,
and a message which is not used any more is kept as obsolete. With --check,
nothing is written and the script fails if the files are out of date.
"""

import argparse
import json
import pathlib
import re
import sys
from typing import Dict, List, Optional, Tuple

import polib
import pydantic

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

TRANSLATIONS_DIR = REPO_ROOT / "translations"

SOURCE_LANGUAGE = "en"


class Language(pydantic.BaseModel):
    """A language of the game, as listed in translations/languages.json."""

    code: str
    name: str
    subtitle: str
    prompt: str
    short: Optional[str] = None
    rtl: bool = False


def read_languages() -> List[Language]:
    """Read all the languages of the game, English first."""
    path = TRANSLATIONS_DIR / "languages.json"
    adapter = pydantic.TypeAdapter(List[Language])
    return adapter.validate_json(path.read_text(encoding="utf-8"))


#: The languages besides English, from translations/languages.json, which lists
#: every language of the game. A new language needs only a new entry there; this
#: script then creates its .po file.
LANGUAGES = [language.code for language in read_languages() if language.code != SOURCE_LANGUAGE]

#: The plural forms of the languages, in the order of Grammar.plural_index.
PLURAL_FORMS = {
    "ar": "nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 "
    ": n%100>=11 ? 4 : 5);",
    "fr": "nplurals=2; plural=(n > 1);",
    "hi": "nplurals=2; plural=(n > 1);",
    "ja": "nplurals=1; plural=0;",
    "ko": "nplurals=1; plural=0;",
    "zh": "nplurals=1; plural=0;",
    "ru": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && "
    "(n%100<10 || n%100>=20) ? 1 : 2);",
    "sh": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && "
    "(n%100<10 || n%100>=20) ? 1 : 2);",
}
DEFAULT_PLURAL_FORMS = "nplurals=2; plural=(n != 1);"

#: The forms of the names, by their kind (see Grammar.CONTEXTS), and what each
#: form is, for the translators.
FORMS = {
    "place": ["to", "in", "from"],
    "person": ["acc", "dat"],
    "good": ["acc", "gen"],
    "thing": ["acc"],
}

FORM_COMMENTS = {
    "to": "where to, with the preposition, e.g. 'в Кракхамн', 'u Kråkhamn', 'nach Kråkhamn'",
    "in": "where, with the preposition, e.g. 'в Кракхамне', 'u Kråkhamnu', 'in Kråkhamn'",
    "from": "where from, with the preposition, e.g. 'из Кракхамна', 'iz Kråkhamna'",
    "acc": "the accusative (the direct object), e.g. 'бочку эля', 'bačvu piva'",
    "dat": "the dative, e.g. 'Ульфу', 'Ulfu'",
    "gen": "the genitive (of what), e.g. 'соли', 'soli'",
}

_STRING = r'"((?:[^"\\]|\\.)*)"'
#: A literal in double quotes or (as gdformat may write one with double
#: quotes in it) in single quotes.
_STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'')

#: A call which takes an English message as its first argument.
CALL_RE = re.compile(
    r"(?<![\w.])(?:tr|Grammar\.text|Grammar\.phrase|Grammar\.title|ChoicePanel\.card"
    r"|ChoicePanel\.title_of|ChoicePanel\.detail|TranslationServer\.translate)\("
)

#: The comment for the translators of the messages of some calls: where they
#: show (see tests/godot/test_text_fit.gd, which checks that they fit).
CARD_TITLE = "the title of a card (a button): a word or two, at most two short lines"
CARD_DETAIL = "the second line of a card (a button), under its title: a few words"
ROLES = {
    "ChoicePanel.card(": CARD_TITLE,
    "ChoicePanel.title_of(": CARD_TITLE,
    "ChoicePanel.detail(": CARD_DETAIL,
}

TRANSLATORS_RE = re.compile(r"#\s*TRANSLATORS:\s*(.*)$")

#: A comment above a constant whose texts are messages, see the module doc.
CONSTANT_RE = re.compile(r"^#\s*TRANSLATORS\[([a-z_]*)(?:@([a-z_]+))?\]:\s*(.*)$")

#: (context, message id)
Key = Tuple[str, str]


def _unescape(text: str) -> str:
    return text.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


class Messages:
    """The messages collected so far, in a stable order."""

    def __init__(self) -> None:
        self.entries: Dict[Key, polib.POEntry] = {}

    def add(self, msgid: str, relative: str, comment: Optional[str], context: str = "") -> None:
        """Add the message (or another place where it appears)."""
        if msgid == "":
            return
        key = (context, msgid)
        entry = self.entries.get(key)
        if entry is None:
            entry = polib.POEntry(msgid=msgid, msgstr="")
            if context:
                entry.msgctxt = context
            self.entries[key] = entry
        # NOTE (mristin):
        # We record only the file, not the line, so that the translation files do
        # not change whenever the code moves.
        if (relative, "") not in entry.occurrences:
            entry.occurrences.append((relative, ""))
        if comment and comment not in (entry.comment or ""):
            entry.comment = (entry.comment + "\n" if entry.comment else "") + comment

    def add_name(self, msgid: str, kind: str, relative: str, comment: str) -> None:
        """Add a name and its grammatical forms (see FORMS)."""
        self.add(msgid, relative, comment)
        for context in FORMS[kind]:
            self.add(
                msgid,
                relative,
                f"the {kind} '{msgid}' for {{{kind}@{context}}} in the translations: "
                f"{FORM_COMMENTS[context]}; leave it empty if it is the same as the plain "
                f"translation",
                context,
            )


def _literals(text: str, at: int) -> Optional[Tuple[str, int]]:
    """Read the literal (or the literals joined with "+", maybe in parentheses)
    which starts at ``at``, skipping the spaces and the comments; return it and
    where it starts, or None if there is none."""
    i = at
    start = -1
    parts: List[str] = []
    while i < len(text):
        c = text[i]
        if c in " \t\n(":
            i += 1
        elif c == "#":
            i = text.find("\n", i)
            if i < 0:
                break
        elif c in "\"'":
            match = _STRING_RE.match(text, i)
            if match is None:
                break
            if start < 0:
                start = i
            parts.append(match.group(1) if match.group(1) is not None else match.group(2))
            i = match.end()
            following = re.match(r"\s*\+\s*", text[i:])
            if following is None:
                break
            i += following.end()
        else:
            break
    if not parts:
        return None
    return "".join(_unescape(part) for part in parts), start


def _comment_above(lines: List[str], line: int) -> Optional[str]:
    """The comment ``# TRANSLATORS:`` right above the line (1-based), if any."""
    for previous in reversed(lines[: line - 1]):
        translators = TRANSLATORS_RE.search(previous.strip())
        if translators:
            return translators.group(1)
        if previous.strip() and not previous.strip().startswith("#"):
            return None
    return None


def _constant_block(text: str, at: int) -> str:
    """The text of the constant which starts at the line ``at`` (its brackets)."""
    open_at = min(i for i in (text.find("[", at), text.find("{", at)) if i >= 0)
    depth = 0
    in_string = False
    i = open_at
    while i < len(text):
        c = text[i]
        if in_string:
            if c == "\\":
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c in "[{(":
            depth += 1
        elif c in "]})":
            depth -= 1
            if depth == 0:
                return text[open_at : i + 1]
        i += 1
    return text[open_at:]


def _literal_group(block: str, at: int) -> Tuple[str, int]:
    """Read the literals joined with "+" which start at ``at``; return their text
    and where they end."""
    parts: List[str] = []
    i = at
    while True:
        match = _STRING_RE.match(block, i)
        assert match is not None
        parts.append(match.group(1))
        i = match.end()
        following = re.match(r"\s*\+\s*\"", block[i:])
        if following is None:
            break
        i += following.end() - 1
    return _unescape("".join(parts)), i


def _constant_texts(block: str, field: str) -> List[str]:
    """The texts in the constant: the values of the ``field``, or every value
    (the elements of an array and the values of a dictionary, not its keys)."""
    result: List[str] = []
    key: Optional[str] = None
    after_colon = False
    i = 0
    while i < len(block):
        c = block[i]
        if c == '"':
            value, end = _literal_group(block, i)
            if block[end:].lstrip().startswith(":"):
                key = value
            else:
                owner = key if after_colon else None
                if (field and owner == field) or not field:
                    result.append(value)
                after_colon = False
            i = end
        elif c == ":":
            after_colon = True
            i += 1
        else:
            if not c.isspace():
                after_colon = False
            i += 1
    return result


def collect_scripts(messages: Messages) -> None:
    """Collect the messages of all the GDScripts."""
    for path in sorted((REPO_ROOT / "scenes").rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(REPO_ROOT).as_posix()
        lines = text.splitlines()

        for match in CALL_RE.finditer(text):
            line_start = text.rfind("\n", 0, match.start()) + 1
            if text[line_start : match.start()].lstrip().startswith("#"):
                continue
            found = _literals(text, match.end())
            if found is None:
                continue
            msgid, start = found
            line = text.count("\n", 0, start) + 1
            call_line = text.count("\n", 0, match.start()) + 1
            comment = _comment_above(lines, line) or _comment_above(lines, call_line)
            role = ROLES.get(match.group(0))
            if role is not None:
                comment = role + (f"; {comment}" if comment else "")
            messages.add(msgid, relative, comment)

        for number, line_text in enumerate(lines):
            constant = CONSTANT_RE.match(line_text.strip())
            if constant is None:
                continue
            field, kind_or_context, comment = constant.groups()
            start = sum(len(line) + 1 for line in lines[: number + 1])
            for value in _constant_texts(_constant_block(text, start), field):
                if kind_or_context in FORMS:
                    messages.add_name(value, kind_or_context, relative, comment)
                else:
                    messages.add(value, relative, comment, kind_or_context or "")


# ---------------------------------------------------------------------------
# The data
# ---------------------------------------------------------------------------


class _Data(pydantic.BaseModel):
    model_config = pydantic.ConfigDict(extra="ignore")


class Named(_Data):
    name: str


class World(_Data):
    labels: List[Named]
    places: List[Named]
    start: Named
    goal: Named


class Goods(_Data):
    goods: List[Named]


class Animal(_Data):
    name: str
    counted: str
    plural: str
    young: Optional[str] = None
    young_plural: Optional[str] = None


class Farm(_Data):
    animals: Dict[str, Animal]
    crops: Dict[str, Named]
    plots: List[Named]


class HowToPart(_Data):
    title: str
    text: str


class HowTo(_Data):
    parts: List[HowToPart]


class Shipwright(_Data):
    name: str
    short: str
    yard: str


class Ship(_Data):
    name: str
    about: str


class Ships(_Data):
    shipwright: Shipwright
    ships: List[Ship]


class Person(_Data):
    name: str


class Step(_Data):
    say: Optional[str] = None
    load_say: Optional[str] = None
    says: List[str] = []
    who: Optional[Person] = None
    from_who: Optional[Person] = None
    to_who: Optional[Person] = None


class Item(_Data):
    name: str
    counted: str


class Reward(_Data):
    gift: Optional[str] = None


class Mission(_Data):
    title: str
    giver: Person
    offer: str
    steps: List[Step]
    items: Dict[str, Item] = {}
    reward: Reward
    fact: Optional[str] = None


def _read(model: type, path: pathlib.Path):  # type: ignore[no-untyped-def]
    return model.model_validate_json(path.read_text(encoding="utf-8"))


COUNTED = (
    "{count|...|...} picks the form for the number {count} (one, then the others; "
    "see the Plural-Forms of this file for how many forms your language has), e.g., "
    "'{count|a crate of salt|{count} crates of salt}'"
)


def collect_data(messages: Messages) -> None:
    """Collect the texts of the data."""

    def relative(path: pathlib.Path) -> str:
        return path.relative_to(REPO_ROOT).as_posix()

    path = REPO_ROOT / "data/world/home_lakes.json"
    world: World = _read(World, path)
    for place in world.places + [world.start, world.goal]:
        messages.add_name(place.name, "place", relative(path), "the name of a settlement")
    for label in world.labels:
        messages.add(
            label.name,
            relative(path),
            "a name on the map (of a lake, a sound, an island or a settlement); "
            "keep the Swedish name in the Latin alphabet, or write it in your own",
        )

    path = REPO_ROOT / "data/economy/goods.json"
    goods: Goods = _read(Goods, path)
    for good in goods.goods:
        messages.add_name(
            good.name,
            "good",
            relative(path),
            "a good which the players trade, as it stands in a sentence (lower case), "
            "e.g., 'They pay 5 silver for salt'",
        )

    path = REPO_ROOT / "data/farm/farm.json"
    farm: Farm = _read(Farm, path)
    for animal in farm.animals.values():
        messages.add(animal.name, relative(path), "an animal, under its crate in the boat")
        messages.add_name(animal.counted, "thing", relative(path), f"so many animals; {COUNTED}")
        messages.add(animal.plural, relative(path), "all the animals of a kind, e.g., 'The hens'")
        if animal.young is not None:
            messages.add_name(animal.young, "thing", relative(path), f"so many young; {COUNTED}")
        if animal.young_plural is not None:
            messages.add(animal.young_plural, relative(path), "the young of a kind, e.g., 'no lambs'")
    for crop in farm.crops.values():
        messages.add_name(
            crop.name,
            "thing",
            relative(path),
            "a crop, as it stands in a sentence (lower case); also the title of its card (a button)",
        )
    for plot in farm.plots:
        messages.add_name(
            plot.name,
            "thing",
            relative(path),
            "a plot of land, as it stands in a sentence; also the title of its card (a button)",
        )

    path = REPO_ROOT / "data/how_to/how_to.json"
    how_to: HowTo = _read(HowTo, path)
    for part in how_to.parts:
        messages.add(part.title, relative(path), "the title of a part of How to play, a few words")
        messages.add(part.text, relative(path), "how to play: at most 2 lines on the screen, short sentences")

    path = REPO_ROOT / "data/ships/ships.json"
    ships: Ships = _read(Ships, path)
    messages.add_name(ships.shipwright.name, "person", relative(path), "the name of the shipwright")
    messages.add(
        ships.shipwright.short,
        relative(path),
        "the first name of the shipwright, on the second line of a card (a button)",
    )
    messages.add(ships.shipwright.yard, relative(path), "the title of the shipyard's screen")
    for ship in ships.ships:
        messages.add_name(
            ship.name,
            "thing",
            relative(path),
            "a kind of ship (lower case); also the title of its card (a button)",
        )
        messages.add(ship.about, relative(path), "what the ship is like, one short sentence")

    for path in sorted((REPO_ROOT / "data/missions").glob("*/mission.json")):
        mission: Mission = _read(Mission, path)
        where = relative(path)
        messages.add(
            mission.title,
            where,
            "the title of a task, also on its card (a button): a few words, at most two short lines",
        )
        messages.add_name(mission.giver.name, "person", where, "who gives a task")
        messages.add(mission.offer, where, "what the giver of a task asks, at most 6 lines")
        for step in mission.steps:
            for line in [step.say, step.load_say] + step.says:
                if line is not None:
                    messages.add(line, where, "what a person says, at most 6 lines")
            for who in [step.who, step.from_who, step.to_who]:
                if who is not None:
                    messages.add_name(who.name, "person", where, "who speaks in a task")
        for item in mission.items.values():
            messages.add(item.name, where, "a thing of a task, under its crate: at most 10 letters")
            messages.add_name(item.counted, "thing", where, f"a thing of a task; {COUNTED}")
        if mission.reward.gift is not None:
            messages.add_name(mission.reward.gift, "thing", where, "a gift for a task: 'You get ...'")
        if mission.fact is not None:
            messages.add(mission.fact, where, "a fun fact at the end of a task, 2 short sentences")


# ---------------------------------------------------------------------------
# The files
# ---------------------------------------------------------------------------


def _key(entry: polib.POEntry) -> Key:
    return (entry.msgctxt or "", entry.msgid)


def make_template(messages: Messages) -> polib.POFile:
    """Make the template of all the messages."""
    template = polib.POFile(wrapwidth=100)
    template.metadata = {
        "Project-Id-Version": "Drunken Vikings",
        "MIME-Version": "1.0",
        "Content-Type": "text/plain; charset=UTF-8",
        "Content-Transfer-Encoding": "8bit",
    }
    for entry in messages.entries.values():
        template.append(entry)
    return template


def merge(template: polib.POFile, existing: Optional[polib.POFile], language: str) -> polib.POFile:
    """Make the translation of the template, keeping the existing translations."""
    old: Dict[Key, polib.POEntry] = {}
    if existing is not None:
        old = {_key(entry): entry for entry in existing}

    result = polib.POFile(wrapwidth=100)
    result.metadata = dict(template.metadata)
    result.metadata["Language"] = language
    result.metadata["Plural-Forms"] = PLURAL_FORMS.get(language, DEFAULT_PLURAL_FORMS)
    if existing is not None:
        for name in ("Last-Translator", "Language-Team"):
            if name in existing.metadata:
                result.metadata[name] = existing.metadata[name]

    used = set()
    for entry in template:
        merged = polib.POEntry(
            msgid=entry.msgid,
            msgctxt=entry.msgctxt,
            msgstr="",
            occurrences=list(entry.occurrences),
            comment=entry.comment,
        )
        previous = old.get(_key(entry))
        if previous is not None and not previous.obsolete:
            used.add(_key(entry))
            merged.msgstr = previous.msgstr
            merged.flags = list(previous.flags)
            merged.tcomment = previous.tcomment
        elif previous is not None:
            used.add(_key(entry))
            merged.msgstr = previous.msgstr
            merged.flags = list(previous.flags)
        result.append(merged)

    # NOTE (mristin):
    # We keep the unused translations as obsolete, so that a message which comes
    # back does not have to be translated again.
    for key, previous in old.items():
        if key not in used and previous.msgstr:
            previous.obsolete = True
            result.append(previous)

    return result


def main() -> int:
    """Execute the main routine."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write anything; fail if the translation files are out of date.",
    )
    args = parser.parse_args()

    messages = Messages()
    collect_scripts(messages)
    collect_data(messages)
    template = make_template(messages)

    outputs: List[Tuple[pathlib.Path, str]] = [(TRANSLATIONS_DIR / "messages.pot", str(template))]
    for language in LANGUAGES:
        path = TRANSLATIONS_DIR / f"{language}.po"
        existing = polib.pofile(str(path), wrapwidth=100) if path.exists() else None
        outputs.append((path, str(merge(template, existing, language))))

    stale = [path for path, text in outputs if not path.exists() or path.read_text("utf-8") != text]
    if args.check:
        for path in stale:
            print(
                f"{path.relative_to(REPO_ROOT)} is out of date; run dev/translations/extract.py",
                file=sys.stderr,
            )
        return 1 if stale else 0

    TRANSLATIONS_DIR.mkdir(exist_ok=True)
    for path, text in outputs:
        if path in stale:
            path.write_text(text, encoding="utf-8")
            print(f"Wrote {path.relative_to(REPO_ROOT)}")
    print(f"{len(template)} message(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
