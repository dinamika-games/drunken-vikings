extends Node2D

## The party mode, for the smaller children: the players row their small
## boat through the lakes behind the wedding longship, from their farm to the
## market village. The wedding party drops flower wreaths, ribbons, honey
## cakes and apples into the water (see [Treats]); every one the players pick
## up gives them a silver coin, into the purse of their voyage (see
## GameState). The longship waits for the players, and nobody is ever lost.
##
## Each stroke of the players pushes the boat, which glides on (see
## RowingMeter). Alone, the player steers by leaning to the side (the head
## and the shoulders, see RowingMeter); two players pull an oar each (the
## player on the left of the mirrored picture the left one), and the boat
## turns away from the stronger rower (see RowBoat). Start with
## [code]-- --players=2[/code] for two players. The players play only with
## their bodies, never with the keyboard. The view turns with the boat,
## so that the bow always points up and going left turns left.
##
## Once the longship is in the market village, the players choose with
## their hands (see ChoicePanel): another party, the farm, or stop. Escape twice
## ends the journey (see EscapeGuard).
##
## With [code]-- --autopilot[/code], the boat rows and steers by itself along
## the route, to try the level without the camera (e.g., to render it). With
## [code]-- --record[/code], the vision records what it measures while the
## players row (only numbers, see VisionRecorder) into
## ~/Downloads/rowing_recordings/level-<time>.jsonl, to study it with
## dev/rowing/analyze.py. With [code]-- --log-pose[/code] (see Vision), the
## party prints into the log, along with the poses and on the same clock,
## where the boat and the longship are and where the nearest treats lie from
## the boat, and every drop and pick, so that we can study where the player
## meant to go (see [method _log_party]).

## How many pixels a metre takes on the screen.
const ZOOM := 6.0

## With --log-pose, print this many of the nearest treats.
const LOG_TREATS := 3

## The camera looks this far ahead of the boat, in metres, so that the
## players see where they go.
const LOOK_AHEAD := 45.0

## The wedding party drops a treat every this many seconds (at random within).
const DROP_EVERY := Vector2(4.0, 7.0)

## The treats fall this far to the side of the longship's wake, in metres,
## each one on the other side than the one before, so that the players row a
## gentle slalom from one treat to the next.
const DROP_SIDEWAYS := Vector2(4.0, 10.0)

## The level is done when the boat comes this close to the end of the route
## after the viking ship arrived, in metres.
const FINISH_DISTANCE := 90.0

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _INK := Color("0c0e14")

## The map of the level, made by dev/maps/make_lakes.py.
@export var map_path := GameState.MAP_PATH

var _map: LakeMap
var _boat := RowBoat.new()
var _rower: RowerView
var _ship: Longship
var _boat_wake: Wake
var _splashes: Splashes
var _drip := 0.0
var _ship_wake: Wake
var _camera: Camera2D
var _labels: Array[Node2D] = []
var _service: Node
## The strokes of each player which the boat got already.
var _strokes_seen := [0, 0]
var _elapsed := 0.0
var _done := false
var _treats: Treats
var _drop_left := 1.0
## The side of the wake where the next treat falls (1 or -1).
var _drop_side := 1.0
var _coins := 0
var _rng := RandomNumberGenerator.new()
var _state: Node
var _panel: ChoicePanel
var _actions: Array[Callable] = []
var _autopilot := false
## With --log-pose, print the party every this many seconds; 0 prints nothing.
var _log_every := 0.0
var _logged_at := -INF
var _autopilot_beat := 0.0

var _hud: CanvasLayer
var _banner: Label
var _info: Label
var _overlay: Control


