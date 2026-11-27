extends "res://tests/godot/end2end/driver.gd"
## The bot of the Home Lakes (see world.gd), for the end-to-end test: it does
## the tasks one after the other, as a child who follows the hints would, and
## all on the screens, with the hand: it takes the tasks in the ports, rows
## where they lead, buys and carries what they ask, hails the skippers,
## plants, unloads the animals at home, and sleeps when a task must wait.
## When it lacks silver, it trades: it buys where a good is cheap and sells
## where it is dear. Now and then it also takes a detour, as the players do:
## it talks to the people, looks at its tasks, takes a deal of a skipper,
## buys a ship at the shipyard, looks at the map (C), presses Escape once,
## and sleeps for no reason.
##
## Not a test itself (its name does not start with test_).

const WORLD := "res://scenes/world/world.tscn"
const LEVEL := "res://scenes/level/level.tscn"
const CHASE := "res://scenes/chase/chase.tscn"
const START := "res://scenes/start/start.tscn"

const WorldScript := preload("res://scenes/world/world.gd")
const LakesPlan := preload("res://tests/godot/end2end/lakes_plan.gd")

## Rowing to a place must come at least this much closer to it every
## [constant STUCK_SECONDS] seconds of the game, in metres, else the
## players are stuck.
const PROGRESS := 3.0
const STUCK_SECONDS := 90.0

## A task must be done within this many legs (from port to port), else the
## players are stuck.
const LEGS_PER_TASK := 40

## How long hailing a skipper may take, in seconds of the game.
const HAIL_SECONDS := 900.0

## The chances of the detours.
const TALK_CHANCE := 0.15
const LOOK_CHANCE := 0.15
const DEAL_CHANCE := 0.3
const SLEEP_CHANCE := 0.2
const CHART_CHANCE := 0.1
const ESCAPE_CHANCE := 0.05
const SHIP_CHANCE := 0.5
const SELL_ANIMAL_CHANCE := 0.15

## What the bot did, by what: how often.
var did := {}

## The silver at the start of the party (see Contracts.check_party).
var party_silver := 0

## Where to go next, and what the tasks need (see lakes_plan.gd).
var planner := LakesPlan.new(voyage, world_map, func() -> Vector2: return my_boat().position, did)
var _last_mode := ""
var _watched_scene := 0
var _legs := 0
var _legs_done := 0


func tally(what: String) -> void:
    did[what] = int(did.get(what, 0)) + 1


func voyage() -> Node:
    return root.get_node("/root/GameState")


func _scene() -> String:
    return current_scene.scene_file_path if current_scene != null else ""


func _watch() -> void:
    super()
    if current_scene != null and current_scene.get_instance_id() != _watched_scene:
        _watched_scene = current_scene.get_instance_id()
        contracts.restart(voyage().day)
        _last_mode = ""
    match _scene():
        WORLD:
            var world := current_scene
            if world.map() == null or world.boat() == null:
                return
            contracts.check_world(world)
            var mode: String = world._mode
            if mode == "port" and _last_mode == "rowing":
                contracts.check_save(voyage())
            _last_mode = mode
        LEVEL:
            if current_scene._map != null and current_scene._ship != null:
                contracts.check_party(current_scene, party_silver)
        CHASE:
            if current_scene._map != null and not current_scene._target.is_empty():
                contracts.check_chase(current_scene)
        START:
            contracts.check_music("start", "the start")


# ---------------------------------------------------------------------------
# The lakes
# ---------------------------------------------------------------------------


