class_name LakeMap
extends Node2D

## The lakes of a level (made by dev/maps/make_lakes.py): it draws the land,
## the water, the islands, the forests on the shores and the villages, and
## tells the water from the land for the boats.
##
## The map is in metres, x east and y south; one unit of the canvas is a metre.

const WATER_SHADER := preload("res://scenes/level/water.gdshader")
const SHORE_SHADER := preload("res://scenes/level/shore.gdshader")
const GROUND_SHADER := preload("res://scenes/level/ground.gdshader")

## The band of sand along the shores is this wide, in metres, half of it over
## the water (for the foam), half on the land (see shore.gdshader).
const SHORE_BAND := 16.0

## The jetties are land for the boats: no boat comes closer to the middle of
## a jetty than this, in metres (half the jetty and half a boat).
const JETTY_CLEARANCE := 5.5

## A boat lies this far beyond the end of the jetty, in metres.
const BERTH := 8.0

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

## The painted buildings of each kind of settlement, the main one first (see
## Pictures): [sheet, picture, long side in metres].
const PAINTED_VILLAGES := {
    "home":
    [["buildings", "longhouse_turf", 26.0], ["buildings", "barn", 20.0], ["farm", "sheep", 4.0]],
    "market":
    [
        ["buildings", "market", 24.0],
        ["buildings", "longhouse_shingles", 26.0],
        ["buildings", "storehouse", 13.0],
        ["buildings", "market", 20.0]
    ],
    "healer":
    [["buildings", "herb_hut", 20.0], ["farm", "herb_bed", 8.0], ["farm", "herb_bed", 8.0]],
    "inn":
    [["buildings", "inn", 26.0], ["buildings", "longhouse_thatch", 24.0], ["farm", "barrels", 5.0]],
    "fishers":
    [
        ["buildings", "longhouse_turf", 24.0],
        ["buildings", "boathouse", 16.0],
        ["farm", "fish_rack", 7.0]
    ],
    "brewer":
    [["buildings", "longhouse_shingles", 26.0], ["farm", "barrels", 6.0], ["farm", "barrels", 5.0]],
    "beekeeper":
    [["buildings", "longhouse_thatch", 24.0], ["farm", "beehive", 4.0], ["farm", "beehive", 4.0]],
    "horse_farm":
    [["buildings", "longhouse_turf", 26.0], ["buildings", "barn", 20.0], ["farm", "horse", 5.0]],
    "weaver": [["buildings", "longhouse_shingles", 24.0], ["farm", "cloth_line", 8.0]],
    "chieftain": [["buildings", "hall", 32.0], ["buildings", "longhouse_shingles", 24.0]],
    "farm":
    [
        ["buildings", "longhouse_thatch", 24.0],
        ["buildings", "barn", 20.0],
        ["farm", "barley_ripe", 18.0]
    ],
    "mill": [["buildings", "mill", 24.0], ["buildings", "storehouse", 13.0]],
    "smith": [["buildings", "smithy", 22.0], ["buildings", "longhouse_turf", 24.0]],
    "potter": [["buildings", "kiln", 18.0], ["buildings", "longhouse_thatch", 24.0]],
    "herders":
    [["buildings", "longhouse_turf", 24.0], ["farm", "sheep", 4.0], ["farm", "goat", 3.5]],
}

## The painted trees and plants on the land ("<sheet>/<picture>", see
## Pictures), and how often each grows; the first sheet whose pictures are
## all there is used.
const PAINTED_TREES := [
    {
        "trees/pine": 4,
        "trees/spruce": 4,
        "trees/young_spruce": 2,
        "trees/birch": 3,
        "trees/oak": 2,
        "trees/linden": 2,
        "trees/rowan": 1,
        "trees/apple": 1,
        "trees/willow": 1,
        "trees/alder": 1,
        "trees/aspen": 1,
        "trees/maple": 1,
        "trees/juniper": 2,
        "trees/birches": 2,
        "trees/hazel": 2,
        "trees/old_pine": 1,
        "nature/rock": 1,
        "bushes/lingonberry": 1,
        "bushes/blueberry": 1,
        "bushes/raspberry": 1,
        "bushes/wild_rose": 1,
        "bushes/elder": 1,
        "bushes/hawthorn": 1,
        "bushes/juniper": 1,
        "bushes/fern": 1,
        "bushes/heather": 1,
        "bushes/broom": 1,
        "bushes/evergreen": 1,
        "bushes/guelder_rose": 1,
        "bushes/sapling": 1,
        "bushes/bracken": 1,
        "bushes/meadowsweet": 1,
    },
    {
        "nature/pine": 4,
        "nature/spruce": 4,
        "nature/birch": 3,
        "nature/trees": 2,
        "nature/berry_bush": 1,
        "nature/rock": 1,
        "nature/wild_flowers": 1
    },
]

