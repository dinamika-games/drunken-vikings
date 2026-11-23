class_name LakeMap
extends Node2D

## The lakes of a level (made by dev/maps/make_lakes.py): it draws the land,
## the water, the islands, the forests on the shores and the villages, and
## tells the water from the land for the boats.
##
## The map is in metres, x east and y south; one unit of the canvas is a metre.

const WATER_SHADER := preload("res://scenes/level/water.gdshader")

const LAND := Color("5d6b3a")
const FOREST := Color("3f4d2a")
const FOREST_DARK := Color("2f3b20")
const SHORE := Color("c9b98a")
const WATER := Color("3d6f9c")
const WATER_DEEP := Color("34628c")
const ROOF := Color("8a3b2a")
const WALL := Color("b08a5a")

## The width of the sandy shore, in metres.
const SHORE_WIDTH := 3.0

## The size of the map in metres.
var size_m := Vector2.ZERO

## The polygons of the water: Array of {"outer": PackedVector2Array,
## "holes": Array[PackedVector2Array]}.
var water: Array = []

## The course of the viking ship.
var route := PackedVector2Array()

## The names: Array of {"kind", "name", "at": Vector2}.
var labels: Array = []

## The start and the goal: {"name", "at": Vector2}.
var start := {}
var goal := {}

## The settlements: Array of {"id", "kind", "name", "at": Vector2, "jetty": Vector2}.
var places: Array = []

## The ways of the boats between the places: "<id>|<id>" -> PackedVector2Array.
var routes := {}

## The grid of the water for the boats which find their own way (the pirates
## of the chase), or null if the map has none.
var _grid: AStarGrid2D

## The length of the route up to each of its points, in metres.
var _route_lengths := PackedFloat32Array()

var _trees: Array = []
var _water_nodes: Array[Polygon2D] = []
var _above: Node2D


## Load the map from the JSON of dev/maps/make_lakes.py; return what went wrong, or "".
func load_map(path: String) -> String:
    var text := FileAccess.get_file_as_string(path)
    if text == "":
        return "Could not read the map %s." % path
    var data: Variant = JSON.parse_string(text)
    if not data is Dictionary:
        return "The map %s is no JSON object." % path
    size_m = Vector2(data["size_m"][0], data["size_m"][1])
    water.clear()
    for polygon in data["water"]:
        var holes: Array[PackedVector2Array] = []
        for hole in polygon["holes"]:
            holes.append(_points(hole))
        water.append({"outer": _points(polygon["outer"]), "holes": holes})
    route = _points(data["route"])
    _route_lengths.resize(route.size())
    var total := 0.0
    for i in range(route.size()):
        if i > 0:
            total += route[i - 1].distance_to(route[i])
        _route_lengths[i] = total
    labels.clear()
    for label in data["labels"]:
        labels.append(
            {
                "kind": label["kind"],
                "name": label["name"],
                "at": Vector2(label["at"][0], label["at"][1])
            }
        )
    places.clear()
    for place in data.get("places", []):
        places.append(
            {
                "id": place["id"],
                "kind": place["kind"],
                "name": place["name"],
                "at": _vector(place["at"]),
                "jetty": _vector(place["jetty"])
            }
        )
    routes.clear()
    for key in data.get("routes", {}).keys():
        routes[key] = _points(data["routes"][key])
    _grid = _make_grid(data.get("nav", {}))
    start = {"name": data["start"]["name"], "at": _vector(data["start"]["at"])}
    goal = {"name": data["goal"]["name"], "at": _vector(data["goal"]["at"])}
    _plant_trees()
    _build_layers()
    queue_redraw()
    return ""


static func _vector(pair: Array) -> Vector2:
    return Vector2(pair[0], pair[1])


