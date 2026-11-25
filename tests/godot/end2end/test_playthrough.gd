extends "res://tests/godot/end2end/lakes_bot.gd"
## Play the game from the first screen on, as the players do (only with the
## camera, see fake_vision.gd), much faster than in real time, and check its
## contracts on every frame (see contracts.gd): a property-based test, whose
## random choices come from a seed.
##
## 1. A new journey with one rower: How to play, then the party behind the
##    wedding longship, to its end, and then to the farm.
## 2. The Home Lakes: the bot does the first tasks, one after the other (see
##    lakes_bot.gd), with its detours; then Escape twice ends the journey.
## 3. The journey goes on with How to play again, then the chase: the bot rows
##    away from the pirates to the town, and back to the start.
## 4. A second journey with two rowers, who row an oar each, sees How to play
##    for two, does its first task; then the players delete it, in three steps.
## 5. The first journey goes on: the voyage comes back from the disk as it
##    was left, and the bot does one more task (or rows home, if all are done).
##
## All the way, the game must never log an error (e.g., a sound which is not
## there), the music must fit where the players are, and the players must never
## get stuck: every screen lets them go on, every card they hold is chosen,
## every way leads to its jetty, and every task gets done.
##
## $GODOT --headless --fixed-fps 60 --path . \
##     --script tests/godot/end2end/test_playthrough.gd -- --no-camera
##
## Pass -- --seed=<n> to try other choices, --tasks=<n> for more or fewer
## tasks, --time-scale=<x> for another speed of the game, --draw-every=<n> to
## draw more or less often, and --wall-seconds=<s> for another limit of the
## wall clock. The test keeps its journeys in user://tests/playthrough (a
## directory for each seed, so that several seeds may run at once), and
## leaves the players' alone.

const DIRECTORY := "user://tests/playthrough"

## How many tasks the first journey does on the lakes.
const DEFAULT_TASKS := 40

## How long the party and the chase may take, in seconds of the game.
const PARTY_SECONDS := 900.0
const CHASE_SECONDS := 600.0

## The sounds which the players hear in every playthrough (see Audio).
const HEARD := [
    "click", "oar", "dock", "coins", "hooray", "bell", "horn", "pickup", "coin", "pirates", "jingle"
]

## How long the players watch How to play, in seconds of the game.
const HOW_TO_SECONDS := 20.0

## How often the players try the chase before they make it.
const CHASES := 3

## The first journey, and what of it was saved when the players left it.
var _first := ""
var _left := {}


func _play() -> void:
    var state := voyage()
    # NOTE: A directory for each seed, so that several seeds may run at once.
    var directory := "%s/seed_%s" % [DIRECTORY, argument("seed", str(DEFAULT_SEED))]
    _clean(directory)
    state.saves_dir = directory + "/saves"
    state.settings_path = directory + "/settings.cfg"
    state.save_path = directory + "/none.json"
    DirAccess.make_dir_recursive_absolute(state.saves_dir)
    for phase in [_new_journey, _lakes, _chase_phase, _second_journey, _back]:
        if aborted():
            break
        await phase.call()
    print("Did: %s" % did)
    var heard := Audio.played()
    print("Heard: %s" % heard)
    for sound in HEARD:
        check(heard.has(sound), "the players hear the sound %s" % sound)
    print(
        (
            "%d tasks done with %d stars on day %d, %d silver, the ship %s, %d legs"
            % [
                state.missions.done.size(),
                state.missions.stars(),
                state.day,
                state.silver,
                state.ships.current,
                _legs_done
            ]
        )
    )
    _clean(directory)


func _new_journey() -> void:
    print("1. A new journey with one rower, and the party")
    change_scene_to_file(START)
    if not await wait_for_scene(START):
        return
    await play_for(0.5)
    check(
        panel() != null and panel().title == "A new journey",
        "without a journey, the game starts a new one"
    )
    await choose("One rower")
    check(fake.players == 1, "the camera follows one player")
    # NOTE: A detour: Back from the second screen of the looks, and on.
    await choose("Boy")
    await choose("Back")
    await _choose_look(["Boy", "Tan", "Black", "Red"])
    check(
        voyage().look(0) == {"figure": "boy", "skin": 2, "hair": 4, "clothes": 3},
        "the rower looks as chosen"
    )
    await _how_to(1)
    party_silver = voyage().silver
    await choose("Party!")
    await _party()
    await choose("To the farm")
    await wait_for_scene(WORLD)


