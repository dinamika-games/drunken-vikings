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
##   so does the detail; all on a card (its texts, its picture with the hair
##   of a rower, its stars, its crate, its arrow) keeps a padding from the
##   painted frame, clear of the nails, and the picture keeps clear of the
##   title;
## * the title of the screen fits the board, and so does its text (a long
##   text a little smaller, see ChoicePanel.fit_text; the farm's at the
##   usual size);
## * no text shows a placeholder (e.g., "%d", "{place}", "<null>");
## * every picture on a card, and every face, is painted.
##
## On the lakes (see world.gd), on every frame:
##
## * the boat stays on the water (off the jetties, too) and never crosses
##   the land between two frames, nor goes faster than its ship can; so do
##   the boats of the skippers, which never jump either (their ways are
##   preconditions of the map, see tests/godot/test_map.gd);
## * the skippers keep clear of the players' boat: they never sail into it
##   while it goes slowly (see NpcBoat);
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
## happened. The example tells all that is needed to see what went wrong
## without running the test again: where (the screen, the day, the mode, the
## place), what was measured against what was allowed, and the state of what
## broke the contract (the boat, the skipper, the longship).
##
## Not a test itself (its name does not start with test_).

## The cards of ChoicePanel and how they draw (see ChoicePanel, DwellButton).
const SCREEN_WIDTH := 1920.0
const CARD := DwellButton.SIZE
const CARD_GAP := 34.0
const BOARD_WIDTH := 1100.0
const TITLE_FONT := 40

## All on a card keeps at least this far from the wood of its frame, and
## its picture this far above the letters of its title, in pixels.
const CARD_PADDING := 10.0
const PICTURE_GAP := 6.0

## The texts which betray a placeholder or a missing value.
const PLACEHOLDERS := ["%s", "%d", "%.", "{", "}", "<null>", "<Object", "[]", "Nil "]

## The boats of the skippers are checked on every this many frames.
const NPC_EVERY := 4

## A sailing skipper never comes closer to the players' boat than this, in
## metres between their middle lines (see NpcBoat.CLEARANCE), unless the
## players row faster than this, in metres a second (and run into the
## skipper), or the players' boat came to the skipper rather than the skipper
## to it.
const NPC_GAP := 6.0
const NPC_RAMMING := 2.0

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
## What each skipper saw of the players' boat on the last check (a
## _Sighting, by the instance id of the skipper).
var _npc_gap := {}
## How often the game put the players' boat somewhere (it docks at a berth,
## or undocks, turned to head out), see check_world.
var _placings := 0


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
    _npc_gap.clear()


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
        _expect(
            not titles.has(title),
            "no two cards are called the same",
            "%s: '%s' twice among %s" % [where, title, str(_titles(panel))]
        )
        titles[title] = true
        _check_card(font, card, where)
    _expect(
        enabled > 0,
        "the players can always go on",
        "%s: all %d cards disabled: %s" % [where, panel.cards.size(), str(_titles(panel))]
    )
    var count := panel.cards.size()
    _expect(
        count * CARD.x + (count - 1) * CARD_GAP <= SCREEN_WIDTH,
        "the cards fit the screen side by side",
        (
            "%s: %d cards take %.0f px of %.0f: %s"
            % [
                where,
                count,
                count * CARD.x + (count - 1) * CARD_GAP,
                SCREEN_WIDTH,
                str(_titles(panel))
            ]
        )
    )

    var left := 40.0 + (140.0 if not panel.face.is_empty() else 0.0)
    var width := BOARD_WIDTH - left - 40.0
    var title_width := (
        font.get_string_size(panel.title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT).x
    )
    _expect(
        title_width <= width,
        "the title of a screen fits the board",
        "%s: %.0f px wide at %d px, %.0f px free" % [where, title_width, TITLE_FONT, width]
    )
    var fitted := ChoicePanel.fit_text(font, panel.text, width)
    _expect(
        fitted["all"],
        "the text of a screen fits the board",
        (
            "%s: not all of it fits %.0f px even at %s px: %s"
            % [where, width, fitted["size"], panel.text]
        )
    )
    _expect(
        fitted["size"] == ChoicePanel.TEXT_SIZES[0] or not where.begins_with("'The farm'"),
        "the text of the farm fits the board at the usual size",
        (
            "%s: at %s px instead of %s px: %s"
            % [where, fitted["size"], ChoicePanel.TEXT_SIZES[0], panel.text]
        )
    )
    for text in [panel.title, panel.text]:
        _check_placeholders(text, where)
    var face := str(panel.face.get("picture", ""))
    _expect(
        face == "" or Pictures.of("faces", face) != null,
        "every face is painted",
        "%s: no picture faces/%s" % [where, face]
    )


