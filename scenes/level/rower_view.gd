class_name RowerView
extends Node2D

## The small boat of the players, seen from above, with its rowers: viking
## women with braids, who pull the oars with the strokes of the players.
##
## Alone, Ylva (blond braids) sits in the middle and pulls both oars. With two
## players, Ylva sits on the left and pulls the left oar, and Sigrid (red
## braids) sits on the right and pulls the right oar; the oars flash gold when
## the two row in time.
##
## The oars follow the players: while the camera sees a player row, the oar
## goes forward as the player reaches forward and back as the player leans
## back ([member live_pull], see RowingMeter.Pull). Otherwise (e.g., the
## autopilot), each stroke plays a pull; a stroke which comes before the last
## pull is done speeds the oar up, but never makes it jump.
##
## The bow points up (-y); the rowers face the stern, as rowers do. The picture
## is larger than the boat would be (see [constant SCALE]), so that the players
## see the rowers well.

## How much larger than life we draw the boat.
const SCALE := 3.0

## How long the pull of the oars takes after a stroke, in seconds (when the
## oars do not follow the players).
const PULL_SECONDS := 0.9

## How long the oar takes to come forward again for the next pull, in seconds.
const RECOVER_SECONDS := 0.5

## The oar follows the pull of the player with this time constant, in seconds.
const FOLLOW_SECONDS := 0.06

## Where the oars rest while the boat glides (between -1 forward and 1 back).
const REST := 0.3

## The oar never moves faster than this, in swings (from -1 to 1) per second,
## so that it never jumps, e.g., when it starts to follow a player.
const MAX_SPEED := 6.0

## How long the oars shine after strokes in time, in seconds.
const GOLD_SECONDS := 0.7

const HULL := Color("8a5a2b")
const HULL_DARK := Color("6a4320")
const PLANK := Color("a8743c")
const OAR := Color("d8c08a")
const OAR_GOLD := Color("f2c14e")
const SKIN := Color("f0c8a0")
const BELT := Color("5a3a1e")

## The looks of the rowers: [hair, hair in shadow, band, tunic].
const YLVA := [Color("e8c25a"), Color("c9a03e"), Color("b8332a"), Color("2f6f6a")]
const SIGRID := [Color("c9602a"), Color("a04a20"), Color("2f5f8a"), Color("7a3a6a")]

## The boat to draw.
var boat: RowBoat

## Whether two players row, an oar each.
var pair := false

## How far the player of each oar ([left, right]) is through the stroke, from
## the vision (0 forward, 1 back), or below 0 when the oar does not follow a
## player (set by the level every frame).
var live_pull := [-1.0, -1.0]

## Whether the blade of each oar dipped in (caught the water) in this frame,
## and whether it pulls through the water now (for the splashes).
var catches := [false, false]
var pulling := [false, false]

## The swing of each oar: -1 forward (the blade towards the bow, ready to
## pull), 1 back (the pull done).
var _swing := [REST, REST]

## The stage of each oar when it plays the strokes: "rest", "recover" (coming
## forward) or "pull"; and how many strokes wait to be played.
var _stage := ["rest", "rest"]
var _pending := [0, 0]
var _last_since := [INF, INF]


func _process(delta: float) -> void:
    if boat != null and delta > 0.0:
        for side in [0, 1]:
            _move_oar(side, delta)
    queue_redraw()


## Move the oar of the side for the frame: follow the player, or play the strokes.
func _move_oar(side: int, delta: float) -> void:
    var before: float = _swing[side]
    var was_pulling: bool = pulling[side]
    catches[side] = false

    # NOTE (mristin):
    # The strokes of the boat, for the oars which play them.
    var since: float = boat.since_side[side] if pair else boat.since_stroke
    if since < _last_since[side]:
        _pending[side] += 1
    _last_since[side] = since

    var pull: float = live_pull[side]
    if pull >= 0.0:
        _pending[side] = 0
        _stage[side] = "rest"
        var target := lerpf(-1.0, 1.0, pull)
        var followed := lerpf(_swing[side], target, 1.0 - exp(-delta / FOLLOW_SECONDS))
        _swing[side] = move_toward(_swing[side], followed, MAX_SPEED * delta)
        var speed: float = (_swing[side] - before) / delta
        pulling[side] = speed > 0.8
        catches[side] = pulling[side] and not was_pulling and before < -0.2
        return

    # NOTE (mristin):
    # Strokes which wait make the oar quicker, so that it keeps up without jumping.
    var hurry := 1.0 + float(_pending[side])
    match _stage[side]:
        "rest":
            _swing[side] = move_toward(_swing[side], REST, delta * 0.8)
            if _pending[side] > 0:
                _stage[side] = "recover"
        "recover":
            _swing[side] = move_toward(_swing[side], -1.0, delta * 2.0 / RECOVER_SECONDS * hurry)
            if _swing[side] <= -1.0:
                _stage[side] = "pull"
                _pending[side] = maxi(0, _pending[side] - 1)
                catches[side] = true
        "pull":
            _swing[side] = move_toward(_swing[side], 1.0, delta * 2.0 / PULL_SECONDS * hurry)
            if _swing[side] >= 1.0:
                _stage[side] = "recover" if _pending[side] > 0 else "rest"
    pulling[side] = _stage[side] == "pull"


