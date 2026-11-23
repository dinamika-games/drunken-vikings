extends Control

## The first screen: the players choose with their hands (see ChoicePanel)
## how many row (one, or two with an oar each), and what they play: the party
## mode for the smaller children (follow the wedding longship and pick up what
## falls into the water), or the practical mode (the farm and the trading on
## the lakes), going on with their voyage or starting a new one; or the
## chase mode (row to a town before the pirates catch you).

const PARTY_SCENE := "res://scenes/level/level.tscn"
const CHASE_SCENE := "res://scenes/chase/chase.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"

const _TITLE := Color("f2c14e")
const _PAPER := Color("f1f0ea")

var _service: Node
var _state: Node
var _panel: ChoicePanel
var _actions: Array[Callable] = []
var _time := 0.0


func _ready() -> void:
    var vision := get_node_or_null("/root/Vision")
    _service = vision.service if vision != null else null
    _state = get_node_or_null("/root/GameState")
    set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel = ChoicePanel.new(_service)
    _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel.chosen.connect(_on_chosen)
    add_child(_panel)
    _ask_players.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        _quit()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _quit()


func _quit() -> void:
    if _service != null:
        _service.Shutdown()
    get_tree().quit()


func _on_chosen(index: int) -> void:
    if index >= 0 and index < _actions.size():
        _actions[index].call()


func _ask_players() -> void:
    _actions = [_set_players.bind(1), _set_players.bind(2)]
    _panel.show_cards(
        "Drunken Vikings",
        "Welcome, vikings! How many of you row today? Two rowers pull an oar each.",
        [
            {"title": "One rower", "detail": "Ylva"},
            {"title": "Two rowers", "detail": "Ylva and Sigrid"}
        ],
        {"hair": Color("e8c25a"), "braids": true}
    )


func _set_players(count: int) -> void:
    if _service != null:
        _service.SetPlayerCount(count)
    _ask_mode()


func _ask_mode() -> void:
    _actions = [_party, _chase, _ask_voyage, _ask_players]
    (
        _panel
        . show_cards(
            "What do you play?",
            (
                "Follow the wedding longship and pick up what falls into the water, "
                + "flee from the pirates to a town, "
                + "or trade on the lakes and look after your farm."
            ),
            [
                {"title": "Party!", "detail": "follow the wedding"},
                {"title": "Chase!", "detail": "flee the pirates"},
                {"title": "The farm", "detail": "trade and farm"},
                {"title": "Back", "detail": ""},
            ],
            {"hair": Color("e8c25a"), "braids": true}
        )
    )


func _party() -> void:
    get_tree().change_scene_to_file(PARTY_SCENE)


func _chase() -> void:
    get_tree().change_scene_to_file(CHASE_SCENE)


func _ask_voyage() -> void:
    var saved: bool = _state != null and _state.load_voyage()
    if not saved:
        _new_voyage()
        return
    _actions = [_go_on, _new_voyage, _ask_mode]
    (
        _panel
        . show_cards(
            "Your voyage",
            (
                "Go on where you stopped, or start a new voyage "
                + "with a small farm and a few pieces of silver?"
            ),
            [
                {"title": "Go on", "detail": "day %d, %d silver" % [_state.day, _state.silver]},
                {"title": "A new voyage", "detail": "from the start"},
                {"title": "Back", "detail": ""},
            ],
            {"hair": Color("d8d8d0"), "braids": true}
        )
    )


func _go_on() -> void:
    get_tree().change_scene_to_file(WORLD_SCENE)


func _new_voyage() -> void:
    if _state != null:
        _state.new_voyage()
        _state.save()
    get_tree().change_scene_to_file(WORLD_SCENE)


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


## The lake at dusk behind the screens, with a longship sailing by.
func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("1f3a5a"))
    for i in range(14):
        var y := 420.0 + i * 46.0
        var x := fmod(_time * (20.0 + i * 3.0) + i * 137.0, size.x + 200.0) - 100.0
        draw_line(Vector2(x, y), Vector2(x + 90.0, y), Color(1, 1, 1, 0.12), 3.0)
    var ship := Vector2(fmod(_time * 40.0, size.x + 400.0) - 200.0, 380.0)
    draw_colored_polygon(
        PackedVector2Array(
            [
                ship + Vector2(-120, 0),
                ship + Vector2(120, 0),
                ship + Vector2(90, 30),
                ship + Vector2(-90, 30)
            ]
        ),
        Color("6a4320")
    )
    for k in range(5):
        draw_rect(
            Rect2(ship + Vector2(-60 + k * 24, -110), Vector2(24, 100)),
            Color("b8332a") if k % 2 == 0 else Color("f1e6cc")
        )
    draw_line(ship + Vector2(0, -120), ship, Color("4a3018"), 6.0)
