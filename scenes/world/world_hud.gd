class_name WorldHud
extends Control

## What the open world shows over the lakes: the day, the silver and the
## cargo, the tasks under way, what the farm reminds of, the last news, the
## map of the region with the settlements and the boats (and gold rings where
## the tasks lead), and, for two players, the pull of each oar.

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _RED := Color("b8332a")
const _INK := Color(0.05, 0.07, 0.1, 0.75)
const _WATER := Color("3d6f9c")
const _LAND := Color("5d6b3a")
const _MINIMAP := Rect2(1700, 100, 200, 660)

## Up to this many crates, the HUD shows every crate of the hold; a bigger
## hold shows one crate for each kind of cargo, with how many.
const CRATES_SHOWN := 12

## The world (see world.gd).
var world: Node

var _minimap_polygons: Array = []
var _minimap_scale := 1.0

## The silver shown, and how much its number still jumps (see CoinPurse).
var _silver := -1
var _pop := 0.0


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
    _pop = maxf(0.0, _pop - delta * 2.0)


func _draw() -> void:
    if world == null or world.map() == null or world.map().places.is_empty():
        return
    _draw_purse()
    _draw_tasks()
    _draw_reminder()
    _draw_minimap()
    _draw_rowing()


func _outlined(at: Vector2, text: String, font_size: int, color := _PAPER) -> void:
    var font := ThemeDB.fallback_font
    draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, _INK)
    draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The day, the silver and the crates in the boat.
func _draw_purse() -> void:
    var state: Node = world.state()
    _outlined(Vector2(30, 50), "Day %d" % state.day, 34, _GOLD)
    if int(state.silver) != _silver:
        _pop = 1.0 if _silver >= 0 else 0.0
        _silver = int(state.silver)
    CoinPurse.draw(self, Vector2(30, 70), _silver, _pop)
    if int(state.capacity) > CRATES_SHOWN:
        _draw_hold_grouped(state)
        return
    var x := 30.0
    var items: Array = []
    for item in state.cargo.keys():
        for i in range(int(state.cargo[item])):
            items.append(item)
    for slot in range(state.capacity):
        var rect := Rect2(Vector2(x, 172), Vector2(52, 44))
        draw_rect(rect.grow(3.0), _INK)
        if slot < items.size():
            _draw_crate(state, rect, items[slot])
            _outlined(rect.position + Vector2(2, 62), state.good_name(items[slot]), 14)
        else:
            draw_rect(rect, Color(1, 1, 1, 0.08))
        x += 60.0


## A big hold: one crate for each kind of cargo, with how many, and how full
## the hold is.
func _draw_hold_grouped(state: Node) -> void:
    var x := 30.0
    for item in state.cargo.keys():
        var rect := Rect2(Vector2(x, 172), Vector2(52, 44))
        draw_rect(rect.grow(3.0), _INK)
        _draw_crate(state, rect, item)
        _outlined(rect.position + Vector2(2, 62), state.good_name(item), 14)
        _outlined(rect.end + Vector2(-22, -4), "%d" % int(state.cargo[item]), 22, _GOLD)
        x += 60.0
    var bar := Rect2(Vector2(x + 6, 182), Vector2(160, 24))
    draw_rect(bar.grow(3.0), _INK)
    draw_rect(bar, Color(1, 1, 1, 0.08))
    var used := float(state.load_count()) / float(state.capacity)
    draw_rect(Rect2(bar.position, Vector2(bar.size.x * used, bar.size.y)), Color("c8a878"))
    _outlined(
        bar.position + Vector2(8, 20), "%d of %d crates" % [state.load_count(), state.capacity], 18
    )


## A crate of the cargo in the [param rect]: painted, or drawn simply.
func _draw_crate(state: Node, rect: Rect2, item: String) -> void:
    var picture := _cargo_picture(item)
    if picture != null:
        draw_rect(rect, Color("e8d8b0"))
        Pictures.draw(self, picture, rect.get_center(), 42.0)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    elif Missions.is_item(item):
        draw_rect(rect, state.missions.item_color(item))
        draw_rect(rect, _GOLD, false, 3.0)
    elif item.begins_with("animal:"):
        draw_rect(rect, Color("7a8a4a"))
        draw_circle(rect.get_center(), 14.0, Color("f1f0ea"))
        draw_circle(rect.get_center() + Vector2(10, -6), 6.0, Color("e8e0d0"))
    else:
        draw_rect(rect, state.economy.goods[item]["color"])
        draw_line(rect.position, rect.end, Color(0, 0, 0, 0.25), 2.0)
        draw_line(
            Vector2(rect.end.x, rect.position.y),
            Vector2(rect.position.x, rect.end.y),
            Color(0, 0, 0, 0.25),
            2.0
        )


## The painted picture of a crate in the boat: the good, or the animal.
func _cargo_picture(item: String) -> Texture2D:
    if Missions.is_item(item):
        var picture: Array = world.state().missions.item_picture(item)
        return Pictures.of(picture[0], picture[1]) if picture.size() == 2 else null
    if item.begins_with("animal:"):
        var kind := item.trim_prefix("animal:")
        return Pictures.of("farm", "beehive" if kind == "bees" else kind)
    return Pictures.of("goods", item)


