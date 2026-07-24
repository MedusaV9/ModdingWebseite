# P6-W4 wiring (floating sanctum island + crater, build pass 1)

**Zero integrator wiring lines.** Everything P6-W4 shipped lives in files the package
owns, and the only two event subscribers involved (`AltarSanctumBuilder`,
`SanctumProtection`) were ALREADY `@EventBusSubscriber(modid = EclipseMod.MOD_ID)`
classes before this wave — annotation-discovered, no `EclipseMod.java` constructor
lines, no payload registrations, no gradle/toml edits.

## Files touched (all P6-W4-owned per the plan matrix)

| File | Change |
|---|---|
| `worldgen/structure/AltarSanctumBuilder.java` | Became the v2 entry: stage gate + `SanctumVersionData` guard in new `ensureSanctum`, live `WorldStageService.StageListener` (registered once on `ServerAboutToStartEvent`), `repinSpawn` v2 (crater-rim south plaza when floating), sanctum-top builders opened to package-private for reuse. Herald API (`pillarBaseCorner`/`pillarBases`/`pillarTopY`) formulas UNTOUCHED. |
| `worldgen/structure/FloatingSanctumBuilder.java` | NEW — island mass/underside/rim/glide notches/bridge access + the frozen anchor APIs (below). |
| `worldgen/structure/SanctumCrater.java` | NEW — r=12 bowl 4 deep, strata, boulders, snapped stumps, scorch + rubble rim, south walk sector kept clear. |
| `worldgen/structure/SanctumVersionData.java` | NEW — own SavedData `eclipse_sanctum_version` (v0 none / v1 grounded / v2 floating). Deliberately NOT a field on the shared `EclipseWorldState`. |
| `worldgen/structure/SanctumProtection.java` | Zone grew r=16 sphere → r=18 cylinder × y[−26..+24] around the altar. `isProtected(Level, BlockPos)` signature unchanged (frozen P4/P2 interface). |
| `worldgen/structure/SundialPlaza.java` | Javadoc only — the dial re-anchors onto the island top automatically (`altarPos`-derived, groundMix erase contract). No code change. |

## Frozen interfaces other workers consume

- **P6-W5 (orbitals, build pass 2):**
  `FloatingSanctumBuilder.orbitalAnchors(BlockPos altarPos)` → 12 `OrbitalAnchor(ring,
  index, center, radius, phaseRadians, scale, block)` records — ring 0 = low ring
  (r=13.0, islandTop−4, 7 displays, clockwise), ring 1 = high ring (r=9.0, altar+7,
  5 displays, counter-clockwise). Composition per plan §2.6: 5 purpur, 3 obsidian,
  2 crying obsidian, 2 amethyst, scales 0.40–0.70. W5 spawns/animates the display
  entities and owns tag persistence; W4 owns only this anchor data.
- **P4 (edge auto-glide safety rule) / P2 (glide FX):**
  `FloatingSanctumBuilder.glideLedges(BlockPos altarPos)` → the 4 launch-ledge
  positions (outer slab of each diagonal rim notch at island-top Y; notches at
  45°/135°/225°/315°, half-width 9°). Pure geometry, no level access.
  `SanctumCrater.depthAt(dx, dz)` → pure parabolic bowl depth for fall-safety math.
  `SanctumProtection.isProtected(Level, BlockPos)` unchanged.
- **P6-W11 (Herald):** `AltarSanctumBuilder.pillarBaseCorner/pillarBases/pillarTopY`
  formulas identical and relative to `altarPos` — on the island the r=9 ring simply
  rides the altar up. Arena stays on the island top (ellipse r=16/14 ≥ pull radius),
  rim parapet keeps P3 pulls from yeeting players off the edge.

## Behavior contract (for the orchestrator's QA pass)

- Stage 0 boot, fresh world → v1 GROUNDED sanctum exactly as before (zero visual delta
  pre-intro), version stamped v1.
- Overworld stage reaches ≥ 1 (boot-time check on `ServerStartedEvent` at LOW priority
  OR live via the stage listener the moment the stage-1 terrain sweep completes) →
  one-shot flip: legacy volume (r=13, ground+1..+16) cleared, island + crater +
  bridge built, altar block re-placed on the island (block-entity state is
  transient-only; durable progress lives in `EclipseWorldState`, re-persisted through
  the existing `setSanctumBuilt(newAltarPos)` path), spawn re-pinned to the crater-rim
  south plaza, players stranded in the torn-out zone teleported there, protection
  refreshed. Version stamped v2 = terminal.
- Every later boot: log line `Sanctum v2 present at ... — idempotent boot, zero block
  changes` and NO setBlock calls from this package.
- Legacy pre-versioning saves (grounded sanctum, no version file) are adopted as v1 on
  first boot (`Sanctum version adopt` log line), then follow the same flip rule.
