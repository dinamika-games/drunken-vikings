class_name ScreenBackdrop
extends Control

## What a screen of choices lays over what lies behind it (see ChoicePanel):
## a dim, and the dim mirror of the players (see HandCursor.draw_mirror), so
## that their hand lies under the cursor.
##
## Both clear over the [member clear_rects] (e.g., the fields and the pasture
## of the farm at home, see FarmView.clear_rects), so that what lies behind
## shows there almost as it is; the fog clears softly around them (see
## screen_backdrop.gdshader).

const _SHADER := preload("res://scenes/ui/screen_backdrop.gdshader")

## The most clear rects which the shader takes.
const MAX_CLEAR := 32

## How much the backdrop darkens what lies behind it.
var dim := 0.0

## The cursor which draws the mirror of the players, if any.
var cursor: HandCursor = null

## Where what lies behind shows clearly, in the pixels of the canvas.
var clear_rects: Array[Rect2] = []:
    set(value):
        clear_rects = value
        _update_clear()


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shader_material := ShaderMaterial.new()
    shader_material.shader = _SHADER
    material = shader_material
    _update_clear()


func _process(_delta: float) -> void:
    if is_visible_in_tree():
        queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.1, dim))
    if cursor != null:
        cursor.draw_mirror(self, size)


func _update_clear() -> void:
    var rects := PackedVector4Array()
    rects.resize(MAX_CLEAR)
    # NOTE (mristin):
    # The farm has far fewer things to show than the shader takes; any more
    # stay under the fog.
    var count := mini(clear_rects.size(), MAX_CLEAR)
    for i in range(count):
        var rect := clear_rects[i]
        rects[i] = Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
    var shader_material := material as ShaderMaterial
    shader_material.set_shader_parameter("clear_rects", rects)
    shader_material.set_shader_parameter("clear_count", count)