## Play on the lakes until [param tasks] tasks are done in all (or the test
## stops), then stay on the water.
func play_lakes(tasks: int) -> void:
    if _scene() != WORLD:
        fail("the players are on the lakes, not on %s" % _scene(), true)
        return
    var world := current_scene
    contracts.restart(voyage().day)
    _last_mode = ""
    _legs = 0
    var done_before: int = voyage().missions.done.size()
    while not aborted() and voyage().missions.done.size() < tasks:
        if world._mode != "rowing":
            await _ashore()
            continue
        if voyage().missions.done.size() > done_before:
            done_before = voyage().missions.done.size()
            _legs = 0
            print(
                (
                    "  %d tasks done on day %d, %d silver, %.0f s of the game, %.0f s on the wall"
                    % [done_before, voyage().day, voyage().silver, clock, wall()]
                )
            )
        _legs += 1
        _legs_done += 1
        if _legs > LEGS_PER_TASK:
            var active: Array = voyage().missions.active
            fail("the players are stuck with the tasks %s" % [active], true)
            return
        var plan: Dictionary = planner.next_leg()
        if planner.problem != "":
            fail(planner.problem, true)
            return
        if tracing:
            print(
                (
                    "  leg %d: %s (%d silver, cargo %s)"
                    % [_legs, plan, voyage().silver, voyage().cargo]
                )
            )
        await _detour_at_sea()
        if plan.has("hail"):
            await _hail(plan["hail"])
        else:
            await row_to(plan["go"])


func world_map() -> LakeMap:
    return current_scene.map()


func my_boat() -> RowBoat:
    return current_scene.boat()


# ---------------------------------------------------------------------------
# On the water
# ---------------------------------------------------------------------------


## Row to the jetty of the [param place] until the boat docks there (or
## anywhere, or a skipper is hailed).
func row_to(id: String) -> void:
    var world := current_scene
    var jetty: Vector2 = world_map().place(id)["jetty"]
    if world._left_place == id:
        # NOTE: The boat docks again only once it was away from the jetty.
        await _row_away(jetty)
    var path := PackedVector2Array()
    var planned := -INF
    var stroke := -INF
    var best := INF
    var best_at := clock
    while world._mode == "rowing" and not aborted():
        var boat := my_boat()
        var distance := boat.position.distance_to(jetty)
        if clock - planned > 2.0:
            planned = clock
            path = world_map().water_path(boat.position, jetty)
        var aim := jetty
        for point in path:
            if point.distance_to(boat.position) > 20.0:
                aim = point
                break
        var wanted := (aim - boat.position).angle() + PI / 2.0
        var beat := 1.0
        var brake := false
        if distance < 45.0:
            beat = 2.0 if boat.speed < 1.0 else 0.0
            brake = boat.speed > 3.2
        elif distance < 90.0:
            beat = 1.5 if boat.speed < 5.0 else 0.0
            brake = boat.speed > 8.0
        stroke = row_towards(boat, wanted, beat, stroke)
        fake.brake = [brake, brake]
        if distance < best - PROGRESS:
            best = distance
            best_at = clock
        elif clock - best_at > STUCK_SECONDS:
            fail(
                (
                    "the boat is stuck on the way to %s: %.0f m from its jetty at %s"
                    % [id, distance, boat.position]
                ),
                true
            )
        await frame()
    rest()


## Row out of reach of the jetty at [param jetty].
func _row_away(jetty: Vector2) -> void:
    var world := current_scene
    var stroke := -INF
    var since := clock
    while (
        world._mode == "rowing"
        and my_boat().position.distance_to(jetty) <= WorldScript.UNDOCK_DISTANCE + 5.0
        and not aborted()
    ):
        var away := (my_boat().position - jetty).angle() + PI / 2.0
        stroke = row_towards(my_boat(), away, 1.0, stroke)
        if clock - since > STUCK_SECONDS:
            fail("the boat can not leave the jetty at %s" % jetty, true)
        await frame()
    rest()


