class_name Missions
extends RefCounted

## The missions (the tasks) which the people of the lakes give the players
## (see data/missions/ and DESIGN.md, "Missions").
##
## A mission is plain data: who gives it and where, what they ask, which
## missions must be done before it, and a list of steps, done one after the
## other:
##
## * "visit": dock at the place "at".
## * "carry": take the mission's "item" ("count" of them) at the place "from"
##   and bring it to the place "to". Every item takes the room of a crate in
##   the boat, so a big load needs room, or several trips: at "from", the
##   boat takes as many as fit, and the rest waits there.
## * "deliver": bring "count" of the "item" (a good, e.g. "ale", or an
##   animal, e.g. "animal:goat") to the place "at"; the players buy or make
##   it themselves. At home, the goods go into the store, the animals onto
##   the farm.
## * "pay": pay "silver" at the place "at".
## * "hail": hail a skipper on the lakes ("skipper", the name of their
##   picture, or any skipper if left out), "count" times.
## * "have": the farm has "count" animals of the kind "animal" (checked at home).
## * "plant": a field of the farm grows the "crop" (checked at home).
##
## Any step may "wait" some nights after the step before (e.g., the cheese
## ripens), "say" what the people say when it is done and "who" says it (for
## a carry step, "from_who" loads the items, "load_say" is what they say, and
## "to_who" takes them); without, the giver speaks at their own place.
##
## A mission is done with its last step: the players get the reward (silver,
## goods for the store, animals for the farm, land, a bigger hold) and 1 to 3
## stars, by how many days it took against its "days" (3 stars without them).
## Nothing ever fails: a late mission only gives fewer stars.

## How many missions the players carry out at the same time, at most.
const MAX_ACTIVE := 3

## The kinds of the steps.
const STEP_KINDS := ["visit", "carry", "deliver", "pay", "hail", "have", "plant"]

## The prefix of the items of the missions in the cargo: "task:<mission>:<item>".
const PREFIX := "task:"

## The missions: id -> the data of data/missions/<nnn>_<id>/mission.json.
var missions := {}

## The ids of the missions by their number.
var order: Array[String] = []

## The missions done: id -> stars.
var done := {}

## The missions under way: Array of {"id", "step", "accepted" (the day),
## "since" (the day the step began), "loaded", "count" (how many items the step
## has delivered, or skippers hailed)}.
var active: Array = []

## The names of the places: id -> name.
var _place_names := {}


## Load the missions of [param dir] and check them against the [param places]
## (id -> {"name", ...}), the goods of the [param economy] and the animals and
## crops of the [param farm]; return what went wrong, or "".
func load_data(dir: String, places: Dictionary, economy: Economy, farm: Farm) -> String:
    missions.clear()
    order.clear()
    _place_names = {}
    for id in places.keys():
        _place_names[id] = places[id]["name"]
    var problems: Array[String] = []
    var numbers := {}
    if DirAccess.get_directories_at(dir).is_empty():
        problems.append("There are no missions in %s." % dir)
    for folder in DirAccess.get_directories_at(dir):
        var path := "%s/%s/mission.json" % [dir, folder]
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if not data is Dictionary:
            problems.append("Could not read the mission %s." % path)
            continue
        var problem := _check(data, places, economy, farm)
        if problem != "":
            problems.append("The mission %s: %s" % [path, problem])
            continue
        var number := int(data["number"])
        if numbers.has(number):
            problems.append(
                "The missions %s and %s have the same number." % [numbers[number], data["id"]]
            )
        if folder != "%03d_%s" % [number, data["id"]]:
            problems.append(
                "The folder of the mission %s should be %03d_%s." % [path, number, data["id"]]
            )
        numbers[number] = data["id"]
        missions[data["id"]] = data
    var sorted := numbers.keys()
    sorted.sort()
    for number in sorted:
        order.append(numbers[number])
    for id in order:
        for needed in missions[id].get("requires", []):
            if not missions.has(needed):
                problems.append("The mission %s requires the unknown mission %s." % [id, needed])
            elif int(missions[needed]["number"]) >= int(missions[id]["number"]):
                problems.append("The mission %s requires the later mission %s." % [id, needed])
    return problems[0] if not problems.is_empty() else ""


