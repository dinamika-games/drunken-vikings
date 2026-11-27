extends SceneTree

## Check that the texts of the cards (the buttons) fit their cards in every
## language (see translations/ and Languages), as the end-to-end test checks
## the cards it sees (see end2end/contracts.gd, whose checks we reuse): the
## title fits the width of the card, clear of the nails of its frame, above
## the detail and below the picture; the detail fits its line; and the fonts
## show every letter of every translation.
##
## Which messages are on the cards, we know from their comments in
## translations/messages.pot (see dev/translations/extract.py): the titles
## (ChoicePanel.card, and the names of the crops, the plots, the ships and
## the tasks), the details (ChoicePanel.detail), the colours of the looks, and
## the names of the languages. A placeholder takes every value it may take
## (every good, every animal, numbers from 1 to the most the game shows, so
## that every plural form shows up), and a choice for the rowers its longest
## form. A card which shows a picture has its title below the picture; we
## lay the title out with a detail under it, unless the card never has one.
##
## $GODOT --headless --path . --script tests/godot/test_text_fit.gd -- --no-camera [--lang=de]

const Contracts := preload("res://tests/godot/end2end/contracts.gd")
const WorldScript := preload("res://scenes/world/world.gd")

const TEMPLATE := "res://translations/messages.pot"
const LANGUAGES_PATH := "res://translations/languages.json"

## The titles of the cards which show a picture besides those with an icon
## (see world.gd, CARD_ICONS): the cards of the goods, the animals, the
## crops and the ships, the colours of the looks, and these.
const WITH_PICTURE := [
    "How to play",
    "Ready!",
    "Language",
    "Girl",
    "Boy",
    "Sell {good} ({count})",
    "Buy {good}",
    "Load {good}",
    "Buy {animal}",
    "Sell {animal}",
]

## The cards which never have a detail.
const NO_DETAIL := [
    "Row on", "Hooray!", "Go on", "Not now", "Harvest", "Load from the store", "Keep"
]

## The numbers a placeholder may take, by its name, the most the game shows
## last: the silver of a rich voyage, the crates of the biggest hold, ...
const NUMBERS := {
    "silver": [1, 2, 3, 5, 11, 21, 102, 220, 450, 1500],
    "price": [1, 2, 5, 11, 45, 80, 220, 450, 800],
    "count": [1, 2, 3, 5, 11, 21, 44],
    # NOTE: The crates of the cards are the holds of the ships, 4 at least.
    "crates": [4, 5, 8, 11, 16, 21, 44],
    "room": [1, 2, 3, 5, 11, 21, 44],
    "days": [1, 2, 3, 5, 11],
    "day": [1, 2, 3, 5, 11, 21, 102, 365],
}

var _failures := 0
var _checked := 0

## The values of the placeholders which are not numbers, by their names.
var _values := {}


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _run() -> void:
    var languages: Node = root.get_node("/root/Languages")
    var codes: Array[String] = languages.codes()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--lang="):
            codes = [arg.get_slice("=", 1)]
    var messages := _read_template()
    _values = _placeholder_values()
    Grammar.longest_crew_forms = true
    for code in codes:
        languages.use(code)
        var before := _failures
        _check_language(code, messages, languages)
        print("%s: %d card texts, %d failures" % [code, _checked, _failures - before])
        _checked = 0
    languages.use("en")
    Grammar.longest_crew_forms = false
    print("PASS test_text_fit" if _failures == 0 else "FAIL test_text_fit (%d)" % _failures)
    quit(0 if _failures == 0 else 1)


func _check_language(code: String, messages: Array, languages: Node) -> void:
    for message: Dictionary in messages:
        var comment: String = message["comment"]
        var context: String = message["context"]
        var msgid: String = message["msgid"]
        var title := (
            comment.begins_with("the title of a card")
            or "title of its card" in comment
            or "also on its card" in comment
            or context in ["skin", "hair", "clothes"]
        )
        var detail := "second line of a card" in comment
        if context != "" and not context in ["skin", "hair", "clothes"]:
            continue
        if title:
            for shown in _texts(msgid, context, true):
                _check_card(code, msgid, {"title": shown, "detail": _detail_for(msgid)}, true)
        elif detail:
            for shown in _texts(msgid, context, false):
                _check_card(code, msgid, {"title": "X", "detail": shown}, false)
        _check_letters(code, msgid, context)
    # NOTE: The language select shows the letters of all the languages; each
    # card those of its own (whose fonts lay it out).
    for language in languages.languages:
        languages.use_fonts(language["code"])
        _check_card(
            code,
            language["name"],
            {"title": language["name"], "detail": language["subtitle"]},
            true
        )
        _check_letters_of(code, language["name"] + language["subtitle"] + language["prompt"])
    languages.use_fonts(code)


## The detail which the card of the title [param msgid] is laid out with: none,
## if it never has one, else a short one.
func _detail_for(msgid: String) -> String:
    return "" if msgid in NO_DETAIL else "1"


## Check a card of the [param card] dictionary; [param whole] tells whether to
## check the title (else only the detail).
func _check_card(code: String, msgid: String, card: Dictionary, whole: bool) -> void:
    _checked += 1
    if whole and (WorldScript.CARD_ICONS.has(msgid) or msgid in WITH_PICTURE or _pictured(msgid)):
        card["picture"] = ["icons", "sell"]
    var contracts := Contracts.new()
    contracts._check_card(ThemeDB.fallback_font, card, "%s, %s" % [code, msgid])
    for violation in contracts.violations():
        if not whole and not "detail" in violation:
            continue
        _check(false, violation)


