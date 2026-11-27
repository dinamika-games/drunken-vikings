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
A new journey first shows **How to play** (`scenes/how_to/`, also from the card "How to play" when choosing what to play): the parts of `data/how_to/how_to.json`, one after the other, until a hand holds Ready!; on the left the players in the camera picture (`HowToFigure`), on the right the boat of the game rowed by the same strokes; one rower learns to steer by leaning, two rowers to row together and turn with the oars. The rowers, the room behind them and the jetty are painted (`assets/pictures/how_to/`, cut by `venv/bin/python dev/pictures/cut_sheets.py how_to_rowers how_to_jetty` from the sheets of `~/Downloads/viking/how-to/`: the rowers figure by figure, onto canvases of the same size, their laps at the bottom middle), and drawn in code when missing. `tests/godot/test_how_to.gd` checks that every part shows what its line says, and `venv/bin/python dev/how_to/make_svgs.py` draws the parts into SVGs (`~/Downloads/viking/how-to/all_svgs/`, with the prompts to paint them in `~/Downloads/viking/how-to/PROMPT.md`).
The players row with their bodies and choose on the screens with their hands: a raised hand moves a cursor, which sticks to the cards, and holding it still for 2 s chooses (`HandCursor`, `DwellButton`, `ChoicePanel`; the hands come from the YOLOX hand detector, which runs only while a screen shows). The mouse clicks the cards, too. **C** shows the map of the lakes with where the missions lead (the game waits). Escape quits.

* `--players=2`: two players, each pulls the oar on their side; the boat turns away from the stronger rower.
* `--new`: a new voyage instead of the saved one.
* `--no-camera --autopilot`: the boat trades by itself, to try the world without the camera; for the developers, `--dev-keys` lets the arrows and Space choose on the screens, and `--shots=<dir>` saves screenshots.
* `--skeleton`: draw the key points of the pose over the camera picture, too (the players are dressed up as Ylva there, see `DressUp`; the rowing experiment shows only the skeleton).
* `--log-pose[=<times a second>]`: print the head and the shoulders of the players and how they row and steer into the log (4 times a second by default), e.g., `Pose: t=12.34 p=0 src=RtmPose head=(330,200) unit=180 home=325 shift=-0.03 tilt=+2.1 level=-1.0 steer=+0.00 (head +0.00, body +0.00) strokes=5 pull=0.40`; only numbers, and nothing is recorded.
  In the party, it also prints where the boat and the longship are and the nearest treats as seen from the boat (`next=[(metres ahead, metres to the right, bearing), ...]`), and every drop and pick, on the same clock (`t`) as the poses, to study where the player meant to go.

The chase mode (`scenes/chase/`: row to a town before the pirates catch you; the pirates find their way on the grid of the water of the map, `LakeMap.water_path`) runs directly with `$GODOT --path . res://scenes/chase/chase.tscn`. The party mode runs directly with `$GODOT --path . res://scenes/level/level.tscn` (add `-- --record` to record the vision while playing, `-- --no-camera --autopilot` to let it play itself), and the practical mode with `$GODOT --path . res://scenes/world/world.tscn`.

The ships of the shipwright (`data/ships/ships.json`, see `Ships` and DESIGN.md, section 8) are sold in her shipyard in Ekvik; each changes how the boat rows (`RowBoat.set_ship`) and is drawn under the players from its painted parts, placed on its hull by its "drawn" data (`Longship.look`, `world.gd`, `refit`).

The missions (`data/missions/<nnn>_<id>/mission.json`, see DESIGN.md, section 10) are offered in the ports (the card "Tasks"); `Missions` (`scenes/game/missions.gd`) checks their data when the game starts, and `tests/godot/test_missions.gd` plays all of them through, in their order, as a careful player would.

The map of the Home Lakes is made by `venv/bin/python dev/maps/make_lakes.py --name home_lakes` (the lakes, the islands, the settlements and the ways of the boats between them, from berth to berth, clear of the shores and the jetties; `--plot out.png` draws it).
`tests/godot/test_map.gd` checks the preconditions of the map, on which the boats which the game steers rely: `LakeMap.is_water` tells the water from the land everywhere (it counts the shores crossed itself, see `Shores`: `Geometry2D.is_point_in_polygon` put thin lines of land across the lakes), every berth is clear of the shore, the routes between the places (the skippers), the route of the party (the wedding longship) and the grid of the water (the pirates) stay on the water and keep 3 m from the land and the jetties. The economy (`data/economy/`) and the farm (`data/farm/`) are plain data.

