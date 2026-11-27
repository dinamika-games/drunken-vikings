extends SceneTree

## Check the preconditions of the map of the Home Lakes (made by
## dev/maps/make_lakes.py), on which the boats which the game steers rely:
## they follow the ways of the map without looking where they go, so the ways
## themselves must keep to the water (see LakeMap.is_water: off the land and
## off the jetties).
##
## * LakeMap.is_water tells the water from the land everywhere, as counting
##   the shores crossed on the way out of the map tells it.
## * Every berth (where a boat lies at a jetty) is on the water, clear of the
##   shore (beside its jetty).
## * The skippers sail the routes between the places from berth to berth (see
##   NpcBoat): every route, sailed so, stays on the water all the way, and
##   clear of the shore except where it comes to a berth.
## * The wedding longship sails the route of the party (see Longship.sail):
##   it stays on the water, clear of the shore.
## * The pirates find their way on the grid of the water (see
##   LakeMap.water_path): every free cell is on the water, clear of the shore,
##   and every step between two free cells which the grid allows stays on the
##   water.
##
## $GODOT --headless --path . --script tests/godot/test_map.gd -- --no-camera

## The steps in which the ways are checked, in metres.
const STEP := 0.5

## The spacing of the points where is_water is checked, in metres.
const WATER_GRID := 4

## How far a way keeps from the land and the jetties, in metres: a boat is
## not a point.
const CLEARANCE := 3.0

## Near a berth, a way comes to the jetty: the clearance does not hold this
## close to the berth, in metres.
const NEAR_BERTH := 20.0

var _failures := 0
var _map: LakeMap


func _initialize() -> void:
    _run.call_deferred()


func _check(ok: bool, what: String) -> void:
    if not ok:
        _failures += 1
        if _failures <= 400:
            print("FAIL: " + what)


func _run() -> void:
    _map = LakeMap.new()
    root.add_child(_map)
    var error := _map.load_map(GameState.MAP_PATH)
    _check(error == "", "the map loads: " + error)
    _check_water()
    _check_berths()
    _check_routes()
    _check_party()
    _check_grid()
    if _failures > 40:
        print("... and %d more failures" % (_failures - 40))
    print("PASS test_map" if _failures == 0 else "FAIL test_map (%d)" % _failures)
    quit(0 if _failures == 0 else 1)


## Whether a boat at [param point] is clear of the land and of the jetties
## (of the shore only, without [param jetties]).
func _clear(point: Vector2, jetties := true) -> bool:
    if not _map.is_water(point):
        return false
    for k in range(8):
        var around := point + Vector2.RIGHT.rotated(TAU * k / 8.0) * CLEARANCE
        var free := _map.is_water(around) if jetties else _on_lakes(around)
        if not free:
            return false
    return true


## Whether the [param point] lies on the lakes (off the land; the jetties aside).
func _on_lakes(point: Vector2) -> bool:
    for polygon in _map.water:
        if Geometry2D.is_point_in_polygon(point, polygon["outer"]):
            for hole in polygon["holes"]:
                if Geometry2D.is_point_in_polygon(point, hole):
                    return false
            return true
    return false


## The first point of the way from [param from] to [param to] which is not on
## the water (or not clear, where [param clear] says so for the point), or
## Vector2.INF.
func _off_water(from: Vector2, to: Vector2, clear: Callable) -> Vector2:
    var steps := maxi(1, ceili(from.distance_to(to) / STEP))
    for i in range(steps + 1):
        var point := from.lerp(to, float(i) / steps)
        if not _map.is_water(point) or (clear.call(point) and not _clear(point)):
            return point
    return Vector2.INF


## LakeMap.is_water must tell the water from the land everywhere: off the
## jetties, it agrees with counting the shores crossed on the way out of the
## map, the same in each of four directions, on a grid of points over the
## whole map (and next to every corner of the shores, where counting is hard).
func _check_water() -> void:
    var rings: Array[PackedVector2Array] = []
    for polygon in _map.water:
        rings.append(polygon["outer"])
        for hole in polygon["holes"]:
            rings.append(hole)
    var wrong := 0
    var checked := 0
    # NOTE: On the grid, the crossings of a whole row (and column) at once.
    var columns := {}
    for x in range(0, int(_map.size_m.x), WATER_GRID):
        columns[x] = _cuts(rings, x + 0.37, 0)
    for y in range(0, int(_map.size_m.y), WATER_GRID):
        var row := _cuts(rings, y + 0.61, 1)
        for x in range(0, int(_map.size_m.x), WATER_GRID):
            var point := Vector2(x + 0.37, y + 0.61)
            var column: PackedFloat64Array = columns[x]
            var left := row.bsearch(point.x)
            var up := column.bsearch(point.y)
            var answers := [left % 2, (row.size() - left) % 2, up % 2, (column.size() - up) % 2]
            if answers.min() != answers.max() or _map._on_jetty(point):
                continue
            checked += 1
            if _map.is_water(point) != (answers[0] == 1):
                wrong += 1
                _check(false, "is_water tells the water from the land at %s" % point)
    for ring in rings:
        for corner: Vector2 in ring:
            for k in range(4):
                var point := corner + Vector2.RIGHT.rotated(TAU * (k + 0.5) / 4.0) * 1.5
                var counted := _counted(point, rings)
                if counted < 0 or _map._on_jetty(point):
                    continue
                checked += 1
                if _map.is_water(point) != (counted == 1):
                    wrong += 1
                    _check(false, "is_water tells the water from the land at %s" % point)
    print("is_water: %d points checked, %d told wrongly" % [checked, wrong])


