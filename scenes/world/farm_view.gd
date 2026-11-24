class_name FarmView
extends Control

## The players' own farm at home, seen from above, behind the screens of home:
## the fields with their crops as far as they have grown (and the birds on a
## crop harvested late), how many days are left, the animals wandering in
## their pasture behind the fence (with a bubble of the food they miss when
## hungry), the store, and the land still for sale.
##
## It draws the painted pictures (see Pictures, the sheets "farm" and
## "farm_view"), and simple shapes where a picture is missing.

## Where the fields and the pasture lie on the screen: between the text at the
## top and the cards at the bottom of the screens (see ChoicePanel).
const FIELDS := Rect2(70, 385, 860, 380)
const PASTURE := Rect2(1000, 395, 850, 360)

## A field is this many pixels on a side.
const FIELD := 140.0

## How long each animal is on the screen, in pixels.
const ANIMAL_SIZE := {"hen": 50.0, "sheep": 88.0, "goat": 80.0, "cow": 130.0, "bees": 70.0}

## At most this many of each animal walk in the pasture.
const MAX_SHOWN := 6

## The animals walk this fast, in pixels per second.
const WALK := 22.0

## The pictures of a crop as it grows: the first which is there is drawn.
const STAGES := {
    "sown":
    {
        "barley": ["sown", "soil"],
        "flax": ["sown", "soil"],
        "meadow": ["sown", "soil"],
        "flowers": ["sown", "soil"],
    },
    "sprouts":
    {
        "barley": ["sprouts", "barley_young"],
        "flax": ["sprouts", "flax_young"],
        "meadow": ["sprouts", "meadow_young"],
        "flowers": ["sprouts", "flowers_young"],
    },
    "young":
    {
        "barley": ["barley_young"],
        "flax": ["flax_young"],
        "meadow": ["meadow_young", "hay_meadow"],
        "flowers": ["flowers_young", "flower_field"],
    },
    "ripe":
    {
        "barley": ["barley_ripe"],
        "flax": ["flax_bloom"],
        "meadow": ["hay_meadow"],
        "flowers": ["flower_field"],
    },
}

const _INK := Color("2a1d10")
const _PAPER := Color("f1f0ea")
const _SOIL := Color("6a4a2a")
const _GREEN := Color("6a9a3a")

## The farm and the day to show.
var farm: Farm
var day := 0

## The animals in the pasture: Array of {"kind", "at", "to", "wait"}.
var _herd: Array = []
var _shown := {}
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _rng.seed = 7


func _process(delta: float) -> void:
    if not visible or farm == null:
        return
    _time += delta
    _update_herd()
    for animal in _herd:
        if animal["kind"] == "bees":
            continue
        animal["wait"] = float(animal["wait"]) - delta
        if animal["wait"] > 0.0:
            continue
        var at: Vector2 = animal["at"]
        var to: Vector2 = animal["to"]
        var speed := WALK * (2.0 if animal["kind"] == "hen" else 1.0)
        animal["at"] = at.move_toward(to, speed * delta)
        if at.distance_to(to) < 1.0:
            animal["to"] = _somewhere()
            animal["wait"] = _rng.randf_range(1.0, 5.0)
    queue_redraw()


## Keep as many animals in the pasture as the farm has (up to MAX_SHOWN of each).
func _update_herd() -> void:
    var wanted := {}
    for kind in farm.animals.keys():
        wanted[kind] = mini(int(farm.animals[kind]), MAX_SHOWN)
    if wanted == _shown:
        return
    _shown = wanted
    var kept: Array = []
    var counts := {}
    for animal in _herd:
        var kind: String = animal["kind"]
        if int(counts.get(kind, 0)) < int(wanted.get(kind, 0)):
            kept.append(animal)
            counts[kind] = int(counts.get(kind, 0)) + 1
    for kind in wanted.keys():
        for i in range(int(counts.get(kind, 0)), int(wanted[kind])):
            var at := _somewhere()
            if kind == "bees":
                at = PASTURE.position + Vector2(PASTURE.size.x - 50.0 - i * 64.0, 50.0)
            kept.append({"kind": kind, "at": at, "to": _somewhere(), "wait": _rng.randf() * 3.0})
    _herd = kept


func _somewhere() -> Vector2:
    var inner := PASTURE.grow(-50.0)
    inner.position.y += 50.0
    inner.size.y -= 50.0
    return inner.position + Vector2(_rng.randf() * inner.size.x, _rng.randf() * inner.size.y)


func _draw() -> void:
    if farm == null:
        return
    var grass := Pictures.of("ground", "grass_lush")
    var tint := Color.WHITE
    if grass == null:
        grass = Pictures.of("nature", "grass")
        tint = Color(0.82, 0.88, 0.78)
    if grass != null:
        draw_texture_rect(grass, Rect2(Vector2.ZERO, size), true, tint)
    else:
        draw_rect(Rect2(Vector2.ZERO, size), Color("5d6b3a"))
    _draw_fields()
    _draw_pasture()
    _draw_decor()