## What is wrong with the data of a mission, or "".
func _check(data: Dictionary, places: Dictionary, economy: Economy, farm: Farm) -> String:
    var problems: Array[String] = []
    for key in ["number", "id", "title", "giver", "offer", "steps", "reward"]:
        if not data.has(key):
            problems.append("it has no %s." % key)
    if not problems.is_empty():
        return problems[0]
    if not places.has(data["giver"].get("place", "")):
        problems.append("it is given at the unknown place %s." % data["giver"].get("place", ""))
    var items: Dictionary = data.get("items", {})
    for item in items.keys():
        if not items[item].has("name"):
            problems.append("its item %s has no name." % item)
    if data["steps"].is_empty():
        problems.append("it has no steps.")
    for step in data["steps"]:
        problems.append_array(_check_step(step, items, places, economy, farm))
    problems.append_array(_check_reward(data["reward"], economy, farm))
    return problems[0] if not problems.is_empty() else ""


func _check_step(
    step: Dictionary, items: Dictionary, places: Dictionary, economy: Economy, farm: Farm
) -> Array[String]:
    var problems: Array[String] = []
    var kind: String = step.get("do", "")
    if not kind in STEP_KINDS:
        problems.append("it has a step of the unknown kind %s." % kind)
    for key in ["at", "from", "to"]:
        if step.has(key) and not places.has(step[key]):
            problems.append("a step goes to the unknown place %s." % step[key])
    if kind in ["visit", "pay", "deliver"] and not step.has("at"):
        problems.append("a %s step has no place." % kind)
    match kind:
        "pay":
            if int(step.get("silver", 0)) <= 0:
                problems.append("a pay step has no silver.")
        "carry":
            var item: String = step.get("item", "")
            if not step.has("from") or not step.has("to"):
                problems.append("a carry step needs a place from and a place to.")
            if not items.has(item):
                problems.append("a carry step carries the undeclared item %s." % item)
            elif int(step.get("count", 1)) > 1 and not items[item].has("many"):
                problems.append("the item %s is carried by the many, but has no many." % item)
            if step.has("who"):
                problems.append("a carry step has from_who and to_who, not who.")
        "deliver":
            var item: String = step.get("item", "")
            if item.begins_with("animal:"):
                if not farm.animal_kinds.has(item.trim_prefix("animal:")):
                    problems.append("a deliver step asks for the unknown animal %s." % item)
            elif not economy.goods.has(item):
                problems.append("a deliver step asks for the unknown good %s." % item)
        "hail":
            var skipper: String = step.get("skipper", "")
            if skipper != "" and not _skipper_known(skipper):
                problems.append("a hail step asks for the unknown skipper %s." % skipper)
        "have":
            if not farm.animal_kinds.has(step.get("animal", "")):
                problems.append("a have step asks for the unknown animal %s." % step.get("animal"))
        "plant":
            if not farm.crop_kinds.has(step.get("crop", "")):
                problems.append("a plant step asks for the unknown crop %s." % step.get("crop"))
    return problems


func _check_reward(reward: Dictionary, economy: Economy, farm: Farm) -> Array[String]:
    var problems: Array[String] = []
    for good in reward.get("goods", {}).keys():
        if not economy.goods.has(good):
            problems.append("it rewards the unknown good %s." % good)
    for animal in reward.get("animals", {}).keys():
        if not farm.animal_kinds.has(animal):
            problems.append("it rewards the unknown animal %s." % animal)
    if reward.has("plot"):
        var found := false
        for plot in farm.plot_kinds:
            found = found or plot["id"] == reward["plot"]
        if not found:
            problems.append("it rewards the unknown plot %s." % reward["plot"])
    return problems


static func _skipper_known(picture: String) -> bool:
    for skipper in Gossip.SKIPPERS:
        if skipper["picture"] == picture:
            return true
    return false


## Start afresh: no mission done, none under way.
func reset() -> void:
    done = {}
    active = []


# ---------------------------------------------------------------------------
# Which missions there are
# ---------------------------------------------------------------------------


## The missions which the players can take on now, by their number.
func available() -> Array[String]:
    var result: Array[String] = []
    for id in order:
        if done.has(id) or is_active(id):
            continue
        var ready := true
        for needed in missions[id].get("requires", []):
            ready = ready and done.has(needed)
        if ready:
            result.append(id)
    return result


