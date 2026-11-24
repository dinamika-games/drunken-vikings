class_name Longship
extends Node2D

## The viking ship which the players follow: it sails the route of the map
## from the start village to the goal, and keeps ahead of the players, but
## never too far: it slows down as they fall behind, so that it sails at
## their pace and the treats it drops fall not far ahead of them, waits for
## them when they fall far behind, and hurries on when they come too close.
## Nobody is ever lost; the ship always waits.

## The speed at which the ship sails while the players keep up, in metres per second.
const CRUISE := 8.0

## The speed at which the ship hurries on when the players come too close.
const HURRY := 12.0

## The ship keeps between these many metres ahead of the players along the
## route: it hurries on when closer than LEAD_NEAR, cruises up to LEAD_EASE,
## slows down gently beyond, and waits from LEAD_FAR on. A player who rows
## at half the cruise sails about midway between LEAD_EASE and LEAD_FAR
## behind it.
const LEAD_NEAR := 60.0
const LEAD_EASE := 90.0
const LEAD_FAR := 150.0

## How much larger than life we draw the ship, as the boats.
const SCALE := 2.0

const HULL := Color("6a4320")
const PLANK := Color("8a5a2b")
const DECK := Color("a8743c")
const SAIL := Color("f1e6cc")
const STRIPE := Color("b8332a")
const SHIELDS := [Color("c8a23a"), Color("b8332a"), Color("2f5f8a"), Color("e8e0d0")]
const OAR := Color("d8c08a")
const HAIR := [Color("e8c25a"), Color("8a5a2b"), Color("c9502a"), Color("3a2a1a")]

## The painted ship (see Pictures), in the units of the drawing: how long the
## hull is from the dragon to the stern, where the oars go out under the
## shields, and how long they are.
const PAINTED_LENGTH := 25.0
const PAINTED_LOCK_X := 3.4
## One oar for each rower: the crew sits on three benches, two on each
## (see the crew in _draw_painted, 6.3 long around 1.2).
const PAINTED_OARS_Y := [-0.9, 1.2, 3.3]
const PAINTED_OAR := 7.5

## The painted ship is drawn this much smaller than the units above, so that
## it fits the lakes.
const PAINTED_SCALE := 0.75

## How long the crew takes to pull the oars in, or to put them out, in seconds.
const SHIP_SECONDS := 0.5

## The map whose route the ship sails.
var map: LakeMap

## How far along the route the ship is, in metres.
var progress := 0.0

## The speed, in metres per second.
var speed := 0.0

## Where the ship heads, in radians: 0 points north, clockwise.
var heading := 0.0

## Whether the ship waits for the players.
var waiting := false

## Whether the ship reached the goal.
var arrived := false

## Whether the crew dipped the oars in this frame (for the splashes).
var dipped := false

## Whether the ship carries a wedding: garlands of flowers, a pink and white
## sail, and the bride and the groom at the stern.
var wedding := false

## Whether the ship is the pirates' (see the chase mode): a black sail with a
## laughing skull, and the pirates with their red scarves.
var pirate := false

## Whether the captain of the pirates stands at the bow and shakes a fist.
var shaking := false

## Whether the ship has a sail (the færing of the players has none).
var has_sail := true

## The swing of the oars, from -1 to 1, when the crew rows to the beat of the
## players (see [method follow]); NAN when the crew keeps its own beat.
var oars_swing := NAN

## Whether the oars of the crew pull now (with [member oars_swing]).
var oars_pulling := false

var _time := 0.0
var _beat := 0.0

## How far the oars of each side ([left, right]) are pulled in along the hull,
## out of the way of the land: from 0 (out) to 1 (in).
var _shipped := [0.0, 0.0]


## Sail for a frame; [param players_progress] is how far along the route the
## players got (the farthest of them).
func sail(delta: float, players_progress: float) -> void:
    _time += delta
    _ship_oars(delta)
    var before := _beat
    _beat += delta * (0.4 + speed / CRUISE * 0.5)
    # NOTE (mristin):
    # The oars dip in at the start of each beat, while the ship moves.
    dipped = floorf(_beat) > floorf(before) and speed > 0.5
    var lead := progress - players_progress
    var target := CRUISE
    if lead < LEAD_NEAR:
        target = HURRY
    elif lead > LEAD_EASE:
        # NOTE (mristin):
        # Slow down gently rather than stop all at once: the ship then
        # settles at the pace of the players, a little farther ahead the
        # slower they row.
        target = CRUISE * clampf((LEAD_FAR - lead) / (LEAD_FAR - LEAD_EASE), 0.0, 1.0)
    waiting = target == 0.0
    speed = lerpf(speed, target, 1.0 - exp(-delta / 1.5))
    var length := map.route_length()
    progress = minf(length, progress + speed * delta)
    arrived = progress >= length - 0.5
    if arrived:
        speed = 0.0

    position = map.route_point(progress)
    var ahead := map.route_point(progress + 15.0)
    if ahead.distance_to(position) > 0.5:
        var target_heading := (ahead - position).angle() + PI / 2.0
        heading = lerp_angle(heading, target_heading, 1.0 - exp(-delta / 0.8))
    rotation = heading
    queue_redraw()