func _draw_fields() -> void:
    var font := ThemeDB.fallback_font
    var per_row := int((FIELDS.size.x + 20.0) / (FIELD + 30.0))
    var count := farm.fields.size()
    for i in range(count):
        var cell := Vector2(i % per_row, i / per_row)
        var at := FIELDS.position + cell * Vector2(FIELD + 30.0, FIELD + 46.0)
        var rect := Rect2(at, Vector2(FIELD, FIELD))
        var crop: String = farm.fields[i]["crop"]
        var label := "empty"
        if crop == "":
            _draw_field(rect, ["soil"], _SOIL)
        else:
            var to_ripe := farm.days_to_ripe(i, day)
            var days := int(farm.crop_kinds[crop]["days"])
            var grown := 1.0 - float(to_ripe) / maxf(1.0, days)
            if to_ripe > 0:
                var stage := "sown" if grown < 0.2 else ("sprouts" if grown < 0.45 else "young")
                _draw_field(rect, STAGES[stage].get(crop, []), _GREEN)
                label = "%d day%s" % [to_ripe, "" if to_ripe == 1 else "s"]
            else:
                var left := farm.days_to_harvest(i, day)
                if left < 0:
                    _draw_late(rect, crop)
                    label = "birds!"
                else:
                    _draw_field(rect, STAGES["ripe"].get(crop, []), Color("d8b84a"))
                    label = "ripe! %d day%s" % [left + 1, "" if left == 0 else "s"]
        _outlined(font, Vector2(rect.position.x, rect.end.y + 30.0), label, rect.size.x, 22)

    # NOTE (mristin):
    # The land still for sale, as a sign after the last field.
    var for_sale := farm.plot_kinds.size() - farm.plots.size()
    if for_sale > 0:
        var cell := Vector2(count % per_row, count / per_row)
        var at := FIELDS.position + cell * Vector2(FIELD + 30.0, FIELD + 46.0)
        var sign := Pictures.of("farm_view", "plot_sign")
        var center := at + Vector2(FIELD, FIELD) / 2.0
        if sign != null:
            Pictures.draw(self, sign, center, 90.0)
        else:
            draw_rect(Rect2(center - Vector2(36, 26), Vector2(72, 40)), Color("b08a5a"))
            draw_line(center + Vector2(0, 14), center + Vector2(0, 50), Color("6a4320"), 6.0)
        _outlined(font, Vector2(at.x, at.y + FIELD + 30.0), "land for sale", FIELD, 22)


## A field with the first picture of [param names] which is there, or of
## [param color] with furrows.
func _draw_field(rect: Rect2, names: Array, color: Color) -> void:
    for name in names:
        var picture := Pictures.of("farm_view", name)
        if picture == null:
            picture = Pictures.of("farm", name)
        if picture != null:
            draw_texture_rect(picture, rect, false)
            return
    draw_rect(rect, color)
    for k in range(1, 6):
        var y := rect.position.y + rect.size.y * k / 6.0
        draw_line(
            Vector2(rect.position.x + 6, y), Vector2(rect.end.x - 6, y), color.darkened(0.25), 3.0
        )
    draw_rect(rect, color.darkened(0.4), false, 3.0)


## A ripe crop harvested late: the birds peck at it.
func _draw_late(rect: Rect2, crop: String) -> void:
    if crop == "barley" and Pictures.of("farm", "birds") != null:
        _draw_field(rect, ["birds"], Color("d8b84a"))
        return
    _draw_field(rect, STAGES["ripe"].get(crop, []), Color("d8b84a"))
    var birds := Pictures.of("farm_view", "birds_pecking")
    var hop := absf(sin(_time * 6.0)) * 4.0
    if birds != null:
        Pictures.draw(self, birds, rect.get_center() + Vector2(0, -hop), rect.size.x * 0.8)
        return
    for k in range(3):
        var at := rect.position + Vector2(30 + k * 40, 50 + (k % 2) * 40 - hop)
        draw_circle(at, 9.0, Color("3a3a40"))
        draw_circle(at + Vector2(7, -5), 5.0, Color("3a3a40"))


