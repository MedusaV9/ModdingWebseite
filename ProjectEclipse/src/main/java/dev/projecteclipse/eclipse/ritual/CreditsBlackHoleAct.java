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
import net.minecraft.world.level.levelgen.Heightmap;
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
 * <p><b>Displays (F-068 devour polish)</b>: {@link #count} fragments (the F-102
 * {@link CreditsDisplayBudget} ladder: 180 VERIFY / 900 STANDARD / 1600 EPIC) of REAL
 * sampled map terrain ({@link #sampleTerrainPalette} reads the overworld's surface
 * strata around the hole column at {@link #prepare} time — the world itself is what
 * falls in) ride the accretion disc in {@value #CLUSTER_SIZE}-piece tear-off clusters:
 * each cluster launches as one coherent terrain chunk (shared shell slot, launch phase
 * and palette pocket, tiny per-member jitter) and spirals inward together. The disc is
 * layered over {@code PLANE_TILT.length} tilted ring planes; per-fragment brightness
 * rides a Doppler ladder (the disc's approaching limb burns brighter — refreshed in
 * strided waves from {@link #animate}; the stride widens with the tier so the NBT
 * refresh cost stays flat). Crossing the last ~28% of the fall the fragments
 * SPAGHETTIFY: the tumble slerps into a radial alignment while the scale column
 * stretches toward the hole and thins crosswise, then drains to the floor over the
 * horizon (swallowed, never popped). Every entity is RECYCLED on a per-cluster fall
 * cycle ({@value #FALL_TICKS_MIN}–{@value #FALL_TICKS_MIN}+{@value #FALL_TICKS_VAR}t,
 * wrap seam hidden by the shell-edge grow-in) — the infall stream never dries up while
 * the live count stays flat at {@link #count}. Budgeted spawn ({@link #spawnPerTick}/t),
 * pushes on the {@value #PUSH_STRIDE}t stride, hard-cap checked, {@link #TAG} stray-sweep
 * covered, discarded (staggered) behind the final black. {@link #swallowPulse} publishes
 * the deterministic "gulp" schedule (a cluster group crossing the horizon) that
 * {@code CreditsSequence} answers with a shockwave ring + brightness blink.</p>
 *
 * <p><b>F-072 V3 infall dramaturgy</b>: crossing {@value #HEAT_START} of the fall every
 * fragment IGNITES — the terrain state swaps to a magma-core heat state (hashed
 * shroomlight accents) at full-bright, tidal friction made visible right before the
 * swallow — and cools back to its real terrain block when the recycle wraps it out to
 * the rim. The cluster arc-trailing WIDENS across the spaghettification window
 * (+{@value #FILAMENT_TRAIL} rad/member), so a tear-off chunk visibly strings out into a
 * glowing spiral filament instead of falling as a lump. {@link #horizonFlash} publishes
 * a second, denser schedule of weak "letzte Blitze" between the big gulps that
 * {@code CreditsSequence} forwards as low-strength client Pulse flickers.</p>
 *
 * <p><b>F-102 "Himmel-Kontraktion" (sky-drain streams)</b>: from act tick
 * {@value #SKYDRAIN_FROM} a SECOND population of {@link #drainCount} displays (60
 * VERIFY / 260 STANDARD / 520 EPIC) spawns budgeted — {@value #DRAIN_STREAM_SIZE}-piece
 * debris STREAMS born high on a wide upper dome (58–96 anchor-blocks out, above the
 * disc) that curl inward and pour into the hole, recycled on their own cycles: the sky
 * itself visibly contracts into the eclipse across the devour's back half ("am Himmel
 * zieht sich alles zusammen"), thinning out with the act wind-down exactly when the
 * eclipse dims away ({@code CreditsSequence}'s F-102 eclipse-fade beat). Same tag,
 * same discard paths, same stateless pose law.</p>
 */
final class CreditsBlackHoleAct {
    static final String TAG = "eclipse_credits_blackhole";

    /**
     * Spiraling map-debris displays. F-068 raised the F-056 300–600 band to a recycled
     * 840; F-090/F-093 trimmed it to 700 for the effigy's sake; F-102 put it on the
     * {@link CreditsDisplayBudget} ladder (180/900/1600) — every entity re-falls on its
     * cluster's fall cycle, so the visual throughput is several thousand infalls across
     * the act while the LIVE count (the budget that matters) never exceeds this.
     */
    private int count = 1;
    private int spawnPerTick = 1;
    static final int PUSH_STRIDE = 10;
    /** F-102 sky-contraction streams: population + spawn start (act clock) + coherence. */
    private int drainCount;
    static final int SKYDRAIN_FROM = 620;
    static final int DRAIN_STREAM_SIZE = 8;
    /** Full consume duration: reveal → all swallowed (the act's master clock). */
    static final int SPIRAL_TICKS = 1300;
    /** Photon maw re-fire cadence (kneel-corona sustain law: re-sends dedup silently). */
    static final int MAW_CADENCE = 300;

    /** Fragments per tear-off cluster (one terrain chunk ripping loose as a group). */
    static final int CLUSTER_SIZE = 6;
    /** Per-cluster fall cycle band (ticks) — the recycling clock. */
    private static final int FALL_TICKS_MIN = 460;
    private static final int FALL_TICKS_VAR = 240;
    /** The act's exit: everything drains to the floor across the last {@value}t. */
    private static final int WIND_DOWN_TICKS = 140;

    /** Swallow-pulse ("gulp") schedule: spacing + hashed jitter (see {@link #swallowPulse}). */
    private static final int PULSE_PERIOD = 115;
    private static final int PULSE_JITTER = 34;

    /** V3 horizon "letzte Blitze": the denser, weaker flash schedule between big gulps. */
    private static final int FLASH_PERIOD = 47;
    private static final int FLASH_JITTER = 21;
    /** V3 heat glow: fall progress where a fragment ignites (magma-core state swap). */
    private static final float HEAT_START = 0.78F;
    /** V3 tidal filament: extra per-member arc trailing gained across the stretch window. */
    private static final float FILAMENT_TRAIL = 0.34F;

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
    /** Disc squash: the vertical (up-basis) share of each ring radius. */
    private static final float DISC_SQUASH = 0.55F;
    /** Tilt (radians, about the camera-right axis) of the three accretion ring planes. */
    private static final float[] PLANE_TILT = {-0.22F, 0.0F, 0.26F};
    /** Extra roll (radians, about the view normal) de-phasing the ring planes. */
    private static final float[] PLANE_ROLL = {0.0F, 0.55F, 1.15F};

    /** Spaghettification window: radial stretch ramps across the last {@value}% of the fall. */
    private static final float STRETCH_START = 0.72F;
    /** Peak radial elongation factor at the horizon. */
    private static final float STRETCH_MAX = 2.6F;

    /** Doppler brightness band (display brightness override, sky channel). */
    private static final int DOPPLER_SKY_MIN = 3;
    private static final int DOPPLER_SKY_MAX = 13;
    /** Brightness refresh: 1/{@value} of the field per {@link #animate} push wave. */
    private static final int DOPPLER_STRIDE = 4;

    /** Terrain sampling: spiral of surface columns out to this map radius. */
    private static final double TERRAIN_SAMPLE_RADIUS = 170.0D;
    private static final int TERRAIN_SAMPLES = 96;

    private static final float VIEW_RANGE = 4.0F;
    private static final float SCALE_FLOOR = 0.02F;

    /** Fallback palette when the terrain sampling finds nothing renderable. */
    private static final BlockState[] FALLBACK_PALETTE = {
            Blocks.GRASS_BLOCK.defaultBlockState(),
            Blocks.DIRT.defaultBlockState(),
            Blocks.STONE.defaultBlockState(),
            Blocks.SAND.defaultBlockState(),
            Blocks.OAK_LOG.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState()};

    /** V3 heat-glow states (the burn right before the swallow): magma core + rare accent. */
    private static final BlockState HEAT_PRIMARY = Blocks.MAGMA_BLOCK.defaultBlockState();
    private static final BlockState HEAT_ACCENT = Blocks.SHROOMLIGHT.defaultBlockState();

    private final List<Display.BlockDisplay> displays = new ArrayList<>();
    /** F-102 sky-drain stream displays (own pose family, same tag/discard paths). */
    private final List<Display.BlockDisplay> drainDisplays = new ArrayList<>();
    /** REAL sampled surface states, ordered center→rim (cluster pockets stay coherent). */
    private final List<BlockState> terrainPalette = new ArrayList<>(TERRAIN_SAMPLES * 2);
    /** Last pushed Doppler sky value per display (skip no-op NBT round trips). */
    private int[] dopplerCache = new int[0];
    /** V3: whether each fragment currently shows its heat state (swap on crossings only). */
    private boolean[] hotCache = new boolean[0];
    /** Doppler refresh stride (1/{@code dopplerStride} of the field per push wave). */
    private int dopplerStride = DOPPLER_STRIDE;
    private Vec3 holeCenter = Vec3.ZERO;
    private Vec3 vantage = Vec3.ZERO;
    private Vec3 fxAnchor = Vec3.ZERO;
    /** Camera-facing disc basis at the anchor (right / up / toward-camera normal). */
    private Vector3f right = new Vector3f(1.0F, 0.0F, 0.0F);
    private Vector3f up = new Vector3f(0.0F, 1.0F, 0.0F);
    private Vector3f normal = new Vector3f(0.0F, 0.0F, 1.0F);
    /** Precomputed tilted (right, up) bases of the {@link #PLANE_TILT} ring planes. */
    private final Vector3f[] planeRight = new Vector3f[PLANE_TILT.length];
    private final Vector3f[] planeUp = new Vector3f[PLANE_TILT.length];
    private float yaw;
    private float pitch;
    private int spawnCursor;
    /** F-102: budgeted spawn cursor of the sky-drain stream population. */
    private int drainCursor;
    /** Push-wave counter driving the strided Doppler refresh. */
    private int pushWave;
    private boolean prepared;

    /**
     * Computes the whole stage from the sanctum altar column (fallback: the overworld
     * spawn). Never fails — the finale must always have SOME center to devour. Also
     * samples the REAL map surface into {@link #terrainPalette} (F-068): what spirals
     * into the hole is the terrain the players actually lived on. F-102: resolves the
     * accretion/sky-drain counts off the {@link CreditsDisplayBudget} ladder.
     */
    void prepare(ServerLevel overworld, @javax.annotation.Nullable BlockPos altarPos,
            CreditsDisplayBudget.Snapshot budget) {
        this.count = Math.max(CLUSTER_SIZE, budget.holeCount());
        this.spawnPerTick = Math.max(1, budget.holeSpawnPerTick());
        this.drainCount = Math.max(0, budget.skyDrainCount());
        // Doppler refresh spreads wider on the big tiers — the per-push check budget
        // stays roughly flat (~200-225 cache checks/push across the ladder; only the
        // changed quantized values pay the actual NBT write).
        this.dopplerStride = Math.max(DOPPLER_STRIDE, this.count / 200);
        this.dopplerCache = new int[this.count];
        this.hotCache = new boolean[this.count];
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
        this.normal = new Vector3f((float) dir.x, (float) dir.y, (float) dir.z);
        this.right = new Vector3f(this.normal).cross(0.0F, 1.0F, 0.0F).normalize();
        this.up = new Vector3f(this.right).cross(this.normal).normalize();
        // Tilted ring-plane bases: roll the (right, up) pair about the view normal, then
        // tilt the rolled up-axis out of the disc plane about the rolled right-axis.
        for (int k = 0; k < PLANE_TILT.length; k++) {
            Vector3f r = new Vector3f(this.right).rotateAxis(PLANE_ROLL[k],
                    this.normal.x, this.normal.y, this.normal.z);
            Vector3f u = new Vector3f(this.up).rotateAxis(PLANE_ROLL[k],
                    this.normal.x, this.normal.y, this.normal.z);
            this.planeRight[k] = r;
            this.planeUp[k] = new Vector3f(u).mul(Mth.cos(PLANE_TILT[k]))
                    .add(new Vector3f(this.normal).mul(Mth.sin(PLANE_TILT[k])));
        }
        sampleTerrainPalette(overworld, center);
        java.util.Arrays.fill(this.dopplerCache, Integer.MIN_VALUE);
        java.util.Arrays.fill(this.hotCache, false);
        this.prepared = true;
        EclipseMod.LOGGER.info("CreditsBlackHoleAct: staged — hole {}, vantage {}, anchor {} (yaw {} pitch {}), "
                + "{} terrain sample(s)", this.holeCenter, this.vantage, this.fxAnchor, this.yaw,
                this.pitch, this.terrainPalette.size());
    }

    /**
     * Reads the REAL map surface into the accretion palette: a golden-angle spiral of
     * {@value #TERRAIN_SAMPLES} columns out to {@value #TERRAIN_SAMPLE_RADIUS} blocks
     * around the hole column, top surface block + a hashed strata pick below it —
     * ordered center→rim so cluster palette pockets stay spatially coherent. Fluids and
     * invisible states are skipped; an empty result falls back to the static palette
     * (the finale must never fall back to nothing).
     */
    private void sampleTerrainPalette(ServerLevel overworld, BlockPos center) {
        for (int k = 0; k < TERRAIN_SAMPLES; k++) {
            double r = TERRAIN_SAMPLE_RADIUS * Math.sqrt((k + 0.5D) / TERRAIN_SAMPLES);
            double theta = k * CreditsSequence.GOLDEN_ANGLE;
            int x = center.getX() + (int) Math.round(r * Math.cos(theta));
            int z = center.getZ() + (int) Math.round(r * Math.sin(theta));
            overworld.getChunk(x >> 4, z >> 4); // force-load (GhostShipBuilder pattern)
            int top = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
            BlockPos surface = new BlockPos(x, top - 1, z);
            BlockState state = overworld.getBlockState(surface);
            if (isSampleable(state)) {
                this.terrainPalette.add(state);
            }
            if (CreditsSequence.hash01(k, 90) < 0.5D) {
                BlockState below = overworld.getBlockState(surface.below(
                        1 + (int) (CreditsSequence.hash01(k, 89) * 3.0D)));
                if (isSampleable(below)) {
                    this.terrainPalette.add(below);
                }
            }
        }
        if (this.terrainPalette.isEmpty()) {
            EclipseMod.LOGGER.warn("CreditsBlackHoleAct: terrain sampling found nothing renderable "
                    + "— using the fallback palette");
            java.util.Collections.addAll(this.terrainPalette, FALLBACK_PALETTE);
        }
    }

    /** A state a block display can meaningfully render (no fluids, no invisibles). */
    private static boolean isSampleable(BlockState state) {
        return !state.isAir()
                && state.getFluidState().isEmpty()
                && state.getRenderShape() != net.minecraft.world.level.block.RenderShape.INVISIBLE;
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

    boolean spawnRemaining(int actTick) {
        return this.spawnCursor < this.count
                || (actTick >= SKYDRAIN_FROM && this.drainCursor < this.drainCount);
    }

    /**
     * Budgeted spawn wave; every entity parks at the shared anchor (tracking-safe).
     * The accretion field fills first; from {@value #SKYDRAIN_FROM} the same per-tick
     * budget arms the F-102 sky-drain streams (never both bursts in one tick over
     * budget — one shared allowance).
     */
    void spawnBatch(ServerLevel overworld, int actTick) {
        int budget = this.spawnPerTick;
        while (budget-- > 0 && this.spawnCursor < this.count) {
            if (CreditsSequence.actCapReached()) {
                this.spawnCursor = this.count;
                break;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(overworld);
            if (piece == null) {
                return;
            }
            int i = this.spawnCursor;
            piece.moveTo(this.fxAnchor.x, this.fxAnchor.y, this.fxAnchor.z, 0.0F, 0.0F);
            piece.setBlockState(fragmentState(i));
            piece.addTag(TAG);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            piece.setTransformation(pose(i, actTick));
            // Dim space-lit silhouettes — the Doppler wave re-lights the approaching limb.
            CreditsSequence.applyBrightnessOverride(piece, 6, 3);
            CreditsSequence.applyViewRange(piece, VIEW_RANGE);
            CreditsSequence.trackDisplay(piece);
            overworld.addFreshEntity(piece);
            this.displays.add(piece);
            this.spawnCursor++;
        }
        if (this.spawnCursor >= this.count && this.displays.size() == this.count
                && this.drainCursor == 0 && actTick < SKYDRAIN_FROM) {
            EclipseMod.LOGGER.info("CreditsBlackHoleAct: accretion field live — {} display(s) falling in "
                    + "({} tear-off cluster(s), recycled)", this.displays.size(),
                    this.count / CLUSTER_SIZE);
        }
        // F-102 sky-contraction streams (the leftover allowance of this tick's budget).
        while (budget-- > 0 && actTick >= SKYDRAIN_FROM && this.drainCursor < this.drainCount) {
            if (CreditsSequence.actCapReached()) {
                this.drainCursor = this.drainCount;
                break;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(overworld);
            if (piece == null) {
                return;
            }
            int j = this.drainCursor;
            piece.moveTo(this.fxAnchor.x, this.fxAnchor.y, this.fxAnchor.z, 0.0F, 0.0F);
            piece.setBlockState(fragmentState(this.count + j));
            piece.addTag(TAG);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            piece.setTransformation(drainPose(j, actTick));
            CreditsSequence.applyBrightnessOverride(piece, 5, 2);
            CreditsSequence.applyViewRange(piece, VIEW_RANGE);
            CreditsSequence.trackDisplay(piece);
            overworld.addFreshEntity(piece);
            this.drainDisplays.add(piece);
            this.drainCursor++;
        }
        if (this.drainCount > 0 && this.drainCursor >= this.drainCount
                && this.drainDisplays.size() == this.drainCount) {
            EclipseMod.LOGGER.info("CreditsBlackHoleAct: sky-drain streams live — {} display(s) in {} "
                    + "stream(s) contracting into the hole", this.drainDisplays.size(),
                    (this.drainCount + DRAIN_STREAM_SIZE - 1) / DRAIN_STREAM_SIZE);
        }
    }

    /**
     * Cluster-coherent terrain pick: each cluster owns a pocket of the center→rim-ordered
     * palette (neighbors in the list are spatial neighbors on the map), members pick
     * inside ±2 of the pocket anchor — a tear-off group reads as ONE terrain chunk
     * (grass + dirt + stone together), not confetti.
     */
    private BlockState fragmentState(int index) {
        int cluster = index / CLUSTER_SIZE;
        int size = this.terrainPalette.size();
        int anchor = (int) (CreditsSequence.hash01(cluster, 91) * size);
        int pick = Math.floorMod(anchor + (int) (CreditsSequence.hash01(index, 88) * 5.0D) - 2, size);
        return this.terrainPalette.get(pick);
    }

    /**
     * One lookahead interpolation window per {@value #PUSH_STRIDE}t, plus the strided
     * Doppler brightness wave (1/{@value #DOPPLER_STRIDE} of the field per push; values
     * are quantized and cached so unchanged fragments never pay the NBT round trip).
     *
     * <p>V3 heat glow rides the same loop: crossing {@value #HEAT_START} of the fall the
     * fragment's state swaps to {@link #heatState} at full-bright (tidal friction turned
     * visible), and the recycle wrap swaps the real terrain block back in with a fresh
     * Doppler value — both are crossing-edge-only NBT writes, never per-push.</p>
     */
    void animate(int actTick) {
        this.pushWave++;
        for (int i = 0; i < this.displays.size(); i++) {
            Display.BlockDisplay piece = this.displays.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(pose(i, actTick + PUSH_STRIDE));
            boolean hot = fallProgress(i, actTick) >= HEAT_START;
            if (hot != this.hotCache[i]) {
                this.hotCache[i] = hot;
                if (hot) {
                    piece.setBlockState(heatState(i));
                    CreditsSequence.applyBrightnessOverride(piece, 15, 15);
                    this.dopplerCache[i] = Integer.MIN_VALUE;
                } else {
                    // Recycle wrap: back to real terrain, immediately re-lit (a full-
                    // bright chunk at the cold shell rim would read wrong for 40t).
                    piece.setBlockState(fragmentState(i));
                    int sky = dopplerSky(i, actTick);
                    this.dopplerCache[i] = sky;
                    CreditsSequence.applyBrightnessOverride(piece, sky, Math.max(0, sky - 3));
                }
            }
            if (!hot && i % this.dopplerStride == this.pushWave % this.dopplerStride) {
                int sky = dopplerSky(i, actTick);
                if (sky != this.dopplerCache[i]) {
                    this.dopplerCache[i] = sky;
                    CreditsSequence.applyBrightnessOverride(piece, sky, Math.max(0, sky - 3));
                }
            }
        }
        // F-102 sky-drain streams: transform pushes only — no Doppler/heat NBT churn
        // (they read as dim silhouettes pouring out of the dark sky by design).
        for (int j = 0; j < this.drainDisplays.size(); j++) {
            Display.BlockDisplay piece = this.drainDisplays.get(j);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(drainPose(j, actTick + PUSH_STRIDE));
        }
    }

    /** V3 heat pick: magma core with a hashed shroomlight accent (deterministic). */
    private static BlockState heatState(int index) {
        return CreditsSequence.hash01(index, 104) < 0.25D ? HEAT_ACCENT : HEAT_PRIMARY;
    }

    /**
     * F-068 "Schluck-Momente": the deterministic gulp schedule — roughly one pulse per
     * {@value #PULSE_PERIOD}t (hashed jitter, strength ramping with act progress) while
     * cluster groups pour over the horizon. Returns the pulse strength 0..1 when a gulp
     * lands exactly at {@code actTick}, else -1; {@code CreditsSequence} answers with the
     * shockwave ring + brightness blink + devour thump (sends stay sequence-owned).
     */
    float swallowPulse(int actTick) {
        int slot = actTick / PULSE_PERIOD;
        int due = slot * PULSE_PERIOD + (int) (CreditsSequence.hash01(slot, 87) * PULSE_JITTER);
        if (actTick != due || actTick >= SPIRAL_TICKS - WIND_DOWN_TICKS) {
            return -1.0F;
        }
        float progress = Mth.clamp(actTick / (float) SPIRAL_TICKS, 0.0F, 1.0F);
        return 0.35F + 0.5F * progress;
    }

    /**
     * F-072 V3 "letzte Blitze": the denser, weaker flash schedule between the big
     * {@link #swallowPulse} gulps — a fragment's final flare crossing the horizon.
     * Returns the flash strength 0..1 when one lands exactly at {@code actTick}, else
     * -1. {@code CreditsSequence} forwards it as a low-strength client Pulse (photon-
     * ring flicker only — the shockwave, blink and thump stay reserved for true gulps).
     */
    float horizonFlash(int actTick) {
        int slot = actTick / FLASH_PERIOD;
        int due = slot * FLASH_PERIOD + (int) (CreditsSequence.hash01(slot, 105) * FLASH_JITTER);
        if (actTick != due || actTick >= SPIRAL_TICKS - WIND_DOWN_TICKS) {
            return -1.0F;
        }
        return 0.10F + 0.16F * (float) CreditsSequence.hash01(slot, 106);
    }

    void discard() {
        for (Display.BlockDisplay piece : this.displays) {
            CreditsSequence.untrackDisplay(piece);
            piece.discard();
        }
        this.displays.clear();
        for (Display.BlockDisplay piece : this.drainDisplays) {
            CreditsSequence.untrackDisplay(piece);
            piece.discard();
        }
        this.drainDisplays.clear();
    }

    /**
     * F-102 staggered teardown (accretion + sky-drain streams): ownership moves to
     * {@code CreditsSequence}'s removal queue — see {@code CreditsShatterAct#discardInto}.
     */
    void discardInto(java.util.function.Consumer<Display.BlockDisplay> sink) {
        for (Display.BlockDisplay piece : this.displays) {
            sink.accept(piece);
        }
        this.displays.clear();
        for (Display.BlockDisplay piece : this.drainDisplays) {
            sink.accept(piece);
        }
        this.drainDisplays.clear();
    }

    // ------------------------------------------------------------------ pose

    /** Per-cluster fall-cycle length (the recycling clock). */
    private static int fallCycle(int cluster) {
        return FALL_TICKS_MIN + (int) (CreditsSequence.hash01(cluster, 92) * FALL_TICKS_VAR);
    }

    /** Wrapping fall progress 0..1 of fragment {@code index} at {@code actTick}. */
    private static float fallProgress(int index, int actTick) {
        int cluster = index / CLUSTER_SIZE;
        int cycle = fallCycle(cluster);
        int phase = (int) (CreditsSequence.hash01(cluster, 93) * cycle)
                + (int) (CreditsSequence.hash01(index, 94) * 14.0D); // small member stagger
        return Math.floorMod(actTick + phase, cycle) / (float) cycle;
    }

    /**
     * Disc angle (radians in the ring plane) of fragment {@code index} at fall progress
     * {@code q}. V3: the per-member arc trailing WIDENS across the spaghettification
     * window ({@code 0.09 → 0.09 + }{@value #FILAMENT_TRAIL} rad) — the tidal field
     * pulls a tear-off cluster apart into a glowing spiral filament before the swallow.
     */
    private static float discTheta(int index, int actTick, float q) {
        int cluster = index / CLUSTER_SIZE;
        float turns = 2.0F + (float) CreditsSequence.hash01(cluster, 95) * 2.5F;
        float filament = Mth.clamp((q - STRETCH_START) / (1.0F - STRETCH_START), 0.0F, 1.0F);
        return cluster * CreditsSequence.GOLDEN_ANGLE
                + (index % CLUSTER_SIZE) * (0.09F + FILAMENT_TRAIL * filament)
                + turns * Mth.TWO_PI * q * q
                + actTick * 0.0016F; // the whole disc slowly turns even between falls
    }

    /**
     * Doppler brightness (display sky channel) of fragment {@code index}: the disc limb
     * swinging TOWARD the camera-right axis burns bright, the receding limb drains dark
     * — quantized to the {@value #DOPPLER_SKY_MIN}..{@value #DOPPLER_SKY_MAX} band.
     */
    private int dopplerSky(int index, int actTick) {
        float q = fallProgress(index, actTick);
        float theta = discTheta(index, actTick, q);
        float approach = 0.5F + 0.5F * Mth.cos(theta);
        return DOPPLER_SKY_MIN + Math.round((DOPPLER_SKY_MAX - DOPPLER_SKY_MIN) * approach);
    }

    /**
     * Absolute pose of accretion fragment {@code index} at {@code actTick}: a recycled,
     * cluster-grouped inward spiral in one of the tilted ring planes, spaghettifying
     * over the horizon. Pure function of (index, tick) — the stateless-push law.
     */
    private Transformation pose(int index, int actTick) {
        int cluster = index / CLUSTER_SIZE;
        int member = index % CLUSTER_SIZE;
        float q = fallProgress(index, actTick);

        // Cluster shell slot + small per-member radial jitter (the group stays a chunk).
        float r0 = SHELL_RADIUS_MIN + (SHELL_RADIUS_MAX - SHELL_RADIUS_MIN)
                * (float) Math.sqrt(CreditsSequence.hash01(cluster, 96))
                + ((float) CreditsSequence.hash01(index, 97) * 2.0F - 1.0F) * 3.0F;
        // Accelerating infall: slow far out, rushing over the horizon.
        float radius = Math.max(SWALLOW_RADIUS, r0 * (float) Math.pow(1.0F - q, 1.45D));
        float theta = discTheta(index, actTick, q);
        int plane = cluster % PLANE_TILT.length;
        Vector3f pr = this.planeRight[plane];
        Vector3f pu = this.planeUp[plane];
        // Small out-of-plane wobble so the disc has body, damped as it falls in.
        float wobble = 5.0F * (1.0F - q) * Mth.sin(index * 2.1F + actTick * 0.01F)
                + ((float) CreditsSequence.hash01(index, 98) * 2.0F - 1.0F) * 1.5F;
        Vector3f offset = new Vector3f(pr).mul(radius * Mth.cos(theta))
                .add(new Vector3f(pu).mul(radius * Mth.sin(theta) * DISC_SQUASH))
                .add(new Vector3f(this.normal).mul(wobble));

        // Tumble (golden-phased) → radial alignment as the spaghettification takes over.
        float tumble = index * CreditsSequence.GOLDEN_ANGLE
                + q * (3.0F + (float) CreditsSequence.hash01(index, 99) * 5.0F);
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(index, 100) * 2.0D - 1.0D),
                (float) (0.3D + CreditsSequence.hash01(index, 101)),
                (float) (CreditsSequence.hash01(index, 102) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(tumble, axis);
        float stretchRamp = Mth.clamp((q - STRETCH_START) / (1.0F - STRETCH_START), 0.0F, 1.0F);
        if (stretchRamp > 0.0F) {
            // Unit inward direction in the ring plane (toward the disc center).
            Vector3f inward = new Vector3f(pr).mul(-Mth.cos(theta))
                    .add(new Vector3f(pu).mul(-Mth.sin(theta) * DISC_SQUASH)).normalize();
            Quaternionf aligned = new Quaternionf().rotationTo(
                    new Vector3f(1.0F, 0.0F, 0.0F), inward);
            rotation = rotation.slerp(aligned, Math.min(1.0F, stretchRamp * 1.4F));
        }

        // Scale: cluster cores are big boulders, trailing members smaller shards. The
        // shell-edge grow-in hides the recycle wrap; the swallow drain + act wind-down
        // take everything to the floor (never popped, never exactly 0).
        float base = member == 0
                ? 2.2F + (float) CreditsSequence.hash01(cluster, 103) * 1.8F
                : 1.0F + (float) CreditsSequence.hash01(index, 103) * 1.8F;
        float growIn = Mth.clamp(q / 0.06F, 0.0F, 1.0F);
        float drain = 1.0F - Mth.clamp((q - 0.88F) / 0.12F, 0.0F, 1.0F);
        float windDown = 1.0F - Mth.clamp(
                (actTick - (SPIRAL_TICKS - WIND_DOWN_TICKS)) / (float) WIND_DOWN_TICKS, 0.0F, 1.0F);
        float body = Math.max(SCALE_FLOOR, base * growIn * drain * windDown);
        // Spaghettification: elongate the local X (radial) column, thin the cross-section
        // (inverse-sqrt keeps the visual mass roughly constant while it stretches).
        float stretch = 1.0F + (STRETCH_MAX - 1.0F) * stretchRamp * stretchRamp;
        float thin = (float) (1.0D / Math.sqrt(stretch));
        Vector3f scale = new Vector3f(body * stretch, body * thin, body * thin);
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = offset.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    // ------------------------------------------------------------------ F-102 sky drain

    /**
     * Wrapping contraction progress 0..1 of sky-drain fragment {@code j}: streams share
     * a per-stream cycle (240–390t) and phase, members trail 11t apart — pearls on a
     * string pouring into the hole; the recycle keeps the sky contracting for the whole
     * back half of the devour.
     */
    private static float drainProgress(int j, int actTick) {
        int stream = j / DRAIN_STREAM_SIZE;
        int cycle = 240 + (int) (CreditsSequence.hash01(stream, 110) * 150.0D);
        int phase = (int) (CreditsSequence.hash01(stream, 111) * cycle)
                + (j % DRAIN_STREAM_SIZE) * 11;
        return Math.floorMod(actTick - SKYDRAIN_FROM + phase, cycle) / (float) cycle;
    }

    /**
     * Absolute pose of sky-drain fragment {@code j} at {@code actTick} (pure function —
     * the stateless-push law): born high on a wide upper dome (58–96 anchor-blocks out,
     * upper screen half through the camera basis), it accelerates inward along a curling
     * path (±0.5–1.1 rad swirl about the view normal) and pours into the hole center;
     * the last 30% stretches the fragment along its inward direction (the tidal read at
     * stream scale). Scale rides grow-in / swallow-drain / act-wind-down envelopes — a
     * stream never pops in or out, and the whole population is gone with the wind-down
     * (exactly when the eclipse dims away).
     */
    private Transformation drainPose(int j, int actTick) {
        int stream = j / DRAIN_STREAM_SIZE;
        float q = drainProgress(j, actTick);

        float r0 = 58.0F + (float) CreditsSequence.hash01(stream, 112) * 38.0F;
        // Upper screen half: azimuth 0.25..2.9 rad keeps sin(az) > 0 (above the disc).
        float az0 = 0.25F + (float) CreditsSequence.hash01(stream, 113) * 2.65F;
        float swirl = (CreditsSequence.hash01(stream, 114) < 0.5D ? -1.0F : 1.0F)
                * (0.5F + (float) CreditsSequence.hash01(stream, 115) * 0.6F);
        float az = az0 + swirl * q + ((float) CreditsSequence.hash01(j, 116) - 0.5F) * 0.08F;
        // Accelerating contraction: slow leave from the dome, rushing over the horizon.
        float radius = Math.max(SWALLOW_RADIUS, r0 * (float) Math.pow(1.0F - q, 1.6D));
        float wobble = 4.0F * (1.0F - q) * Mth.sin(j * 1.7F + actTick * 0.012F);
        Vector3f offset = new Vector3f(this.right).mul(radius * Mth.cos(az))
                .add(new Vector3f(this.up).mul(radius * Mth.sin(az) * 0.9F))
                .add(new Vector3f(this.normal).mul(wobble));

        // Tumble → inward alignment across the final stretch window.
        float tumble = j * CreditsSequence.GOLDEN_ANGLE
                + q * (2.0F + (float) CreditsSequence.hash01(j, 117) * 4.0F);
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(j, 118) * 2.0D - 1.0D),
                (float) (0.3D + CreditsSequence.hash01(j, 119)),
                (float) (CreditsSequence.hash01(j, 120) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(tumble, axis);
        float stretchRamp = Mth.clamp((q - 0.7F) / 0.3F, 0.0F, 1.0F);
        if (stretchRamp > 0.0F) {
            Vector3f inward = new Vector3f(this.right).mul(-Mth.cos(az))
                    .add(new Vector3f(this.up).mul(-Mth.sin(az) * 0.9F)).normalize();
            Quaternionf aligned = new Quaternionf().rotationTo(
                    new Vector3f(1.0F, 0.0F, 0.0F), inward);
            rotation = rotation.slerp(aligned, Math.min(1.0F, stretchRamp * 1.4F));
        }

        float base = 0.9F + (float) CreditsSequence.hash01(j, 121) * 1.1F;
        float growIn = Mth.clamp(q / 0.06F, 0.0F, 1.0F);
        float drain = 1.0F - Mth.clamp((q - 0.9F) / 0.1F, 0.0F, 1.0F);
        float windDown = 1.0F - Mth.clamp(
                (actTick - (SPIRAL_TICKS - WIND_DOWN_TICKS)) / (float) WIND_DOWN_TICKS, 0.0F, 1.0F);
        // Arm-in: unlike the accretion field (spawned behind black), the streams spawn
        // MID-SHOT with hashed cycle phases — without this whole-population ramp a
        // member at q=0.5 would pop in at full scale in the middle of the sky.
        float armIn = Mth.clamp((actTick - SKYDRAIN_FROM) / 50.0F, 0.0F, 1.0F);
        float body = Math.max(SCALE_FLOOR, base * growIn * drain * windDown * armIn);
        float stretch = 1.0F + 1.2F * stretchRamp * stretchRamp;
        float thin = (float) (1.0D / Math.sqrt(stretch));
        Vector3f scale = new Vector3f(body * stretch, body * thin, body * thin);
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = offset.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }
}