func _ready() -> void:
    EscapeGuard.attach(self, _leave)
    Audio.music("party")
    Audio.ambient("water")
    Audio.play("horn")
    _autopilot = "--autopilot" in OS.get_cmdline_user_args()
    _rng.seed = Time.get_ticks_usec()
    _state = get_node_or_null("/root/GameState")
    if _state != null and not _state.load_voyage():
        _state.new_voyage()
    var vision := get_node_or_null("/root/Vision")
    if vision != null:
        _service = vision.service
        _strokes_seen = [_service.GetStrokes(0), _service.GetStrokes(1)]
        var rate: float = _service.LogPoseRate
        if rate > 0.0:
            _log_every = 1.0 / rate
        if "--record" in OS.get_cmdline_user_args():
            var path := (
                "%s/Downloads/rowing_recordings/level-%s.jsonl"
                % [
                    OS.get_environment("HOME"),
                    Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
                ]
            )
            if _service.StartRecording(path, false, "level"):
                print("Recording into %s" % path)

    _map = LakeMap.new()
    add_child(_map)
    var error := _map.load_map(map_path)
    if error != "":
        push_error(error)
        return

    _splashes = Splashes.new()
    add_child(_splashes)

    _boat_wake = Wake.new()
    _boat_wake.width = 2.5
    _boat_wake.spread = 8.0
    add_child(_boat_wake)
    _ship_wake = Wake.new()
    _ship_wake.width = 6.0
    _ship_wake.spread = 16.0
    add_child(_ship_wake)

    _treats = Treats.new()
    add_child(_treats)

    _ship = Longship.new()
    _ship.wedding = true
    _ship.map = _map
    _ship.progress = 80.0
    var course := _map.route_point(95.0) - _map.route_point(80.0)
    _ship.heading = course.angle() + PI / 2.0
    _ship.position = _map.route_point(80.0)
    _ship.rotation = _ship.heading
    add_child(_ship)

    _boat.position = _map.route_point(0.0)
    var ahead := _map.route_point(20.0) - _boat.position
    _boat.heading = ahead.angle() + PI / 2.0
    _rower = RowerView.new()
    _rower.boat = _boat
    _rower.map = _map
    _rower.pair = players() == 2
    add_child(_rower)

    for label in _map.labels:
        if label["kind"] == "village":
            continue
        var mark := MapLabel.new()
        mark.text = label["name"]
        mark.kind = label["kind"]
        mark.position = label["at"]
        add_child(mark)
        _labels.append(mark)
    for village in [_map.start, _map.goal]:
        var mark := MapLabel.new()
        mark.text = village["name"]
        mark.kind = "village"
        mark.position = village["at"]
        add_child(mark)
        _labels.append(mark)

    _camera = Camera2D.new()
    _camera.zoom = Vector2(ZOOM, ZOOM)
    _camera.ignore_rotation = false
    _camera.position_smoothing_enabled = false
    add_child(_camera)
    _camera.make_current()

    _build_hud()
    _camera.rotation = _boat.heading
    _camera.position = _boat.position + Vector2.UP.rotated(_boat.heading) * LOOK_AHEAD


func _build_hud() -> void:
    _hud = CanvasLayer.new()
    add_child(_hud)

    _overlay = HudOverlay.new()
    _overlay.level = self
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud.add_child(_overlay)

    _banner = _label(Vector2(0, 20), Vector2(1920, 60), 40, _GOLD)
    _banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _info = _label(Vector2(30, 960), Vector2(900, 100), 24, _PAPER)

    _panel = ChoicePanel.new(_service)
    _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel.visible = false
    _panel.chosen.connect(_on_chosen)
    _hud.add_child(_panel)

    var panel := CameraPanel.new()
    panel.service = _service
    panel.position = Vector2(1560, 790)
    panel.size = Vector2(340, 255)
    _hud.add_child(panel)


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


## Closing the window saves, too (the treats picked up so far stay in the purse).
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if _state != null:
            _state.save()
        _quit()


## Stop the camera first, so that no camera frame arrives while the game shuts down.
func _quit() -> void:
    if _service != null:
        _service.Shutdown()
    get_tree().quit()


