extends SceneTree

## Export every figure which the game draws in code, at twice its size in the
## game, on a transparent background, and a manifest.json with the size of
## each in the game and where it is anchored: the references for painting
## the art (see the prompts which go with them).
##
## [codeblock]
## $GODOT --path . --script dev/pictures/export_figures.gd -- <folder> -- --no-camera
## [/codeblock]
##
## It needs a display (not --headless), since it renders the figures.

## The game shows a metre as this many pixels (see world.gd, ZOOM).
const GAME_PX_PER_M := 6.0

## The figures are exported at this many times their size in the game.
const EXPORT_SCALE := 2.0

var _folder := ""
var _manifest: Array = []


func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if not arg.begins_with("--"):
            _folder = arg
    if _folder == "":
        _folder = OS.get_environment("HOME") + "/Downloads/viking"
    DirAccess.make_dir_recursive_absolute(_folder)
    _run.call_deferred()


func _run() -> void:
    var px := GAME_PX_PER_M * EXPORT_SCALE

    var boat := RowBoat.new()
    var one := RowerView.new()
    one.boat = boat
    await _export(
        "rowboat_one_rower",
        one,
        Vector2(40, 26),
        px,
        "The players' boat with Ylva pulling both oars; the bow points up."
    )
    var two := RowerView.new()
    two.boat = boat
    two.pair = true
    await _export(
        "rowboat_two_rowers",
        two,
        Vector2(40, 26),
        px,
        "The boat with two players: Ylva (left oar) and Sigrid (right oar)."
    )

    for kind in ["plain", "wedding", "pirate"]:
        var ship := Longship.new()
        ship.speed = Longship.CRUISE
        ship.wedding = kind == "wedding"
        ship.pirate = kind == "pirate"
        await _export(
            "longship_%s" % kind,
            ship,
            Vector2(30, 60),
            px,
            "A longship (%s), bow up, its oars and crew." % kind
        )

    var npc := NpcBoat.new()
    npc.skipper = Gossip.skipper(0)
    await _export(
        "skipper_boat",
        npc,
        Vector2(12, 20),
        px,
        "A small boat of a skipper on the lakes, with a little square sail."
    )

    for kind in Treats.KINDS:
        var treats := Treats.new()
        treats.items = [{"at": Vector2.ZERO, "kind": kind, "age": 0.0, "spin": 0.0}]
        await _export(
            "treat_%s" % kind,
            treats,
            Vector2(8, 8),
            px,
            "A treat which the wedding drops into the water: %s." % kind
        )

    for kind in [
        "home",
        "market",
        "healer",
        "inn",
        "fishers",
        "brewer",
        "beekeeper",
        "horse_farm",
        "weaver",
        "chieftain",
        "farm",
        "mill",
        "smith",
        "potter",
        "herders"
    ]:
        var village := VillageFigure.new()
        village.kind = kind
        await _export(
            "settlement_%s" % kind,
            village,
            Vector2(230, 180),
            px * 0.5,
            "A settlement (%s) seen from above; its jetty points down to the water." % kind
        )

    var file := FileAccess.open(_folder + "/manifest.json", FileAccess.WRITE)
    file.store_string(
        JSON.stringify(
            {
                "game_px_per_metre": GAME_PX_PER_M,
                "export_scale": EXPORT_SCALE,
                "figures": _manifest
            },
            "  "
        )
    )
    print("Exported %d figures into %s" % [_manifest.size(), _folder])
    quit()


## Render the [param node] (drawn around its origin, in metres) into a picture
## of [param size_m] metres, at [param px] pixels per metre.
func _export(name: String, node: Node2D, size_m: Vector2, px: float, what: String) -> void:
    var viewport := SubViewport.new()
    viewport.transparent_bg = true
    viewport.size = Vector2i((size_m * px).ceil())
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var holder := Node2D.new()
    holder.position = Vector2(viewport.size) / 2.0
    holder.scale = Vector2(px, px)
    viewport.add_child(holder)
    holder.add_child(node)
    for i in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    image.save_png("%s/%s.png" % [_folder, name])
    (
        _manifest
        . append(
            {
                "file": name + ".png",
                "what": what,
                "size_in_game_px":
                [
                    roundi(size_m.x * GAME_PX_PER_M * px / (GAME_PX_PER_M * EXPORT_SCALE)),
                    roundi(size_m.y * GAME_PX_PER_M * px / (GAME_PX_PER_M * EXPORT_SCALE))
                ],
                "exported_px": [viewport.size.x, viewport.size.y],
                "anchor": "the middle of the picture",
                "facing":
                (
                    "up (north): the bow points to the top"
                    if not name.begins_with("settlement")
                    else "the jetty points down"
                ),
            }
        )
    )
    viewport.queue_free()


## A settlement on its own, as the map draws it, with its jetty to the south.
class VillageFigure:
    extends Node2D

    var kind := "home"

    func _draw() -> void:
        var map := LakeMap.new()
        map.places = []
        map._draw_village(self, Vector2(0, -10), Vector2(0, 50), kind)
        map.free()
