class_name HandCursor
extends Control

## The cursors of the screens, moved by the players' raised hands (the wrists
## which the pose sees, see VisionService.GetHands), or by the mouse when no
## hand is raised. Every raised hand has its own cursor (a small viking
## glove), so that a child sees at once which is hers, and two players can
## point together. The [DwellButton]s ask where the cursors are with [method
## points]: a hand clicks by holding its cursor still over a button.
##
## The cursor of a hand is calm and sticky, since the hands of children are
## hard to hold still: on a button, it is drawn towards the middle and leaves
## only when the hand moves clearly beyond the edge, and it glides instead of
## jumping. Behind the screen, the players see themselves dimly, mirrored, so
## that the hand in the picture lies right under the cursor.

## The part of the mirrored camera picture, normalized, which maps onto the
## whole screen, so that the players reach every corner without stretching.
## Its bottom follows the shoulders (see [method _follow_shoulders]).
const _REACH := Rect2(0.15, 0.1, 0.7, 0.6)

## The bottom of the screen lies this far below the shoulders.
const _BELOW_SHOULDERS := 0.04

## A hand lower than this below the bottom of the reach rests and does not count.
const _BELOW_REACH := 0.08

## How fast the reach follows the shoulders.
const _REACH_FOLLOW := 2.0

## A cursor on a button leaves it only when the hand is this far beyond its edge.
const STICKY_MARGIN := 40.0

## On a button, the cursor moves only this share of the way of the hand from
## the middle of the button.
const STICKY_SHARE := 0.35

## The time constant of the cursor gliding.
const _GLIDE_SECONDS := 0.08

## How bright the mirror of the players is behind the screen.
const MIRROR_ALPHA := 0.55

## A hand is followed this long after the pose lost it, in seconds.
const _GRACE_SECONDS := 0.3

## A hand moving further than this in one frame, normalized, is another hand.
const _SAME_HAND := 0.25

const _LEFT_SHOULDER := 5
const _RIGHT_SHOULDER := 6

## Where all the cursors are, in the pixels of the screen.
static var cursors: Array[Vector2] = []

## Whether hands move the cursors now (else the mouse).
static var by_hand := false

## The part of the camera picture which maps onto the screen now.
static var reach := _REACH

## Whether to show the mirror of the players behind the screen.
var mirror := true

var _service: Node = null
var _hands: Array[Hand] = []


## Where the hands point.
static func points() -> Array[Vector2]:
    return cursors if by_hand else ([] as Array[Vector2])


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    z_index = 100
    var vision := get_node_or_null("/root/Vision")
    _service = vision.service if vision != null else null


func _process(delta: float) -> void:
    if not is_visible_in_tree():
        cursors.clear()
        by_hand = false
        return
    _follow_hands()
    var screen := get_viewport_rect().size
    cursors.clear()
    for hand in _hands:
        var target := (hand.smoothed - reach.position) / reach.size * screen
        target = target.clamp(Vector2.ZERO, screen)
        hand.cursor = target if hand.fresh else _glide(hand, target, delta)
        hand.fresh = false
        cursors.append(hand.cursor)
    by_hand = not cursors.is_empty()
    queue_redraw()


## The cursor glides towards its hand, and sticks to the button under it.
func _glide(hand: Hand, target: Vector2, delta: float) -> Vector2:
    var glide := 1.0 - exp(-delta / _GLIDE_SECONDS)
    var button: DwellButton = null
    if (
        is_instance_valid(hand.stuck)
        and hand.stuck.is_visible_in_tree()
        and hand.stuck.get_global_rect().grow(STICKY_MARGIN).has_point(target)
    ):
        button = hand.stuck
    if button == null:
        button = _button_at(target)
    hand.stuck = button
    if button == null:
        return hand.cursor.lerp(target, glide)
    var middle := button.get_global_rect().get_center()
    var wanted := middle + (target - middle) * STICKY_SHARE
    if not button.get_global_rect().has_point(wanted):
        wanted = middle
    return hand.cursor.lerp(wanted, glide)


## The smallest visible button under the point, or null.
func _button_at(point: Vector2) -> DwellButton:
    var best: DwellButton = null
    for node in get_tree().root.find_children("*", "DwellButton", true, false):
        var button := node as DwellButton
        if not button.is_visible_in_tree() or not button.get_global_rect().has_point(point):
            continue
        if best == null or button.size.x * button.size.y < best.size.x * best.size.y:
            best = button
    return best


## Let the bottom of the reach follow the shoulders, so that the hand reaches
## the bottom of the screen while it is still raised.
func _follow_shoulders() -> void:
    var points: PackedVector2Array = _service.GetKeypoints(0)
    var scores: PackedFloat32Array = _service.GetKeypointScores(0)
    if points.size() <= _RIGHT_SHOULDER or scores.size() <= _RIGHT_SHOULDER:
        return
    var shoulders := 0.0
    var count := 0
    for i in [_LEFT_SHOULDER, _RIGHT_SHOULDER]:
        if scores[i] >= 0.5:
            shoulders += points[i].y
            count += 1
    if count == 0:
        return
    var bottom := clampf(shoulders / count + _BELOW_SHOULDERS, _REACH.position.y + 0.25, 0.95)
    var step := minf(1.0, get_process_delta_time() * _REACH_FOLLOW)
    reach.size.y = lerpf(reach.size.y, bottom - _REACH.position.y, step)


