class_name RowBoat
extends RefCounted

## The small boat of the players: where it is, where it heads and how fast it
## goes. Each stroke pushes it, and it glides on, slowing down slowly, so that
## the players row a few strokes and then steer while the boat glides.
##
## One player pulls both oars and steers with the head ([member steer]). Two
## players pull an oar each ([method stroke_side]): each stroke kicks the bow
## away from its side, so the boat turns away from the stronger rower, and
## strokes in time cancel the kicks and push more.
##
## Both hands raised high above the head brake ([member brake]): the rowers
## hold the blades in the water, the boat slows down quickly, and strokes do
## not count.
##
## The boat never stops hard on the land: it slides along the shore, so that
## the players keep most of their way (see [method _slide]).

## How much faster each stroke makes the boat, in metres per second, for a
## stroke of the usual depth.
const STROKE_PUSH := 8.0

## The usual depth of a stroke, in units of the player (see RowingMeter).
const USUAL_DEPTH := 0.75

## The boat is never faster than this, in metres per second.
const MAX_SPEED := 32.0

## How long the boat glides: its speed falls to a third in this many seconds.
const GLIDE_SECONDS := 6.0

## While braking, the speed falls to a third in this many seconds.
const BRAKE_SECONDS := 0.8

## How fast the boat turns at full steering, in degrees per second.
const TURN_DEGREES := 90.0

## Even standing still, the boat turns this share of its full turn (the
## rower turns it with the oars), so that the players can aim before rowing.
const TURN_STILL := 0.6

## At this speed and faster, the boat turns fully, in metres per second.
const TURN_FULL_SPEED := 6.0

## Faster than [constant TURN_FULL_SPEED], the boat turns quicker still, up to
## this share more of its full turn at [constant TURN_FAST_SPEED], so that the
## fast boat does not draw too wide circles.
const TURN_FAST_EXTRA := 0.5

## At this speed and faster, the boat turns its quickest, in metres per second.
const TURN_FAST_SPEED := 24.0

## With two rowers, each stroke pushes this share of a stroke of one player
## pulling both oars (two rowers in time push more than one).
const PAIR_SHARE := 0.6

## Two strokes within this many seconds are in time.
const IN_TIME_SECONDS := 0.5

## Strokes in time push this much more.
const IN_TIME_BONUS := 0.33

## A stroke on one side turns the boat by about this many degrees in all.
const KICK_DEGREES := 28.0

## The turn of a kick fades with this time constant, in seconds.
const KICK_SECONDS := 1.0

## Where the boat is, in metres.
var position := Vector2.ZERO

## Where the boat heads, in radians: 0 points north (up), clockwise.
var heading := 0.0

## The speed, in metres per second.
var speed := 0.0

## How the ship rows, as shares of the small rowing boat (see [method
## set_ship]): the push of a stroke, how long it glides, how quickly it turns
## and how fast it can go.
var push_share := 1.0
var glide_share := 1.0
var turn_share := 1.0
var top_share := 1.0

## How far the bow of the ship reaches ahead of where the boat is, in metres:
## the bow, too, must stay on the water (0 for the small boat).
var bow := 0.0

## The steering of the player, from -1 (left) to 1 (right).
var steer := 0.0

## Whether the rowers brake: the blades held in the water (see BrakeMeter).
var brake := false

## Seconds since the last stroke (for the oars of the picture).
var since_stroke := INF

## How many strokes the boat was rowed.
var strokes := 0

## The turning of the kicks of the strokes on one side, in radians per second,
## positive clockwise (to the right).
var yaw_rate := 0.0

## Seconds since the last stroke of each side: [left, right].
var since_side := [INF, INF]

## Seconds since the last strokes in time (for the golden oars of the picture).
var since_in_time := INF

## The side to which the boat slid along the shore last (1 right, -1 left).
var _slide_side := 1.0


## Row as the ship of the [param data] rows (its "push", "glide", "turn" and
## "top", see data/ships/ships.json).
func set_ship(data: Dictionary) -> void:
    push_share = float(data.get("push", 1.0))
    glide_share = float(data.get("glide", 1.0))
    turn_share = float(data.get("turn", 1.0))
    top_share = float(data.get("top", 1.0))
    bow = float(data.get("bow", 0.0))


