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
 *   <li><b>Spiral arms</b> ({@value #SPIRAL_COUNT}, F-068 rework of the phyllotaxis
 *       scatter) — {@value #SPIRAL_ARMS} COHERENT debris arms winding around the players'
 *       east view line: two interleaved 3-arm spirals counter-rotating at incommensurate
 *       rates (the whole composition slowly orbits, the arms keep their shape). Element
 *       radius is bunched toward the {@value #TUNNEL_RADIUS_MAX} rim (outward ^0.7 bias)
 *       and depth is bunched toward the horizon end of the tunnel (^0.65 bias) — the
 *       placement DENSIFIES along the camera sightlines while every element still sits
 *       ≥ {@value #TUNNEL_RADIUS_MIN} blocks off the axis: the view center (the sunrise
 *       → the eclipse) stays OPEN, the periphery/horizon reads dense — the "dichter am
 *       Horizont, offener in Blickmitte" placement law.</li>
 *   <li><b>Rotating rings</b> ({@value #RING_GROUPS}×{@value #RING_SIZE}) — face-on rings
 *       at staggered depths down the view axis, alternating spin directions, breathing
 *       ±6% radius on a slow sine, with a gentle per-ring tilt precession (F-068) so the
 *       stack never freezes into flat billboards.</li>
 *   <li><b>Column arcs</b> ({@value #COLUMN_GROUPS}×{@value #COLUMN_SIZE}, F-068 rework
 *       of the scattered field) — ascending sea-surface columns COMPOSED onto two
 *       symmetric arcs flanking the view axis (bearing swinging 0.30..1.05 rad off-axis
 *       as they recede — a receding colonnade framing the sunrise), each arc drifting a
 *       slow orbital sway; elements climb, wrap and re-climb with the wrap seam hidden by
 *       the same scale-floor envelope the flyers use.</li>
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
 *
 * <p><b>F-072 V3 "Versammlungs-Sog"</b>: every element is born {@value #GATHER_REACH}×
 * beyond its formation slot with a ±{@value #GATHER_SWIRL} rad swirl about the view
 * axis, and {@link #gather} pulls it onto the slot over its first {@value #GATHER_TICKS}
 * ticks on a smootherstep — the formations visibly ASSEMBLE (sucked into place, soft
 * catch) instead of fading in already-formed. Steady state is bit-identical to the pure
 * formation pose, so late re-pushes still agree with the stateless-push law.</p>
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
    /** Base angular drift (rad/t) of the first arm set; the second counter-rotates slower. */
    private static final float BAND_RATE = 0.0022F;
    /** F-068 spiral arms: two interleaved 3-arm spirals (6 coherent arms total). */
    private static final int SPIRAL_ARMS = 6;
    /** Winding (radians) of one arm across its radial run — a readable spiral sweep. */
    private static final float ARM_WIND = 2.6F;

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
    /** V3 gathering pull: convergence window (t), radial over-reach, swirl (rad). */
    private static final float GATHER_TICKS = 90.0F;
    private static final float GATHER_REACH = 0.45F;
    private static final float GATHER_SWIRL = 0.35F;

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

    /**
     * F-102 staggered teardown (the scripted end-of-act path): hands the ~{@value
     * #TOTAL}-strong backdrop to {@code CreditsSequence}'s removal queue instead of a
     * single-tick mass discard (the shrink-out already took every element to the scale
     * floor, so the staggered removal is invisible). The act forgets its displays here
     * — the queue owns them; {@link #discard} stays the immediate abort path.
     */
    void discardInto(java.util.function.Consumer<Display.BlockDisplay> sink) {
        for (Display.BlockDisplay piece : this.displays) {
            sink.accept(piece);
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
        offset = gather(offset, index, actTick); // V3: born wide, sucked onto the slot
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
     * Spiral-arm element (F-068): {@value #SPIRAL_ARMS} coherent arms around the east
     * view axis — arms 0–2 form one 3-arm spiral orbiting at {@value #BAND_RATE} rad/t,
     * arms 3–5 a second one counter-rotating at 0.62× (incommensurate, so the two sheets
     * cross forever without syncing). Radius runs the arm's ^0.7-biased outward sweep
     * (bunched toward the horizon rim) with ±4-block jitter; depth is ^0.65-biased
     * toward the tunnel's far end (dense along the sightlines) and breathes a slow
     * ±5-block axial sine. A small per-element angular oscillation keeps the arms alive
     * without smearing their shape.
     */
    private static Vector3f spiralOffset(int index, int actTick) {
        int arm = index % SPIRAL_ARMS;
        int slot = index / SPIRAL_ARMS;
        float s = (slot + 0.5F) / (SPIRAL_COUNT / (float) SPIRAL_ARMS); // 0..1 along the arm
        float radius = TUNNEL_RADIUS_MIN + (TUNNEL_RADIUS_MAX - TUNNEL_RADIUS_MIN)
                * (float) Math.pow(s, 0.7D)
                + ((float) CreditsSequence.hash01(index, 87) * 2.0F - 1.0F) * 4.0F;
        boolean secondSheet = arm >= 3;
        float rate = secondSheet ? -BAND_RATE * 0.62F : BAND_RATE;
        float theta = (arm % 3) * (Mth.TWO_PI / 3.0F)
                + (secondSheet ? 0.52F : 0.0F) // de-phase the sheets
                + ARM_WIND * s
                + actTick * rate
                + 0.05F * Mth.sin(actTick * 0.004F + index * 0.9F);
        float depth = (float) Math.pow(CreditsSequence.hash01(index, 88), 0.65D) * TUNNEL_DEPTH
                + 5.0F * Mth.sin(actTick * 0.006F + index * 0.7F);
        // Squashed vertically, lifted over the sea; the bottom arc folds onto a
        // sea-skimming band (never under the water plane).
        float y = Math.max(radius * Mth.sin(theta) * 0.62F + 26.0F, 3.0F);
        return new Vector3f(depth, y, radius * Mth.cos(theta));
    }

    /**
     * Ring element: face-on ring at a staggered depth, alternating spin, breathing
     * radius, with a slow per-ring tilt PRECESSION (F-068) — the stack leans and
     * recovers a few degrees over ~40 s instead of freezing into flat billboards.
     */
    private static Vector3f ringOffset(int ringIndex, int actTick) {
        int group = ringIndex / RING_SIZE;
        int slot = ringIndex % RING_SIZE;
        float radius = RING_RADIUS_MIN + group * RING_RADIUS_STEP;
        radius *= 1.0F + 0.06F * Mth.sin(actTick * 0.0035F + group * 1.9F);
        float rate = RING_RATE * (group % 2 == 0 ? 1.0F : -1.0F) * (1.0F + group * 0.12F);
        float theta = slot * (Mth.TWO_PI / RING_SIZE) + actTick * rate + group * 0.61F;
        float depth = RING_DEPTH_MIN + group * RING_DEPTH_STEP;
        // Static lean per ring + the slow precession sine.
        float tilt = (group - RING_GROUPS / 2.0F) * 0.08F
                + 0.03F * Mth.sin(actTick * 0.0025F + group * 2.7F);
        float y = Math.max(radius * Mth.sin(theta) + 30.0F, 2.0F); // rings dip TO the sea, not under
        float z = radius * Mth.cos(theta);
        return new Vector3f(depth + z * tilt, y, z);
    }

    /**
     * Column-arc element (F-068): the {@code COLUMN_GROUPS} sea-surface columns are
     * COMPOSED onto two symmetric arcs flanking the view axis — group parity picks the
     * side, the group's rank along its arc sweeps the bearing 0.30..1.05 rad off-axis
     * while the distance recedes {@value #COLUMN_FIELD_MIN}..{@value #COLUMN_FIELD_MAX}
     * blocks (a colonnade framing the sunrise, open in the middle). Each arc sways a
     * slow ±0.02 rad orbital drift. Elements climb their column's
     * {@value #COLUMN_CLIMB}-block run on a wrapping clock (staggered per slot) —
     * {@link #columnEnvelope} floors the scale at both wrap ends so the seam never pops.
     */
    private static Vector3f columnOffset(int columnIndex, int actTick) {
        int group = columnIndex / COLUMN_SIZE;
        int side = group % 2 == 0 ? 1 : -1;
        float along = (group / 2 + 0.5F) / (COLUMN_GROUPS / 2.0F); // 0..1 down the arc
        float bearing = side * (0.30F + 0.75F * along)
                + side * 0.02F * Mth.sin(actTick * 0.0035F + group * 1.3F); // orbital sway
        float dist = COLUMN_FIELD_MIN + (COLUMN_FIELD_MAX - COLUMN_FIELD_MIN) * along;
        float climb = columnProgress(columnIndex, actTick) * COLUMN_CLIMB;
        float sway = 2.5F * Mth.sin(actTick * 0.008F + group * 2.3F);
        return new Vector3f(
                40.0F + dist * Mth.cos(bearing) + sway,
                2.0F + climb,
                dist * Mth.sin(bearing));
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

    /**
     * F-072 V3 "Versammlungs-Sog": maps the pure formation offset to the element's
     * CONVERGING position during its first {@value #GATHER_TICKS} ticks — born
     * {@value #GATHER_REACH}× beyond the slot (radially off the anchor, mildly ahead on
     * the view axis) and swirled ±{@value #GATHER_SWIRL} rad about the view axis, both
     * decaying with the pull. Identity once {@code pull >= 1} (steady state stays the
     * exact formation pose). The y floor keeps the swirl from dipping under the sea.
     */
    private static Vector3f gather(Vector3f offset, int index, int actTick) {
        float pull = gatherPull(index, actTick);
        if (pull >= 1.0F) {
            return offset;
        }
        float loose = 1.0F - pull;
        float swirl = GATHER_SWIRL * loose
                * (CreditsSequence.hash01(index, 90) < 0.5D ? -1.0F : 1.0F);
        float cos = Mth.cos(swirl);
        float sin = Mth.sin(swirl);
        float y = offset.y * cos - offset.z * sin;
        float z = offset.y * sin + offset.z * cos;
        float reach = 1.0F + GATHER_REACH * loose;
        return new Vector3f(offset.x * (1.0F + 0.25F * loose),
                Math.max(y * reach, 2.0F), z * reach);
    }

    /**
     * Convergence clock 0..1: a smootherstep over the element's first
     * {@value #GATHER_TICKS}t — gentle start, decisive mid rush, soft catch (reads as
     * suction, not interpolation). 1 forever afterwards.
     */
    private static float gatherPull(int index, int actTick) {
        float spawnTick = index / (float) SPAWN_PER_TICK;
        float linear = Mth.clamp((actTick - spawnTick) / GATHER_TICKS, 0.0F, 1.0F);
        return linear * linear * linear * (linear * (linear * 6.0F - 15.0F) + 10.0F);
    }
}
