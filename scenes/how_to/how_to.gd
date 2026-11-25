class_name HowTo
extends Control

## How to play, as in our other games (Bird Dog, The Steppe Rescue): the
## parts of data/how_to/how_to.json, one after the other, again and again,
## until a hand holds the card Ready! (or Escape is pressed).
##
## Behind it all, the players see themselves in the camera, dimly and
## mirrored, as behind every screen of choices, so that their raised hand lies
## under the glove (see HandCursor). On the left, the players in the camera
## picture, drawn as they should sit (see HowToFigure): they row, lean to steer, raise both hands to
## brake, or one hand to choose. On the right, what it does: the boat of the
## game, rowed by the same strokes (see RowBoat, RowerView), a jetty where it
## glides to a stop, or a card which the glove chooses. A title and a line say
## what to do; the dots at the bottom show the part.
##
## The parts for one rower show how to steer by leaning; those for two rowers
## how to row together and turn with the oars (see [member players]).
##
## dev/how_to/make_svgs.py draws the parts into SVGs, from the same data.

signal done

const DATA_PATH := "res://data/how_to/how_to.json"

## The painting of the start screen, dimmed behind, and the room behind the
## rowers in the camera picture.
const PAINTING := "res://assets/pictures/start/start.jpg"
const BACKDROP := "res://assets/pictures/how_to/backdrop.jpg"

## The camera picture and the lakes (or the card), on the screen.
const FRAME := Rect2(110, 300, 720, 540)
const PANEL := Rect2(1090, 300, 720, 540)

## How far the camera of the lakes looks ahead of the boat, in metres, and
## its zoom (as on the lakes, see world.gd).
const LOOK_AHEAD := 12.0
const ZOOM := 9.0

## The beads of the parts (see dots.gdshader): each this wide, in a row at
## this height, in pixels.
const DOTS_SHADER := preload("res://scenes/how_to/dots.gdshader")
const DOT := 60.0
const DOTS_Y := 920.0

## How far the water reaches around the boat, in metres.
const WATER := 200.0

## How long the hands take to rise, and the body to lean, in seconds.
const RISE := 0.4
const LEAN := 0.8

const _GOLD := Color("f2c14e")
const _PAPER := Color("f1e6cc")
const _INK := Color(0.05, 0.07, 0.1, 0.85)
const _ROOM := Color("2c3440")

## How many row: 1 or 2 (set before adding the screen).
var players := 1

## The parts shown (for [member players]), and the part now.
var parts: Array = []
var part := 0

## The seconds into the part now.
var time := 0.0

## The boat of the lakes, and how often the card was chosen (for the tests).
var boat := RowBoat.new()
var chosen := 0

var _map := LakeMap.new()
var _rower: RowerView
var _wake: Wake
var _lake: _Lake
var _camera: Camera2D
var _view: SubViewportContainer
var _ready_button: DwellButton
var _strokes := {}
var _lean := [0.0, 0.0]
var _painting: Texture2D
var _backdrop: Texture2D
var _camera_picture: _Picture
var _hands: HandCursor
var _water: Polygon2D
var _dots: ColorRect
var _beads := 0.0
var _service: Node

## The glove over the card, and how far its rope ring is full.
var _cursor := Vector2.ZERO
var _progress := 0.0
var _chose := false


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    size = get_viewport_rect().size
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    for item in data["parts"] if data is Dictionary else []:
        if float(players) in item["players"]:
            parts.append(item)
    if ResourceLoader.exists(PAINTING):
        _painting = load(PAINTING)
    if ResourceLoader.exists(BACKDROP):
        _backdrop = load(BACKDROP)
    _map.visible = false
    _map.water = [
        {
            "outer":
            PackedVector2Array(
                [Vector2(-1e5, -1e5), Vector2(1e5, -1e5), Vector2(1e5, 1e5), Vector2(-1e5, 1e5)]
            ),
            "holes": []
        }
    ]
    _build_lakes()
    _dots = ColorRect.new()
    var beads := ShaderMaterial.new()
    beads.shader = DOTS_SHADER
    beads.set_shader_parameter("count", parts.size())
    _dots.material = beads
    _dots.size = Vector2(DOT * parts.size(), DOT)
    _dots.position = Vector2((size.x - _dots.size.x) / 2.0, DOTS_Y - DOT / 2.0)
    _dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_dots)
    _camera_picture = _Picture.new()
    _camera_picture.how = self
    _camera_picture.position = FRAME.position
    _camera_picture.size = FRAME.size
    _camera_picture.clip_contents = true
    _camera_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_camera_picture)
    _ready_button = DwellButton.new()
    _ready_button.card = {"title": "Ready!", "detail": "let's row", "picture": ["icons", "row"]}
    _ready_button.position = Vector2(1560, 1076.0 - DwellButton.SIZE.y)
    _ready_button.size = DwellButton.SIZE
    _ready_button.pressed.connect(func() -> void: done.emit())
    add_child(_ready_button)
    _hands = HandCursor.new()
    add_child(_hands)
    # NOTE: The hand detector runs only while a screen asks for the hands.
    var vision := get_node_or_null("/root/Vision")
    _service = vision.service if vision != null else null
    if _service != null:
        _service.SetHandTracking(true)
    _start_part(0)


