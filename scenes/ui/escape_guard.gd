class_name EscapeGuard
extends Control

## Escape twice to leave: the first Escape shows [member question] at the top
## of the screen for a few seconds; a second Escape in that time emits
## [signal confirmed] (the scene then ends the journey, or the game). So a key
## pressed by chance never ends a voyage.

signal confirmed

## How long the second Escape may wait, in seconds.
const SECONDS := 3.0

const _INK := Color(0.1, 0.07, 0.03, 0.9)
const _GOLD := Color("f2c14e")

## What the first Escape asks.
var question := "Press Esc again to end the journey."

var _left := 0.0


## Put a guard over the [param scene] (on its own layer, above everything),
## which calls [param on_confirmed] after Escape twice.
static func attach(scene: Node, on_confirmed: Callable, asking := "") -> EscapeGuard:
    var layer := CanvasLayer.new()
    layer.layer = 100
    scene.add_child(layer)
    var guard := EscapeGuard.new()
    if asking != "":
        guard.question = asking
    guard.confirmed.connect(on_confirmed)
    layer.add_child(guard)
    guard.set_anchors_preset(Control.PRESET_FULL_RECT)
    return guard


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)


func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    if event.keycode != KEY_ESCAPE:
        return
    get_viewport().set_input_as_handled()
    if _left > 0.0:
        _left = 0.0
        queue_redraw()
        confirmed.emit()
        return
    _left = SECONDS
    queue_redraw()


func _process(delta: float) -> void:
    if _left > 0.0:
        _left = maxf(0.0, _left - delta)
        queue_redraw()


func _draw() -> void:
    if _left <= 0.0:
        return
    var font := ThemeDB.fallback_font
    var font_size := 36
    var width := font.get_string_size(question, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var alpha := clampf(_left / 0.4, 0.0, 1.0)
    var box := Rect2(Vector2((size.x - width) / 2.0 - 30.0, 400.0), Vector2(width + 60.0, 70.0))
    draw_rect(box, Color(_INK, 0.85 * alpha))
    draw_string(
        font,
        Vector2(box.position.x + 30.0, box.position.y + 48.0),
        question,
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        font_size,
        Color(_GOLD, alpha)
    )
