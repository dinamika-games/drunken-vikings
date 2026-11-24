extends SceneTree

## The journeys of GameState: new ones, the list (the last played first),
## going on with one, and deleting one.
##
## $GODOT --headless --path . --script tests/godot/test_journeys.gd -- --no-camera

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _run() -> void:
    var state: Node = root.get_node("/root/GameState")
    var dir := "user://test_journeys"
    for file in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute(dir + "/" + file)
    state.saves_dir = dir
    state.settings_path = dir + "/settings.cfg"

    state.new_journey(2)
    var first: String = state.journey_id
    state.silver = 77
    state.save()
    _check(state.journeys().size() == 1, "one journey after the first")
    _check(state.last_journey() == first, "the first journey is the last one")

    # NOTE (mristin):
    # The ids are the date and the time to the second; wait for a new one (on
    # the wall clock: a timer of the game may fire early after a slow frame).
    var started := Time.get_datetime_string_from_system()
    while Time.get_datetime_string_from_system() == started:
        await process_frame
    state.new_journey(1)
    var second: String = state.journey_id
    _check(second != first, "a new journey has a new id")
    _check(state.silver == GameState.START_SILVER, "a new journey starts afresh")
    var listed: Array = state.journeys()
    _check(listed.size() == 2, "two journeys")
    _check(listed[0]["id"] == second, "the last played comes first")
    _check(int(listed[0]["players"]) == 1, "the second journey has one rower")

    _check(state.open_journey(first), "the first journey opens")
    _check(state.silver == 77, "the first journey keeps its silver")
    _check(state.players == 2, "the first journey keeps its two rowers")
    _check(state.last_journey() == first, "the opened journey is the last one")

    state.delete_journey(second)
    _check(state.journeys().size() == 1, "one journey after deleting")
    _check(not state.open_journey(second), "a deleted journey does not open")

    print("PASS test_journeys" if _failures == 0 else "FAIL test_journeys (%d)" % _failures)
    quit(0 if _failures == 0 else 1)
