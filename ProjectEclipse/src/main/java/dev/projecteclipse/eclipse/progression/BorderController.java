package dev.projecteclipse.eclipse.progression;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.border.WorldBorder;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Owns the overworld world border (vanilla mirrors it into the other dimensions).
 * The border is always centered on the shared world spawn; the authoritative size lives
 * in {@link EclipseWorldState#getBorderSize()} (default 1000) and is re-enforced on every
 * server start so manual {@code /worldborder} edits do not survive a restart.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BorderController {
    private BorderController() {}

    /**
     * Re-centers the border on the world spawn and moves it to {@code size} blocks over
     * {@code ms} milliseconds ({@code ms <= 0} snaps instantly). The new size is persisted
     * in {@link EclipseWorldState}.
     */
    public static void setBorder(MinecraftServer server, double size, long ms) {
        ServerLevel overworld = server.overworld();
        WorldBorder border = overworld.getWorldBorder();
        BlockPos spawn = overworld.getSharedSpawnPos();
        border.setCenter(spawn.getX() + 0.5D, spawn.getZ() + 0.5D);
        if (ms <= 0L) {
            border.setSize(size);
        } else {
            border.lerpSizeBetween(border.getSize(), size, ms);
        }
        EclipseWorldState.get(server).setBorderSize(size);
        EclipseMod.LOGGER.info("Eclipse world border set to {} over {} ms, centered on spawn ({}, {})",
                size, ms, spawn.getX(), spawn.getZ());
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        double size = EclipseWorldState.get(server).getBorderSize();
        setBorder(server, size, 0L);
        EclipseMod.LOGGER.info("Eclipse world border enforced at startup: size {}", size);
    }
}
