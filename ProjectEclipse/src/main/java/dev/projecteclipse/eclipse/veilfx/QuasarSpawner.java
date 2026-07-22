package dev.projecteclipse.eclipse.veilfx;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;

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

    /** Spawns a one-shot emitter at the given position. @return {@code true} on success. */
    public static boolean spawn(ResourceLocation emitterId, Vec3 pos) {
        if (BROKEN.contains(emitterId)) {
            return false;
        }
        try {
            ParticleSystemManager manager = VeilRenderSystem.renderer().getParticleManager();
            ParticleEmitter emitter = manager.createEmitter(emitterId);
            if (emitter == null) {
                warnUnknown(emitterId);
                return false;
            }
            emitter.setPosition(pos);
            manager.addParticleSystem(emitter);
            return true;
        } catch (Throwable t) {
            fail(emitterId, t);
            return false;
        }
    }

    /**
     * {@code S2CQuasarPayload} entry point: spawns the emitter, or — when Quasar is unavailable
     * or the emitter id is unknown — a small vanilla END_ROD/PORTAL burst at the position so
     * the server-driven cue is never silently dropped.
     */
    public static void spawnOrFallback(ResourceLocation emitterId, Vec3 pos) {
        if (spawn(emitterId, pos)) {
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

    /**
     * Ensures a (typically looping) emitter is attached to the entity, spawning one if none is
     * live yet. @return {@code true} while a healthy attached emitter exists.
     */
    public static boolean ensureAttached(ResourceLocation emitterId, Entity entity) {
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
