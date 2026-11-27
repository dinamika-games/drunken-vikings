extends "res://tests/godot/end2end/lakes_bot.gd"
## The base of the end-to-end tests, one for each mode of the game:
## test_party.gd, test_lakes.gd and test_chase.gd. Each plays the game from the
## very first start on, as the players do (only with the camera, see
## fake_vision.gd), much faster than in real time, and checks its contracts on
## every frame (see contracts.gd): a property-based test, whose random choices
## come from a seed.
##
## All the way, the game must never log an error (e.g., a sound which is not
## there), the music must fit where the players are, and the players must never
## get stuck: every screen lets them go on, every card they hold is chosen,
## every way leads to its jetty, and every task gets done.
##
## $GODOT --headless --fixed-fps 60 --path . \
##     --script tests/godot/end2end/test_<mode>.gd -- --no-camera
##
## The bot plays in every language (it finds the cards by their English
## titles, see driver.gd), and the contracts check that every text fits.
##
## Pass -- --lang=<code> to play in another language, e.g., de,
## --seed=<n> to try other choices, --time-scale=<x> for another speed of the
## game, --draw-every=<n> to draw more or less often, and --wall-seconds=<s>
## for another limit of the wall clock. A test keeps its journeys in
## user://tests/<mode> (a directory for each seed, so that several seeds may
## run at once), and leaves the players' alone.
##
## Not a test itself (its name does not start with test_).

const DIRECTORY := "user://tests"

## How long the players watch How to play, in seconds of the game.
const HOW_TO_SECONDS := 20.0

## The language which the players choose.
var language := "en"


## Overridden by the test: the name of its directory, e.g., "party".
func mode() -> String:
    return ""


## Overridden by the test: the sounds which the players must hear (see Audio).
func heard() -> Array:
    return []


## Overridden by the test: play the mode.
func play_mode() -> void:
    pass


func _play() -> void:
    var state := voyage()
    # NOTE: A directory for each seed, so that several seeds may run at once.
    var directory := (
        "%s/%s/seed_%s" % [DIRECTORY, mode(), argument("seed", str(DEFAULT_SEED))]
    )
    _clean(directory)
    state.saves_dir = directory + "/saves"
    state.settings_path = directory + "/settings.cfg"
    state.save_path = directory + "/none.json"
    DirAccess.make_dir_recursive_absolute(state.saves_dir)
    # NOTE: The game starts as at the very first start, in English; the
    # players choose their language (see first_journey).
    var languages: Node = root.get_node("/root/Languages")
    language = argument("lang", "en")
    languages.settings_path = directory + "/settings.cfg"
    languages.has_chosen = false
    languages.use("en")
    await play_mode()
    print("Did: %s" % did)
    var sounds := Audio.played()
    print("Heard: %s" % sounds)
    for sound in heard():
        check(sounds.has(sound), "the players hear the sound %s" % sound)
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


## The very first start: the players choose their language, then a new
## journey with one rower, who looks as the cards [param looks] say (one per
## screen), and watch How to play; then they choose what to play.
func first_journey(looks: Array) -> void:
    change_scene_to_file(START)
    if not await wait_for_scene(START):
        return
    await play_for(0.5)
    var languages: Node = root.get_node("/root/Languages")
    var name := ""
    for item in languages.languages:
        if item["code"] == language:
            name = item["name"]
    check(loose_button(name) != null, "at the very first start, the players choose the language")
    await choose(name)
    check(languages.current() == language, "the game speaks the language %s" % language)
    await play_for(0.5)
    check(screen_is("A new journey"), "without a journey, the game starts a new one")
    await choose("One rower")
    check(fake.players == 1, "the camera follows one player")
    await choose_look(looks)
    await how_to(1)


## Choose how the rowers look: the cards [param titles], one per screen.
func choose_look(titles: Array) -> void:
    for title in titles:
        if aborted():
            return
        await choose(title)


## How to play shows for the [param players]: watch some of its parts, then
## hold the hand on Ready!.
func how_to(players: int) -> void:
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
    check(screen_is("What do you play?"), "after how to play, the players choose what they play")


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
static func snapshot(state: Node) -> Dictionary:
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
                        "place": state.place,
                        "boat": [state.boat_at.x, state.boat_at.y, state.boat_heading],
                    }
                )
            )
        )
    )


## Escape twice ends the journey: back to the start, with the voyage saved;
## return what was saved.
func leave_lakes() -> Dictionary:
    if aborted():
        return {}
    var state := voyage()
    await tap(KEY_ESCAPE)
    await tap(KEY_ESCAPE)
    if not await wait_for_scene(START):
        return {}
    contracts.check_save(state)
    var left := snapshot(state)
    await play_for(0.5)
    check(screen_is("Your journeys"), "the start shows the journeys")
    return left


## Go on with the journey [param id] on the start screen.
func go_on(id: String) -> void:
    if aborted():
        return
    var state := voyage()
    var journeys: Array = state.journeys()
    check(
        not journeys.is_empty() and journeys[0]["id"] == id, "the journey played last comes first"
    )
    await choose("Go on: {journey}")
    check(state.journey_id == id, "the journey %s goes on" % id)


## Delete the journey [param id] called [param title], in three steps.
func delete_journey(id: String, title: String) -> void:
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
    check(screen_is("Your journeys"), "the journeys show again")
