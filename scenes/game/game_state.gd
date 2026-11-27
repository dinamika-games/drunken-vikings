extends Node

## The state of the players' voyage, for the whole game (the autoload
## GameState): the silver, the cargo of the boat, the day, the economy of the
## lakes, the farm, the prices the players saw and the news they heard. It
## saves in every port, and every 30 seconds on the water (see [method save]).
##
## The players keep as many **journeys** as they like (so that several
## children can share a computer): each is one voyage with its own name, its
## number of players (one or two rowers) and its progress, saved as JSON in
## user://saves/<id>.json; user://settings.cfg remembers the last journey.

## The single voyage of the first versions, which becomes a journey once.
const OLD_SAVE_PATH := "user://voyage.json"

## The version of the format of the saves.
##
## 3: the boat on the water ("boat": {"x", "y", "heading"} when "place" is "").
const FORMAT := 3

const MAP_PATH := "res://data/world/home_lakes.json"
const GOODS_PATH := "res://data/economy/goods.json"
const REGION_PATH := "res://data/economy/home_lakes.json"
const FARM_PATH := "res://data/farm/farm.json"
const MISSIONS_DIR := "res://data/missions"
const SHIPS_PATH := "res://data/ships/ships.json"

## The silver at the start of a new voyage.
const START_SILVER := 20

## Where the voyage is saved (the tests save elsewhere).
var save_path := ""

## Where the journeys are saved, and the settings (the tests use others).
var saves_dir := "user://saves"
var settings_path := "user://settings.cfg"

## The journey: its id (the date and the time it began), its name, and how
## many players row (1 or 2).
var journey_id := ""
var journey_name := ""
var players := 1

## How each player looks: a viking girl or boy, and the colours of the skin,
## the hair and the clothes (see Looks); one for each of the two players,
## whether one or two row.
var looks: Array = [Looks.default_look(0), Looks.default_look(1)]

## The silver, in pieces.
var silver := START_SILVER

## The cargo of the boat: good (or "animal:<kind>", or an item of a mission,
## "task:<mission>:<item>", see Missions) -> crates.
var cargo := {}

## How many crates (and animals) the boat carries: the hold of the ship (see Ships).
var capacity: int:
    get:
        return ships.hold()

## The ships of the players.
var ships := Ships.new()

## The day of the voyage, from 1.
var day := 1

## The id of the place where the boat lies (at its jetty), or "" on the water.
var place := "home":
    set(value):
        place = value
        if value != "" and value != "home":
            travelled = true

## Where the boat is on the water, while [member place] is "" (the world sets
## it before it saves there), and its heading, in radians.
var boat_at := Vector2.ZERO
var boat_heading := 0.0

## Whether the boat came to another place than home since the players last
## slept: they may sleep only after a day's trip, so
## that the farm does not make goods and young night after night without the
## players rowing.
var travelled := false

## The economy of the lakes.
var economy := Economy.new()

## The farm.
var farm := Farm.new()

## The missions, done and under way.
var missions := Missions.new()

## The places of the map: id -> {"kind", "name", "at", "jetty"}.
var places := {}

## The prices the players saw: "<place>|<good>" -> {"buy", "sell", "day"}.
var price_book := {}

## The news the players heard: Array of {"day", "text", "place", "good"}, the newest last.
var news: Array = []

## What went wrong when loading the data, or "".
var error := ""

## When the journey began.
var _created := ""

## The players as the command line forced them (-- --players=2), or 0.
var _forced_players := 0


func _ready() -> void:
    error = _load_data()
    if error != "":
        push_error(error)
    _adopt_old_save()
    var last := last_journey()
    if last != "" and FileAccess.file_exists(_journey_path(last)):
        _use_journey(last)
    else:
        _start_journey_record(1)
    # NOTE (mristin):
    # For the developers who start a scene directly: -- --players=2.
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--players="):
            _forced_players = clampi(int(arg.trim_prefix("--players=")), 1, 2)
            players = _forced_players


## The journeys, the most recently played first: Array of {"id", "name",
## "players", "day", "silver", "updated"}.
func journeys() -> Array:
    _recover_saves()
    var result: Array = []
    for file in DirAccess.get_files_at(saves_dir):
        if not file.ends_with(".json"):
            continue
        var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(saves_dir + "/" + file))
        if not data is Dictionary:
            continue
        (
            result
            . append(
                {
                    "id": file.trim_suffix(".json"),
                    "name": str(data.get("name", file.trim_suffix(".json"))),
                    "players": int(data.get("players", 1)),
                    "day": int(data.get("day", 1)),
                    "silver": int(data.get("silver", START_SILVER)),
                    "updated": str(data.get("updated", "")),
                }
            )
        )
    result.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool: return str(a["updated"]) > str(b["updated"])
    )
    return result


