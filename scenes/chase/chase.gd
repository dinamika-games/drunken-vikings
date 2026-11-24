extends Node2D

## The chase mode: the pirates hunt the players, who must row from one
## settlement to another before the pirates catch them. Nobody is hurt: the
## pirates who catch the players only laugh, kiss the prow of their boat and
## sail away, and the players try again; the players who make it get silver
## (into the purse of their voyage, see GameState), and the people of the town
## chase the pirates away.
##
## The pirates find their way across the water (see LakeMap.water_path) and
## row a little slower than players who keep rowing: who keeps rowing makes
## it, who stops for long is caught. The players row and steer as everywhere
## (see RowBoat), and choose on the last screen with their hands (see
## ChoicePanel). With [code]-- --no-camera --autopilot[/code], the boat rows
## by itself, to try the chase.

const ZOOM := 6.0
const LOOK_AHEAD := 45.0

## The pirates row this fast, in metres per second (the players who keep
## rowing go about 9).
const PIRATE_SPEED := 7.0

## The pirates set out this many seconds after the players.
const HEAD_START := 5.0

## The pirates catch the players this close, in metres.
const CATCH_DISTANCE := 22.0

## The players are safe this close to the jetty of the target, in metres.
const SAFE_DISTANCE := 35.0

## The pirate captain shakes a fist from this close, in metres.
const SHAKE_DISTANCE := 90.0

## The target lies this far from the start along the water, in metres.
const TARGET_DISTANCE := Vector2(800.0, 1800.0)

## The pirates find their way again every this many seconds.
const REPLAN_SECONDS := 1.0

## The silver for the players who make it.
const REWARD := 10

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _RED := Color("e0402c")
const _INK := Color("0c0e14")

var _map: LakeMap
var _boat := RowBoat.new()
var _rower: RowerView
var _pirates: Longship
var _boat_wake: Wake
var _pirate_wake: Wake
var _splashes: Splashes
var _camera: Camera2D
var _labels: Array[Node2D] = []
var _beacon: Beacon
var _service: Node
var _state: Node
var _rng := RandomNumberGenerator.new()
var _strokes_seen := [0, 0]
var _drip := 0.0

var _start: Dictionary
var _target: Dictionary
var _path := PackedVector2Array()
var _replan := 0.0

## Whether the pirates may sail straight to their goal (see _hunt).
var _straight := false
var _elapsed := 0.0
var _outcome := ""

## Where the pirates wait at the start.
var _pirate_start := Vector2.ZERO

var _hud: CanvasLayer
var _banner: Label
var _info: Label
var _overlay: ChaseOverlay
var _panel: ChoicePanel
var _actions: Array[Callable] = []

var _autopilot := false
var _autopilot_beat := 0.0
var _autopilot_strokes := 0


