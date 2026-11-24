extends SceneTree
## How long the farm and the trading last: play the game's rules (GameState,
## Economy, Farm, Missions, Ships) with bots of several strategies, many times,
## and measure when the players can buy what there is to buy (the ships, the
## land), in hours of play and in tasks done.
##
## The bots do not row: a trip between two places takes the length of its
## route (LakeMap.route_between) at the speed of the ship, and every port, every
## hail and every night take a little time (see the constants). Everything else
## is the game's own rules: the prices move with every crate and recover over
## the nights, the animals eat and give, the crops grow, the tasks pay.
##
## The strategies:
##
## * tasks: a careful child: the tasks one after the other, trading only when
##   the silver runs short;
## * mixed: the tasks, and on every trip the free room of the hold filled with
##   what sells better where the boat goes;
## * trader: no tasks, only trading, the best margin for the time;
## * farmer: the tasks, and the farm grown (animals, fields), its goods sold;
## * random: random but legal choices (a fuzzer of the rules: the silver never
##   goes below zero, the cargo fits the hold).
##
## Each buys the next ship and the next plot as soon as the silver allows
## (keeping a little), except random, which buys at random.
##
##   $GODOT --headless --path . --script dev/balance/balance.gd -- --no-camera \
##       [--runs=20] [--hours=12] [--speed=8] [--strategies=tasks,mixed,...]

## How fast the rowing boat goes on average, in metres a second (a child who
## rows steadily; the ships go faster by their "top").
const DEFAULT_SPEED := 8.0

## How long a port (the screens and the choices), a hail and a night's sleep
## take, in seconds of play.
const PORT_SECONDS := 60.0
const HAIL_SECONDS := 90.0
const SLEEP_SECONDS := 20.0

## The pasture which the farmer keeps free for the tasks which want animals.
const SPARE_PASTURE := 3.0

## The silver which the bots keep when they buy a ship or land.
const RESERVE := 20

## The most crates bought of one good in one go, and the least margin a
## crate must leave.
const MOST_CRATES := 40
const LEAST_MARGIN := 1

const ANIMALS_SOLD := PortScreens.ANIMALS_SOLD

var _state: Node
var _map: LakeMap
var _rng := RandomNumberGenerator.new()
var _speed := DEFAULT_SPEED

## The run now: the seconds of play, the events, and the farm's goods.
var _clock := 0.0
var _events := {}
var _farm_value := 0.0
var _trade_profit := 0.0
var _bought := {}
var _broken: Array[String] = []


func _initialize() -> void:
    _run.call_deferred()


static func _argument(name: String, default: String) -> String:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--%s=" % name):
            return arg.trim_prefix("--%s=" % name)
    return default


func _run() -> void:
    _state = root.get_node("/root/GameState")
    _state.saves_dir = "user://balance"
    _state.settings_path = "user://balance/settings.cfg"
    _state.save_path = "user://balance/none.json"
    _map = LakeMap.new()
    root.add_child(_map)
    _map.load_map(GameState.MAP_PATH)
    var runs := int(_argument("runs", "20"))
    var hours := float(_argument("hours", "12"))
    _speed = float(_argument("speed", str(DEFAULT_SPEED)))
    var strategies := _argument("strategies", "tasks,mixed,trader,farmer,random").split(",")
    print(
        (
            "%d runs of each strategy, up to %.0f hours of play, rowing %.1f m/s, %d s a port%s%s"
            % [
                runs,
                hours,
                _speed,
                PORT_SECONDS,
                (
                    ", ships " + _argument("ship-prices", "")
                    if _argument("ship-prices", "") != ""
                    else ""
                ),
                (
                    ", rewards x" + _argument("reward-scale", "")
                    if _argument("reward-scale", "") != ""
                    else ""
                ),
            ]
        )
    )
    var all := {}
    for strategy in strategies:
        var results: Array = []
        for run in range(runs):
            results.append(_play(strategy, 1000 + run, hours * 3600.0))
        all[strategy] = results
        _summarize(strategy, results)
    if not _broken.is_empty():
        for broken in _broken.slice(0, 12):
            print("BROKEN: ", broken)
    _map.queue_free()
    await process_frame
    quit(1 if not _broken.is_empty() else 0)


