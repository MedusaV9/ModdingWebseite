package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.wizard.WizardData;
import dev.projecteclipse.eclipse.entity.wizard.WizardService;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.BedBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BedPart;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Orin's mountain observatory (W4-WIZARD; {@code docs/plans_v3/ideas_wave4/
 * IDEA-19_wand.md} §3 "Observatorium"): a small round stone hut with a copper-seamed
 * dome and a brass block-telescope poking out the north slope, stamped ON the highest
 * mountain's summit — the authored {@link DiscMapData.Mountain} center of
 * {@code disc_map.json} (grounding row "highest-peak site selection").
 *
 * <p><b>Placement</b> rides the two-phase {@link StructurePendingRegistry} (design D7)
 * — deliberately NOT another server-start block loop, because the pending registry
 * already provides the rift-tear reveal, SavedData resume, dedup and erase-stage
 * cleanup for free:</p>
 * <ol>
 *   <li>An own {@link WorldStageService.StageListener} (registered once at
 *       {@link ServerAboutToStartEvent}, {@code AltarSanctumBuilder} pattern) enqueues
 *       the single site {@code eclipse:wizard_observatory} when the overworld crosses
 *       stage {@value #MIN_STAGE} — the first stage whose disc fully contains the
 *       mountain ({@code DiscMapDefaults}: "fully inside the stage-3 disc"). A
 *       LOW-priority {@link ServerStartedEvent} catch-up enqueues on worlds that
 *       crossed the stage before this code merged (LOW so the registry's own
 *       server-start load has already run).</li>
 *   <li>The registered {@link StructurePendingRegistry.AsyncSitePlacer} terraforms an
 *       11×11 summit shelf via {@link SitePrep#preparePlateau} (anchored on the LOWEST
 *       deterministic surface Y of the footprint, so the jagged tip is cut down rather
 *       than the hut floated up), then runs one deterministic setBlock pass.</li>
 * </ol>
 *
 * <p><b>Idempotence + versioning</b> ({@code GhostShipBuilder}/{@code ShipVersionData}
 * pattern): {@link ObservatoryVersionData} (own tiny SavedData in the overworld's data
 * storage) stamps {@link ObservatoryVersionData#VERSION_V1} after a successful build;
 * once stamped, re-placements make ZERO block changes. An erase sweep below stage
 * {@value #MIN_STAGE} clears the stamp (and Orin, via
 * {@link WizardService#onObservatoryErased}) so a regrow re-enqueues and rebuilds
 * deterministically — matching the registry's own erase contract.</p>
 *
 * <p>When the build completes it stamps Orin's home position into {@link WizardData}
 * and calls {@link WizardService#ensureWizard} so the hermit appears with his hut.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WizardObservatory {
    /** Frozen site + structure id of the single observatory instance. */
    public static final String SITE_ID = "eclipse:wizard_observatory";
    /** First overworld stage whose disc fully contains the mountain (D8 radii). */
    public static final int MIN_STAGE = 3;
    /** Full XZ extent (terrace ring included) — the pending rift is sized from it. */
    public static final int FOOTPRINT = 11;
    /** Half extent of the stamped footprint (anchor ± this). */
    private static final int HALF = 5;

    /** Hut interior radius² (wall band sits just outside; see {@link #buildAt}). */
    private static final int INTERIOR_R2 = 12;
    private static final int WALL_MIN_R2 = 13;
    private static final int WALL_MAX_R2 = 20;
    private static final int TERRACE_R2 = 29;
    private static final int RAIL_MIN_R2 = 25;

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private WizardObservatory() {}

    // --- lifecycle wiring (own listeners; StructureStamper is never touched) ---

    /** Registers the placer + stage listener (once per JVM). */
    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        StructurePendingRegistry.registerAsyncPlacer(SITE_ID, WizardObservatory::placeSite);
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(WizardObservatory::onStageTerrainComplete);
            EclipseMod.LOGGER.info("WizardObservatory registered as world-stage listener (enqueue at stage {})",
                    MIN_STAGE);
        }
    }

    /**
     * Boot catch-up: worlds already past stage {@value #MIN_STAGE} (grown before this
     * code merged, or a resumed save whose pending row was lost to the legacy JSON era)
     * get their site enqueued now. LOW priority so {@link StructurePendingRegistry}'s
     * own {@code ServerStartedEvent} (NORMAL) has already restored its tables.
     */
    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        int stage = WorldStageService.stage(server, DiscProfile.OVERWORLD);
        if (stage >= MIN_STAGE) {
            enqueueIfNeeded(server.overworld());
        }
    }

    /** Stage listener: grow across {@value #MIN_STAGE} enqueues; erase below it resets. */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile != DiscProfile.OVERWORLD) {
            return;
        }
        if (toStage >= MIN_STAGE && toStage > fromStage) {
            enqueueIfNeeded(level.getServer().overworld());
        } else if (toStage < MIN_STAGE && fromStage >= MIN_STAGE) {
            // The erase sweep removed the mountain annulus (registry cleared the placed
            // record itself); drop the version stamp + the hermit so a regrow rebuilds.
            ObservatoryVersionData version = ObservatoryVersionData.get(level.getServer().overworld());
            if (version.version() != ObservatoryVersionData.VERSION_NONE) {
                version.setVersion(ObservatoryVersionData.VERSION_NONE);
                WizardService.onObservatoryErased(level.getServer().overworld());
                EclipseMod.LOGGER.info("WizardObservatory erased with stage {} -> {}; version stamp cleared",
                        fromStage, toStage);
            }
        }
    }

    // --- enqueue ---

    /** Enqueues the single site once (registry ignores pending/placed duplicates). */
    private static void enqueueIfNeeded(ServerLevel overworld) {
        if (StructurePendingRegistry.wasPlaced(SITE_ID)
                || isBuilt(overworld)) {
            return;
        }
        for (PendingSite pending : StructurePendingRegistry.pending()) {
            if (pending.siteId().equals(SITE_ID)) {
                return;
            }
        }
        BlockPos anchor = summitAnchor();
        if (anchor == null) {
            EclipseMod.LOGGER.warn("WizardObservatory skipped: no mountain authored in disc_map.json");
            return;
        }
        StructurePendingRegistry.enqueue(new PendingSite(SITE_ID, SITE_ID,
                DiscProfile.OVERWORLD.name(), anchor, MIN_STAGE, FOOTPRINT,
                overworld.getGameTime()));
    }

    /**
     * The summit anchor: the authored mountain center, at the LOWEST deterministic
     * surface Y of the 11×11 footprint — SitePrep then cuts the jagged tip down to a
     * shelf instead of stilting the hut on a needle (cut beats fill on a steep cone).
     */
    @Nullable
    private static BlockPos summitAnchor() {
        DiscMapData.Mountain mountain = DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        if (mountain == null) {
            return null;
        }
        int minY = Integer.MAX_VALUE;
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                minY = Math.min(minY, DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD,
                        mountain.x() + dx, mountain.z() + dz));
            }
        }
        return new BlockPos(mountain.x(), minY, mountain.z());
    }

    // --- placement (async SitePrep placer, stronghold-vault pattern) ---

    private static void placeSite(ServerLevel level, PendingSite site, Runnable onComplete,
            java.util.function.Consumer<Throwable> onFailure) {
        ServerLevel overworld = level.getServer().overworld();
        ObservatoryVersionData version = ObservatoryVersionData.get(overworld);
        if (version.version() >= ObservatoryVersionData.VERSION_V1) {
            EclipseMod.LOGGER.info("WizardObservatory already at version {} — placement is a no-op",
                    version.version());
            onComplete.run();
            return;
        }
        BlockPos anchor = site.anchor();
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                anchor.getX() - HALF, anchor.getZ() - HALF,
                anchor.getX() + HALF, anchor.getZ() + HALF, anchor);
        prepared.whenReady(() -> {
            BlockPos surface = new BlockPos(anchor.getX(), prepared.plateauY(), anchor.getZ());
            buildAt(level, surface);
            SitePrep.touchBounds(prepared, anchor.getX() - HALF, anchor.getZ() - HALF,
                    anchor.getX() + HALF, anchor.getZ() + HALF);
            SitePrep.finish(level, prepared);
            version.setVersion(ObservatoryVersionData.VERSION_V1);
            version.setAnchor(surface);
            // One west of center: the telescope tube crosses the center column at head
            // height, so the spawn cell keeps a full 3-block clear column instead.
            BlockPos home = surface.offset(-1, 1, 0);
            WizardData.get(overworld).setHomePos(home);
            WizardService.ensureWizard(overworld);
            EclipseMod.LOGGER.info("WizardObservatory v{} built at {} (Orin home {})",
                    ObservatoryVersionData.VERSION_V1, surface.toShortString(), home.toShortString());
            onComplete.run();
        }, onFailure);
    }

    /** Whether the current-version observatory stands in this save. */
    public static boolean isBuilt(ServerLevel overworld) {
        return ObservatoryVersionData.get(overworld).version() >= ObservatoryVersionData.VERSION_V1;
    }

    /** The stamped hut anchor (dais ground center), or null while unbuilt. */
    @Nullable
    public static BlockPos builtAnchor(ServerLevel overworld) {
        ObservatoryVersionData version = ObservatoryVersionData.get(overworld);
        return version.version() >= ObservatoryVersionData.VERSION_V1 ? version.anchor() : null;
    }

    // --- the deterministic build (pure setBlock loops, GhostShipBuilder school) ---

    /**
     * Stamps the hut around {@code surface} (the plateau's ground level): polished
     * deepslate terrace disc, round stone-brick room (interior r²≤{@value #INTERIOR_R2}),
     * two-block south doorway, glass portholes, copper-seamed deepslate dome, a brass
     * telescope of waxed cut copper climbing from its pedestal out through the dome's
     * north slope to a tinted-glass lens, and the cozy interior — bed, cauldron,
     * bookshelves, lectern + cartography table (his star charts), amethyst study block,
     * lanterns and glowstone floor lamps.
     */
    private static void buildAt(ServerLevel level, BlockPos surface) {
        int y0 = surface.getY();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();

        // Floor + terrace (ground level): deepslate disc, stone-brick room floor,
        // glowstone corner lamps sunk flush into the floor.
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 > TERRACE_R2) {
                    continue;
                }
                BlockState floor;
                if (d2 <= INTERIOR_R2) {
                    boolean cracked = FallbackBuilders.hash01(surface.getX() + dx, y0,
                            surface.getZ() + dz) < 0.15D;
                    floor = (cracked ? Blocks.CRACKED_STONE_BRICKS : Blocks.STONE_BRICKS)
                            .defaultBlockState();
                } else {
                    floor = Blocks.POLISHED_DEEPSLATE.defaultBlockState();
                }
                if (Math.abs(dx) == 2 && Math.abs(dz) == 2) {
                    floor = Blocks.GLOWSTONE.defaultBlockState(); // Warm floor lamps.
                }
                set(level, cursor.set(surface.getX() + dx, y0, surface.getZ() + dz), floor);
            }
        }

        // Interior air column (y0+1..y0+8): a clean room before walls/furniture land.
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                if (dx * dx + dz * dz > INTERIOR_R2) {
                    continue;
                }
                for (int dy = 1; dy <= 8; dy++) {
                    set(level, cursor.set(surface.getX() + dx, y0 + dy, surface.getZ() + dz),
                            Blocks.AIR.defaultBlockState());
                }
            }
        }

        // Walls (y0+1..y0+4): round stone-brick band with deepslate-tile piers, glass
        // portholes N/E/W at eye height, a 2-tall open doorway due south, and glowstone
        // set into the wall crown at the three porthole piers.
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 < WALL_MIN_R2 || d2 > WALL_MAX_R2) {
                    continue;
                }
                boolean pier = (Math.abs(dx) == 4 && dz == 0) || (dx == 0 && Math.abs(dz) == 4)
                        || (Math.abs(dx) == 3 && Math.abs(dz) == 3);
                boolean doorway = dx == 0 && dz == 4;
                boolean porthole = (Math.abs(dx) == 4 && dz == 0) || (dx == 0 && dz == -4);
                for (int dy = 1; dy <= 4; dy++) {
                    BlockState state;
                    if (doorway && dy <= 2) {
                        state = Blocks.AIR.defaultBlockState(); // Open archway, no door.
                    } else if (porthole && (dy == 2 || dy == 3)) {
                        state = Blocks.GLASS.defaultBlockState();
                    } else if (porthole && dy == 4) {
                        state = Blocks.GLOWSTONE.defaultBlockState(); // Wall crown lamps.
                    } else if (pier) {
                        state = Blocks.DEEPSLATE_TILES.defaultBlockState();
                    } else {
                        boolean cracked = FallbackBuilders.hash01(surface.getX() + dx,
                                y0 + dy, surface.getZ() + dz) < 0.12D;
                        state = (cracked ? Blocks.CRACKED_STONE_BRICKS : Blocks.STONE_BRICKS)
                                .defaultBlockState();
                    }
                    set(level, cursor.set(surface.getX() + dx, y0 + dy, surface.getZ() + dz), state);
                }
            }
        }

        // Dome (y0+5..y0+8): shrinking deepslate rings with waxed-copper seams, closing
        // to a copper cap — the observatory silhouette.
        stampDomeRing(level, surface, y0 + 5, 9, WALL_MAX_R2);
        stampDomeRing(level, surface, y0 + 6, 3, 10);
        stampDomeRing(level, surface, y0 + 7, 0, 4);
        set(level, cursor.set(surface.getX(), y0 + 8, surface.getZ()),
                Blocks.WAXED_CUT_COPPER.defaultBlockState());

        // Brass telescope: pedestal + a waxed-copper tube climbing diagonally north,
        // punching through the dome's north slope, tipped with a tinted-glass lens.
        set(level, cursor.set(surface.getX(), y0 + 1, surface.getZ() + 1),
                Blocks.DEEPSLATE_TILES.defaultBlockState());
        int[][] tube = {{0, 2, 1}, {0, 3, 0}, {0, 4, -1}, {0, 5, -2}, {0, 6, -2}};
        for (int[] seg : tube) {
            set(level, cursor.set(surface.getX() + seg[0], y0 + seg[1], surface.getZ() + seg[2]),
                    Blocks.WAXED_CUT_COPPER.defaultBlockState());
        }
        set(level, cursor.set(surface.getX(), y0 + 7, surface.getZ() - 3),
                Blocks.TINTED_GLASS.defaultBlockState()); // The lens, outside the dome.

        // Cozy interior. Bed along the west wall (head north), cauldron, book stacks,
        // the star-chart desk (lectern + cartography table), an amethyst study block
        // and two standing lanterns.
        BlockState bedFoot = Blocks.CYAN_BED.defaultBlockState()
                .setValue(BedBlock.FACING, Direction.NORTH).setValue(BedBlock.PART, BedPart.FOOT);
        BlockState bedHead = Blocks.CYAN_BED.defaultBlockState()
                .setValue(BedBlock.FACING, Direction.NORTH).setValue(BedBlock.PART, BedPart.HEAD);
        set(level, cursor.set(surface.getX() - 2, y0 + 1, surface.getZ() - 1), bedFoot);
        set(level, cursor.set(surface.getX() - 2, y0 + 1, surface.getZ() - 2), bedHead);
        set(level, cursor.set(surface.getX() + 2, y0 + 1, surface.getZ() - 2),
                Blocks.CAULDRON.defaultBlockState());
        set(level, cursor.set(surface.getX() - 3, y0 + 1, surface.getZ()),
                Blocks.BOOKSHELF.defaultBlockState());
        set(level, cursor.set(surface.getX() - 3, y0 + 2, surface.getZ()),
                Blocks.BOOKSHELF.defaultBlockState());
        set(level, cursor.set(surface.getX() + 3, y0 + 1, surface.getZ() + 1),
                Blocks.BOOKSHELF.defaultBlockState());
        set(level, cursor.set(surface.getX() + 3, y0 + 2, surface.getZ() + 1),
                Blocks.BOOKSHELF.defaultBlockState());
        set(level, cursor.set(surface.getX(), y0 + 1, surface.getZ() - 3),
                Blocks.LECTERN.defaultBlockState()
                        .setValue(HorizontalDirectionalBlock.FACING, Direction.SOUTH));
        set(level, cursor.set(surface.getX() + 1, y0 + 1, surface.getZ() - 3),
                Blocks.CARTOGRAPHY_TABLE.defaultBlockState());
        set(level, cursor.set(surface.getX() + 3, y0 + 1, surface.getZ() - 1),
                Blocks.AMETHYST_BLOCK.defaultBlockState());
        set(level, cursor.set(surface.getX() - 1, y0 + 1, surface.getZ() + 2),
                Blocks.LANTERN.defaultBlockState());
        set(level, cursor.set(surface.getX() + 2, y0 + 1, surface.getZ() + 1),
                Blocks.LANTERN.defaultBlockState());

        // Terrace rail: a weathered cobbled-deepslate ring with a south approach gap.
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 < RAIL_MIN_R2 || d2 > TERRACE_R2) {
                    continue;
                }
                if (dz >= 4 && Math.abs(dx) <= 1) {
                    continue; // The approach gap in front of the doorway.
                }
                if (FallbackBuilders.hash01(surface.getX() + dx, y0 + 1, surface.getZ() + dz) < 0.8D) {
                    set(level, cursor.set(surface.getX() + dx, y0 + 1, surface.getZ() + dz),
                            Blocks.COBBLED_DEEPSLATE_WALL.defaultBlockState());
                }
            }
        }
    }

    /** One dome ring: deepslate tiles with a deterministic waxed-copper seam. */
    private static void stampDomeRing(ServerLevel level, BlockPos surface, int y,
            int minR2Exclusive, int maxR2) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 <= minR2Exclusive || d2 > maxR2) {
                    continue;
                }
                boolean seam = Math.floorMod(dx + dz, 3) == 0;
                set(level, cursor.set(surface.getX() + dx, y, surface.getZ() + dz),
                        (seam ? Blocks.WAXED_CUT_COPPER : Blocks.DEEPSLATE_TILES).defaultBlockState());
            }
        }
    }

    /** Silent write; SitePrep.finish() relights + resends the touched chunks after. */
    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
    }

    /** Heightmap probe for dev tooling ({@code /dev wizard tp} lands on the terrace). */
    public static BlockPos surfaceProbe(ServerLevel level, BlockPos anchor) {
        return level.getHeightmapPos(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, anchor);
    }

    // --- version stamp (own tiny SavedData; ShipVersionData pattern) ---

    /**
     * Version stamp of the observatory, persisted as {@code data/
     * eclipse_wizard_observatory.dat} in the OVERWORLD data storage (deliberately not a
     * field on the shared {@code EclipseWorldState} — plans_v3 §2.5 migration rule).
     * {@link #VERSION_NONE} = never built (or erased with its stage);
     * {@link #VERSION_V1} = the current hut. Terminal per version: once stamped, boots
     * and re-placements make ZERO block changes.
     */
    public static final class ObservatoryVersionData extends SavedData {
        public static final String DATA_NAME = "eclipse_wizard_observatory";

        public static final int VERSION_NONE = 0;
        public static final int VERSION_V1 = 1;

        private static final String TAG_VERSION = "version";
        private static final String TAG_ANCHOR = "anchor";

        private int version = VERSION_NONE;
        @Nullable
        private BlockPos anchor;

        public ObservatoryVersionData() {}

        public static ObservatoryVersionData get(ServerLevel overworld) {
            return overworld.getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(ObservatoryVersionData::new, ObservatoryVersionData::load),
                    DATA_NAME);
        }

        public static ObservatoryVersionData load(CompoundTag tag, HolderLookup.Provider registries) {
            ObservatoryVersionData data = new ObservatoryVersionData();
            data.version = tag.getInt(TAG_VERSION);
            if (tag.contains(TAG_ANCHOR)) {
                data.anchor = BlockPos.of(tag.getLong(TAG_ANCHOR));
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putInt(TAG_VERSION, this.version);
            if (this.anchor != null) {
                tag.putLong(TAG_ANCHOR, this.anchor.asLong());
            }
            return tag;
        }

        public int version() {
            return this.version;
        }

        public void setVersion(int version) {
            if (this.version != version) {
                this.version = version;
                setDirty();
            }
        }

        @Nullable
        public BlockPos anchor() {
            return this.anchor;
        }

        public void setAnchor(@Nullable BlockPos anchor) {
            if (!java.util.Objects.equals(this.anchor, anchor)) {
                this.anchor = anchor;
                setDirty();
            }
        }
    }
}