func _draw() -> void:
    if boat == null:
        return
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
    var oar_color := OAR_GOLD if boat.since_in_time < GOLD_SECONDS else OAR

    var swings := [_swing[0], _swing[1]]
    for side in [0, 1]:
        _draw_oar(side, swings[side], oar_color)

    _draw_hull()
    if pair:
        _draw_rower(Vector2(-0.45, 0.35), [swings[0], swings[0]], YLVA, 0.8, [0])
        _draw_rower(Vector2(0.45, 0.35), [swings[1], swings[1]], SIGRID, 0.8, [1])
    else:
        _draw_rower(Vector2(0, 0.35), swings, YLVA, 1.0, [0, 1])


## The swing of the oar of a side (0 left, 1 right) now.
func swing_of(side: int) -> float:
    return _swing[side]


## Where the blade of the oar of a side (0 left, 1 right) is, in the world.
func blade_position(side: int) -> Vector2:
    var sign := -1.0 if side == 0 else 1.0
    var out := Vector2(sign, 0).rotated(sign * swing_of(side) * 0.6)
    return to_global((Vector2(sign * 1.0, 0.2) + out * 4.1) * SCALE)


## The oar of a side (0 left, 1 right), from the oarlock out over the water.
func _draw_oar(side: int, swing: float, color: Color) -> void:
    var sign := -1.0 if side == 0 else 1.0
    var lock := Vector2(sign * 1.0, 0.2)
    var out := Vector2(sign, 0).rotated(sign * swing * 0.6)
    var blade := lock + out * 3.6
    var handle := lock - out * 0.9
    draw_line(handle, blade, color, 0.16)
    var across := out.orthogonal() * 0.22
    draw_colored_polygon(
        PackedVector2Array(
            [
                blade - across,
                blade + out * 0.9 - across * 0.8,
                blade + out * 0.9 + across * 0.8,
                blade + across
            ]
        ),
        color.darkened(0.1)
    )


## The hull: pointed at the bow and at the stern.
func _draw_hull() -> void:
    var hull := PackedVector2Array(
        [
            Vector2(0, -3.0),
            Vector2(0.75, -2.0),
            Vector2(1.1, -0.5),
            Vector2(1.05, 1.2),
            Vector2(0.6, 2.5),
            Vector2(0, 3.0),
            Vector2(-0.6, 2.5),
            Vector2(-1.05, 1.2),
            Vector2(-1.1, -0.5),
            Vector2(-0.75, -2.0),
        ]
    )
    draw_colored_polygon(hull, HULL)
    var closed := hull.duplicate()
    closed.append(hull[0])
    draw_polyline(closed, HULL_DARK, 0.18, true)
    for y in [-1.5, 1.6]:
        draw_line(Vector2(-0.85, y), Vector2(0.85, y), PLANK, 0.3)


## A rower at [param seat], facing the stern (down), pulling the oars of the
## [param sides] (each with its swing in [param swings]); the pull leans her
## back towards the bow. [param looks] are her colors (see [constant YLVA]).
func _draw_rower(seat: Vector2, swings: Array, looks: Array, size: float, sides: Array) -> void:
    var swing: float = (swings[0] + swings[1]) / 2.0
    var body := seat + Vector2(0, -0.35 * swing)
    var tunic: Color = looks[3]
    for side in sides:
        var sign := -1.0 if side == 0 else 1.0
        var shoulder := body + Vector2(sign * 0.45 * size, 0)
        var grip := Vector2(sign * (0.25 if sides.size() == 2 else 0.65), 0.2 - 0.9 * swings[side])
        draw_line(shoulder, grip, tunic.lightened(0.1), 0.26 * size)
        draw_circle(grip, 0.13 * size, SKIN)
    draw_set_transform(body * SCALE, 0.0, Vector2(SCALE, SCALE * 0.75))
    draw_circle(Vector2.ZERO, 0.6 * size, tunic)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
    draw_line(
        body + Vector2(-0.55 * size, 0.05), body + Vector2(0.55 * size, 0.05), BELT, 0.12 * size
    )

    # NOTE (mristin):
    # Her head, seen from above: her hair, a band, and two braids down her
    # back (towards the bow, since she faces the stern).
    var head := body + Vector2(0, -0.05)
    var hair: Color = looks[0]
    var shadow: Color = looks[1]
    var band: Color = looks[2]
    for sign in [-1.0, 1.0]:
        var from := head + Vector2(sign * 0.22, -0.2) * size
        var sway := 0.08 * sin(Time.get_ticks_msec() / 400.0 + sign)
        var to := head + Vector2(sign * (0.3 + sway), -1.0) * size
        draw_line(from, to, shadow, 0.2 * size)
        for k in range(1, 4):
            draw_circle(from.lerp(to, k / 4.0), 0.12 * size, hair)
        draw_circle(to, 0.09 * size, band)
    draw_circle(head, 0.4 * size, hair)
    draw_arc(head, 0.4 * size, 0.0, TAU, 24, band, 0.08 * size)
    draw_circle(head + Vector2(0, 0.22 * size), 0.17 * size, SKIN)
