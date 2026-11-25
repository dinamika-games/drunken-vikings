class_name DwellButton
extends Control

## A big card of the screens, which a hand clicks by holding its cursor (see
## [HandCursor]) still over it for [constant DWELL_SECONDS]: a ring fills
## around the card meanwhile. The mouse clicks it, too. A hovered card grows a
## little.
##
## The card shows its [member card]: "title", "detail" (a second line, e.g., a
## price), "picture" (the [sheet, name] of a painted picture (see Pictures),
## or a Texture2D; optional), "color" (of the crate on it, optional), "mood" (-1 cheap, 1 dear, 0
## as usual; optional), "stars" (0 to 3, the stars a task earned; optional) and
## "enabled" (default true).

signal pressed

## The hand holds still this long to click.
const DWELL_SECONDS := 2.0

## The hovered card grows by this many pixels on each side.
const _GROW := 6.0

## On the painted card (also the golden one of the hovered card), a nail
## sits in each corner, its middle this far from the sides and from the top
## (and the bottom); a line of text which runs past the nails keeps this much
## clear of them (the nail itself included).
const NAIL := Vector2(34.0, 33.0)
const NAIL_CLEAR := 20.0

## The sizes of the text: the title, and the detail (each as large as fits
## clear of the nails, down to the smallest).
const TITLE_SIZES := [26, 24, 22, 20]
const DETAIL_SIZES := [24, 22, 20, 18, 16, 14]

## Where the first line of the title goes when nothing is drawn above it,
## from the top of the card, and how far the lines of the title are apart.
const TITLE_TOP := 50.0
const TITLE_LINE := 30.0

## The detail lies this far above the bottom of the painted card (of the
## card drawn in code).
const DETAIL_ABOVE := 30.0
const DETAIL_ABOVE_PLAIN := 18.0

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
    Audio.play("click")
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

    # NOTE (mristin):
    # The card grows while a hand is on it, but its nails stay where they are
    # (see _draw_painted_card), so what is on the card stays, too.
    rect = Rect2(Vector2.ZERO, size)
    var top := rect.position.y + TITLE_TOP
    var painted: Texture2D = null
    if card.get("picture") is Texture2D:
        painted = card["picture"]
    elif card.has("picture"):
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

    var title := str(card.get("title", ""))
    var title_font := title_size(font, title, rect.size, top, _painted)
    var lines := wrap_title(font, title, rect.size, top, _painted, title_font)
    for i in range(lines.size()):
        draw_string(
            font,
            Vector2(rect.position.x, top + i * TITLE_LINE),
            lines[i],
            HORIZONTAL_ALIGNMENT_CENTER,
            rect.size.x,
            title_font,
            ink
        )
    var detail := str(card.get("detail", ""))
    if detail != "":
        draw_string(
            font,
            Vector2(rect.position.x, detail_baseline(rect.size, _painted)),
            detail,
            HORIZONTAL_ALIGNMENT_CENTER,
            rect.size.x,
            detail_size(font, detail, rect.size, _painted),
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
## How wide a line of text may be on a card of the [param card] size, at
## the [param baseline] in the [param font_size]: as wide as the card allows,
## or, where the line runs past the nails of the [param painted] card,
## between them.
static func line_width(
    font: Font, card: Vector2, baseline: float, font_size: int, painted: bool
) -> float:
    if painted:
        var top := baseline - font.get_ascent(font_size)
        var bottom := baseline + font.get_descent(font_size)
        for nail in [NAIL.y, card.y - NAIL.y]:
            if top < nail + NAIL_CLEAR and bottom > nail - NAIL_CLEAR:
                return card.x - 2.0 * (NAIL.x + NAIL_CLEAR)
    return card.x - 20.0


## The lines of the [param title] on a card of the [param card] size, the
## first at the [param baseline]: each as wide as its row allows (see
## [method line_width]).
static func wrap_title(
    font: Font,
    title: String,
    card: Vector2,
    baseline: float,
    painted: bool,
    font_size: int = TITLE_SIZES[0]
) -> Array[String]:
    var lines: Array[String] = []
    var current := ""
    for word in title.split(" ", false):
        var candidate := word if current == "" else current + " " + word
        var at := baseline + lines.size() * TITLE_LINE
        var width := line_width(font, card, at, font_size, painted)
        if (
            font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width
            and current != ""
        ):
            lines.append(current)
            current = word
        else:
            current = candidate
    if current != "":
        lines.append(current)
    return lines


## The size of the [param title] on a card of the [param card] size, its
## first line at the [param baseline]: as large as lets every line fit its
## row (a word alone may be too wide for a row by the nails).
static func title_size(
    font: Font, title: String, card: Vector2, baseline: float, painted: bool
) -> int:
    for font_size in TITLE_SIZES:
        var lines := wrap_title(font, title, card, baseline, painted, font_size)
        var fits := true
        for i in range(lines.size()):
            var width := line_width(font, card, baseline + i * TITLE_LINE, font_size, painted)
            if font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
                fits = false
                break
        if fits:
            return font_size
    return TITLE_SIZES[-1]


## Where the detail lies on a card of the [param card] size.
static func detail_baseline(card: Vector2, painted: bool) -> float:
    return card.y - (DETAIL_ABOVE if painted else DETAIL_ABOVE_PLAIN)


## The size of the text of the [param detail], as large as fits its row.
static func detail_size(font: Font, detail: String, card: Vector2, painted: bool) -> int:
    var baseline := detail_baseline(card, painted)
    for font_size in DETAIL_SIZES:
        var width := line_width(font, card, baseline, font_size, painted)
        if font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
            return font_size
    return DETAIL_SIZES[-1]


func _draw_painted_card(rect: Rect2, lit: bool, on: bool) -> bool:
    if lit:
        return Pictures.draw_frame(self, "card_chosen", rect.grow(14.0), 44.0)
    return Pictures.draw_frame(self, "card" if on else "card_off", rect, 30.0)
