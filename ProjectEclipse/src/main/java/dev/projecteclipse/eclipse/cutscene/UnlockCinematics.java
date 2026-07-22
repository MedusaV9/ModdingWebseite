package dev.projecteclipse.eclipse.cutscene;

import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Ring-growth unlock cinematics: when an ANIMATED stage growth starts
 * ({@link WorldStageService.GrowthStartListener}), every player in the growing dimension is
 * frozen + made invulnerable and shown the {@code unlock_ring} orbital shot, anchored at the
 * point of the old ring edge nearest to them (the direction the new terrain will sweep
 * past first). The freeze rides the cutscene session: it releases on the client's FINISHED
 * ACK or the watchdog — and if the sweep finishes even earlier, the completion listener
 * aborts any still-running {@code unlock_ring} flights so nobody outlives the show.
 *
 * <p>Skipped entirely for the intro-fusion stage ({@code stages.json} trigger
 * {@code "intro_fusion"} — the start event owns that cinematography), for instant stamps and
 * erases, and when the {@code cutscenes.freezeDuringUnlocks} dev toggle ({@code general.json},
 * default true) is off. Players in a different dimension than the path targets (e.g. nether
 * growth vs. the overworld-scoped default {@code unlock_ring}) ACK-finish instantly and lose
 * the freeze right away — duplicate the path JSON with the other dimension to cover it.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class UnlockCinematics {
    private static final String PATH_ID = "unlock_ring";
    private static final AtomicBoolean LISTENERS_REGISTERED = new AtomicBoolean();

    private UnlockCinematics() {}

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENERS_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addGrowthStartListener(UnlockCinematics::onGrowthStart);
            WorldStageService.addListener(UnlockCinematics::onGrowthComplete);
            EclipseMod.LOGGER.info("UnlockCinematics registered as world-stage growth listeners");
        }
    }

    private static void onGrowthStart(ServerLevel level, DiscProfile profile, int fromStage,
            int toStage, boolean animate) {
        if (!animate || toStage <= fromStage) {
            return; // instant stamps and erases are not cinematic
        }
        if (!EclipseConfig.freezeDuringUnlocks()) {
            EclipseMod.LOGGER.info("UnlockCinematics: cutscenes.freezeDuringUnlocks is off — skipping");
            return;
        }
        EclipseConfig.StageEntry entry = EclipseConfig.stage(profile.name(), toStage);
        if (entry != null && "intro_fusion".equals(entry.trigger())) {
            return; // the start-event intro owns that moment (intro_rise is still playing)
        }
        List<ServerPlayer> watchers = List.copyOf(level.players());
        if (watchers.isEmpty()) {
            return;
        }
        int edgeRadius = StageRadii.radius(profile, fromStage);
        EclipseMod.LOGGER.info("UnlockCinematics: {} growth {} -> {} — freezing {} player(s) for '{}'",
                profile.name(), fromStage, toStage, watchers.size(), PATH_ID);
        for (ServerPlayer player : watchers) {
            // Per-player play: each watcher orbits the ring-edge point nearest to THEM.
            CutsceneService.play(PATH_ID, List.of(player), edgeAnchorFor(level, player, edgeRadius), null);
        }
    }

    /** Aborts (and thereby unfreezes) flights that outlive the sweep — usually a no-op. */
    private static void onGrowthComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage) {
        for (ServerPlayer player : level.players()) {
            if (PATH_ID.equals(CutsceneService.activePathId(player))) {
                EclipseMod.LOGGER.info("UnlockCinematics: growth complete — releasing {} from '{}'",
                        player.getScoreboardName(), PATH_ID);
                CutsceneService.abort(List.of(player));
            }
        }
    }

    /**
     * The old ring edge point nearest to the player (discs are origin-centered), at terrain
     * height — the {@code unlock_ring} keyframes are offsets around this anchor.
     */
    private static Vec3 edgeAnchorFor(ServerLevel level, ServerPlayer player, int edgeRadius) {
        double angle = Math.atan2(player.getZ(), player.getX());
        int x = Mth.floor(Math.cos(angle) * edgeRadius);
        int z = Mth.floor(Math.sin(angle) * edgeRadius);
        level.getChunk(x >> 4, z >> 4); // force-load before the height lookup
        int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (surfaceY <= level.getMinBuildHeight()) {
            surfaceY = level.getSeaLevel(); // void column beyond the disc: anchor at sea level
        }
        return new Vec3(x + 0.5D, surfaceY, z + 0.5D);
    }
}
