# Collector #4 — Content: Mobs / Bosses / Altar / Rewards / Days

**Shared infra [MUST, 2]**: models authored as code with `MeshDefinition`/`PartDefinition`/`CubeListBuilder` (vanilla layer-definition API). One `EclipseEntities` DeferredRegister, `EntityRenderersEvent.RegisterLayerDefinitions` + `RegisterRenderers`, `EntityAttributeCreationEvent`. Spawning via server-tick `EclipseSpawner` keyed off day (NOT biome modifiers).

NOTE (orchestrator): collector #4 believed Quasar is a separate unavailable mod — WRONG, Quasar ships inside Veil (see collector #2). Particle auras can use Quasar.

## 1. Custom mobs (5)

### 1.1 The Other — doppelganger event mob [MUST, 4]
Signature paranoia mob. Uses existing humanoid layout + `uniform_skin.png` all players wear → indistinguishable from teammate at distance (no nametags/chat!).
- Event hunter, spawns only during "Pale Night" events, 2–3 per event, ≥24 blocks from players, surface. Despawns at dawn w/ SOUL_ESCAPE + wisp burst.
- Model: vanilla HumanoidModel geometry (head 8×8×8, body 8×12×4, limbs 4×12×4). Texture = uniform_skin copy w/ pure-black eyes + faint purple face seam (visible <6 blocks). Zero new geometry.
- AI (PathfinderMob, MONSTER): FloatGoal, WaterAvoidingRandomStrollGoal(1.0), LookAtPlayerGoal(32f), custom MimicWalkGoal (paths toward nearest player at 0.42, stops at 5 blocks and STARES), MeleeAttackGoal(1.2,false) only when player within 3 blocks or hits it, HurtByTargetGoal. Random setSprinting (fake mannerisms).
- Anim: humanoid walk; on aggro head snaps 180° in 2t.
- Drops: 1–2 `eclipse:umbral_shard`, 5 XP. Sounds: SILENT idle; hurt PLAYER_HURT pitch 0.8; death WARDEN_SONIC_CHARGE vol 0.3.

### 1.2 Gazer — ambient watcher [MUST, 3]
- Never attacks, only watches. Model (6 cubes): root floats 6px above ground; cloak 10×18×6; hood 8×8×8 (pivot 0,18,0); face inset 6×6×1 emissive (RenderType.eyes); 2 tatters 3×8×1.
- Anim: bob `root.y += sin(age*0.06)*0.8`; tatters `xRot = sin(age*0.1+phase)*0.15`; hood yaw-locked to nearest player (lerp 10%/t).
- AI: NO movement goals. VanishWhenSeenGoal: player look-vector dot ≥0.985 for 40t → despawn w/ wisp puff + mood sound at that player. RelocateGoal: every 200–400t teleport to surface point 20–40 blocks away in peripheral FOV (dot 0.3–0.8).
- Spawn: overworld nights day 3+; 1 per ~4 players; 1 guaranteed near altar during sacrifices. hurt() → vanish (unkillable). Sounds: whisper loop ≤12 blocks (`eclipse:ambient.gazer_whisper`).

### 1.3 Umbral Stalker — pack hunter [MUST, 4]
- Night hunter day 5+. Model (11 cubes): body 8×7×14 (pivot 0,10,0, xRot 0.05); head 7×6×8 (pivot 0,12,−8) + 2 jaw shards 1×3×1; 4 legs 3×8×3; 3 spine shards (2×4×2, 2×5×2, 2×4×2) at z −4/0/4, zRot ±0.2.
- Anim: quadruped `leg.xRot = cos(limbSwing*0.66+phase)*1.2*limbSwingAmount`; shards pulse-breathe; head lowers 0.3 w/ target.
- AI: FloatGoal, LeapAtTargetGoal(0.4), MeleeAttackGoal(1.3,true), stroll, RandomLook; HurtByTargetGoal().setAlertOthers(), NearestAttackableTargetGoal<Player>(true). 20 HP, 4 dmg, speed 0.32, follow 40.
- Packs 3–4, night, day 5+; double on Umbral Nights. Dawn: flees + despawns. Drops: 0–2 umbral_shard, 20% heart_fragment. Sounds: WOLF_GROWL 0.5, RAVAGER_ATTACK 1.4.

