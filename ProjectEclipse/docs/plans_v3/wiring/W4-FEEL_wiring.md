# W4-FEEL wiring notes — game-feel quick wins (IDEA-02/03/04/05/06 top picks)

Twelve S/M feel beats across combat, mining, movement, HUD and menus — all Quiet-Eclipse
subtle (`P3_ui.md` §2), all `reducedFx`-gated, all F1-safe (every HUD beat lives inside
layers that already respect `hideGui`). **Zero hub edits landed**: no `EclipseMod`,
`EclipsePayloads`, `EclipseGuiLayers`, `registry/**`, lang JSON, `sounds.json` or
`build.gradle` changes. New service classes self-register via `@EventBusSubscriber`;
everything else rides existing seams. Langdrop: `docs/plans_v3/langdrop/W4-FEEL.json`
(13 keys × en/de).

## What landed

### COMBAT (IDEA-02 top 3)

1. **Universal hurt-spark** — `client/entity/geo/HurtSparks.java` (NEW, package-private)
   hoists the `GlitchedGeoRenderer.HurtSparks` pattern into the frozen base:
   `EclipseGeoRenderer.preRender` now pops one BURST-budgeted `eclipse:rift_spark`
   crackle on the first `hurtTime` frame of EVERY Eclipse custom mob (per-entity 10 t
   dedup, owner-managed loop-emitter expiry, teardown-safe). `GlitchedGeoRenderer` was
   deduped — it keeps only its alt-frame corruption extra (`hurtTime ≥ 8` forcing the
   datamosh frame); the spark now arrives via its `super.preRender` call. The
   `eclipse:rift_spark` emitter asset already ships (GLITCHED family) — no P2 ask.
2. **Kill-confirm chime** — `drama/KillConfirmService.java` (NEW): `LivingDeathEvent` at
   LOW, killer-private `playNotifySound` layer (amethyst chime + ghosted attack-crit),
   deeper/louder variant for elites (`FogColossusEntity`, `StormHoundEntity`); bosses
   (`FogTyrantEntity`, `RiftWardenEntity`) excluded — their scripted deaths own the
   moment. `EclipseGeoMonster` guard keeps vanilla mobs and the Herald/Ferryman out.
3. **Hit-stop punch** — `drama/HitStopService.java` (NEW): `LivingDamageEvent.Post`,
   direct player melee on colossus/tyrant/warden with damage actually applied →
   `S2CShakePayload.shake(0.12F, 2)` to the attacker. `reducedFx` drops shake impulses
   client-side in the `CameraDirector`, so no server gate needed.

### MINING (IDEA-03 top 3)

4. **First-ore fanfare** — `drama/MiningFeelService.onNaturalOreMined` (NEW), called from
   the tail of `SkillPerks.onNaturalOreMined` (already natural-only + placed-re-checked):
   analytics `mine:<block_id>` lifetime sum across BOTH ore variants `== 1` right after
   the increment → private `UI_UNLOCK_STING` + `ore_first_<oreId>` proc toast. Zero new
   state; the dynamic-key cap degrades to "never double-fires".
