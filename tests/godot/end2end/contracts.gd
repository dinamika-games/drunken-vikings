extends RefCounted
## The contracts of the game, which the end-to-end test checks all the way
## while the bot plays (design by contract, in the tests only, so that the
## game never pays for them): what must hold on every frame and on every
## screen, whatever the players do.
##
## On every screen of choices (see ChoicePanel):
##
## * the players can always go on: at least one card can be chosen;
## * the cards fit the screen side by side, and no two cards are called
##   the same;
## * the title of every card fits it, above its detail and its picture, and
##   so does the detail; the title of the screen fits the board, and so does
##   its text (a long text a little smaller, see ChoicePanel.fit_text; the
##   farm's at the usual size);
## * no text shows a placeholder (e.g., "%d", "{place}", "<null>");
## * every picture on a card, and every face, is painted.
##
## On the lakes (see world.gd), on every frame:
##
## * the boat stays on the water (off the jetties, too) and never crosses
##   the land between two frames, nor goes faster than its ship can; so do
##   the boats of the skippers, which never jump either (their ways are
##   preconditions of the map, see tests/godot/test_map.gd);
## * the boat rows exactly while no screen shows; in a port, the boat lies
##   still at the berth and the state knows the place; with a skipper, the
##   skipper waits;
## * the ship drawn under the players is the ship they own and row;
## * the music is the farm's while the boat lies at home, else the lakes';
## * the silver never goes below zero, the days never run backwards, the
##   cargo fits the hold, and every crate in the boat is a good, an animal or
##   an item of a task under way (nothing of a finished task stays aboard);
## * at most three tasks are under way, none of them done, and every task
##   done has one to three stars;
## * whenever the boat docks, the save on the disk is the voyage in memory.
##
## In the party and in the chase: the boat, the wedding longship and the
## pirates stay on the water, every treat picked up is a silver coin in the
## purse, and the music is the party's and the chase's (on the start screen,
## the start's).
##
## Each problem is reported once, with its first example and how often it
## happened.
##
## Not a test itself (its name does not start with test_).

## The cards of ChoicePanel and how they draw (see ChoicePanel, DwellButton).
const SCREEN_WIDTH := 1920.0
const CARD := Vector2(250, 190)
const CARD_GAP := 34.0
const CARD_FONT := 26
const CARD_LINE := 30.0
const DETAIL_FONT := 24
const BOARD_WIDTH := 1100.0
const TITLE_FONT := 40

## The texts which betray a placeholder or a missing value.
const PLACEHOLDERS := ["%s", "%d", "%.", "{", "}", "<null>", "<Object", "[]", "Nil "]

## The boats of the skippers are checked on every this many frames.
const NPC_EVERY := 4

## A little slack for the floats, in metres and metres a second.
const SLACK := 0.01

var _found := {}
var _checks := 0
var _screens_seen := {}
var _last_cards: Array = []
var _last_title := ""
var _frame := 0

## The boat on the last frame, to see that it never jumps over the land.
var _last_boat := Vector2.INF
var _last_mode := ""
var _last_day := 0
var _npc_last := {}


## The problems found, one line each.
func violations() -> Array[String]:
    var result: Array[String] = []
    for key in _found:
        var found: Dictionary = _found[key]
        result.append("%s (%d times), e.g., %s" % [key, found["count"], found["example"]])
    return result


## How many times the contracts were checked.
func checks() -> int:
    return _checks


## Forget the last frame, e.g., when a scene starts or the boat is put at a
## jetty; [param day] is the day of the voyage now.
func restart(day: int) -> void:
    _last_boat = Vector2.INF
    _last_mode = ""
    _last_day = day
    _npc_last.clear()


func _report(key: String, example: String) -> void:
    if not _found.has(key):
        _found[key] = {"count": 0, "example": example}
        print("CONTRACT BROKEN: ", key, ": ", example)
    _found[key]["count"] += 1


func _expect(ok: bool, key: String, example: String) -> void:
    _checks += 1
    if not ok:
        _report(key, example)


