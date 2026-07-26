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
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/**
 * F-058 — the ISLAND SHATTER act of the final credits (owned and clocked by
 * {@link CreditsSequence}; this class only holds the per-run display state and the
 * deterministic choreography):
 *
 * <p><b>Sampling</b> ({@link #prepare}): the REAL top-surface blocks of the sanctum
 * island are read column by column across the {@link FloatingSanctumBuilder} ellipse
 * (r 16×14, ~700 columns; the altar/dais columns fall inside it), plus a hashed ~65%
 * second-layer pick — {@value #SAMPLE_CAP}-capped, typically ~1100 fragments, inside the
 * requested 800–1500 band. The world is NEVER modified (Kulisse law): each sample spawns
 * one {@code BLOCK_DISPLAY} exactly over its source block (identity transform — the
 * overlay is pixel-perfect until the first drift push).</p>
 *
 * <p><b>Choreography</b>: a pure function of the act clock (stateless-push law, the
 * {@code debrisPose} recipe) — every fragment gets a hashed launch delay, then drifts
 * outward along its column's radial direction while RISING (up-bias 0.55..1.3), tumbling
 * slowly around a hashed axis. Pushes ride {@value #PUSH_STRIDE}t interpolation windows
 * (~{@value #SAMPLE_CAP}/{@value #PUSH_STRIDE} ≈ 145 entity updates/t worst case, well
 * inside the FIN-6 display budget); spawns are budgeted by the caller. Discard is
 * guaranteed: {@link CreditsSequence} discards on the act-end beat, on skip, on
 * {@code /dev end_event} and belt-and-braces at run teardown, and every display carries
 * {@link #TAG} for the crash-stray join sweep.</p>
 */
final class CreditsShatterAct {
    /** Crash-stray sweep tag ({@code CreditsSequence.onEntityJoin}). */
    static final String TAG = "eclipse_credits_shatter";
    /** Hard sample cap (the F-058 spec band is 800–1500). */
    static final int SAMPLE_CAP = 1400;
    /** Budgeted spawn rate (fragments per tick) while samples remain. */
    static final int SPAWN_PER_TICK = 60;
    /** Transform-push cadence == interpolation window length. */
    static final int PUSH_STRIDE = 10;
    /** Act length (local ticks) the drift progress is normalized over. */
    static final int DRIFT_TICKS = 450;
    /** Widened display view range (×64 blocks) — the far island rim is ~85 blocks out. */
    private static final float VIEW_RANGE = 2.5F;
    /** Fragments never fully vanish mid-shot; they thin slightly while rising. */
    private static final float END_SCALE = 0.9F;

    private record Sample(BlockPos pos, BlockState state) {}

    private final List<Sample> samples = new ArrayList<>();
    private final List<Display.BlockDisplay> fragments = new ArrayList<>();
    private BlockPos altar;
    private int islandTop;
    private int spawnCursor;

    /**
     * Reads the island's surface into the sample list. Returns {@code false} (act
     * invalid, {@link CreditsSequence} skips the whole shatter window) when the sanctum
     * was never built.
     */
    boolean prepare(ServerLevel overworld, @javax.annotation.Nullable BlockPos altarPos) {
        if (altarPos == null) {
            return false;
        }
        this.altar = altarPos;
        this.islandTop = FloatingSanctumBuilder.islandTopY(altarPos);
        int rx = FloatingSanctumBuilder.SURFACE_RADIUS_X;
        int rz = FloatingSanctumBuilder.SURFACE_RADIUS_Z;
        for (int dx = -rx; dx <= rx && this.samples.size() < SAMPLE_CAP; dx++) {
            for (int dz = -rz; dz <= rz && this.samples.size() < SAMPLE_CAP; dz++) {
                double ellipse = dx * dx / (double) (rx * rx) + dz * dz / (double) (rz * rz);
                if (ellipse > 1.0D) {
                    continue;
                }
                int x = altarPos.getX() + dx;
                int z = altarPos.getZ() + dz;
                overworld.getChunk(x >> 4, z >> 4); // force-load (GhostShipBuilder pattern)
                // Top-down scan catches the altar (top+4), dais steps and pillar stumps.
                int surfaceY = Integer.MIN_VALUE;
                for (int y = this.islandTop + 6; y >= this.islandTop - 2; y--) {
                    BlockPos pos = new BlockPos(x, y, z);
                    BlockState state = overworld.getBlockState(pos);
                    if (!state.isAir() && state.getRenderShape() != net.minecraft.world.level.block.RenderShape.INVISIBLE) {
                        this.samples.add(new Sample(pos, state));
                        surfaceY = y;
                        break;
                    }
                }
                // Hashed second-layer pick fills the count toward the 800–1500 band.
                if (surfaceY != Integer.MIN_VALUE && this.samples.size() < SAMPLE_CAP
                        && CreditsSequence.hash01(dx * 61 + dz, 61) < 0.65D) {
                    BlockPos below = new BlockPos(x, surfaceY - 1, z);
                    BlockState state = overworld.getBlockState(below);
                    if (!state.isAir()) {
                        this.samples.add(new Sample(below, state));
                    }
                }
            }
        }
        EclipseMod.LOGGER.info("CreditsShatterAct: sampled {} island fragment(s) around {}",
                this.samples.size(), altarPos.toShortString());
        return !this.samples.isEmpty();
    }

