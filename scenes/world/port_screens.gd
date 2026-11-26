class_name PortScreens
extends RefCounted

## The screens of the ports and of the farm (see world.gd): the market (sell,
## buy, the animals, the news of the people), and at home the farm (plant,
## harvest, buy land), the unloading and the loading of the boat, and the
## sleep which ends the day. In every port, the missions do what they ask
## there first (see Missions), and the card "Tasks" shows the missions the
## people offer there and those under way.

## What each kind of settlement is called on the screens (English message
## IDs, see Grammar).
# TRANSLATORS[]: what a settlement is, after its name in a title, e.g., "Kråkhamn, the market"
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

## How many cards a list shows at once (with "More" and "Back", six cards
## fit the screen side by side).
const PAGE := 4

var _world: Node
var _state: Node
var _map: LakeMap
var _rng := RandomNumberGenerator.new()
var _shipyard: ShipyardScreens


func _init(world: Node, state: Node, map: LakeMap) -> void:
    _world = world
    _state = state
    _map = map
    _shipyard = ShipyardScreens.new(world, state, show_port)
    _rng.seed = Time.get_ticks_usec()


func place_title(id: String) -> String:
    var place := _map.place(id)
    return Grammar.text(
        "{place}, {kind}", {"place": place["name"], "kind": KIND_NAMES.get(place["kind"], "")}
    )


func show_port(message := "") -> void:
    if _run_tasks(show_port.bind(message)):
        return
    var id: String = _state.place
    var place := _map.place(id)
    if place["kind"] == "home":
        _show_home(message)
        return
    var economy: Economy = _state.economy
    var sellable := _sellable(id)
    var text := message if message != "" else Grammar.text("Welcome! What would you like to do?")
    if message == "":
        text = " ".join([text] + _task_notes(id))
        if id == _state.ships.shipyard:
            text += (
                " "
                + Grammar.text(
                    "{person} builds ships here.", {"person": _state.ships.shipwright["name"]}
                )
            )
    var cards: Array = [
        ChoicePanel.card(
            "Sell",
            (
                ChoicePanel.detail("{count} {count|crate|crates}", {"count": sellable.size()})
                if not sellable.is_empty()
                else ChoicePanel.detail("nothing to sell")
            ),
            {"enabled": not sellable.is_empty()}
        ),
        ChoicePanel.card("Buy", silver(_state.silver), {"enabled": _goods_sold(id).size() > 0}),
    ]
    var actions: Array[Callable] = [_show_sell.bind(0), _show_buy.bind(0)]
    if ANIMALS_SOLD.has(place["kind"]):
        cards.append(ChoicePanel.card("Animals", ChoicePanel.detail("for your farm")))
        actions.append(_show_animals)
    if id == _state.ships.shipyard:
        cards.append(ChoicePanel.card("Shipyard", Grammar.text(_state.ships.shipwright["short"])))
        actions.append(_shipyard.show)
    cards.append(_tasks_card(id))
    actions.append(_show_tasks.bind(0))
    cards.append(ChoicePanel.card("Talk", ChoicePanel.detail("the news")))
    actions.append(_talk)
    cards.append(ChoicePanel.card("Row on"))
    actions.append(_world.undock.bind(id))
    if economy.is_market(id):
        for good in economy.good_ids:
            _state.note_prices(id, good)
    var face := {}
    if Pictures.of("faces", place["kind"]) != null:
        face = {"picture": place["kind"]}
    _world.show_screen(place_title(id), text, cards, actions, face)


## So much silver, short enough for a card, e.g., "12 silver".
static func silver(amount: int) -> String:
    return ChoicePanel.detail("{silver} silver", {"silver": amount})


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
        cards.append(ChoicePanel.card("More", "→"))
        actions.append(again.bind(page + 1))
    cards.append(ChoicePanel.card("Back"))
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
                    "id": "Sell {good} ({count})",
                    "title":
                    ChoicePanel.title_of(
                        "Sell {good} ({count})",
                        {"good": _state.good_name(good), "count": int(_state.cargo[good])}
                    ),
                    "detail": silver(economy.sell_price(id, good)),
                    "color": economy.goods[good]["color"],
                    "picture": ["goods", good],
                    "mood": economy.mood(id, good),
                }
            )
        )
        actions.append(_sell.bind(good, page))
    if items.is_empty():
        show_port(message if message != "" else Grammar.text("Nothing more to sell here."))
        return
    var text := (
        message
        if message != ""
        else Grammar.text("What do you sell? Silver: {silver}.", {"silver": _state.silver})
    )
    _show_list(place_title(id), text, items, actions, page, _show_sell)