## The id of the last journey played, or "".
func last_journey() -> String:
    var settings := ConfigFile.new()
    if settings.load(settings_path) != OK:
        return ""
    return str(settings.get_value("journeys", "last", ""))


## Start a new journey of [param count] players, named after the date and the
## time, and save it.
func new_journey(count: int) -> void:
    new_voyage()
    _start_journey_record(count)
    save()


## Go on with the journey [param id]; return whether it could be read.
func open_journey(id: String) -> bool:
    _recover_saves()
    if not FileAccess.file_exists(_journey_path(id)):
        return false
    _use_journey(id)
    return load_voyage()


## Delete the journey [param id] for good.
func delete_journey(id: String) -> void:
    DirAccess.remove_absolute(_journey_path(id))
    if last_journey() == id:
        var settings := ConfigFile.new()
        settings.load(settings_path)
        settings.set_value("journeys", "last", "")
        settings.save(settings_path)


func _journey_path(id: String) -> String:
    return "%s/%s.json" % [saves_dir, id]


## A new journey, not yet saved: its id and its name are the date and the time.
func _start_journey_record(count: int) -> void:
    var now := Time.get_datetime_dict_from_system()
    journey_id = (
        "%04d-%02d-%02d_%02d-%02d-%02d"
        % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]
    )
    journey_name = (
        "%04d-%02d-%02d %02d:%02d"
        % [now["year"], now["month"], now["day"], now["hour"], now["minute"]]
    )
    players = count
    _created = Time.get_datetime_string_from_system()
    save_path = _journey_path(journey_id)


func _use_journey(id: String) -> void:
    journey_id = id
    save_path = _journey_path(id)
    var settings := ConfigFile.new()
    settings.load(settings_path)
    settings.set_value("journeys", "last", id)
    settings.save(settings_path)


## The voyage of the first versions becomes the first journey, once.
func _adopt_old_save() -> void:
    DirAccess.make_dir_recursive_absolute(saves_dir)
    if not FileAccess.file_exists(OLD_SAVE_PATH):
        return
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE_PATH))
    if data is Dictionary:
        data["name"] = "My first voyage"
        data["players"] = 1
        data["format"] = FORMAT
        data["updated"] = Time.get_datetime_string_from_system()
        var id := "2026-01-01_00-00-00"
        var file := FileAccess.open(_journey_path(id), FileAccess.WRITE)
        if file != null:
            file.store_string(JSON.stringify(data, "  "))
            file.close()
            _use_journey(id)
    DirAccess.rename_absolute(OLD_SAVE_PATH, OLD_SAVE_PATH + ".adopted")


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
    problem = farm.load_data(FARM_PATH)
    if problem != "":
        return problem
    for good in economy.goods.keys():
        farm.good_names[good] = economy.goods[good]["name"]
    problem = ships.load_data(SHIPS_PATH, places)
    if problem != "":
        return problem
    missions.reset()
    return missions.load_data(MISSIONS_DIR, places, economy, farm)


## Start a new voyage.
func new_voyage() -> void:
    silver = START_SILVER
    cargo = {}
    day = 1
    place = "home"
    boat_at = Vector2.ZERO
    boat_heading = 0.0
    travelled = false
    price_book = {}
    news = []
    looks = [Looks.default_look(0), Looks.default_look(1)]
    _load_data()


## The name of a place, e.g., "Laxestad" (an English message ID, see Grammar).
func place_name(id: String) -> String:
    return places[id]["name"] if places.has(id) else id


## The name of a good, e.g., "dried fish", or of an item of a mission or an
## animal in the boat, e.g., "Kitten" (English message IDs, see Grammar).
func good_name(good: String) -> String:
    if good.begins_with("animal:"):
        return farm.animal_kinds[good.trim_prefix("animal:")]["name"]
    if Missions.is_item(good):
        return missions.item_name(good)
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
    travelled = false
    economy.next_day()
    farm.next_day()


