extends Node2D

## The open world of a region: the players row their boat across the lakes,
## dock at the jetties of the settlements to trade, meet the skippers of the
## boats on the lakes (news and quick offers), and come home to the farm,
## where a night's sleep ends the day (see DESIGN.md).
##
## The players row and choose only with their bodies (see HandCursor and RowingMeter); the
## keyboard is never used, but Escape twice ends the journey (see EscapeGuard),
## and C shows the map of the region (see WorldChart), while the game waits.
## Start with [code]-- --players=2[/code]
## for two players (an oar each), [code]-- --new[/code] for a new voyage, and
## [code]-- --autopilot[/code] to let the boat trade by itself (to try the
## world without the camera). For the developers, [code]-- --shots=<dir>[/code]
## saves a screenshot every 20 seconds and whenever a screen opens.

const ZOOM := 6.0
const LOOK_AHEAD := 45.0

## The boat docks when it glides this close to a jetty, this slowly.
const DOCK_DISTANCE := 30.0
const DOCK_SPEED := 3.5

## After leaving a jetty, the boat docks there again only once it was this far
## from it, in metres: the boat leaves slowly from the berth, within reach of
## the jetty, and must not dock again at once.
##
## NOTE (mristin):
## Keep this only a little beyond [constant DOCK_DISTANCE]. A single stroke
## carries the boat some 60 m; the players who row out a stroke, turn and
## come back (e.g., they forgot to load the boat) must be able to dock again,
## and not row to another place first.
const UNDOCK_DISTANCE := DOCK_DISTANCE + 10.0

## A skipper hails the players when they glide this close, this slowly.
const HAIL_DISTANCE := 40.0
const HAIL_SPEED := 4.0

## Seconds before a skipper hails the players again.
const HAIL_COOLDOWN := 90.0

## How many boats sail the lakes.
const NPC_COUNT := 9

## The gulls cry now and then on the lakes, every this many seconds at random.
const GULLS_EVERY := Vector2(25.0, 70.0)

## The painted pictures of the cards which show no good, animal or crop (see
## dev/pictures/: the sheet "icons"), by their titles, so that the children
## who can not read yet see what a card does.
const CARD_ICONS := {
    "Sell": "sell",
    "Buy": "buy",
    "Animals": "animals",
    "Shipyard": "shipyard",
    "Talk": "talk",
    "Row on": "row",
    "Row out": "row",
    "Tasks": "tasks",
    "More": "more",
    "Go on": "more",
    "Back": "back",
    "Thank you!": "thanks",
    "The farm": "farm",
    "Unload the boat": "unload",
    "Load from the store": "load",
    "Sleep": "sleep",
    "Plant": "plant",
    "Harvest": "harvest",
    "Buy land": "buy_land",
    "Stop for today": "stop",
    "Yes, I will help!": "help",
    "Not now": "not_now",
}

var _map: LakeMap
var _boat := RowBoat.new()
var _rower: RowerView
## The ship under the players, when they row a bigger one than the rowing
## boat (see [method refit]); null in the rowing boat.
var _ship_view: Longship
## Where the players sit on the ship, behind its middle, in metres.
var _stern := 0.0
var _boat_wake: Wake
var _splashes: Splashes
var _camera: Camera2D
var _npcs: Array[NpcBoat] = []
var _labels: Array[Node2D] = []
var _service: Node
var _state: Node
var _strokes_seen := [0, 0]
var _drip := 0.0
var _rng := RandomNumberGenerator.new()

var _screens: PortScreens
var _hud: WorldHud
var _panel: ChoicePanel
var _farm_view: FarmView
var _arrows: TaskArrows
var _chart_layer: CanvasLayer
var _chart: WorldChart
var _actions: Array[Callable] = []
var _mode := "rowing"
var _left_place := ""
var _talking_to: NpcBoat
var _toast := ""
var _toast_left := 0.0
var _gulls_left := 10.0

var _autopilot := false
var _autopilot_target := ""
var _autopilot_beat := 0.0
var _autopilot_wait := 0.0
var _autopilot_steps := 0
## Where the autopilot bought last (it does not sell there what it bought).
var _autopilot_bought := ""
## Where the autopilot set out from.
var _autopilot_from := "home"
var _autopilot_log := 0.0