## The missions which the people of the [param place] offer now.
func offers_at(place: String) -> Array[String]:
    var result: Array[String] = []
    for id in available():
        if missions[id]["giver"]["place"] == place:
            result.append(id)
    return result


func is_active(id: String) -> bool:
    return _entry(id) != {}


## Whether the players can take on one more mission.
func can_accept() -> bool:
    return active.size() < MAX_ACTIVE


## Take on the mission on the [param day].
func accept(id: String, day: int) -> void:
    if is_active(id) or done.has(id):
        return
    active.append({"id": id, "step": 0, "accepted": day, "since": day, "loaded": 0, "count": 0})


## How many stars the players won in all.
func stars() -> int:
    var total := 0
    for id in done.keys():
        total += int(done[id])
    return total


func _entry(id: String) -> Dictionary:
    for entry in active:
        if entry["id"] == id:
            return entry
    return {}


## The step of the mission under way.
func current_step(id: String) -> Dictionary:
    var entry := _entry(id)
    if entry.is_empty():
        return {}
    return missions[id]["steps"][int(entry["step"])]


# ---------------------------------------------------------------------------
# The items of the missions in the boat
# ---------------------------------------------------------------------------


## The key of an item of a mission in the cargo.
static func item_key(mission: String, item: String) -> String:
    return "%s%s:%s" % [PREFIX, mission, item]


static func is_item(key: String) -> bool:
    return key.begins_with(PREFIX)


func _item(key: String) -> Dictionary:
    var parts := key.trim_prefix(PREFIX).split(":")
    if parts.size() != 2 or not missions.has(parts[0]):
        return {}
    return missions[parts[0]].get("items", {}).get(parts[1], {})


## The name of the item of a mission, e.g., "Wedding ale".
func item_name(key: String) -> String:
    return str(_item(key).get("name", key))


## The color of the crate of the item of a mission.
func item_color(key: String) -> Color:
    return Color(str(_item(key).get("color", "c8a878")))


## The picture of the item of a mission: [sheet, name], or [].
func item_picture(key: String) -> Array:
    return _item(key).get("picture", [])


# ---------------------------------------------------------------------------
# What the players should do
# ---------------------------------------------------------------------------


func _name(place: String) -> String:
    return str(_place_names.get(place, place))


## How the texts call [param count] of the [param item]: an item of the
## [param mission] (its "one" and "many", e.g., "Tova", "barrels of ale"), a
## good ("3 crates of ale") or an animal ("a goat", "2 goats").
func _thing(state: Node, item: String, count: int, mission := "") -> String:
    if mission != "" and missions[mission].get("items", {}).has(item):
        var data: Dictionary = missions[mission]["items"][item]
        var one := str(data.get("one", str(data["name"]).to_lower()))
        if count == 1:
            return one
        return "%d %s" % [count, str(data.get("many", one + "s"))]
    var name: String = state.good_name(item).to_lower()
    if item.begins_with("animal:"):
        if count == 1:
            return "a " + name
        return "%d %s" % [count, name if name == "sheep" or name.ends_with("s") else name + "s"]
    if count == 1:
        return "a crate of " + name
    return "%d crates of %s" % [count, name]


static func _upper_first(text: String) -> String:
    return text.left(1).to_upper() + text.substr(1)


