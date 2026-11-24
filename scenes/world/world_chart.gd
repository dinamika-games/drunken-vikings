class_name WorldChart
extends Control

## The map of the whole region over the whole screen, shown with the key C (as
## the chart of Bird Dog): the lakes, every settlement with its name, the
## places where the tasks lead (gold rings, with the tasks beside them), the
## boats on the lakes and the players' boat, so that the players get their
## bearings. The game waits meanwhile; C or Escape closes it.

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _INK := Color(0.05, 0.07, 0.1, 0.85)
const _WATER := Color("3d6f9c")
const _LAND := Color("6b7a45")

## Where the map goes; the title stands on its left, the legend on its right.
const _AREA := Rect2(560, 20, 800, 1040)
const _SIDE := 500.0

## The world (see world.gd).
var world: Node

var _polygons: Array = []

## Where the names of the places went on this drawing, so that they do not
## cover each other.
var _taken: Array[Rect2] = []
var _scale := 1.0
var _origin := Vector2.ZERO


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
    queue_redraw()


func _fit() -> void:
    var map: LakeMap = world.map()
    _scale = minf(_AREA.size.x / map.size_m.x, _AREA.size.y / map.size_m.y)
    _origin = _AREA.position + (_AREA.size - map.size_m * _scale) / 2.0
    for polygon in map.water:
        var outer := PackedVector2Array()
        for p in polygon["outer"]:
            outer.append(_at(p))
        var holes: Array[PackedVector2Array] = []
        for hole in polygon["holes"]:
            var ring := PackedVector2Array()
            for p in hole:
                ring.append(_at(p))
            if not Geometry2D.triangulate_polygon(ring).is_empty():
                holes.append(ring)
        _polygons.append({"outer": outer, "holes": holes})


func _at(point: Vector2) -> Vector2:
    return _origin + point * _scale


func _outlined(at: Vector2, text: String, font_size: int, color := _PAPER, width := -1.0) -> void:
    var font := ThemeDB.fallback_font
    var align := HORIZONTAL_ALIGNMENT_LEFT if width < 0.0 else HORIZONTAL_ALIGNMENT_CENTER
    draw_string_outline(font, at, text, align, width, font_size, 8, _INK)
    draw_string(font, at, text, align, width, font_size, color)


## Write the [param name] of a place beside its jetty at [param at], on the
## side of the land ([param inland]), so that the names of the places across
## the water from each other do not cover each other.
func _label(at: Vector2, inland: Vector2, name: String) -> void:
    var font := ThemeDB.fallback_font
    var width := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
    var side := inland.normalized()
    var start := at + Vector2(-width / 2.0, 36.0)
    if side.x < -0.4:
        start = at + Vector2(-width - 20.0, 8.0)
    elif side.x > 0.4:
        start = at + Vector2(20.0, 8.0)
    elif side.y < 0.0:
        start = at + Vector2(-width / 2.0, -22.0)
    var box := Rect2(start + Vector2(0, -20), Vector2(width, 26))
    var tries := 0
    while tries < 6 and _taken.any(func(other: Rect2) -> bool: return other.intersects(box)):
        box.position.y += 24.0
        tries += 1
    _taken.append(box)
    _outlined(box.position + Vector2(0, 20), name, 22)


func _draw() -> void:
    if world == null or world.map() == null:
        return
    if _polygons.is_empty():
        _fit()
    var map: LakeMap = world.map()
    var state: Node = world.state()
    _taken.clear()
    draw_rect(Rect2(Vector2.ZERO, size), Color("10161c"))
    draw_rect(Rect2(_origin, map.size_m * _scale).grow(8.0), Color("4a3a22"))
    draw_rect(Rect2(_origin, map.size_m * _scale), _LAND)
    for polygon in _polygons:
        draw_colored_polygon(polygon["outer"], _WATER)
        for hole in polygon["holes"]:
            draw_colored_polygon(hole, _LAND)

    # Where the tasks lead: Array of [place, title].
    var leads: Array = []
    for entry in state.missions.active:
        var target: String = state.missions.target(state, entry["id"])
        if target != "":
            leads.append([target, state.missions.missions[entry["id"]]["title"]])
            var ring := _at(map.place(target)["jetty"])
            var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 200.0)
            draw_arc(ring, 22.0 * pulse, 0.0, TAU, 32, _INK, 8.0)
            draw_arc(ring, 22.0 * pulse, 0.0, TAU, 32, _GOLD, 4.0)

    for place in map.places:
        var at := _at(place["jetty"])
        var things: Array = LakeMap.PAINTED_VILLAGES.get(place["kind"], [])
        var building: Texture2D = null
        if not things.is_empty():
            building = Pictures.of(things[0][0], things[0][1])
        if building != null:
            Pictures.draw(self, building, at, 30.0)
        else:
            draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), _GOLD)
        var name: String = place["name"]
        if place["kind"] == "home":
            name += " (home)"
        _label(at, place["at"] - place["jetty"], name)

    for npc in world.npcs():
        var skipper := Pictures.of("skippers", npc.skipper.get("picture", ""))
        if skipper != null:
            Pictures.draw(self, skipper, _at(npc.position), 22.0, npc.heading)
    var boat: RowBoat = world.boat()
    var hull := Pictures.of("rowboat", "hull")
    var at := _at(boat.position)
    draw_arc(at, 16.0, 0.0, TAU, 24, _GOLD, 3.0)
    if hull != null:
        Pictures.draw(self, hull, at, 28.0, boat.heading)
    else:
        draw_circle(at, 6.0, _GOLD)

    var font := ThemeDB.fallback_font
    draw_multiline_string(
        font,
        Vector2(30, 120),
        "The Home Lakes",
        HORIZONTAL_ALIGNMENT_CENTER,
        _SIDE - 60,
        56,
        -1,
        _GOLD
    )
    draw_multiline_string(
        font,
        Vector2(30, 260),
        "Day %d. You are in the gold ring with the boat." % state.day,
        HORIZONTAL_ALIGNMENT_LEFT,
        _SIDE - 60,
        30,
        -1,
        _PAPER
    )
    var x := size.x - _SIDE + 40.0
    var y := 120.0
    _outlined(Vector2(x, y), "Your tasks", 40, _GOLD)
    y += 60.0
    if leads.is_empty():
        draw_multiline_string(
            font,
            Vector2(x, y),
            "No task leads anywhere now. Ask for tasks in the ports!",
            HORIZONTAL_ALIGNMENT_LEFT,
            _SIDE - 60,
            28,
            -1,
            _PAPER
        )
    for lead in leads:
        draw_arc(Vector2(x + 14, y - 10), 13.0, 0.0, TAU, 24, _GOLD, 4.0)
        draw_multiline_string(
            font,
            Vector2(x + 44, y),
            "%s: to %s" % [lead[1], state.place_name(lead[0])],
            HORIZONTAL_ALIGNMENT_LEFT,
            _SIDE - 100,
            28,
            -1,
            _PAPER
        )
        y += 110.0
    _outlined(Vector2(x, size.y - 60), "C closes the map", 30)
