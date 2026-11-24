class_name HowToFigure
extends RefCounted

## A rower as the camera sees her from the front, mirrored as the players see
## themselves (see HowTo): she sits, rows (leans back and pulls her hands to
## her belly, then leans forward and reaches out), leans to a side to steer,
## raises both hands to brake, or one hand to point at a card.
##
## The geometry is in units of the height of the frame (see [method joints]);
## dev/how_to/make_svgs.py draws the same figure into the SVGs, with the same
## numbers.

## Ylva and Sigrid, as painted (see the faces and the dress): the braids, the
## apron-dress, the headband and the sleeves.
const LOOKS := [
    {
        "hair": Color("e8c25a"),
        "dress": Color("2f6f6a"),
        "band": Color("b8332a"),
        "sleeve": Color("f1e6cc")
    },
    {
        "hair": Color("c8562a"),
        "dress": Color("7a3a6a"),
        "band": Color("3a6ea8"),
        "sleeve": Color("f1e6cc")
    },
]

## The names of the painted rowers (see dev/pictures/cut_sheets.py), the
## painted poses to use when one is missing, and how big the painted canvas
## is drawn, per pixel of the height of the frame (the girl from her head to
## her lap is then about 0.75 of the frame high).
const NAMES := ["ylva", "sigrid"]
const FALLBACKS := {"hold": ["reach", "rest"], "point": ["rest"], "up": ["rest"]}
const PAINTED_SCALE := 0.75 / 415.0

const SKIN := Color("f0c8a0")
const INK := Color("2a1e14")

## The body, in units of the height of the frame.
const HIPS_Y := 0.98
const TORSO := 0.42
const SHOULDER := 0.16
const HEAD := 0.095
const NECK := 0.07

## How far the head goes down when she leans back, and how far her body tilts
## when she leans to a side, at most.
const CRUNCH := 0.07
const TILT_DEGREES := 20.0


## The joints of the rower at the [param center] x of a frame of the [param
## height], for the [param pose]: {"lean": 0 (forward) to 1 (back), "tilt":
## -1 (to the left of the picture) to 1, "hands": "rest", "oar", "up" or
## "point", "up": 0 to 1 (how far the hands are raised, for "up" and
## "point"), "target": where the pointing hand goes}. Return the head, the
## shoulders, the elbows, the wrists and the hips.
static func joints(center: float, height: float, pose: Dictionary) -> Dictionary:
    var lean := float(pose.get("lean", 0.0))
    var tilt := float(pose.get("tilt", 0.0))
    var up := float(pose.get("up", 0.0))
    var hips := Vector2(center, HIPS_Y * height)
    var angle := deg_to_rad(TILT_DEGREES) * tilt
    var torso := Vector2(0, -(TORSO - CRUNCH * lean) * height).rotated(angle)
    var neck := hips + torso
    var across := Vector2(SHOULDER * height * (1.0 - 0.08 * lean), 0).rotated(angle)
    var head := neck + Vector2(0, -(NECK + HEAD) * height).rotated(angle)
    var result := {
        "head": head,
        "neck": neck,
        "hips": hips,
        "shoulders": [neck - across, neck + across],
    }
    var elbows := []
    var wrists := []
    for side in [-1.0, 1.0]:
        var shoulder: Vector2 = neck + across * side
        var rest_elbow := shoulder + Vector2(0.06 * side, 0.22) * height
        var rest_wrist := hips + Vector2(0.12 * side, -0.08) * height
        var elbow := rest_elbow
        var wrist := rest_wrist
        match str(pose.get("hands", "rest")):
            "oar":
                var reach_elbow := shoulder + Vector2(0.04 * side, 0.18) * height
                var reach_wrist := neck + Vector2(0.07 * side, 0.12) * height
                var pull_elbow := shoulder + Vector2(0.11 * side, 0.2) * height
                var pull_wrist := hips + Vector2(0.1 * side, -0.17) * height
                elbow = reach_elbow.lerp(pull_elbow, lean)
                wrist = reach_wrist.lerp(pull_wrist, lean)
            "up":
                elbow = rest_elbow.lerp(shoulder + Vector2(0.05 * side, -0.1) * height, up)
                wrist = rest_wrist.lerp(head + Vector2(0.13 * side, -0.2) * height, up)
            "point":
                if side > 0.0:
                    var target: Vector2 = pose.get(
                        "target", shoulder + Vector2(0.15, -0.12) * height
                    )
                    var raised := shoulder.lerp(target, 0.5) + Vector2(0, 0.05 * height)
                    elbow = rest_elbow.lerp(raised, up)
                    wrist = rest_wrist.lerp(target, up)
        elbows.append(elbow)
        wrists.append(wrist)
    result["elbows"] = elbows
    result["wrists"] = wrists
    return result


