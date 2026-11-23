extends SceneTree

## Check the prices of the goods (see Economy) and the trading of GameState.
## Run with:
## [code]$GODOT --headless --path . --script tests/godot/test_economy.gd -- --no-camera[/code]

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    var state: Node = root.get_node("GameState")
    _check(state.error == "", "The data loads: %s" % state.error)
    # NOTE (mristin):
    # Never touch the voyage of the players.
    state.save_path = "user://test_voyage.json"
    state.new_voyage()
    var economy: Economy = state.economy

    # Every place of the map is a settlement of the economy, and the goods they
    # trade exist.
    for id in state.places.keys():
        _check(economy.places.has(id), "The economy knows the place %s" % id)
    _check(not economy.is_market("home"), "The home farm is no market")
    _check(economy.is_market("market"), "The market village is a market")

    # Cheap where made, dear where wanted.
    _check(
        economy.buy_price("fishers", "fish") < economy.sell_price("inn", "fish"),
        "Buying fish from the fishers and selling them at the inn pays"
    )
    _check(
        economy.sells("fishers", "fish") and not economy.sells("inn", "fish"),
        "Only the fishers sell fish"
    )
    _check(economy.buy_price("market", "salt") > 0, "The market sells salt")

    # Selling much lowers the price; it recovers over the days.
    var before := economy.sell_price("inn", "fish")
    for i in range(5):
        economy.sold("inn", "fish")
    var after := economy.sell_price("inn", "fish")
    _check(after < before, "Selling much lowers the price: %d -> %d" % [before, after])
    for i in range(10):
        economy.next_day()
    _check(economy.sell_price("inn", "fish") == before, "The price recovers over the days")

    # Events.
    var ale := economy.sell_price("inn", "ale")
    economy.start_event("inn", "ale", 1.8, 2, "A wedding")
    _check(economy.sell_price("inn", "ale") > ale, "A wedding raises the price of ale")
    economy.next_day()
    economy.next_day()
    _check(economy.sell_price("inn", "ale") == ale, "The wedding ends")

    # The best places.
    _check(economy.best_buy("fish")["place"] == "fishers", "Fish are cheapest at the fishers")
    _check(
        (
            economy.best_sell("ale")["place"] == "inn"
            or economy.best_sell("ale")["place"] == "fishers"
        ),
        "Ale sells best where it is wanted"
    )

    # Trading with the boat.
    state.silver = 30
    _check(state.buy("fishers", "fish"), "The players buy a crate of fish")
    _check(state.cargo.get("fish", 0) == 1, "The fish are in the boat")
    _check(not state.buy("inn", "fish"), "The inn sells no fish")
    var silver: int = state.silver
    _check(state.sell("inn", "fish"), "The players sell the fish at the inn")
    _check(state.silver > silver, "Selling brings silver")
    for i in range(10):
        state.buy("fishers", "fish")
    _check(state.load_count() == state.capacity, "The boat carries only its crates")

    # The save keeps the voyage.
    state.silver = 77
    state.day = 5
    _check(state.save(), "The voyage saves")
    state.new_voyage()
    _check(state.load_voyage() and state.silver == 77 and state.day == 5, "The voyage loads again")

    if _failures.is_empty():
        print("PASS test_economy")
    quit(1 if not _failures.is_empty() else 0)
