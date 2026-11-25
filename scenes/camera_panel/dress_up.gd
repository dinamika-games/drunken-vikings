class_name DressUp
extends RefCounted

## Dress the player up in the camera picture as the viking of their look
## (see Looks): the painted pieces of Ylva's dress (res://assets/pictures/dress/,
## cut by dev/pictures/cut_dress.py) or of the boy's tunic
## (res://assets/pictures/dress_boy/, cut by dev/pictures/cut_looks.py), each
## with their anchors in dress.json and in the colours of the look, drawn
## along the key points of the pose. The boy's pieces are laid out as Ylva's:
## his lap piece (the hem of his tunic over his knees) lies as her skirt, his
## upper tunic as her bodice.
##
## The player sits on the floor and rows, so the dress comes in two parts:
##
## * the skirt lies over her lap, level, from the waist down to the knees (if
##   the knees are seen, else as painted);
## * the bodice goes from her shoulders down to her waist and tilts with her
##   as she leans; its belt covers the top of the skirt;
## * the hair sits on her head by her eyes (by her ears while the eyes are
##   not seen), and turns and tilts with it;
## * each sleeve comes out of the armhole of the bodice with the round of the
##   shoulder and bends along her arm, through the elbow, to the fist (as The
##   Steppe Rescue's PaintedBody: its start under the bodice, the rest over
##   it, since the arms reach in front of the body);
## * a fist holds the oar on each hand which the hand detector finds (see
##   VisionService.GetHands), matched to the arm by its wrist; a little beyond
##   the wrist while the hand is not found. The fist is pulled (the forearm
##   from below) while the hand is above the elbow, else it reaches (the
##   forearm from above); the painted left fist, mirrored for the right hand.
##
## A piece whose key points are not seen is left out. The key points glide
## a little between the poses, so that the dress does not jitter.

enum Kp {
    NOSE,
    LEFT_EYE,
    RIGHT_EYE,
    LEFT_EAR,
    RIGHT_EAR,
    LEFT_SHOULDER,
    RIGHT_SHOULDER,
    LEFT_ELBOW,
    RIGHT_ELBOW,
    LEFT_WRIST,
    RIGHT_WRIST,
    LEFT_HIP,
    RIGHT_HIP,
    LEFT_KNEE,
    RIGHT_KNEE,
}

## The sheet of Ylva's dress, which the game needs (the boy's is optional).
const SHEET := "dress"

## A key point counts from this score on.
const THRESHOLD := 0.3

## The key points glide to the new pose with this time constant, in seconds.
const GLIDE := 0.06

## Forget a key point not seen for this many seconds.
const FORGET := 0.4

## The sizes of the pieces, in the widths of the shoulders (between the key
## points of the shoulders): the bodice is as wide as the shoulders at the
## waist (its straps lie inside the shoulders, where the sleeves start), its
## top a little above the key points; the torso as long as painted times
## TORSO (while the hips are not seen); the sleeves as thick and the fists as
## wide (with the oar) as given.
const BODICE_WIDTH := 1.0
const SHOULDER_TOP := 0.1
const TORSO := 0.85
const SLEEVE_SHARE := 0.3
const FIST_WIDTH := 0.5

## The painted sleeve flares open at the shoulder; it is drawn from this
## share of its length on, so that the opening does not show.
const SLEEVE_TRIM := 0.1

## The sleeve begins round, as the shoulder does: over this share of its
## painted length, it swells along a half ellipse from a point to its full
## thickness, in SLEEVE_DOME_STEPS pieces, so that its outline goes round the
## shoulder instead of ending square above it; the ellipse is
## SLEEVE_DOME_DEPTH as deep as it is wide, so that the shoulder does not rise
## like a puff (as in The Steppe Rescue).
const SLEEVE_DOME := 0.14
const SLEEVE_DOME_STEPS := 8
const SLEEVE_DOME_DEPTH := 0.5

## This share of the upper arm, from the shoulder, is drawn under the bodice,
## so that the armhole lies over the sleeve; the rest is drawn over it, so
## that an arm reaching in front of the body stays in front.
const SLEEVE_UNDER := 0.35

## The middle of the round of the shoulder lies this share of the way from
## the shoulder to the neck, so that the arm comes out from under the
## bodice...
const SLEEVE_TUCK := 0.12

