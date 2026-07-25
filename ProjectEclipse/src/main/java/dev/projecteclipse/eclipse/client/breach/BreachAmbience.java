package dev.projecteclipse.eclipse.client.breach;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-WORLD (IDEAS-world.md #7) — the breathing nether-breach vent: periodic Photon ash
 * geysers erupting from the chimney whose ash REALLY bounces off the crater lip / funnel
 * wall ({@code eclipse:breach_ash_geyser}, physics collision — the module Quasar cannot
 * match), plus four ember ara ribbons corkscrewing up the thermal
 * ({@code eclipse:breach_ember_updraft}). This is the WINDOWED-loop controller mandated
 * by INTEGRATION.md §4 (the {@code SanctumLightfall}/{@code AltarCoronaIdle} window
 * school): a materialize/release hysteresis band
 * ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}), a {@value #RETRY_TICKS}-tick
 * probe/retry cadence, and unconditional release on {@code reducedFx} / dimension
 * change / logout.
 *
 * <p>The anchor needs ZERO new sync: {@link BreachGeometry#centerX()}/{@code centerZ()}/
 * {@code lipY()} derive from {@code DiscMapData}/{@code DiscTerrainFunction}, both
 * already exercised client-side ({@code MapTab}, {@code LimboHorizonShips}). Both loops
 * sit at the chimney mouth, {@value #ANCHOR_BELOW_LIP} below the lip plane. Whether the
 * breach has actually been CARVED is a server flag the client can't read — so the gate
 * is the {@code SanctumLightfall} physical-probe trick: the loop only runs while the
 * crater interior block {@value #PROBE_BELOW_LIP} below the lip at the center column is
 * loaded AND air, which is only ever true once W1.7's builder has opened the funnel.
 * Self-correcting, re-probed on the retry cadence.</p>
 *
 * <p><b>Fallback / budgets:</b> the two registry rows ({@code WorldPhotonFxRows}) have
 * no Quasar leg by design — the shipped server ambience (the CAMPFIRE_COSY_SMOKE lip
 * ring + SOUL_FIRE_FLAME/ASH updraft of {@code BreachTransferService.ambientTick}) is
 * the photon-less read and keeps running unchanged for everyone (Mode.LAYER). Photon
 * absent / missing asset / executor budget ⇒ silent no-op, bit-identical to today.
 * {@code reducedFx} kills the loops wholesale (instant release, and the bridge refuses
 * re-spawns) — correct, this is garnish. Cost ceiling while open: 220 colliding ash +
 * ~24 glow + 4 ribbons at ONE landmark (both assets carry renderer cull boxes + hard
 * {@code maxParticles}). Idle cost while far: one distance check per tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BreachAmbience {
    /** Window materializes within this camera distance of the lip center (blocks)… */
    private static final double MATERIALIZE_DIST = 96.0D;
    /** …and releases only beyond this one (hysteresis — no boundary thrash). */
    private static final double RELEASE_DIST = 110.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Loop anchor depth below the lip plane — the chimney mouth (IDEAS-world #7 spec). */
    private static final int ANCHOR_BELOW_LIP = 6;
    /** Built-probe depth below the lip: air here ⇔ the funnel interior is actually carved. */
    private static final int PROBE_BELOW_LIP = 4;
    /** Probe / refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
    private static final int RETRY_TICKS = 40;

    /** Whether the window is currently open (drives the hysteresis band). */
    private static boolean open;
    private static int retryCountdown;

    private BreachAmbience() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            close(false);
            return;
        }
        Vec3 lip = new Vec3(BreachGeometry.centerX() + 0.5D, BreachGeometry.lipY(),
                BreachGeometry.centerZ() + 0.5D);
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(lip);
        if (distSq > (open ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            close(true); // walked away: graceful fade, not a pop
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        if (--retryCountdown > 0) {
            return;
        }
        // Physical probe: the crater interior column is air below the lip only once the
        // breach is actually carved (the server's breachOpen flag is not client-readable).
        BlockPos probe = BlockPos.containing(lip.x, lip.y - PROBE_BELOW_LIP, lip.z);
        if (!level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                SectionPos.blockToSectionCoord(probe.getZ()))
                || !level.getBlockState(probe).isAir()) {
            close(false); // breach not built (yet) — keep probing on the cadence
            retryCountdown = RETRY_TICKS;
            return;
        }
        open = true;
        Vec3 anchor = lip.add(0.0D, -ANCHOR_BELOW_LIP, 0.0D);
        boolean geyser = PhotonFxRegistry.ensureLoop(FxCues.CUE_BREACH_ASH_GEYSER, anchor);
        boolean updraft = PhotonFxRegistry.ensureLoop(FxCues.CUE_BREACH_EMBER_UPDRAFT, anchor);
        // Healthy legs: re-ensure every tick (idempotent prune + re-spawn of pruned legs).
        // Refused (photon absent / missing asset / executor budget): back off RETRY_TICKS.
        retryCountdown = geyser && updraft ? 1 : RETRY_TICKS;
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern; registry releases too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        close(false);
    }

    private static void close(boolean graceful) {
        if (open) {
            PhotonFxRegistry.releaseLoop(FxCues.CUE_BREACH_ASH_GEYSER, graceful);
            PhotonFxRegistry.releaseLoop(FxCues.CUE_BREACH_EMBER_UPDRAFT, graceful);
        }
        open = false;
        retryCountdown = 0;
    }
}
