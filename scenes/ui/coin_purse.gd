class_name CoinPurse
extends RefCounted

## The silver of the players as a little display: a stack of painted coins
## (the more silver, the taller) and the number beside it, big, on a wooden
## board; for the children who can not read "silver" yet.

const _WOOD := Color("6a4320")
const _WOOD_LIGHT := Color("8a5a2b")
const _INK := Color(0.1, 0.07, 0.03, 0.9)
const _GOLD := Color("f2c14e")

## One more coin on the stack for every this much silver, up to MAX_STACK.
const PER_COIN := 10
const MAX_STACK := 6


## Draw the purse with [param count] coins on [param canvas], its top left
## at [param at]; [param pop] (from 1 down to 0) makes the number jump after
## coins came in. The board grows with the number (thousands fit).
static func draw(canvas: CanvasItem, at: Vector2, count: int, pop := 0.0) -> void:
    var font := ThemeDB.fallback_font
    var text := str(count)
    var font_size := 46
    var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var board := Rect2(at, Vector2(96.0 + text_width + 26.0, 76.0))
    if not Pictures.draw_frame(canvas, "plaque", board.grow(6.0), 40.0):
        canvas.draw_rect(board.grow(4.0), _INK)
        canvas.draw_rect(board, _WOOD)
        canvas.draw_rect(board.grow(-5.0), _WOOD_LIGHT)

    var coin := Pictures.of("treats", "coin")
    if coin == null:
        coin = Pictures.of("goods", "coin")
    var stack := clampi(1 + count / PER_COIN, 1, MAX_STACK)
    # NOTE (mristin):
    # The stack is centred on the board, however tall it is.
    var base := at + Vector2(48, 38.0 + (stack - 1) * 3.0)
    for i in range(stack):
        # NOTE (mristin):
        # The coins lie on each other a little askew, the top one whole.
        var spot := base + Vector2(sin(i * 2.1) * 3.0, -i * 6.0)
        if coin != null and i == stack - 1:
            Pictures.draw(canvas, coin, spot, 52.0)
        else:
            canvas.draw_set_transform(spot, 0.0, Vector2(1.0, 0.45))
            canvas.draw_circle(Vector2.ZERO, 22.0, Color("8a8a96"))
            canvas.draw_circle(Vector2.ZERO, 19.0, Color("c8c8d4"))
            canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    var grow := 1.0 + 0.35 * clampf(pop, 0.0, 1.0)
    var ascent := font.get_ascent(font_size)
    var text_at := at + Vector2(96.0, 38.0 + ascent * 0.5 - 4.0)
    canvas.draw_set_transform(text_at, 0.0, Vector2(grow, grow))
    canvas.draw_string_outline(
        font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, _INK
    )
    canvas.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _GOLD)
    canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
