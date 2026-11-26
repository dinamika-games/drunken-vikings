class_name Gossip
extends RefCounted

## What the skippers of the boats on the lakes tell the players: the news (a
## good deal, a bad price, an event, a reminder of the farm, a fun fact of the
## time) and the quick offers (a few crates bought or sold on the spot, or a
## swap). The news are made from the state of the economy, so they are true
## when told (see DESIGN.md, "The boats on the lakes").

## The skippers: each has a name, their picture (of the sheets "skippers" and
## "faces", see Pictures), a kind (what they know best), their looks (for the
## face drawn in code) and the color of their sail.
# TRANSLATORS[name@person]: the name of a skipper on the lakes
const SKIPPERS := [
    {
        "name": "Ragna the fisher",
        "picture": "ragna",
        "kind": "fisher",
        "goods": ["fish", "salt", "ale"],
        "hair": "c9602a",
        "braids": true,
        "sail": "e8e0d0"
    },
    {
        "name": "Old Halvard the ferryman",
        "picture": "halvard",
        "kind": "ferryman",
        "goods": [],
        "hair": "d8d8d0",
        "braids": false,
        "sail": "8a5a2b"
    },
    {
        "name": "Inga the messenger",
        "picture": "inga",
        "kind": "messenger",
        "goods": ["mead", "ale", "flowers"],
        "hair": "3a2a1a",
        "braids": true,
        "sail": "2f5f8a"
    },
    {
        "name": "Bjørn the salt trader",
        "picture": "bjorn",
        "kind": "trader",
        "goods": ["salt", "grain", "cloth"],
        "hair": "8a5a2b",
        "braids": false,
        "sail": "b8332a"
    },
    {
        "name": "Freya and Liv in their canoe",
        "picture": "freya_and_liv",
        "kind": "children",
        "goods": ["eggs", "flowers", "honey"],
        "hair": "e8c25a",
        "braids": true,
        "sail": "e86a9a"
    },
    {
        "name": "Sigvor the goat woman",
        "picture": "sigvor",
        "kind": "farmer",
        "goods": ["cheese", "hay", "wool"],
        "hair": "a04a20",
        "braids": true,
        "sail": "6a9a4a"
    },
]

## The fun facts of the time, which the skippers tell now and then (English
## message IDs, see Grammar).
# TRANSLATORS[]: a fun fact of the viking times, which a skipper tells, at most 2 short sentences
const FACTS := [
    (
        "The traders weigh their silver on small scales: a broken piece of a bracelet "
        + "buys as much as a coin of the same weight."
    ),
    "The combs of antler are so precious that people are buried with them.",
    "The vikings make their sails of wool; it takes a weaver a whole year to weave a big one.",
    "Honey is the only sweet the vikings know, so the bees are worth a lot.",
    "The runes are carved in straight lines, so that they are easy to cut in wood and stone.",
    "In winter, the lakes freeze, and people travel on skates made of horse bones.",
    "Women hold the keys of the house: a woman with keys on her belt runs the farm.",
    "The vikings give their boats names, like Long Serpent or Sea Horse.",
    "The cats on the farms catch the mice in the grain stores, so everybody loves them.",
    "A good horse is worth more than a whole boatload of fish.",
]


## The skipper of the given index, with the colors as Color.
static func skipper(index: int) -> Dictionary:
    var data: Dictionary = SKIPPERS[index % SKIPPERS.size()].duplicate()
    data["hair"] = Color(data["hair"])
    data["sail"] = Color(data["sail"])
    return data


