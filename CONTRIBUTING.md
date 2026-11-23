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

## Formatting

```
venv/bin/black -l 110 dev/
venv/bin/gdformat dev/ scenes/
venv/bin/gdlint dev/ scenes/
```