### 1.4 Deckhand — limbo ambient [SHOULD, 3]
- Mute rowing crew on ghost ship. Model (7 cubes): hunched torso 8×10×4 (xRot 0.15); head 8×8×8 + hood inflate 0.25; 2 arms 3×10×3 extended (xRot −1.2) gripping oar 1×1×22; robe base 8×8×6, no legs.
- Anim: rowing synced to OarAnimator: `arm.xRot = −1.2 + sin(age*0.08)*0.35`; sway zRot.
- No AI except LookAtPlayerGoal(48f) — occasionally tracks a ghost player. 6–8 at oar benches by GhostShipBuilder. Invulnerable, no push. Limbo only.

### 1.5 Sunmote — altar swarm wisp [NICE, 2]
- Model (2 cubes): core 2×2×2 emissive + halo 4×1×4 rot 45°, fullbright. Position driven in tick(): orbit radius 6+level, angle += 0.02, y bob; halo spins.
- altarLevel motes maintained by altar BE. Killable → 1 glowstone dust, respawn next dawn. AMETHYST_BLOCK_CHIME every ~200t.

## 2. Bosses

### 2.1 The Herald of the Eclipse — Day 7 [MUST, 5]
- Arena: altar sanctum (25-block ring). Summon: deposit "Herald's Lure" (4 umbral shards + 1 heart fragment) at altar after dusk. ServerBossEvent PURPLE, NOTCHED_6 (phase breaks at notches 4 and 2); particle wall arena lock r=15.
- Model (~27 cubes): core 12×12×12 (pivot 0,40,0 floating); innerEye 6×6×6 emissive (RenderType.eyes); corona: 8 shard wedges 2×6×2 on rotating ring bone r=14px; chains: 4 tentacles × 4 cubes (2×6×2, chained pivots).
- Anim: ring yRot = age*0.05; shards y = sin(age*0.1 + i*π/4)*2px; tentacle segment k xRot = sin(age*0.09 + k*0.6)*0.25; core bob; P3 speeds ×2 + shards tilt out (zRot lerp 0.6).
- Fight (300 HP base): **P1 Volley** (100–66%): hovers 8–12, strafes; every 60t telegraph (shards glow + BEACON_POWER_SELECT, 20t) then 3 homing shard projectiles (ShulkerBullet-style, 4 dmg, shootable); every 200t summon 2 Umbral Stalkers (cap 4). **P2 Gaze** (66–33%): guardian-style beam: locks one player (only they hear WARDEN_HEARTBEAT), 40t charge w/ visible wisp beam, 8 dmg + Darkness 5s unless LOS broken behind pillar — pillars = mechanical cover. Volley at 90t. **P3 Collapse** (33–0): descends to y+3, pulls players 0.08/t toward center, expanding damage rings every 80t (radius +0.4/t; jump over; SOUL_FIRE_FLAME floor markers). Shards detach as HP drops, crash as AoE.
- Scaling: HP = 300*(1+0.35*(n−1)); stalker cap 2+n; telegraphs −2t per player (floor 12).
- Drops: 1 `eclipse:herald_core` — REQUIRED for altar milestone L4 (L4 cost: herald_core ×1 + ender_pearl ×16), + 3 umbral shards per participant (dropped at each player's feet). Bossbar: "☀ The Herald".

### 2.2 The Ferryman — Day 14 finale [MUST, 5]
- Arena: limbo ghost ship. Finale ritual at altar teleports ALL living players to deck; ghosts already there and PARTICIPATE (re-light lanterns — ghost-only interaction).
- Model (~18 cubes, 3.5 blocks tall): robe 10×26×8 floating (4 hanging strips 2×6×1); skull head 7×7×7 under hood 9×9×9; arms 3×20×3; oar weapon 2×2×36 two-handed; lantern 4×5×4 on 3-segment chain (1×4×1) off left shoulder, swinging w/ drag-lag.
- Fight (400 HP base, bossbar WHITE→PURPLE→RED per phase): **P1 Oar**: melee stalker; telegraphed 180° sweep (raise 25t, TRIDENT_RIPTIDE_3, 10 dmg + big KB — overboard = void-cold water DoT until climb back). "Gunwale slam": jump-slam tilting ship visually (client shake payload). **P2 Crew** (66%): kneels invulnerable at stern; 6–8 Deckhands rise hostile; 4 deck lanterns extinguish. Living kill Deckhands; ghosts re-light lanterns (right-click 3s channel). 4 lanterns lit → phase ends. **P3 The Toll** (33%): plants oar; ship sinks (water rises 1 layer/30s soft enrage); alternates sweeps with "Lantern Gaze": lowest-hearts player marked (vignette overlay only they see) and hunted 15s — forces defending the weakest.
- Scaling: HP ×(1+0.4*(n−1)) living; lanterns = min(4, ghosts+2); sink slows if ≤3 alive.
- End: drops `eclipse:ferryman_toll`; all banned players mass-revived (ReviveRitual completion path) — ship "returns everyone" as win cinematic (reverse StartEventCutscene). Wipe = Eclipse victory ending.

## 3. Altar structure — "Sanctum of the Occluded Sun" [MUST, 3]
~25×25, altar centered, built by `AltarSanctumBuilder` (GhostShipBuilder pattern: build-once flag, ServerStartedEvent).
- Dais: 3 concentric circular steps polished blackstone (r=5 y0, r=3.5 y1, r=2 y2); altar at y3. Slab edges; 15% cracked variants.
- Pillar ring: 8 pillars at r=9 every 45°: 2×2 obsidian base (2h) + purpur pillar shafts heights 4/6/7/5/6/4/7/5, three "snapped" w/ deepslate wall tops. **Herald LOS cover.**
- Floating rings: r=4 purple tinted-glass ring at y+8 (every other block), r=2.5 crying obsidian ring y+11 (cardinal 4). No supports — eclipse halo.
- Amethyst clusters on 6 dais blocks; soul lanterns on chains from 4 tall pillars; sculk veins at dais perimeter (20%); 4 purple candles ×3.
- Approach: 4 cardinal blackstone-slab paths (len 5); terrain flattened r=12 w/ coarse dirt + rubble.
- **Spawn protection [MUST, 2]**: cancel BlockEvent.BreakEvent / EntityPlaceEvent / explosions within r=16 (ops exempt); suppress non-eclipse hostile spawns r=16 (FinalizeSpawnEvent) — unnaturally calm.
- Level-up evolution [NICE, 2]: L2 lights candles, L3 sunmotes, L4 end rods on stumps, L5 y+11 ring glows.

## 4. Custom rewards (umbral shard economy)
Deposit `umbral_shard`s at altar while sneaking → personal reward shop cycled on action bar.

| Reward | Cost | Spec | Tag/Effort |
|---|---|---|---|
| Compass of the Watcher | 8 | compass pointing at NEAREST OTHER PLAYER, updates 40t: inventoryTick writes target GlobalPos into `minecraft:lodestone_tracker` component. Never says who. | [MUST] 2 |
| Grave Dowser | 4 | same trick → holder's nearest grave. Grave positions: List<GlobalPos> per owner in EclipseWorldState (append on grave place, remove on break/expiry). | [MUST] 2 |
| Vitae Shard | 12 | consumable (32t use, TOTEM_USE): +1 heart, cap 7. Only heart source besides revive. | [MUST] 1 |
| Eclipse-touched tools | 10–16 | Umbral Pick (+mining speed under open sky at night) / Umbral Blade (+1 heart lifesteal on kill) via ItemAttributeModifiers; unrepairable, high durability. | [SHOULD] 3 |
| Particle auras | 6 ea | Quasar (via Veil) helix auras: Wisp Halo, Ember Crown, Eclipse Shadow. Selection = String attachment; toggle in artifact menu. | [SHOULD] 3 |
| Team: Supply Beacon | 24 pooled | pooled counter in world-state; falling supply crate 50–100 blocks from altar w/ END_ROD column; curated barrel loot. Coordinates secret — first come first served. | [SHOULD] 3 |
| Team: Eclipse's Favor | 16 pooled | global Regen I + Saturation rest of day; altar beam brighter. | [NICE] 2 |
| Whisper Ward | 6 | while in inventory: Gazers keep +10 distance; The Other won't pick you first. | [NICE] 2 |

## 5. New unlockable mods (Modrinth-verified NeoForge 1.21.1, 2026-07)

| Mod | Version | Namespace | Unlock | Notes |
|---|---|---|---|---|
| Farmer's Delight (`farmers-delight`) | 1.21.1-1.3.2 ✅ | farmersdelight | Day 4 | communal meals = trust ritual. [MUST] |
| Sophisticated Backpacks | 1.21.1-3.25.71 ✅ | sophisticatedbackpacks | Day 8 | requires `sophisticated-core` — do NOT gate the library. [MUST] |
| Supplementaries | 1.21.1-3.8.3 ✅ | supplementaries | Day 5 | needs Moonlight Lib (don't gate). CAVEAT: adds sign-like text blocks → TextInputBlocker must cover them. [SHOULD] |
| Create: Crafts & Additions (`createaddition`) | neoforge-1.21.1-1.6.0 ✅ | createaddition | Day 9 (altar L4) | electricity tier on Create. [SHOULD] |
| Create: Connected | 1.3.2-mc1.21.1 ✅ | create_connected | with `create` key (day 3) | verify namespace from jar. [NICE] |
| Create: Steam 'n' Rails | ❌ no NeoForge 1.21.1 | — | excluded | |

## 6. Improved 14-day arc
Recurring events: **Umbral Night** (double stalkers, red-shifted eclipse), **Pale Night** (The Other spawns), **Limbo Whispers** (living near graves hear stingers), **Supply drops**.

| Day | Theme | Goals | Expansion/Unlocks/Events |
|---|---|---|---|
| 1 | First Light | survive night; bank 16 logs + stone tools; everyone touches altar | stage: fused disc. Gazer teaser at dusk. |
| 2 | The Burning Door | enter Nether; 8 gold; altar L1 (16 iron) | Unlock: nether (N1), main_inventory |
| 3 | Machines in the Dark | Create contraption; iron toolset; scout new ring (village) | Expansion→village ring. Unlock: workbenches, create (L1) |
| 4 | The Feast | 3 FD meals; food farm; full iron armor | Unlock: armor, farmersdelight, simulated (L2: 16 gold). First Pale Night. |
| 5 | Skyward | fly (aeronautics); 24 iron; Supplementaries rigging | Expansion→desert temple. Unlock: aeronautics (L3: 8 diamonds), supplementaries |
| 6 | Fortress | find fortress; 6 blaze rods; craft Herald's Lure | Umbral Night (shard farming). Enchanting prep. |
| 7 | BOSS: The Herald | summon at dusk; defeat; deposit herald_core | Herald fight. Unlock on kill: enchanting. |
| 8 | The Hoard | team ender chest; 16 pearls; altar L4 (core+pearls) | Expansion→jungle temple. Unlock: ender_chests, sophisticatedbackpacks, sable |
| 9 | Alchemy & Voltage | strength + fire-res potions; electrify machine; pool 24 shards | Unlock: brewing, createaddition. Supply drop. |
| 10 | Deep Ruin | smithing template; netherite upgrade; fortify base | Nether N2 + overworld ruin. Unlock: smithing. Umbral Night. |
| 11 | The Weakest Link | everyone ≥4 hearts; revive a banned player; End kit | economy day. Limbo Whispers all day. |
| 12 | Stronghold | locate stronghold; breach; hold portal room overnight | Final expansion + stronghold emergence. Unlock: end (L5: 2 netherite). Pale Night in corridors. |
| 13 | The Dragon | defeat dragon; claim egg; all survivors return | End open. Egg = finale catalyst. |
| 14 | BOSS: The Ferryman | offer egg at dusk; survive crossing; defeat before ship sinks | All → limbo ship. Win: mass revive + credits. |

**Milestones**: L1 16 iron, L2 16 gold, L3 8 diamonds, L4 herald_core+16 pearls, L5 2 netherite. modgate.json += farmersdelight, supplementaries, sophisticatedbackpacks, createaddition (+create_connected sharing `create` key).

**Priority**: §6 config + §1.1/1.3 mobs + §3 sanctum → §2.1 Herald → §4 MUST rewards → §2.2 Ferryman → SHOULD/NICE.
