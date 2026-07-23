package dev.projecteclipse.eclipse.core.util;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.food.FoodData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Single-writer exhaustion scaler shared by skill perks (T3 Iron Stomach) and timed buffs
 * (half hunger). Factors register under stable string keys; a 20-tick server sweep multiplies
 * all active factors and scales each online player's exhaustion delta for that tick.
 *
 * <p>Factors return {@code 1.0f} for neutral. Values below {@code 1.0f} reduce hunger drain;
 * values above {@code 1.0f} increase it. The product of all factors is clamped to
 * {@code [0, 4]} to avoid runaway modifiers.</p>
 */
@EventBusSubscriber(modid = dev.projecteclipse.eclipse.EclipseMod.MOD_ID)
public final class ExhaustionScaler {
    private static final int SWEEP_INTERVAL_TICKS = 20;

    // statics reset on ServerStopped
    private static final Map<String, Supplier<Float>> FACTORS = new ConcurrentHashMap<>();
    private static int tickCounter = 0;
    private static final Map<java.util.UUID, Float> lastExhaustion = new ConcurrentHashMap<>();

    private ExhaustionScaler() {}

    /**
     * Registers or replaces a named exhaustion factor supplier. Call from
     * {@link net.neoforged.neoforge.event.server.ServerStartedEvent} in the owning package.
     *
     * @param key      stable id (e.g. {@code skill_iron_stomach}, {@code buff_half_hunger})
     * @param supplier returns multiplier for the current tick; {@code 1.0f} = no change
     */
    public static void registerFactor(String key, Supplier<Float> supplier) {
        FACTORS.put(key, supplier);
    }

    /** Removes a factor by key (e.g. on feature disable). */
    public static void unregisterFactor(String key) {
        FACTORS.remove(key);
    }

    /** Combined multiplier from all registered factors this tick. */
    public static float combinedMultiplier() {
        float product = 1.0F;
        for (Supplier<Float> supplier : FACTORS.values()) {
            product *= supplier.get();
        }
        return Math.clamp(product, 0.0F, 4.0F);
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (++tickCounter < SWEEP_INTERVAL_TICKS) {
            return;
        }
        tickCounter = 0;

        float multiplier = combinedMultiplier();
        if (Math.abs(multiplier - 1.0F) < 1.0E-4F) {
            lastExhaustion.clear();
            return;
        }

        ServerLevel overworld = event.getServer().overworld();
        for (ServerPlayer player : overworld.players()) {
            FoodData food = player.getFoodData();
            java.util.UUID id = player.getUUID();
            float current = food.getExhaustionLevel();
            Float previous = lastExhaustion.get(id);
            if (previous != null) {
                float delta = current - previous;
                if (delta > 0.0F) {
                    float scaled = previous + delta * multiplier;
                    food.setExhaustion(scaled);
                    current = scaled;
                }
            }
            lastExhaustion.put(id, current);
        }

        // Drop snapshots for players who went offline this interval.
        lastExhaustion.keySet().removeIf(uuid -> overworld.getServer().getPlayerList().getPlayer(uuid) == null);
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        FACTORS.clear();
        lastExhaustion.clear();
        tickCounter = 0;
        EclipseMod.LOGGER.debug("ExhaustionScaler factors and snapshots cleared");
    }
}
