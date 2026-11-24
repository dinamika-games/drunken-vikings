"""
Make the music and the sound effects of the game from the downloaded sources
(see ~/Downloads/viking/AUDIO_SOURCES.md and THIRD_PARTY_NOTICES.md):

* the music: render each MIDI file with TiMidity++ and the FluidR3 General
  MIDI SoundFont into Ogg Vorbis, at an even loudness, into
  assets/audio/music/<mood>_<n>.ogg (see scenes/audio/audio.gd for the moods);
* the sounds: cut the part of each recording which the game needs, fade its
  ends, and bring it to an even peak, into assets/audio/sounds/<name>.ogg.

    venv/bin/python dev/audio/make_audio.py [--source ~/Downloads/viking]

Needs timidity, the SoundFont /usr/share/sounds/sf2/FluidR3_GM.sf2, ffmpeg and sox.
"""

import argparse
import pathlib
import shutil
import subprocess
import sys
from typing import List, Optional

import pydantic

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = REPO_ROOT / "assets" / "audio"
SOUNDFONT = pathlib.Path("/usr/share/sounds/sf2/FluidR3_GM.sf2")

#: The loudness of the music, in LUFS, and the peak of the sounds, in dB
#: (the game sets how loud each sound plays, see scenes/audio/audio.gd).
MUSIC_LOUDNESS = -20.0
SOUND_PEAK = -3.0


class Tune(pydantic.BaseModel):
    """A tune of the music: its MIDI file and the name in the game."""

    model_config = pydantic.ConfigDict(frozen=True)

    midi: str
    name: str


class Sound(pydantic.BaseModel):
    """A sound effect: the part of a recording, and how it fades."""

    model_config = pydantic.ConfigDict(frozen=True)

    source: str
    name: str
    start: float = 0.0
    duration: Optional[float] = None
    fade_in: float = 0.0
    fade_out: float = 0.05


TUNES: List[Tune] = [
    Tune(midi="01_start_varvindar_friska.mid", name="start_1"),
    Tune(midi="16_evening_den_lyse_dag.mid", name="start_2"),
    Tune(midi="02_farm_krummi_svaf_i_klettagja.mid", name="farm_1"),
    Tune(midi="03_farm_kristallen_den_fina.mid", name="farm_2"),
    Tune(midi="04_lakes_drunken_sailor.mid", name="lakes_1"),
    Tune(midi="05_lakes_rolling_down_to_old_maui.mid", name="lakes_2"),
    Tune(midi="06_lakes_hamborger_veermaster.mid", name="lakes_3"),
    Tune(midi="07_nordic_stale_storli.mid", name="lakes_4"),
    Tune(midi="08_nordic_draumkvedet.mid", name="lakes_5"),
    Tune(midi="09_nordic_asmund_fraegdegjeva.mid", name="lakes_6"),
    Tune(midi="13_jig_muirsheen_durkin.mid", name="lakes_7"),
    Tune(midi="10_party_hargalaten.mid", name="party_1"),
    Tune(midi="11_party_sma_grodorna.mid", name="party_2"),
    Tune(midi="12_party_girl_i_left_behind.mid", name="party_3"),
    Tune(midi="14_chase_kaapren_varen.mid", name="chase_1"),
    Tune(midi="15_chase_ej_uchnem_volga_boatmen.mid", name="chase_2"),
]

