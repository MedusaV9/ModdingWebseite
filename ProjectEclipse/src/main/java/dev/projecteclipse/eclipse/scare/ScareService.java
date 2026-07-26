package dev.projecteclipse.eclipse.scare;

import java.util.concurrent.ThreadLocalRandom;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CScareCuePayload;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server half of the Scare framework (F-064): fires one {@code S2CScareCuePayload} at
 * exactly ONE player. All presentation is client-side ({@code client.scare.ScareDirector});
 * the server's whole job is picking the target, the script id and the per-run seed.
 * Deliberately no broadcast variant — scares are personal by design (the psychothriller
 * law: nobody else must be able to tell it happened).
 */
public final class ScareService {
    private ScareService() {}

    /**
     * Sends the scare cue with a fresh random seed. {@code scareId} must be one of the
     * {@link ScareIds} names — unknown ids are refused here (log, no send) so a typo in a
     * future call site can never put a dead payload on the wire.
     */
    public static void send(ServerPlayer player, String scareId) {
        send(player, scareId, ThreadLocalRandom.current().nextLong());
    }

    /** Seeded form ({@link ScareTripService} re-uses one seed across the trip's beats). */
    public static void send(ServerPlayer player, String scareId, long seed) {
        if (!ScareIds.isKnown(scareId)) {
            EclipseMod.LOGGER.warn("Refusing unknown scare id '{}' for {}", scareId,
                    player.getScoreboardName());
            return;
        }
        PacketDistributor.sendToPlayer(player, new S2CScareCuePayload(scareId, seed));
        EclipseMod.LOGGER.info("Scare '{}' sent to {} (seed {})", scareId,
                player.getScoreboardName(), Long.toHexString(seed));
    }
}