## The tests

```
dotnet test tests/DrunkenVikings.Tests
for test in tests/godot/test_*.gd; do $GODOT --headless --path . --script $test -- --no-camera; done
for mode in party chase lakes; do $GODOT --headless --fixed-fps 60 --path . --script tests/godot/end2end/test_$mode.gd -- --no-camera; done
```

**The end-to-end tests**, one for each mode of the game (`tests/godot/end2end/test_party.gd`, `test_chase.gd` and `test_lakes.gd`, on the common base `playthrough.gd`), play the game from the very first start on (each chooses the language and starts a new journey), as the players do: only through the camera, which `fake_vision.gd` stands in for (it rows strokes, leans to steer, raises both hands to brake, and holds a raised hand on a card until it is chosen), and with Escape and C from the keyboard.
The party follows the wedding to its end and goes to the farm; the chase escapes the pirates and goes on with the journey, which must keep the reward; the lakes do the first 40 tasks on the Home Lakes (`lakes_bot.gd`: it takes the tasks, rows where they lead, buys, carries, hails, plants, unloads, sleeps when a task waits, trades when it lacks silver, buys a ship when it has silver to spare, and takes detours: the news, its tasks, the deals of the skippers, the map, Escape once), start and delete a second journey with two rowers, and go on with the first, which must come back from the disk as it was left.
All the way, they check the contracts of the game on every frame (`contracts.gd`, in the tests only): e.g., every screen lets the players go on, the cards fit the screen and their texts fit the cards, the boat never leaves the water nor crosses the land, the boat rows exactly while no screen shows, the silver never goes below zero, the cargo fits the hold, nothing of a finished task stays aboard, and the save on the disk is the voyage in memory whenever the boat docks.
They fail on any error which the game logs (`error_log.gd`), and whenever the players get stuck: a card which the hand holds is not chosen, the boat comes no closer to its jetty, or a task is not done within 40 legs.

They run as fast as the computer can: `--fixed-fps 60` makes every frame 1/60 s of the game however fast it is computed, the game runs 10 times faster than that, and what redraws on every frame (the boats, the wakes, the HUD) is drawn only on every 8th frame, so that the party and the chase take some seconds, and the five hours of the game on the lakes a few minutes (some 250 to 700 frames a second, depending on the computer); each test has its own limit of the wall clock (2 minutes for the party and the chase, 10 for the lakes).
The random choices come from a seed; try others with `-- --seed=<n>`, and more tasks on the lakes with `-- --tasks=<n>` (all 100 take longer: e.g., `-- --tasks=100 --wall-seconds=1200`); `-- --trace` prints every choice and where the bot rows.

**Always log the runs of the fuzzing tests** (the end-to-end tests and the balance bot) to a file, and delete the log only once the test passes; otherwise a failure means running it all again only to see what went wrong, which takes double the time.
`dev/logged.sh <log> <command>...` does just that: it keeps the log and shows its end when the test fails, and deletes it when the test passes (so never delete the logs by hand):

```
dev/logged.sh lakes.log $GODOT --headless --fixed-fps 60 --path . --script tests/godot/end2end/test_lakes.gd -- --no-camera
```

Run one end-to-end test at a time: they share the saved journeys (`user://`), so two at once see each other's journeys and fail.

**The balance** of the farm and the trading is checked by a bot which plays the rules of the game (`GameState`, `Economy`, `Farm`, `Missions`, `Ships`) without rowing, a trip taking the length of its route at the speed of the ship, many times with several strategies (a careful child doing the tasks, the tasks with trading on the way, a pure trader, a farmer, and a random fuzzer), and reports when the players can buy the ships and the land, in hours of play and in tasks done, and whether any run gets stuck:

```
dev/logged.sh balance.log $GODOT --headless --path . --script dev/balance/balance.gd -- --no-camera [--runs=20] [--hours=50] [--speed=8] [--strategies=tasks,mixed,trader,farmer,random] [--ship-prices=80,220,450,800] [--reward-scale=1.0]
```

With the rewards of the tasks as they are, a careful child gets the færing after about 30 tasks (7 hours of play at 8 m/s), the karve after about 65 and the knarr near the end; the longship is a goal for those who also trade or farm.

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

## The music and the sounds