## How many players row: two pull an oar each.
## How many row: as the journey says (see GameState.players).
func players() -> int:
    if _state != null:
        return _state.players
    return _service.GetPlayerCount() if _service != null else 1


## The steering, from the head of the player; with two players, nobody steers
## with the head (the boat turns away from the stronger rower).
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
    var pair := players() == 2
    for player in range(players()):
        var strokes: int = _service.GetStrokes(player)
        while _strokes_seen[player] < strokes:
            _strokes_seen[player] += 1
            if _done:
                continue
            var depth: float = _service.GetLastStrokeDepth(player)
            if pair:
                _boat.stroke_side(player, depth)
            else:
                _boat.stroke(depth)


func _process(delta: float) -> void:
    if _map == null or _map.route.is_empty():
        return
    _boat.brake = _read_brake()
    _read_strokes()
    _boat.steer = _read_steer()
    if _autopilot:
        _fly(delta)
    if not _done:
        _elapsed += delta
    _boat.move(delta, _map)
    _rower.position = _boat.position
    _rower.rotation = _boat.heading
    _rower.live_pull = _live_pull()
    _boat_wake.follow(_boat.position, delta, absf(_boat.speed))

    var progress := _map.route_progress(_boat.position)
    _ship.sail(delta, progress)
    _splash_oars(delta)
    _ship_wake.follow(_ship.position, delta, _ship.speed)

    _drop_treats(delta)
    var picked := _treats.pick(_boat.position)
    if picked > 0:
        Audio.play("pickup")
        Audio.play("coin")
        _coins += picked
        if _state != null:
            _state.silver += picked
        if _log_every > 0.0:
            print(
                (
                    "Party: t=%.2f picked=%d coins=%d boat=(%.1f,%.1f)"
                    % [_now(), picked, _coins, _boat.position.x, _boat.position.y]
                )
            )

    if not _done and _ship.arrived and _boat.position.distance_to(_map.route[-1]) < FINISH_DISTANCE:
        _done = true
        print("Done: %d strokes in %.0f s, %d coins" % [_boat.strokes, _elapsed, _coins])
        _finish()

    if _log_every > 0.0 and _now() - _logged_at >= _log_every:
        _logged_at = _now()
        _log_party()

    _place_camera(delta)
    for label in _labels:
        label.rotation = _camera.rotation
    _update_hud(progress)


## Splash where the oars dip in: a big splash at the start of each pull, and
## small swirls behind the blades while they pull; and the oars of the
## longship, at each beat of its crew.
func _splash_oars(delta: float) -> void:
    _drip += delta
    var drip := _drip >= 0.12
    if drip:
        _drip = 0.0
    if _rower.catches[0] or _rower.catches[1]:
        Audio.play("oar")
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
    if _ship.dipped:
        for blade in _ship.blade_positions():
            _splashes.splash(blade, 4.0, 1.3, 0.5)


## Row a stroke every few seconds, and steer to a point of the route ahead:
## alone with the head, as a pair with an extra stroke on the side away from
## the turn.
func _fly(delta: float) -> void:
    _autopilot_beat += delta
    var target := _map.route_point(_map.route_progress(_boat.position) + 60.0)
    # NOTE (mristin):
    # Go for a treat close ahead.
    for item in _treats.items:
        var at: Vector2 = item["at"]
        if (
            at.distance_to(_boat.position) < 50.0
            and (at - _boat.position).dot(_boat.forward()) > 0.0
        ):
            target = at
            break
    var wanted := (target - _boat.position).angle() + PI / 2.0
    var turn := clampf(angle_difference(_boat.heading, wanted) * 2.0, -1.0, 1.0)
    if players() == 2:
        if _autopilot_beat >= 2.6 and not _done:
            _autopilot_beat = 0.0
            _boat.stroke_side(0)
            _boat.stroke_side(1)
        elif (
            absf(turn) > 0.3
            and _autopilot_beat >= 1.3
            and _boat.since_side[0] > 1.0
            and _boat.since_side[1] > 1.0
        ):
            # NOTE (mristin):
            # To turn right, the left oar pulls (and the other way round).
            _boat.stroke_side(0 if turn > 0.0 else 1)
        return
    if _autopilot_beat >= 2.6 and not _done:
        _autopilot_beat = 0.0
        _boat.stroke()
    _boat.steer = turn


