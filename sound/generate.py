#!/usr/bin/env python3
"""Regenerate every game sound with the ElevenLabs API (C3 Sound package).

Run from the repo root:  python3 sound/generate.py [--only key1,key2] [--force]

Auth: cloud sessions go through a proxy that injects the real key, so the header
below is a dummy. Locally, set ELEVENLABS_API_KEY instead.

Output: sound/sfx/*.mp3 (mono), sound/music/*.mp3, sound/voice/*.mp3 (mono).
Every file is normalized with ffmpeg (loudnorm) so volumes in Config/Sounds.luau
stay meaningful. Existing files are skipped unless --force is given.

Cow names are read from src/shared/Config/Cows.luau so voice lines always match the game.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sound")
API = "https://api.elevenlabs.io/v1"
KEY = os.environ.get("ELEVENLABS_API_KEY", "dummy")

BANNED = ["tung tung", "tralalero", "bombardiro", "ballerina cappuccina"]

# Expressive character voice ("Callum - Husky Trickster", a premade voice).
VOICE_ID = "N2lVS1w4EtoT3dr4eOWO"

# key -> (file, prompt, seconds, loop)
SFX = {
    "Moo1": ("sfx_moo_1", "A single short funny cartoon cow moo, close up, clean, no background", 1.5, False),
    "Moo2": ("sfx_moo_2", "A long dramatic low cow mooo, comedic, clean, no background noise", 2.0, False),
    "Moo3": ("sfx_moo_3", "A high pitched silly squeaky cow moo, cartoon, short, clean", 1.2, False),
    "MilkPipe": (
        "sfx_milk_pipe_loop",
        "Seamless loop of milk gently flowing and gurgling through a metal pipe, soft bubbling liquid",
        4.0,
        True,
    ),
    "CanFill": ("sfx_can_fill", "Milk pouring quickly into a metal milk can, rising pitch as it fills, short", 1.5, False),
    "DepositSplash": ("sfx_deposit_splash", "A big cartoon splash of milk poured into a vat, satisfying, short", 1.2, False),
    "CashCollect": (
        "sfx_cash_collect",
        "Cash register cha-ching with a shower of coins, bright, satisfying game reward sound",
        1.5,
        False,
    ),
    "Coin": ("sfx_coin", "A single bright tiny coin pickup blip, mobile game, very short", 0.5, False),
    "BuyCow": (
        "sfx_buy_cow",
        "Cheerful pop and sparkle purchase sound followed by a tiny happy moo, mobile game",
        1.2,
        False,
    ),
    "Merge": (
        "sfx_merge",
        "Magical whoosh and pop as three things fuse into one, rising chime, cartoon game merge sound",
        1.5,
        False,
    ),
    "CrateSpin": (
        "sfx_crate_spin",
        "Fast ticking roulette wheel spinning and slowing down, game loot box spin, clicks",
        2.5,
        False,
    ),
    "CrateReveal": (
        "sfx_crate_reveal",
        "Loot box opening reveal, wooden crate pop then triumphant sparkly chime, game reward",
        1.5,
        False,
    ),
    "RareSparkle": (
        "sfx_rare_sparkle",
        "Shimmering magical sparkle with glittering bells, rare item found, game sound",
        1.5,
        False,
    ),
    "Rebirth": (
        "sfx_rebirth",
        "Huge epic upward whoosh with a choir swell and a bright explosion of light, game level reset",
        3.0,
        False,
    ),
    "Upgrade": ("sfx_upgrade", "Short ascending power up arpeggio blip, cheerful mobile game upgrade", 1.0, False),
    "ErrorBuzz": ("sfx_error_buzz", "Short low cartoon error buzzer, two quick buzzes, game UI denied", 0.6, False),
    "UiClick": ("sfx_ui_click", "A very short soft bubbly UI button click pop", 0.5, False),
    "TruckHorn": (
        "sfx_truck_horn",
        "A goofy old delivery truck horn honking twice, la cucaracha style comedic horn",
        2.0,
        False,
    ),
    "EventFanfare": (
        "sfx_event_fanfare",
        "Short goofy Italian brass and accordion fanfare announcing a special event, energetic",
        3.0,
        False,
    ),
    "NewCowFanfare": (
        "sfx_newcow_fanfare",
        "Short triumphant orchestral hit with sparkles, new character unlocked, game jingle",
        2.0,
        False,
    ),
}

MUSIC = {
    "MusicFarm": (
        "music_farm_loop",
        "Goofy upbeat Italian brainrot farm tune, mandolin and accordion lead, bouncy tuba bass, "
        "pizzicato strings, playful comedic mood, 120 bpm, instrumental, loopable video game background music",
        90000,
    ),
    "MusicCalm": (
        "music_farm_calm",
        "Calm relaxed Italian countryside farm music, gentle mandolin and soft accordion, light acoustic "
        "guitar, warm and cozy, 85 bpm, instrumental, loopable video game background music",
        90000,
    ),
}

VOICE_STYLES = ["[shouting]", "[dramatically]", "[excited]"]


def cow_names():
    src = open(os.path.join(ROOT, "src/shared/Config/Cows.luau"), encoding="utf-8").read()
    # each row starts with: {\n\t\t"id",\n\t\t"Name",
    names = re.findall(r'\{\s*\n\s*"([a-z]+)",\s*\n\s*"([^"]+)",', src)
    assert len(names) == 18, f"expected 18 cows, got {len(names)}"
    for _, name in names:
        assert not any(b in name.lower() for b in BANNED), f"banned name: {name}"
    return [n for _, n in names]


def post(path, body, out_path):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode(),
        headers={"xi-api-key": KEY, "content-type": "application/json", "accept": "audio/mpeg"},
        method="POST",
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                data = r.read()
            with open(out_path, "wb") as f:
                f.write(data)
            return
        except Exception as e:  # noqa: BLE001
            print(f"  retry {attempt + 1}: {e}", file=sys.stderr)
            time.sleep(2 ** (attempt + 1))
    raise RuntimeError(f"failed: {path}")


def finish(raw, dst, mono, bitrate):
    # loudness normalize, optional mono, re-encode small
    args = ["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]
    if mono:
        args += ["-ac", "1"]
    args += ["-ar", "44100", "-b:a", bitrate, dst]
    subprocess.run(args, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))

    for sub in ("sfx", "music", "voice"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    tmp = tempfile.mkdtemp()

    def want(key, dst):
        if only and key not in only:
            return False
        return a.force or not os.path.exists(dst)

    for key, (fname, prompt, secs, loop) in SFX.items():
        dst = os.path.join(OUT, "sfx", fname + ".mp3")
        if not want(key, dst):
            continue
        print("sfx", key)
        raw = os.path.join(tmp, fname + ".mp3")
        body = {"text": prompt, "duration_seconds": secs, "prompt_influence": 0.6}
        if loop:
            body["loop"] = True
            body["model_id"] = "eleven_text_to_sound_v2"
        post("/sound-generation?output_format=mp3_44100_128", body, raw)
        finish(raw, dst, mono=True, bitrate="64k")

    for key, (fname, prompt, ms) in MUSIC.items():
        dst = os.path.join(OUT, "music", fname + ".mp3")
        if not want(key, dst):
            continue
        print("music", key)
        raw = os.path.join(tmp, fname + ".mp3")
        body = {"prompt": prompt, "music_length_ms": ms, "force_instrumental": True}
        post("/music?output_format=mp3_44100_128", body, raw)
        finish(raw, dst, mono=False, bitrate="96k")

    for i, name in enumerate(cow_names(), start=1):
        key = f"Voice{i}"
        dst = os.path.join(OUT, "voice", f"voice_tier_{i:02d}.mp3")
        if not want(key, dst):
            continue
        print("voice", key, name)
        raw = os.path.join(tmp, f"voice_{i}.mp3")
        style = VOICE_STYLES[i % len(VOICE_STYLES)]
        body = {
            "text": f"{style} {name}!!",
            "model_id": "eleven_v3",
            "language_code": "it",
            "voice_settings": {"stability": 0.0, "similarity_boost": 0.8},
        }
        post(f"/text-to-speech/{VOICE_ID}?output_format=mp3_44100_128", body, raw)
        finish(raw, dst, mono=True, bitrate="64k")

    print("done")


if __name__ == "__main__":
    main()
