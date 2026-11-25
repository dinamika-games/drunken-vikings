class_name Splashes
extends Node2D

## The splashes of the oars on the water (see splash.gdshader): each one a
## swirl of foam where an oar dips in, then rings which spread and fade.

const SHADER := preload("res://scenes/level/splash.gdshader")

## The most splashes at a time; the oldest go first.
const MAX_SPLASHES := 96

## The splashes, the oldest first.
var _splashes: Array[_Splash] = []


func _ready() -> void:
    var shader_material := ShaderMaterial.new()
    shader_material.shader = SHADER
    material = shader_material


## Splash at [param at] (in metres), [param radius] metres wide at the end,
## lasting [param life] seconds, of the [param strength] in [0, 1].
func splash(at: Vector2, radius := 4.0, life := 1.4, strength := 1.0) -> void:
    _splashes.append(_Splash.new(at, life, radius, clampf(strength, 0.0, 1.0)))
    if _splashes.size() > MAX_SPLASHES:
        _splashes.pop_front()


func _process(delta: float) -> void:
    for item in _splashes:
        item.age += delta
    _splashes = _splashes.filter(func(item: _Splash) -> bool: return item.age < item.life)
    queue_redraw()


func _draw() -> void:
    for item in _splashes:
        var at := item.at
        var radius := item.radius
        var age := clampf(item.age / item.life, 0.0, 1.0)
        draw_rect(
            Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
            Color(age, item.strength, 0.0, 1.0)
        )


## A splash: where it is (in metres), how old it is and how long it lasts (in
## seconds), how wide it is at the end (in metres), and how strong (0 to 1).
class _Splash:
    var at: Vector2
    var age := 0.0
    var life: float
    var radius: float
    var strength: float

    func _init(where: Vector2, lasting: float, wide: float, strong: float) -> void:
        at = where
        life = lasting
        radius = wide
        strength = strong
