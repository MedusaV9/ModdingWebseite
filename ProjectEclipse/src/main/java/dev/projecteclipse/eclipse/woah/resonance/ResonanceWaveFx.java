package dev.projecteclipse.eclipse.woah.resonance;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import com.mojang.math.Transformation;

import org.joml.Vector3f;

import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * W13-C3 — the resonance-wave beat: every {@value #WAVE_PERIOD_TICKS} ticks (offset by a
 * deterministic anchor hash so the raster is stateless) a resonance wave rolls outward
 * from the altar at {@value #FRONT_SPEED} blocks/tick. The Photon
 * {@code resonance_wave_ring} garnish (cue {@code CUE_RESONANCE_WAVE}) paints the front
 * on the bowl floor; when the front crosses a monolith's XZ distance the whole crystal
 * VIBRATES for {@value #VIBRATE_TICKS} ticks — a radial tremor of
 * {@value #AMPLITUDE} blocks at 2.5 Hz under a sine envelope that is exactly 0 at both
 * ends, so every display returns byte-identically to its base transformation.
 *
 * <p><b>Base-transform ledger:</b> {@link ResonanceFieldBuilder#spawnDisplay} registers
 * each display's spawn transformation here (UUID → {@link Transformation}); a self-heal
 * rebuild re-registers automatically because it passes through the same spawn path, and
 * {@link ResonanceFieldBuilder#sweepFieldEntities} drops the ledger wholesale. Pieces
 * without a ledger entry are skipped — the tremor never guesses a pose.</p>
 *
 * <p><b>Budget:</b> pushes ride the {@value #PUSH_CADENCE_TICKS}-tick cadence
 * (13 pushes/crystal/wave, 9–15 displays each). Arrival times follow the double ring
 * (inner 4 at r 13.5–16.5 → hits t 30–37, outer 5 at r 24–28 → hits t 53–62), so worst
 * case one whole ring trembles at once: 5 crystals × 9–15 displays every 2 t
 * ≈ 30–40 transform packets/tick averaged for ≤ 33 t per wave — well under the
 * 240-display DomeShatter burst. The wave-start check carries the MSPT guard
 * ({@code StormDebrisFx} lever): above {@value #MSPT_SKIP_NANOS} ns average tick time
 * the beat is skipped entirely, never degraded mid-show. Only ticked while
 * {@code playersNear} (§3.7 gate) — a wave suspended by the gate self-resolves on
 * resume (elapsed time keeps counting, the final base push still lands).</p>
 */
final class ResonanceWaveFx {
    /** Beat raster: one wave every 30 s (offset per anchor — stateless, restart-safe). */
    private static final int WAVE_PERIOD_TICKS = 600;
    /** Wavefront speed in blocks/tick (reaches the outer ring r≈28 at ~t62). */
    private static final double FRONT_SPEED = 0.45D;
    /** Tremor window per crystal + its push cadence. */
    private static final int VIBRATE_TICKS = 24;
    private static final int PUSH_CADENCE_TICKS = 2;
    /** Tremor period 8 t = 2.5 Hz (matches the melody-note attack read). */
    private static final float TREMOR_PERIOD_TICKS = 8.0F;
    /** Radial displacement peak in blocks (small enough to never read as a teleport). */
    private static final float AMPLITUDE = 0.07F;
    /** MSPT guard threshold (the 45 ms StormDebrisFx/EndShatterSequence lever). */
    private static final long MSPT_SKIP_NANOS = 45_000_000L;

    /** Spawn-time base transformation per display UUID (session-scoped). */
    private static final Map<UUID, Transformation> BASE_TRANSFORMS = new HashMap<>();
    /** Live tremors: crystalIdx → tremor start gameTime. */
    private static final Map<Integer, Long> VIBRATIONS = new HashMap<>();
    /** Crystals already hit by the CURRENT wave (front stays past them). */
    private static final Set<Integer> TRIGGERED = new HashSet<>();
    /** Start gameTime of the live wave, {@code MIN_VALUE} = none. */
    private static long waveStart = Long.MIN_VALUE;

    private ResonanceWaveFx() {}

    // ------------------------------------------------------------------ ledger

    /** Spawn hook ({@link ResonanceFieldBuilder#spawnDisplay}): remember the base pose. */
    static void registerBase(UUID uuid, Transformation transformation) {
        BASE_TRANSFORMS.put(uuid, transformation);
    }

    /** Sweep hook: the whole field is being discarded — drop every base pose. */
    static void clearBases() {
        BASE_TRANSFORMS.clear();
        VIBRATIONS.clear();
    }

    /** Server-stop reset ({@link ResonanceFieldService#onServerStopped} seam). */
    static void clearSession() {
        clearBases();
        TRIGGERED.clear();
        waveStart = Long.MIN_VALUE;
    }

    // ------------------------------------------------------------------ tick

    /** Called from the service tick, only while built + {@code playersNear}. */
    static void tick(ServerLevel level, ResonanceFieldData data, long gameTime) {
        BlockPos anchor = data.anchor();
        BlockPos altar = data.altarPos();
        if (anchor == null || altar == null) {
            return;
        }
        Vec3 centre = Vec3.atBottomCenterOf(altar.above());
        if (waveStart == Long.MIN_VALUE) {
            if (Math.floorMod(gameTime, WAVE_PERIOD_TICKS) == waveOffset(anchor)
                    && level.getServer().getAverageTickTimeNanos() <= MSPT_SKIP_NANOS) {
                waveStart = gameTime;
                TRIGGERED.clear();
                FxPayloads.sendFxEvent(level, ResonanceCues.CUE_RESONANCE_WAVE, centre,
                        0.0F, 0.0F, 96.0D);
                level.playSound(null, centre.x, centre.y, centre.z,
                        SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.9F, 0.55F);
            }
        } else {
            double front = (gameTime - waveStart) * FRONT_SPEED;
            List<ResonanceFieldData.Monolith> monoliths = data.monoliths();
            for (int i = 0; i < monoliths.size(); i++) {
                if (!TRIGGERED.contains(i)
                        && xzDistance(monoliths.get(i).basePos, centre) <= front) {
                    TRIGGERED.add(i);
                    VIBRATIONS.put(i, gameTime);
                }
            }
            if (front > ResonanceFieldBuilder.VALLEY_RADIUS) {
                waveStart = Long.MIN_VALUE; // every monolith is < VALLEY_RADIUS out
            }
        }
        tickVibrations(level, data, gameTime, centre);
    }

    /** Beat-raster offset: a stateless anchor hash — no persisted scheduling state. */
    private static int waveOffset(BlockPos anchor) {
        return (int) Math.floorMod(anchor.asLong() * 0x9E3779B97F4A7C15L, WAVE_PERIOD_TICKS);
    }

    private static void tickVibrations(ServerLevel level, ResonanceFieldData data,
            long gameTime, Vec3 centre) {
        if (VIBRATIONS.isEmpty()) {
            return;
        }
        Iterator<Map.Entry<Integer, Long>> iterator = VIBRATIONS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<Integer, Long> entry = iterator.next();
            int elapsed = (int) (gameTime - entry.getValue());
            if (elapsed >= VIBRATE_TICKS) {
                // Final push: exact base transformation — zero accumulated drift.
                pushMonolith(level, data, entry.getKey(), 0.0F, centre);
                iterator.remove();
            } else if (elapsed % PUSH_CADENCE_TICKS == 0) {
                // Target the NEXT cadence boundary (GravityRiftOrbitals.animate law).
                float t = elapsed + PUSH_CADENCE_TICKS;
                float envelope = Mth.sin(Mth.PI * Math.min(t / VIBRATE_TICKS, 1.0F));
                float tremor = Mth.sin(Mth.TWO_PI * t / TREMOR_PERIOD_TICKS);
                pushMonolith(level, data, entry.getKey(), AMPLITUDE * envelope * tremor,
                        centre);
            }
        }
    }

    /**
     * One interpolated transform push over a crystal's full display set: base
     * translation + a uniform radial XZ delta (the whole monolith trembles as one
     * body — rotation/scale never touched, so facets keep their exact silhouette).
     */
    private static void pushMonolith(ServerLevel level, ResonanceFieldData data,
            int crystalIdx, float radialOffset, Vec3 centre) {
        if (crystalIdx < 0 || crystalIdx >= data.monoliths().size()) {
            return;
        }
        ResonanceFieldData.Monolith monolith = data.monoliths().get(crystalIdx);
        double dx = monolith.basePos.getX() + 0.5D - centre.x;
        double dz = monolith.basePos.getZ() + 0.5D - centre.z;
        double length = Math.sqrt(dx * dx + dz * dz);
        Vector3f delta = length > 1.0E-3D
                ? new Vector3f((float) (dx / length * radialOffset), 0.0F,
                        (float) (dz / length * radialOffset))
                : new Vector3f(radialOffset, 0.0F, 0.0F);
        String idxTag = ResonanceFieldBuilder.CRYSTAL_IDX_PREFIX + crystalIdx;
        List<Entity> pieces = level.getEntities((Entity) null,
                new AABB(monolith.basePos).inflate(10.0D, monolith.height + 4.0D, 10.0D),
                entity -> entity instanceof Display.BlockDisplay
                        && entity.getTags().contains(idxTag));
        for (Entity piece : pieces) {
            Transformation base = BASE_TRANSFORMS.get(piece.getUUID());
            if (base == null) {
                continue; // stray without a ledger entry — never guess a pose
            }
            Display.BlockDisplay display = (Display.BlockDisplay) piece;
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(PUSH_CADENCE_TICKS);
            display.setTransformation(new Transformation(
                    new Vector3f(base.getTranslation()).add(delta),
                    base.getLeftRotation(), base.getScale(), base.getRightRotation()));
        }
    }

    private static double xzDistance(BlockPos pos, Vec3 centre) {
        double dx = pos.getX() + 0.5D - centre.x;
        double dz = pos.getZ() + 0.5D - centre.z;
        return Math.sqrt(dx * dx + dz * dz);
    }
}
