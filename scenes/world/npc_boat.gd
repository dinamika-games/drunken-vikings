class_name NpcBoat
extends Node2D

## A boat of the lakes with its skipper (see Gossip.SKIPPERS): it sails the
## ways between the settlements (see LakeMap.routes), waits a while at a
## jetty, and sets out to another place. When the players hail it, it stops
## beside them until they are done talking.
##
## The skipper keeps clear of the players' boat: they look where it will be
## in the next seconds, and when their way would come too close, they turn
## aside (away from the players, and only where the water lies open), or wait
## when no way is clear; then they come back to their way. A boat moored where
## the players come to lie makes room for them.

## How fast the boat goes, in metres per second.
const SPEED := 4.5

## How long it waits at a jetty, in seconds.
const WAIT := Vector2(6.0, 14.0)

## How quickly the boat comes to its speed, stops, and turns its hull to its
## course (the time constants, in seconds).
const SPEED_SECONDS := 1.5
const STOP_SECONDS := 0.5
const TURN_SECONDS := 0.7

## How much larger than life we draw the boat, as the players' boat.
const SCALE := 2.6

## How long the boat is, in metres (the painted boat is 7 long in the units of
## the drawing).
const LENGTH := 7.0 * SCALE

## The skipper keeps the middle line of their boat this far from the middle
## line of the players' boat, in metres: half of the both beams with their
## oars, and some room.
const CLEARANCE := 12.0

## How far ahead the skipper looks for the players' boat, in seconds, and in
## which steps.
const LOOK_AHEAD := 5.0
const LOOK_STEP := 0.25

## The turns which the skipper tries to keep clear, in degrees, the smaller
## first; the boat waits instead of turning more than [constant WAIT_BEFORE].
const SWERVES := [20.0, 40.0, 60.0, 90.0, 120.0, 150.0]
const WAIT_BEFORE := 90.0

## How often a boat off its way looks whether the land lies between it and
## the next point of its way, in seconds.
const AIM_EVERY := 0.5

## The course which the boat keeps clear on already counts as if it kept this
## much further clear, in metres, against the other ways.
const KEEP_BONUS := 1.0

## A turn aside must lie on the open water this far ahead, in metres.
const SWERVE_LOOK := 12.0

## The skipper gives up a point of their way which the players block when
## they are this close to it, in metres, and half the length of the players'
## boat more, and sails on to the next one (or moors there, at the end of the
## way).
const GIVE_UP := 25.0

const HULL := Color("7a4f28")
const HULL_DARK := Color("5a3a1e")

## The skipper (see Gossip.skipper).
var skipper := {}

## Whether the boat stops for the players (while they talk).
var held := false

## Seconds until the skipper hails the players again.
var cooldown := 0.0

## Where the boat heads, in radians: 0 points north, clockwise.
var heading := 0.0

## The boat of the players, which the skipper keeps clear of (none in tests).
var players: RowBoat

## How long the players' boat is, in metres (their ship, see World.refit).
var players_length := 6.4

var _map: LakeMap
var _rng := RandomNumberGenerator.new()
var _at_place := ""
var _to_place := ""
var _path := PackedVector2Array()
var _index := 0
var _wait := 0.0
var _time := 0.0
var _speed := 0.0
## Where the boat goes now, a unit vector.
var _course := Vector2.UP
## Where the boat set out from.
var _origin := Vector2.ZERO
## Whether the boat left its way to keep clear (it then must not cut over the
## land to come back to it).
var _off_route := false
## To which side the boat turns to keep clear (1 or -1; 0 when it does not).
var _swerve_side := 0.0
## Whether the boat comes back to its way along the grid of the water (see
## [method _rejoin]).
var _rejoining := false
## Seconds until the boat off its way looks again whether the land lies
## between it and the next point of its way, and whether it did.
var _aim_clock := 0.0
var _aim_blocked := false
## How fast the players' boat turns, in radians a second, as seen from frame
## to frame, and its heading on the last frame.
var _players_turn := 0.0
var _players_heading := NAN


## Start at the berth of the place (beside the end of its jetty, on the
## water), with the skipper, on the [param map].
func setup(map: LakeMap, place_id: String, who: Dictionary, seed: int) -> void:
    _map = map
    skipper = who
    _rng.seed = seed
    _at_place = place_id
    position = map.place(place_id)["berth"]
    _wait = _rng.randf_range(0.0, WAIT.y)
    _time = _rng.randf() * 10.0


## Whether the boat sails now (not waiting at a jetty, not held).
func sailing() -> bool:
    return not held and _wait <= 0.0 and _index < _path.size()


