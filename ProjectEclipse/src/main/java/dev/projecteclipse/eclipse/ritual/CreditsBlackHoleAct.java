package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.List;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/**
 * F-056 — the black-hole finale's stage manager. The shot: everyone parked at a HIGH
 * tele-vantage far south of the map center ({@value #VANTAGE_SOUTH} blocks out,
 * y={@value #VANTAGE_Y}), FOV crushed client-side ({@code S2CCreditsFovPayload}) — the
 * orthographic-looking "whole map from above" read — while a giant black hole eats the
 * world at the sanctum column.
 *
 * <p><b>The screen-alignment trick</b> (the eclipse-anchor law at finale scale): the true
 * hole center sits ~{@value #VANTAGE_SOUTH} blocks from the players — far outside display
 * tracking range AND chunk render distance. So nothing visual is staged there: the Photon
 * maw ({@code eclipse:black_hole_maw}) and every display entity anchor at
 * {@link #fxAnchor()}, the point {@value #ANCHOR_AHEAD} blocks along the players'
 * EXACT view ray toward the hole. Through the crushed FOV the anchor is pixel-aligned
 * with the true center and the authored ~26-block maw reads as a map-devouring monster
 * (~4× angular scale-up). The Veil post pass ({@code eclipse:black_hole}) projects the
 * TRUE center per frame ({@code SunTracker.worldToNdc}) — both layers land on the same
 * screen spot by construction.</p>
 *
 * <p><b>Displays</b>: {@value #COUNT} map-palette fragments spawn on a wide accretion
 * shell around the anchor (in the camera-facing disc plane) and spiral inward over
 * {@value #SPIRAL_TICKS}t — staggered launches, 2–4.5 turns each, radius collapsing on an
 * accelerating curve, scale draining to the floor as each one crosses the horizon
 * (swallowed, never popped). Budgeted spawn ({@value #SPAWN_PER_TICK}/t), pushes on the
 * {@value #PUSH_STRIDE}t stride, hard-cap checked, {@link #TAG} stray-sweep covered,
 * discarded behind the final black.</p>
 */
final class CreditsBlackHoleAct {
    static final String TAG = "eclipse_credits_blackhole";

    /** Spiraling map-debris displays (F-056 ask: 300–600). */
    static final int COUNT = 480;
    static final int SPAWN_PER_TICK = 48;
    static final int PUSH_STRIDE = 10;
    /** Full consume duration: reveal → all swallowed (the act's master clock). */
    static final int SPIRAL_TICKS = 1300;
    /** Photon maw re-fire cadence (kneel-corona sustain law: re-sends dedup silently). */
    static final int MAW_CADENCE = 300;

    /** Vantage geometry: high above and far south of the map center. */
    private static final double VANTAGE_SOUTH = 430.0D;
    private static final double VANTAGE_Y = 300.0D;
    /** How far above the island top the hole's visual center sits. */
    private static final double HOLE_ABOVE_TOP = 30.0D;
    /** FX/display anchor distance along the view ray (inside tracking range). */
    private static final double ANCHOR_AHEAD = 110.0D;

    // --- accretion shell (anchor-frame blocks; ~4.3× that at map scale) ---
    private static final float SHELL_RADIUS_MIN = 24.0F;
    private static final float SHELL_RADIUS_MAX = 92.0F;
    private static final float SWALLOW_RADIUS = 1.6F;

    private static final float VIEW_RANGE = 4.0F;
    private static final float SCALE_FLOOR = 0.02F;

    /** The map's greatest hits — what the world is made of, torn loose. */
    private static final BlockState[] PALETTE = {
            Blocks.GRASS_BLOCK.defaultBlockState(),
            Blocks.DIRT.defaultBlockState(),
            Blocks.STONE.defaultBlockState(),
            Blocks.SAND.defaultBlockState(),
            Blocks.OAK_LOG.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState()};

    private final List<Display.BlockDisplay> displays = new ArrayList<>(COUNT);
    private Vec3 holeCenter = Vec3.ZERO;
    private Vec3 vantage = Vec3.ZERO;
    private Vec3 fxAnchor = Vec3.ZERO;
    /** Camera-facing disc basis at the anchor (right / up / toward-camera normal). */
    private Vector3f right = new Vector3f(1.0F, 0.0F, 0.0F);
    private Vector3f up = new Vector3f(0.0F, 1.0F, 0.0F);
    private float yaw;
    private float pitch;
    private int spawnCursor;
    private boolean prepared;

    /**
     * Computes the whole stage from the sanctum altar column (fallback: the overworld
     * spawn). Never fails — the finale must always have SOME center to devour.
     */
    void prepare(ServerLevel overworld, @javax.annotation.Nullable BlockPos altarPos) {
        BlockPos center = altarPos != null ? altarPos : overworld.getSharedSpawnPos();
        double topY = altarPos != null
                ? FloatingSanctumBuilder.islandTopY(altarPos)
                : center.getY();
        this.holeCenter = new Vec3(center.getX() + 0.5D, topY + HOLE_ABOVE_TOP, center.getZ() + 0.5D);
        this.vantage = new Vec3(center.getX() + 0.5D,
                Math.min(VANTAGE_Y, overworld.getMaxBuildHeight() - 12.0D),
                center.getZ() + 0.5D + VANTAGE_SOUTH);
        Vec3 toHole = this.holeCenter.subtract(this.vantage);
        Vec3 dir = toHole.normalize();
        this.fxAnchor = this.vantage.add(dir.scale(ANCHOR_AHEAD));
        // MC yaw: 0 = +Z; vantage sits south looking north (−Z) → ~180. Pitch + = down.
        this.yaw = (float) Math.toDegrees(Math.atan2(-dir.x, dir.z));
        this.pitch = (float) Math.toDegrees(
                Math.atan2(-dir.y, Math.sqrt(dir.x * dir.x + dir.z * dir.z)));
        Vector3f normal = new Vector3f((float) dir.x, (float) dir.y, (float) dir.z);
        this.right = new Vector3f(normal).cross(0.0F, 1.0F, 0.0F).normalize();
        this.up = new Vector3f(this.right).cross(normal).normalize();
        this.prepared = true;
        EclipseMod.LOGGER.info("CreditsBlackHoleAct: staged — hole {}, vantage {}, anchor {} (yaw {} pitch {})",
                this.holeCenter, this.vantage, this.fxAnchor, this.yaw, this.pitch);
    }

