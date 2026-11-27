extends SceneTree

## Check the missions (see Missions): the data of every mission is sound, the
## items of a mission take the room of crates (a big load takes several
## trips), the save keeps the missions, and a careful player can play all the
## missions one after the other, with three stars.
##
## $GODOT --headless --path . --script tests/godot/test_missions.gd -- --no-camera

## The longest texts which fit the screen of choices (six lines).
const LONGEST_TEXT := 300

## Where the players buy the animals (see PortScreens.ANIMALS_SOLD).
const ANIMAL_PLACES := {
    "hen": "market",
    "sheep": "market",
    "goat": "horse_farm",
    "cow": "horse_farm",
    "bees": "beekeeper"
}

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _run() -> void:
    var state: Node = root.get_node("/root/GameState")
    _check(state.error == "", "the data loads: " + state.error)
    if state.error != "":
        quit(1)
        return
    state.saves_dir = "user://test_missions"
    state.settings_path = "user://test_missions/settings.cfg"
    state.save_path = "user://test_missions/voyage.json"

    _check_texts(state)
    _check_hold(state)
    _check_save(state)
    _play_all(state)

    print("PASS test_missions" if _failures == 0 else "FAIL test_missions (%d)" % _failures)
    quit(0 if _failures == 0 else 1)


## The numbers run from 1 without a gap, and the texts fit the screens.
func _check_texts(state: Node) -> void:
    var missions: Missions = state.missions
    print("%d missions" % missions.order.size())
    for i in range(missions.order.size()):
        var mission: Dictionary = missions.missions[missions.order[i]]
        _check(
            int(mission["number"]) == i + 1,
            "the mission %s has the number %d" % [mission["id"], i + 1]
        )
        var giver: Dictionary = mission["giver"]
        _check(
            (str(giver["name"]) + mission["offer"]).length() <= LONGEST_TEXT,
            "the offer of %s fits the screen" % mission["id"]
        )
        _check_face(giver, mission["id"])
        for step in mission["steps"]:
            _check(
                str(step.get("say", "")).length() <= LONGEST_TEXT,
                "what %s says fits the screen: %s" % [mission["id"], step.get("say", "")]
            )
            for line in step.get("says", []):
                _check(str(line).length() <= LONGEST_TEXT, "a line of %s fits" % mission["id"])
            for key in ["who", "from_who", "to_who"]:
                if step.has(key):
                    _check_face(step[key], mission["id"])
        var reward_text := str(mission.get("fact", ""))
        _check(reward_text.length() <= 200, "the fact of %s is short" % mission["id"])
        for item in mission.get("items", {}).keys():
            _check(
                str(mission["items"][item]["name"]).length() <= 10,
                "the name of the item %s of %s fits a crate" % [item, mission["id"]]
            )
            var picture: Array = mission["items"][item].get("picture", [])
            _check(
                picture.size() == 2 and Pictures.of(picture[0], picture[1]) != null,
                "the item %s of %s is painted" % [item, mission["id"]]
            )


func _check_face(who: Dictionary, id: String) -> void:
    _check(str(who.get("name", "")) != "", "who speaks in %s has a name" % id)
    var picture := str(who.get("picture", ""))
    _check(
        picture != "" and Pictures.of("faces", picture) != null,
        "the face of %s in %s is painted" % [who.get("name", ""), id]
    )


## A load bigger than the hold takes several trips, and the items of the
## missions can not be sold.
func _check_hold(state: Node) -> void:
    state.new_voyage()
    var missions: Missions = state.missions
    missions.missions["test_hold"] = {
        "number": 0,
        "id": "test_hold",
        "title": "Test",
        "giver": {"place": "home", "name": "Grandmother Åsa"},
        "offer": "",
        "items": {"hay": {"name": "Hay", "counted": "{count|a bale of hay|{count} bales of hay}"}},
        "steps": [{"do": "carry", "item": "hay", "count": 6, "from": "home", "to": "horse_farm"}],
        "reward": {"silver": 5},
    }
    missions.accept("test_hold", state.day)
    state.add_cargo("fish")
    var key := Missions.item_key("test_hold", "hay")
    missions.arrive(state, "home")
    _check(int(state.cargo.get(key, 0)) == 3, "the boat takes as much hay as fits beside the fish")
    _check(not missions.blocked_at(state, "home").is_empty(), "the rest waits at home")
    _check(missions.target(state, "test_hold") == "horse_farm", "the hay goes to the horse farm")
    _check(not state.sell("market", key), "the hay of a mission can not be sold")
    missions.arrive(state, "horse_farm")
    _check(not state.cargo.has(key), "the hay is unloaded at the horse farm")
    _check(missions.target(state, "test_hold") == "home", "the rest of the hay waits at home")
    state.remove_cargo("fish")
    missions.arrive(state, "home")
    _check(int(state.cargo.get(key, 0)) == 3, "the boat takes the rest of the hay")
    var silver: int = state.silver
    missions.arrive(state, "horse_farm")
    _check(missions.done.has("test_hold"), "the hay is all there")
    _check(state.silver == silver + 5, "the reward is paid")
    missions.missions.erase("test_hold")
    missions.reset()