func _check_card(font: Font, card: Dictionary, where: String) -> void:
    var title := str(card.get("title", ""))
    var detail := str(card.get("detail", ""))
    _check_placeholders(title, where)
    _check_placeholders(detail, where)
    if card.has("picture") and not card["picture"] is Texture2D:
        var picture: Array = card["picture"]
        _expect(
            picture.size() == 2 and Pictures.of(picture[0], picture[1]) != null,
            "every picture on a card is painted",
            "%s: card '%s' shows %s, which is not painted" % [where, title, str(picture)]
        )
    # NOTE: As DwellButton._draw lays the card out: no line runs into the
    # nails of the painted card (see DwellButton.line_width).
    var top := DwellButton.title_top(card)
    var painted := Pictures.of("ui", "card") != null
    var title_font := DwellButton.title_size(font, title, CARD, top, painted, detail != "")
    var lines := DwellButton.wrap_title(font, title, CARD, top, painted, title_font)
    for i in range(lines.size()):
        var at := top + i * DwellButton.TITLE_LINE
        var line_width := (
            font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, title_font).x
        )
        var free := DwellButton.line_width(font, CARD, at, title_font, painted)
        _expect(
            line_width <= free,
            "the title of a card fits its width, clear of the nails",
            (
                "%s: card '%s', line %d '%s' is %.0f px wide at %d px, %.0f px free"
                % [where, title, i + 1, lines[i], line_width, title_font, free]
            )
        )
    var bottom := CARD.y - 8.0
    if detail != "":
        var detail_font := DwellButton.detail_size(font, detail, CARD, painted)
        var baseline := DwellButton.detail_baseline(CARD, painted)
        bottom = baseline - font.get_ascent(detail_font)
        var detail_width := (
            font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_font).x
        )
        var detail_free := DwellButton.line_width(font, CARD, baseline, detail_font, painted)
        _expect(
            detail_width <= detail_free,
            "the detail of a card fits its width, clear of the nails",
            (
                "%s: card '%s', detail '%s' is %.0f px wide at %d px, %.0f px free"
                % [where, title, detail, detail_width, detail_font, detail_free]
            )
        )
    _check_card_padding(font, card, where, top, title_font, painted)
    var last := top + (lines.size() - 1) * DwellButton.TITLE_LINE + font.get_descent(title_font)
    _expect(
        last <= bottom,
        "the title of a card fits above its detail",
        (
            "%s: '%s' / '%s': %d lines at %d px end at %.0f px, the detail begins at %.0f px"
            % [where, title, detail, lines.size(), title_font, last, bottom]
        )
    )