## How far each oar's player is through the stroke, from the vision (see
## RowerView.live_pull): alone, the player pulls both oars.
func _live_pull() -> Array:
    if _service == null or not _service.IsRunning():
        return [-1.0, -1.0]
    if players() == 2:
        return [_service.GetPull(0), _service.GetPull(1)]
    var pull: float = _service.GetPull(0)
    return [pull, pull]


func _place_camera(delta: float) -> void:
    # NOTE (mristin):
    # The view follows the turn of the boat a bit late, so that the players
    # see the boat turn first.
    var weight := 1.0 - exp(-delta / 1.2)
    _camera.rotation = lerp_angle(_camera.rotation, _boat.heading, weight)
    var target := _boat.position + Vector2.UP.rotated(_camera.rotation) * LOOK_AHEAD
    _camera.position = _camera.position.lerp(target, 1.0 - exp(-delta / 0.25))


## The wedding party drops a treat now and then, to the side of the wake.
func _drop_treats(delta: float) -> void:
    if _done or _ship.arrived:
        return
    _drop_left -= delta
    if _drop_left > 0.0:
        return
    _drop_left = _rng.randf_range(DROP_EVERY.x, DROP_EVERY.y)
    var back := Vector2.DOWN.rotated(_ship.heading)
    # NOTE (mristin):
    # The sides take turns, so that the treats lie in a slalom: one to the
    # left and one to the right of the wake all at once is too sharp a turn.
    _drop_side = -_drop_side
    var side := back.orthogonal() * _drop_side
    var spot: Vector2 = (
        _ship.position + back * 24.0 + side * _rng.randf_range(DROP_SIDEWAYS.x, DROP_SIDEWAYS.y)
    )
    # NOTE (mristin):
    # Only on the water, never on the shore.
    if _map.is_water(spot) and not _map.crosses_land(_ship.position, spot):
        _treats.drop(spot, _rng)
        if _log_every > 0.0:
            var seen := _from_boat(spot)
            print(
                (
                    "Party: t=%.2f drop=(%.1f,%.1f) side=%+d ahead=%.1f right=%.1f bearing=%+.0f"
                    % [_now(), spot.x, spot.y, int(_drop_side), seen.x, seen.y, seen.z]
                )
            )


## The time on the clock of the vision (as the poses in the log), in seconds.
func _now() -> float:
    return _service.Now if _service != null else Time.get_ticks_msec() / 1000.0


## Where [param at] lies from the boat: x metres ahead, y metres to the right,
## and z the bearing in degrees (positive to the right, 0 straight ahead).
func _from_boat(at: Vector2) -> Vector3:
    var ahead_dir := _boat.forward()
    var right_dir := ahead_dir.rotated(PI / 2.0)
    var rel := at - _boat.position
    var ahead := rel.dot(ahead_dir)
    var right := rel.dot(right_dir)
    return Vector3(ahead, right, rad_to_deg(atan2(right, ahead)))


