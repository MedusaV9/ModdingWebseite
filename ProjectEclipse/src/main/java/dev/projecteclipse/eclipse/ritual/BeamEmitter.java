package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.List;

import org.joml.Vector3f;

import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;

/**
 * Sends the revive ritual's vertical beam — end-rod plus purple dust particle
 * columns from the altar up to the world's max build height (~y 320) — to every
 * player within {@value #VIEW_RANGE} blocks. Uses per-player
 * {@link ServerLevel#sendParticles(ServerPlayer, net.minecraft.core.particles.ParticleOptions, boolean, double, double, double, int, double, double, double, double)}
 * (packet-based, so Iris/Sodium-safe: no custom rendering involved).
 */
public final class BeamEmitter {
    /** Players within this many blocks of the altar receive the beam packets. */
    public static final double VIEW_RANGE = 512.0D;
    /** Vertical spacing between particle bursts in the column. */
    private static final int COLUMN_STEP = 4;

    private static final DustParticleOptions PURPLE_DUST =
            new DustParticleOptions(new Vector3f(0.55F, 0.15F, 0.85F), 1.6F);

    private BeamEmitter() {}

    /** Emits one beam burst at the given altar position. Call every few ticks while a ritual runs. */
    public static void emit(ServerLevel level, BlockPos altarPos) {
        double x = altarPos.getX() + 0.5D;
        double y0 = altarPos.getY();
        double z = altarPos.getZ() + 0.5D;
        double rangeSqr = VIEW_RANGE * VIEW_RANGE;

        List<ServerPlayer> receivers = new ArrayList<>();
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(x, y0, z) <= rangeSqr) {
                receivers.add(player);
            }
        }
        if (receivers.isEmpty()) {
            return;
        }
        int top = level.getMaxBuildHeight();
        for (int y = altarPos.getY() + 1; y <= top; y += COLUMN_STEP) {
            for (ServerPlayer player : receivers) {
                level.sendParticles(player, ParticleTypes.END_ROD, true,
                        x, y, z, 2, 0.12D, 1.5D, 0.12D, 0.01D);
                level.sendParticles(player, PURPLE_DUST, true,
                        x, y + 2.0D, z, 2, 0.25D, 1.5D, 0.25D, 0.0D);
            }
        }
    }
}
