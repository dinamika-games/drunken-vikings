extends SceneTree

## Check the rowing of the boat with one and with two players (see RowBoat):
## run with [code]$GODOT --headless --path . --script tests/godot/test_row_boat.gd[/code].

const DELTA := 1.0 / 60.0

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


## A lake of open water, 2 km on each side, with the boat in its middle.
func _lake() -> LakeMap:
    var map := LakeMap.new()
    map.water = [
        {
            "outer":
            PackedVector2Array(
                [Vector2(0, 0), Vector2(2000, 0), Vector2(2000, 2000), Vector2(0, 2000)]
            ),
            "holes": []
        }
    ]
    return map


func _boat() -> RowBoat:
    var boat := RowBoat.new()
    boat.position = Vector2(1000, 1000)
    return boat


## Row for [param seconds]: a stroke of each side at the times of [param left]
## and [param right] (in seconds, in the order of time).
func _row(boat: RowBoat, map: LakeMap, seconds: float, left: Array, right: Array) -> void:
    var t := 0.0
    while t < seconds:
        if not left.is_empty() and t >= left[0]:
            left.pop_front()
            boat.stroke_side(0)
        if not right.is_empty() and t >= right[0]:
            right.pop_front()
            boat.stroke_side(1)
        boat.move(DELTA, map)
        t += DELTA


func _initialize() -> void:
    var map := _lake()

    var together := _boat()
    _row(together, map, 12.0, [0.0, 3.0, 6.0, 9.0], [0.0, 3.0, 6.0, 9.0])
    _check(absf(together.heading) < 0.01, "In time, the boat goes straight: %f" % together.heading)
    _check(together.since_in_time < 4.0, "The strokes in time are noticed")

    var out_of_time := _boat()
    _row(out_of_time, map, 12.0, [0.0, 3.0, 6.0, 9.0], [1.5, 4.5, 7.5, 10.5])
    _check(
        absf(out_of_time.heading) < deg_to_rad(30.0),
        "Out of time, the boat wobbles but keeps its way: %f" % out_of_time.heading
    )
    _check(
        (
            together.position.distance_to(Vector2(1000, 1000))
            > out_of_time.position.distance_to(Vector2(1000, 1000))
        ),
        "Rowing in time goes farther"
    )

    var left_stronger := _boat()
    _row(left_stronger, map, 12.0, [0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0], [0.0, 6.0])
    _check(
        left_stronger.heading > deg_to_rad(45.0),
        "A stronger left rower turns the boat right: %f" % left_stronger.heading
    )

    var right_stronger := _boat()
    _row(right_stronger, map, 12.0, [0.0, 6.0], [0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0])
    _check(
        right_stronger.heading < -deg_to_rad(45.0),
        "A stronger right rower turns the boat left: %f" % right_stronger.heading
    )

    var alone := _boat()
    alone.stroke()
    alone.steer = 1.0
    for i in range(60):
        alone.move(DELTA, map)
    _check(
        alone.heading > deg_to_rad(45.0) and alone.heading < deg_to_rad(120.0),
        "Alone, the head steers: %f" % alone.heading
    )

    _check_oars(map)
    # NOTE (mristin):
    # The map is a node, not counted by references: free it, or it outlives
    # the test with its shader and textures.
    map.free()

    if _failures.is_empty():
        print("PASS test_row_boat")
    quit(1 if not _failures.is_empty() else 0)


## The oars never jump: strokes faster than the pull speed the oar up, and the
## oars which follow the players move smoothly with them.
func _check_oars(map: LakeMap) -> void:
    for pair in [false, true]:
        var boat := _boat()
        var rower := RowerView.new()
        rower.boat = boat
        rower.pair = pair
        var strokes := [0.0, 0.3, 0.5, 2.0, 2.2, 2.4, 2.6, 5.0]
        var t := 0.0
        var biggest := 0.0
        var catches := 0
        while t < 8.0:
            if not strokes.is_empty() and t >= strokes[0]:
                strokes.pop_front()
                if pair:
                    boat.stroke_side(0)
                    boat.stroke_side(1)
                else:
                    boat.stroke()
            boat.move(DELTA, map)
            var before := rower.swing_of(0)
            rower._process(DELTA)
            biggest = maxf(biggest, absf(rower.swing_of(0) - before))
            catches += 1 if rower.catches[0] else 0
            t += DELTA
        # NOTE (mristin):
        # Even in a hurry, the oar moves at most a small step in a frame.
        _check(biggest < 0.35, "The oar never jumps (pair %s): %f in a frame" % [pair, biggest])
        _check(catches == 8, "Every stroke is pulled through (pair %s): %d" % [pair, catches])
        rower.free()

    var follower := RowerView.new()
    follower.boat = _boat()
    var biggest := 0.0
    var catches := 0
    for i in range(240):
        var pull := 0.5 - 0.5 * cos(i * DELTA * TAU / 2.5)
        follower.live_pull = [pull, pull]
        var before := follower.swing_of(0)
        follower._process(DELTA)
        biggest = maxf(biggest, absf(follower.swing_of(0) - before))
        catches += 1 if follower.catches[0] else 0
    _check(biggest < 0.2, "The oar follows the player smoothly: %f in a frame" % biggest)
    _check(
        absf(follower.swing_of(0) - lerpf(-1.0, 1.0, follower.live_pull[0])) < 0.3,
        "The oar is where the player is"
    )
    _check(catches >= 1, "Following the player, the blade dips in: %d" % catches)
    follower.free()
