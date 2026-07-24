package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.CaveEntrances;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import dev.projecteclipse.eclipse.worldgen.structure.dungeon.CollapsedVaultBuilder;
import dev.projecteclipse.eclipse.worldgen.structure.dungeon.DungeonSpawners;
import dev.projecteclipse.eclipse.worldgen.structure.dungeon.UmbralWarrensBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.world.level.storage.loot.BuiltInLootTables;

/**
 * Deterministic underground-site tables of design D7: hashed per stage annulus from the
 * frozen map seed with min-spacing, landmark-clearance and depth checks — the same save
 * always rolls the same sites, and a stage erase + regrow re-enqueues them identically.
 *
 * <p>Per overworld annulus: 1–3 {@code minecraft:mineshaft} starts (y ≈ −20…10), up to
 * {@value #MAX_MONSTER_ROOMS} vanilla-style monster rooms at the shaft bottoms of
 * {@link CaveEntrances} in the band, and — on stage {@value #DUNGEON_STAGE} — the two
 * custom dungeons: the standalone {@link CollapsedVaultBuilder Collapsed Vault} in the
 * annulus and the {@link UmbralWarrensBuilder Umbral Warrens} inside the deep-dark band
 * under the mountain flank ({@code CaveBiomeMap}: y &lt; −32, r ≤ 120 of the mountain).</p>
 *
 * <p>Sites are two-phase: {@link StructureStamper} enqueues the rows returned by
 * {@link #sitesFor} into {@link StructurePendingRegistry} when their stage's terrain
 * completes, and the {@link StructurePendingRegistry.SitePlacer placers} registered by
 * {@link #registerPlacers()} build on trigger/auto-delay. All builders here self-carve,
 * so no SitePrep terraform pass is needed — each placer ends with
 * {@link SitePrep#finishBounds} for heightmaps + relight/resend.</p>
 */
public final class UndergroundSites {
    /** Placer key of the vanilla-mineshaft sites ({@code minecraft:mineshaft} start). */
    public static final String MINESHAFT_ID = "eclipse:mineshaft";
    /** Placer key of the monster-room cluster sites. */
    public static final String MONSTER_ROOM_ID = "eclipse:monster_room";
    /** Placer key of the standalone Collapsed Vault instance. */
    public static final String COLLAPSED_VAULT_ID = "eclipse:collapsed_vault";
    /** Placer key of the Umbral Warrens. */
    public static final String UMBRAL_WARRENS_ID = "eclipse:umbral_warrens";

    /** Stage whose annulus hosts both custom dungeons (D7/D8: stage-3 band). */
    public static final int DUNGEON_STAGE = 3;

    /** Keep-out margin from both edges of the annulus band. */
    private static final int BAND_MARGIN = 24;
    /** Minimum spacing between two accepted underground sites of the same annulus. */
    private static final int MIN_SPACING = 96;
    /** Minimum clearance from any authored landmark center (plus its radius). */
    private static final int LANDMARK_CLEARANCE = 24;
    /** Hashed placement attempts per wanted mineshaft. */
    private static final int ATTEMPTS_PER_SITE = 24;
    /** Monster-room cap per annulus. */
    private static final int MAX_MONSTER_ROOMS = 4;
    /** Salt family for this class's rolls (seed registry: wiring doc P1-W1.6). */
    private static final int SALT_MINESHAFT = 61;
    private static final int SALT_VAULT = 62;
    private static final int SALT_WARRENS = 63;
    private static final int SALT_ROOM = 64;

    private UndergroundSites() {}

    // --- deterministic tables ---

