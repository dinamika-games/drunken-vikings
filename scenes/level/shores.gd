class_name Shores
extends RefCounted

## The shores of the water of a map (see LakeMap.water), which tell the water
## from the land: a point is on the water when the way from it straight to the
## left (out of the map) crosses the shores an odd number of times, the shores
## of the islands, too.
##
## We count the crossings ourselves, in 64-bit floats: Geometry2D.is_point_in_polygon
## casts its ray to a point very far away in 32-bit floats, and miscounts where
## the ray grazes a corner of a shore, which put thin lines of land across the
## lakes (see tests/godot/test_map.gd). The sides of the shores are sorted into
## bands along y, so that a point looks only at the sides which reach its band.

## The height of the bands, in metres.
const BAND := 8.0

## The sides of the shores which reach into each band, as ax, ay, bx, by;
## the first band begins at [member _top].
var _bands: Array[PackedFloat64Array] = []
var _top := 0.0


## The shores of the [param water] (Array of {"outer", "holes"}).
func _init(water: Array) -> void:
    var rings: Array[PackedVector2Array] = []
    var bottom := -INF
    _top = INF
    for polygon in water:
        for ring: PackedVector2Array in [polygon["outer"]] + polygon["holes"]:
            rings.append(ring)
            for point in ring:
                _top = minf(_top, point.y)
                bottom = maxf(bottom, point.y)
    if rings.is_empty():
        return
    _bands.resize(floori((bottom - _top) / BAND) + 1)
    for i in range(_bands.size()):
        _bands[i] = PackedFloat64Array()
    for ring in rings:
        for i in range(ring.size()):
            var a := ring[i]
            var b := ring[(i + 1) % ring.size()]
            for band in range(_band(minf(a.y, b.y)), _band(maxf(a.y, b.y)) + 1):
                _bands[band].append_array([a.x, a.y, b.x, b.y])


func _band(y: float) -> int:
    return floori((y - _top) / BAND)


## Whether the shores enclose the [param point] (it is on the water).
func encloses(point: Vector2) -> bool:
    var band := _band(point.y)
    if band < 0 or band >= _bands.size():
        return false
    var sides := _bands[band]
    var px := float(point.x)
    var py := float(point.y)
    var inside := false
    for i in range(0, sides.size(), 4):
        var ay := sides[i + 1]
        var by := sides[i + 3]
        if (ay > py) == (by > py):
            continue
        var ax := sides[i]
        if ax + (py - ay) * (sides[i + 2] - ax) / (by - ay) < px:
            inside = not inside
    return inside