## Hail a skipper with the picture [param picture] (any, if "").
func _hail(picture: String) -> void:
    var world := current_scene
    var stroke := -INF
    var since := clock
    var hails: int = did.get("hails", 0)
    var path := PackedVector2Array()
    var planned := -INF
    while world._mode == "rowing" and not aborted():
        var target: NpcBoat = null
        for npc: NpcBoat in world.npcs():
            if (picture == "" or npc.skipper.get("picture", "") == picture) and npc.cooldown <= 0:
                if (
                    target == null
                    or (
                        npc.position.distance_to(my_boat().position)
                        < target.position.distance_to(my_boat().position)
                    )
                ):
                    target = npc
        if target == null:
            rest()
        else:
            var distance := target.position.distance_to(my_boat().position)
            if clock - planned > 1.0:
                planned = clock
                path = world_map().water_path(my_boat().position, target.position)
            var aim := target.position
            if distance > 40.0 and path.size() > 1:
                aim = path[1]
            var wanted := (aim - my_boat().position).angle() + PI / 2.0
            var beat := 1.0 if distance > 45.0 else (1.5 if my_boat().speed < 2.0 else 0.0)
            stroke = row_towards(my_boat(), wanted, beat, stroke)
            var brake := distance < 45.0 and my_boat().speed > WorldScript.HAIL_SPEED - 0.3
            fake.brake = [brake, brake]
        if clock - since > HAIL_SECONDS:
            fail("the players can not hail %s" % (picture if picture != "" else "a skipper"), true)
        await frame()
    rest()
    if world._mode == "skipper" and int(did.get("hails", 0)) == hails:
        tally("hails")


## Now and then, look at the map or press Escape once while rowing.
func _detour_at_sea() -> void:
    var world := current_scene
    if rng.randf() < CHART_CHANCE:
        tally("map")
        await tap(KEY_C)
        check(world._chart != null, "C shows the map")
        var at := my_boat().position
        var day: int = voyage().day
        await play_for(2.0)
        check(
            my_boat().position == at and voyage().day == day, "the game waits while the map shows"
        )
        await tap(KEY_C)
        check(world._chart == null, "C hides the map")
    if rng.randf() < ESCAPE_CHANCE:
        tally("escape once")
        await tap(KEY_ESCAPE)
        await play_for(EscapeGuard.SECONDS + 1.0)
        check(_scene() == WORLD, "Escape once does not end the journey")


# ---------------------------------------------------------------------------
# Ashore: the screens of the ports and of the skippers
# ---------------------------------------------------------------------------


func _ashore() -> void:
    var world := current_scene
    if world._mode == "skipper":
        await _talk_to_skipper()
        return
    tally("docked")
    await _settle()
    if aborted() or world._mode != "port":
        return
    if voyage().place == "home":
        await _at_home()
    else:
        await _at_market()
    if aborted() or world._mode != "port":
        return
    await _settle()
    var out := "Row out" if voyage().place == "home" else "Row on"
    await choose(out)


func _talk_to_skipper() -> void:
    var world := current_scene
    var guard := 0
    while world._mode == "skipper" and not aborted() and guard < 20:
        guard += 1
        if can("Yes, deal!") and rng.randf() < DEAL_CHANCE:
            tally("deals")
            await choose("Yes, deal!")
        elif can("No, thank you"):
            await choose("No, thank you")
        elif cards().size() == 1:
            await choose(cards()[0])
        else:
            fail("a skipper shows the cards %s" % [cards()], true)
    check(world._mode != "skipper", "the players leave the skipper")


## Whether the main screen of the port shows (with the card to leave).
func _at_main() -> bool:
    var titles := cards()
    return "Row on" in titles or ("Sleep" in titles and "Row out" in titles)


## Go through the screens of the tasks (and back) to the main screen.
func _settle() -> void:
    var guard := 0
    while not _at_main() and not aborted():
        if panel() == null and current_scene._mode == "rowing":
            fail("the bot looks for the port on the water", true)
            return
        guard += 1
        if guard > 40:
            fail("the screens of '%s' never lead back to the port" % cards(), true)
            return
        var titles := cards()
        if titles.size() == 1:
            if titles[0] in ["Go on", "Hooray!", "Thank you!"]:
                tally("events")
            await choose(titles[0])
        elif can("Back"):
            await choose("Back")
        elif panel() == null:
            await frame()
        else:
            fail("the screen '%s' has no way back: %s" % [panel().title, titles], true)


