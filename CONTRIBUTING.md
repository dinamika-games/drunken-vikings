# Contributing

## Overview

The game is made with [Godot] 4.6 (.NET), in GDScript and C#.

* **The vision is in C#** (`scenes/vision/`), all on the CPU through ONNX Runtime:
  * `PoseFollower` finds the players with RTMO-t and follows each of them on every frame with RTMPose-t (one or two players, each in their half of the picture).
  * `RowingSignals` measures the candidate signals of the rowing and the steering on each pose (the torso, the head, the hands, the elbows, the shoulders), in the unit of the player (`BodyScale`, the widest shoulders of late).
  * `VisionRecorder` records the key points and the signals as JSON lines.

  The core (`scenes/vision/core/`) does not depend on Godot, so we unit-test it with plain .NET in `tests/DrunkenVikings.Tests/`.
  The node `VisionService` runs it all and offers plain getters to GDScript; the autoload `Vision` keeps it running across the scenes.
* **The development tools** live in `dev/`, which Godot ignores, so that they are never released with the game.

[Godot]: https://godotengine.org

## Setting up

You need [Git LFS] (the ONNX models are in LFS), the .NET 8 SDK, the **.NET** build of Godot 4.6.2, Python 3.10+ and a webcam which supports 640x480.

```
export GODOT=~/apps/Godot_v4.6.2-stable_mono_linux_x86_64/Godot_v4.6.2-stable_mono_linux.x86_64
git lfs install && git lfs pull
python3 -m venv venv && touch venv/.gdignore
venv/bin/pip install -r dev/requirements.txt
dotnet build DrunkenVikings.sln
$GODOT --headless --path . --import
```

Run the tests with `dotnet test tests/DrunkenVikings.Tests`.

[Git LFS]: https://git-lfs.com

## Running the game

```
$GODOT --path . [-- --players=2] [--new]
```

The game starts with the start screen (`scenes/start/`): how many row, and which mode, the party (`scenes/level/level.tscn`: follow the wedding longship and pick up the treats it drops) or the practical mode, which opens the Home Lakes (`scenes/world/`): row to the settlements to trade (glide slowly to a jetty to dock), hail the boats on the lakes (glide slowly close to them), and row home to the farm, where a night's sleep ends the day and saves the voyage (`user://voyage.json`).
The players row with their bodies and choose on the screens with their hands: a raised hand moves a cursor, which sticks to the cards, and holding it still for 2 s chooses (`HandCursor`, `DwellButton`, `ChoicePanel`; the hands come from the YOLOX hand detector, which runs only while a screen shows). The mouse clicks the cards, too. Escape quits.

* `--players=2`: two players, each pulls the oar on their side; the boat turns away from the stronger rower.
* `--new`: a new voyage instead of the saved one.
* `--no-camera --autopilot`: the boat trades by itself, to try the world without the camera; for the developers, `--dev-keys` lets the arrows and Space choose on the screens, and `--shots=<dir>` saves screenshots.
* `--log-pose[=<times a second>]`: print the head and the shoulders of the players and how they row and steer into the log (4 times a second by default), e.g., `Pose: t=12.34 p=0 src=RtmPose head=(330,200) unit=180 home=325 shift=-0.03 tilt=+2.1 level=-1.0 steer=+0.00 (head +0.00, body +0.00) strokes=5 pull=0.40`; only numbers, and nothing is recorded.
  In the party, it also prints where the boat and the longship are and the nearest treats as seen from the boat (`next=[(metres ahead, metres to the right, bearing), ...]`), and every drop and pick, on the same clock (`t`) as the poses, to study where the player meant to go.

The chase mode (`scenes/chase/`: row to a town before the pirates catch you; the pirates find their way on the grid of the water of the map, `LakeMap.water_path`) runs directly with `$GODOT --path . res://scenes/chase/chase.tscn`. The party mode runs directly with `$GODOT --path . res://scenes/level/level.tscn` (add `-- --record` to record the vision while playing, `-- --no-camera --autopilot` to let it play itself), and the practical mode with `$GODOT --path . res://scenes/world/world.tscn`.

The map of the Home Lakes is made by `venv/bin/python dev/maps/make_lakes.py --name home_lakes` (the lakes, the islands, the settlements and the ways of the boats between them; `--plot out.png` draws it). The economy (`data/economy/`) and the farm (`data/farm/`) are plain data.

## The tests

```
dotnet test tests/DrunkenVikings.Tests
for test in tests/godot/test_*.gd; do $GODOT --headless --path . --script $test -- --no-camera; done
```

## The rowing experiment

Record freely what the vision sees while you row:

```
$GODOT --path . --script dev/rowing/record_rowing.gd -- [--players=2] [--note=TEXT] [--frames] [<recording.jsonl>]
```

* It starts to record as soon as the camera sees you (all players, with `--players=2`), and stops on **Escape**.
  **Space** marks a moment in the recording, e.g., where you start to steer.
* The screen shows the mirrored camera with the skeleton (grey dots: unsure key points), which model found the pose, and the signals over the last 10 s, so you see at once what moves with the rowing.
* The recording goes to `~/Downloads/rowing_recordings/free-<time>.jsonl` by default: only numbers (the key points and the signals), no pictures.
  Describe the session with `--note`, e.g., `--note="camera on a chair, 2 m, facing"`.
* With `--frames`, every camera frame is also saved as a picture next to the recording (`<recording>.frames/`), to study the session frame by frame.
  Record only people who agreed to it (for children, their parents, too), and never commit the recordings.

Then study the recording:

```
venv/bin/python dev/rowing/analyze.py <recording.jsonl> [--plot out.png]
```

It prints how well the vision saw the players (the poses a second, which key points it saw), and for each signal its range against its noise and the rhythm it swings in (the strokes), over the whole recording and in windows between the marks.

To see how the game steers on a recording (the head and the tilt of the shoulders, see `RowingMeter`), replay it:

```
venv/bin/python dev/rowing/replay_steering.py <recording.jsonl> [--every 0.25] [--csv out.csv]
```

To study a party played with `-- --log-pose` (how the vision saw the player, how they steered, and which treats they picked), save its log and analyze it:

```
$GODOT --path . res://scenes/level/level.tscn -- --log-pose > party.log 2>&1
venv/bin/python dev/rowing/analyze_party_log.py party.log
```

## Formatting

```
venv/bin/black -l 110 dev/
venv/bin/gdformat dev/ scenes/
venv/bin/gdlint dev/ scenes/
```
