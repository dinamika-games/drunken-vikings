class_name MapLabel
extends Node2D

## A name on the map (of a lake, a sound, an island or a village), written
## upright on the screen whatever way the view turns (the level sets the
## rotation), and as large on the screen whatever the zoom.

## The size of the letters on the screen, by kind, in pixels.
const FONT_SIZES := {"lake": 34, "sound": 26, "island": 24, "village": 34}

const COLORS := {
    "lake": Color(1, 1, 1, 0.75),
    "sound": Color(1, 1, 1, 0.7),
    "island": Color("f1f0ea"),
    "village": Color("f2c14e"),
}

var text := ""
var kind := "lake"


func _draw() -> void:
    var zoom := get_viewport().get_canvas_transform().get_scale().x
    if zoom <= 0.0:
        return
    var font := ThemeDB.fallback_font
    var font_size: int = FONT_SIZES.get(kind, 24)
    var shown := text if kind != "lake" else text.to_upper()
    var size := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    # NOTE (mristin):
    # Draw at the size of the screen, so that the letters stay sharp.
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / zoom)
    var at := Vector2(-size.x / 2.0, font_size * 0.35)
    var color: Color = COLORS.get(kind, Color.WHITE)
    draw_string_outline(
        font,
        at,
        shown,
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        font_size,
        8,
        Color(0.05, 0.07, 0.1, 0.6 if kind in ["lake", "sound"] else 0.9)
    )
    draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
