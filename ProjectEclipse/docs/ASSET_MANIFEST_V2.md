# PROJECT: ECLIPSE v2 — Asset Manifest (orchestrator image-gen + procedural split)

**Global style prompt hint (apply to every image-gen item unless overridden):**
"dark purple eclipse horror aesthetic, occluded violet sun, deep indigo/black palette with
`#B98CFF` accent glow, painterly but crisp, subtle film grain, no text unless specified,
game-UI asset". Match existing final art: `assets/eclipse/textures/gui/title/*` and
`textures/environment/sun_purple.png`.

**Ground rules**
- All paths are relative to `src/main/resources/`. Workers create programmer-art
  placeholders at these EXACT paths/dimensions first (via `scripts/placeholder_gen/`
  generators); orchestrator art is a byte-for-byte drop-in replacement. Never change a
  path or size when replacing.
- PNG only. "Alpha: yes" = transparent background required (straight alpha, no matte).
- Mob/boss textures are generated ONLY after the corresponding worker has committed the
  UV-mapped placeholder + `docs/uv/<mob>.md` (see Batch D workflow).
- Sounds cannot be image-gen'd — see the Sounds section: workers commit placeholder OGGs;
  final audio is sourced/produced separately (CC0 libraries or commissioned).

---

## Batch A — Handbook 2.0 (priority 1, unblocks W9's biggest visual win)

| Path | Size (px) | Alpha | Prompt hint |
|---|---|---|---|
| `assets/eclipse/textures/gui/handbook/book_spread.png` | 2048×1280 | yes | open ancient waterlogged ledger, two-page spread, dark leather + parchment pages tinted violet, ornate eclipse emblem on spine, vignetted edges |
| `assets/eclipse/textures/gui/handbook/parchment_tile.png` | 1024×1024 | no | seamless tileable aged parchment, faint purple water stains, subtle fiber texture, low contrast (text must stay readable) |
| `assets/eclipse/textures/gui/handbook/tab_status.png` | 64×64 | yes | icon: eclipsed sun disc with thin corona, flat emblem style |
| `assets/eclipse/textures/gui/handbook/tab_timeline.png` | 64×64 | yes | icon: horizontal spine with nodes, one node glowing |
| `assets/eclipse/textures/gui/handbook/tab_rules.png` | 64×64 | yes | icon: scroll with wax seal, purple seal |
| `assets/eclipse/textures/gui/handbook/tab_rewards.png` | 64×64 | yes | icon: faceted crystal shard cluster |
| `assets/eclipse/textures/gui/handbook/tab_bestiary.png` | 64×64 | yes | icon: hooded silhouette with black eyes |
| `assets/eclipse/textures/gui/handbook/tab_map.png` | 64×64 | yes | icon: concentric rings with a center dot, cartographic |
| `assets/eclipse/textures/gui/handbook/hero_status.png` | 1024×768 | yes | painterly vista: floating island disc under a purple eclipse, tiny altar glow at center |
| `assets/eclipse/textures/gui/handbook/hero_timeline.png` | 1024×768 | yes | ghost ship sailing a black sea toward a violet horizon |
| `assets/eclipse/textures/gui/handbook/hero_rules.png` | 1024×768 | yes | stone tablet with glowing runes, chained |
| `assets/eclipse/textures/gui/handbook/hero_rewards.png` | 1024×768 | yes | altar dais with floating crystal shards and light motes |
| `assets/eclipse/textures/gui/handbook/hero_bestiary.png` | 1024×768 | yes | several shadowed creature silhouettes in fog, eyes glinting |
| `assets/eclipse/textures/gui/handbook/hero_map.png` | 1024×768 | yes | top-down painted disc world map, ring seams visible, void beyond rim |
| `assets/eclipse/textures/gui/handbook/timeline_node_locked.png` | 96×96 | yes | dark rune circle, cracked, dim |
| `assets/eclipse/textures/gui/handbook/timeline_node_unlocked.png` | 96×96 | yes | same rune circle lit violet |
| `assets/eclipse/textures/gui/handbook/timeline_node_current.png` | 96×96 | yes | rune circle blazing with corona flare |
| `assets/eclipse/textures/gui/handbook/divider.png` | 512×64 | yes | ornamental horizontal divider, eclipse motif center |
| `assets/eclipse/textures/gui/cursor/arrow.png` | 32×32 | yes | themed cursor arrow, pale violet blade, dark outline (hotspot 0,0 — keep tip in top-left) |
| `assets/eclipse/textures/gui/cursor/hand.png` | 32×32 | yes | pointing hand, same style (hotspot 8,0 — fingertip at x=8,y=0) |
| `assets/eclipse/textures/gui/cursor/grab.png` | 32×32 | yes | grabbing fist, same style (hotspot 16,16 — centered) |

## Batch B — HUD: hearts, bossbars, sidebar (priority 2)

