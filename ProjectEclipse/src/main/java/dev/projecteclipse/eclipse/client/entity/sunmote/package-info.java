/**
 * Client renderer + registration for the Sunmote's GeckoLib conversion (MC3, F-098 wave
 * M-C). Own {@code @EventBusSubscriber(Dist.CLIENT)} class per the P6 no-shared-file
 * rule — the shared {@code EclipseEntityRenderers} still carries the legacy
 * {@code SunmoteModel}/{@code SunmoteRenderer} lines until the integrator applies the
 * deletion snippet in {@code docs/plans_v3/session_0730/MC3_AMBIENT_REPORT.md}.
 */
package dev.projecteclipse.eclipse.client.entity.sunmote;