func _exit_tree() -> void:
    if _service != null:
        _service.SetHandTracking(false)


func _build_lakes() -> void:
    _view = SubViewportContainer.new()
    _view.position = PANEL.position
    _view.size = PANEL.size
    _view.stretch = true
    _view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_view)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(PANEL.size)
    viewport.disable_3d = true
    viewport.handle_input_locally = false
    _view.add_child(viewport)
    viewport.add_child(_map)
    # NOTE: The water of the lakes, as on the lakes (see LakeMap); its
    # polygon follows the boat in metres, so that the waves stay put.
    _water = Polygon2D.new()
    var water := ShaderMaterial.new()
    water.shader = LakeMap.WATER_SHADER
    _water.material = water
    viewport.add_child(_water)
    _lake = _Lake.new()
    _lake.boat = boat
    viewport.add_child(_lake)
    _wake = Wake.new()
    _wake.width = 2.5
    _wake.spread = 8.0
    viewport.add_child(_wake)
    _rower = RowerView.new()
    _rower.boat = boat
    _rower.pair = players == 2
    viewport.add_child(_rower)
    _camera = Camera2D.new()
    _camera.zoom = Vector2(ZOOM, ZOOM)
    _camera.ignore_rotation = false
    viewport.add_child(_camera)
    _camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
            get_viewport().set_input_as_handled()
            done.emit()


func _process(delta: float) -> void:
    advance(delta)


## Play the screen on by [param delta] seconds.
func advance(delta: float) -> void:
    if parts.is_empty():
        return
    time += delta
    if time >= float(parts[part]["seconds"]):
        _start_part((part + 1) % parts.size())
    _steer(parts[part], time)
    var before := boat.strokes
    _row(parts[part], time)
    if boat.strokes > before:
        Audio.play("oar")
    boat.move(delta, _map)
    _rower.position = boat.position
    _rower.rotation = boat.heading
    _rower.live_pull = _pulls(parts[part], time)
    _wake.follow(boat.position, delta, absf(boat.speed))
    _choose(parts[part], time)
    _camera.rotation = boat.heading
    _camera.position = boat.position + Vector2.UP.rotated(boat.heading) * LOOK_AHEAD
    _lake.queue_redraw()
    _camera_picture.queue_redraw()
    _water.polygon = PackedVector2Array(
        [
            boat.position + Vector2(-WATER, -WATER),
            boat.position + Vector2(WATER, -WATER),
            boat.position + Vector2(WATER, WATER),
            boat.position + Vector2(-WATER, WATER),
        ]
    )
    _beads += delta
    var dots := _dots.material as ShaderMaterial
    dots.set_shader_parameter("current", float(part))
    dots.set_shader_parameter("progress", time / float(parts[part]["seconds"]))
    dots.set_shader_parameter("time", _beads)
    queue_redraw()


## Start the part of the [param index]: the boat starts afresh at rest (or
## glides on, with "keep_boat"), and the jetty waits where it will stop.
func _start_part(index: int) -> void:
    part = index
    time = 0.0
    _strokes.clear()
    _chose = false
    var data: Dictionary = parts[part]
    if not bool(data.get("keep_boat", false)):
        boat.position = Vector2.ZERO
        boat.heading = 0.0
        boat.speed = 0.0
        boat.yaw_rate = 0.0
        _wake.queue_free()
        _wake = Wake.new()
        _wake.width = 2.5
        _wake.spread = 8.0
        _lake.add_sibling(_wake)
    boat.brake = false
    boat.steer = 0.0
    _lake.jetty = _where_it_stops(data) if data["panel"] == "jetty" else Transform2D()
    _view.visible = data["panel"] != "card"


