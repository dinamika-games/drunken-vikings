class_name Gossip
extends RefCounted

## What the skippers of the boats on the lakes tell the players: the news (a
## good deal, a bad price, an event, a reminder of the farm, a fun fact of the
## time) and the quick offers (a few crates bought or sold on the spot, or a
## swap). The news are made from the state of the economy, so they are true
## when told (see DESIGN.md, "The boats on the lakes").

## The skippers: each has a name, a kind (what they know best), their looks
## (for the face) and the color of their sail.
const SKIPPERS := [
    {
        "name": "Ragna the fisher",
        "kind": "fisher",
        "goods": ["fish", "salt", "ale"],
        "hair": "c9602a",
        "braids": true,
        "sail": "e8e0d0"
    },
    {
        "name": "Old Halvard the ferryman",
        "kind": "ferryman",
        "goods": [],
        "hair": "d8d8d0",
        "braids": false,
        "sail": "8a5a2b"
    },
    {
        "name": "Inga the messenger",
        "kind": "messenger",
        "goods": ["mead", "ale", "flowers"],
        "hair": "3a2a1a",
        "braids": true,
        "sail": "2f5f8a"
    },
    {
        "name": "Bjørn the salt trader",
        "kind": "trader",
        "goods": ["salt", "grain", "cloth"],
        "hair": "8a5a2b",
        "braids": false,
        "sail": "b8332a"
    },
    {
        "name": "Freya and Liv in their canoe",
        "kind": "children",
        "goods": ["eggs", "flowers", "honey"],
        "hair": "e8c25a",
        "braids": true,
        "sail": "e86a9a"
    },
    {
        "name": "Sigvor the goat woman",
        "kind": "farmer",
        "goods": ["cheese", "hay", "wool"],
        "hair": "a04a20",
        "braids": true,
        "sail": "6a9a4a"
    },
]

## The fun facts of the time, which the skippers tell now and then.
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
    var kinds := ["deal", "cheap", "bad", "event", "farm", "fact"]
    var weights := [4, 3, 2, 3, 2, 1]
    for attempt in range(8):
        var kind: String = kinds[_weighted(weights, rng)]
        var good := _pick_good(state, who, rng)
        match kind:
            "deal":
                var best := economy.best_sell(good)
                if best["place"] != "" and economy.mood(best["place"], good) > 0:
                    return {
                        "text":
                        (
                            "They pay %d silver for %s in %s! Bring them some."
                            % [best["price"], _lower(state, good), state.place_name(best["place"])]
                        ),
                        "place": best["place"],
                        "good": good
                    }
            "cheap":
                var best := economy.best_buy(good)
                if best["place"] != "":
                    return {
                        "text":
                        (
                            "%s costs only %d silver in %s."
                            % [
                                state.good_name(good),
                                best["price"],
                                state.place_name(best["place"])
                            ]
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
                        (
                            "Don't bring %s to %s, they have plenty: only %d silver."
                            % [_lower(state, good), state.place_name(worst), lowest]
                        ),
                        "place": worst,
                        "good": good
                    }
            "event":
                if not economy.events.is_empty():
                    var event: Dictionary = economy.events[rng.randi() % economy.events.size()]
                    return {
                        "text":
                        (
                            "%s in %s! They want %s there."
                            % [
                                event["title"],
                                state.place_name(event["place"]),
                                _lower(state, event["good"])
                            ]
                        ),
                        "place": event["place"],
                        "good": event["good"]
                    }
            "farm":
                var reminders: Array = state.farm.reminders(state.day)
                if not reminders.is_empty():
                    return {
                        "text": "Your grandmother asked me to tell you: " + reminders[0]["text"],
                        "place": "home",
                        "good": ""
                    }
            "fact":
                return {
                    "text": "Did you know? " + FACTS[rng.randi() % FACTS.size()],
                    "place": "",
                    "good": ""
                }
    return {
        "text": "Fair winds to you! " + FACTS[rng.randi() % FACTS.size()], "place": "", "good": ""
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
                    (
                        "Swap a crate of your %s for a crate of my %s?"
                        % [_lower(state, good), _lower(state, other)]
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
            (
                "You carry %s? I give you %d silver a crate for %d crate%s, right now."
                % [_lower(state, good), price, count, "" if count == 1 else "s"]
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
        (
            "I have %d crate%s of %s, %d silver each: cheaper than any market. Want them?"
            % [count, "" if count == 1 else "s", _lower(state, good), price]
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
                return "You have no room or not enough silver."
            return (
                "You bought %d crate%s of %s."
                % [bought, "" if bought == 1 else "s", _lower(state, good)]
            )
        "sell":
            var sold: int = state.remove_cargo(good, int(deal["count"]))
            state.silver += sold * int(deal["price"])
            return (
                "You sold %d crate%s for %d silver."
                % [sold, "" if sold == 1 else "s", sold * int(deal["price"])]
            )
        "swap":
            if state.remove_cargo(good, 1) == 1:
                state.add_cargo(deal["other"])
                return (
                    "You swapped %s for %s." % [_lower(state, good), _lower(state, deal["other"])]
                )
    return ""


static func _pick_good(state: Node, who: Dictionary, rng: RandomNumberGenerator) -> String:
    if not who["goods"].is_empty() and rng.randf() < 0.7:
        return who["goods"][rng.randi() % who["goods"].size()]
    var ids: Array = state.economy.good_ids
    return ids[rng.randi() % ids.size()]


static func _lower(state: Node, good: String) -> String:
    return state.good_name(good).to_lower()


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
