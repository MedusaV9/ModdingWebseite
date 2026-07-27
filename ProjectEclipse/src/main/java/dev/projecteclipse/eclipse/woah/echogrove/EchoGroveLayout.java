package dev.projecteclipse.eclipse.woah.echogrove;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;

import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;

/**
 * WOAH-05 shared grove geometry (plan §2) — the ONE place both sides derive the
 * grove anchor from, so the server terraformer and the client's "anchor without
 * sync" window (the {@code ObservatoryAmbience} school) can never drift apart.
 *
 * <p><b>Frozen-map fallback (plan §2.1):</b> {@code disc_map.json} is frozen per
 * save, so existing saves lack the {@code eclipse:echo_grove} landmark row that
 * {@code DiscMapDefaults} now ships. {@link #landmarkXZ} therefore prefers the
 * frozen landmark and falls back to the authored code constant (0, 310) — callers
 * only log a collision warning, never fail.</p>
 *
 * <p><b>Vertical datum:</b> {@code SitePrep.preparePlateau} flattens the footprint
 * to the deterministic {@link DiscTerrainFunction#surfaceY} of the center column
 * (= "plateau Y"). The terraformer sinks the bowl {@value #BOWL_DEPTH} below that
 * and roots the memory tree on the bowl floor; the client re-derives every anchor
 * from the same constants.</p>
 */
public final class EchoGroveLayout {
    /** Landmark id as authored in {@code DiscMapDefaults.overworldDefaults()}. */
    public static final String LANDMARK_ID = "eclipse:echo_grove";
    /** Code fallback for frozen saves without the landmark row (plan §2.1). */
    public static final int FALLBACK_X = 0;
    public static final int FALLBACK_Z = 310;
    /** Grove footprint radius (the landmark row's radius column). */
    public static final int RADIUS = 30;
    /** Bowl depth at the center (cosine profile: rim 0 → center −5). */
    public static final int BOWL_DEPTH = 5;
    /** Memory-tree trunk height above the bowl floor. */
    public static final int TREE_HEIGHT = 12;

    private EchoGroveLayout() {}

    /**
     * Grove center XZ: frozen landmark if the save has it, else the code constant.
     * Never null — the fallback IS the authored position.
     */
    public static int[] landmarkXZ() {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.OVERWORLD)) {
            if (LANDMARK_ID.equals(landmark.id())) {
                return new int[] {landmark.x(), landmark.z()};
            }
        }
        return new int[] {FALLBACK_X, FALLBACK_Z};
    }

    /** Whether the frozen map actually carries the landmark (false = fallback in use). */
    public static boolean landmarkFrozen() {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.OVERWORLD)) {
            if (LANDMARK_ID.equals(landmark.id())) {
                return true;
            }
        }
        return false;
    }

    /** Deterministic plateau Y of the grove center column (both sides compute this). */
    public static int plateauY(int x, int z) {
        int y = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z);
        if (y <= -64) {
            y = DiscMapData.get().surfaceOverrideAt(x, z);
            if (y <= -64) {
                y = (int) DiscProfile.OVERWORLD.surfaceBaseY();
            }
        }
        return y;
    }

    /** Bowl-floor center block (the memory tree roots here). */
    public static BlockPos bowlCenter() {
        int[] xz = landmarkXZ();
        return new BlockPos(xz[0], plateauY(xz[0], xz[1]) - BOWL_DEPTH, xz[1]);
    }

    /**
     * The client build-probe position (plan §2.2 no. 4): the topmost center block of
     * the memory tree is a {@code waxed_oxidized_copper_bulb} — dark without redstone,
     * never occurs naturally, and sits exactly {@value #TREE_HEIGHT} above the bowl
     * floor. Client windows check "chunk loaded AND probe block present" instead of
     * a server flag.
     */
    public static BlockPos probePos() {
        return bowlCenter().above(TREE_HEIGHT);
    }

    /** Convenience: probe derived from a known tree center (server side, post-placement). */
    public static BlockPos probePos(@Nullable BlockPos treeCenter) {
        return treeCenter == null ? probePos() : treeCenter.above(TREE_HEIGHT);
    }
}