# ---------------------------------------------------------------------------
# The screens of choices
# ---------------------------------------------------------------------------


## Check the screen which the [param panel] shows (each different screen once).
func check_screen(panel: ChoicePanel) -> void:
    if is_same(panel.cards, _last_cards) and panel.title == _last_title:
        return
    _last_cards = panel.cards
    _last_title = panel.title
    var signature := "%s|%s|%s|%s" % [panel.title, panel.text, str(panel.cards), str(panel.face)]
    if _screens_seen.has(signature):
        return
    _screens_seen[signature] = true
    var where := "'%s'" % panel.title
    var font := ThemeDB.fallback_font

    var enabled := 0
    var titles := {}
    for card: Dictionary in panel.cards:
        if bool(card.get("enabled", true)):
            enabled += 1
        var title := str(card.get("title", ""))
        _expect(not titles.has(title), "no two cards are called the same", where + ": " + title)
        titles[title] = true
        _check_card(font, card, where)
    _expect(enabled > 0, "the players can always go on", where + ": " + str(titles.keys()))
    var count := panel.cards.size()
    _expect(
        count * CARD.x + (count - 1) * CARD_GAP <= SCREEN_WIDTH,
        "the cards fit the screen side by side",
        "%s: %d cards" % [where, count]
    )

    var left := 40.0 + (140.0 if not panel.face.is_empty() else 0.0)
    var width := BOARD_WIDTH - left - 40.0
    _expect(
        font.get_string_size(panel.title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT).x <= width,
        "the title of a screen fits the board",
        where
    )
    var fitted := ChoicePanel.fit_text(font, panel.text, width)
    _expect(fitted["all"], "the text of a screen fits the board", "%s: %s" % [where, panel.text])
    _expect(
        fitted["size"] == ChoicePanel.TEXT_SIZES[0] or not where.begins_with("'The farm'"),
        "the text of the farm fits the board at the usual size",
        "%s: %s" % [where, panel.text]
    )
    for text in [panel.title, panel.text]:
        _check_placeholders(text, where)
    var face := str(panel.face.get("picture", ""))
    _expect(
        face == "" or Pictures.of("faces", face) != null,
        "every face is painted",
        "%s: %s" % [where, face]
    )


func _check_card(font: Font, card: Dictionary, where: String) -> void:
    var title := str(card.get("title", ""))
    var detail := str(card.get("detail", ""))
    _check_placeholders(title, where)
    _check_placeholders(detail, where)
    if card.has("picture"):
        var picture: Array = card["picture"]
        _expect(
            picture.size() == 2 and Pictures.of(picture[0], picture[1]) != null,
            "every picture on a card is painted",
            "%s: %s %s" % [where, title, str(picture)]
        )
    # NOTE: As DwellButton._draw lays the card out.
    var top := 50.0
    if card.has("picture") or card.has("stars"):
        top = 124.0
    elif card.has("color"):
        top = 100.0
    var lines := ChoicePanel.wrap_text(font, title, CARD.x - 20.0, CARD_FONT)
    for line in lines:
        _expect(
            font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, CARD_FONT).x <= CARD.x - 10.0,
            "the title of a card fits its width",
            "%s: %s" % [where, title]
        )
    var painted := Pictures.of("ui", "card") != null
    var bottom := CARD.y - 8.0
    if detail != "":
        bottom = CARD.y - (30.0 if painted else 18.0) - font.get_ascent(DETAIL_FONT)
        _expect(
            (
                font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT).x
                <= CARD.x - 10.0
            ),
            "the detail of a card fits its width",
            "%s: %s" % [where, detail]
        )
    var last := top + (lines.size() - 1) * CARD_LINE + font.get_descent(CARD_FONT)
    _expect(
        last <= bottom,
        "the title of a card fits above its detail",
        "%s: '%s' / '%s' (%d lines)" % [where, title, detail, lines.size()]
    )


func _check_placeholders(text: String, where: String) -> void:
    for placeholder in PLACEHOLDERS:
        if placeholder in text:
            _report("no text shows a placeholder", "%s: %s" % [where, text])
            return


