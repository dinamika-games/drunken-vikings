class_name CameraPanel
extends Control

## The camera picture, mirrored (as the players see themselves in a mirror),
## with the players dressed up as Ylva (see [DressUp]), or with their
## skeletons: where the dress is not painted, for the rowing experiment, or
## with [code]-- --skeleton[/code].

const _BONES := [
    [5, 6],
    [5, 7],
    [7, 9],
    [6, 8],
    [8, 10],
    [5, 11],
    [6, 12],
    [11, 12],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
    [0, 1],
    [0, 2],
    [1, 3],
    [2, 4],
]

## The colors of the players.
const PLAYER_COLORS := [Color("f2c14e"), Color("5ec8f2")]

## The vision service (see VisionService).
var service: Node

## Whether to draw the skeletons.
var show_skeleton := "--skeleton" in OS.get_cmdline_user_args()

## Whether to dress the players up (if the dress is painted).
var dress_up := true

var _dress := DressUp.new()
var _time := 0.0


func _init() -> void:
    # NOTE (mristin):
    # The dress follows the body, also where it leaves the picture (e.g., the
    # skirt below it): show only what lies within the camera picture.
    clip_contents = true


## The fists of the dress go on the hands: the hand detector runs while the
## camera picture shows.
func _enter_tree() -> void:
    if service != null and dress_up and DressUp.available():
        service.SetHandsForPicture(true)


func _exit_tree() -> void:
    if service != null:
        service.SetHandsForPicture(false)


func _process(delta: float) -> void:
    _time += delta
    if service != null and dress_up and DressUp.available():
        for player in range(service.GetPlayerCount()):
            _dress.observe(
                player,
                service.GetKeypoints(player),
                service.GetKeypointScores(player),
                service.GetHands(),
                size,
                delta,
                _time
            )
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("161a24"))
    if service == null:
        return
    var texture: Texture2D = service.GetCameraTexture()
    if texture != null:
        # NOTE (mristin):
        # We mirror the picture with the transform: a rectangle of a negative
        # width is not drawn by the compatibility renderer.
        draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
        draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    var count: int = service.GetPlayerCount()
    if count > 1:
        draw_dashed_line(
            Vector2(size.x / 2.0, 0), Vector2(size.x / 2.0, size.y), Color("9aa0ad"), 2.0, 10.0
        )
    var dressed := dress_up and DressUp.available()
    if dressed:
        for player in range(count):
            _dress.draw(self, player, service.GetPull(player))
    if dressed and not show_skeleton:
        return
    var width := maxf(2.0, size.x / 240.0)
    for player in range(count):
        var points: PackedVector2Array = service.GetKeypoints(player)
        var scores: PackedFloat32Array = service.GetKeypointScores(player)
        if points.size() != 17 or scores.size() != 17:
            continue
        var color: Color = PLAYER_COLORS[player]
        for bone in _BONES:
            var a: int = bone[0]
            var b: int = bone[1]
            if scores[a] < 0.3 or scores[b] < 0.3:
                continue
            draw_line(points[a] * size, points[b] * size, color, width)
        for k in range(17):
            var dot := Color(color, 0.35) if scores[k] < 0.3 else color
            draw_circle(points[k] * size, width * 1.4, dot)
