class_name PortScreens
extends RefCounted

## The screens of the ports and of the farm (see world.gd): the market (sell,
## buy, the animals, the news of the people), and at home the farm (plant,
## harvest, buy land), the unloading and the loading of the boat, and the
## sleep which ends the day.

## What each kind of settlement is called on the screens.
const KIND_NAMES := {
    "home": "your farm",
    "market": "the market village",
    "healer": "Tova the healer",
    "inn": "the inn",
    "fishers": "the fishing village",
    "brewer": "the brewer",
    "beekeeper": "the beekeeper",
    "horse_farm": "the horse farm",
    "weaver": "the weaver",
    "chieftain": "the chieftain's hall",
    "farm": "a farm",
    "mill": "the mill",
    "smith": "the smith",
    "potter": "the potter",
    "herders": "the herders",
}

## Which animals each kind of settlement sells.
## The painted fields of the crops on their cards (see Pictures).
const CROP_PICTURES := {
    "barley": "barley_ripe", "flax": "flax_bloom", "meadow": "hay_meadow", "flowers": "flower_field"
}

## Grandmother Åsa, who keeps the farm at home.
const GRANDMOTHER := {"hair": Color("d8d8d0"), "braids": true, "picture": "grandmother"}

const ANIMALS_SOLD := {
    "market": ["hen", "sheep"],
    "horse_farm": ["goat", "cow"],
    "beekeeper": ["bees"],
    "farm": ["hen"],
    "herders": ["sheep", "goat"],
}

## How many cards a list shows at once (with "More" and "Back").
const PAGE := 5

var _world: Node
var _state: Node
var _map: LakeMap
var _rng := RandomNumberGenerator.new()


func _init(world: Node, state: Node, map: LakeMap) -> void:
    _world = world
    _state = state
    _map = map
    _rng.seed = Time.get_ticks_usec()


func place_title(id: String) -> String:
    var place := _map.place(id)
    return "%s, %s" % [place["name"], KIND_NAMES.get(place["kind"], "")]


func show_port(message := "") -> void:
    var id: String = _state.place
    var place := _map.place(id)
    if place["kind"] == "home":
        _show_home(message)
        return
    var economy: Economy = _state.economy
    var sellable := _sellable(id)
    var text := message if message != "" else "Welcome! What would you like to do?"
    var cards: Array = [
        {
            "title": "Sell",
            "detail":
            "%d crates" % sellable.size() if not sellable.is_empty() else "nothing to sell",
            "enabled": not sellable.is_empty()
        },
        {
            "title": "Buy",
            "detail": "%d silver" % _state.silver,
            "enabled": _goods_sold(id).size() > 0
        },
    ]
    var actions: Array[Callable] = [_show_sell.bind(0), _show_buy.bind(0)]
    if ANIMALS_SOLD.has(place["kind"]):
        cards.append({"title": "Animals", "detail": "for your farm"})
        actions.append(_show_animals)
    cards.append({"title": "Talk", "detail": "the news"})
    actions.append(_talk)
    cards.append({"title": "Row on", "detail": ""})
    actions.append(_world.undock.bind(id))
    if economy.is_market(id):
        for good in economy.good_ids:
            _state.note_prices(id, good)
    var face := {}
    if Pictures.of("faces", place["kind"]) != null:
        face = {"picture": place["kind"]}
    _world.show_screen(place_title(id), text, cards, actions, face)


func _sellable(id: String) -> Array:
    var goods: Array = []
    for item in _state.cargo.keys():
        if _state.economy.buys(id, item):
            goods.append(item)
    return goods


func _goods_sold(id: String) -> Array:
    var goods: Array = []
    for good in _state.economy.good_ids:
        if _state.economy.sells(id, good):
            goods.append(good)
    return goods


## Show a page of a list of cards, with "More" and "Back".
func _show_list(
    title: String,
    text: String,
    items: Array,
    item_actions: Array[Callable],
    page: int,
    again: Callable
) -> void:
    var first := page * PAGE
    var cards: Array = []
    var actions: Array[Callable] = []
    for i in range(first, mini(first + PAGE, items.size())):
        cards.append(items[i])
        actions.append(item_actions[i])
    if first + PAGE < items.size():
        cards.append({"title": "More", "detail": "→"})
        actions.append(again.bind(page + 1))
    cards.append({"title": "Back", "detail": ""})
    actions.append(show_port)
    _world.show_screen(title, text, cards, actions)