## The tasks under way, and what to do next for each.
func _draw_tasks() -> void:
    var state: Node = world.state()
    var y := 270.0
    for entry in state.missions.active:
        var id: String = entry["id"]
        _outlined(Vector2(30, y), state.missions.missions[id]["title"], 26, _GOLD)
        _outlined(Vector2(30, y + 30), state.missions.hint(state, id), 20)
        y += 72.0


## What the farm reminds of, and what happened last.
func _draw_reminder() -> void:
    var state: Node = world.state()
    var font := ThemeDB.fallback_font
    var lines: Array[String] = []
    var toast: String = world.toast()
    if toast != "":
        lines.append(toast)
    var reminders: Array = state.farm.reminders(state.day)
    if not reminders.is_empty():
        lines.append("Farm: " + reminders[0]["text"])
    var y := 50.0
    for line in lines:
        var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
        _outlined(
            Vector2(960 - width / 2.0, y), line, 28, _GOLD if line.begins_with("Farm") else _PAPER
        )
        y += 40.0


func _fit_minimap() -> void:
    var map: LakeMap = world.map()
    _minimap_scale = minf(_MINIMAP.size.x / map.size_m.x, _MINIMAP.size.y / map.size_m.y)
    for polygon in map.water:
        var outer := PackedVector2Array()
        for p in polygon["outer"]:
            outer.append(_MINIMAP.position + p * _minimap_scale)
        var holes: Array[PackedVector2Array] = []
        for hole in polygon["holes"]:
            var ring := PackedVector2Array()
            for p in hole:
                ring.append(_MINIMAP.position + p * _minimap_scale)
            # NOTE (mristin):
            # At the small scale of the map, a ring may fold onto itself and can
            # not be filled; we leave it out (it is a tiny island anyhow).
            if not Geometry2D.triangulate_polygon(ring).is_empty():
                holes.append(ring)
        _minimap_polygons.append({"outer": outer, "holes": holes})


func _draw_minimap() -> void:
    if _minimap_polygons.is_empty():
        _fit_minimap()
    var map: LakeMap = world.map()
    var box := Rect2(_MINIMAP.position, map.size_m * _minimap_scale)
    draw_rect(box.grow(6.0), _INK)
    draw_rect(box, _LAND)
    for polygon in _minimap_polygons:
        draw_colored_polygon(polygon["outer"], _WATER)
        for hole in polygon["holes"]:
            draw_colored_polygon(hole, _LAND)
    for place in map.places:
        var at: Vector2 = _MINIMAP.position + place["jetty"] * _minimap_scale
        var home: bool = place["kind"] == "home"
        if home:
            draw_circle(at, 13.0, _GOLD)
        var things: Array = LakeMap.PAINTED_VILLAGES.get(place["kind"], [])
        var building: Texture2D = null
        if not things.is_empty():
            building = Pictures.of(things[0][0], things[0][1])
        if building != null:
            Pictures.draw(self, building, at, 20.0)
        else:
            draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), _GOLD if home else _RED)
    var state: Node = world.state()
    for entry in state.missions.active:
        var target: String = state.missions.target(state, entry["id"])
        if target != "":
            var place := map.place(target)
            var ring: Vector2 = _MINIMAP.position + place["jetty"] * _minimap_scale
            draw_arc(ring, 17.0, 0.0, TAU, 24, _INK, 6.0)
            draw_arc(ring, 17.0, 0.0, TAU, 24, _GOLD, 3.0)
    for npc in world.npcs():
        var at: Vector2 = _MINIMAP.position + npc.position * _minimap_scale
        var skipper := Pictures.of("skippers", npc.skipper.get("picture", ""))
        if skipper != null:
            Pictures.draw(self, skipper, at, 16.0, npc.heading)
        else:
            draw_circle(at, 3.0, _PAPER)
    var boat: RowBoat = world.boat()
    var at := _MINIMAP.position + boat.position * _minimap_scale
    var hull := Pictures.of("rowboat", "hull")
    if hull != null:
        # NOTE (mristin):
        # A ring of gold around the players' boat, so that they find it.
        draw_arc(at, 12.0, 0.0, TAU, 24, _GOLD, 2.5)
        Pictures.draw(self, hull, at, 20.0, boat.heading)
        return
    var forward := Vector2.UP.rotated(boat.heading)
    draw_colored_polygon(
        PackedVector2Array(
            [
                at + forward * 9.0,
                at - forward * 5.0 + forward.orthogonal() * 5.0,
                at - forward * 5.0 - forward.orthogonal() * 5.0
            ]
        ),
        _GOLD
    )


## How the players row as a pair: the pull of each oar.
func _draw_rowing() -> void:
    var center := Vector2(960, 1040)
    var boat: RowBoat = world.boat()
    if world.players() == 2:
        for side in [0, 1]:
            var pull := exp(-float(boat.since_side[side]) / 1.5)
            var sign := -1.0 if side == 0 else 1.0
            var bar := Rect2(center + Vector2(sign * 40.0 - 12.0, -90.0), Vector2(24.0, 90.0))
            draw_rect(bar.grow(4.0), _INK)
            var height := bar.size.y * pull
            var color := _GOLD if boat.since_in_time < 0.7 else _PAPER
            draw_rect(
                Rect2(bar.position + Vector2(0, bar.size.y - height), Vector2(bar.size.x, height)),
                color
            )