var _shots := ""
var _shot_clock := 0.0
var _shot_count := 0


func _ready() -> void:
    EscapeGuard.attach(self, _leave)
    _rng.seed = Time.get_ticks_usec()
    _autopilot = "--autopilot" in OS.get_cmdline_user_args()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--shots="):
            _shots = arg.trim_prefix("--shots=")
            DirAccess.make_dir_recursive_absolute(_shots)
    _state = get_node("/root/GameState")
    if "--new" in OS.get_cmdline_user_args() or not _state.load_voyage():
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
    _add_shipyard()

    _splashes = Splashes.new()
    add_child(_splashes)
    _boat_wake = Wake.new()
    _boat_wake.width = 2.5
    _boat_wake.spread = 8.0
    add_child(_boat_wake)

    for i in range(NPC_COUNT):
        var npc := NpcBoat.new()
        var start: Dictionary = _map.places[(i * 3 + 1) % _map.places.size()]
        npc.setup(_map, start["id"], Gossip.skipper(i), 1000 + i)
        npc.cooldown = 20.0
        npc.players = _boat
        add_child(npc)
        _npcs.append(npc)

    _rower = RowerView.new()
    _rower.boat = _boat
    _rower.map = _map
    _rower.pair = players() == 2
    add_child(_rower)
    refit()

    for label in _map.labels:
        if label["kind"] == "place":
            continue
        _add_label(label["name"], label["kind"], label["at"])
    for place in _map.places:
        if place["kind"] != "healer":
            _add_label(place["name"], "village", place["at"])

    _camera = Camera2D.new()
    _camera.zoom = Vector2(ZOOM, ZOOM)
    _camera.ignore_rotation = false
    add_child(_camera)
    _camera.make_current()

    var layer := CanvasLayer.new()
    add_child(layer)
    _hud = WorldHud.new()
    _hud.world = self
    _hud.set_anchors_preset(Control.PRESET_FULL_RECT)
    layer.add_child(_hud)
    _arrows = TaskArrows.new()
    _arrows.world = self
    _arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
    layer.add_child(_arrows)
    var camera_panel := CameraPanel.new()
    camera_panel.service = _service
    camera_panel.position = Vector2(1560, 790)
    camera_panel.size = Vector2(340, 255)
    layer.add_child(camera_panel)
    _farm_view = FarmView.new()
    _farm_view.set_anchors_preset(Control.PRESET_FULL_RECT)
    _farm_view.visible = false
    layer.add_child(_farm_view)
    _panel = ChoicePanel.new(_service)
    _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel.visible = false
    _panel.chosen.connect(_on_chosen)
    layer.add_child(_panel)

    _chart_layer = CanvasLayer.new()
    _chart_layer.layer = 50
    add_child(_chart_layer)

    _screens = PortScreens.new(self, _state, _map)
    _undock(_state.place)
    _camera.rotation = _boat.heading
    _camera.position = _boat.position + Vector2.UP.rotated(_boat.heading) * LOOK_AHEAD
    Audio.ambient("water")
    _say("Day %d. Row to the settlements to trade; glide slowly to a jetty to dock." % _state.day)


## Put the players on their ship (see GameState.ship): it rows as its data
## says, and a bigger ship than the rowing boat is drawn under the players,
## who row on its stern bench, with its crew rowing to their beat.
func refit() -> void:
    var data: Dictionary = _state.ships.data()
    _boat.set_ship(data)
    if _ship_view != null:
        _ship_view.queue_free()
        _ship_view = null
    _stern = 0.0
    _rower.scale = Vector2.ONE
    _rower.show_hull = true
    _boat_wake.width = 2.5
    _boat_wake.spread = 8.0
    for npc in _npcs:
        npc.players_length = float(data.get("drawn", {}).get("length", RowerView.HULL_LENGTH))
    if not data.has("drawn"):
        return
    _ship_view = Longship.new()
    _ship_view.map = _map
    _ship_view.look = data["drawn"]
    add_child(_ship_view)
    move_child(_ship_view, _rower.get_index())
    # The players sit on the stern bench, a little smaller than in their boat.
    var size := float(data["drawn"]["length"]) / 37.5
    _stern = _ship_view.stern_offset()
    _rower.scale = Vector2.ONE * clampf(size * 0.6, 0.45, 0.8)
    _rower.show_hull = false
    _boat_wake.width = 2.5 + 0.35 * _ship_view.beam()
    _boat_wake.spread = 8.0 + 10.0 * size