The game plays its music and its sounds through `Audio` (`scenes/audio/audio.gd`, which passes on to the autoload `AudioService`): the music by mood (`Audio.music("lakes")`: the start screen, the farm, the lakes, the party, the chase; the tunes of a mood shuffled, fading into each other), the sounds over it (`Audio.play("oar")`), and one sound of the surroundings looping under it all (`Audio.ambient("water")`).
Start the game with `-- --mute` for silence.

The music and the sounds are made from the downloads of `~/Downloads/viking/music/` (MIDI) and `~/Downloads/viking/sounds/` (see `~/Downloads/viking/AUDIO_SOURCES.md`, and THIRD_PARTY_NOTICES.md for their licenses) by

```
venv/bin/python dev/audio/make_audio.py
```

which renders the tunes with TiMidity++ and the FluidR3 General MIDI SoundFont (`sudo apt install timidity fluid-soundfont-gm`), and cuts, fades and evens out the sounds with ffmpeg and sox, into `assets/audio/`.
The end-to-end tests check that the music fits where the players are, and that the players hear the sounds of what they do.

## Formatting

```
venv/bin/black -l 110 dev/
venv/bin/gdformat dev/ scenes/
venv/bin/gdlint dev/ scenes/
```

## Packaging

The export presets (`export_presets.cfg`) package the game for Linux, Windows and macOS into `build/`.
You need the export templates of Godot 4.6.2 (.NET) (in the editor: Editor, Manage Export Templates), then:

```
GODOT=<the Godot executable> venv/bin/python dev/package.py
```