5. **Vein reveal + completion chime** — `worldgen/ore/VeinTracker.java` (NEW, stateless):
   re-derives the cell's deterministic vein with the exact `OreField.tryOre` math and
   counts remaining blob blocks (≤ ~245 in-cell reads per ORE break, pre-removal
   semantics: `present == total` ⇒ intact first break → actionbar size reveal
   (`message.eclipse.vein.reveal`); `present == 1` ⇒ clearing break → two-note chime +
   "Vein cleared ×N" toast (`vein_clear` proc id, magnitude = vein size).
6. **Ore-proc sparkle** — `MiningFeelService.sendOreProcSparkle` ships
   `eclipse:fx/ore_proc` on the sanctioned `S2CFxEventPayload` seam
   (`a` = extra-drop magnitude, `b` = packed 24-bit ore RGB — exact in a float). Fired
   from `SkillPerks` (T2 `double_ore`, T6 `bonus_ore` procs) and `BuffEffects.onBlockDrops`
   (`ore_drops` buff, one statement). Client body ships ready in
   `client/drama/OreProcFxClient.java` (NEW): ore-tinted dust ring + 2 END_ROD glints,
   ≤ 14 vanilla one-shot particles, `reducedFx` skips. **Needs the FxPayloads diff below**
   — until it lands the id falls into the debug-log arm (silent no-op, nothing breaks).

### MOVEMENT (IDEA-04 idea 6 only)

7. **Bounce anticipation squash** — `progression/ContainmentService.java`: falling fast
   through the 10 blocks above `bounceY` streams reverse-portal motes below the player +
   one low chime per fall (re-arms above the band); the flip itself now compresses
   horizontal velocity to 0.25 and springs back ×1.6 three ticks later (same 0.4 total
   budget as before — trajectory-neutral, but the arc visibly pinches then releases).
   New statics reset on `ServerStopped`. Glide/soft-landing untouched (other worker).

### HUD (IDEA-05 top 3)

8. **Goal-complete stamp** — `client/hud/SidebarPanel.java`: the existing
   `LAST_GOAL_DONE` edge now drives (a) 2 t white→GOOD checkbox flash, (b) expanding
   fading GOOD ring (4 hairline fills), (c) TEXT→GOOD row-text crossfade over a 600 ms
   stamp TTL (`STAMP_MILLIS`, extended from the 300 ms sweep), (d) one
   `UiSounds.goalStamp(pitch)` cue pitch-salted by `row.phaseSalt()` (arpeggiates
   back-to-back completions), fired from the edge, never from render. First payload
   population after join/day-flip seeds silently (no login stamp chorus — this also
   removes the old join-replay of the box sweep, which was unintended noise).
   `reducedFx` keeps the instant color swap only.
9. **TAB-card checkmark draw-on** — `client/hud/SidebarExpanded.java`: the static `✓`
   glyph became a two-stroke vector check (six 1×2 fills) whose strokes draw on over
   8 t eased, keyed off the shared stamp timestamp (new package-private
   `SidebarPanel.goalStampStarted(id)`); the goal bar recolors ACCENT→GOOD left-to-right
   over the same window. No live stamp ⇒ fully drawn. `reducedFx` ⇒ glyph as before.
10. **XP strip specular sweep + carry** — `client/skills/SkillXpBarLayer.java`: the flat
    white level-up bar became an accent bar with a 3-layer specular band (half-widths
    7/4/2 px, alphas .30/.55/.95) crossing left-to-right; multi-level gains queue one
    sweep per level (cap 3) before easing to the final fraction, the numeral
    odometer-increments once per sweep (`skillLevel - pendingSweeps`) with a white flash
    per step. Carry sweeps 2/3 play `UiSounds.levelUp(1.06F/1.12F)` — the FIRST sweep's
    audio stays `LevelUpOverlay`'s existing `levelUp()` (no doubling). `reducedFx` keeps
    today's snap (`pendingSweeps = 0`).

### MENUS (IDEA-06 top 3)

11. **Purchase cascade** — `client/skills/SkillTreeWidget.java`: `onNodePurchased` diffs
    the bought node's children that are AVAILABLE now (they required this node, so they
    were LOCKED a frame ago) into `unlockAnimStart` with future starts
    (`now + RING_MILLIS + 80 ms × sibling order`); their edges keep the locked hairline
    underlay while a dim-accent wipe travels over (`LINE_MILLIS`, `easeOutCubic`) and the
    tiles flash a soft accent outset border over 250 ms before the normal affordable
    pulse takes over. One `UiSounds.skillUnlockWave()` per cascade, never per node.
12. **Toggle knob glide + page-turn paper feel** — `client/menu/SettingsPanel.ThemedToggle`:
    the knob glides between docks over 80 ms eased with a DIM↔ACCENT in-flight tint and a
    two-stage click (press = existing `toggle()`, dock = new `toggleSettle(on)` — ON lands
    brighter). Hitbox untouched (B3), keyboard path free.
    `client/handbook/HandbookScreen.java`: the tab crossfade gains (a) a 0.97 horizontal
    squash of the outgoing page toward its exit edge (incoming un-squashes; pose-only,
    pivoted at the content edge, widgets untransformed), (b) a 1 px accent page-edge line
    sweeping the content rect in the switch direction, (c) keyboard `pageTurn` pitched by
    direction (forward 1.05 / back 0.9) via the new `pageTurn(float)` overload; the open
    rustle stays at 1.0. All inside the existing `switchProgress`/`reducedFx` gates.

### UiSounds (additive helpers only, frozen API respected)