static func _points(pairs: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for pair in pairs:
        points.append(Vector2(pair[0], pair[1]))
    # NOTE (mristin):
    # The rings of the JSON repeat their first point at the end.
    if points.size() > 1 and points[0] == points[-1]:
        points.remove_at(points.size() - 1)
    return points


## Whether the point is on the water.
func is_water(point: Vector2) -> bool:
    for polygon in water:
        if not Geometry2D.is_point_in_polygon(point, polygon["outer"]):
            continue
        for hole in polygon["holes"]:
            if Geometry2D.is_point_in_polygon(point, hole):
                return false
        return true
    return false


## Whether the way from [param from] to [param to] crosses any land.
func crosses_land(from: Vector2, to: Vector2) -> bool:
    var steps := maxi(1, ceili(from.distance_to(to) / 2.0))
    for i in range(1, steps + 1):
        if not is_water(from.lerp(to, float(i) / steps)):
            return true
    return false


## The grid of the water from the "nav" of the map (see dev/maps/make_lakes.py).
static func _make_grid(nav: Dictionary) -> AStarGrid2D:
    if nav.is_empty():
        return null
    var grid := AStarGrid2D.new()
    var cell := float(nav["cell"])
    grid.region = Rect2i(0, 0, int(nav["cols"]), int(nav["rows"]))
    grid.cell_size = Vector2(cell, cell)
    grid.offset = Vector2(cell, cell) * 0.5
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.update()
    var rows: Array = nav["runs"]
    for y in range(rows.size()):
        var x := 0
        var land := true
        for length in rows[y]:
            if land:
                grid.fill_solid_region(Rect2i(x, y, int(length), 1), true)
            x += int(length)
            land = not land
    return grid


## The way on the water from [param from] to [param to], away from the shores
## (empty if there is none, or the map has no grid).
func water_path(from: Vector2, to: Vector2) -> PackedVector2Array:
    if _grid == null:
        return PackedVector2Array()
    var a := _free_cell(from)
    var b := _free_cell(to)
    if a == Vector2i(-1, -1) or b == Vector2i(-1, -1):
        return PackedVector2Array()
    return _grid.get_point_path(a, b)


## The free cell of the grid nearest to the point, or (-1, -1).
func _free_cell(point: Vector2) -> Vector2i:
    var cell := Vector2i((point / _grid.cell_size).floor())
    for radius in range(0, 8):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                var candidate := cell + Vector2i(dx, dy)
                if _grid.is_in_boundsv(candidate) and not _grid.is_point_solid(candidate):
                    return candidate
    return Vector2i(-1, -1)


## The place of the id, or an empty Dictionary.
func place(id: String) -> Dictionary:
    for item in places:
        if item["id"] == id:
            return item
    return {}


## The way of the boats on the water from the jetty of one place to the jetty
## of another.
func route_between(from_id: String, to_id: String) -> PackedVector2Array:
    if routes.has("%s|%s" % [from_id, to_id]):
        return routes["%s|%s" % [from_id, to_id]]
    if routes.has("%s|%s" % [to_id, from_id]):
        var reversed: PackedVector2Array = routes["%s|%s" % [to_id, from_id]].duplicate()
        reversed.reverse()
        return reversed
    return PackedVector2Array()


## How long the route is, in metres.
func route_length() -> float:
    return _route_lengths[-1] if _route_lengths.size() > 0 else 0.0


## The point of the route at [param s] metres from its start.
func route_point(s: float) -> Vector2:
    if route.is_empty():
        return Vector2.ZERO
    s = clampf(s, 0.0, route_length())
    var i := _route_lengths.bsearch(s)
    if i <= 0:
        return route[0]
    if i >= route.size():
        return route[-1]
    var a := _route_lengths[i - 1]
    var b := _route_lengths[i]
    var t := (s - a) / maxf(b - a, 1e-6)
    return route[i - 1].lerp(route[i], t)


## How far along the route the point lies, in metres: the nearest point of the route.
func route_progress(point: Vector2) -> float:
    var best := INF
    var progress := 0.0
    for i in range(1, route.size()):
        var closest := Geometry2D.get_closest_point_to_segment(point, route[i - 1], route[i])
        var distance := point.distance_squared_to(closest)
        if distance < best:
            best = distance
            progress = _route_lengths[i - 1] + route[i - 1].distance_to(closest)
    return progress


## Plant the forests: trees on the land near the shores, the same every time.
func _plant_trees() -> void:
    _trees.clear()
    var rng := RandomNumberGenerator.new()
    rng.seed = 1234
    var tries := int(size_m.x * size_m.y / 900.0)
    for i in range(tries):
        var p := Vector2(rng.randf() * size_m.x, rng.randf() * size_m.y)
        if is_water(p):
            continue
        var near := false
        for angle in [0.0, PI / 2.0, PI, PI * 1.5]:
            if is_water(p + Vector2.RIGHT.rotated(angle) * 60.0):
                near = true
                break
        if not near and rng.randf() > 0.15:
            continue
        # NOTE (mristin):
        # No trees on the sand, nor where the villages stand.
        if (
            is_water(p + Vector2(SHORE_WIDTH * 2.0, 0))
            or is_water(p - Vector2(SHORE_WIDTH * 2.0, 0))
        ):
            continue
        var by_houses := false
        for item in places:
            if p.distance_to(item["at"]) < 70.0:
                by_houses = true
        if by_houses or p.distance_to(start["at"]) < 70.0 or p.distance_to(goal["at"]) < 70.0:
            continue
        _trees.append([p, rng.randf_range(4.0, 8.0), rng.randf() < 0.5])


## The layers above the land: the water (with the shader of the waves), and
## above it the islands, the forests and the villages (see [LandAbove]).
func _build_layers() -> void:
    for node in _water_nodes:
        node.queue_free()
    _water_nodes.clear()
    if _above != null:
        _above.queue_free()
    var shader_material := ShaderMaterial.new()
    shader_material.shader = WATER_SHADER
    for polygon in water:
        var node := Polygon2D.new()
        node.polygon = polygon["outer"]
        node.material = shader_material
        add_child(node)
        _water_nodes.append(node)
    _above = LandAbove.new()
    _above.map = self
    add_child(_above)


## The land and the sand along the shores, under the water.
func _draw() -> void:
    draw_rect(Rect2(Vector2(-2000, -2000), size_m + Vector2(4000, 4000)), LAND)
    for polygon in water:
        draw_colored_polygon(polygon["outer"], SHORE)
        _draw_ring(polygon["outer"], SHORE, SHORE_WIDTH * 2.0)


## Draw what lies above the water: the islands, the forests and the villages.
func draw_above(canvas: CanvasItem) -> void:
    for polygon in water:
        for hole in polygon["holes"]:
            canvas.draw_colored_polygon(hole, SHORE)
            var closed: PackedVector2Array = hole.duplicate()
            closed.append(hole[0])
            canvas.draw_polyline(closed, SHORE, SHORE_WIDTH * 2.0, true)
        for hole in polygon["holes"]:
            var inner := Geometry2D.offset_polygon(hole, -SHORE_WIDTH)
            for ring in inner:
                canvas.draw_colored_polygon(ring, LAND)
    for tree in _trees:
        var at: Vector2 = tree[0]
        var radius: float = tree[1]
        canvas.draw_circle(at + Vector2(1.5, 1.5), radius, FOREST_DARK)
        canvas.draw_circle(at, radius, FOREST if tree[2] else FOREST.lightened(0.08))
    if places.is_empty():
        _draw_village(canvas, start["at"])
        _draw_village(canvas, goal["at"])
    for item in places:
        _draw_village(canvas, item["at"], item["jetty"], item["kind"])


func _draw_ring(ring: PackedVector2Array, color: Color, width: float) -> void:
    var closed := ring.duplicate()
    closed.append(ring[0])
    draw_polyline(closed, color, width, true)


## A few long houses with red roofs and a jetty.
## A settlement: its houses with red roofs, a jetty out to [param jetty], and
## what shows its kind (the fence and the animals of a farm, the stalls of the
## market, the herb garden of the healer, the sign of the inn, the nets of the
## fishers, the barrels of the brewer, the hives of the beekeeper, the paddock
## of the horse farm, the cloth of the weaver).
func _draw_village(canvas: CanvasItem, at: Vector2, jetty := Vector2.INF, kind := "") -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(at.x * 31.0 + at.y)
    var toward := Vector2.ZERO
    if jetty != Vector2.INF:
        toward = (jetty - at).normalized()
    else:
        for angle in range(0, 360, 15):
            var direction := Vector2.RIGHT.rotated(deg_to_rad(angle))
            if is_water(at + direction * 30.0):
                toward += direction
        toward = toward.normalized() if toward != Vector2.ZERO else Vector2.DOWN
    var back := -toward
    var side := back.orthogonal()

    # The jetty, out into the water, on its posts.
    var jetty_end := jetty if jetty != Vector2.INF else at + toward * 28.0
    canvas.draw_line(at, jetty_end, WALL.darkened(0.25), 5.0)
    canvas.draw_line(at, jetty_end, WALL, 3.5)
    for k in range(1, 5):
        var post := at.lerp(jetty_end, k / 4.0)
        canvas.draw_circle(post + side * 2.5, 0.9, WALL.darkened(0.4))
        canvas.draw_circle(post - side * 2.5, 0.9, WALL.darkened(0.4))

    var counts := {"market": 6, "home": 2, "healer": 1, "inn": 2, "fishers": 3}
    var houses: int = counts.get(kind, 2)
    for i in range(houses):
        var spot := (
            at
            + back * (22.0 + 18.0 * (i / 2))
            + side * (-18.0 + 36.0 * (i % 2))
            + side * rng.randf_range(-4.0, 4.0)
        )
        _draw_house(
            canvas,
            spot,
            back.angle() + rng.randf_range(-0.25, 0.25),
            1.0 if kind != "healer" else 0.7
        )

    var yard := at + back * 30.0 + side * (60.0 if rng.randf() < 0.5 else -60.0)
    match kind:
        "home":
            _draw_fence(canvas, yard, 26.0)
            for k in range(3):
                canvas.draw_circle(
                    yard + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15)),
                    2.0,
                    Color("f1f0ea")
                )
            canvas.draw_circle(yard + Vector2(5, -8), 3.0, Color("e8e0d0"))
        "market":
            for k in range(4):
                var stall := at + back * 12.0 + side * (-24.0 + 16.0 * k)
                canvas.draw_rect(
                    Rect2(stall - Vector2(5, 4), Vector2(10, 8)),
                    [Color("b8332a"), Color("f2c14e"), Color("2f5f8a"), Color("6a9a4a")][k]
                )
        "healer":
            for k in range(9):
                var bed := yard + Vector2((k % 3) * 9.0 - 9.0, (k / 3) * 9.0 - 9.0)
                canvas.draw_circle(
                    bed, 3.2, [Color("6a9a4a"), Color("9a6ab8"), Color("e8c25a")][k % 3]
                )
        "inn":
            var sign_at := at + back * 8.0 + side * 10.0
            canvas.draw_line(sign_at, sign_at + side * 6.0, WALL.darkened(0.3), 1.5)
            canvas.draw_circle(sign_at + side * 6.0, 3.0, Color("f2c14e"))
            for k in range(3):
                canvas.draw_circle(
                    at + back * 14.0 + side * (-12.0 + 6.0 * k), 2.0, WALL.darkened(0.2)
                )
        "fishers":
            for k in range(3):
                var rack := at + side * (16.0 + 8.0 * k) + back * 6.0
                canvas.draw_line(rack - back * 6.0, rack + back * 6.0, WALL.darkened(0.3), 1.2)
                canvas.draw_line(
                    rack - back * 6.0 + side * 3.0,
                    rack + back * 6.0 + side * 3.0,
                    Color("9aa6b0"),
                    2.5
                )
        "brewer":
            for k in range(5):
                canvas.draw_circle(
                    at + back * 10.0 + side * (12.0 + 5.0 * k), 2.4, WALL.darkened(0.35)
                )
        "beekeeper":
            for k in range(6):
                var hive := yard + Vector2((k % 3) * 10.0 - 10.0, (k / 3) * 10.0 - 5.0)
                canvas.draw_circle(hive, 3.0, Color("e8a830"))
                canvas.draw_arc(hive, 3.0, 0.0, TAU, 10, WALL.darkened(0.3), 0.8)
        "horse_farm":
            _draw_fence(canvas, yard, 34.0)
            for k in range(3):
                var horse := yard + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
                var heading := rng.randf() * TAU
                canvas.draw_set_transform(horse, heading, Vector2.ONE)
                canvas.draw_rect(
                    Rect2(Vector2(-4, -1.6), Vector2(8, 3.2)),
                    [Color("8a5a2b"), Color("3a2a1a"), Color("e8e0d0")][k]
                )
                canvas.draw_circle(
                    Vector2(4.8, 0), 1.5, [Color("8a5a2b"), Color("3a2a1a"), Color("e8e0d0")][k]
                )
                canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        "weaver":
            for k in range(3):
                var line_at := at + back * 8.0 + side * (14.0 + 9.0 * k)
                canvas.draw_rect(
                    Rect2(line_at - Vector2(3, 5), Vector2(6, 10)),
                    [Color("b8332a"), Color("2f5f8a"), Color("e8c25a")][k]
                )


