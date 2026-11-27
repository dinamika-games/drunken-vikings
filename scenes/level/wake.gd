class_name Wake
extends Node2D

## The trail which a boat leaves on the water, fading out over a few seconds:
## a soft band of churned water behind the boat, and the two faint arms of the
## bow wave, which spread out in a V as they age. The faster the boat went,
## the brighter its trail.
##
## The trail starts under the boat (it follows the middle of the boat, and is
## drawn below it), so that its start never shows; every band fades to
## nothing at its sides, so the trail has no hard edges.

## How long the foam stays, in seconds.
const SECONDS := 4.0

## Leave a new point every this many metres.
const SPACING := 1.0

## The trail is brightest at this speed, in metres per second.
const FULL_SPEED := 8.0

const FOAM := Color(0.92, 0.97, 1.0)

## How wide the trail is behind the boat, and how far its arms spread at its
## end, in metres.
var width := 2.0
var spread := 6.0

## The points of the trail, the oldest first.
var _points: Array[_Point] = []
var _head := Vector2.INF
var _head_strength := 0.0
var _time := 0.0


## Follow the boat whose middle is at [param at], at [param speed] metres per
## second.
func follow(at: Vector2, delta: float, speed := FULL_SPEED) -> void:
    _time += delta
    _head = at
    _head_strength = clampf(speed / FULL_SPEED, 0.0, 1.0)
    if _points.is_empty() or _points[-1].at.distance_to(at) >= SPACING:
        _points.append(_Point.new(at, _time, _head_strength))
    while not _points.is_empty() and _time - _points[0].time > SECONDS:
        _points.pop_front()
    queue_redraw()


func _draw() -> void:
    if _points.is_empty():
        return
    # NOTE (mristin):
    # The newest point is where the boat is now, so that the trail never lags.
    var line := PackedVector2Array()
    var ages := PackedFloat32Array()
    var strengths := PackedFloat32Array()
    for point in _points:
        line.append(point.at)
        ages.append(clampf((_time - point.time) / SECONDS, 0.0, 1.0))
        strengths.append(point.strength)
    if _head != Vector2.INF and line[-1].distance_to(_head) > 0.05:
        line.append(_head)
        ages.append(0.0)
        strengths.append(_head_strength)
    if line.size() < 2:
        return

    var sides := PackedVector2Array()
    for i in range(line.size()):
        sides.append(_side(line, i, sides[i - 1] if i > 0 else Vector2.ZERO))

    var half := PackedFloat32Array()
    var alpha := PackedFloat32Array()
    var arms := [PackedVector2Array(), PackedVector2Array()]
    var arm_half := PackedFloat32Array()
    var arm_alpha := PackedFloat32Array()
    for i in range(line.size()):
        var age := ages[i]
        var fade := (1.0 - age) * strengths[i]
        half.append(lerpf(width * 0.5, width * 1.3, age))
        alpha.append(0.26 * fade)
        var out := lerpf(width * 0.4, spread, age)
        arms[0].append(line[i] + sides[i] * out)
        arms[1].append(line[i] - sides[i] * out)
        arm_half.append(lerpf(0.4, 1.4, age))
        arm_alpha.append(0.32 * fade * (1.0 - age))
    _draw_soft_band(line, sides, half, alpha)
    for arm in arms:
        _draw_soft_band(arm, sides, arm_half, arm_alpha)


## A band along [param line], [param half] wide to each side (along [param
## sides]), its colour [param alpha] in the middle, fading to nothing at its
## sides.
func _draw_soft_band(
    line: PackedVector2Array,
    sides: PackedVector2Array,
    half: PackedFloat32Array,
    alpha: PackedFloat32Array
) -> void:
    var clear := Color(FOAM, 0.0)
    for i in range(1, line.size()):
        var a := Color(FOAM, alpha[i - 1])
        var b := Color(FOAM, alpha[i])
        if line[i - 1].distance_squared_to(line[i]) < 1e-4:
            continue
        for sign: float in [-1.0, 1.0]:
            var outer0 := line[i - 1] + sides[i - 1] * half[i - 1] * sign
            var outer1 := line[i] + sides[i] * half[i] * sign
            # NOTE (mristin):
            # Two triangles each, which need no triangulation (a quad of a
            # turning trail may fold onto itself).
            draw_primitive(
                PackedVector2Array([line[i - 1], line[i], outer1]),
                PackedColorArray([a, b, clear]),
                PackedVector2Array()
            )
            draw_primitive(
                PackedVector2Array([line[i - 1], outer1, outer0]),
                PackedColorArray([a, clear, clear]),
                PackedVector2Array()
            )


## The sideways direction of the [param line] at its point [param i],
## smoothed over its neighbours, and turned the same way as [param before]
## so that the bands never twist.
func _side(line: PackedVector2Array, i: int, before: Vector2) -> Vector2:
    var from := line[maxi(0, i - 3)]
    var to := line[mini(line.size() - 1, i + 3)]
    var along := to - from
    if along.length() < 0.001:
        return before if before != Vector2.ZERO else Vector2.RIGHT
    var side := along.normalized().orthogonal()
    if before != Vector2.ZERO and side.dot(before) < 0.0:
        side = -side
    return side


## A point of the trail: where the boat was, when (see Wake._time), and how
## bright its trail is there (0 to 1).
class _Point:
    var at: Vector2
    var time: float
    var strength: float

    func _init(where: Vector2, when: float, bright: float) -> void:
        at = where
        time = when
        strength = bright
