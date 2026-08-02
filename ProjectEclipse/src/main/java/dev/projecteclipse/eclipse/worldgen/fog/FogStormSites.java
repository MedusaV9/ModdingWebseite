package dev.projecteclipse.eclipse.worldgen.fog;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.entity.boss.fog.FogBankMarker;
import dev.projecteclipse.eclipse.network.S2CFogStormPayload;
import dev.projecteclipse.eclipse.stormfx.StormRegistry;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.SnowyDirtBlock;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Fog-storm site placement (req 14): storm-scarred groves with loot chests at overworld stage 3.
 * Sites are frozen in {@code worldgen.json → fogstorms} and materialize when the stage-3 terrain
 * sweep completes. Visuals (fog walls, lightning) are P2; storm mobs are P6.
 *
 * <p>Sites use W1.6's two-phase registry: stage completion only enqueues a pending row;
 * the registered placer runs {@link SitePrep} and materializes the grove after a rift
 * trigger/auto-delay. Chest positions and placed/active lifecycle flags persist in
 * {@link EclipseWorldgenState}, so standing walls are re-announced after restart.</p>
 *
 * <p>B13: the grove palette is biome-aware (cold columns keep a snow/powder-snow scar
 * instead of mud/podzol), and when a storm retires — stage rollback or the
 * {@link #stormEnded} hook — a budgeted {@code freeze_top_layer}-style sweep re-snows
 * the footprint. The per-site {@code recovered} flag in {@link EclipseWorldgenState}
 * keeps restarts from re-running the sweep.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogStormSites {
    /** Shared pending-registry placer id for all configured fog sites. */
    public static final String STRUCTURE_ID = "eclipse:fog_storm";

    /** One configured fog-storm site (frozen per save). */
    public record Site(String id, int x, int z, int radius, int stage, List<String> mobSet, boolean active) {}

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();
    private static volatile List<Site> sites = List.of();
    private static volatile MinecraftServer activeServer;

    private FogStormSites() {}

    /** Active site table for P6 storm spawners (center, radius, mobSet). */
    public static List<Site> sites() {
        return sites;
    }

    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(FogStormSites::onStageTerrainComplete);
            EclipseMod.LOGGER.info("FogStormSites registered as world-stage listener");
        }
        StructurePendingRegistry.registerAsyncPlacer(STRUCTURE_ID,
                (level, pending, complete, failure) -> {
            Site site = findSite(pending.siteId());
            if (site == null) {
                failure.accept(new IllegalStateException("Missing frozen fog site " + pending.siteId()));
                return;
            }
            materializeSite(level, site, complete, failure);
        });
    }

    /** Restores persisted placed/active flags before the storm registry's first poll. */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        activeServer = event.getServer();
        restoreFromState(activeServer);
    }

    @SubscribeEvent
    public static void onServerStopping(ServerStoppingEvent event) {
        ServerLevel overworld = event.getServer().overworld();
        for (Site site : sites) {
            retireSessionSite(overworld, site);
        }
        FogBankMarker.clearAll(overworld);
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeServer = null;
        sites = List.of();
    }

    private static List<Site> loadSites(@Nullable Path saveEclipseDir) {
        if (saveEclipseDir == null) {
            return List.of();
        }
        Path file = saveEclipseDir.resolve("fogstorms.json");
        if (!Files.isRegularFile(file)) {
            return List.of();
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            return parseSites(root);
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("FogStormSites: failed to read {}", file, e);
            return List.of();
        }
    }

    private static List<Site> parseSites(JsonObject root) {
        if (!root.has("sites")) {
            return List.of();
        }
        List<Site> parsed = new ArrayList<>();
        for (JsonElement element : root.getAsJsonArray("sites")) {
            JsonObject obj = element.getAsJsonObject();
            String id = obj.get("id").getAsString();
            int x = obj.get("x").getAsInt();
            int z = obj.get("z").getAsInt();
            int radius = obj.has("radius") ? obj.get("radius").getAsInt() : 28;
            int stage = obj.has("stage") ? obj.get("stage").getAsInt() : 3;
            List<String> mobSet = new ArrayList<>();
            if (obj.has("mobSet")) {
                obj.getAsJsonArray("mobSet").forEach(e -> mobSet.add(e.getAsString()));
            }
            parsed.add(new Site(id, x, z, radius, stage, List.copyOf(mobSet), false));
        }
        return List.copyOf(parsed);
    }

    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage) {
        if (profile != DiscProfile.OVERWORLD) {
            return;
        }
        if (toStage <= fromStage) {
            EclipseWorldgenState state = EclipseWorldgenState.get(level.getServer());
            for (Site site : sites) {
                if (site.stage() <= toStage) {
                    continue;
                }
                // B13: sweep before the state reset — recoverSite reads placed/recovered.
                recoverSite(level, site);
                state.setFogSiteState(site.id(), List.of(), false, false);
                retireSessionSite(level, site);
                broadcast(level, site, surfaceCenter(level, site.x(), site.z()), false);
            }
            reconcileTyrantLair(level);
            return;
        }
        for (Site site : sites) {
            if (site.stage() > toStage || site.stage() <= fromStage) {
                continue;
            }
            BlockPos center = surfaceCenter(level, site.x(), site.z());
            StructurePendingRegistry.enqueue(new PendingSite(site.id(), STRUCTURE_ID,
                    DiscProfile.OVERWORLD.name(), center, site.stage(), site.radius() * 2,
                    level.getGameTime()));
        }
    }

    /**
     * Builds one pending storm grove through SitePrep, persists its chests/lifecycle and
     * broadcasts {@link S2CFogStormPayload}. Called by the pending-registry placer.
     */
    public static void materializeSite(ServerLevel level, Site site) {
        materializeSite(level, site, () -> {},
                error -> EclipseMod.LOGGER.error("Fog storm placement of {} failed", site.id(), error));
    }

    /**
     * Callback-aware materialization used by the pending registry. Completion fires only
     * after SitePrep and all grove/chest writes finish.
     */
    public static void materializeSite(ServerLevel level, Site site, Runnable onComplete,
            java.util.function.Consumer<Throwable> onFailure) {
        BlockPos center = surfaceCenter(level, site.x(), site.z());
        int surfaceY = center.getY();
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                site.x() - site.radius(), site.z() - site.radius(),
                site.x() + site.radius(), site.z() + site.radius(), center);
        prepared.whenReady(() -> {
            carveGrove(level, center, site.radius(), surfaceY);
            placeCamp(level, center, surfaceY);
            List<BlockPos> chests = placeChests(level, center, surfaceY, site.id());
            SitePrep.finish(level, prepared);
            EclipseWorldgenState.get(level.getServer()).setFogSiteState(site.id(), chests, true, true);
            broadcast(level, site, center, true);
            EclipseMod.LOGGER.info("FogStormSites: materialized {} at {}", site.id(), center);
            reconcileTyrantLair(level);
            onComplete.run();
        }, onFailure);
    }

    /**
     * P6-W11 seam, widened by F-083: EVERY active storm hosts its own Fog Tyrant lair
     * (statue + boss), fightable independently and in any order — no more single
     * highest-stage pick. Markers are session-only and are fully reconciled whenever
     * site lifecycle changes (clear-all + re-mark actives in one pass; statues survive
     * the churn, see {@code FogBankMarker.clearAll}).
     */
    private static void reconcileTyrantLair(ServerLevel level) {
        FogBankMarker.clearAll(level);
        sites.stream().filter(Site::active)
                .forEach(site -> FogBankMarker.markLair(level,
                        surfaceCenter(level, site.x(), site.z())));
    }

    private static void retireSessionSite(ServerLevel level, Site site) {
        BlockPos center = surfaceCenter(level, site.x(), site.z());
        FogBankMarker.clearLair(level, center);
        StormRegistry.handleFogSite(level, site.id(), Vec3.atCenterOf(center), site.radius(), false);
    }

    /**
     * B13 "storm ended" hook: retires one site's standing wall at runtime (boss defeat,
     * quest beat or dev command) and runs the one-shot snow-recovery sweep. Unlike the
     * server-stop retirement this persists {@code active=false}, so the wall stays down
     * after restart. Unknown ids are ignored.
     */
    public static void stormEnded(ServerLevel level, String siteId) {
        Site site = findSite(siteId);
        if (site == null) {
            return;
        }
        recoverSite(level, site);
        BlockPos center = surfaceCenter(level, site.x(), site.z());
        FogBankMarker.clearLair(level, center);
        StormRegistry.handleFogSite(level, site.id(), Vec3.atCenterOf(center), site.radius(), false);
        EclipseWorldgenState state = EclipseWorldgenState.get(level.getServer());
        EclipseWorldgenState.FogSiteState saved = state.fogSiteState(site.id());
        state.setFogSiteState(site.id(), saved.chests(), saved.placed(), false, saved.recovered());
        broadcast(level, site, center, false);
        reconcileTyrantLair(level);
    }

    /**
     * B13 snow-recovery sweep: after the storm retires, walks every column of the site
     * footprint and re-freezes cold-biome tops — a manual {@code freeze_top_layer}:
     * water sources become ice, then a snow layer lands on motion-blocking,
     * snow-supporting tops (chest/campfire columns are skipped). Runs through
     * {@link BudgetedBlockWriter} like all site work and flips the persisted
     * {@code recovered} flag exactly once; never runs for unplaced or already
     * recovered sites.
     */
    private static void recoverSite(ServerLevel level, Site site) {
        EclipseWorldgenState state = EclipseWorldgenState.get(level.getServer());
        EclipseWorldgenState.FogSiteState saved = state.fogSiteState(site.id());
        if (!saved.placed() || saved.recovered()) {
            return;
        }
        state.setFogSiteRecovered(site.id(), true);
        int radius = site.radius();
        int span = radius * 2 + 1;
        int total = span * span;
        int[] cursor = {0};
        // WAVE6 (F-106 B) B6: honest skip counter — columns the loaded-chunk gate below
        // refuses are COUNTED instead of silently mis-read at the dimension floor.
        int[] skipped = {0};
        BudgetedBlockWriter.enqueue(level, budget -> {
            int end = Math.min(total, cursor[0] + budget);
            for (; cursor[0] < end; cursor[0]++) {
                int dx = cursor[0] % span - radius;
                int dz = cursor[0] / span - radius;
                if (dx * dx + dz * dz <= radius * radius
                        && !recoverColumn(level, site.x() + dx, site.z() + dz)) {
                    skipped[0]++;
                }
            }
            return cursor[0] >= total;
        }, () -> {
            EclipseMod.LOGGER.info("FogStormSites: snow recovery finished for {}", site.id());
            if (skipped[0] > 0) {
                EclipseMod.LOGGER.info("[w6b-recover] site={} skipped={} columns",
                        site.id(), skipped[0]);
            }
        }, error -> EclipseMod.LOGGER.error("FogStormSites: snow recovery for {} failed",
                        site.id(), error));
    }

    /**
     * One column of the recovery sweep; no-op outside cold-at-surface biomes.
     *
     * @return {@code false} when the column was SKIPPED because its chunk is not loaded
     */
    private static boolean recoverColumn(ServerLevel level, int x, int z) {
        // WAVE6 (F-106 B) B6 boot-order gate (pollFogSites fix class, commit 1c56087):
        // getHeightmapPos on an UNLOADED chunk lands at the dimension floor, whose biome
        // lookup is a cave biome — the column was then dropped SILENTLY while the sweep
        // still reported "finished". Skip it honestly instead.
        if (!level.isLoaded(new BlockPos(x, level.getSeaLevel(), z))) {
            return false;
        }
        BlockPos top = level.getHeightmapPos(Heightmap.Types.MOTION_BLOCKING, new BlockPos(x, 0, z));
        Biome biome = level.getBiome(top).value();
        if (!biome.coldEnoughToSnow(top)) {
            return true;
        }
        BlockPos below = top.below();
        BlockState ground = level.getBlockState(below);
        if (ground.is(Blocks.CHEST) || ground.is(Blocks.CAMPFIRE)) {
            return true;
        }
        if (biome.shouldFreeze(level, below, false)) {
            level.setBlock(below, Blocks.ICE.defaultBlockState(), 3);
            return true;
        }
        if (biome.shouldSnow(level, top)) {
            level.setBlock(top, Blocks.SNOW.defaultBlockState(), 3);
            if (ground.hasProperty(SnowyDirtBlock.SNOWY)) {
                level.setBlock(below, ground.setValue(SnowyDirtBlock.SNOWY, true), 2);
            }
        }
        return true;
    }

    private static BlockPos surfaceCenter(ServerLevel level, int x, int z) {
        int y = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z);
        if (y <= level.getMinBuildHeight()) {
            y = DiscMapData.get().surfaceOverrideAt(x, z);
            if (y <= level.getMinBuildHeight()) {
                y = (int) DiscProfile.OVERWORLD.surfaceBaseY();
            }
        }
        return new BlockPos(x, y, z);
    }

    private static void carveGrove(ServerLevel level, BlockPos center, int radius, int surfaceY) {
        int cx = center.getX();
        int cz = center.getZ();
        for (int dx = -radius; dx <= radius; dx++) {
            for (int dz = -radius; dz <= radius; dz++) {
                double dist = Math.hypot(dx, dz);
                if (dist > radius) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                // SitePrep flattened the whole grove footprint to the center height.
                // Painting the pre-terraform procedural height would bury these blocks
                // under the plateau (or suspend them above it on former slopes).
                int colY = surfaceY;
                double scar = 1.0D - dist / radius;
                BlockPos groundPos = new BlockPos(x, colY, z);
                // B13: cold columns (snowy grove ring) keep a snow scar instead of the
                // biome-blind mud/podzol palette; the scorched center stays mud.
                boolean cold = level.getBiome(groundPos.above()).value()
                        .coldEnoughToSnow(groundPos.above());
                BlockState ground;
                if (scar > 0.55D) {
                    ground = Blocks.MUD.defaultBlockState();
                } else if (cold) {
                    ground = Math.floorMod(x * 31 + z * 17, 19) == 0
                            ? Blocks.POWDER_SNOW.defaultBlockState()
                            : Blocks.SNOW_BLOCK.defaultBlockState();
                } else {
                    ground = scar > 0.25D ? Blocks.PODZOL.defaultBlockState()
                            : Blocks.GRASS_BLOCK.defaultBlockState();
                }
                level.setBlock(groundPos, ground, 3);
                if (scar > 0.7D && (x + z) % 7 == 0) {
                    level.setBlock(new BlockPos(x, colY + 1, z), Blocks.DEAD_BUSH.defaultBlockState(), 3);
                }
            }
        }
    }

    private static void placeCamp(ServerLevel level, BlockPos center, int surfaceY) {
        BlockPos fire = center.offset(2, 1, 0);
        level.setBlock(fire.below(), Blocks.NETHERRACK.defaultBlockState(), 3);
        level.setBlock(fire, Blocks.FIRE.defaultBlockState(), 3);
        for (int i = 0; i < 3; i++) {
            BlockPos rod = center.offset(-3 + i * 3, 1, -2);
            level.setBlock(rod.below(), Blocks.STONE_BRICKS.defaultBlockState(), 3);
            level.setBlock(rod, Blocks.LIGHTNING_ROD.defaultBlockState()
                    .setValue(net.minecraft.world.level.block.LightningRodBlock.FACING, Direction.UP), 3);
        }
        // Ruined camp: scattered cobweb + cracked stone accents.
        level.setBlock(center.offset(-1, 1, 1), Blocks.COBWEB.defaultBlockState(), 3);
        level.setBlock(center.offset(1, 1, -1), Blocks.CRACKED_STONE_BRICKS.defaultBlockState(), 3);
        level.setBlock(center.offset(0, 1, 2), Blocks.CAMPFIRE.defaultBlockState(), 3);
    }

    private static List<BlockPos> placeChests(ServerLevel level, BlockPos center, int surfaceY, String siteId) {
        BlockPos[] chestPositions = {
                center.offset(-4, 1, 3),
                center.offset(4, 1, 2),
                center.offset(0, 1, -4)
        };
        List<BlockPos> placedChests = new ArrayList<>(chestPositions.length);
        for (int i = 0; i < chestPositions.length; i++) {
            BlockPos pos = chestPositions[i].below().getY() < surfaceY ? chestPositions[i].atY(surfaceY + 1) : chestPositions[i];
            level.setBlock(pos.below(), Blocks.STONE.defaultBlockState(), 3);
            level.setBlock(pos, Blocks.CHEST.defaultBlockState(), 3);
            if (level.getBlockEntity(pos) instanceof RandomizableContainerBlockEntity chest) {
                chest.setLootTable(StormLootData.chestTable(siteId, i), FrozenParams.mapSeed() + i);
            }
            placedChests.add(pos.immutable());
        }
        return List.copyOf(placedChests);
    }

    private static void broadcast(ServerLevel level, Site site, BlockPos center, boolean active) {
        S2CFogStormPayload payload = new S2CFogStormPayload(site.id(), center, site.radius(), active);
        for (ServerPlayer player : level.players()) {
            PacketDistributor.sendToPlayer(player, payload);
        }
        sites = sites.stream()
                .map(s -> s.id().equals(site.id()) ? new Site(s.id(), s.x(), s.z(), s.radius(), s.stage(), s.mobSet(), active) : s)
                .toList();
    }

    /** Re-reads site config from the save-local freeze extract (after {@code refreeze fogstorms}). */
    public static void reloadFromSave() {
        List<Site> previous = sites;
        List<Site> replacement = loadSites(FrozenParams.saveEclipseDir());
        MinecraftServer server = activeServer;
        if (server != null) {
            ServerLevel overworld = server.overworld();
            for (Site old : previous) {
                boolean retained = replacement.stream().anyMatch(next ->
                        next.id().equals(old.id())
                                && next.x() == old.x() && next.z() == old.z()
                                && next.radius() == old.radius());
                if (!retained) {
                    retireSessionSite(overworld, old);
                }
            }
            FogBankMarker.clearAll(overworld);
        }
        sites = replacement;
        if (server != null) {
            restoreFromState(server);
        }
        EclipseMod.LOGGER.info("FogStormSites: loaded {} site(s) from save freeze", sites.size());
    }

    @Nullable
    private static Site findSite(String siteId) {
        for (Site site : sites) {
            if (site.id().equals(siteId)) {
                return site;
            }
        }
        return null;
    }

    private static void restoreFromState(MinecraftServer server) {
        EclipseWorldgenState state = EclipseWorldgenState.get(server);
        sites = sites.stream().map(site -> {
            EclipseWorldgenState.FogSiteState saved = state.fogSiteState(site.id());
            return new Site(site.id(), site.x(), site.z(), site.radius(), site.stage(),
                    site.mobSet(), saved.placed() && saved.active());
        }).toList();
        long active = sites.stream().filter(Site::active).count();
        if (active > 0) {
            EclipseMod.LOGGER.info("FogStormSites: restored {} active storm wall(s) from SavedData", active);
        }
        reconcileTyrantLair(server.overworld());
    }
}
