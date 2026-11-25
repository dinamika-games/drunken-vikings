extends SceneTree

## Check that the skippers keep clear of the players' boat (see NpcBoat): they
## turn aside or wait, and still come to where they sail.
##
## $GODOT --headless --path . --script tests/godot/test_npc_boat.gd -- --no-camera

const DELTA := 1.0 / 30.0

## The skipper never comes closer to the players than this, in metres between
## the middle lines of the boats (a little less than NpcBoat.CLEARANCE, for
## the turn and the slowing down).
const NEVER_CLOSER := 8.0

var _failures: Array[String] = []

## The nodes made, to free them at the end.
var _made: Array[Node] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


## A lake of open water, 2 km on each side, with two places on its west and
## east shores and a straight way between their berths.
func _lake() -> LakeMap:
    var map := LakeMap.new()
    _made.append(map)
    map.water = [
        {
            "outer":
            PackedVector2Array(
                [Vector2(0, 0), Vector2(2000, 0), Vector2(2000, 2000), Vector2(0, 2000)]
            ),
            "holes": []
        }
    ]
    map.places = [
        {
            "id": "west",
            "at": Vector2(-50, 1000),
            "jetty": Vector2(-20, 1000),
            "berth": Vector2(400, 1000)
        },
        {
            "id": "east",
            "at": Vector2(2050, 1000),
            "jetty": Vector2(2020, 1000),
            "berth": Vector2(1000, 1000)
        },
    ]
    map.routes = {"west|east": PackedVector2Array([Vector2(400, 1000), Vector2(1000, 1000)])}
    return map


func _skipper(map: LakeMap, players: RowBoat, length: float) -> NpcBoat:
    var npc := NpcBoat.new()
    _made.append(npc)
    npc.setup(map, "west", {"name": "Test"}, 7)
    npc.players = players
    npc.players_length = length
    return npc


## How far apart the middle lines of the skipper's and the players' boats are.
func _gap(npc: NpcBoat, players: RowBoat, length: float) -> float:
    var ahead := Vector2.UP.rotated(npc.heading) * NpcBoat.LENGTH / 2.0
    var theirs := players.forward() * length / 2.0
    var closest := Geometry2D.get_closest_points_between_segments(
        npc.position - ahead,
        npc.position + ahead,
        players.position - theirs,
        players.position + theirs
    )
    return closest[0].distance_to(closest[1])


## How far apart the middle lines of the skipper's boat and of a boat of the
## [param length] lying [param at], heading [param heading], are.
func _gap_at(npc: NpcBoat, at: Vector2, heading: float, length: float) -> float:
    var ahead := Vector2.UP.rotated(npc.heading) * NpcBoat.LENGTH / 2.0
    var theirs := Vector2.UP.rotated(heading) * length / 2.0
    var closest := Geometry2D.get_closest_points_between_segments(
        npc.position - ahead, npc.position + ahead, at - theirs, at + theirs
    )
    return closest[0].distance_to(closest[1])


## Sail the skipper for [param seconds] (the players' boat glides as it goes);
## return the closest the boats came, and whether the skipper arrived.
func _sail(
    npc: NpcBoat, players: RowBoat, map: LakeMap, length: float, seconds: float
) -> Dictionary:
    var closest := INF
    var arrived := false
    var sailed := false
    var t := 0.0
    while t < seconds:
        npc._process(DELTA)
        players.move(DELTA, map)
        closest = minf(closest, _gap(npc, players, length))
        _check(map.is_water(npc.position), "the skipper stays on the water: %s" % npc.position)
        sailed = sailed or npc.sailing()
        if sailed and not npc.sailing():
            arrived = true
            break
        t += DELTA
    return {"closest": closest, "arrived": arrived, "at": npc.position}