func _show_sell(page: int, message := "") -> void:
    var id: String = _state.place
    var economy: Economy = _state.economy
    var items: Array = []
    var actions: Array[Callable] = []
    for good in _sellable(id):
        (
            items
            . append(
                {
                    "title":
                    "Sell %s (%d)" % [_state.good_name(good).to_lower(), int(_state.cargo[good])],
                    "detail": "%d silver" % economy.sell_price(id, good),
                    "color": economy.goods[good]["color"],
                    "picture": ["goods", good],
                    "mood": economy.mood(id, good),
                }
            )
        )
        actions.append(_sell.bind(good, page))
    if items.is_empty():
        show_port(message if message != "" else "Nothing more to sell here.")
        return
    var text := message if message != "" else "What do you sell? Silver: %d." % _state.silver
    _show_list(place_title(id), text, items, actions, page, _show_sell)


func _sell(good: String, page: int) -> void:
    var id: String = _state.place
    var price: int = _state.economy.sell_price(id, good)
    if _state.sell(id, good):
        _show_sell(
            page,
            (
                "Sold a crate of %s for %d silver. Silver: %d."
                % [_state.good_name(good).to_lower(), price, _state.silver]
            )
        )


func _show_buy(page: int, message := "") -> void:
    var id: String = _state.place
    var economy: Economy = _state.economy
    var items: Array = []
    var actions: Array[Callable] = []
    for good in _goods_sold(id):
        var price := economy.buy_price(id, good)
        (
            items
            . append(
                {
                    "title": "Buy %s" % _state.good_name(good).to_lower(),
                    "detail": "%d silver" % price,
                    "color": economy.goods[good]["color"],
                    "picture": ["goods", good],
                    "mood": economy.mood(id, good),
                    "enabled": _state.silver >= price and _state.has_room(),
                }
            )
        )
        actions.append(_buy.bind(good, page))
    var text := message
    if text == "":
        text = (
            "Silver: %d. Room in the boat: %d of %d crates."
            % [_state.silver, _state.capacity - _state.load_count(), _state.capacity]
        )
    _show_list(place_title(id), text, items, actions, page, _show_buy)


func _buy(good: String, page: int) -> void:
    var id: String = _state.place
    var price: int = _state.economy.buy_price(id, good)
    if _state.buy(id, good):
        _show_buy(
            page,
            (
                "Bought a crate of %s for %d silver. Silver: %d, room for %d more."
                % [
                    _state.good_name(good).to_lower(),
                    price,
                    _state.silver,
                    _state.capacity - _state.load_count()
                ]
            )
        )


func _show_animals(message := "") -> void:
    var place := _map.place(_state.place)
    var items: Array = []
    var actions: Array[Callable] = []
    for kind in ANIMALS_SOLD.get(place["kind"], []):
        var animal: Dictionary = _state.farm.animal_kinds[kind]
        var price := int(animal["price"])
        (
            items
            . append(
                {
                    "title": "Buy a %s" % String(animal["name"]).to_lower(),
                    "detail": "%d silver" % price,
                    "picture": ["farm", "beehive" if kind == "bees" else kind],
                    "enabled": _state.silver >= price and _state.has_room(),
                }
            )
        )
        actions.append(_buy_animal.bind(kind))
    var text := (
        message
        if message != ""
        else "An animal takes the room of a crate in the boat. Silver: %d." % _state.silver
    )
    _show_list(
        place_title(_state.place),
        text,
        items,
        actions,
        0,
        func(_page: int) -> void: _show_animals()
    )


func _buy_animal(kind: String) -> void:
    var price := int(_state.farm.animal_kinds[kind]["price"])
    if _state.silver < price or not _state.has_room():
        return
    _state.silver -= price
    _state.add_cargo("animal:" + kind)
    _show_animals(
        (
            "The %s is in the boat. Row it home to your farm!"
            % String(_state.farm.animal_kinds[kind]["name"]).to_lower()
        )
    )


func _talk() -> void:
    var who := {"name": "", "goods": [], "hair": Color("8a5a2b"), "braids": _rng.randf() < 0.5}
    var news := Gossip.news(_state, who, _rng)
    _state.hear(news["text"], news["place"], news["good"])
    var cards: Array = [{"title": "Thank you!", "detail": ""}]
    var actions: Array[Callable] = [show_port]
    _world.show_screen(
        place_title(_state.place),
        news["text"],
        cards,
        actions,
        {"hair": who["hair"], "braids": who["braids"], "picture": who.get("picture", "")}
    )