# ---------------------------------------------------------------------------
# One run
# ---------------------------------------------------------------------------


func _play(strategy: String, seed_value: int, limit: float) -> Dictionary:
    _state.new_voyage()
    _tune()
    _rng.seed = seed_value
    seed(seed_value)
    _clock = 0.0
    _events = {}
    _farm_value = 0.0
    _trade_profit = 0.0
    _bought = {}
    var steps := 0
    var stuck := 0
    var done_before := 0
    while _clock < limit and steps < 20000:
        steps += 1
        match strategy:
            "trader":
                _trade_step(true)
            "random":
                _random_step()
            _:
                _task_step(strategy)
        if strategy != "random":
            _buy_upgrades()
        _check()
        var done: int = _state.missions.done.size()
        stuck = 0 if done > done_before else stuck + 1
        done_before = done
        var open: bool = (
            not _state.missions.active.is_empty() or not _state.missions.available().is_empty()
        )
        if strategy != "trader" and strategy != "random" and open and stuck > 400:
            _broken.append(
                (
                    "%s %d: stuck with %s, the pasture %.2f of %.0f, the hold %d of %d, %d silver"
                    % [
                        strategy,
                        seed_value,
                        _state.missions.active,
                        _state.farm.room_used(),
                        _state.farm.pasture,
                        _state.load_count(),
                        _state.capacity,
                        _state.silver
                    ]
                )
            )
            break
        if _everything_bought() and (done >= _state.missions.order.size() or strategy == "trader"):
            break
    return {
        "events": _events.duplicate(),
        "hours": _clock / 3600.0,
        "tasks": _state.missions.done.size(),
        "silver": _state.silver,
        "day": _state.day,
        "farm": _farm_value,
        "trade": _trade_profit,
    }


func _note(event: String) -> void:
    if not _events.has(event):
        _events[event] = {"hours": _clock / 3600.0, "tasks": _state.missions.done.size()}


func _check() -> void:
    if _state.silver < 0:
        _broken.append("the silver went below zero: %d" % _state.silver)
    if _state.load_count() > _state.capacity:
        _broken.append(
            "the cargo %d is more than the hold %d" % [_state.load_count(), _state.capacity]
        )


func _everything_bought() -> bool:
    var ships: Ships = _state.ships
    for plot in _state.farm.plot_kinds:
        if not plot["id"] in _state.farm.plots:
            return false
    return ships.owned.size() == ships.ids.size()


## Try another balance (after the data loads anew): -- --ship-prices=80,220,450,800
## and -- --reward-scale=1.5 (the silver of the tasks' rewards).
func _tune() -> void:
    var prices := _argument("ship-prices", "")
    if prices != "":
        var ships: Ships = _state.ships
        var values := prices.split(",")
        for i in range(mini(values.size(), ships.ids.size() - 1)):
            ships.kinds[ships.ids[i + 1]]["price"] = int(values[i])
    var scale := float(_argument("reward-scale", "1.0"))
    if scale != 1.0:
        for id in _state.missions.missions:
            var reward: Dictionary = _state.missions.missions[id]["reward"]
            if reward.has("silver"):
                reward["silver"] = roundi(float(reward["silver"]) * scale)


# ---------------------------------------------------------------------------
# Going places
# ---------------------------------------------------------------------------


func _route(from: String, to: String) -> float:
    if from == to:
        return 0.0
    var points := _map.route_between(from, to)
    var length := 0.0
    for i in range(1, points.size()):
        length += points[i - 1].distance_to(points[i])
    return length


func _boat_speed() -> float:
    return _speed * float(_state.ships.data().get("top", 1.0))


## Row to the place [param id] and dock there: the tasks do what they ask.
func _go(id: String) -> void:
    var from: String = _state.place if _state.place != "" else "home"
    _clock += _route(from, id) / _boat_speed() + PORT_SECONDS
    _state.place = id
    _state.missions.arrive(_state, id)
    if id == "home":
        _at_home()


