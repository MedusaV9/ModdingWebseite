/**
 * WOAH-03 — CHRONO-STASE (docs/plans_v3/woah/PLAN-03_chrono_stasis.md): a permanent
 * map set-piece in the birch-forest wedge (landmark {@code eclipse:chrono_stasis},
 * r ≈ 241, stage 3) where one instant is frozen forever — a standing lightning bolt,
 * an explosion caught mid-detonation, a watchtower hanging mid-collapse, frozen rain,
 * birds and leaves stopped mid-motion, and the Chronosphere clock artifact at the
 * center.
 *
 * <p>Layout (the WoahFeatures ownership law — ALL feature code lives here):</p>
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.ChronoStasisSite} —
 *       stage listener, pending-registry placer, terraforming, anchor publish,
 *       rollback + the frozen site constants shared with the client.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.ChronoSceneBuilder} —
 *       deterministic ~460-display scene (seeded), identity tags, reconcile,
 *       budgeted spawn, stateless {@code poseOf} functions.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.ChronoStasisService} —
 *       JOLT×5 → DISCHARGE → REWIND statemachine, slowness aura, interaction pad,
 *       reward, watchdog.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.ChronoStasisData} —
 *       own SavedData file (ownership law: never a field on a shared schema).</li>
 *   <li>{@code client} subpackage — zone ease, Veil grade, Photon loop windows,
 *       ticking sound, cue rows (all {@code Dist.CLIENT}-gated).</li>
 * </ul>
 */
package dev.projecteclipse.eclipse.woah.chronostasis;
