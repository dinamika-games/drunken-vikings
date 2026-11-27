class_name Grammar
extends RefCounted

## Translate the texts of the game and fill their placeholders with the right
## grammatical forms (see CONTRIBUTING.md, "Translations").
##
## Every text which a player sees is a whole sentence in English, the message
## ID, with named placeholders: [code]Grammar.text("Row to {place}.",
## {"place": "Kråkhamn"})[/code]. The sentence is translated as a whole, so
## every language orders its words its own way, and then the placeholders are
## filled:
##
## * a String value is an English message ID itself (e.g., the name of a
##   place or a good), translated here;
## * a number is written as it is;
## * [method phrase] is a phrase with placeholders of its own (e.g., "{count}
##   crates of {good}"), translated and filled here;
## * [method raw] is a text which is not translated (e.g., the name of a
##   journey);
## * an Array is a list of values, joined by the separator of the language.
##
## A translation may ask for more than the English:
##
## * a form of an inserted word: [code]{place@to}[/code] takes the translation
##   of the place's name with the context "to" (e.g., "в Кракхамн", "u
##   Kråkhamn"; see [constant CONTEXTS]), and the plain translation if the
##   form is not given;
## * a word which agrees with a number: [code]{count|ящик|ящика|ящиков}[/code]
##   picks the form for the number of [code]{count}[/code] by the plural rule
##   of the language (see [method plural_index]); a form may hold
##   placeholders itself ([code]{count|a crate|{count} crates}[/code]);
## * the words which depend on who is addressed: [code]{crew|ты пришёл|ты
##   пришла|вы пришли|вы пришли}[/code] picks the form for one boy, one girl,
##   two rowers with a boy among them, and two girls (see [method address]).
##
## A sentence which begins with a placeholder begins with a capital letter.

## The forms which the translations may ask for, by the kind of the inserted
## word (see dev/translations/extract.py, which collects them as messages with
## that context).
const CONTEXTS := {
    "place": ["to", "in", "from"],
    "person": ["acc", "dat"],
    "good": ["acc", "gen"],
    "thing": ["acc"],
}

## The genders of the addressed rowers ("girl" or "boy"), for the tests;
## empty to take them from GameState.
static var genders: Array[String] = []

## Pick the longest form of every [code]{crew|...}[/code] choice instead, so
## that a test can check that every form fits.
static var longest_crew_forms := false

static var _crew_choice := RegEx.create_from_string("\\{crew\\|([^{}]*)\\}")
static var _key := RegEx.create_from_string("^([a-z_]+)")


## Translate the [param msgid] and fill its placeholders with the [param args].
static func text(msgid: String, args := {}) -> String:
    var translated := String(TranslationServer.translate(msgid))
    var result := format(translated, args)
    if translated.begins_with("{"):
        result = upper_first(result)
    return result


## A phrase to insert into a sentence: the [param msgid], translated and filled
## with its own [param args] (e.g., [code]Grammar.phrase("{count|a crate of
## {good}|{count} crates of {good}}", {"count": 3, "good": "salt"})[/code]).
static func phrase(msgid: String, args := {}) -> Dictionary:
    return {"phrase": msgid, "args": args}


## A text to insert as it is, without translating it.
static func raw(value: String) -> Dictionary:
    return {"raw": value}


## Translate the [param msgid] alone, e.g., the name of a good on a card,
## with a capital letter.
static func title(msgid: String) -> String:
    return upper_first(address(String(TranslationServer.translate(msgid))))


## The [param value] with its first letter in capitals (in Turkish, the
## capital of "i" is "İ").
static func upper_first(value: String) -> String:
    if value == "":
        return value
    var first := value.left(1)
    if first == "i" and TranslationServer.get_locale().get_slice("_", 0) == "tr":
        return "İ" + value.substr(1)
    return first.to_upper() + value.substr(1)


## Fill the placeholders of the translated [param template].
static func format(template: String, args: Dictionary) -> String:
    template = address(template)
    var result := ""
    var at := 0
    while at < template.length():
        var open := template.find("{", at)
        if open < 0:
            result += template.substr(at)
            break
        var close := _closing(template, open)
        if close < 0:
            result += template.substr(at)
            break
        result += template.substr(at, open - at)
        var inner := template.substr(open + 1, close - open - 1)
        result += _placeholder(inner, args, template.substr(open, close - open + 1))
        at = close + 1
    return result


