package dev.projecteclipse.eclipse.client.nether;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.NetherOpenPhotonFxRows;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Phase 4 of the nether opening: the PERMANENT cloud. Once the pit is open, a dense dark
 * smoke body hangs {@value #PLUME_HOVER} blocks over the mouth, turning slowly, with orange
 * fire tongues burning inside it and periodic spark spurts
 * ({@code eclipse:nether_pit_plume}) — plus a quiet fire-crackle/rumble bed that fades out
 * with distance.
 *
 * <p>This is the WINDOWED-loop controller the loop law demands (INTEGRATION.md §4, the
 * {@code BreachAmbience}/{@code SanctumLightfall} window school): materialize/release
 * hysteresis ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}), a {@value #RETRY_TICKS}-
 * tick probe/retry cadence, unconditional release on {@code reducedFx} / dimension change /
 * logout.</p>
 *
 * <p><b>Why the cloud survives a server restart with zero new sync</b>: like
 * {@code BreachAmbience}, the anchor is client-computable ({@link BreachGeometry} derives
 * from the frozen disc map) and the "is it open?" gate is the physical-probe trick — the
 * crater interior {@value #PROBE_BELOW_LIP} blocks below the lip is air only once the
 * builder has actually excavated the funnel. No {@code netherOpened} flag has to reach the
 * client, and no state can drift: a rejoining player re-probes and the cloud is simply
 * there. {@link #onOpened()} only skips the retry backoff at the end of the live show so the
 * plume is up the same tick.</p>
 *
 * <p><b>Cost</b>: while open, one Photon executor (four emitters, all cull-boxed and hard-
 * capped: 110 smoke + 56 fire + 44 sparks + 18 haze) and one sound every
 * {@value #CRACKLE_INTERVAL_TICKS}/{@value #RUMBLE_INTERVAL_TICKS} ticks. While far away,
 * one distance check per tick. Photon absent or {@code reducedFx} ⇒ the loop never spawns
 * and the shipped server ambience is the whole read.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class NetherPitPlume {
    /** Hover height of the cloud over the lip plane (blocks). */
    private static final int PLUME_HOVER = 14;
    /** Window materializes within this camera distance of the cloud (blocks)… */
    private static final double MATERIALIZE_DIST = 128.0D;
    /** …and releases only beyond this one (hysteresis — no boundary thrash). */
    private static final double RELEASE_DIST = 152.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Built-probe depth below the lip: air here ⇔ the funnel is actually carved. */
    private static final int PROBE_BELOW_LIP = 4;
    /** Probe / refused-spawn retry cadence (ticks) — the BreachAmbience cadence. */
    private static final int RETRY_TICKS = 40;

    /** Fire-crackle bed cadence (ticks) and its source volume/pitch. */
    private static final int CRACKLE_INTERVAL_TICKS = 70;
    private static final float CRACKLE_VOLUME = 1.6F;
    private static final float CRACKLE_PITCH = 0.7F;
    /** Deep-rumble bed cadence (ticks) and its source volume/pitch — carries further. */
    private static final int RUMBLE_INTERVAL_TICKS = 170;
    private static final float RUMBLE_VOLUME = 3.0F;
    private static final float RUMBLE_PITCH = 0.42F;

    /** Whether the window is currently open (drives the hysteresis band). */
    private static boolean open;
    private static int retryCountdown;
    private static int soundClock;

    private NetherPitPlume() {}

    /**
     * The opening show just finished: drop the retry backoff so the cloud materialises on
     * the next tick instead of up to {@value #RETRY_TICKS} ticks later. Purely cosmetic
     * timing — the probe still has the final say.
     */
    public static void onOpened() {
        retryCountdown = 0;
    }

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
        Vec3 anchor = lip.add(0.0D, PLUME_HOVER, 0.0D);
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        if (distSq > (open ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            close(true); // walked away: graceful fade, not a pop
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        if (open) {
            tickSoundBed(level, lip);
        }
        if (--retryCountdown > 0) {
            return;
        }
        // Physical probe: the crater interior is air below the lip only once the pit has
        // really been dug (the server's breachOpen flag is not client-readable).
        BlockPos probe = BlockPos.containing(lip.x, lip.y - PROBE_BELOW_LIP, lip.z);
        if (!level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                SectionPos.blockToSectionCoord(probe.getZ()))
                || !level.getBlockState(probe).isAir()) {
            close(false); // pit not open (yet) — keep probing on the cadence
            retryCountdown = RETRY_TICKS;
            return;
        }
        open = true;
        boolean live = PhotonFxRegistry.ensureLoop(
                NetherOpenPhotonFxRows.CUE_NETHER_PIT_PLUME, anchor);
        // Healthy leg: re-ensure every tick (idempotent prune + re-spawn of a pruned leg).
        // Refused (photon absent / missing asset / executor budget): back off RETRY_TICKS.
        retryCountdown = live ? 1 : RETRY_TICKS;
    }

    /** Quiet fire-crackle + deep-rumble bed under the cloud (vanilla distance falloff). */
    private static void tickSoundBed(ClientLevel level, Vec3 lip) {
        soundClock++;
        BlockPos at = BlockPos.containing(lip.x, lip.y + 1.0D, lip.z);
        if (soundClock % CRACKLE_INTERVAL_TICKS == 0) {
            level.playLocalSound(at, SoundEvents.FIRE_AMBIENT, SoundSource.AMBIENT,
                    CRACKLE_VOLUME, CRACKLE_PITCH, false);
        }
        if (soundClock % RUMBLE_INTERVAL_TICKS == 0) {
            level.playLocalSound(at, SoundEvents.AMBIENT_CAVE.value(), SoundSource.AMBIENT,
                    RUMBLE_VOLUME, RUMBLE_PITCH, false);
        }
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern; the registry releases too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        close(false);
    }

    private static void close(boolean graceful) {
        if (open) {
            PhotonFxRegistry.releaseLoop(NetherOpenPhotonFxRows.CUE_NETHER_PIT_PLUME, graceful);
        }
        open = false;
        retryCountdown = 0;
        soundClock = 0;
    }
}