## Check that all on the [param card] (on the screen [param where]) keeps
## clear of the frame (and of the nails) of the [param painted] card, and its
## picture clear of the title, which begins at the [param top] in the
## [param title_font].
func _check_card_padding(
    font: Font, card: Dictionary, where: String, top: float, title_font: int, painted: bool
) -> void:
    var title := str(card.get("title", ""))
    var detail := str(card.get("detail", ""))
    var inset := (DwellButton.PAPER_INSET if painted else 0.0) + CARD_PADDING
    var paper := Rect2(Vector2(inset, inset), CARD - 2.0 * Vector2(inset, inset))
    var letters_top := top - font.get_ascent(title_font)
    _expect(
        letters_top >= paper.position.y,
        "the title of a card keeps a padding from the frame",
        (
            "%s: card '%s' at %d px: its letters begin at %.0f px, the padding ends at %.0f px"
            % [where, title, title_font, letters_top, paper.position.y]
        )
    )
    if detail != "":
        var detail_font := DwellButton.detail_size(font, detail, CARD, painted)
        var detail_bottom := (
            DwellButton.detail_baseline(CARD, painted) + font.get_descent(detail_font)
        )
        _expect(
            detail_bottom <= paper.end.y,
            "the detail of a card keeps a padding from the frame",
            (
                "%s: card '%s', detail '%s' at %d px: ends at %.0f px, the padding at %.0f"
                % [where, title, detail, detail_font, detail_bottom, paper.end.y]
            )
        )
    # NOTE: Whatever is drawn above the title (the picture, the stars or the
    # crate), and the arrow of the mood, lies within the box of the picture,
    # or the picture itself is checked.
    var drawn: Array[Rect2] = []
    var picture := DwellButton.picture_of(card)
    if picture != null:
        drawn.append(DwellButton.picture_rect(picture, CARD))
    elif card.has("stars") or card.has("color"):
        drawn.append(DwellButton.picture_box(CARD))
    if int(card.get("mood", 0)) != 0:
        drawn.append(Rect2(DwellButton.mood_at(CARD) - Vector2(12, 16), Vector2(24, 32)))
    var nails: Array[Rect2] = []
    if painted:
        for x in [DwellButton.NAIL.x, CARD.x - DwellButton.NAIL.x]:
            for y in [DwellButton.NAIL.y, CARD.y - DwellButton.NAIL.y]:
                nails.append(
                    Rect2(
                        Vector2(x, y) - Vector2.ONE * DwellButton.NAIL_CLEAR,
                        Vector2.ONE * 2.0 * DwellButton.NAIL_CLEAR
                    )
                )
    for rect in drawn:
        _expect(
            paper.encloses(rect),
            "the picture of a card keeps a padding from the frame",
            (
                "%s: card '%s' draws %s, the padded paper is %s (e.g., hair on the frame)"
                % [where, title, str(rect), str(paper)]
            )
        )
        for nail in nails:
            _expect(
                not nail.intersects(rect),
                "the picture of a card keeps clear of the nails",
                "%s: card '%s' draws %s over the nail %s" % [where, title, str(rect), str(nail)]
            )
    if not drawn.is_empty():
        _expect(
            drawn[0].end.y + PICTURE_GAP <= letters_top,
            "the picture of a card keeps clear of its title",
            (
                "%s: card '%s': the picture ends at %.0f px, the title begins at %.0f px"
                % [where, title, drawn[0].end.y, letters_top]
            )
        )


## The titles of the cards on the screen of the [param panel].
static func _titles(panel: ChoicePanel) -> Array:
    var result := []
    for card: Dictionary in panel.cards:
        result.append(
            str(card.get("title", "")) + ("" if bool(card.get("enabled", true)) else " (disabled)")
        )
    return result