## What the players should do next for the mission, e.g., "Bring 3 crates of
## ale to Vargvik (1 of 3 there)."
func hint(state: Node, id: String) -> String:
    var entry := _entry(id)
    if entry.is_empty():
        return ""
    var step := current_step(id)
    var count := int(step.get("count", 1))
    var text := ""
    match step["do"]:
        "visit":
            text = "Row to %s." % _name(step["at"])
        "carry":
            var key := item_key(id, step["item"])
            var carried := int(state.cargo.get(key, 0))
            var name := _thing(state, step["item"], count, id)
            if carried > 0 or int(entry["loaded"]) >= count:
                text = "Bring %s to %s." % [name, _name(step["to"])]
            else:
                text = "Fetch %s in %s." % [name, _name(step["from"])]
            if int(entry["count"]) > 0:
                text += " (%d of %d there)" % [int(entry["count"]), count]
        "deliver":
            text = "Bring %s to %s." % [_thing(state, step["item"], count), _name(step["at"])]
            if int(entry["count"]) > 0:
                text += " (%d of %d there)" % [int(entry["count"]), count]
        "pay":
            text = "Pay %d silver in %s." % [int(step["silver"]), _name(step["at"])]
        "hail":
            var who := "a boat on the lakes"
            if step.get("skipper", "") != "":
                who = _skipper_name(step["skipper"])
            text = "Hail %s: glide slowly beside the boat." % who
            if count > 1:
                text = (
                    "Hail %d boats on the lakes (%d of %d)." % [count, int(entry["count"]), count]
                )
        "have":
            text = (
                "Have %d %s on your farm."
                % [count, state.farm.animal_kinds[step["animal"]]["name"].to_lower()]
            )
        "plant":
            text = "Plant %s on your farm." % state.farm.crop_kinds[step["crop"]]["name"].to_lower()
    var wait := _wait_left(state, entry, step)
    if wait > 0:
        text += " Wait %d night%s first." % [wait, "" if wait == 1 else "s"]
    return text


static func _skipper_name(picture: String) -> String:
    for skipper in Gossip.SKIPPERS:
        if skipper["picture"] == picture:
            return skipper["name"]
    return picture


## Where the players should row for the mission next, or "" (on the lakes).
func target(state: Node, id: String) -> String:
    var entry := _entry(id)
    if entry.is_empty():
        return ""
    var step := current_step(id)
    match step["do"]:
        "visit", "deliver", "pay":
            return step["at"]
        "carry":
            var carried := int(state.cargo.get(item_key(id, step["item"]), 0))
            if carried > 0 or int(entry["loaded"]) >= int(step.get("count", 1)):
                return step["to"]
            return step["from"]
        "have", "plant":
            return "home"
    return ""


func _wait_left(state: Node, entry: Dictionary, step: Dictionary) -> int:
    return maxi(0, int(entry["since"]) + int(step.get("wait", 0)) - int(state.day))


## Why the players can not go on with the missions at the [param place] now:
## Array of texts (e.g., "Your boat is full").
func blocked_at(state: Node, place: String) -> Array[String]:
    var result: Array[String] = []
    for entry in active:
        var id: String = entry["id"]
        var step := current_step(id)
        if target(state, id) != place and not (step["do"] == "carry" and step["from"] == place):
            continue
        var title: String = missions[id]["title"]
        if _wait_left(state, entry, step) > 0:
            var wait := _wait_left(state, entry, step)
            result.append("%s: come back in %d day%s." % [title, wait, "" if wait == 1 else "s"])
            continue
        match step["do"]:
            "carry":
                var left := int(step.get("count", 1)) - int(entry["loaded"])
                if step["from"] == place and left > 0 and not state.has_room():
                    result.append(
                        (
                            "%s: %s wait%s here, but your boat is full. Make room!"
                            % [
                                title,
                                _upper_first(_thing(state, step["item"], left, id)),
                                "s" if left == 1 else ""
                            ]
                        )
                    )
            "deliver":
                var left := int(step.get("count", 1)) - int(entry["count"])
                result.append("%s: bring %s here." % [title, _thing(state, step["item"], left)])
            "pay":
                result.append("%s: you need %d silver." % [title, int(step["silver"])])
            "have":
                result.append(hint(state, id))
            "plant":
                result.append(hint(state, id))
    return result


# ---------------------------------------------------------------------------
# Doing the missions
# ---------------------------------------------------------------------------


## The players are at the [param place] (docked, or at home on the farm): do
## what the missions under way ask there. Return what happened, as screens
## to show: Array of {"title", "text", "who" (Dictionary), "place", "done" (bool)}.
func arrive(state: Node, place: String) -> Array:
    var events: Array = []
    var moved := true
    while moved:
        moved = false
        for entry in active.duplicate():
            var result := _try_step(state, entry, place)
            events.append_array(result["events"])
            moved = moved or result["advanced"]
    return events


