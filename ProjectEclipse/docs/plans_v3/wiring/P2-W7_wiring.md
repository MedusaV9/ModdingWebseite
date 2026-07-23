# P2-W7 wiring notes — Map-Expansion Sequence v2 (SKYWARD → FLYOVER → GROWTH → STRUCTURES → END)

Zero shared-file edits. Everything self-registers: `sequence/ExpansionSequence.java` is one
`@EventBusSubscriber` class (game bus) with a nested `ClientHooks` MOD-bus/`Dist.CLIENT`
subscriber for the growth dust wall, and registers all its seams on
`ServerAboutToStartEvent` (`WorldStageService` growth-start + stage listeners,
`StructurePendingRegistry` site listener, the `"growth_front"` dynamic-anchor resolver,
`SequenceReplayable.Registry` id `"expansion"`).

## Files delivered

| File | What |
|---|---|
| `sequence/ExpansionSequence.java` | Phase machine + FX-only replay + persisted nether returns (`SavedData` `eclipse_expansion_returns`) + client dust-wall hook (nested `ClientHooks`). |
| `assets/eclipse/cutscenes/expansion_skyward.json` | NEW — player-anchored 80t sky tilt (bezier, hands off from the player's own eyes, pitch → −74°, `event.eclipse_drone` path event). |
| `assets/eclipse/cutscenes/expansion_flyover.json` | NEW — world-anchored 300t front flyover, `params.dynamicAnchor = "growth_front"`, lookAt-tracked, carries the `eclipse.caption.expansion.growing` caption event. |
| `assets/eclipse/cutscenes/unlock_ring.json` | RESHOT — low dramatic pickup → rising lookAt-tracked orbit → high reveal (uses the R12 `lookAt` schema instead of v1's guessed fixed yaws). Also W7's FLYOVER fallback shot. |
| `assets/eclipse/quasar/emitters/growth_dust_wall.json` | NEW — wavefront dust curtain (billboard, non-additive, ≤ 12 particles per emitter, no `veil:light`). |
| `assets/eclipse/quasar/emitters/structure_slam_dust.json` | NEW — slam ground burst (16 particles, gravity + drag, no `veil:light`). |
| `assets/eclipse/quasar/emitters/roulette_flare.json` | NEW — award head-roulette flare (additive gold→purple; P3 consumes, nothing references it yet by design). |
| `assets/eclipse/quasar/emitters/map_expand_materialize.json` | MODIFIED — `veil:light` module REMOVED (last live per-particle light perf trap). Compensation: `additive: true` (emissive read), `base_particle_size` 0.18 → 0.36, `count` 4 → 6. |
| `cutscene/UnlockCinematics.java` | DELETED (v1 — trigger absorbed, see below). |
| `docs/plans_v3/langdrop/P2-W7.json` | 5 caption keys, en+de. |

## Orchestrator asks (MUST-DO)

### 1. `cutscene/CutscenePaths.java` (W6 owns it this wave — do not double-edit)

Two changes:

```diff
     private static final List<String> DEFAULT_IDS =
-            List.of("intro_v3_ship", "intro_v3_flight", "intro_v3_reveal", "unlock_ring", "finale_return");
+            List.of("intro_v3_ship", "intro_v3_flight", "intro_v3_reveal", "unlock_ring",
+                    "expansion_skyward", "expansion_flyover", "finale_return");
```

```diff
     private static final Map<String, List<String>> LEGACY_DEFAULT_HASHES = Map.of(
+            // W7 reshot unlock_ring (v1 fixed-yaw orbit); hash of the replaced bundled JSON:
+            "unlock_ring", List.of("2d5f63f7cb778bd799f185e700549fcc1e213488229b63fff5a0a4cd457eaefa"),
             "finale_return", List.of("6a0fcdab0fb32e8e3c66e0dc725b53d36304c70350a07df55f462ed48574bb43"),
```

(The old `unlock_ring` hash is the SHA-256 of the pre-W7 bundled asset, verified with
`sha256sum` before the reshoot. Without it, worlds whose `config/eclipse/cutscenes/unlock_ring.json`
predates the defaults manifest keep the stale v1 shot with only a warning.)

Note `ExpansionSequence` degrades cleanly while this ask is pending: `CutscenePaths.get()`
misses → SKYWARD's group callback fires synchronously and FLYOVER falls back to
`unlock_ring` per watcher (v1 shape), so nothing softlocks.

### 2. Lang merge

Merge `docs/plans_v3/langdrop/P2-W7.json` into `assets/eclipse/lang/en_us.json` /
`de_de.json` (5 keys: `eclipse.caption.expansion.skyward|growing|structures|done|nether_return`).

### 3. Nothing else

Sounds reused, already registered + in `sounds.json` (W1): `eclipse:event.eclipse_drone`,
`eclipse:event.rift_slam`. Payloads reused (all frozen): `S2CEclipsePhasePayload`,
`S2CFxEventPayload` (`fx/shockwave`, `fx/rift_open|close`), `S2CQuasarPayload`,
`S2CCaptionPayload`, `S2CScreenFadePayload`, `S2CShakePayload`, `S2CGrowthWavePayload`.

## UnlockCinematics removal

`cutscene/UnlockCinematics.java` deleted. Grep confirmed **zero references outside the file
itself** (it was a self-registering `@EventBusSubscriber`); no shared-file diffs needed. Its
behaviour is absorbed verbatim into `ExpansionSequence.onGrowthStart`:

- Only ANIMATED, GROWING commits are cinematic (instant stamps / erases skipped).
- `cutscenes.freezeDuringUnlocks` (`general.json`, default true) still gates the whole show.
- `intro_fusion`-trigger stages still skipped (start event owns that cinematography).
- Its `edgeAnchorFor` geometry lives on as the FLYOVER-fallback / viewpoint / dynamic-anchor
  helper. Its growth-complete abort listener is superseded by the phase machine (the sweep
  completing now *advances* the sequence instead of aborting it).

## Integration contract (what siblings can rely on)

- **Trigger**: `WorldStageService.GrowthStartListener`. Overworld commits get the full
  cinematic; nether commits run a reduced variant (eclipse grade + captions + structure
  beats, no cutscenes, no cross-dimension transport). Concurrent runs per profile: a new
  commit supersedes/aborts the old run and carries its nether visitors forward.
- **`"growth_front"` dynamic anchor** (registered with `CutsceneService`): current wave
  radius from `RingGrowthService.progressFraction` lerped between the from/to stage radii,
  6 blocks inside the front (already-written terrain), at the average watcher angle,
  heightmap-snapped. Resolves sanely even with no live run (current stage edge) — other
  paths may reuse the key.
- **Nether players (R12)**: transported to a viewpoint arc 24 blocks inside the OLD rim
  (never rewritten by the sweep) at SKYWARD, invuln-only flag refreshed every 100t while
  the run lives, returned at END. Return origins persist in SavedData
  (`data/eclipse_expansion_returns.dat`): crash/restart/logout mid-event → applied at next
  login. The viewpoint is < 128 blocks from the flyover anchor **on purpose** so W2's
  global gather never re-snapshots the visitors (their return stays W7's).
- **STRUCTURES beats**: sequential, 50t spacing, per site: close the enqueue-time ground
  tear (opened by `EclipsePayloads.handleStructureRift` at `anchor + (0.5, 1, 0.5)` — beat
  rifts replace it), open a `STYLE_STRUCTURE` sky tear 26 blocks up (width = footprint ×
  1.7, `RiftFx` caps), 40t hold, `StructurePendingRegistry.trigger`, on PLACED: slam dust
  (+4 corner bursts for footprints ≥ 64) + `fx/shockwave (0.5, 30)` + `event.rift_slam` +
  shake 0.4, rift closes 8t later. Beat timeout 60 s (placer missing/async) closes the rift
  and moves on — the registry's auto-delay still guarantees eventual placement. A stage
  with no structures skips straight to END (graceful-degrade requirement).
- **Chat unlock list**: untouched — `timeline.AnnouncementService`'s stage listener already
  announces finished GROW sweeps with localized unlock keys.
- **Award-roulette hook (P3 seam)**: `AwardService.sendRevealNow(server)` fires at END of
  the last concurrent run. `roulette_flare.json` is shipped for P3's overlay; nothing
  spawns it yet.
- **Replay (R12)**: `/eclipsefx sequence expansion SKYWARD|FLYOVER|GROWTH|STRUCTURES|END`
  — FX-only (LOCAL plays, fake beat positions ahead of each watcher, no `trigger()`, no
  transports, END replay does NOT call `sendRevealNow` since that writes reveal state).

## FX budget compliance (veilfx/FxBudget)

- Dust wall: client-side hook consumes `S2CGrowthWavePayload` (via
  `GrowthPayloads.setClientWaveHandler`, the documented P2 seam — installing a second
  handler elsewhere would replace ours). ≤ 2 emitter spawns per pulse (pulses every 5t →
  ≤ 8 spawns/s), 96-block spawn radius, SEQUENCE channel — refusals drop silently. Intro
  fusion pulses (overworld `fromStage == 0`, where `waveR` is an edge distance) skipped.
- Slam dust: 1 payload burst per site (5 for footprint ≥ 64), server-paced ≥ 50t apart.
- No `veil:light` in any W7 emitter; `map_expand_materialize`'s light module removed.

## Risks

1. **`CutscenePaths` ask pending** → FLYOVER runs the `unlock_ring` fallback and SKYWARD
   no-ops (instant callback). Cosmetic-only, no softlock (see above).
2. **Flyover anchor freshness**: the dynamic anchor resolves once per play (W2 contract);
   over the 300t shot the wave outruns the anchor by design (the shot pulls up/back to
   compensate). Worst case on huge stages the front leaves frame near the end.
3. **Two overlapping profile runs** (overworld + nether growing simultaneously): eclipse
   grade is global, so it releases only when the LAST run ends; captions are
   dimension-scoped so no cross-talk. Award hook also fires once (last run).
4. **`sendToPlayersNear` 192-block radius for slam dust** vs. cinematic view distances:
   watchers parked farther than 192 from a site see rift + shockwave (dimension-ranged)
   but no dust — acceptable, dust is subpixel there anyway.
5. **`map_expand_materialize` additive flip**: the materialize motes now read emissive
   (brighter at night). If P1 owners dislike the look, revert `additive` to `false` and
   keep only the size/count compensation — the perf fix (no light module) stands alone.
6. **Nether visitor logs back into a FINISHED event**: covered — login applies the
   persisted return immediately; mid-event relogs keep watching and go home at END.

## Test steps

1. `/eclipse stage set overworld <n+1> animate` (op level 3+ for `/dev`, 2 for `/eclipse`)
   with ≥ 2 players (one in the nether): sky tilt for all + eclipse grade ramp; nether
   player fades to an overworld rim viewpoint (log: "brought <name> from the nether");
   flyover flies the growth front; dust walls ride the wave; after the sweep each stage
   structure gets ground-tear-close → sky rift → 40t hold → paste → dust/shockwave/thunder/
   shake → rift close, 50t apart; END: caption, grade release over 100t, nether player
   returned (whisper caption), announcement chat list appears, award reveal fires
   (log `AwardService`).
2. Stage with **no structures**: sequence ends right after the sweep (no STRUCTURES caption).
3. `/eclipse stage set nether <n+1> animate`: reduced run — grade + growing caption +
   structure beats in the nether, no cutscenes, nobody transported.
4. Kill the server mid-FLYOVER; restart: no stuck freeze (transient), sweep resumes and
   completes silently, pending sites place via registry auto-delay, nether player's return
   applies at next login.
5. `/eclipsefx sequence expansion <each phase>`: FX-only beats in front of the caller; no
   blocks placed, nobody teleported, no award reveal on END.
6. `cutscenes.freezeDuringUnlocks=false` in `general.json`: growth runs with zero W7
   involvement (v1 parity).
