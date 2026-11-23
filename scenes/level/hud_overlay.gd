class_name HudOverlay
extends Control

## What the level shows over the lakes: how far the boat and the viking ship
## got along the route, the map of all the lakes, how the players steer, and
## an arrow to the viking ship when it is out of sight.

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _RED := Color("b8332a")
const _INK := Color(0.05, 0.07, 0.1, 0.75)
const _WATER := Color("3d6f9c")
const _LAND := Color("5d6b3a")
const _MINIMAP := Rect2(1700, 100, 200, 660)

## The level (see level.gd).
var level: Node

## How far the boat and the ship got along the route, in [0, 1].
var progress := 0.0
var ship_progress := 0.0

## The map of the lakes, fitted into its box once.
var _minimap_polygons: Array = []
var _minimap_route := PackedVector2Array()
var _minimap_scale := 1.0


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    if level == null or level.map() == null:
        return
    _draw_progress()
    _draw_minimap()
    _draw_steering()
    _draw_ship_arrow()


## The route as a bar: from the start village to the goal, with the boat
## and the viking ship on it.
func _draw_progress() -> void:
    var map: LakeMap = level.map()
    var font := ThemeDB.fallback_font
    var left := Vector2(560, 100)
    var right := Vector2(1360, 100)
    draw_line(left, right, _INK, 14.0)
    draw_line(left, left.lerp(right, progress), _GOLD, 8.0)
    var start_width := font.get_string_size(map.start["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
    _outlined(font, left + Vector2(-16 - start_width, 8), map.start["name"], 24)
    _outlined(font, right + Vector2(16, 8), map.goal["name"], 24)
    draw_circle(left.lerp(right, ship_progress), 12.0, _RED)
    draw_circle(left.lerp(right, ship_progress), 5.0, _PAPER)
    draw_circle(left.lerp(right, progress), 9.0, _GOLD)


func _outlined(font: Font, at: Vector2, text: String, font_size: int) -> void:
    draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, _INK)
    draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _PAPER)


func _fit_minimap() -> void:
    var map: LakeMap = level.map()
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
    for p in map.route:
        _minimap_route.append(_MINIMAP.position + p * _minimap_scale)


func _draw_minimap() -> void:
    if _minimap_polygons.is_empty():
        _fit_minimap()
    var map: LakeMap = level.map()
    var box := Rect2(_MINIMAP.position, map.size_m * _minimap_scale)
    draw_rect(box.grow(6.0), _INK)
    draw_rect(box, _LAND)
    for polygon in _minimap_polygons:
        draw_colored_polygon(polygon["outer"], _WATER)
        for hole in polygon["holes"]:
            draw_colored_polygon(hole, _LAND)
    for i in range(0, _minimap_route.size() - 1, 2):
        draw_line(_minimap_route[i], _minimap_route[i + 1], Color(1, 1, 1, 0.4), 1.5)
    draw_circle(_MINIMAP.position + map.goal["at"] * _minimap_scale, 5.0, _GOLD)
    var ship: Longship = level.ship()
    draw_circle(_MINIMAP.position + ship.position * _minimap_scale, 6.0, _RED)
    var boat: RowBoat = level.boat()
    var at := _MINIMAP.position + boat.position * _minimap_scale
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


## How the players steer: alone, a needle from left to right (the head);
## as a pair, the pull of each oar, so that they see who rows harder.
func _draw_steering() -> void:
    var center := Vector2(960, 1040)
    var radius := 50.0
    var boat: RowBoat = level.boat()
    if level.players() == 2:
        # NOTE (mristin):
        # The pull of an oar fades over the seconds after its stroke.
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
        var turn := clampf(boat.yaw_rate / deg_to_rad(40.0), -1.0, 1.0)
        draw_line(center, center + Vector2(turn * 30.0, -0.0), _GOLD, 6.0)
        draw_circle(center, 7.0, _GOLD)
    else:
        draw_arc(center, radius, PI * 1.15, PI * 1.85, 24, _INK, 14.0)
        draw_arc(center, radius, PI * 1.45, PI * 1.55, 8, Color(1, 1, 1, 0.3), 14.0)
        var angle: float = PI * 1.5 + level.steer() * PI * 0.35
        draw_line(center, center + Vector2.RIGHT.rotated(angle) * (radius + 8.0), _GOLD, 5.0)
        draw_circle(center, 7.0, _GOLD)

    # NOTE (mristin):
    # For tuning: how far the head is to the side of home, and the steering.
    var service: Node = level.service()
    if service != null and service.IsRunning():
        var text := (
            "head %+.2f  steer %+.2f  strokes %d"
            % [service.GetShift(0), service.GetSteer(0), service.GetStrokes(0)]
        )
        if level.players() == 2:
            text = "strokes %d / %d" % [service.GetStrokes(0), service.GetStrokes(1)]
        _outlined(ThemeDB.fallback_font, center + Vector2(110, 0), text, 20)


## An arrow at the edge of the screen to the viking ship, when it is out of sight.
func _draw_ship_arrow() -> void:
    var ship: Longship = level.ship()
    var at: Vector2 = level.to_screen(ship.position)
    var screen := Rect2(Vector2.ZERO, size).grow(-60.0)
    if screen.has_point(at):
        return
    var center := size / 2.0
    var direction := (at - center).normalized()
    var t := INF
    for axis in [0, 1]:
        if absf(direction[axis]) > 1e-6:
            var limit: float = screen.end[axis] if direction[axis] > 0 else screen.position[axis]
            t = minf(t, (limit - center[axis]) / direction[axis])
    var tip := center + direction * t
    var side := direction.orthogonal()
    draw_colored_polygon(
        PackedVector2Array(
            [tip, tip - direction * 40.0 + side * 22.0, tip - direction * 40.0 - side * 22.0]
        ),
        _RED
    )
    draw_polyline(
        PackedVector2Array(
            [tip, tip - direction * 40.0 + side * 22.0, tip - direction * 40.0 - side * 22.0, tip]
        ),
        _PAPER,
        3.0
    )
