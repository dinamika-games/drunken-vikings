class_name Pictures
extends RefCounted

## The painted pictures of the game (cut by dev/pictures/cut_sheets.py into
## res://assets/pictures/<sheet>/<name>.png), loaded once, and drawn in the
## units of whoever draws them.
##
## Every figure keeps the drawing in code for when a picture is missing.

const ROOT := "res://assets/pictures"

static var _cache := {}


## The picture [param name] of the [param sheet], or null if it is missing.
static func of(sheet: String, name: String) -> Texture2D:
    var key := sheet + "/" + name
    if not _cache.has(key):
        var path := "%s/%s.png" % [ROOT, key]
        _cache[key] = load(path) if ResourceLoader.exists(path) else null
    return _cache[key]


## Whether all the pictures [param names] of the [param sheet] are there.
static func has_all(sheet: String, names: Array) -> bool:
    for name in names:
        if of(sheet, name) == null:
            return false
    return true


## The size of [param picture] when its longer side is [param long_side].
static func size_of(picture: Texture2D, long_side: float) -> Vector2:
    return (
        Vector2(picture.get_size()) * (long_side / maxf(picture.get_width(), picture.get_height()))
    )


## Draw [param picture] on [param canvas], its middle at [param at], its
## longer side [param long_side] long, turned by [param angle] and squeezed
## along its height by [param squeeze]; [param base] is the transform the
## canvas draws in, which is set back afterwards.
static func draw(
    canvas: CanvasItem,
    picture: Texture2D,
    at: Vector2,
    long_side: float,
    angle := 0.0,
    base := Transform2D.IDENTITY,
    tint := Color.WHITE,
    squeeze := 1.0
) -> void:
    var size := size_of(picture, long_side) * Vector2(1.0, squeeze)
    canvas.draw_set_transform_matrix(base * Transform2D(angle, at))
    canvas.draw_texture_rect(picture, Rect2(-size / 2.0, size), false, tint)
    canvas.draw_set_transform_matrix(base)


## Draw the frame [param name] of the [param sheet] (see dev/pictures/) stretched
## over [param rect] (nine-slice): its corners as painted, [param border]
## pixels of the picture on each side, its sides and middle stretched; return
## whether the picture is there.
static func draw_frame(
    canvas: CanvasItem, name: String, rect: Rect2, border: float, tint := Color.WHITE, sheet := "ui"
) -> bool:
    var picture := of(sheet, name)
    if picture == null:
        return false
    var key := "frame/%s/%s/%d" % [sheet, name, int(border)]
    if not _cache.has(key):
        var box := StyleBoxTexture.new()
        box.texture = picture
        box.set_texture_margin_all(border)
        _cache[key] = box
    var box: StyleBoxTexture = _cache[key]
    box.modulate_color = tint
    canvas.draw_style_box(box, rect)
    return true
