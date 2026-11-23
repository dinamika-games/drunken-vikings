extends SceneTree

## Record freely what the vision measures while the players move as they
## like (row, steer, rest), to see afterwards which movements the vision tells
## apart, and to tune the game on them.
##
## [codeblock]
## $GODOT --path . --script dev/rowing/record_rowing.gd -- \
##     [--players=2] [--note=TEXT] [--frames] [<recording.jsonl>]
## [/codeblock]
##
## It needs the camera and a display (not --headless). It starts to record
## as soon as the camera sees the player(s), and stops on Escape. Space marks
## the moment in the recording ("mark" with the name "space"), e.g., to tell
## where something interesting starts.
##
## The vision service records what it measures (see VisionRecorder): only
## numbers, the key points and the signals of the rowing. The recording goes
## to ~/Downloads/rowing_recordings/free-<time>.jsonl by default. Pass
## [code]--note[/code] to describe the session in the recording (e.g., where
## the camera stands, "camera on a chair, 2 m, facing").
##
## The screen shows the camera picture with the skeleton and, on the right,
## the signals over the last seconds, so you see at once what moves with the
## rowing and the steering. dev/rowing/analyze.py studies the recording.
##
## With [code]--frames[/code], it also saves every camera frame as a picture
## into [code]<recording>.frames/[/code] (00001.jpg, ...; each written as a
## "frame" line with its time), to study the session frame by frame offline.
## Only for developing the vision, and only with the consent of the players:
## the game itself never saves the pictures.

## How many seconds the graphs show.
const _HISTORY_SECONDS := 10.0

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _GREY := Color("9aa0ad")
const _RED := Color("ff5a4f")

## The colors of the players.
const _PLAYER_COLORS := [Color("f2c14e"), Color("5ec8f2")]

## The signals to graph, and the least range of each graph, so that noise
## does not look like a movement: [name, least range, what it shows].
const _GRAPHS := [
    ["torso_up", 0.5, "shoulders above hips"],
    ["head_y", 0.1, "head down in picture"],
    ["hands_up", 0.5, "hands above shoulders"],
    ["reach_left", 0.5, "left wrist to shoulder"],
    ["reach_right", 0.5, "right wrist to shoulder"],
    ["elbow_spread", 0.5, "elbows apart"],
    ["hands_side", 0.5, "hands to the right"],
    ["torso_lean", 20.0, "torso lean right, deg"],
    ["shoulder_tilt", 20.0, "shoulder tilt right, deg"],
    ["shoulder_width", 0.3, "shoulder width (twist)"],
    ["head_side", 0.3, "nose to the right"],
]


## The camera picture, mirrored, with the skeletons of the players.
class CameraView:
    extends Control

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

    var service: Node

    func _process(_delta: float) -> void:
        queue_redraw()

    func _draw() -> void:
        draw_rect(Rect2(Vector2.ZERO, size), Color("161a24"))
        if service == null:
            return
        var texture: Texture2D = service.GetCameraTexture()
        if texture != null:
            # NOTE (mristin):
            # The picture is mirrored, so that the players see themselves as
            # in a mirror; a negative width flips it.
            draw_texture_rect(texture, Rect2(Vector2(size.x, 0), Vector2(-size.x, size.y)), false)

        var count: int = service.GetPlayerCount()
        if count > 1:
            draw_dashed_line(
                Vector2(size.x / 2.0, 0), Vector2(size.x / 2.0, size.y), _GREY, 3.0, 12.0
            )

        for player in range(count):
            var points: PackedVector2Array = service.GetKeypoints(player)
            var scores: PackedFloat32Array = service.GetKeypointScores(player)
            if points.size() != 17 or scores.size() != 17:
                continue
            var color: Color = _PLAYER_COLORS[player]
            for bone in _BONES:
                var a: int = bone[0]
                var b: int = bone[1]
                if scores[a] < 0.3 or scores[b] < 0.3:
                    continue
                draw_line(points[a] * size, points[b] * size, color, 5.0)
            for k in range(17):
                var faint := scores[k] < 0.3
                var dot := Color(color, 0.35) if faint else color
                draw_circle(points[k] * size, 7.0, dot)

            var source: String = service.GetPoseSource(player)
            draw_string(
                get_theme_default_font(),
                Vector2(16.0 + (size.x / 2.0) * player, size.y - 16.0),
                "player %d: %s" % [player + 1, source],
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                22,
                color
            )


