package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.List;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/**
 * F-057 — the choreographed credits BACKDROP: {@value #TOTAL} block displays filling the
 * epilogue sky around the standing (no more auto-run) players in three deterministic
 * formation families, all pure functions of (index, act tick) so re-pushes always agree
 * (the stateless-push law of {@code CreditsSequence}):
 *
 * <ol>
 *   <li><b>Spiral bands</b> ({@value #SPIRAL_COUNT}) — a huge slowly-turning debris tunnel
 *       whose axis is the players' east view line: golden-angle phyllotaxis around the view
 *       axis, radii {@value #TUNNEL_RADIUS_MIN}..{@value #TUNNEL_RADIUS_MAX} blocks, three
 *       interleaved bands drifting at incommensurate angular rates. Because every element
 *       sits at ≥ {@value #TUNNEL_RADIUS_MIN} blocks off the axis, the view center (the
 *       sunrise → the eclipse) stays OPEN and the periphery/horizon reads dense — the
 *       "dichter am Horizont, offener in Blickmitte" placement law.</li>
 *   <li><b>Rotating rings</b> ({@value #RING_GROUPS}×{@value #RING_SIZE}) — face-on rings
 *       at staggered depths down the view axis, alternating spin directions, breathing
 *       ±6% radius on a slow sine.</li>
 *   <li><b>Ascending columns</b> ({@value #COLUMN_GROUPS}×{@value #COLUMN_SIZE}) — golden-
 *       angle scattered sea-surface columns whose elements climb, wrap and re-climb; the
 *       wrap seam is hidden by the same scale-floor envelope the flyers use.</li>
 * </ol>
 *
 * <p><b>Budget</b>: spawned {@value #SPAWN_PER_TICK}/t (≈{@code TOTAL/SPAWN_PER_TICK}
 * ticks to full), all under {@code CreditsSequence}'s hard cap; transform pushes ride
 * {@value #PUSH_STRIDE}t interpolation windows (~{@code TOTAL/PUSH_STRIDE} ≈ 130 entity
 * updates/t). Every entity is anchored at ONE position near the surf line (inside display
 * tracking range of the standing players) with the whole formation geometry living on the
 * translation + a widened view range — the eclipse-anchor trick at formation scale.
 * Despawn guarantee: shrink-out + discard with the flyers, belt-and-braces discard at the
 * white peak and in {@code endEvent}, and the {@link #TAG} stray sweep.</p>
 */
final class CreditsFormationAct {
    static final String TAG = "eclipse_credits_formation";

    // --- population (F-057: "wirklich tausende") ---
    static final int SPIRAL_COUNT = 1080;
    static final int RING_GROUPS = 6;
    static final int RING_SIZE = 70;
    static final int COLUMN_GROUPS = 20;
    static final int COLUMN_SIZE = 15;
    static final int TOTAL = SPIRAL_COUNT + RING_GROUPS * RING_SIZE + COLUMN_GROUPS * COLUMN_SIZE;

    /** Budgeted spawn rate (F-057 ask: "gestaffelt gespawnt (z.B. 50/Tick-Batch)"). */
    static final int SPAWN_PER_TICK = 50;
    /** Transform push cadence — long windows, smooth drift, ~TOTAL/14 updates per tick. */
    static final int PUSH_STRIDE = 14;

    // --- tunnel geometry (blocks off the view axis) ---
    private static final float TUNNEL_RADIUS_MIN = 34.0F;
    private static final float TUNNEL_RADIUS_MAX = 150.0F;
    /** Tunnel depth: elements spread this far east of the anchor along the view axis. */
    private static final float TUNNEL_DEPTH = 210.0F;
    /** Base angular drift (rad/t) of the slowest spiral band; bands ride multiples. */
    private static final float BAND_RATE = 0.0022F;

    // --- ring geometry ---
    private static final float RING_RADIUS_MIN = 30.0F;
    private static final float RING_RADIUS_STEP = 12.0F;
    private static final float RING_DEPTH_MIN = 60.0F;
    private static final float RING_DEPTH_STEP = 34.0F;
    private static final float RING_RATE = 0.0045F;

    // --- column geometry ---
    private static final float COLUMN_FIELD_MIN = 55.0F;
    private static final float COLUMN_FIELD_MAX = 175.0F;
    private static final float COLUMN_CLIMB = 46.0F;
    private static final int COLUMN_CYCLE = 520;

    private static final float VIEW_RANGE = 4.0F;
    private static final float SCALE_FLOOR = 0.02F;
    /** Spawn grow-in window (ticks) — a batch never pops in at full scale. */
    private static final float GROW_IN_TICKS = 40.0F;

    /** The formation's greatest-hits palette (the flyer palette + glass accents). */
    private static final BlockState[] PALETTE = {
            Blocks.DARK_OAK_PLANKS.defaultBlockState(),
            Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState(),
            Blocks.DEEPSLATE_TILES.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.AMETHYST_BLOCK.defaultBlockState(),
            Blocks.PURPUR_BLOCK.defaultBlockState(),
            Blocks.TINTED_GLASS.defaultBlockState()};