func _sell(good: String, page: int) -> void:
    var id: String = _state.place
    var price: int = _state.economy.sell_price(id, good)
    if _state.sell(id, good):
        Audio.play("coins")
        _show_sell(
            page,
            Grammar.text(
                "Sold a crate of {good} for {price} silver. Silver: {silver}.",
                {"good": _state.good_name(good), "price": price, "silver": _state.silver}
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
                    "id": "Buy {good}",
                    "title": ChoicePanel.title_of("Buy {good}", {"good": _state.good_name(good)}),
                    "detail": silver(price),
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
        text = Grammar.text(
            "Silver: {silver}. Room in the boat: {room} of {crates} crates.",
            {
                "silver": _state.silver,
                "room": _state.capacity - _state.load_count(),
                "crates": _state.capacity
            }
        )
    _show_list(place_title(id), text, items, actions, page, _show_buy)


func _buy(good: String, page: int) -> void:
    var id: String = _state.place
    var price: int = _state.economy.buy_price(id, good)
    if _state.buy(id, good):
        Audio.play("coins")
        _show_buy(
            page,
            Grammar.text(
                (
                    "Bought a crate of {good} for {price} silver. Silver: "
                    + "{silver}, room for {room} more."
                ),
                {
                    "good": _state.good_name(good),
                    "price": price,
                    "silver": _state.silver,
                    "room": _state.capacity - _state.load_count()
                }
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
                    "id": "Buy {animal}",
                    "title": ChoicePanel.title_of("Buy {animal}", {"animal": _one(kind)}),
                    "detail": silver(price),
                    "picture": ["farm", "beehive" if kind == "bees" else kind],
                    "enabled": _state.silver >= price and _state.has_room(),
                }
            )
        )
        actions.append(_buy_animal.bind(kind))
    # NOTE (mristin):
    # The animals which the place deals in can be sold here, too, from the
    # boat or (fetched) from the farm: a full pasture never keeps a task from
    # being done (see dev/balance/balance.gd).
    for kind in ANIMALS_SOLD.get(place["kind"], []):
        var owned := _animals_owned(kind)
        if owned == 0:
            continue
        (
            items
            . append(
                {
                    "id": "Sell {animal}",
                    "title": ChoicePanel.title_of("Sell {animal}", {"animal": _one(kind)}),
                    "detail": ChoicePanel.detail("+{silver} silver", {"silver": sale_price(kind)}),
                    "picture": ["farm", "beehive" if kind == "bees" else kind],
                }
            )
        )
        actions.append(_sell_animal.bind(kind))
    var text := (
        message
        if message != ""
        else Grammar.text(
            "An animal takes the room of a crate in the boat. Silver: {silver}.",
            {"silver": _state.silver}
        )
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
    Audio.play(Audio.ANIMALS.get(kind, "coins"))
    _show_animals(
        Grammar.text("{animal} is in the boat. Row it home to your farm!", {"animal": _one(kind)})
    )


## One animal of the [param kind], e.g., "a goat" (see Grammar.phrase).
func _one(kind: String) -> Dictionary:
    return Missions.crates(_state, "animal:" + kind, 1)


## What a place pays for an animal of the [param kind]: half its price.
func sale_price(kind: String) -> int:
    return maxi(1, int(_state.farm.animal_kinds[kind]["price"]) / 2)


## How many animals of the [param kind] the players have, in the boat and on
## the farm.
func _animals_owned(kind: String) -> int:
    return int(_state.cargo.get("animal:" + kind, 0)) + int(_state.farm.animals.get(kind, 0))


func _sell_animal(kind: String) -> void:
    var args := {"animal": _one(kind), "price": sale_price(kind)}
    var text := ""
    if _state.remove_cargo("animal:" + kind) == 1:
        text = Grammar.text("You sold {animal} from your boat for {price} silver.", args)
    elif _state.farm.remove_animal(kind):
        text = Grammar.text(
            "You sold {animal} from your farm for {price} silver; they fetch it tomorrow.", args
        )
    else:
        _show_animals()
        return
    _state.silver += sale_price(kind)
    Audio.play("coins")
    _show_animals(text + " " + Grammar.text("Silver: {silver}.", {"silver": _state.silver}))


func _talk() -> void:
    var who := {"name": "", "goods": [], "hair": Color("8a5a2b"), "braids": _rng.randf() < 0.5}
    var news := Gossip.news(_state, who, _rng)
    _state.hear(news["text"], news["place"], news["good"])
    var cards: Array = [ChoicePanel.card("Thank you!")]
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
    if _run_tasks(_show_home.bind(message)):
        return
    var farm: Farm = _state.farm
    var text := message
    if text == "":
        var reminders := farm.reminders(_state.day)
        text = (
            Grammar.text("Grandmother Åsa waves from the jetty.")
            + " "
            + (
                reminders[0]["text"]
                if not reminders.is_empty()
                else Grammar.text("All is well on the farm.")
            )
        )
        text = " ".join([text] + _task_notes("home"))
    var cards: Array = [
        ChoicePanel.card("The farm", _animals_count()),
        ChoicePanel.card(
            "Unload the boat",
            ChoicePanel.detail("{count} {count|crate|crates}", {"count": _unloadable()}),
            {"enabled": _unloadable() > 0}
        ),
        ChoicePanel.card(
            "Load from the store",
            "",
            {"enabled": not _store_goods().is_empty() and _state.has_room()}
        ),
        _tasks_card("home"),
        ChoicePanel.card(
            "Sleep",
            (
                ChoicePanel.detail("end the day")
                if _state.travelled
                else ChoicePanel.detail("row a trip first")
            ),
            {"enabled": _state.travelled}
        ),
        ChoicePanel.card("Row out"),
    ]
    var actions: Array[Callable] = [
        _show_farm,
        _unload,
        _show_load.bind(0),
        _show_tasks.bind(0),
        _sleep,
        _world.undock.bind("home")
    ]
    _world.show_screen(place_title("home"), text, cards, actions, GRANDMOTHER)


## How many animals the farm keeps, short enough for a card.
func _animals_count() -> String:
    var total := 0
    for kind in _state.farm.animals.keys():
        total += int(_state.farm.animals[kind])
    return ChoicePanel.detail("{count} {count|animal|animals}", {"count": total})


## The animals of the farm, e.g., [3 hens, a sheep] (see Grammar.phrase).
func _animals_line() -> Array:
    var parts: Array = []
    for kind in _state.farm.animals.keys():
        parts.append(Missions.crates(_state, "animal:" + kind, int(_state.farm.animals[kind])))
    return parts


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
    lines.append(
        Grammar.text(
            "Animals: {animals} (room for {room}).",
            {"animals": _animals_line(), "room": int(farm.pasture)}
        )
    )
    var store: Array = []
    for good in farm.store.keys():
        if farm.crates(good) > 0:
            store.append(Missions.crates(_state, good, farm.crates(good)))
    if store.is_empty():
        lines.append(Grammar.text("Store: empty."))
    else:
        lines.append(Grammar.text("Store: {goods}.", {"goods": store}))
    # NOTE: The board has room for the two most pressing reminders.
    for reminder in farm.reminders(_state.day).slice(0, 2):
        lines.append(reminder["text"])
    var empty := -1
    var ripe := false
    for i in range(farm.fields.size()):
        if farm.fields[i]["crop"] == "" and empty < 0:
            empty = i
        elif farm.fields[i]["crop"] != "" and farm.days_to_ripe(i, _state.day) == 0:
            ripe = true
    var cards: Array = [
        ChoicePanel.card(
            "Plant",
            (
                ChoicePanel.detail("an empty field")
                if empty >= 0
                else ChoicePanel.detail("no empty field")
            ),
            {"enabled": empty >= 0}
        ),
        ChoicePanel.card("Harvest", "", {"enabled": ripe}),
        ChoicePanel.card("Buy land", silver(_state.silver)),
        ChoicePanel.card("Back"),
    ]
    var actions: Array[Callable] = [_show_plant.bind(empty), _harvest, _show_land, _show_home]
    _world.show_screen(Grammar.text("The farm"), " ".join(lines), cards, actions, GRANDMOTHER)


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
                    "id": crop,
                    "title": Grammar.title(kind["name"]),
                    "detail":
                    Grammar.text(
                        "{silver} silver, {days} {days|day|days}",
                        {"silver": price, "days": int(kind["days"])}
                    ),
                    "color": _state.economy.goods[kind["gives"]]["color"],
                    "picture": ["farm", CROP_PICTURES.get(crop, "")],
                    "enabled": _state.silver >= price,
                }
            )
        )
        actions.append(_plant.bind(field, crop))
    _show_list(
        Grammar.text("Plant a field"),
        Grammar.text(
            "What do you plant? It grows while you trade; come back to harvest it in time."
        ),
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
        Grammar.text(
            "You planted {crop}. It is ripe in {days} {days|day|days}.",
            {"crop": kind["name"], "days": int(kind["days"])}
        )
    )


