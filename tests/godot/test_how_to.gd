extends SceneTree

## Check How to play (see HowTo): every part shows what its line says, with
## the boat of the game, for one rower and for two. The boat moves on the
## strokes and glides on, slower; leaning turns it to that side; two rowers in
## time row it straight with golden oars, and the left one alone turns it
## right; the brake stops it; it stops beside the jetty; the hand chooses the
## card once; and the rowers stay inside the camera picture, painted in every
## pose (see HowToFigure.painted_pose).
##
## $GODOT --headless --path . --script tests/godot/test_how_to.gd -- --no-camera

const STEP := 1.0 / 60.0

const WorldScript := preload("res://scenes/world/world.gd")

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _run() -> void:
    for players in [1, 2]:
        var how := HowTo.new()
        how.players = players
        how.set_process(false)
        root.add_child(how)
        await process_frame
        var ids: Array = how.parts.map(func(part: Dictionary) -> String: return part["id"])
        _check(("left" in ids) == (players == 1), "only one rower steers by leaning")
        _check(("turn" in ids) == (players == 2), "only two rowers turn with the oars")
        for index in range(how.parts.size()):
            _play_part(how, index)
        how.queue_free()
        await process_frame
    print("PASS test_how_to" if _failures == 0 else "FAIL test_how_to (%d)" % _failures)
    quit(0 if _failures == 0 else 1)


## Play the part of the [param index] from its start to just before its end,
## and check what it shows.
func _play_part(how: HowTo, index: int) -> void:
    how._start_part(index)
    var data: Dictionary = how.parts[index]
    var id: String = data["id"]
    var seconds := float(data["seconds"])
    var where := "%s (%d rowers)" % [id, how.players]
    var start_speed := how.boat.speed
    var heading := how.boat.heading
    var speed_at_half := 0.0
    var lean_from := INF
    var lean_turn := 0.0
    var golden := false
    var t := 0.0
    while t < seconds - 2.0 * STEP:
        how.advance(STEP)
        t += STEP
        _check(how.part == index, "%s plays to its end" % where)
        if t <= seconds / 2.0:
            speed_at_half = how.boat.speed
        if how.boat.steer != 0.0:
            # NOTE: The turn while the rower leans, in steps (it may go round).
            if lean_from == INF:
                lean_from = t
            lean_turn += rad_to_deg(how.boat.yaw_rate * STEP) + _turn_step(how)
        golden = golden or how.boat.since_in_time < 0.5
        if int(t / STEP) % 30 == 0:
            for who in range(how.players):
                _check_inside(how, data, t, who, where)
    var turned := rad_to_deg(angle_difference(heading, how.boat.heading))
    match id:
        "sit":
            _check(how.boat.speed == 0.0, "%s: the boat waits" % where)
        "row", "pair":
            _check(
                how.boat.speed > 3.0,
                "%s: the strokes push the boat (%.1f)" % [where, how.boat.speed]
            )
            _check(absf(turned) < 10.0, "%s: the boat goes straight (%.0f)" % [where, turned])
        "glide":
            _check(
                start_speed > how.boat.speed and how.boat.speed > 0.5,
                (
                    "%s: the boat glides on, slower (%.1f to %.1f)"
                    % [where, start_speed, how.boat.speed]
                )
            )
        "left":
            _check(
                lean_turn < -45.0 and lean_turn > -180.0,
                (
                    "%s: leaning to the left turns left, by less than half round (%.0f)"
                    % [where, lean_turn]
                )
            )
        "right":
            _check(
                lean_turn > 45.0 and lean_turn < 180.0,
                (
                    "%s: leaning to the right turns right, by less than half round (%.0f)"
                    % [where, lean_turn]
                )
            )
        "turn":
            _check(
                turned > 15.0,
                "%s: the left oar alone turns the boat right (%.0f)" % [where, turned]
            )
        "brake":
            _check(
                speed_at_half > 2.0 and how.boat.speed < 0.5,
                (
                    "%s: the brake stops the boat (%.1f to %.1f)"
                    % [where, speed_at_half, how.boat.speed]
                )
            )
        "dock":
            var jetty: Vector2 = how._lake.jetty.origin
            _check(
                (
                    how.boat.position.distance_to(jetty) < 1.5
                    and how.boat.speed < WorldScript.DOCK_SPEED
                ),
                (
                    "%s: the boat comes to the jetty slowly enough to dock (%.1f m away, %.1f m/s)"
                    % [where, how.boat.position.distance_to(jetty), how.boat.speed]
                )
            )
        "choose":
            _check(how.chosen >= 1, "%s: the hand chooses the card" % where)
    if id == "pair":
        _check(golden, "%s: the oars shine gold when the two row in time" % where)


## How far the boat of [param how] turned by steering on the last step, in degrees.
static func _turn_step(how: HowTo) -> float:
    var boat := how.boat
    var turning := clampf(
        RowBoat.TURN_STILL + boat.speed / RowBoat.TURN_FULL_SPEED, RowBoat.TURN_STILL, 1.0
    )
    return boat.steer * RowBoat.TURN_DEGREES * turning * boat.turn_share * STEP


## The rower [param who] stays inside the camera picture.
func _check_inside(how: HowTo, data: Dictionary, t: float, who: int, where: String) -> void:
    var height := HowTo.FRAME.size.y * (1.0 if how.players == 1 else 0.92)
    var center := how._center(who)
    var pose := how.pose(data, t, who)
    var at := HowToFigure.joints(center, height, pose)
    if Pictures.of("how_to", "ylva_rest") != null:
        _check(
            HowToFigure.painted_pose(pose, who)[0] != "",
            "%s: the rower %d is painted in the pose %s" % [where, who, pose]
        )
    var points: Array = [at["head"] - Vector2(0, HowToFigure.HEAD * height)]
    points.append_array(at["wrists"])
    points.append_array(at["elbows"])
    for point: Vector2 in points:
        _check(
            Rect2(Vector2.ZERO, HowTo.FRAME.size).has_point(point),
            "%s: the rower stays in the camera picture at %.1f s: %s" % [where, t, point]
        )
