package dev.projecteclipse.eclipse.eventdim;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.function.BiFunction;
import java.util.function.Function;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.backrooms.BackroomsEventService;
import dev.projecteclipse.eclipse.xboxevent.XboxEventConfig;
import dev.projecteclipse.eclipse.xboxevent.XboxEventService;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.RandomSource;

/**
 * The portal-event variant registry (plans_v5 PLAN-C C18 §6/§7 — "more unique portals
 * later"): every one-off event dimension registers an open/close pair plus a rarity
 * weight here, and {@code /dev portal <variant> open|close} (plus the weighted
 * {@code /dev portal roll}) drives them through ONE surface. The 1-page recipe for
 * adding a variant lives in {@code docs/plans_v3/plans_v5/PORTAL_RECIPE.md}.
 *
 * <p>Deliberately minimal — a name→callbacks map, not a timer: scheduling WHEN portals
 * open stays with the ops team / future automation; this class only guarantees that every
 * portal event is startable through the same dev verb and that rarity weights live in one
 * place. The two launch variants are registered from this class's initializer (the xbox
 * files stay untouched per the C18 template-extraction rule):</p>
 *
 * <ul>
 *   <li>{@code xbox} — COMMON (weight {@value Rarity#COMMON_WEIGHT}); opens the first
 *       configured tutorial world via {@code XboxEventService.start}.</li>
 *   <li>{@code backrooms} — RARE (weight {@value Rarity#RARE_WEIGHT}); the C18 event via
 *       {@code BackroomsEventService.start}.</li>
 * </ul>
 */
public final class PortalEventScheduler {

    /** Roll weight classes; {@code weight} enters the {@link #roll} lottery. */
    public enum Rarity {
        COMMON(Rarity.COMMON_WEIGHT), RARE(Rarity.RARE_WEIGHT);

        public static final int COMMON_WEIGHT = 4;
        public static final int RARE_WEIGHT = 1;

        private final int weight;

        Rarity(int weight) {
            this.weight = weight;
        }

        public int weight() {
            return weight;
        }
    }

    /**
     * One portal-event variant.
     *
     * @param opener returns {@code null} on success or the player-facing error component
     * @param closer returns {@code null} on success or the player-facing error component
     */
    public record Variant(String id, Rarity rarity,
            BiFunction<MinecraftServer, ServerPlayer, Component> opener,
            Function<MinecraftServer, Component> closer) {}

    private static final Map<String, Variant> VARIANTS = new LinkedHashMap<>();

    static {
        // xbox — COMMON: delegate to the existing tutorial-world event (default world,
        // default minutes). Multi-world starts stay on /dev xboxevent start.
        register(new Variant("xbox", Rarity.COMMON,
                (server, operator) -> {
                    String world = XboxEventConfig.get().worlds().isEmpty()
                            ? "tu12" : XboxEventConfig.get().worlds().get(0);
                    XboxEventService.StartResult result = XboxEventService.start(server, world, 0,
                            operator == null ? "portal-scheduler" : operator.getScoreboardName());
                    return result.started() ? null : result.message();
                },
                server -> XboxEventService.stop(server, false)));

        // backrooms — RARE (C18: "register the event in the portal-event scheduler as a
        // rare variant").
        register(new Variant("backrooms", Rarity.RARE,
                (server, operator) -> {
                    BackroomsEventService.StartResult result = BackroomsEventService.start(server, 0,
                            operator == null ? "portal-scheduler" : operator.getScoreboardName());
                    return result.started() ? null : result.message();
                },
                server -> BackroomsEventService.stop(server, false)));
    }

    private PortalEventScheduler() {}

    /** Registers a variant; last registration wins on id collision (dev-time override). */
    public static void register(Variant variant) {
        VARIANTS.put(variant.id(), variant);
    }

    @Nullable
    public static Variant byId(String id) {
        return VARIANTS.get(id);
    }

    public static Set<String> ids() {
        return Collections.unmodifiableSet(VARIANTS.keySet());
    }

    /** Weighted lottery over all registered variants (rare ≈ 1-in-5 with the launch pair). */
    public static Variant roll(RandomSource random) {
        int total = VARIANTS.values().stream().mapToInt(variant -> variant.rarity().weight()).sum();
        int pick = random.nextInt(Math.max(1, total));
        for (Variant variant : VARIANTS.values()) {
            pick -= variant.rarity().weight();
            if (pick < 0) {
                return variant;
            }
        }
        return VARIANTS.values().iterator().next();
    }

    /** Opens {@code variant}; {@code null} on success, else the error component. */
    @Nullable
    public static Component open(MinecraftServer server, String variantId,
            @Nullable ServerPlayer operator) {
        Variant variant = VARIANTS.get(variantId);
        if (variant == null) {
            return Component.translatable("dev.eclipse.portal.unknown_variant",
                    variantId, String.join(", ", ids()));
        }
        return variant.opener().apply(server, operator);
    }

    /** Closes {@code variant} gracefully; {@code null} on success, else the error. */
    @Nullable
    public static Component close(MinecraftServer server, String variantId) {
        Variant variant = VARIANTS.get(variantId);
        if (variant == null) {
            return Component.translatable("dev.eclipse.portal.unknown_variant",
                    variantId, String.join(", ", ids()));
        }
        return variant.closer().apply(server);
    }
}