## ... and this share of the shoulders below it: the shoulder of the vision is
## the top of the arm, not its middle.
const SLEEVE_DROP := 0.1

## The pieces of a sleeve along the arm.
const SLEEVE_STEPS := 24

## A hand of the hand detector belongs to an arm when it is at most this far
## from its wrist (from its elbow, while the wrist is not seen), in the widths
## of the shoulders.
const HAND_REACH := 0.7

## While the hand is not found, the fist sits this share of the forearm
## beyond the wrist.
const HAND_BEYOND := 0.3

## The fist reaches forward while the stroke is up to this far through (see
## VisionService.GetPull), when the elbow is not seen.
const REACH_UNTIL := 0.4

## The anchors of the pieces, by their sheet.
static var _anchors: Dictionary = {}

## The look of each player (see Looks); the default look for a player without.
var looks: Array = []

## The look of the player being drawn, and the anchors of its pieces.
var _look: Dictionary = {}

## Per player: the gliding key points (Vector2 in pixels of the panel, or
## null) and when each was seen the last time.
var _points: Array = [[], []]
var _seen: Array = [[], []]

## Per player: the gliding hand of each arm (the player's left, right; Vector2
## in pixels of the panel, or null) and when each was found the last time.
var _hands: Array = [[null, null], [null, null]]
var _hands_seen: Array = [[-INF, -INF], [-INF, -INF]]


## Whether the painted dress is there.
static func available() -> bool:
    return (
        not anchors().is_empty()
        and Pictures.has_all(
            SHEET, ["head", "bodice", "skirt", "sleeve", "fist_reach", "fist_pull"]
        )
    )


## The anchors of the pieces of the [param sheet] (see
## dev/pictures/cut_dress.py); empty if missing.
static func anchors(sheet := SHEET) -> Dictionary:
    if not _anchors.has(sheet):
        _anchors[sheet] = {}
        var path := "%s/%s/dress.json" % [Pictures.ROOT, sheet]
        if FileAccess.file_exists(path):
            var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
            if parsed is Dictionary:
                _anchors[sheet] = parsed
    return _anchors[sheet]


## The look of the [param player]: as given, or the default (see Looks). A
## boy whose pieces are not painted is dressed as Ylva, in his colours.
func look_of(player: int) -> Dictionary:
    var look: Dictionary = (
        looks[player] if player < looks.size() and looks[player] is Dictionary else {}
    )
    if look.is_empty():
        look = Looks.default_look(player)
    if anchors(Looks.dress_sheet(look)).is_empty():
        look = look.duplicate()
        look["figure"] = "girl"
    return look


## The piece [param name] in the look of the player being drawn.
func _piece(name: String) -> Texture2D:
    return Looks.dress(_look, name)


static func _point(value: Dictionary) -> Vector2:
    return Vector2(float(value["x"]), float(value["y"]))


## Take in the key points of the [param player] (normalized, in the mirrored
## picture) and their scores, and the [param hands] which the hand detector
## found (of all the players, normalized), for the panel of [param size].
func observe(
    player: int,
    points: PackedVector2Array,
    scores: PackedFloat32Array,
    hands: PackedVector2Array,
    size: Vector2,
    delta: float,
    now: float
) -> void:
    var glided: Array = _points[player]
    var seen: Array = _seen[player]
    if glided.size() != 17:
        glided.resize(17)
        seen.resize(17)
        seen.fill(-INF)
    var follow := 1.0 - exp(-delta / GLIDE)
    for k in range(17):
        if points.size() == 17 and scores[k] >= THRESHOLD:
            var target := points[k] * size
            glided[k] = target if glided[k] == null else (glided[k] as Vector2).lerp(target, follow)
            seen[k] = now
        elif now - float(seen[k]) > FORGET:
            glided[k] = null
    _observe_hands(player, hands, size, follow, now)


