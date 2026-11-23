class_name Wake
extends Node2D

## The trail of foam which a boat leaves on the water: it fades out over a
## few seconds.

## How long the foam stays, in seconds.
const SECONDS := 4.0

## Leave a new point of foam every this many metres.
const SPACING := 2.0

## How wide the trail is behind the boat, and at its end, in metres.
var width := 2.0
var spread := 6.0

## The points of the trail: Array of [Vector2, time].
var _points: Array = []
var _time := 0.0


## Follow the stern of the boat at [param at].
func follow(at: Vector2, delta: float) -> void:
    _time += delta
    if _points.is_empty() or (_points[-1][0] as Vector2).distance_to(at) >= SPACING:
        _points.append([at, _time])
    while not _points.is_empty() and _time - float(_points[0][1]) > SECONDS:
        _points.pop_front()
    queue_redraw()


func _draw() -> void:
    for i in range(1, _points.size()):
        var age := (_time - float(_points[i][1])) / SECONDS
        var a: Vector2 = _points[i - 1][0]
        var b: Vector2 = _points[i][0]
        var color := Color(1, 1, 1, 0.35 * (1.0 - age))
        draw_line(a, b, color, lerpf(width, spread, age))
