package dev.projecteclipse.eclipse.worldgen.stage;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.network.S2CCutscenePayload;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The intro fusion: the special overworld stage 0 → 1 growth played right after the
 * start-event cutscene, where the void between the main disc and the eight player discs
 * fills in over ~60–90 s.
 *
 * <p><b>Ordering</b>: unlike a normal ring sweep, fusion columns are ordered by distance
 * to the NEAREST pre-existing disc edge (main-disc rim r=96 or any player-disc rim r=24
 * around the r=170 ring, {@link #distanceToNearestDiscEdge}) — land grows outward from the
 * main disc and outward from every player disc at the same time, so the land bridges race
 * toward each other and fuse in the middle of the gap. {@link RingGrowthService} asks
 * {@link #isIntroFusion} per job and uses this ordering instead of radius-then-angle.</p>
 *
 * <p><b>Trigger</b>: {@link #maybeStartIntroFusion} runs once per world — called by
 * {@code limbo.StartEventCutscene} at the moment {@code startEventDone} flips true, and
 * guarded on "overworld stage is still 0" + "stage 1 trigger is {@code intro_fusion}"
 * (stages.json). W6's cinematics should call the same method (idempotent) if it wants to
 * own the timing instead.</p>
 *
 * <p><b>Presentation</b>: while the fusion sweep runs, every {@value #RUMBLE_INTERVAL_TICKS}
 * ticks each online player gets a low-pitched thunder rumble and one
 * {@link S2CCutscenePayload} {@code SHAKE} pulse (clients treat every received SHAKE as a
 * ~2 s camera-shake impulse — W6 owns the visual).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FusionSequence {
    /** One rumble + shake pulse every 2 s while fusion runs. */
    private static final int RUMBLE_INTERVAL_TICKS = 40;

    private FusionSequence() {}

    /**
     * Starts the intro fusion (overworld stage 0 → 1, animated) if it never ran: no-op
     * unless the committed overworld stage is 0 and stages.json marks stage 1 as
     * {@code intro_fusion}. Returns whether the fusion actually started.
     */
    public static boolean maybeStartIntroFusion(MinecraftServer server) {
        if (WorldStageService.stage(server, DiscProfile.OVERWORLD) != 0) {
            return false; // already fused (or beyond) — the once-per-world guard
        }
        EclipseConfig.StageEntry stageOne = EclipseConfig.stage("overworld", 1);
        if (stageOne == null || !"intro_fusion".equals(stageOne.trigger())) {
            EclipseMod.LOGGER.info("Intro fusion skipped: overworld stage 1 trigger is {}",
                    stageOne == null ? "unconfigured" : stageOne.trigger());
            return false;
        }
        EclipseMod.LOGGER.info("Intro fusion starting: overworld stage 0 -> 1 (post-cutscene)");
        return WorldStageService.setStage(server, Level.OVERWORLD, 1, true);
    }

    /**
     * Whether a stage transition is the intro fusion (drives the special column ordering —
     * also applied to instant/rebuild 0→1 stamps, where ordering is invisible but staying
     * deterministic keeps growth-cursor resumes exact).
     */
    static boolean isIntroFusion(DiscProfile profile, int fromStage, int toStage) {
        return profile == DiscProfile.OVERWORLD && fromStage == 0 && toStage >= 1;
    }

    /**
     * Distance (blocks, floored) from column (x, z) to the nearest stage-0 disc edge:
     * {@code |r − 96|} for the main disc, {@code |dist(center_i) − 24|} for each of the
     * eight player discs. The fusion sweep sorts ascending on this.
     */
    static int distanceToNearestDiscEdge(int x, int z) {
        double best = Math.abs(Math.sqrt((double) x * x + (double) z * z) - DiscGeometry.MAIN_DISC_RADIUS);
        for (int i = 0; i < DiscGeometry.PLAYER_DISC_COUNT; i++) {
            BlockPos center = DiscGeometry.playerDiscCenter(i);
            double dx = x - center.getX();
            double dz = z - center.getZ();
            double edge = Math.abs(Math.sqrt(dx * dx + dz * dz) - DiscGeometry.PLAYER_DISC_RADIUS);
            if (edge < best) {
                best = edge;
            }
        }
        return (int) best;
    }

    /** Rumble + camera-shake pulses for as long as the fusion sweep is running. */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % RUMBLE_INTERVAL_TICKS != 0
                || !RingGrowthService.isRunningIntroFusion()) {
            return;
        }
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.SHAKE));
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.AMBIENT, 0.6F, 0.5F);
        }
    }
}