## Row for a frame towards [param target] at [param target_speed] (in metres
## per second), not along the route: for the pirates of the chase mode.
func drive(delta: float, target: Vector2, target_speed: float) -> void:
    _time += delta
    _ship_oars(delta)
    var before := _beat
    _beat += delta * (0.4 + speed / CRUISE * 0.5)
    dipped = floorf(_beat) > floorf(before) and speed > 0.5
    speed = lerpf(speed, target_speed, 1.0 - exp(-delta / 1.5))
    var to := target - position
    if to.length() > 0.5:
        var wanted := to.angle() + PI / 2.0
        heading = lerp_angle(heading, wanted, 1.0 - exp(-delta / 0.6))
        position += to.normalized() * minf(speed * delta, to.length())
    rotation = heading
    queue_redraw()


## Go with the players' boat for a frame: the ship of the players (see
## world.gd), whose crew rows to their beat ([member oars_swing]).
func follow(delta: float, at: Vector2, towards: float, boat_speed: float) -> void:
    _time += delta
    _ship_oars(delta)
    position = at
    heading = towards
    rotation = towards
    speed = boat_speed
    queue_redraw()


## Over the land, the crew pulls in the oars of that side, and puts them out
## again over the water.
func _ship_oars(delta: float) -> void:
    if map == null or not _painted():
        return
    for i in range(2):
        var side := -1.0 if i == 0 else 1.0
        var reach := Vector2(side * (PAINTED_LOCK_X + PAINTED_OAR * 0.85), PAINTED_OARS_Y[1])
        var over_land := not map.is_water(to_global(reach * SCALE * PAINTED_SCALE))
        _shipped[i] = move_toward(_shipped[i], 1.0 if over_land else 0.0, delta / SHIP_SECONDS)


## How far the oars are through their swing, from -1 to 1.
func _swing() -> float:
    if not is_nan(oars_swing):
        return oars_swing
    return -cos(_beat * TAU) if speed > 0.5 else 0.3


## Where the blades of the oars which are out are, in the world.
func blade_positions() -> Array[Vector2]:
    var blades: Array[Vector2] = []
    var swing := _swing()
    if _painted():
        for y: float in PAINTED_OARS_Y:
            for side in [-1.0, 1.0]:
                if _shipped[0 if side < 0.0 else 1] > 0.0:
                    continue
                var out := Vector2(side, 0).rotated(side * swing * 0.45)
                var blade := Vector2(side * PAINTED_LOCK_X, y) + out * PAINTED_OAR * 0.75
                blades.append(to_global(blade * SCALE * PAINTED_SCALE))
        return blades
    for i in range(7):
        var y := -6.0 + i * 2.2
        for side in [-1.0, 1.0]:
            var out := Vector2(side, 0).rotated(side * swing * 0.45)
            blades.append(to_global((Vector2(side * 2.1, y) + out * 5.6) * SCALE))
    return blades


## Which of the painted ships this is.
func _kind() -> String:
    return "pirate" if pirate else ("wedding" if wedding else "plain")


## Whether the pictures of the painted ship are there.
func _painted() -> bool:
    var kind := _kind()
    return Pictures.has_all(
        "longships",
        ["hull_" + kind, "oar", "crew_" + kind, "sail_%s_full" % kind, "sail_%s_slack" % kind]
    )