## Match the hands to the arms of the [param player]: the nearest hand to each
## wrist, each hand to one arm only.
func _observe_hands(
    player: int, hands: PackedVector2Array, size: Vector2, follow: float, now: float
) -> void:
    var p: Array = _points[player]
    var width := 0.25 * size.x
    if p[Kp.LEFT_SHOULDER] != null and p[Kp.RIGHT_SHOULDER] != null:
        width = (p[Kp.LEFT_SHOULDER] as Vector2).distance_to(p[Kp.RIGHT_SHOULDER])
    var pairs: Array = []
    for side in [0, 1]:
        var near: Variant = p[Kp.LEFT_WRIST + side]
        var reach := width * HAND_REACH
        if near == null:
            near = p[Kp.LEFT_ELBOW + side]
            reach *= 1.5
        if near == null:
            continue
        for i in range(hands.size()):
            var distance := (hands[i] * size).distance_to(near)
            if distance <= reach:
                pairs.append([distance, side, i])
    pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    var found: Array = [null, null]
    var taken := {}
    for pair in pairs:
        if found[pair[1]] == null and not taken.has(pair[2]):
            found[pair[1]] = hands[pair[2]] * size
            taken[pair[2]] = true
    for side in [0, 1]:
        if found[side] != null:
            var glided: Variant = _hands[player][side]
            _hands[player][side] = (
                found[side] if glided == null else (glided as Vector2).lerp(found[side], follow)
            )
            _hands_seen[player][side] = now
        elif now - float(_hands_seen[player][side]) > FORGET:
            _hands[player][side] = null


## Draw the dress of the [param player] on the [param canvas]; [param pull]
## is how far through the stroke the player is (see VisionService.GetPull).
func draw(canvas: CanvasItem, player: int, pull: float) -> void:
    var p: Array = _points[player]
    if p.size() != 17:
        return
    _look = look_of(player)
    var a := anchors(Looks.dress_sheet(_look))
    var shoulders_seen: bool = p[Kp.LEFT_SHOULDER] != null and p[Kp.RIGHT_SHOULDER] != null
    if not shoulders_seen:
        _draw_head(canvas, p, a)
        canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        return
    var width: float = (p[Kp.LEFT_SHOULDER] as Vector2).distance_to(p[Kp.RIGHT_SHOULDER])
    var fists: Array = []
    var strips: Array = []
    for side in [0, 1]:
        var fist := _fist(p, a, player, side, width, pull)
        fists.append(fist)
        strips.append(_sleeve_strip(p, a, side, width, fist))
    var waist := _waist(p, a)
    _draw_skirt(canvas, p, a, waist)
    for strip in strips:
        _draw_sleeve(canvas, strip, true)
    _draw_bodice(canvas, p, a, waist)
    _draw_head(canvas, p, a)
    for strip in strips:
        _draw_sleeve(canvas, strip, false)
    for fist in fists:
        _draw_fist(canvas, fist)
    canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The bodice from the shoulders: its top corners on the screen, and the
## middle, the direction (along the line of the shoulders) and the width of
## the waist, from the hips if seen, else straight below the shoulders.
func _waist(p: Array, a: Dictionary) -> Dictionary:
    var left: Vector2 = p[Kp.LEFT_SHOULDER]
    var right: Vector2 = p[Kp.RIGHT_SHOULDER]
    var width := left.distance_to(right)
    var along := (right - left) / maxf(width, 1.0)
    var down := Vector2(-along.y, along.x)
    var bodice: Dictionary = a["bodice"]
    var tex_shoulders := _point(bodice["shoulder_right"]).x - _point(bodice["shoulder_left"]).x
    var tex_waist := _point(bodice["waist_right"]).x - _point(bodice["waist_left"]).x
    var tex_height := _point(bodice["waist_left"]).y - _point(bodice["shoulder_left"]).y
    var scale := width * BODICE_WIDTH / tex_waist
    var middle := (left + right) / 2.0 - down * width * SHOULDER_TOP
    var top_left := middle - along * tex_shoulders * scale / 2.0
    var top_right := middle + along * tex_shoulders * scale / 2.0

    var length := tex_height * scale * TORSO
    var waist_middle := middle + down * length
    var waist_along := along
    if p[Kp.LEFT_HIP] != null and p[Kp.RIGHT_HIP] != null:
        var hips: Vector2 = ((p[Kp.LEFT_HIP] as Vector2) + (p[Kp.RIGHT_HIP] as Vector2)) / 2.0
        var hip_line: Vector2 = (p[Kp.RIGHT_HIP] as Vector2) - (p[Kp.LEFT_HIP] as Vector2)
        if hip_line.length() > 1.0:
            waist_along = hip_line.normalized()
        # NOTE (mristin):
        # The belt sits a little above the hips; lean forward or back, and
        # the torso looks shorter, but never much shorter or longer.
        var to_waist := hips - down * width * 0.15 - middle
        var reach := clampf(to_waist.length(), length * 0.6, length * 1.4)
        waist_middle = middle + to_waist.normalized() * reach
    return {
        "top_left": top_left,
        "top_right": top_right,
        "middle": waist_middle,
        "along": waist_along,
        "width": tex_waist * scale,
        "scale": scale,
    }


