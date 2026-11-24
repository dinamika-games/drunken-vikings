extends SceneTree

## Check the ships (see Ships): buying one takes silver and keeps it, taking
## one needs room for the cargo, the boatwright's crates go from ship to
## ship, the save keeps the ships (also from before the ships), and every
## ship rows as its data says.
##
## $GODOT --headless --path . --script tests/godot/test_ships.gd -- --no-camera

var _failures := 0


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        print("FAIL: " + what)


func _run() -> void:
    var state: Node = root.get_node("/root/GameState")
    _check(state.error == "", "the data loads: " + state.error)
    state.saves_dir = "user://test_ships"
    state.settings_path = "user://test_ships/settings.cfg"
    state.save_path = "user://test_ships/voyage.json"
    state.new_voyage()
    var ships: Ships = state.ships

    _check(ships.current == Ships.START, "a voyage starts in the rowing boat")
    _check(state.capacity == 4, "the rowing boat carries four crates")
    _check(state.economy.places.has(ships.shipyard), "the shipyard is a settlement")
    var last_price := -1
    for id in ships.ids:
        var kind: Dictionary = ships.kinds[id]
        _check(int(kind["price"]) > last_price, "the ships get dearer: %s" % id)
        last_price = int(kind["price"])
        for key in ["name", "hold", "crew", "push", "glide", "turn", "top", "about"]:
            _check(kind.has(key), "the ship %s has its %s" % [id, key])

    # Buying.
    state.silver = 50
    _check(not ships.buy(state, "faering"), "a færing costs more than 50 silver")
    _check(state.silver == 50, "a failed purchase costs nothing")
    state.silver = 100
    _check(ships.buy(state, "faering"), "a færing can be bought for 100 silver")
    _check(state.silver == 100 - int(ships.kinds["faering"]["price"]), "the færing is paid")
    _check(not ships.buy(state, "faering"), "a ship is bought only once")
    _check(ships.current == Ships.START, "buying does not take the ship yet")
    _check(ships.take("faering", state.load_count()), "the players take their færing")
    _check(state.capacity == 8, "the færing carries eight crates")

    # The cargo must fit.
    for i in range(6):
        state.add_cargo("fish")
    _check(not ships.take(Ships.START, state.load_count()), "six crates do not fit the rowing boat")
    _check(ships.current == "faering", "so the players keep the færing")
    _check(not ships.take("knarr", 0), "a ship which is not bought can not be taken")
    state.cargo = {}

    # The boatwright's crates go with the players.
    ships.hold_bonus = 2
    _check(state.capacity == 10, "the færing and two crates of the boatwright")
    _check(ships.take(Ships.START, 0) and state.capacity == 6, "the rowing boat keeps them too")

    # The save.
    ships.take("faering", 0)
    _check(state.save(), "the voyage saves")
    state.new_voyage()
    _check(state.load_voyage(), "the voyage loads")
    _check(ships.current == "faering", "the save keeps the ship")
    _check("faering" in ships.owned, "the save keeps the ships owned")
    _check(ships.hold_bonus == 2, "the save keeps the boatwright's crates")

    # A save from before the ships kept the whole hold.
    ships.restore({}, 8)
    _check(ships.current == Ships.START and ships.hold_bonus == 4, "an old hold of 8 becomes 4 + 4")

    # Every ship rows as its data says.
    var small := _row(ships.kinds[Ships.START])
    for id in ships.ids:
        var kind: Dictionary = ships.kinds[id]
        var rowed := _row(kind)
        if float(kind["glide"]) > 1.0:
            _check(rowed["glide"] > small["glide"], "the %s glides longer" % id)
        if float(kind["push"]) > 1.0:
            _check(rowed["push"] > small["push"], "a stroke pushes the %s more" % id)
        if float(kind["turn"]) < 1.0:
            _check(rowed["turn"] < small["turn"], "the %s turns slower" % id)

    # The scripts of the world, which sell and draw the ships, compile.
    for path in [
        "res://scenes/world/world.gd",
        "res://scenes/world/port_screens.gd",
        "res://scenes/world/world_hud.gd",
        "res://scenes/level/longship.gd",
        "res://scenes/level/rower_view.gd",
    ]:
        var script: Script = load(path)
        _check(script != null and script.can_instantiate(), "%s compiles" % path)

    print("PASS test_ships" if _failures == 0 else "FAIL test_ships (%d)" % _failures)
    quit(0 if _failures == 0 else 1)


## Row a boat as the ship of the [param kind] on a lake of open water: how
## fast one stroke makes it, which share of that it still goes 5 s later, and
## how far it turns in 1 s at full steering.
func _row(kind: Dictionary) -> Dictionary:
    var map := LakeMap.new()
    map.water = [
        {
            "outer":
            PackedVector2Array(
                [Vector2(0, 0), Vector2(2000, 0), Vector2(2000, 2000), Vector2(0, 2000)]
            ),
            "holes": []
        }
    ]
    var boat := RowBoat.new()
    boat.position = Vector2(1000, 1000)
    boat.set_ship(kind)
    boat.stroke()
    var push := boat.speed
    for i in range(300):
        boat.move(1.0 / 60.0, map)
    var turner := RowBoat.new()
    turner.position = Vector2(1000, 1000)
    turner.set_ship(kind)
    turner.steer = 1.0
    for i in range(60):
        turner.move(1.0 / 60.0, map)
    return {"push": push, "glide": boat.speed / push, "turn": absf(turner.heading)}