| Path | Size (px) | Alpha | Prompt hint |
|---|---|---|---|
| `assets/eclipse/textures/gui/hearts/heart_full.png` | 36×36 | yes | violet-black heart, faint inner glow, crisp game-HUD icon (4× res of a 9×9 heart) |
| `assets/eclipse/textures/gui/hearts/heart_empty.png` | 36×36 | yes | hollow dark heart outline, embers |
| `assets/eclipse/textures/gui/hearts/heart_cracked.png` | 36×36 | yes | same heart with glowing crack |
| `assets/eclipse/textures/gui/hearts/burst_sheet.png` | 216×36 (6 frames 36×36) | yes | heart shattering left→right: flash, crack, 6 shards flying; frame-consistent |
| `assets/eclipse/textures/gui/bossbar/day_frame.png` | 512×64 | yes | ornate bar frame, silver-violet filigree, sun-dial end caps |
| `assets/eclipse/textures/gui/bossbar/goal_frame.png` | 512×64 | yes | same family, crystal-shard end caps |
| `assets/eclipse/textures/gui/bossbar/boss_frame.png` | 512×64 | yes | same family, menacing thorned frame, darker |
| `assets/eclipse/textures/gui/bossbar/fill.png` | 512×32 | yes | horizontal energy gradient, violet→magenta core |
| `assets/eclipse/textures/gui/bossbar/scroll.png` | 256×32 | yes | seamless-x scrolling energy streaks overlay, additive-friendly (bright on transparent) |
| `assets/eclipse/textures/gui/bossbar/glow.png` | 64×64 | yes | soft radial end-cap glow |
| `assets/eclipse/textures/gui/sidebar/panel.png` | 64×64 (9-slice, 8px corners) | yes | rounded dark glass panel, thin violet rim |
| `assets/eclipse/textures/gui/sidebar/icon_heart.png` | 24×24 | yes | mini heart icon, HUD-legible |
| `assets/eclipse/textures/gui/sidebar/icon_day.png` | 24×24 | yes | mini eclipse-sun icon |
| `assets/eclipse/textures/gui/sidebar/icon_altar.png` | 24×24 | yes | mini altar/dais icon |
| `assets/eclipse/textures/gui/sidebar/icon_players.png` | 24×24 | yes | mini hooded-figures icon |
| `assets/eclipse/textures/gui/sidebar/icon_goal.png` | 24×24 | yes | mini checkmark rune icon |
| `assets/eclipse/textures/gui/icons/altar_ring.png` | 256×256 | yes | circular progress ring, runic segment marks, violet glow (drawn in arc segments by code) |

## Batch C — Title screen v2 + settings (priority 3)

| Path | Size (px) | Alpha | Prompt hint |
|---|---|---|---|
| `assets/eclipse/textures/gui/title/parallax_far.png` | 1024×512 | yes | distant wispy violet nebula clouds, very low contrast |
| `assets/eclipse/textures/gui/title/parallax_mid.png` | 1024×512 | yes | mid-depth drifting fog banks, purple-grey |
| `assets/eclipse/textures/gui/title/parallax_near.png` | 1024×512 | yes | near black smoke tendrils framing screen edges |
| `assets/eclipse/textures/gui/title/wisp.png` | 32×32 | yes | single soft purple wisp mote, additive-friendly |
| `assets/eclipse/textures/gui/title/flare_sweep.png` | 512×128 | yes | horizontal lens-flare streak, white-violet core (swept across logo by code) |
| `assets/eclipse/textures/gui/title/gear.png` | 48×48 | yes | settings gear icon, filigree style matching title buttons |

Note: `title/background.png`, `logo.png`, `panorama_0..5.png`, `button*.png` are FINAL v1
art — do not regenerate.

## Batch D — Mob & boss textures (priority 4 — ONLY after UV docs exist)

Workflow: worker W10/W11/W12 commits (1) programmer-art texture at the path below (distinct
flat color per body part + seam lines) and (2) `docs/uv/<name>.md` (texture size + per-cube
UV origin/box dims/face rects). The orchestrator then generates art that respects those
exact pixel rects — paint each face rect as specified, keep 1px bleed margins, transparent
elsewhere. Boxy, readable, Minecraft-native pixel density (no painterly gradients across
face boundaries).