## The index of the brace which closes the one at [param open], or -1.
static func _closing(template: String, open: int) -> int:
    var depth := 0
    for i in range(open, template.length()):
        var c := template[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


## Split the [param inner] of a choice at its top-level bars.
static func _forms(inner: String) -> PackedStringArray:
    var forms := PackedStringArray()
    var depth := 0
    var start := 0
    for i in range(inner.length()):
        var c := inner[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "|" and depth == 0:
            forms.append(inner.substr(start, i - start))
            start = i + 1
    forms.append(inner.substr(start))
    return forms


static func _placeholder(inner: String, args: Dictionary, whole: String) -> String:
    var found := _key.search(inner)
    if found == null:
        return whole
    var key := found.get_string(1)
    if not args.has(key):
        return whole
    var how := inner.substr(key.length())
    if how.begins_with("|"):
        var forms := _forms(how.substr(1))
        var form := forms[mini(plural_index(int(args[key])), forms.size() - 1)]
        return format(form, args)
    if how == "" or how.begins_with("@"):
        return fill(args[key], how.substr(1))
    return whole


## The text of a [param value] (see the class description), in the form of
## the [param context] if the translation gives it.
static func fill(value: Variant, context := "") -> String:
    if value is Array:
        var parts: Array[String] = []
        for each in value:
            parts.append(fill(each, context))
        # TRANSLATORS: the separator of the items of a list, e.g., "3 hens, 2 sheep"
        return String(TranslationServer.translate(", ")).join(parts)
    if value is Dictionary:
        if value.has("raw"):
            return str(value["raw"])
        if value.has("phrase"):
            return format(_translate(str(value["phrase"]), context), value.get("args", {}))
        return str(value)
    if value is float:
        return decimal(value)
    if not value is String and not value is StringName:
        return str(value)
    if String(value) == "":
        return ""
    return _translate(String(value), context)


## Translate the [param msgid] in the form of the [param context], or plainly
## if the translation gives no such form; with the forms for the rowers who
## are addressed (a name or a gift may need them, too).
static func _translate(msgid: String, context: String) -> String:
    if context != "":
        var form := String(TranslationServer.translate(msgid, context))
        if form != msgid:
            return address(form)
    return address(String(TranslationServer.translate(msgid)))


## A number with one decimal, with the decimal separator of the language.
static func decimal(value: float) -> String:
    var plain := "%.1f" % value
    # TRANSLATORS: the decimal separator, e.g., "," in German (1,5)
    var separator := String(TranslationServer.translate("."))
    return plain.replace(".", separator)


## Replace every [code]{crew|...}[/code] choice of a translated text with the
## form for the rowers who are addressed.
static func address(template: String) -> String:
    if not "{crew|" in template:
        return template
    var result := ""
    var at := 0
    for match in _crew_choice.search_all(template):
        result += template.substr(at, match.get_start() - at)
        at = match.get_end()
        result += _crew_form(match.get_string(1).split("|"))
    return result + template.substr(at)


static func _crew_form(forms: PackedStringArray) -> String:
    if longest_crew_forms:
        var longest := ""
        for form in forms:
            if form.length() > longest.length():
                longest = form
        return longest
    var index := crew_index()
    if index == 3 and forms.size() < 4:
        index = 2
    if index == 2 and forms.size() < 3:
        index = 0
    return forms[mini(index, forms.size() - 1)]


## Which form of a [code]{crew|...}[/code] choice the rowers take: 0 for one
## boy, 1 for one girl, 2 for two rowers with a boy among them, 3 for two girls.
static func crew_index() -> int:
    var addressed := _addressed_genders()
    if addressed.size() == 1:
        return 1 if addressed[0] == "girl" else 0
    return 2 if "boy" in addressed else 3


## The genders of the rowers of the journey (see GameState.looks).
static func _addressed_genders() -> Array[String]:
    if not genders.is_empty():
        return genders.duplicate()
    var result: Array[String] = []
    var tree := Engine.get_main_loop() as SceneTree
    var state: Node = tree.root.get_node_or_null("/root/GameState") if tree != null else null
    if state == null:
        result.append("girl")
        return result
    for player in range(int(state.players)):
        result.append(str(state.look(player).get("figure", "girl")))
    return result


## Which form of a word goes with the [param count] in the current language,
## in the order of the forms of its "Plural-Forms" (see the .po files):
##
## * English and most languages: 0 for one, 1 for the others;
## * French and Hindi: 0 for zero and one, 1 for the others;
## * Russian and Bosnian, Croatian and Serbian: 0 for one (21, 31, ...), 1
##   for a few (2 to 4, 22 to 24, ...), 2 for many (5 to 20, 25, ...);
## * Arabic: 0 for zero, 1 for one, 2 for two, 3 for a few (3 to 10, 103
##   to 110, ...), 4 for many (11 to 99, 111 to 199, ...), 5 for the others
##   (100, 101, 102, ...);
## * Chinese, Japanese and Korean have one form.
static func plural_index(count: int) -> int:
    var language := TranslationServer.get_locale().get_slice("_", 0)
    var n := absi(count)
    match language:
        "zh", "ja", "ko":
            return 0
        "fr", "hi":
            return 0 if n <= 1 else 1
        "ru", "sh", "hr", "sr", "bs", "uk":
            var last := n % 10
            var last_two := n % 100
            if last == 1 and last_two != 11:
                return 0
            if last >= 2 and last <= 4 and (last_two < 12 or last_two > 14):
                return 1
            return 2
        "ar":
            if n == 0:
                return 0
            if n == 1:
                return 1
            if n == 2:
                return 2
            if n % 100 >= 3 and n % 100 <= 10:
                return 3
            if n % 100 >= 11:
                return 4
            return 5
    return 0 if n == 1 else 1
