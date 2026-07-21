package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseParticles;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Spawns 1-2 {@code eclipse:purple_wisp} particles near the right arm of every visible player
 * that carries the arm artifact, every {@value #SPAWN_INTERVAL_TICKS} client ticks.
 *
 * <p>Remote players' full inventories are not synced to this client, so for them the check
 * falls back to the visible held items (main/off hand); the local player is checked against
 * the whole inventory (where the artifact is slot-locked anyway).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ArmParticles {
    private static final int SPAWN_INTERVAL_TICKS = 4;
    /** Horizontal distance from the body center to the right arm. */
    private static final double ARM_OFFSET = 0.38D;

    private ArmParticles() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || minecraft.isPaused() || level.getGameTime() % SPAWN_INTERVAL_TICKS != 0) {
            return;
        }
        for (Player player : level.players()) {
            if (!player.isInvisible() && hasArtifact(minecraft, player)) {
                spawnWisps(level, player);
            }
        }
    }

    private static boolean hasArtifact(Minecraft minecraft, Player player) {
        Item artifact = EclipseItems.ARM_ARTIFACT.get();
        if (player == minecraft.player) {
            return player.getInventory().contains(stack -> stack.is(artifact));
        }
        return player.getMainHandItem().is(artifact) || player.getOffhandItem().is(artifact);
    }

    /** Approximates the right arm from body yaw: right = (-cos(yaw), 0, -sin(yaw)). */
    private static void spawnWisps(ClientLevel level, Player player) {
        float yawRad = player.yBodyRot * Mth.DEG_TO_RAD;
        double armX = player.getX() - Math.cos(yawRad) * ARM_OFFSET;
        double armZ = player.getZ() - Math.sin(yawRad) * ARM_OFFSET;
        double armY = player.getY() + (player.isCrouching() ? 0.85D : 1.05D);

        int count = 1 + level.random.nextInt(2);
        for (int i = 0; i < count; i++) {
            level.addParticle(EclipseParticles.PURPLE_WISP.get(),
                    armX + (level.random.nextDouble() - 0.5D) * 0.15D,
                    armY + (level.random.nextDouble() - 0.5D) * 0.35D,
                    armZ + (level.random.nextDouble() - 0.5D) * 0.15D,
                    (level.random.nextDouble() - 0.5D) * 0.01D,
                    0.015D + level.random.nextDouble() * 0.01D,
                    (level.random.nextDouble() - 0.5D) * 0.01D);
        }
    }
}
