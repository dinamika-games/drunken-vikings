extends Node

## Know the languages of the game, choose one, and remember it (the autoload
## Languages).
##
## The languages are listed in `res://translations/languages.json`, each with
## its code, its name in itself, an optional second line (e.g., the script),
## "Choose your language" in itself, optionally a short name (for the card
## "Language", if the name is long) and whether it is written from right to
## left ("rtl"). That list is the only place to add a language: the
## translations (`res://translations/<code>.po`) are registered from it here,
## the language select shows it (see LanguageSelect), and the tools in
## dev/translations/ create and check the .po files from it.
##
## The language which the players chose is saved in `user://settings.cfg` and
## used from then on. Start the game with `-- --lang=<code>` to override it.
## The tests start in English (see [method _ready]).
##
## The game always shows the whole translation of the chosen language. The
## fuzzy mark of a message in the .po files only tells the translators that a
## native speaker has not reviewed it yet (see CONTRIBUTING.md); since Godot
## would skip the fuzzy messages and show English for them, we load the
## translations with the fuzzy marks removed (see [method _load_translation]).
##
## The font of the game (Godot's own, for the Latin, Greek and Cyrillic
## letters) falls back on the Noto fonts in `res://assets/fonts/` for Arabic,
## Devanagari (Hindi) and the Chinese, Japanese and Korean characters (cut to
## the characters of the translations, see dev/translations/make_fonts.py).
## Only the language of the game brings its font: the fonts of the other
## scripts are taller and would change the lines of every text (and Chinese,
## Japanese and Korean draw their shared characters each a little
## differently); the language select brings them all (see [method
## all_scripts]).

const SOURCE_LANGUAGE := "en"

const _LIST_PATH := "res://translations/languages.json"
const _TRANSLATIONS_DIR := "user://translations"

const FONTS_DIR := "res://assets/fonts"

## The fonts which the font of the game falls back on, by the languages
## which need them.
const _FALLBACKS := {
    "ar": "NotoNaskhArabic-Regular.ttf",
    "hi": "NotoSansDevanagari-Regular.ttf",
    "zh": "NotoSansSC-Regular.otf",
    "ja": "NotoSansJP-Regular.otf",
    "ko": "NotoSansKR-Regular.otf",
}

## How much bolder the fallback fonts are drawn, to match the semi-bold font
## of the game.
const _EMBOLDEN := 0.5

## The languages in the order of the list, each a dictionary with "code",
## "name", "subtitle", "prompt" and maybe "rtl".
var languages: Array[Dictionary] = []

## Whether the language was chosen before (or given on the command line).
var has_chosen := false

## Where the chosen language is kept for the next start (the end-to-end tests
## keep it in a file of their own, so that they leave the player's alone).
var settings_path := "user://settings.cfg"

var _fallbacks := {}
var _font: FontVariation


func _ready() -> void:
    var listing: JSON = load(_LIST_PATH)
    for entry in listing.data:
        languages.append(entry)

    for code in codes():
        if code == SOURCE_LANGUAGE:
            continue
        var translation := _load_translation(code)
        if translation != null:
            TranslationServer.add_translation(translation)

    _set_up_font()

    # NOTE (mristin):
    # The tests (run with --script) start in English, whatever the players
    # chose, unless they ask for a language with --lang.
    var settings := ConfigFile.new()
    if not "--script" in OS.get_cmdline_args() and settings.load(settings_path) == OK:
        var saved: String = settings.get_value("general", "language", "")
        if saved in codes():
            _switch(saved)
            has_chosen = true

    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--lang="):
            var code := arg.get_slice("=", 1)
            if code in codes():
                _switch(code)
                has_chosen = true
            else:
                push_warning("Unknown language %s; we know %s." % [code, codes()])

    if not has_chosen:
        _switch(SOURCE_LANGUAGE)


## The codes of all the languages, e.g., ["en", "ar", "da"].
func codes() -> Array[String]:
    var result: Array[String] = []
    for language in languages:
        result.append(language["code"])
    return result


