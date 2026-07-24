package dev.projecteclipse.eclipse.entity.spawn;

import dev.projecteclipse.eclipse.worldgen.fog.FogStormSites;
import dev.projecteclipse.eclipse.worldgen.stage.NewRingRegistry;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.biome.Biome;

/**
 * P6-W6/W56 (plans_v3 §2.8): the pluggable area-gate seam between the P6 spawn rules and
 * P1's world systems. {@link EventSpawnRules} consults ONLY these predicates when
 * deciding whether a position belongs to a mob family's spawn area — P1 (or an
 * integrator) upgrades precision later by installing a sharper predicate with a single
 * assignment, e.g.:
 *
 * <pre>{@code
 * SpawnGates.FOG_STORM = FogStormService::isStormAt;      // plan §4.1
 * SpawnGates.NEW_RING = (level, pos) -> RingIndex.isNewest(level, pos);
 * SpawnGates.PALE_GARDEN = PaleGardenAreas::contains;
 * }</pre>
 *
 * <p><b>Shipped defaults</b> (all read live P1 systems already in-tree — no noise-patch
 * stand-ins needed anymore):</p>
 * <ul>
 *   <li>{@link #FOG_STORM} — inside the radius of an ACTIVE
 *       {@link FogStormSites#sites() fog-storm site} (sites materialize with the stage-3
 *       terrain sweep; inactive/unplaced sites never gate open).</li>
 *   <li>{@link #NEW_RING} — {@link NewRingRegistry#isFreshRing}: the position lies in a
 *       grown ring annulus that has not decayed past {@code glitch.freshTicks}.</li>
 *   <li>{@link #PALE_GARDEN} — the baked biome at the position is
 *       {@code eclipse:pale_garden} (biomes are baked into chunk sections at generation
 *       time — see {@code DiscBiomeSource}; the lookup falls back to the pure
 *       generator function for unloaded chunks and never sync-loads).</li>
 * </ul>
 *
 * <p>Fields are {@code volatile} so an install from a server-start hook publishes safely
 * to the tick thread. Gates are position gates ONLY — day/night/cap/weighting policy
 * lives in {@link EventSpawnRules}.</p>
 */
public final class SpawnGates {
    /** Area predicate: does {@code pos} in {@code level} belong to this spawn context? */
    @FunctionalInterface
    public interface Gate {
        boolean test(ServerLevel level, BlockPos pos);
    }

    /** {@code eclipse:pale_garden} (P1-W1.4's baked ring biome of the plains wedge). */
    public static final ResourceKey<Biome> PALE_GARDEN_BIOME = ResourceKey.create(
            Registries.BIOME, ResourceLocation.fromNamespaceAndPath("eclipse", "pale_garden"));

    /** Fog-storm areas: fog_revenant, storm_hound, fog_colossus (plan §2.8 row 1–3). */
    public static volatile Gate FOG_STORM = SpawnGates::insideActiveStormSite;
    /** Freshly-grown ring annuli: the glitched trio (plan §2.8 row 4). */
    public static volatile Gate NEW_RING = NewRingRegistry::isFreshRing;
    /** Pale-garden sectors: pale_sentinel (plan §2.8 row 5). */
    public static volatile Gate PALE_GARDEN = SpawnGates::insidePaleGarden;

    private SpawnGates() {}

    /** Default FOG_STORM gate: within an active {@link FogStormSites} site's radius. */
    private static boolean insideActiveStormSite(ServerLevel level, BlockPos pos) {
        if (level.dimension() != Level.OVERWORLD) {
            return false;
        }
        for (FogStormSites.Site site : FogStormSites.sites()) {
            if (!site.active()) {
                continue;
            }
            double dx = pos.getX() - site.x();
            double dz = pos.getZ() - site.z();
            if (dx * dx + dz * dz <= (double) site.radius() * site.radius()) {
                return true;
            }
        }
        return false;
    }

    /** Default PALE_GARDEN gate: the baked (or generator-derived) biome at the position. */
    private static boolean insidePaleGarden(ServerLevel level, BlockPos pos) {
        return level.dimension() == Level.OVERWORLD
                && level.getBiome(pos).is(PALE_GARDEN_BIOME);
    }
}
