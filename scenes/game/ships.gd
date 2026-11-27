class_name Ships
extends RefCounted

## The ships of the players: the one they row now, the ones they bought from
## Signe the shipwright, and what the boatwright added to the hold (see
## data/ships/ships.json and DESIGN.md, section 8).
##
## As in Bird Dog, a ship is bought once and kept; the players may take any
## of their ships in the shipyard for free, if their cargo fits in its hold.
## The crates which the boatwright adds (the missions) go with them from ship
## to ship.
##
## The ships are plain data, so that the game saves them (see [method to_data]).

## The ship of a new voyage.
const START := "rowing_boat"

## The ships of the shipwright: id -> {"name", "price", "hold", "crew",
## "push", "glide", "turn", "top", "drawn", "about"}, in the order of [member ids].
var kinds := {}
var ids: Array[String] = []

## Where the shipwright has her shipyard (the id of a place), and who she is.
var shipyard := ""
var shipwright := {}

## The ship the players row now, and the ships they own.
var current := START
var owned: Array = [START]

## The crates which the boatwright added to the hold.
var hold_bonus := 0


## Load the ships of [param path]; the shipyard must be one of the [param
## places] (id -> ...). Return what went wrong, or "".
func load_data(path: String, places: Dictionary) -> String:
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary:
        return "Could not read the ships %s." % path
    shipyard = str(data.get("shipyard", ""))
    if not places.has(shipyard):
        return "The shipyard is at the unknown place %s." % shipyard
    shipwright = data["shipwright"]
    kinds = {}
    ids.clear()
    for kind in data["ships"]:
        kinds[kind["id"]] = kind
        ids.append(kind["id"])
    if not kinds.has(START):
        return "There is no ship %s to start with." % START
    reset()
    return ""


## Start afresh: the rowing boat, and nothing added to its hold.
func reset() -> void:
    current = START
    owned = [START]
    hold_bonus = 0


## The data of the ship the players row now.
func data() -> Dictionary:
    return kinds.get(current, kinds.get(START, {}))


## How many crates the ship of the [param id] (the current one by default)
## carries, with what the boatwright added.
func hold(id := "") -> int:
    var kind: Dictionary = kinds.get(id if id != "" else current, data())
    return int(kind.get("hold", 4)) + hold_bonus


## Buy the ship of the [param id] with the silver of the [param state];
## return whether it worked.
func buy(state: Node, id: String) -> bool:
    if not kinds.has(id) or id in owned:
        return false
    var price := int(kinds[id]["price"])
    if state.silver < price:
        return false
    state.silver -= price
    owned.append(id)
    return true


## Take the ship of the [param id], which the players own, if the [param
## load] (the crates in the boat) fits in it; return whether it worked.
func take(id: String, load: int) -> bool:
    if not id in owned or load > hold(id):
        return false
    current = id
    return true


## The ships as plain data for the save.
func to_data() -> Dictionary:
    return {"current": current, "owned": owned.duplicate(), "hold_bonus": hold_bonus}


## Restore the ships of [method to_data] (after [method load_data]); the
## saves before the ships kept the whole hold as [param old_capacity].
func restore(data: Dictionary, old_capacity := 4) -> void:
    owned = []
    for id in data.get("owned", [START]):
        if kinds.has(id):
            owned.append(id)
    if not START in owned:
        owned.insert(0, START)
    current = str(data.get("current", START))
    if not current in owned:
        current = START
    hold_bonus = int(data.get("hold_bonus", maxi(0, old_capacity - int(kinds[START]["hold"]))))