Pass `--platforms` to package only some, e.g., `--platforms windows`.
The script exports the presets, adds `LICENSE`, `THIRD_PARTY_NOTICES.md` and the licenses of Godot (`licenses/godot/`), of the models and of ONNX Runtime to every package, and copies the camera extension next to the Windows executable: Godot 4.6 has no camera on Windows, and the game loads the extension from there itself (see `addons/CameraServerExtension/CameraServerExtension.gdextension` and `VisionService.StartCameraExtension`).
Export with the script rather than from the editor, or the Windows package has no camera.
It fails if Godot reports an error (Godot exits with zero even if it fails to build the C# part) or a package misses ONNX Runtime.

## Translations

The game is written in English and translated to Arabic (`ar`), Danish (`da`), German (`de`), Spanish (`es`), French (`fr`), Hindi (`hi`), Italian (`it`), Japanese (`ja`), Korean (`ko`), Norwegian Bokmål (`nb`), Russian (`ru`), Bosnian, Croatian and Serbian as one text (`sh`), Albanian (`sq`), Swedish (`sv`), Turkish (`tr`) and Chinese (`zh`); see DESIGN.md, "Technical design".
The players choose the language on the very first screen (and later with the card "Language" of the journeys); `-- --lang=<code>` starts the game in a language.

* **In the code,** every text a player sees goes through `Grammar.text("...")` (or `ChoicePanel.card("...")` for the title of a card and `ChoicePanel.detail("...")` for its second line) with the whole sentence and named placeholders: `Grammar.text("Row to {place}.", {"place": place_name})`. Never glue a sentence together from pieces. A string value of a placeholder is itself an English message (a name of the data), translated when filled; `Grammar.phrase(...)` inserts a phrase with placeholders of its own, `Grammar.raw(...)` a text which is not translated, and an Array a list. A comment `# TRANSLATORS: ...` right above the call reaches the translators. A constant whose texts are messages gets the comment `# TRANSLATORS[<field>@<kind or context>]: ...` (see `dev/translations/extract.py`).
* **Numbers, cases and the rowers** (see `scenes/languages/grammar.gd`): `{count|crate|crates}` picks the form for the number by the plural rule of the language (English writes these, too); `{place@to}` asks for a form of an inserted name, a message of its own with that context (the places have `to`, `in` and `from`, the persons `acc` and `dat`, the goods `acc` and `gen`, the counted things, the crops, the plots, the ships and the gifts `acc`); `{crew|one boy|one girl|two rowers|two girls}` picks the words for the rowers who are addressed.
* **The data** holds the nouns as they stand in a sentence ("salt", "the sunny hill"; a card shows them with a capital letter) and counted phrases (`"counted": "{count|a barrel of ale|{count} barrels of ale}"`).
* **Collect the messages** after changing texts:

  ```
  venv/bin/python dev/translations/extract.py
  ```

  This updates `translations/messages.pot` and merges it into every `translations/<code>.po`, keeping the existing translations.
* **Translate** the `.po` files with any PO editor (e.g., Poedit), or in batches of JSON with `venv/bin/python dev/translations/batch.py dump <code> --missing` and `... apply <code> <file.json>`. A new translation stays marked as *fuzzy* until a native speaker has reviewed it in the game; the game shows it anyway (see `scenes/languages/languages.gd`).
* **Check** the placeholders and the forms (`--verbose` lists the open messages):

  ```
  venv/bin/python dev/translations/check.py --verbose
  ```

* **The fonts:** after the translations change, cut the fonts of Chinese, Japanese and Korean to their characters again (and copy the Arabic and Devanagari fonts) from the Noto fonts of the system (`fonts-noto-core`, `fonts-noto-cjk`):

  ```
  venv/bin/python dev/translations/make_fonts.py
  ```

* **The texts fit:** `tests/godot/test_text_fit.gd` lays out every text of the cards in every language (every value of its placeholders, the longest form for the rowers) and checks that it fits its card, and that the fonts show every letter; `-- --lang=<code>` checks one language. The end-to-end tests play in any language, too (`-- --lang=<code>`), and their contracts check every screen they see.
* **Add a language** with one entry in `translations/languages.json` (the code, its name in itself, an optional second line, "Choose your language" in itself, optionally a short name for the card "Language", and `"rtl": true` if it is written from right to left; keep English first and the rest sorted by the code), then run `extract.py`, which creates its `.po` file; add its plural rule to `Grammar.plural_index` and `PLURAL_FORMS` of `extract.py` if it is not "one and other", and its font to `make_fonts.py` and `Languages` if Godot's font lacks its letters.

## A class, not a positional array

When a few values of different kinds belong together (a record: e.g., how far a skipper was from the boat, where the boat lay and how it headed), give them a class with named fields rather than an array read by position.
`before.gap` tells what it is, `before[0]` does not, and a value put in the wrong place goes unnoticed.
In GDScript, a small inner class does it (see `_Sighting` in `tests/godot/end2end/contracts.gd`):

```gdscript
class _Sighting:
    var gap: float
    var at: Vector2
    var heading: float
```

An array stays right for values of the same kind, also when read by position: the two ends of a segment, the left and the right rower (`catches[0]`, `catches[1]`), the first of a list (`offers[0]`), and what the data files keep as an array (a picture as `[sheet, name]`).
In Python, likewise, a pydantic model rather than a tuple.

## The dress in the camera picture

The players are dressed up as the vikings of their looks in the camera picture (Ylva's dress, or the boy's tunic in `assets/pictures/dress_boy/`, see below) (`scenes/camera_panel/dress_up.gd`): the hair by the eyes, the bodice from the shoulders to the waist, the skirt over the lap, the sleeves along the arms and the fists on the oar, painted with ChatGPT from the prompts of `~/Downloads/viking/dress/`. Cut them into `assets/pictures/dress/` (with their anchors in `dress.json`), and see how they sit on the poses of a recording (only the key points, no camera picture):

```
venv/bin/python dev/pictures/cut_dress.py [~/Downloads/viking/dress]
$GODOT --path . --script dev/pictures/preview_dress.gd -- <recording.jsonl> <out dir> <t> [<t> ...] [--reach] [--skeleton]
```

## The looks of the players

Each rower chooses a viking girl or boy and the colours of the skin, the hair and the clothes (`Looks`, `scenes/looks/looks.gd`; saved with the journey in `GameState.looks`).
The painted pictures of the rowers in the boat (`assets/pictures/rowboat/`: `ylva_*`, `sigrid_*`, `boy_*`, `boy_one_*`) and of the dress-up have each a mask (`<name>_mask.png`: red the skin, green the hair, blue the clothes, white what keeps its colour); `Recolor.cs` (`scenes/looks/core/Recoloring.cs`, tested in `tests/DrunkenVikings.Tests/RecoloringTests.cs`) recolours the masked areas keeping their shading, when a look first needs a picture, and `Looks` keeps it.
The boy and the masks were painted with ChatGPT from the prompts of `~/Downloads/viking-masks/` (see its README.md) onto sheets laid out like the game's pictures (made by the `make_*.py` there), and are cut, fitted to the pictures and placed (the boy's pieces with their anchors in `dress_boy/dress.json`) by:

```
venv/bin/python dev/pictures/cut_looks.py [~/Downloads/viking-masks]
```