func _process(delta: float) -> void:
    _time += delta
    cooldown = maxf(0.0, cooldown - delta)
    if _map == null:
        return
    _watch_players(delta)
    if held:
        # NOTE: The skipper stops beside the players, not on them.
        _make_room(delta)
    elif _wait > 0.0:
        _wait -= delta
        _make_room(delta)
        if _wait <= 0.0:
            _set_out()
    elif _index < _path.size():
        _sail(delta)
    rotation = heading
    queue_redraw()


## Sail along the way for a frame, clear of the players.
func _sail(delta: float) -> void:
    var target := _path[_index]
    var aim := _aim(delta)
    var direct := (aim - position).normalized() if aim != position else _course
    var velocity := _keep_clear(direct, SPEED)
    var swerving := not velocity.is_equal_approx(direct * SPEED)
    var give_up := GIVE_UP + players_length / 2.0
    if swerving and position.distance_to(target) < give_up and _blocked(target):
        _index += 1
        _off_route = true
        _aim_clock = 0.0
        if _index >= _path.size():
            _moor()
        return
    if velocity == Vector2.ZERO:
        _speed = lerpf(_speed, 0.0, 1.0 - exp(-delta / STOP_SECONDS))
    else:
        _course = velocity.normalized()
        _speed = lerpf(_speed, SPEED, 1.0 - exp(-delta / SPEED_SECONDS))
    var step := _speed * delta
    if not swerving and aim == target and position.distance_to(target) <= step:
        position = target
        _index += 1
        _off_route = false
        _rejoining = false
        if _index >= _path.size():
            _moor()
        return
    var blocked := not _map.is_water(position + _course * step)
    if blocked or ((swerving or _off_route) and not _open(_course, step)):
        # NOTE: Keeping clear never runs the boat onto the land; off its way,
        # the boat finds its way back to the next point on the water. (Looking
        # along a line for the land, in steps, may miss the tip of a cape.)
        _speed = 0.0
        if not swerving:
            _off_route = true
            _rejoin(target)
        return
    var gap := gap_to_players()
    var was_at := position
    var was_heading := heading
    position += _course * step
    if step > 0.0:
        heading = wrapf(
            lerp_angle(heading, _course.angle() + PI / 2.0, 1.0 - exp(-delta / TURN_SECONDS)),
            -PI,
            PI
        )
    # NOTE (mristin):
    # Too close to the players already, the skipper never sails any closer,
    # not even by the sweep of its hull as it turns: it slides aside instead,
    # as when moored, and sails on once clear.
    if gap < CLEARANCE and gap_to_players() < gap:
        position = was_at
        heading = was_heading
        _make_room(delta)
        return
    if swerving and step > 0.0 and not _off_route:
        _off_route = true
        _aim_clock = 0.0


## Come back to the [param target], the next point of the way, along the
## grid of the water (see LakeMap.water_path), which keeps off the shores.
func _rejoin(target: Vector2) -> void:
    if _rejoining:
        return
    var way := _map.water_path(position, target)
    if way.is_empty():
        return
    _rejoining = true
    # NOTE: The first cell of the grid is the free one nearest to the boat,
    # which leads it off the shore.
    var path := _path.slice(0, _index)
    path.append_array(way)
    path.append_array(_path.slice(_index))
    _path = path


func _moor() -> void:
    _at_place = _to_place
    _wait = _rng.randf_range(WAIT.x, WAIT.y)
    _speed = 0.0
    _swerve_side = 0.0


## Where the boat heads to come to the next point of its way: straight there,
## unless it left its way and the land lies between, then back to its way.
func _aim(delta: float) -> Vector2:
    var target := _path[_index]
    if not _off_route:
        return target
    # NOTE: Looking along the whole line for the land is dear: the boat looks
    # again only now and then, and is back on a safe way once the line is
    # clear (it then sails straight there, as on its way).
    _aim_clock -= delta
    if _aim_clock <= 0.0:
        _aim_clock = AIM_EVERY
        _aim_blocked = _map.crosses_land(position, target)
        if not _aim_blocked and _swerve_side == 0.0:
            _off_route = false
    if not _aim_blocked:
        return target
    var from := _path[_index - 1] if _index > 0 else _origin
    var back := Geometry2D.get_closest_point_to_segment(position, from, target)
    # NOTE: Aim a little further along the way, to join it rather than only
    # come ever closer to it.
    return back.move_toward(target, SWERVE_LOOK)


