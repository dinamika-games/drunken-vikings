extends "res://tests/godot/end2end/playthrough.gd"
## The end-to-end test of the party (see playthrough.gd): at the very first
## start, the players choose their language, start a new journey with one
## rower (with a detour back from the second screen of the looks), watch How
## to play, then follow the wedding longship and pick up the treats to the end
## of the party, go to the farm, and Escape twice ends the journey.
##
## $GODOT --headless --fixed-fps 60 --path . \
##     --script tests/godot/end2end/test_party.gd -- --no-camera

## How long the party may take, in seconds of the game.
const PARTY_SECONDS := 900.0


func mode() -> String:
    return "party"


func heard() -> Array:
    return ["click", "oar", "horn", "pickup", "coin", "hooray"]


func default_wall_seconds() -> float:
    return 120.0


func play_mode() -> void:
    print("A new journey with one rower, and the party")
    # NOTE: A detour: Back from the second screen of the looks, and on.
    await first_journey(["Boy", "Back", "Boy", "Tan", "Black", "Red"])
    check(
        voyage().look(0) == {"figure": "boy", "skin": 2, "hair": 4, "clothes": 3},
        "the rower looks as chosen"
    )
    party_silver = voyage().silver
    await choose("Party!")
    await _party()
    await choose("To the farm")
    if aborted() or not await wait_for_scene(WORLD):
        return
    await play_for(1.0)
    var left := await leave_lakes()
    check(
        int(left.get("silver", -1)) == voyage().silver and voyage().silver > party_silver,
        "the silver of the party goes into the purse of the voyage"
    )


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
