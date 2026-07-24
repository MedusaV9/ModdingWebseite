package dev.projecteclipse.eclipse.worldgen.ore;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.BlockPos;

/**
 * P4-facing progression seam: which ores are unlocked per annulus band and where a position
 * falls on the disc.
 */
public final class OreGateApi {

    /** Stable ore identifier matching {@code ores.json} {@code id} fields. */
    public record OreId(String id) {}

    private OreGateApi() {}

    /** Ore ids whose {@code unlockStage} is satisfied in the given annulus band index. */
    public static List<OreId> unlockedInBand(int band) {
        OreConfig.Snapshot snapshot = OreConfig.current();
        List<OreId> out = new ArrayList<>();
        collectUnlocked(snapshot.overworld(), band, out);
        collectUnlocked(snapshot.nether(), band, out);
        out.sort(Comparator.comparing(OreId::id));
        return List.copyOf(out);
    }

    /** Configured unlock stage for {@code oreId}, or {@code -1} when unknown. */
    public static int unlockStageOf(String oreId) {
        Integer stage = OreConfig.current().unlockStages().get(oreId);
        return stage != null ? stage : -1;
    }

    /** Annulus band index at {@code pos} on the given disc profile (XZ distance from origin). */
    public static int bandAt(DiscProfile profile, BlockPos pos) {
        double r = Math.hypot(pos.getX(), pos.getZ());
        return FrozenParams.annulusBand(profile, r);
    }

    private static void collectUnlocked(List<OreConfig.ResolvedOre> ores, int band, List<OreId> out) {
        for (OreConfig.ResolvedOre ore : ores) {
            if (band >= ore.unlockStage()) {
                out.add(new OreId(ore.id()));
            }
        }
    }
}
