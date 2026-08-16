# Gooby Mod — Roadmap: 15 Shippable Versions (v3.0.0 → v5.0.0)

> **Scope:** NeoForge 1.21.1 / neo 21.1.248 · GeckoLib 4.9.x · mod_id `goobymod` ·
> package `de.sonic0810.goobymod` · "made by Sonic0810" · full DE+EN i18n.
> **Base:** current `mod_version 2.0.0` ("Best Friends").
> This document is analysis + planning only; no code has been changed.

---

## Table of Contents

1. [Current-State Assessment](#1-current-state-assessment)
2. [Non-Negotiable Constraints for Every Version](#2-non-negotiable-constraints-for-every-version)
3. [The Strict Polish Rubric (Global)](#3-the-strict-polish-rubric-global)
4. [Most Important Current Bugs & Risks (file + why)](#4-most-important-current-bugs--risks)
5. [The 15 Versions](#5-the-15-versions)
6. [Prioritized Idea Backlog](#6-prioritized-idea-backlog)
7. [Master Asset List to Create](#7-master-asset-list-to-create)
8. [Localization Strategy (DE+EN)](#8-localization-strategy-deen)
9. [Testing & Release Engineering Strategy](#9-testing--release-engineering-strategy)

---

## 1. Current-State Assessment

### What exists and works (verified by reading the code)

**Entity & AI** — `entity/GoobyEntity.java` (1306 lines, well-documented):
- `TamableAnimal` + `GeoEntity`; 1.1×1.4 hitbox, 40 HP, knockback-immune, step height 1.
- Real taming via Nutella (`tame(player)` fires the vanilla `tame_animal` trigger), per-player
  friendship map 0–100 (persistent NBT list), gift charges/cooldown economy, satisfaction 0–100
  with decay + happy-speed modifier, synced hat via `EntityData` string, home/nest position,
  jar-target claiming for the night-spawn path.
- Goals: `FloatGoal`, strict `GoobySitGoal`, `GoobyTemptGoal` (Nutella lure), `GoobyFollowOwnerGoal`
  (vanilla-based, command-gated), `GoobySleepGoal` (hutch preference, wake suppression),
  `GoobyDigGoal`, `GoobyRandomSitGoal`, stroll/look goals.
- Player-invulnerability with boing + sad reaction; environmental danger teleport; riding with
  Nutella steering, wobble gait, joy-hops.

**Rendering** — `client/GoobyRenderer.java`, `client/GoobyModel.java`:
- GeckoLib renderer with hat item layer on the `head` bone and a hand-rolled billboard speech
  bubble (multi-line, camera-facing text — the 2.0 fix for the invisible-text bug is in place).
- Head-tracking in `setCustomAnimations` (0.6/0.7 damping), disabled while sleeping/digging.

**Assets:**
- `geo/gooby.geo.json`: 12 bones (root, body, head, nose, 2 eyes, 2 ears, tail, 2 paws, 2 feet),
  64×64 texture. Eyes are flat planes — good base for texture-swap blinking.
- `animations/gooby.animation.json`: 9 animations (idle, hop, sleep, sit, pet, eat, wave, dig, sad).
- 7 synthesized OGG sounds (one file per event, no variants), `sounds.json` with subtitles.
- Zzz particle, speech-bubble texture, block/item textures — all script-generated
  (`scripts/gen_textures.py`, `gen_sounds.py`, `gen_whistle_texture.py`, `gen_structure.py`).

**Blocks** — gooby wool (fall-damage cancel), nutella jar (atomic `CLAIMED` spawn reservation,
random-tick self-heal), rabbit hutch (facing, sleep target).

**Data:** 5 recipes, 7-node advancement tree, block loot tables, mineable tags, 2 GameTest arena
structures.

**Quality infrastructure:**
- 18 GameTests in `gametest/GoobyGameTests.java` covering recipes, conversion, taming, friendship
  cooldown, whistle owner-binding, stay/follow, gift cost+cooldown, persistence roundtrip, hat sync,
  atomic jar spawn, sleep interruption, Create degradation, advancement tree, Sophie regression +
  killswitch + gameplay-parity.
- CI `/.github/workflows/modjar.yml`: clean build + FATAL GameTests + jar artifact.
- Server-synced config (`GoobyConfig`) with safe pre-load fallbacks.
- EN/DE parity verified: 114 keys in each lang file, zero divergence.

**Compat** — `compat/CreateCompat.java`: reflection against Create 6.x
`SeatBlock.sitDown(Level, BlockPos, Entity)`, full signature verification, permanent crash-free
degradation, no hard dependency.

### Honest gaps (what "cute companion" still lacks)

1. **Micro-life:** no blinking, ear twitches, nose wiggles, yawns, stretches, transitions
   (sit-down/stand-up are hard cuts). Idle is a single loop → visibly robotic after 30 seconds.
2. **Sound depth:** one sample per event, no variant pools, no mood-differentiated ambient, no
   looping purr while petting, cheerful squeak doubles as *death* sound (tone mismatch).
3. **Survivability:** Gooby is only invulnerable to *players*. Zombies, wolves, cacti pushed into,
   or the void can kill a beloved tamed companion silently — hat item is destroyed with it
   (no death-drop). This is the single biggest emotional risk in a companion mod.
4. **Bond expression:** friendship is a number in the actionbar; no tiers, no visible behavior
   change per tier, no memory ("first pet"), no reaction to its own name.
5. **Interaction breadth:** pet / feed / brush / whistle / hat / ride — no tricks, no training loop,
   no held-item reactions, no social behavior between multiple Goobys.
6. **Home:** hutch is a solid block Gooby physically cannot enter (14×13×14 voxel shape vs 1.1-wide
   entity) — it sleeps *next to* it while the README promises "kuschelt sich hinein".
7. **Release engineering per the new constraints:** no top-level `versions/` folder, no
   `PATCHNOTES.md`, no DE+EN Handbuch.

---

## 2. Non-Negotiable Constraints for Every Version

Every one of the 15 versions MUST ship with all of the following. Treat this as the release
checklist template that is copy-pasted into each release PR:

| # | Constraint | Concrete rule |
|---|---|---|
| C1 | Platform | NeoForge 1.21.1, `neo_version=21.1.248`, GeckoLib 4.9.x line. No MC version bumps inside this roadmap. |
| C2 | Author | `mod_authors=Sonic0810`; "made by Sonic0810" stays in `mod_description` and README/Handbuch footer. |
| C3 | i18n | 100% key parity `en_us.json` ⇄ `de_de.json`, enforced by a GameTest (see v3.0). Every new user-facing string gets both languages in the same commit. |
| C4 | Jar archive | Built jar copied to top-level `versions/` as `versions/NN-goobymod-X.Y.Z.jar` (NN = 01, 02, … release ordinal for stable sorting). `.gitattributes` marks `versions/*.jar binary`; a `versions/README.md` indexes them. |
| C5 | Patch notes | `PATCHNOTES.md` at repo root gains a dated section per version (DE first, EN below — mirroring `CHANGELOG.md` style). `CHANGELOG.md` remains the terse engineering log; `PATCHNOTES.md` is player-facing. |
| C6 | Handbuch | `docs/HANDBUCH_DE.md` + `docs/MANUAL_EN.md` updated with every feature; from v3.6 also the in-game Handbuch item (see roadmap). |
| C7 | Tests | GameTests green and FATAL in CI. Every new mechanic ships with at least one GameTest; every fixed bug ships with a regression test. |
| C8 | Version bump | `gradle.properties` `mod_version` bumped; `versions/` jar name, PATCHNOTES header, and README version line all match. |
| C9 | Polish gate | The Strict Polish Rubric (section 3) scored; ship only at ≥ 18/20 with no criterion at 0. |

**Suggested new tooling (built in v3.0, reused forever):** `scripts/release.py` that
(1) verifies C3 parity, (2) builds, (3) copies the jar to `versions/`, (4) refuses to run if
`PATCHNOTES.md` has no section for the current version, (5) prints the rubric template to fill in.

---

## 3. The Strict Polish Rubric (Global)

Score each criterion 0 (fail) / 1 (acceptable) / 2 (excellent). **Ship gate: total ≥ 18/20, no 0s.**
Versions add their own specific rubric rows in section 5; those are additive pass/fail gates.

| # | Criterion | 2 = excellent means |
|---|---|---|
| R1 | **Animation fidelity** | No pose pops: every state change (idle↔hop↔sit↔sleep↔dig) blends via GeckoLib transition ticks or dedicated transition clips; squash & stretch consistent with mass. |
| R2 | **Animation variety** | Idle never looks identical for 60 s straight (blink/ear/nose micro-layer active); triggered anims never cut each other off mid-keyframe. |
| R3 | **Sound design** | No event plays the identical sample twice in a row (variant pools + pitch/volume jitter); volumes sit correctly in the vanilla mix; subtitles exist for every sound. |
| R4 | **AI believability** | No goal flicker (sit/stand oscillation), no pathing into hazards, reactions have anticipation (look → telegraph → act), needs/moods are readable from behavior alone. |
| R5 | **Interaction feedback** | Every right-click gives triple feedback: animation + sound + particle/message within 2 ticks; failure cases give a *friendly* denial (sound + bubble), never silence. |
| R6 | **Multiplayer correctness** | Every new synced state verified with the 2-client setup (`runClientMp` + `runClientMp2`): visible to observers, survives relog, no owner-only leaks. |
| R7 | **Persistence** | Save/reload roundtrip GameTest covers every new NBT field; no state resets after restart. |
| R8 | **Performance** | No per-tick allocations in hot paths (aiStep/renderer); new particles/sounds are distance-culled; server tick time of 50 Goobys within +10% of v2.0 baseline. |
| R9 | **i18n & accessibility** | DE+EN parity test green; subtitles complete; no hardcoded strings in Java; new config options documented in both languages. |
| R10 | **Docs & release hygiene** | PATCHNOTES + Handbuch (DE+EN) updated; `versions/` jar present; README feature tables current; rubric filled in the release PR. |

---

## 4. Most Important Current Bugs & Risks

Prioritized. Each entry: **file → what → why it matters**. These are scheduled into v3.0–v3.2.

### P0 — fix in v3.0

1. **`entity/GoobyEntity.java` (`hurt()`, no death handling) — mobs can kill Gooby; hat is destroyed.**
   `hurt()` only blocks *player* damage and escapable environmental damage. A zombie, stray wolf,
   or skeleton kills a tamed companion overnight with no defense goal, no owner notification, and
   no `dropCustomDeathLoot` → the equipped hat item is silently destroyed. For a companion mod
   this is the worst possible player experience ("my Gooby is gone and I don't know why").
2. **`block/NutellaJarBlock.java` (`findClaimingGooby`, 24-block scan) + `entity/GoobyEntity.java` (`remove()`) — claim self-heal can double-spawn.**
   The self-heal frees `CLAIMED` when no claiming Gooby is found within 24 blocks. A claiming Gooby
   that wandered > 24 blocks, or whose chunk unloaded (`remove(UNLOAD)` intentionally keeps the
   claim), still exists → the jar spawns a **second** Gooby for one jar. The 2.0 atomicity fix
   covers the same-tick race but not the cross-chunk lifecycle.
3. **Repo root — release constraints unmet.** No `versions/` folder, no `PATCHNOTES.md`, no
   DE+EN Handbuch. Blocks every future release per the new constraints; must be built first.

### P1 — fix in v3.0–v3.1

4. **`entity/GoobyEntity.java` (`getDeathSound()`) — cheerful squeak on death.** Same sample as the
   happy squeak. If Gooby ever dies (void, `/kill`, P0#1 until fixed), the tone is jarringly wrong.
5. **`entity/GoobyEntity.java` (`hurt()`, satisfaction −3 per hit) — boing-spam griefing.**
   Friendship gain is cooldown-gated but satisfaction *loss* is not: rapid-clicking a Gooby drains
   satisfaction to 0 (removes happy aura + speed) with zero cost to the attacker. Needs the same
   per-player cooldown as `gainFriendship`.
6. **`client/GoobyRenderer.java` (`HatLayer.renderStackForBone`, fixed `translate(0, 0.5, 0)`) —
   floating hat.** The hat offset ignores the animated head pose: while sleeping (head lowered) or
   during pet/eat squash the hat hovers visibly above the model. Should derive from the bone's
   world-space transform or use a dedicated `hat_anchor` locator bone.
7. **`block/RabbitHutchBlock.java` + `entity/goals/GoobySleepGoal.java` — Gooby cannot enter its
   home.** Solid voxel shape (1–15 × 0–13 × 1–15) vs 1.1-wide entity; `fallAsleep` triggers at
   `distToCenterSqr < 4.5`, i.e. *beside* the hutch. README promises cuddling inside. Cosmetic but
   it is the mod's core fantasy ("Zuhause").
8. **`entity/GoobyEntity.java` (`tickRidden` joy-hop) — client/server double audio + desync.**
   `tickRidden` runs on both sides for the controlling rider; `playSound` broadcasts server-side
   (null player → includes rider) *and* plays client-side on the rider's own roll. The rider hears
   doubled/ghost squeaks that nobody else hears.

### P2 — fix opportunistically (scheduled in v3.1–v3.4)

9. **`entity/GoobyEntity.java` (`greetedPlayers`, `lastFriendshipGain`) — unbounded maps.**
   Transient per-entity maps never evict; trivial leak on long-running servers with player churn.
10. **`gametest/GoobyGameTests.java` (`@SuppressWarnings("removal")`,
    `makeMockServerPlayerInLevel`) — deprecated NeoForge test API.** Will break on a NeoForge patch
    bump inside the 21.1 line; isolate behind one helper so the fix is a one-liner.
11. **`.github/workflows/modjar.yml` (`on: push`, no filters, no concurrency) — CI pileup.** Every
    push of every branch runs a full NeoForge build + GameTest server (~15–25 min). Add branch/path
    filters and a `concurrency` group with cancel-in-progress.
12. **`compat/CreateCompat.java` (`degraded` is permanent) — one transient error disables compat
    until restart.** A single `Throwable` (e.g. race on an occupied seat) permanently degrades.
    Distinguish "API shape wrong → permanent" from "runtime hiccup → retry with backoff".
13. **`client/GoobyRenderer.java` (`renderSpeechBubble`) — bubble renders through walls / while
    invisible.** Minor immersion leak; add a line-of-sight or `isInvisible()` check.
14. **`build.gradle` — unused Curios/Modrinth repositories.** Harmless cruft today; either remove
    or (better) actually use them in v3.9 (Curios) and keep documented.
15. **`entity/GoobyEntity.java` (`playSound` override) — every sound is server-broadcast**, even the
    0.1-volume step sound: more network chatter than needed; also bypasses vanilla's own-sound
    optimizations. Audit which sounds truly need global broadcast when doing the v3.2 sound pass.

---

## 5. The 15 Versions

Numbering: `3.0.0 … 3.9.0`, then `4.0.0 … 4.3.0`, finale `5.0.0`. Each is independently shippable
and builds strictly on the previous one. "Rubric+" rows are version-specific pass/fail gates *in
addition to* the global rubric (section 3) and the constraint checklist (section 2).

---

### v3.0.0 — "Release Rails" / DE: „Schienen & Schrauben"

**Theme:** Build the release machine the next 14 versions run on, and kill every P0 bug. No new
gameplay; this version buys trust.

**(a) New features**
- Top-level `versions/` folder + `versions/README.md` index; `scripts/release.py` (parity check →
  build → copy jar as `versions/01-goobymod-3.0.0.jar` → verify PATCHNOTES section exists).
- `PATCHNOTES.md` (player-facing, DE+EN per section) seeded with retroactive 1.0/2.0 summaries.
- `docs/HANDBUCH_DE.md` + `docs/MANUAL_EN.md` v1: getting a Gooby, taming, friendship, whistle,
  gifts, hats, riding, hutch, config reference — with a "Neu in 3.0 / New in 3.0" section pattern.
- **Guardian Angel system** (design decision for P0#1): tamed Goobys become invulnerable to
  non-player mobs as well; instead of taking lethal damage they play `boing`, gain a short
  `panicTicks` state, and at ≤ 30% "pressure" teleport to the owner (or home) with the existing
  portal-plop effect. Wild Goobys keep vanilla vulnerability but get a flee goal (v3.4 expands it).
  Owner gets a chat line if their Gooby had to escape ("Gooby ist zu dir geflüchtet!").
- CI: copy of the built jar attached per release tag; `concurrency` group + branch filters
  (P2#11); workflow renamed step comments in EN.

**(b) Bug fixes (concrete)**
- P0#1 mob-death: `GoobyEntity.hurt()` + new escape path + `dropCustomDeathLoot` override that
  drops the hat if death still occurs (void/`/kill`).
- P0#2 double-spawn: replace the radius scan with a **jar-side UUID lease** — `NutellaJarBlock`
  stores the claiming Gooby's UUID + game-time lease in a small `BlockEntity` (or keep the boolean
  state and persist the lease in `SavedData`); the lease only self-heals after expiry (e.g. 15 min)
  AND entity-lookup-by-UUID fails across the server, not a 24-block AABB.
- P1#4 death sound: dedicated `entity.gooby.sad_whimper` (new asset) wired to `getDeathSound()` and
  the sad state.
- P1#5 boing-spam: per-player satisfaction-loss cooldown mirroring `PET_FRIENDSHIP_COOLDOWN_TICKS`.
- P1#8 riding double-audio: joy-hop rolls server-side only; client plays via the sound event it
  receives.
- P2#9 map eviction: prune `greetedPlayers`/`lastFriendshipGain` entries older than 10 min in the
  existing 20-tick housekeeping branch.

**(c) Polish**
- README updated to the new release layout; `CHANGELOG.md` stays engineering-only.
- Config additions: `protection.goobyMobProtection` (default true, so servers can opt out),
  `protection.escapeToOwner` (default true).

**(d) Model/texture/animation/sound work**
- Sound: synthesize `sad_whimper.ogg` (2 variants) in `scripts/gen_sounds.py`; add to `sounds.json`
  + subtitles (DE+EN).
- No model/animation changes (explicitly — keep the diff reviewable).

**(e) DE+EN localization needs**
- ~10 new keys: `msg.goobymod.escaped_to_owner`, `msg.goobymod.escaped_home`,
  `subtitles.goobymod.sad_whimper`, config docs, Handbuch/PATCHNOTES prose (files, not lang keys).

**(f) Acceptance criteria + Rubric+**
- GameTests (new): `mob_damage_protection` (zombie attack → no HP loss, panic state set),
  `escape_teleport_to_owner`, `hat_drops_on_forced_death`, `jar_lease_no_double_spawn`
  (simulate claimer removal via UUID invalidation → lease persists until expiry),
  `satisfaction_spam_cooldown`, `lang_parity` (loads both JSONs, asserts equal key sets — this is
  constraint C3 automated forever). Total suite ≥ 24 tests, FATAL in CI.
- `versions/01-goobymod-3.0.0.jar` exists and launches on a clean NeoForge 21.1.248 + GeckoLib
  4.9.x client (manual smoke on the 2-client setup).
- Rubric+: [ ] A zombie left alone with a tamed Gooby for 3 in-game nights causes zero deaths.
  [ ] `scripts/release.py` refuses to release with a missing PATCHNOTES section (tested).

---

### v3.1.0 — "Alive & Blinking" / DE: „Lebenszeichen"

**Theme:** Idle micro-life. The version after which nobody calls Gooby "static" again. Pure
creature polish, near-zero gameplay risk.

**(a) New features**
- **Micro-animation layer:** third GeckoLib `AnimationController` ("micro") playing randomized,
  non-looping clips layered over the movement controller: `blink` (every 3–7 s), `ear_twitch`,
  `nose_wiggle` (rabbit sniffing, every 4–10 s while idle), `stretch_yawn` (after waking),
  `tail_wiggle` (when happy). Keyframes only touch bones the base clips leave stable (eyes, ears,
  nose, tail) so layering never fights.
- **Transition clips:** `sit_down`/`stand_up`, `sleep_down`/`wake_up` as `thenPlay` bridges;
  controller state machine in `registerControllers` upgraded from if-chain to a small explicit
  state holder so transitions are deterministic.
- **Landing squash:** `land` one-shot triggered from `causeFallDamage`-adjacent hook
  (`onGround` edge detection) with cloud puff particle for falls > 2 blocks.

**(b) Bug fixes**
- P1#6 floating hat: add `hat_anchor` locator bone to `gooby.geo.json` (child of `head`, pivot on
  the crown); `HatLayer` reads that bone instead of hardcoded +0.5 — hat now follows sleep/pet
  poses exactly.
- P2#13 bubble through walls: skip bubble when `entity.isInvisible()` or no line of sight from
  camera.
- Animation audit: `triggerAnim("actions", …)` calls no longer interrupt each other mid-clip
  (queue or ignore while playing — pick ignore + cooldown, simplest).

**(c) Polish**
- Head-tracking easing: lerp the head-look application in `GoobyModel.setCustomAnimations` so fast
  camera passes don't snap the head.
- Sleeping: eyes closed via texture swap (see (d)) instead of open-eyed sleep.
- Idle body sway amplitude reduced ~15% while a bubble is showing (readability).

**(d) Model/texture/animation/sound work**
- **Model:** add `hat_anchor` locator bone; add `eyelidLeft`/`eyelidRight` planes (or use UV-shift
  blink — decide in Blockbench; eyelid planes preferred, they animate without texture swaps).
- **Texture:** closed-eye + half-lid rows added to `gooby.png` (script `gen_textures.py` extended);
  sleeping face variant.
- **Animations (new clips):** `blink`, `ear_twitch_l/r`, `nose_wiggle`, `stretch_yawn`,
  `tail_wiggle`, `sit_down`, `stand_up`, `sleep_down`, `wake_up`, `land`. All ≤ 20 keyframes,
  documented FPS/length in a new `docs/ANIMATION_GUIDE.md`.
- **Sound:** `yawn.ogg` (1), `sniff.ogg` (2 variants) + subtitles; sound keyframes inside
  `stretch_yawn`/`nose_wiggle` clips via GeckoLib `setSoundKeyframeHandler` (client-side, no
  network cost).

**(e) DE+EN localization needs**
- ~6 keys: subtitles for yawn/sniff, Handbuch section "Goobys Körpersprache / Gooby body language".

**(f) Acceptance criteria + Rubric+**
- GameTests: `micro_controller_never_blocks_movement` (trigger blink then move → hop plays),
  transition state machine unit-style test (state holder is a plain class → testable without
  client), regression suite green.
- Manual 2-client: 5-minute observation recording — blink/ear/nose fire at randomized intervals,
  visible to the *second* client (they are client-random, that's fine — assert they fire locally on
  both).
- Rubric+: [ ] 60-second idle screen recording contains ≥ 8 distinct micro-motions.
  [ ] Hat stays glued to the head in all 9 base animations + all new transitions.
  [ ] No animation hard-cut visible when commanding sit via whistle.

---

### v3.2.0 — "Voice of Gooby" / DE: „Goobys Stimme"

**Theme:** Sound design overhaul. Gooby should be identifiable with eyes closed.

**(a) New features**
- **Variant pools:** every existing event gets 3 variants (`squeak1-3.ogg` etc.) via extended
  `gen_sounds.py` (randomized formant/length seeds); `sounds.json` lists all with weights; runtime
  keeps vanilla's random selection + add ±10% pitch/volume jitter at call sites.
- **Mood-driven ambient:** `getAmbientSound()` picks from happy-trill / neutral-mumble /
  sleepy-mumble pools based on satisfaction & time of day (pool selection server-side, so subtitle
  + sound match).
- **Purr loop while petting:** client-side `AbstractTickableSoundInstance` bound to the pet
  animation window, fading in/out (no server broadcast — pure local sweetener for the petter),
  plus the existing one-shot for bystanders.
- **Item sounds:** whistle gets 3 distinct pitches for Wander/Follow/Stay (players learn the mode
  by ear); brush gets a soft `brush.ogg`.

**(b) Bug fixes**
- P2#15 sound audit: step sound switched to a proper local `playStepSound` (no global broadcast);
  review every `playSound` call for volume/range sanity; snore volume distance-checked.
- Ambient interval: while sleeping the 90-tick snore stays, but ambient interval respects
  `isGoobySleeping` (already null — verify + test).

**(c) Polish**
- Subtitle pass: every sound has a distinct, flavorful subtitle in DE+EN (e.g. "Gooby trillert
  glücklich" / "Gooby trills happily").
- Config: `audio.goobyVolumeScale` (0.0–2.0) master scale for servers with many Goobys.

**(d) Model/texture/animation/sound work**
- **Sounds to synthesize (gen_sounds.py):** squeak×3, purr×3 + purr_loop (seamless), boing×2,
  plop×2, munch×3, snore×2, ambient-neutral×3, ambient-happy×3 (trills), ambient-sleepy×2,
  whistle_wander/follow/stay, brush×2, yawn (reuse), sniff (reuse). ~28 files total.
- Animation: `eat` clip gains sound keyframes for munch layering (jar-clink + munch).

**(e) DE+EN localization needs**
- ~12 subtitle keys + config comment strings; Handbuch section "Klänge verstehen / Reading Gooby's
  sounds" (the whistle-pitch table!).

**(f) Acceptance criteria + Rubric+**
- GameTests: `ambient_pool_matches_mood` (satisfaction high → happy pool key chosen; testable by
  extracting pool selection into a pure function), `whistle_mode_sound_mapping`.
- Manual: blind test — a second player identifies whistle mode changes by ear 5/5 times.
- Rubric+: [ ] No sample repeats twice in a row in a 3-minute petting session recording.
  [ ] Subtitle log (F3+sound debug) shows correct subtitles for all new events.
  [ ] 50-Gooby soak: no audible "machine-gun" stacking (rate-limit verified).

---

### v3.3.0 — "Moods & Needs" / DE: „Launen & Bedürfnisse"

**Theme:** An inner life that players can *read* — the foundation for believable companion AI.

**(a) New features**
- **Mood state machine** (server-authoritative, synced enum): `HAPPY`, `CONTENT`, `HUNGRY`,
  `SLEEPY`, `LONELY`, `SCARED` (SCARED reserved for v3.4). Derived from satisfaction, time since
  last feed (new `lastFedTime` NBT), time of day, owner proximity over time.
- **Readable telltales:** mood drives (1) ambient pool (built in v3.2), (2) micro-anim frequency
  (v3.1 layer — e.g. LONELY = drooped ears via a persistent additive pose clip), (3) idle-line
  category (extend `GoobySpeech` with per-mood pools), (4) particle accents (HUNGRY = occasional
  "nutella thought" bubble particle).
- **Needs feed loop:** feeding when HUNGRY grants +2 bonus friendship ("you noticed!"); petting
  when LONELY grants double satisfaction. Teaches players to read the creature.
- **Shift-look inspection:** sneaking + looking at your own Gooby for 1 s shows a compact
  actionbar status line: `❤ 82 · 😊 Happy · 🎁 2` (icons via font glyphs; no GUI screen yet).

**(b) Bug fixes**
- Satisfaction decay tuning: decay pauses while sleeping (currently drains overnight → morning
  grumpiness contradicts the hutch bonus in `GoobySleepGoal.stop()`).
- `wantsPet` request loop: suppress while mood is SLEEPY (currently begs for pets at 3 AM).

**(c) Polish**
- `GoobySpeech`: mood-context pools (`hungry1-4`, `lonely1-4`, `sleepy1-3`) so bubbles match state;
  pool weighting so context lines beat generic lines when a mood is active.
- Config: `needs.hungerHours` (default 1.5 in-game days), `needs.lonelyMinutes`.

**(d) Model/texture/animation/sound work**
- Animations: `ears_droop` additive pose, `beg` (sits up, paws together — reused for HUNGRY near a
  player holding Nutella), `happy_bounce_in_place`.
- Texture: subtle mood eye variants (sparkle pupils when HAPPY) — optional stretch.
- Sounds: `whine_hungry.ogg`×2, `lonely_sigh.ogg`×2 + subtitles.

**(e) DE+EN localization needs**
- ~20 keys: mood names (`mood.goobymod.*` ×6), status line, 11 new bubble lines ×2 languages,
  subtitles, config comments; Handbuch chapter "Bedürfnisse / Needs".

**(f) Acceptance criteria + Rubric+**
- GameTests: `mood_derivation_pure` (mood function extracted pure → table-driven test of all
  transitions), `hungry_feed_bonus`, `mood_persistence_roundtrip`, `beg_only_when_hungry`.
- Rubric+: [ ] A new player can name Gooby's current mood without UI in a 5-clip blind test
  (internal playtest, 4/5 required). [ ] No mood flapping: minimum dwell time 30 s enforced and
  tested. [ ] Status line renders correctly with DE strings (umlauts, length).

---

### v3.4.0 — "Streetwise Companion" / DE: „Wachsamer Gefährte"

**Theme:** Awareness AI — Gooby behaves like it lives in a dangerous world, and it makes the
*player* safer too.

**(a) New features**
- **Threat awareness:** new `GoobyAlertGoal` — detects hostiles within 12 blocks; SCARED mood, ears
  up `alert` pose, faces the threat, emits `alarm_squeak` (distinct sound), and if the owner is
  within 16 blocks, hops between owner and threat with the `alert` pose (it cannot fight — it
  *warns*). Creeper special case: louder alarm + 2 s earlier detection radius.
- **Self-preservation v2:** wild Goobys get `PanicGoal`-style flee from damage source; tamed Goobys
  extend the v3.0 escape with *pre-emptive* avoidance — pathfinding malus for fire/cactus/powder
  snow via `setPathfindingMalus` in the constructor.
- **Weather sense:** rain → seeks roof/hutch (`shelter` sub-goal), `shake_off_water` animation when
  drying; thunder → SCARED, hides behind owner.
- **Day rhythm:** gentle schedule — morning stretch (after hutch sleep), midday activity peak
  (digs/wanders more), evening wind-down (sits near owner more often). Implemented as goal-weight
  modulation by time-of-day, not new goals.

**(b) Bug fixes**
- P2#10: wrap `makeMockServerPlayerInLevel` in a single `TestPlayers.create(helper)` helper.
- `GoobyFollowOwnerGoal`: verify vanilla teleport target checks (won't land in fire/lava) — add a
  regression test with a lava moat arena.
- `teleportOutOfDanger()`: exclude targets above the void / outside world border (currently only
  fluid/solid checks).

**(c) Polish**
- SCARED bubbles ("E-ein Creeper! HILFE!" / "A-a creeper! HELP!") — 4 lines.
- Alert stance blends with the v3.1 transition system (no pose pop from idle → alert).
- Config: `awareness.creeperAlarm` (default true), `awareness.alertRadius`.

**(d) Model/texture/animation/sound work**
- Animations: `alert` (ears vertical, body low), `shake_off_water`, `hide_behind` micro-clip,
  `shiver` (thunder/freezing).
- Sounds: `alarm_squeak.ogg`×2 (sharp, distinct from happy squeak), `shake.ogg`, subtitles.
- Particles: water droplet burst for shake-off (vanilla splash particles fine).

**(e) DE+EN localization needs**
- ~14 keys: SCARED/alert bubbles, subtitles, config comments; Handbuch chapter "Gooby passt auf
  dich auf / Gooby watches your back".

**(f) Acceptance criteria + Rubric+**
- GameTests: `alert_on_zombie` (zombie spawn → SCARED + alarm within 40 ticks),
  `creeper_early_warning_radius`, `rain_seeks_shelter` (weather-controlled arena),
  `follow_teleport_never_lands_in_lava` (lava moat, 50 iterations), `pathfinding_avoids_fire`.
- Rubric+: [ ] In a staged creeper ambush the alarm fires before the creeper hiss 10/10 times.
  [ ] No alert flicker when a hostile paths in/out of radius (hysteresis tested).
  [ ] 30-Gooby village soak: alert system adds < 0.5 ms/tick (spark profile attached to PR).

---

### v3.5.0 — "Bonds of Trust" / DE: „Bande des Vertrauens"

**Theme:** Make the friendship number *mean* something — tiers, memory, name recognition. Heart of
taming/bonding.

**(a) New features**
- **Friendship tiers** (derived from the existing 0–100 map, no data migration):
  `STRANGER` (0–19), `BUDDY` (20–49), `FRIEND` (50–89), `BEST_FRIEND` (90–100). Tier-up moment:
  hearts + jingle + dedicated bubble + toast-style actionbar.
- **Per-tier unlock table** (documented in Handbuch): BUDDY → Gooby greets you by waving; FRIEND →
  gifts (existing ≥ 50 rule now tier-based), follows you *without* whistle if you sprint past
  (brief "tag-along" impulse), ride unlock moves here (replaces flat ≥ 30 — migration note in
  PATCHNOTES); BEST_FRIEND → golden gifts (existing ≥ 90 rule), exclusive `snuggle` interaction
  (sneak-right-click: Gooby leans against you, regen I for 10 s, once per day per player).
- **Memory moments:** first pet, first feed, tier-ups stored as timestamps ("Erinnerungen" NBT);
  anniversary bubble when a stored moment is ~7 in-game days old ("Weißt du noch…?").
- **Name recognition:** name-tagged Goobys react to their name in chat from their owner (ears
  perk + look at owner) — server chat event listener, cheap contains-check, config-gated.

**(b) Bug fixes**
- Friendship actionbar spam: only show the message on threshold crossings and every ±5, not every
  gain (current `gainFriendship` messages every single +2 pet).
- `RIDE_FRIENDSHIP` constant vs new tier gate — one source of truth (`FriendshipTier.of(int)`),
  regression-tested against the 2.0 GameTests.

**(c) Polish**
- Tier shown in the shift-look status line (v3.3) with tier icon glyph.
- `GoobySpeech` per-tier greeting pools (BEST_FRIEND greetings are noticeably warmer).
- Advancements: `snuggle_time` ("Kuschelzeit" / "Snuggle Time") added under best_friends.

**(d) Model/texture/animation/sound work**
- Animations: `snuggle_lean` (2.5 s loop-in-out), `tier_up_bounce`, `ears_perk`.
- Sounds: `tier_up_jingle.ogg` (short, melodic — the mod's signature sting), `snuggle_purr_long`.
- Particles: custom `heart_gold.png` particle for BEST_FRIEND moments.

**(e) DE+EN localization needs**
- ~30 keys: 4 tier names, tier-up messages, snuggle strings, 12 new bubble lines (tier greetings,
  anniversaries), advancement title/desc, subtitles; Handbuch chapter "Freundschaftsstufen /
  Friendship tiers" with the unlock table.

**(f) Acceptance criteria + Rubric+**
- GameTests: `tier_boundaries_table` (pure function test 0/19/20/49/50/89/90/100),
  `snuggle_once_per_day`, `ride_gate_tier_based_matches_legacy_30`, `memory_persistence`,
  `tierup_fires_exactly_once`.
- Rubric+: [ ] Tier-up moment reads as a celebration (anim+sound+particle+line all within 10
  ticks — frame-checked in a recording). [ ] Old 2.0 worlds load with correct tiers derived from
  existing friendship values (migration test on a copied 2.0 save). [ ] No chat-listener
  performance regression with 100 msgs/s spam test.

---

### v3.6.0 — "Tricks & Training" / DE: „Kunststücke"

**Theme:** The interaction loop players sink hours into — teach, reward, show off. Whistle 2.0.

**(a) New features**
- **Trick training:** new item `training_treat` (crafted: Gooby fluff + sugar + cocoa). With treat
  in hand, sneak-right-click cycles the trick to train (`SPIN`, `HIGH_FIVE`, `FLOP`, `SPEAK`);
  each successful training session (right-click, 3× with cooldown) raises proficiency 0→3
  (persistent per trick). Trained tricks can then be requested bare-handed via a quick radial-less
  UX: double-right-click = last trick; whistle sneak-use opens trick selection (chat-click menu —
  no GUI screen needed, keeps it lightweight).
- **Whistle 2.0:** using the whistle *in the air* (not on the Gooby) calls your nearest owned Gooby
  to you (teleport if > 32 blocks, pathfind otherwise) — the missing "come here" verb. Whistle
  tooltip shows current mode; mode pitch sounds from v3.2 retained.
- **In-game Handbuch item:** `gooby_handbook` (craft: book + Gooby fluff) — written-book-style
  generated content (DE or EN based on client language, via lang keys per page), covering the
  Handbuch chapters. Given automatically on first taming (config-gated).

**(b) Bug fixes**
- `handleWhistle` on non-tamed/foreign Goobys plays the *same* squeak as success — give the denial
  its own lower-pitched sound (interaction feedback rule R5).
- Trick trigger vs micro-layer: ensure `actions` controller priority so tricks never stall
  (extends the v3.1 no-interrupt rule).

**(c) Polish**
- Trick proficiency shown as stars in the shift-look status line.
- `SPEAK` trick = a guaranteed bubble from the general pool + ambient sound (crowd-pleaser).
- Advancements: `first_trick` ("Sitz! Platz! Flauf!" / "Sit! Stay! Floof!"), `all_tricks_mastered`.

**(d) Model/texture/animation/sound work**
- Animations: `trick_spin` (360° with ear lag), `trick_high_five` (paw raise toward camera),
  `trick_flop` (dramatic side flop + tongue), `trick_speak` (head bob), `training_success_hop`.
- Textures: `training_treat.png`, `gooby_handbook.png` item icons.
- Sounds: `trick_chime.ogg` (success), `flop_thud.ogg`, subtitles.

**(e) DE+EN localization needs**
- ~45 keys: 4 trick names + descriptions, training messages (start/progress/mastered/denied),
  whistle-call messages, handbook item name + ~20 handbook page keys ×2 languages, advancements,
  subtitles, config comments.

**(f) Acceptance criteria + Rubric+**
- GameTests: `training_proficiency_progression`, `trick_request_requires_training`,
  `whistle_air_call_teleports_beyond_32`, `whistle_denial_foreign_gooby`,
  `handbook_given_once_on_tame`.
- Rubric+: [ ] Full training loop (0→mastered→perform) completable in < 5 min and feels rewarding
  (playtest sign-off). [ ] Handbook renders correctly in DE (umlauts, page overflow) and EN.
  [ ] Trick animations never slide feet (root motion locked, frame-checked).

---

### v3.7.0 — "Hutch, Sweet Hutch" / DE: „Traumstall"

**Theme:** Fix the home fantasy properly — Gooby visibly lives somewhere. (Scheduled before babies
so the family version has a nest to build on.)

**(a) New features**
- **Hutch 2.0:** `RabbitHutchBlock` becomes a `BlockEntity` block with an open entrance in the
  voxel shape (south face opening, 8×8), interior render (Gooby curls inside — entity snaps to a
  `sleep_in_hutch` anchor pose when sleeping at home). Upgradeable bedding: right-click with wool →
  comfort level 1–3 (visible bedding texture layers; higher comfort = faster satisfaction regen at
  wake, morning gift chance at comfort 3).
- **Nameplate:** right-click hutch with a name tag → hutch shows the resident's name (sign-style
  text render); binds hutch ↔ Gooby explicitly (removes the fuzzy `findHutch` radius search for
  bound pairs).
- **Wake-up routine:** morning sequence — hutch exit hop, `stretch_yawn` (v3.1), happy trill,
  then patrol to owner if online. A tiny scripted vignette players will screenshot.

**(b) Bug fixes**
- P1#7 fully resolved: entrance + interior anchor replaces "sleeps beside the box".
- `GoobySleepGoal.findHutch` — bound hutch has absolute priority; the 48-block home distance check
  removed for bound pairs (Gooby *travels* home at dusk if within 96 blocks, else sleeps rough with
  a lonely line — feeds the LONELY mood).
- Hutch break while occupant sleeps: Gooby pops out safely (no suffocation), home cleared, sad line.

**(c) Polish**
- Zzz particles emit from the hutch entrance when occupied (visible occupancy cue).
- Loot table: hutch drops bedding wool on break.
- Config: `home.duskTravelRadius`.

**(d) Model/texture/animation/sound work**
- **Model:** hutch gets a proper block model with entrance + 3 bedding overlay models; Gooby
  `sleep_curl_tight` variant animation (tighter than freestanding sleep, fits interior).
- **Textures:** hutch interior/bedding (3 levels), nameplate area; block item updated.
- **Animations:** `hutch_enter` (hop-in with squash — the money shot), `hutch_exit`,
  `sleep_curl_tight`.
- **Sounds:** `hutch_rustle.ogg` (enter/exit), `hutch_creak.ogg`, morning trill reuse; subtitles.

**(e) DE+EN localization needs**
- ~16 keys: bedding messages, nameplate messages, break/sad lines, subtitles, config; Handbuch
  chapter "Ein Zuhause für Gooby / A home for Gooby" rewritten.

**(f) Acceptance criteria + Rubric+**
- GameTests: `hutch_entrance_pathable` (Gooby navigates *into* the hutch bounding box),
  `bedding_upgrade_levels`, `bound_hutch_priority`, `hutch_break_ejects_safely`,
  `comfort3_morning_gift`, persistence roundtrip for BlockEntity data.
- Rubric+: [ ] The dusk→enter→sleep→dawn→exit cycle runs unattended for 3 in-game days without a
  single pathing failure (time-lapse recording). [ ] Hutch renders correctly from all 4 facings
  with all 3 bedding levels. [ ] Old worlds: existing hutches upgrade in place (block state
  migration test on a 2.0 save).

---

### v3.8.0 — "Little Goobys" / DE: „Gooby-Nachwuchs"

**Theme:** Baby Goobys — the cuteness multiplier, built on hutch + bonding foundations.

**(a) New features**
- **The Nutella-cake ritual (breeding-lite):** two adult tamed Goobys (any owners) near a placed
  cake with a Nutella jar used on it ("Nutella-Kuchen") enter love mode → one baby Gooby. No
  vanilla `isFood` breeding (keeps `isFood() == false` and the no-endless-breeding design); 1
  baby per pair per day, requires both at FRIEND+ tier with their owners (bond quality gates
  offspring — thematic).
- **Baby behavior:** 0.55 scale (GeckoLib `withScale` / render scale), follows a parent
  (`follow_parent` goal), higher-pitch sounds (+0.4 voice pitch), extra-frequent micro-anims,
  cannot be ridden, wears no hats (too small — denial line), grows up in 1.5 in-game days
  (accelerable with training treats).
- **Family AI:** parents sleep adjacent to the baby's hutch spot; baby "tag" play — short chase
  bursts between baby and parent (pure flavor goal, low priority).

**(b) Bug fixes**
- `getBreedOffspring` currently returns null — implement properly for the ritual path while
  keeping vanilla breeding disabled; audit `AgeableMob` age serialization (baby persists as baby).
- Ensure `GoobyFollowOwnerGoal`/whistle ignore babies (they follow parents, not commands) —
  friendly denial line.

**(c) Polish**
- Baby-specific bubble pool (simpler, sillier lines — 6 lines).
- `gooby_ride` and trick goals gated to adults with proper messages.
- Advancement: `gooby_family` ("Familienglück" / "Family Bliss").

**(d) Model/texture/animation/sound work**
- **Model:** baby proportion overrides — bigger head ratio via dedicated `gooby_baby.geo.json`
  (head 1.3×, ears 0.8× — babies are not just scaled adults; this is the polish difference).
- **Animations:** `baby_hop` (higher frequency, clumsier), `baby_tumble` (occasional face-plant on
  landing — guaranteed clip-worthy), `parent_nuzzle`, `grow_up_pop`.
- **Sounds:** baby squeak set ×3 (pitched + shortened variants generated separately, not runtime
  pitch only), `nuzzle.ogg`; subtitles.
- **Texture:** baby texture (softer markings, bigger eye UVs); Nutella-cake block texture overlay.

**(e) DE+EN localization needs**
- ~22 keys: ritual messages, baby denial lines, baby bubbles ×6, advancement, subtitles, config
  (`family.growthTicks`, `family.ritualCooldown`); Handbuch chapter "Nachwuchs / Offspring".

**(f) Acceptance criteria + Rubric+**
- GameTests: `ritual_spawns_one_baby` (atomicity — mirrors the jar lease lesson),
  `ritual_requires_friend_tier`, `baby_growth_timing`, `baby_ignores_whistle`,
  `baby_persistence_roundtrip`, `no_vanilla_breeding_via_food`.
- Rubric+: [ ] Baby reads as *baby* at a glance (proportion check vs adult side-by-side
  screenshot). [ ] `baby_tumble` triggers ≤ 1/min (charming, not slapstick spam).
  [ ] Ritual cannot be exploited for infinite Goobys (cooldown + pair-tracking test).

---

### v3.9.0 — "Fashion Fluff" / DE: „Mode & Fussel"

**Theme:** Wardrobe depth + visual identity per Gooby. Cosmetic economy for Gooby fluff.

**(a) New features**
- **Accessory slots:** head (existing hats) + **neck** (new: scarves, bowties) + **back** (new:
  tiny satchel — cosmetic now, functional in v4.3). Items: `gooby_scarf` (craft: 3 wool + fluff,
  dyeable via vanilla dye recipe → 16 colors), `gooby_bowtie`, `tiny_satchel`. Sync mirrors the
  proven `DATA_HAT` string pattern → generalize into a small `GoobyWardrobe` synced component
  (one string with slot map, or three accessors — pick three accessors, simplest to sync/test).
- **Hat expansion:** all small flowers + dyed wool carpets as beanies; hat list moves from the
  hardcoded `HAT_ITEMS` set to an item tag `#goobymod:gooby_hats` (data-driven, pack-extendable).
- **Coat variants:** brushing at BEST_FRIEND tier occasionally (5%) grants a `shimmer_fluff`;
  using 4 shimmer fluff on your Gooby unlocks a coat variant (cream / cocoa / spotted) — permanent,
  switchable via brush sneak-click cycle. Stored as synced byte; texture swap in `GoobyModel`.
- **Curios compat (optional dep):** if Curios is installed, the Gooby whistle is equippable in a
  charm slot (the repo already declares the Curios maven — now it earns its place; same
  reflection-and-degrade pattern as CreateCompat, or compileOnly dep — choose compileOnly with
  `ModList.isLoaded` guard: cleaner than reflection, still no hard dependency).

**(b) Bug fixes**
- P2#14: `build.gradle` repositories cleanup — Curios repo now used; Modrinth exclusiveContent
  documented or removed.
- Hat handling with wardrobe: shears now strip *all* accessories with one clear message listing
  dropped items (previously hat-only).

**(c) Polish**
- Wardrobe state in shift-look status line (small glyphs).
- Dye interaction feedback: color-matched particle puff on scarf dye.
- Advancement: `full_outfit` ("Herausgeputzt" / "Dressed to the Nines").

**(d) Model/texture/animation/sound work**
- **Model:** `neck_anchor` + `back_anchor` locator bones (as with `hat_anchor` in v3.1); scarf as a
  geo attachment rendered via a second `BlockAndItemGeoLayer`-style custom layer (flat item models
  look bad on the neck — build tiny geo models for scarf/satchel: `scarf.geo.json`,
  `satchel.geo.json`).
- **Textures:** scarf (16 dye tints via layer tinting — one grayscale base), bowtie, satchel,
  3 coat variant textures (`gooby_cream.png`, `gooby_cocoa.png`, `gooby_spotted.png` — script-
  generated recolors + hand-tuned markings), `shimmer_fluff.png` item.
- **Animations:** none new required; verify scarf bones inherit hop/sleep motion cleanly.
- **Sounds:** `dress_up.ogg` (soft fabric), reuse shear sound; subtitles.

**(e) DE+EN localization needs**
- ~28 keys: 4 item names, wardrobe messages, coat variant names, denial lines, advancement,
  subtitles, tag-driven hat tooltip; Handbuch chapter "Goobys Garderobe / Gooby's wardrobe".

**(f) Acceptance criteria + Rubric+**
- GameTests: `wardrobe_sync_and_persist` (all 3 slots), `hat_tag_driven` (datapack-added hat item
  works), `coat_variant_unlock_and_persist`, `shears_strip_all_slots`, `curios_absent_no_crash`.
- Manual 2-client: full outfit visible to second client + after relog.
- Rubric+: [ ] Scarf deforms plausibly during hop/sleep (no clipping in the 4 key poses,
  screenshot grid). [ ] All 16 scarf colors render distinctly (colorblind check: at least
  value-differentiated). [ ] With Curios installed: whistle works from charm slot; without: zero
  log noise.

---

### v4.0.0 — "Create Express" / DE: „Create-Express"

**Theme:** The cross-mod flagship. Create integration goes from "can sit on a seat" to "belongs in
a Create world". Major version bump: first version with a compile-visible optional dependency.

**(a) New features**
- **Compile-time Create API usage:** add Create as `compileOnly` dependency (Modrinth maven already
  configured); keep ALL calls behind `ModList.isLoaded("create")` + a single `CreateBridge`
  isolation class (same degrade philosophy, now with typed code instead of reflection — the
  reflection path stays as fallback for API drift, preserving the 2.0 safety property).
- **Contraption passenger:** Gooby seated on a Create seat that becomes a contraption (train,
  gantry) stays seated and renders correctly during assembly/disassembly; owner gets a bubble on
  arrival ("Sind wir schon da?"). Explicit GameTest with a moving bearing contraption.
- **Nutella industrialization:** Create-only recipes — Mixer: milk fluid + 3 cocoa + sugar →
  Nutella jar (bulk path that doesn't invalidate the handcraft); Spout: fill empty jar item (new
  `empty_jar` item, also purchasable back from crafting). Recipes in `data/goobymod/recipe/create/`
  with `neoforge:conditions` on mod-loaded → zero impact without Create.
- **Depot naps:** a Gooby whose STAY point is near a running Create machine gains a "cozy machine
  hum" satisfaction trickle (Goobys love vibrations — flavor synergy) + unique idle lines about the
  machinery (6 lines).
- **Whistle + trains:** whistle-call (v3.6) refuses politely if Gooby is on a moving contraption
  ("Ich fahre gerade Zug!").

**(b) Bug fixes**
- P2#12: degrade semantics split — `PERMANENT_API_MISMATCH` vs `TRANSIENT` (3 retries with
  backoff); GameTest simulates a transient throw and asserts recovery.
- `isSeatFree` entity-class-name check replaced by typed check when compileOnly API available.

**(c) Polish**
- `CreateCompat` diagnostics: one INFO line at startup stating detected Create version + active
  integration level (helps bug reports).
- Handbuch: dedicated Create chapter with the mixer recipe diagram.

**(d) Model/texture/animation/sound work**
- Animations: `seated_contraption_idle` (relaxed sway matched to contraption motion — subtle),
  `train_lean` micro-clip.
- Textures: `empty_jar.png` item.
- Sounds: none new (reuse); verify sound attenuation while on fast contraptions.

**(e) DE+EN localization needs**
- ~16 keys: empty jar, recipe JEI-ish tooltips, contraption bubbles ×6, refusal lines, log-free
  user messages; Handbuch Create chapter.

**(f) Acceptance criteria + Rubric+**
- GameTests: `create_absent_all_features_dormant` (run in default CI without Create),
  plus a **second CI job** `modjar-create.yml` matrix leg that adds Create via Modrinth maven and
  runs `contraption_keeps_gooby_seated`, `mixer_nutella_recipe`, `transient_degrade_recovers`.
- Rubric+: [ ] Jar built without Create in classpath still classloads all mod classes
  (no `NoClassDefFoundError` — verified by the default CI leg). [ ] Gooby on a moving train for
  5 min: no desync, no dismount, seated anim plays (recording). [ ] Mixer recipe appears/disappears
  correctly with/without Create (conditions test).

---

### v4.1.0 — "Out in the Wild" / DE: „Wilde Welt"

**Theme:** World presence — Goobys exist in the world before the player makes one.

**(a) New features**
- **Rare natural spawns:** wild Goobys spawn in flower forests, cherry groves, meadows (biome tag
  `#goobymod:has_wild_goobys`), CREATURE category, very low weight, config `worldgen.wildSpawns`
  (default on, servers can disable). Wild Goobys are shyer: flee radius from non-owner players
  until fed once.
- **Gooby burrow (worldgen structure):** small surface burrow (mound + tunnel + cozy chamber with
  a nutella-jar loot cache) via jigsaw/structure JSON in `data/goobymod/worldgen/`; spawns a wild
  Gooby with a `homePos` at the chamber. Uses the existing `gen_structure.py` pipeline for NBT
  authoring.
- **Footprints & dig holes:** temporary footprint particles on soft ground (snow/sand leave actual
  vanilla-style transient marks — particle-only, no block changes); dig sites leave a small
  `dug_dirt` decal block that decays in 2 min (visual history of Gooby activity).
- **Fauna reactions:** rabbits follow wild Goobys (big sibling!), cats are sus (stare), wolves
  trigger the v3.4 alert. Pure goal/flavor wiring on existing systems.

**(b) Bug fixes**
- `removeWhenFarAway` returns false for ALL Goobys — correct for tamed, but natural-spawned wild
  Goobys must despawn normally or meadows fill up (`removeWhenFarAway = !isTame() && !hasCustomName()`
  for naturally spawned ones; conversion/jar Goobys keep persistence via `setPersistenceRequired`).
- Spawn-egg Goobys: verify `finalizeSpawn` paths set satisfaction consistently (jar path sets 70
  via convert, egg path uses default 40 — unify).

**(c) Polish**
- Burrow loot table: fluff, carrots, one nutella jar (the starter-kit fantasy).
- Wild Gooby bubbles: 5 shy lines (only after first feed: normal pools).
- Advancement: `found_burrow` ("Wer wohnt denn hier?" / "Who lives here?").

**(d) Model/texture/animation/sound work**
- Textures: `dug_dirt` decal block, burrow interior blocks reuse vanilla; footprint particle
  texture (`paw_print.png`).
- Animations: `shy_peek` (wild Gooby watching from distance — ears half-down).
- Sounds: distant ambient `wild_call.ogg` (lets players *find* burrows by ear, 32-block range).

**(e) DE+EN localization needs**
- ~14 keys: biome/structure names where surfaced, shy lines, advancement, subtitles, config;
  Handbuch chapter "Wilde Goobys & Baue / Wild Goobys & burrows".

**(f) Acceptance criteria + Rubric+**
- GameTests: `wild_despawn_rules` (natural wild despawns; tamed & converted never),
  `burrow_gooby_has_home`, `shy_until_fed`; structure placement smoke test via
  `/place structure` in a GameTest arena.
- Manual: locate 3 burrows in a fresh world within 30 min using `wild_call` audio (tuning check).
- Rubric+: [ ] Spawn rates: ≤ 2 wild Goobys per 1000×1000 blocks exploration sample (they must
  stay special). [ ] Burrow never generates floating/buried beyond tolerance in 20 sampled seeds.
  [ ] Zero despawn of any player-associated Gooby across a 3-night AFK soak (log instrumented).

---

### v4.2.0 — "Gooby & Friends" / DE: „Soziale Goobys"

**Theme:** Multi-Gooby social behavior + richer expression toward players. The world's Goobys feel
like a community.

**(a) New features**
- **Gooby-to-Gooby social AI:** when two Goobys meet: greeting bounce ritual (synchronized via a
  tiny handshake — initiator entity-data flag, partner mirrors), occasional play-chase (bounded
  30 s, cooldown 5 min/pair), synchronized napping (nap magnetism: a sleeping Gooby lowers the
  sleep threshold of nearby Goobys), gift-sharing (a Gooby with charges may gift *another Gooby* —
  purely cosmetic exchange with heart particles).
- **Player emote reactions:** sneak-bowing at your Gooby (sneak toggled 2× within 1 s while
  looking at it) → Gooby bows back (`bow` anim); jumping repeatedly near a HAPPY Gooby → it joins
  with `happy_bounce`. Detection server-side via pose/jump tracking, radius 6.
- **Speech bubble v2:** emoji-style icon glyphs in bubbles via custom font provider
  (`assets/goobymod/font/icons.json` — heart, nutella, zzz, alarm icons usable inline in lang
  strings), bubble tail points at the addressed player, gentle pop-in/out scale animation
  (renderer interpolation, no new network data).
- **Photo-op advancement:** `group_nap` ("Flauschhaufen" / "Fluff pile") — 3+ Goobys sleeping
  within 3 blocks.

**(b) Bug fixes**
- Bubble overlap: two adjacent Goobys' bubbles now vertically stagger (renderer offset by entity
  id hash) instead of z-fighting.
- Social goals strictly LOW priority — GameTest asserts follow/stay/sleep always win (command
  obedience is sacred).

**(c) Polish**
- Idle lines referencing nearby named Goobys ("%s ist mein bester Flauschfreund!").
- Group-nap Zzz particles merge into one bigger Zzz (cute detail).
- Config: `social.playChase` (some servers will want it off), `social.emoteReactions`.

**(d) Model/texture/animation/sound work**
- Animations: `greeting_bounce` (2-phase: initiator + mirror), `play_chase_lunge`, `bow`,
  `happy_bounce` (already partially exists as bounce-in-place from v3.3 — extend), `nap_huddle`
  (sleep variant leaning toward neighbor).
- Font: `icons.png` glyph atlas + font provider JSON.
- Sounds: `chirp_social.ogg`×2 (Gooby-to-Gooby only — distinct register), subtitles.

**(e) DE+EN localization needs**
- ~18 keys: social bubbles ×8, emote feedback, advancement, subtitles, config comments; Handbuch
  chapter "Goobys unter sich / Goobys among themselves" + emote how-to.

**(f) Acceptance criteria + Rubric+**
- GameTests: `greeting_ritual_synchronizes`, `social_never_overrides_stay`,
  `play_chase_terminates_and_cooldowns`, `group_nap_advancement`, `bow_detection_window`.
- Rubric+: [ ] 4-Gooby pen observed 10 min: ≥ 3 distinct social behaviors occur, zero goal
  deadlocks (recording). [ ] Bubble icons render at all GUI scales 1–4 without blur.
  [ ] Emote detection has zero false positives during normal parkour near a Gooby (playtest).

---

### v4.3.0 — "Treasure Trails" / DE: „Schatzsucher"

**Theme:** Gooby as adventure buddy — the satchel becomes functional, digging becomes a game.

**(a) New features**
- **Functional satchel:** the v3.9 `tiny_satchel` accessory gains 4 slots (menu via sneak-use of
  the brush? No — right-click satchel *item* on Gooby opens a minimal 4-slot container GUI, owner
  only). Gooby auto-stashes its own dug gifts into the satchel when the recipient is > 10 blocks
  away (gifts stop rotting on the ground).
- **Sniff & Seek:** with FRIEND+ tier and a `training_treat`, the owner can show Gooby an item
  (right-click with it while sneaking) → Gooby sniffs (`sniff_seek` anim) and, if a matching block
  is within 24 blocks underground (ores config-gated to "cozy" targets by default: only carrots,
  buried treasure-ish loot; optional `seek.allowOres` for servers that want truffle-pig gameplay),
  hops toward it and digs a marker hole. Cooldown 5 min.
- **Treasure trails:** rare dig outcome (charged + BEST_FRIEND): a `torn_map_scrap`; 4 scraps craft
  a `gooby_treasure_map` pointing to a small buried cache (loot table: cosmetics, shimmer fluff,
  nutella). Uses vanilla map decoration API — no custom world scanning beyond one structure
  locate.
- **Backpack fashion payoff:** satchel contents drop safely on Gooby "death"/escape (there is no
  real death for tamed ones post-3.0 — escape drops nothing, contents persist; test the edge).

**(b) Bug fixes**
- Gift economy audit: charges/cooldown interplay with satchel stashing (no dupe via
  stash-then-drop; GameTest hammering).
- `spawnAtLocation` item ownership: dug gifts get 10 s pickup priority for the intended recipient
  (thrower-style tag) — fixes "another player yoinks the gift" complaint-in-waiting.

**(c) Polish**
- Seek success celebration: `trick_chime` + trail of paw-print particles from Gooby to the find.
- Map scrap flavor text (lore lines, DE+EN).
- Advancements: `treasure_map_complete`, `satchel_full`.

**(d) Model/texture/animation/sound work**
- Animations: `sniff_seek` (nose to ground, sweeping), `dig_excited` (faster dig variant),
  `present_item` (offers satchel content to owner).
- Textures: `torn_map_scrap.png`, `gooby_treasure_map.png`, satchel GUI (4-slot minimal),
  paw-print particle reuse from v4.1.
- Sounds: `sniff_long.ogg`, `map_rustle.ogg`; subtitles.

**(e) DE+EN localization needs**
- ~24 keys: satchel GUI title, seek messages (start/found/nothing), map items + lore, advancement,
  subtitles, config (`seek.allowOres`, `seek.cooldown`); Handbuch chapter "Auf Schatzsuche /
  Treasure hunting".

**(f) Acceptance criteria + Rubric+**
- GameTests: `satchel_persistence_and_owner_gate`, `seek_finds_planted_target`,
  `seek_respects_cooldown`, `gift_recipient_pickup_priority`, `no_dupe_satchel_stash_cycle`,
  `map_scrap_drop_rate_bounds` (statistical, seeded RNG).
- Rubric+: [ ] Full loop demo: train → seek → dig → map → cache in one 10-min recording without
  dev commands (except time-set). [ ] Satchel GUI usable with mouse + keyboard-only.
  [ ] Seek is useless-feeling-proof: "nothing found" case gives a charming consolation line, never
  silence (R5).

---

### v5.0.0 — "Grand Polish LTS" / DE: „Hochglanz"

**Theme:** The long-term-support finale: performance, accessibility, QA saturation, addon API,
and the definitive Handbuch. No new gameplay systems — everything existing is sanded to a shine.

**(a) New features**
- **Addon API surface:** tiny, documented `de.sonic0810.goobymod.api` package — events
  (`GoobyTameEvent`, `GoobyTierChangeEvent`, `GoobyGiftEvent`), registration hooks for hat tag /
  speech pools (datapack + code), stable `GoobyEntity` accessor interface. Semver promise
  documented in README ("API frozen within 5.x").
- **In-game Handbuch 2.0:** the v3.6 handbook item upgraded to a paged, illustrated custom screen
  (chapter icons, animated Gooby portrait on the cover page), fully lang-key driven, DE+EN.
- **Accessibility pack:** `accessibility.reducedMotion` (dampens micro-anims + camera-independent
  bubbles), `accessibility.highContrastBubbles`, full subtitle verification, whistle modes also
  shown as actionbar icons (audio-independent).
- **Performance program:** Gooby LOD — micro-anim controller and particle accents suspend beyond
  24 blocks / when not rendered; sound rate-limiter per chunk; `friendship` map bounded (top 32
  relationships + owner, LRU eviction with PATCHNOTES note); renderer allocation audit.

**(b) Bug fixes**
- Sweep of the entire P2 backlog remnants + every issue found during v3.x/v4.x playtests
  (dedicated triage milestone; zero known-issue release).
- CI: pin exact GeckoLib + (matrix) Create versions used per release in `versions/README.md`
  (reproducibility).

**(c) Polish**
- Final texture pass: consistent palette + outline treatment across all 30+ item/block textures.
- Final animation timing pass with 20% playback-speed review of every clip (nothing floats,
  nothing pops).
- Final speech audit: every pool ≥ 4 lines, no near-duplicates, DE not a literal EN translation
  but idiomatic (and vice versa).
- README + Handbuch final restructure; trailer-ready demo world saved under `docs/demo_world/`
  (creative showcase of all features).

**(d) Model/texture/animation/sound work**
- No *new* clips; re-export all animations after the timing pass; bake final sound mastering pass
  (loudness normalization to vanilla creature levels, verified with a level meter).
- Handbook illustrations (12–16 small PNGs, script-assisted from posed screenshots).

**(e) DE+EN localization needs**
- ~30 keys: handbook 2.0 chapters, accessibility config, API docs strings; full-file proofread of
  both lang files by a human (final QA gate).

**(f) Acceptance criteria + Rubric+**
- GameTest suite ≥ 70 tests, all green, FATAL; matrix CI (vanilla + Create leg) green.
- Performance: 100-Gooby stress world ≤ 5% server tick budget on the reference machine; client
  FPS within 10% of vanilla-mob-equivalent scene (numbers recorded in PATCHNOTES).
- Rubric: **20/20 required** for this release (no criterion below 2), plus:
  [ ] Full Handbuch read-through in both languages with zero errors.
  [ ] A brand-new player reaches "tamed + first trick + hutch home" in under 30 minutes using
  only the in-game handbook (moderated playtest).
  [ ] `versions/` contains all 15 jars, numbered 01–15, each launch-verified.

---

## 6. Prioritized Idea Backlog

Ideas *not* scheduled above, ordered by (player value ÷ effort). Pull from the top when a version
lands early; push scheduled items here if a version runs hot.

**High priority (strong candidates to swap in):**
1. **Gooby carry** — pick your (small/baby) Gooby up on your shoulder/arms (pose + carried anim);
   massive cuteness ROI, moderate render complexity.
2. **Nutella toast** — spreadable food item (bread + jar); shared bite with Gooby doubles
   satisfaction gain; eat-together anim.
3. **Sitting on Gooby wool couch** — wool block becomes sittable (half-slab seat behavior);
   Gooby joins you (couch magnetism).
4. **Weather cosmetics** — tiny umbrella hat item (rain), snow hat; seasonal ear muffs.
5. **JEI/EMI recipe integration** — recipe category for the Nutella + Create paths (compat tier 2).
6. **Gooby statue block** — craft from wool + fluff; decorative petrified pose selection.

**Medium priority:**
7. Jade/WTHIT tooltip plugin (mood + tier at a glance) — compat tier 2.
8. Gooby-themed paintings (2–3 vanilla painting variants via datapack).
9. Waypoint hutch — whistle triple-click sends Gooby home from anywhere (loaded chunks only).
10. Nutella golem — april-fools-grade easter egg boss-pet (huge scope, pure fun).
11. Gooby sounds resource-pack override guide (docs) for community sound packs.
12. Localized Sophie-style *configurable* special lines: server owners can define their own
    name-bound cosmetic lines via datapack (generalizes the hardcoded pool; keeps the killswitch).

**Low priority / parked:**
13. Gooby minecart & boat riding poses (fiddly vanilla seat math).
14. Shoulder parrot-style perch for baby Goobys (collides with carry idea — pick one).
15. Gooby plushie item (renders as handheld mini-Gooby) — merch energy.
16. Aquatic float ring — Gooby swims confidently with a swim ring accessory (new swim goals).
17. Cross-mod: Farmer's Delight nutella cutting/spreading recipes.
18. Cross-mod: Supplementaries rope/pulley interactions for the hutch.

---

## 7. Master Asset List to Create

Consolidated from sections 5(d). Owner: `scripts/gen_*` pipeline first, hand-polish in Blockbench
where noted. **Bold = hand-authoring required.**

### Geometry (`assets/goobymod/geo/`)
| Asset | Version | Notes |
|---|---|---|
| `gooby.geo.json` — add `hat_anchor`, eyelid planes | 3.1 | **Blockbench**; keep UV layout stable |
| `gooby.geo.json` — add `neck_anchor`, `back_anchor` | 3.9 | locator bones only |
| **`gooby_baby.geo.json`** | 3.8 | re-proportioned, not scaled |
| **`scarf.geo.json`**, **`satchel.geo.json`** | 3.9 | attachment mini-models |
| Hutch block model with entrance + 3 bedding overlays | 3.7 | JSON block models |

### Textures (`assets/goobymod/textures/`)
| Asset | Version |
|---|---|
| `gooby.png` closed/half-lid eye rows, sleep face | 3.1 |
| Mood eye variants (sparkle) — stretch | 3.3 |
| `gooby_cream.png`, `gooby_cocoa.png`, `gooby_spotted.png` coat variants | 3.9 |
| Baby texture | 3.8 |
| Items: `training_treat`, `gooby_handbook`, `empty_jar`, `gooby_scarf` (grayscale+tint), `gooby_bowtie`, `tiny_satchel`, `shimmer_fluff`, `torn_map_scrap`, `gooby_treasure_map` | 3.6–4.3 |
| Blocks: hutch interior/bedding ×3, `dug_dirt` decal, nutella-cake overlay | 3.7–4.1 |
| Particles: `paw_print.png`, `heart_gold.png` | 3.5/4.1 |
| Font glyph atlas `icons.png` + provider JSON | 4.2 |
| Handbook GUI + 12–16 illustrations | 3.6/5.0 |

### Animations (`assets/goobymod/animations/gooby.animation.json` + baby file)
| Clip | Version |
|---|---|
| `blink`, `ear_twitch_l/r`, `nose_wiggle`, `stretch_yawn`, `tail_wiggle`, `sit_down`, `stand_up`, `sleep_down`, `wake_up`, `land` | 3.1 |
| `ears_droop` (additive), `beg`, `happy_bounce_in_place` | 3.3 |
| `alert`, `shake_off_water`, `hide_behind`, `shiver` | 3.4 |
| `snuggle_lean`, `tier_up_bounce`, `ears_perk` | 3.5 |
| `trick_spin`, `trick_high_five`, `trick_flop`, `trick_speak`, `training_success_hop` | 3.6 |
| `hutch_enter`, `hutch_exit`, `sleep_curl_tight` | 3.7 |
| `baby_hop`, `baby_tumble`, `parent_nuzzle`, `grow_up_pop` | 3.8 |
| `seated_contraption_idle`, `train_lean` | 4.0 |
| `shy_peek` | 4.1 |
| `greeting_bounce`, `play_chase_lunge`, `bow`, `nap_huddle` | 4.2 |
| `sniff_seek`, `dig_excited`, `present_item` | 4.3 |

### Sounds (`assets/goobymod/sounds/entity/gooby/` + items; all via `gen_sounds.py`, +subtitles DE+EN)
| Asset | Version |
|---|---|
| `sad_whimper` ×2 | 3.0 |
| `yawn`, `sniff` ×2 | 3.1 |
| Variant pools: squeak×3, purr×3+loop, boing×2, plop×2, munch×3, snore×2, ambient neutral×3 / happy×3 / sleepy×2; `whistle_wander/follow/stay`, `brush`×2 | 3.2 |
| `whine_hungry`×2, `lonely_sigh`×2 | 3.3 |
| `alarm_squeak`×2, `shake` | 3.4 |
| `tier_up_jingle`, `snuggle_purr_long` | 3.5 |
| `trick_chime`, `flop_thud` | 3.6 |
| `hutch_rustle`, `hutch_creak` | 3.7 |
| Baby squeak set ×3, `nuzzle` | 3.8 |
| `dress_up` | 3.9 |
| `wild_call` | 4.1 |
| `chirp_social`×2 | 4.2 |
| `sniff_long`, `map_rustle` | 4.3 |
| Final mastering pass, all files | 5.0 |

### Structures & data
| Asset | Version |
|---|---|
| Burrow jigsaw/structure NBT + loot tables | 4.1 |
| Item tag `#goobymod:gooby_hats`, biome tag `#goobymod:has_wild_goobys` | 3.9/4.1 |
| Create-conditional recipes | 4.0 |
| Demo world `docs/demo_world/` | 5.0 |

---

## 8. Localization Strategy (DE+EN)

1. **Parity is law (C3):** the `lang_parity` GameTest from v3.0 makes EN⇄DE divergence a CI
   failure forever. Currently 114/114 keys match — keep it that way.
2. **DE is a first-class language, not a translation:** speech-bubble lines are written natively
   per language (the current files already do this well — e.g. "Fussel-komprimiert" vs
   "fluff-compressed"). Rule: puns may differ, *meaning* and *count* must match.
3. **Sophie special lines** stay German in both files by design (proper-noun-bound); document this
   exception in a lang-file header comment key (`_comment` keys are tolerated by the parser via
   the parity test's allowlist — or document in `docs/` instead; choose docs to keep files clean).
4. **Growth estimate:** ~114 keys today → ~420 keys by v5.0 (per-version counts in section 5(e)).
   Keep pool keys strictly patterned (`bubble.goobymod.<pool><n>`) so `GoobySpeech.keys()` stays
   the single source of pool sizes; add a GameTest asserting every `GoobySpeech` pool key exists
   in both lang files (catches "added key 5 of 4" mistakes).
5. **Handbuch:** `docs/HANDBUCH_DE.md` and `docs/MANUAL_EN.md` are sibling documents updated in the
   same commit (release script checks both files' version headers). In-game handbook pages are
   lang-key driven → automatically bilingual.
6. **Subtitles:** every `sounds.json` entry must carry a subtitle key; audited by a GameTest from
   v3.2 (parse sounds.json, assert subtitle keys exist in both langs).

---

## 9. Testing & Release Engineering Strategy

**Per-version cadence (repeats 15 times):**
1. Implement against a feature branch; every mechanic lands with its GameTest in the same PR.
2. `./gradlew runGameTestServer` locally green → 2-client manual matrix
   (`runServer` + `runClientMp` [sophiex456] + `runClientMp2` [maxi789]): sync, relog persistence,
   observer visibility for every new synced field.
3. Fill the Strict Polish Rubric in the release PR; attach recordings/screenshots demanded by the
   version's Rubric+ rows.
4. `scripts/release.py`: parity check → `clean build` → copy `versions/NN-goobymod-X.Y.Z.jar` →
   verify PATCHNOTES + Handbuch headers → tag.
5. CI (`modjar.yml`): build + FATAL GameTests on the release branch; from v4.0 additionally the
   Create-matrix leg.

**Test-suite growth targets:** 18 (today) → ≥ 24 (v3.0) → ≥ 32 (v3.3) → ≥ 45 (v3.7) → ≥ 58 (v4.1)
→ ≥ 70 (v5.0). Regression tests are never deleted, only migrated.

**Standing manual test matrix (grows with features):**
- Taming/friendship/whistle/riding smoke (2 clients) — every version.
- Sleep cycle overnight soak — every version touching AI.
- 50-Gooby performance pen — v3.2, v3.4, v4.2, v5.0 (spark profiles archived in the PR).
- Old-save migration (a preserved 2.0 world + latest world) — every version touching NBT.

---

*Made with ❤ (und sehr viel Nutella) by Sonic0810 — plan authored for the v3.0→v5.0 arc.*