`pageTurn(float pitchScale)`, `levelUp(float pitch)` (no-arg variants now delegate),
`goalStamp(float pitch)` → ledger `ui.goal_stamp` (fallback `UI_TAB` ×1.4),
`skillUnlockWave()` → ledger `ui.skill_unlock` (fallback `UI_HOVER` ×0.8),
`toggleSettle(boolean on)` → ledger `ui.toggle_settle` (fallback `UI_TAB`, pitch
1.1/0.75, vol 0.35). All use the self-healing `play(String, …, fallback, scale)` pattern —
they sound today and pick the real events up automatically once the ledger lands.

## Wiring asks (integrator)

### 1. `network/fx/FxPayloads.java` — exact diff (file is FROZEN/shared)

Add the frozen-id constant next to the other `FX_*` ids:

```java
    /** pos = block center, a = extra-drop magnitude, b = packed 24-bit ore RGB (W4-FEEL). */
    public static final ResourceLocation FX_ORE_PROC = fx("ore_proc");
```

Add the dispatch branch in `handleFxEvent`, before the debug-log `else`:

```java
        } else if (FX_ORE_PROC.equals(id)) {
            dev.projecteclipse.eclipse.client.drama.OreProcFxClient.handle(
                    payload.pos(), payload.a(), payload.b());
        } else {
```

Optionally repoint `MiningFeelService.FX_ORE_PROC` at the new `FxPayloads.FX_ORE_PROC`
(the two constants carry the identical id; the local one exists only because this file
is frozen this wave).

### 2. Sound ledger — 3 new `ui.*` events

Register in `EclipseSounds` + `sounds.json` when the ledger next opens:
`eclipse:ui.goal_stamp` (short dry stamp/click, pitch-salted at call site),
`eclipse:ui.skill_unlock` (soft onward whoosh, one per cascade),
`eclipse:ui.toggle_settle` (tiny knob-dock tick; ON plays at 1.1, OFF at 0.75 — one
sample is enough). Fallbacks keep everything audible until then.

### 3. Lang merge

Merge `docs/plans_v3/langdrop/W4-FEEL.json` into `en_us.json`/`de_de.json`. Note:
`message.eclipse.skill.proc.ore_first_<id>` keys cover the shipped `ores.json` ids
(coal/copper/iron/gold/redstone/lapis/diamond/zinc/quartz/nether_gold/netherite);
server-custom ore ids degrade readably in the toast (`SkillProcToast` underscores→spaces)
until a key is added per id.

### 4. `worldgen/ore/OreField` owner — consolidation ask

`VeinTracker` mirrors `OreField`'s private `hash3`/`mix`/`to01`/`H_ORE` and the whole
`tryOre` derivation **bit-identically** (verified against the current file). Please
expose a package-private `veinAt(ResolvedOre, DiscProfile, cx, cy, cz)` (center + radius,
or null) so the duplication can collapse; until then treat the two files as ONE frozen
algorithm — any `tryOre` math change must be mirrored or vein feel silently misfires
(worst case: no chime; it can never place/remove ore).

## Coordination / risks

- **Hash-parity drift** (above) is the only real correctness risk; everything else fails
  quiet by construction (missing FX branch → debug log, missing lang key → readable
  degrade, missing ledger sound → re-pitched fallback).
- **Vein census vs carving**: `VeinTracker` counts generated-blob candidates; a
  cave-carved vein reads `present < total` on first break, so the size reveal simply
  doesn't show and the completion chime still fires on the true last block. Deliberate.
- **Cascade approximation**: children are matched by `requires.contains(boughtId)` +
  currently AVAILABLE. Under the tree's ALL-parents-required semantics this is exact; if
  an ANY-of node type ever lands, an already-available child could re-flash once
  (cosmetic only).
- **LevelUpOverlay ownership**: the first level-up sting stays with the overlay's queue;
  `SkillXpBarLayer` only adds the 1.06/1.12 stings for carry sweeps 2/3. If the overlay's
  `levelUpCelebrations` toggle is off, carry sweeps still arpeggiate (deliberate — the
  strip is the quiet fallback presentation).
- **Kill-confirm audio layering**: purely additive `playNotifySound` on the killer; if a
  future mob ships its own death sting, exclude it in `KillConfirmService` the same way
  the two bosses are excluded.
