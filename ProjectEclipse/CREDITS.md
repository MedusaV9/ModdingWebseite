# Eclipse Event Credits

## Musik — Treblo-generierte Tracks (2026-07-24)

Alle 15 Musik-Cues wurden mit **Treblo (Sonauto V3)** über die offizielle API generiert
(Custom-Prompt-Design, style_scale/prompt_strength-Tuning, instrumental):
`title_theme`, `limbo_ambience`, `boss_herald`, `boss_ferryman`, `boss_rift_warden`,
`boss_fog_tyrant`, `intro_storm`, `expansion_theme`, `eclipse_totality`, `fog_storm`,
`kill_contract`, `wand_awakening`, `day_final`, `victory_theme`, `xbox_nostalgia`.
Nachbearbeitung (`tools/music/treblo_generate.py` `postprocess()`):
Loudness-Normalisierung auf −16 LUFS (Two-Pass loudnorm), Re-Encode als
OGG Vorbis 48 kHz stereo (~q4/128 kbps, Step-down bei >2,5 MB), Nicht-Audio-Streams
entfernt. Die früher als Platzhalter genutzten Kevin-MacLeod-CC-BY-Tracks und die
gepitchten Aliasse (`fog_storm`/`boss_fog_tyrant`) werden nicht mehr ausgeliefert.

## Music

All 15 music cues in `assets/eclipse/sounds/music/` were **generated with Treblo
(Sonauto V3)** through the official API for Eclipse Event (custom prompt design,
instrumental). Post-processing via `tools/music/treblo_generate.py postprocess()`:
two-pass loudness normalization to -16 LUFS, re-encoded to stereo OGG Vorbis at
48 kHz (~q4/128 kbps, stepped down when a track exceeds the 2.5 MB budget), with all
non-audio streams stripped. Shipped assets are checked by
`tools/music/validate_oggs.py` (pure-Vorbis, ≤ 48 kHz, stereo, size budget).

Earlier builds shipped Kevin MacLeod (incompetech.com, CC BY 4.0) placeholder tracks
for some cues; as of 2026-07-24 no third-party music is redistributed anymore.

## Classic textures

**“Minecraft: Classic Edition”** resource pack by **JS03**, version 1.2.3 —
[Modrinth](https://modrinth.com/resourcepack/minecraft-classic-edition), project `6r6dKiPb`;
**MIT License**, verified via the
[Modrinth API](https://api.modrinth.com/v2/project/minecraft-classic-edition).
The pack is a community-made recreation of the old 16×16 look. Some textures were drawn
procedurally or derived from the pack's MIT art. Per-texture transformations and sources are
recorded in [`tools/classicblocks/provenance.json`](tools/classicblocks/provenance.json).

## Xbox 360 tutorial worlds

World content is by **Mojang / 4J Studios**. Java Edition conversions are courtesy of
[The Minecraft Architect](https://theminecraftarchitect.com/tutorial-worlds):

| World | Exact conversion source |
|---|---|
| TU1 | <https://downloads.theminecraftarchitect.com/tutorial-worlds/TU1%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip> |
| TU12 | <https://downloads.theminecraftarchitect.com/tutorial-worlds/TU12%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip> |
| TU14 | <https://downloads.theminecraftarchitect.com/tutorial-worlds/TU14%20Tutorial%20World%20%5BJE%20Latest%5D%20%5BUNZIP%5D.zip> |

Additional archive reference:
[Fridtjof-DE/Minecraft-Xbox-360-Tutorial-Worlds](https://github.com/Fridtjof-DE/Minecraft-Xbox-360-Tutorial-Worlds).
The worlds were upgraded locally with Mojang's official 1.21.1 server data fixer; that tool is
not redistributed. Source pins, integrity hashes, and pipeline provenance are tracked in
[`tools/xboxworlds/`](tools/xboxworlds/) and
[`docs/plans_v3/wiring/P5-W7_wiring.md`](docs/plans_v3/wiring/P5-W7_wiring.md).

**No legal clearance is claimed for redistributing the Mojang/4J tutorial-world binaries.**
The upstream conversions do not provide an explicit redistribution license. They are intended
for a private, non-commercial community event and not for standalone re-hosting. If distribution
approval is required, use the documented first-boot download fallback instead of bundling them.

## Bundled mods and libraries

The build currently embeds these dependencies as nested jars. The complete legal/technical
bundling decisions, external pack dependencies and source links belong to
[`docs/BUNDLING.md`](docs/BUNDLING.md).

| Component | Bundled version | Author/project | License |
|---|---|---|---|
| EMI | 1.1.24+1.21.1 | [Emily Ploszaj / EMI](https://github.com/emilyploszaj/emi) | MIT |
| Mouse Tweaks | 1.21-2.26.1-neoforge | [YaLTeR / Mouse Tweaks](https://github.com/YaLTeR/MouseTweaks) | BSD-3-Clause |
| Veil | 4.3.0 | [FoundryMC / Veil](https://github.com/FoundryMC/Veil) | LGPL-3.0 |
| GeckoLib | 4.9.2 | [GeckoLib](https://github.com/bernie-g/geckolib) | MIT |

Minecraft is © Mojang Studios. Xbox 360 Edition work is © Mojang / 4J Studios. This fan project
is not affiliated with or endorsed by Mojang, Microsoft, 4J Studios, or the credited artists.
