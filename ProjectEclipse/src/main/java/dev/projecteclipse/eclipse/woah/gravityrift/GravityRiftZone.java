package dev.projecteclipse.eclipse.woah.gravityrift;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/**
 * WOAH-02 pure geometry (plan §5): every number the builder, the service, the orbital
 * choreographer and the dev commands share lives HERE — one law, no drift between the
 * carve and the animation.
 *
 * <p><b>Anchor deviation from the plan text</b> (centrally decided, landmark collisions):
 * the frozen landmark row is {@code eclipse:gravity_rift, -239, 167, 40, 4} — the
 * BAMBOO-JUNGLE ring (anchor r ≈ 291.6; max extent 291.6 + 40 = 331.6 &lt; 336 = the
 * inner edge of any future stage-4→5 rim-rewrite band, so no sweep ever touches the
 * crater even on saves without the landmark protection). All island palettes are
 * jungle-themed (moss / jungle wood / bamboo accents — the Pandora vibe).</p>
 *
 * <p><b>Collision-free choreography</b> (plan §5.2 hybrid law): everything that MOVES is
 * display scenery, everything you STAND on is real blocks. Orbital bands and the static
 * step spiral are interleaved so displays never sweep through a deck:</p>
 * <pre>
 *   shell 0 "Kies"      r  6–14   y +3..+12    (steps in that band sit at r ≥ 18)
 *   shell 1 "Schollen"  r 12–20   y +12..+28   (steps +17/+23 sit at r ≥ 24)
 *   shell 2 "Inseln"    r 11–16.5 y +28..+38   (steps +30..+44 sit at r ≥ 17;
 *                                               loot floe r 8 at +46 clears the shell's
 *                                               lifted top ≈ +44)
 * </pre>
 *
 * <p>All heights are relative to the crater floor ({@code floorY} = deterministic
 * surface Y at the anchor − {@value #MAX_DEPTH}).</p>
 */
public final class GravityRiftZone {
    /** Landmark id in {@code DiscMapDefaults} AND pending-registry structure/site id. */
    public static final String STRUCTURE_ID = "eclipse:gravity_rift";
    /** Stage gate — mirrors the frozen landmark row (stage 4, bamboo-jungle ring). */
    public static final int STAGE = 4;

    // Landmark constants mirrored (single source for the client classes, plan §2.2).
    public static final int CENTER_X = -239;
    public static final int CENTER_Z = 167;

    /** Crater bowl radius. */
    public static final int CRATER_RADIUS = 28;
    /** Center depth of the bowl below the (plateau-prepared) ground surface. */
    public static final int MAX_DEPTH = 13;
    /** Outer radius of the broken rim-rubble ring. */
    public static final double RIM_OUTER_RADIUS = 31.0D;
    /** Terrace ring radii (the strata read as three cut steps, not a smooth parabola). */
    public static final double[] TERRACE_RADII = {9.0D, 17.0D, 24.0D};

    /** Low-G cylinder radius around the anchor. */
    public static final int ZONE_RADIUS = 34;
    /** Zone extends from floorY − this … */
    public static final int ZONE_BELOW = 2;
    /** … to floorY + this (loot floe +46 stays well inside). */
    public static final int ZONE_ABOVE = 56;

    /** Pulse beat raster (45 s). Stateless: {@code gameTime % PERIOD == phaseOffset}. */
    public static final int PULSE_PERIOD_TICKS = 900;
    /** The pulse-ring asset ramps 30 t before the launch beat (plan §7.1 telegraph). */
    public static final int PULSE_TELEGRAPH_TICKS = 30;

    /** Inversion: fall 80 t, chaotic hold to 200 t, glide back to 300 t (plan §3.3). */
    public static final int INVERT_ACTIVE_TICKS = 200;
    public static final int INVERT_TOTAL_TICKS = 300;
    public static final int INVERT_COOLDOWN_TICKS = 2400;

