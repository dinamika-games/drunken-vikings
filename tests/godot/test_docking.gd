extends SceneTree

## Check the docking of the practical mode (see World): the boat which leaves a
## jetty does not dock there again at once, while it still glides at the
## jetty, but the players who row out a stroke, turn and row back dock there
## again, without visiting another place first.
##
## $GODOT --headless --path . --script tests/godot/test_docking.gd -- --no-camera

const WorldScript := preload("res://scenes/world/world.gd")

const DELTA := 1.0 / 60.0

## The saves of the test, apart from the journeys of the players.
const DIRECTORY := "user://test_docking"

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


## Let the world play for [param seconds] (or until the boat docks, if
## [param until_docked]).
func _play(world: Node, seconds: float, until_docked := false) -> void:
    var t := 0.0
    while t < seconds:
        world._process(DELTA)
        if until_docked and world._mode != "rowing":
            return
        t += DELTA


## Leave the place [param id], row out a stroke, turn, row back a stroke and
## glide to its jetty.
func _leave_and_come_back(world: Node, id: String) -> void:
    var state: Node = world.state()
    var boat: RowBoat = world.boat()
    var place: Dictionary = world.map().place(id)
    var jetty: Vector2 = place["jetty"]

    world.undock(id)
    _check(world._mode == "rowing", "%s: the boat is on the water after leaving" % id)

    # The boat which just left glides slowly at the jetty: it must not dock
    # again at once.
    _play(world, 20.0)
    _check(
        world._mode == "rowing",
        "%s: the boat does not dock again while it glides at the jetty" % id
    )

    # Out a stroke, until the boat lies nearly still.
    boat.stroke()
    _play(world, 15.0)
    var out := boat.position.distance_to(jetty)
    _check(
        world._mode == "rowing" and out > WorldScript.DOCK_DISTANCE,
        "%s: a stroke takes the boat out of reach of the jetty: %.0f m" % [id, out]
    )

    # Turn to the berth and row back a stroke: the boat glides to the jetty.
    boat.heading = (Vector2(place["berth"]) - boat.position).angle() + PI / 2.0
    boat.speed = 0.0
    boat.stroke()
    _play(world, 30.0, true)
    _check(
        world._mode == "port" and state.place == id,
        (
            (
                "%s: the boat rowed out %.0f m and back docks there again "
                + "(mode %s, place %s, %.0f m from the jetty)"
            )
            % [id, out, world._mode, state.place, boat.position.distance_to(jetty)]
        )
    )


func _run() -> void:
    var state: Node = root.get_node("/root/GameState")
    _check(state.error == "", "the data loads: " + state.error)
    state.saves_dir = DIRECTORY
    state.settings_path = DIRECTORY + "/settings.cfg"
    state.save_path = DIRECTORY + "/voyage.json"
    DirAccess.remove_absolute(state.save_path)
    state.new_voyage()

    # NOTE: The test hears nothing: the sounds which play while the test
    # computes the frames itself would stay with the audio server at exit.
    root.get_node("/root/AudioService")._muted = true
    var world: Node = load("res://scenes/world/world.tscn").instantiate()
    root.add_child(world)
    # NOTE (mristin):
    # The test plays the world itself, frame by frame; the skippers stay
    # where they are and hail nobody, so that only the docking counts.
    world.process_mode = Node.PROCESS_MODE_DISABLED
    for npc: NpcBoat in world.npcs():
        npc.cooldown = INF

    # The farm (as in the first mission, the voyage starts at home), and a
    # market: the boat docks again at any place it left.
    for id in ["home", "market"]:
        _leave_and_come_back(world, id)

    world.free()
    root.get_node("/root/AudioService").silence()
    DirAccess.remove_absolute(state.save_path)
    DirAccess.remove_absolute(state.settings_path)
    DirAccess.remove_absolute(DIRECTORY)
    print("PASS test_docking" if _failures == 0 else "FAIL test_docking (%d)" % _failures)
    quit(0 if _failures == 0 else 1)