## At home: the animals go onto the farm (with room), the ripe crops are
## harvested.
func _at_home() -> void:
    var farm: Farm = _state.farm
    for item in _state.cargo.keys():
        if item.begins_with("animal:") and not _needed(true).has(item):
            var kind: String = item.trim_prefix("animal:")
            while int(_state.cargo.get(item, 0)) > 0 and farm.has_room_for(kind):
                farm.add_animal(kind)
                _state.remove_cargo(item)
    for i in range(farm.fields.size()):
        if farm.fields[i]["crop"] != "" and farm.days_to_ripe(i, _state.day) == 0:
            var result: Dictionary = farm.harvest(i, _state.day)
            _farm_value += float(result["count"]) * _base(result["good"])


func _sleep() -> void:
    if _state.place != "home":
        _go("home")
    var before: Dictionary = _state.farm.store.duplicate()
    _clock += SLEEP_SECONDS
    _state.next_day()
    for good in _state.farm.store:
        var gained := float(_state.farm.store[good]) - float(before.get(good, 0.0))
        if gained > 0.0:
            _farm_value += gained * _base(good)
    _note("slept")
    _at_home()


func _base(good: String) -> float:
    return float(_state.economy.goods[good]["base"]) if _state.economy.goods.has(good) else 0.0


# ---------------------------------------------------------------------------
# Trading
# ---------------------------------------------------------------------------


## Sell here what sells for more than it cost on average, and all the farm's
## goods.
func _sell_here() -> void:
    var id: String = _state.place
    if not _state.economy.is_market(id):
        return
    var needed := _needed()
    for good in _state.cargo.keys():
        if needed.has(good) or not _state.economy.buys(id, good):
            continue
        var floor_price := int(float(_bought.get(good, 0.0)))
        while int(_state.cargo.get(good, 0)) > 0:
            var price: int = _state.economy.sell_price(id, good)
            if price < floor_price and _best_elsewhere(good, id) > price:
                break
            if not _state.sell(id, good):
                break
            _trade_profit += price - float(_bought.get(good, 0.0))


func _best_elsewhere(good: String, here: String) -> int:
    var best := 0
    for place in _map.places:
        if place["id"] != here and _state.economy.buys(place["id"], good):
            best = maxi(best, _state.economy.sell_price(place["id"], good))
    return best


## The best trade from here: {"good", "to", "rate"} (silver a second), or {}.
func _best_trade(room: int) -> Dictionary:
    var id: String = _state.place
    var economy: Economy = _state.economy
    var best := {}
    if room <= 0 or not economy.is_market(id):
        return best
    for good in economy.good_ids:
        if not economy.sells(id, good):
            continue
        var price := economy.buy_price(id, good)
        if price > _state.silver:
            continue
        for place in _map.places:
            if place["id"] == id or not economy.buys(place["id"], good):
                continue
            var margin := economy.sell_price(place["id"], good) - price
            if margin < LEAST_MARGIN:
                continue
            # NOTE: Each crate moves the prices: about half the margin stays
            # for a full hold.
            var crates := mini(room, mini(MOST_CRATES, _state.silver / maxi(1, price)))
            var profit := margin * crates * 0.6
            var seconds := _route(id, place["id"]) / _boat_speed() + PORT_SECONDS
            var rate := profit / seconds
            if best.is_empty() or rate > float(best["rate"]):
                best = {"good": good, "to": place["id"], "rate": rate}
    return best


## Buy the [param good] here while it leaves a margin at [param to].
func _buy_for(good: String, to: String, room: int) -> void:
    var id: String = _state.place
    var count := 0
    while count < room and _state.has_room():
        var price: int = _state.economy.buy_price(id, good)
        if price > _state.silver or _state.economy.sell_price(to, good) - price < LEAST_MARGIN:
            break
        if not _state.buy(id, good):
            break
        var had := float(int(_state.cargo.get(good, 0)) - 1)
        _bought[good] = (float(_bought.get(good, 0.0)) * had + price) / (had + 1.0)
        count += 1