## Row a stroke of the [param depth] (in units of the player).
func stroke(depth := USUAL_DEPTH) -> void:
    if brake:
        return
    var strength := clampf(depth / USUAL_DEPTH, 0.6, 1.3)
    speed = minf(MAX_SPEED * top_share, speed + STROKE_PUSH * strength * push_share)
    since_stroke = 0.0
    strokes += 1


## Row a stroke with the oar of one side (0 left, 1 right), of the [param depth]
## (in units of the player): it pushes the boat, and kicks the bow away from
## the side; in time with the other side, it pushes more.
func stroke_side(side: int, depth := USUAL_DEPTH) -> void:
    if brake:
        return
    var strength := clampf(depth / USUAL_DEPTH, 0.6, 1.3)
    var push := STROKE_PUSH * strength * PAIR_SHARE * push_share
    if since_side[1 - side] <= IN_TIME_SECONDS:
        push *= 1.0 + IN_TIME_BONUS
        since_in_time = 0.0
    speed = minf(MAX_SPEED * top_share, speed + push)
    # NOTE (mristin):
    # The left oar pushes the left side forward, so the bow turns right.
    var away := 1.0 if side == 0 else -1.0
    yaw_rate += away * deg_to_rad(KICK_DEGREES) / KICK_SECONDS * strength * turn_share
    since_side[side] = 0.0
    since_stroke = 0.0
    strokes += 1


## The direction in which the boat heads.
func forward() -> Vector2:
    return Vector2.UP.rotated(heading)


## Turn and move for a frame on the [param map]; return how far the boat went.
func move(delta: float, map: LakeMap) -> float:
    since_stroke += delta
    since_side[0] += delta
    since_side[1] += delta
    since_in_time += delta
    var turning := (
        clampf(TURN_STILL + speed / TURN_FULL_SPEED, TURN_STILL, 1.0)
        + TURN_FAST_EXTRA
        * clampf((speed - TURN_FULL_SPEED) / (TURN_FAST_SPEED - TURN_FULL_SPEED), 0.0, 1.0)
    )
    heading = wrapf(
        heading + (steer * deg_to_rad(TURN_DEGREES) * turning * turn_share + yaw_rate) * delta,
        -PI,
        PI
    )
    var slowing := BRAKE_SECONDS if brake else GLIDE_SECONDS * glide_share
    yaw_rate *= exp(-delta / minf(KICK_SECONDS, slowing))
    speed *= exp(-delta / slowing)
    if speed < 0.05:
        speed = 0.0

    var next := position + forward() * speed * delta
    if next == position:
        return 0.0
    if not _free(next, forward(), map):
        next = _slide(next, map, delta)
    var moved := position.distance_to(next)
    position = next
    return moved


## Whether the boat may go from where it is to [param next], heading
## [param ahead]: on the water all the way, and its bow on the water too.
func _free(next: Vector2, ahead: Vector2, map: LakeMap) -> bool:
    if not map.is_water(next) or map.crosses_land(position, next):
        return false
    return bow <= 0.0 or map.is_water(next + ahead * bow)


## The boat runs onto the shore at [param blocked]: it slides along the shore
## instead of stopping. It takes the free direction closest to its heading,
## keeps the speed which goes along the shore, and its bow turns gently along
## the shore. Only running nearly head-on stops it, and then it keeps a little
## way on, to go off at once when it turns away from the shore.
func _slide(blocked: Vector2, map: LakeMap, delta: float) -> Vector2:
    var step := position.distance_to(blocked)
    for degrees: float in [15.0, 30.0, 45.0, 60.0, 75.0]:
        # NOTE (mristin):
        # Prefer the side to which the player steers, otherwise the side of the
        # last slide, so that a boat in a cove keeps turning one way until it
        # is out, instead of zig-zagging in place.
        var first := signf(steer) if steer != 0.0 else _slide_side
        for side: float in [first, -first]:
            var angle := deg_to_rad(degrees) * side
            var along := Vector2.UP.rotated(heading + angle)
            var keep := cos(angle)
            var candidate := position + along * step * keep
            if not _free(candidate, along, map):
                continue
            _slide_side = side
            speed *= lerpf(1.0, keep, minf(1.0, delta * 4.0))
            heading = wrapf(heading + angle * minf(1.0, delta * 1.5), -PI, PI)
            return candidate
    speed = minf(speed, 1.5)
    return position