    private final List<Display.BlockDisplay> displays = new ArrayList<>(TOTAL);
    private Vec3 anchor = Vec3.ZERO;
    private int spawnCursor;

    /** Anchors the whole formation once (surf line, players' eye height band). */
    void setAnchor(Vec3 anchor) {
        this.anchor = anchor;
    }

    boolean spawnRemaining() {
        return this.spawnCursor < TOTAL;
    }

    /** Budgeted spawn wave ({@value #SPAWN_PER_TICK}/t), pose seeded at the CURRENT act tick. */
    void spawnBatch(ServerLevel epilogue, int actTick) {
        int budget = SPAWN_PER_TICK;
        while (budget-- > 0 && this.spawnCursor < TOTAL) {
            if (CreditsSequence.actCapReached()) {
                this.spawnCursor = TOTAL; // over cap: keep what floats, stop trying
                break;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(epilogue);
            if (piece == null) {
                return; // retry the same index next tick (list/index alignment invariant)
            }
            int i = this.spawnCursor;
            piece.moveTo(this.anchor.x, this.anchor.y, this.anchor.z, 0.0F, 0.0F);
            piece.setBlockState(PALETTE[
                    (int) (CreditsSequence.hash01(i, 81) * PALETTE.length) % PALETTE.length]);
            piece.addTag(TAG);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            piece.setTransformation(pose(i, actTick, 1.0F));
            // Backlit silhouettes against the sunrise (the flyer brightness law).
            CreditsSequence.applyBrightnessOverride(piece, 7, 4);
            CreditsSequence.applyViewRange(piece, VIEW_RANGE);
            CreditsSequence.trackDisplay(piece);
            epilogue.addFreshEntity(piece);
            this.displays.add(piece);
            this.spawnCursor++;
        }
        if (this.spawnCursor >= TOTAL) {
            EclipseMod.LOGGER.info("CreditsFormationAct: backdrop complete — {} display(s) in formation",
                    this.displays.size());
        }
    }

    /** One lookahead interpolation window toward the pose at {@code actTick + PUSH_STRIDE}. */
    void animate(int actTick) {
        for (int i = 0; i < this.displays.size(); i++) {
            Display.BlockDisplay piece = this.displays.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(pose(i, actTick + PUSH_STRIDE, 1.0F));
        }
    }

    /** End-of-act exit: one long push to the scale floor (nothing pops out of the sky). */
    void shrinkOut(int actTick, int windowTicks) {
        for (int i = 0; i < this.displays.size(); i++) {
            Display.BlockDisplay piece = this.displays.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(windowTicks);
            piece.setTransformation(pose(i, actTick, SCALE_FLOOR));
        }
    }

    void discard() {
        for (Display.BlockDisplay piece : this.displays) {
            CreditsSequence.untrackDisplay(piece);
            piece.discard();
        }
        this.displays.clear();
    }

    // ------------------------------------------------------------------ poses

    /**
     * Absolute pose of formation element {@code index} at {@code actTick} (translation is
     * relative to the shared anchor; +X = east = the view axis). {@code shrink} rides the
     * end-of-act shrink-out push.
     */
    private Transformation pose(int index, int actTick, float shrink) {
        Vector3f offset;
        float baseScale;
        if (index < SPIRAL_COUNT) {
            offset = spiralOffset(index, actTick);
            baseScale = 0.7F + (float) CreditsSequence.hash01(index, 82) * 1.5F;
        } else if (index < SPIRAL_COUNT + RING_GROUPS * RING_SIZE) {
            offset = ringOffset(index - SPIRAL_COUNT, actTick);
            baseScale = 0.9F + (float) CreditsSequence.hash01(index, 82) * 1.1F;
        } else {
            offset = columnOffset(index - SPIRAL_COUNT - RING_GROUPS * RING_SIZE, actTick);
            baseScale = 0.8F + (float) CreditsSequence.hash01(index, 82) * 1.0F;
        }
        // Gentle golden-phased tumble — neighbors never spin in sync (BD-SHIP law).
        float spin = index * CreditsSequence.GOLDEN_ANGLE
                + actTick * (0.004F + (float) CreditsSequence.hash01(index, 83) * 0.006F);
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(index, 84) * 2.0D - 1.0D),
                (float) (0.35D + CreditsSequence.hash01(index, 85)),
                (float) (CreditsSequence.hash01(index, 86) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        float scale = Math.max(SCALE_FLOOR,
                baseScale * growIn(index, actTick) * columnEnvelope(index, actTick) * shrink);
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = offset.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /**
     * Spiral-band element: phyllotaxis around the east view axis. Radius and depth are
     * per-element constants; the whole tunnel slowly turns (three bands at 1×/1.6×/2.3×
     * the base rate, alternating sign) and drifts a slow ±5-block axial breath.
     */
    private static Vector3f spiralOffset(int index, int actTick) {
        int band = index % 3;
        float rate = BAND_RATE * (band == 0 ? 1.0F : band == 1 ? -1.6F : 2.3F);
        // sqrt-uniform in area, biased outward (^0.8) — denser toward the horizon rim.
        float radial = (float) Math.pow(CreditsSequence.hash01(index, 87), 0.8D);
        float radius = TUNNEL_RADIUS_MIN + (TUNNEL_RADIUS_MAX - TUNNEL_RADIUS_MIN)
                * (float) Math.sqrt(radial);
        float theta = index * CreditsSequence.GOLDEN_ANGLE + actTick * rate;
        float depth = (float) CreditsSequence.hash01(index, 88) * TUNNEL_DEPTH
                + 5.0F * Mth.sin(actTick * 0.006F + index * 0.7F);
        // Squashed vertically, lifted over the sea; the bottom arc folds onto a
        // sea-skimming band (never under the water plane).
        float y = Math.max(radius * Mth.sin(theta) * 0.62F + 26.0F, 3.0F);
        return new Vector3f(depth, y, radius * Mth.cos(theta));
    }

    /** Ring element: face-on ring at a staggered depth, alternating spin, breathing radius. */
    private static Vector3f ringOffset(int ringIndex, int actTick) {
        int group = ringIndex / RING_SIZE;
        int slot = ringIndex % RING_SIZE;
        float radius = RING_RADIUS_MIN + group * RING_RADIUS_STEP;
        radius *= 1.0F + 0.06F * Mth.sin(actTick * 0.0035F + group * 1.9F);
        float rate = RING_RATE * (group % 2 == 0 ? 1.0F : -1.0F) * (1.0F + group * 0.12F);
        float theta = slot * (Mth.TWO_PI / RING_SIZE) + actTick * rate + group * 0.61F;
        float depth = RING_DEPTH_MIN + group * RING_DEPTH_STEP;
        // Slight tilt per ring so the stack never reads as flat billboards.
        float tilt = (group - RING_GROUPS / 2.0F) * 0.08F;
        float y = Math.max(radius * Mth.sin(theta) + 30.0F, 2.0F); // rings dip TO the sea, not under
        float z = radius * Mth.cos(theta);
        return new Vector3f(depth + z * tilt, y, z);
    }

    /**
     * Column element: {@code COLUMN_GROUPS} golden-angle scattered sea-surface columns;
     * each element climbs its column's {@value #COLUMN_CLIMB}-block run on a wrapping
     * clock (staggered per slot) — {@link #columnEnvelope} floors the scale at both wrap
     * ends so the seam never pops.
     */
    private static Vector3f columnOffset(int columnIndex, int actTick) {
        int group = columnIndex / COLUMN_SIZE;
        float fieldR = COLUMN_FIELD_MIN + (COLUMN_FIELD_MAX - COLUMN_FIELD_MIN)
                * (float) Math.sqrt((group + 0.5F) / COLUMN_GROUPS);
        float fieldTheta = group * CreditsSequence.GOLDEN_ANGLE;
        float climb = columnProgress(columnIndex, actTick) * COLUMN_CLIMB;
        float sway = 2.5F * Mth.sin(actTick * 0.008F + group * 2.3F);
        return new Vector3f(
                40.0F + fieldR * Math.abs(Mth.sin(fieldTheta)) + sway,
                2.0F + climb,
                fieldR * Mth.cos(fieldTheta) * 0.8F);
    }

    /** Wrapping climb clock 0..1 of a column element (slot-staggered, per-column phase). */
    private static float columnProgress(int columnIndex, int actTick) {
        int slot = columnIndex % COLUMN_SIZE;
        int phase = slot * (COLUMN_CYCLE / COLUMN_SIZE)
                + (int) (CreditsSequence.hash01(columnIndex, 89) * 40.0D);
        return Math.floorMod(actTick + phase, COLUMN_CYCLE) / (float) COLUMN_CYCLE;
    }

    /** Scale envelope hiding the column wrap seam (1 for spiral/ring elements). */
    private float columnEnvelope(int index, int actTick) {
        int columnStart = SPIRAL_COUNT + RING_GROUPS * RING_SIZE;
        if (index < columnStart) {
            return 1.0F;
        }
        float p = columnProgress(index - columnStart, actTick);
        return Mth.clamp(Math.min(p, 1.0F - p) / 0.10F, SCALE_FLOOR, 1.0F);
    }

    /** Spawn grow-in: element {@code i} eases from 0→1 scale over its first 40 ticks. */
    private static float growIn(int index, int actTick) {
        float spawnTick = index / (float) SPAWN_PER_TICK;
        float linear = Mth.clamp((actTick - spawnTick) / GROW_IN_TICKS, 0.0F, 1.0F);
        return linear * linear * (3.0F - 2.0F * linear);
    }
}
