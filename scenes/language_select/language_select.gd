class_name LanguageSelect
extends Control

## Let the players choose the language of the game: the very first screen
## (see start.gd), and later the card "Language" of the journeys.
##
## Each language is a card (a DwellButton) with its name in itself, so that
## everybody finds their own without reading the others. The cards come from
## the list of the languages (see the Languages autoload), so a new language
## needs no change here: up to [constant COLUMNS] cards in a row, and more
## languages make more rows. "Choose your language" cycles through all the
## languages above the cards, and shows the language of the card pointed at.
##
## As on every screen of choices (see ChoicePanel), the players point at a
## card with a raised hand and hold it still to choose; the mouse clicks the
## cards, too. The choice is remembered for the next start.

signal chosen

const COLUMNS := 6

## The area of the cards, and the gap between them.
const CARDS_AREA := Rect2(60, 230, 1800, 760)
const GAP := 24.0

## Show each translation of "Choose your language" this long, in seconds.
const PROMPT_SECONDS := 2.2

const _PAPER := Color("f1e6cc")
const _GOLD := Color("f2c14e")
const _INK := Color("2a1e14")

var _service: Node
var _languages: Node
var _buttons: Array[DwellButton] = []
var _cursor: HandCursor
var _backdrop := ScreenBackdrop.new()
var _time := 0.0
var _done := false


func _init(service: Node = null) -> void:
    _service = service
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _backdrop.show_behind_parent = true
    _backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_backdrop)


func _ready() -> void:
    _languages = get_node_or_null("/root/Languages")
    if _languages != null:
        _languages.all_scripts(true)
    var count := _count()
    for i in range(count):
        var language := _language(i)
        var button := DwellButton.new()
        button.card = {
            "id": language["code"], "title": language["name"], "detail": language["subtitle"]
        }
        var rect := card_rect(i, count)
        button.position = rect.position
        button.size = rect.size
        button.pressed.connect(_choose.bind(i))
        add_child(button)
        _buttons.append(button)
    _cursor = HandCursor.new()
    add_child(_cursor)
    _backdrop.cursor = _cursor
    if _service != null:
        _service.SetHandTracking(true)


func _exit_tree() -> void:
    if _languages != null:
        _languages.all_scripts(false)
    if _service != null:
        _service.SetHandTracking(false)


func _count() -> int:
    return _languages.languages.size() if _languages != null else 0


func _language(index: int) -> Dictionary:
    return _languages.languages[index]


## Where the card of the language [param index] of [param count] lies: the
## cards fill the rows from the left, at most [constant COLUMNS] in a row, and
## a shorter last row is centered.
static func card_rect(index: int, count: int) -> Rect2:
    var columns := mini(COLUMNS, count)
    var rows := ceili(float(count) / columns)
    var card := DwellButton.SIZE
    var row := index / columns
    var in_row := mini(columns, count - row * columns)
    var row_width := in_row * card.x + (in_row - 1) * GAP
    var left := CARDS_AREA.position.x + (CARDS_AREA.size.x - row_width) * 0.5
    var total_height := rows * card.y + (rows - 1) * GAP
    var top := CARDS_AREA.position.y + (CARDS_AREA.size.y - total_height) * 0.5
    var column := index % columns
    return Rect2(Vector2(left + column * (card.x + GAP), top + row * (card.y + GAP)), card)


func _choose(index: int) -> void:
    if _done or index < 0 or index >= _count():
        return
    _done = true
    _languages.choose(_language(index)["code"])
    _languages.all_scripts(true)
    chosen.emit()


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


func _draw() -> void:
    _backdrop.dim = ChoicePanel.DIM
    var font := ThemeDB.fallback_font
    if _count() == 0:
        return
    # NOTE (mristin):
    # "Choose your language" in every language, one after the other, fading
    # from one to the next; while a card is pointed at, in its language.
    var index := -1
    for i in range(_buttons.size()):
        if _buttons[i].hovered():
            index = i
    var alpha := 1.0
    if index < 0:
        var phase := _time / PROMPT_SECONDS
        index = int(phase) % _count()
        var t := fmod(phase, 1.0)
        alpha = clampf(minf(t, 1.0 - t) * 6.0, 0.0, 1.0)
    var prompt: String = _language(index)["prompt"]
    var at := Vector2(0, 150)
    draw_string_outline(
        font, at, prompt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 64, 10, Color(_INK, alpha)
    )
    draw_string(font, at, prompt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 64, Color(_GOLD, alpha))
