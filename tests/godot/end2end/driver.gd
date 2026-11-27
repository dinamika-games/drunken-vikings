extends SceneTree
## The base of the end-to-end tests (see playthrough.gd): it runs the game
## frame by frame as fast as the computer can, checks the contracts on every
## frame (see contracts.gd), and plays as the players do, only through the
## camera (see fake_vision.gd): it rows strokes, leans to steer, raises both
## hands to brake, and holds a raised hand on a card to choose it. Escape and
## C come from the keyboard, as in the game.
##
## Speed: the test runs with [code]--fixed-fps 60[/code], so that every frame
## plays 1/60 s of the game however fast it is computed, and the game runs
## [member time_scale] times faster than that (10 by default). Most of a frame goes into
## drawing (even headless), so what redraws on every frame (the boats, their
## wakes, the HUD) is drawn only on every [member draw_every]-th frame; the
## map is drawn once, as in the game, and the screens of choices on every
## frame, since the cards work by being visible.
##
## Not a test itself (its name does not start with test_).

const FakeVision := preload("res://tests/godot/end2end/fake_vision.gd")
const Contracts := preload("res://tests/godot/end2end/contracts.gd")
const ErrorLog := preload("res://tests/godot/end2end/error_log.gd")

const DEFAULT_SEED := 20261124
const DEFAULT_TIME_SCALE := 10.0
const DEFAULT_DRAW_EVERY := 8

## The test fails if it takes longer than this, in seconds of the wall clock.
const DEFAULT_WALL_SECONDS := 300.0

## A card held by the hand must be chosen within this many seconds of the
## game (it takes DwellButton.DWELL_SECONDS).
const CHOOSE_SECONDS := 6.0

## The screen.
const SCREEN := Vector2(1920, 1080)

## What redraws on every frame, and which the game itself never hides: the
## test draws it only now and then (see [method _paint]). The rest is drawn
## as in the game: the map once, the screens of choices on every frame.
const REDRAWN := [
    "WorldHud",
    "Wake",
    "Longship",
    "NpcBoat",
    "RowerView",
    "Splashes",
    "Treats",
    "CameraPanel",
    "HudOverlay",
]

var fake: Node
var contracts := Contracts.new()
var errors := ErrorLog.new()
var rng := RandomNumberGenerator.new()

## Whether to print every choice (-- --trace).
var tracing := false

var time_scale := DEFAULT_TIME_SCALE
var draw_every := DEFAULT_DRAW_EVERY
var wall_seconds := DEFAULT_WALL_SECONDS

## The seconds of the game played, and the frames.
var clock := 0.0
var frames := 0

## What the players saw: the titles of the screens, and how often.
var seen := {}

var _failures: Array[String] = []
var _aborted := false
var _started_ms := 0
var _chosen := -1
var _panels := {}
var _panels_scene := 0
var _scene_panels: Array[Node] = []
var _drawn: Array[CanvasItem] = []
var _drawn_scene := 0
var _drawn_children := -1


## Read the arguments after "--": --name=value, or [param default].
static func argument(name: String, default: String) -> String:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--%s=" % name):
            return arg.trim_prefix("--%s=" % name)
    return default


func _initialize() -> void:
    _run.call_deferred()


## Overridden by the test: play the game.
func _play() -> void:
    pass


## Overridden by the test: how long it may take by default, in seconds of the
## wall clock (-- --wall-seconds=<s> sets another limit).
func default_wall_seconds() -> float:
    return DEFAULT_WALL_SECONDS