    /** Heart center height above the crater floor (pedestal top + hover). */
    public static final double HEART_HEIGHT = 3.2D;

    /** Fixed display mount height above the crater floor (open air, one owner chunk). */
    public static final int MOUNT_ABOVE_FLOOR = 30;

    private GravityRiftZone() {}

    // ------------------------------------------------------------------ anchor resolution

    /** Frozen landmark center (x, z) — reads the {@code DiscMapData} row, else constants. */
    public static BlockPos landmarkXZ() {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.OVERWORLD)) {
            if (STRUCTURE_ID.equals(landmark.id())) {
                return new BlockPos(landmark.x(), 0, landmark.z());
            }
        }
        return new BlockPos(CENTER_X, 0, CENTER_Z);
    }

    /**
     * Site center at the deterministic (vegetation-blind) surface Y — the same source
     * {@code SitePrep.preparePlateau} anchors on ({@code ChronoStasisSite.surfaceCenter}
     * recipe).
     */
    public static BlockPos surfaceCenter(ServerLevel level) {
        BlockPos xz = landmarkXZ();
        int y = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, xz.getX(), xz.getZ());
        if (y <= level.getMinBuildHeight()) {
            y = DiscMapData.get().surfaceOverrideAt(xz.getX(), xz.getZ());
            if (y <= level.getMinBuildHeight()) {
                y = (int) DiscProfile.OVERWORLD.surfaceBaseY();
            }
        }
        return new BlockPos(xz.getX(), y, xz.getZ());
    }

    /** Pulse phase offset for an anchor — deterministic, restart-safe (plan §3.1). */
    public static int pulsePhaseOffset(BlockPos anchor) {
        return (int) Math.floor(hash01(anchor.getX(), 7, anchor.getZ()) * PULSE_PERIOD_TICKS);
    }

    // ------------------------------------------------------------------ crater profile

    /** Parabolic carve depth below ground at offset (dx, dz); 0 outside the bowl. */
    public static int depthAt(int dx, int dz) {
        int rr2 = dx * dx + dz * dz;
        if (rr2 > CRATER_RADIUS * CRATER_RADIUS) {
            return 0;
        }
        double base = MAX_DEPTH * (1.0D - rr2 / (double) (CRATER_RADIUS * CRATER_RADIUS));
        return (int) Math.round(base);
    }

    /** {@link #depthAt} + a deterministic ±2 hash "bite" and the three terrace flats. */
    public static int roughDepth(int x, int z, int dx, int dz) {
        int depth = depthAt(dx, dz);
        if (depth <= 0) {
            return depth;
        }
        double rr = Math.sqrt(dx * dx + dz * dz);
        // Terrace flats: snap the parabola to a step just inside each terrace radius.
        for (double terraceR : TERRACE_RADII) {
            if (rr >= terraceR - 1.6D && rr <= terraceR + 0.4D) {
                depth = depthAt((int) Math.round(terraceR - 1.6D), 0);
                break;
            }
        }
        double bite = hash01(x, 101, z);
        if (depth > 1 && depth < MAX_DEPTH && bite < 0.22D) {
            depth++;
        } else if (depth > 2 && bite > 0.90D) {
            depth--;
        }
        return Math.min(depth, MAX_DEPTH);
    }

    /**
     * The kept-clear rim access sector faces the disc center (the walkable way in —
     * "Süd-Walk-Regel" of {@code SanctumCrater}, aimed at our anchor's inward bearing):
     * from (−239, 167) toward (0, 0) is the unit direction (0.820, −0.573), i.e. an
     * azimuth of ≈ 325°. Half-width ≈ 25°.
     */
    public static boolean inWalkSector(int dx, int dz) {
        double rr = Math.sqrt(dx * dx + dz * dz);
        if (rr < 1.0E-3D) {
            return true;
        }
        double dot = (dx * 0.820D + dz * -0.573D) / rr;
        return dot > 0.906D; // cos(25°)
    }

    // ------------------------------------------------------------------ zone tests

    /** Whether (x, y, z) is inside the low-G cylinder for the given crater-floor anchor. */
    public static boolean inZone(BlockPos anchor, double x, double y, double z) {
        double dx = x - (anchor.getX() + 0.5D);
        double dz = z - (anchor.getZ() + 0.5D);
        if (dx * dx + dz * dz > (double) ZONE_RADIUS * ZONE_RADIUS) {
            return false;
        }
        return y >= anchor.getY() - ZONE_BELOW && y <= anchor.getY() + ZONE_ABOVE;
    }

    // ------------------------------------------------------------------ static islands

    /**
     * One static parkour step (real blocks): a deck at {@code height} above the crater
     * floor, centered {@code radius} out at {@code angleDeg} (counter-clockwise spiral).
     * {@code half} = deck half-extent (1 → 3×3, effectively 2×2 with the corner nibble).
     *
     * <p>Deck-top rises: 6→11 (+5), →17 (+6), →23 (+6), →30 (+7 HERO), →36 (+6),
     * →41 (+5 HERO), →44 (+3), loot +46 (+2). Chord gaps ≈ 6.5–7.5 blocks, the two hero
     * gaps ≈ 10.6/10.9 — jump height under the zone's modifiers is ≈ 6.7 blocks
     * (v₀ = 0.42·1.35, g = 0.08·0.30), so +5/+6 rises are floaty sprint jumps and the
     * two +7/long gaps need the pulse launch (v₀ 0.9 → ≈ 16.9 blocks). Verified against
     * the shell bands in the class javadoc.</p>
     */
    public record Step(double angleDeg, double radius, int height, int half) {}

    /** The 8-step counter-clockwise spiral (plan §5.3, jungle-adjusted radii). */
    public static final List<Step> STEPS = List.of(
            new Step(10.0D, 20.0D, 6, 1),
            new Step(28.0D, 21.0D, 11, 1),
            new Step(46.0D, 24.0D, 17, 1),
            new Step(63.0D, 25.0D, 23, 1),
            new Step(88.0D, 24.0D, 30, 1),   // hero gap 1 landing (pulse-timed)
            new Step(104.0D, 23.0D, 36, 1),
            new Step(132.0D, 22.0D, 41, 1),  // hero gap 2 landing (pulse-timed)
            new Step(152.0D, 17.0D, 44, 1));

    /** Loot floe: 5×2×5 deck at +{@value #LOOT_HEIGHT}, r {@value #LOOT_RADIUS} @ 170°. */
    public static final int LOOT_HEIGHT = 46;
    public static final double LOOT_RADIUS = 8.0D;
    public static final double LOOT_ANGLE_DEG = 170.0D;

    /** Ambient mega floes (7×5×7 + real mini jungle tree) — the 200-block silhouette. */
    public record MegaFloe(double angleDeg, double radius, int height) {}

    public static final List<MegaFloe> MEGA_FLOES = List.of(
            new MegaFloe(215.0D, 30.0D, 20),
            new MegaFloe(275.0D, 26.0D, 34));

    /** Local (dx, dz) of an island center from its polar layout row. */
    public static double polarX(double angleDeg, double radius) {
        return Math.cos(Math.toRadians(angleDeg)) * radius;
    }

    public static double polarZ(double angleDeg, double radius) {
        return Math.sin(Math.toRadians(angleDeg)) * radius;
    }

    // ------------------------------------------------------------------ orbital pieces

    /**
     * One BlockDisplay of the orbital (composite members share orbit parameters and
     * carry a local offset). All motion fields are consumed by
     * {@code GravityRiftOrbitals.poseAt} as absolute functions of game time.
     *
     * <p>Fields: {@code layer} 0 gravel / 1 floes / 2 islands / 3 heart core / 4 heart
     * shells; {@code index} identity-tag index (unique across the set);
     * {@code baseRadius}/{@code baseY} orbit radius (blocks from the axis) and height
     * over the crater floor; {@code phase0}/{@code omega} orbit start angle (rad) and
     * angular velocity (rad/t, signed); {@code sx sy sz} per-axis display scale;
     * {@code wobAmp wobPeriod wobPhase} radial wobble; {@code bobAmp bobPeriod bobPhase}
     * vertical bob; {@code spinRate} own-axis tumble (rad/t, signed) about the
     * {@code axX axY axZ} axis (normalized by the choreographer);
     * {@code offX offY offZ} composite-local member offset (rotated with the tumble);
     * {@code layerLift} pulse lift multiplier (0.6 / 1.0 / 1.4, heart 0);
     * {@code fallDepth} inversion drop toward the bowl floor (blocks, ≥ 0);
     * {@code viewRange} display view_range (× 64 blocks); {@code block} the rendered
     * block state.</p>
     */
    public record Piece(int layer, int index, double baseRadius, double baseY,
            double phase0, double omega, float sx, float sy, float sz,
            double wobAmp, double wobPeriod, double wobPhase,
            double bobAmp, double bobPeriod, double bobPhase,
            double spinRate, float axX, float axY, float axZ,
            double offX, double offY, double offZ,
            double layerLift, double fallDepth, float viewRange, BlockState block) {}

    /** Hard cap sanity bound (plan §5.1: ~220 built, cap 260). */
    public static final int PIECE_HARD_CAP = 260;

    /** Shell 0 piece count (single gravel displays). */
    private static final int SHELL0_COUNT = 110;
    /** Shell 1 orbit slots; the first {@value #SHELL1_COMPOSITES} are 2-slab composites. */
    private static final int SHELL1_COUNT = 48;
    private static final int SHELL1_COMPOSITES = 12;
    /** Shell 2 island composites (4–6 displays each). */
    private static final int SHELL2_COUNT = 10;

    /** Tangential speeds (blocks/tick) — outer shells drift slower (StormDebrisFx rule). */
    private static final double SHELL0_TANGENTIAL = 0.25D;
    private static final double SHELL1_TANGENTIAL = 0.12D;
    private static final double SHELL2_TANGENTIAL = 0.05D;

    private static List<Piece> pieces;

    /** The full deterministic piece list (lazily built once; pure function of the seed). */
    public static synchronized List<Piece> pieces() {
        if (pieces == null) {
            List<Piece> list = new ArrayList<>(240);
            buildShell0(list);
            buildShell1(list);
            buildShell2(list);
            buildHeart(list);
            if (list.size() > PIECE_HARD_CAP) {
                throw new IllegalStateException("GravityRiftZone: " + list.size()
                        + " pieces exceed the hard cap " + PIECE_HARD_CAP);
            }
            pieces = Collections.unmodifiableList(list);
        }
        return pieces;
    }

    /** Shell 0 "Kies": 110 small fast stones, r 6–14, y +3..+12, sizes 0.25–0.6. */
    private static void buildShell0(List<Piece> list) {
        for (int i = 0; i < SHELL0_COUNT; i++) {
            double h1 = hash01(i, 11, 0);
            double h2 = hash01(i, 12, 0);
            double h3 = hash01(i, 13, 0);
            double h4 = hash01(i, 14, 0);
            double radius = 6.0D + h1 * 8.0D;
            double baseY = 3.0D + h2 * 9.0D;
            double omega = SHELL0_TANGENTIAL / radius; // rad/t; r6 → ~2.4°/t, r14 → ~1.0°/t
            float size = (float) (0.25D + h3 * 0.35D);
            list.add(new Piece(0, list.size(), radius, baseY,
                    h4 * Math.PI * 2.0D, omega, size, size, size,
                    0.3D + h2 * 0.4D, 220.0D + h1 * 160.0D, h3 * Math.PI * 2.0D,
                    0.35D + h3 * 0.35D, 150.0D + h4 * 130.0D, h1 * Math.PI * 2.0D,
                    Math.toRadians(0.5D + h2 * 0.7D) * (h1 < 0.5D ? 1.0D : -1.0D),
                    (float) (h1 - 0.5D), 1.0F, (float) (h4 - 0.5D),
                    0.0D, 0.0D, 0.0D,
                    0.6D, fallDepthFor(radius, baseY, size),
                    3.0F, gravelMix(i)));
        }
    }

    /**
     * Shell 1 "Schollen": 48 orbit slots at r 12–20, y +12..+28, sizes 0.8–1.8 with a
     * flattened Y (×0.5); the first 12 slots are 2-slab composites (60 displays total).
     */
    private static void buildShell1(List<Piece> list) {
        for (int i = 0; i < SHELL1_COUNT; i++) {
            double h1 = hash01(i, 21, 1);
            double h2 = hash01(i, 22, 1);
            double h3 = hash01(i, 23, 1);
            double h4 = hash01(i, 24, 1);
            double radius = 12.0D + h1 * 8.0D;
            double baseY = 12.0D + h2 * 16.0D;
            double omega = -SHELL1_TANGENTIAL / radius; // counter-rotates against shell 0
            double phase0 = h4 * Math.PI * 2.0D;
            float sx = (float) (0.8D + h3 * 1.0D);
            float sy = sx * 0.5F;
            double spin = Math.toRadians(0.15D + h2 * 0.45D) * (h3 < 0.5D ? 1.0D : -1.0D);
            double wobA = 0.3D + h3 * 0.3D;
            double wobP = 260.0D + h1 * 180.0D;
            double bobA = 0.5D + h4 * 0.5D;
            double bobP = 180.0D + h2 * 140.0D;
            boolean composite = i < SHELL1_COMPOSITES;
            double fall = fallDepthFor(radius, baseY, sx);
            list.add(new Piece(1, list.size(), radius, baseY, phase0, omega,
                    sx, sy, sx, wobA, wobP, h2 * Math.PI * 2.0D,
                    bobA, bobP, h3 * Math.PI * 2.0D, spin,
                    (float) (h2 - 0.5D), 1.1F, (float) (h1 - 0.5D),
                    0.0D, 0.0D, 0.0D, 1.0D, fall, 6.0F, floeMix(i, 0)));
            if (composite) {
                // Canted under-slab hanging just below/beside the main slab — the
                // ExpansionBorderFx.buildBoulder "never a scaled cube" recipe.
                float ux = sx * (0.55F + (float) h1 * 0.25F);
                list.add(new Piece(1, list.size(), radius, baseY, phase0, omega,
                        ux, ux * 0.6F, ux, wobA, wobP, h2 * Math.PI * 2.0D,
                        bobA, bobP, h3 * Math.PI * 2.0D, spin,
                        (float) (h2 - 0.5D), 1.1F, (float) (h1 - 0.5D),
                        (h1 - 0.5D) * sx, -sy * 0.8D - 0.1D, (h4 - 0.5D) * sx,
                        1.0D, fall, 6.0F, floeMix(i, 1)));
            }
        }
    }

    /**
     * Shell 2 "Inseln": 10 big slow composites at r 11–16.5, y +28..+38 — a moss deck
     * slab up to (5.5, 1.6, 5.5), 2–3 nested under-slabs, and on four of them a real
     * jungle-tree fragment (log + leaf displays). ~50 displays.
     */
    private static void buildShell2(List<Piece> list) {
        for (int i = 0; i < SHELL2_COUNT; i++) {
            double h1 = hash01(i, 31, 2);
            double h2 = hash01(i, 32, 2);
            double h3 = hash01(i, 33, 2);
            double h4 = hash01(i, 34, 2);
            double radius = 11.0D + h1 * 5.5D;
            double baseY = 28.0D + h2 * 10.0D;
            double omega = SHELL2_TANGENTIAL / radius; // slow, same sense as shell 0
            double phase0 = i * (Math.PI * 2.0D / SHELL2_COUNT) + h3 * 0.5D;
            double spin = Math.toRadians(0.08D + h3 * 0.10D) * (h4 < 0.5D ? 1.0D : -1.0D);
            double wobA = 0.25D;
            double wobP = 340.0D + h1 * 200.0D;
            double bobA = 0.7D + h4 * 0.5D;
            double bobP = 240.0D + h2 * 160.0D;
            double bobPh = h1 * Math.PI * 2.0D;
            double fall = fallDepthFor(radius, baseY, 2.0F);
            float axX = (float) (h2 - 0.5D) * 0.4F;
            float axZ = (float) (h3 - 0.5D) * 0.4F;
            float deck = (float) (3.6D + h3 * 1.9D); // 3.6–5.5
            // Deck: moss/grass top slab.
            list.add(new Piece(2, list.size(), radius, baseY, phase0, omega,
                    deck, 1.0F, deck, wobA, wobP, h2 * 6.0D, bobA, bobP, bobPh, spin,
                    axX, 1.0F, axZ, 0.0D, 0.0D, 0.0D, 1.4D, fall, 8.0F,
                    h4 < 0.6D ? Blocks.MOSS_BLOCK.defaultBlockState()
                            : Blocks.GRASS_BLOCK.defaultBlockState()));
            // 2–3 nested canted under-slabs (dirt → stone taper).
            int subs = 2 + (h1 > 0.5D ? 1 : 0);
            for (int s = 0; s < subs; s++) {
                double hs = hash01(i * 8 + s, 35, 2);
                float sub = deck * (0.72F - 0.18F * s) * (0.9F + (float) hs * 0.2F);
                list.add(new Piece(2, list.size(), radius, baseY, phase0, omega,
                        sub, 0.9F + (float) hs * 0.5F, sub,
                        wobA, wobP, h2 * 6.0D, bobA, bobP, bobPh, spin,
                        axX, 1.0F, axZ,
                        (hs - 0.5D) * 1.4D, -1.0D - s * 0.95D, (h4 - 0.5D) * 1.4D,
                        1.4D, fall, 8.0F,
                        s == 0 ? Blocks.ROOTED_DIRT.defaultBlockState()
                                : (hs < 0.5D ? Blocks.STONE.defaultBlockState()
                                        : Blocks.DEEPSLATE.defaultBlockState())));
            }
            // Four islands carry a jungle-tree fragment: trunk + canopy displays.
            if (i % 3 == 0 && i < 12) {
                double tx = (h2 - 0.5D) * deck * 0.5D;
                double tz = (h3 - 0.5D) * deck * 0.5D;
                list.add(new Piece(2, list.size(), radius, baseY, phase0, omega,
                        0.6F, 2.2F, 0.6F, wobA, wobP, h2 * 6.0D, bobA, bobP, bobPh, spin,
                        axX, 1.0F, axZ, tx, 1.0D, tz, 1.4D, fall, 8.0F,
                        Blocks.JUNGLE_LOG.defaultBlockState()));
                list.add(new Piece(2, list.size(), radius, baseY, phase0, omega,
                        2.0F, 1.3F, 2.0F, wobA, wobP, h2 * 6.0D, bobA, bobP, bobPh, spin,
                        axX, 1.0F, axZ, tx, 3.1D, tz, 1.4D, fall, 8.0F,
                        Blocks.JUNGLE_LEAVES.defaultBlockState()));
            }
        }
    }

    /**
     * The heart composite (plan §4.5): a budding-amethyst core whose SCALE breathes
     * 1.4↔1.8 (the choreographer owns that absolute time term) inside two
     * counter-rotating tinted-glass cage shells on 45°-canted axes. Radius 0 — the
     * heart never orbits; the pulse lift/inversion terms are zeroed via layerLift 0.
     */
    private static void buildHeart(List<Piece> list) {
        list.add(new Piece(3, list.size(), 0.0D, HEART_HEIGHT, 0.0D, 0.0D,
                1.6F, 1.6F, 1.6F, 0.0D, 1.0D, 0.0D, 0.12D, 90.0D, 0.0D,
                0.0D, 0.0F, 1.0F, 0.0F, 0.0D, 0.0D, 0.0D, 0.0D, 0.0D, 8.0F,
                Blocks.BUDDING_AMETHYST.defaultBlockState()));
        list.add(new Piece(4, list.size(), 0.0D, HEART_HEIGHT, 0.0D, 0.0D,
                2.4F, 2.4F, 2.4F, 0.0D, 1.0D, 0.0D, 0.0D, 1.0D, 0.0D,
                Math.toRadians(0.4D), 1.0F, 1.0F, 0.0F, 0.0D, 0.0D, 0.0D,
                0.0D, 0.0D, 8.0F, Blocks.TINTED_GLASS.defaultBlockState()));
        list.add(new Piece(4, list.size(), 0.0D, HEART_HEIGHT, 0.0D, 0.0D,
                2.8F, 2.8F, 2.8F, 0.0D, 1.0D, 0.0D, 0.0D, 1.0D, 0.0D,
                -Math.toRadians(0.4D), 0.0F, 1.0F, 1.0F, 0.0D, 0.0D, 0.0D,
                0.0D, 0.0D, 8.0F, Blocks.TINTED_GLASS.defaultBlockState()));
    }

    /** Inversion drop: from baseY down to ~2 blocks over the local bowl floor. */
    private static double fallDepthFor(double radius, double baseY, float size) {
        int depth = depthAt((int) Math.round(radius), 0);
        double floorRel = -depth; // bowl floor at that radius, relative to floorY
        return Math.max(0.0D, baseY - (floorRel + 2.0D + size * 0.5D));
    }

    /** Shell 0 palette: cobbled deepslate / stone / tuff / andesite. */
    private static BlockState gravelMix(int i) {
        double h = hash01(i, 15, 0);
        if (h < 0.30D) return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
        if (h < 0.58D) return Blocks.STONE.defaultBlockState();
        if (h < 0.82D) return Blocks.TUFF.defaultBlockState();
        return Blocks.ANDESITE.defaultBlockState();
    }

    /** Shell 1 palette (jungle-adjusted): dirt/rooted dirt/moss/coarse dirt/stone. */
    private static BlockState floeMix(int i, int member) {
        double h = hash01(i * 2 + member, 25, 1);
        if (h < 0.26D) return Blocks.DIRT.defaultBlockState();
        if (h < 0.46D) return Blocks.ROOTED_DIRT.defaultBlockState();
        if (h < 0.68D) return Blocks.MOSS_BLOCK.defaultBlockState();
        if (h < 0.86D) return Blocks.COARSE_DIRT.defaultBlockState();
        return Blocks.STONE.defaultBlockState();
    }

    // ------------------------------------------------------------------ hash

    /**
     * Deterministic 0..1 hash — the {@code FallbackBuilders.hash01} algorithm mirrored
     * (that one is package-private in {@code worldgen.structure}; same splitmix64-style
     * avalanche over {@link DiscMapData#ECLIPSE_SEED} so results stay save-stable).
     */
    public static double hash01(int x, int y, int z) {
        long h = DiscMapData.ECLIPSE_SEED
                ^ (x * 341873128712L + y * 986534123L + z * 132897987541L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h >>> 11) & 0xFFFFF) / (double) 0x100000;
    }

    /** Clamped smoothstep 0..1 (shared by service pulse + orbital envelopes). */
    public static double smoothstep(double x) {
        x = Math.max(0.0D, Math.min(1.0D, x));
        return x * x * (3.0D - 2.0D * x);
    }
}