## The bushes are drawn this much smaller than the trees.
const BUSH_SCALE := 0.5

## The details scattered over the grass (see LandDetails), how often each
## lies, and how long it is in metres.
const GRASS_DETAILS := {
    "tall_tuft": [3, 4.0],
    "long_grass": [2, 4.5],
    "clover": [3, 4.0],
    "daisies": [3, 4.0],
    "buttercups": [3, 4.0],
    "heather": [1, 4.5],
    "moss": [2, 4.0],
    "fern": [1, 4.5],
    "mushroom_ring": [1, 4.0],
    "stones": [2, 4.0],
    "molehill": [1, 3.0],
    "bare_earth": [1, 5.0],
    "lush_patch": [3, 10.0],
    "dry_patch": [3, 10.0],
    "leaves": [1, 4.0],
}

## About one detail on the grass for every this many square metres.
const GRASS_DETAIL_AREA := 500.0

## The painted textures of the land and of the sand are this many metres wide.
const TEXTURE_METRES := 24.0

## The size of the map in metres.
var size_m := Vector2.ZERO

## The polygons of the water: Array of {"outer": PackedVector2Array,
## "holes": Array[PackedVector2Array]}. Assign it whole (its shores are
## indexed then, see [method is_water]).
var water: Array = []:
    set(value):
        water = value
        _shores = Shores.new(water)

## The course of the viking ship.
var route := PackedVector2Array()

## The names: Array of {"kind", "name", "at": Vector2}.
var labels: Array = []

## The start and the goal: {"name", "at": Vector2}.
var start := {}
var goal := {}

## The settlements: Array of {"id", "kind", "name", "at": Vector2, "jetty":
## Vector2 (the end of its jetty), "berth": Vector2 (where a boat lies at the
## end of the jetty)}.
var places: Array = []

## The ways of the boats between the places: "<id>|<id>" -> PackedVector2Array.
var routes := {}

## The grid of the water for the boats which find their own way (the pirates
## of the chase), or null if the map has none.
var _grid: AStarGrid2D

## The shores, which tell the water from the land (see [method is_water]).
var _shores := Shores.new([])

## The length of the route up to each of its points, in metres.
var _route_lengths := PackedFloat32Array()

var _trees: Array[LakeGrowth.GrowingTree] = []

## The details on the grass.
var _details: Array[LakeGrowth.GrassDetail] = []

## The shader of the grass on the land and the islands, or null.
var _ground: ShaderMaterial

## The reeds and the water lilies by the shores.
var _water_plants: Array[LakeGrowth.WaterPlant] = []
var _water_nodes: Array[Node2D] = []
var _above: Node2D


func _init() -> void:
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    _ground = _make_ground()
    material = _ground


## The shader of the grass (see ground.gdshader), or null without the painted grass.
static func _make_ground() -> ShaderMaterial:
    var lush := Pictures.of("ground", "grass_lush")
    if lush == null:
        return null
    var ground := ShaderMaterial.new()
    ground.shader = GROUND_SHADER
    ground.set_shader_parameter("lush", lush)
    var dry := Pictures.of("ground", "grass_dry")
    ground.set_shader_parameter("has_dry", dry != null)
    if dry != null:
        ground.set_shader_parameter("dry", dry)
    return ground


