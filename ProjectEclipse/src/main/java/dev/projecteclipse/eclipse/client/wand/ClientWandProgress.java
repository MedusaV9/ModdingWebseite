package dev.projecteclipse.eclipse.client.wand;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.network.wand.S2CWandProgressPayload;
import dev.projecteclipse.eclipse.wand.WandPath;
import net.minecraft.Util;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Client cache of the {@code S2CWandProgressPayload} sync (V6-FIXWIRE #5; the
 * {@code ClientRebirthState} pattern). {@link WandProgressPanel} reads the SERVER's wand
 * tuning from here — power costs/cooldowns, the level-cost curve, charge max, the
 * earn-hint numbers — instead of the client's own local {@code WandConfig} file, which
 * only matched on singleplayer. Live level/xp/charge stay read from the synced item
 * components (they mirror the server store every tick); this cache carries what the
 * components cannot: config numbers and per-power cooldown state.
 *
 * <p>Cooldowns arrive as remaining ticks and are pinned to wall-clock millis on receipt
 * ({@link #cooldownRemainingSeconds}), so the panel's countdown keeps running between
 * payloads without needing a shared game-time base.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class ClientWandProgress {
    /** One power's synced tuning ({@code cooldownExpiresAtMillis} 0 = ready). */
    public record Power(int cost, int cooldownTicks, long cooldownExpiresAtMillis) {}

    /** False until the first payload lands — the panel renders its syncing hint. */
    public static volatile boolean synced = false;
    public static volatile int level = 1;
    public static volatile int xp = 0;
    public static volatile int chargeMax = 100;
    public static volatile float xpPerCostPoint = 0.0F;
    public static volatile float xpKillBonus = 0.0F;
    private static volatile List<Integer> levelCosts = List.of();
    private static final Map<String, Power> POWERS = new ConcurrentHashMap<>();

    private ClientWandProgress() {}

    /** Payload-handler entry point ({@code WandPayloads.handleProgress}). */
    public static void update(S2CWandProgressPayload payload) {
        level = payload.level();
        xp = payload.xp();
        chargeMax = Math.max(1, payload.chargeMax());
        xpPerCostPoint = payload.xpPerCostPoint();
        xpKillBonus = payload.xpKillBonus();
        levelCosts = payload.levelCosts();
        long now = Util.getMillis();
        POWERS.clear();
        for (S2CWandProgressPayload.PowerRow row : payload.powers()) {
            long expires = row.cooldownRemainingTicks() > 0
                    ? now + row.cooldownRemainingTicks() * 50L : 0L;
            POWERS.put(row.key(), new Power(row.cost(), row.cooldownTicks(), expires));
        }
        synced = true;
    }

    /** Server-synced XP needed to leave {@code currentLevel} (mirror of {@code WandConfig.Xp}). */
    public static int costForLevel(int currentLevel) {
        List<Integer> costs = levelCosts;
        if (currentLevel >= WandPath.MAX_LEVEL || costs.isEmpty()) {
            return Integer.MAX_VALUE;
        }
        return costs.get(Math.max(0, Math.min(costs.size() - 1, currentLevel - 1)));
    }

    /** Server-synced power tuning; a safe stub before/without a row (panel guards on {@link #synced}). */
    public static Power power(String key) {
        Power power = POWERS.get(key);
        return power != null ? power : new Power(0, 0, 0L);
    }

    /** Seconds left on this power's cooldown right now (0 = ready). */
    public static int cooldownRemainingSeconds(String key) {
        long expires = power(key).cooldownExpiresAtMillis();
        return expires <= 0L ? 0 : (int) Math.max(0L, (expires - Util.getMillis() + 999L) / 1000L);
    }

    public static void reset() {
        synced = false;
        level = 1;
        xp = 0;
        chargeMax = 100;
        xpPerCostPoint = 0.0F;
        xpKillBonus = 0.0F;
        levelCosts = List.of();
        POWERS.clear();
    }

    /** Disconnect reset ({@code ClientRebirthState.DisconnectReset} pattern). */
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