# ---------------------------------------------------------------------------
# Home: the farm
# ---------------------------------------------------------------------------


func _show_home(message := "") -> void:
    var farm: Farm = _state.farm
    var text := message
    if text == "":
        var reminders := farm.reminders(_state.day)
        text = (
            "Grandmother Åsa waves from the jetty. "
            + (reminders[0]["text"] if not reminders.is_empty() else "All is well on the farm.")
        )
    var cards: Array = [
        {"title": "The farm", "detail": _animals_line()},
        {
            "title": "Unload the boat",
            "detail": "%d crates" % _state.load_count(),
            "enabled": _state.load_count() > 0
        },
        {
            "title": "Load from the store",
            "detail": "",
            "enabled": not _store_goods().is_empty() and _state.has_room()
        },
        {"title": "Sleep", "detail": "end the day"},
        {"title": "Row out", "detail": ""},
    ]
    var actions: Array[Callable] = [
        _show_farm, _unload, _show_load.bind(0), _sleep, _world.undock.bind("home")
    ]
    _world.show_screen(place_title("home"), text, cards, actions, GRANDMOTHER)


func _animals_line() -> String:
    var parts: Array[String] = []
    for kind in _state.farm.animals.keys():
        parts.append(
            (
                "%d %s"
                % [
                    _state.farm.animals[kind],
                    String(_state.farm.animal_kinds[kind]["name"]).to_lower()
                ]
            )
        )
    return ", ".join(parts)


func _store_goods() -> Array:
    var goods: Array = []
    for good in _state.farm.store.keys():
        if _state.farm.crates(good) > 0:
            goods.append(good)
    return goods


func _show_farm(message := "") -> void:
    var farm: Farm = _state.farm
    var lines: Array[String] = []
    if message != "":
        lines.append(message)
    lines.append("Animals: %s (room for %d)." % [_animals_line(), int(farm.pasture)])
    var store: Array[String] = []
    for good in farm.store.keys():
        store.append("%.1f %s" % [farm.store[good], _state.good_name(good).to_lower()])
    lines.append("Store: %s." % (", ".join(store) if not store.is_empty() else "empty"))
    for reminder in farm.reminders(_state.day):
        lines.append(reminder["text"])
    var empty := -1
    var ripe := false
    for i in range(farm.fields.size()):
        if farm.fields[i]["crop"] == "" and empty < 0:
            empty = i
        elif farm.fields[i]["crop"] != "" and farm.days_to_ripe(i, _state.day) == 0:
            ripe = true
    var cards: Array = [
        {
            "title": "Plant",
            "detail": "an empty field" if empty >= 0 else "no empty field",
            "enabled": empty >= 0
        },
        {"title": "Harvest", "detail": "", "enabled": ripe},
        {"title": "Buy land", "detail": "%d silver" % _state.silver},
        {"title": "Back", "detail": ""},
    ]
    var actions: Array[Callable] = [_show_plant.bind(empty), _harvest, _show_land, _show_home]
    _world.show_screen("The farm", " ".join(lines), cards, actions, GRANDMOTHER)


func _show_plant(field: int) -> void:
    var items: Array = []
    var actions: Array[Callable] = []
    for crop in _state.farm.crop_kinds.keys():
        var kind: Dictionary = _state.farm.crop_kinds[crop]
        var price := int(kind["seed_price"])
        (
            items
            . append(
                {
                    "title": String(kind["name"]),
                    "detail": "%d silver, %d days" % [price, int(kind["days"])],
                    "color": _state.economy.goods[kind["gives"]]["color"],
                    "picture": ["farm", CROP_PICTURES.get(crop, "")],
                    "enabled": _state.silver >= price,
                }
            )
        )
        actions.append(_plant.bind(field, crop))
    _show_list(
        "Plant a field",
        "What do you plant? It grows while you trade; come back to harvest it in time.",
        items,
        actions,
        0,
        func(_p: int) -> void: _show_plant(field)
    )


func _plant(field: int, crop: String) -> void:
    var kind: Dictionary = _state.farm.crop_kinds[crop]
    _state.silver -= int(kind["seed_price"])
    _state.farm.plant(field, crop, _state.day)
    _show_farm(
        (
            "You planted %s. It is ripe in %d days."
            % [String(kind["name"]).to_lower(), int(kind["days"])]
        )
    )


