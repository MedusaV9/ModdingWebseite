package dev.projecteclipse.eclipse.client.entity.geo;

import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * One tiny {@code eclipse:rift_spark} crackle on the first hurt frame of an Eclipse
 * custom mob (W4-FEEL, IDEA-02 #1 — hoisted from {@code GlitchedGeoRenderer.HurtSparks},
 * FIX-5 / IDEAS-C #2, so EVERY {@link EclipseGeoRenderer} mob confirms hits, not just the
 * GLITCHED family). The emitter JSON is {@code loop: true}, so each spawn goes through
 * {@link QuasarSpawner#spawnManaged} and the handle is expired here after
 * {@value #PUFF_LIFE_TICKS} ticks (the {@code LimboAmbience} owner-manages-loop law);
 * a per-entity dedup window keeps one puff per hit even though {@code preRender} runs
 * every frame. BURST-budgeted — over-budget puffs drop silently.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
final class HurtSparks {
    private static final ResourceLocation RIFT_SPARK_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_spark");

    /** Loop-emitter lifetime — a short crackle accent (~4–6 particles), not a fountain. */
    private static final int PUFF_LIFE_TICKS = 8;
    /** Minimum game-time gap between puffs per entity (matches the ≥ 8 t flash guard). */
    private static final long DEDUP_WINDOW_TICKS = 10L;
    /** Dedup map safety valve — cleared wholesale rather than tracked precisely. */
    private static final int MAX_TRACKED = 128;

    private record Puff(ParticleEmitter emitter, int expireTick) {}

    /** Live short-lifetime spark handles, oldest first. */
    private static final ArrayDeque<Puff> PUFFS = new ArrayDeque<>();
    /** Last puff game time per entity id (render-thread only). */
    private static final Map<Integer, Long> LAST_PUFF = new HashMap<>();

    private static int clientTicks;

    private HurtSparks() {}

    /** Render-thread entry from {@link EclipseGeoRenderer#preRender}. */
    static void onHurtFrame(LivingEntity entity) {
        long gameTime = entity.level().getGameTime();
        Long last = LAST_PUFF.get(entity.getId());
        if (last != null && gameTime - last < DEDUP_WINDOW_TICKS) {
            return;
        }
        if (LAST_PUFF.size() >= MAX_TRACKED) {
            LAST_PUFF.clear();
        }
        LAST_PUFF.put(entity.getId(), gameTime);
        ParticleEmitter emitter = QuasarSpawner.spawnManaged(RIFT_SPARK_EMITTER,
                entity.position().add(0.0D, entity.getBbHeight() * 0.55D, 0.0D),
                FxBudget.Channel.BURST);
        if (emitter != null) {
            PUFFS.addLast(new Puff(emitter, clientTicks + PUFF_LIFE_TICKS));
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (Minecraft.getInstance().level == null) {
            clear();
            return;
        }
        clientTicks++;
        while (!PUFFS.isEmpty() && PUFFS.peekFirst().expireTick() <= clientTicks) {
            removeEmitter(PUFFS.pollFirst().emitter());
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    private static void clear() {
        while (!PUFFS.isEmpty()) {
            removeEmitter(PUFFS.pollFirst().emitter());
        }
        LAST_PUFF.clear();
    }

    private static void removeEmitter(ParticleEmitter emitter) {
        try {
            if (!emitter.isRemoved()) {
                emitter.remove();
            }
        } catch (Throwable ignored) {
            // Teardown-order safe (QuasarSpawner.clearAttached pattern).
        }
    }
}