## While moored or held, slide aside slowly (keeping the heading, as pushed off)
## when the players' boat lies on this one, straight away from it or as close
## to that as the water lies open.
func _make_room(delta: float) -> void:
    _speed = 0.0
    if players == null or gap_to_players() >= CLEARANCE:
        return
    var theirs := _players_line()
    var away := position - Geometry2D.get_closest_point_to_segment(position, theirs[0], theirs[1])
    if away.length() < 0.01:
        away = players.forward().orthogonal()
    var step := SPEED * 0.5 * delta
    for degrees: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
        var way := away.normalized().rotated(deg_to_rad(degrees))
        if _open(way, SWERVE_LOOK):
            position += way * step
            _speed = SPEED * 0.5
            _off_route = true
            _aim_clock = 0.0
            return


## The velocity which keeps clear of the players, as close as may be to going
## [param direct] at [param speed]: turned aside a little, or still, or
## turned more; the turn which keeps clear the longest
## when none keeps clear all the time.
func _keep_clear(direct: Vector2, speed: float) -> Vector2:
    if players == null or _far_from_players():
        _swerve_side = 0.0
        return direct * speed
    var now := gap_to_players()
    var best := direct * speed
    var best_look := _look(best)
    if is_inf(best_look.conflict):
        _swerve_side = 0.0
        return best
    var side := _swerve_side
    if side == 0.0:
        var from_players := position - players.position
        var right := direct.rotated(0.3).dot(from_players)
        side = 1.0 if right >= direct.rotated(-0.3).dot(from_players) else -1.0
    var candidates: Array[Vector2] = []
    # NOTE: The course which the boat keeps clear on already comes first,
    # so that it does not waver between two ways, its hull never turned to
    # either.
    var kept := _course * speed
    if _swerve_side != 0.0 and absf(direct.angle_to(_course)) <= deg_to_rad(WAIT_BEFORE):
        candidates.append(kept)
    var waits := false
    for degrees: float in SWERVES:
        if degrees > WAIT_BEFORE and not waits:
            candidates.append(Vector2.ZERO)
            waits = true
        for turn: float in [side, -side]:
            candidates.append(direct.rotated(deg_to_rad(degrees) * turn) * speed)
    # NOTE: Straight on, the hull sweeps nothing as it does not turn.
    candidates.append(Vector2.UP.rotated(heading) * speed)
    # NOTE: Whether the water lies open is dear to tell: the boat looks only
    # at the ways which would keep it clear.
    for velocity in candidates:
        var look := _look(velocity)
        # NOTE (mristin):
        # The course kept counts as further clear only while it sails no
        # closer than the boat is now; otherwise, the bonus would let the
        # skipper sail into the players' boat once too close beside it.
        if velocity == kept and look.closest >= minf(now, CLEARANCE):
            look.closest += KEEP_BONUS
        if not is_inf(look.conflict) and not look.better(best_look):
            continue
        if velocity != Vector2.ZERO and not _open(velocity.normalized(), SWERVE_LOOK):
            continue
        if is_inf(look.conflict):
            _swerve_side = signf(direct.cross(velocity)) if velocity != Vector2.ZERO else side
            return velocity
        best = velocity
        best_look = look
    if best != direct * speed and best != Vector2.ZERO:
        _swerve_side = signf(direct.cross(best))
    return best


## What the boat does now, in one line, to tell what went wrong (e.g., in the
## contracts of the end-to-end test).
func describe() -> String:
    var doing := ""
    if held:
        doing = "held by the players"
    elif _wait > 0.0:
        doing = "moored at %s for %.1f s more" % [_at_place, _wait]
    elif _index < _path.size():
        doing = (
            "sailing from %s to %s, at point %d of %d %s (%.1f m away)%s"
            % [
                _at_place,
                _to_place,
                _index,
                _path.size(),
                _path[_index],
                position.distance_to(_path[_index]),
                ", off its way" if _off_route else ""
            ]
        )
    else:
        doing = "idle at %s" % _at_place
    var swerve := ""
    if _swerve_side != 0.0:
        swerve = ", keeping clear to the %s" % ("right" if _swerve_side > 0.0 else "left")
    var to_players := ""
    if players != null:
        to_players = (
            ", %.1f m from the players' boat (%.1f m long)" % [gap_to_players(), players_length]
        )
    return (
        "%s at %s heading %.0f°, %.2f m/s along %s, %s%s%s, hails again in %.0f s"
        % [
            skipper.get("name", "?"),
            position,
            rad_to_deg(heading),
            _speed,
            _course,
            doing,
            swerve,
            to_players,
            cooldown
        ]
    )