func _check_placeholders(text: String, where: String) -> void:
    for placeholder in PLACEHOLDERS:
        if placeholder in text:
            _report("no text shows a placeholder", "%s: '%s' in %s" % [where, placeholder, text])
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
    var where := (
        "day %d, %s (after %s), at '%s', on the %s"
        % [state.day, mode, _last_mode, state.place, state.ships.current]
    )

    _check_boat(map, boat, mode == "rowing" and _last_mode == "rowing", where)
    if (mode == "rowing") != (_last_mode == "rowing"):
        _placings += 1
    _last_mode = mode
    _frame += 1
    for npc: NpcBoat in world.npcs() if _frame % NPC_EVERY == 0 else []:
        var last: Vector2 = _npc_last.get(npc.get_instance_id(), npc.position)
        _expect(
            map.is_water(npc.position),
            "the skippers stay on the water",
            (
                "%s: %s, %s, came from %s; %s"
                % [where, npc.describe(), _near(map, npc.position), last, _boat_text(boat)]
            )
        )
        var allowed := NpcBoat.SPEED * 0.2 * NPC_EVERY + SLACK
        _expect(
            last.distance_to(npc.position) <= allowed,
            "the skippers never jump",
            (
                "%s: %s, came %.1f m from %s in %d frames (at most %.1f m)"
                % [where, npc.describe(), last.distance_to(npc.position), last, NPC_EVERY, allowed]
            )
        )
        _npc_last[npc.get_instance_id()] = npc.position
        # NOTE: The skippers can not help it when the players' boat comes
        # to lie beside them: when it docks (it is put at the berth) or
        # undocks (it is turned to head out), when the players hail them
        # (they stop beside the boat), and when the players row or turn their
        # boat into them. The skippers only never sail into where the
        # players' boat lay (nor deeper, once close), unless they flee the
        # boat as it lies now (a long boat turned onto them sweeps its hull
        # over where it lay).
        var gap: float = npc.gap_to_players()
        var before: _Sighting = _npc_gap.get(
            npc.get_instance_id(), _Sighting.new(INF, boat, npc, _placings)
        )
        if before.placings != _placings:
            # NOTE: Put there by the game since the last look: nothing to
            # compare with.
            before = _Sighting.new(0.0, boat, npc, _placings)
        var length := npc.players_length
        var sailed_into := _gap_to(npc, before.at, before.heading, length)
        var fled := (
            _gap_to(npc, boat.position, boat.heading, length)
            >= (
                _gap_between(
                    before.skipper_at, before.skipper_heading, boat.position, boat.heading, length
                )
                - SLACK
            )
        )
        _expect(
            (
                not npc.sailing()
                or boat.speed > NPC_RAMMING
                or gap >= NPC_GAP
                or sailed_into >= minf(NPC_GAP, before.gap - SLACK)
                or fled
            ),
            "the skippers keep clear of the players' boat",
            (
                (
                    "%s: %s, %.1f m before (keep %.1f m), %.1f m from where the boat lay"
                    + " at %s heading %.0f°; %s"
                )
                % [
                    where,
                    npc.describe(),
                    before.gap,
                    NPC_GAP,
                    sailed_into,
                    before.at,
                    rad_to_deg(before.heading),
                    _boat_text(boat)
                ]
            )
        )
        _npc_gap[npc.get_instance_id()] = _Sighting.new(gap, boat, npc, _placings)

    var panel: ChoicePanel = world._panel
    var chart: bool = world._chart != null
    match mode:
        "rowing":
            _expect(
                state.place == "",
                "on the water, the boat is at no place",
                "%s: %s" % [where, _boat_text(boat)]
            )
            _expect(
                not panel.visible,
                "on the water, no screen shows",
                "%s: the screen '%s' shows" % [where, panel.title]
            )
        "port":
            _expect(
                state.place != "",
                "in a port, the state knows the place",
                "%s: %s, %s" % [where, _boat_text(boat), _near(map, boat.position)]
            )
            _expect(
                panel.visible or chart,
                "in a port, a screen shows",
                "%s: neither a screen nor the map shows" % where
            )
            if state.place != "":
                var berth: Vector2 = map.place(state.place)["berth"]
                _expect(
                    boat.speed == 0.0 and boat.position.distance_to(berth) < SLACK,
                    "in a port, the boat lies still at the berth",
                    (
                        "%s: %s, %.2f m from the berth %s"
                        % [where, _boat_text(boat), boat.position.distance_to(berth), berth]
                    )
                )
        "skipper":
            _expect(
                panel.visible or chart,
                "with a skipper, a screen shows",
                "%s: neither a screen nor the map shows" % where
            )
            var talking: NpcBoat = world._talking_to
            _expect(
                talking != null and talking.held,
                "the skipper waits while the players talk",
                (
                    "%s: %s"
                    % [where, talking.describe() if talking != null else "no skipper to talk to"]
                )
            )
        _:
            _report("the world is rowing, in a port or with a skipper", "%s: '%s'" % [where, mode])

    check_music("farm" if mode == "port" and state.place == "home" else "lakes", where)
    var ships: Ships = state.ships
    var kind: Dictionary = ships.data()
    _expect(
        world._ship_view == null or kind.has("drawn") == true,
        "only a ship with a drawing is drawn",
        "%s: the %s has no drawing, yet a ship is drawn" % [where, ships.current]
    )
    if kind.has("drawn"):
        var drawn: Variant = world._ship_view.look if world._ship_view != null else null
        _expect(
            world._ship_view != null and drawn == kind["drawn"],
            "the ship drawn is the ship the players row",
            "%s: the %s should look %s, drawn %s" % [where, ships.current, kind["drawn"], drawn]
        )
    check_state(state)