## Find the card on the pages of a list (see PortScreens._show_list).
func _find(title: String, prefix := false) -> bool:
    for i in range(8):
        if can(title, prefix):
            return true
        if not can("More"):
            return false
        await choose("More")
    return false


func _at_market() -> void:
    var state := voyage()
    var id: String = state.place
    await _sell_all(id)
    await _take_tasks(id)
    await _buy_needs(id)
    if not planner.trade.is_empty() and planner.trade["from"] == id and planner.trade["to"] != id:
        await _buy(planner.trade["good"], 1 << 20)
        planner.trade["from"] = ""
    if id == state.ships.shipyard:
        await _shipyard()
    await _sell_animals(id)
    if rng.randf() < TALK_CHANCE:
        await _settle()
        tally("talks")
        await choose("Talk")
        await choose("Thank you!")
    if rng.randf() < LOOK_CHANCE and not state.missions.active.is_empty():
        await _look_at_tasks()


## Sell the animal which the pasture needs gone (see [method _pasture_plan]),
## or now and then a spare one, if this place deals in it.
func _sell_animals(id: String) -> void:
    var state := voyage()
    var dealt: Array = PortScreens.ANIMALS_SOLD.get(world_map().place(id)["kind"], [])
    var kind := planner.sell_kind
    if kind == "" and rng.randf() < SELL_ANIMAL_CHANCE:
        var needed := planner.needed()
        for animal in dealt:
            if int(state.farm.animals.get(animal, 0)) > 1 and not needed.has("animal:" + animal):
                kind = animal
    if kind == "" or not kind in dealt:
        return
    var name := Grammar.text(
        "Sell {animal}", {"animal": Missions.crates(state, "animal:" + kind, 1)}
    )
    await _settle()
    await choose("Animals")
    var found: bool = await _find(name)
    if found:
        var silver: int = state.silver
        await choose(name)
        tally("animals sold")
        check(state.silver > silver, "selling an animal pays")
    planner.sell_kind = ""
    await _settle()


## Sell what no task needs (the goods of a trade only where it sells).
func _sell_all(id: String) -> void:
    var state := voyage()
    var needed := planner.needed()
    var goods: Array[String] = []
    for item in state.cargo.keys():
        if not state.economy.buys(id, item):
            continue
        if needed.has(item) and not (not planner.trade.is_empty() and planner.trade["to"] == id):
            continue
        goods.append(item)
    if goods.is_empty():
        return
    await _settle()
    var opened: bool = await choose("Sell")
    if not opened:
        return
    for good in goods:
        while int(state.cargo.get(good, 0)) > 0 and not aborted():
            var name := Grammar.text(
                "Sell {good} ({count})",
                {"good": state.good_name(good), "count": int(state.cargo.get(good, 0))}
            )
            if _at_main():
                if not can("Sell"):
                    break
                await choose("Sell")
            var found: bool = await _find(name)
            if not found:
                fail("the card '%s' shows while the boat carries it" % name)
                break
            tally("sold")
            await choose(name)
    if not planner.trade.is_empty() and planner.trade["to"] == id:
        planner.trade = {}
    await _settle()


## Take the tasks offered here, up to [constant LakesPlan.MAX_TASKS].
func _take_tasks(id: String) -> void:
    var missions: Missions = voyage().missions
    while (
        not missions.offers_at(id).is_empty()
        and missions.active.size() < LakesPlan.MAX_TASKS
        and not aborted()
    ):
        var offer: String = missions.offers_at(id)[0]
        # NOTE: The next task in the order first, as the hints lead.
        if missions.available()[0] != offer and not missions.active.is_empty():
            return
        await _settle()
        await choose("Tasks")
        var listed: bool = await _find(missions.missions[offer]["title"])
        if not listed:
            fail("the task %s offered here is on the list" % offer, true)
            return
        await choose(missions.missions[offer]["title"])
        tally("tasks taken")
        await choose("Yes, I will help!")
        check(missions.is_active(offer), "the task %s is taken" % offer)
        await _settle()


