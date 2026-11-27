class_name TaskArrows
extends Control

## Point to where each task under way leads, when the place lies off the
## screen (as the target arrow of Bird Dog): a golden arrow on a ring around
## the middle of the screen, with the name of the place and of the task, so
## that the players need not remember where to go.

## The radius of the ring on which the arrows go round, in pixels.
const RING := 330.0

## Arrows closer than this angle (in radians) become one.
const MERGE_ANGLE := 0.45

const _GOLD := Color("f2c14e")
const _INK := Color(0.05, 0.07, 0.1, 0.85)

## The world (see world.gd).
var world: Node


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    if world == null or world.map() == null or world.map().places.is_empty():
        return
    var state: Node = world.state()
    var screen := Rect2(Vector2.ZERO, size).grow(-60.0)
    var center := size / 2.0
    # The tasks which lead to the same place share an arrow.
    var titles := {}
    for entry in state.missions.active:
        var target: String = state.missions.target(state, entry["id"])
        if target != "" and target != state.place:
            if not titles.has(target):
                titles[target] = []
            titles[target].append(Grammar.text(state.missions.missions[entry["id"]]["title"]))
    # The arrows which point nearly the same way become one, with all the names.
    var arrows: Array = []
    for target in titles.keys():
        var at: Vector2 = world.to_screen(world.map().place(target)["jetty"])
        if screen.has_point(at):
            continue
        var direction := (at - center).normalized()
        var joined := false
        for arrow in arrows:
            if absf(arrow["direction"].angle_to(direction)) < MERGE_ANGLE:
                arrow["names"].append(Grammar.text(state.place_name(target)))
                arrow["titles"].append_array(titles[target])
                joined = true
                break
        if not joined:
            arrows.append(
                {
                    "direction": direction,
                    "names": [Grammar.text(state.place_name(target))],
                    "titles": titles[target].duplicate()
                }
            )
    for arrow in arrows:
        _draw_arrow(
            center,
            arrow["direction"],
            " · ".join(arrow["names"]),
            Grammar.fill(
                arrow["titles"].map(func(title: String) -> Dictionary: return Grammar.raw(title))
            )
        )


func _draw_arrow(center: Vector2, direction: Vector2, name: String, title: String) -> void:
    var tip := center + direction * RING
    var pulse := 1.0 + 0.1 * sin(Time.get_ticks_msec() / 150.0)
    var painted := Pictures.of("ui", "arrow")
    if painted != null:
        Pictures.draw(self, painted, tip - direction * 5.0, 96.0 * pulse, direction.angle())
    else:
        _draw_plain_arrow(tip, direction, pulse)
    var font := ThemeDB.fallback_font
    var label_at := tip - direction * 150 + Vector2(-200, -4)
    for line in [[name, 32, 0.0], [title, 22, 30.0]]:
        var where: Vector2 = label_at + Vector2(0, line[2])
        draw_string_outline(
            font, where, line[0], HORIZONTAL_ALIGNMENT_CENTER, 400, line[1], 8, _INK
        )
        draw_string(font, where, line[0], HORIZONTAL_ALIGNMENT_CENTER, 400, line[1], _GOLD)


## The arrow drawn simply, when its picture is missing.
func _draw_plain_arrow(tip: Vector2, direction: Vector2, pulse: float) -> void:
    var side := direction.orthogonal()
    var arrow := PackedVector2Array(
        [
            tip + direction * 40 * pulse,
            tip + side * 30 - direction * 10,
            tip + side * 12 - direction * 10,
            tip + side * 12 - direction * 50,
            tip - side * 12 - direction * 50,
            tip - side * 12 - direction * 10,
            tip - side * 30 - direction * 10,
        ]
    )
    draw_colored_polygon(arrow, _GOLD)
    var outline := arrow.duplicate()
    outline.append(arrow[0])
    draw_polyline(outline, _INK, 3.0, true)