func _run() -> void:
    # NOTE: With --fixed-fps 60, every frame plays exactly 1/60 s, however fast.
    await process_frame
    await process_frame
    if absf(root.get_process_delta_time() - 1.0 / 60.0) > 1e-6:
        print("Run the test with --fixed-fps 60 (see the description of driver.gd).")
        quit(2)
        return
    OS.add_logger(errors)
    var seed_value := int(argument("seed", str(DEFAULT_SEED)))
    rng.seed = seed_value
    seed(seed_value)
    time_scale = float(argument("time-scale", str(DEFAULT_TIME_SCALE)))
    draw_every = maxi(1, int(argument("draw-every", str(DEFAULT_DRAW_EVERY))))
    wall_seconds = float(argument("wall-seconds", str(default_wall_seconds())))
    tracing = "--trace" in OS.get_cmdline_user_args()
    Engine.time_scale = time_scale
    Engine.max_fps = 0
    print(
        (
            "Seed %d, the game %.0f times faster, drawn every %d frames"
            % [seed_value, time_scale, draw_every]
        )
    )

    fake = FakeVision.new()
    root.add_child(fake)
    root.get_node("/root/Vision").service = fake
    _started_ms = Time.get_ticks_msec()

    await _play()

    Engine.time_scale = 1.0
    # NOTE: The audio server lets go of the sounds on its next mix, in its
    # own thread.
    Audio.silence()
    await create_timer(0.3, true, false, true).timeout
    for violation in contracts.violations():
        _failures.append("contract: " + violation)
    for error in errors.errors():
        _failures.append("error: " + error)
    for warning in errors.warnings():
        print("WARNING: ", warning)
    var titles := seen.keys()
    titles.sort()
    print("Screens seen: %d different, e.g., %s" % [titles.size(), titles.slice(0, 30)])
    print(
        (
            (
                "%.0f s of the game in %d frames, %.1f s on the wall clock (%.0f frames a second), "
                + "%d checks of the contracts"
            )
            % [clock, frames, wall(), frames / maxf(wall(), 0.001), contracts.checks()]
        )
    )
    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
        return
    for failure in _failures:
        print("FAIL: ", failure)
    print("RESULT: FAILED (%d)" % _failures.size())
    quit(1)


## The seconds on the wall clock since the test began.
func wall() -> float:
    return (Time.get_ticks_msec() - _started_ms) / 1000.0


## Report that something went wrong; stop the playing if [param fatal].
func fail(what: String, fatal := false) -> void:
    print("FAIL: ", what)
    _failures.append(what)
    if fatal:
        _aborted = true


## Whether the test must stop playing (something went wrong for good).
func aborted() -> bool:
    return _aborted


func check(ok: bool, what: String) -> void:
    if not ok:
        fail(what)


# ---------------------------------------------------------------------------
# The frames
# ---------------------------------------------------------------------------


## Play one frame: check the contracts and draw now and then.
func frame() -> void:
    _paint()
    await process_frame
    frames += 1
    clock += root.get_process_delta_time()
    if errors.errors().size() > 0 and not _aborted:
        fail("the game logged an error: %s" % errors.errors()[0], true)
    if wall() > wall_seconds and not _aborted:
        fail("the test took longer than %.0f s" % wall_seconds, true)
    _watch()


## Play for [param seconds] of the game.
func play_for(seconds: float) -> void:
    var until := clock + seconds
    while clock < until and not _aborted:
        await frame()


## Overridden by the test: check the contracts of the scene on this frame.
func _watch() -> void:
    var panel := panel()
    if panel != null:
        contracts.check_screen(panel)


## Hide what redraws on every frame, except on every [member draw_every]-th
## frame (see the description).
func _paint() -> void:
    var scene := current_scene
    if scene == null:
        return
    if scene.get_instance_id() != _drawn_scene or scene.get_child_count() != _drawn_children:
        _collect_drawn(scene)
    var draw := frames % draw_every == 0
    for item in _drawn:
        if is_instance_valid(item):
            item.visible = draw


func _collect_drawn(scene: Node) -> void:
    for item in _drawn:
        if is_instance_valid(item):
            item.visible = true
    _drawn.clear()
    _drawn_scene = scene.get_instance_id()
    _drawn_children = scene.get_child_count()
    for child in scene.get_children():
        if child is CanvasLayer:
            for item in child.get_children():
                if _redrawn(item):
                    _drawn.append(item)
        elif _redrawn(child):
            _drawn.append(child)