## The painted pose of the rower of the [param look] for the [param pose] (see
## [method joints]), and how far it leans (-1 to 1): the painted sheet has
## the poses ready, reaching, holding (the hands at the chest), pulling, both
## hands up and pointing; the rower rows by reaching and pulling, upright,
## leans to steer by tilting the holding pose, and the poses which are not
## painted fall back on the nearest ones.
static func painted_pose(pose: Dictionary, look: int) -> Array:
    var lean := float(pose.get("lean", 0.0))
    var up := float(pose.get("up", 0.0))
    var name := "rest"
    var tilt := 0.0
    match str(pose.get("hands", "rest")):
        "oar":
            tilt = float(pose.get("tilt", 0.0))
            # NOTE (mristin):
            # The holding pose is painted leaning a little: only who leans
            # to steer holds; who rows reaches and pulls, upright.
            if tilt != 0.0:
                name = "hold"
            else:
                name = "reach" if lean < 0.5 else "pull"
        "up":
            name = "rest" if up < 0.4 else "up"
        "point":
            name = "rest" if up < 0.4 else "point"
    var who: String = NAMES[look]
    for fallback in [name] + FALLBACKS.get(name, []):
        if Pictures.of("how_to", "%s_%s" % [who, fallback]) != null:
            return ["%s_%s" % [who, fallback], tilt]
    return ["", 0.0]


## Draw the painted rower (see [method painted_pose]), her lap at the bottom
## middle of the frame; return whether the pictures are there.
static func _draw_painted(
    canvas: CanvasItem, center: float, height: float, pose: Dictionary, look: int
) -> bool:
    var chosen := painted_pose(pose, look)
    if chosen[0] == "":
        return false
    var picture := Pictures.of("how_to", chosen[0])
    var size := Vector2(picture.get_size()) * (height * PAINTED_SCALE)
    var angle := deg_to_rad(TILT_DEGREES) * float(chosen[1])
    # NOTE (mristin):
    # The frame cuts the rower at her lap; leaning, she turns about the lap,
    # and goes down by as much as the corners of the cut rise, so that the cut
    # stays below the frame.
    var lap := Vector2(center, height + size.x / 2.0 * absf(sin(angle)))
    canvas.draw_set_transform(lap, angle)
    canvas.draw_texture_rect(picture, Rect2(Vector2(-size.x / 2.0, -size.y), size), false)
    canvas.draw_set_transform(Vector2.ZERO)
    return true


## Draw the rower of the [param look] (an index of [constant LOOKS]) on the
## [param canvas], at the [param center] x of a frame of the [param height]
## (its top at y = 0), in the [param pose] (see [method joints]).
static func draw(
    canvas: CanvasItem, center: float, height: float, pose: Dictionary, look := 0
) -> void:
    if _draw_painted(canvas, center, height, pose, look):
        return
    var colors: Dictionary = LOOKS[look]
    var at := joints(center, height, pose)
    var unit := height
    var head: Vector2 = at["head"]
    var hips: Vector2 = at["hips"]
    var shoulders: Array = at["shoulders"]
    # The braids hang behind the shoulders.
    for side in [-1.0, 1.0]:
        var top := head + Vector2(0.075 * side, 0.02) * unit
        for k in range(5):
            canvas.draw_circle(
                top + Vector2(0.004 * side, 0.04 * k) * unit, 0.026 * unit, colors["hair"]
            )
    # The dress, from the shoulders to the hips.
    var dress := PackedVector2Array(
        [
            shoulders[0],
            shoulders[1],
            hips + Vector2(0.15, 0) * unit,
            hips + Vector2(-0.15, 0) * unit,
        ]
    )
    canvas.draw_colored_polygon(dress, colors["dress"])
    canvas.draw_polyline(dress + PackedVector2Array([dress[0]]), INK, 0.006 * unit)
    # The arms: the sleeves and the hands.
    for i in range(2):
        var shoulder: Vector2 = shoulders[i]
        var elbow: Vector2 = at["elbows"][i]
        var wrist: Vector2 = at["wrists"][i]
        canvas.draw_line(shoulder, elbow, colors["sleeve"], 0.05 * unit)
        canvas.draw_line(elbow, wrist, colors["sleeve"], 0.045 * unit)
        canvas.draw_circle(elbow, 0.025 * unit, colors["sleeve"])
        canvas.draw_circle(wrist, 0.032 * unit, SKIN)
    # The head: the face, the hair, the eyes and the smile.
    canvas.draw_line(at["neck"], head, SKIN, 0.07 * unit)
    canvas.draw_circle(head, HEAD * unit, SKIN)
    canvas.draw_arc(head, HEAD * unit, PI * 1.05, PI * 1.95, 16, colors["hair"], 0.05 * unit)
    canvas.draw_arc(
        head, HEAD * unit * 0.86, PI * 1.12, PI * 1.88, 16, colors["band"], 0.022 * unit
    )
    for side in [-1.0, 1.0]:
        canvas.draw_circle(head + Vector2(0.032 * side, -0.005) * unit, 0.011 * unit, INK)
    canvas.draw_arc(
        head + Vector2(0, 0.02) * unit, 0.035 * unit, 0.3, PI - 0.3, 10, INK, 0.006 * unit
    )
