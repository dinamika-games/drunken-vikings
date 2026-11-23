extends SceneTree

## Check the farm (see Farm): the animals eat and give, never die, the crops
## grow and must be harvested in time. Run with
## [code]$GODOT --headless --path . --script tests/godot/test_farm.gd -- --no-camera[/code].

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if not condition:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    var farm := Farm.new()
    _check(farm.load_data("res://data/farm/farm.json") == "", "The farm data loads")
    _check(
        farm.animals.get("hen", 0) == 3 and farm.animals.get("sheep", 0) == 1,
        "The farm starts with three hens and a sheep"
    )

    # The animals eat and give.
    var grain := float(farm.store.get("grain", 0.0))
    farm.next_day()
    _check(float(farm.store.get("grain", 0.0)) < grain, "The hens eat grain")
    _check(
        float(farm.store.get("eggs", 0.0)) > 0.9,
        "The hens lay eggs: %f" % farm.store.get("eggs", 0.0)
    )

    # Without feed, they are hungry and give nothing, but none dies.
    farm.store.erase("grain")
    farm.store.erase("hay")
    farm.store.erase("eggs")
    farm.store.erase("wool")
    for i in range(30):
        farm.next_day()
    _check(
        farm.animals.get("hen", 0) == 3 and farm.animals.get("sheep", 0) == 1, "No animal ever dies"
    )
    _check(farm.hungry.has("hen") and farm.hungry.has("sheep"), "The animals are hungry")
    _check(not farm.store.has("eggs"), "Hungry hens lay no eggs")
    var reminders := farm.reminders(1)
    _check(
        reminders.size() >= 2 and reminders[0]["kind"] == "hungry",
        "The farm reminds of the hungry animals"
    )
    farm.put("hay", 5)
    farm.next_day()
    _check(
        not farm.hungry.has("sheep") and farm.store.has("wool"), "Fed again, the sheep gives wool"
    )

    # The crops grow, and must be harvested in time.
    farm.plant(0, "barley", 10)
    _check(farm.days_to_ripe(0, 10) == 4, "Barley is ripe in 4 days")
    _check(farm.harvest(0, 12)["count"] == 0, "Unripe barley gives nothing")
    _check(farm.days_to_harvest(0, 14) == 3, "Ripe barley waits 3 days")
    var on_time := farm.harvest(0, 15)
    _check(
        on_time["good"] == "grain" and on_time["count"] == 4,
        "On time, the full harvest: %s" % str(on_time)
    )
    farm.plant(0, "barley", 20)
    var late := farm.harvest(0, 29)
    _check(
        late["count"] >= 1 and late["count"] < 4,
        "Late, a smaller harvest, but never nothing: %s" % str(late)
    )
    farm.plant(1, "flowers", 30)
    var ripe_soon := farm.reminders(31)
    _check(
        ripe_soon.any(func(r: Dictionary) -> bool: return r["kind"] == "ripe" and r["days"] == 1),
        "The farm says when the crop is ripe"
    )
    var harvest_now := farm.reminders(33)
    _check(
        harvest_now.any(func(r: Dictionary) -> bool: return r["kind"] == "harvest"),
        "The farm warns to harvest in time"
    )

    # The land.
    var fields := farm.fields.size()
    var pasture := farm.pasture
    farm.add_plot("hill")
    _check(
        farm.fields.size() == fields + 1 and farm.pasture > pasture,
        "A plot of land brings fields and pasture"
    )

    # The room for the animals.
    while farm.has_room_for("cow"):
        farm.add_animal("cow")
    _check(not farm.has_room_for("cow"), "The pasture has room for only so many animals")

    # The save.
    var again := Farm.new()
    again.load_data("res://data/farm/farm.json")
    again.restore(farm.to_data())
    _check(
        again.animals == farm.animals and again.fields.size() == farm.fields.size(),
        "The farm saves and loads"
    )

    if _failures.is_empty():
        print("PASS test_farm")
    quit(1 if not _failures.is_empty() else 0)
