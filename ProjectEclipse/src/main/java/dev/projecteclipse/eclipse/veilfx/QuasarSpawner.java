package dev.projecteclipse.eclipse.veilfx;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import foundry.veil.api.quasar.particle.ParticleSystemManager;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client-only safe wrapper around Veil's Quasar particle system spawning:
 * {@code VeilRenderSystem.renderer().getParticleManager()} &rarr; {@code createEmitter(id)}
 * &rarr; {@code setPosition(pos)} / {@code setAttachedEntity(entity)} &rarr;
 * {@code addParticleSystem(e)}.
 *
 * <p>Every call is try/caught and returns {@code false} on failure so call sites can fall back
 * to their v1 vanilla-particle paths; an unknown/broken emitter id is logged once and skipped
 * from then on. Quasar particles are deliberately NOT gated on the Iris shaderpack state —
 * they render fine under packs (unlike Veil post pipelines).</p>
 *
 * <p><b>Budget law (P2 §3.5):</b> every spawn is charged against {@link FxBudget} first. The
 * no-channel overloads charge {@link FxBudget.Channel#BURST} (one-shots) or
 * {@link FxBudget.Channel#AMBIENT} (attached loops); rate-sensitive callers pass their channel
 * explicitly. A budget refusal drops the spawn <i>silently</i> — it never triggers the vanilla
 * fallback burst (that would defeat the budget), which stays reserved for broken/unknown
 * emitters.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class QuasarSpawner {
    /** Emitter ids that threw — permanently disabled for the session. */
    private static final Set<ResourceLocation> BROKEN = new HashSet<>();
    /** Emitter ids that already logged an unknown-id warning (not fatal: id may appear after a reload). */
    private static final Set<ResourceLocation> WARNED_UNKNOWN = new HashSet<>();
    /** Live entity-attached looping emitters, keyed per (entity id, emitter id). */
    private static final Map<AttachKey, ParticleEmitter> ATTACHED = new HashMap<>();

    private record AttachKey(int entityId, ResourceLocation emitterId) {}

    private QuasarSpawner() {}

    /** Spawns a one-shot emitter at the given position on the BURST budget channel. */
    public static boolean spawn(ResourceLocation emitterId, Vec3 pos) {
        return spawn(emitterId, pos, FxBudget.Channel.BURST);
    }

    /** Spawns a one-shot emitter charged to the given budget channel. @return {@code true} on success. */
    public static boolean spawn(ResourceLocation emitterId, Vec3 pos, FxBudget.Channel channel) {
        return spawnManaged(emitterId, pos, channel) != null;
    }

    /** {@link #spawnManaged(ResourceLocation, Vec3, FxBudget.Channel)} on the BURST channel. */
    @Nullable
    public static ParticleEmitter spawnManaged(ResourceLocation emitterId, Vec3 pos) {
        return spawnManaged(emitterId, pos, FxBudget.Channel.BURST);
    }

    /**
     * Spawns an emitter at the given position and returns the live handle so the caller can
     * manage its lifetime, or {@code null} on failure (same warn/disable rules as
     * {@link #spawn}) or budget refusal (silent). Required for {@code loop: true} emitters:
     * Veil never expires a looping position-based emitter on its own (only entity-attached
     * ones die with their entity), so whoever spawns a loop MUST keep the handle and
     * {@code remove()} it — see {@link LimboAmbience} for the reference pattern.
     */
    @Nullable
    public static ParticleEmitter spawnManaged(ResourceLocation emitterId, Vec3 pos, FxBudget.Channel channel) {
        if (BROKEN.contains(emitterId) || !FxBudget.tryEmitter(channel)) {
            return null;
        }
        return createAt(emitterId, pos);
    }

    /** Raw creation path shared by the budgeted entry points (budget already charged). */
    @Nullable
    private static ParticleEmitter createAt(ResourceLocation emitterId, Vec3 pos) {
        try {
            ParticleSystemManager manager = VeilRenderSystem.renderer().getParticleManager();
            ParticleEmitter emitter = manager.createEmitter(emitterId);
            if (emitter == null) {
                warnUnknown(emitterId);
                return null;
            }
            emitter.setPosition(pos);
            manager.addParticleSystem(emitter);
            return emitter;
        } catch (Throwable t) {
            fail(emitterId, t);
            return null;
        }
    }

    /** {@link #spawnOrFallback(ResourceLocation, Vec3, FxBudget.Channel)} on the BURST channel. */
    public static void spawnOrFallback(ResourceLocation emitterId, Vec3 pos) {
        spawnOrFallback(emitterId, pos, FxBudget.Channel.BURST);
    }

    /**
     * {@code S2CQuasarPayload} entry point: spawns the emitter, or — when Quasar is unavailable
     * or the emitter id is unknown — a small vanilla END_ROD/PORTAL burst at the position so
     * the server-driven cue is never silently dropped. A {@link FxBudget} refusal, by contrast,
     * IS a silent drop: over-budget cues must disappear, not turn into vanilla particle floods.
     */
    public static void spawnOrFallback(ResourceLocation emitterId, Vec3 pos, FxBudget.Channel channel) {
        if (!FxBudget.tryEmitter(channel)) {
            return; // budget drop — deliberate, silent
        }
        if (!BROKEN.contains(emitterId) && createAt(emitterId, pos) != null) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        RandomSource random = level.random;
        for (int i = 0; i < 8; i++) {
            level.addParticle(i % 2 == 0 ? ParticleTypes.END_ROD : ParticleTypes.PORTAL,
                    pos.x + (random.nextDouble() - 0.5D) * 0.6D,
                    pos.y + random.nextDouble() * 1.2D,
                    pos.z + (random.nextDouble() - 0.5D) * 0.6D,
                    (random.nextDouble() - 0.5D) * 0.02D,
                    0.05D + random.nextDouble() * 0.05D,
                    (random.nextDouble() - 0.5D) * 0.02D);
        }
    }

    /** {@link #ensureAttached(ResourceLocation, Entity, FxBudget.Channel)} on the AMBIENT channel. */
    public static boolean ensureAttached(ResourceLocation emitterId, Entity entity) {
        return ensureAttached(emitterId, entity, FxBudget.Channel.AMBIENT);
    }

    /**
     * Ensures a (typically looping) emitter is attached to the entity, spawning one if none is
     * live yet. The budget channel is only charged when a NEW emitter is actually created —
     * keeping an existing loop alive is free, so budget-refused callers can simply retry next
     * tick. @return {@code true} while a healthy attached emitter exists.
     */
    public static boolean ensureAttached(ResourceLocation emitterId, Entity entity, FxBudget.Channel channel) {
        if (BROKEN.contains(emitterId)) {
            return false;
        }
        prune();
        AttachKey key = new AttachKey(entity.getId(), emitterId);
        try {
            ParticleEmitter existing = ATTACHED.get(key);
            if (existing != null && !existing.isRemoved()) {
                return true;
            }
            if (!FxBudget.tryEmitter(channel)) {
                return false;
            }
            ParticleSystemManager manager = VeilRenderSystem.renderer().getParticleManager();
            ParticleEmitter emitter = manager.createEmitter(emitterId);
            if (emitter == null) {
                warnUnknown(emitterId);
                return false;
            }
            emitter.setPosition(entity.position());
            emitter.setAttachedEntity(entity);
            manager.addParticleSystem(emitter);
            ATTACHED.put(key, emitter);
            return true;
        } catch (Throwable t) {
            fail(emitterId, t);
            return false;
        }
    }

    /** Stops and forgets the entity-attached emitter previously created by {@link #ensureAttached}. */
    public static void removeAttached(ResourceLocation emitterId, Entity entity) {
        ParticleEmitter emitter = ATTACHED.remove(new AttachKey(entity.getId(), emitterId));
        if (emitter != null) {
            try {
                emitter.remove();
            } catch (Throwable t) {
                fail(emitterId, t);
            }
        }
    }

    /**
     * Stops and forgets EVERY live entity-attached emitter — the disconnect/world-unload
     * reset. The emitters themselves die with the level (Veil frees them on unload), but
     * the map would otherwise keep stale {@link ParticleEmitter} references keyed by the
     * OLD level's entity ids into the next session — entity ids restart on rejoin, so a
     * recycled id could make {@link #ensureAttached} report a dead emitter as healthy.
     */
    public static void clearAttached() {
        for (ParticleEmitter emitter : ATTACHED.values()) {
            try {
                if (!emitter.isRemoved()) {
                    emitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe: Veil may have freed its state already — dropping
                // the reference is the part that matters.
            }
        }
        ATTACHED.clear();
    }

    /** Disconnect reset hook (mirrors {@code client.WaveOverlay}'s clear-on-disconnect). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class DisconnectReset {
        private DisconnectReset() {}

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            clearAttached();
        }
    }

    /** Drops map entries whose emitters Veil already removed (entity death, dimension change). */
    private static void prune() {
        Iterator<Map.Entry<AttachKey, ParticleEmitter>> it = ATTACHED.entrySet().iterator();
        while (it.hasNext()) {
            try {
                if (it.next().getValue().isRemoved()) {
                    it.remove();
                }
            } catch (Throwable t) {
                it.remove();
            }
        }
    }

    private static void warnUnknown(ResourceLocation emitterId) {
        if (WARNED_UNKNOWN.add(emitterId)) {
            EclipseMod.LOGGER.warn("Quasar emitter {} is unknown/unloaded; falling back to vanilla particles", emitterId);
        }
    }

    private static void fail(ResourceLocation emitterId, Throwable t) {
        if (BROKEN.add(emitterId)) {
            EclipseMod.LOGGER.warn("Quasar emitter {} threw; disabling it for this session (vanilla fallback)", emitterId, t);
        }
    }
}
