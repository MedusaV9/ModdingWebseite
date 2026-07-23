package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.EndPortalFrameBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.world.level.levelgen.structure.structures.StrongholdPieces;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The final-day set piece ({@code eclipse:stronghold_emergence}, stage 5): quake sounds for
 * every player, a scripted fissure trench that rips down the mountainside over a few seconds
 * (tick-budgeted column edits, same philosophy as the ring-growth queue), a purple
 * {@code eclipse:altar_beam} Quasar burst at the fissure mouth, and finally
 * {@code minecraft:stronghold} stamped INTO the sealed mountain-core cavity
 * ({@code DiscMapData.Mountain.caveY/caveRadiusXz/caveRadiusY}, pre-carved by the terrain
 * function) with every piece translated so the guaranteed portal room sits centered in the
 * cavity above its lava pool — end portal frames forcibly WITHOUT eyes.
 *
 * <p>If vanilla generation fails after {@value StructureStamper#VANILLA_ATTEMPTS} attempts,
 * a compact procedural portal room ({@link FallbackBuilders#strongholdPortalRoom}) is built
 * in the cavity instead, so the finale never silently misses. A start-up self-check re-runs
 * the emergence if stage 5 is committed but no portal frame exists (e.g. crash mid-sequence).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StrongholdEmergence {
    /** Ticks of pure quake rumble before the fissure starts tearing. */
    private static final int QUAKE_TICKS = 60;
    /** Fissure columns carved per tick (paces the trench to a few dramatic seconds). */
    private static final int CARVE_COLUMNS_PER_TICK = 4;
    /** Ticks between the fissure finishing and the stronghold stamp (beam moment). */
    private static final int BEAM_TICKS = 30;

    @Nullable
    private static Sequence active;

    private StrongholdEmergence() {}

    /** Starts the emergence sequence (no-op while one is already running). */
    public static void begin(ServerLevel level) {
        if (active != null) {
            EclipseMod.LOGGER.warn("Stronghold emergence already running; ignoring re-trigger");
            return;
        }
        DiscMapData.Mountain mountain = DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        if (mountain == null) {
            EclipseMod.LOGGER.error("No mountain in disc_map.json; stamping fallback portal room at spawn axis");
            FallbackBuilders.strongholdPortalRoom(level, new BlockPos(54, 90, -129));
            return;
        }
        active = new Sequence(level, mountain);
        EclipseMod.LOGGER.info("Stronghold emergence started: mountain ({}, {}), cavity y {}..{} (lava to {}), {} fissure columns",
                mountain.x(), mountain.z(), active.cavityFloorY, active.cavityCeilY,
                active.cavityLavaY, active.fissureColumns.size());
        quake(level.getServer());
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        Sequence sequence = active;
        if (sequence == null) {
            return;
        }
        if (sequence.level.getServer() != event.getServer()) {
            active = null;
            return;
        }
        if (sequence.tick()) {
            active = null;
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        active = null;
    }

    /**
     * Self-heal: if the final stage is committed but the cavity holds no portal frame (crash
     * mid-sequence, pre-W5 save raised by hand, …), re-run the emergence on start-up.
     */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        ServerLevel overworld = server.overworld();
        int stage = EclipseWorldState.get(server).getWorldStage(DiscProfile.OVERWORLD);
        if (stage < WorldStageService.maxStage(DiscProfile.OVERWORLD)) {
            return;
        }
        DiscMapData.Mountain mountain = DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        if (mountain == null || hasPortalFrame(overworld, mountain)) {
            return;
        }
        EclipseMod.LOGGER.warn("Final stage committed but no portal room found in the mountain cavity; re-running emergence");
        begin(overworld);
    }

    private static boolean hasPortalFrame(ServerLevel level, DiscMapData.Mountain mountain) {
        level.getChunk(mountain.x() >> 4, mountain.z() >> 4);
        int r = mountain.caveRadiusXz();
        for (BlockPos pos : BlockPos.betweenClosed(
                mountain.x() - r, mountain.caveY() - mountain.caveRadiusY(), mountain.z() - r,
                mountain.x() + r, mountain.caveY() + mountain.caveRadiusY(), mountain.z() + r)) {
            if (level.getBlockState(pos).is(Blocks.END_PORTAL_FRAME)) {
                return true;
            }
        }
        return false;
    }

    /** Deep global quake rumble (thunder pitched down + deepslate cracking for everyone). */
    private static void quake(MinecraftServer server) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.AMBIENT, 1.0F, 0.5F);
            player.playNotifySound(Blocks.DEEPSLATE.defaultBlockState().getSoundType().getBreakSound(),
                    SoundSource.AMBIENT, 1.0F, 0.5F);
        }
    }

    /** One running emergence: QUAKE → CARVE (budgeted fissure) → BEAM → STAMP. */
    private static final class Sequence {
        final ServerLevel level;
        final DiscMapData.Mountain mountain;
        final int cavityFloorY;
        final int cavityCeilY;
        final int cavityLavaY;
        /** Fissure columns ordered from the mountain crown outward: {x, z, carveFloorY}. */
        final ArrayDeque<int[]> fissureColumns = new ArrayDeque<>();
        private int ticks;
        private int phaseTicks;
        private Phase phase = Phase.QUAKE;
        private Vec3 fissureMouth;

        private enum Phase { QUAKE, CARVE, BEAM, STAMP }

        Sequence(ServerLevel level, DiscMapData.Mountain mountain) {
            this.level = level;
            this.mountain = mountain;
            this.cavityFloorY = mountain.caveY() - mountain.caveRadiusY();
            this.cavityCeilY = mountain.caveY() + mountain.caveRadiusY();
            this.cavityLavaY = this.cavityFloorY + 3;
            buildFissure();
            level.getChunk(mountain.x() >> 4, mountain.z() >> 4);
            int mouthY = level.getHeight(Heightmap.Types.MOTION_BLOCKING, mountain.x(), mountain.z());
            this.fissureMouth = new Vec3(mountain.x() + 0.5D, mouthY, mountain.z() + 0.5D);
        }

        /**
         * Precomputes the fissure trench: a winding crack from the mountain crown towards
         * the altar axis (spawn at 0,0). Each column is carved from a rising floor line —
         * {@code caveY + 4} at the crown (breaching the cavity roof) climbing 2 blocks per
         * step until it surfaces on the flank, forming a walkable descent into the cavity.
         */
        private void buildFissure() {
            double length = Math.sqrt((double) mountain.x() * mountain.x()
                    + (double) mountain.z() * mountain.z());
            double ux = -mountain.x() / length;
            double uz = -mountain.z() / length;
            double px = -uz;
            double pz = ux;
            for (int t = 0; t <= 70; t++) {
                int floorY = mountain.caveY() + 4 + t * 2;
                double wind = Math.sin(t * 0.35D) * 2.0D;
                int halfWidth = t < 15 ? 2 : 1;
                for (int w = -halfWidth; w <= halfWidth; w++) {
                    int x = mountain.x() + (int) Math.round(ux * t + px * (w + wind));
                    int z = mountain.z() + (int) Math.round(uz * t + pz * (w + wind));
                    this.fissureColumns.add(new int[] {x, z, floorY});
                }
            }
        }

        /** Advances one tick; returns true when the sequence is done. */
        boolean tick() {
            this.ticks++;
            this.phaseTicks++;
            switch (this.phase) {
                case QUAKE -> {
                    if (this.phaseTicks % 20 == 0) {
                        quake(this.level.getServer());
                    }
                    if (this.phaseTicks >= QUAKE_TICKS) {
                        advance(Phase.CARVE);
                    }
                }
                case CARVE -> {
                    if (carveBudget()) {
                        advance(Phase.BEAM);
                    }
                }
                case BEAM -> {
                    if (this.phaseTicks == 1) {
                        PacketDistributor.sendToPlayersInDimension(this.level,
                                new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, this.fissureMouth));
                        quake(this.level.getServer());
                    }
                    if (this.phaseTicks >= BEAM_TICKS) {
                        advance(Phase.STAMP);
                    }
                }
                case STAMP -> {
                    stampStronghold();
                    return true;
                }
            }
            return false;
        }

        private void advance(Phase next) {
            this.phase = next;
            this.phaseTicks = 0;
        }

        /** Carves up to {@value #CARVE_COLUMNS_PER_TICK} fissure columns; true when empty. */
        private boolean carveBudget() {
            BlockState air = Blocks.AIR.defaultBlockState();
            for (int i = 0; i < CARVE_COLUMNS_PER_TICK && !this.fissureColumns.isEmpty(); i++) {
                int[] column = this.fissureColumns.poll();
                this.level.getChunk(column[0] >> 4, column[1] >> 4);
                int surface = this.level.getHeight(Heightmap.Types.MOTION_BLOCKING, column[0], column[1]);
                if (column[2] >= surface) {
                    continue; // the crack has run out of mountainside
                }
                for (int y = column[2]; y < surface; y++) {
                    this.level.setBlock(new BlockPos(column[0], y, column[1]), air, Block.UPDATE_ALL);
                }
                if (this.ticks % 10 == 0) {
                    this.level.playSound(null, new BlockPos(column[0], surface, column[1]),
                            Blocks.DEEPSLATE.defaultBlockState().getSoundType().getBreakSound(),
                            SoundSource.BLOCKS, 2.0F, 0.6F);
                }
            }
            return this.fissureColumns.isEmpty();
        }

        /**
         * Vanilla {@code minecraft:stronghold} generation (guaranteed portal room), then
         * EVERY piece is translated by one offset so the portal room lands centered in the
         * cavity with its floor above the lava pool. Falls back to the compact procedural
         * portal room when vanilla generation fails.
         */
        private void stampStronghold() {
            BlockPos anchor = new BlockPos(this.mountain.x(), this.mountain.caveY(), this.mountain.z());
            StructureStart start = StructureStamper.generateVanilla(this.level,
                    ResourceLocation.withDefaultNamespace("stronghold"), anchor);
            StrongholdPieces.PortalRoom portalRoom = start == null ? null : findPortalRoom(start);
            if (start == null || portalRoom == null) {
                EclipseMod.LOGGER.warn("PROCEDURAL FALLBACK: minecraft:stronghold produced no portal room; building fallback portal room in cavity");
                FallbackBuilders.strongholdPortalRoom(this.level,
                        new BlockPos(this.mountain.x(), this.cavityLavaY + 1, this.mountain.z()));
                return;
            }
            BoundingBox portalBox = portalRoom.getBoundingBox();
            int dx = this.mountain.x() - (portalBox.minX() + portalBox.maxX()) / 2;
            int dz = this.mountain.z() - (portalBox.minZ() + portalBox.maxZ()) / 2;
            int dy = (this.cavityLavaY + 1) - portalBox.minY();
            for (StructurePiece piece : start.getPieces()) {
                piece.move(dx, dy, dz);
            }
            BoundingBox placed = StructureStamper.placeStart(this.level, start,
                    StructureStamper.placementRandom(anchor));
            BoundingBox movedPortalBox = portalRoom.getBoundingBox();
            int strippedEyes = stripPortalEyes(movedPortalBox);
            StructureStamper.registerStart(this.level, start, placed);
            EclipseMod.LOGGER.info(
                    "VANILLA GENERATE: stronghold stamped into mountain cavity (moved by {},{},{}; bounds {}; portal room {}; {} frame eyes stripped)",
                    dx, dy, dz, placed, movedPortalBox, strippedEyes);
        }

        @Nullable
        private static StrongholdPieces.PortalRoom findPortalRoom(StructureStart start) {
            for (StructurePiece piece : start.getPieces()) {
                if (piece instanceof StrongholdPieces.PortalRoom portalRoom) {
                    return portalRoom;
                }
            }
            return null;
        }

        /** Forces every end portal frame in the portal room to {@code eye=false}. */
        private int stripPortalEyes(BoundingBox portalBox) {
            int stripped = 0;
            for (BlockPos pos : BlockPos.betweenClosed(portalBox.minX(), portalBox.minY(), portalBox.minZ(),
                    portalBox.maxX(), portalBox.maxY(), portalBox.maxZ())) {
                BlockState state = this.level.getBlockState(pos);
                if (state.is(Blocks.END_PORTAL_FRAME) && state.getValue(EndPortalFrameBlock.HAS_EYE)) {
                    this.level.setBlock(pos, state.setValue(EndPortalFrameBlock.HAS_EYE, false), Block.UPDATE_ALL);
                    stripped++;
                }
            }
            return stripped;
        }
    }
}
