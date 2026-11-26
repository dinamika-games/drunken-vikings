class_name Farm
extends RefCounted

## The players' farm: the animals, the fields, the land and the store (see
## data/farm/farm.json and DESIGN.md, "The farm").
##
## The farm lives by the days of the game, which pass only on the trips: each
## day, the animals eat from the store and give their goods, and the crops on
## the fields grow. **No animal ever dies or comes to harm**: without feed,
## it only gives nothing and is hungry until the players bring feed. A crop
## must be harvested within some days after it is ripe; a late harvest is
## smaller (the birds ate some), but never lost.
##
## The cows, the goats and the sheep give milk. The cellar keeps only so much
## of it (see [member milk_kept]); Grandmother Åsa makes cheese of the rest
## overnight, from so many crates of milk a crate of cheese.
##
## The animals have young as steadily as a clock, never faster for a bigger
## herd: a pair of a kind (or more) has one young every so many days (the
## "young_days" of the kind), counting only the days on which the whole herd
## of the kind ate its fill and the farm had room for one more. Hungry or
## crowded, the herd has no young until the players bring feed or buy land.
##
## The farm is plain data, so that the game saves it (see [method to_data]).

## A late harvest loses this share for each day late, but keeps at least the
## share [constant LATE_KEEP].
const LATE_LOSS := 0.25
const LATE_KEEP := 0.25

## The animals and the crops of the data: id -> their properties.
var animal_kinds := {}
var crop_kinds := {}

## The plots of land to buy: Array of {"id", "name", "price", "fields", "pasture"}.
var plot_kinds: Array = []

## The names of the goods (id -> name), for the texts; set by the game (see
## GameState), the ids themselves without.
var good_names := {}

## How many of each animal the farm has: id -> count.
var animals := {}

## Which animals were hungry on the last day (gave nothing): id -> true.
var hungry := {}

## The days counted towards the next young of each kind: id -> days.
var young_progress := {}

## The young born on the last day: id -> how many.
var born := {}

## How many crates of milk the cellar keeps; the rest becomes cheese overnight.
var milk_kept := 2.0

## How many crates of milk make a crate of cheese.
var milk_per_cheese := 2.0

## The store of the farm: good -> crates (with fractions, e.g., 2.5 crates of eggs).
var store := {}

## The fields: Array of {"crop": id or "", "planted": day}.
var fields: Array = []

## How much room the pastures and the barn have for the animals.
var pasture := 0.0

## The plots of land the players bought: Array of ids.
var plots: Array = []


## Load the kinds of the animals, the crops and the plots, and start a new
## farm as the data says; return what went wrong, or "".
func load_data(path: String) -> String:
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary:
        return "Could not read the farm %s." % path
    animal_kinds = data["animals"]
    crop_kinds = data["crops"]
    plot_kinds = data["plots"]
    var start: Dictionary = data["start"]
    animals = start["animals"].duplicate()
    for kind in animals.keys():
        animals[kind] = int(animals[kind])
    store = {}
    for good in start["store"].keys():
        store[good] = float(start["store"][good])
    fields = []
    for i in range(int(start["fields"])):
        fields.append({"crop": "", "planted": 0})
    pasture = float(start["pasture"])
    var cheese: Dictionary = data["cheese"]
    milk_kept = float(cheese["milk_kept"])
    milk_per_cheese = float(cheese["milk_per_cheese"])
    plots = []
    hungry = {}
    young_progress = {}
    born = {}
    return ""


## How much room the animals take now.
func room_used() -> float:
    var used := 0.0
    for kind in animals.keys():
        used += float(animal_kinds[kind]["room"]) * int(animals[kind])
    return used


## Whether there is room for one more animal of the kind.
func has_room_for(kind: String) -> bool:
    return room_used() + float(animal_kinds[kind]["room"]) <= pasture + 1e-6


## Bring an animal home (bought somewhere, carried in the boat).
func add_animal(kind: String) -> void:
    animals[kind] = int(animals.get(kind, 0)) + 1


## Sell an animal away (to another farm); return whether there was one.
func remove_animal(kind: String) -> bool:
    if int(animals.get(kind, 0)) <= 0:
        return false
    animals[kind] = int(animals[kind]) - 1
    if animals[kind] == 0:
        animals.erase(kind)
        hungry.erase(kind)
    if animals.get(kind, 0) < 2:
        young_progress.erase(kind)
    return true


## How many crates of the good are in the store (whole ones).
func crates(good: String) -> int:
    return int(floor(float(store.get(good, 0.0)) + 1e-6))


