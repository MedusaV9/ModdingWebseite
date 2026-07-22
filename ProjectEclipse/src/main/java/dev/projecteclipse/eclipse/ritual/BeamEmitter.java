package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Sends the revive ritual's vertical beam to every player within {@value #VIEW_RANGE} blocks.
 *
 * <p>v2: one {@link S2CQuasarPayload} per receiver per burst spawns the
 * {@code eclipse:altar_beam} Quasar emitter (violet additive column shooting upward from the
 * altar) instead of the v1 END_ROD/dust {@code sendParticles} column — far fewer packets
 * (1 instead of ~160 per receiver per burst). The client handler
 * ({@code veilfx.QuasarSpawner#spawnOrFallback}) falls back to a small vanilla END_ROD/PORTAL
 * burst if Quasar is unavailable, so the ritual cue is never lost.</p>
 */
public final class BeamEmitter {
    /** Players within this many blocks of the altar receive the beam packets. */
    public static final double VIEW_RANGE = 512.0D;

    private BeamEmitter() {}

    /** Emits one beam burst at the given altar position. Call every few ticks while a ritual runs. */
    public static void emit(ServerLevel level, BlockPos altarPos) {
        double x = altarPos.getX() + 0.5D;
        double y0 = altarPos.getY();
        double z = altarPos.getZ() + 0.5D;
        double rangeSqr = VIEW_RANGE * VIEW_RANGE;

        S2CQuasarPayload payload = new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, new Vec3(x, y0 + 1.0D, z));
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(x, y0, z) <= rangeSqr) {
                PacketDistributor.sendToPlayer(player, payload);
            }
        }
    }
}