func _check_boat(map: LakeMap, boat: RowBoat, moving: bool, where: String) -> void:
    var at := boat.position
    _expect(
        is_finite(at.x) and is_finite(at.y) and is_finite(boat.heading),
        "the boat is somewhere",
        "%s: %s" % [where, _boat_text(boat)]
    )
    _expect(
        map.is_water(at),
        "the boat stays on the water",
        "%s: %s, %s, came from %s" % [where, _boat_text(boat), _near(map, at), _last_boat]
    )
    if moving and _last_boat != Vector2.INF:
        _expect(
            not map.crosses_land(_last_boat, at),
            "the boat never crosses the land",
            (
                "%s: %s, came %.1f m from %s, %s"
                % [where, _boat_text(boat), _last_boat.distance_to(at), _last_boat, _near(map, at)]
            )
        )
    _last_boat = at
    var top := RowBoat.MAX_SPEED * boat.top_share
    _expect(
        boat.speed >= 0.0 and boat.speed <= top + SLACK,
        "the boat never goes faster than its ship can",
        "%s: %s, at most %.2f m/s" % [where, _boat_text(boat), top]
    )


## How far the middle line of the skipper's boat ([param npc]) is from the
## middle line of a boat [param length] long at [param at], heading
## [param heading].
static func _gap_to(npc: NpcBoat, at: Vector2, heading: float, length: float) -> float:
    return _gap_between(npc.position, npc.heading, at, heading, length)


## How far the middle line of a skipper's boat lying [param npc_at], heading
## [param npc_heading], is from the middle line of a boat of the [param length]
## lying [param at], heading [param heading].
static func _gap_between(
    npc_at: Vector2, npc_heading: float, at: Vector2, heading: float, length: float
) -> float:
    var mine := Vector2.UP.rotated(npc_heading) * NpcBoat.LENGTH / 2.0
    var theirs := Vector2.UP.rotated(heading) * length / 2.0
    var closest := Geometry2D.get_closest_points_between_segments(
        npc_at - mine, npc_at + mine, at - theirs, at + theirs
    )
    return closest[0].distance_to(closest[1])


## The players' [param boat] in one line.
static func _boat_text(boat: RowBoat) -> String:
    return (
        "the boat at %s heading %.0f°, %.2f m/s, steering %+.2f%s (bow %.1f m)"
        % [
            boat.position,
            rad_to_deg(boat.heading),
            boat.speed,
            boat.steer,
            ", braking" if boat.brake else "",
            boat.bow
        ]
    )


## Where the [param point] is on the [param map]: how far from the nearest berth.
static func _near(map: LakeMap, point: Vector2) -> String:
    var nearest := {}
    for place: Dictionary in map.places:
        if (
            nearest.is_empty()
            or (point.distance_to(place["berth"]) < point.distance_to(nearest["berth"]))
        ):
            nearest = place
    if nearest.is_empty():
        return "no place on the map"
    return (
        "%.0f m from the berth of %s (%.0f m from its jetty end)"
        % [point.distance_to(nearest["berth"]), nearest["id"], point.distance_to(nearest["jetty"])]
    )


## The [param ship] (the wedding longship or the pirates) in one line.
static func _longship_text(ship: Longship) -> String:
    return (
        "at %s heading %.0f°, %.2f m/s, %.0f m along its way%s%s"
        % [
            ship.position,
            rad_to_deg(ship.heading),
            ship.speed,
            ship.progress,
            ", waiting" if ship.waiting else "",
            ", arrived" if ship.arrived else ""
        ]
    )