## Save the voyage, first into a temporary file which then replaces the save,
## so that a crash never destroys the last good save.
func save() -> bool:
    var data := {
        "format": FORMAT,
        "name": journey_name,
        "players": players,
        "looks": looks,
        "created": _created,
        "updated": Time.get_datetime_string_from_system(),
        "silver": silver,
        "cargo": cargo,
        "ships": ships.to_data(),
        "day": day,
        "travelled": travelled,
        "place": place,
        "economy": economy.to_data(),
        "farm": farm.to_data(),
        "missions": missions.to_data(),
        "price_book": price_book,
        "news": news,
    }
    if place == "":
        data["boat"] = {"x": boat_at.x, "y": boat_at.y, "heading": boat_heading}
    DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
    # NOTE (mristin):
    # The save must never be half written (the game autosaves while the
    # children row, and they switch the computer off whenever they like). We
    # write the whole voyage into a temporary file next to the save, and only
    # then put it in the place of the save: a crash leaves either the old save
    # or the new one. The temporary file holds JSON which ends with the last
    # brace, so a cut one does not parse, and a whole one is the newest save
    # (see [method _recover_saves]); e.g., Windows removes the old save before
    # it renames the new one into its place.
    var temporary := save_path + ".tmp"
    var text := JSON.stringify(data, "  ")
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        push_error("Could not save the voyage into %s." % temporary)
        return false
    var written := file.store_string(text)
    file.close()
    if not written or FileAccess.get_file_as_string(temporary) != text:
        push_error("Could not save the voyage into %s." % temporary)
        DirAccess.remove_absolute(temporary)
        return false
    if DirAccess.rename_absolute(temporary, save_path) != OK:
        push_error("Could not save the voyage into %s." % save_path)
        return false
    if journey_id != "" and save_path == _journey_path(journey_id):
        _use_journey(journey_id)
    return true


## The look of the [param player] (see Looks).
func look(player: int) -> Dictionary:
    return looks[player] if player >= 0 and player < looks.size() else Looks.default_look(player)


## Load the saved voyage; return whether there was one.
func load_voyage() -> bool:
    _recover_saves()
    if not FileAccess.file_exists(save_path):
        return false
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
    if not data is Dictionary:
        return false
    journey_name = str(data.get("name", journey_name))
    players = clampi(int(data.get("players", 1)), 1, 2)
    if _forced_players > 0:
        players = _forced_players
    var saved_looks: Variant = data.get("looks", [])
    looks = []
    for player in range(2):
        var saved: Variant = (
            saved_looks[player] if saved_looks is Array and player < saved_looks.size() else null
        )
        looks.append(Looks.normalized(saved, player))
    _created = str(data.get("created", ""))
    silver = int(data.get("silver", START_SILVER))
    cargo = {}
    for item in data.get("cargo", {}).keys():
        cargo[item] = int(data["cargo"][item])
    ships.restore(data.get("ships", {}), int(data.get("capacity", 4)))
    day = int(data.get("day", 1))
    place = str(data.get("place", "home"))
    var boat: Variant = data.get("boat", null)
    if place == "" and boat is Dictionary:
        boat_at = Vector2(float(boat.get("x", 0.0)), float(boat.get("y", 0.0)))
        boat_heading = float(boat.get("heading", 0.0))
    elif place == "":
        # NOTE (mristin):
        # The saves from before the format 3 did not say where on the water.
        place = "home"
    # NOTE (mristin):
    # The saves from before the trips counted may sleep at once.
    travelled = bool(data.get("travelled", true))
    economy.restore(data.get("economy", {}))
    farm.restore(data.get("farm", {}))
    missions.restore(data.get("missions", {}))
    price_book = data.get("price_book", {})
    news = data.get("news", [])
    return true


## Finish the saves which a crash cut short (see [method save]): a whole
## temporary file is the newest save and takes the place of the save; a cut
## one is dropped, and the save before it stays.
func _recover_saves() -> void:
    var dirs := [saves_dir]
    if save_path != "" and save_path.get_base_dir() != saves_dir:
        dirs.append(save_path.get_base_dir())
    for dir: String in dirs:
        for file in DirAccess.get_files_at(dir):
            if not file.ends_with(".json.tmp"):
                continue
            var temporary := dir + "/" + file
            var json := JSON.new()
            var text := FileAccess.get_file_as_string(temporary)
            if json.parse(text) == OK and json.data is Dictionary:
                DirAccess.rename_absolute(temporary, temporary.trim_suffix(".tmp"))
            else:
                DirAccess.remove_absolute(temporary)