## Follow the raised hands: each found hand continues the nearest hand
## followed before, if close; the others start new cursors.
func _follow_hands() -> void:
    if _service == null or not _service.IsRunning():
        _hands.clear()
        return
    _follow_shoulders()
    var lowest := reach.end.y + _BELOW_REACH
    var now := Time.get_ticks_msec() / 1000.0
    var found: Array[Vector2] = []
    for hand in _service.GetHands():
        if hand.y <= lowest:
            found.append(hand)
    var pairs := []
    for h in _hands.size():
        for f in found.size():
            var distance := _hands[h].raw.distance_to(found[f])
            if distance <= _SAME_HAND:
                pairs.append([distance, h, f])
    pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    var taken_hands := {}
    var taken_found := {}
    for pair in pairs:
        if taken_hands.has(pair[1]) or taken_found.has(pair[2]):
            continue
        taken_hands[pair[1]] = true
        taken_found[pair[2]] = true
        _hands[pair[1]].see(found[pair[2]], now)
    for f in found.size():
        if not taken_found.has(f):
            var born := Hand.new()
            born.see(found[f], now)
            _hands.append(born)
    var kept: Array[Hand] = []
    for hand in _hands:
        if now - hand.seen_at <= _GRACE_SECONDS:
            kept.append(hand)
    _hands = kept


## Draw the mirror of the players (dim, behind the buttons) on the [param canvas],
## stretched so that the part of the picture which the hands reach covers it.
func draw_mirror(canvas: CanvasItem, area: Vector2) -> void:
    if not mirror or _service == null or not _service.IsRunning():
        return
    var texture: Texture2D = _service.GetCameraTexture()
    if texture == null:
        return
    var whole := area / reach.size
    var origin := -reach.position * whole
    # NOTE (mristin):
    # The hands are in the mirrored picture, so the texture is flipped.
    canvas.draw_set_transform(Vector2(area.x, 0), 0, Vector2(-1, 1))
    var flipped := Rect2(Vector2(area.x - origin.x - whole.x, origin.y), whole)
    canvas.draw_texture_rect(texture, flipped, false, Color(1, 1, 1, MIRROR_ALPHA))
    canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _exit_tree() -> void:
    cursors.clear()
    by_hand = false


## A cursor: a viking glove of leather with a gold cuff.
func _draw() -> void:
    var glove := Pictures.of("ui", "glove")
    if glove != null:
        for hand in _hands:
            if is_instance_valid(hand.stuck) and hand.stuck.progress > 0.0:
                _draw_ring(hand.cursor, hand.stuck.progress)
        for point in cursors:
            Pictures.draw(
                self,
                glove,
                point + Vector2(3, 5),
                72.0,
                0.0,
                Transform2D.IDENTITY,
                Color(0, 0, 0, 0.35)
            )
            Pictures.draw(self, glove, point, 72.0)
        return
    for point in cursors:
        draw_circle(point + Vector2(3, 4), 30.0, Color(0, 0, 0, 0.35))
        draw_circle(point, 30.0, Color("8a5a2b"))
        draw_circle(point, 30.0, Color("f2c14e"), false, 5.0)
        for k in range(4):
            draw_circle(point + Vector2(-15.0 + 10.0 * k, -26.0), 8.0, Color("8a5a2b"))
        draw_circle(point + Vector2(-30, 2), 9.0, Color("8a5a2b"))
        draw_circle(point, 6.0, Color("f2c14e"))


## The rope ring around the cursor at [param at], which fills clockwise from
## the top while the hand holds still over a card ([param progress] from 0 to 1).
func _draw_ring(at: Vector2, progress: float) -> void:
    var ring := Pictures.of("ui", "rope_ring")
    if ring == null:
        return
    var radius := 56.0
    var square := Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
    draw_texture_rect(ring, square, false, Color(1, 1, 1, 0.3))
    # A slice of the ring, as far as the hand got, reaching past the corners.
    var points := PackedVector2Array([at])
    var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
    var steps := maxi(2, int(64 * progress))
    for k in range(steps + 1):
        var direction := Vector2.from_angle(-PI / 2.0 + TAU * progress * k / steps) * 1.5
        points.append(at + direction * radius)
        uvs.append(Vector2(0.5, 0.5) + direction * 0.5)
    draw_colored_polygon(points, Color.WHITE, uvs, ring)


## A raised hand which we follow, and its cursor.
class Hand:
    extends RefCounted
    ## Where the pose saw it last, normalized.
    var raw := Vector2.ZERO
    ## Where it is, smoothed, normalized.
    var smoothed := Vector2.ZERO
    var seen_at := 0.0
    ## Where its cursor is, in the pixels of the screen.
    var cursor := Vector2.ZERO
    ## Whether the cursor just appeared (it jumps to the hand, not glides).
    var fresh := true
    var stuck: DwellButton = null
    var _x := OneEuro.new()
    var _y := OneEuro.new()

    func see(point: Vector2, now: float) -> void:
        raw = point
        seen_at = now
        smoothed = Vector2(_x.filter(point.x, now), _y.filter(point.y, now))


## Smooth a noisy signal with little lag: the faster it moves, the less we
## smooth (Casiez, Roussel and Vogel, "1€ Filter", CHI 2012).
class OneEuro:
    extends RefCounted
    var min_cutoff := 1.2
    var beta := 4.0
    var derivative_cutoff := 1.0
    var _value := 0.0
    var _derivative := 0.0
    var _last := -1.0

    func filter(value: float, time: float) -> float:
        if _last < 0.0:
            _value = value
            _last = time
            return value
        var dt := time - _last
        if dt <= 0.000001:
            return _value
        _last = time
        var derivative := (value - _value) / dt
        _derivative += _alpha(derivative_cutoff, dt) * (derivative - _derivative)
        var cutoff := min_cutoff + beta * absf(_derivative)
        _value += _alpha(cutoff, dt) * (value - _value)
        return _value

    func _alpha(cutoff: float, dt: float) -> float:
        var tau := 1.0 / (TAU * cutoff)
        return 1.0 / (1.0 + tau / dt)
