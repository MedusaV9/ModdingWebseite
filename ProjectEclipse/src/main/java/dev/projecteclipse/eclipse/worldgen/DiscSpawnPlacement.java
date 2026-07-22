package dev.projecteclipse.eclipse.worldgen;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Pins the overworld spawn to the disc center: (0, surface + 1, 0) — the flat spawn pad
 * the terrain function carves for the altar + sanctum. Runs at {@link EventPriority#HIGH}
 * so it precedes {@code BorderController}, which centers the world border on the spawn at
 * the same event. Vanilla's initial spawn search may wander (its climate sampler is a
 * dummy for non-noise generators), and manual {@code /setworldspawn} edits should not
 * survive a restart, so this re-pins on EVERY server start.
 *
 * <p>v1 start-event flow is untouched: {@code StartEventCutscene} teleports players from
 * limbo to {@code overworld.getSharedSpawnPos()} — exactly the position enforced here.
 * Per-player disc starts (if worker 6 wants them) go through
 * {@link DiscGeometry#playerDiscCenter(int)} instead.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DiscSpawnPlacement {
    private DiscSpawnPlacement() {}

    @SubscribeEvent(priority = EventPriority.HIGH)
    public static void onServerStarted(ServerStartedEvent event) {
        ServerLevel overworld = event.getServer().overworld();
        if (!(overworld.getChunkSource().getGenerator() instanceof DiscChunkGenerator generator)) {
            return;
        }
        DiscProfile profile = generator.profile();
        BlockPos spawn = new BlockPos(0, DiscTerrainFunction.surfaceY(profile, 0, 0) + 1, 0);
        overworld.setDefaultSpawnPos(spawn, 0.0F);
        EclipseMod.LOGGER.info(
                "Eclipse disc world active (generator eclipse:disc, stage {}): spawn pinned to ({}, {}, {})",
                WorldStageAccess.stage(profile), spawn.getX(), spawn.getY(), spawn.getZ());
    }
}