func _draw_bodice(canvas: CanvasItem, _p: Array, a: Dictionary, waist: Dictionary) -> void:
    var texture := _piece("bodice")
    var bodice: Dictionary = a["bodice"]
    var size := texture.get_size()
    var sl := _point(bodice["shoulder_left"])
    var sr := _point(bodice["shoulder_right"])
    var wl := _point(bodice["waist_left"])
    var wr := _point(bodice["waist_right"])
    var top_left: Vector2 = waist["top_left"]
    var top_right: Vector2 = waist["top_right"]
    var along: Vector2 = waist["along"]
    var half: float = waist["width"] / 2.0
    var bottom_left: Vector2 = waist["middle"] - along * half
    var bottom_right: Vector2 = waist["middle"] + along * half

    # NOTE (mristin):
    # Map the whole picture: its corners, found along the lines of the
    # shoulders and of the waist in the picture.
    var top := func(x: float) -> Vector2:
        return top_left.lerp(top_right, (x - sl.x) / (sr.x - sl.x))
    var bottom := func(x: float) -> Vector2:
        return bottom_left.lerp(bottom_right, (x - wl.x) / (wr.x - wl.x))
    var t0: Vector2 = top.call(0.0)
    var t1: Vector2 = top.call(size.x)
    var b0: Vector2 = bottom.call(0.0)
    var b1: Vector2 = bottom.call(size.x)
    # The rows above the shoulders and below the waist, stretched alike.
    var over := sl.y / maxf(wl.y - sl.y, 1.0)
    var under := (size.y - wl.y) / maxf(wl.y - sl.y, 1.0)
    var c0 := t0 + (t0 - b0) * over
    var c1 := t1 + (t1 - b1) * over
    var c2 := b1 + (b1 - t1) * under
    var c3 := b0 + (b0 - t0) * under
    canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    canvas.draw_primitive(
        PackedVector2Array([c0, c1, c2, c3]),
        PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
        PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
        texture
    )


func _draw_skirt(canvas: CanvasItem, p: Array, a: Dictionary, waist: Dictionary) -> void:
    var texture := _piece("skirt")
    var skirt: Dictionary = a["skirt"]
    var wl := _point(skirt["waist_left"])
    var wr := _point(skirt["waist_right"])
    var scale: float = waist["width"] / (wr.x - wl.x)
    # NOTE (mristin):
    # The skirt lies on the floor: level, unless we see the hips; the
    # waistband goes a little under the belt of the bodice.
    var along := Vector2.RIGHT
    if p[Kp.LEFT_HIP] != null and p[Kp.RIGHT_HIP] != null:
        along = ((p[Kp.RIGHT_HIP] as Vector2) - (p[Kp.LEFT_HIP] as Vector2)).normalized()
    var at: Vector2 = waist["middle"] - Vector2(-along.y, along.x) * wl.y * scale * 2.0
    var stretch := 1.0
    if p[Kp.LEFT_KNEE] != null and p[Kp.RIGHT_KNEE] != null:
        var knees: Vector2 = ((p[Kp.LEFT_KNEE] as Vector2) + (p[Kp.RIGHT_KNEE] as Vector2)) / 2.0
        var painted := (float(skirt["hem_y"]) - wl.y) * 0.85 * scale
        stretch = clampf(knees.distance_to(at) / maxf(painted, 1.0), 0.6, 1.5)
    canvas.draw_set_transform(at, along.angle(), Vector2(scale, scale * stretch))
    canvas.draw_texture(texture, -Vector2((wl.x + wr.x) / 2.0, wl.y))


