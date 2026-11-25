extends Control

## The first screen: the players choose with their hands (see ChoicePanel)
## their journey (see GameState): go on with the last one, open another
## recent one, start a new one (then they choose how many row: one, or two
## with an oar each, how each rower looks, and see how to play, see HowTo),
## or delete one (in three steps). Then they choose what
## they play: the party mode for the smaller children (follow the wedding
## longship and pick up what falls into the water), the chase mode (row to a
## town before the pirates catch you), or the farm and the trading on the
## lakes; or change how they look.
##
## How a rower looks (see Looks): a viking girl or boy, and the colour of the
## skin, of the hair and of the clothes, one screen each; every card shows
## the rower in the boat as the card would make them look. Escape twice quits.

const PARTY_SCENE := "res://scenes/level/level.tscn"
const CHASE_SCENE := "res://scenes/chase/chase.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"

const _TITLE := Color("f2c14e")
const _PAPER := Color("f1f0ea")

const PAINTING := "res://assets/pictures/start/start.jpg"

## The most journeys shown to go on with (the last one first).
const MAX_JOURNEYS := 3

const YLVA := {"hair": Color("e8c25a"), "braids": true, "picture": "ylva"}
const GRANDMOTHER := {"hair": Color("d8d8d0"), "braids": true, "picture": "grandmother"}

var _service: Node
var _state: Node
var _panel: ChoicePanel
var _actions: Array[Callable] = []
var _time := 0.0

## Choosing the looks: the steps ([player, "figure", "skin", "hair" or
## "clothes"]), the step on the screen, what comes after the last step, and
## what Back on the first step does.
var _look_steps: Array = []
var _look_step := 0
var _look_done: Callable
var _look_back: Callable

## The painting of the start screen (see dev/pictures/cut_sheets.py), or
## null: then we draw a simple lake.
var _painting: Texture2D = load(PAINTING) as Texture2D if ResourceLoader.exists(PAINTING) else null


func _ready() -> void:
    var vision := get_node_or_null("/root/Vision")
    _service = vision.service if vision != null else null
    _state = get_node_or_null("/root/GameState")
    set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel = ChoicePanel.new(_service)
    _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel.chosen.connect(_on_chosen)
    add_child(_panel)
    EscapeGuard.attach(self, _quit, "Press Esc again to quit the game.")
    Audio.music("start")
    Audio.ambient("")
    _ask_journey.call_deferred()


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


## The journeys: go on with the last one, open one of the other recent ones,
## start a new one, or delete one; without any journey, a new one starts.
func _ask_journey() -> void:
    var journeys: Array = _state.journeys() if _state != null else []
    if journeys.is_empty():
        _ask_players()
        return
    var cards: Array = []
    _actions = []
    for i in range(mini(journeys.size(), MAX_JOURNEYS)):
        var journey: Dictionary = journeys[i]
        (
            cards
            . append(
                {
                    "title": ("Go on: " if i == 0 else "") + _journey_title(journey),
                    "detail": _journey_detail(journey),
                }
            )
        )
        _actions.append(_open_journey.bind(str(journey["id"])))
    cards.append({"title": "+ New journey", "detail": "one or two rowers"})
    _actions.append(_ask_players)
    cards.append({"title": "Delete", "detail": "a journey"})
    _actions.append(_ask_delete)
    _panel.show_cards(
        "Your journeys",
        "Welcome, vikings! Go on with your journey, or start a new one.",
        cards,
        YLVA
    )


func _journey_detail(journey: Dictionary) -> String:
    return "day %d, %d silver" % [int(journey["day"]), int(journey["silver"])]


## The name of the journey, and its two rowers if it has them.
func _journey_title(journey: Dictionary) -> String:
    return str(journey["name"]) + (" (2 rowers)" if int(journey["players"]) == 2 else "")


func _open_journey(id: String) -> void:
    if _state != null and not _state.open_journey(id):
        _ask_journey()
        return
    _apply_players()
    _ask_mode()


## A new journey: how many row?
func _ask_players() -> void:
    _actions = [_start_journey.bind(1), _start_journey.bind(2), _ask_journey]
    (
        _panel
        . show_cards(
            "A new journey",
            "How many of you row? Two rowers pull an oar each.",
            [
                {"title": "One rower", "detail": "both oars"},
                {"title": "Two rowers", "detail": "an oar each"},
                {"title": "Back", "detail": ""},
            ],
            YLVA
        )
    )


func _start_journey(count: int) -> void:
    if _state != null:
        _state.new_journey(count)
    _apply_players()
    _ask_looks(_how_to, _undo_journey)


## Back from the looks of a new journey: it is not begun after all.
func _undo_journey() -> void:
    if _state != null and _state.journey_id != "":
        _state.delete_journey(_state.journey_id)
    _ask_players()


## How the rowers look: the steps of each rower, one after the other; then
## [param done], or [param back] from the first step.
func _ask_looks(done: Callable, back: Callable) -> void:
    _look_steps = []
    var count: int = _state.players if _state != null else 1
    for player in range(count):
        for step in ["figure", "skin", "hair", "clothes"]:
            _look_steps.append([player, step])
    _look_step = 0
    _look_done = done
    _look_back = back
    _ask_look_step()


## The look of the [param player] so far.
func _look(player: int) -> Dictionary:
    if _state != null:
        return _state.look(player)
    return Looks.default_look(player)


func _set_look(player: int, look: Dictionary) -> void:
    if _state != null:
        _state.looks[player] = look