## How far the middle lines of this boat and the players' boat are apart now,
## in metres (INF without the players).
func gap_to_players() -> float:
    return _gap_at(Vector2.ZERO, 0.0) if players != null else INF


## Whether the players are too far to matter in the next seconds.
func _far_from_players() -> bool:
    var reach := (
        (SPEED + absf(players.speed)) * LOOK_AHEAD + (LENGTH + players_length) / 2.0 + CLEARANCE
    )
    return position.distance_squared_to(players.position) > reach * reach


## Whether the players' boat lies on the [param point] (or close to it).
func _blocked(point: Vector2) -> bool:
    var theirs := _players_line()
    var closest := Geometry2D.get_closest_point_to_segment(point, theirs[0], theirs[1])
    return closest.distance_to(point) < CLEARANCE + LENGTH / 2.0


## Whether the water lies open [param distance] ahead in the [param way].
func _open(way: Vector2, distance: float) -> bool:
    var ahead := position + way * maxf(distance, 0.5)
    return _map.is_water(ahead) and not _map.crosses_land(position, ahead)


## See how fast the players' boat turns.
func _watch_players(delta: float) -> void:
    if players == null or delta <= 0.0:
        return
    if not is_nan(_players_heading):
        var turn := angle_difference(_players_heading, players.heading) / delta
        _players_turn = lerpf(_players_turn, turn, 1.0 - exp(-delta / 0.2))
    _players_heading = players.heading


## The middle line of the players' boat, from its stern to its bow, after
## [param seconds] if it goes on as it goes now (and turns as it turns now,
## by a quarter at most).
func _players_line(seconds := 0.0) -> PackedVector2Array:
    var turned := clampf(_players_turn * seconds, -PI / 2.0, PI / 2.0)
    var ahead := Vector2.UP.rotated(players.heading + turned)
    var middle := players.position + players.forward() * players.speed * seconds
    var half := ahead * players_length / 2.0
    return PackedVector2Array([middle - half, middle + half])


## How far the middle lines of the two boats are apart after [param seconds],
## this boat setting out at [param velocity] now: as in [method _sail], it
## takes the course at once, but comes to its speed and turns its hull to the
## course only little by little.
func _gap_at(velocity: Vector2, seconds: float, players_seconds := NAN) -> float:
    var target := velocity.length()
    var way := velocity / target if target > 0.0 else _course
    var ease := SPEED_SECONDS if target > 0.0 else STOP_SECONDS
    var travelled := target * seconds + (_speed - target) * ease * (1.0 - exp(-seconds / ease))
    var turned := heading
    if target > 0.0:
        turned = lerp_angle(heading, way.angle() + PI / 2.0, 1.0 - exp(-seconds / TURN_SECONDS))
    return _gap_along(
        position + way * travelled,
        Vector2.UP.rotated(turned),
        _players_line(seconds if is_nan(players_seconds) else players_seconds)
    )


func _gap_along(middle: Vector2, ahead: Vector2, theirs: PackedVector2Array) -> float:
    var half := ahead * LENGTH / 2.0
    var closest := Geometry2D.get_closest_points_between_segments(
        middle - half, middle + half, theirs[0], theirs[1]
    )
    return closest[0].distance_to(closest[1])


## What the skipper sees ahead, going at [param velocity] (see _Look).
##
## Once already closer than [constant CLEARANCE], the skipper looks only at
## where the players' boat lies now, not where it glides: else it would pass
## behind the gliding boat, through where the boat lies, which it must
## never sail into (the boat may stop any time).
func _look(velocity: Vector2) -> _Look:
    var conflict := INF
    var closest := INF
    var gap := INF
    var seconds := 0.0
    var lying := NAN if gap_to_players() >= CLEARANCE else 0.0
    while seconds <= LOOK_AHEAD:
        gap = _gap_at(velocity, seconds, lying)
        if gap < CLEARANCE and is_inf(conflict):
            conflict = seconds
        if seconds > 0.0:
            closest = minf(closest, gap)
        seconds += LOOK_STEP
    return _Look.new(conflict, closest, gap)


func _set_out() -> void:
    var others: Array = []
    for place in _map.places:
        if place["id"] != _at_place and place["id"] != "home":
            others.append(place["id"])
    if others.is_empty():
        return
    _to_place = others[_rng.randi() % others.size()]
    # NOTE (mristin):
    # The routes run from jetty to jetty, whose ends count as land: the boat
    # leaves from the berth and moors at the berth instead.
    # NOTE: The routes run from berth to berth, clear of the shores and the
    # jetties (see dev/maps/make_lakes.py and tests/godot/test_map.gd).
    sail_along(_map.route_between(_at_place, _to_place), _to_place)