## Whether the [param node] redraws on every frame (and nothing else hides it).
static func _redrawn(node: Node) -> bool:
    var script := node.get_script() as Script
    return script != null and script.get_global_name() in REDRAWN and (node as CanvasItem).visible


## Wait until the scene of the [param path] runs (after a change of scenes).
func wait_for_scene(path: String) -> bool:
    var waited := 0
    while (current_scene == null or current_scene.scene_file_path != path) and waited < 30:
        await frame()
        waited += 1
    await frame()
    var ok := current_scene != null and current_scene.scene_file_path == path
    check(ok, "the scene %s starts" % path)
    return ok


# ---------------------------------------------------------------------------
# The screens of choices
# ---------------------------------------------------------------------------


## The screen of choices which shows now, or null.
func panel() -> ChoicePanel:
    if current_scene == null:
        return null
    if current_scene.get_instance_id() != _panels_scene:
        _panels_scene = current_scene.get_instance_id()
        _scene_panels = current_scene.find_children("*", "ChoicePanel", true, false)
    for node in _scene_panels:
        var found := node as ChoicePanel
        if (
            is_instance_valid(found)
            and found.is_visible_in_tree()
            and found.process_mode != Node.PROCESS_MODE_DISABLED
        ):
            return found
    return null


## The cards on the screen: the English title of each (its id, see
## ChoicePanel.card), or its title as shown.
func cards() -> Array[String]:
    var titles: Array[String] = []
    var shown := panel()
    if shown != null:
        for data: Dictionary in shown.cards:
            titles.append(str(data.get("id", data.get("title", ""))))
    return titles


## Whether the card of the [param data] is the card [param title]: its title
## as shown, or in English (its id, or its title translated), so that the
## test plays in every language.
static func is_card(data: Dictionary, title: String, prefix := false) -> bool:
    var name := str(data.get("title", ""))
    return (
        name == title
        or str(data.get("id", "")) == title
        or name == String(TranslationServer.translate(title))
        or (prefix and name.begins_with(title))
    )


## Whether the screen of choices which shows now has the [param title] (in
## English, or as shown).
func screen_is(title: String) -> bool:
    var shown := panel()
    return shown != null and shown.title in [title, Grammar.text(title)]


## The index of the first card which can be chosen and whose title is
## [param title] (see [method is_card]; or begins with it, if [param
## prefix]), or -1.
func card(title: String, prefix := false) -> int:
    var shown := panel()
    if shown == null:
        return -1
    for i in range(shown.cards.size()):
        var data: Dictionary = shown.cards[i]
        if is_card(data, title, prefix) and bool(data.get("enabled", true)):
            return i
    return -1


## Whether a card can be chosen now.
func can(title: String, prefix := false) -> bool:
    return card(title, prefix) >= 0


## Raise a hand to the card [param title] and hold it still until the card is
## chosen, then lower the hand; return whether it worked.
func choose(title: String, prefix := false) -> bool:
    if _aborted:
        return false
    var shown := panel()
    var index := card(title, prefix)
    if (shown == null or index < 0) and loose_button(title) != null:
        return await _hold(loose_button(title))
    if shown == null or index < 0:
        fail(
            (
                "the card '%s' can be chosen on '%s' (cards: %s)"
                % [title, shown.title if shown != null else "no screen", cards()]
            )
        )
        return false
    var screen_title := shown.title
    seen[screen_title] = int(seen.get(screen_title, 0)) + 1
    if tracing:
        print("  [%.0f s] %s: %s" % [clock, screen_title, shown.cards[index].get("title", "")])
    if not _panels.has(shown.get_instance_id()):
        _panels[shown.get_instance_id()] = true
        shown.chosen.connect(func(i: int) -> void: _chosen = i)
    var button: DwellButton = shown._buttons[index]
    _chosen = -1
    fake.point_at(button.get_global_rect().get_center(), SCREEN)
    var since := clock
    while _chosen < 0 and not _aborted:
        await frame()
        if _chosen >= 0 and _chosen != index:
            fail(
                (
                    "the hand on '%s' chose '%s' on '%s'"
                    % [
                        title,
                        (
                            shown.cards[_chosen].get("title", "")
                            if is_instance_valid(shown) and _chosen < shown.cards.size()
                            else _chosen
                        ),
                        screen_title
                    ]
                )
            )
        if clock - since > CHOOSE_SECONDS:
            fail(
                "the card '%s' on '%s' is chosen by holding the hand on it" % [title, screen_title]
            )
            fake.point_at(Vector2.INF, SCREEN)
            return false
    fake.point_at(Vector2.INF, SCREEN)
    await frame()
    return _chosen == index


