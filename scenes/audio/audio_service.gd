extends Node

## The music and the sounds of the game (the autoload AudioService, which
## the game reaches through Audio), made by
## dev/audio/make_audio.py into assets/audio/ (see THIRD_PARTY_NOTICES.md).
##
## * The music plays by mood (see [method music]): the tunes of the mood one
##   after the other, shuffled, fading over into each other, and into the
##   tunes of the next mood.
## * The sounds (see [method play]) play over the music, each a little higher
##   or lower than the last, so that a sound heard often never sounds the same.
## * One sound of the surroundings loops under it all (see [method ambient]),
##   e.g., the water lapping at the boat.
##
## Start with [code]-- --mute[/code] for silence.

## The tunes of each mood: assets/audio/music/<mood>_<n>.ogg, n from 1.
const MOODS := {"start": 2, "farm": 2, "lakes": 7, "party": 3, "chase": 2}

## How loud the music plays, in dB, and how long it fades, in seconds.
const MUSIC_DB := -12.0
const FADE := 1.5

## How loud each sound plays, in dB (0 by default): the sounds are made to the
## same peak, the game evens them out here.
const LEVELS := {
    "click": -8.0,
    "oar_1": -10.0,
    "oar_2": -8.0,
    "creak": -8.0,
    "dock": -6.0,
    "coins": -4.0,
    "coin": -6.0,
    "pickup": -4.0,
    "horn": -6.0,
    "bell": -6.0,
    "hens": -10.0,
    "sheep": -8.0,
    "goat": -10.0,
    "cow": -10.0,
    "bees": -12.0,
    "market": -12.0,
    "gulls": -16.0,
    "water": -20.0,
}

## The sounds which come in several takes: name -> how many
## (<name>_1.ogg, <name>_2.ogg, ...), one of them at random each time.
const TAKES := {"oar": 2}

## How many sounds play at once, at most.
const VOICES := 10

## The sounds played so far, by name: how often (for the tests).
var played := {}

## The mood of the music now, or "".
var mood := ""

## The sound of the surroundings now, or "".
var surroundings := ""

var _muted := false
var _players: Array[AudioStreamPlayer] = []
var _current := 0
var _tunes: Array[String] = []
var _next := 0
var _voices: Array[AudioStreamPlayer] = []
var _ambient: AudioStreamPlayer
var _streams := {}
var _tweens := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _muted = "--mute" in OS.get_cmdline_user_args()
    for i in range(2):
        var player := AudioStreamPlayer.new()
        player.finished.connect(_on_finished.bind(i))
        add_child(player)
        _players.append(player)
    for i in range(VOICES):
        var voice := AudioStreamPlayer.new()
        add_child(voice)
        _voices.append(voice)
    _ambient = AudioStreamPlayer.new()
    add_child(_ambient)


## Play the music of the [param new_mood] (see [constant MOODS]); "" fades
## the music out. The same mood goes on as it is.
func music(new_mood: String) -> void:
    if new_mood == mood:
        return
    mood = new_mood
    _tunes.clear()
    for i in range(int(MOODS.get(mood, 0))):
        _tunes.append("res://assets/audio/music/%s_%d.ogg" % [mood, i + 1])
    if mood != "" and _tunes.is_empty():
        push_error("There is no music of the mood %s." % mood)
    # NOTE: Shuffled, but never the same tune twice in a row.
    for i in range(_tunes.size() - 1, 0, -1):
        var j := _rng.randi_range(0, i)
        var swap := _tunes[i]
        _tunes[i] = _tunes[j]
        _tunes[j] = swap
    _next = 0
    _play_next()


## Play the sound of the [param name] (assets/audio/sounds/<name>.ogg), [param
## db] louder than usual (see [constant LEVELS]).
func play(name: String, db := 0.0) -> void:
    played[name] = int(played.get(name, 0)) + 1
    if TAKES.has(name):
        name = "%s_%d" % [name, _rng.randi_range(1, int(TAKES[name]))]
    var stream := _stream("res://assets/audio/sounds/%s.ogg" % name)
    if stream == null or _muted:
        return
    var voice: AudioStreamPlayer = null
    for candidate in _voices:
        if not candidate.playing:
            voice = candidate
            break
    if voice == null:
        # NOTE: All voices busy: the oldest makes room.
        voice = _voices.pop_front()
        _voices.append(voice)
    voice.stream = stream
    voice.volume_db = float(LEVELS.get(name, 0.0)) + db
    voice.pitch_scale = _rng.randf_range(0.94, 1.06)
    voice.play()


## Loop the sound of the [param name] under everything; "" stops it.
func ambient(name: String) -> void:
    if name == surroundings:
        return
    surroundings = name
    if name == "":
        _fade(_ambient, -60.0, true)
        return
    var stream := _stream("res://assets/audio/sounds/%s.ogg" % name)
    if stream == null or _muted:
        return
    var looped := stream.duplicate() as AudioStreamOggVorbis
    if looped != null:
        looped.loop = true
    _ambient.stream = looped if looped != null else stream
    _ambient.volume_db = -60.0
    _ambient.play()
    _fade(_ambient, float(LEVELS.get(name, 0.0)), false)


## Stop the music and every sound, and let go of them.
func silence() -> void:
    mood = ""
    surroundings = ""
    for player in _players + _voices + [_ambient]:
        player.stop()
        player.stream = null
    _streams.clear()


func _exit_tree() -> void:
    silence()


func _play_next() -> void:
    var old := _players[_current]
    if old.playing:
        _fade(old, -60.0, true)
    if _tunes.is_empty() or _muted:
        return
    var stream := _stream(_tunes[_next % _tunes.size()])
    _next += 1
    if stream == null:
        return
    _current = 1 - _current
    var player := _players[_current]
    player.stream = stream
    player.volume_db = -40.0
    player.play()
    _fade(player, MUSIC_DB, false)


func _on_finished(index: int) -> void:
    if index == _current:
        _play_next()


func _fade(player: AudioStreamPlayer, db: float, then_stop: bool) -> void:
    # NOTE: A new fade replaces the last one of the player, so that a fade out
    # never stops what plays on the player since.
    var last: Tween = _tweens.get(player.get_instance_id())
    if last != null and last.is_valid():
        last.kill()
    var tween := create_tween()
    _tweens[player.get_instance_id()] = tween
    tween.tween_property(player, "volume_db", db, FADE)
    if then_stop:
        tween.tween_callback(player.stop)


func _stream(path: String) -> AudioStream:
    if not _streams.has(path):
        if not ResourceLoader.exists(path):
            push_error("There is no sound %s." % path)
            _streams[path] = null
        else:
            _streams[path] = load(path)
    return _streams[path]
