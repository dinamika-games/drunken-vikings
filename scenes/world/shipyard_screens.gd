class_name ShipyardScreens
extends RefCounted

## The screens of Signe's shipyard (see Ships and world.gd): the ships which
## she builds and the players' own, each with how it rows; the players buy a
## ship, or take one of their own, and their cargo goes over into it.

var _world: Node
var _state: Node

## What Back does: the screen of the port.
var _back: Callable


func _init(world: Node, state: Node, back: Callable) -> void:
    _world = world
    _state = state
    _back = back


func _shipwright_face() -> Dictionary:
    var who: Dictionary = _state.ships.shipwright
    return {
        "hair": Color(str(who.get("hair", "8a5a2b"))),
        "braids": bool(who.get("braids", false)),
        "picture": str(who.get("picture", ""))
    }


## The ships of the shipwright, and the players' own.
func show(message := "") -> void:
    var ships: Ships = _state.ships
    var cards: Array = []
    var actions: Array[Callable] = []
    for id in ships.ids:
        var kind: Dictionary = ships.kinds[id]
        var detail := PortScreens.silver(int(kind["price"]))
        if id == ships.current:
            detail = ChoicePanel.detail("your ship")
        elif id in ships.owned:
            detail = ChoicePanel.detail("yours")
        (
            cards
            . append(
                {
                    "id": id,
                    "title": Grammar.title(kind["name"]),
                    "detail":
                    ChoicePanel.detail(
                        "{crates} crates, {detail}",
                        {"crates": ships.hold(id), "detail": Grammar.raw(detail)}
                    ),
                    "picture": kind["drawn"]["hull"] if kind.has("drawn") else ["rowboat", "hull"],
                }
            )
        )
        actions.append(_show_ship.bind(id))
    cards.append(ChoicePanel.card("Back"))
    actions.append(_back)
    var text := message
    if text == "":
        text = Grammar.text(
            (
                "Welcome to my shipyard! A bigger ship carries more, and its crew rows to your "
                + "beat. A ship you buy stays yours: take any of them, any time. Silver: {silver}."
            ),
            {"silver": _state.silver}
        )
    _world.show_screen(
        Grammar.text(ships.shipwright["yard"]), text, cards, actions, _shipwright_face()
    )


## How a share of the rowing boat reads: 2 for much more (e.g., "much
## faster" for 1.5), 1 for more, 0 for as much, -1 for less, -2 for much less.
static func _compared(share: float) -> int:
    if share >= 1.45:
        return 2
    if share >= 1.1:
        return 1
    if share <= 0.7:
        return -2
    if share <= 0.9:
        return -1
    return 0


func _show_ship(id: String) -> void:
    var ships: Ships = _state.ships
    var kind: Dictionary = ships.kinds[id]
    var lines: Array[String] = [Grammar.text(str(kind.get("about", "")))]
    var speed: String = [
        Grammar.text("as the rowing boat"),
        Grammar.text("faster"),
        Grammar.text("much faster"),
        Grammar.text("much slower"),
        Grammar.text("slower")
    ][_compared(float(kind["top"]))]
    var turns: String = [
        Grammar.text("as the rowing boat"),
        Grammar.text("quicker"),
        Grammar.text("much quicker"),
        Grammar.text("much slower"),
        Grammar.text("slower")
    ][_compared(float(kind["turn"]))]
    var glides: String = [
        Grammar.text("as the rowing boat"),
        Grammar.text("longer"),
        Grammar.text("much longer"),
        Grammar.text("much shorter"),
        Grammar.text("shorter")
    ][_compared(float(kind["glide"]))]
    var crew := (
        Grammar.text("{rowers} {rowers|rower|rowers}", {"rowers": int(kind["crew"])})
        if int(kind["crew"]) > 0
        else Grammar.text("just you")
    )
    lines.append(
        Grammar.text(
            (
                "Hold: {crates} crates. Crew: {rowers}. Speed: {speed}. "
                + "Turns: {turns}. Glides: {glides}."
            ),
            {
                "crates": ships.hold(id),
                "rowers": Grammar.raw(crew),
                "speed": Grammar.raw(speed),
                "turns": Grammar.raw(turns),
                "glides": Grammar.raw(glides)
            }
        )
    )
    var cards: Array = []
    var actions: Array[Callable] = []
    if id == ships.current:
        lines.append(Grammar.text("You row her now."))
    elif id in ships.owned:
        var fits: bool = _state.load_count() <= ships.hold(id)
        if not fits:
            lines.append(Grammar.text("Your cargo does not fit in her: sell or unload some first."))
        cards.append(ChoicePanel.card("Take her", ChoicePanel.detail("free"), {"enabled": fits}))
        actions.append(_take_ship.bind(id))
    else:
        var price := int(kind["price"])
        var fits: bool = _state.load_count() <= ships.hold(id)
        cards.append(
            ChoicePanel.card(
                "Buy her", PortScreens.silver(price), {"enabled": _state.silver >= price and fits}
            )
        )
        actions.append(_buy_ship.bind(id))
    cards.append(ChoicePanel.card("Back"))
    actions.append(show.bind(""))
    _world.show_screen(
        Grammar.title(kind["name"]), " ".join(lines), cards, actions, _shipwright_face()
    )


func _buy_ship(id: String) -> void:
    var ships: Ships = _state.ships
    if not ships.buy(_state, id):
        return
    ships.take(id, _state.load_count())
    Audio.play("jingle")
    _world.refit()
    _state.save()
    var crew := int(ships.kinds[id]["crew"])
    show(
        (
            (Grammar.text(
                (
                    "She is yours! Your cargo is aboard, and her crew of {rowers} rows to "
                    + "your beat. Fair winds! Silver: {silver}."
                ),
                {"rowers": crew, "silver": _state.silver}
            ))
            if crew > 0
            else (Grammar.text(
                (
                    "She is yours! Your cargo is aboard, and she rows to your "
                    + "beat. Fair winds! Silver: {silver}."
                ),
                {"silver": _state.silver}
            ))
        )
    )


func _take_ship(id: String) -> void:
    var ships: Ships = _state.ships
    if ships.take(id, _state.load_count()):
        Audio.play("creak")
        _world.refit()
        _state.save()
        show(
            Grammar.text(
                "Your cargo goes over into the {ship}. She is ready!",
                {"ship": ships.kinds[id]["name"]}
            )
        )