## Signe's slipway with a ship half built, and her timber and tar, on the shore
## of the shipyard beside its jetty (see Ships).
func _add_shipyard() -> void:
    var place := _map.place(_state.ships.shipyard)
    if place.is_empty():
        return
    var at: Vector2 = place["at"]
    var toward := (Vector2(place["jetty"]) - at).normalized()
    var side := toward.orthogonal()
    # The bow of the ship on the slipway points to the water.
    var things := [
        ["slipway", at + toward * 8.0 + side * 24.0, toward.angle() + PI / 2.0, 30.0],
        ["timber", at + toward * 4.0 - side * 26.0, toward.angle() - PI / 2.0, 22.0],
    ]
    for thing in things:
        var picture := Pictures.of("ships", thing[0])
        if picture == null:
            continue
        var sprite := Sprite2D.new()
        sprite.texture = picture
        sprite.position = thing[1]
        sprite.rotation = thing[2]
        sprite.scale = Vector2.ONE * (thing[3] / maxf(picture.get_width(), picture.get_height()))
        add_child(sprite)


func _add_label(text: String, kind: String, at: Vector2) -> void:
    var mark := MapLabel.new()
    mark.text = text
    mark.kind = kind
    mark.position = at
    add_child(mark)
    _labels.append(mark)


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


# ---------------------------------------------------------------------------
# The getters for the HUD
# ---------------------------------------------------------------------------


## How many row: as the journey says (see GameState.players).
func players() -> int:
    if _state != null:
        return _state.players
    return _service.GetPlayerCount() if _service != null else 1


func map() -> LakeMap:
    return _map


func boat() -> RowBoat:
    return _boat


func npcs() -> Array[NpcBoat]:
    return _npcs


func state() -> Node:
    return _state


func service() -> Node:
    return _service


func toast() -> String:
    return _toast if _toast_left > 0.0 else ""