func _harvest() -> void:
    var parts: Array = []
    for i in range(_state.farm.fields.size()):
        var crop: String = _state.farm.fields[i]["crop"]
        if crop != "" and _state.farm.days_to_ripe(i, _state.day) == 0:
            var result: Dictionary = _state.farm.harvest(i, _state.day)
            parts.append(Missions.crates(_state, result["good"], int(result["count"])))
    _show_farm(Grammar.text("You harvested {goods}.", {"goods": parts}))


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
                    "id": plot["id"],
                    "title": Grammar.title(plot["name"]),
                    "detail": silver(int(plot["price"])),
                    "enabled": _state.silver >= int(plot["price"]),
                }
            )
        )
        actions.append(_buy_land.bind(plot))
    _show_list(
        Grammar.text("Buy land"),
        Grammar.text("More land: more fields and more room for the animals."),
        items,
        actions,
        0,
        func(_p: int) -> void: _show_land()
    )


func _buy_land(plot: Dictionary) -> void:
    _state.silver -= int(plot["price"])
    _state.farm.add_plot(plot["id"])
    _show_farm(Grammar.text("{plot} is yours now!", {"plot": plot["name"]}))


func _unload() -> void:
    Audio.play("creak")
    var parts: Array = []
    var animals := {}
    for item in _state.cargo.keys():
        var count := int(_state.cargo[item])
        if Missions.is_item(item):
            # NOTE: The items of the missions belong elsewhere; they stay in the boat.
            continue
        if item.begins_with("animal:"):
            var kind: String = item.trim_prefix("animal:")
            for i in range(count):
                if _state.farm.has_room_for(kind):
                    _state.farm.add_animal(kind)
                    _state.remove_cargo(item)
                    animals[item] = int(animals.get(item, 0)) + 1
        else:
            _state.farm.put(item, count)
            _state.remove_cargo(item, count)
            parts.append(Missions.crates(_state, item, count))
    for item in animals.keys():
        parts.append(Missions.crates(_state, item, int(animals[item])))
    var text := (
        Grammar.text("Unloaded: {things}.", {"things": parts})
        if not parts.is_empty()
        else Grammar.text(
            "Nothing to unload: no room for the animals, or only what your tasks carry."
        )
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
                    "id": "Load {good}",
                    "title": ChoicePanel.title_of("Load {good}", {"good": _state.good_name(good)}),
                    "detail":
                    ChoicePanel.detail("{count} in the store", {"count": _state.farm.crates(good)}),
                    "color": _state.economy.goods[good]["color"],
                    "picture": ["goods", good],
                    "enabled": _state.has_room(),
                }
            )
        )
        actions.append(_load_good.bind(good, page))
    var text := message if message != "" else _room()
    _show_list(Grammar.text("The store"), text, items, actions, page, _show_load)


