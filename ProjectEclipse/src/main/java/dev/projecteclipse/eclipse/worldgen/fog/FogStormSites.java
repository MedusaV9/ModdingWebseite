package dev.projecteclipse.eclipse.worldgen.fog;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CFogStormPayload;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Fog-storm site placement (req 14): storm-scarred groves with loot chests at overworld stage 3.
 * Sites are frozen in {@code worldgen.json → fogstorms} and materialize when the stage-3 terrain
 * sweep completes. Visuals (fog walls, lightning) are P2; storm mobs are P6.
 *
 * <p>W1.6's {@code StructurePendingRegistry} two-phase hook: this class currently places on
 * {@link WorldStageService.StageListener} terrain completion; when W1.6 lands, enqueue via
 * {@code StructurePendingRegistry.enqueue} and move {@link #materializeSite} into the trigger
 * callback (see {@code docs/plans_v3/wiring/P1-W1.9_wiring.md}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogStormSites {
    /** One configured fog-storm site (frozen per save). */
    public record Site(String id, int x, int z, int radius, int stage, List<String> mobSet, boolean active) {}

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();
    private static volatile List<Site> sites = List.of();
    private static final Set<String> placed = Collections.synchronizedSet(new HashSet<>());

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
        if (profile != DiscProfile.OVERWORLD || toStage <= fromStage) {
            return;
        }
        for (Site site : sites) {
            if (site.stage() > toStage || site.stage() <= fromStage) {
                continue;
            }
            if (!placed.add(site.id())) {
                continue;
            }
            materializeSite(level, site);
        }
    }

    /** Builds the storm-scarred grove and broadcasts {@link S2CFogStormPayload}. */
    public static void materializeSite(ServerLevel level, Site site) {
        BlockPos center = surfaceCenter(level, site.x(), site.z());
        int surfaceY = center.getY();
        carveGrove(level, center, site.radius(), surfaceY);
        placeCamp(level, center, surfaceY);
        placeChests(level, center, surfaceY, site.id());
        broadcast(level, site, center, true);
        EclipseMod.LOGGER.info("FogStormSites: materialized {} at {}", site.id(), center);
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
                int colY = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z);
                if (colY <= level.getMinBuildHeight()) {
                    colY = surfaceY;
                }
                double scar = 1.0D - dist / radius;
                BlockState ground = scar > 0.55D ? Blocks.MUD.defaultBlockState()
                        : scar > 0.25D ? Blocks.PODZOL.defaultBlockState()
                        : Blocks.GRASS_BLOCK.defaultBlockState();
                level.setBlock(new BlockPos(x, colY, z), ground, 3);
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

    private static void placeChests(ServerLevel level, BlockPos center, int surfaceY, String siteId) {
        BlockPos[] chestPositions = {
                center.offset(-4, 1, 3),
                center.offset(4, 1, 2),
                center.offset(0, 1, -4)
        };
        for (int i = 0; i < chestPositions.length; i++) {
            BlockPos pos = chestPositions[i].below().getY() < surfaceY ? chestPositions[i].atY(surfaceY + 1) : chestPositions[i];
            level.setBlock(pos.below(), Blocks.STONE.defaultBlockState(), 3);
            level.setBlock(pos, Blocks.CHEST.defaultBlockState(), 3);
            if (level.getBlockEntity(pos) instanceof RandomizableContainerBlockEntity chest) {
                chest.setLootTable(StormLootData.chestTable(siteId, i), FrozenParams.mapSeed() + i);
            }
            // Persist chest index seam: EclipseWorldgenState.fogChests() when W1.5 lands.
        }
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
        placed.clear();
        sites = loadSites(FrozenParams.saveEclipseDir());
        EclipseMod.LOGGER.info("FogStormSites: loaded {} site(s) from save freeze", sites.size());
    }
}
