extends "res://tests/godot/end2end/playthrough.gd"
## The end-to-end test of the chase (see playthrough.gd): at the very first
## start, the players choose their language, start a new journey with one
## rower and watch How to play; then How to play once more and a new colour of
## the hair (detours from the choice of what to play), then the chase: the bot
## rows away from the pirates to the town, and back to the start. The journey
## then goes on with the reward of the town in its purse.
##
## $GODOT --headless --fixed-fps 60 --path . \
##     --script tests/godot/end2end/test_chase.gd -- --no-camera

## How long a chase may take, in seconds of the game.
const CHASE_SECONDS := 600.0

## How often the players try the chase before they make it.
const CHASES := 3


func mode() -> String:
    return "chase"


func heard() -> Array:
    return ["click", "oar", "pirates", "jingle"]


func default_wall_seconds() -> float:
    return 120.0


func play_mode() -> void:
    print("A new journey with one rower, and the chase")
    await first_journey(["Boy", "Tan", "Black", "Red"])
    var id: String = voyage().journey_id
    # A detour: How to play again, from the choice of what to play.
    await choose("How to play")
    await how_to(1)
    # And another: a new colour of the hair.
    await choose("Your vikings")
    await choose_look(["Boy", "Tan", "Brown", "Red"])
    check(voyage().look(0)["hair"] == 2, "the rower changes how they look")
    await choose("Chase!")
    await _chase()
    if aborted():
        return
    var left := snapshot(voyage())
    check(screen_is("Your journeys"), "after the chase, the start shows the journeys")
    await go_on(id)
    check(
        voyage().look(0) == {"figure": "boy", "skin": 2, "hair": 2, "clothes": 3},
        "the journey keeps how its rower looks"
    )
    var back := snapshot(voyage())
    check(
        JSON.stringify(left) == JSON.stringify(back),
        "the journey comes back as the chase left it"
    )


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
