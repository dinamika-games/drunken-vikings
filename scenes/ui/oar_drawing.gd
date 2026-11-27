class_name OarDrawing
extends RefCounted

## Draw a painted oar as if it moved in three dimensions, seen from above.
##
## A real oar does more than swing around its lock. In the pull, its blade
## stands upright in the water, so that from above one sees only its edge,
## under the water. On the way back, the rower lifts the blade out and turns
## it flat (feathers it), so that one sees it whole, and it throws a shadow on
## the water. The oar is also tilted, so it looks a little shorter.
##
## The painted oar (handle at its left, blade at its right) is drawn in two
## parts, the shaft and the blade, so that the blade can turn on its own.

## How the sun throws the shadows, in the world (down and to the right of the
## screen).
const SUN := Vector2(0.55, 0.85)

## The colour of the water over the blade while it pulls.
const UNDER_WATER := Color(0.55, 0.78, 0.92, 0.7)

## How far the blade tilts down (in the pull) and up (lifted), in radians.
const DIP := 0.2
const RAISE := 0.45

## Where the blade begins in each picture, as a fraction of its width.
static var _blade_starts := {}


## Draw [param picture] on [param canvas] (which draws in [param base]),
## turning around [param lock] by [param angle], [param length] long, the
## lock [param handle] of the length from the handle. [param lift] goes from
## 0 (the blade upright in the water, pulling) to 1 (lifted out and flat).
## With [param inboard_only], only the part from the handle to the lock is
## drawn: the boat draws it again over its hull, so that the oar reaches the
## hands of the rower.
static func draw(
    canvas: CanvasItem,
    picture: Texture2D,
    base: Transform2D,
    lock: Vector2,
    angle: float,
    length: float,
    handle: float,
    lift: float,
    tint := Color.WHITE,
    inboard_only := false
) -> void:
    lift = clampf(lift, 0.0, 1.0)
    var pitch := lerpf(-DIP, RAISE, lift)
    var shorten := cos(pitch)
    var flat := smoothstep(0.05, 0.95, lift)
    # NOTE (mristin):
    # A lifted blade comes closer to the eye, so it looks a little larger.
    var grow := 1.0 + 0.1 * lift

    var width := float(picture.get_width())
    var height := float(picture.get_height())
    var blade_at := blade_start(picture)
    var thick := length * height / width
    var shaft_length := length * blade_at * shorten
    var blade_length := length * (1.0 - blade_at) * shorten * grow
    var start := -handle * length * shorten
    var blade_thick := thick * lerpf(0.3, 1.0, flat) * grow

    var shaft_source := Rect2(0, 0, width * blade_at, height)
    var blade_source := Rect2(width * blade_at, 0, width * (1.0 - blade_at), height)
    var shaft_rect := Rect2(start, -thick / 2.0, shaft_length, thick)
    var blade_rect := Rect2(start + shaft_length, -blade_thick / 2.0, blade_length, blade_thick)

    var turn := Transform2D(angle, lock)
    if inboard_only:
        canvas.draw_set_transform_matrix(base * turn)
        canvas.draw_texture_rect_region(
            picture,
            Rect2(start, -thick / 2.0, -start, thick),
            Rect2(0, 0, width * handle, height),
            tint
        )
        canvas.draw_set_transform_matrix(base)
        return
    if lift > 0.05:
        # The shadow of the outboard part on the water, the further away the
        # higher the blade is.
        var rise := sin(maxf(pitch, 0.0)) * (start + shaft_length + blade_length)
        var to_local := (canvas.get_global_transform() * base * turn).affine_inverse()
        var away := to_local.basis_xform(SUN).normalized() * rise * 0.45
        var shade := Color(0.0, 0.05, 0.15, 0.22 * lift)
        canvas.draw_set_transform_matrix(base * turn * Transform2D(0.0, away))
        canvas.draw_texture_rect_region(picture, shaft_rect, shaft_source, shade)
        canvas.draw_texture_rect_region(picture, blade_rect, blade_source, shade)

    canvas.draw_set_transform_matrix(base * turn)
    canvas.draw_texture_rect_region(picture, shaft_rect, shaft_source, tint)
    var blade_tint := tint
    if lift < 0.3:
        blade_tint = tint * UNDER_WATER.lerp(Color.WHITE, lift / 0.3)
    canvas.draw_texture_rect_region(picture, blade_rect, blade_source, blade_tint)
    canvas.draw_set_transform_matrix(base)


## Where the blade of the oar in [param picture] begins, as a fraction of its
## width: the first column, from the right, where the picture is less than
## half as tall as the blade.
static func blade_start(picture: Texture2D) -> float:
    var key := picture.resource_path
    if _blade_starts.has(key):
        return _blade_starts[key]
    var start := 0.7
    var image := picture.get_image()
    if image != null:
        if image.is_compressed():
            image.decompress()
        var heights := PackedInt32Array()
        heights.resize(image.get_width())
        var tallest := 0
        for x in range(image.get_width()):
            var painted := 0
            for y in range(image.get_height()):
                if image.get_pixel(x, y).a > 0.5:
                    painted += 1
            heights[x] = painted
            tallest = maxi(tallest, painted)
        # NOTE (mristin):
        # The tip of the blade is round, hence short: go from the right into
        # the blade first, then on to where it narrows into the shaft.
        var in_blade := false
        for x in range(image.get_width() - 1, -1, -1):
            if heights[x] >= tallest * 0.8:
                in_blade = true
            elif in_blade and heights[x] < tallest / 2:
                start = float(x + 1) / image.get_width()
                break
    _blade_starts[key] = start
    return start
