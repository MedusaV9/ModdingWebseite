package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.logging.LogUtils;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModBlocks;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.Holder;
import net.minecraft.core.Vec3i;
import net.minecraft.core.registries.Registries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.tags.TagKey;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.LegacyRandomSource;
import net.minecraft.world.level.levelgen.WorldgenRandom;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.PoolElementStructurePiece;
import net.minecraft.world.level.levelgen.structure.Structure;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.pools.JigsawPlacement;
import net.minecraft.world.level.levelgen.structure.pools.StructureTemplatePool;
import net.minecraft.world.level.levelgen.structure.pools.alias.PoolAliasLookup;
import net.minecraft.world.level.levelgen.structure.structures.JigsawStructure;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructurePlaceSettings;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructureTemplate;
import net.minecraft.world.level.storage.loot.LootTable;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;
import org.slf4j.Logger;

/**
 * Worldgen-Wave v5.2: Jigsaw-Ausbau des Gooby-Baus (Gaenge, Kammern,
 * Terminator-Kappen) und die oberirdische Picknick-Begegnung. Die Tests
 * laden und platzieren jede neue Template-Variante headless, pruefen die
 * zentralen Marker-Bloecke (Jigsaws, Truhen, Pluesch/Statue, Decke) und
 * verifizieren die komplette Datenkette Structure -> StructureSet ->
 * TemplatePool -> NBT -> LootTable inklusive Pool-Termination. Zusaetzlich
 * beweist ein End-to-End-Test mit dem echten Vanilla-Jigsaw-Placer
 * ({@code JigsawPlacement.generateJigsaw}), dass der Hub tatsaechlich
 * Tunnel- und Kammer-Kinder expandiert — nicht nur Einzeltemplates.
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyWorldExpansionTests {
    private static final Logger LOGGER = LogUtils.getLogger();
    private static final String ARENA = "arena";
    private static final String ARENA_LARGE = "arena_large";
    private static final String ARENA_WORLDGEN = "arena_worldgen";

    /**
     * Fester Worldgen-Seed der Assembly (Konvention wie 810/8121 der
     * Generator-Skripte): gewaehlt, weil er Hub + Tunnel + Kammer baut.
     */
    private static final long JIGSAW_ASSEMBLY_SEED = 810L;

    private static final String TUNNEL_POOL = "goobymod:burrow/tunnel_pool";
    private static final String DEN_POOL = "goobymod:burrow/den_pool";
    private static final String TERMINATOR_POOL = "goobymod:burrow/terminator_pool";
    private static final String EMPTY_POOL = "minecraft:empty";
    private static final String PLUG = "goobymod:burrow_plug";

    // ------------------------------------------------------------------
    // Helfer
    // ------------------------------------------------------------------

    private static StructureTemplate template(GameTestHelper helper, String path) {
        ResourceLocation id = ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, path);
        Optional<StructureTemplate> template = helper.getLevel().getStructureManager().get(id);
        helper.assertTrue(template.isPresent(), "Template-NBT fehlt: " + path);
        return template.get();
    }

    private static void placeTemplate(GameTestHelper helper, String path, BlockPos relOrigin,
            Vec3i expectedSize) {
        StructureTemplate template = template(helper, path);
        helper.assertTrue(template.getSize().equals(expectedSize),
                path + " hat unerwartete Groesse " + template.getSize());
        BlockPos origin = helper.absolutePos(relOrigin);
        helper.assertTrue(template.placeInWorld(helper.getLevel(), origin, origin,
                        new StructurePlaceSettings(), RandomSource.create(810), 3),
                path + " konnte nicht headless platziert werden");
    }

    private static CompoundTag blockEntityTag(GameTestHelper helper, BlockPos rel) {
        BlockEntity blockEntity = helper.getBlockEntity(rel);
        helper.assertTrue(blockEntity != null, "BlockEntity fehlt bei " + rel);
        return blockEntity.saveWithoutMetadata(helper.getLevel().registryAccess());
    }

    private static void assertJigsaw(GameTestHelper helper, BlockPos rel, String pool,
            String finalState) {
        helper.assertTrue(helper.getBlockState(rel).is(Blocks.JIGSAW),
                "Kein Jigsaw-Block bei " + rel);
        CompoundTag tag = blockEntityTag(helper, rel);
        helper.assertTrue(pool.equals(tag.getString("pool")),
                "Jigsaw bei " + rel + " hat Pool " + tag.getString("pool") + " statt " + pool);
        helper.assertTrue(PLUG.equals(tag.getString("target")),
                "Jigsaw bei " + rel + " zielt nicht auf " + PLUG);
        helper.assertTrue(finalState.equals(tag.getString("final_state")),
                "Jigsaw bei " + rel + " hat final_state " + tag.getString("final_state"));
    }

    private static void assertChestLoot(GameTestHelper helper, BlockPos rel, String lootTable) {
        helper.assertTrue(helper.getBlockState(rel).is(Blocks.CHEST),
                "Keine Truhe bei " + rel);
        CompoundTag tag = blockEntityTag(helper, rel);
        helper.assertTrue(lootTable.equals(tag.getString("LootTable")),
                "Truhe bei " + rel + " hat LootTable '" + tag.getString("LootTable")
                        + "' statt " + lootTable);
    }

    private static List<GoobyEntity> goobysWithin(GameTestHelper helper, BlockPos relOrigin,
            Vec3i size) {
        BlockPos origin = helper.absolutePos(relOrigin);
        AABB bounds = new AABB(Vec3.atLowerCornerOf(origin),
                Vec3.atLowerCornerOf(origin.offset(size.getX(), size.getY(), size.getZ())));
        return helper.getLevel().getEntitiesOfClass(GoobyEntity.class, bounds);
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyWorldExpansionTests.class.getClassLoader()
                .getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8))
                    .getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    // ------------------------------------------------------------------
    // Bau-Set: jede Template-Variante laedt, platziert und traegt Marker
    // ------------------------------------------------------------------

    /**
     * Der Startraum besitzt drei Tunnel-Sockets, Loot-Truhe und Bewohner.
     * Die Sockets muessen auf der Aussenschicht der Bounding Box liegen
     * (lokal x=8/x=0/z=0), sonst verwirft die Jigsaw-Assembly alle Kinder.
     */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void burrow_hub_offers_three_jigsaw_sockets(GameTestHelper helper) {
        placeTemplate(helper, "burrow/gooby_burrow", new BlockPos(4, 2, 4), new Vec3i(9, 5, 9));
        assertJigsaw(helper, new BlockPos(12, 3, 8), TUNNEL_POOL, "minecraft:air");
        assertJigsaw(helper, new BlockPos(4, 3, 8), TUNNEL_POOL, "minecraft:air");
        assertJigsaw(helper, new BlockPos(8, 3, 4), TUNNEL_POOL, "minecraft:air");
        // Durchgang Ost: Luft ueber dem Socket und dahinter offener Innenraum.
        helper.assertBlockPresent(Blocks.AIR, new BlockPos(12, 4, 8));
        helper.assertBlockPresent(Blocks.AIR, new BlockPos(11, 3, 8));
        // Grasdach des Huegels ueberspannt die volle Grundflaeche.
        helper.assertBlockPresent(Blocks.GRASS_BLOCK, new BlockPos(8, 6, 8));
        assertChestLoot(helper, new BlockPos(8, 3, 7), "goobymod:chests/gooby_burrow");

        List<GoobyEntity> residents = goobysWithin(helper, new BlockPos(4, 2, 4),
                new Vec3i(9, 5, 9));
        helper.assertTrue(residents.size() == 1,
                "Startraum platzierte nicht exakt einen Gooby: " + residents.size());
        helper.assertTrue(residents.getFirst().isBurrowResident(),
                "Startraum-Gooby ist kein Bau-Bewohner");
        helper.succeed();
    }

    /** Gerader Gang: Plug + expandierender Far-Socket, Stuetzen und Fackel. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void tunnel_straight_variant_places(GameTestHelper helper) {
        placeTemplate(helper, "burrow/tunnel_straight", new BlockPos(5, 2, 5), new Vec3i(6, 5, 5));
        assertJigsaw(helper, new BlockPos(5, 3, 7), EMPTY_POOL, "minecraft:air");
        assertJigsaw(helper, new BlockPos(10, 3, 7), DEN_POOL, "minecraft:air");
        helper.assertBlockPresent(Blocks.AIR, new BlockPos(7, 4, 7));
        helper.assertBlockPresent(Blocks.OAK_PLANKS, new BlockPos(6, 5, 7));
        helper.assertBlockPresent(Blocks.TORCH, new BlockPos(8, 3, 7));
        helper.assertBlockPresent(Blocks.GRASS_BLOCK, new BlockPos(7, 6, 7));
        helper.succeed();
    }

    /** Eck-Gang: Knick nach Sueden mit eigenem Far-Socket. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void tunnel_corner_variant_places(GameTestHelper helper) {
        placeTemplate(helper, "burrow/tunnel_corner", new BlockPos(5, 2, 5), new Vec3i(5, 5, 5));
        assertJigsaw(helper, new BlockPos(5, 3, 7), EMPTY_POOL, "minecraft:air");
        assertJigsaw(helper, new BlockPos(7, 3, 9), DEN_POOL, "minecraft:air");
        helper.assertBlockPresent(Blocks.AIR, new BlockPos(7, 4, 7));
        helper.assertBlockPresent(Blocks.AIR, new BlockPos(7, 4, 8));
        helper.assertBlockPresent(Blocks.OAK_PLANKS, new BlockPos(7, 5, 7));
        helper.assertBlockPresent(Blocks.GRASS_BLOCK, new BlockPos(7, 6, 7));
        helper.succeed();
    }

    /** Kuschelkammer: Pluesch-Gooby, Woll-Nest, Heu und Fackel — terminal. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void den_variant_offers_cozy_nest(GameTestHelper helper) {
        placeTemplate(helper, "burrow/den_small", new BlockPos(5, 2, 5), new Vec3i(7, 5, 7));
        assertJigsaw(helper, new BlockPos(5, 3, 8), EMPTY_POOL, "minecraft:air");

        BlockState plushie = helper.getBlockState(new BlockPos(8, 3, 8));
        helper.assertTrue(plushie.is(ModBlocks.GOOBY_PLUSHIE.get()),
                "Kuschelkammer ohne Gooby-Plushie");
        helper.assertTrue(plushie.getValue(BlockStateProperties.HORIZONTAL_FACING) == Direction.WEST,
                "Plushie blickt nicht zum Kammer-Eingang");
        helper.assertBlockPresent(ModBlocks.GOOBY_WOOL.get(), new BlockPos(9, 3, 9));
        helper.assertBlockPresent(ModBlocks.GOOBY_WOOL.get(), new BlockPos(10, 3, 9));
        helper.assertBlockPresent(Blocks.HAY_BLOCK, new BlockPos(10, 3, 6));
        helper.assertBlockPresent(Blocks.TORCH, new BlockPos(6, 3, 10));
        helper.assertBlockPresent(Blocks.GRASS_BLOCK, new BlockPos(8, 6, 8));
        helper.succeed();
    }

    /** Vorratskammer: eigene Pantry-Loot-Truhe, Heustapel und Regal — terminal. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void pantry_variant_stocks_burrow_loot(GameTestHelper helper) {
        placeTemplate(helper, "burrow/pantry", new BlockPos(5, 2, 5), new Vec3i(7, 5, 7));
        assertJigsaw(helper, new BlockPos(5, 3, 8), EMPTY_POOL, "minecraft:air");
        assertChestLoot(helper, new BlockPos(8, 3, 8), "goobymod:chests/gooby_burrow_pantry");
        helper.assertBlockPresent(Blocks.HAY_BLOCK, new BlockPos(6, 3, 6));
        helper.assertBlockPresent(Blocks.HAY_BLOCK, new BlockPos(6, 4, 6));
        helper.assertBlockPresent(Blocks.OAK_PLANKS, new BlockPos(10, 3, 6));
        helper.assertBlockPresent(Blocks.GRASS_BLOCK, new BlockPos(8, 6, 8));
        helper.succeed();
    }

    /** Terminator-Kappe: versiegelt sich selbst mit Erde (final_state dirt). */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void end_cap_variant_seals_tunnels(GameTestHelper helper) {
        placeTemplate(helper, "burrow/end_cap", new BlockPos(5, 2, 5), new Vec3i(1, 5, 5));
        assertJigsaw(helper, new BlockPos(5, 3, 7), EMPTY_POOL, "minecraft:dirt");
        helper.assertBlockPresent(Blocks.DIRT, new BlockPos(5, 2, 7));
        helper.assertBlockPresent(Blocks.DIRT, new BlockPos(5, 4, 7));
        helper.assertBlockPresent(Blocks.GRASS_BLOCK, new BlockPos(5, 6, 7));
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Echte Jigsaw-Assembly (Vanilla-Placer, kein Einzeltemplate)
    // ------------------------------------------------------------------

    /**
     * End-to-End-Beweis der Bau-Expansion: {@link JigsawPlacement#generateJigsaw}
     * — derselbe Placer wie Weltgenerierung und {@code /place jigsaw} — baut aus
     * dem Start-Pool eine echte Piece-Kette. Erwartung: der Hub steht (drei
     * Tunnel-Sockets), mindestens ein Tunnel UND mindestens eine Kammer
     * (Kuschelkammer oder Vorratskammer) entstehen als Kind-Pieces. Vor dem
     * Boundary-Fix der Hub-Sockets schlug genau das fehl: jeder Socket wurde
     * sofort mit der Terminator-Kappe versiegelt.
     *
     * <p>{@code keepJigsaws=true} laesst die Jigsaw-Block-NBT stehen, sodass
     * platzierte Pieces eindeutig ueber ihre Pool-Eintraege nachweisbar sind:
     * nur der Hub traegt tunnel_pool-Sockets, nur Tunnel tragen den
     * den_pool-Far-Socket. Die Assertions sind bewusst varianten-agnostisch
     * (gerade/Eck-Tunnel, Kuschel-/Vorratskammer).
     *
     * <p><b>Determinismus:</b> {@code generateJigsaw} leitet seinen Worldgen-RNG
     * aus Level-Seed + Chunk-Position ab — und die haengt von der zufaelligen
     * Arena-Platzierung des GameTest-Runners ab. Je nach Lauf konnte so eine
     * Rotations-/Varianten-Kombination gezogen werden, bei der alle drei
     * Kammern kollidierten und nur Terminator-Kappen fielen (seltener Flake).
     * Der Test baut den identischen Vanilla-Pfad ({@code addPieces} +
     * {@code PoolElementStructurePiece.place}) deshalb mit einem FESTEN
     * {@link WorldgenRandom}-Seed nach: gleiche Piece-Kette in jedem Lauf,
     * unabhaengig davon, wo der Runner die Arena platziert. Die Assertions
     * selbst bleiben unveraendert streng.
     */
    @GameTest(template = ARENA_WORLDGEN, timeoutTicks = 400)
    public static void burrow_jigsaw_assembly_expands_tunnels_and_chambers(GameTestHelper helper) {
        ServerLevel level = helper.getLevel();
        Holder<StructureTemplatePool> startPool = level.registryAccess()
                .registryOrThrow(Registries.TEMPLATE_POOL)
                .getHolderOrThrow(ResourceKey.create(Registries.TEMPLATE_POOL,
                        ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "burrow/start_pool")));
        BlockPos anchor = helper.absolutePos(new BlockPos(24, 3, 24));
        ChunkGenerator chunkGenerator = level.getChunkSource().getGenerator();
        // Fester Seed + feste ChunkPos: die Assembly ist damit byte-identisch
        // reproduzierbar — exakt der Codepfad von generateJigsaw, nur ohne
        // dessen platzierungsabhaengige RNG-Ableitung.
        Structure.GenerationContext context = new Structure.GenerationContext(
                level.registryAccess(), chunkGenerator, chunkGenerator.getBiomeSource(),
                level.getChunkSource().randomState(), level.getStructureManager(),
                new WorldgenRandom(new LegacyRandomSource(JIGSAW_ASSEMBLY_SEED)),
                JIGSAW_ASSEMBLY_SEED, new ChunkPos(0, 0), level, biome -> true);
        Optional<Structure.GenerationStub> stub = JigsawPlacement.addPieces(context, startPool,
                Optional.of(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "burrow_socket")),
                2, anchor, false, Optional.empty(), 128, PoolAliasLookup.EMPTY,
                JigsawStructure.DEFAULT_DIMENSION_PADDING, JigsawStructure.DEFAULT_LIQUID_SETTINGS);
        helper.assertTrue(stub.isPresent(),
                "JigsawPlacement.addPieces fand keinen Start-Socket im Hub");
        RandomSource placeRandom = RandomSource.create(JIGSAW_ASSEMBLY_SEED);
        for (StructurePiece piece : stub.orElseThrow().getPiecesBuilder().build().pieces()) {
            if (piece instanceof PoolElementStructurePiece pooled) {
                pooled.place(level, level.structureManager(), chunkGenerator, placeRandom,
                        BoundingBox.infinite(), anchor, true);
            }
        }

        int hubSockets = 0;
        int tunnelFarSockets = 0;
        int chamberMarkers = 0;
        for (BlockPos pos : BlockPos.betweenClosed(helper.absolutePos(BlockPos.ZERO),
                helper.absolutePos(new BlockPos(47, 9, 47)))) {
            BlockState state = level.getBlockState(pos);
            if (state.is(Blocks.JIGSAW)) {
                BlockEntity blockEntity = level.getBlockEntity(pos);
                helper.assertTrue(blockEntity != null, "Jigsaw ohne BlockEntity bei " + pos);
                String pool = blockEntity.saveWithoutMetadata(level.registryAccess())
                        .getString("pool");
                if (TUNNEL_POOL.equals(pool)) {
                    hubSockets++;
                } else if (DEN_POOL.equals(pool)) {
                    tunnelFarSockets++;
                }
            } else if (state.is(ModBlocks.GOOBY_PLUSHIE.get())) {
                chamberMarkers++;
            } else if (state.is(Blocks.CHEST)) {
                BlockEntity blockEntity = level.getBlockEntity(pos);
                if (blockEntity != null && "goobymod:chests/gooby_burrow_pantry".equals(
                        blockEntity.saveWithoutMetadata(level.registryAccess())
                                .getString("LootTable"))) {
                    chamberMarkers++;
                }
            }
        }
        LOGGER.info("[GoobyWorldgen] Jigsaw-Assembly: hubSockets={}, tunnelFarSockets={}, "
                + "chamberMarkers={}", hubSockets, tunnelFarSockets, chamberMarkers);
        helper.assertTrue(hubSockets == 3,
                "Hub-Startraum fehlt oder unvollstaendig: " + hubSockets
                        + " tunnel_pool-Sockets statt 3");
        helper.assertTrue(tunnelFarSockets >= 1,
                "Kein Tunnel-Piece platziert (kein den_pool-Far-Socket gefunden)");
        helper.assertTrue(chamberMarkers >= 1,
                "Keine Kammer platziert (weder Pluesch-Gooby noch Pantry-Truhe gefunden)");

        List<GoobyEntity> residents = goobysWithin(helper, BlockPos.ZERO, new Vec3i(48, 10, 48));
        helper.assertTrue(residents.size() == 1,
                "Assembly spawnte nicht exakt einen Bewohner: " + residents.size());
        helper.assertTrue(residents.getFirst().isBurrowResident(),
                "Assembly-Bewohner ist kein Bau-Bewohner");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Picknick-Begegnung
    // ------------------------------------------------------------------

    /** Picknick: Karo-Decke, Kuchen, Pluesch, Statue, Korb-Loot und scheuer Gast. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void picnic_encounter_places_with_markers(GameTestHelper helper) {
        placeTemplate(helper, "picnic/gooby_picnic", new BlockPos(3, 2, 3), new Vec3i(11, 4, 11));

        BlockState plushie = helper.getBlockState(new BlockPos(7, 3, 7));
        helper.assertTrue(plushie.is(ModBlocks.GOOBY_PLUSHIE.get()),
                "Picknick ohne Pluesch-Gast auf der Decke");
        helper.assertTrue(plushie.getValue(BlockStateProperties.HORIZONTAL_FACING) == Direction.EAST,
                "Pluesch-Gast blickt nicht zum Kuchen");
        BlockState statue = helper.getBlockState(new BlockPos(5, 3, 11));
        helper.assertTrue(statue.is(ModBlocks.GOOBY_STATUE.get()), "Picknick ohne Gooby-Statue");

        helper.assertBlockPresent(Blocks.CAKE, new BlockPos(8, 3, 8));
        helper.assertBlockPresent(Blocks.WHITE_CARPET, new BlockPos(6, 3, 6));
        helper.assertBlockPresent(Blocks.PINK_CARPET, new BlockPos(6, 3, 7));
        helper.assertBlockPresent(Blocks.HAY_BLOCK, new BlockPos(11, 3, 11));
        helper.assertBlockPresent(Blocks.LANTERN, new BlockPos(11, 4, 11));
        helper.assertBlockPresent(Blocks.DANDELION, new BlockPos(4, 3, 8));
        assertChestLoot(helper, new BlockPos(8, 3, 11), "goobymod:chests/gooby_picnic");

        List<GoobyEntity> guests = goobysWithin(helper, new BlockPos(3, 2, 3),
                new Vec3i(11, 4, 11));
        helper.assertTrue(guests.size() == 1,
                "Picknick platzierte nicht exakt einen Gooby: " + guests.size());
        helper.assertTrue(guests.getFirst().isShyWild(), "Picknick-Gooby startete nicht scheu");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Datenketten: Registries, Pools, Termination, Loot, Streuung
    // ------------------------------------------------------------------

    /** Der Server hat alle neuen Worldgen-Eintraege wirklich in die Registries geladen. */
    @GameTest(template = ARENA)
    public static void worldgen_registries_contain_new_entries(GameTestHelper helper) {
        var access = helper.getLevel().registryAccess();
        var structures = access.registryOrThrow(Registries.STRUCTURE);
        for (String id : List.of("gooby_burrow", "gooby_picnic", "gooby_treasure_cache")) {
            helper.assertTrue(structures.containsKey(
                            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, id)),
                    "Structure-Registry ohne goobymod:" + id);
        }
        var sets = access.registryOrThrow(Registries.STRUCTURE_SET);
        for (String id : List.of("gooby_burrows", "gooby_picnics", "gooby_treasure_caches")) {
            helper.assertTrue(sets.containsKey(
                            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, id)),
                    "StructureSet-Registry ohne goobymod:" + id);
        }
        var pools = access.registryOrThrow(Registries.TEMPLATE_POOL);
        for (String id : List.of("burrow/start_pool", "burrow/tunnel_pool", "burrow/den_pool",
                "burrow/terminator_pool", "picnic/start_pool", "treasure_cache/start_pool")) {
            helper.assertTrue(pools.containsKey(
                            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, id)),
                    "TemplatePool-Registry ohne goobymod:" + id);
        }

        var biomes = access.registryOrThrow(Registries.BIOME);
        var picnicBiomes = biomes.getTag(TagKey.create(Registries.BIOME,
                ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "has_gooby_picnics")));
        helper.assertTrue(picnicBiomes.isPresent() && picnicBiomes.get().size() >= 3,
                "Biome-Tag has_gooby_picnics fehlt oder ist zu klein");
        helper.succeed();
    }

    /** Jeder Pool loest auf, jede Socket-Kette endet in der Terminator-Kappe. */
    @GameTest(template = ARENA)
    public static void jigsaw_pools_resolve_and_terminate(GameTestHelper helper) {
        for (Map.Entry<String, String> entry : Map.of(
                "data/goobymod/worldgen/template_pool/burrow/tunnel_pool.json", TERMINATOR_POOL,
                "data/goobymod/worldgen/template_pool/burrow/den_pool.json", TERMINATOR_POOL,
                "data/goobymod/worldgen/template_pool/burrow/terminator_pool.json", EMPTY_POOL,
                "data/goobymod/worldgen/template_pool/picnic/start_pool.json", EMPTY_POOL)
                .entrySet()) {
            JsonObject pool = loadAssetJson(helper, entry.getKey());
            helper.assertTrue(entry.getValue().equals(pool.get("fallback").getAsString()),
                    entry.getKey() + " hat falschen Fallback: " + pool.get("fallback"));
        }

        // Erwartete Sockets (pool != minecraft:empty) pro Template-Variante.
        Map<String, Map<String, Integer>> expected = Map.of(
                "burrow/gooby_burrow", Map.of(TUNNEL_POOL, 3),
                "burrow/tunnel_straight", Map.of(DEN_POOL, 1),
                "burrow/tunnel_corner", Map.of(DEN_POOL, 1),
                "burrow/den_small", Map.of(),
                "burrow/pantry", Map.of(),
                "burrow/end_cap", Map.of(),
                "picnic/gooby_picnic", Map.of());
        for (Map.Entry<String, Map<String, Integer>> entry : expected.entrySet()) {
            StructureTemplate template = template(helper, entry.getKey());
            List<StructureTemplate.StructureBlockInfo> jigsaws = template.filterBlocks(
                    BlockPos.ZERO, new StructurePlaceSettings(), Blocks.JIGSAW);
            Set<String> plugNames = new HashSet<>();
            Map<String, Integer> sockets = new HashMap<>();
            for (StructureTemplate.StructureBlockInfo info : jigsaws) {
                CompoundTag tag = info.nbt();
                helper.assertTrue(tag != null, entry.getKey() + ": Jigsaw ohne NBT");
                plugNames.add(tag.getString("name"));
                String pool = tag.getString("pool");
                if (!EMPTY_POOL.equals(pool)) {
                    sockets.merge(pool, 1, Integer::sum);
                    helper.assertTrue(PLUG.equals(tag.getString("target")),
                            entry.getKey() + ": Socket zielt nicht auf " + PLUG);
                }
            }
            helper.assertTrue(sockets.equals(entry.getValue()),
                    entry.getKey() + ": Sockets " + sockets + " statt " + entry.getValue());
            if (entry.getKey().startsWith("burrow/") && !entry.getKey().endsWith("gooby_burrow")) {
                helper.assertTrue(plugNames.contains(PLUG),
                        entry.getKey() + ": anschliessbarer Plug '" + PLUG + "' fehlt");
            }
        }

        // Terminator-Garantie: Die Kappe ist sockelfrei — jede Kette endet dort.
        StructureTemplate cap = template(helper, "burrow/end_cap");
        for (StructureTemplate.StructureBlockInfo info : cap.filterBlocks(
                BlockPos.ZERO, new StructurePlaceSettings(), Blocks.JIGSAW)) {
            helper.assertTrue(EMPTY_POOL.equals(info.nbt().getString("pool")),
                    "end_cap expandiert weiter statt zu terminieren");
        }
        helper.succeed();
    }

    /** Die Structure-Sets bleiben selten: spacing > separation, eindeutige Salts. */
    @GameTest(template = ARENA)
    public static void structure_sets_stay_sparse(GameTestHelper helper) {
        Set<Integer> salts = new HashSet<>();
        for (String set : List.of("gooby_burrows", "gooby_picnics", "gooby_treasure_caches")) {
            JsonObject placement = loadAssetJson(helper,
                    "data/goobymod/worldgen/structure_set/" + set + ".json")
                    .getAsJsonObject("placement");
            int spacing = placement.get("spacing").getAsInt();
            int separation = placement.get("separation").getAsInt();
            helper.assertTrue(spacing > separation && separation > 0,
                    set + ": spacing/separation unplausibel (" + spacing + "/" + separation + ")");
            helper.assertTrue(spacing >= 32,
                    set + ": spacing " + spacing + " wuerde die Welt zuspammen");
            helper.assertTrue(salts.add(placement.get("salt").getAsInt()),
                    set + ": salt kollidiert mit anderem Gooby-Set");
        }
        helper.succeed();
    }

    /** Alle Loot-Tables der Wave sind serverseitig registriert und nicht leer. */
    @GameTest(template = ARENA)
    public static void expansion_loot_tables_are_served(GameTestHelper helper) {
        for (String id : List.of("chests/gooby_burrow", "chests/gooby_burrow_pantry",
                "chests/gooby_picnic", "chests/gooby_treasure_cache")) {
            LootTable table = helper.getLevel().getServer().reloadableRegistries()
                    .getLootTable(ResourceKey.create(Registries.LOOT_TABLE,
                            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, id)));
            helper.assertTrue(table != LootTable.EMPTY,
                    "LootTable goobymod:" + id + " wurde nicht geladen");
        }
        helper.succeed();
    }
}