func _draw_head(canvas: CanvasItem, p: Array, a: Dictionary) -> void:
    var head: Dictionary = a["head"]
    var middle: Vector2
    var line: Vector2
    if p[Kp.LEFT_EYE] != null and p[Kp.RIGHT_EYE] != null:
        line = (p[Kp.RIGHT_EYE] as Vector2) - (p[Kp.LEFT_EYE] as Vector2)
        middle = ((p[Kp.LEFT_EYE] as Vector2) + (p[Kp.RIGHT_EYE] as Vector2)) / 2.0
    elif p[Kp.LEFT_EAR] != null and p[Kp.RIGHT_EAR] != null:
        # NOTE (mristin):
        # On the template, the ears are 2.08 eye distances apart and 0.22
        # below the eyes.
        var ears: Vector2 = (p[Kp.RIGHT_EAR] as Vector2) - (p[Kp.LEFT_EAR] as Vector2)
        line = ears / 2.08
        middle = (
            ((p[Kp.LEFT_EAR] as Vector2) + (p[Kp.RIGHT_EAR] as Vector2)) / 2.0
            - Vector2(-line.y, line.x) * 0.22
        )
    else:
        return
    if line.length() < 1.0:
        return
    var scale := line.length() / float(head["eye_distance"])
    canvas.draw_set_transform(middle, line.angle(), Vector2(scale, scale))
    canvas.draw_texture(_piece("head"), -_point(head["eyes"]))


## Where the fist of [param side] (0 the player's left arm, on the left of
## the picture) goes: {"name", "at" (the middle of the hand on the screen),
## "scale", "mirror", "wrist" (where its sleeve ends on the screen)}, or
## empty if neither the hand nor the wrist is seen.
func _fist(
    p: Array, a: Dictionary, player: int, side: int, width: float, pull: float
) -> Dictionary:
    var wrist: Variant = p[Kp.LEFT_WRIST + side]
    var elbow: Variant = p[Kp.LEFT_ELBOW + side]
    var at: Variant = _hands[player][side]
    if at == null and wrist != null:
        at = wrist
        if elbow != null:
            at = (wrist as Vector2) + ((wrist as Vector2) - (elbow as Vector2)) * HAND_BEYOND
    if at == null:
        return {}
    var reach := pull >= 0.0 and pull < REACH_UNTIL
    if elbow != null:
        reach = (at as Vector2).y >= (elbow as Vector2).y
    var name := "fist_reach" if reach else "fist_pull"
    var fist: Dictionary = a[name]
    var scale := width * FIST_WIDTH / float(fist["width"])
    var mirror := -1.0 if side == 1 else 1.0
    var hand := _point(fist["hand"])
    var offset := (_point(fist["wrist"]) - hand) * scale
    return {
        "name": name,
        "at": at,
        "scale": scale,
        "mirror": mirror,
        "hand": hand,
        "wrist": (at as Vector2) + Vector2(offset.x * mirror, offset.y),
    }


func _draw_fist(canvas: CanvasItem, fist: Dictionary) -> void:
    if fist.is_empty():
        return
    var scale: float = fist["scale"]
    canvas.draw_set_transform(fist["at"], 0.0, Vector2(scale * float(fist["mirror"]), scale))
    canvas.draw_texture(_piece(fist["name"]), -(fist["hand"] as Vector2))


