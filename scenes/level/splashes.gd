class_name Splashes
extends Node2D

## The splashes of the oars on the water (see splash.gdshader): each one a
## swirl of foam where an oar dips in, then rings which spread and fade.

const SHADER := preload("res://scenes/level/splash.gdshader")

## The most splashes at a time; the oldest go first.
const MAX_SPLASHES := 96

## The splashes: Array of [position, age in seconds, life in seconds, radius in metres, strength].
var _splashes: Array = []


func _ready() -> void:
    var shader_material := ShaderMaterial.new()
    shader_material.shader = SHADER
    material = shader_material


## Splash at [param at] (in metres), [param radius] metres wide at the end,
## lasting [param life] seconds, of the [param strength] in [0, 1].
func splash(at: Vector2, radius := 4.0, life := 1.4, strength := 1.0) -> void:
    _splashes.append([at, 0.0, life, radius, clampf(strength, 0.0, 1.0)])
    if _splashes.size() > MAX_SPLASHES:
        _splashes.pop_front()


func _process(delta: float) -> void:
    for item in _splashes:
        item[1] += delta
    _splashes = _splashes.filter(func(item: Array) -> bool: return item[1] < item[2])
    queue_redraw()


func _draw() -> void:
    for item in _splashes:
        var at: Vector2 = item[0]
        var radius: float = item[3]
        var age := clampf(float(item[1]) / float(item[2]), 0.0, 1.0)
        draw_rect(
            Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
            Color(age, item[4], 0.0, 1.0)
        )