## One trading trip: sell here, buy the best, row there; with nothing good to
## trade, sleep (the prices recover over the nights) or go to a market.
func _trade_step(may_sleep: bool) -> void:
    _sell_here()
    var trade := _best_trade(_state.capacity - _state.load_count())
    if trade.is_empty() and _state.silver < 10 and _sell_farm_goods():
        return
    if trade.is_empty():
        if may_sleep and _rng.randf() < 0.5:
            _sleep()
        else:
            _go(_random_market())
        return
    _buy_for(trade["good"], trade["to"], _state.capacity - _state.load_count())
    _go(trade["to"])
    _sell_here()


## Without silver: fetch what the farm made (not the feed) and sell it where
## it sells best; return whether there was any.
func _sell_farm_goods() -> bool:
    var farm: Farm = _state.farm
    var goods: Array = farm.store.keys().filter(
        func(good: String) -> bool: return good not in ["hay", "grain"] and farm.crates(good) > 0
    )
    if goods.is_empty():
        return false
    if _state.place != "home":
        _go("home")
    var best := ""
    for good in goods:
        while farm.crates(good) > 0 and _state.has_room():
            farm.take(good, 1)
            _state.add_cargo(good)
            best = good
    if best == "":
        return false
    _note("sold the farm's goods")
    _go(_state.economy.best_sell(best)["place"])
    _sell_here()
    return true


func _random_market() -> String:
    var markets: Array = _map.places.filter(
        func(place: Dictionary) -> bool:
            return _state.economy.is_market(place["id"]) and place["id"] != _state.place
    )
    return markets[_rng.randi() % markets.size()]["id"]


# ---------------------------------------------------------------------------
# The tasks
# ---------------------------------------------------------------------------


## What the tasks under way need: item -> how many; with [param elsewhere],
## only what goes to other places than home.
func _needed(elsewhere := false) -> Dictionary:
    var needed := {}
    for entry in _state.missions.active:
        var step: Dictionary = _state.missions.current_step(entry["id"])
        if step["do"] == "deliver" and not (elsewhere and step["at"] == "home"):
            needed[step["item"]] = (
                int(needed.get(step["item"], 0)) + int(step.get("count", 1)) - int(entry["count"])
            )
        elif step["do"] == "have" and not elsewhere:
            needed["animal:" + step["animal"]] = int(step.get("count", 1))
    return needed


## One step of the tasks: take the next, do what the first under way asks
## (earning the silver for it by trading), and with the [param strategy]
## "mixed", carry goods to sell on the way, with "farmer", grow the farm.
func _task_step(strategy: String) -> void:
    var missions: Missions = _state.missions
    _take_tasks()
    if strategy == "farmer":
        _grow_farm()
    if missions.active.is_empty():
        var next := missions.available()
        if next.is_empty():
            _trade_step(true)
            return
        _go(missions.missions[next[0]]["giver"]["place"])
        return
    var entry: Dictionary = missions.active[0]
    var id: String = entry["id"]
    var step := missions.current_step(id)
    if missions._wait_left(_state, entry, step) > 0:
        _sleep()
        return
    var goal := _goal(id, entry, step)
    if goal.has("earn"):
        _trade_step(true)
        return
    if goal.has("hail"):
        _clock += HAIL_SECONDS
        var picture: String = goal["hail"]
        if picture == "":
            picture = Gossip.SKIPPERS[_rng.randi() % Gossip.SKIPPERS.size()]["picture"]
        missions.hail(_state, picture)
        return
    var to: String = goal["go"]
    if goal.has("buy"):
        _buy_need(goal["buy"], to)
    if goal.has("plant"):
        _plant(goal["plant"])
    if goal.has("land"):
        _buy_land(goal["land"])
    if goal.has("sell_animal"):
        if _state.place != to:
            _go(to)
        _state.farm.remove_animal(goal["sell_animal"])
        _state.silver += maxi(1, int(_state.farm.animal_kinds[goal["sell_animal"]]["price"]) / 2)
        _note("sold an animal")
        return
    if strategy in ["mixed", "farmer"] and to != _state.place:
        _sell_here()
        var room: int = _state.capacity - _state.load_count() - _room_for_tasks()
        var best := ""
        var margin := LEAST_MARGIN
        for good in _state.economy.good_ids:
            if (
                _state.economy.is_market(_state.place)
                and _state.economy.sells(_state.place, good)
                and _state.economy.buys(to, good)
            ):
                var m: int = (
                    _state.economy.sell_price(to, good)
                    - _state.economy.buy_price(_state.place, good)
                )
                if m > margin:
                    margin = m
                    best = good
        if best != "" and room > 0:
            _buy_for(best, to, room)
    if to != _state.place:
        _go(to)
        if strategy in ["mixed", "farmer"]:
            _sell_here()
    else:
        # NOTE: Here already (e.g., after buying what the task needs): the task
        # goes on when the boat docks again.
        _state.missions.arrive(_state, to)
        if to == "home":
            _at_home()


