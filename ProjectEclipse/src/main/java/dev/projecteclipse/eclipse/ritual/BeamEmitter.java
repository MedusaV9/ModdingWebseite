package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.List;

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

    /** W4-CEREMONY / IDEA-10 #1: witness-ring geometry — beams orbit at this radius. */
    private static final double WITNESS_RING_RADIUS = 2.5D;
    /** Budget cap on extra ring beams per burst (a bigger crowd shares the same ring). */
    private static final int WITNESS_RING_MAX_BEAMS = 8;
    /** Slow ring rotation (radians per game tick) so the circle visibly breathes. */
    private static final double WITNESS_RING_SPIN = 0.02D;

    private BeamEmitter() {}

    /** Emits one beam burst at the given altar position. Call every few ticks while a ritual runs. */
    public static void emit(ServerLevel level, BlockPos altarPos) {
        emit(level, altarPos, 0);
    }

    /**
     * W4-CEREMONY / IDEA-10 #1 — witness circle overload (additive; the no-witness call is
     * byte-identical to the classic single beam): the central {@code ALTAR_BEAM} plus one
     * staggered ring beam per witness (capped at {@value #WITNESS_RING_MAX_BEAMS}), evenly
     * spread on a slowly rotating {@value #WITNESS_RING_RADIUS}-block circle — the crowd is
     * visible in the monument itself.
     */
    public static void emit(ServerLevel level, BlockPos altarPos, int witnesses) {
        double x = altarPos.getX() + 0.5D;
        double y0 = altarPos.getY();
        double z = altarPos.getZ() + 0.5D;
        double rangeSqr = VIEW_RANGE * VIEW_RANGE;

        List<S2CQuasarPayload> payloads = new ArrayList<>(1 + Math.max(0, witnesses));
        payloads.add(new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, new Vec3(x, y0 + 1.0D, z)));
        int ringBeams = Math.min(Math.max(0, witnesses), WITNESS_RING_MAX_BEAMS);
        if (ringBeams > 0) {
            double spin = level.getGameTime() * WITNESS_RING_SPIN;
            for (int i = 0; i < ringBeams; i++) {
                double angle = spin + (Math.PI * 2.0D * i) / ringBeams;
                payloads.add(new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, new Vec3(
                        x + Math.cos(angle) * WITNESS_RING_RADIUS,
                        y0 + 1.0D,
                        z + Math.sin(angle) * WITNESS_RING_RADIUS)));
            }
        }
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(x, y0, z) <= rangeSqr) {
                for (S2CQuasarPayload payload : payloads) {
                    PacketDistributor.sendToPlayer(player, payload);
                }
            }
        }
    }
}