# ---------------------------------------------------------------------------
# The lakes
# ---------------------------------------------------------------------------


## Check the [param world] (see world.gd) on this frame.
func check_world(world: Node) -> void:
    var state: Node = world.state()
    var map: LakeMap = world.map()
    var boat: RowBoat = world.boat()
    var mode: String = world._mode
    var where := "day %d, %s" % [state.day, mode]

    _check_boat(map, boat, mode == "rowing" and _last_mode == "rowing", where)
    _last_mode = mode
    _frame += 1
    for npc in world.npcs() if _frame % NPC_EVERY == 0 else []:
        _expect(
            map.is_water(npc.position),
            "the skippers stay on the water",
            "%s at %s" % [npc.skipper["name"], npc.position]
        )
        var last: Vector2 = _npc_last.get(npc.get_instance_id(), npc.position)
        _expect(
            last.distance_to(npc.position) <= NpcBoat.SPEED * 0.2 * NPC_EVERY + SLACK,
            "the skippers never jump",
            "%s from %s to %s" % [npc.skipper["name"], last, npc.position]
        )
        _npc_last[npc.get_instance_id()] = npc.position

    var panel: ChoicePanel = world._panel
    var chart: bool = world._chart != null
    match mode:
        "rowing":
            _expect(
                state.place == "",
                "on the water, the boat is at no place",
                "%s: %s, after %s" % [where, state.place, _last_mode]
            )
            _expect(not panel.visible, "on the water, no screen shows", where)
        "port":
            _expect(state.place != "", "in a port, the state knows the place", where)
            _expect(panel.visible or chart, "in a port, a screen shows", where)
            if state.place != "":
                var berth: Vector2 = map.place(state.place)["berth"]
                _expect(
                    boat.speed == 0.0 and boat.position.distance_to(berth) < SLACK,
                    "in a port, the boat lies still at the berth",
                    "%s: %s, speed %.2f" % [state.place, boat.position, boat.speed]
                )
        "skipper":
            _expect(panel.visible or chart, "with a skipper, a screen shows", where)
            _expect(
                world._talking_to != null and world._talking_to.held,
                "the skipper waits while the players talk",
                where
            )
        _:
            _report("the world is rowing, in a port or with a skipper", mode)

    check_music("farm" if mode == "port" and state.place == "home" else "lakes", where)
    var ships: Ships = state.ships
    var kind: Dictionary = ships.data()
    _expect(
        world._ship_view == null or kind.has("drawn") == true,
        "only a ship with a drawing is drawn",
        ships.current
    )
    if kind.has("drawn"):
        _expect(
            world._ship_view != null and world._ship_view.look == kind["drawn"],
            "the ship drawn is the ship the players row",
            ships.current
        )
    check_state(state)


func _check_boat(map: LakeMap, boat: RowBoat, moving: bool, where: String) -> void:
    var at := boat.position
    _expect(
        is_finite(at.x) and is_finite(at.y) and is_finite(boat.heading),
        "the boat is somewhere",
        where
    )
    _expect(map.is_water(at), "the boat stays on the water", "%s at %s" % [where, at])
    if moving and _last_boat != Vector2.INF:
        _expect(
            not map.crosses_land(_last_boat, at),
            "the boat never crosses the land",
            "%s from %s to %s" % [where, _last_boat, at]
        )
    _last_boat = at
    _expect(
        boat.speed >= 0.0 and boat.speed <= RowBoat.MAX_SPEED * boat.top_share + SLACK,
        "the boat never goes faster than its ship can",
        "%s: %.2f" % [where, boat.speed]
    )