func _draw_pasture() -> void:
    _draw_fence(PASTURE)
    var trough := "trough_full"
    for kind in farm.hungry.keys():
        if farm.animal_kinds[kind]["eats"] == "hay":
            trough = "trough_empty"
    var trough_picture := Pictures.of("farm_view", trough)
    if trough_picture != null:
        Pictures.draw(self, trough_picture, PASTURE.position + Vector2(90, 60), 100.0)
    var water := Pictures.of("farm_view", "water_trough")
    if water != null:
        Pictures.draw(self, water, PASTURE.position + Vector2(80, 150), 80.0)
    if farm.animals.has("hen"):
        var house := Pictures.of("farm_view", "hen_house")
        if house != null:
            Pictures.draw(self, house, PASTURE.position + Vector2(220, 62), 90.0)

    var bubbles := {}
    for animal in _herd:
        var kind: String = animal["kind"]
        var picture := Pictures.of("farm", "beehive" if kind == "bees" else kind)
        var at: Vector2 = animal["at"]
        var to: Vector2 = animal["to"]
        var length: float = ANIMAL_SIZE.get(kind, 60.0)
        # NOTE (mristin):
        # The painted animals look down; they turn to where they walk.
        var angle := 0.0
        if kind != "bees" and to.distance_to(at) > 1.0:
            angle = (to - at).angle() - PI / 2.0
        if picture != null:
            Pictures.draw(self, picture, at, length, angle)
        else:
            draw_circle(at, length * 0.35, Color("e8e0d0"))
        if farm.hungry.has(kind) and int(bubbles.get(kind, 0)) < 2:
            bubbles[kind] = int(bubbles.get(kind, 0)) + 1
            _draw_bubble(at + Vector2(length * 0.4, -length * 0.6), farm.animal_kinds[kind]["eats"])


## Grandmother Åsa walking along the fields, the cat asleep, the store, and
## the scarecrow when the birds come (each only when painted).
func _draw_decor() -> void:
    var store := Pictures.of("farm_view", "store")
    if store != null:
        Pictures.draw(self, store, Vector2(965, 470), 70.0)
    var cat := Pictures.of("farm_view", "cat")
    if cat != null:
        Pictures.draw(self, cat, Vector2(965, 735), 46.0)
    var grandmother := Pictures.of("farm_view", "grandmother")
    if grandmother != null:
        var walk := 0.5 + 0.5 * sin(_time * 0.15)
        var at := Vector2(lerpf(FIELDS.position.x + 40.0, FIELDS.end.x - 60.0, walk), 732.0)
        Pictures.draw(self, grandmother, at, 64.0, sin(_time * 4.0) * 0.06)
    var scarecrow := Pictures.of("farm_view", "scarecrow")
    if scarecrow != null:
        for i in range(farm.fields.size()):
            if farm.fields[i]["crop"] != "" and farm.days_to_harvest(i, day) < 0:
                Pictures.draw(
                    self, scarecrow, Vector2(FIELDS.end.x - 70.0, FIELDS.position.y + 260.0), 90.0
                )
                break


## A thought bubble with the food the animal misses.
func _draw_bubble(at: Vector2, food: String) -> void:
    var bob := sin(_time * 3.0) * 3.0
    at.y += bob
    var bubble := Pictures.of("ui", "thought_bubble")
    if bubble != null:
        Pictures.draw(self, bubble, at + Vector2(-4, 8), 76.0)
    else:
        draw_circle(at + Vector2(-16, 22), 5.0, Color(1, 1, 1, 0.95))
        draw_circle(at, 26.0, Color(1, 1, 1, 0.95))
    var picture := Pictures.of("goods", food)
    if picture != null:
        Pictures.draw(self, picture, at, 38.0)
    else:
        draw_string(
            ThemeDB.fallback_font,
            at + Vector2(-26, 8),
            "?",
            HORIZONTAL_ALIGNMENT_CENTER,
            52,
            28,
            _INK
        )


## The fence around the pasture, of the painted pieces, with a gate at the bottom.
func _draw_fence(rect: Rect2) -> void:
    var piece := Pictures.of("farm", "fence")
    var gate := Pictures.of("farm", "gate")
    if piece == null:
        draw_rect(rect, Color("b08a5a"), false, 6.0)
        return
    var length := 90.0
    var sides := [
        [rect.position, Vector2(rect.end.x, rect.position.y)],
        [Vector2(rect.end.x, rect.position.y), rect.end],
        [rect.end, Vector2(rect.position.x, rect.end.y)],
        [Vector2(rect.position.x, rect.end.y), rect.position],
    ]
    for s in range(4):
        var from: Vector2 = sides[s][0]
        var to: Vector2 = sides[s][1]
        var count := maxi(1, roundi(from.distance_to(to) / length))
        for k in range(count):
            var middle := from.lerp(to, (k + 0.5) / count)
            var picture := piece
            if s == 2 and k == count / 2 and gate != null:
                picture = gate
            Pictures.draw(
                self, picture, middle, from.distance_to(to) / count * 1.08, (to - from).angle()
            )


func _outlined(font: Font, at: Vector2, text: String, width: float, font_size: int) -> void:
    draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 8, _INK)
    draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, _PAPER)