## Where the boat stops in the [param data] of a part: play it ahead with a
## copy of the boat.
func _where_it_stops(data: Dictionary) -> Transform2D:
    var saved := _strokes.duplicate()
    var copy := RowBoat.new()
    copy.position = boat.position
    copy.heading = boat.heading
    copy.speed = boat.speed
    var real := boat
    boat = copy
    var step := 1.0 / 60.0
    var t := 0.0
    while t < float(data["seconds"]):
        _steer(data, t)
        _row(data, t)
        boat.move(step, _map)
        t += step
    boat = real
    _strokes = saved
    return Transform2D(copy.heading, copy.position)


## The moves of the [param data] at the [param t] for the rower [param who].
func _moves(data: Dictionary, t: float, who: int) -> Array:
    var result: Array = []
    for move in data["moves"]:
        var for_who := int(move.get("who", -1))
        if (for_who == -1 or for_who == who) and t >= float(move["from"]) and t < float(move["to"]):
            result.append(move)
    return result


## The glove comes to the card as the hand rises, the rope ring fills, and
## the card is chosen once.
func _choose(data: Dictionary, t: float) -> void:
    _cursor = PANEL.position + Vector2(PANEL.size.x * 0.85, PANEL.size.y * 0.9)
    _progress = 0.0
    for move in _moves(data, t, 0):
        if move["do"] != "point":
            continue
        var since := t - float(move["from"])
        # NOTE: The glove rests on the lower right of the card, so that its
        # picture and its title show.
        var card := PANEL.get_center() + Vector2(70, 50)
        _cursor = _cursor.lerp(card, smoothstep(0.0, 1.0, since / 0.8))
        _progress = clampf((since - 0.8) / DwellButton.DWELL_SECONDS, 0.0, 1.0)
        if _progress >= 1.0 and not _chose:
            _chose = true
            chosen += 1
            Audio.play("click")


## How far the [param move] is along at [param t], eased in over [param
## seconds].
## How far the rower leans in the [param move] at [param t]: she leans in
## over [constant LEAN] seconds, and sits up again over the last ones.
static func _leaning(move: Dictionary, t: float) -> float:
    return minf(
        smoothstep(0.0, 1.0, (t - float(move["from"])) / LEAN),
        smoothstep(0.0, 1.0, (float(move["to"]) - t) / LEAN)
    )


static func _eased(move: Dictionary, t: float, seconds: float) -> float:
    return smoothstep(0.0, 1.0, (t - float(move["from"])) / seconds)


## Lean and brake: what the moves of the [param data] do to the boat at [param t].
func _steer(data: Dictionary, t: float) -> void:
    boat.steer = 0.0
    boat.brake = false
    for move in _moves(data, t, 0):
        match move["do"]:
            "lean":
                boat.steer = float(move["side"]) * _leaning(move, t)
            "brake":
                boat.brake = true


## Row the strokes of the moves of the [param data] up to [param t]: a stroke
## at the end of each period, when the rower comes forward again.
func _row(data: Dictionary, t: float) -> void:
    for who in range(players):
        for move in _moves(data, t, who):
            if move["do"] != "row":
                continue
            var count := floori((t - float(move["from"])) / float(move["period"]))
            var key := "%s|%d" % [str(move), who]
            while int(_strokes.get(key, 0)) < count:
                _strokes[key] = int(_strokes.get(key, 0)) + 1
                if players == 2:
                    boat.stroke_side(who)
                else:
                    boat.stroke()


## How far each rower leans back now (see RowerView.live_pull), -1 if not rowing.
func _pulls(data: Dictionary, t: float) -> Array:
    var pulls := [-1.0, -1.0]
    for who in range(players):
        var pose := pose(data, t, who)
        if pose["hands"] == "oar":
            pulls[who] = pose["lean"]
    if players == 1:
        pulls[1] = pulls[0]
    return pulls