func _ready() -> void:
    EscapeGuard.attach(self, _leave)
    _autopilot = "--autopilot" in OS.get_cmdline_user_args()
    _rng.seed = Time.get_ticks_usec()
    _state = get_node_or_null("/root/GameState")
    if _state != null and not _state.load_voyage():
        _state.new_voyage()
    var vision := get_node_or_null("/root/Vision")
    if vision != null:
        _service = vision.service
        _strokes_seen = [_service.GetStrokes(0), _service.GetStrokes(1)]

    _map = LakeMap.new()
    add_child(_map)
    var error := _map.load_map(GameState.MAP_PATH)
    if error != "":
        push_error(error)
        return
    _choose_places()

    _splashes = Splashes.new()
    add_child(_splashes)
    _boat_wake = Wake.new()
    _boat_wake.width = 2.5
    _boat_wake.spread = 8.0
    add_child(_boat_wake)
    _pirate_wake = Wake.new()
    _pirate_wake.width = 6.0
    _pirate_wake.spread = 16.0
    add_child(_pirate_wake)

    _beacon = Beacon.new()
    _beacon.position = _target["jetty"]
    add_child(_beacon)

    _pirates = Longship.new()
    _pirates.pirate = true
    _pirates.map = _map
    add_child(_pirates)

    _rower = RowerView.new()
    _rower.boat = _boat
    _rower.map = _map
    _rower.pair = players() == 2
    add_child(_rower)

    for place in _map.places:
        if place["kind"] != "healer":
            var mark := MapLabel.new()
            mark.text = place["name"]
            mark.kind = "village"
            mark.position = place["at"]
            add_child(mark)
            _labels.append(mark)

    _boat.position = _start["berth"]
    var out: Vector2 = (_start["jetty"] - _start["at"]).normalized()
    _boat.heading = out.angle() + PI / 2.0
    _boat.speed = 2.0

    _camera = Camera2D.new()
    _camera.zoom = Vector2(ZOOM, ZOOM)
    _camera.ignore_rotation = false
    add_child(_camera)
    _camera.make_current()
    _camera.rotation = _boat.heading
    _camera.position = _boat.position + Vector2.UP.rotated(_boat.heading) * LOOK_AHEAD

    _build_hud()


## Choose where the players start, where they row to, and where the pirates
## wait: the target far enough along the water, the pirates behind the
## players.
func _choose_places() -> void:
    var pairs: Array = []
    for a in _map.places:
        for b in _map.places:
            if a["id"] == b["id"]:
                continue
            var length := _length(_map.route_between(a["id"], b["id"]))
            if length >= TARGET_DISTANCE.x and length <= TARGET_DISTANCE.y:
                pairs.append([a, b])
    if pairs.is_empty():
        pairs.append([_map.places[0], _map.places[1]])
    var pair: Array = pairs[_rng.randi() % pairs.size()]
    _start = pair[0]
    _target = pair[1]

    # NOTE (mristin):
    # The pirates wait in a cove behind the players: a point on the water
    # some 250 m from the start, as far from the target as can be.
    var best := Vector2.INF
    var best_score := -INF
    for i in range(48):
        var angle := TAU * i / 48.0
        var spot: Vector2 = _start["jetty"] + Vector2.RIGHT.rotated(angle) * 250.0
        if not _map.is_water(spot):
            continue
        var path := _map.water_path(spot, _start["jetty"])
        if path.is_empty() or _length(path) > 450.0:
            continue
        var score := spot.distance_to(_target["jetty"])
        if score > best_score:
            best_score = score
            best = spot
    if best == Vector2.INF:
        best = _start["jetty"] + (_start["jetty"] - _target["jetty"]).normalized() * 200.0
    _pirate_start = best


static func _length(points: PackedVector2Array) -> float:
    var total := 0.0
    for i in range(1, points.size()):
        total += points[i - 1].distance_to(points[i])
    return total


func _build_hud() -> void:
    _pirates.position = _pirate_start
    _pirates.heading = (_start["jetty"] - _pirate_start).angle() + PI / 2.0
    _pirates.rotation = _pirates.heading

    _hud = CanvasLayer.new()
    add_child(_hud)
    _overlay = ChaseOverlay.new()
    _overlay.chase = self
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud.add_child(_overlay)
    _banner = _label(Vector2(0, 20), Vector2(1920, 60), 40, _GOLD)
    _banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _info = _label(Vector2(30, 960), Vector2(1200, 100), 26, _PAPER)
    var camera_panel := CameraPanel.new()
    camera_panel.service = _service
    camera_panel.position = Vector2(1560, 790)
    camera_panel.size = Vector2(340, 255)
    _hud.add_child(camera_panel)
    _panel = ChoicePanel.new(_service)
    _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel.visible = false
    _panel.chosen.connect(_on_chosen)
    _hud.add_child(_panel)


