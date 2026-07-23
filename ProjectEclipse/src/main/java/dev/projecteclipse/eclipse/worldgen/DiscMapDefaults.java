package dev.projecteclipse.eclipse.worldgen;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * Authored v2 defaults of the disc map (D6) plus the sub-ring biome tables that split
 * each pie wedge into inner/mid/outer rings (Appendix A of the P1 plan). This class is
 * the single authoring point for:
 *
 * <ul>
 *   <li>{@link #overworldDefaults()} / {@link #netherDefaults()} — the built-in
 *       {@code disc_map.json} template (§3.10 seam; {@code DiscMapData} falls back to it
 *       and {@code FrozenParams} snapshots it into new saves). Includes the v2 landmark
 *       table: mansion, pillager outpost, trial chambers, ancient city (in the mountain),
 *       nether breach + arrival chimney, fog storms, stronghold moved to the far rim.</li>
 *   <li>{@link #ringBiome} — radius-based sub-ring resolution of a wedge biome id
 *       (plains → sunflower_plains → {@code eclipse:pale_garden}, …), with a fixed-seed
 *       boundary wobble so ring seams are not perfect circles, plus the ice-spikes
 *       patches of the outer snowy ring. Deliberately <b>stage-free</b>: biomes are baked
 *       into chunks at generation time and ring sweeps never rewrite them, so every
 *       lookup here may depend only on position and frozen data.</li>
 *   <li>{@link #flankBiome} — the mountain flank ring split (authored flank biome /
 *       cherry grove / meadow thirds around the mountain center).</li>
 *   <li>{@link #allBiomeIds} — every biome id the v2 map can produce (consumed by
 *       {@code DiscBiomeSource} for holder resolution and
 *       {@code collectPossibleBiomes}).</li>
 * </ul>
 *
 * <p>Noise salts 30 (ring-boundary wobble), 31 (ice-spikes patches) and 32 (flank-ring
 * split wobble) of the frozen map-seed family live here; 29 is
 * {@link CaveBiomeMap}. Salt registry: {@code docs/plans_v3/wiring/P1-W1.2_wiring.md}.</p>
 */
public final class DiscMapDefaults {
    /** Amplitude in blocks of the ring-boundary radius wobble (D6: ±6-block hash wobble). */
    public static final double RING_WOBBLE_BLOCKS = 6.0D;
    /** Horizontal feature scale (blocks) of the ring-boundary wobble noise. */
    private static final double RING_WOBBLE_SCALE = 48.0D;
    /** Feature scale (blocks) of the ice-spikes patch field in the outer snowy ring. */
    private static final double ICE_PATCH_SCALE = 72.0D;
    /** Noise threshold above which an outer-snowy-ring column reads ice_spikes (~18 %). */
    private static final double ICE_PATCH_THRESHOLD = 0.45D;
    /** Angular wobble (degrees) of the mountain flank-ring split boundaries. */
    private static final double FLANK_WOBBLE_DEG = 14.0D;
    /** Feature scale (blocks) of the flank-split wobble noise. */
    private static final double FLANK_WOBBLE_SCALE = 40.0D;

    /** Lifecycle-keyed wobble fields (salts 30–32 of the frozen map-seed family). */
    private static volatile MapNoises mapNoises;

    private record MapNoises(long seed, SimplexNoise ringWobble, SimplexNoise icePatch,
            SimplexNoise flankWobble) {}

    /** One sub-ring of a wedge: applies while {@code r <= maxR} (wobbled); last ring is open-ended. */
    public record Ring(double maxR, String biome) {}

    /**
     * Sub-ring tables keyed by the wedge's BASE biome id (the id authored in the sector
     * list). Ring boundaries are deliberately close to the frozen stage radii
     * (150 = stage 1, 280 = stage 3) so each growth stage reveals a new biome band; the
     * desert wedge runs slightly wider (200/310) so the stage-2 desert temple sits on
     * sand and the nether-breach halo (r ≈ 120 + 28) stays fully inside the sand ring.
     * Outputs that are themselves table keys resolve to the same result, so the lookup
     * is idempotent (safe to apply both here and in a future {@code DiscMapData.biomeAt}
     * hook).
     */
    private static final Map<String, List<Ring>> OVERWORLD_RINGS = Map.ofEntries(
            Map.entry("minecraft:plains", List.of(
                    new Ring(150.0D, "minecraft:plains"),
                    new Ring(300.0D, "minecraft:sunflower_plains"),
                    new Ring(Double.MAX_VALUE, "eclipse:pale_garden"))),
            Map.entry("minecraft:desert", List.of(
                    new Ring(200.0D, "minecraft:desert"),
                    new Ring(310.0D, "minecraft:badlands"),
                    new Ring(Double.MAX_VALUE, "minecraft:wooded_badlands"))),
            Map.entry("minecraft:forest", List.of(
                    new Ring(150.0D, "minecraft:forest"),
                    new Ring(280.0D, "minecraft:birch_forest"),
                    new Ring(Double.MAX_VALUE, "minecraft:old_growth_birch_forest"))),
            Map.entry("minecraft:jungle", List.of(
                    new Ring(150.0D, "minecraft:jungle"),
                    new Ring(280.0D, "minecraft:sparse_jungle"),
                    new Ring(Double.MAX_VALUE, "minecraft:bamboo_jungle"))),
            Map.entry("minecraft:savanna", List.of(
                    new Ring(150.0D, "minecraft:savanna"),
                    new Ring(280.0D, "minecraft:savanna_plateau"),
                    new Ring(Double.MAX_VALUE, "minecraft:windswept_savanna"))),
            Map.entry("minecraft:swamp", List.of(
                    new Ring(150.0D, "minecraft:swamp"),
                    new Ring(280.0D, "minecraft:mangrove_swamp"),
                    new Ring(Double.MAX_VALUE, "minecraft:swamp"))),
            Map.entry("minecraft:snowy_slopes", List.of(
                    new Ring(150.0D, "minecraft:snowy_slopes"),
                    new Ring(280.0D, "minecraft:grove"),
                    new Ring(Double.MAX_VALUE, "minecraft:snowy_taiga"))),
            Map.entry("minecraft:dark_forest", List.of(
                    new Ring(150.0D, "minecraft:dark_forest"),
                    new Ring(280.0D, "minecraft:taiga"),
                    new Ring(Double.MAX_VALUE, "minecraft:old_growth_pine_taiga"))));

    /** Base biome id of the outer-snowy-ring whose patches flip to ice_spikes. */
    private static final String SNOWY_OUTER_RING = "minecraft:snowy_taiga";

    private DiscMapDefaults() {}

    // --- authored v2 map defaults (§3.10 seam) ---

    /**
     * Built-in overworld map template: the eight classic wedges (base biomes; rings come
     * from {@link #ringBiome}), the mountain, the three authored rivers and whisper wells
     * of v1 (kept byte-identical — {@code BreachGeometry} lip planes and the W1.2 rim
     * spill curtains are tuned to them), and the v2 landmark table.
     *
     * <p>Landmark placement rules honoured here (against the D8 radii
     * {@code {96, 150, 210, 280, 360, 440}}): a stage-N site plus its radius fits inside
     * the stage-N disc; sites clear the eight r=24 player discs on the r=170 ring, the
     * authored river centerlines (&gt;18 blocks + site radius), the mountain flank and
     * each other; each site sits inside its wedge with margin for the ±5° seam wobble
     * where geometrically possible.</p>
     */
    public static DiscMapData.MapProfile overworldDefaults() {
        List<DiscMapData.Sector> sectors = List.of(
                new DiscMapData.Sector("minecraft:plains", 337.5D, 22.5D),
                new DiscMapData.Sector("minecraft:desert", 22.5D, 67.5D),
                new DiscMapData.Sector("minecraft:forest", 67.5D, 112.5D),
                new DiscMapData.Sector("minecraft:jungle", 112.5D, 157.5D),
                new DiscMapData.Sector("minecraft:savanna", 157.5D, 202.5D),
                new DiscMapData.Sector("minecraft:swamp", 202.5D, 247.5D),
                new DiscMapData.Sector("minecraft:snowy_slopes", 247.5D, 292.5D),
                new DiscMapData.Sector("minecraft:dark_forest", 292.5D, 337.5D));
        // Peak in the snowy N sector, fully inside the stage-3 disc (r ≈ 140 + 75 < 280).
        DiscMapData.Mountain mountain = new DiscMapData.Mountain(54, -129, 280, 75,
                "minecraft:snowy_slopes", "minecraft:grove", 96, 20, 14);
        List<DiscMapData.Landmark> landmarks = List.of(
                // Existing sites, repositioned for the D8 radii (old spots fell outside
                // their stage's new disc or collided with the r=170 player-disc ring).
                new DiscMapData.Landmark("eclipse:desert_temple", 165, 99, 16, 2),      // r≈192, desert ring
                new DiscMapData.Landmark("eclipse:jungle_temple", -173, 173, 16, 3),    // r≈245, sparse jungle
                new DiscMapData.Landmark("eclipse:village_plains", 254, -22, 40, 4),    // r≈255, sunflower plains
                // Stronghold finale moved to the far rim (D6) — the mountain now hosts
                // the Ancient City instead. Snowy-taiga outer ring, due south (270°).
                new DiscMapData.Landmark("eclipse:stronghold_emergence", 0, -400, 24, 5),
                // New v2 set-piece sites (D6/D8; stamped via W1.6's two-phase registry).
                new DiscMapData.Landmark("eclipse:pillager_outpost", -192, -34, 14, 2), // r≈195, savanna plateau
                new DiscMapData.Landmark("eclipse:trial_chambers", 143, 205, 24, 3),    // r≈250, under badlands ring
                new DiscMapData.Landmark("eclipse:ancient_city", 54, -129, 40, 4),      // in the mountain, y≈-40
                new DiscMapData.Landmark("eclipse:mansion", 219, -219, 40, 4),          // r≈310, dark-forest outer ring
                // Nether breach crater (D10; W1.7 materializes on nether stage 1 / day 2).
                // r ≈ 120 keeps the crater + 12-block creep halo inside the stage-1 rim
                // (120 + 28 < 150) — see BreachGeometry.LANDMARK_ID.
                new DiscMapData.Landmark("eclipse:nether_breach", 85, 85, 16, 2),
                // Fog-storm groves (req 14; W1.9's FogStormSites places, P2 renders).
                new DiscMapData.Landmark("eclipse:fog_storm_1", -173, -173, 20, 3),     // mangrove swamp ring
                new DiscMapData.Landmark("eclipse:fog_storm_2", 0, -250, 20, 3));       // snowy grove ring
        // Painted rivers + whisper wells: unchanged from v1 (endpoints overshoot the
        // final rim on purpose; all lines keep >18 blocks clear of every site above).
        List<List<DiscMapData.Point>> rivers = List.of(
                List.of(new DiscMapData.Point(30, -80), new DiscMapData.Point(8, -34),
                        new DiscMapData.Point(36, 8), new DiscMapData.Point(110, 26),
                        new DiscMapData.Point(210, 48), new DiscMapData.Point(330, 68),
                        new DiscMapData.Point(500, 95)),
                List.of(new DiscMapData.Point(-98, -52), new DiscMapData.Point(-150, -88),
                        new DiscMapData.Point(-225, -118), new DiscMapData.Point(-310, -185),
                        new DiscMapData.Point(-425, -295)),
                List.of(new DiscMapData.Point(38, 115), new DiscMapData.Point(62, 215),
                        new DiscMapData.Point(65, 320), new DiscMapData.Point(100, 495)));
        List<DiscMapData.Point> wells = List.of(new DiscMapData.Point(-60, 30),
                new DiscMapData.Point(88, 40), new DiscMapData.Point(-30, -70));
        // Center cap is plains in v2 (Appendix A: "center cap: plains (sanctum)").
        return new DiscMapData.MapProfile("minecraft:plains", 40, sectors, mountain, null,
                landmarks, rivers, wells);
    }

    /**
     * Built-in nether map template: the five wedges and E/W moat causeways of v1 plus
     * the v2 landmarks — the breach arrival chimney near the stage-1 rim (D10; must
     * exist at nether stage 1 / day 2, i.e. r &lt; 64), the top-side bastion remnant and
     * the underside Hanging Court set-piece (both stage 2, W1.7 places them).
     */
    public static DiscMapData.MapProfile netherDefaults() {
        List<DiscMapData.Sector> sectors = List.of(
                new DiscMapData.Sector("minecraft:nether_wastes", 0.0D, 72.0D),
                new DiscMapData.Sector("minecraft:soul_sand_valley", 72.0D, 144.0D),
                new DiscMapData.Sector("minecraft:basalt_deltas", 144.0D, 216.0D),
                new DiscMapData.Sector("minecraft:crimson_forest", 216.0D, 288.0D),
                new DiscMapData.Sector("minecraft:warped_forest", 288.0D, 360.0D));
        DiscMapData.Moat moat = new DiscMapData.Moat(50, 4, List.of(0.0D, 180.0D), 6.0D);
        List<DiscMapData.Landmark> landmarks = List.of(
                new DiscMapData.Landmark("eclipse:fortress_core", 0, 0, 40, 1),
                // Basalt spiral + soul updraft return chimney (W1.7 builds; the radius
                // is the protection clearance, not the build size). The only legal band
                // at nether stage 1 is the 10-block annulus between the moat channel's
                // outer edge (50 + 4) and the rim (64): center r ≈ 59.4, clearance 4
                // keeps 55.4 > 54 off the moat and 63.4 <= 64 inside the rim. Wastes
                // wedge, 30 deg away from the 0 deg bridge causeway.
                new DiscMapData.Landmark("eclipse:breach_arrival", 48, 35, 4, 1),
                new DiscMapData.Landmark("eclipse:bastion_remnant", -25, -76, 24, 2),   // crimson wedge, r≈80
                new DiscMapData.Landmark("eclipse:hanging_court", 60, -60, 20, 2));     // warped wedge, underside
        return new DiscMapData.MapProfile("minecraft:nether_wastes", 30, sectors, null, moat,
                landmarks, List.of(), List.of());
    }

    // --- sub-ring resolution ---

    /** Sub-ring table of a wedge base biome id, or null when the wedge has no rings. */
    public static List<Ring> ringsFor(DiscProfile profile, String wedgeBiome) {
        return profile == DiscProfile.NETHER ? null : OVERWORLD_RINGS.get(wedgeBiome);
    }

    /**
     * Resolves a wedge base biome id to its sub-ring biome at (x, z): walks the wedge's
     * ring table against the wobbled radius, then applies the ice-spikes patch field
     * inside the outer snowy ring. Ids without a table (nether wedges, mountain/center
     * biomes, user-authored customs and all ring OUTPUT ids) pass through unchanged, so
     * the lookup is idempotent and degrades gracefully. Pure and worker-thread safe.
     */
    public static String ringBiome(DiscProfile profile, String wedgeBiome, double x, double z) {
        List<Ring> rings = ringsFor(profile, wedgeBiome);
        if (rings == null) {
            return wedgeBiome;
        }
        MapNoises noises = mapNoises();
        double r = Math.sqrt(x * x + z * z)
                + noises.ringWobble().getValue(x / RING_WOBBLE_SCALE, z / RING_WOBBLE_SCALE)
                        * RING_WOBBLE_BLOCKS;
        for (Ring ring : rings) {
            if (r <= ring.maxR()) {
                if (SNOWY_OUTER_RING.equals(ring.biome()) && ring.maxR() == Double.MAX_VALUE
                        && noises.icePatch().getValue(x / ICE_PATCH_SCALE, z / ICE_PATCH_SCALE)
                                > ICE_PATCH_THRESHOLD) {
                    return "minecraft:ice_spikes";
                }
                return ring.biome();
            }
        }
        return rings.get(rings.size() - 1).biome();
    }

    /**
     * Mountain flank ring biome at (x, z): the flank annulus splits into three wobbled
     * angular thirds around the mountain center — the authored flank biome (default
     * grove), cherry grove and meadow (D6: "cherry_grove + meadow on the mountain flank
     * ring"). Callers pass the live map's mountain so user re-authoring is respected.
     */
    public static String flankBiome(DiscMapData.Mountain mountain, double x, double z) {
        double angle = Math.toDegrees(Math.atan2(z - mountain.z(), x - mountain.x()))
                + mapNoises().flankWobble().getValue(x / FLANK_WOBBLE_SCALE, z / FLANK_WOBBLE_SCALE)
                        * FLANK_WOBBLE_DEG;
        angle = ((angle % 360.0D) + 360.0D) % 360.0D;
        if (angle < 120.0D) {
            return mountain.flankBiome();
        }
        return angle < 240.0D ? "minecraft:cherry_grove" : "minecraft:meadow";
    }

    private static MapNoises mapNoises() {
        long seed = FrozenParams.mapSeed();
        MapNoises cached = mapNoises;
        if (cached == null || cached.seed() != seed) {
            synchronized (DiscMapDefaults.class) {
                cached = mapNoises;
                if (cached == null || cached.seed() != seed) {
                    cached = new MapNoises(seed, DiscTerrainFunction.noise(30),
                            DiscTerrainFunction.noise(31), DiscTerrainFunction.noise(32));
                    mapNoises = cached;
                }
            }
        }
        return cached;
    }

    /**
     * Every biome id the v2 lookup can emit for the profile — ring outputs, mountain
     * core/flank-split ids, river ribbon, detached-shard mushroom fields, the 3-D cave
     * biomes and the End-disc biome. {@code DiscBiomeSource} unions this with the live
     * map's authored ids so {@code collectPossibleBiomes} stays complete (missing
     * entries would break feature/spawn bookkeeping for those biomes).
     */
    public static Set<String> allBiomeIds(DiscProfile profile) {
        Set<String> ids = new LinkedHashSet<>();
        if (profile == DiscProfile.NETHER) {
            ids.add("minecraft:nether_wastes");
            ids.add("minecraft:soul_sand_valley");
            ids.add("minecraft:basalt_deltas");
            ids.add("minecraft:crimson_forest");
            ids.add("minecraft:warped_forest");
            return ids;
        }
        for (List<Ring> rings : OVERWORLD_RINGS.values()) {
            for (Ring ring : rings) {
                ids.add(ring.biome());
            }
        }
        ids.add("minecraft:ice_spikes");
        // Mountain: core (+ jagged peaks above y 200) and the flank ring split.
        ids.add("minecraft:snowy_slopes");
        ids.add("minecraft:jagged_peaks");
        ids.add("minecraft:grove");
        ids.add("minecraft:cherry_grove");
        ids.add("minecraft:meadow");
        // River ribbon along the authored polylines; mushroom shards off the final rim.
        ids.add("minecraft:river");
        ids.add("minecraft:mushroom_fields");
        // 3-D underground / sky lookups (CaveBiomeMap + End disc).
        ids.add("minecraft:dripstone_caves");
        ids.add("minecraft:lush_caves");
        ids.add("minecraft:deep_dark");
        ids.add("minecraft:the_end");
        return ids;
    }
}