func _initialize() -> void:
    var map := _lake()

    # The players lie still across the way, in the small boat and in the longship.
    for length: float in [RowerView.HULL_LENGTH, 52.5]:
        var players := RowBoat.new()
        players.position = Vector2(700, 1000)
        players.heading = 0.0
        var npc := _skipper(map, players, length)
        var result := _sail(npc, players, map, length, 300.0)
        _check(
            result["closest"] >= NEVER_CLOSER,
            (
                "the skipper passes the still boat (%.1f m long) clear: %.1f m"
                % [length, result["closest"]]
            )
        )
        _check(
            result["arrived"], "the skipper still arrives past the still boat: %s" % result["at"]
        )

    # The players row slowly towards the skipper on the way.
    var players := RowBoat.new()
    players.position = Vector2(900, 1000)
    players.heading = -PI / 2.0
    var npc := _skipper(map, players, RowerView.HULL_LENGTH)
    npc._wait = DELTA / 2.0
    var t := 0.0
    var closest := INF
    while t < 120.0:
        if fmod(t, 1.0) < DELTA:
            players.speed = 3.0
        npc._process(DELTA)
        players.move(DELTA, map)
        closest = minf(closest, _gap(npc, players, RowerView.HULL_LENGTH))
        t += DELTA
    _check(closest >= NEVER_CLOSER, "the skipper passes the oncoming boat clear: %.1f m" % closest)

    # The skipper finds itself too close beside the players' boat, which
    # glides slowly towards its side, while it turns about to pass behind the
    # boat (as the end-to-end test once saw, see NpcBoat._look): on every
    # step, it sails no closer to where the boat lay a step before (the boat
    # may come closer itself, as the contracts of the end-to-end test allow).
    for glide: float in [0.0, 0.7, 1.35, 1.9]:
        for side: float in [-1.0, 1.0]:
            for shift: float in [-1.0, 0.0, 1.0]:
                players = RowBoat.new()
                players.position = Vector2(680.3, 780.6 + shift)
                players.heading = deg_to_rad(-110.0)
                players.speed = glide
                npc = _skipper(map, players, 6.4)
                npc._path = PackedVector2Array([Vector2(655, 780), Vector2(400, 780)])
                npc._index = 0
                npc._wait = 0.0
                npc._off_route = true
                npc.position = Vector2(677.7, 787.7)
                npc.heading = deg_to_rad(96.0)
                npc._course = Vector2(0.984, -0.179)
                npc._speed = 4.08
                npc._swerve_side = side
                var worst := 0.0
                var worst_before := 0.0
                for i in range(int(3.0 / DELTA)):
                    var lay := Vector2(players.position)
                    var lay_heading := players.heading
                    var before := _gap_at(npc, lay, lay_heading, 6.4)
                    npc._process(DELTA)
                    players.move(DELTA, map)
                    var after := _gap_at(npc, lay, lay_heading, 6.4)
                    if after - before < worst - worst_before:
                        worst = after
                        worst_before = before
                var what := (
                    "the skipper beside the gliding boat (%.2f m/s, to %+.0f, %+.0f m)"
                    % [glide, side, shift]
                )
                _check(
                    worst >= worst_before - 0.01,
                    "%s sails into where it lay: %.3f m to %.3f m" % [what, worst_before, worst]
                )

    # The players lie at the berth where the skipper arrives: the skipper moors
    # beside them.
    players = RowBoat.new()
    players.position = Vector2(1000, 1000)
    npc = _skipper(map, players, 37.5)
    var result := _sail(npc, players, map, 37.5, 300.0)
    _check(
        result["closest"] >= NEVER_CLOSER,
        "the skipper moors clear of the players: %.1f m" % result["closest"]
    )
    _check(
        result["arrived"], "the skipper moors beside the players at the berth: %s" % result["at"]
    )

    # The players come to lie on the moored skipper: the skipper makes room.
    players = RowBoat.new()
    npc = _skipper(map, players, 28.0)
    players.position = npc.position
    npc._wait = 1000.0
    for i in range(int(20.0 / DELTA)):
        npc._process(DELTA)
    _check(
        _gap(npc, players, 28.0) >= NpcBoat.CLEARANCE - 0.5,
        "the moored skipper makes room: %.1f m" % _gap(npc, players, 28.0)
    )

    for node in _made:
        node.free()
    print(
        (
            "PASS test_npc_boat"
            if _failures.is_empty()
            else "FAIL test_npc_boat (%d)" % _failures.size()
        )
    )
    quit(0 if _failures.is_empty() else 1)
