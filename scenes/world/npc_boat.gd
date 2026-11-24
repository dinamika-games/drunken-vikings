class_name NpcBoat
extends Node2D

## A boat of the lakes with its skipper (see Gossip.SKIPPERS): it sails the
## ways between the settlements (see LakeMap.routes), waits a while at a
## jetty, and sets out to another place. When the players hail it, it stops
## beside them until they are done talking.

## How fast the boat goes, in metres per second.
const SPEED := 4.5

## How long it waits at a jetty, in seconds.
const WAIT := Vector2(6.0, 14.0)

## How much larger than life we draw the boat, as the players' boat.
const SCALE := 2.6

const HULL := Color("7a4f28")
const HULL_DARK := Color("5a3a1e")

## The skipper (see Gossip.skipper).
var skipper := {}

## Whether the boat stops for the players (while they talk).
var held := false

## Seconds until the skipper hails the players again.
var cooldown := 0.0

## Where the boat heads, in radians: 0 points north, clockwise.
var heading := 0.0

var _map: LakeMap
var _rng := RandomNumberGenerator.new()
var _at_place := ""
var _to_place := ""
var _path := PackedVector2Array()
var _index := 0
var _wait := 0.0
var _time := 0.0
var _speed := 0.0


## Start at the berth of the place (beside the end of its jetty, on the
## water), with the skipper, on the [param map].
func setup(map: LakeMap, place_id: String, who: Dictionary, seed: int) -> void:
    _map = map
    skipper = who
    _rng.seed = seed
    _at_place = place_id
    position = map.place(place_id)["berth"]
    _wait = _rng.randf_range(0.0, WAIT.y)
    _time = _rng.randf() * 10.0


## Whether the boat sails now (not waiting at a jetty, not held).
func sailing() -> bool:
    return not held and _wait <= 0.0 and _index < _path.size()


func _process(delta: float) -> void:
    _time += delta
    cooldown = maxf(0.0, cooldown - delta)
    if _map == null:
        return
    if held:
        _speed = lerpf(_speed, 0.0, 1.0 - exp(-delta / 0.5))
    elif _wait > 0.0:
        _wait -= delta
        _speed = 0.0
        if _wait <= 0.0:
            _set_out()
    elif _index < _path.size():
        _speed = lerpf(_speed, SPEED, 1.0 - exp(-delta / 1.5))
        var target := _path[_index]
        var step := _speed * delta
        var to := target - position
        if to.length() <= step:
            position = target
            _index += 1
            if _index >= _path.size():
                _at_place = _to_place
                _wait = _rng.randf_range(WAIT.x, WAIT.y)
        else:
            position += to.normalized() * step
            heading = lerp_angle(heading, to.angle() + PI / 2.0, 1.0 - exp(-delta / 0.7))
    rotation = heading
    queue_redraw()


func _set_out() -> void:
    var others: Array = []
    for place in _map.places:
        if place["id"] != _at_place and place["id"] != "home":
            others.append(place["id"])
    if others.is_empty():
        return
    _to_place = others[_rng.randi() % others.size()]
    # NOTE (mristin):
    # The routes run from jetty to jetty, whose ends count as land: the boat
    # leaves from the berth and moors at the berth instead.
    # NOTE: The routes run from berth to berth, clear of the shores and the
    # jetties (see dev/maps/make_lakes.py and tests/godot/test_map.gd).
    _path = _map.route_between(_at_place, _to_place)
    _index = 0


func _draw() -> void:
    var painted := Pictures.of("skippers", skipper.get("picture", ""))
    if painted != null:
        # NOTE (mristin):
        # The painted boat, with its sail and its oars, is 7 long in the
        # units of the drawing; it rocks a little while it sails.
        var rock := sin(_time * 2.4) * 0.04 if _speed > 0.5 else 0.0
        Pictures.draw(self, painted, Vector2.ZERO, 7.0 * SCALE, rock)
        _draw_bubble()
        return
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
    var swing := sin(_time * 2.4) if _speed > 0.5 else 0.3
    for sign in [-1.0, 1.0]:
        var lock := Vector2(sign * 0.9, 0.4)
        var out := Vector2(sign, 0).rotated(sign * swing * 0.5)
        draw_line(lock, lock + out * 3.0, Color("d8c08a"), 0.15)
    var hull := PackedVector2Array(
        [
            Vector2(0, -3.2),
            Vector2(0.8, -2.0),
            Vector2(1.0, 0.5),
            Vector2(0.6, 2.6),
            Vector2(0, 3.0),
            Vector2(-0.6, 2.6),
            Vector2(-1.0, 0.5),
            Vector2(-0.8, -2.0),
        ]
    )
    draw_colored_polygon(hull, HULL)
    var closed := hull.duplicate()
    closed.append(hull[0])
    draw_polyline(closed, HULL_DARK, 0.16, true)
    # The skipper, and a little square sail of their color.
    var hair: Color = skipper.get("hair", Color("8a5a2b"))
    draw_circle(Vector2(0, 1.0), 0.45, Color("4a5a6a"))
    draw_circle(Vector2(0, 0.9), 0.35, hair)
    var sail: Color = skipper.get("sail", Color.WHITE)
    var belly := 0.6 if _speed > 0.5 else 0.2
    draw_colored_polygon(
        PackedVector2Array(
            [
                Vector2(-1.6, -0.6),
                Vector2(1.6, -0.6),
                Vector2(1.4, -0.6 - belly - 0.4),
                Vector2(-1.4, -0.6 - belly - 0.4)
            ]
        ),
        sail
    )
    draw_line(Vector2(-1.7, -0.6), Vector2(1.7, -0.6), HULL_DARK, 0.2)
    _draw_bubble()


## A bubble when the skipper wants to talk.
func _draw_bubble() -> void:
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
    if not held and cooldown <= 0.0:
        var bob := sin(_time * 3.0) * 0.2
        var bubble := Pictures.of("ui", "speech_bubble")
        if bubble != null:
            var base := Transform2D(0.0, Vector2(SCALE, SCALE), 0.0, Vector2.ZERO)
            Pictures.draw(self, bubble, Vector2(2.6, -3.6 + bob), 2.4, 0.0, base)
            return
        draw_circle(Vector2(2.4, -3.4 + bob), 0.7, Color(1, 1, 1, 0.9))
        draw_circle(Vector2(1.8, -2.7 + bob), 0.25, Color(1, 1, 1, 0.9))