## The signals of the players over the last seconds, one graph per signal.
class SignalGraphs:
    extends Control

    var service: Node
    var names: PackedStringArray
    ## [player] -> Array of [t, PackedFloat32Array].
    var history: Array = [[], []]
    ## The calls of late: Array of [t, name].
    var calls: Array = []

    func _process(_delta: float) -> void:
        if service == null:
            return
        if names.is_empty():
            names = service.GetSignalNames()
        var now := Time.get_ticks_msec() / 1000.0
        for player in range(2):
            var samples: Array = history[player]
            if player < service.GetPlayerCount() and service.HasPlayer(player):
                samples.append([now, service.GetSignals(player)])
            while not samples.is_empty() and now - samples[0][0] > _HISTORY_SECONDS:
                samples.pop_front()
        while not calls.is_empty() and now - calls[0][0] > _HISTORY_SECONDS:
            calls.pop_front()
        queue_redraw()

    func mark(name: String) -> void:
        calls.append([Time.get_ticks_msec() / 1000.0, name])

    func _draw() -> void:
        if names.is_empty():
            return
        var font := get_theme_default_font()
        var now := Time.get_ticks_msec() / 1000.0
        var row := size.y / _GRAPHS.size()
        for g in range(_GRAPHS.size()):
            var graph: Array = _GRAPHS[g]
            var index := names.find(graph[0])
            if index < 0:
                continue
            var top := g * row
            var box := Rect2(Vector2(0, top + 2), Vector2(size.x, row - 4))
            draw_rect(box, Color(1, 1, 1, 0.05))

            # NOTE (mristin):
            # Each graph scales to the values of all the players, but never to
            # less than its least range.
            var low := INF
            var high := -INF
            for samples in history:
                for sample in samples:
                    var value: float = sample[1][index]
                    if not is_nan(value):
                        low = minf(low, value)
                        high = maxf(high, value)
            if low == INF:
                low = 0.0
                high = 0.0
            var least: float = graph[1]
            if high - low < least:
                var middle := (high + low) / 2.0
                low = middle - least / 2.0
                high = middle + least / 2.0

            for call in calls:
                var x: float = (1.0 - (now - call[0]) / _HISTORY_SECONDS) * size.x
                draw_line(Vector2(x, box.position.y), Vector2(x, box.end.y), Color(_RED, 0.6), 2.0)

            var latest := ""
            for player in range(2):
                var samples: Array = history[player]
                var color: Color = _PLAYER_COLORS[player]
                var previous := Vector2.INF
                for sample in samples:
                    var value: float = sample[1][index]
                    if is_nan(value):
                        previous = Vector2.INF
                        continue
                    var x: float = (1.0 - (now - sample[0]) / _HISTORY_SECONDS) * size.x
                    var y: float = box.end.y - (value - low) / (high - low) * box.size.y
                    var point := Vector2(x, y)
                    if previous != Vector2.INF:
                        draw_line(previous, point, color, 2.5)
                    previous = point
                if not samples.is_empty():
                    var value: float = samples[-1][1][index]
                    latest += ("  %+.2f" % value) if not is_nan(value) else "  ?"

            draw_string(
                font,
                Vector2(6, top + 22),
                "%s%s" % [graph[2], latest],
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                18,
                _PAPER
            )
            draw_string(
                font,
                Vector2(size.x - 70, top + 22),
                "%.2f" % high,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                14,
                _GREY
            )
            draw_string(
                font,
                Vector2(size.x - 70, top + row - 8),
                "%.2f" % low,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                14,
                _GREY
            )


var _service: Node
var _path := ""
var _note := ""
var _frames := false
var _recording := false
var _done := false
var _started_at := 0.0
var _marks := 0
var _space_down := false

var _graphs: SignalGraphs
var _title: Label
var _text: Label
var _status: Label
var _beep: AudioStreamPlayer