## Check the voyage in the [param state].
func check_state(state: Node) -> void:
    var where := "day %d" % state.day
    _expect(state.silver >= 0, "the silver never goes below zero", "%s: %d" % [where, state.silver])
    _expect(
        state.day >= _last_day,
        "the days never run backwards",
        "%d after %d" % [state.day, _last_day]
    )
    _last_day = state.day
    _expect(
        state.load_count() <= state.capacity,
        "the cargo fits the hold",
        "%s: %d of %d" % [where, state.load_count(), state.capacity]
    )
    var missions: Missions = state.missions
    var active := {}
    for entry in missions.active:
        _expect(not active.has(entry["id"]), "a task is under way once", entry["id"])
        active[entry["id"]] = true
        _expect(not missions.done.has(entry["id"]), "a task under way is not done", entry["id"])
    _expect(
        missions.active.size() <= Missions.MAX_ACTIVE,
        "at most three tasks are under way",
        str(active.keys())
    )
    for id in missions.done:
        _expect(
            int(missions.done[id]) >= 1 and int(missions.done[id]) <= 3,
            "a task done has one to three stars",
            "%s: %s" % [id, missions.done[id]]
        )
    for item in state.cargo:
        _expect(int(state.cargo[item]) > 0, "the cargo holds no empty crates", item)
        _expect(_known(state, item, active), "every crate in the boat is known", item)
    var ships: Ships = state.ships
    _expect(ships.current in ships.owned, "the players row a ship they own", ships.current)


func _known(state: Node, item: String, active: Dictionary) -> bool:
    if item.begins_with("animal:"):
        return state.farm.animal_kinds.has(item.trim_prefix("animal:"))
    if Missions.is_item(item):
        var parts := item.trim_prefix(Missions.PREFIX).split(":")
        return (
            parts.size() == 2
            and active.has(parts[0])
            and state.missions.missions[parts[0]].get("items", {}).has(parts[1])
        )
    return state.economy.goods.has(item)


## The voyage saved on the disk must be the one in memory.
func check_save(state: Node) -> void:
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(state.save_path))
    if not data is Dictionary:
        _report("the voyage is saved", state.save_path)
        return
    var where := "day %d at %s" % [state.day, state.place]
    var missions: Dictionary = state.missions.to_data()
    var same := {
        "silver": int(data.get("silver", -1)) == state.silver,
        "day": int(data.get("day", -1)) == state.day,
        "place": str(data.get("place", "")) == state.place,
        "cargo": _same(data.get("cargo", {}), state.cargo),
        "missions": _same(data.get("missions", {}), missions),
        "ships": _same(data.get("ships", {}), state.ships.to_data()),
        "farm": _same(data.get("farm", {}), state.farm.to_data()),
    }
    for key in same:
        _expect(same[key], "the save on the disk is the voyage in memory", "%s: %s" % [where, key])


## Whether two values are the same as JSON (whose numbers are all floats).
static func _same(a: Variant, b: Variant) -> bool:
    return (
        JSON.stringify(a, "", true)
        == JSON.stringify(JSON.parse_string(JSON.stringify(b)), "", true)
    )


# ---------------------------------------------------------------------------
# The party and the chase
# ---------------------------------------------------------------------------


## Check the party ([param level], see level.gd): the treats picked are the
## silver gained since the party began with [param silver].
func check_party(level: Node, silver: int) -> void:
    var map: LakeMap = level.map()
    _check_boat(map, level.boat(), true, "the party")
    _expect(
        map.is_water(level.ship().position),
        "the wedding longship stays on the water",
        str(level.ship().position)
    )
    check_music("party", "the party")
    var state: Node = level._state
    _expect(
        state.silver - silver == level.coins(),
        "every treat picked is a silver coin in the purse",
        "%d coins, %d silver more" % [level.coins(), state.silver - silver]
    )
    check_state(state)


## The music plays the [param mood] (see Audio.music).
func check_music(mood: String, where: String) -> void:
    _expect(
        Audio.mood() == mood,
        "the music fits where the players are",
        "%s: %s instead of %s" % [where, Audio.mood(), mood]
    )


## Check the [param chase] (see chase.gd).
func check_chase(chase: Node) -> void:
    check_music("chase", "the chase")
    var map: LakeMap = chase._map
    _check_boat(map, chase.boat(), chase.outcome() == "", "the chase")
    _expect(
        map.is_water(chase.pirates().position),
        "the pirates stay on the water",
        str(chase.pirates().position)
    )
    check_state(chase._state)
