package dev.projecteclipse.eclipse.client.skills;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Client-side cache of the rebirth sync (wave-5 A14 UI half; server half is W-REBIRTH's
 * {@code rebirth/RebirthService}, PLAN-D D11 / PLAN-A A13). The {@code SkillTreeScreen}
 * footer renders rebirth count + next umbral-splinter cost from these fields and stays in
 * its LOCKED state until the first sync arrives ({@link #synced}).
 *
 * <p>// SEAM(W-REBIRTH): {@code S2CRebirthStatePayload} (count, next cost, multiplier —
 * PLAN-D D11 §5) is defined and registered by the rebirth package. Its CLIENT handler
 * must call {@link #update(int, int, float)} so this cache (and the skill screen footer)
 * reflects server truth. Affordability is derived from the already-synced personal
 * splinter balance ({@code ClientStateCache.sidebarShards}, sent via
 * {@code S2CSidebarStatePayload}); no extra balance sync is required.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class ClientRebirthState {
    /** False until the first {@code S2CRebirthStatePayload} lands — footer renders locked. */
    public static volatile boolean synced = false;
    /** Completed rebirths of the local player. */
    public static volatile int count = 0;
    /** Umbral-splinter cost of the NEXT rebirth ({@code RebirthApi.costForNext}). */
    public static volatile int nextCostShards = 0;
    /** Current per-rebirth level-cost multiplier ({@code RebirthApi.levelCostMultiplier}). */
    public static volatile float levelCostMultiplier = 1.0F;

    private ClientRebirthState() {}

    /** Payload-handler entry point (see the class-level SEAM note). */
    public static void update(int rebirthCount, int nextCost, float multiplier) {
        count = Math.max(0, rebirthCount);
        nextCostShards = Math.max(0, nextCost);
        levelCostMultiplier = multiplier > 0.0F ? multiplier : 1.0F;
        synced = true;
    }

    public static void reset() {
        synced = false;
        count = 0;
        nextCostShards = 0;
        levelCostMultiplier = 1.0F;
    }

    /**
     * Disconnect reset ({@code ClientStateCache.DisconnectReset} pattern) — the next
     * server join must not inherit the previous session's rebirth footer state.
     */
    @net.neoforged.fml.common.EventBusSubscriber(modid = dev.projecteclipse.eclipse.EclipseMod.MOD_ID,
            value = Dist.CLIENT)
    static final class DisconnectReset {
        private DisconnectReset() {}

        @net.neoforged.bus.api.SubscribeEvent
        static void onLoggingOut(net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent.LoggingOut event) {
            reset();
        }
    }
}
