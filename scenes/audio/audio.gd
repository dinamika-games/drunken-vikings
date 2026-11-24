class_name Audio
extends RefCounted

## The music and the sounds of the game, for every script: they pass on to
## the autoload AudioService (see audio_service.gd), if it runs, and do
## nothing otherwise (e.g., in a test without it). Scripts compiled before the
## autoloads exist (e.g., by the tests) can call them, too.

## The sound of each animal of the farm (see Farm.animal_kinds).
const ANIMALS := {"hen": "hens", "sheep": "sheep", "goat": "goat", "cow": "cow", "bees": "bees"}


## The autoload AudioService, or null.
static func service() -> Node:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.root.get_node_or_null("AudioService") if tree != null else null


## Play the music of the [param mood] (see AudioService.music).
static func music(mood: String) -> void:
    var audio := service()
    if audio != null:
        audio.music(mood)


## Play the sound of the [param name] (see AudioService.play).
static func play(name: String, db := 0.0) -> void:
    var audio := service()
    if audio != null:
        audio.play(name, db)


## Loop the sound of the [param name] under everything (see AudioService.ambient).
static func ambient(name: String) -> void:
    var audio := service()
    if audio != null:
        audio.ambient(name)


## Stop the music and every sound (e.g., before the game quits).
static func silence() -> void:
    var audio := service()
    if audio != null:
        audio.silence()


## The mood of the music now, or "".
static func mood() -> String:
    var audio := service()
    return audio.mood if audio != null else ""


## The sounds played so far, by name: how often.
static func played() -> Dictionary:
    var audio := service()
    return audio.played if audio != null else {}
