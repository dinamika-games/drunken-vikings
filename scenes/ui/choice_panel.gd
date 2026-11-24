class_name ChoicePanel
extends Control

## A calm screen with a few big choices: a title, who speaks (a face), what
## they say, and a row of cards ([DwellButton]s). The players point at a card
## with a raised hand and hold it still to choose (see [HandCursor]); behind
## the screen, they see themselves dimly, mirrored, so that their hand lies
## under the cursor. The hand detector runs only while the screen shows (see
## VisionService.SetHandTracking).
##
## Each card is a Dictionary: "title", "detail" (a second line, e.g., a
## price), "color" (of the crate on it, optional), "mood" (-1 cheap, 1 dear, 0
## as usual; optional) and "enabled" (default true).
##
## For the developers only, [code]-- --dev-keys[/code] lets the arrows move a
## highlight and Space choose, to try the screens without the camera.

signal chosen(index: int)

## How much the screen darkens what lies behind it, by default.
const DIM := 0.55

const _PAPER := Color("f1e6cc")
const _INK := Color("2a1e14")
const _WOOD := Color("6a4320")
const _GREY := Color("8a8070")

## The sizes of the text on the board, the usual first (see [method
## fit_text]), and how far down the board the lines may go, in pixels.
const TEXT_SIZES := [28, 26, 24, 22]
const TEXT_HEIGHT := 180.0

const _CARD := Vector2(250, 190)
const _GAP := 34.0

var title := ""
var text := ""

## How much the screen darkens what lies behind it.
var dim := DIM

## The face of who speaks: {"hair": Color, "braids": bool, "picture": the
## name of the painted face (see Pictures), if any} or empty.
var face := {}

var cards: Array = []

## The highlighted card, for the developers' keys.
var highlight := 0

## A hint under the cards.
var hint := "Raise your hand to a card and hold it there to choose."

var _service: Node
var _buttons: Array[DwellButton] = []
var _cursor: HandCursor
var _dev_keys := false
var _keys_down := {}


func _init(service: Node = null) -> void:
    _service = service
    _dev_keys = "--dev-keys" in OS.get_cmdline_user_args()
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
    _cursor = HandCursor.new()
    add_child(_cursor)


## Show the [param new_cards].
func show_cards(new_title: String, new_text: String, new_cards: Array, new_face := {}) -> void:
    title = new_title
    text = new_text
    cards = new_cards
    face = new_face
    highlight = clampi(highlight, 0, maxi(0, cards.size() - 1))
    for button in _buttons:
        button.queue_free()
    _buttons.clear()
    var row := cards.size() * _CARD.x + (cards.size() - 1) * _GAP
    var x := (size.x - row) / 2.0
    for i in range(cards.size()):
        var button := DwellButton.new()
        button.card = cards[i]
        button.position = Vector2(x, size.y - _CARD.y - 110.0)
        button.size = _CARD
        button.pressed.connect(_on_pressed.bind(i))
        add_child(button)
        _buttons.append(button)
        x += _CARD.x + _GAP
    # NOTE (mristin):
    # The cursors stay above the cards.
    move_child(_cursor, get_child_count() - 1)
    visible = true
    if _service != null:
        _service.SetHandTracking(true)
    queue_redraw()


func close() -> void:
    visible = false
    for button in _buttons:
        button.queue_free()
    _buttons.clear()
    if _service != null:
        _service.SetHandTracking(false)


func _on_pressed(index: int) -> void:
    if index >= 0 and index < cards.size() and bool(cards[index].get("enabled", true)):
        chosen.emit(index)


## Choose the card as the players would (for the tests and the autopilot).
func choose(index: int) -> void:
    highlight = index
    _on_pressed(index)


func _process(_delta: float) -> void:
    if not visible:
        return
    if _dev_keys:
        for pair in [[KEY_LEFT, -1], [KEY_RIGHT, 1], [KEY_SPACE, 0]]:
            var down := Input.is_physical_key_pressed(pair[0])
            if down and not _keys_down.get(pair[0], false):
                if pair[1] == 0:
                    choose(highlight)
                else:
                    highlight = clampi(highlight + pair[1], 0, maxi(0, cards.size() - 1))
            _keys_down[pair[0]] = down
    queue_redraw()


