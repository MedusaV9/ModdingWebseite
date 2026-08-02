package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WAVE6 (F-106 B) — Team B's {@link PhotonFxRegistry} row registrar for the day-13
 * dragon stage ({@code worldgen/end/EclipseDragonFight}):
 *
 * <ul>
 *   <li><b>B2 {@code wave6_crystal_burst}</b> — one-shot cold End bloom + rising
 *       splinters fired by the server at the position of a destroyed spire crystal
 *       (payload lane, {@code FxPayloads.sendFxEvent}). Photon-only garnish: the
 *       vanilla crystal EXPLOSION is the photon-less baseline, so the Quasar leg is
 *       {@code null} (legal for NEW cues).</li>
 *   <li><b>B4 {@code wave6_dragon_wisp}</b> — quiet WINDOWED loop breathing over the
 *       dragon egg after the victory. The server publishes a {@link FxAnchors} anchor
 *       (re-published on every boot of a won save); the {@link DragonWisp} window below
 *       owns the hysteresis band and drives {@code ensureLoop/releaseLoop}.</li>
 * </ul>
 *
 * <p>Both assets are authored by {@code tools/photon/wave6_dragon_fx.py} (fxlib,
 * uuid5-deterministic) — re-run that script instead of hand-editing the gzip-NBT.
 * Cue/anchor ids are re-derived on both sides via {@code FxCues.cue(...)}
 * ({@code SmallCueFxRows}/{@code Wave5BossFxRows} two-sided precedent), so the frozen
 * {@code FxCues.java} stays untouched.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class Wave6DragonFxRows {
    /** B2 one-shot at a destroyed spire crystal (server fires the payload). */
    public static final ResourceLocation CUE_CRYSTAL_BURST = FxCues.cue("wave6_crystal_burst");
    /** B4 victory wisp — loop-row logical id AND the server's {@link FxAnchors} key. */
    public static final ResourceLocation CUE_DRAGON_WISP = FxCues.cue("wave6_dragon_wisp");

    private static final ResourceLocation CRYSTAL_BURST_FX =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wave6_crystal_burst");
    private static final ResourceLocation DRAGON_WISP_FX =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wave6_dragon_wisp");

    private Wave6DragonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // B2: BURST one-shot — the crystal death is a fight beat, not ambience. Quasar
        // leg null (new cue; the vanilla crystal explosion is the photon-less read).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CRYSTAL_BURST,
                CRYSTAL_BURST_FX,
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B4: AMBIENT loop — idles over the egg for minutes, must never outbid a burst.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_DRAGON_WISP,
                DRAGON_WISP_FX,
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
    }

    /**
     * B4 windowed-loop controller — the {@code Wave5BossFxRows.TrophyWisp} pattern for
     * ONE anchor: hysteresis band {@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}
     * around the {@link FxAnchors} egg anchor, overworld-gated (the End disc is an
     * overworld structure), healthy legs re-ensured every tick, refusals backed off
     * {@value #RETRY_TICKS} ticks. {@code reducedFx} skips the loop entirely — the egg
     * and portal blocks are the baseline read.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class DragonWisp {
        /** Close-look band: the wisp is a monument detail, not a landmark beacon. */
        static final double MATERIALIZE_DIST = 28.0D;
        static final double RELEASE_DIST = 36.0D;
        private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
        private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
        /** Refused-spawn retry cadence (ticks) — the NetherPitPlume cadence. */
        private static final int RETRY_TICKS = 40;

        private static boolean open;
        private static int retryCountdown;

        private DragonWisp() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            Minecraft minecraft = Minecraft.getInstance();
            ClientLevel level = minecraft.level;
            if (level == null || EclipseClientConfig.reducedFx()) {
                close(false);
                return;
            }
            Vec3 anchor = FxAnchors.get(CUE_DRAGON_WISP);
            if (anchor == null || level.dimension() != Level.OVERWORLD) {
                close(false);
                return;
            }
            double distSq = minecraft.gameRenderer.getMainCamera().getPosition()
                    .distanceToSqr(anchor);
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
            open = true;
            retryCountdown = PhotonFxRegistry.ensureLoop(CUE_DRAGON_WISP, anchor) ? 1 : RETRY_TICKS;
        }

        /** Disconnect reset (the registry's own DisconnectReset releases the legs too). */
        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            close(false);
        }

        private static void close(boolean graceful) {
            if (open) {
                PhotonFxRegistry.releaseLoop(CUE_DRAGON_WISP, graceful);
            }
            open = false;
            retryCountdown = 0;
        }
    }
}