## Check the voyage in the [param state].
func check_state(state: Node) -> void:
    var where := "day %d at '%s'" % [state.day, state.place]
    _expect(state.silver >= 0, "the silver never goes below zero", "%s: %d" % [where, state.silver])
    _expect(
        state.day >= _last_day,
        "the days never run backwards",
        "%s, after day %d" % [where, _last_day]
    )
    _last_day = state.day
    _expect(
        state.load_count() <= state.capacity,
        "the cargo fits the hold",
        (
            "%s: %d of %d on the %s: %s"
            % [where, state.load_count(), state.capacity, state.ships.current, state.cargo]
        )
    )
    var missions: Missions = state.missions
    var active := {}
    var under_way := []
    for entry in missions.active:
        under_way.append(entry["id"])
    for entry in missions.active:
        _expect(
            not active.has(entry["id"]),
            "a task is under way once",
            "%s: %s among %s" % [where, entry["id"], under_way]
        )
        active[entry["id"]] = true
        _expect(
            not missions.done.has(entry["id"]),
            "a task under way is not done",
            "%s: %s, done with %s stars" % [where, entry["id"], missions.done.get(entry["id"])]
        )
    _expect(
        missions.active.size() <= Missions.MAX_ACTIVE,
        "at most three tasks are under way",
        "%s: %s" % [where, under_way]
    )
    for id in missions.done:
        _expect(
            int(missions.done[id]) >= 1 and int(missions.done[id]) <= 3,
            "a task done has one to three stars",
            "%s: %s with %s stars" % [where, id, missions.done[id]]
        )
    for item in state.cargo:
        _expect(
            int(state.cargo[item]) > 0,
            "the cargo holds no empty crates",
            "%s: %s x %s in %s" % [where, item, state.cargo[item], state.cargo]
        )
        _expect(
            _known(state, item, active),
            "every crate in the boat is known",
            "%s: %s is no good, animal nor item of a task under way %s" % [where, item, under_way]
        )
    var ships: Ships = state.ships
    _expect(
        ships.current in ships.owned,
        "the players row a ship they own",
        "%s: the %s, owning %s" % [where, ships.current, ships.owned]
    )


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
        _report(
            "the voyage is saved",
            "day %d at '%s': %s holds no voyage" % [state.day, state.place, state.save_path]
        )
        return
    var where := "day %d at %s" % [state.day, state.place]
    var missions: Dictionary = state.missions.to_data()
    var memory := {
        "silver": state.silver,
        "day": state.day,
        "place": state.place,
        "cargo": state.cargo,
        "missions": missions,
        "ships": state.ships.to_data(),
        "farm": state.farm.to_data(),
    }
    for key in memory:
        _expect(
            data.has(key) and _same(data[key], memory[key]),
            "the save on the disk is the voyage in memory",
            (
                "%s: the %s saved is %s, in memory %s"
                % [
                    where,
                    key,
                    JSON.stringify(data.get(key)).left(300),
                    JSON.stringify(memory[key]).left(300)
                ]
            )
        )


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
        (
            "the party: the longship %s, %s; %s"
            % [
                _longship_text(level.ship()),
                _near(map, level.ship().position),
                _boat_text(level.boat())
            ]
        )
    )
    check_music("party", "the party")
    var state: Node = level._state
    _expect(
        state.silver - silver == level.coins(),
        "every treat picked is a silver coin in the purse",
        (
            "the party: %d coins picked, but %d silver more (%d now, %d at the start)"
            % [level.coins(), state.silver - silver, state.silver, silver]
        )
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
        (
            "the chase: the pirates %s, %s; %s"
            % [
                _longship_text(chase.pirates()),
                _near(map, chase.pirates().position),
                _boat_text(chase.boat())
            ]
        )
    )
    check_state(chase._state)


## What a skipper saw of the players' boat on a check: how far apart the
## boats were, where the boat lay and how it headed, where the skipper lay
## and how it headed, and how often the game had put the boat somewhere by
## then (see Contracts._placings).
class _Sighting:
    var gap: float
    var at: Vector2
    var heading: float
    var skipper_at: Vector2
    var skipper_heading: float
    var placings: int

    func _init(apart: float, boat: RowBoat, npc: NpcBoat, placed: int) -> void:
        gap = apart
        at = boat.position
        heading = boat.heading
        skipper_at = npc.position
        skipper_heading = npc.heading
        placings = placed