## The pose of the rower [param who] in the [param data] at [param t] (see
## HowToFigure.joints).
func pose(data: Dictionary, t: float, who: int) -> Dictionary:
    var result := {"lean": 0.0, "tilt": 0.0, "hands": "rest", "up": 0.0}
    for move in _moves(data, t, who):
        match move["do"]:
            "row":
                var phase := (t - float(move["from"])) / float(move["period"])
                result["hands"] = "oar"
                result["lean"] = 0.5 - 0.5 * cos(TAU * phase)
            "lean":
                result["hands"] = "oar"
                result["lean"] = 0.15
                result["tilt"] = float(move["side"]) * _leaning(move, t)
            "brake":
                result["hands"] = "up"
                result["up"] = _eased(move, t, RISE)
            "point":
                result["hands"] = "point"
                result["up"] = _eased(move, t, RISE * 2.0)
                # NOTE: The card is to the right of the picture: the hand
                # goes up and to the right.
                var height := FRAME.size.y * (1.0 if players == 1 else 0.92)
                result["target"] = Vector2(_center(who) + 0.3 * height, 0.24 * height)
    return result


func _draw() -> void:
    if _painting != null:
        draw_texture_rect(_painting, Rect2(Vector2.ZERO, size), false, Color(0.35, 0.35, 0.4))
    else:
        draw_rect(Rect2(Vector2.ZERO, size), Color("1f3a5a"))
    # NOTE (mristin):
    # As behind every screen of choices (see ChoicePanel): the players see
    # themselves, mirrored, so that their raised hand lies under the glove.
    if _hands != null:
        _hands.draw_mirror(self, size)
    if parts.is_empty():
        return
    var data: Dictionary = parts[part]
    var font := ThemeDB.fallback_font
    _outlined(font, Vector2(0, 100), "How to play: " + str(data["title"]), 56, _GOLD)
    var lines := ChoicePanel.wrap_text(font, str(data["text"]), 1600.0, 34)
    for i in range(lines.size()):
        _outlined(font, Vector2(0, 165 + i * 44), lines[i], 34, _PAPER)
    _draw_frame()
    if data["panel"] == "card":
        _draw_card()
    _draw_border(PANEL, "The lakes" if data["panel"] != "card" else "The screens")


func _outlined(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
    draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 8, _INK)
    draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


## The players in the camera picture, mirrored.
## The border of the camera picture (the picture itself is [member _camera]).
func _draw_frame() -> void:
    _draw_border(FRAME, "You, in the camera" if players == 1 else "You two, in the camera")


## The camera picture: the room, and the players in it, mirrored; clipped to
## the frame, so that raised hands go no higher than the picture.
func draw_camera(canvas: Control) -> void:
    if _backdrop != null:
        canvas.draw_texture_rect(_backdrop, Rect2(Vector2.ZERO, FRAME.size), false)
    else:
        canvas.draw_rect(Rect2(Vector2.ZERO, FRAME.size), _ROOM)
    if parts.is_empty():
        return
    var data: Dictionary = parts[part]
    for who in range(players):
        var scale := 1.0 if players == 1 else 0.92
        HowToFigure.draw(canvas, _center(who), FRAME.size.y * scale, pose(data, time, who), who)


## Where the rower [param who] sits across the camera picture, in pixels.
func _center(who: int) -> float:
    if players == 1:
        return FRAME.size.x / 2.0
    return FRAME.size.x * (0.27 if who == 0 else 0.73)


