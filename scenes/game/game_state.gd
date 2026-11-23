extends Node

## The state of the players' voyage, for the whole game (the autoload
## GameState): the silver, the cargo of the boat, the day, the economy of the
## lakes, the farm, the prices the players saw and the news they heard. It
## saves to user://voyage.json in every port (see [method save]).

const SAVE_PATH := "user://voyage.json"

const MAP_PATH := "res://data/world/home_lakes.json"
const GOODS_PATH := "res://data/economy/goods.json"
const REGION_PATH := "res://data/economy/home_lakes.json"
const FARM_PATH := "res://data/farm/farm.json"

## The silver at the start of a new voyage.
const START_SILVER := 20

## The crates which the small boat carries.
const START_CAPACITY := 4

## Where the voyage is saved (the tests save elsewhere).
var save_path := SAVE_PATH

## The silver, in pieces.
var silver := START_SILVER

## The cargo of the boat: good (or "animal:<kind>") -> crates.
var cargo := {}

## How many crates (and animals) the boat carries.
var capacity := START_CAPACITY

## The day of the voyage, from 1.
var day := 1

## The id of the place where the boat lies (at its jetty), or "" on the water.
var place := "home"

## The economy of the lakes.
var economy := Economy.new()

## The farm.
var farm := Farm.new()

## The places of the map: id -> {"kind", "name", "at", "jetty"}.
var places := {}

## The prices the players saw: "<place>|<good>" -> {"buy", "sell", "day"}.
var price_book := {}

## The news the players heard: Array of {"day", "text", "place", "good"}, the newest last.
var news: Array = []

## What went wrong when loading the data, or "".
var error := ""


func _ready() -> void:
    error = _load_data()
    if error != "":
        push_error(error)


func _load_data() -> String:
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
    if not data is Dictionary:
        return "Could not read the map %s." % MAP_PATH
    places = {}
    for place_data in data.get("places", []):
        places[place_data["id"]] = {
            "kind": place_data["kind"],
            "name": place_data["name"],
            "at": Vector2(place_data["at"][0], place_data["at"][1]),
            "jetty": Vector2(place_data["jetty"][0], place_data["jetty"][1]),
        }
    var problem := economy.load_data(GOODS_PATH, REGION_PATH, data.get("places", []))
    if problem != "":
        return problem
    return farm.load_data(FARM_PATH)


## Start a new voyage.
func new_voyage() -> void:
    silver = START_SILVER
    cargo = {}
    capacity = START_CAPACITY
    day = 1
    place = "home"
    price_book = {}
    news = []
    _load_data()


## The name of a place, e.g., "Laxestad".
func place_name(id: String) -> String:
    return places[id]["name"] if places.has(id) else id


## The name of a good, e.g., "Dried fish".
func good_name(good: String) -> String:
    if good.begins_with("animal:"):
        return farm.animal_kinds[good.trim_prefix("animal:")]["name"]
    return economy.goods[good]["name"] if economy.goods.has(good) else good


## How many crates the boat carries now.
func load_count() -> int:
    var total := 0
    for item in cargo.keys():
        total += int(cargo[item])
    return total


## Whether there is room in the boat for one more crate (or animal).
func has_room() -> bool:
    return load_count() < capacity


func add_cargo(item: String, count := 1) -> void:
    cargo[item] = int(cargo.get(item, 0)) + count


## Take crates out of the boat; return how many were there.
func remove_cargo(item: String, count := 1) -> int:
    var taken := mini(count, int(cargo.get(item, 0)))
    if taken > 0:
        cargo[item] = int(cargo[item]) - taken
        if cargo[item] == 0:
            cargo.erase(item)
    return taken


## Buy a crate of the good at the place; return whether it worked.
func buy(at: String, good: String) -> bool:
    if not economy.sells(at, good) or not has_room():
        return false
    var price := economy.buy_price(at, good)
    if silver < price:
        return false
    silver -= price
    add_cargo(good)
    economy.bought(at, good)
    note_prices(at, good)
    return true


## Sell a crate of the good at the place; return whether it worked.
func sell(at: String, good: String) -> bool:
    if not economy.buys(at, good) or int(cargo.get(good, 0)) <= 0:
        return false
    silver += economy.sell_price(at, good)
    remove_cargo(good)
    economy.sold(at, good)
    note_prices(at, good)
    return true


## Remember the prices of the good at the place today (the price book).
func note_prices(at: String, good: String) -> void:
    price_book["%s|%s" % [at, good]] = {
        "buy": economy.buy_price(at, good) if economy.sells(at, good) else -1,
        "sell": economy.sell_price(at, good),
        "day": day,
    }


## Remember a piece of news.
func hear(text: String, at := "", good := "") -> void:
    news.append({"day": day, "text": text, "place": at, "good": good})
    if news.size() > 40:
        news.pop_front()


## The players sleep at home: a day passes for the lakes and the farm.
func next_day() -> void:
    day += 1
    economy.next_day()
    farm.next_day()


## Save the voyage.
func save() -> bool:
    var data := {
        "version": 1,
        "silver": silver,
        "cargo": cargo,
        "capacity": capacity,
        "day": day,
        "place": place,
        "economy": economy.to_data(),
        "farm": farm.to_data(),
        "price_book": price_book,
        "news": news,
    }
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    if file == null:
        push_error("Could not save the voyage into %s." % save_path)
        return false
    file.store_string(JSON.stringify(data, "  "))
    return true


## Load the saved voyage; return whether there was one.
func load_voyage() -> bool:
    if not FileAccess.file_exists(save_path):
        return false
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
    if not data is Dictionary:
        return false
    silver = int(data.get("silver", START_SILVER))
    cargo = {}
    for item in data.get("cargo", {}).keys():
        cargo[item] = int(data["cargo"][item])
    capacity = int(data.get("capacity", START_CAPACITY))
    day = int(data.get("day", 1))
    place = str(data.get("place", "home"))
    economy.restore(data.get("economy", {}))
    farm.restore(data.get("farm", {}))
    price_book = data.get("price_book", {})
    news = data.get("news", [])
    return true
