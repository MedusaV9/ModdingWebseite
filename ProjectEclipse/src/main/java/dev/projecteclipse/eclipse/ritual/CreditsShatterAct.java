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
 * <p><b>Choreography (F-068 shatter polish)</b>: a pure function of the act clock
 * (stateless-push law, the {@code debrisPose} recipe) — every fragment gets a hashed
 * launch delay, then drifts outward along its column's radial direction while RISING
 * (up-bias 0.55..1.3). Fragments carry a SIZE CLASS (a boulder minority swells toward
 * 1.6–2.1× and tumbles lazily; a shard tier thins toward 0.45–0.7× and spins hot; the
 * rest hold near 1× — every class still spawns at the pixel-perfect identity scale and
 * only diverges with the drift). The tumble is an IMPULSE: the launch kicks the spin
 * hard and it decays toward a lazy drift (the {@code 1-(1-q)^3} integral). Two
 * {@link #AFTERSHOCK_AT} beats step every airborne fragment a small extra reach outward
 * (the island coughs twice more; {@code CreditsSequence} pairs them with shake +
 * thunder, the Photon veil bakes matching rings). On top of the samples a
 * {@link #splinterCount} SPLINTER SHOWER spawns — small shards growing out of hashed
 * source columns and ejecting fast and far. The ALTAR CORE (the |dx|,|dz| ≤ 2 columns at
 * dais height) launches LAST at {@value #CORE_BREAK_TICK}t — {@code CreditsSequence}
 * fires the light flash on that exact beat and the Photon veil bakes the matching core
 * flash.</p>
 *
 * <p>Pushes ride {@value #PUSH_STRIDE}t interpolation windows (~1850/{@value
 * #PUSH_STRIDE} ≈ 185 entity updates/t worst case, inside the FIN-6 display budget);
 * spawns are budgeted by the caller. Discard is guaranteed: {@link CreditsSequence}
 * discards on the act-end beat, on skip, on {@code /dev end_event} and belt-and-braces
 * at run teardown, and every display carries {@link #TAG} for the crash-stray join
 * sweep.</p>
 */
final class CreditsShatterAct {
    /** Crash-stray sweep tag ({@code CreditsSequence.onEntityJoin}). */
    static final String TAG = "eclipse_credits_shatter";
    /** Hard sample cap (the F-058 spec band is 800–1500). */
    static final int SAMPLE_CAP = 1400;
    /** Extra splinter-shower displays on top of the samples (F-068). */
    static final int SPLINTER_CAP = 420;
    /** Budgeted spawn rate (fragments per tick) while samples remain. */
    static final int SPAWN_PER_TICK = 60;
    /** Transform-push cadence == interpolation window length. */
    static final int PUSH_STRIDE = 10;
    /** Act length (local ticks) the drift progress is normalized over. */
    static final int DRIFT_TICKS = 450;
    /**
     * Act tick the altar-core fragments break loose (their launch fraction band is
     * {@value #CORE_LAUNCH_MIN}..{@value #CORE_LAUNCH_MIN}+{@value #CORE_LAUNCH_VAR} of
     * {@value #DRIFT_TICKS}t — this is the band's leading edge, the flash beat).
     */
    static final int CORE_BREAK_TICK = 270;
    /** Aftershock beats (act ticks): every airborne fragment steps a little further out. */
    static final int[] AFTERSHOCK_AT = {150, 300};
    /** Core launch fraction band (of the drift clock). */
    private static final float CORE_LAUNCH_MIN = 0.60F;
    private static final float CORE_LAUNCH_VAR = 0.06F;
    /** Aftershock kick: extra reach fraction eased in over {@value #AFTERSHOCK_RAMP}t. */
    private static final float AFTERSHOCK_KICK = 0.11F;
    private static final int AFTERSHOCK_RAMP = 50;
    /** Widened display view range (×64 blocks) — the far island rim is ~85 blocks out. */
    private static final float VIEW_RANGE = 2.5F;
    /** Splinters never fully vanish mid-shot either; floor for every scale envelope. */
    private static final float SCALE_FLOOR = 0.02F;

    private record Sample(BlockPos pos, BlockState state, boolean core) {}

    private final List<Sample> samples = new ArrayList<>();
    private final List<Display.BlockDisplay> fragments = new ArrayList<>();
    private BlockPos altar;
    private int islandTop;
    private int spawnCursor;
    /** Splinter-shower size, fixed at prepare time (~30% of the sample count). */
    private int splinterCount;

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
                        // F-068: the altar/dais core breaks LAST (the CORE_BREAK_TICK flash).
                        boolean core = Math.abs(dx) <= 2 && Math.abs(dz) <= 2
                                && y >= this.islandTop + 1;
                        this.samples.add(new Sample(pos, state, core));
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
                        this.samples.add(new Sample(below, state, false));
                    }
                }
            }
        }
        this.splinterCount = Math.min(SPLINTER_CAP, this.samples.size() * 3 / 10);
        EclipseMod.LOGGER.info("CreditsShatterAct: sampled {} island fragment(s) around {} "
                + "(+{} splinter(s) planned)", this.samples.size(), altarPos.toShortString(),
                this.splinterCount);
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

    /** Total display count: sampled fragments + the splinter shower. */
    private int totalCount() {
        return this.samples.size() + this.splinterCount;
    }

    boolean spawnRemaining() {
        return this.spawnCursor < totalCount();
    }

    /** Budgeted spawn wave (≤ {@value #SPAWN_PER_TICK}/t, hard-cap guarded). */
    void spawnBatch(ServerLevel overworld, int actTick) {
        int budget = SPAWN_PER_TICK;
        while (budget-- > 0 && this.spawnCursor < totalCount()) {
            if (CreditsSequence.actCapReached()) {
                // Over cap: keep what flies, stop trying (the flyer-wave contract).
                this.spawnCursor = totalCount();
                return;
            }
            Display.BlockDisplay fragment = EntityType.BLOCK_DISPLAY.create(overworld);
            if (fragment == null) {
                return; // retry the same index next tick (list/index alignment invariant)
            }
            int i = this.spawnCursor;
            Sample sample = this.samples.get(sourceSampleIndex(i));
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
        if (this.spawnCursor >= totalCount()) {
            EclipseMod.LOGGER.info("CreditsShatterAct: island airborne — {} fragment display(s) live "
                    + "({} sampled + {} splinter(s))", this.fragments.size(), this.samples.size(),
                    Math.max(0, this.fragments.size() - this.samples.size()));
        }
    }

    /** Source sample of display {@code index} (splinters hash onto a sampled column). */
    private int sourceSampleIndex(int index) {
        if (index < this.samples.size()) {
            return index;
        }
        return (int) (CreditsSequence.hash01(index - this.samples.size(), 66) * this.samples.size());
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
     * Impulse tumble integral: the launch kicks the rotation hard, the rate decays to a
     * lazy drift (reaches exactly 1 at q=1 — the total spin stays hash-budgeted).
     */
    private static float impulseTumble(float q) {
        float inv = 1.0F - q;
        return 1.0F - inv * inv * inv;
    }

    /** Sum of the eased {@link #AFTERSHOCK_AT} reach kicks live at {@code actTick}. */
    private static float aftershockKick(int actTick) {
        float kick = 0.0F;
        for (int at : AFTERSHOCK_AT) {
            float w = Mth.clamp((actTick - at) / (float) AFTERSHOCK_RAMP, 0.0F, 1.0F);
            kick += AFTERSHOCK_KICK * w * w * (3.0F - 2.0F * w);
        }
        return kick;
    }

    /**
     * Absolute fragment pose at local act tick {@code actTick}: hashed launch delay
     * (altar-core columns hold until the {@value #CORE_BREAK_TICK} beat), then an eased
     * outward drift along the column's radial + a strong rise, an impulse-decay tumble,
     * the aftershock reach steps, and the per-class size envelope — deterministic per
     * index, so re-pushes always agree.
     */
    private Transformation pose(int index, int actTick) {
        boolean splinter = index >= this.samples.size();
        Sample sample = this.samples.get(sourceSampleIndex(index));
        float p = Mth.clamp(actTick / (float) DRIFT_TICKS, 0.0F, 1.0F);
        float launch;
        if (sample.core() && !splinter) {
            // The altar heart holds while the island leaves — then breaks with the flash.
            launch = CORE_LAUNCH_MIN + (float) CreditsSequence.hash01(index, 71) * CORE_LAUNCH_VAR;
        } else if (splinter) {
            launch = 0.05F + (float) CreditsSequence.hash01(index, 71) * 0.40F;
        } else {
            launch = (float) CreditsSequence.hash01(index, 71) * 0.3F;
        }
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
        // Splinters eject harder and flatter; boulders drift heavy and slow.
        float reach = splinter
                ? 16.0F + (float) CreditsSequence.hash01(index, 73) * 26.0F
                : 8.0F + (float) CreditsSequence.hash01(index, 73) * 20.0F;
        float riseBias = sample.core() && !splinter
                ? 1.3F + (float) CreditsSequence.hash01(index, 74) * 0.4F // the heart climbs
                : 0.55F + (float) CreditsSequence.hash01(index, 74) * 0.75F;
        // F-068 aftershocks: each beat steps every airborne fragment a bit further out.
        float kicked = drive * (1.0F + aftershockKick(actTick) * Mth.clamp(q * 4.0F, 0.0F, 1.0F));
        float x = outX * reach * kicked * (0.6F + 0.5F * (float) CreditsSequence.hash01(index, 75));
        float y = reach * riseBias * drive;
        float z = outZ * reach * kicked * (0.6F + 0.5F * (float) CreditsSequence.hash01(index, 76));

        // Impulse tumble (F-068): hot at launch, decaying — splinters spin ~2.5× hotter,
        // the boulder class (the same hash the size envelope reads) stays lazy.
        float spinBudget = splinter
                ? 2.5F + (float) CreditsSequence.hash01(index, 77) * 4.0F
                : 0.8F + (float) CreditsSequence.hash01(index, 77) * 1.6F;
        if (!splinter && CreditsSequence.hash01(index, 65) < 0.10D) {
            spinBudget *= 0.55F;
        }
        float spin = impulseTumble(q) * spinBudget;
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(index, 78) * 2.0D - 1.0D),
                (float) (0.3D + CreditsSequence.hash01(index, 79)),
                (float) (CreditsSequence.hash01(index, 80) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        float scale = Math.max(SCALE_FLOOR, scaleEnvelope(index, sample, splinter, drive));
        // Rotate about the block CENTER: counter-rotate the half extent, then re-center.
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = new Vector3f(x + 0.5F, y + 0.5F, z + 0.5F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /**
     * F-068 size-class envelope. Sampled fragments spawn at the pixel-perfect identity
     * scale and DIVERGE with the drift: a ~10% boulder class swells toward 1.6–2.1×
     * (chunks holding together), a ~28% shard class thins toward 0.45–0.7× (the surface
     * crumbling), the rest settle near 0.85–1.1×. Splinters instead GROW out of their
     * source column (0 → 0.25–0.5×) as they eject — nothing ever pops in at full size.
     */
    private static float scaleEnvelope(int index, Sample sample, boolean splinter, float drive) {
        if (splinter) {
            float target = 0.25F + (float) CreditsSequence.hash01(index, 65) * 0.25F;
            return target * Mth.clamp(drive * 5.0F, 0.0F, 1.0F);
        }
        double clazz = CreditsSequence.hash01(index, 65);
        float target;
        if (sample.core()) {
            target = 1.15F + (float) CreditsSequence.hash01(index, 64) * 0.35F; // the heart stays whole
        } else if (clazz < 0.10D) {
            target = 1.6F + (float) CreditsSequence.hash01(index, 64) * 0.5F;
        } else if (clazz > 0.72D) {
            target = 0.45F + (float) CreditsSequence.hash01(index, 64) * 0.25F;
        } else {
            target = 0.85F + (float) CreditsSequence.hash01(index, 64) * 0.25F;
        }
        return Mth.lerp(drive, 1.0F, target);
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