    /**
     * The underground sites of one committed stage (overworld only; empty otherwise).
     * Pure function of the frozen map seed + stage radii — call any time.
     * {@code enqueuedGameTime} of the returned rows is set to {@code gameTime}.
     */
    public static List<PendingSite> sitesFor(DiscProfile profile, int stage, long gameTime) {
        if (profile != DiscProfile.OVERWORLD || stage < 2) {
            return List.of();
        }
        int[] radii = FrozenParams.stageRadii(profile);
        if (stage >= radii.length) {
            return List.of();
        }
        int inner = radii[stage - 1];
        int outer = radii[stage];
        List<PendingSite> sites = new ArrayList<>();
        List<BlockPos> taken = new ArrayList<>();

        // 1–3 mineshafts, area-proportional to the annulus.
        int wanted = Math.max(1, Math.min(3,
                (int) Math.round(Math.PI * (outer * (double) outer - inner * (double) inner) / 70000.0D)));
        for (int i = 0; i < wanted; i++) {
            BlockPos pos = pickInBand(profile, SALT_MINESHAFT, stage, i, inner, outer, taken);
            if (pos == null) {
                continue;
            }
            int y = -20 + (int) (hash01(SALT_MINESHAFT, pos.getX(), stage, pos.getZ()) * 30.0D);
            taken.add(pos);
            sites.add(new PendingSite(MINESHAFT_ID + "/s" + stage + "_" + i, MINESHAFT_ID,
                    profile.name(), new BlockPos(pos.getX(), y, pos.getZ()), stage, 64, gameTime));
        }

        // Monster rooms at the cave-entrance shaft bottoms inside the band.
        int rooms = 0;
        DiscMapData map = DiscMapData.get();
        for (CaveEntrances.Entrance entrance : entrancesInBand(map, inner, outer)) {
            if (rooms >= MAX_MONSTER_ROOMS) {
                break;
            }
            double angle = hash01(SALT_ROOM, entrance.x(), 1, entrance.z()) * Math.PI * 2.0D;
            int off = 7 + (int) (hash01(SALT_ROOM, entrance.x(), 2, entrance.z()) * 6.0D);
            BlockPos anchor = new BlockPos(entrance.x() + (int) Math.round(Math.cos(angle) * off),
                    entrance.bottomY() + 1,
                    entrance.z() + (int) Math.round(Math.sin(angle) * off));
            if (!clearOfLandmarks(DiscProfile.OVERWORLD, anchor.getX(), anchor.getZ(), 32)) {
                continue;
            }
            sites.add(new PendingSite(MONSTER_ROOM_ID + "/s" + stage + "_" + rooms, MONSTER_ROOM_ID,
                    profile.name(), anchor, stage, 12, gameTime));
            rooms++;
        }

        // Both custom dungeons roll on the stage-3 annulus.
        if (stage == DUNGEON_STAGE) {
            BlockPos vault = pickInBand(profile, SALT_VAULT, stage, 0, inner, outer, taken);
            if (vault != null) {
                int y = -6 + (int) (hash01(SALT_VAULT, vault.getX(), 7, vault.getZ()) * 12.0D);
                taken.add(vault);
                sites.add(new PendingSite(COLLAPSED_VAULT_ID + "/s" + stage, COLLAPSED_VAULT_ID,
                        profile.name(), new BlockPos(vault.getX(), y, vault.getZ()), stage, 48, gameTime));
            }
            sites.add(new PendingSite(UMBRAL_WARRENS_ID + "/s" + stage, UMBRAL_WARRENS_ID,
                    profile.name(), warrensAnchor(map), stage, 64, gameTime));
        }
        return List.copyOf(sites);
    }

    /**
     * Deterministic mineshaft rows from every annulus through {@code committedStage}.
     * Used by the disc generator's dynamic {@code /locate structure mineshaft} path;
     * no authored {@code disc_map.json} landmark is required.
     */
    public static List<PendingSite> mineshaftsThroughStage(int committedStage) {
        List<PendingSite> result = new ArrayList<>();
        for (int stage = 2; stage <= committedStage; stage++) {
            for (PendingSite site : sitesFor(DiscProfile.OVERWORLD, stage, 0L)) {
                if (MINESHAFT_ID.equals(site.structureId())) {
                    result.add(site);
                }
            }
        }
        return List.copyOf(result);
    }

    /**
     * The Umbral Warrens anchor: hashed angle on a ring 112 blocks off the mountain
     * center (inside the deep-dark r=120 band, outside the Ancient City piece envelope),
     * at y = −106 (below the deep-dark ceiling −32, above the hull floor). Falls back to
     * a fixed offset from the map origin when the map has no mountain.
     */
    private static BlockPos warrensAnchor(DiscMapData map) {
        DiscMapData.Mountain mountain = map.profile(DiscProfile.OVERWORLD).mountain();
        int cx = mountain != null ? mountain.x() : 0;
        int cz = mountain != null ? mountain.z() : 0;
        double angle = hash01(SALT_WARRENS, cx, 1, cz) * Math.PI * 2.0D;
        return new BlockPos(cx + (int) Math.round(Math.cos(angle) * 112.0D), -106,
                cz + (int) Math.round(Math.sin(angle) * 112.0D));
    }

    /**
     * Area-uniform hashed pick inside the [inner+margin, outer-margin] ring, rejecting
     * candidates near accepted sites, near landmarks or on water-cut columns. Null when
     * every attempt failed (annulus crowded) — the caller simply rolls fewer sites.
     */
    private static BlockPos pickInBand(DiscProfile profile, int salt, int stage, int index,
            int inner, int outer, List<BlockPos> taken) {
        double rMin = inner + BAND_MARGIN;
        double rMax = Math.max(rMin + 8, outer - BAND_MARGIN);
        for (int attempt = 0; attempt < ATTEMPTS_PER_SITE; attempt++) {
            double a = hash01(salt, stage, index * 100 + attempt, 1) * Math.PI * 2.0D;
            double rr = Math.sqrt(rMin * rMin
                    + hash01(salt, stage, index * 100 + attempt, 2) * (rMax * rMax - rMin * rMin));
            int x = (int) Math.round(Math.cos(a) * rr);
            int z = (int) Math.round(Math.sin(a) * rr);
            if (DiscTerrainFunction.surfaceY(profile, x, z) < profile.seaLevel() + 2) {
                continue; // river notch / low cut — a shaft would flood
            }
            if (!clearOfLandmarks(profile, x, z, 0)) {
                continue;
            }
            boolean crowded = false;
            for (BlockPos other : taken) {
                int dx = other.getX() - x;
                int dz = other.getZ() - z;
                if (dx * dx + dz * dz < MIN_SPACING * MIN_SPACING) {
                    crowded = true;
                    break;
                }
            }
            if (!crowded) {
                return new BlockPos(x, 0, z);
            }
        }
        return null;
    }