func _draw() -> void:
    if not visible:
        return
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.1, dim))
    if _cursor != null:
        _cursor.draw_mirror(self, size)

    var font := ThemeDB.fallback_font
    var width := 1100.0
    var box := Rect2(Vector2((size.x - width) / 2.0, 60.0), Vector2(width, 300.0))
    if not Pictures.draw_frame(self, "board", box.grow(14.0), 44.0):
        draw_rect(box.grow(10.0), _WOOD)
        draw_rect(box, Color(_PAPER, 0.95))
    var left := box.position.x + 40.0
    if not face.is_empty():
        _draw_face(box.position + Vector2(90, 110), 60.0)
        left += 140.0
    draw_string(
        font, Vector2(left, box.position.y + 60.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, _WOOD
    )
    var fitted := fit_text(font, text, box.end.x - left - 40.0)
    var lines: Array[String] = fitted["lines"]
    var font_size: int = fitted["size"]
    for i in range(lines.size()):
        draw_string(
            font,
            Vector2(left, box.position.y + 110.0 + i * (font_size + 8.0)),
            lines[i],
            HORIZONTAL_ALIGNMENT_LEFT,
            -1,
            font_size,
            _INK
        )
    draw_string(
        font, Vector2(0, size.y - 40.0), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, _PAPER
    )
    if _dev_keys and highlight < _buttons.size():
        var rect := _buttons[highlight].get_rect().grow(14.0)
        draw_rect(rect, Color("5ec8f2"), false, 4.0)


## The face of who speaks to the players: painted, or drawn simply.
func _draw_face(center: Vector2, radius: float) -> void:
    var painted := Pictures.of("faces", str(face.get("picture", "")))
    if painted != null:
        var size := Pictures.size_of(painted, radius * 2.4)
        var frame := Rect2(center - size / 2.0, size)
        draw_rect(frame.grow(6.0), _WOOD)
        draw_rect(frame, Color("e8d8b0"))
        draw_texture_rect(painted, frame, false)
        return
    var hair: Color = face.get("hair", Color("8a5a2b"))
    var skin: Color = face.get("skin", Color("f0c8a0"))
    draw_circle(center + Vector2(0, radius * 0.15), radius * 1.05, hair)
    draw_circle(center, radius * 0.8, skin)
    draw_circle(center + Vector2(-radius * 0.28, -radius * 0.05), radius * 0.09, _INK)
    draw_circle(center + Vector2(radius * 0.28, -radius * 0.05), radius * 0.09, _INK)
    draw_arc(center + Vector2(0, radius * 0.18), radius * 0.3, 0.2, PI - 0.2, 12, _INK, 3.0)
    draw_circle(
        center + Vector2(-radius * 0.5, radius * 0.2), radius * 0.12, Color(1, 0.5, 0.5, 0.4)
    )
    draw_circle(
        center + Vector2(radius * 0.5, radius * 0.2), radius * 0.12, Color(1, 0.5, 0.5, 0.4)
    )
    if face.get("braids", false):
        for sign in [-1.0, 1.0]:
            for k in range(4):
                draw_circle(
                    center + Vector2(sign * radius * 0.95, radius * (0.2 + k * 0.3)),
                    radius * 0.15,
                    hair
                )


## Fit the [param text] into the [param width] of the board, in at most the
## lines which the board has room for: at the usual size of the text, or a
## little smaller for a long text; return {"lines", "size"} (the lines which
## fit, all of them unless the text is too long even at the smallest size).
static func fit_text(font: Font, text: String, width: float) -> Dictionary:
    var lines: Array[String] = []
    for font_size in TEXT_SIZES:
        lines = wrap_text(font, text, width, font_size)
        var room := int(TEXT_HEIGHT / (font_size + 8.0)) + 1
        if lines.size() <= room or font_size == TEXT_SIZES[-1]:
            return {"lines": lines.slice(0, room), "size": font_size, "all": lines.size() <= room}
    return {"lines": lines, "size": TEXT_SIZES[0], "all": true}


## Break the [param line] into lines which fit the [param width].
static func wrap_text(font: Font, line: String, width: float, font_size: int) -> Array[String]:
    var result: Array[String] = []
    var current := ""
    for word in line.split(" ", false):
        var candidate := word if current == "" else current + " " + word
        if (
            font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width
            and current != ""
        ):
            result.append(current)
            current = word
        else:
            current = candidate
    if current != "":
        result.append(current)
    return result
