# Eclipse Event Credits

## Music

All eight tracks are by **Kevin MacLeod** and were downloaded from
[incompetech.com](https://incompetech.com). They are redistributed under
[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
The mod copies are trimmed where noted, loudness-normalized to approximately -16 LUFS,
faded for one second at each edge, and encoded as stereo OGG Vorbis.

| Eclipse cue | Track / ISRC | Source (exact downloaded file) | Mod copy | License |
|---|---|---|---|---|
| `boss_ferryman` | “Final Battle of the Dark Wizards” / `USUAN1500085` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Final%20Battle%20of%20the%20Dark%20Wizards.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1500085) | 03:00, 2,109,802 B; excerpt from 00:30 | CC BY 4.0 |
| `boss_herald` | “Volatile Reaction” / `USUAN1400039` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Volatile%20Reaction.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400039) | 02:43, 1,895,245 B | CC BY 4.0 |
| `limbo_ambience` | “Echoes of Time v2” / `USUAN1300030` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Echoes%20of%20Time%20v2.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300030) | 03:00, 2,157,957 B; opening excerpt | CC BY 4.0 |
| `title_theme` | “Atlantean Twilight” / `USUAN1100322` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Atlantean%20Twilight.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100322) | 02:49, 1,999,372 B | CC BY 4.0 |
| `expansion_theme` | “Enchanted Valley” / `USUAN1200093` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Enchanted%20Valley.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1200093) | 01:30, 1,165,397 B; excerpt from 00:25 | CC BY 4.0 |
| `intro_storm` | “Stormfront” / `USUAN1200043` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Stormfront.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1200043) | 02:30, 2,016,591 B; excerpt from 00:30 | CC BY 4.0 |
| `victory_theme` | “Ascending the Vale” / `USUAN1600064` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Ascending%20the%20Vale.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1600064) | 03:00, 2,063,594 B; opening excerpt | CC BY 4.0 |
| `xbox_nostalgia` | “Dream Culture” / `USUAN1300046` | [MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Dream%20Culture.mp3) · [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300046) | 03:00, 2,024,259 B; opening excerpt | CC BY 4.0 |

Attribution text requested by the artist:

> “[Track title]” Kevin MacLeod (incompetech.com)  
> Licensed under Creative Commons: By Attribution 4.0  
> https://creativecommons.org/licenses/by/4.0/

License snapshot checked **2026-07-23**:
[Incompetech's Music FAQ](https://incompetech.com/music/royalty-free/faq.html) says the music
may be used in video games with a discoverable credits screen, requires the attribution above,
and permits chopping, splicing, compressing and otherwise changing the music. CC BY 4.0 grants
worldwide permission to reproduce, share and adapt the material subject to attribution. The
canonical full legal code is
<https://creativecommons.org/licenses/by/4.0/legalcode.en>.

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
not redistributed. Integrity hashes and the full staging ledger are in
`/workspace/xbox_staging/SOURCES_AND_LICENSES.md`.

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
| EMI | 1.1.18+1.21.1 | [Emily Ploszaj / EMI](https://github.com/emilyploszaj/emi) | MIT |
| Mouse Tweaks | 1.21-2.26.1-neoforge | [YaLTeR / Mouse Tweaks](https://github.com/YaLTeR/MouseTweaks) | BSD-3-Clause |
| Veil | 4.3.0 | [FoundryMC / Veil](https://github.com/FoundryMC/Veil) | LGPL-3.0 |
| GeckoLib | 4.9.2 | [GeckoLib](https://github.com/bernie-g/geckolib) | MIT |

Minecraft is © Mojang Studios. Xbox 360 Edition work is © Mojang / 4J Studios. This fan project
is not affiliated with or endorsed by Mojang, Microsoft, 4J Studios, or the credited artists.