func _draw_house(canvas: CanvasItem, spot: Vector2, angle: float, scale: float) -> void:
    var transform := Transform2D(angle, spot) * Transform2D.IDENTITY.scaled(Vector2(scale, scale))
    canvas.draw_colored_polygon(
        (
            transform
            * PackedVector2Array(
                [Vector2(-14, -5), Vector2(14, -5), Vector2(14, 5), Vector2(-14, 5)]
            )
        ),
        WALL
    )
    canvas.draw_colored_polygon(
        (
            transform
            * PackedVector2Array(
                [Vector2(-15, -6), Vector2(15, -6), Vector2(15, 0), Vector2(-15, 0)]
            )
        ),
        ROOF
    )
    canvas.draw_colored_polygon(
        (
            transform
            * PackedVector2Array([Vector2(-15, 0), Vector2(15, 0), Vector2(15, 6), Vector2(-15, 6)])
        ),
        ROOF.darkened(0.25)
    )


func _draw_fence(canvas: CanvasItem, center: Vector2, half: float) -> void:
    canvas.draw_rect(
        Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), Color("7a8a4a")
    )
    canvas.draw_rect(
        Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0),
        WALL.darkened(0.2),
        false,
        1.2
    )


## The islands, the forests and the villages, drawn above the water.
class LandAbove:
    extends Node2D

    var map: LakeMap

    func _draw() -> void:
        if map != null:
            map.draw_above(self)