func _draw() -> void:
    if _painted():
        _draw_painted()
        return
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))

    # NOTE (mristin):
    # The crew rows while the ship moves, the faster the quicker.
    var swing := _swing()

    for i in range(7):
        var y := -6.0 + i * 2.2
        for side in [-1.0, 1.0]:
            var lock := Vector2(side * 2.1, y)
            var out := Vector2(side, 0).rotated(side * swing * 0.45)
            draw_line(lock, lock + out * 5.5, OAR, 0.22)
            draw_line(lock + out * 4.8, lock + out * 6.0, OAR.darkened(0.15), 0.5)

    var hull := PackedVector2Array(
        [
            Vector2(0, -11.0),
            Vector2(1.2, -9.0),
            Vector2(2.3, -5.0),
            Vector2(2.5, 0.0),
            Vector2(2.3, 5.0),
            Vector2(1.2, 9.0),
            Vector2(0, 11.0),
            Vector2(-1.2, 9.0),
            Vector2(-2.3, 5.0),
            Vector2(-2.5, 0.0),
            Vector2(-2.3, -5.0),
            Vector2(-1.2, -9.0),
        ]
    )
    draw_colored_polygon(hull, HULL)
    var inner := PackedVector2Array()
    for point in hull:
        inner.append(point * Vector2(0.78, 0.88))
    draw_colored_polygon(inner, DECK)
    for y in range(-8, 9, 2):
        var half := 1.9 * sqrt(maxf(0.0, 1.0 - pow(y / 10.0, 2.0)))
        draw_line(Vector2(-half, y), Vector2(half, y), PLANK, 0.15)

    # The shields along the sides.
    for i in range(9):
        var y := -7.0 + i * 1.75
        var half := 2.45 * sqrt(maxf(0.0, 1.0 - pow(y / 11.0, 2.0)))
        for side in [-1.0, 1.0]:
            var color: Color = SHIELDS[(i + (1 if side > 0 else 0)) % SHIELDS.size()]
            draw_circle(Vector2(side * half, y), 0.6, color)
            draw_circle(Vector2(side * half, y), 0.2, Color("4a4a4a"))

    # The crew, in pairs on the benches.
    for i in range(6):
        var y := -5.0 + i * 2.2
        for side in [-1.0, 1.0]:
            draw_circle(
                Vector2(side * 0.9, y + swing * 0.2),
                0.45,
                Color("b8332a") if pirate else HAIR[(i * 2 + int(side > 0)) % HAIR.size()]
            )

    # The dragon at the bow and the curl of the stern.
    draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-0.5, -10.5), Vector2(0.5, -10.5), Vector2(0.3, -13.0), Vector2(-0.3, -13.0)]
        ),
        HULL
    )
    draw_circle(Vector2(0, -13.2), 0.75, HULL)
    draw_circle(Vector2(0.35, -13.5), 0.18, Color("f2c14e"))
    draw_circle(Vector2(-0.35, -13.5), 0.18, Color("f2c14e"))
    draw_arc(Vector2(0, 11.6), 0.9, -PI * 0.2, PI * 1.2, 12, HULL, 0.6)

    # The square sail across the mast, filled by the wind, red and white.
    var sail_y := -1.0
    var belly := 1.3 if speed > 0.5 else 0.5
    var stripes := 6
    for k in range(stripes):
        var x0 := -5.0 + k * 10.0 / stripes
        var x1 := x0 + 10.0 / stripes
        var b0 := belly * (1.0 - pow(x0 / 5.0, 2.0))
        var b1 := belly * (1.0 - pow(x1 / 5.0, 2.0))
        draw_colored_polygon(
            PackedVector2Array(
                [
                    Vector2(x0, sail_y),
                    Vector2(x1, sail_y),
                    Vector2(x1, sail_y - b1 - 0.6),
                    Vector2(x0, sail_y - b0 - 0.6)
                ]
            ),
            _sail_color(k)
        )
    draw_line(Vector2(-5.4, sail_y), Vector2(5.4, sail_y), HULL, 0.35)
    draw_circle(Vector2(0, sail_y), 0.4, HULL)
    if wedding:
        _draw_wedding()
    if pirate:
        _draw_skull(Vector2(0, sail_y - belly * 0.6 - 0.3))


func _sail_color(stripe: int) -> Color:
    if pirate:
        return Color("1a1a1e") if stripe % 2 == 0 else Color("2a2a30")
    if stripe % 2 == 1:
        return SAIL
    return Color("e86a9a") if wedding else STRIPE


## A laughing skull on the black sail: a cartoon, for the children.
func _draw_skull(at: Vector2) -> void:
    draw_circle(at, 0.9, Color("f1f0ea"))
    draw_rect(Rect2(at + Vector2(-0.5, 0.5), Vector2(1.0, 0.5)), Color("f1f0ea"))
    draw_circle(at + Vector2(-0.35, -0.1), 0.25, Color("1a1a1e"))
    draw_circle(at + Vector2(0.35, -0.1), 0.25, Color("1a1a1e"))
    draw_arc(at + Vector2(0, 0.35), 0.35, 0.2, PI - 0.2, 8, Color("1a1a1e"), 0.12)
    draw_line(at + Vector2(-1.4, 1.4), at + Vector2(1.4, 2.2), Color("f1f0ea"), 0.25)
    draw_line(at + Vector2(1.4, 1.4), at + Vector2(-1.4, 2.2), Color("f1f0ea"), 0.25)