## The save keeps the missions done and under way.
func _check_save(state: Node) -> void:
    state.new_voyage()
    var missions: Missions = state.missions
    var first: String = missions.order[0]
    missions.done[first] = 2
    var second: String = missions.available()[0]
    missions.accept(second, 1)
    _check(state.save(), "the voyage saves")
    missions.reset()
    _check(state.load_voyage(), "the voyage loads")
    _check(int(missions.done.get(first, 0)) == 2, "the save keeps the missions done")
    _check(missions.is_active(second), "the save keeps the missions under way")
    missions.reset()


## Play every mission, in their order, as a careful player would: never
## sleep unless a step must wait, and keep the boat free for the mission.
func _play_all(state: Node) -> void:
    state.new_voyage()
    var missions: Missions = state.missions
    var extra_silver := 0
    for id in missions.order:
        var mission: Dictionary = missions.missions[id]
        if not id in missions.available():
            _check(false, "the mission %s is available after the ones before it" % id)
            continue
        var giver: String = mission["giver"]["place"]
        _check(id in missions.offers_at(giver), "%s is offered at %s" % [id, giver])
        missions.accept(id, state.day)
        _go(state, giver)
        var guard := 0
        while missions.is_active(id) and guard < 100:
            guard += 1
            extra_silver += _do_step(state, id)
        _check(not missions.is_active(id), "the mission %s can be done" % id)
        _check(int(missions.done.get(id, 0)) == 3, "the mission %s gives three stars" % id)
        for item in state.cargo.keys():
            _check(
                not item.begins_with(Missions.PREFIX + id + ":"),
                "nothing of %s stays in the boat" % id
            )
    print(
        (
            (
                "All missions done on day %d: %d stars, %d silver, a hold of %d crates, %s, "
                + "%d silver added for the purchases."
            )
            % [
                state.day,
                missions.stars(),
                state.silver,
                state.capacity,
                str(state.farm.animals),
                extra_silver
            ]
        )
    )


func _go(state: Node, place: String) -> void:
    state.place = place
    state.missions.arrive(state, place)


## Do what the step of the mission asks; return the silver which had to be
## added for it.
func _do_step(state: Node, id: String) -> int:
    var missions: Missions = state.missions
    var step := missions.current_step(id)
    var added := 0
    var entry: Dictionary = missions._entry(id)
    var wait := int(entry["since"]) + int(step.get("wait", 0)) - int(state.day)
    for i in range(wait):
        state.next_day()
    # Keep the boat free for the mission.
    for item in state.cargo.keys():
        if not item.begins_with(Missions.PREFIX + id + ":") and not item == step.get("item", ""):
            state.cargo.erase(item)
    match step["do"]:
        "visit":
            _go(state, step["at"])
        "pay":
            if state.silver < int(step["silver"]):
                added += int(step["silver"]) - state.silver
                state.silver = int(step["silver"])
            _go(state, step["at"])
        "carry":
            _go(state, missions.target(state, id))
        "deliver":
            var item: String = step["item"]
            var left := (
                int(step.get("count", 1)) - int(entry["count"]) - int(state.cargo.get(item, 0))
            )
            for i in range(mini(left, state.capacity - state.load_count())):
                if item.begins_with("animal:"):
                    var kind := item.trim_prefix("animal:")
                    var price := int(state.farm.animal_kinds[kind]["price"])
                    if state.silver < price:
                        added += price - state.silver
                        state.silver = price
                    state.silver -= price
                    state.add_cargo(item)
                else:
                    var at: String = state.economy.best_buy(item)["place"]
                    var price: int = state.economy.buy_price(at, item)
                    if state.silver < price:
                        added += price - state.silver
                        state.silver = price
                    _check(state.buy(at, item), "%s can be bought for %s" % [item, id])
            _go(state, step["at"])
        "hail":
            missions.hail(state, step.get("skipper", "ragna"))
        "have":
            var kind: String = step["animal"]
            while int(state.farm.animals.get(kind, 0)) < int(step.get("count", 1)):
                added += int(state.farm.animal_kinds[kind]["price"])
                state.farm.add_animal(kind)
            _go(state, "home")
        "plant":
            var field := 0
            for i in range(state.farm.fields.size()):
                if state.farm.fields[i]["crop"] == "":
                    field = i
                    break
            state.farm.plant(field, step["crop"], state.day)
            _go(state, "home")
    return added
