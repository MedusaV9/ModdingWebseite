package dev.projecteclipse.eclipse.gametest.worldgen;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.worldgen.DiscBiomeSource;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.Holder;
import net.minecraft.core.HolderGetter;
import net.minecraft.core.QuartPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.Biomes;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * PLAN-C C12 belt: the whole overworld sky band above
 * {@link DiscBiomeSource#END_BIOME_MIN_Y} is {@code minecraft:the_end} for EVERY column
 * (footprint or not — the footprint check is what let neighboring cold columns snow onto
 * the disc rim through quart blending), and no authored terrain outside the End disc may
 * ever reach into that band (else it would silently flip biome when the rule broadened).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class EndBiomeBandTest {
    /** Sample stride for the terrain-ceiling sweep (pure math, so a fine grid is cheap). */
    private static final int SAMPLE_STRIDE = 8;

    private EndBiomeBandTest() {}

    /**
     * No authored overworld terrain column exceeds {@code END_BIOME_MIN_Y} (320): the
     * wizard mountain peaks at ≈ 280 and the End disc itself starts at
     * {@link EndDiscGeometry#MIN_Y} (340), so the sky band is exclusively End territory.
     */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void terrainNeverEntersEndBand(GameTestHelper helper) {
        int[] radii = FrozenParams.stageRadii(DiscProfile.OVERWORLD);
        int reach = radii[radii.length - 1] + 64; // final rim + crumble-shard band
        int worst = Integer.MIN_VALUE;
        int worstX = 0;
        int worstZ = 0;
        for (int x = -reach; x <= reach; x += SAMPLE_STRIDE) {
            for (int z = -reach; z <= reach; z += SAMPLE_STRIDE) {
                int surface = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z);
                if (surface > worst) {
                    worst = surface;
                    worstX = x;
                    worstZ = z;
                }
            }
        }
        helper.assertTrue(worst <= DiscBiomeSource.END_BIOME_MIN_Y,
                "authored terrain must stay below the End biome band: surfaceY=" + worst
                        + " at (" + worstX + ", " + worstZ + ") exceeds "
                        + DiscBiomeSource.END_BIOME_MIN_Y);
        helper.assertTrue(EndDiscGeometry.MIN_Y > DiscBiomeSource.END_BIOME_MIN_Y,
                "End disc blocks must sit inside the End biome band");
        helper.succeed();
    }

    /**
     * The biome source returns {@code the_end} for every sample above the band floor —
     * inside the disc footprint, over the (snowy) wizard mountain and out past the rim —
     * and keeps the ground biomes untouched below it.
     */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void endBiomeCoversWholeSkyBand(GameTestHelper helper) {
        HolderGetter<Biome> biomes =
                helper.getLevel().registryAccess().lookupOrThrow(Registries.BIOME);
        DiscBiomeSource source = new DiscBiomeSource(DiscProfile.OVERWORLD, biomes);

        int[][] columns = {
                {0, 0},        // disc center (inside the footprint)
                {90, 0},       // disc rim
                {120, 0},      // just OUTSIDE the footprint — the old snow leak
                {54, -129},    // wizard mountain summit column (snowy_slopes ground)
                {400, 400}     // far rim
        };
        for (int[] column : columns) {
            for (int blockY : new int[] {330, 360, 440}) {
                Holder<Biome> biome = source.getNoiseBiome(
                        QuartPos.fromBlock(column[0]), QuartPos.fromBlock(blockY),
                        QuartPos.fromBlock(column[1]), null);
                helper.assertTrue(biome.is(Biomes.THE_END),
                        "sky band sample (" + column[0] + ", " + blockY + ", " + column[1]
                                + ") must be the_end, was " + biome.getRegisteredName());
            }
        }
        // Below the band the ground rules still win (mountain summit stays snowy).
        Holder<Biome> summit = source.getNoiseBiome(
                QuartPos.fromBlock(54), QuartPos.fromBlock(276), QuartPos.fromBlock(-129), null);
        helper.assertFalse(summit.is(Biomes.THE_END),
                "below-band mountain sample must keep its ground biome, was "
                        + summit.getRegisteredName());
        helper.succeed();
    }
}
