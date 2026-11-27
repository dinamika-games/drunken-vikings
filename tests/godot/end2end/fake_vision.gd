# gdlint: disable=function-name, class-variable-name, max-public-methods
# NOTE: The names are those of the VisionService in C#, which the game calls.
extends Node
## The camera of the end-to-end tests: it stands in for the VisionService (see
## scenes/vision/vision.gd), so that the bot plays the game through the very
## inputs which the players give with their bodies: it rows strokes, leans to
## steer, raises both hands to brake, and raises a hand to point at the cards
## (see HandCursor). It offers the methods of the service which the scripts
## call, with nothing of the camera behind them.
##
## Not a test itself (its name does not start with test_).

## The players' strokes so far, and the depth of the last.
var strokes := [0, 0]
var depth := [0.75, 0.75]

## How far each player leans, in [-1, 1] (see RowingMeter.Steer).
var steer := [0.0, 0.0]

## Whether the players hold both hands above the head.
var brake := [false, false]

## Where the raised hand points, normalized in the mirrored picture, or
## Vector2.INF while no hand is raised.
var hand := Vector2.INF

var players := 1
var hand_tracking := false
var hands_for_picture := false
var LogPoseRate := 0.0
var Now := 0.0


func _process(delta: float) -> void:
    Now += delta


## Row one stroke with the player (both, if -1).
func row(player := -1, stroke_depth := 0.75) -> void:
    for p in range(players):
        if player < 0 or player == p:
            strokes[p] += 1
            depth[p] = stroke_depth


## Point the raised hand at the [param point] of the screen of [param size]
## (see HandCursor.reach), or lower it with Vector2.INF.
func point_at(point: Vector2, size: Vector2) -> void:
    if point == Vector2.INF:
        hand = Vector2.INF
        return
    hand = HandCursor.reach.position + point / size * HandCursor.reach.size


# The methods of the VisionService which the game calls.


func IsRunning() -> bool:
    return true


func GetStatus() -> String:
    return "Running"


func GetStatusMessage() -> String:
    return ""


func GetPlayerCount() -> int:
    return players


func SetPlayerCount(count: int) -> void:
    players = clampi(count, 1, 2)


func HasPlayer(player: int) -> bool:
    return player < players


func GetStrokes(player: int) -> int:
    return strokes[clampi(player, 0, 1)]


func GetLastStrokeDepth(player: int) -> float:
    return depth[clampi(player, 0, 1)]


func GetSteer(player: int) -> float:
    return steer[clampi(player, 0, 1)]


func GetBrake(player: int) -> bool:
    return brake[clampi(player, 0, 1)]


func GetPull(_player: int) -> float:
    return -1.0


func GetShift(_player: int) -> float:
    return 0.0


func GetKeypoints(_player: int) -> PackedVector2Array:
    return PackedVector2Array()


func GetKeypointScores(_player: int) -> PackedFloat32Array:
    return PackedFloat32Array()


func SetHandTracking(on: bool) -> void:
    hand_tracking = on


func SetHandsForPicture(on: bool) -> void:
    hands_for_picture = on


## The raised hand, while the screens look for hands (as the hand detector).
func GetHands() -> Array[Vector2]:
    if hand_tracking and hand != Vector2.INF:
        return [hand]
    return []


func GetCameraTexture() -> Texture2D:
    return null


func GetInferenceMs() -> float:
    return 0.0


func GetPoseRate() -> float:
    return 0.0


func GetSignalNames() -> PackedStringArray:
    return PackedStringArray()


func GetSignals(_player: int) -> PackedFloat32Array:
    return PackedFloat32Array()


func ResetPlayers() -> void:
    pass


func Shutdown() -> void:
    pass