SOUNDS: List[Sound] = [
    Sound(source="ui_click_wood.ogg", name="click"),
    Sound(source="oar_splash_2.ogg", name="oar_1"),
    Sound(source="small_splash_3.ogg", name="oar_2"),
    Sound(source="wood_creak_short.ogg", name="creak"),
    Sound(source="rope_creak_2.ogg", name="dock", duration=2.0, fade_out=0.4),
    Sound(source="coins_handle.ogg", name="coins"),
    Sound(source="coin_clink.ogg", name="coin"),
    Sound(source="small_splash_pickup_1.ogg", name="pickup"),
    Sound(source="success_hooray_voices.ogg", name="hooray"),
    Sound(source="success_jingle_2.ogg", name="jingle"),
    Sound(source="fail_sting.ogg", name="fail"),
    Sound(source="pirate_arr_1.ogg", name="pirates"),
    Sound(source="pirate_arr_2.ogg", name="pirates_laugh"),
    Sound(source="viking_horn_1.ogg", name="horn", duration=3.5, fade_out=0.8),
    Sound(source="bell_1.ogg", name="bell"),
    Sound(source="rooster_1.ogg", name="rooster"),
    Sound(source="hens_2.ogg", name="hens", duration=3.0, fade_out=0.5),
    Sound(source="sheep_1.ogg", name="sheep"),
    Sound(source="goat_2.ogg", name="goat", duration=2.5, fade_out=0.4),
    Sound(source="cow_1.ogg", name="cow", duration=3.0, fade_out=0.5),
    Sound(source="bees_1.ogg", name="bees", duration=4.0, fade_in=0.3, fade_out=0.8),
    Sound(source="market_crowd.ogg", name="market", duration=5.0, fade_in=0.5, fade_out=1.0),
    Sound(source="seagulls_1.ogg", name="gulls", fade_out=0.3),
    Sound(source="water_lapping_loop_1.ogg", name="water", duration=24.0, fade_in=1.0, fade_out=1.0),
]


def ffmpeg(arguments: List[str]) -> None:
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error"] + arguments, check=True)


def make_music(source: pathlib.Path, work: pathlib.Path) -> None:
    (OUT / "music").mkdir(parents=True, exist_ok=True)
    for tune in TUNES:
        wav = work / f"{tune.name}.wav"
        subprocess.run(
            [
                "timidity",
                "-x",
                f"soundfont {SOUNDFONT}",
                "-Ow",
                "-s",
                "44100",
                "-o",
                str(wav),
                str(source / "music" / tune.midi),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        target = OUT / "music" / f"{tune.name}.ogg"
        ffmpeg(
            [
                "-i",
                str(wav),
                "-af",
                f"silenceremove=stop_periods=-1:stop_duration=1.5:stop_threshold=-60dB,"
                f"loudnorm=I={MUSIC_LOUDNESS}:TP=-1.5",
                "-ar",
                "44100",
                "-c:a",
                "libvorbis",
                "-q:a",
                "4",
                str(target),
            ]
        )
        print(f"  {target.relative_to(REPO_ROOT)} <- {tune.midi}")


def make_sounds(source: pathlib.Path, work: pathlib.Path) -> None:
    (OUT / "sounds").mkdir(parents=True, exist_ok=True)
    for sound in SOUNDS:
        arguments = ["-ss", str(sound.start)]
        if sound.duration is not None:
            arguments += ["-t", str(sound.duration)]
        arguments += ["-i", str(source / "sounds" / sound.source)]
        filters = ["anull"]
        if sound.fade_in > 0.0:
            filters.append(f"afade=t=in:d={sound.fade_in}")
        if sound.duration is not None and sound.fade_out > 0.0:
            filters.append(f"afade=t=out:st={sound.duration - sound.fade_out}:d={sound.fade_out}")
        wav = work / f"{sound.name}.wav"
        ffmpeg(arguments + ["-af", ",".join(filters), "-ar", "44100", str(wav)])
        # NOTE (mristin):
        # The loudness filter of ffmpeg needs some 3 s; the short sounds are
        # brought to their peak instead.
        target = OUT / "sounds" / f"{sound.name}.ogg"
        subprocess.run(["sox", str(wav), "-C", "5", str(target), "gain", "-n", str(SOUND_PEAK)], check=True)
        print(f"  {target.relative_to(REPO_ROOT)} <- {sound.source}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--source", default=str(pathlib.Path.home() / "Downloads" / "viking"))
    args = parser.parse_args()
    source = pathlib.Path(args.source).expanduser()
    # NOTE (mristin):
    # The ffmpeg of the snap reads and writes only in the home directory.
    work = source / "_render"
    work.mkdir(parents=True, exist_ok=True)
    try:
        print("The music:")
        make_music(source, work)
        print("The sounds:")
        make_sounds(source, work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
