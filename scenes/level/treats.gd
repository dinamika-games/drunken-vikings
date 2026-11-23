class_name Treats
extends Node2D

## The things which the wedding longship drops into the water (flower
## wreaths, ribbons, honey cakes and apples), floating and bobbing until the
## players row over them and pick them up: each one gives a silver coin, and
## a "+1" floats up where it was.

## The kinds of the treats.
const KINDS := ["wreath", "ribbon", "cake", "apple"]

## The boat picks a treat up within this many metres of its middle.
const PICK_RADIUS := 10.0

## A treat floats this long, in seconds, and then sinks gently.
const LIFE := 90.0

## How much larger than life we draw the treats, as the boats.
const SCALE := 3.0

## The treats on the water: Array of {"at", "kind", "age", "spin"}.
var items: Array = []

## The "+1" which float up: Array of {"at", "age"}.
var _pops: Array = []
var _time := 0.0


## Drop a treat of a random kind at [param at].
func drop(at: Vector2, rng: RandomNumberGenerator) -> void:
    items.append(
        {"at": at, "kind": KINDS[rng.randi() % KINDS.size()], "age": 0.0, "spin": rng.randf() * TAU}
    )


## Pick up the treats near the boat at [param at]; return how many.
func pick(at: Vector2) -> int:
    var picked := 0
    var left: Array = []
    for item in items:
        if (item["at"] as Vector2).distance_to(at) <= PICK_RADIUS:
            picked += 1
            _pops.append({"at": item["at"], "age": 0.0})
        else:
            left.append(item)
    items = left
    return picked


func _process(delta: float) -> void:
    _time += delta
    var left: Array = []
    for item in items:
        item["age"] = float(item["age"]) + delta
        if item["age"] < LIFE:
            left.append(item)
    items = left
    var pops: Array = []
    for pop in _pops:
        pop["age"] = float(pop["age"]) + delta
        if pop["age"] < 1.2:
            pops.append(pop)
    _pops = pops
    queue_redraw()


func _draw() -> void:
    for item in items:
        var at: Vector2 = item["at"]
        var age: float = item["age"]
        var bob := sin(_time * 2.0 + float(item["spin"]) * 3.0) * 0.6
        var fade := clampf((LIFE - age) / 5.0, 0.0, 1.0)
        draw_set_transform(
            at + Vector2(0, bob), float(item["spin"]) + _time * 0.2, Vector2(SCALE, SCALE)
        )
        # NOTE (mristin):
        # A ring of glitter on the water around each treat, so that the
        # players see it from afar.
        var glow := 0.5 + 0.5 * sin(_time * 4.0 + float(item["spin"]))
        draw_arc(Vector2.ZERO, 2.4, 0.0, TAU, 24, Color(1, 1, 0.8, 0.35 * fade * glow), 0.25)
        match item["kind"]:
            "wreath":
                for k in range(8):
                    var leaf := Vector2.RIGHT.rotated(k * TAU / 8.0) * 1.0
                    draw_circle(leaf, 0.45, Color(0.35, 0.6, 0.3, fade))
                for k in range(4):
                    var flower := Vector2.RIGHT.rotated(k * TAU / 4.0 + 0.4) * 1.0
                    draw_circle(
                        flower,
                        0.35,
                        Color(Color("e86a9a"), fade) if k % 2 == 0 else Color(1, 1, 1, fade)
                    )
            "ribbon":
                draw_line(
                    Vector2(-1.2, -0.4), Vector2(1.2, 0.4), Color(Color("b8332a"), fade), 0.45
                )
                draw_line(
                    Vector2(-1.0, 0.6), Vector2(1.0, -0.6), Color(Color("2f5f8a"), fade), 0.45
                )
                draw_circle(Vector2.ZERO, 0.35, Color(Color("f2c14e"), fade))
            "cake":
                draw_circle(Vector2.ZERO, 0.9, Color(Color("c9802a"), fade))
                draw_circle(Vector2.ZERO, 0.6, Color(Color("e8a830"), fade))
                draw_circle(Vector2(0.2, -0.2), 0.2, Color(1, 1, 1, 0.7 * fade))
            "apple":
                draw_circle(Vector2.ZERO, 0.8, Color(Color("c8302c"), fade))
                draw_line(Vector2(0, -0.7), Vector2(0.1, -1.2), Color(Color("5a3a1e"), fade), 0.15)
                draw_circle(Vector2(0.35, -1.1), 0.25, Color(Color("4a8a3a"), fade))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    var font := ThemeDB.fallback_font
    var zoom := get_viewport().get_canvas_transform().get_scale().x
    for pop in _pops:
        var age: float = pop["age"]
        var at: Vector2 = pop["at"] + Vector2(0, -age * 12.0)
        draw_set_transform(
            at,
            -get_viewport().get_canvas_transform().get_rotation(),
            Vector2.ONE / maxf(zoom, 0.01)
        )
        var alpha := 1.0 - age / 1.2
        draw_string_outline(
            font,
            Vector2(-30, 0),
            "+1",
            HORIZONTAL_ALIGNMENT_CENTER,
            60,
            44,
            10,
            Color(0.1, 0.07, 0.03, alpha)
        )
        draw_string(
            font,
            Vector2(-30, 0),
            "+1",
            HORIZONTAL_ALIGNMENT_CENTER,
            60,
            44,
            Color(Color("f2c14e"), alpha)
        )
        draw_circle(Vector2(46, -14), 14.0, Color(Color("d8d8e0"), alpha))
        draw_circle(Vector2(46, -14), 9.0, Color(Color("b8b8c8"), alpha))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