## Sail along the [param path] (from where the boat is) to the place
## [param place_id].
func sail_along(path: PackedVector2Array, place_id: String) -> void:
    _to_place = place_id
    _path = path
    _index = 0
    _origin = position
    _off_route = path.is_empty() or position.distance_to(path[0]) > 1.0
    _rejoining = false
    _swerve_side = 0.0


func _draw() -> void:
    var painted := Pictures.of("skippers", skipper.get("picture", ""))
    if painted != null:
        # NOTE (mristin):
        # The painted boat, with its sail and its oars, is 7 long in the
        # units of the drawing; it rocks a little while it sails.
        var rock := sin(_time * 2.4) * 0.04 if _speed > 0.5 else 0.0
        Pictures.draw(self, painted, Vector2.ZERO, 7.0 * SCALE, rock)
        _draw_bubble()
        return
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
    var swing := sin(_time * 2.4) if _speed > 0.5 else 0.3
    for sign in [-1.0, 1.0]:
        var lock := Vector2(sign * 0.9, 0.4)
        var out := Vector2(sign, 0).rotated(sign * swing * 0.5)
        draw_line(lock, lock + out * 3.0, Color("d8c08a"), 0.15)
    var hull := PackedVector2Array(
        [
            Vector2(0, -3.2),
            Vector2(0.8, -2.0),
            Vector2(1.0, 0.5),
            Vector2(0.6, 2.6),
            Vector2(0, 3.0),
            Vector2(-0.6, 2.6),
            Vector2(-1.0, 0.5),
            Vector2(-0.8, -2.0),
        ]
    )
    draw_colored_polygon(hull, HULL)
    var closed := hull.duplicate()
    closed.append(hull[0])
    draw_polyline(closed, HULL_DARK, 0.16, true)
    # The skipper, and a little square sail of their color.
    var hair: Color = skipper.get("hair", Color("8a5a2b"))
    draw_circle(Vector2(0, 1.0), 0.45, Color("4a5a6a"))
    draw_circle(Vector2(0, 0.9), 0.35, hair)
    var sail: Color = skipper.get("sail", Color.WHITE)
    var belly := 0.6 if _speed > 0.5 else 0.2
    draw_colored_polygon(
        PackedVector2Array(
            [
                Vector2(-1.6, -0.6),
                Vector2(1.6, -0.6),
                Vector2(1.4, -0.6 - belly - 0.4),
                Vector2(-1.4, -0.6 - belly - 0.4)
            ]
        ),
        sail
    )
    draw_line(Vector2(-1.7, -0.6), Vector2(1.7, -0.6), HULL_DARK, 0.2)
    _draw_bubble()


## A bubble when the skipper wants to talk.
func _draw_bubble() -> void:
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
    if not held and cooldown <= 0.0:
        var bob := sin(_time * 3.0) * 0.2
        var bubble := Pictures.of("ui", "speech_bubble")
        if bubble != null:
            var base := Transform2D(0.0, Vector2(SCALE, SCALE), 0.0, Vector2.ZERO)
            Pictures.draw(self, bubble, Vector2(2.6, -3.6 + bob), 2.4, 0.0, base)
            return
        draw_circle(Vector2(2.4, -3.4 + bob), 0.7, Color(1, 1, 1, 0.9))
        draw_circle(Vector2(1.8, -2.7 + bob), 0.25, Color(1, 1, 1, 0.9))


## What the skipper sees ahead on a way (see [method _look]): in how many
## seconds the boat comes closer to the players' boat than
## [constant CLEARANCE] (0 if it is now, INF if not within
## [constant LOOK_AHEAD]), the closest it comes after now, and the gap at
## the end.
class _Look:
    var conflict: float
    var closest: float
    var end_gap: float

    func _init(too_close_in: float, closest_after_now: float, gap_at_end: float) -> void:
        conflict = too_close_in
        closest = closest_after_now
        end_gap = gap_at_end

    ## Whether this look keeps clearer than the [param other]: it comes too
    ## close later; or, as late, it never comes as close; or it ends further
    ## away.
    func better(other: _Look) -> bool:
        if conflict != other.conflict:
            return conflict > other.conflict
        if absf(closest - other.closest) > 0.01:
            return closest > other.closest
        return end_gap > other.end_gap