## The room which the tasks under way still need in the hold.
func _room_for_tasks() -> int:
    var room := 0
    for item in _needed():
        room += maxi(0, int(_needed()[item]) - int(_state.cargo.get(item, 0)))
    return mini(room, 6)


func _take_tasks() -> void:
    var missions: Missions = _state.missions
    var here: String = _state.place
    for id in missions.offers_at(here):
        if missions.active.size() >= 2 or id != missions.available()[0]:
            break
        missions.accept(id, _state.day)
        missions.arrive(_state, here)


## Where the step leads: {"go": place} (and "buy", "plant", "land" to do there
## first), {"hail": picture}, or {"earn": silver}.
func _goal(id: String, entry: Dictionary, step: Dictionary) -> Dictionary:
    var count := int(step.get("count", 1))
    var goal := {}
    match step["do"]:
        "visit":
            goal = {"go": step["at"]}
        "carry":
            goal = {"go": _state.missions.target(_state, id)}
            if goal["go"] == step["from"] and not _state.has_room():
                goal = _make_room()
        "pay":
            goal = (
                {"go": step["at"]}
                if _state.silver >= int(step["silver"])
                else {"earn": int(step["silver"])}
            )
        "deliver":
            goal = _deliver_goal(step, count - int(entry["count"]))
        "hail":
            goal = {"hail": str(step.get("skipper", ""))}
        "have":
            var kind: String = step["animal"]
            if int(_state.farm.animals.get(kind, 0)) >= count:
                goal = {"go": "home"}
            elif int(_state.cargo.get("animal:" + kind, 0)) > 0:
                goal = {"go": "home"}
                if not _state.farm.has_room_for(kind):
                    var plot := _cheapest_plot("pasture")
                    if plot.is_empty():
                        _note("no land left for the animals")
                        goal = _sell_animal_goal(kind)
                    elif int(plot["price"]) > _state.silver:
                        goal = {"earn": int(plot["price"])}
                    else:
                        goal["land"] = "pasture"
            else:
                goal = _deliver_goal({"item": "animal:" + kind, "at": "home"}, 1)
        "plant":
            goal = {"go": "home", "plant": step["crop"]}
    return goal


func _deliver_goal(step: Dictionary, left: int) -> Dictionary:
    var item: String = step["item"]
    var have := int(_state.cargo.get(item, 0))
    if have >= left or (have > 0 and not _state.has_room()):
        return {"go": step["at"]}
    var price := 0
    var where := ""
    if item.begins_with("animal:"):
        var kind := item.trim_prefix("animal:")
        price = int(_state.farm.animal_kinds[kind]["price"])
        for place in _map.places:
            if kind in ANIMALS_SOLD.get(place["kind"], []):
                where = place["id"]
                break
    else:
        var best: Dictionary = _state.economy.best_buy(item)
        price = int(best["price"])
        where = best["place"]
    if _state.silver < price:
        return {"earn": price}
    if not _state.has_room():
        _sell_here_or_unload()
    return {"go": where, "buy": item} if where != _state.place else {"go": where, "buy": item}


func _sell_here_or_unload() -> void:
    _sell_here()


## The hold is full of what no task needs: unload the animals at home, or
## sell the goods at the nearest market.
func _make_room() -> Dictionary:
    for item in _state.cargo:
        if item.begins_with("animal:"):
            return {"go": "home"}
    _sell_here()
    if _state.has_room():
        return {"go": _state.place}
    return {"go": _random_market()}