## Where the line at [param at] (x = at for [param axis] 0, y = at for 1)
## crosses the sides of the [param rings], sorted along the line.
static func _cuts(rings: Array[PackedVector2Array], at: float, axis: int) -> PackedFloat64Array:
    var other := 1 - axis
    var cuts := PackedFloat64Array()
    for ring in rings:
        for i in range(ring.size()):
            var a := ring[i]
            var b := ring[(i + 1) % ring.size()]
            if (a[axis] > at) == (b[axis] > at):
                continue
            cuts.append(a[other] + (at - a[axis]) * (b[other] - a[other]) / (b[axis] - a[axis]))
    cuts.sort()
    return cuts


## Whether the [param point] is on the water, counted along four rays (to the
## left, right, up and down): 1 on the water, 0 on the land, -1 if the rays
## disagree (on a shore).
func _counted(point: Vector2, rings: Array[PackedVector2Array]) -> int:
    var answers := {}
    for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
        var count := 0
        for ring in rings:
            count += _crossings(point, direction, ring)
        answers[count % 2 == 1] = true
    if answers.size() > 1:
        return -1
    return 1 if answers.has(true) else 0


## How many sides of the [param ring] the ray from the [param point] in the
## axis [param direction] crosses (a vertex on the ray counts on one side only).
static func _crossings(point: Vector2, direction: Vector2, ring: PackedVector2Array) -> int:
    var axis := 0 if direction.x != 0.0 else 1
    var other := 1 - axis
    var count := 0
    for i in range(ring.size()):
        var a := ring[i]
        var b := ring[(i + 1) % ring.size()]
        if (a[other] > point[other]) == (b[other] > point[other]):
            continue
        var at := a[axis] + (point[other] - a[other]) * (b[axis] - a[axis]) / (b[other] - a[other])
        if (at - point[axis]) * direction[axis] > 0.0:
            count += 1
    return count


func _check_berths() -> void:
    for place in _map.places:
        # NOTE: The berth lies beside its jetty, clear of the shore.
        _check(_clear(place["berth"], false), "the berth of %s is clear on the water" % place["id"])


func _check_routes() -> void:
    var bad := 0
    for i in range(_map.places.size()):
        for j in range(_map.places.size()):
            if i == j:
                continue
            var a: Dictionary = _map.places[i]
            var b: Dictionary = _map.places[j]
            var route := _map.route_between(a["id"], b["id"])
            if route.size() < 2:
                _check(false, "there is a route from %s to %s" % [a["id"], b["id"]])
                continue
            if i > j:
                continue
            var sailed := route.duplicate()
            sailed[0] = a["berth"]
            sailed[-1] = b["berth"]
            var ends := [a["berth"], b["berth"]]
            var clear := func(point: Vector2) -> bool:
                return (
                    point.distance_to(ends[0]) > NEAR_BERTH
                    and point.distance_to(ends[1]) > NEAR_BERTH
                )
            for k in range(1, sailed.size()):
                var off := _off_water(sailed[k - 1], sailed[k], clear)
                if off != Vector2.INF:
                    bad += 1
                    _check(
                        false,
                        (
                            "the route from %s to %s stays clear on the water: not at %s"
                            % [a["id"], b["id"], off]
                        )
                    )
                    break
    print("%d routes leave the water or come too close to the land" % bad)


func _check_party() -> void:
    var route := _map.route
    var start := _map.route_point(0.0)
    var end := _map.route[-1]
    var clear := func(point: Vector2) -> bool:
        return point.distance_to(start) > NEAR_BERTH and point.distance_to(end) > NEAR_BERTH
    for k in range(1, route.size()):
        var off := _off_water(route[k - 1], route[k], clear)
        if off != Vector2.INF:
            _check(false, "the route of the party stays clear on the water: not at %s" % off)
            return


func _check_grid() -> void:
    var grid: AStarGrid2D = _map._grid
    var region := grid.region
    var cells := 0
    var bad_cells := 0
    var bad_steps := 0
    for y in range(region.size.y):
        for x in range(region.size.x):
            var cell := Vector2i(x, y)
            if grid.is_point_solid(cell):
                continue
            cells += 1
            var at := grid.get_point_position(cell)
            if not _clear(at):
                bad_cells += 1
                _check(false, "the free cell %s of the grid is clear on the water: %s" % [cell, at])
                continue
            for step in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
                var next: Vector2i = cell + step
                if not region.has_point(next) or grid.is_point_solid(next):
                    continue
                # NOTE: Diagonal steps only where no corner is solid (see
                # AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES).
                if (
                    step.x != 0
                    and step.y != 0
                    and (
                        grid.is_point_solid(cell + Vector2i(step.x, 0))
                        or grid.is_point_solid(cell + Vector2i(0, step.y))
                    )
                ):
                    continue
                var off := _off_water(
                    at, grid.get_point_position(next), func(_p: Vector2) -> bool: return false
                )
                if off != Vector2.INF:
                    bad_steps += 1
                    _check(
                        false, "the step from the cell %s to %s stays on the water" % [cell, next]
                    )
    print("%d free cells, %d not clear, %d steps off the water" % [cells, bad_cells, bad_steps])