## Whether the card of the title [param msgid] shows a painted thing: a
## crop, a ship or a colour of the looks.
func _pictured(msgid: String) -> bool:
    return msgid in _values["crop"] or msgid in _values["ship"] or msgid in _values["colour"]


## The texts which the message [param msgid] may show: translated, its
## placeholders filled with every value they may take (see [member _values]
## and [constant NUMBERS]); a [param title] with a capital letter.
func _texts(msgid: String, context: String, title: bool) -> Array[String]:
    var keys: Array[String] = []
    var placeholder := RegEx.create_from_string("\\{([a-z_]+)")
    for found in placeholder.search_all(msgid):
        var key := found.get_string(1)
        if not key in keys:
            keys.append(key)
    var combinations: Array = [{}]
    for key in keys:
        var options: Array = NUMBERS.get(key, _values.get(key, [1, 2, 5, 22]))
        var more: Array = []
        for combination: Dictionary in combinations:
            for option in options:
                var next := combination.duplicate()
                next[key] = option
                more.append(next)
        combinations = more
    var result: Array[String] = []
    for args: Dictionary in combinations:
        var shown: String
        if context != "":
            shown = Grammar.fill(msgid, context)
        else:
            shown = Grammar.text(msgid, args)
        if title:
            shown = Grammar.upper_first(shown)
        if not shown in result:
            result.append(shown)
    return result


## The values of the placeholders of the cards which are not numbers.
func _placeholder_values() -> Dictionary:
    var goods: Array = []
    for good in _json("res://data/economy/goods.json")["goods"]:
        goods.append(good["name"])
    var farm: Dictionary = _json("res://data/farm/farm.json")
    var animals: Array = []
    for kind in farm["animals"].values():
        animals.append(Grammar.phrase(kind["counted"], {"count": 1}))
    var crops: Array = []
    for crop in farm["crops"].values():
        crops.append(crop["name"])
    var ships: Array = []
    for ship in _json("res://data/ships/ships.json")["ships"]:
        ships.append(ship["name"])
    var colours: Array = []
    for palette in [Looks.SKINS, Looks.HAIRS, Looks.CLOTHES]:
        for entry in palette:
            colours.append(entry["name"])
    # NOTE: The prices of the ships, in every plural form (e.g., 220 in Arabic).
    var details: Array = [Grammar.phrase("your ship"), Grammar.phrase("yours")]
    for price in [80, 220, 450, 800]:
        details.append(Grammar.phrase("{silver} silver", {"silver": price}))
    return {
        "good": goods,
        "animal": animals,
        "crop": crops,
        "ship": ships,
        "colour": colours,
        "journey": [Grammar.raw("2026-11-26 14:23")],
        # NOTE: Phrases, so that they are translated into the language checked.
        "detail": details,
    }


static func _json(path: String) -> Variant:
    return JSON.parse_string(FileAccess.get_file_as_string(path))


## Check that the fonts show every letter of the translation of the message.
func _check_letters(code: String, msgid: String, context: String) -> void:
    var shown := String(TranslationServer.translate(msgid, context))
    if shown != msgid:
        _check_letters_of(code, shown)


func _check_letters_of(code: String, text: String) -> void:
    var font: Font = ThemeDB.fallback_font
    var fonts: Array[Font] = [font]
    fonts.append_array(font.fallbacks)
    if font is FontVariation:
        fonts.append((font as FontVariation).base_font)
    for i in range(text.length()):
        var c := text.unicode_at(i)
        if c < 0x20:
            continue
        var shown := false
        for each in fonts:
            var base: Font = each
            if base is FontVariation:
                base = (base as FontVariation).base_font
            if base != null and base.has_char(c):
                shown = true
                break
        _check(
            shown,
            (
                (
                    "%s: the fonts show the letter %s (U+%04X) of '%s' (run "
                    + "dev/translations/make_fonts.py)"
                )
                % [code, char(c), c, text]
            )
        )


## The messages of the template: Array of {"msgid", "context", "comment"}.
func _read_template() -> Array:
    var result: Array = []
    var entry := {"msgid": "", "context": "", "comment": ""}
    var field := ""
    for line in FileAccess.get_file_as_string(TEMPLATE).split("\n"):
        if line.strip_edges() == "":
            if entry["msgid"] != "":
                result.append(entry)
            entry = {"msgid": "", "context": "", "comment": ""}
            field = ""
        elif line.begins_with("#. "):
            entry["comment"] += ("\n" if entry["comment"] != "" else "") + line.substr(3)
        elif line.begins_with("msgctxt "):
            field = "context"
            entry["context"] = _unquote(line.substr(8))
        elif line.begins_with("msgid "):
            field = "msgid"
            entry["msgid"] = _unquote(line.substr(6))
        elif line.begins_with("msgstr "):
            field = ""
        elif line.begins_with('"') and field != "":
            entry[field] += _unquote(line)
    if entry["msgid"] != "":
        result.append(entry)
    return result


static func _unquote(quoted: String) -> String:
    return quoted.strip_edges().trim_prefix('"').trim_suffix('"').c_unescape()
