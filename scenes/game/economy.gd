class_name Economy
extends RefCounted

## The prices of the goods in the settlements, and how they move.
##
## Every settlement makes a few goods (cheap there, and for sale), wants a few
## (dear there), and buys the rest at the middle price (see
## data/economy/<region>.json). Selling many crates lowers the price at a
## place, buying many raises it, and the prices go back to the middle over the
## days, so that the same trade does not pay twice in a row. Events (a
## wedding, a feast, a good catch) raise or lower the price of a good at a
## place for some days.
##
## The economy is plain data, so that the game saves it (see [method
## to_data]); it never depends on the scenes.

## A made good costs this share of its base price, a wanted one this share.
const MADE := 0.6
const WANTED := 1.6

## Each crate sold lowers the price by this share, each crate bought raises it.
const PER_CRATE := 0.08

## The pressure of the trades stays within these shares of the price.
const LOWEST := 0.5
const HIGHEST := 1.6

## Each day, the pressure goes back towards none by this share.
const RECOVERY := 0.3

## The traders keep this share of the price as their gain: they buy for less
## than they sell.
const MARGIN := 0.12

## The goods: id -> {"name", "base", "color"}.
var goods := {}

## The ids of the goods, in the order of the data.
var good_ids: Array[String] = []

## The settlements: id of the place -> {"kind", "makes", "wants", "sells_all"}.
var places := {}

## The pressure of the trades: "<place>|<good>" -> a share (1 is none).
var pressure := {}

## The events: Array of {"place", "good", "factor", "days", "title"}.
var events: Array = []


## Load the goods and what the settlements of the region make and want; the
## [param places_of_map] are the places of the map (see LakeMap.places).
## Return what went wrong, or "".
func load_data(goods_path: String, region_path: String, places_of_map: Array) -> String:
    var goods_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(goods_path))
    if not goods_data is Dictionary:
        return "Could not read the goods %s." % goods_path
    goods.clear()
    good_ids.clear()
    for good in goods_data["goods"]:
        goods[good["id"]] = {
            "name": good["name"], "base": float(good["base"]), "color": Color(good["color"])
        }
        good_ids.append(good["id"])

    var region: Variant = JSON.parse_string(FileAccess.get_file_as_string(region_path))
    if not region is Dictionary:
        return "Could not read the region %s." % region_path
    var kinds: Dictionary = region["settlements"]
    places.clear()
    for place in places_of_map:
        var kind: String = place["kind"]
        if not kinds.has(kind):
            return (
                "The region %s says nothing of the settlements of the kind %s."
                % [region_path, kind]
            )
        var settlement: Dictionary = kinds[kind]
        for good in settlement["makes"] + settlement["wants"]:
            if not goods.has(good):
                return "The settlement %s trades the unknown good %s." % [kind, good]
        places[place["id"]] = {
            "kind": kind,
            "makes": settlement["makes"],
            "wants": settlement["wants"],
            "sells_all": bool(settlement.get("sells_all", false)),
        }
    return ""


## Whether the place trades at all (the home farm does not).
func is_market(place: String) -> bool:
    var settlement: Dictionary = places.get(place, {})
    return not settlement.is_empty() and settlement["kind"] != "home"


## Whether the players can buy the good at the place.
func sells(place: String, good: String) -> bool:
    var settlement: Dictionary = places.get(place, {})
    if settlement.is_empty() or settlement["kind"] == "home":
        return false
    return settlement["sells_all"] or good in settlement["makes"]


## Whether the players can sell the good at the place: every market buys
## everything, the wanted goods dearly.
func buys(place: String, good: String) -> bool:
    return is_market(place) and goods.has(good)


## How the place values the good: cheap (-1), as usual (0) or dear (1).
func mood(place: String, good: String) -> int:
    var settlement: Dictionary = places.get(place, {})
    if settlement.is_empty():
        return 0
    if good in settlement["makes"]:
        return -1
    if good in settlement["wants"]:
        return 1
    return 0


## The middle price of the good at the place now, before the margin of the
## traders, in silver.
func value(place: String, good: String) -> float:
    var base: float = goods[good]["base"]
    var share := 1.0
    match mood(place, good):
        -1:
            share = MADE
        1:
            share = WANTED
    share *= float(pressure.get(_key(place, good), 1.0))
    for event in events:
        if event["place"] == place and event["good"] == good:
            share *= float(event["factor"])
    return base * share


## What the players pay for a crate of the good at the place, in silver.
func buy_price(place: String, good: String) -> int:
    return maxi(1, roundi(value(place, good) * (1.0 + MARGIN)))


## What the players get for a crate of the good at the place, in silver.
func sell_price(place: String, good: String) -> int:
    return maxi(1, roundi(value(place, good) * (1.0 - MARGIN)))


## The players bought a crate of the good at the place: the price rises.
func bought(place: String, good: String) -> void:
    _press(place, good, 1.0 + PER_CRATE)


## The players sold a crate of the good at the place: the price falls.
func sold(place: String, good: String) -> void:
    _press(place, good, 1.0 - PER_CRATE)


func _press(place: String, good: String, factor: float) -> void:
    var key := _key(place, good)
    pressure[key] = clampf(float(pressure.get(key, 1.0)) * factor, LOWEST, HIGHEST)


## A day passes: the prices go back towards the middle, and the events end.
func next_day() -> void:
    for key in pressure.keys():
        var share: float = pressure[key]
        share += (1.0 - share) * RECOVERY
        if absf(share - 1.0) < 0.01:
            pressure.erase(key)
        else:
            pressure[key] = share
    var left: Array = []
    for event in events:
        event["days"] = int(event["days"]) - 1
        if event["days"] > 0:
            left.append(event)
    events = left


## Start an event: the price of the good at the place goes up (or down) by
## the [param factor] for some [param days], e.g., ale for a wedding.
func start_event(place: String, good: String, factor: float, days: int, title: String) -> void:
    events.append({"place": place, "good": good, "factor": factor, "days": days, "title": title})


## Where the good sells best now, and for how much: {"place", "price"}.
func best_sell(good: String) -> Dictionary:
    var best := {"place": "", "price": 0}
    for place in places.keys():
        if buys(place, good):
            var price := sell_price(place, good)
            if price > best["price"]:
                best = {"place": place, "price": price}
    return best


## Where the good is cheapest now, and for how much: {"place", "price"}.
func best_buy(good: String) -> Dictionary:
    var best := {"place": "", "price": 1 << 30}
    for place in places.keys():
        if sells(place, good):
            var price := buy_price(place, good)
            if price < best["price"]:
                best = {"place": place, "price": price}
    return best


func _key(place: String, good: String) -> String:
    return "%s|%s" % [place, good]


## The state of the economy which changes, as plain data for the save.
func to_data() -> Dictionary:
    return {"pressure": pressure.duplicate(), "events": events.duplicate(true)}


## Restore the state of [method to_data].
func restore(data: Dictionary) -> void:
    pressure = data.get("pressure", {}).duplicate()
    events = data.get("events", []).duplicate(true)