## Buy what the task needs here (at [param here]), as far as the room and
## the silver go.
func _buy_need(item: String, here: String) -> void:
    if _state.place != here:
        _go(here)
    var left := int(_needed().get(item, 1)) - int(_state.cargo.get(item, 0))
    for i in range(left):
        if not _state.has_room():
            break
        if item.begins_with("animal:"):
            var price := int(_state.farm.animal_kinds[item.trim_prefix("animal:")]["price"])
            if _state.silver < price:
                break
            _state.silver -= price
            _state.add_cargo(item)
        elif not _state.buy(here, item):
            break


func _plant(crop: String) -> void:
    if _state.place != "home":
        _go("home")
    var farm: Farm = _state.farm
    var price := int(farm.crop_kinds[crop]["seed_price"])
    for i in range(farm.fields.size()):
        if farm.fields[i]["crop"] == "" and _state.silver >= price:
            _state.silver -= price
            farm.plant(i, crop, _state.day)
            _state.missions.arrive(_state, "home")
            return
    # NOTE: No free field: buy one, or wait for a harvest.
    if not _buy_land("fields"):
        _sleep()


## The pasture is full and no land is left: sell the animal which takes the
## most room (not of the [param keep] kind) where such animals are dealt in.
func _sell_animal_goal(keep: String) -> Dictionary:
    var farm: Farm = _state.farm
    var best := ""
    for kind in farm.animals:
        if kind == keep:
            continue
        if (
            best == ""
            or float(farm.animal_kinds[kind]["room"]) > float(farm.animal_kinds[best]["room"])
        ):
            best = kind
    if best == "":
        return {}
    for place in _map.places:
        if best in ANIMALS_SOLD.get(place["kind"], []):
            return {"go": place["id"], "sell_animal": best}
    return {}


## The cheapest plot not yet bought with more [param what], or {}.
func _cheapest_plot(what: String) -> Dictionary:
    var best := {}
    for plot in _state.farm.plot_kinds:
        if plot["id"] in _state.farm.plots or int(plot[what]) <= 0:
            continue
        if best.is_empty() or int(plot["price"]) < int(best["price"]):
            best = plot
    return best


## Buy the cheapest plot with more [param what] which the silver allows.
func _buy_land(what: String) -> bool:
    var best := {}
    for plot in _state.farm.plot_kinds:
        if plot["id"] in _state.farm.plots or int(plot[what]) <= 0:
            continue
        if int(plot["price"]) > _state.silver:
            continue
        if best.is_empty() or int(plot["price"]) < int(best["price"]):
            best = plot
    if best.is_empty():
        return false
    _state.silver -= int(best["price"])
    _state.farm.add_plot(best["id"])
    _note("land " + str(best["id"]))
    return true


# ---------------------------------------------------------------------------
# Spending
# ---------------------------------------------------------------------------


## Buy the next ship (rowing to the shipyard) and the next plot, as soon as
## the silver allows, keeping a little.
func _buy_upgrades() -> void:
    var ships: Ships = _state.ships
    for id in ships.ids:
        if id in ships.owned:
            continue
        if _state.silver >= int(ships.kinds[id]["price"]) + RESERVE:
            _go(ships.shipyard)
            ships.buy(_state, id)
            ships.take(id, _state.load_count())
            _note("ship " + id)
        break
    for plot in _state.farm.plot_kinds:
        if plot["id"] in _state.farm.plots:
            continue
        if _state.silver >= int(plot["price"]) + RESERVE:
            _state.silver -= int(plot["price"])
            _state.farm.add_plot(plot["id"])
            _note("land " + str(plot["id"]))
        break
    if _everything_bought():
        _note("everything")


