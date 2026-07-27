package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * WOAH-05 site materialization (plan §2.1) — exactly the {@code worldgen/fog/
 * FogStormSites} two-phase pattern: a {@code WorldStageService} listener enqueues a
 * pending row when overworld stage-4 terrain completes; the registered async placer
 * runs {@link SitePrep#preparePlateau}, hands the footprint to
 * {@link EchoGroveTerraformer}, finishes with {@link SitePrep#finish} and persists
 * {@code placed=true} in {@link EchoGroveState}. Landmark discovery (the
 * {@code CUE_LANDMARK_DISCOVERED} flare) rides the existing sweep for free where the
 * frozen map carries the row.
 *
 * <p><b>Frozen-map fallback:</b> coordinates come from {@link EchoGroveLayout}
 * (landmark row preferred, code constant otherwise); on fallback we only log a
 * collision warning — old saves can't re-check the authored map (plan §11.1).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoGroveSites {
    public static final String STRUCTURE_ID = "eclipse:echo_grove";
    /** Stray-sweep tag for dynamic scene displays (CreditsFormationAct despawn law). */
    public static final String SCENE_DISPLAY_TAG = "eclipse_echo_scene";

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private EchoGroveSites() {}

    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(EchoGroveSites::onStageTerrainComplete);
            EclipseMod.LOGGER.info("EchoGroveSites registered as world-stage listener");
        }
        StructurePendingRegistry.registerAsyncPlacer(STRUCTURE_ID,
                (level, pending, complete, failure) -> materialize(level, complete, failure));
    }

    /** Stray-sweep for dynamic scene displays that a crash left behind (plan §3.4). */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        ServerLevel overworld = event.getServer().overworld();
        int swept = 0;
        for (Entity entity : overworld.getEntities(EntityType.BLOCK_DISPLAY,
                e -> e.getTags().contains(SCENE_DISPLAY_TAG))) {
            entity.discard();
            swept++;
        }
        if (swept > 0) {
            EclipseMod.LOGGER.info("EchoGroveSites: swept {} stray scene display(s)", swept);
        }
        if (!EchoGroveLayout.landmarkFrozen()) {
            EclipseMod.LOGGER.warn("EchoGroveSites: frozen disc_map.json has no {} row — using "
                    + "code fallback ({}, {}); collisions against relocated authored points "
                    + "cannot be re-checked on this save", EchoGroveLayout.LANDMARK_ID,
                    EchoGroveLayout.FALLBACK_X, EchoGroveLayout.FALLBACK_Z);
        }
    }

    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile != DiscProfile.OVERWORLD || toStage <= fromStage) {
            return; // rollbacks never un-build the grove — the site is final (plan §2.2)
        }
        int stage = landmarkStage();
        if (stage > toStage || stage <= fromStage) {
            return;
        }
        if (EchoGroveState.get(level.getServer()).placed()) {
            return;
        }
        int[] xz = EchoGroveLayout.landmarkXZ();
        BlockPos center = new BlockPos(xz[0], EchoGroveLayout.plateauY(xz[0], xz[1]), xz[1]);
        StructurePendingRegistry.enqueue(new PendingSite(EchoGroveLayout.LANDMARK_ID, STRUCTURE_ID,
                DiscProfile.OVERWORLD.name(), center, stage, EchoGroveLayout.RADIUS * 2,
                level.getGameTime()));
    }

    private static int landmarkStage() {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.OVERWORLD)) {
            if (EchoGroveLayout.LANDMARK_ID.equals(landmark.id())) {
                return landmark.stage();
            }
        }
        return 4;
    }

    /** Dev entry ({@code /dev woah echo spawn}) — stage-independent immediate build. */
    public static void materializeNow(ServerLevel level) {
        materializeNow(level, () -> {},
                error -> EclipseMod.LOGGER.error("Echo grove placement failed", error));
    }

    /** Dev entry with completion callbacks (the ChronoStasisSite.materialize seam). */
    public static void materializeNow(ServerLevel level, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        materialize(level, onComplete, onFailure);
    }

    private static void materialize(ServerLevel level, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        if (EchoGroveState.get(level.getServer()).placed()) {
            onComplete.run();
            return;
        }
        int[] xz = EchoGroveLayout.landmarkXZ();
        int radius = EchoGroveLayout.RADIUS;
        BlockPos center = new BlockPos(xz[0], EchoGroveLayout.plateauY(xz[0], xz[1]), xz[1]);
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                xz[0] - radius, xz[1] - radius, xz[0] + radius, xz[1] + radius, center);
        prepared.whenReady(() -> EchoGroveTerraformer.terraform(level, center, () -> {
            SitePrep.finish(level, prepared);
            BlockPos treeCenter = center.below(EchoGroveLayout.BOWL_DEPTH);
            EchoGroveState.get(level.getServer()).setPlaced(treeCenter);
            EchoGrovePayloads.syncAll(level.getServer());
            EclipseMod.LOGGER.info("EchoGroveSites: materialized echo grove at {}", center);
            onComplete.run();
        }, onFailure), onFailure);
    }
}
