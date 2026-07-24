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
 * <p><b>W-P-ALTAR2 motifs:</b> at altar level {@value #HELIX_MIN_LEVEL}+ two of every
 * three window spawns are placed on a slow DOUBLE-HELIX column above the altar
 * (deterministic strand positions from game time; the motes' own upward wind animates
 * the strands) while the third keeps the old ambient ring. At level
 * {@value #PATCH_MIN_LEVEL}+ a second slow cadence projects faint moving LIGHT PATCHES
 * onto the island floor ({@code eclipse:altar_halo_patch}) whose azimuth follows the
 * sky halo-beam fan ({@code AltarVeilSky.BEAM_SPIN_DEG_PER_SEC[0]}) — the ground read
 * of the L4 sky tier.</p>
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
    private static final int MAX_LIVE_CAP = 8;
    private static final int MIN_INTERVAL_TICKS = 70;
    private static final int MAX_INTERVAL_TICKS = 110;
    /**
     * W-P-ALTAR idle-presence scaling: each altar level shortens the spawn cadence by
     * {@value #LEVEL_INTERVAL_BONUS_TICKS} t (floored at {@value #MIN_INTERVAL_FLOOR_TICKS} t)
     * and pushes the placement ring/height band outward, so a leveled altar reads denser,
     * wider and taller at a glance. Worst case (level 5): one spawn per ~1.75–3.75 s into
     * a window of {@value #MAX_LIVE_CAP} loops — still far inside the AMBIENT budget.
     */
    private static final int LEVEL_INTERVAL_BONUS_TICKS = 7;
    private static final int MIN_INTERVAL_FLOOR_TICKS = 35;
    private static final double LEVEL_RING_BONUS = 0.35D;
    private static final double LEVEL_HEIGHT_BONUS = 0.25D;
    /** Placement ring around the anchor (blocks) — hugging the island, never in the beam. */
    private static final double RING_MIN_RADIUS = 2.0D;
    private static final double RING_MAX_RADIUS = 5.5D;
    /** Height band above the anchor point. */
    private static final double Y_BIAS_MIN = 0.3D;
    private static final double Y_BIAS_RANGE = 1.9D;

    // --- W-P-ALTAR2: L3+ double-helix column (deterministic strand placement) ---
    private static final int HELIX_MIN_LEVEL = 3;
    /** Strand radius — tighter than the ambient ring, outside the beam core. */
    private static final double HELIX_RADIUS = 1.7D;
    private static final double HELIX_HEIGHT = 3.4D;
    private static final double HELIX_BASE_Y = 0.35D;
    /** Whole-helix slow rotation period (ticks). */
    private static final double HELIX_TURN_TICKS = 460.0D;
    /** One full base→top climb per this many ticks (samples trace the strands). */
    private static final double HELIX_CLIMB_TICKS = 360.0D;
    /** Strand twist over the full column height (radians). */
    private static final double HELIX_TWIST = Math.PI * 1.5D;

    // --- W-P-ALTAR2: L4+ ground-projected halo light patches ---
    private static final int PATCH_MIN_LEVEL = 4;
    private static final ResourceLocation PATCH_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_halo_patch");
    private static final int PATCH_MIN_INTERVAL_TICKS = 55;
    private static final int PATCH_MAX_INTERVAL_TICKS = 80;
    /** MUST match {@code AltarVeilSky.BEAM_SPIN_DEG_PER_SEC[0]} — the sky-fan azimuth. */
    private static final float PATCH_DEG_PER_SEC = 2.1F;
    private static final double PATCH_RADIUS = 4.6D;
    /** Patches hover just off the floor so the additive quad reads as cast light. */
    private static final double PATCH_HOVER_Y = 0.12D;

    /** Live looping emitters, oldest first (LimboAmbience window law). */
    private static final ArrayDeque<ParticleEmitter> LIVE = new ArrayDeque<>();
    private static int countdown;
    /** Round-robin spawn counter (helix strand alternation + ring interleave). */
    private static int spawnCounter;
    private static int patchCountdown;
    /** Which of the four sky beams the next patch tracks (round-robin). */
    private static int patchBeamIndex;

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
        int altarLevel = clientAltarLevel();
        tickHaloPatches(level, anchor, altarLevel);
        if (--countdown > 0) {
            return;
        }
        RandomSource random = level.random;
        countdown = Math.max(MIN_INTERVAL_FLOOR_TICKS,
                random.nextIntBetweenInclusive(MIN_INTERVAL_TICKS, MAX_INTERVAL_TICKS)
                        - altarLevel * LEVEL_INTERVAL_BONUS_TICKS);

        ParticleEmitter emitter = QuasarSpawner.spawnManaged(MOTES_EMITTER,
                pickSpawnPos(level, anchor, random, altarLevel), FxBudget.Channel.AMBIENT);
        if (emitter == null) {
            return; // budget refusal / Quasar unavailable — the window simply stays thinner
        }
        LIVE.addLast(emitter);
        while (LIVE.size() > maxLive()) {
            removeEmitter(LIVE.pollFirst());
        }
    }

    /**
     * W-P-ALTAR2 L4+ ground read of the sky halo beams: on its own slow cadence, one
     * {@code altar_halo_patch} one-shot lands on the island floor at the azimuth of the
     * next beam of the sky fan (same 2.1 °/s spin constant, wall-clock driven exactly
     * like {@code AltarVeilSky}), so the faint light pools genuinely SWEEP with the sky.
     * One-shots — no handles to manage; a budget refusal just skips a pool.
     */
    private static void tickHaloPatches(ClientLevel level, Vec3 anchor, int altarLevel) {
        if (altarLevel < PATCH_MIN_LEVEL) {
            patchCountdown = 0;
            return;
        }
        if (--patchCountdown > 0) {
            return;
        }
        patchCountdown = level.random.nextIntBetweenInclusive(
                PATCH_MIN_INTERVAL_TICKS, PATCH_MAX_INTERVAL_TICKS);
        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        patchBeamIndex = (patchBeamIndex + 1) & 3;
        double angle = Math.toRadians(seconds * PATCH_DEG_PER_SEC)
                + patchBeamIndex * (Math.PI / 2.0D);
        double radius = PATCH_RADIUS + (altarLevel - PATCH_MIN_LEVEL) * 0.4D
                + (level.random.nextDouble() - 0.5D) * 1.2D;
        QuasarSpawner.spawn(PATCH_EMITTER, new Vec3(
                anchor.x + Math.cos(angle) * radius,
                anchor.y + PATCH_HOVER_Y,
                anchor.z + Math.sin(angle) * radius), FxBudget.Channel.AMBIENT);
    }

    /** Live-loop cap, richer as the altar levels up (clamped for the AMBIENT budget). */
    private static int maxLive() {
        return Math.min(BASE_LIVE + clientAltarLevel(), MAX_LIVE_CAP);
    }

    /** Synced altar level, clamped to the presence-scaling band. */
    private static int clientAltarLevel() {
        return Math.min(Math.max(
                dev.projecteclipse.eclipse.client.ClientStateCache.altarLevel, 0), 5);
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    /**
     * Spawn placement. Below level {@value #HELIX_MIN_LEVEL}: a random spot on the
     * ambient ring (level-widened), biased into the height band. At
     * {@value #HELIX_MIN_LEVEL}+ (W-P-ALTAR2 motif), two of every three spawns land on
     * one of two double-helix strands instead: the strand point is a deterministic
     * function of game time (slow whole-helix rotation + a climbing sample height with
     * {@value #HELIX_TWIST}-radian twist), so the rolling window of standing loops
     * traces a faint slow double helix while each mote's own upward wind animates it.
     */
    private static Vec3 pickSpawnPos(ClientLevel level, Vec3 anchor, RandomSource random,
            int altarLevel) {
        spawnCounter++;
        if (altarLevel >= HELIX_MIN_LEVEL && spawnCounter % 3 != 0) {
            long gameTime = level.getGameTime();
            double strand = (spawnCounter & 1) == 0 ? 0.0D : Math.PI;
            double climb = (gameTime % (long) HELIX_CLIMB_TICKS) / HELIX_CLIMB_TICKS;
            double spin = (gameTime % (long) HELIX_TURN_TICKS) / HELIX_TURN_TICKS
                    * Math.PI * 2.0D;
            double angle = spin + strand + climb * HELIX_TWIST;
            double radius = HELIX_RADIUS + (random.nextDouble() - 0.5D) * 0.3D;
            return new Vec3(anchor.x + Math.cos(angle) * radius,
                    anchor.y + HELIX_BASE_Y + climb * HELIX_HEIGHT,
                    anchor.z + Math.sin(angle) * radius);
        }
        double angle = random.nextDouble() * Math.PI * 2.0D;
        double maxRadius = RING_MAX_RADIUS + altarLevel * LEVEL_RING_BONUS;
        double radius = RING_MIN_RADIUS + random.nextDouble() * (maxRadius - RING_MIN_RADIUS);
        double heightRange = Y_BIAS_RANGE + altarLevel * LEVEL_HEIGHT_BONUS;
        return new Vec3(anchor.x + Math.cos(angle) * radius,
                anchor.y + Y_BIAS_MIN + random.nextDouble() * heightRange,
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
        patchCountdown = 0;
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
