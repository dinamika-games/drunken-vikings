class_name Looks
extends RefCounted

## How the players look: each rower chooses a viking girl or a viking boy,
## and the colour of the skin, of the hair and of the clothes. A look is a
## Dictionary {"figure": "girl" or "boy", "skin", "hair", "clothes": the
## index into [constant SKINS], [constant HAIRS] and [constant CLOTHES]};
## GameState keeps the looks of the journey (see GameState.looks).
##
## The painted pictures (the dress-up of the camera picture, see DressUp,
## and the rowers in the boat, see RowerView) are recoloured by their masks
## (<name>_mask.png, cut by dev/pictures/cut_looks.py; see Recolor.cs) when a
## look first needs them, and kept. An area in the colour it was painted in
## stays as painted.

const FIGURES := ["girl", "boy"]

## The colours to choose from: {"name", "color"}. The colour is the average
## of the area as painted (its outlines and shadows included, see
## Recoloring.cs), so it is darker than the colour one sees.
const SKINS := [
    {"name": "Fair", "color": Color("e8b08a")},
    {"name": "Light", "color": Color("d8955f")},
    {"name": "Tan", "color": Color("b47546")},
    {"name": "Brown", "color": Color("865034")},
    {"name": "Dark", "color": Color("553222")},
]
const HAIRS := [
    {"name": "Blond", "color": Color("cc9035")},
    {"name": "Red", "color": Color("b65a20")},
    {"name": "Brown", "color": Color("7a4a26")},
    {"name": "Dark brown", "color": Color("4a2c1a")},
    {"name": "Black", "color": Color("262220")},
]
const CLOTHES := [
    {"name": "Teal", "color": Color("36574c")},
    {"name": "Plum", "color": Color("69363f")},
    {"name": "Blue", "color": Color("2e4f80")},
    {"name": "Red", "color": Color("8e2e26")},
    {"name": "Green", "color": Color("4a6a2a")},
]

## The areas of a look, in the order of the masks (see Recoloring.cs).
const AREAS := ["skin", "hair", "clothes"]

## What the pictures were painted in, by the prefix of their names: the
## indices of the skin, the hair and the clothes.
const _PAINTED := {
    "dress/": [1, 0, 0],
    "dress_boy/": [1, 0, 0],
    "rowboat/ylva_": [1, 0, 0],
    "rowboat/sigrid_": [1, 1, 1],
    "rowboat/boy_": [1, 0, 0],
}

## The recolouring (C#), loaded when a picture first needs it.
const _RECOLOR := "res://scenes/looks/Recolor.cs"

static var _baked := {}
static var _recolor: RefCounted


## The look of the [param player] of a new journey: Ylva (blond, in teal) for
## the first, Sigrid (red braids, in plum) for the second.
static func default_look(player: int) -> Dictionary:
    if player == 1:
        return {"figure": "girl", "skin": 1, "hair": 1, "clothes": 1}
    return {"figure": "girl", "skin": 1, "hair": 0, "clothes": 0}


## The [param value] (e.g., from a save) as a look, what is missing or wrong in
## it as in the default look of the [param player].
static func normalized(value: Variant, player: int) -> Dictionary:
    var look := default_look(player)
    if not value is Dictionary:
        return look
    var data: Dictionary = value
    if str(data.get("figure", "")) in FIGURES:
        look["figure"] = str(data["figure"])
    for pair in [["skin", SKINS], ["hair", HAIRS], ["clothes", CLOTHES]]:
        var index := int(data.get(pair[0], -1))
        if index >= 0 and index < (pair[1] as Array).size():
            look[pair[0]] = index
    return look


## The colours to choose from for the [param area] ("skin", "hair" or "clothes").
static func palette(area: String) -> Array:
    match area:
        "skin":
            return SKINS
        "hair":
            return HAIRS
        _:
            return CLOTHES


## The sheet of the dress-up of the [param look] (see DressUp).
static func dress_sheet(look: Dictionary) -> String:
    return "dress_boy" if look.get("figure", "girl") == "boy" else "dress"


## The piece [param name] of the dress-up of the [param look], or null if it
## is not painted.
static func dress(look: Dictionary, name: String) -> Texture2D:
    return _picture(dress_sheet(look), name, look)


## The rower of the [param look] in the boat, in the [param pose] ("forward",
## "middle", "back" or "wave"): pulling both oars, or one oar with both
## hands ([param one_oar]); null if it is not painted.
static func rower(look: Dictionary, one_oar: bool, pose: String) -> Texture2D:
    var who: String
    if look.get("figure", "girl") == "boy":
        who = "boy_one" if one_oar else "boy"
    else:
        who = "sigrid" if one_oar else "ylva"
    return _picture("rowboat", "%s_%s" % [who, pose], look)


## The picture [param name] of the [param sheet] in the colours of the
## [param look]: as painted where its colours are those of the look (or
## where it has no mask), else recoloured, once.
static func _picture(sheet: String, name: String, look: Dictionary) -> Texture2D:
    var painted := Pictures.of(sheet, name)
    if painted == null:
        return null
    var as_painted := _painted_in(sheet + "/" + name)
    var colors: Array[Color] = []
    var changed := false
    for i in range(AREAS.size()):
        var area: String = AREAS[i]
        var index := int(look.get(area, as_painted[i]))
        if index == as_painted[i]:
            colors.append(Color(0, 0, 0, 0))
        else:
            colors.append((palette(area)[index] as Dictionary)["color"])
            changed = true
    if not changed:
        return painted
    var key := "%s/%s/%s" % [sheet, name, colors]
    if _baked.has(key):
        return _baked[key]
    var mask := Pictures.of(sheet, name + "_mask")
    var result: Texture2D = painted
    if mask != null:
        if _recolor == null:
            _recolor = (load(_RECOLOR) as Script).new()
        var baked: Variant = _recolor.call("Bake", painted, mask, colors[0], colors[1], colors[2])
        if baked is Texture2D:
            result = baked
    _baked[key] = result
    return result


## The indices of the skin, the hair and the clothes which the picture of
## [param key] (sheet/name) was painted in.
static func _painted_in(key: String) -> Array:
    var best := ""
    for prefix in _PAINTED.keys():
        if key.begins_with(prefix) and (prefix as String).length() > best.length():
            best = prefix
    return _PAINTED[best] if best != "" else [1, 0, 0]
