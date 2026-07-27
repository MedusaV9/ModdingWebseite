/**
 * WOAH-03 Chrono-Stase, client half (plan §4) — everything here is
 * {@code Dist.CLIENT}-gated and driven by ONE shared signal:
 * {@link dev.projecteclipse.eclipse.woah.chronostasis.client.ChronoZoneState}, which
 * eases an inside-amount from the camera's distance to the synced
 * {@code FxAnchors.CHRONO_CENTER} anchor and times the jolt/discharge windows armed by
 * the two {@code ChronoCues} rows.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.client.ChronoGradeFx} —
 *       Veil GRADE {@code eclipse:chrono_grade} (desaturate/cool/vignette/time dust;
 *       reducedFx + Iris gates, XboxEraFx lineage).</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.client.ChronoRainField} —
 *       distance-LOD Photon loop windows (far pillar, frozen rain, dust shimmer,
 *       sphere corona, bolt glow) + the discharge rain-release swap.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.client.ChronoTickSound} —
 *       the clock beat whose period stretches toward the center.</li>
 *   <li>{@link dev.projecteclipse.eclipse.woah.chronostasis.client.ChronoStasisFxRows} —
 *       self-registering {@code PhotonFxRegistry} rows for the two cues.</li>
 * </ul>
 *
 * <p>The vanilla-rain suppression lives in the shared
 * {@code client/mixin/LevelRendererMixin} (two HEAD-cancels gated on
 * {@code ChronoZoneState.suppressVanillaRain()}).</p>
 */
package dev.projecteclipse.eclipse.woah.chronostasis.client;