    boolean prepared() {
        return this.prepared;
    }

    /** The TRUE map-center hole position (the post pass + sky payload anchor). */
    Vec3 holeCenter() {
        return this.holeCenter;
    }

    /** Player park position for the tele shot. */
    Vec3 vantage() {
        return this.vantage;
    }

    /** Screen-aligned near anchor for the Photon maw + every display entity. */
    Vec3 fxAnchor() {
        return this.fxAnchor;
    }

    float vantageYaw() {
        return this.yaw;
    }

    float vantagePitch() {
        return this.pitch;
    }

    boolean spawnRemaining() {
        return this.spawnCursor < COUNT;
    }

    /** Budgeted spawn wave; every entity parks at the shared anchor (tracking-safe). */
    void spawnBatch(ServerLevel overworld, int actTick) {
        int budget = SPAWN_PER_TICK;
        while (budget-- > 0 && this.spawnCursor < COUNT) {
            if (CreditsSequence.actCapReached()) {
                this.spawnCursor = COUNT;
                break;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(overworld);
            if (piece == null) {
                return;
            }
            int i = this.spawnCursor;
            piece.moveTo(this.fxAnchor.x, this.fxAnchor.y, this.fxAnchor.z, 0.0F, 0.0F);
            piece.setBlockState(PALETTE[
                    (int) (CreditsSequence.hash01(i, 91) * PALETTE.length) % PALETTE.length]);
            piece.addTag(TAG);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            piece.setTransformation(pose(i, actTick));
            // Dim space-lit silhouettes — the post pass drains them further anyway.
            CreditsSequence.applyBrightnessOverride(piece, 6, 3);
            CreditsSequence.applyViewRange(piece, VIEW_RANGE);
            CreditsSequence.trackDisplay(piece);
            overworld.addFreshEntity(piece);
            this.displays.add(piece);
            this.spawnCursor++;
        }
        if (this.spawnCursor >= COUNT) {
            EclipseMod.LOGGER.info("CreditsBlackHoleAct: accretion field live — {} display(s) falling in",
                    this.displays.size());
        }
    }

    /** One lookahead interpolation window per {@value #PUSH_STRIDE}t. */
    void animate(int actTick) {
        for (int i = 0; i < this.displays.size(); i++) {
            Display.BlockDisplay piece = this.displays.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(pose(i, actTick + PUSH_STRIDE));
        }
    }

    void discard() {
        for (Display.BlockDisplay piece : this.displays) {
            CreditsSequence.untrackDisplay(piece);
            piece.discard();
        }
        this.displays.clear();
    }

    // ------------------------------------------------------------------ pose

    /**
     * Absolute pose of accretion fragment {@code index} at {@code actTick}: a staggered
     * inward spiral in the camera-facing disc plane. Pure function of (index, tick) —
     * the stateless-push law.
     */
    private Transformation pose(int index, int actTick) {
        float p = Mth.clamp(actTick / (float) SPIRAL_TICKS, 0.0F, 1.0F);
        float launch = (float) CreditsSequence.hash01(index, 92) * 0.55F;
        float q = Mth.clamp((p - launch) / (1.0F - launch), 0.0F, 1.0F);

        float r0 = SHELL_RADIUS_MIN + (SHELL_RADIUS_MAX - SHELL_RADIUS_MIN)
                * (float) Math.sqrt(CreditsSequence.hash01(index, 93));
        // Accelerating infall: slow far out, rushing over the horizon.
        float radius = Math.max(SWALLOW_RADIUS,
                r0 * (float) Math.pow(1.0F - q, 1.35D));
        float turns = 2.0F + (float) CreditsSequence.hash01(index, 94) * 2.5F;
        float theta = index * CreditsSequence.GOLDEN_ANGLE
                + turns * Mth.TWO_PI * q * q
                + actTick * 0.0016F; // the whole disc slowly turns even pre-launch
        // Small out-of-plane wobble so the disc has body, damped as it falls in.
        float wobble = 6.0F * (1.0F - q)
                * Mth.sin(index * 2.1F + actTick * 0.01F);

        Vector3f offset = new Vector3f(this.right).mul(radius * Mth.cos(theta))
                .add(new Vector3f(this.up).mul(radius * Mth.sin(theta) * 0.55F))
                .add(new Vector3f(this.right).cross(this.up, new Vector3f()).mul(wobble));

        float tumble = index * CreditsSequence.GOLDEN_ANGLE
                + q * (3.0F + (float) CreditsSequence.hash01(index, 95) * 5.0F);
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(index, 96) * 2.0D - 1.0D),
                (float) (0.3D + CreditsSequence.hash01(index, 97)),
                (float) (CreditsSequence.hash01(index, 98) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(tumble, axis);

        // Swallowed: scale drains to the floor across the last 15% of the fall.
        float swallow = Mth.clamp((q - 0.85F) / 0.15F, 0.0F, 1.0F);
        float scale = Math.max(SCALE_FLOOR,
                (1.4F + (float) CreditsSequence.hash01(index, 99) * 2.6F) * (1.0F - swallow));
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = offset.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }
}