func to_screen(point: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform() * point


# ---------------------------------------------------------------------------
# Rowing
# ---------------------------------------------------------------------------


## C opens and closes the map of the region; Escape closes it, too.
func _input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    if event.keycode == KEY_C or (event.keycode == KEY_ESCAPE and _chart != null):
        get_viewport().set_input_as_handled()
        _toggle_chart()


func _toggle_chart() -> void:
    if _chart != null:
        _chart.queue_free()
        _chart = null
        _panel.process_mode = Node.PROCESS_MODE_INHERIT
        return
    if _map == null or _map.places.is_empty():
        return
    _chart = WorldChart.new()
    _chart.world = self
    _chart_layer.add_child(_chart)
    # NOTE: The cards of a screen must not be chosen behind the map.
    _panel.process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
    if _map == null or _map.places.is_empty():
        return
    if _chart != null:
        # The game waits while the map shows; the strokes meanwhile do not row.
        _skip_strokes()
        return
    _toast_left = maxf(0.0, _toast_left - delta)
    if _shots != "":
        _shot_clock += delta
        if _shot_clock >= 20.0:
            _shot_clock = 0.0
            _shoot.call_deferred()
    if _mode == "rowing":
        _boat.brake = _read_brake()
        _read_strokes()
        _boat.steer = _read_steer()
        if _autopilot:
            _fly(delta)
        _gulls_left -= delta
        if _gulls_left <= 0.0:
            _gulls_left = _rng.randf_range(GULLS_EVERY.x, GULLS_EVERY.y)
            Audio.play("gulls")
        _check_docking()
        # NOTE: The boat which just docked hails nobody: the port shows.
        if _mode == "rowing":
            _check_hailing()
    else:
        # NOTE (mristin):
        # The strokes in a port choose; they must not row once the boat is out.
        _skip_strokes()
        _boat.steer = 0.0
        _boat.brake = false
        if _autopilot:
            _autopilot_choose(delta)
    _boat.move(delta, _map)
    _rower.position = _boat.position + Vector2(0, _stern).rotated(_boat.heading)
    _rower.rotation = _boat.heading
    if _ship_view != null:
        _ship_view.oars_swing = (_rower.swing_of(0) + _rower.swing_of(1)) / 2.0
        _ship_view.oars_pulling = _rower.pulling[0] or _rower.pulling[1]
        _ship_view.follow(delta, _boat.position, _boat.heading, _boat.speed)
    _rower.live_pull = _live_pull()
    _boat_wake.follow(_boat.position, delta, absf(_boat.speed))
    _splash_oars(delta)
    _place_camera(delta)
    for label in _labels:
        label.rotation = _camera.rotation
    _hud.queue_redraw()


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


func _splash_oars(delta: float) -> void:
    _drip += delta
    var drip := _drip >= 0.12
    if drip:
        _drip = 0.0
    if _ship_view != null and (_rower.catches[0] or _rower.catches[1]):
        # The crew dips its oars with the players.
        for blade in _ship_view.blade_positions():
            _splashes.splash(blade, 4.0, 1.4, 0.9)
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
    var weight := 1.0 - exp(-delta / 1.2)
    _camera.rotation = lerp_angle(_camera.rotation, _boat.heading, weight)
    var target := _boat.position + Vector2.UP.rotated(_camera.rotation) * LOOK_AHEAD
    _camera.position = _camera.position.lerp(target, 1.0 - exp(-delta / 0.25))


func _say(text: String) -> void:
    _toast = text
    _toast_left = 6.0
    if _autopilot:
        print("Day %d: %s" % [_state.day, text])


# ---------------------------------------------------------------------------
# Docking and the ports
# ---------------------------------------------------------------------------


func _check_docking() -> void:
    for place in _map.places:
        var distance: float = _boat.position.distance_to(place["jetty"])
        if place["id"] == _left_place:
            if distance > UNDOCK_DISTANCE:
                _left_place = ""
            continue
        if distance < DOCK_DISTANCE and _boat.speed < DOCK_SPEED:
            _dock(place["id"])
            return


func _dock(id: String) -> void:
    var place := _map.place(id)
    _boat.speed = 0.0
    _boat.position = place["berth"]
    _state.place = id
    _state.save()
    _mode = "port"
    _sound_of_port(place)
    _screens.show_port()


## The sounds of the port at the [param place]: the jetty, and what lives
## there (the farm's music and an animal at home, the crowd of a market).
func _sound_of_port(place: Dictionary) -> void:
    Audio.play("dock")
    match place["kind"]:
        "home":
            Audio.music("farm")
            var kinds: Array = _state.farm.animals.keys()
            if not kinds.is_empty():
                Audio.play(Audio.ANIMALS.get(kinds[_rng.randi() % kinds.size()], "hens"))
        "market":
            Audio.play("market")
        "beekeeper":
            Audio.play("bees")


## Put the boat at the jetty of the place, heading out on the water.
func _undock(id: String) -> void:
    var place := _map.place(id)
    if place.is_empty():
        place = _map.places[0]
    _boat.position = place["berth"]
    var out: Vector2 = (place["jetty"] - place["at"]).normalized()
    _boat.heading = out.angle() + PI / 2.0
    _boat.speed = 2.0
    _left_place = place["id"]
    _autopilot_from = place["id"]
    _state.place = ""
    _mode = "rowing"
    Audio.music("lakes")
    _panel.close()
    _farm_view.visible = false
    _arrows.visible = true
    _autopilot_target = ""


## Show a screen of choices (for PortScreens).
func show_screen(
    title: String, text: String, cards: Array, actions: Array[Callable], face := {}
) -> void:
    _show(title, text, cards, actions, face)


## Leave the jetty of the place (for PortScreens).
func undock(id: String) -> void:
    _undock(id)


## Save nothing more and quit (for PortScreens).
func quit() -> void:
    _quit()


func _show(title: String, text: String, cards: Array, actions: Array[Callable], face := {}) -> void:
    _actions = actions
    for card: Dictionary in cards:
        var icon := str(CARD_ICONS.get(card.get("title", ""), ""))
        if icon != "" and not card.has("picture") and not card.has("stars"):
            card["picture"] = ["icons", icon]
    # NOTE (mristin):
    # At home, the screens show the farm behind them, dimmed less.
    var home: bool = _mode == "port" and _state.place == "home"
    _farm_view.visible = home
    if home:
        _farm_view.farm = _state.farm
        _farm_view.day = _state.day
    _panel.dim = 0.2 if home else ChoicePanel.DIM
    _panel.clear_rects = _farm_view.clear_rects() if home else ([] as Array[Rect2])
    _arrows.visible = false
    _panel.show_cards(title, text, cards, face)
    if _shots != "":
        _shoot.call_deferred()


## Save a screenshot for the developers (see --shots).
func _shoot() -> void:
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    if image != null:
        _shot_count += 1
        image.save_png("%s/%03d.png" % [_shots, _shot_count])


func _on_chosen(index: int) -> void:
    if _autopilot:
        print(
            (
                "Day %d, %d silver, cargo %s: %s: %s"
                % [
                    _state.day,
                    _state.silver,
                    str(_state.cargo),
                    _panel.title,
                    _panel.cards[index].get("title", "")
                ]
            )
        )
    if index >= 0 and index < _actions.size():
        _actions[index].call()


# ---------------------------------------------------------------------------
# The skippers on the lakes
# ---------------------------------------------------------------------------


func _check_hailing() -> void:
    if _boat.speed > HAIL_SPEED:
        return
    for npc in _npcs:
        if npc.cooldown > 0.0 or npc.held:
            continue
        if npc.position.distance_to(_boat.position) < HAIL_DISTANCE:
            _hail(npc)
            return


func _hail(npc: NpcBoat) -> void:
    Audio.play("bell")
    npc.held = true
    _talking_to = npc
    _mode = "skipper"
    var who: Dictionary = npc.skipper
    var face := {"hair": who["hair"], "braids": who["braids"], "picture": who.get("picture", "")}
    var events: Array = _state.missions.hail(_state, who.get("picture", ""))
    if not events.is_empty():
        _state.save()
        _show_hail_events(events, 0, face)
        return
    var news := Gossip.news(_state, who, _rng)
    _state.hear(news["text"], news["place"], news["good"])
    var deal := Gossip.offer(_state, who, _rng) if _rng.randf() < 0.7 else {}
    var text: String = news["text"]
    var cards: Array = []
    var actions: Array[Callable] = []
    if not deal.is_empty():
        text += "  " + deal["text"]
        var color: Color = (
            _state.economy.goods[deal["good"]]["color"]
            if _state.economy.goods.has(deal["good"])
            else Color.WHITE
        )
        cards.append({"title": "Yes, deal!", "detail": _deal_detail(deal), "color": color})
        actions.append(_take_deal.bind(deal))
        cards.append({"title": "No, thank you", "detail": ""})
        actions.append(_part.bind(""))
    else:
        cards.append({"title": "Thank you!", "detail": "fair winds"})
        actions.append(_part.bind(""))
    _show(
        who["name"],
        text,
        cards,
        actions,
        {"hair": who["hair"], "braids": who["braids"], "picture": who.get("picture", "")}
    )


## Show what the hail did for the missions (see Missions.hail), one screen
## after the other.
func _show_hail_events(events: Array, index: int, face: Dictionary) -> void:
    if index >= events.size():
        _part("")
        return
    var event: Dictionary = events[index]
    var text: String = event["text"]
    if str(event["who"].get("name", "")) != "":
        text = '%s: "%s"' % [event["who"]["name"], text]
    var cards: Array = [{"title": "Hooray!" if event["done"] else "Thank you!", "detail": ""}]
    if event["done"]:
        cards[0]["stars"] = int(event.get("stars", 0))
        Audio.play("hooray")
    var actions: Array[Callable] = [_show_hail_events.bind(events, index + 1, face)]
    _show(event["title"], text, cards, actions, {} if event["done"] else face)


func _deal_detail(deal: Dictionary) -> String:
    match deal["kind"]:
        "buy":
            return "-%d silver" % (int(deal["price"]) * int(deal["count"]))
        "sell":
            return "+%d silver" % (int(deal["price"]) * int(deal["count"]))
    return "a swap"


func _take_deal(deal: Dictionary) -> void:
    Audio.play("coins")
    _part(Gossip.take(_state, deal))


func _part(message: String) -> void:
    if _talking_to != null:
        _talking_to.held = false
        _talking_to.cooldown = HAIL_COOLDOWN
        _talking_to = null
    _panel.close()
    _arrows.visible = true
    _mode = "rowing"
    if message != "":
        _say(message)


# ---------------------------------------------------------------------------
# The autopilot (to try the world without the camera)
# ---------------------------------------------------------------------------


func _fly(delta: float) -> void:
    if _autopilot_target == "":
        var others: Array = []
        for place in _map.places:
            if place["id"] != _left_place:
                others.append(place["id"])
        _autopilot_target = (
            "home"
            if _autopilot_steps % 4 == 3 and _left_place != "home"
            else others[_rng.randi() % others.size()]
        )
        _autopilot_steps += 1
    var jetty: Vector2 = _map.place(_autopilot_target)["jetty"]
    var path := _map.route_between(_autopilot_from, _autopilot_target)
    _autopilot_log += delta
    if _autopilot_log > 30.0:
        _autopilot_log = 0.0
        print(
            (
                "  rowing from %s to %s: %.0f m to go, speed %.1f"
                % [
                    _autopilot_from,
                    _autopilot_target,
                    _boat.position.distance_to(_map.place(_autopilot_target)["jetty"]),
                    _boat.speed
                ]
            )
        )
    var aim := jetty
    for point in path:
        if (
            point.distance_to(_boat.position) > 30.0
            and point.distance_to(jetty) < _boat.position.distance_to(jetty)
        ):
            aim = point
            break
    var wanted := (aim - _boat.position).angle() + PI / 2.0
    _boat.steer = clampf(angle_difference(_boat.heading, wanted) * 2.0, -1.0, 1.0)
    _autopilot_beat += delta
    var near := _boat.position.distance_to(jetty) < 60.0
    if _autopilot_beat >= 2.6 and (not near or _boat.speed < 1.0):
        _autopilot_beat = 0.0
        _boat.stroke()


func _autopilot_choose(delta: float) -> void:
    _autopilot_wait += delta
    if _autopilot_wait < 1.0 or not _panel.visible:
        return
    _autopilot_wait = 0.0
    var titles: Array[String] = []
    for card in _panel.cards:
        titles.append(str(card.get("title", "")))
    # NOTE (mristin):
    # Sell what can be sold, buy a little, take the deals, sleep at home, and row on.
    var selling: bool = _autopilot_bought != _state.place
    for wanted in ["Yes, deal!", "Unload the boat", "Sell", "Thank you!"]:
        for i in range(titles.size()):
            if wanted == "Sell" and not selling:
                continue
            if titles[i] == wanted and bool(_panel.cards[i].get("enabled", true)):
                _panel.choose(i)
                return
    for i in range(titles.size()):
        if (
            titles[i].begins_with("Sell ")
            and selling
            and bool(_panel.cards[i].get("enabled", true))
        ):
            _panel.choose(i)
            return
    if "Buy" in titles and _state.load_count() == 0:
        var buy := titles.find("Buy")
        if bool(_panel.cards[buy].get("enabled", true)):
            _autopilot_bought = _state.place
            _panel.choose(buy)
            return
    for i in range(titles.size()):
        if (
            titles[i].begins_with("Buy ")
            and bool(_panel.cards[i].get("enabled", true))
            and _state.load_count() < 2
        ):
            _panel.choose(i)
            return
    for wanted in ["Back", "Sleep", "Row out", "Row on", "No, thank you"]:
        var index := titles.find(wanted)
        if index >= 0:
            if wanted == "Sleep" and (_state.day > 3 or not _state.travelled):
                continue
            _panel.choose(index)
            return