func _room() -> String:
    var room: int = _state.capacity - _state.load_count()
    return Grammar.text("Room in the boat: {room} {room|crate|crates}.", {"room": room})


func _load_good(good: String, page: int) -> void:
    if _state.has_room() and _state.farm.take(good, 1) == 1:
        _state.add_cargo(good)
    _show_load(page, _room())


func _sleep() -> void:
    var before: Dictionary = _state.farm.store.duplicate()
    _state.next_day()
    Audio.play("rooster")
    _state.save()
    var made: Array = []
    for good in _state.farm.store.keys():
        var gained := float(_state.farm.store[good]) - float(before.get(good, 0.0))
        if gained > 0.05:
            var args := {"crates": Grammar.decimal(gained), "good": _state.good_name(good)}
            # TRANSLATORS: a share of crates of a good, e.g., "1.5 crates of eggs"
            made.append(Grammar.phrase("{crates} crates of {good}", args))
    var lines: Array[String] = [Grammar.text("Good morning! It is day {day}.", {"day": _state.day})]
    if not made.is_empty():
        lines.append(Grammar.text("The farm made {goods} overnight.", {"goods": made}))
    var young: Array = []
    for kind in _state.farm.born.keys():
        young.append(
            Grammar.phrase(
                str(_state.farm.animal_kinds[kind]["young"]), {"count": int(_state.farm.born[kind])}
            )
        )
    if not young.is_empty():
        lines.append(Grammar.text("New on the farm: {young}!", {"young": young}))
    # NOTE: The board has room for the two most pressing reminders.
    for reminder in _state.farm.reminders(_state.day).slice(0, 2):
        lines.append(reminder["text"])
    lines.append(Grammar.text("The voyage is saved: you can stop here and come back another day."))
    var cards: Array = [
        ChoicePanel.card("Row out", ChoicePanel.detail("a new day")),
        ChoicePanel.card("Stop for today", ChoicePanel.detail("see you!")),
        ChoicePanel.card("The farm")
    ]
    var actions: Array[Callable] = [_world.undock.bind("home"), _world.quit, _show_farm]
    _world.show_screen(Grammar.text("A new day"), " ".join(lines), cards, actions, GRANDMOTHER)