    /** The audience anchor: hovering south of the island, eye-level with the plateau. */
    Vec3 vantage() {
        return new Vec3(this.altar.getX() + 0.5D, this.islandTop + 13.0D, this.altar.getZ() + 52.5D);
    }

    /** FX/sound anchor: the island's visual center, slightly above the plateau. */
    Vec3 islandCenter() {
        return new Vec3(this.altar.getX() + 0.5D, this.islandTop + 4.0D, this.altar.getZ() + 0.5D);
    }

    boolean prepared() {
        return !this.samples.isEmpty();
    }

    boolean spawnRemaining() {
        return this.spawnCursor < this.samples.size();
    }

    /** Budgeted spawn wave (≤ {@value #SPAWN_PER_TICK}/t, hard-cap guarded). */
    void spawnBatch(ServerLevel overworld, int actTick) {
        int budget = SPAWN_PER_TICK;
        while (budget-- > 0 && this.spawnCursor < this.samples.size()) {
            if (CreditsSequence.actCapReached()) {
                // Over cap: keep what flies, stop trying (the flyer-wave contract).
                this.spawnCursor = this.samples.size();
                return;
            }
            Display.BlockDisplay fragment = EntityType.BLOCK_DISPLAY.create(overworld);
            if (fragment == null) {
                return; // retry the same index next tick (list/index alignment invariant)
            }
            int i = this.spawnCursor;
            Sample sample = this.samples.get(i);
            fragment.moveTo(sample.pos().getX(), sample.pos().getY(), sample.pos().getZ(),
                    0.0F, 0.0F);
            fragment.setBlockState(sample.state());
            fragment.addTag(TAG);
            fragment.setTransformationInterpolationDelay(0);
            fragment.setTransformationInterpolationDuration(0);
            fragment.setTransformation(pose(i, actTick));
            CreditsSequence.applyViewRange(fragment, VIEW_RANGE);
            CreditsSequence.trackDisplay(fragment);
            overworld.addFreshEntity(fragment);
            this.fragments.add(fragment);
            this.spawnCursor++;
        }
        if (this.spawnCursor >= this.samples.size()) {
            EclipseMod.LOGGER.info("CreditsShatterAct: island airborne — {} fragment display(s) live",
                    this.fragments.size());
        }
    }

    /** One lookahead interpolation window per fragment (FloatingDecor transport pattern). */
    void animate(int actTick) {
        for (int i = 0; i < this.fragments.size(); i++) {
            Display.BlockDisplay fragment = this.fragments.get(i);
            if (fragment.isRemoved()) {
                continue;
            }
            fragment.setTransformationInterpolationDelay(0);
            fragment.setTransformationInterpolationDuration(PUSH_STRIDE);
            fragment.setTransformation(pose(i, actTick + PUSH_STRIDE));
        }
    }

    /**
     * Absolute fragment pose at local act tick {@code actTick}: hashed launch delay,
     * then an eased outward drift along the column's radial + a strong rise, with a slow
     * hashed-axis tumble — deterministic per index, so re-pushes always agree.
     */
    private Transformation pose(int index, int actTick) {
        Sample sample = this.samples.get(index);
        float p = Mth.clamp(actTick / (float) DRIFT_TICKS, 0.0F, 1.0F);
        float launch = (float) CreditsSequence.hash01(index, 71) * 0.3F;
        float q = Mth.clamp((p - launch) / (1.0F - launch), 0.0F, 1.0F);
        float drive = q * q * (3.0F - 2.0F * q);

        double dx = sample.pos().getX() + 0.5D - (this.altar.getX() + 0.5D);
        double dz = sample.pos().getZ() + 0.5D - (this.altar.getZ() + 0.5D);
        double r = Math.sqrt(dx * dx + dz * dz);
        float outX;
        float outZ;
        if (r < 0.5D) {
            double angle = CreditsSequence.hash01(index, 72) * Math.PI * 2.0D;
            outX = (float) Math.cos(angle);
            outZ = (float) Math.sin(angle);
        } else {
            outX = (float) (dx / r);
            outZ = (float) (dz / r);
        }
        float reach = 8.0F + (float) CreditsSequence.hash01(index, 73) * 20.0F;
        float riseBias = 0.55F + (float) CreditsSequence.hash01(index, 74) * 0.75F;
        float x = outX * reach * drive * (0.6F + 0.5F * (float) CreditsSequence.hash01(index, 75));
        float y = reach * riseBias * drive;
        float z = outZ * reach * drive * (0.6F + 0.5F * (float) CreditsSequence.hash01(index, 76));

        float spin = drive * (0.8F + (float) CreditsSequence.hash01(index, 77) * 1.6F);
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(index, 78) * 2.0D - 1.0D),
                (float) (0.3D + CreditsSequence.hash01(index, 79)),
                (float) (CreditsSequence.hash01(index, 80) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        float scale = Mth.lerp(drive, 1.0F, END_SCALE);
        // Rotate about the block CENTER: counter-rotate the half extent, then re-center.
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = new Vector3f(x + 0.5F, y + 0.5F, z + 0.5F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /** Guaranteed teardown — every fragment display is discarded and untracked. */
    void discard() {
        for (Display.BlockDisplay fragment : this.fragments) {
            CreditsSequence.untrackDisplay(fragment);
            fragment.discard();
        }
        this.fragments.clear();
    }
}