## Buy what the tasks need here, as far as the room and the silver go.
func _buy_needs(id: String) -> void:
    var state := voyage()
    var kind: String = world_map().place(id)["kind"]
    var needed := planner.needed()
    for item in needed.keys():
        var missing := int(needed[item]) - int(state.cargo.get(item, 0))
        if missing <= 0 or (not planner.trade.is_empty() and item == planner.trade["good"]):
            continue
        if item.begins_with("animal:"):
            var animal: String = str(item).trim_prefix("animal:")
            if animal in PortScreens.ANIMALS_SOLD.get(kind, []):
                await _buy_animals(animal, missing)
        elif state.economy.sells(id, item):
            await _buy(item, missing)


func _buy(good: String, wanted: int) -> void:
    var state := voyage()
    var name := Grammar.text("Buy {good}", {"good": state.good_name(good)})
    await _settle()
    await choose("Buy")
    var bought := 0
    while bought < wanted and not aborted():
        var found: bool = await _find(name)
        if not found:
            break
        tally("bought")
        await choose(name)
        bought += 1
    await _settle()


func _buy_animals(kind: String, wanted: int) -> void:
    var name := Grammar.text(
        "Buy {animal}", {"animal": Missions.crates(voyage(), "animal:" + kind, 1)}
    )
    await _settle()
    await choose("Animals")
    var bought := 0
    while bought < wanted and can(name) and not aborted():
        tally("animals bought")
        await choose(name)
        bought += 1
    await _settle()


## The next ship which the players can buy with silver to spare, or "".
## Buy the next ship when there is silver to spare, or take another one.
func _shipyard() -> void:
    var state := voyage()
    var ships: Ships = state.ships
    var next := planner.next_ship()
    var buying := next != ""
    var other := ""
    for id in ships.owned:
        if id != ships.current and state.load_count() <= ships.hold(id):
            other = id
    if not buying and (other == "" or rng.randf() > SHIP_CHANCE):
        return
    await _settle()
    await choose("Shipyard")
    var id := next if buying else other
    await choose(Grammar.title(ships.kinds[id]["name"]))
    await choose("Buy her" if buying else "Take her")
    tally("ships bought" if buying else "ships taken")
    check(ships.current == id, "the players row the ship %s they chose" % id)
    check(current_scene._ship_view != null or id == Ships.START, "the ship %s is drawn" % id)
    await choose("Back")


func _look_at_tasks() -> void:
    var missions: Missions = voyage().missions
    await _settle()
    tally("looked at the tasks")
    await choose("Tasks")
    var title: String = missions.missions[missions.active[0]["id"]]["title"]
    var found: bool = await _find(title)
    if found:
        await choose(title)
        await choose("Back")
    await _settle()


# ---------------------------------------------------------------------------
# At home
# ---------------------------------------------------------------------------


func _at_home() -> void:
    var state := voyage()
    await _unload()
    await _load_needs(planner.needed(true))
    if not planner.trade.is_empty() and planner.trade["from"] == "home":
        await _load_from_store(planner.trade["good"], 1 << 20)
        planner.trade["from"] = ""
    await _farm_work()
    await _take_tasks("home")
    var sleep := planner.must_sleep or _waiting() or _no_free_field() or rng.randf() < SLEEP_CHANCE
    planner.must_sleep = false
    # NOTE: One night at a time (see _night_plan).
    if sleep and state.travelled and not aborted():
        var day: int = state.day
        await _settle()
        tally("slept")
        await choose("Sleep")
        check(state.day == day + 1, "a night's sleep ends the day")
        await choose("The farm")
        await choose("Back")
        await _settle()
        await _farm_work()


## Whether a task under way waits for a night to pass.
func _waiting() -> bool:
    var state := voyage()
    for entry in state.missions.active:
        var step: Dictionary = state.missions.current_step(entry["id"])
        if state.missions._wait_left(state, entry, step) > 0:
            return true
    return false


