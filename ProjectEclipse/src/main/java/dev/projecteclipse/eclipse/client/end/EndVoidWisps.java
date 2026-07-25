package dev.projecteclipse.eclipse.client.end;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
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
 * PH-WORLD (IDEAS-world.md #6b) — the End-disc void wisps: 1200 GPU-instanced
 * ghost-light plankton drifting in the void around the disc rim
 * ({@code eclipse:end_void_wisps} — THE Photon GPU-instancing showcase: one emitter,
 * {@code useGPUInstance} + parallel update/render, one draw call). This is the
 * WINDOWED-loop controller mandated by INTEGRATION.md §4 (the
 * {@code SanctumLightfall}/{@code AltarCoronaIdle} window school).
 *
 * <p><b>Window:</b> overworld (the disc hangs at Y {@code ~360} over the overworld) +
 * NOT {@code reducedFx} + the camera within {@value #MATERIALIZE_DIST}/{@value
 * #RELEASE_DIST} (hysteresis) of the RIM RING — the 3D distance to the circle of radius
 * {@link DiscProfile#END_DISC_RADIUS} at {@link DiscProfile#END_DISC_SURFACE_Y}, so the
 * band covers standing anywhere on the disc as well as flying past under it, but never
 * the ground 300 blocks below. The anchor is the frozen disc center
 * ({@code END_DISC_CENTER_*}, {@code SURFACE_Y − }{@value #ANCHOR_BELOW_SURFACE}), the
 * exact origin the rim-band cylinder shape in the asset was authored against.</p>
 *
 * <p><b>Materialization gate:</b> whether the disc has actually materialized is a
 * server flag the client can't read — so the {@code SanctumLightfall} physical-probe
 * trick: wisps only run while the disc-surface block at the center column
 * ({@link EndDiscGeometry#surfaceYAt}) is loaded AND non-air, which is only ever true
 * once the disc exists. Re-probed on the {@value #RETRY_TICKS}-tick cadence.</p>
 *
 * <p><b>Fallback / budgets:</b> the registry row ({@code WorldPhotonFxRows}) has no
 * Quasar leg BY DESIGN — the wisps are pure garnish and the photon-less baseline is
 * deliberately nothing (today's empty void, zero regression). The asset carries a
 * renderer cull box ({@code ±110/−20..30}) so an off-screen disc costs one AABB test,
 * and a hard {@code maxParticles: 1200}; {@code reducedFx} kills the loop wholesale
 * (instant release + bridge re-spawn refusal). If min-spec profiling ever complains,
 * halve the asset's {@code emissionRate} — density is the only knob that matters
 * (IDEAS-world #6b). Idle cost while far: one distance check per tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EndVoidWisps {
    /** Window materializes within this camera distance of the rim ring (blocks)… */
    private static final double MATERIALIZE_DIST = 160.0D;
    /** …and releases only beyond this one (hysteresis — no boundary thrash). */
    private static final double RELEASE_DIST = 180.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Anchor depth below the disc surface plane (IDEAS-world #6b authoring origin). */
    private static final int ANCHOR_BELOW_SURFACE = 6;
    /** Probe / refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
    private static final int RETRY_TICKS = 40;

    /** Whether the window is currently open (drives the hysteresis band). */
    private static boolean open;
    private static int retryCountdown;

    private EndVoidWisps() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            close(false);
            return;
        }
        double distSq = rimDistSq(minecraft.gameRenderer.getMainCamera().getPosition());
        if (distSq > (open ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            close(true); // left the end band: graceful fade, not a pop
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        if (--retryCountdown > 0) {
            return;
        }
        // Physical probe: the disc-surface block at the center column exists only once
        // the disc has materialized (the server's flag is not client-readable).
        BlockPos probe = new BlockPos(DiscProfile.END_DISC_CENTER_X,
                EndDiscGeometry.surfaceYAt(DiscProfile.END_DISC_CENTER_X, DiscProfile.END_DISC_CENTER_Z),
                DiscProfile.END_DISC_CENTER_Z);
        if (!level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                SectionPos.blockToSectionCoord(probe.getZ()))
                || level.getBlockState(probe).isAir()) {
            close(false); // disc not materialized (or center unloaded) — keep probing
            retryCountdown = RETRY_TICKS;
            return;
        }
        open = true;
        boolean live = PhotonFxRegistry.ensureLoop(FxCues.CUE_END_VOID_WISPS,
                new Vec3(DiscProfile.END_DISC_CENTER_X,
                        DiscProfile.END_DISC_SURFACE_Y - ANCHOR_BELOW_SURFACE,
                        DiscProfile.END_DISC_CENTER_Z));
        // Healthy leg: re-ensure every tick (idempotent prune + re-spawn of pruned legs).
        // Refused (photon absent / missing asset / executor budget): back off RETRY_TICKS.
        retryCountdown = live ? 1 : RETRY_TICKS;
    }

    /** Squared 3D camera distance to the disc rim ring (radius 96 circle at Y 360). */
    private static double rimDistSq(Vec3 camera) {
        double dx = camera.x - DiscProfile.END_DISC_CENTER_X;
        double dz = camera.z - DiscProfile.END_DISC_CENTER_Z;
        double dr = Math.sqrt(dx * dx + dz * dz) - DiscProfile.END_DISC_RADIUS;
        double dy = camera.y - DiscProfile.END_DISC_SURFACE_Y;
        return dr * dr + dy * dy;
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern; registry releases too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        close(false);
    }

    private static void close(boolean graceful) {
        if (open) {
            PhotonFxRegistry.releaseLoop(FxCues.CUE_END_VOID_WISPS, graceful);
        }
        open = false;
        retryCountdown = 0;
    }
}