## Print one line about the party, e.g.:
## [code]Party: t=12.34 boat=(10.0,-200.0) heading=+12 speed=4.2 steer=+0.30
## strokes=7 ship=(15.0,-290.0) ship_ahead=88.0 coins=2 treats=5
## next=[(31.0,+6.0,+11),(70.0,-8.0,-7)][/code], where [code]next[/code] are
## the nearest treats as (metres ahead, metres to the right, bearing in
## degrees), nearest first.
func _log_party() -> void:
    var near: Array = []
    for item in _treats.items:
        near.append(_from_boat(item["at"]))
    near.sort_custom(
        func(a: Vector3, b: Vector3) -> bool: return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y
    )
    var parts: PackedStringArray = []
    for seen in near.slice(0, LOG_TREATS):
        parts.append("(%.1f,%+.1f,%+.0f)" % [seen.x, seen.y, seen.z])
    print(
        (
            (
                "Party: t=%.2f boat=(%.1f,%.1f) heading=%+.0f speed=%.1f steer=%+.2f strokes=%d"
                % [
                    _now(),
                    _boat.position.x,
                    _boat.position.y,
                    rad_to_deg(wrapf(_boat.heading, -PI, PI)),
                    _boat.speed,
                    _boat.steer,
                    _boat.strokes
                ]
            )
            + (
                " ship=(%.1f,%.1f) ship_ahead=%.1f coins=%d treats=%d next=[%s]"
                % [
                    _ship.position.x,
                    _ship.position.y,
                    _from_boat(_ship.position).x,
                    _coins,
                    _treats.items.size(),
                    ",".join(parts)
                ]
            )
        )
    )


## The party is over: the coins go into the voyage, and the players choose
## what next with their hands.
func _finish() -> void:
    Audio.play("hooray")
    if _state != null:
        _state.save()
    var cards: Array = [
        ChoicePanel.card("Another party!"),
        ChoicePanel.card("To the farm", ChoicePanel.detail("trade and farm")),
        ChoicePanel.card("Stop for today", ChoicePanel.detail("see you!")),
    ]
    _actions = [get_tree().reload_current_scene, _to_farm, _quit]
    _panel.show_cards(
        Grammar.text("What a wedding!"),
        Grammar.text(
            (
                "The wedding party is in {place}. You picked up {count} {count|thing|things} "
                + "from the water: {count} silver {count|coin|coins} for your purse!"
            ),
            {"place": _map.goal["name"], "count": _coins}
        ),
        cards,
        {"hair": Color("e8c25a"), "braids": true, "picture": "ylva"}
    )


func _to_farm() -> void:
    get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_chosen(index: int) -> void:
    if index >= 0 and index < _actions.size():
        _actions[index].call()


func _update_hud(progress: float) -> void:
    var goal: String = _map.goal["name"]
    if _done:
        _banner.text = Grammar.text("What a wedding!")
        _info.text = Grammar.text("{count} silver {count|coin|coins}!", {"count": _coins})
    else:
        if _ship.arrived:
            _banner.text = Grammar.text(
                "The wedding party is in {place}. Row to the jetty!", {"place": goal}
            )
        elif _ship.waiting:
            _banner.text = Grammar.text("The wedding longship waits for you. Row!")
        else:
            _banner.text = Grammar.text(
                "Follow the wedding to {place}, and pick up what falls into the water!",
                {"place": goal}
            )
        _info.text = (
            Grammar.text(
                "Strokes: {strokes}    {time}",
                {
                    "strokes": _boat.strokes,
                    "time": Grammar.raw("%d:%02d" % [int(_elapsed) / 60, int(_elapsed) % 60])
                }
            )
            + "\n"
            + (
                Grammar.text("Row in time to go straight; the stronger rower turns the boat.")
                if players() == 2
                else Grammar.text(
                    "Row: lean back and forth.   Steer: go to the side with your head."
                )
            )
        )
    _overlay.progress = progress / maxf(_map.route_length(), 1.0)
    _overlay.ship_progress = _ship.progress / maxf(_map.route_length(), 1.0)
    _overlay.queue_redraw()


## Where a point of the world is on the screen.
func to_screen(point: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform() * point


func map() -> LakeMap:
    return _map


func boat() -> RowBoat:
    return _boat


func ship() -> Longship:
    return _ship


## How many coins the players picked up.
func coins() -> int:
    return _coins


func steer() -> float:
    return _boat.steer


func service() -> Node:
    return _service


func camera_rotation() -> float:
    return _camera.rotation