## Choose how the rowers look: the cards [param titles], one per screen.
func _choose_look(titles: Array) -> void:
    for title in titles:
        if aborted():
            return
        await choose(title)


func _lakes() -> void:
    var tasks := int(argument("tasks", str(DEFAULT_TASKS)))
    print("2. The Home Lakes, %d tasks" % tasks)
    await play_lakes(tasks)
    _first = voyage().journey_id
    await _leave_lakes()


func _chase_phase() -> void:
    print("3. The chase")
    await _go_on(_first)
    # A detour: How to play again, from the choice of what to play.
    await choose("How to play")
    await _how_to(1)
    # And another: a new colour of the hair.
    await choose("Your vikings")
    await _choose_look(["Boy", "Tan", "Brown", "Red"])
    check(voyage().look(0)["hair"] == 2, "the rower changes how they look")
    await choose("Chase!")
    await _chase()
    _left = _snapshot(voyage())


func _second_journey() -> void:
    print("4. A second journey with two rowers")
    var state := voyage()
    await choose("+ New journey")
    await choose("Two rowers")
    check(fake.players == 2, "the camera follows two players")
    await _choose_look(["Girl", "Dark", "Brown", "Blue", "Boy", "Fair", "Red", "Green"])
    check(
        (
            voyage().look(0) == {"figure": "girl", "skin": 4, "hair": 2, "clothes": 2}
            and voyage().look(1) == {"figure": "boy", "skin": 0, "hair": 1, "clothes": 4}
        ),
        "the two rowers look as chosen"
    )
    await _how_to(2)
    await choose("The farm")
    if aborted() or not await wait_for_scene(WORLD):
        return
    check(state.day == 1 and state.missions.done.is_empty(), "a new journey starts afresh")
    await play_lakes(1)
    var second: String = state.journey_id
    var second_name := "%s (2 rowers)" % state.journey_name
    await _leave_lakes()
    await _delete(second, second_name)


func _back() -> void:
    print("5. The first journey goes on")
    var state := voyage()
    await _go_on(_first)
    check(fake.players == 1, "the first journey has one rower again")
    check(
        voyage().look(0) == {"figure": "boy", "skin": 2, "hair": 2, "clothes": 3},
        "the first journey keeps how its rower looks"
    )
    await choose("The farm")
    if aborted() or not await wait_for_scene(WORLD):
        return
    var back := _snapshot(state)
    for key in _left:
        check(
            JSON.stringify(_left[key]) == JSON.stringify(back[key]),
            "the journey comes back as it was left: %s" % key
        )
    if state.missions.available().is_empty() and state.missions.active.is_empty():
        await row_to("home")
    else:
        await play_lakes(state.missions.done.size() + 1)
    await _leave_lakes()


## How to play shows for the [param players]: watch some of its parts, then
## hold the hand on Ready!.
func _how_to(players: int) -> void:
    if aborted():
        return
    await frame()
    var found := current_scene.find_children("*", "HowTo", true, false)
    check(found.size() == 1, "how to play shows")
    if found.is_empty():
        return
    var how: HowTo = found[0]
    check(how.players == players, "how to play shows the parts for %d rowers" % players)
    var parts := {}
    var until := clock + HOW_TO_SECONDS
    while clock < until and not aborted():
        parts[how.part] = true
        await frame()
    check(parts.size() > 2, "how to play goes from part to part")
    tally("how to play")
    await choose("Ready!")
    await play_for(0.5)
    check(
        panel() != null and panel().title == "What do you play?",
        "after how to play, the players choose what they play"
    )


## Remove the [param directory] with everything in it.
static func _clean(directory: String) -> void:
    if not DirAccess.dir_exists_absolute(directory):
        return
    for sub in DirAccess.get_directories_at(directory):
        _clean(directory.path_join(sub))
    for file in DirAccess.get_files_at(directory):
        DirAccess.remove_absolute(directory.path_join(file))
    DirAccess.remove_absolute(directory)


