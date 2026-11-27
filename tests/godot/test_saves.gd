extends SceneTree

## The saves of GameState: the boat on the water comes back where it was, and
## no crash, cut write or failed write leaves a broken save behind.
##
## $GODOT --headless --path . --script tests/godot/test_saves.gd -- --no-camera

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _write(path: String, text: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()


func _parses(path: String) -> bool:
    return JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary


func _run() -> void:
    var state: Node = root.get_node("/root/GameState")
    var dir := "user://test_saves"
    DirAccess.make_dir_recursive_absolute(dir)
    for file in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute(dir + "/" + file)
    for sub in DirAccess.get_directories_at(dir):
        DirAccess.remove_absolute(dir + "/" + sub)
    state.saves_dir = dir
    state.settings_path = dir + "/settings.cfg"

    state.new_journey(1)
    var id: String = state.journey_id
    var path: String = state.save_path
    var temporary := path + ".tmp"

    # The boat on the water.
    state.place = ""
    state.boat_at = Vector2(123.5, -456.25)
    state.boat_heading = 1.25
    state.silver = 31
    _check(state.save(), "the voyage saves on the water")
    _check(not FileAccess.file_exists(temporary), "a save leaves no temporary file")
    state.new_voyage()
    _check(state.open_journey(id), "the voyage saved on the water opens")
    _check(state.place == "", "the boat is still on the water")
    _check(state.boat_at == Vector2(123.5, -456.25), "the boat is where it was")
    _check(is_equal_approx(state.boat_heading, 1.25), "the boat heads where it headed")
    _check(state.silver == 31, "the purse is kept")

    # A save from before the format 3 says no more than "on the water".
    var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
    old.erase("boat")
    old["format"] = 2
    _write(path, JSON.stringify(old))
    _check(state.load_voyage(), "an old save on the water loads")
    _check(state.place == "home", "an old save on the water starts at home")

    # Autosave after autosave, the save is always whole.
    state.place = ""
    for i in range(50):
        state.boat_at = Vector2(i, i)
        state.save()
        _check(_parses(path), "autosave %d is whole" % i)
    _check(not FileAccess.file_exists(temporary), "the autosaves leave no temporary file")
    _check(state.load_voyage() and state.boat_at == Vector2(49, 49), "the last autosave wins")

    # A crash cut the temporary file short: the save before stays.
    var whole := FileAccess.get_file_as_string(path)
    _write(temporary, whole.substr(0, whole.length() / 2))
    _check(state.load_voyage(), "a cut temporary file does not spoil the save")
    _check(state.boat_at == Vector2(49, 49), "the save before the cut one stays")
    _check(not FileAccess.file_exists(temporary), "a cut temporary file is dropped")
    _write(temporary, whole.substr(0, whole.length() - 1))
    _check(state.journeys().size() == 1, "a cut temporary file is no journey")
    _check(not FileAccess.file_exists(temporary), "the list of journeys drops a cut file")

    # A crash after writing the temporary file but before the rename (e.g., on
    # Windows, between removing the old save and renaming the new one).
    state.boat_at = Vector2(7, 8)
    var newer: Dictionary = JSON.parse_string(whole)
    newer["boat"] = {"x": 7.0, "y": 8.0, "heading": 0.5}
    _write(temporary, JSON.stringify(newer, "  "))
    DirAccess.remove_absolute(path)
    _check(state.journeys().size() == 1, "the journey is listed though its save was gone")
    _check(state.open_journey(id), "the journey opens from the whole temporary file")
    _check(state.boat_at == Vector2(7, 8), "the newest save wins")
    _check(not FileAccess.file_exists(temporary), "the temporary file became the save")

    # A write which fails leaves the save as it was.
    var before := FileAccess.get_file_as_string(path)
    DirAccess.make_dir_absolute(temporary)
    state.boat_at = Vector2(9, 9)
    _check(not state.save(), "a save which cannot write says so")
    _check(FileAccess.get_file_as_string(path) == before, "a failed save keeps the save")
    DirAccess.remove_absolute(temporary)
    _check(state.save() and _parses(path), "the next save works again")

    print("PASS test_saves" if _failures == 0 else "FAIL test_saves (%d)" % _failures)
    quit(0 if _failures == 0 else 1)