## Put crates into the store.
func put(good: String, count: float) -> void:
    store[good] = float(store.get(good, 0.0)) + count


## Take crates out of the store; return how many were there to take.
func take(good: String, count: int) -> int:
    var taken := mini(count, crates(good))
    store[good] = float(store.get(good, 0.0)) - taken
    if store[good] <= 1e-6:
        store.erase(good)
    return taken


## How many days the feed lasts for the animals which eat the good.
func feed_days(good: String) -> float:
    var per_day := 0.0
    for kind in animals.keys():
        if animal_kinds[kind]["eats"] == good:
            per_day += float(animal_kinds[kind]["eats_per_day"]) * int(animals[kind])
    if per_day <= 0.0:
        return INF
    return float(store.get(good, 0.0)) / per_day


## Plant the crop on the empty field on the [param day].
func plant(field: int, crop: String, day: int) -> void:
    fields[field] = {"crop": crop, "planted": day}


## How many days until the crop of the field is ripe (0 when ripe); -1 for an empty field.
func days_to_ripe(field: int, day: int) -> int:
    var crop: String = fields[field]["crop"]
    if crop == "":
        return -1
    var ripe: int = int(fields[field]["planted"]) + int(crop_kinds[crop]["days"])
    return maxi(0, ripe - day)


## How many days are left to harvest the ripe crop of the field in time (0 on
## the last day, negative when late); INF if not ripe or empty.
func days_to_harvest(field: int, day: int) -> int:
    var crop: String = fields[field]["crop"]
    if crop == "" or days_to_ripe(field, day) > 0:
        return 1 << 30
    var ripe: int = int(fields[field]["planted"]) + int(crop_kinds[crop]["days"])
    return ripe + int(crop_kinds[crop]["window"]) - day


## Harvest the ripe crop of the field into the store; return {"good", "count"}
## (count 0 if not ripe). Late, the birds ate some.
func harvest(field: int, day: int) -> Dictionary:
    var crop: String = fields[field]["crop"]
    if crop == "" or days_to_ripe(field, day) > 0:
        return {"good": "", "count": 0}
    var kind: Dictionary = crop_kinds[crop]
    var late := maxi(0, -days_to_harvest(field, day))
    var share := maxf(LATE_KEEP, 1.0 - LATE_LOSS * late)
    var count := maxi(1, roundi(float(kind["harvest"]) * share))
    put(kind["gives"], count)
    fields[field] = {"crop": "", "planted": 0}
    return {"good": kind["gives"], "count": count}


## Buy the plot of land: more fields and more pasture.
func add_plot(plot_id: String) -> void:
    for plot in plot_kinds:
        if plot["id"] == plot_id and not plot_id in plots:
            plots.append(plot_id)
            pasture += float(plot["pasture"])
            for i in range(int(plot["fields"])):
                fields.append({"crop": "", "planted": 0})


## A day passes: the animals eat and give, if there is feed; the milk which
## the cellar cannot keep becomes cheese; the fed herds with room have young.
func next_day() -> void:
    hungry = {}
    born = {}
    for kind in animals.keys():
        var count: int = animals[kind]
        var properties: Dictionary = animal_kinds[kind]
        var food: String = properties["eats"]
        var need := float(properties["eats_per_day"]) * count
        if food != "" and need > 0.0:
            if float(store.get(food, 0.0)) + 1e-6 < need:
                hungry[kind] = true
                continue
            store[food] = float(store[food]) - need
            if store[food] <= 1e-6:
                store.erase(food)
        var gives: Dictionary = properties["gives"]
        for good in gives.keys():
            put(good, float(gives[good]) * count)
    _make_cheese()
    for kind in animals.keys():
        if not may_have_young(kind) or hungry.has(kind) or not has_room_for(kind):
            continue
        young_progress[kind] = int(young_progress.get(kind, 0)) + 1
        if int(young_progress[kind]) >= int(animal_kinds[kind]["young_days"]):
            young_progress[kind] = 0
            add_animal(kind)
            born[kind] = 1


## Whether the animals of the kind can have young at all: a pair at least,
## of a kind which has young.
func may_have_young(kind: String) -> bool:
    return int(animals.get(kind, 0)) >= 2 and int(animal_kinds[kind].get("young_days", 0)) > 0


## In how many days the herd of the kind has its next young, if it stays fed
## and has room; -1 if it has none.
func days_to_young(kind: String) -> int:
    if not may_have_young(kind):
        return -1
    return int(animal_kinds[kind]["young_days"]) - int(young_progress.get(kind, 0))


