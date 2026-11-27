extends SceneTree

## Closing the window saves the voyage, in the world, the party and the chase.
##
## Closing the window quits the game, so the test runs each scene in a Godot of
## its own (with -- --scene=<name>): it starts a journey, plays the scene for a
## moment, puts 5 silver more in the purse (as the treats of the party do),
## and closes the window; the test then reads the save which it left.
##
## $GODOT --headless --path . --script tests/godot/test_close.gd -- --no-camera

const SCENES := {
    "world": "res://scenes/world/world.tscn",
    "party": "res://scenes/level/level.tscn",
    "chase": "res://scenes/chase/chase.tscn",
}

const DIRECTORY := "user://test_close"

## The silver which the scene adds before the window closes.
const GAINED := 5

## The frames which a scene plays before the window closes, and which it may
## take to quit after.
const FRAMES := 30

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _argument(name: String) -> String:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--%s=" % name):
            return arg.trim_prefix("--%s=" % name)
    return ""


func _run() -> void:
    var scene := _argument("scene")
    if scene != "":
        await _close(scene)
        return
    for name: String in SCENES:
        _check_scene(name)
    print("PASS test_close" if _failures == 0 else "FAIL test_close (%d)" % _failures)
    quit(0 if _failures == 0 else 1)


## In a Godot of its own: play the [param scene] and close the window.
func _close(scene: String) -> void:
    var state: Node = root.get_node("/root/GameState")
    var dir := DIRECTORY.path_join(scene)
    DirAccess.make_dir_recursive_absolute(dir)
    for file in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute(dir.path_join(file))
    state.saves_dir = dir
    state.settings_path = dir.path_join("settings.cfg")
    state.new_journey(1)
    change_scene_to_file(SCENES[scene])
    for i in range(FRAMES):
        await process_frame
    state.silver += GAINED
    current_scene.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
    for i in range(FRAMES):
        await process_frame
    print("FAIL: closing the window does not quit the %s" % scene)
    quit(1)


## Run the [param scene] in a Godot of its own, and check what it saved.
func _check_scene(scene: String) -> void:
    var output: Array = []
    var args := [
        "--headless",
        "--path",
        ProjectSettings.globalize_path("res://"),
        "--script",
        "res://tests/godot/test_close.gd",
        "--",
        "--no-camera",
        "--scene=" + scene,
    ]
    var code := OS.execute(OS.get_executable_path(), args, output, true)
    var log: String = "\n".join(output)
    _check(code == 0, "the %s quits when the window closes (exit code %d)" % [scene, code])
    _check(not "SCRIPT ERROR" in log, "the %s closes without an error" % scene)
    var dir := DIRECTORY.path_join(scene)
    var saves := Array(DirAccess.get_files_at(dir)).filter(
        func(file: String) -> bool: return file.ends_with(".json")
    )
    _check(saves.size() == 1, "the %s leaves one journey" % scene)
    if saves.size() != 1:
        print(log)
        return
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(saves[0])))
    _check(data is Dictionary, "the save of the %s is whole" % scene)
    if not data is Dictionary:
        return
    _check(
        int(data.get("silver", -1)) == GameState.START_SILVER + GAINED,
        "closing the window in the %s saves the purse (%s silver)" % [scene, data.get("silver")]
    )
    if scene == "world":
        _check(
            data.get("place", "") == "" and data.get("boat", null) is Dictionary,
            "closing the window on the water saves where the boat is"
        )
    if _failures > 0:
        print(log)