## Who chooses on the screens of the looks: the only rower, or the one on
## the left or on the right of the boat.
func _rower_name(player: int) -> String:
    var count: int = _state.players if _state != null else 1
    if count == 1:
        return "Your viking"
    return "The left rower" if player == 0 else "The right rower"


## The rower of the [param player] in the boat as the [param look] makes them look.
func _preview(player: int, look: Dictionary) -> Texture2D:
    var count: int = _state.players if _state != null else 1
    return Looks.rower(look, count == 2 and player == 1, "middle")


func _ask_look_step() -> void:
    var player: int = _look_steps[_look_step][0]
    var step: String = _look_steps[_look_step][1]
    var look := _look(player)
    var cards: Array = []
    _actions = []
    var text: String
    if step == "figure":
        text = "Who rows: a viking girl or a viking boy?"
        for pair in [["girl", "Girl"], ["boy", "Boy"]]:
            var changed := look.duplicate()
            changed["figure"] = pair[0]
            cards.append({"title": pair[1], "detail": "", "picture": _preview(player, changed)})
            _actions.append(_choose_look.bind(player, "figure", pair[0]))
    else:
        var palette := Looks.palette(step)
        text = {
            "skin": "Choose the colour of the skin.",
            "hair": "Choose the colour of the hair.",
            "clothes": "Choose the colour of the clothes.",
        }[step]
        for index in range(palette.size()):
            var changed := look.duplicate()
            changed[step] = index
            var entry: Dictionary = palette[index]
            (
                cards
                . append(
                    {
                        "title": str(entry["name"]),
                        "detail": "as now" if int(look[step]) == index else "",
                        "picture": _preview(player, changed),
                    }
                )
            )
            _actions.append(_choose_look.bind(player, step, index))
    cards.append({"title": "Back", "detail": ""})
    _actions.append(_look_previous)
    _panel.show_cards(_rower_name(player), text, cards, YLVA)


func _choose_look(player: int, step: String, value: Variant) -> void:
    var look := _look(player).duplicate()
    look[step] = value
    _set_look(player, look)
    _look_step += 1
    if _look_step < _look_steps.size():
        _ask_look_step()
        return
    if _state != null:
        _state.save()
    _look_done.call()


func _look_previous() -> void:
    if _look_step == 0:
        _look_back.call()
        return
    _look_step -= 1
    _ask_look_step()


## Show how to play (see HowTo), then what to play.
func _how_to() -> void:
    _panel.close()
    var how := HowTo.new()
    how.players = _state.players if _state != null else 1
    # NOTE: Out of the tree first, so that it lets go of the hands before the
    # next screen asks for them.
    how.done.connect(
        func() -> void:
            remove_child(how)
            how.queue_free()
            _ask_mode()
    )
    add_child(how)


## Tell the camera how many players to follow, as the journey says.
func _apply_players() -> void:
    if _service != null and _state != null:
        _service.SetPlayerCount(_state.players)


## Which journey to delete: the first of three steps, so that a hand resting
## on the screen never deletes one by chance.
func _ask_delete() -> void:
    var journeys: Array = _state.journeys() if _state != null else []
    var cards: Array = []
    _actions = []
    for i in range(mini(journeys.size(), MAX_JOURNEYS + 1)):
        var journey: Dictionary = journeys[i]
        cards.append({"title": _journey_title(journey), "detail": _journey_detail(journey)})
        _actions.append(_confirm_delete.bind(journey))
    cards.append({"title": "Back", "detail": ""})
    _actions.append(_ask_journey)
    _panel.show_cards("Delete a journey", "Which journey should be deleted?", cards, GRANDMOTHER)


func _confirm_delete(journey: Dictionary) -> void:
    _actions = [_delete.bind(str(journey["id"])), _ask_journey]
    _panel.show_cards(
        "Delete %s?" % journey["name"],
        "The journey and everything in it will be gone for good.",
        [{"title": "Delete", "detail": "for good"}, {"title": "Keep", "detail": ""}],
        GRANDMOTHER
    )


func _delete(id: String) -> void:
    if _state != null:
        _state.delete_journey(id)
    _ask_journey()


func _ask_mode() -> void:
    _actions = [
        _party, _chase, _go_on, _how_to, _ask_looks.bind(_ask_mode, _ask_mode), _ask_journey
    ]
    var name: String = _state.journey_name if _state != null else ""
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
                {"title": "Party!", "detail": "the wedding"},
                {"title": "Chase!", "detail": "flee the pirates"},
                {"title": "The farm", "detail": "trade and farm"},
                {"title": "How to play", "detail": "row and steer", "picture": ["icons", "help"]},
                {"title": "Your vikings", "detail": "how you look"},
                {"title": "Back", "detail": name},
            ],
            YLVA
        )
    )


func _party() -> void:
    get_tree().change_scene_to_file(PARTY_SCENE)


func _chase() -> void:
    get_tree().change_scene_to_file(CHASE_SCENE)


func _go_on() -> void:
    get_tree().change_scene_to_file(WORLD_SCENE)


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


## The lake at dusk behind the screens, with a longship sailing by.
func _draw() -> void:
    if _painting != null:
        # NOTE (mristin):
        # The painting fills the screen and drifts very slowly, as if one
        # looked around over the lake.
        var zoom := 1.04 + 0.02 * sin(_time * 0.1)
        var cover := maxf(size.x / _painting.get_width(), size.y / _painting.get_height()) * zoom
        var shown := Vector2(_painting.get_size()) * cover
        var drift := Vector2(sin(_time * 0.07), cos(_time * 0.05)) * (shown - size) * 0.4
        draw_texture_rect(_painting, Rect2((size - shown) / 2.0 + drift, shown), false)
        return
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