func _draw_border(rect: Rect2, label: String) -> void:
    draw_rect(rect.grow(6.0), Color("6a4320"), false, 12.0)
    var font := ThemeDB.fallback_font
    draw_string_outline(
        font, rect.position + Vector2(0, -18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, _INK
    )
    draw_string(
        font, rect.position + Vector2(0, -18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, _PAPER
    )


## A card of the screens which the raised hand chooses: the glove comes to it,
## the rope ring fills, and the card glows.
func _draw_card() -> void:
    draw_rect(PANEL, Color("1b2230"))
    var card := Rect2(PANEL.get_center() - DwellButton.SIZE / 2.0, DwellButton.SIZE)
    var progress := _progress
    var cursor := _cursor
    var lit := progress > 0.0
    if not Pictures.draw_frame(
        self,
        "card_chosen" if lit else "card",
        card.grow(14.0 if lit else 0.0),
        44.0 if lit else 30.0
    ):
        draw_rect(card, _PAPER)
    # NOTE (mristin):
    # Laid out as DwellButton lays out its cards.
    var coins := Pictures.of("goods", "ale")
    if coins != null:
        var at := DwellButton.picture_rect(coins, card.size)
        draw_texture_rect(coins, Rect2(card.position + at.position, at.size), false)
    var font := ThemeDB.fallback_font
    draw_string(
        font,
        card.position + Vector2(0, DwellButton.TITLE_BELOW_PICTURE),
        "Sell",
        HORIZONTAL_ALIGNMENT_CENTER,
        card.size.x,
        DwellButton.TITLE_SIZES[0],
        Color("2a1e14")
    )
    if progress > 0.0:
        draw_arc(cursor, 54.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, _GOLD, 10.0)
    var glove := Pictures.of("ui", "glove")
    if glove != null:
        Pictures.draw(self, glove, cursor, 72.0)
    else:
        draw_circle(cursor, 20.0, _PAPER)


## The camera picture (see [method HowTo.draw_camera]).
class _Picture:
    extends Control

    var how: HowTo

    func _draw() -> void:
        how.draw_camera(self)


## The jetty where the boat docks, and the shore behind it (over the water).
class _Lake:
    extends Node2D

    ## Where the jetty and the shore lie ahead of the boat where it stops, in
    ## metres: the end of the jetty this far ahead of the middle of the boat
    ## (clear of its bow), the jetty this long (and as wide as painted, about
    ## a third), its root under the reeds of the shore by this much, and the
    ## shore (its reeds on the water, then the grass) this deep.
    const JETTY_GAP := 6.0
    const JETTY_LENGTH := 26.0
    const SHORE_OVERLAP := 2.0
    const SHORE_WIDTH := 16.0

    static var _grass_color := Color.TRANSPARENT

    ## The boat, and where it stops at the jetty (identity: no jetty).
    var boat: RowBoat
    var jetty := Transform2D()

    ## The colour of the grass at the inner edge of the painted [param shore],
    ## to fill the land behind it.
    static func _grass(shore: Texture2D) -> Color:
        if _grass_color == Color.TRANSPARENT:
            var image := shore.get_image()
            image.decompress()
            var sum := Color(0, 0, 0, 0)
            var count := 0
            for y in range(0, image.get_height(), 4):
                for x in range(int(image.get_width() * 0.7), int(image.get_width() * 0.8)):
                    var pixel := image.get_pixel(x, y)
                    if pixel.a > 0.9:
                        sum += pixel
                        count += 1
            _grass_color = Color(sum / maxf(1.0, count), 1.0)
        return _grass_color

    func _draw() -> void:
        if jetty == Transform2D():
            return
        # NOTE (mristin):
        # As on the lakes, the boat docks at the end of the jetty, in line with
        # it (see LakeMap.BERTH): the jetty lies ahead of the bow, the shore
        # across beyond it, so that the oars, out to the sides, never touch
        # them. Drawn turned so that "ahead" is along x.
        draw_set_transform_matrix(jetty * Transform2D(-PI / 2.0, Vector2.ZERO))
        var shore := Pictures.of("how_to", "shore")
        var pier := Pictures.of("how_to", "jetty")
        var land := JETTY_GAP + JETTY_LENGTH - SHORE_OVERLAP
        if shore != null and pier != null:
            var width := SHORE_WIDTH
            var tile := width * shore.get_height() / shore.get_width()
            draw_rect(Rect2(land + width * 0.85, -80, 100, 160), _grass(shore))
            # NOTE: The tiles overlap a little: their ends are not quite opaque.
            var y := -80.0
            while y < 80.0:
                draw_texture_rect(shore, Rect2(land, y, width, tile), false)
                y += tile * 0.96
            var thick := JETTY_LENGTH * pier.get_height() / pier.get_width()
            draw_texture_rect(pier, Rect2(JETTY_GAP, -thick / 2.0, JETTY_LENGTH, thick), false)
        else:
            draw_rect(Rect2(land, -80, 100, 160), Color("5d6b3a"))
            draw_rect(Rect2(land, -80, 3, 160), Color("c9b98a"))
            draw_rect(Rect2(JETTY_GAP, -2.5, JETTY_LENGTH, 5), Color("8a6a40"))
            for k in range(int(JETTY_LENGTH / 1.6)):
                var u := JETTY_GAP + 0.8 + k * 1.6
                draw_line(Vector2(u, -2.5), Vector2(u, 2.5), Color("5a3a1e"), 0.2)
        draw_set_transform_matrix(Transform2D())
