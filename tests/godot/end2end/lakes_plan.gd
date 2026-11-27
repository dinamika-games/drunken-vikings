extends RefCounted
## The planner of the bot of the Home Lakes (see lakes_bot.gd): where to go
## next, what the tasks under way need, how to earn the silver they ask, which
## ship to buy, and when to sleep. It only reads the voyage, the map and where
## the boat is; it never chooses on a screen nor waits for the game, so that
## the decisions stay apart from the slow driving of the game.
##
## Not a test itself (its name does not start with test_).

## The most tasks the bot carries at once.
const MAX_TASKS := 2

## The silver which the bot keeps when it buys a ship.
const RESERVE := 20

## A trade under way: {"good", "from", "to"}, or empty.
var trade := {}
## Whether the bot must sleep at home (for the farm to make goods).
var must_sleep := false
## The kind of animal to sell for room on the pasture, or "".
var sell_kind := ""
## Why the players are stuck (see [method next_leg]), or "".
var problem := ""

## The voyage (GameState), the map of the lakes and where the boat is, each
## looked up when needed (the scenes change), and what the bot did (see
## LakesBot.did).
var _voyage: Callable
var _map: Callable
var _boat_at: Callable
var _did: Dictionary


func _init(voyage: Callable, map: Callable, boat_at: Callable, did: Dictionary) -> void:
    _voyage = voyage
    _map = map
    _boat_at = boat_at
    _did = did


func _state() -> Node:
    return _voyage.call()


func _lakes() -> LakeMap:
    return _map.call()


func _boat() -> Vector2:
    return _boat_at.call()


func _tally(what: String) -> void:
    _did[what] = int(_did.get(what, 0)) + 1


## The next ship to buy when there is silver to spare (keeping [constant
## RESERVE]) and the cargo fits its hold, or "".
func next_ship() -> String:
    var state := _state()
    var ships: Ships = state.ships
    for id in ships.ids:
        if not id in ships.owned:
            if (
                state.silver >= int(ships.kinds[id]["price"]) + RESERVE
                and state.load_count() <= ships.hold(id)
            ):
                return id
            return ""
    return ""


## Where to go next: {"go": place} or {"hail": the picture of the skipper,
## "" for any}, with "why".
func next_leg() -> Dictionary:
    var state := _state()
    var missions: Missions = state.missions
    var plan := {}
    if next_ship() != "" and not trade.has("good"):
        plan = {"go": state.ships.shipyard, "why": "buy the %s" % next_ship()}
    if plan.is_empty():
        plan = _task_plan()
    if plan.is_empty() and not trade.is_empty():
        if int(state.cargo.get(trade["good"], 0)) > 0:
            plan = {"go": trade["to"], "why": "sell " + trade["good"]}
        else:
            trade = {}
    if plan.is_empty():
        var next := missions.available()
        if not next.is_empty() and missions.active.size() < MAX_TASKS:
            plan = {"go": missions.missions[next[0]]["giver"]["place"], "why": "take " + next[0]}
        elif not missions.active.is_empty():
            plan = _make_room()
        else:
            plan = {"go": "home", "why": "rest"}
    return plan


## Where the first task under way which can go on leads, or {}.
func _task_plan() -> Dictionary:
    var state := _state()
    var missions: Missions = state.missions
    for entry in missions.active:
        var id: String = entry["id"]
        var step := missions.current_step(id)
        if missions._wait_left(state, entry, step) > 0:
            return _night_plan("wait for " + id)
        var plan := _step_plan(id, entry, step)
        if not plan.is_empty():
            return plan
    return {}