## The players hailed the skipper of the [param picture]: return what
## happened (see [method arrive]).
func hail(state: Node, picture: String) -> Array:
    var events: Array = []
    for entry in active.duplicate():
        var step := current_step(entry["id"])
        if step["do"] != "hail" or _wait_left(state, entry, step) > 0:
            continue
        if step.get("skipper", "") != "" and step["skipper"] != picture:
            continue
        entry["count"] = int(entry["count"]) + 1
        var count := int(step.get("count", 1))
        var says: Array = step.get("says", [])
        var who := {"name": _skipper_name(picture), "picture": picture}
        if int(entry["count"]) < count:
            var line: String = (
                says[int(entry["count"]) - 1]
                if int(entry["count"]) - 1 < says.size()
                else "I know nothing of it, sorry. Ask the others!"
            )
            events.append(_event(entry["id"], line, who, ""))
            continue
        var text: String = step.get("say", says[-1] if not says.is_empty() else "Good luck!")
        events.append(_event(entry["id"], text, who, ""))
        events.append_array(_advance(state, entry))
    return events


func _event(
    id: String, text: String, who: Dictionary, place: String, finished := false
) -> Dictionary:
    return {
        "title": missions[id]["title"], "text": text, "who": who, "place": place, "done": finished
    }


## Who speaks at the [param place] for the step: its [param key] ("who", or
## for a carry step "from_who" and "to_who"), or the giver at their place.
func _who(id: String, step: Dictionary, place: String, key := "who") -> Dictionary:
    if step.has(key):
        return step[key]
    var giver: Dictionary = missions[id]["giver"]
    if giver["place"] == place:
        return giver
    return {}


func _try_step(state: Node, entry: Dictionary, place: String) -> Dictionary:
    var id: String = entry["id"]
    var step := current_step(id)
    var events: Array = []
    if _wait_left(state, entry, step) > 0:
        return {"events": events, "advanced": false}
    var count := int(step.get("count", 1))
    var complete := false
    match step["do"]:
        "visit":
            complete = step["at"] == place
        "pay":
            if step["at"] == place and state.silver >= int(step["silver"]):
                state.silver -= int(step["silver"])
                complete = true
        "have":
            complete = place == "home" and int(state.farm.animals.get(step["animal"], 0)) >= count
        "plant":
            if place == "home":
                for field in state.farm.fields:
                    complete = complete or field["crop"] == step["crop"]
        "deliver":
            if step["at"] == place:
                var item: String = step["item"]
                var given: int = state.remove_cargo(item, count - int(entry["count"]))
                if given > 0:
                    entry["count"] = int(entry["count"]) + given
                    if place == "home":
                        if item.begins_with("animal:"):
                            for i in range(given):
                                state.farm.add_animal(item.trim_prefix("animal:"))
                        else:
                            state.farm.put(item, given)
                    complete = int(entry["count"]) >= count
                    if not complete:
                        events.append(
                            _event(
                                id,
                                (
                                    "Thank you! That is %d of %d. Bring %s more."
                                    % [
                                        int(entry["count"]),
                                        count,
                                        _thing(state, item, count - int(entry["count"]))
                                    ]
                                ),
                                _who(id, step, place),
                                place
                            )
                        )
        "carry":
            var key := item_key(id, step["item"])
            if step["to"] == place:
                var given: int = state.remove_cargo(key, count - int(entry["count"]))
                if given > 0:
                    entry["count"] = int(entry["count"]) + given
                    complete = int(entry["count"]) >= count
                    if not complete:
                        var left := count - int(entry["count"])
                        events.append(
                            _event(
                                id,
                                (
                                    "Unloaded %s. %s still wait%s in %s."
                                    % [
                                        _thing(state, step["item"], given, id),
                                        _upper_first(_thing(state, step["item"], left, id)),
                                        "s" if left == 1 else "",
                                        _name(step["from"])
                                    ]
                                ),
                                _who(id, step, place, "to_who"),
                                place
                            )
                        )
            if step["from"] == place and not complete:
                var loaded := 0
                while int(entry["loaded"]) < count and state.has_room():
                    state.add_cargo(key)
                    entry["loaded"] = int(entry["loaded"]) + 1
                    loaded += 1
                if loaded > 0:
                    var left := count - int(entry["loaded"])
                    var text: String = (
                        step.get("load_say", "")
                        if int(entry["loaded"]) == loaded and step.has("load_say")
                        else ""
                    )
                    if text == "":
                        text = (
                            "You load %s into your boat." % _thing(state, step["item"], loaded, id)
                        )
                    if left > 0:
                        text += (
                            " Your boat is full: %s wait%s here for the next trip."
                            % [_thing(state, step["item"], left, id), "s" if left == 1 else ""]
                        )
                    else:
                        text += " Now row to %s." % _name(step["to"])
                    events.append(_event(id, text, _who(id, step, place, "from_who"), place))
    if not complete:
        return {"events": events, "advanced": false}
    var speaker := _who(id, step, place, "to_who" if step["do"] == "carry" else "who")
    events.append(_event(id, step.get("say", "Thank you!"), speaker, place))
    events.append_array(_advance(state, entry))
    return {"events": events, "advanced": true}