## How many crates of the boat can be unloaded at home (not the items of the missions).
func _unloadable() -> int:
    var count := 0
    for item in _state.cargo.keys():
        if not Missions.is_item(item):
            count += int(_state.cargo[item])
    return count


# ---------------------------------------------------------------------------
# The missions
# ---------------------------------------------------------------------------


## The face of who speaks for a mission (see Missions.arrive): their painted
## face, or the face of the place.
func _face(who: Dictionary, place: String) -> Dictionary:
    if not who.is_empty():
        return {
            "picture": str(who.get("picture", "")),
            "hair": Color(str(who.get("hair", "8a5a2b"))),
            "braids": bool(who.get("braids", false)),
        }
    if place != "":
        var kind: String = _map.place(place).get("kind", "")
        if kind == "home":
            return GRANDMOTHER
        if Pictures.of("faces", kind) != null:
            return {"picture": kind}
    return {}


## Do what the missions ask at the place of the boat; if anything happened,
## show it, and then call [param then]. Return whether anything happened.
func _run_tasks(then: Callable) -> bool:
    var events: Array = _state.missions.arrive(_state, _state.place)
    if events.is_empty():
        return false
    _state.save()
    _show_events(events, 0, then)
    return true


## Show the screens of the [param events] (see Missions.arrive), one by one,
## from the [param index], and then call [param then].
func _show_events(events: Array, index: int, then: Callable) -> void:
    if index >= events.size():
        then.call()
        return
    var event: Dictionary = events[index]
    var who: Dictionary = event["who"]
    var text: String = event["text"]
    if str(who.get("name", "")) != "":
        text = said(who["name"], text)
    var cards: Array = [ChoicePanel.card("Hooray!") if event["done"] else ChoicePanel.card("Go on")]
    if event["done"]:
        cards[0]["stars"] = int(event.get("stars", 0))
        Audio.play("hooray")
    var actions: Array[Callable] = [_show_events.bind(events, index + 1, then)]
    _world.show_screen(event["title"], text, cards, actions, _face(who, event["place"]))


## What the [param person] says: their name and the [param text] in quotes.
static func said(person: String, text: String) -> String:
    # TRANSLATORS: who says what, e.g., Ulf: "Welcome!"; use the quotes of your language
    return Grammar.text('{person}: "{text}"', {"person": person, "text": Grammar.raw(text)})