func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg == "--frames":
            _frames = true
        elif arg.begins_with("--note="):
            _note = arg.trim_prefix("--note=")
        elif not arg.begins_with("--"):
            _path = arg
    if _path == "":
        _path = (
            "%s/Downloads/rowing_recordings/free-%s.jsonl"
            % [
                OS.get_environment("HOME"),
                Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
            ]
        )
    _build.call_deferred()


func _build() -> void:
    _service = root.get_node("Vision").service
    _service.ResetPlayers()

    var screen := ColorRect.new()
    screen.color = Color("0c0e14")
    screen.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(screen)

    var camera := CameraView.new()
    camera.service = _service
    camera.position = Vector2(20, 90)
    camera.size = Vector2(1200, 900)
    screen.add_child(camera)

    _graphs = SignalGraphs.new()
    _graphs.service = _service
    _graphs.position = Vector2(1240, 300)
    _graphs.size = Vector2(660, 770)
    screen.add_child(_graphs)

    _title = _label(screen, Vector2(20, 16), Vector2(1880, 60), 44, _GOLD)
    _text = _label(screen, Vector2(1240, 90), Vector2(660, 200), 26, _PAPER)
    _text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status = _label(screen, Vector2(20, 1000), Vector2(1200, 70), 20, _GREY)
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

    _beep = AudioStreamPlayer.new()
    _beep.stream = _make_beep()
    root.add_child(_beep)

    _title.text = "Get ready"
    _text.text = (
        "Sit 2 to 3 m from the camera, so that it sees you from your head to your feet. "
        + "The recording starts as soon as the camera sees you."
    )


func _label(parent: Node, at: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.position = at
    label.size = size
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label


## A short beep, so that the player hears the mark even when they look away.
func _make_beep() -> AudioStreamWAV:
    var rate := 22050
    var samples := PackedByteArray()
    var count := int(rate * 0.12)
    samples.resize(count * 2)
    for i in range(count):
        var fade := 1.0 - float(i) / count
        var value := int(sin(TAU * 880.0 * i / rate) * 12000.0 * fade)
        samples.encode_s16(i * 2, value)
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = rate
    stream.data = samples
    return stream


func _start() -> void:
    if not _service.StartRecording(_path, _frames, _note):
        _title.text = "Could not record into %s" % _path
        _done = true
        return
    _recording = true
    _started_at = Time.get_ticks_msec() / 1000.0
    _service.SetRecordingLabel("free")
    _text.text = (
        "Move as you like: row, steer, rest. Press Space to mark a moment, "
        + "and Escape when you are done."
    )
    _beep.play()


func _finish() -> void:
    var lines: int = _service.StopRecording() if _recording else 0
    _recording = false
    _done = true
    _title.text = "Thank you, all done!"
    _text.text = (
        "Recorded %d lines into:\n%s\n\nClose the window, or press Escape." % [lines, _path]
    )
    print("Recorded %d lines into %s" % [lines, _path])


func _all_seen() -> bool:
    if not _service.IsRunning():
        return false
    for player in range(_service.GetPlayerCount()):
        if not _service.HasPlayer(player):
            return false
    return true


func _process(_delta: float) -> bool:
    if Input.is_key_pressed(KEY_ESCAPE):
        if not _done:
            _finish()
        return true
    if _service == null:
        return false

    _update_status()
    if _done:
        return false

    if not _recording:
        if _all_seen():
            _start()
        return false

    var elapsed := int(Time.get_ticks_msec() / 1000.0 - _started_at)
    _title.text = ("Recording   %d:%02d   (%d marks)" % [elapsed / 60, elapsed % 60, _marks])

    var space := Input.is_key_pressed(KEY_SPACE)
    if space and not _space_down:
        _marks += 1
        _service.MarkRecording("space")
        _graphs.mark("space")
        _beep.play()
    _space_down = space
    return false


func _update_status() -> void:
    var status: String = _service.GetStatus()
    var text := "%s %s" % [status, _service.GetStatusMessage()]
    if status == "Running":
        text = (
            "pose %.0f ms, %.0f poses a second, %d player(s)"
            % [_service.GetInferenceMs(), _service.GetPoseRate(), _service.GetPlayerCount()]
        )
    if _recording:
        text += "   recording into %s" % _path
    _status.text = text