func _harvest() -> void:
    var parts: Array[String] = []
    for i in range(_state.farm.fields.size()):
        var crop: String = _state.farm.fields[i]["crop"]
        if crop != "" and _state.farm.days_to_ripe(i, _state.day) == 0:
            var result: Dictionary = _state.farm.harvest(i, _state.day)
            parts.append(
                "%d crates of %s" % [result["count"], _state.good_name(result["good"]).to_lower()]
            )
    _show_farm("You harvested %s." % ", ".join(parts))


func _show_land() -> void:
    var items: Array = []
    var actions: Array[Callable] = []
    for plot in _state.farm.plot_kinds:
        if plot["id"] in _state.farm.plots:
            continue
        (
            items
            . append(
                {
                    "title": plot["name"],
                    "detail": "%d silver" % int(plot["price"]),
                    "enabled": _state.silver >= int(plot["price"]),
                }
            )
        )
        actions.append(_buy_land.bind(plot))
    _show_list(
        "Buy land",
        "More land: more fields and more room for the animals.",
        items,
        actions,
        0,
        func(_p: int) -> void: _show_land()
    )


func _buy_land(plot: Dictionary) -> void:
    _state.silver -= int(plot["price"])
    _state.farm.add_plot(plot["id"])
    _show_farm("%s is yours now!" % plot["name"])


func _unload() -> void:
    var parts: Array[String] = []
    for item in _state.cargo.keys():
        var count := int(_state.cargo[item])
        if item.begins_with("animal:"):
            var kind: String = item.trim_prefix("animal:")
            for i in range(count):
                if _state.farm.has_room_for(kind):
                    _state.farm.add_animal(kind)
                    _state.remove_cargo(item)
                    parts.append("a %s" % String(_state.farm.animal_kinds[kind]["name"]).to_lower())
        else:
            _state.farm.put(item, count)
            _state.remove_cargo(item, count)
            parts.append("%d %s" % [count, _state.good_name(item).to_lower()])
    var text := (
        "Unloaded: %s." % ", ".join(parts)
        if not parts.is_empty()
        else "There is no room for the animals; buy more land."
    )
    _show_home(text)


func _show_load(page: int, message := "") -> void:
    var items: Array = []
    var actions: Array[Callable] = []
    for good in _store_goods():
        (
            items
            . append(
                {
                    "title": "Load %s" % _state.good_name(good).to_lower(),
                    "detail": "%d in the store" % _state.farm.crates(good),
                    "color": _state.economy.goods[good]["color"],
                    "picture": ["goods", good],
                    "enabled": _state.has_room(),
                }
            )
        )
        actions.append(_load_good.bind(good, page))
    var text := (
        message
        if message != ""
        else "Room in the boat: %d crates." % (_state.capacity - _state.load_count())
    )
    _show_list("The store", text, items, actions, page, _show_load)


func _load_good(good: String, page: int) -> void:
    if _state.has_room() and _state.farm.take(good, 1) == 1:
        _state.add_cargo(good)
    _show_load(page, "Room in the boat: %d crates." % (_state.capacity - _state.load_count()))


func _sleep() -> void:
    var before: Dictionary = _state.farm.store.duplicate()
    _state.next_day()
    _state.save()
    var made: Array[String] = []
    for good in _state.farm.store.keys():
        var gained := float(_state.farm.store[good]) - float(before.get(good, 0.0))
        if gained > 0.05:
            made.append("%.1f %s" % [gained, _state.good_name(good).to_lower()])
    var lines: Array[String] = ["Good morning! It is day %d." % _state.day]
    if not made.is_empty():
        lines.append("The farm made %s overnight." % ", ".join(made))
    for reminder in _state.farm.reminders(_state.day):
        lines.append(reminder["text"])
    lines.append("The voyage is saved: you can stop here and come back another day.")
    var cards: Array = [
        {"title": "Row out", "detail": "a new day"},
        {"title": "Stop for today", "detail": "see you!"},
        {"title": "The farm", "detail": ""}
    ]
    var actions: Array[Callable] = [_world.undock.bind("home"), _world.quit, _show_farm]
    _world.show_screen("A new day", " ".join(lines), cards, actions, GRANDMOTHER)
