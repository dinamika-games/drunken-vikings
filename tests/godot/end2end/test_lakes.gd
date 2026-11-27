extends "res://tests/godot/end2end/playthrough.gd"
## The end-to-end test of the Home Lakes (see playthrough.gd):
##
## 1. At the very first start, the players choose their language, start a new
##    journey with one rower, watch How to play, and row to the farm.
## 2. The bot does the first tasks, one after the other (see lakes_bot.gd),
##    with its detours; then Escape twice ends the journey.
## 3. A second journey with two rowers, who row an oar each, sees How to play
##    for two, does its first task; then the players delete it, in three steps.
## 4. The first journey goes on: the voyage comes back from the disk as it
##    was left, and the bot does one more task (or rows home, if all are done).
##
## $GODOT --headless --fixed-fps 60 --path . \
##     --script tests/godot/end2end/test_lakes.gd -- --no-camera
##
## Pass -- --tasks=<n> for more or fewer tasks.

## How many tasks the first journey does on the lakes.
const DEFAULT_TASKS := 40

## The first journey, and what of it was saved when the players left it.
var _first := ""
var _left := {}


func mode() -> String:
    return "lakes"


func heard() -> Array:
    return ["click", "oar", "dock", "coins", "hooray", "bell"]


func default_wall_seconds() -> float:
    return 600.0


func play_mode() -> void:
    for phase in [_first_journey, _lakes, _second_journey, _back]:
        if aborted():
            break
        await phase.call()


func _first_journey() -> void:
    print("1. A new journey with one rower")
    await first_journey(["Girl", "Fair", "Red", "Green"])
    await choose("The farm")
    await wait_for_scene(WORLD)


func _lakes() -> void:
    var tasks := int(argument("tasks", str(DEFAULT_TASKS)))
    print("2. The Home Lakes, %d tasks" % tasks)
    await play_lakes(tasks)
    _first = voyage().journey_id
    _left = await leave_lakes()


func _second_journey() -> void:
    print("3. A second journey with two rowers")
    var state := voyage()
    await choose("+ New journey")
    await choose("Two rowers")
    check(fake.players == 2, "the camera follows two players")
    await choose_look(["Girl", "Dark", "Brown", "Blue", "Boy", "Fair", "Red", "Green"])
    check(
        (
            voyage().look(0) == {"figure": "girl", "skin": 4, "hair": 2, "clothes": 2}
            and voyage().look(1) == {"figure": "boy", "skin": 0, "hair": 1, "clothes": 4}
        ),
        "the two rowers look as chosen"
    )
    await how_to(2)
    await choose("The farm")
    if aborted() or not await wait_for_scene(WORLD):
        return
    check(state.day == 1 and state.missions.done.is_empty(), "a new journey starts afresh")
    await play_lakes(1)
    var second: String = state.journey_id
    var second_name := Grammar.text(
        "{journey} (2 rowers)", {"journey": Grammar.raw(state.journey_name)}
    )
    await leave_lakes()
    await delete_journey(second, second_name)


func _back() -> void:
    print("4. The first journey goes on")
    var state := voyage()
    await go_on(_first)
    check(fake.players == 1, "the first journey has one rower again")
    check(
        voyage().look(0) == {"figure": "girl", "skin": 0, "hair": 1, "clothes": 4},
        "the first journey keeps how its rower looks"
    )
    await choose("The farm")
    if aborted() or not await wait_for_scene(WORLD):
        return
    var back := snapshot(state)
    for key in _left:
        check(
            JSON.stringify(_left[key]) == JSON.stringify(back[key]),
            "the journey comes back as it was left: %s" % key
        )
    if state.missions.available().is_empty() and state.missions.active.is_empty():
        await row_to("home")
    else:
        await play_lakes(state.missions.done.size() + 1)
    await leave_lakes()