| Path | Size (px) | Alpha | Prompt hint |
|---|---|---|---|
| `assets/eclipse/textures/entity/the_other.png` | 64×64 (player skin layout) | yes | exact copy-style of `uniform_skin.png` but pure black eyes and a faint purple seam splitting the face — must be nearly indistinguishable at distance |
| `assets/eclipse/textures/entity/gazer.png` | 64×64 | yes | tattered void-cloak fabric, deep purple-black weave; hood interior pure black; face plate emissive pale violet |
| `assets/eclipse/textures/entity/umbral_stalker.png` | 64×64 | yes | sleek obsidian-furred quadruped, glowing violet spine shards, black-glass jaw |
| `assets/eclipse/textures/entity/deckhand.png` | 64×64 | yes | drowned grey-violet robes, waterlogged rope details, hollow hood |
| `assets/eclipse/textures/entity/sunmote.png` | 32×32 | yes | tiny radiant violet-gold core + halo ring, fullbright |
| `assets/eclipse/textures/entity/herald.png` | 128×128 | yes | eclipsed-sun godhead: obsidian core cube, blazing violet inner eye, corona shard wedges like broken stained glass, chain-tentacles |
| `assets/eclipse/textures/entity/ferryman.png` | 128×128 | yes | skeletal ferryman: bone skull under deep hood, rotted robe strips, ancient oar wood, verdigris lantern |

## Batch E — Items & environment (priority 5)

16×16 item icons are BETTER done as worker programmer pixel-art first (image-gen is weak at
16×16). Orchestrator MAY optionally regenerate them at 256×256 in pixel-art style and
downscale with nearest-neighbor — only replace if clearly better.

| Path | Size (px) | Alpha | Who | Hint |
|---|---|---|---|---|
| `assets/eclipse/textures/item/umbral_shard.png` | 16×16 | yes | worker first, image-gen optional | jagged violet crystal shard |
| `assets/eclipse/textures/item/herald_core.png` | 16×16 | yes | worker first, image-gen optional | caged black sun orb |
| `assets/eclipse/textures/item/ferryman_toll.png` | 16×16 | yes | worker first, image-gen optional | ancient ghostly coin |
| `assets/eclipse/textures/item/heralds_lure.png` | 16×16 | yes | worker first, image-gen optional | shard bundle bound with sinew |
| `assets/eclipse/textures/item/compass_of_watcher.png` | 16×16 | yes | worker first, image-gen optional | compass with an eye needle |
| `assets/eclipse/textures/item/grave_dowser.png` | 16×16 | yes | worker first, image-gen optional | forked bone rod |
| `assets/eclipse/textures/item/vitae_shard.png` | 16×16 | yes | worker first, image-gen optional | pulsing red-violet heart crystal |
| `assets/eclipse/textures/item/umbral_pick.png` / `umbral_blade.png` | 16×16 | yes | worker first, image-gen optional | obsidian-violet tools |

## Procedural-by-worker ONLY (do NOT image-gen)

- `assets/eclipse/textures/environment/border_glitch.png` (256×256, seamless): animated-scroll
  glitch static — value noise + horizontal displacement bands; must tile in X. Code-generated
  noise is crisper and seamless-guaranteed.
- Quasar particle sprites (`assets/eclipse/textures/particle/`): soft radial glows, shard
  glints, mote dots (16–32px, additive). Trivial radial-gradient math beats image-gen here.
- All `scripts/placeholder_gen/` programmer-art (mob placeholders, UI placeholders) — by
  definition worker-authored.
- Glitch/"???" text effects, letterbox bars, vignettes, ring diagrams, progress arcs —
  drawn by code at runtime, no textures needed.
- `docs/uv/*.md` UV descriptions — worker-authored alongside models.

## Sounds (NOT image-gen — workers commit placeholders; source/produce finals separately)

| Id (registered) | File | Placeholder by | Character |
|---|---|---|---|
| `eclipse:ui.hover` / `ui.page_turn` / `ui.tab` / `ui.unlock_sting` | `assets/eclipse/sounds/ui/*.ogg` | W9 | soft paper/chime UI suite |
| `eclipse:ui.heart_shatter` | `assets/eclipse/sounds/ui/heart_shatter.ogg` | W2 | glass crack + low thud |
| `eclipse:ui.typewriter` | `assets/eclipse/sounds/ui/typewriter.ogg` | W8 | single dry tick |
| `eclipse:ambient.gazer_whisper` | `assets/eclipse/sounds/ambient/gazer_whisper.ogg` | W10 | breathy reversed whispering loop |
| `eclipse:boss.herald_ambient` / `boss.herald_telegraph` | `assets/eclipse/sounds/boss/*.ogg` | W11 | choral drone / rising shard chime |
| `eclipse:event.border_glitch` | `assets/eclipse/sounds/event/border_glitch.ogg` | W7 | digital static burst |
| (existing) `ambient.limbo_loop`, `event.submerge` | v1 placeholders | — | replace with final ambience later |

## Generation order for the orchestrator

1. Batch A after W9 lands (paths exist, placeholders prove wiring).
2. Batch B after W2/W8.
3. Batch C after W15.
4. Batch D after W10/W11/W12 commit UV docs — generate one mob, verify in-game via
   `runClient` before batch-generating the rest.
5. Batch E last, optional.
Each drop-in: replace file, `./gradlew build` (resources repack), `runClient` spot-check,
commit `eclipse v2: final art drop <batch>`.
