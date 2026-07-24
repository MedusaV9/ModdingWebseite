package dev.projecteclipse.eclipse.client.drama;

import java.util.ArrayDeque;
import java.util.Iterator;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Altar island idle motes (FIX-5, IDEAS-C #3): the altar is the social hub but sits
 * visually dead between rituals — while the camera is within {@value #MATERIALIZE_DIST}
 * blocks of the client-synced {@link FxAnchors#ALTAR_CENTER} anchor, a rolling window of
 * looping {@code eclipse:door_glow_motes} emitters drifts slowly around the altar —
 * {@value #BASE_LIVE} loops at altar level 0, one more per synced altar level (capped at
 * {@value #MAX_LIVE_CAP}): the hub visibly thickens as the community levels the altar.
 * The {@code LimboAmbience} window pattern verbatim: looping position emitters never
 * expire on their own, so handles are kept and the oldest is culled beyond the live cap.
 *
 * <p>All spawns charge {@link FxBudget.Channel#AMBIENT}; the whole effect pauses under
 * {@code reducedFx} (FIX-5 order — existing emitters are released, not just thinned).
 * Overworld-gated: anchors carry no dimension client-side (the {@code ShipDoorGlow}
 * caveat) and the sanctum altar lives in the overworld, so the dimension check doubles as
 * the cross-dimension guard. Distance uses a small hysteresis band so the boundary never
 * flickers.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarIdleMotes {
    private static final ResourceLocation MOTES_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "door_glow_motes");

    /** FX materialize within this camera distance (blocks)… */
    private static final double MATERIALIZE_DIST = 64.0D;
    /** …and release only beyond this one (ShipDoorGlow hysteresis, no boundary thrash). */
    private static final double RELEASE_DIST = 72.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;

    /**
     * Rolling-window shape: one fresh spawn every 3.5–5.5 s into a live cap that grows
     * with the altar (W4-ISLAND level-up transformation): {@value #BASE_LIVE} at level 0,
     * +1 per {@code ClientStateCache.altarLevel}, hard-capped at {@value #MAX_LIVE_CAP}
     * (still comfortably inside the AMBIENT budget window). A level-up mid-window simply
     * lets the next spawns stack deeper — no re-shuffle needed; the level dropping on
     * disconnect reset shrinks the window via the existing oldest-first cull.
     */
    private static final int BASE_LIVE = 3;
    private static final int MAX_LIVE_CAP = 6;
    private static final int MIN_INTERVAL_TICKS = 70;
    private static final int MAX_INTERVAL_TICKS = 110;
    /** Placement ring around the anchor (blocks) — hugging the island, never in the beam. */
    private static final double RING_MIN_RADIUS = 2.0D;
    private static final double RING_MAX_RADIUS = 5.5D;
    /** Height band above the anchor point. */
    private static final double Y_BIAS_MIN = 0.3D;
    private static final double Y_BIAS_RANGE = 1.9D;

    /** Live looping emitters, oldest first (LimboAmbience window law). */
    private static final ArrayDeque<ParticleEmitter> LIVE = new ArrayDeque<>();
    private static int countdown;

    private AltarIdleMotes() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            clear();
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null) {
            clear();
            return;
        }
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        if (distSq > (LIVE.isEmpty() ? MATERIALIZE_DIST_SQ : RELEASE_DIST_SQ)) {
            clear();
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        prune();
        if (--countdown > 0) {
            return;
        }
        RandomSource random = level.random;
        countdown = random.nextIntBetweenInclusive(MIN_INTERVAL_TICKS, MAX_INTERVAL_TICKS);

        ParticleEmitter emitter = QuasarSpawner.spawnManaged(MOTES_EMITTER,
                pickSpawnPos(anchor, random), FxBudget.Channel.AMBIENT);
        if (emitter == null) {
            return; // budget refusal / Quasar unavailable — the window simply stays thinner
        }
        LIVE.addLast(emitter);
        while (LIVE.size() > maxLive()) {
            removeEmitter(LIVE.pollFirst());
        }
    }

    /** Live-loop cap, richer as the altar levels up (clamped for the AMBIENT budget). */
    private static int maxLive() {
        int level = Math.max(0, dev.projecteclipse.eclipse.client.ClientStateCache.altarLevel);
        return Math.min(BASE_LIVE + level, MAX_LIVE_CAP);
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    /** A random spot on the placement ring, biased into the low height band. */
    private static Vec3 pickSpawnPos(Vec3 anchor, RandomSource random) {
        double angle = random.nextDouble() * Math.PI * 2.0D;
        double radius = RING_MIN_RADIUS + random.nextDouble() * (RING_MAX_RADIUS - RING_MIN_RADIUS);
        return new Vec3(anchor.x + Math.cos(angle) * radius,
                anchor.y + Y_BIAS_MIN + random.nextDouble() * Y_BIAS_RANGE,
                anchor.z + Math.sin(angle) * radius);
    }

    /** Drops handles Veil already removed (level swap cleared the particle manager). */
    private static void prune() {
        Iterator<ParticleEmitter> it = LIVE.iterator();
        while (it.hasNext()) {
            try {
                if (it.next().isRemoved()) {
                    it.remove();
                }
            } catch (Throwable t) {
                it.remove();
            }
        }
    }

    private static void clear() {
        while (!LIVE.isEmpty()) {
            removeEmitter(LIVE.pollFirst());
        }
        countdown = 0;
    }

    private static void removeEmitter(ParticleEmitter emitter) {
        try {
            if (!emitter.isRemoved()) {
                emitter.remove();
            }
        } catch (Throwable ignored) {
            // Teardown-order safe (LimboAmbience pattern).
        }
    }
}