## The milk beyond what the cellar keeps becomes cheese.
func _make_cheese() -> void:
    var milk := float(store.get("milk", 0.0))
    if milk <= milk_kept + 1e-6:
        return
    store["milk"] = milk_kept
    put("cheese", (milk - milk_kept) / milk_per_cheese)


## What the farm should remind the players of, on the [param day]: Array of
## {"kind": "harvest"|"ripe"|"hungry"|"crowded"|"feed", "text", "days"}, the
## most urgent first.
func reminders(day: int) -> Array:
    var result: Array = []
    for i in range(fields.size()):
        var crop: String = fields[i]["crop"]
        if crop == "":
            continue
        var name: String = crop_kinds[crop]["name"]
        var to_ripe := days_to_ripe(i, day)
        if to_ripe > 0:
            result.append(
                {
                    "kind": "ripe",
                    "days": to_ripe,
                    "text":
                    Grammar.text(
                        "{crop} is ripe in {days} {days|day|days}.", {"crop": name, "days": to_ripe}
                    )
                }
            )
        else:
            var left := days_to_harvest(i, day)
            var text := Grammar.text(
                "{crop} is ripe: harvest within {days} {days|day|days}!",
                {"crop": name, "days": left + 1}
            )
            if left < 0:
                text = Grammar.text(
                    "{crop} is ripe, the birds are eating it: harvest it now!", {"crop": name}
                )
            result.append({"kind": "harvest", "days": left, "text": text})
    for kind in hungry.keys():
        var text := Grammar.text(
            "The {animals} are hungry: bring {good}!",
            {
                "animals": animal_kinds[kind]["plural"],
                "good": _good_name(animal_kinds[kind]["eats"])
            }
        )
        if may_have_young(kind):
            text = Grammar.text(
                "The {animals} are hungry, so no {young}: bring {good}!",
                {
                    "animals": animal_kinds[kind]["plural"],
                    "young": animal_kinds[kind]["young_plural"],
                    "good": _good_name(animal_kinds[kind]["eats"])
                }
            )
        result.append({"kind": "hungry", "days": -1, "text": text})
    # NOTE (mristin):
    # One reminder for all the herds without room, so that a full farm does
    # not crowd out the other reminders.
    var crowded: Array[String] = []
    for kind in animals.keys():
        if may_have_young(kind) and not hungry.has(kind) and not has_room_for(kind):
            crowded.append(animal_kinds[kind]["young_plural"])
    if not crowded.is_empty():
        result.append(
            {
                "kind": "crowded",
                "days": 1,
                "text": Grammar.text("No room for {young}: buy land!", {"young": crowded})
            }
        )
    for food in ["grain", "hay"]:
        var days := feed_days(food)
        if days < 2.0 and days != INF and not _anyone_hungry_for(food):
            result.append(
                {
                    "kind": "feed",
                    "days": int(days),
                    "text":
                    Grammar.text(
                        "The {good} lasts only {days} more {days|day|days}.",
                        {"good": _good_name(food), "days": int(days)}
                    )
                }
            )
    result.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool: return int(a["days"]) < int(b["days"])
    )
    return result


func _anyone_hungry_for(food: String) -> bool:
    for kind in hungry.keys():
        if animal_kinds[kind]["eats"] == food:
            return true
    return false


## The name of the [param good] (an English message ID, see Grammar), e.g.,
## "grain".
func _good_name(good: String) -> String:
    return str(good_names.get(good, good))


## The farm as plain data for the save.
func to_data() -> Dictionary:
    return {
        "animals": animals.duplicate(),
        "hungry": hungry.duplicate(),
        "young_progress": young_progress.duplicate(),
        "store": store.duplicate(),
        "fields": fields.duplicate(true),
        "pasture": pasture,
        "plots": plots.duplicate(),
    }


## Restore the farm of [method to_data] (after [method load_data]).
func restore(data: Dictionary) -> void:
    animals = {}
    for kind in data.get("animals", {}).keys():
        animals[kind] = int(data["animals"][kind])
    hungry = data.get("hungry", {}).duplicate()
    young_progress = {}
    for kind in data.get("young_progress", {}).keys():
        young_progress[kind] = int(data["young_progress"][kind])
    store = {}
    for good in data.get("store", {}).keys():
        store[good] = float(data["store"][good])
    fields = data.get("fields", []).duplicate(true)
    pasture = float(data.get("pasture", pasture))
    plots = data.get("plots", []).duplicate()