## The code of the language of the game now, e.g., "de".
func current() -> String:
    var locale := TranslationServer.get_locale()
    for code in codes():
        if locale == code or locale.begins_with(code + "_"):
            return code
    return SOURCE_LANGUAGE


## Whether the language of the game is written from right to left.
func is_rtl() -> bool:
    for language in languages:
        if language["code"] == current():
            return bool(language.get("rtl", false))
    return false


## Switch to the language and remember it for the next start.
func choose(code: String) -> void:
    if code not in codes():
        push_warning("Unknown language %s; we know %s." % [code, codes()])
        return
    _switch(code)
    has_chosen = true

    var settings := ConfigFile.new()
    settings.load(settings_path)
    settings.set_value("general", "language", code)
    settings.save(settings_path)


## Switch to the language for now (e.g., for a test), without remembering it.
func use(code: String) -> void:
    if code in codes():
        _switch(code)


func _switch(code: String) -> void:
    TranslationServer.set_locale(code)
    use_fonts(code)


## Make the font of the game fall back on the Noto fonts (see the class
## description).
func _set_up_font() -> void:
    for key in _FALLBACKS:
        var path := "%s/%s" % [FONTS_DIR, _FALLBACKS[key]]
        if not ResourceLoader.exists(path):
            continue
        var font := FontVariation.new()
        font.base_font = load(path)
        font.variation_embolden = _EMBOLDEN
        _fallbacks[key] = font
    _font = FontVariation.new()
    _font.base_font = ThemeDB.fallback_font
    ThemeDB.fallback_font = _font
    use_fonts(SOURCE_LANGUAGE)


## Let the font of the game fall back on the font of the language [param
## code] only, if it needs one (e.g., for a test of the card of a language).
func use_fonts(code: String) -> void:
    if _font == null:
        return
    var fonts: Array[Font] = []
    if _fallbacks.has(code):
        fonts.append(_fallbacks[code])
    _font.fallbacks = fonts


## Let the font of the game show the letters of all the languages (for the
## language select), or again only those of the language of the game.
func all_scripts(on: bool) -> void:
    if _font == null:
        return
    if not on:
        use_fonts(current())
        return
    var fonts: Array[Font] = []
    if _fallbacks.has(current()):
        fonts.append(_fallbacks[current()])
    for key in _FALLBACKS:
        if _fallbacks.has(key) and not _fallbacks[key] in fonts:
            fonts.append(_fallbacks[key])
    _font.fallbacks = fonts


## Load the translation of the language with the fuzzy marks removed, so that
## every translated message shows (Godot skips the fuzzy ones); null if there
## is none.
func _load_translation(code: String) -> Translation:
    var source := "res://translations/%s.po" % code
    if not FileAccess.file_exists(source):
        # NOTE (mristin):
        # Without the text of the .po file (e.g., in an export which left it
        # out), the imported translation, without its fuzzy messages.
        if ResourceLoader.exists(source):
            return load(source)
        push_warning("The translation of %s is missing; run dev/translations/extract.py." % code)
        return null
    var kept := PackedStringArray()
    for line in FileAccess.get_file_as_string(source).split("\n"):
        if line.begins_with("#,") and "fuzzy" in line:
            var flags := line.substr(2).replace("fuzzy", "").replace(",", " ").strip_edges()
            if flags != "":
                kept.append("#, " + ", ".join(flags.split(" ", false)))
            continue
        kept.append(line)
    # NOTE (mristin):
    # Every running game writes a file of its own (several may start at once,
    # e.g., in the tests), loads it, and removes it again.
    DirAccess.make_dir_recursive_absolute(_TRANSLATIONS_DIR)
    var target := "%s/%s_%d.po" % [_TRANSLATIONS_DIR, code, OS.get_process_id()]
    var file := FileAccess.open(target, FileAccess.WRITE)
    if file == null:
        return load(source)
    file.store_string("\n".join(kept))
    file.close()
    var translation: Translation = ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE)
    DirAccess.remove_absolute(target)
    return translation
