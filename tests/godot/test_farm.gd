extends SceneTree

## Check the farm (see Farm): the animals eat and give, never die, have young
## steadily (only fed and with room), the milk becomes cheese, the crops grow
## and must be harvested in time. Run with
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

    _check_young()
    _check_milk()

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
    farm.young_progress = {"cow": 2}
    again.restore(farm.to_data())
    _check(again.young_progress == {"cow": 2}, "The farm saves the days towards the young")

    if _failures.is_empty():
        print("PASS test_farm")
    quit(1 if not _failures.is_empty() else 0)


## A farm with only the [param animals] (id -> count), the [param store] and
## the [param pasture].
func _farm(animals: Dictionary, store: Dictionary, pasture: float) -> Farm:
    var farm := Farm.new()
    farm.load_data("res://data/farm/farm.json")
    farm.animals = animals.duplicate()
    farm.store = store.duplicate()
    farm.pasture = pasture
    return farm


func _check_young() -> void:
    # A pair has one young every so many fed days, however big the herd.
    var days := 12
    var pair := _farm({"hen": 2}, {"grain": 1000.0}, 100.0)
    var flock := _farm({"hen": 20}, {"grain": 1000.0}, 100.0)
    var every := int(pair.animal_kinds["hen"]["young_days"])
    for i in range(days):
        pair.next_day()
        flock.next_day()
    _check(
        pair.animals["hen"] == 2 + days / every,
        "A pair of hens has a chick every %d days: %d hens" % [every, pair.animals["hen"]]
    )
    _check(
        flock.animals["hen"] - 20 == pair.animals["hen"] - 2,
        (
            "A big flock has no more chicks than a pair: %d and %d"
            % [flock.animals["hen"] - 20, pair.animals["hen"] - 2]
        )
    )

    # One alone has no young, nor have the bees.
    var alone := _farm({"sheep": 1, "bees": 3}, {"hay": 1000.0}, 100.0)
    for i in range(20):
        alone.next_day()
    _check(
        alone.animals == {"sheep": 1, "bees": 3},
        "One sheep alone has no lambs, the bees no young: %s" % str(alone.animals)
    )

    # The days count towards the young when the herd is fed and has room.
    var goats := _farm({"goat": 2}, {"hay": 1000.0}, 100.0)
    every = int(goats.animal_kinds["goat"]["young_days"])
    for i in range(every - 1):
        goats.next_day()
    _check(goats.animals["goat"] == 2 and goats.born.is_empty(), "No kid before its day")
    _check(goats.days_to_young("goat") == 1, "The kid comes in a day")
    goats.next_day()
    _check(goats.animals["goat"] == 3 and goats.born == {"goat": 1}, "The kid is born on its day")

    # Without feed, no young.
    var hungry := _farm({"sheep": 2}, {}, 100.0)
    for i in range(20):
        hungry.next_day()
    _check(hungry.animals["sheep"] == 2, "Hungry sheep have no lambs")
    var reminders := hungry.reminders(1)
    _check(
        (
            not reminders.is_empty()
            and reminders[0]["kind"] == "hungry"
            and "lambs" in reminders[0]["text"]
            and "hay" in reminders[0]["text"]
        ),
        "The farm says why there are no lambs: %s" % str(reminders)
    )
    # NOTE: Only the days with feed count.
    hungry.put("hay", 1000)
    every = int(hungry.animal_kinds["sheep"]["young_days"])
    for i in range(every):
        hungry.next_day()
    _check(hungry.animals["sheep"] == 3, "Fed again, the sheep have a lamb in %d days" % every)

    # Not enough feed for the whole herd: none eats its fill, no young.
    var short := _farm({"cow": 2}, {"hay": 1.5}, 100.0)
    short.next_day()
    _check(
        short.hungry.has("cow") and short.young_progress.get("cow", 0) == 0,
        "Too little hay for the herd: no day towards a calf"
    )

    # Without room, no young; with land, they come again.
    var crowded := _farm({"goat": 2}, {"hay": 1000.0}, 2.0)
    for i in range(20):
        crowded.next_day()
    _check(crowded.animals["goat"] == 2, "Without room, the goats have no kids")
    reminders = crowded.reminders(1)
    _check(
        reminders.any(
            func(r: Dictionary) -> bool: return r["kind"] == "crowded" and "kids" in r["text"]
        ),
        "The farm says there is no room for the kids: %s" % str(reminders)
    )
    crowded.pasture = 3.0
    _check(
        not crowded.reminders(1).any(func(r: Dictionary) -> bool: return r["kind"] == "crowded"),
        "With land, the farm is not crowded"
    )
    for i in range(every):
        crowded.next_day()
    _check(crowded.animals["goat"] == 3, "With room, the goats have a kid")
    for i in range(20):
        crowded.next_day()
    _check(crowded.animals["goat"] == 3, "The young never crowd the farm beyond its room")


func _check_milk() -> void:
    # The animals eat their feed, and the cows give milk.
    var farm := _farm({"cow": 2}, {"hay": 10.0}, 4.0)
    var eats := float(farm.animal_kinds["cow"]["eats_per_day"]) * 2
    var milk := float(farm.animal_kinds["cow"]["gives"]["milk"]) * 2
    farm.next_day()
    _check(
        is_equal_approx(float(farm.store["hay"]), 10.0 - eats),
        "Two cows eat %.1f hay a day: %s" % [eats, str(farm.store)]
    )
    # The cellar keeps only so much milk: the rest becomes cheese.
    var kept := minf(milk, farm.milk_kept)
    _check(
        is_equal_approx(float(farm.store.get("milk", 0.0)), kept),
        "The cellar keeps the milk: %s" % str(farm.store)
    )
    _check(
        is_equal_approx(float(farm.store.get("cheese", 0.0)), (milk - kept) / farm.milk_per_cheese),
        "The milk beyond the cellar becomes cheese: %s" % str(farm.store)
    )
    var cheese := float(farm.store.get("cheese", 0.0))
    farm.next_day()
    _check(
        is_equal_approx(float(farm.store["milk"]), farm.milk_kept),
        "The cellar stays full: %s" % str(farm.store)
    )
    _check(
        is_equal_approx(float(farm.store["cheese"]), cheese + milk / farm.milk_per_cheese),
        "With a full cellar, all the new milk becomes cheese: %s" % str(farm.store)
    )
    # The milk taken out leaves room in the cellar again.
    farm.take("milk", 2)
    cheese = float(farm.store["cheese"])
    farm.put("hay", 10)
    farm.next_day()
    _check(
        is_equal_approx(float(farm.store["milk"]), minf(milk, farm.milk_kept)),
        "Fresh milk fills the emptied cellar first: %s" % str(farm.store)
    )
    # Hungry cows give no milk and make no cheese.
    farm.store = {"milk": 1.0}
    farm.next_day()
    _check(
        farm.store == {"milk": 1.0},
        "Hungry cows give no milk, and the milk in the cellar keeps: %s" % str(farm.store)
    )
