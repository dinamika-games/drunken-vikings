extends SceneTree

## Draw the dress of Ylva (see DressUp) over the poses of a recording of the
## vision (only the key points, no camera picture), at the given times, into
## PNGs, to see how the dress sits without sitting in front of the camera:
##
##   $GODOT --path . --script dev/pictures/preview_dress.gd -- \
##       <recording.jsonl> <out dir> <t> [<t> ...] [--reach] [--skeleton]
##
## With --reach, the fists reach forward (the start of a stroke), else they
## are pulled to the chest. With --skeleton, the key points are drawn, too.

const SIZE := Vector2(640, 480)

const BONES := [
    [5, 6], [5, 7], [7, 9], [6, 8], [8, 10], [5, 11], [6, 12], [11, 12], [11, 13], [12, 14]
]

var _canvas: Control
var _dress := DressUp.new()
var _points := PackedVector2Array()
var _scores := PackedFloat32Array()
var _skeleton := false
var _pull := 1.0


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    var args := OS.get_cmdline_user_args()
    _skeleton = "--skeleton" in args
    _pull = 0.1 if "--reach" in args else 1.0
    var rest: Array = []
    for arg in args:
        if not arg.begins_with("--"):
            rest.append(arg)
    if rest.size() < 3 or not DressUp.available():
        push_error("Usage: <recording.jsonl> <out dir> <t> [<t> ...]; and cut the dress first.")
        quit(1)
        return
    var poses := _load(rest[0])
    DirAccess.make_dir_recursive_absolute(rest[1])

    root.size = Vector2i(SIZE)
    _canvas = Control.new()
    _canvas.size = SIZE
    _canvas.clip_contents = true
    _canvas.draw.connect(_draw)
    root.add_child(_canvas)
    DisplayServer.window_set_size(Vector2i(SIZE))
    # NOTE (mristin):
    # The first frames come before the window is ready: wait them out.
    for _i in range(5):
        await process_frame

    for t_text in rest.slice(2):
        var t := float(t_text)
        var pose: Dictionary = poses[0]
        for candidate in poses:
            if absf(float(candidate["t"]) - t) < absf(float(pose["t"]) - t):
                pose = candidate
        _set_pose(pose)
        _dress.observe(0, _points, _scores, PackedVector2Array(), SIZE, 10.0, t)
        _canvas.queue_redraw()
        await process_frame
        await process_frame
        var path := "%s/dress_%06.2f.png" % [rest[1], t]
        root.get_texture().get_image().save_png(path)
        print("Wrote %s (the pose at %.2f s)" % [path, float(pose["t"])])
    quit(0)


## The poses of the first player in the recording: Array of {"t", "keypoints", "width", "height"}.
func _load(path: String) -> Array:
    var poses: Array = []
    var width := 640.0
    var height := 480.0
    for line in FileAccess.get_file_as_string(path).split("\n"):
        var parsed: Variant = JSON.parse_string(line)
        if not parsed is Dictionary:
            continue
        if parsed["kind"] == "start":
            width = float(parsed["width"])
            height = float(parsed["height"])
        elif parsed["kind"] == "pose":
            var players: Array = parsed["players"]
            if not players.is_empty() and players[0] != null:
                poses.append(
                    {
                        "t": parsed["t"],
                        "keypoints": players[0]["keypoints"],
                        "width": width,
                        "height": height
                    }
                )
    return poses


## Mirror the key points of the pose and normalize them, as VisionService.GetKeypoints.
func _set_pose(pose: Dictionary) -> void:
    var k: Array = pose["keypoints"]
    _points = PackedVector2Array()
    _scores = PackedFloat32Array()
    for i in range(17):
        _points.append(
            Vector2(
                1.0 - float(k[3 * i]) / float(pose["width"]),
                float(k[3 * i + 1]) / float(pose["height"])
            )
        )
        _scores.append(float(k[3 * i + 2]))


func _draw() -> void:
    _canvas.draw_rect(Rect2(Vector2.ZERO, SIZE), Color("3a4a5c"))
    _dress.draw(_canvas, 0, _pull)
    if not _skeleton:
        return
    for bone in BONES:
        if _scores[bone[0]] >= 0.3 and _scores[bone[1]] >= 0.3:
            _canvas.draw_line(
                _points[bone[0]] * SIZE, _points[bone[1]] * SIZE, Color(1, 1, 0, 0.6), 2.0
            )
    for i in range(17):
        if _scores[i] >= 0.3:
            _canvas.draw_circle(_points[i] * SIZE, 3.0, Color(1, 1, 0, 0.8))