## The step of the [param entry] is done: go on to the next, or finish the
## mission; return the events of finishing.
func _advance(state: Node, entry: Dictionary) -> Array:
    var id: String = entry["id"]
    entry["step"] = int(entry["step"]) + 1
    entry["since"] = state.day
    entry["loaded"] = 0
    entry["count"] = 0
    if int(entry["step"]) < missions[id]["steps"].size():
        return []
    active.erase(entry)
    var mission: Dictionary = missions[id]
    var took := int(state.day) - int(entry["accepted"]) + 1
    var count := 3
    if mission.has("days"):
        var par := int(mission["days"])
        count = 3 if took <= par else (2 if took <= par + 2 else 1)
    done[id] = count
    var gifts := _reward(state, mission["reward"])
    var text := "Mission done! %s" % "★".repeat(count) + "☆".repeat(3 - count)
    if not gifts.is_empty():
        text += "  You get %s." % ", ".join(gifts)
    if mission.has("fact"):
        text += "  " + str(mission["fact"])
    return [_event(id, text, {}, "", true)]


func _reward(state: Node, reward: Dictionary) -> Array[String]:
    var gifts: Array[String] = []
    if int(reward.get("silver", 0)) > 0:
        state.silver += int(reward["silver"])
        gifts.append("%d silver" % int(reward["silver"]))
    if int(reward.get("capacity", 0)) > 0:
        state.ships.hold_bonus += int(reward["capacity"])
        gifts.append(
            (
                "a bigger hold (room for %d more crate%s)"
                % [int(reward["capacity"]), "" if int(reward["capacity"]) == 1 else "s"]
            )
        )
    var goods: Dictionary = reward.get("goods", {})
    for good in goods.keys():
        state.farm.put(good, int(goods[good]))
        gifts.append("%s for your store" % _thing(state, good, int(goods[good])))
    var animals: Dictionary = reward.get("animals", {})
    for kind in animals.keys():
        for i in range(int(animals[kind])):
            state.farm.add_animal(kind)
        gifts.append("%s for your farm" % _thing(state, "animal:" + kind, int(animals[kind])))
    if reward.has("plot") and not reward["plot"] in state.farm.plots:
        state.farm.add_plot(reward["plot"])
        for plot in state.farm.plot_kinds:
            if plot["id"] == reward["plot"]:
                gifts.append(String(plot["name"]).to_lower())
    if reward.has("gift"):
        gifts.append(str(reward["gift"]))
    return gifts


# ---------------------------------------------------------------------------
# The save
# ---------------------------------------------------------------------------


## The state of the missions, as plain data for the save.
func to_data() -> Dictionary:
    return {"done": done.duplicate(), "active": active.duplicate(true)}


## Restore the state of [method to_data]; the missions which are gone from the
## data are forgotten.
func restore(data: Dictionary) -> void:
    done = {}
    for id in data.get("done", {}).keys():
        if missions.has(id):
            done[id] = int(data["done"][id])
    active = []
    for entry in data.get("active", []):
        if missions.has(entry.get("id", "")):
            var step := int(entry.get("step", 0))
            if step < missions[entry["id"]]["steps"].size():
                (
                    active
                    . append(
                        {
                            "id": entry["id"],
                            "step": step,
                            "accepted": int(entry.get("accepted", 1)),
                            "since": int(entry.get("since", 1)),
                            "loaded": int(entry.get("loaded", 0)),
                            "count": int(entry.get("count", 0)),
                        }
                    )
                )
