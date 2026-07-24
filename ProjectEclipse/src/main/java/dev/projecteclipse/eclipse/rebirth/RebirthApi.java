package dev.projecteclipse.eclipse.rebirth;

import java.util.UUID;

import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * Frozen rebirth surface (D11). Consumers: PLANNER-A / W-SKILLTREE's rebirth UI (footer
 * section of the skill tree screen renders {@link #costForNext} + {@link #count} from the
 * synced {@code S2CRebirthStatePayload} and sends {@code C2SRebirthPayload});
 * {@code skills.RebirthHooks.curveFor} applies {@link #levelCostMultiplier} to every
 * per-player skill-curve lookup.
 */
public final class RebirthApi {
    /** Outcome of one {@link #tryRebirth} transaction (all-or-nothing on the server thread). */
    public enum Result {
        /** Ceremony completed: shards consumed, progression wiped, +Leben granted, count bumped. */
        OK,
        /** Player is dead/disconnecting — no transaction. */
        NOT_ALIVE,
        /** Player stands in an event dimension (limbo/minigame/xbox) — no transaction. */
        EVENT_DIMENSION,
        /** Personal umbral-shard balance below {@link #costForNext} — nothing changes. */
        NOT_ENOUGH_SHARDS,
        /** Already at {@code HeartsService.MAX_HEARTS} — the +1 Leben would burn; refused. */
        AT_LIFE_CAP,
        /** {@code maxRebirths} config cap reached — refused. */
        MAX_REBIRTHS
    }

    private RebirthApi() {}

    /** Personal-shard price of the player's NEXT rebirth: {@code round(base * growth^count)}. */
    public static int costForNext(MinecraftServer server, UUID uuid) {
        return RebirthConfig.get().costForCount(count(server, uuid));
    }

    /** Completed rebirths (persisted; offline players included). */
    public static int count(MinecraftServer server, UUID uuid) {
        return RebirthState.get(server).count(uuid);
    }

    /**
     * Global skill level-cost multiplier: {@code levelCostMultiplierPerRebirth ^ count}.
     * Exactly {@code 1.0} for players who never rebirthed (the {@code RebirthHooks} fast
     * path relies on that).
     */
    public static double levelCostMultiplier(MinecraftServer server, UUID uuid) {
        return RebirthConfig.get().levelCostMultiplier(count(server, uuid));
    }

    /**
     * Validates and (when every precondition holds) executes one full rebirth ceremony.
     * See {@link RebirthService#tryRebirth} for the transaction order.
     */
    public static Result tryRebirth(ServerPlayer player) {
        return RebirthService.tryRebirth(player);
    }
}