## A piece of news from the skipper: {"text", "place", "good"}.
static func news(state: Node, who: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
    var economy: Economy = state.economy
    var kinds := ["deal", "cheap", "bad", "event", "farm", "fact", "task", "ship"]
    var weights := [4, 3, 2, 3, 2, 1, 2, 1]
    for attempt in range(8):
        var kind: String = kinds[_weighted(weights, rng)]
        var good := _pick_good(state, who, rng)
        match kind:
            "deal":
                var best := economy.best_sell(good)
                if best["place"] != "" and economy.mood(best["place"], good) > 0:
                    return {
                        "text":
                        Grammar.text(
                            "They pay {silver} silver for {good} in {place}! Bring them some.",
                            {
                                "silver": best["price"],
                                "good": state.good_name(good),
                                "place": state.place_name(best["place"])
                            }
                        ),
                        "place": best["place"],
                        "good": good
                    }
            "cheap":
                var best := economy.best_buy(good)
                if best["place"] != "":
                    return {
                        "text":
                        Grammar.text(
                            "{good} costs only {silver} silver in {place}.",
                            {
                                "good": state.good_name(good),
                                "silver": best["price"],
                                "place": state.place_name(best["place"])
                            }
                        ),
                        "place": best["place"],
                        "good": good
                    }
            "bad":
                var worst := ""
                var lowest := 1 << 30
                for place in economy.places.keys():
                    if economy.buys(place, good) and economy.sell_price(place, good) < lowest:
                        lowest = economy.sell_price(place, good)
                        worst = place
                if worst != "" and float(economy.pressure.get("%s|%s" % [worst, good], 1.0)) < 0.9:
                    return {
                        "text":
                        Grammar.text(
                            (
                                "Don't bring {good} to {place}, they have plenty: "
                                + "only {silver} silver."
                            ),
                            {
                                "good": state.good_name(good),
                                "place": state.place_name(worst),
                                "silver": lowest
                            }
                        ),
                        "place": worst,
                        "good": good
                    }
            "event":
                if not economy.events.is_empty():
                    var event: Dictionary = economy.events[rng.randi() % economy.events.size()]
                    return {
                        "text":
                        Grammar.text(
                            "{event} in {place}! They want {good} there.",
                            {
                                "event": event["title"],
                                "place": state.place_name(event["place"]),
                                "good": state.good_name(event["good"])
                            }
                        ),
                        "place": event["place"],
                        "good": event["good"]
                    }
            "farm":
                var reminders: Array = state.farm.reminders(state.day)
                if not reminders.is_empty():
                    return {
                        "text":
                        Grammar.text(
                            "Your grandmother asked me to tell you: {reminder}",
                            {"reminder": Grammar.raw(reminders[0]["text"])}
                        ),
                        "place": "home",
                        "good": ""
                    }
            "task":
                var offers: Array[String] = state.missions.available()
                if not offers.is_empty():
                    var mission: Dictionary = state.missions.missions[offers[
                        rng.randi() % offers.size()
                    ]]
                    var giver: Dictionary = mission["giver"]
                    return {
                        "text":
                        Grammar.text(
                            "{person} in {place} is looking for help: {task}.",
                            {
                                "person": giver["name"],
                                "place": state.place_name(giver["place"]),
                                "task": mission["title"]
                            }
                        ),
                        "place": giver["place"],
                        "good": ""
                    }
            "ship":
                var ships: Ships = state.ships
                for id in ships.ids:
                    if not id in ships.owned:
                        return {
                            "text":
                            Grammar.text(
                                (
                                    "{person} in {place} builds ships: a {ship} carries "
                                    + "{crates} crates, for {silver} silver!"
                                ),
                                {
                                    "person": ships.shipwright["name"],
                                    "place": state.place_name(ships.shipyard),
                                    "ship": ships.kinds[id]["name"],
                                    "crates": int(ships.kinds[id]["hold"]),
                                    "silver": int(ships.kinds[id]["price"])
                                }
                            ),
                            "place": ships.shipyard,
                            "good": ""
                        }
            "fact":
                return {
                    "text":
                    Grammar.text(
                        "Did you know? {fact}", {"fact": FACTS[rng.randi() % FACTS.size()]}
                    ),
                    "place": "",
                    "good": ""
                }
    return {
        "text":
        Grammar.text("Fair winds to you! {fact}", {"fact": FACTS[rng.randi() % FACTS.size()]}),
        "place": "",
        "good": ""
    }


## A quick offer of the skipper, or an empty Dictionary: {"kind": "buy"|"sell"|"swap",
## "good", "count", "price" (per crate), "other" (for a swap), "text"}.
## "buy": the players buy crates from the skipper; "sell": the skipper buys
## crates from the players; "swap": a crate of the players' "good" for a crate
## of "other".
static func offer(state: Node, who: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
    var economy: Economy = state.economy
    # NOTE (mristin):
    # Prefer to buy what the players carry: it is what they can use at once.
    var carried: Array = []
    for item in state.cargo.keys():
        if economy.goods.has(item):
            carried.append(item)
    if not carried.is_empty() and rng.randf() < 0.55:
        var good: String = carried[rng.randi() % carried.size()]
        if rng.randf() < 0.3:
            var other := _pick_good(state, who, rng)
            if other != good:
                return {
                    "kind": "swap",
                    "good": good,
                    "other": other,
                    "count": 1,
                    "price": 0,
                    "text":
                    Grammar.text(
                        "Swap a crate of your {good} for a crate of my {other}?",
                        {"good": state.good_name(good), "other": state.good_name(other)}
                    )
                }
        var best := economy.best_sell(good)
        var price := maxi(1, roundi(float(best["price"]) * rng.randf_range(1.0, 1.2)))
        var count := mini(int(state.cargo[good]), rng.randi_range(1, 2))
        return {
            "kind": "sell",
            "good": good,
            "other": "",
            "count": count,
            "price": price,
            "text":
            Grammar.text(
                (
                    "You carry {good}? I give you {silver} silver a crate for "
                    + "{count} {count|crate|crates}, right now."
                ),
                {"good": state.good_name(good), "silver": price, "count": count}
            )
        }
    if who["goods"].is_empty():
        return {}
    var good: String = who["goods"][rng.randi() % who["goods"].size()]
    var best := economy.best_buy(good)
    if best["place"] == "":
        best = {"price": economy.buy_price("market", good)}
    var price := maxi(1, roundi(float(best["price"]) * rng.randf_range(0.7, 0.95)))
    var count := rng.randi_range(1, 3)
    return {
        "kind": "buy",
        "good": good,
        "other": "",
        "count": count,
        "price": price,
        "text":
        Grammar.text(
            (
                "I have {count} {count|crate|crates} of {good}, {silver} silver each: "
                + "cheaper than any market. Want {count|it|them}?"
            ),
            {"count": count, "good": state.good_name(good), "silver": price}
        )
    }


## Take the offer: return what happened, for the players to read.
static func take(state: Node, deal: Dictionary) -> String:
    var good: String = deal["good"]
    match deal["kind"]:
        "buy":
            var bought := 0
            for i in range(int(deal["count"])):
                if not state.has_room() or state.silver < int(deal["price"]):
                    break
                state.silver -= int(deal["price"])
                state.add_cargo(good)
                bought += 1
            if bought == 0:
                return Grammar.text("You have no room or not enough silver.")
            return Grammar.text(
                "You bought {count} {count|crate|crates} of {good}.",
                {"count": bought, "good": state.good_name(good)}
            )
        "sell":
            var sold: int = state.remove_cargo(good, int(deal["count"]))
            state.silver += sold * int(deal["price"])
            return Grammar.text(
                "You sold {count} {count|crate|crates} for {silver} silver.",
                {"count": sold, "silver": sold * int(deal["price"])}
            )
        "swap":
            if state.remove_cargo(good, 1) == 1:
                state.add_cargo(deal["other"])
                return Grammar.text(
                    "You swapped {good} for {other}.",
                    {"good": state.good_name(good), "other": state.good_name(deal["other"])}
                )
    return ""


static func _pick_good(state: Node, who: Dictionary, rng: RandomNumberGenerator) -> String:
    if not who["goods"].is_empty() and rng.randf() < 0.7:
        return who["goods"][rng.randi() % who["goods"].size()]
    var ids: Array = state.economy.good_ids
    return ids[rng.randi() % ids.size()]


static func _weighted(weights: Array, rng: RandomNumberGenerator) -> int:
    var total := 0
    for w in weights:
        total += w
    var pick := rng.randi() % total
    for i in range(weights.size()):
        pick -= weights[i]
        if pick < 0:
            return i
    return weights.size() - 1
