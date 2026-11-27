class_name LakeGrowth
extends RefCounted

## What grows on the lakes of a level (see LakeMap): the trees on the land,
## the reeds and the water lilies by the shores, and the details on the grass.
##
## NOTE (mristin):
## These live apart from LakeMap only to keep its file short.


## A tree or a bush on the land (see LakeMap._plant_trees).
class GrowingTree:
    var at: Vector2

    ## The radius of the crown, in metres.
    var radius: float

    ## Whether the crown is drawn darker when no picture is painted.
    var dark: bool

    ## The painted picture, as "<sheet>/<picture>" (see Pictures).
    var picture: String
    var angle: float

    func _init(
        stands_at: Vector2, crown: float, darker: bool, painted: String, turned: float
    ) -> void:
        at = stands_at
        radius = crown
        dark = darker
        picture = painted
        angle = turned


## The reeds or the water lilies, a few metres out from a shore (see
## LakeMap._plant_in_water).
class WaterPlant:
    var at: Vector2

    ## The picture on the sheet "nature" (see Pictures).
    var picture: String

    ## How large it is drawn, in metres.
    var size: float
    var angle: float

    func _init(grows_at: Vector2, painted: String, drawn: float, turned: float) -> void:
        at = grows_at
        picture = painted
        size = drawn
        angle = turned


## A detail on the grass (see LakeMap._scatter_details).
class GrassDetail:
    var at: Vector2

    ## The picture on the sheet "grass_details" (see Pictures).
    var picture: String

    ## How long it is drawn, in metres.
    var length: float
    var angle: float

    ## Whether it lies on an island.
    var island: bool

    func _init(
        lies_at: Vector2, painted: String, drawn: float, turned: float, on_island: bool
    ) -> void:
        at = lies_at
        picture = painted
        length = drawn
        angle = turned
        island = on_island