    /** Whether (x, z) keeps {@code extra} + radius + clearance away from every landmark. */
    private static boolean clearOfLandmarks(DiscProfile profile, int x, int z, int extra) {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(profile)) {
            int keep = landmark.radius() + LANDMARK_CLEARANCE + extra;
            int dx = landmark.x() - x;
            int dz = landmark.z() - z;
            if (dx * dx + dz * dz < keep * keep) {
                return false;
            }
        }
        return true;
    }

    /**
     * Every {@link CaveEntrances} entrance whose anchor lies in the ring [inner, outer −
     * {@value #BAND_MARGIN}]: probes each 96-block cell on an 8-block grid (REACH is 9,
     * so one probe always lands inside the entrance's catch square). Deterministic order
     * (cell scan order), deduped by anchor.
     */
    private static List<CaveEntrances.Entrance> entrancesInBand(DiscMapData map, int inner, int outer) {
        List<CaveEntrances.Entrance> found = new ArrayList<>();
        int cellMin = Math.floorDiv(-outer, CaveEntrances.CELL);
        int cellMax = Math.floorDiv(outer, CaveEntrances.CELL);
        for (int cellX = cellMin; cellX <= cellMax; cellX++) {
            for (int cellZ = cellMin; cellZ <= cellMax; cellZ++) {
                CaveEntrances.Entrance entrance = probeCell(map, cellX, cellZ);
                if (entrance == null) {
                    continue;
                }
                double r = Math.sqrt(entrance.x() * (double) entrance.x()
                        + entrance.z() * (double) entrance.z());
                if (r >= inner && r <= outer - BAND_MARGIN) {
                    found.add(entrance);
                }
            }
        }
        return found;
    }

    /** Probes one entrance cell on the 8-block grid; null when the cell rolled no entrance. */
    private static CaveEntrances.Entrance probeCell(DiscMapData map, int cellX, int cellZ) {
        int baseX = cellX * CaveEntrances.CELL;
        int baseZ = cellZ * CaveEntrances.CELL;
        for (int px = 24; px < 72; px += 8) {
            for (int pz = 24; pz < 72; pz += 8) {
                CaveEntrances.Entrance entrance = CaveEntrances.entranceAt(map, baseX + px, baseZ + pz);
                if (entrance != null) {
                    return entrance;
                }
            }
        }
        return null;
    }

    // --- placers (registered by StructureStamper at server start) ---

    /** Registers the four underground-site placers (idempotent, first wins). */
    public static void registerPlacers() {
        StructurePendingRegistry.registerPlacer(MINESHAFT_ID, UndergroundSites::placeMineshaft);
        StructurePendingRegistry.registerPlacer(MONSTER_ROOM_ID, (level, site) -> {
            BoundingBox bounds = monsterRoom(level, site.anchor());
            SitePrep.finishBounds(level, bounds.minX(), bounds.minZ(), bounds.maxX(), bounds.maxZ());
        });
        StructurePendingRegistry.registerPlacer(COLLAPSED_VAULT_ID, (level, site) -> {
            int surfaceY = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD,
                    site.anchor().getX(), site.anchor().getZ());
            BoundingBox bounds = CollapsedVaultBuilder.buildStandalone(level, site.anchor(), surfaceY);
            SitePrep.finishBounds(level, bounds.minX(), bounds.minZ(), bounds.maxX(), bounds.maxZ());
        });
        StructurePendingRegistry.registerPlacer(UMBRAL_WARRENS_ID, (level, site) -> {
            BoundingBox bounds = UmbralWarrensBuilder.build(level, site.anchor());
            SitePrep.finishBounds(level, bounds.minX(), bounds.minZ(), bounds.maxX(), bounds.maxZ());
        });
    }

    /**
     * Vanilla {@code minecraft:mineshaft} start at the site anchor: generated under the
     * frozen seed, translated so the piece-union center sits on the anchor (mineshafts
     * pick their own spot), placed chunk-by-chunk (corridors carve their own galleries).
     * Falls back to a monster room so the site is never empty.
     */
    private static void placeMineshaft(ServerLevel level, PendingSite site) {
        StructureStart start = StructureStamper.generateVanilla(level,
                ResourceLocation.withDefaultNamespace("mineshaft"), site.anchor());
        if (start == null) {
            EclipseMod.LOGGER.warn("PROCEDURAL FALLBACK: minecraft:mineshaft failed at {}; "
                    + "building a monster room instead", site.anchor().toShortString());
            BoundingBox bounds = monsterRoom(level, site.anchor());
            SitePrep.finishBounds(level, bounds.minX(), bounds.minZ(), bounds.maxX(), bounds.maxZ());
            return;
        }
        BoundingBox union = StructureStamper.pieceUnion(start);
        BlockPos center = union.getCenter();
        int dx = site.anchor().getX() - center.getX();
        int dy = site.anchor().getY() - center.getY();
        int dz = site.anchor().getZ() - center.getZ();
        for (StructurePiece piece : start.getPieces()) {
            piece.move(dx, dy, dz);
        }
        BoundingBox placed = StructureStamper.placeStart(level, start,
                StructureStamper.placementRandom(site.anchor()));
        StructureStamper.registerStart(level, start, placed);
        SitePrep.finishBounds(level, placed.minX(), placed.minZ(), placed.maxX(), placed.maxZ());
        EclipseMod.LOGGER.info("VANILLA GENERATE: placed minecraft:mineshaft for {} at {} (bounds {})",
                site.siteId(), site.anchor().toShortString(), placed);
    }

    /**
     * A vanilla-style monster room: 9×5×9 mossy-cobble shell, hashed rubble floor, one
     * config spawner ({@code dungeons.json} key {@code monster_room}) and 1–2
     * {@code simple_dungeon} chests. Self-carving; returns the shell bounds.
     */
    static BoundingBox monsterRoom(ServerLevel level, BlockPos center) {
        int x = center.getX();
        int y = center.getY();
        int z = center.getZ();
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                boolean wall = Math.abs(dx) == 4 || Math.abs(dz) == 4;
                set(level, x + dx, y - 1, z + dz, roomMix(x + dx, y - 1, z + dz));
                for (int dyy = 0; dyy <= 3; dyy++) {
                    BlockState state = wall || dyy == 3
                            ? roomMix(x + dx, y + dyy, z + dz)
                            : Blocks.CAVE_AIR.defaultBlockState();
                    set(level, x + dx, y + dyy, z + dz, state);
                }
            }
        }
        // Two window slits so cave passers-by can hear the spawner (vanilla flavor).
        set(level, x + 4, y + 1, z, Blocks.CAVE_AIR.defaultBlockState());
        set(level, x - 4, y + 1, z, Blocks.CAVE_AIR.defaultBlockState());
        DungeonSpawners.applyTo(level, new BlockPos(x, y, z), DungeonSpawners.MONSTER_ROOM,
                (int) (hash01(SALT_ROOM, x, y, z) * 3.0D));
        chest(level, new BlockPos(x + 2, y, z - 3), Direction.SOUTH);
        if (hash01(SALT_ROOM, x, y + 7, z) < 0.5D) {
            chest(level, new BlockPos(x - 3, y, z + 2), Direction.EAST);
        }
        return new BoundingBox(x - 4, y - 1, z - 4, x + 4, y + 3, z + 4);
    }

    private static void chest(ServerLevel level, BlockPos pos, Direction facing) {
        set(level, pos.getX(), pos.getY(), pos.getZ(),
                Blocks.CHEST.defaultBlockState().setValue(HorizontalDirectionalBlock.FACING, facing));
        if (level.getBlockEntity(pos) instanceof RandomizableContainerBlockEntity chest) {
            chest.setLootTable(BuiltInLootTables.SIMPLE_DUNGEON, FrozenParams.mapSeed() ^ pos.asLong());
        }
    }

    private static BlockState roomMix(int x, int y, int z) {
        return hash01(SALT_ROOM, x, y ^ 31, z) < 0.45D
                ? Blocks.MOSSY_COBBLESTONE.defaultBlockState()
                : Blocks.COBBLESTONE.defaultBlockState();
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.setBlock(new BlockPos(x, y, z), state,
                net.minecraft.world.level.block.Block.UPDATE_CLIENTS
                        | net.minecraft.world.level.block.Block.UPDATE_KNOWN_SHAPE);
    }

    /** Salted map-seed hash in [0, 1) — the class's only randomness source. */
    private static double hash01(int salt, int a, int b, int c) {
        long h = FrozenParams.mapSeed() ^ (salt * 0x9E3779B97F4A7C15L)
                ^ (a * 341873128712L + b * 986534123L + c * 132897987541L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h >>> 11) & 0xFFFFF) / (double) 0x100000;
    }
}