## Where the step of the task [param id] leads, or {} if it waits for room.
func _step_plan(id: String, entry: Dictionary, step: Dictionary) -> Dictionary:
    var state := _state()
    var count := int(step.get("count", 1))
    var plan := {}
    match step["do"]:
        "visit":
            plan = {"go": step["at"], "why": id}
        "carry":
            var target: String = state.missions.target(state, id)
            if target != step["from"] or state.has_room():
                plan = {"go": target, "why": id}
        "pay":
            if state.silver >= int(step["silver"]):
                plan = {"go": step["at"], "why": id}
            else:
                plan = _earn(int(step["silver"]))
        "deliver":
            plan = _deliver_plan(id, step, count - int(entry["count"]))
        "hail":
            plan = {"hail": str(step.get("skipper", "")), "why": id}
        "have":
            plan = _have_plan(id, step["animal"], count)
        "plant":
            var price := int(state.farm.crop_kinds[step["crop"]]["seed_price"])
            plan = {"go": "home", "why": id} if state.silver >= price else _earn(price)
    return plan


## Where a task which wants [param count] animals of the [param kind] on the
## farm leads.
func _have_plan(id: String, kind: String, count: int) -> Dictionary:
    var state := _state()
    var aboard := int(state.cargo.get("animal:" + kind, 0))
    if aboard > 0 and not state.farm.has_room_for(kind):
        return _pasture_plan(id)
    if int(state.farm.animals.get(kind, 0)) >= count or aboard > 0:
        return {"go": "home", "why": id}
    return _buy_plan("animal:" + kind, id)


## The animals in the boat need more pasture: earn the silver for the
## cheapest plot with pasture, and buy it at home.
func _pasture_plan(id: String) -> Dictionary:
    var state := _state()
    var price := 1 << 30
    for plot in state.farm.plot_kinds:
        if not plot["id"] in state.farm.plots and int(plot["pasture"]) > 0:
            price = mini(price, int(plot["price"]))
    if price == 1 << 30:
        # NOTE: No land is left: sell the animal which takes the most room
        # where such animals are dealt in (see PortScreens._show_animals).
        var keep: String = state.missions.current_step(id).get("animal", "")
        for kind in state.farm.animals:
            if (
                kind != keep
                and (
                    sell_kind == ""
                    or (
                        float(state.farm.animal_kinds[kind]["room"])
                        > float(state.farm.animal_kinds[sell_kind]["room"])
                    )
                )
            ):
                sell_kind = kind
        if sell_kind == "":
            problem = "the farm has no room for the animals of %s, and nothing to sell" % id
            return {"go": "home", "why": "no land"}
        var places: Array[String] = []
        for place in _lakes().places:
            if sell_kind in PortScreens.ANIMALS_SOLD.get(place["kind"], []):
                places.append(place["id"])
        return {"go": nearest(places), "why": "sell a %s for room for %s" % [sell_kind, id]}
    if state.silver >= price:
        return {"go": "home", "why": "buy land for %s" % id}
    return _earn(price)


## Where a task which wants [param left] more of the item of the [param step]
## delivered leads, or {} if the boat has no room.
func _deliver_plan(id: String, step: Dictionary, left: int) -> Dictionary:
    var state := _state()
    var item: String = step["item"]
    var have := int(state.cargo.get(item, 0))
    if have >= left or (have > 0 and not state.has_room()):
        return {"go": step["at"], "why": id}
    if not state.has_room():
        return {}
    if not item.begins_with("animal:") and step["at"] != "home" and state.farm.crates(item) > 0:
        return {"go": "home", "why": "load %s for %s" % [item, id]}
    return _buy_plan(item, id)


## Where to buy the [param item] (a good, or "animal:<kind>"), or how to earn
## the silver for it first.
func _buy_plan(item: String, id: String) -> Dictionary:
    var state := _state()
    var price := 0
    var places: Array[String] = []
    if item.begins_with("animal:"):
        var kind := item.trim_prefix("animal:")
        price = int(state.farm.animal_kinds[kind]["price"])
        for place in _lakes().places:
            if kind in PortScreens.ANIMALS_SOLD.get(place["kind"], []):
                places.append(place["id"])
    else:
        var best: Dictionary = state.economy.best_buy(item)
        price = int(best["price"])
        places.append(best["place"])
    if state.silver < price:
        return _earn(price)
    return {"go": nearest(places), "why": "buy %s for %s" % [item, id]}