## What the missions ask at the [param place] and can not be done yet, and
## who has a new task here.
func _task_notes(place: String) -> Array[String]:
    var notes: Array[String] = _state.missions.blocked_at(_state, place)
    var offers: Array[String] = _state.missions.offers_at(place)
    if not offers.is_empty():
        var giver: Dictionary = _state.missions.missions[offers[0]]["giver"]
        notes.append(Grammar.text("{person} has a task for you!", {"person": giver["name"]}))
    return notes


func _tasks_card(place: String) -> Dictionary:
    var offers: int = _state.missions.offers_at(place).size()
    var detail := ChoicePanel.detail("{count} under way", {"count": _state.missions.active.size()})
    if offers > 0:
        detail = ChoicePanel.detail("{count} new!", {"count": offers})
    return ChoicePanel.card("Tasks", detail)


## The missions offered here, and those under way.
func _show_tasks(page: int, message := "") -> void:
    var missions: Missions = _state.missions
    var items: Array = []
    var actions: Array[Callable] = []
    for id in missions.offers_at(_state.place):
        items.append(
            {
                "id": id,
                "title": Grammar.text(missions.missions[id]["title"]),
                "detail": ChoicePanel.detail("new task!")
            }
        )
        actions.append(_show_offer.bind(id))
    for entry in missions.active:
        var id: String = entry["id"]
        var where: String = missions.target(_state, id)
        (
            items
            . append(
                {
                    "id": id,
                    "title": Grammar.text(missions.missions[id]["title"]),
                    "detail":
                    (
                        Grammar.text(_state.place_name(where))
                        if where != ""
                        else ChoicePanel.detail("on the lakes")
                    ),
                }
            )
        )
        actions.append(_show_task.bind(id))
    var text := message
    if text == "":
        var lines: Array[String] = []
        if missions.active.is_empty():
            lines.append(Grammar.text("No task under way."))
        var elsewhere: Array = []
        for id in missions.available():
            var giver: Dictionary = missions.missions[id]["giver"]
            if giver["place"] != _state.place:
                elsewhere.append(
                    Grammar.phrase(
                        "{person} in {place}",
                        {"person": giver["name"], "place": _state.place_name(giver["place"])}
                    )
                )
        if not elsewhere.is_empty():
            lines.append(
                Grammar.text("Tasks wait for you: {people}.", {"people": elsewhere.slice(0, 3)})
            )
        lines.append(
            Grammar.text(
                "Done: {tasks} {tasks|task|tasks}, {stars} {stars|star|stars}.",
                {"tasks": missions.done.size(), "stars": missions.stars()}
            )
        )
        text = " ".join(lines)
    _show_list(Grammar.text("Tasks"), text, items, actions, page, _show_tasks)


func _show_offer(id: String) -> void:
    var missions: Missions = _state.missions
    var mission: Dictionary = missions.missions[id]
    var giver: Dictionary = mission["giver"]
    var text := said(giver["name"], Grammar.text(mission["offer"]))
    if mission.has("days"):
        var days := int(mission["days"])
        text += (" " + Grammar.text("(Three stars within {days} {days|day|days}.)", {"days": days}))
    var cards: Array = [
        ChoicePanel.card(
            "Yes, I will help!",
            "" if missions.can_accept() else ChoicePanel.detail("first finish a task"),
            {"enabled": missions.can_accept()}
        ),
        ChoicePanel.card("Not now"),
    ]
    var actions: Array[Callable] = [_accept.bind(id), _show_tasks.bind(0)]
    _world.show_screen(
        Grammar.text(mission["title"]), text, cards, actions, _face(giver, giver["place"])
    )


func _accept(id: String) -> void:
    _state.missions.accept(id, _state.day)
    _state.save()
    var hint: String = _state.missions.hint(_state, id)
    if _state.missions.target(_state, id) == _state.place:
        # NOTE: The first step is right here: do it at once.
        show_port()
        return
    show_port(Grammar.text("Off you go!") + " " + hint)


func _show_task(id: String) -> void:
    var missions: Missions = _state.missions
    var cards: Array = [ChoicePanel.card("Back")]
    var actions: Array[Callable] = [_show_tasks.bind(0)]
    _world.show_screen(
        Grammar.text(missions.missions[id]["title"]), missions.hint(_state, id), cards, actions
    )
