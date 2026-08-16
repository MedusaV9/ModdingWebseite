# Gooby audio pipeline (5.x audio polish wave)

All Gooby sounds are fully synthetic (numpy DSP -> WAV -> ffmpeg/libvorbis ->
`.ogg`); no third-party samples are used anywhere. The single source of truth
is `scripts/gen_sounds.py` — never edit files in
`assets/goobymod/sounds/entity/gooby/` by hand.

## Regenerating & verifying

```bash
python3 scripts/gen_sounds.py               # synthesise all clips + verify
python3 scripts/gen_sounds.py --verify      # verify only (no synthesis)
python3 scripts/gen_sounds.py --prune       # delete unmanaged .ogg files
python3 scripts/gen_sounds.py --metrics m.json   # dump metrics as JSON
python3 scripts/gen_sounds.py --update-manifest  # regen + bless the manifest
```

Requires `numpy` and `ffmpeg` on `PATH` (missing ffmpeg aborts with a clear
error message, not a traceback).

## Determinism & the committed hash manifest

Output is byte-for-byte reproducible on the same ffmpeg/libvorbis build:

- every clip uses a fixed `np.random.default_rng(seed)`,
- ffmpeg runs with `-map_metadata -1 -fflags +bitexact -flags:a +bitexact`,
  which strips version tags and fixes the Ogg stream serial number.

Running the generator twice must produce identical SHA-256 hashes for all
91 clips.

**`docs/audio_manifest.json`** is the committed reference: it pins the
SHA-256 (plus size and duration) of every clip and records the toolchain
that produced them (reference build: **ffmpeg 6.1.1 / libvorbis, numpy 2.x,
Python 3.12** — see the `toolchain` block in the manifest for the exact
versions). `verify()` compares the on-disk files against the manifest
**fail-closed**: any mismatch (accidental re-encode, toolchain drift,
hand-edited file) is a hard error. The toolchain block is documentation
only — verification compares hashes, never versions.

After a *deliberate* recipe or toolchain change, run

```bash
python3 scripts/gen_sounds.py --update-manifest
```

(regenerates, rewrites the manifest, then verifies) and commit the manifest
together with the changed `.ogg` files as one reviewable asset change. Use
`--verify --update-manifest` to bless the existing files without
regenerating.

## Variant policy

Emotionally frequent event families ship **at least 3 clearly distinct
variants**. Variants differ in envelope shape, harmonic content and
micro-timing (sub-event counts, gaps, flutter rates) — never in pitch alone.

| Category | Families | Variants |
|---|---|---:|
| Frequent (>= 3) | squeak, purr, boing, plop, munch, snore, sniff, sad_whimper, yawn, ambient_neutral, ambient_happy, ambient_sleepy, brush, whine_hungry, lonely_sigh, shake, tier_up_jingle, trick_chime, flop_thud, hutch_rustle, hutch_creak, baby_squeak, nuzzle, dress_up, wild_call, chirp_social, sniff_long, map_rustle | 3 each |
| Deliberately single | purr_loop (must loop seamlessly — mathematically periodic over 2.0 s), whistle_wander / whistle_follow / whistle_stay (players learn the three modes by ear), snuggle_purr_long (one canonical signature take) | 1 each |
| Locked size | alarm_squeak — `GoobyGameTests.awareness_assets_complete` asserts exactly 2 pool entries | 2 |

Total: 34 families, 91 clips, ~700 KiB.

`entity.gooby.ambient` aliases the `ambient_neutral` clip pool. The mod
itself always voices ambience through the mood pools, but the generic event
stays registered as a **stable addon-facing fallback** — see
`docs/ADDON_API.md` ("Stable sound events"). `entity.gooby.whistle_denied`
reuses the squeak pool at a deliberate deep pitch of 0.65 (all three squeak
variants).

## sounds.json conventions

Multi-variant pools use weighted entries with gentle static pitch/volume
jitter so each random pick sounds slightly different:

- primary variant: `weight: 3`, no pitch/volume keys (defaults),
- alternates: `weight: 2`, pitch within **[0.94, 1.06]**, volume within
  **[0.90, 1.00]** — these pool bounds are defined in BOTH validators
  (`gen_sounds.py` `POOL_PITCH_*`/`POOL_VOLUME_*` and
  `GoobyAudioExpansionTests` constants); always change the two together
  with this document, never one alone,
- melodic stings (`tier_up_jingle`, `trick_chime`) jitter **volume only** so
  the motif never sounds detuned,
- every `wild_call` variant keeps `attenuation_distance: 32` (players locate
  wild Goobys by ear),
- subtitle keys are stable — localisation lives in `lang/{en_us,de_de}.json`.

## Loudness & container bounds

The generator peak-normalises each clip to a per-family target (0.22–0.50
full scale, quiet foley low, alerts high) and `verify()` re-decodes every
encoded file to enforce:

- mono, 44 100 Hz, healthy Ogg pages + Vorbis ID header,
- decoded peak in [0.10, 0.92] (headroom, no clipping possible),
- RMS in [0.010, 0.36]; active RMS spread within a family <= 2.6x,
- duration in [0.14, 5.0] s, file size in [2, 150] KB,
- variants never byte-identical,
- `sounds.json` <-> on-disk files <-> generator recipes fully bidirectional
  (no dangling references, no orphan files).

The server-side resource gates live in
`gametest/GoobyAudioExpansionTests.java`: registry <-> `sounds.json` sync,
variant cardinalities, Ogg header/duration/size checks (stdlib Ogg parsing —
peak/RMS need a decoder and are covered by the Python verifier instead),
byte-uniqueness, weight/jitter bounds and whistle distinctness.

Sound *playback* pacing is unchanged: `GoobySoundLimiter` semantics are
untouched by the audio wave and stay covered by the existing game tests.

## CI

GoobyMod is a subproject of the surrounding repository, so the nested
workflows under `GoobyMod/.github/workflows/` are **not** executed by
GitHub. The effective CI gate is the root workflow
`.github/workflows/gooby-mod.yml`: on every push/PR touching `GoobyMod/**`
it installs ffmpeg + numpy and runs `gen_sounds.py --verify` (manifest,
container and loudness checks), the asset/worldgen validators, the Python
tests, the release gate, the Gradle build and the GameTests — all
fail-closed. The built jar is uploaded as a workflow artifact and never
committed back into the repository.