## How to earn [param silver]: sell what can go, or trade.
func _earn(silver: int) -> Dictionary:
    var state := _state()
    if not trade.is_empty() and int(state.cargo.get(trade["good"], 0)) > 0:
        return {"go": trade["to"], "why": "sell %s for %d silver" % [trade["good"], silver]}
    var economy: Economy = state.economy
    var best := {}
    var best_score := 0.0
    for place in _lakes().places:
        if not economy.is_market(place["id"]):
            continue
        for good in economy.good_ids:
            if not economy.sells(place["id"], good):
                continue
            var price := economy.buy_price(place["id"], good)
            var sell: Dictionary = economy.best_sell(good)
            var margin := int(sell["price"]) - price
            if price > state.silver or margin < 2 or sell["place"] == place["id"]:
                continue
            var distance := _boat().distance_to(place["jetty"])
            var score := float(margin) / (distance + 400.0)
            if score > best_score:
                best_score = score
                best = {"good": good, "from": place["id"], "to": sell["place"]}
    if best.is_empty():
        return _earn_from_the_farm(silver)
    trade = best
    _tally("trades")
    return {"go": best["from"], "why": "buy %s to earn %d silver" % [best["good"], silver]}


## Without silver to trade, sell what the farm keeps in its store, or sleep
## so that the farm makes some.
func _earn_from_the_farm(silver: int) -> Dictionary:
    var state := _state()
    var needed := needed()
    var best := ""
    for good in state.farm.store.keys():
        if state.farm.crates(good) > 0 and not needed.has(good):
            if best == "" or state.farm.crates(good) > state.farm.crates(best):
                best = good
    _tally("earned from the farm")
    if best == "":
        must_sleep = true
        return _night_plan("sleep for the farm to make what sells, %d silver" % silver)
    trade = {"good": best, "from": "home", "to": state.economy.best_sell(best)["place"]}
    return {"go": "home", "why": "load %s to earn %d silver" % [best, silver]}


## The boat is full of what the tasks need elsewhere: sell or unload the rest.
func _make_room() -> Dictionary:
    var markets: Array[String] = []
    for place in _lakes().places:
        if _state().economy.is_market(place["id"]):
            markets.append(place["id"])
    return {"go": nearest(markets), "why": "make room"}


## Go home to sleep, for [param why]; but first to the nearest place, as the
## players may sleep only after a day's trip (see GameState.travelled).
func _night_plan(why: String) -> Dictionary:
    if _state().travelled:
        return {"go": "home", "why": why}
    var ids := _lakes().places.map(func(place: Dictionary) -> String: return place["id"])
    ids.erase("home")
    return {"go": nearest(Array(ids, TYPE_STRING, "", null)), "why": "a trip, then " + why}


## The place of the [param places] whose jetty lies nearest to the boat.
func nearest(places: Array[String]) -> String:
    var best := ""
    var best_distance := INF
    for id in places:
        var distance := _boat().distance_to(_lakes().place(id)["jetty"])
        if distance < best_distance:
            best_distance = distance
            best = id
    return best


## What the tasks under way need: item -> how many; with [param elsewhere],
## only what goes to other places than home.
func needed(elsewhere := false) -> Dictionary:
    var state := _state()
    var needed := {}
    for entry in state.missions.active:
        var step: Dictionary = state.missions.current_step(entry["id"])
        if step["do"] == "deliver" and not (elsewhere and step["at"] == "home"):
            needed[step["item"]] = (
                int(needed.get(step["item"], 0)) + int(step.get("count", 1)) - int(entry["count"])
            )
        elif step["do"] == "have" and not elsewhere:
            needed["animal:" + step["animal"]] = int(step.get("count", 1))
    if not trade.is_empty():
        needed[trade["good"]] = 1 << 20
    return needed