func _label(at: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.position = at
    label.size = size
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_outline_color", _INK)
    label.add_theme_constant_override("outline_size", 10)
    _hud.add_child(label)
    return label


## Escape twice ends the journey: save, and back to the first screen.
func _leave() -> void:
    if _state != null:
        _state.save()
    get_tree().change_scene_to_file("res://scenes/start/start.tscn")


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _quit()


func _quit() -> void:
    if _service != null:
        _service.Shutdown()
    get_tree().quit()


## How many row: as the journey says (see GameState.players).
func players() -> int:
    if _state != null:
        return _state.players
    return _service.GetPlayerCount() if _service != null else 1


func boat() -> RowBoat:
    return _boat


func pirates() -> Longship:
    return _pirates


func target() -> Dictionary:
    return _target


func outcome() -> String:
    return _outcome


func to_screen(point: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform() * point


func _process(delta: float) -> void:
    if _map == null or _target.is_empty():
        return
    if _outcome == "":
        _elapsed += delta
        _boat.brake = _read_brake()
        _read_strokes()
        _boat.steer = _read_steer()
        if _autopilot:
            _fly(delta)
    else:
        _boat.steer = 0.0
        _boat.brake = false
        _skip_strokes()
    _boat.move(delta, _map)
    _rower.position = _boat.position
    _rower.rotation = _boat.heading
    _rower.live_pull = _live_pull()
    _boat_wake.follow(_boat.position, delta, absf(_boat.speed))
    _hunt(delta)
    _pirate_wake.follow(_pirates.position, delta, _pirates.speed)
    _splash_oars(delta)
    _check_outcome()
    _place_camera(delta)
    for label in _labels:
        label.rotation = _camera.rotation
    _update_hud()


## The pirates find their way to the players and row after them; once the
## chase is over, they sail off.
func _hunt(delta: float) -> void:
    var goal := _boat.position
    var speed := PIRATE_SPEED
    if _elapsed < HEAD_START and _outcome == "":
        speed = 0.0
    if _outcome != "":
        # NOTE (mristin):
        # Caught or escaped, the pirates sail off, away from the players.
        goal = _pirate_start
        speed = PIRATE_SPEED * 0.6
    _replan -= delta
    if _replan <= 0.0:
        _replan = REPLAN_SECONDS
        var found := _map.water_path(_pirates.position, goal)
        if not found.is_empty():
            _path = found
        _straight = (
            _pirates.position.distance_to(goal) < 60.0
            and not _map.crosses_land(_pirates.position, goal)
        )
    # NOTE (mristin):
    # The pirates only ever sail along their way over the water; straight to
    # the goal only when it is near and no land lies between.
    var aim := _pirates.position
    if _straight:
        aim = goal
    else:
        for point in _path:
            if point.distance_to(_pirates.position) > 12.0:
                aim = point
                break
    _pirates.drive(delta, aim, speed)


func _check_outcome() -> void:
    # NOTE (mristin):
    # The pirate captain shakes a fist at the players when close: funny, harmless.
    _pirates.shaking = _boat.position.distance_to(_pirates.position) < SHAKE_DISTANCE
    if _outcome != "":
        return
    if _boat.position.distance_to(_target["jetty"]) < SAFE_DISTANCE:
        _outcome = "escaped"
        _replan = 0.0
        if _state != null:
            _state.silver += REWARD
            _state.save()
        print("Escaped to %s in %.0f s" % [_target["name"], _elapsed])
        _show_end(
            "You made it!",
            (
                (
                    "You reached %s before the pirates! The people of %s chase the pirates "
                    + "away, and give you %d silver."
                )
                % [_target["name"], _target["name"], REWARD]
            )
        )
    elif _elapsed > HEAD_START and _boat.position.distance_to(_pirates.position) < CATCH_DISTANCE:
        _outcome = "caught"
        _replan = 0.0
        _boat.speed = 0.0
        print("Caught after %.0f s" % _elapsed)
        _show_end(
            "Caught!",
            (
                "The pirates caught you! They laugh, kiss the prow of your boat, "
                + "and sail away. Try again?"
            )
        )


func _show_end(title: String, text: String) -> void:
    var cards: Array = [
        {"title": "Another chase!", "detail": ""},
        {"title": "To the start", "detail": "other games"},
        {"title": "Stop for today", "detail": "see you!"},
    ]
    _actions = [get_tree().reload_current_scene, _to_start, _quit]
    _panel.show_cards(
        title, text, cards, {"hair": Color("e8c25a"), "braids": true, "picture": "ylva"}
    )


func _to_start() -> void:
    get_tree().change_scene_to_file("res://scenes/start/start.tscn")


func _on_chosen(index: int) -> void:
    if index >= 0 and index < _actions.size():
        _actions[index].call()


func _update_hud() -> void:
    var gap := _boat.position.distance_to(_pirates.position)
    var to_go := _boat.position.distance_to(_target["jetty"])
    if _outcome != "":
        _banner.text = "You made it!" if _outcome == "escaped" else "Caught!"
        return
    if _elapsed < HEAD_START:
        _banner.text = "Pirates! Row to %s before they catch you!" % _target["name"]
    elif gap < 80.0:
        _banner.text = "The pirates are right behind you! Row, row!"
    else:
        _banner.text = "Row to %s!" % _target["name"]
    _info.text = (
        "%s: %d m to go.   The pirates: %d m behind you." % [_target["name"], int(to_go), int(gap)]
    )


# ---------------------------------------------------------------------------
# Rowing, as in the other modes
# ---------------------------------------------------------------------------


func _read_steer() -> float:
    if _service != null and _service.IsRunning() and players() == 1:
        return _service.GetSteer(0)
    return 0.0


## Whether the players brake: any of them raised both hands above the head.
func _read_brake() -> bool:
    if _service == null or not _service.IsRunning():
        return false
    for player in range(players()):
        if _service.GetBrake(player):
            return true
    return false


func _read_strokes() -> void:
    if _service == null:
        return
    for player in range(players()):
        var strokes: int = _service.GetStrokes(player)
        while _strokes_seen[player] < strokes:
            _strokes_seen[player] += 1
            var depth: float = _service.GetLastStrokeDepth(player)
            if players() == 2:
                _boat.stroke_side(player, depth)
            else:
                _boat.stroke(depth)


func _skip_strokes() -> void:
    if _service != null:
        _strokes_seen = [_service.GetStrokes(0), _service.GetStrokes(1)]


func _live_pull() -> Array:
    if _service == null or not _service.IsRunning():
        return [-1.0, -1.0]
    if players() == 2:
        return [_service.GetPull(0), _service.GetPull(1)]
    var pull: float = _service.GetPull(0)
    return [pull, pull]


func _splash_oars(delta: float) -> void:
    _drip += delta
    var drip := _drip >= 0.12
    if drip:
        _drip = 0.0
    for side in [0, 1]:
        var blade := _rower.blade_position(side)
        if _rower.catches[side]:
            _splashes.splash(blade, 5.0, 1.6, 1.0)
        elif _rower.pulling[side] and drip:
            _splashes.splash(blade, 2.5, 0.9, 0.6)
        elif _rower.holding(side) and drip:
            # NOTE (mristin):
            # Holding water: the blade drags, and the water swirls around it.
            _splashes.splash(blade, 2.0 + 3.0 * clampf(_boat.speed / 6.0, 0.0, 1.0), 1.1, 0.7)
    if _pirates.dipped:
        for blade in _pirates.blade_positions():
            _splashes.splash(blade, 4.0, 1.3, 0.5)


func _place_camera(delta: float) -> void:
    var weight := 1.0 - exp(-delta / 1.2)
    _camera.rotation = lerp_angle(_camera.rotation, _boat.heading, weight)
    var goal := _boat.position + Vector2.UP.rotated(_camera.rotation) * LOOK_AHEAD
    _camera.position = _camera.position.lerp(goal, 1.0 - exp(-delta / 0.25))


## Row to the target along the water, a stroke every 2.3 s.
func _fly(delta: float) -> void:
    _autopilot_beat += delta
    var path := _map.water_path(_boat.position, _target["jetty"])
    var aim: Vector2 = _target["jetty"]
    for point in path:
        if point.distance_to(_boat.position) > 25.0:
            aim = point
            break
    var wanted := (aim - _boat.position).angle() + PI / 2.0
    _boat.steer = clampf(angle_difference(_boat.heading, wanted) * 2.0, -1.0, 1.0)
    if _autopilot_beat >= 2.3:
        _autopilot_beat = 0.0
        _boat.stroke()
        _autopilot_strokes += 1
        if _autopilot_strokes % 5 == 0:
            print(
                (
                    "  rowing to %s: %.0f m to go, speed %.1f, pirates %.0f m behind"
                    % [
                        _target["name"],
                        _boat.position.distance_to(_target["jetty"]),
                        _boat.speed,
                        _boat.position.distance_to(_pirates.position)
                    ]
                )
            )


## The jetty of the target: a golden ring which pulses, so that the players
## see where to row.
class Beacon:
    extends Node2D

    var _time := 0.0

    func _process(delta: float) -> void:
        _time += delta
        queue_redraw()

    func _draw() -> void:
        var pulse := 0.5 + 0.5 * sin(_time * 3.0)
        draw_arc(Vector2.ZERO, 18.0 + 6.0 * pulse, 0.0, TAU, 48, Color(1.0, 0.85, 0.3, 0.8), 2.5)
        draw_arc(Vector2.ZERO, 30.0 + 10.0 * pulse, 0.0, TAU, 48, Color(1.0, 0.85, 0.3, 0.35), 2.0)


## The arrows to the target and to the pirates, and the red glow of danger.
class ChaseOverlay:
    extends Control

    var chase: Node

    func _process(_delta: float) -> void:
        queue_redraw()

    func _draw() -> void:
        if chase == null or chase.target().is_empty():
            return
        var boat: RowBoat = chase.boat()
        var pirates: Longship = chase.pirates()
        var gap := boat.position.distance_to(pirates.position)
        if chase.outcome() == "" and gap < 120.0:
            # NOTE (mristin):
            # The edges of the screen glow red as the pirates come closer.
            var alpha := clampf((120.0 - gap) / 100.0, 0.0, 1.0) * 0.35
            for k in range(6):
                var inset := k * 14.0
                draw_rect(
                    Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0),
                    Color(0.9, 0.15, 0.1, alpha * (1.0 - k / 6.0)),
                    false,
                    14.0
                )
        _arrow(chase.to_screen(chase.target()["jetty"]), Color("f2c14e"))
        _arrow(chase.to_screen(pirates.position), Color("e0402c"))

    ## An arrow at the edge of the screen towards [param at], when it is out of sight.
    func _arrow(at: Vector2, color: Color) -> void:
        var screen := Rect2(Vector2.ZERO, size).grow(-70.0)
        if screen.has_point(at):
            return
        var center := size / 2.0
        var direction := (at - center).normalized()
        var t := INF
        for axis in [0, 1]:
            if absf(direction[axis]) > 1e-6:
                var limit: float = (
                    screen.end[axis] if direction[axis] > 0 else screen.position[axis]
                )
                t = minf(t, (limit - center[axis]) / direction[axis])
        var tip := center + direction * t
        var side := direction.orthogonal()
        var triangle := PackedVector2Array(
            [tip, tip - direction * 44.0 + side * 24.0, tip - direction * 44.0 - side * 24.0]
        )
        draw_colored_polygon(triangle, color)
        triangle.append(tip)
        draw_polyline(triangle, Color("0c0e14"), 3.0)