## The sleeve of [param side] as one strip from the round of the shoulder
## over the elbow to the wrist of its [param fist] (or to the elbow alone), so
## that it bends softly at the elbow: {"points", "us" (the columns of the
## painting, normalized), "widths" (a share of the thickness), "half" (the
## half thickness on the screen), "cut" (the index up to which it lies under
## the bodice)}, or empty if the elbow is not seen.
func _sleeve_strip(
    p: Array, a: Dictionary, side: int, width: float, fist: Dictionary
) -> Dictionary:
    var shoulder_point: Variant = p[Kp.LEFT_SHOULDER + side]
    var elbow: Variant = p[Kp.LEFT_ELBOW + side]
    if elbow == null:
        return {}
    var texture := _piece("sleeve")
    var sleeve: Dictionary = a["sleeve"]
    var size := texture.get_size()
    var neck: Vector2 = ((p[Kp.LEFT_SHOULDER] as Vector2) + (p[Kp.RIGHT_SHOULDER] as Vector2)) / 2.0
    var across: Vector2 = (p[Kp.RIGHT_SHOULDER] as Vector2) - (p[Kp.LEFT_SHOULDER] as Vector2)
    var down := Vector2(-across.y, across.x).normalized()
    var shoulder: Vector2 = (
        (shoulder_point as Vector2).lerp(neck, SLEEVE_TUCK) + down * width * SLEEVE_DROP
    )
    if shoulder.distance_to(elbow) < 1.0:
        return {}

    var start := _point(sleeve["shoulder"]).x
    var cuff := _point(sleeve["cuff"]).x
    var trim := lerpf(start, cuff, SLEEVE_TRIM)
    var dome := (cuff - start) * SLEEVE_DOME
    var elbow_u := (start + cuff) / 2.0
    var scale := width * SLEEVE_SHARE / float(sleeve["thickness"])

    var points := PackedVector2Array()
    var us := PackedFloat32Array()
    var widths := PackedFloat32Array()

    # NOTE (mristin):
    # The round of the shoulder: from a point behind the shoulder, towards the
    # elbow, as wide as a half ellipse, the steps denser at the point.
    var toward := ((elbow as Vector2) - shoulder).normalized()
    var radius := dome * scale
    for i in range(SLEEVE_DOME_STEPS):
        var angle := PI * 0.5 * i / SLEEVE_DOME_STEPS
        var behind := cos(angle)
        points.append(shoulder - toward * radius * SLEEVE_DOME_DEPTH * behind)
        us.append(trim + dome * (1.0 - behind))
        widths.append(sin(angle))
    var from := trim + dome

    var arm := PackedVector2Array()
    if fist.is_empty():
        for i in range(SLEEVE_STEPS + 1):
            var t := float(i) / SLEEVE_STEPS
            arm.append(shoulder.lerp(elbow, t))
            us.append(lerpf(from, elbow_u, t))
    else:
        # NOTE (mristin):
        # The quadratic curve from the shoulder to the wrist which passes
        # through the elbow halfway; the painting runs along it by the length,
        # with the elbow of the painting at the elbow.
        var end: Vector2 = fist["wrist"]
        var control: Vector2 = (elbow as Vector2) * 2.0 - (shoulder + end) * 0.5
        var lengths := PackedFloat32Array([0.0])
        for i in range(SLEEVE_STEPS + 1):
            var t := float(i) / SLEEVE_STEPS
            var point := shoulder.lerp(control, t).lerp(control.lerp(end, t), t)
            if i > 0:
                lengths.append(lengths[i - 1] + point.distance_to(arm[i - 1]))
            arm.append(point)
        var half := SLEEVE_STEPS / 2
        var to_elbow := maxf(lengths[half], 1e-3)
        var from_elbow := maxf(lengths[SLEEVE_STEPS] - lengths[half], 1e-3)
        for i in range(SLEEVE_STEPS + 1):
            if i <= half:
                us.append(lerpf(from, elbow_u, lengths[i] / to_elbow))
            else:
                us.append(lerpf(elbow_u, cuff, (lengths[i] - lengths[half]) / from_elbow))
    points.append_array(arm)
    for i in range(arm.size()):
        widths.append(1.0)
    for i in range(us.size()):
        us[i] /= size.x
    var upper := SLEEVE_STEPS / 2 if not fist.is_empty() else SLEEVE_STEPS
    return {
        "points": points,
        "us": us,
        "widths": widths,
        "half": size.y / 2.0 * scale,
        "cut": SLEEVE_DOME_STEPS + roundi(upper * SLEEVE_UNDER),
    }


## Draw the part of the sleeve under the bodice ([param under]), or the rest.
func _draw_sleeve(canvas: CanvasItem, strip: Dictionary, under: bool) -> void:
    if strip.is_empty():
        return
    var cut: int = strip["cut"]
    var points: PackedVector2Array = strip["points"]
    var us: PackedFloat32Array = strip["us"]
    var widths: PackedFloat32Array = strip["widths"]
    var first := 0 if under else cut
    var last := cut if under else points.size() - 1
    var half: float = strip["half"]
    var texture := _piece("sleeve")
    var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
    canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    var normals := PackedVector2Array()
    for i in range(points.size()):
        var before := points[maxi(0, i - 1)]
        var after := points[mini(points.size() - 1, i + 1)]
        normals.append((after - before).orthogonal().normalized() * half * widths[i])
    for i in range(first, last):
        canvas.draw_primitive(
            PackedVector2Array(
                [
                    points[i] + normals[i],
                    points[i + 1] + normals[i + 1],
                    points[i + 1] - normals[i + 1],
                    points[i] - normals[i]
                ]
            ),
            white,
            PackedVector2Array(
                [Vector2(us[i], 0), Vector2(us[i + 1], 0), Vector2(us[i + 1], 1), Vector2(us[i], 1)]
            ),
            texture
        )
