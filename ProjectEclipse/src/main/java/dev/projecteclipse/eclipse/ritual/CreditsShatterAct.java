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
 * (r 16×14, ~700 columns; the altar/dais columns fall inside it). F-102
 * "Credits-Tausende": the counts ride the {@link CreditsDisplayBudget} ladder — the
 * surface pick plus up to FOUR hashed deeper strata layers per column (the island's
 * real guts, probability derived from the tier's sample cap) fill toward
 * {@link #sampleCap}: ~220 fragments on VERIFY, ~1.9k on STANDARD, ~3.2k on EPIC
 * ("die Insel zerspringt in tausende Teile"). On VERIFY the non-core columns are
 * hash-subsampled instead (the altar core always keeps its heart for the
 * {@value #CORE_BREAK_TICK} flash beat). The world is NEVER modified (Kulisse law):
 * each sample spawns one {@code BLOCK_DISPLAY} exactly over its source block (identity
 * transform — the overlay is pixel-perfect until the first drift push).</p>
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
 * source columns and ejecting fast and far ({@code min(splinterCap, samples/2)} on the
 * F-102 ladder). The ALTAR CORE (the |dx|,|dz| ≤ 2 columns at dais height) launches
 * LAST at {@value #CORE_BREAK_TICK}t — {@code CreditsSequence} fires the light flash on
 * that exact beat and the Photon veil bakes the matching core flash.</p>
 *
 * <p>Pushes ride {@value #PUSH_STRIDE}t interpolation windows and are PHASE-SLICED
 * (F-102): {@link #animate} runs every tick and pushes 1/{@value #PUSH_STRIDE} of the
 * field, so the EPIC worst case (~4.6k live fragments incl. splinters) costs ≈ 460
 * transform writes per tick steady — never a whole-field burst.
 * Spawns are budgeted per tick by {@link #spawnPerTick}. Discard is guaranteed:
 * {@link CreditsSequence} STAGGERS the act-end discard through its removal queue
 * (never a thousands-strong single-tick despawn), discards immediately on skip /
 * {@code /dev end_event} / run teardown, and every display carries {@link #TAG} for
 * the crash-stray join sweep.</p>
 */
final class CreditsShatterAct {
    /** Crash-stray sweep tag ({@code CreditsSequence.onEntityJoin}). */
    static final String TAG = "eclipse_credits_shatter";
    /** Ellipse column estimate (π·16·14) the tier layer probabilities derive from. */
    private static final double ESTIMATED_COLUMNS = 700.0D;
    /** Deepest extra strata layer sampled below a column's surface block (F-102). */
    private static final int MAX_EXTRA_LAYERS = 4;
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
    /** Splinter-shower size, fixed at prepare time (tier-capped, ~50% of the samples). */
    private int splinterCount;
    // F-102 budget-ladder rungs, resolved once in prepare (CreditsDisplayBudget).
    private int sampleCap = 1;
    private int splinterCap;
    private int spawnPerTick = 1;

    /**
     * Reads the island's surface (plus the tiered strata layers) into the sample list.
     * Returns {@code false} (act invalid, {@link CreditsSequence} skips the whole
     * shatter window) when the sanctum was never built.
     */
    boolean prepare(ServerLevel overworld, @javax.annotation.Nullable BlockPos altarPos,
            CreditsDisplayBudget.Snapshot budget) {
        if (altarPos == null) {
            return false;
        }
        this.sampleCap = Math.max(1, budget.shatterSampleCap());
        this.splinterCap = budget.shatterSplinterCap();
        this.spawnPerTick = Math.max(1, budget.shatterSpawnPerTick());
        this.altar = altarPos;
        this.islandTop = FloatingSanctumBuilder.islandTopY(altarPos);
        // F-102 tier density: how many EXTRA strata layers per column the cap asks for
        // (0 on VERIFY — there the surface columns are hash-subsampled instead).
        double density = this.sampleCap / ESTIMATED_COLUMNS - 1.0D;
        double surfaceKeep = Math.min(1.0D, this.sampleCap / ESTIMATED_COLUMNS);
        int rx = FloatingSanctumBuilder.SURFACE_RADIUS_X;
        int rz = FloatingSanctumBuilder.SURFACE_RADIUS_Z;
        for (int dx = -rx; dx <= rx && this.samples.size() < this.sampleCap; dx++) {
            for (int dz = -rz; dz <= rz && this.samples.size() < this.sampleCap; dz++) {
                double ellipse = dx * dx / (double) (rx * rx) + dz * dz / (double) (rz * rz);
                if (ellipse > 1.0D) {
                    continue;
                }
                int x = altarPos.getX() + dx;
                int z = altarPos.getZ() + dz;
                overworld.getChunk(x >> 4, z >> 4); // force-load (GhostShipBuilder pattern)
                // Top-down scan catches the altar (top+4), dais steps and pillar stumps.
                int surfaceY = Integer.MIN_VALUE;
                boolean core = false;
                Sample surface = null;
                for (int y = this.islandTop + 6; y >= this.islandTop - 2; y--) {
                    BlockPos pos = new BlockPos(x, y, z);
                    BlockState state = overworld.getBlockState(pos);
                    if (!state.isAir() && state.getRenderShape() != net.minecraft.world.level.block.RenderShape.INVISIBLE) {
                        // F-068: the altar/dais core breaks LAST (the CORE_BREAK_TICK flash).
                        core = Math.abs(dx) <= 2 && Math.abs(dz) <= 2
                                && y >= this.islandTop + 1;
                        surface = new Sample(pos, state, core);
                        surfaceY = y;
                        break;
                    }
                }
                if (surface == null) {
                    continue;
                }
                // VERIFY subsample: non-core columns thin out toward the tier cap — the
                // core always keeps its heart (the CORE_BREAK_TICK flash needs a body).
                if (!core && surfaceKeep < 1.0D
                        && CreditsSequence.hash01(dx * 61 + dz, 62) >= surfaceKeep) {
                    continue;
                }
                this.samples.add(surface);
                // F-102 strata layers: the island's real guts fill toward the tier cap
                // (layer d keeps with probability clamp(density − (d−1), 0..1)).
                for (int d = 1; d <= MAX_EXTRA_LAYERS
                        && this.samples.size() < this.sampleCap; d++) {
                    double keep = Math.min(1.0D, density - (d - 1));
                    if (keep <= 0.0D
                            || CreditsSequence.hash01(dx * 61 + dz, 56 + d) >= keep) {
                        continue;
                    }
                    BlockPos below = new BlockPos(x, surfaceY - d, z);
                    BlockState state = overworld.getBlockState(below);
                    if (!state.isAir() && state.getRenderShape()
                            != net.minecraft.world.level.block.RenderShape.INVISIBLE) {
                        this.samples.add(new Sample(below, state, false));
                    }
                }
            }
        }
        this.splinterCount = Math.min(this.splinterCap, this.samples.size() / 2);
        EclipseMod.LOGGER.info("CreditsShatterAct: sampled {} island fragment(s) around {} "
                + "(+{} splinter(s) planned, tier {})", this.samples.size(),
                altarPos.toShortString(), this.splinterCount, budget.tier());
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

    /** Budgeted spawn wave (≤ {@link #spawnPerTick}/t on the tier ladder, hard-cap guarded). */
    void spawnBatch(ServerLevel overworld, int actTick) {
        int budget = this.spawnPerTick;
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

    /**
     * One lookahead interpolation window per fragment (FloatingDecor transport
     * pattern). F-102: called EVERY act tick and pushes only the {@code i % PUSH_STRIDE
     * == actTick % PUSH_STRIDE} phase slice — each fragment still gets its window every
     * {@value #PUSH_STRIDE}t, but the NBT batch is 1/{@value #PUSH_STRIDE} of the field
     * per tick (EPIC ≈ 460/t steady instead of a 4.6k spike every 10t; the client-side
     * path is identical, the segments are merely phase-offset per fragment).
     */
    void animate(int actTick) {
        int phase = Math.floorMod(actTick, PUSH_STRIDE);
        for (int i = phase; i < this.fragments.size(); i += PUSH_STRIDE) {
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

    /**
     * F-102 staggered teardown: hands every fragment to {@code CreditsSequence}'s
     * removal queue (drained at a fixed per-tick rate behind the act-end black) instead
     * of a thousands-strong single-tick discard. The act forgets its displays here —
     * the queue owns them (untrack happens at their actual discard tick).
     */
    void discardInto(java.util.function.Consumer<Display.BlockDisplay> sink) {
        for (Display.BlockDisplay fragment : this.fragments) {
            sink.accept(fragment);
        }
        this.fragments.clear();
    }
}