## The farmer keeps the fields sown and buys animals which the farm can feed.
func _grow_farm() -> void:
    var farm: Farm = _state.farm
    if _state.place == "home":
        for i in range(farm.fields.size()):
            if farm.fields[i]["crop"] == "" and _state.silver > 10:
                var crop := "meadow" if i % 2 == 0 else "barley"
                _state.silver -= int(farm.crop_kinds[crop]["seed_price"])
                farm.plant(i, crop, _state.day)
        # NOTE: The farm's goods go along to be sold.
        var room: int = _state.capacity - _state.load_count() - _room_for_tasks() - 4
        for good in farm.store.keys():
            if good in ["hay", "grain"]:
                continue
            while farm.crates(good) > 0 and room > 0:
                room -= 1
                farm.take(good, 1)
                _state.add_cargo(good)
    var kind: String = _state.place
    var sold: Array = ANIMALS_SOLD.get(_map.place(kind).get("kind", ""), [])
    for animal in sold:
        var price := int(farm.animal_kinds[animal]["price"])
        var spare: float = (
            farm.pasture - farm.room_used() - float(farm.animal_kinds[animal]["room"])
        )
        if _state.silver > price + 60 and spare >= SPARE_PASTURE and _state.has_room():
            _state.silver -= price
            _state.add_cargo("animal:" + animal)


# ---------------------------------------------------------------------------
# Random
# ---------------------------------------------------------------------------


func _random_step() -> void:
    var choice := _rng.randi() % 10
    if choice < 4:
        _go(_map.places[_rng.randi() % _map.places.size()]["id"])
    elif choice < 6 and _state.economy.is_market(_state.place):
        var goods: Array = _state.economy.good_ids.filter(
            func(good: String) -> bool: return _state.economy.sells(_state.place, good)
        )
        if not goods.is_empty():
            for i in range(_rng.randi_range(1, 6)):
                _state.buy(_state.place, goods[_rng.randi() % goods.size()])
    elif choice < 7:
        for good in _state.cargo.keys():
            _state.sell(_state.place, good)
    elif choice < 8:
        var offers: Array[String] = _state.missions.offers_at(_state.place)
        if not offers.is_empty() and _state.missions.can_accept():
            _state.missions.accept(offers[0], _state.day)
            _state.missions.arrive(_state, _state.place)
    elif choice < 9:
        _sleep()
    else:
        var ships: Ships = _state.ships
        var id: String = ships.ids[_rng.randi() % ships.ids.size()]
        if _state.place == ships.shipyard and ships.buy(_state, id):
            _note("ship " + id)
        if ships.take(id, _state.load_count()):
            pass


# ---------------------------------------------------------------------------
# The report
# ---------------------------------------------------------------------------


func _summarize(strategy: String, results: Array) -> void:
    print("\n== %s (%d runs)" % [strategy, results.size()])
    var events := {}
    for result in results:
        for event in result["events"]:
            events[event] = true
    var names := events.keys()
    names.sort_custom(
        func(a: String, b: String) -> bool:
            return _median(results, a, "hours") < _median(results, b, "hours")
    )
    for event in names:
        var reached := (
            results.filter(func(r: Dictionary) -> bool: return r["events"].has(event)).size()
        )
        print(
            (
                "  %-22s %3d%% of runs, after %5.1f h (%.1f-%.1f), %3.0f tasks"
                % [
                    event,
                    100 * reached / results.size(),
                    _median(results, event, "hours"),
                    _quantile(results, event, "hours", 0.1),
                    _quantile(results, event, "hours", 0.9),
                    _median(results, event, "tasks"),
                ]
            )
        )
    var end := func(key: String) -> float:
        return _median_of(results.map(func(r: Dictionary) -> float: return float(r[key])))
    print(
        (
            (
                "  at the end: %.1f h, %.0f tasks, day %.0f, %.0f silver; "
                + "the farm made %.0f, trading %.0f"
            )
            % [
                end.call("hours"),
                end.call("tasks"),
                end.call("day"),
                end.call("silver"),
                end.call("farm"),
                end.call("trade")
            ]
        )
    )


func _values(results: Array, event: String, key: String) -> Array:
    var values: Array = []
    for result in results:
        if result["events"].has(event):
            values.append(float(result["events"][event][key]))
    values.sort()
    return values


func _median(results: Array, event: String, key: String) -> float:
    return _median_of(_values(results, event, key))


func _quantile(results: Array, event: String, key: String, q: float) -> float:
    var values := _values(results, event, key)
    return values[int(q * (values.size() - 1))] if not values.is_empty() else 0.0


static func _median_of(values: Array) -> float:
    if values.is_empty():
        return 0.0
    var sorted := values.duplicate()
    sorted.sort()
    return float(sorted[sorted.size() / 2])
