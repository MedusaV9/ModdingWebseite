#!/usr/bin/env python3
"""Treblo (Sonauto) V3 song generation for Eclipse Event.

Reads the API key from the TREBLO_API_KEY environment variable — the key is NEVER
written to disk or logged. Each track is hand-designed: prompt, tags, negative_tags,
length_range and exactly ONE of prompt_strength / style_scale > 1.0 (V3 contract).

Usage:
  TREBLO_API_KEY=... python3 tools/music/treblo_generate.py [--only id,id] [--out DIR]

Raw downloads land in --out (default /tmp/treblo_out); post-processing to
Minecraft-ready OGG Vorbis happens in postprocess() (loudnorm + size budget).
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

API = "https://api.treblo.com/v1"

# Track catalog. Every entry: elaborate prompt, >=3 tags, negative tags, length range
# (multiples of 30), and exactly one of style_scale/prompt_strength > 1.0.
TRACKS = [
    {
        "id": "title_theme",
        "prompt": (
            "A slow, mystic dark-fantasy title theme. Deep sustained drone in D minor, "
            "distant airy choir pads, soft glass bells and a lone cold piano motif that "
            "returns like a memory. Gentle build to a quiet awe-filled swell, then settles "
            "back so the piece loops seamlessly. Purple twilight, an eclipsed sun over a "
            "lonely ocean. Cinematic, restrained, beautiful and slightly unsettling."
        ),
        "tags": ["dark ambient", "cinematic", "orchestral", "mysterious", "fantasy"],
        "negative_tags": ["edm", "pop", "vocals", "drums"],
        "length_range": [120, 180],
        "style_scale": 6.0,
        "instrumental": True,
    },
    {
        "id": "limbo_ambience",
        "prompt": (
            "Ghost-ship purgatory ambience. Endless black ocean at dusk: slow tidal drones, "
            "creaking wood textures, sparse deep bell tolls like a drowned lighthouse, "
            "whale-like distant horn swells, cold shimmering high pad like fog lights. "
            "Almost no rhythm, weightless and mournful, loopable without a clear start."
        ),
        "tags": ["dark ambient", "drone", "atmospheric", "eerie", "soundscape"],
        "negative_tags": ["beat", "edm", "vocals", "guitar"],
        "length_range": [180, 240],
        "style_scale": 5.5,
        "instrumental": True,
    },
    {
        "id": "boss_herald",
        "prompt": (
            "Menacing mid-game boss fight. Driving low-string ostinato at a march-like pulse, "
            "ritualistic taiko and tom hits, muted brass stabs, a hostile whispering choir "
            "that answers the strings, occasional dissonant bell. Builds pressure in waves, "
            "never fully releasing — an eclipse cult herald judging the players. Loopable."
        ),
        "tags": ["epic", "dark orchestral", "boss battle", "percussion", "choir"],
        "negative_tags": ["happy", "pop", "synthwave"],
        "length_range": [120, 180],
        "prompt_strength": 1.8,
        "instrumental": True,
    },
    {
        "id": "boss_ferryman",
        "prompt": (
            "Final boss of a sea purgatory: tragic, huge, orchestral. Full choir in Latin-like "
            "syllables, storm strings, colossal drums, a funeral organ under everything, "
            "and a heartbreaking solo violin theme that surfaces twice. Storm waves and "
            "ship bells inside the orchestration. Climactic, operatic, grief and fury, "
            "ending on an unresolved suspended chord so it loops."
        ),
        "tags": ["epic orchestral", "choir", "boss battle", "tragic", "cinematic"],
        "negative_tags": ["edm", "pop", "lofi"],
        "length_range": [180, 240],
        "style_scale": 7.0,
        "instrumental": True,
    },
    {
        "id": "expansion_theme",
        "prompt": (
            "The world is growing: a magical build-up cue. Rising harp and celesta arpeggios, "
            "shimmering string tremolo, airy choir swells, deep sub pulses like tectonic "
            "movement, chimes cascading upward. Constantly ascending feeling of awe and "
            "revelation, blooming into a bright sustained final chord."
        ),
        "tags": ["cinematic", "magical", "orchestral", "build-up", "wonder"],
        "negative_tags": ["dark", "horror", "vocals"],
        "length_range": [60, 120],
        "style_scale": 6.0,
        "instrumental": True,
    },
    {
        "id": "intro_storm",
        "prompt": (
            "A ship goes down in a supernatural storm. Furious string runs, brutal timpani "
            "and low brass swells, dissonant cluster stabs like lightning, creaking wood and "
            "choir gasps, a huge wave-crash climax followed by sudden eerie stillness with "
            "one deep bell. Terrifying, cinematic, fast."
        ),
        "tags": ["cinematic", "orchestral", "storm", "dramatic", "intense"],
        "negative_tags": ["edm", "happy", "lofi"],
        "length_range": [90, 150],
        "prompt_strength": 2.0,
        "instrumental": True,
    },
    {
        "id": "victory_theme",
        "prompt": (
            "Dawn after the eclipse: relief and grief at once. Warm slow strings rising out of "
            "a dark low drone, a simple hopeful piano melody, soft horns joining, gentle "
            "choir halo, ending in warm consonant light. Tears-in-the-eyes victory, not "
            "triumphant fanfare — survivors watching the sun return."
        ),
        "tags": ["emotional", "orchestral", "hopeful", "cinematic", "uplifting"],
        "negative_tags": ["dark", "horror", "edm"],
        "length_range": [120, 180],
        "style_scale": 5.0,
        "instrumental": True,
    },
    {
        "id": "xbox_nostalgia",
        "prompt": (
            "Nostalgic sandbox childhood: minimal dreamy piano over soft warm synth pads, "
            "slow and naive melody with lots of air and silence between phrases, subtle tape "
            "wow, distant music-box sparkle. Bittersweet memory of endless summer afternoons "
            "building worlds. Calm, simple, loopable."
        ),
        "tags": ["ambient", "piano", "nostalgic", "minimal", "calm"],
        "negative_tags": ["drums", "epic", "vocals"],
        "length_range": [120, 210],
        "style_scale": 5.0,
        "instrumental": True,
    },
    {
        "id": "eclipse_totality",
        "prompt": (
            "Totality: the sun is swallowed. Massive slow sub-bass drone, metallic shimmer "
            "like a corona, reversed choir breaths, deep pulsing heartbeat every few bars, "
            "high glassy whistle of cosmic wind. Oppressive, holy dread, almost static — "
            "the sound of standing under a black sun. Loopable."
        ),
        "tags": ["dark ambient", "drone", "cosmic", "cinematic", "tension"],
        "negative_tags": ["melody", "pop", "beat"],
        "length_range": [120, 180],
        "style_scale": 6.5,
        "instrumental": True,
    },
    {
        "id": "fog_storm",
        "prompt": (
            "Inside a hunting fog storm: claustrophobic tension loop. Muffled rain layer, low "
            "cello pulse like a slow heartbeat, distant rolling thunder, skittering metallic "
            "insect percussion, occasional dissonant string slide — something circles you in "
            "the mist. Sparse, paranoid, loopable."
        ),
        "tags": ["tension", "dark ambient", "horror", "percussion", "atmospheric"],
        "negative_tags": ["happy", "edm", "vocals"],
        "length_range": [120, 180],
        "prompt_strength": 1.6,
        "instrumental": True,
    },
    {
        "id": "boss_rift_warden",
        "prompt": (
            "Void dungeon mini-boss: dark hybrid orchestral with glitch electronics. Grinding "
            "low strings, granular stutter hits synced with heavy drums, hollow metallic "
            "resonance, short silences torn open by riff stabs — a knight made of a broken "
            "dimension. Aggressive but controlled, loopable."
        ),
        "tags": ["hybrid orchestral", "boss battle", "glitch", "dark", "electronic"],
        "negative_tags": ["happy", "pop", "acoustic"],
        "length_range": [120, 180],
        "style_scale": 6.0,
        "instrumental": True,
    },
    {
        "id": "boss_fog_tyrant",
        "prompt": (
            "The storm monarch: regal apocalyptic boss theme. Dark royal brass fanfare "
            "fragments, colossal thunder-drum ensemble, choir surging like gale fronts, "
            "electric crackle textures, a grim waltz-like undercurrent — a crowned tyrant "
            "conducting the tempest. Majestic, violent, loopable."
        ),
        "tags": ["epic orchestral", "boss battle", "choir", "dark", "percussion"],
        "negative_tags": ["lofi", "pop", "synthwave"],
        "length_range": [150, 210],
        "style_scale": 7.0,
        "instrumental": True,
    },
    {
        "id": "kill_contract",
        "prompt": (
            "Assassination hour: stealth tension for a hunt among friends. Dry ticking-clock "
            "percussion, muted heartbeat kick, cold staccato strings, breathing pads, tiny "
            "dissonant piano notes like glances over the shoulder. Minimal, paranoid, "
            "constantly on edge without exploding. Loopable."
        ),
        "tags": ["tension", "thriller", "minimal", "percussion", "suspense"],
        "negative_tags": ["epic", "happy", "vocals"],
        "length_range": [90, 150],
        "prompt_strength": 1.7,
        "instrumental": True,
    },
    {
        "id": "wand_awakening",
        "prompt": (
            "A magic catalyst awakens: short ceremonial sting. Harp glissando bloom, choir "
            "swell from a whisper to radiant, crystal chimes spiraling upward, one deep "
            "gong at the peak, then sparkling decay to silence. Pure wonder, 45 to 60 "
            "seconds, a moment of attunement."
        ),
        "tags": ["magical", "cinematic", "orchestral", "sting", "wonder"],
        "negative_tags": ["dark", "drums", "edm"],
        "length_range": [30, 90],
        "style_scale": 6.0,
        "instrumental": True,
    },
    {
        "id": "day_final",
        "prompt": (
            "The last day: inevitability ambience. Slow funeral bell every few bars, "
            "sustained low strings breathing under a cold high violin line, faint distant "
            "choir like a memorial, ground rumble swells. Heavy, patient, dignified dread — "
            "time is almost gone. Loopable."
        ),
        "tags": ["dark ambient", "orchestral", "melancholic", "cinematic", "tension"],
        "negative_tags": ["edm", "happy", "beat"],
        "length_range": [120, 180],
        "style_scale": 6.5,
        "instrumental": True,
    },
]


def api(path, key, payload=None):
    req = urllib.request.Request(
        f"{API}/{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST" if payload is not None else "GET",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def submit_with_backoff(key, payload):
    """Sequential submits still hit burst limits (403/429) — retry with backoff."""
    for attempt in range(5):
        try:
            return api("generations/v3", key, payload)
        except urllib.error.HTTPError as err:
            if err.code in (403, 429) and attempt < 4:
                wait = 15 * (attempt + 1)
                print(f"  rate-limited ({err.code}); retrying in {wait}s", flush=True)
                time.sleep(wait)
                continue
            raise
    return {}


def generate_one(track, key, out_dir, task_id=None):
    tid = track["id"]
    if task_id is None:
        payload = {k: v for k, v in track.items() if k != "id"}
        payload["output_format"] = "ogg"
        start = submit_with_backoff(key, payload)
        task_id = start.get("task_id")
    if not task_id:
        return tid, "FAILED to start"
    for _ in range(240):  # up to 40 min
        time.sleep(10)
        status = api(f"generations/status/{task_id}", key)
        state = status.get("status")
        if state == "SUCCESS":
            break
        if state == "FAILURE":
            detail = api(f"generations/{task_id}", key)
            return tid, f"FAILURE: {detail.get('error_message', 'unknown')}"
    else:
        return tid, "TIMEOUT"
    result = api(f"generations/{task_id}", key)
    url = result["song_paths"][0]
    raw = out_dir / f"{tid}_raw.ogg"
    with urllib.request.urlopen(url, timeout=120) as resp, open(raw, "wb") as out:
        out.write(resp.read())
    return tid, f"OK {raw.stat().st_size:,} bytes (task {task_id})"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--out", default="/tmp/treblo_out")
    args = parser.parse_args()
    key = os.environ.get("TREBLO_API_KEY", "")
    if not key:
        print("TREBLO_API_KEY not set", file=sys.stderr)
        return 1
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    wanted = [t for t in TRACKS if not args.only or t["id"] in args.only.split(",")]
    print(f"Generating {len(wanted)} tracks -> {out_dir}")
    results = {}
    # Stagger submissions (burst 403s observed), then poll concurrently.
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {}
        for track in wanted:
            futures[pool.submit(generate_one, track, key, out_dir)] = track["id"]
            time.sleep(20)
        for future in as_completed(futures):
            tid, msg = future.result()
            results[tid] = msg
            print(f"[{tid}] {msg}", flush=True)
    failed = [t for t, m in results.items() if not m.startswith("OK")]
    print(f"\nDone. {len(results) - len(failed)} ok, {len(failed)} failed: {failed}")
    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