## The garlands of flowers along the sides, and the bride and the groom at the stern.
func _draw_wedding() -> void:
    var flowers := [Color("e86a9a"), Color("ffffff"), Color("f2c14e"), Color("9a6ab8")]
    for i in range(22):
        var y := -9.5 + i * 0.9
        var half := 2.5 * sqrt(maxf(0.0, 1.0 - pow(y / 11.0, 2.0)))
        for side in [-1.0, 1.0]:
            var sag := 0.15 * sin(i * 1.7)
            draw_circle(
                Vector2(side * (half + 0.15 + sag), y),
                0.32,
                flowers[(i + int(side > 0)) % flowers.size()]
            )
    # NOTE (mristin):
    # Seen from above: the bride in a red dress with a crown of flowers, and
    # the groom in blue, side by side at the stern, waving.
    var wave := sin(_time * 5.0) * 0.3
    draw_circle(Vector2(-0.7, 8.2), 0.75, Color("b8332a"))
    draw_circle(Vector2(-0.7, 8.0), 0.45, Color("e8c25a"))
    for k in range(7):
        draw_circle(
            Vector2(-0.7, 8.0) + Vector2.RIGHT.rotated(k * TAU / 7.0) * 0.5,
            0.18,
            flowers[k % flowers.size()]
        )
    draw_line(Vector2(-1.3, 8.0), Vector2(-1.9, 7.3 + wave), Color("f0c8a0"), 0.2)
    draw_circle(Vector2(0.7, 8.2), 0.75, Color("2f5f8a"))
    draw_circle(Vector2(0.7, 8.0), 0.45, Color("8a5a2b"))
    draw_line(Vector2(1.3, 8.0), Vector2(1.9, 7.3 - wave), Color("f0c8a0"), 0.2)


## The painted ship: the oars turning around their locks under the shields,
## the hull, the crew bobbing with the stroke, the bride and the groom of the
## wedding at the stern, and the sail, full while the ship moves.
func _draw_painted() -> void:
    var kind := _kind()
    var base := Transform2D(0.0, Vector2(SCALE, SCALE) * PAINTED_SCALE, 0.0, Vector2.ZERO)
    var swing := _swing()

    # NOTE (mristin):
    # The blades pull in the water while the swing goes back, and come out
    # flat on the way forward (see OarDrawing); they rest half lifted.
    var lift := 0.5
    if not is_nan(oars_swing):
        lift = 0.0 if oars_pulling else 0.8
    elif speed > 0.5:
        lift = clampf(0.5 - 0.9 * sin(_beat * TAU), 0.0, 1.0)
    var oar := Pictures.of("longships", "oar")
    for y: float in PAINTED_OARS_Y:
        for side in [-1.0, 1.0]:
            var out := Vector2(side, 0).rotated(side * swing * 0.45)
            var shipped: float = _shipped[0 if side < 0.0 else 1]
            # Pulled in, the oar lies along the hull, its blade to the stern.
            var angle := lerp_angle(
                out.angle(), Vector2(-side * 0.1, 1.0).angle(), smoothstep(0.0, 1.0, shipped)
            )
            OarDrawing.draw(
                self,
                oar,
                base,
                Vector2(side * PAINTED_LOCK_X, y),
                angle,
                PAINTED_OAR,
                1.0 / 6.0,
                maxf(lift, shipped)
            )

    Pictures.draw(
        self, Pictures.of("longships", "hull_" + kind), Vector2(0, -0.5), PAINTED_LENGTH, 0.0, base
    )
    Pictures.draw(
        self,
        Pictures.of("longships", "crew_" + kind),
        Vector2(0, 1.2 + swing * 0.2),
        6.3,
        0.0,
        base
    )
    if wedding:
        var bride := Pictures.of("longships", "bride_and_groom")
        if bride != null:
            var wave := sin(_time * 5.0) * 0.04
            Pictures.draw(self, bride, Vector2(0, 7.6), 4.6, wave, base)
    var sail := "sail_%s_%s" % [kind, "full" if speed > 0.5 else "slack"]
    if has_sail:
        Pictures.draw(
            self,
            Pictures.of("longships", sail),
            Vector2(0, -3.8),
            12.0,
            0.0,
            base,
            Color.WHITE,
            0.42
        )
    var fist := Pictures.of("longships", "pirate_fist")
    if pirate and shaking and fist != null:
        Pictures.draw(self, fist, Vector2(0, -7.5), 5.0, sin(_time * 12.0) * 0.2, base)