## Load the map from the JSON of dev/maps/make_lakes.py; return what went wrong, or "".
func load_map(path: String) -> String:
    var text := FileAccess.get_file_as_string(path)
    if text == "":
        return "Could not read the map %s." % path
    var data: Variant = JSON.parse_string(text)
    if not data is Dictionary:
        return "The map %s is no JSON object." % path
    size_m = Vector2(data["size_m"][0], data["size_m"][1])
    var polygons: Array = []
    for polygon in data["water"]:
        var holes: Array[PackedVector2Array] = []
        for hole in polygon["holes"]:
            holes.append(_points(hole))
        polygons.append({"outer": _points(polygon["outer"]), "holes": holes})
    water = polygons
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
        (
            places
            . append(
                {
                    "id": place["id"],
                    "kind": place["kind"],
                    "name": place["name"],
                    "at": _vector(place["at"]),
                    "jetty": _vector(place["jetty"]),
                    "berth":
                    (
                        _vector(place["jetty"])
                        + (_vector(place["jetty"]) - _vector(place["at"])).normalized() * BERTH
                    ),
                }
            )
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


## Whether the point is on the water (the jetties count as land).
func is_water(point: Vector2) -> bool:
    return _shores.encloses(point) and not _on_jetty(point)


## Whether the [param point] is on a jetty (or too close for a boat).
func _on_jetty(point: Vector2) -> bool:
    for item in places:
        var closest := Geometry2D.get_closest_point_to_segment(point, item["at"], item["jetty"])
        if closest.distance_squared_to(point) < JETTY_CLEARANCE * JETTY_CLEARANCE:
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


## The way of the boats on the water from the berth of one place to the
## berth of another, clear of the shores and the jetties.
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
    _water_plants.clear()
    _scatter_details()
    var rng := RandomNumberGenerator.new()
    rng.seed = 1234
    _plant_in_water(rng)
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
        _trees.append(
            LakeGrowth.GrowingTree.new(
                p, rng.randf_range(4.0, 8.0), rng.randf() < 0.5, _pick_tree(rng), rng.randf() * TAU
            )
        )


## Reeds and water lilies in little clusters along the shores, a few metres
## out in the water, but not by the jetties.
func _plant_in_water(rng: RandomNumberGenerator) -> void:
    var rings: Array = []
    for polygon in water:
        rings.append(polygon["outer"])
        rings.append_array(polygon["holes"])
    for ring: PackedVector2Array in rings:
        var walked := 0.0
        for i in range(ring.size()):
            var from := ring[i]
            var to := ring[(i + 1) % ring.size()]
            walked += from.distance_to(to)
            if walked < 30.0:
                continue
            walked = 0.0
            if rng.randf() > 0.6:
                continue
            var on := (from + to) / 2.0
            var normal := (to - from).orthogonal().normalized()
            if not is_water(on + normal * 6.0):
                normal = -normal
            if not is_water(on + normal * 6.0):
                continue
            var by_jetty := false
            for item in places:
                if on.distance_to(item["at"]) < 80.0:
                    by_jetty = true
            if by_jetty:
                continue
            var reeds := rng.randf() < 0.55
            for n in range(rng.randi_range(2, 4)):
                var at := (
                    on
                    + normal * rng.randf_range(3.0, 9.0 if reeds else 16.0)
                    + (to - from).normalized() * rng.randf_range(-9.0, 9.0)
                )
                if not is_water(at):
                    continue
                _water_plants.append(
                    LakeGrowth.WaterPlant.new(
                        at,
                        "reeds" if reeds else "lilies",
                        rng.randf_range(9.0, 14.0) if reeds else rng.randf_range(7.0, 10.0),
                        rng.randf() * TAU
                    )
                )


## Scatter the details over the grass (see GRASS_DETAILS): not on the water,
## nor where the villages stand.
func _scatter_details() -> void:
    _details.clear()
    var total := 0
    for name in GRASS_DETAILS:
        if Pictures.of("grass_details", name) == null:
            return
        total += int(GRASS_DETAILS[name][0])
    var rng := RandomNumberGenerator.new()
    rng.seed = 4321
    var area := (size_m + Vector2(400, 400)) * 1.0
    for i in range(int(area.x * area.y / GRASS_DETAIL_AREA)):
        var p := Vector2(rng.randf() * area.x - 200.0, rng.randf() * area.y - 200.0)
        if is_water(p):
            continue
        var by_houses := false
        for item in places:
            if p.distance_to(item["at"]) < 60.0:
                by_houses = true
                break
        if by_houses:
            continue
        var pick := rng.randi() % total
        for name in GRASS_DETAILS:
            pick -= int(GRASS_DETAILS[name][0])
            if pick < 0:
                var length: float = GRASS_DETAILS[name][1] * rng.randf_range(1.2, 1.9)
                _details.append(
                    LakeGrowth.GrassDetail.new(p, name, length, rng.randf() * TAU, _on_island(p))
                )
                break


func _on_island(point: Vector2) -> bool:
    for polygon in water:
        for hole in polygon["holes"]:
            if Geometry2D.is_point_in_polygon(point, hole):
                return true
    return false


## Draw the details on the grass on [param canvas]: those of the islands
## ([param islands]), or those of the land (see LandDetails and IslandLand).
func draw_details(canvas: CanvasItem, islands := false) -> void:
    for detail in _details:
        if detail.island != islands:
            continue
        var picture := Pictures.of("grass_details", detail.picture)
        if picture != null:
            Pictures.draw(canvas, picture, detail.at, detail.length, detail.angle)


## A painted tree or plant, by how often each grows.
func _pick_tree(rng: RandomNumberGenerator) -> String:
    var kinds: Dictionary = PAINTED_TREES[-1]
    for candidate: Dictionary in PAINTED_TREES:
        var all_there := true
        for key: String in candidate:
            if Pictures.of(key.get_slice("/", 0), key.get_slice("/", 1)) == null:
                all_there = false
                break
        if all_there:
            kinds = candidate
            break
    var total := 0
    for key in kinds:
        total += int(kinds[key])
    var pick := rng.randi() % total
    for key in kinds:
        pick -= int(kinds[key])
        if pick < 0:
            return key
    return "nature/pine"


## The layers above the land: the water (with the shader of the waves), and
## above it the islands, the forests and the villages (see [LandAbove]).
func _build_layers() -> void:
    for node in _water_nodes:
        node.queue_free()
    _water_nodes.clear()
    if _above != null:
        _above.queue_free()
    # NOTE (mristin):
    # The details lie on the grass, under the water and the sand, which
    # cover those by the shores.
    var details := LandDetails.new()
    details.map = self
    add_child(details)
    _water_nodes.append(details)

    var shader_material := ShaderMaterial.new()
    shader_material.shader = WATER_SHADER
    for polygon in water:
        var node := Polygon2D.new()
        node.polygon = polygon["outer"]
        node.material = shader_material
        add_child(node)
        _water_nodes.append(node)

    # NOTE (mristin):
    # The islands lie on the water; their sand comes over them, like the sand
    # of the shores over the land.
    var islands := IslandLand.new()
    islands.map = self
    islands.material = _ground
    add_child(islands)
    _water_nodes.append(islands)
    var island_details := LandDetails.new()
    island_details.map = self
    island_details.islands = true
    add_child(island_details)
    _water_nodes.append(island_details)

    var shore_material := ShaderMaterial.new()
    shore_material.shader = SHORE_SHADER
    var white := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
    for polygon in water:
        var rings: Array = [polygon["outer"]]
        rings.append_array(polygon["holes"])
        for ring: PackedVector2Array in rings:
            var line := Line2D.new()
            line.points = _water_on_left(ring)
            line.closed = true
            line.width = SHORE_BAND
            line.joint_mode = Line2D.LINE_JOINT_ROUND
            line.texture = white
            line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
            line.material = shore_material
            add_child(line)
            _water_nodes.append(line)
    _above = LandAbove.new()
    _above.map = self
    add_child(_above)


## The [param ring] turned so that the water lies to the left of its way,
## where the band of the shore has UV.y = 0 (see shore.gdshader).
func _water_on_left(ring: PackedVector2Array) -> PackedVector2Array:
    var water_left := 0
    var count := mini(ring.size(), 24)
    for k in range(count):
        var i := k * ring.size() / count
        var from := ring[i]
        var to := ring[(i + 1) % ring.size()]
        var middle := (from + to) / 2.0
        var left := (to - from).normalized().orthogonal()
        if is_water(middle + left * 2.0):
            water_left += 1
        elif is_water(middle - left * 2.0):
            water_left -= 1
    if water_left >= 0:
        return ring
    var turned := ring.duplicate()
    turned.reverse()
    return turned


## The land, under the water.
func _draw() -> void:
    var grass := Pictures.of("nature", "grass")
    var land := Rect2(Vector2(-2000, -2000), size_m + Vector2(4000, 4000))
    if _ground != null:
        draw_rect(land, Color.WHITE)
    elif grass != null:
        # NOTE (mristin):
        # The painted textures repeat (see _init); a
        # texture is drawn in its pixels, so we scale it to TEXTURE_METRES.
        var per_pixel := TEXTURE_METRES / grass.get_width()
        draw_set_transform(Vector2.ZERO, 0.0, Vector2(per_pixel, per_pixel))
        draw_texture_rect(grass, Rect2(land.position / per_pixel, land.size / per_pixel), true)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    else:
        draw_rect(land, LAND)


## Draw what lies above the water and the shores: the reeds, the forests and
## the villages.
func draw_above(canvas: CanvasItem) -> void:
    for plant in _water_plants:
        var picture := Pictures.of("nature", plant.picture)
        if picture != null:
            Pictures.draw(canvas, picture, plant.at, plant.size, plant.angle)
    for tree in _trees:
        var at := tree.at
        var radius := tree.radius
        var key := tree.picture
        var painted := Pictures.of(key.get_slice("/", 0), key.get_slice("/", 1))
        if painted != null:
            var scale := BUSH_SCALE if key.begins_with("bushes/") else 1.0
            Pictures.draw(canvas, painted, at, radius * 2.6 * scale, tree.angle)
            continue
        canvas.draw_circle(at + Vector2(1.5, 1.5), radius, FOREST_DARK)
        canvas.draw_circle(at, radius, FOREST if tree.dark else FOREST.lightened(0.08))
    if places.is_empty():
        _draw_village(canvas, start["at"])
        _draw_village(canvas, goal["at"])
    for item in places:
        _draw_village(canvas, item["at"], item["jetty"], item["kind"])


## Fill the [param polygon] on [param canvas] with the repeating [param
## texture], or with [param color] if there is none.
func _fill(
    canvas: CanvasItem, polygon: PackedVector2Array, color: Color, texture: Texture2D
) -> void:
    if texture == null:
        canvas.draw_colored_polygon(polygon, color)
        return
    var uvs := PackedVector2Array()
    for point in polygon:
        uvs.append(point / TEXTURE_METRES)
    canvas.draw_colored_polygon(polygon, Color.WHITE, uvs, texture)


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
    if _draw_painted_village(canvas, at, jetty_end, kind, rng):
        return
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


## The painted settlement (see PAINTED_VILLAGES): the jetty of three pieces,
## the main building behind it with its door to the water, the second one to
## its side, and the rest in the yard. Return false if a picture is missing.
func _draw_painted_village(
    canvas: CanvasItem, at: Vector2, jetty_end: Vector2, kind: String, rng: RandomNumberGenerator
) -> bool:
    var things: Array = PAINTED_VILLAGES.get(kind, PAINTED_VILLAGES["home"])
    var pieces := ["jetty_land", "jetty_middle", "jetty_end"]
    if not Pictures.has_all("buildings", pieces):
        return false
    for thing in things:
        if Pictures.of(thing[0], thing[1]) == null:
            return false

    var toward := (jetty_end - at).normalized()
    var back := -toward
    var side := back.orthogonal()

    # NOTE (mristin):
    # The pieces of the painted jetty lie along their width, the land at
    # their left; they overlap a little so that no gap shows.
    var length := at.distance_to(jetty_end) + 6.0
    var count := maxi(3, roundi(length / 10.0))
    var step := length / count
    for k in range(count):
        var piece: String = pieces[0] if k == 0 else (pieces[2] if k == count - 1 else pieces[1])
        var middle := at - toward * 6.0 + toward * step * (k + 0.5)
        Pictures.draw(canvas, Pictures.of("buildings", piece), middle, step * 1.12, toward.angle())

    # The door of a building is at the bottom of its picture: it faces the water.
    var facing := toward.angle() - PI / 2.0
    var flip := 1.0 if rng.randf() < 0.5 else -1.0
    var spots := [
        at + back * 22.0,
        at + back * 26.0 + side * flip * 34.0,
        at + back * 12.0 - side * flip * 24.0,
        at + back * 44.0 - side * flip * 26.0,
    ]
    for i in range(things.size()):
        var thing: Array = things[i]
        var spot: Vector2 = spots[i % spots.size()]
        var angle := facing + rng.randf_range(-0.15, 0.15)
        if thing[0] == "farm" and float(thing[2]) < 10.0:
            # A few animals or things around their spot, every which way.
            for k in range(3):
                Pictures.draw(
                    canvas,
                    Pictures.of(thing[0], thing[1]),
                    spot + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)),
                    float(thing[2]),
                    rng.randf() * TAU
                )
            continue
        Pictures.draw(canvas, Pictures.of(thing[0], thing[1]), spot, float(thing[2]), angle)
    return true


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


## The details on the grass of the land (see LakeMap.draw_details).
class LandDetails:
    extends Node2D

    var map: LakeMap

    ## Whether these are the details of the islands (drawn over them).
    var islands := false

    func _draw() -> void:
        if map != null:
            map.draw_details(self, islands)


## The land of the islands, drawn over the water.
class IslandLand:
    extends Node2D

    var map: LakeMap

    func _draw() -> void:
        if map == null:
            return
        for polygon in map.water:
            for hole in polygon["holes"]:
                if material != null:
                    draw_colored_polygon(hole, Color.WHITE)
                else:
                    map._fill(self, hole, LAND, Pictures.of("nature", "grass"))


## The reeds, the forests and the villages, drawn above the water.
class LandAbove:
    extends Node2D

    var map: LakeMap

    func _draw() -> void:
        if map != null:
            map.draw_above(self)
