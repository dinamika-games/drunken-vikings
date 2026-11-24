class_name DwellButton
extends Control

## A big card of the screens, which a hand clicks by holding its cursor (see
## [HandCursor]) still over it for [constant DWELL_SECONDS]: a ring fills
## around the card meanwhile. The mouse clicks it, too. A hovered card grows a
## little.
##
## The card shows its [member card]: "title", "detail" (a second line, e.g., a
## price), "color" (of the crate on it, optional), "mood" (-1 cheap, 1 dear, 0
## as usual; optional), "stars" (0 to 3, the stars a task earned; optional) and
## "enabled" (default true).

signal pressed

## The hand holds still this long to click.
const DWELL_SECONDS := 2.0

## The hovered card grows by this many pixels on each side.
const _GROW := 6.0

const _PAPER := Color("fffaf0")
const _PAPER_OFF := Color("d8d0c0")
const _INK := Color("2a1e14")
const _WOOD := Color("6a4320")
const _GOLD := Color("f2c14e")
const _GREEN := Color("4a8a3a")
const _RED := Color("b8332a")
const _GREY := Color("8a8070")

## What the card shows (see the class description).
var card := {}:
    set(value):
        card = value
        queue_redraw()

## How far the hand has held still, in [0, 1].
var progress := 0.0

var _mouse_inside := false

## Whether the card was drawn painted (its frame is thicker).
var _painted := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    mouse_entered.connect(func() -> void: _mouse_inside = true)
    mouse_exited.connect(func() -> void: _mouse_inside = false)


func enabled() -> bool:
    return bool(card.get("enabled", true))


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        accept_event()
        press()


func _process(delta: float) -> void:
    if is_visible_in_tree() and enabled() and _hand_inside():
        progress += delta / DWELL_SECONDS
        if progress >= 1.0:
            progress = 0.0
            press()
    else:
        progress = 0.0
    queue_redraw()


## Click the card.
func press() -> void:
    if not enabled():
        return
    progress = 0.0
    pressed.emit()


## Whether a cursor or the mouse is over the card.
func hovered() -> bool:
    return _hand_inside() or (_mouse_inside and not HandCursor.by_hand)


func _hand_inside() -> bool:
    var rect := get_global_rect()
    for point in HandCursor.points():
        if rect.has_point(point):
            return true
    return false


func _draw() -> void:
    var font := ThemeDB.fallback_font
    var rect := Rect2(Vector2.ZERO, size)
    var on := enabled()
    var lit := hovered() and on
    if lit:
        rect = rect.grow(_GROW)
    _painted = _draw_painted_card(rect, lit, on)
    if not _painted:
        if lit:
            draw_rect(rect.grow(6.0), _GOLD)
        draw_rect(rect, _PAPER if on else _PAPER_OFF)
        draw_rect(rect, _WOOD, false, 3.0)
    var ink := _INK if on else _GREY

    var top := rect.position.y + 50.0
    var painted: Texture2D = null
    if card.has("picture"):
        painted = Pictures.of(card["picture"][0], card["picture"][1])
    if painted != null:
        var size := Pictures.size_of(painted, 80.0)
        var at := rect.position + Vector2(rect.size.x / 2.0, 56.0)
        draw_texture_rect(
            painted, Rect2(at - size / 2.0, size), false, Color.WHITE if on else Color(1, 1, 1, 0.4)
        )
        top = rect.position.y + 124.0
    elif card.has("stars") and Pictures.of("ui", "star") != null:
        # The stars a task earned: three, the earned ones golden.
        for k in range(3):
            var star := Pictures.of("ui", "star" if k < int(card["stars"]) else "star_empty")
            var at := rect.position + Vector2(rect.size.x / 2.0 + (k - 1) * 62.0, 56.0)
            Pictures.draw(self, star, at, 56.0 if k == 1 else 46.0)
        top = rect.position.y + 124.0
    elif card.has("color"):
        var crate := Rect2(rect.position + Vector2(rect.size.x / 2.0 - 34.0, 18.0), Vector2(68, 52))
        var color: Color = card["color"]
        draw_rect(crate, color if on else Color(color, 0.4))
        draw_rect(crate, _WOOD, false, 3.0)
        draw_line(crate.position, crate.end, Color(_WOOD, 0.5), 2.0)
        draw_line(
            Vector2(crate.end.x, crate.position.y),
            Vector2(crate.position.x, crate.end.y),
            Color(_WOOD, 0.5),
            2.0
        )
        top = rect.position.y + 100.0
    var mood := int(card.get("mood", 0))
    if mood != 0:
        var at := rect.position + Vector2(rect.size.x - 30.0, 40.0)
        var up := mood > 0
        var color := _GREEN if up else _RED
        var tip := at + Vector2(0, -16 if up else 16)
        draw_colored_polygon(
            PackedVector2Array(
                [tip, at + Vector2(-12, 4 if up else -4), at + Vector2(12, 4 if up else -4)]
            ),
            color
        )
        draw_line(at, at + Vector2(0, 16 if up else -16), color, 6.0)

    var lines := ChoicePanel.wrap_text(font, str(card.get("title", "")), rect.size.x - 20.0, 26)
    for i in range(lines.size()):
        draw_string(
            font,
            Vector2(rect.position.x, top + i * 30.0),
            lines[i],
            HORIZONTAL_ALIGNMENT_CENTER,
            rect.size.x,
            26,
            ink
        )
    var detail := str(card.get("detail", ""))
    if detail != "":
        draw_string(
            font,
            Vector2(rect.position.x, rect.end.y - (30.0 if _painted else 18.0)),
            detail,
            HORIZONTAL_ALIGNMENT_CENTER,
            rect.size.x,
            24,
            _WOOD
        )

    # NOTE (mristin):
    # With the painted rope ring, the cursor shows how long the hand held
    # still (see HandCursor).
    if progress > 0.0 and Pictures.of("ui", "rope_ring") == null:
        # NOTE (mristin):
        # The ring runs around the frame of the card, clockwise from the top
        # left, so that it fits a card of any shape.
        var outer := rect.grow(10.0)
        var reached := 2.0 * (outer.size.x + outer.size.y) * progress
        var corners := [
            outer.position,
            Vector2(outer.end.x, outer.position.y),
            outer.end,
            Vector2(outer.position.x, outer.end.y),
            outer.position
        ]
        for i in range(4):
            var from: Vector2 = corners[i]
            var to: Vector2 = corners[i + 1]
            var side := from.distance_to(to)
            if reached <= 0.0:
                break
            draw_line(from, from.lerp(to, minf(1.0, reached / side)), _RED, 7.0)
            reached -= side


## The painted card (see Pictures.draw_frame): golden while a hand is on it,
## grey when it can not be chosen; return whether the pictures are there.
func _draw_painted_card(rect: Rect2, lit: bool, on: bool) -> bool:
    if lit:
        return Pictures.draw_frame(self, "card_chosen", rect.grow(14.0), 44.0)
    return Pictures.draw_frame(self, "card" if on else "card_off", rect, 30.0)
