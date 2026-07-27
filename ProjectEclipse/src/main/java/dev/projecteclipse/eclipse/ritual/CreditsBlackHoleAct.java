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
 * <p><b>Displays (F-068 devour polish)</b>: {@value #COUNT} fragments of REAL sampled
 * map terrain ({@link #sampleTerrainPalette} reads the overworld's surface strata around
 * the hole column at {@link #prepare} time — the world itself is what falls in) ride the
 * accretion disc in {@value #CLUSTER_SIZE}-piece tear-off clusters: each cluster launches
 * as one coherent terrain chunk (shared shell slot, launch phase and palette pocket, tiny
 * per-member jitter) and spirals inward together. The disc is layered over
 * {@code PLANE_TILT.length} tilted ring planes; per-fragment brightness rides a Doppler
 * ladder (the disc's approaching limb burns brighter — refreshed in strided waves from
 * {@link #animate}). Crossing the last ~28% of the fall the fragments SPAGHETTIFY: the
 * tumble slerps into a radial alignment while the scale column stretches toward the hole
 * and thins crosswise, then drains to the floor over the horizon (swallowed, never
 * popped). Every entity is RECYCLED on a per-cluster fall cycle
 * ({@value #FALL_TICKS_MIN}–{@value #FALL_TICKS_MIN}+{@value #FALL_TICKS_VAR}t, wrap seam
 * hidden by the shell-edge grow-in) — the infall stream never dries up while the live
 * count stays flat at {@value #COUNT}. Budgeted spawn ({@value #SPAWN_PER_TICK}/t),
 * pushes on the {@value #PUSH_STRIDE}t stride, hard-cap checked, {@link #TAG} stray-sweep
 * covered, discarded behind the final black. {@link #swallowPulse} publishes the
 * deterministic "gulp" schedule (a cluster group crossing the horizon) that
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
 */
final class CreditsBlackHoleAct {
    static final String TAG = "eclipse_credits_blackhole";

    /**
     * Spiraling map-debris displays. F-068 raised the F-056 300–600 band to a recycled
     * 840: every entity re-falls on its cluster's fall cycle, so the visual
     * throughput is several thousand infalls across the act while the LIVE count (the
     * budget that matters) never exceeds this. F-090/F-093 trimmed it to {@value} —
     * the {@code CreditsMapRipAct} effigy (≈ 2190 displays) now carries the map read,
     * and the combined finale peak (≈ 2890) must stay under the audited &lt;3000
     * simultaneous target.
     */
    static final int COUNT = 700;
    static final int SPAWN_PER_TICK = 48;
    static final int PUSH_STRIDE = 10;
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

    private final List<Display.BlockDisplay> displays = new ArrayList<>(COUNT);
    /** REAL sampled surface states, ordered center→rim (cluster pockets stay coherent). */
    private final List<BlockState> terrainPalette = new ArrayList<>(TERRAIN_SAMPLES * 2);
    /** Last pushed Doppler sky value per display (skip no-op NBT round trips). */
    private final int[] dopplerCache = new int[COUNT];
    /** V3: whether each fragment currently shows its heat state (swap on crossings only). */
    private final boolean[] hotCache = new boolean[COUNT];
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
    /** Push-wave counter driving the strided Doppler refresh. */
    private int pushWave;
    private boolean prepared;

    /**
     * Computes the whole stage from the sanctum altar column (fallback: the overworld
     * spawn). Never fails — the finale must always have SOME center to devour. Also
     * samples the REAL map surface into {@link #terrainPalette} (F-068): what spirals
     * into the hole is the terrain the players actually lived on.
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
        if (this.spawnCursor >= COUNT) {
            EclipseMod.LOGGER.info("CreditsBlackHoleAct: accretion field live — {} display(s) falling in "
                    + "({} tear-off cluster(s), recycled)", this.displays.size(), COUNT / CLUSTER_SIZE);
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
            if (!hot && i % DOPPLER_STRIDE == this.pushWave % DOPPLER_STRIDE) {
                int sky = dopplerSky(i, actTick);
                if (sky != this.dopplerCache[i]) {
                    this.dopplerCache[i] = sky;
                    CreditsSequence.applyBrightnessOverride(piece, sky, Math.max(0, sky - 3));
                }
            }
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
}