## Unload the boat at home, unless it carries what the tasks need elsewhere.
func _unload() -> void:
    var needed := planner.needed(true)
    for item in voyage().cargo.keys():
        if needed.has(item):
            return
    if can("Unload the boat"):
        tally("unloaded")
        await choose("Unload the boat")
        await _settle()


## Load from the store what the tasks need elsewhere.
func _load_needs(needed: Dictionary) -> void:
    var state := voyage()
    for good in needed.keys():
        if good.begins_with("animal:") or state.farm.crates(good) <= 0:
            continue
        await _load_from_store(good, int(needed[good]) - int(state.cargo.get(good, 0)))


## Load up to [param wanted] crates of the [param good] from the store.
func _load_from_store(good: String, wanted: int) -> void:
    var state := voyage()
    await _settle()
    if wanted <= 0 or not can("Load from the store"):
        return
    await choose("Load from the store")
    var name := Grammar.text("Load {good}", {"good": state.good_name(good)})
    var loaded := 0
    while loaded < wanted and state.has_room() and state.farm.crates(good) > 0 and not aborted():
        var found: bool = await _find(name)
        if not found:
            break
        tally("loaded from the store")
        await choose(name)
        loaded += 1
    await _settle()


## Plant what the tasks ask, harvest what is ripe, and buy land when the
## animals need room.
func _farm_work() -> void:
    var state := voyage()
    var farm: Farm = state.farm
    var crop := _crop_to_plant()
    var pasture := false
    for entry in state.missions.active:
        var step: Dictionary = state.missions.current_step(entry["id"])
        if step["do"] == "have" and not farm.has_room_for(step["animal"]):
            pasture = true
    for kind in farm.animal_kinds:
        if int(state.cargo.get("animal:" + kind, 0)) > 0 and not farm.has_room_for(kind):
            pasture = true
    var ripe := false
    for i in range(farm.fields.size()):
        ripe = ripe or (farm.fields[i]["crop"] != "" and farm.days_to_ripe(i, state.day) == 0)
    if crop == "" and not pasture and not ripe:
        return
    await _settle()
    await choose("The farm")
    if ripe and can("Harvest"):
        tally("harvested")
        await choose("Harvest")
    var seed := int(farm.crop_kinds[crop]["seed_price"]) if crop != "" else 0
    if crop != "" and not can("Plant"):
        await _buy_land("fields", seed)
    if pasture:
        await _buy_land("pasture", seed)
    if crop != "" and can("Plant"):
        await choose("Plant")
        var name := Grammar.title(farm.crop_kinds[crop]["name"])
        var found: bool = await _find(name)
        if found:
            tally("planted")
            await choose(name)
        else:
            await choose("Back")
    if can("Back") and screen_is("The farm"):
        await choose("Back")
    await _settle()
    await _unload()


## The crop which a task asks to plant and is not growing yet, or "".
func _crop_to_plant() -> String:
    var state := voyage()
    for entry in state.missions.active:
        var step: Dictionary = state.missions.current_step(entry["id"])
        if step["do"] == "plant":
            var growing := false
            for field in state.farm.fields:
                growing = growing or field["crop"] == step["crop"]
            if not growing:
                return step["crop"]
    return ""


## Whether a task asks to plant, and no field is free.
func _no_free_field() -> bool:
    if _crop_to_plant() == "":
        return false
    for field in voyage().farm.fields:
        if field["crop"] == "":
            return false
    return true


## On the screen of the farm, buy the cheapest plot with more [param what]
## ("fields" or "pasture") which leaves [param keep] silver.
func _buy_land(what: String, keep: int) -> void:
    var state := voyage()
    var best := {}
    for plot in state.farm.plot_kinds:
        if plot["id"] in state.farm.plots or int(plot[what]) <= 0:
            continue
        if int(plot["price"]) + keep > state.silver:
            continue
        if best.is_empty() or int(plot["price"]) < int(best["price"]):
            best = plot
    if best.is_empty() or not can("Buy land"):
        return
    await choose("Buy land")
    tally("land bought")
    await choose(best["name"])