## The card of the [param title] which shows outside the screens of choices
## (e.g., Ready! of HowTo), or null.
func loose_button(title: String) -> DwellButton:
    if current_scene == null:
        return null
    for node in current_scene.find_children("*", "DwellButton", true, false):
        var button := node as DwellButton
        if (
            button.is_visible_in_tree()
            and not button.get_parent() is ChoicePanel
            and is_card(button.card, title)
        ):
            return button
    return null


## Hold a raised hand on the [param button] until it is pressed, then lower
## the hand; return whether it worked.
func _hold(button: DwellButton) -> bool:
    var title := str(button.card.get("title", ""))
    seen[title] = int(seen.get(title, 0)) + 1
    if tracing:
        print("  [%.0f s] %s" % [clock, title])
    var pressed := [false]
    button.pressed.connect(func() -> void: pressed[0] = true)
    fake.point_at(button.get_global_rect().get_center(), SCREEN)
    var since := clock
    while not pressed[0] and not _aborted:
        await frame()
        if clock - since > CHOOSE_SECONDS:
            fail("the card '%s' is chosen by holding the hand on it" % title)
            break
    fake.point_at(Vector2.INF, SCREEN)
    await frame()
    return pressed[0]


## Press a key and let it go, as on the keyboard.
func tap(key: Key) -> void:
    for pressed in [true, false]:
        var event := InputEventKey.new()
        event.keycode = key
        event.physical_keycode = key
        event.pressed = pressed
        Input.parse_input_event(event)
    await frame()


# ---------------------------------------------------------------------------
# Rowing
# ---------------------------------------------------------------------------


## Lean (alone) or pull harder on one side (two players) towards the heading
## [param wanted] of the [param boat], and row a stroke every [param beat]
## seconds (none if 0) since [param since]; return when the last stroke was.
func row_towards(boat: RowBoat, wanted: float, beat: float, since: float) -> float:
    var turn := clampf(angle_difference(boat.heading, wanted) * 2.0, -1.0, 1.0)
    if fake.players == 1:
        fake.steer[0] = turn
        # NOTE: Like the players, pull only once the bow points about the
        # right way; otherwise the fast boat circles around where it should go.
        var aligned := absf(angle_difference(boat.heading, wanted)) < deg_to_rad(35.0)
        if beat > 0.0 and aligned and clock - since >= beat:
            fake.row()
            return clock
        return since
    # NOTE: Two rowers: the left oar turns the boat right (see RowBoat.stroke_side).
    fake.steer = [0.0, 0.0]
    # NOTE: Each kick pushes, too: far off the way, let the fast boat glide
    # slower before kicking it round, or it circles.
    if absf(angle_difference(boat.heading, wanted)) > deg_to_rad(35.0) and boat.speed > 8.0:
        return since
    if beat > 0.0 and clock - since >= beat:
        if absf(turn) > 0.5:
            fake.row(0 if turn > 0.0 else 1)
        else:
            fake.row()
        return clock
    if absf(turn) > 0.25 and beat > 0.0 and clock - since >= beat * 0.5:
        fake.row(0 if turn > 0.0 else 1)
        return clock
    return since


## Stop leaning and rowing, and lower the hands.
func rest() -> void:
    fake.steer = [0.0, 0.0]
    fake.brake = [false, false]
