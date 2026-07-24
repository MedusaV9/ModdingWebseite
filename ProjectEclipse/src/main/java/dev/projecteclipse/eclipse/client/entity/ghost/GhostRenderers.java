package dev.projecteclipse.eclipse.client.entity.ghost;

import java.util.HashMap;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import net.minecraft.Util;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Registers {@link GhostPlayerRenderer} for P4-B9's {@code eclipse:logout_ghost} and keeps
 * the client-side name-reveal state.
 *
 * <p><strong>Lookup-guarded registration (§2.7 fallback, upgraded):</strong> the entity
 * type is registered by P4-B9 in the same wave, so it may be absent at this worker's
 * compile/merge time. The renderer is typed against {@link LivingEntity} (the frozen
 * contract guarantees the ghost is a humanoid-sized LivingEntity), which lets us register
 * purely by registry lookup: type present → renderer registered; type absent → one log
 * line and a clean skip. Build and boot stay green either way, and the renderer lights up
 * the moment P4's registration lands — no integrator action needed.</p>
 *
 * <p><strong>Reveal cache:</strong> {@code S2CGhostRevealPayload} is handled in
 * {@code EclipsePayloads} (hub file, untouched) which writes the
 * {@code ClientStateCache.ghostReveal*} mailbox fields. {@link RevealTicker} ingests that
 * mailbox once per client tick into a per-entity countdown map and then resets the mailbox
 * to its defaults ({@code -1/""/0}) so an identical later payload (same ghost re-hit after
 * the server's 5 s rate limit) re-triggers cleanly. All access is client-main-thread.
 * P3 may read {@link #activeReveal(int)} if a HUD-side reveal treatment is ever wanted.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GhostRenderers {
    /** Frozen entity path (P4 plan §2.12; supersedes the older {@code ghost_player} draft id). */
    public static final String GHOST_ENTITY_PATH = "logout_ghost";

    /** entityId → active reveal; pruned every tick, cleared on logout. Client thread only. */
    private static final Map<Integer, Reveal> REVEALS = new HashMap<>();

    private GhostRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        ResourceLocation id = ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, GHOST_ENTITY_PATH);
        // containsKey, NOT getOptional: ENTITY_TYPE is a defaulted registry (falls back to pig).
        if (!BuiltInRegistries.ENTITY_TYPE.containsKey(id)) {
            EclipseMod.LOGGER.info(
                    "[P6-W12] {} not registered (P4-B9 not merged yet) — ghost renderer registration skipped", id);
            return;
        }
        @SuppressWarnings("unchecked") // frozen contract: the ghost is a LivingEntity (see handoff doc)
        EntityType<LivingEntity> type = (EntityType<LivingEntity>) BuiltInRegistries.ENTITY_TYPE.get(id);
        event.registerEntityRenderer(type, GhostPlayerRenderer::new);
        EclipseMod.LOGGER.info("[P6-W12] ghost renderer registered for {}", id);
    }

    /** The reveal for that ghost entity id, or {@code null} when none is running. */
    public static Reveal activeReveal(int entityId) {
        Reveal reveal = REVEALS.get(entityId);
        return reveal != null && !reveal.expired(Util.getMillis()) ? reveal : null;
    }

    /**
     * One glitch name-reveal window (server sends 60t by default). Timed by wall clock from
     * ingest — the payload is the trigger; the entity's synced {@code REVEAL_TICKS} field is
     * server bookkeeping we don't need client-side.
     */
    public record Reveal(String ownerName, long startMillis, int totalTicks) {
        public boolean expired(long nowMillis) {
            return nowMillis >= startMillis + totalTicks * 50L;
        }

        /** 0 → 1 over the reveal window. */
        public float progress(long nowMillis) {
            return Math.min(1.0F, (nowMillis - startMillis) / (totalTicks * 50.0F));
        }
    }

    /** Mailbox ingest + prune, once per client tick (3 volatile reads when idle — trivial). */
    @OnlyIn(Dist.CLIENT)
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class RevealTicker {
        private RevealTicker() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            int entityId = ClientStateCache.ghostRevealEntityId;
            int ticks = ClientStateCache.ghostRevealTicks;
            String ownerName = ClientStateCache.ghostRevealOwnerName;
            if (entityId >= 0 && ticks > 0 && !ownerName.isEmpty()) {
                REVEALS.put(entityId, new Reveal(ownerName, Util.getMillis(), ticks));
                // Consume the mailbox (back to ClientStateCache.resetToDefaults values) so the
                // next identical payload is distinguishable from this stale one.
                ClientStateCache.ghostRevealEntityId = -1;
                ClientStateCache.ghostRevealOwnerName = "";
                ClientStateCache.ghostRevealTicks = 0;
            }
            if (!REVEALS.isEmpty()) {
                long now = Util.getMillis();
                REVEALS.values().removeIf(reveal -> reveal.expired(now));
            }
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            REVEALS.clear();
        }
    }
}