## What of the voyage must come back from the disk.
static func _snapshot(state: Node) -> Dictionary:
    return (
        JSON
        . parse_string(
            (
                JSON
                . stringify(
                    {
                        "silver": state.silver,
                        "day": state.day,
                        "cargo": state.cargo,
                        "ships": state.ships.to_data(),
                        "missions": state.missions.to_data(),
                        "farm": state.farm.to_data(),
                        "economy": state.economy.to_data(),
                        "players": state.players,
                    }
                )
            )
        )
    )


## Escape twice ends the journey: back to the start, with the voyage saved;
## return what was saved.
func _leave_lakes() -> Dictionary:
    if aborted():
        return {}
    var state := voyage()
    await tap(KEY_ESCAPE)
    await tap(KEY_ESCAPE)
    if not await wait_for_scene(START):
        return {}
    contracts.check_save(state)
    var left := _snapshot(state)
    await play_for(0.5)
    check(panel() != null and panel().title == "Your journeys", "the start shows the journeys")
    return left


## Go on with the journey [param id] on the start screen.
func _go_on(id: String) -> void:
    if aborted():
        return
    var state := voyage()
    var journeys: Array = state.journeys()
    check(
        not journeys.is_empty() and journeys[0]["id"] == id, "the journey played last comes first"
    )
    await choose("Go on: ", true)
    check(state.journey_id == id, "the journey %s goes on" % id)


## Delete the journey [param id] called [param title], in three steps.
func _delete(id: String, title: String) -> void:
    if aborted():
        return
    var state := voyage()
    await choose("Delete")
    await choose(title)
    await choose("Delete")
    tally("journeys deleted")
    var ids: Array = state.journeys().map(func(journey: Dictionary) -> String: return journey["id"])
    check(not id in ids, "a deleted journey is gone")
    check(
        not FileAccess.file_exists(state.saves_dir.path_join(id + ".json")),
        "a deleted journey is gone from the disk"
    )
    check(panel() != null and panel().title == "Your journeys", "the journeys show again")


## Follow the wedding longship and pick up the treats until the party ends.
func _party() -> void:
    if aborted() or not await wait_for_scene(LEVEL):
        return
    var level := current_scene
    var stroke := -INF
    var since := clock
    while panel() == null and not aborted():
        var boat: RowBoat = level.boat()
        var map: LakeMap = level.map()
        var target := map.route_point(map.route_progress(boat.position) + 60.0)
        for item in level._treats.items:
            var at: Vector2 = item["at"]
            if (
                at.distance_to(boat.position) < 50.0
                and (at - boat.position).dot(boat.forward()) > 0.0
            ):
                target = at
                break
        stroke = row_towards(boat, (target - boat.position).angle() + PI / 2.0, 1.3, stroke)
        if clock - since > PARTY_SECONDS:
            fail(
                "the party never ends: %.0f m along the route" % map.route_progress(boat.position),
                true
            )
        await frame()
    rest()
    tally("parties")
    check(level.coins() > 0, "the players pick up treats at the party")
    print("  the party took %.0f s of the game, %d treats" % [clock - since, level.coins()])


## Row away from the pirates to the town, until the players make it (or
## give up after [constant CHASES] tries).
func _chase() -> void:
    for attempt in range(CHASES):
        if aborted() or not await wait_for_scene(CHASE):
            return
        var chase := current_scene
        var silver: int = voyage().silver
        var stroke := -INF
        var since := clock
        var path := PackedVector2Array()
        var planned := -INF
        while chase.outcome() == "" and not aborted():
            var boat: RowBoat = chase.boat()
            var jetty: Vector2 = chase.target()["jetty"]
            if clock - planned > 1.0:
                planned = clock
                path = chase._map.water_path(boat.position, jetty)
            var aim := jetty
            for point in path:
                if point.distance_to(boat.position) > 25.0:
                    aim = point
                    break
            stroke = row_towards(boat, (aim - boat.position).angle() + PI / 2.0, 1.0, stroke)
            if clock - since > CHASE_SECONDS:
                fail("the chase never ends", true)
            await frame()
        rest()
        await play_for(0.5)
        tally("chases " + chase.outcome())
        if chase.outcome() == "escaped":
            check(voyage().silver == silver + chase.REWARD, "the town gives the reward")
            await choose("To the start")
            await wait_for_scene(START)
            await play_for(0.5)
            return
        await choose("Another chase!")
        await frame()
    fail("the players never escape the pirates, rowing as hard as they can", true)
