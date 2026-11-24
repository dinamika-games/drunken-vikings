extends Node

## Keep the camera and the vision running for the whole game, across all the
## scenes, so that the camera starts only once (which takes a few seconds).
##
## The scenes use `get_node("/root/Vision").service` (the VisionService, in
## C#): the camera picture, the key points of each player and the signals of
## the rowing (0, or 1 with two players).
##
## Start with `-- --no-camera` to run without the camera, e.g., in the tests,
## and with `-- --players=2` for two players side by side. With
## `-- --log-pose` (or `--log-pose=<times a second>`, 4 by default), the vision
## prints the head and the shoulders of the players and how they row and steer
## into the log, without recording anything.

@onready var service: Node = $Service


func _enter_tree() -> void:
    # NOTE (mristin):
    # The service starts the camera in its _ready, which runs before ours.
    if "--no-camera" in OS.get_cmdline_user_args():
        $Service.UseCamera = false


func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--players="):
            service.SetPlayerCount(int(arg.trim_prefix("--players=")))
        elif arg == "--log-pose":
            service.LogPoseRate = 4.0
        elif arg.begins_with("--log-pose="):
            service.LogPoseRate = float(arg.trim_prefix("--log-pose="))
