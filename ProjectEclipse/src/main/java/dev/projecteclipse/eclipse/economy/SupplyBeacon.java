package dev.projecteclipse.eclipse.economy;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.fx.S2CSupplyMarkerPayload;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.item.FallingBlockEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The pooled team Supply Beacon (spec §4, {@value ShardEconomy#SUPPLY_BEACON_COST} pooled
 * shards): a falling barrel crate lands {@value #MIN_DISTANCE_BLOCKS}–{@value
 * #MAX_DISTANCE_BLOCKS} blocks from the altar, pre-loaded with the curated
 * {@code eclipse:supply_crate} loot table (via {@link FallingBlockEntity#blockData} —
 * merged into the barrel block entity on landing). Coordinates are NEVER announced — first
 * come, first served.
 *
 * <p><b>Marker protocol (P2 R7 rework — replaces the v1 END_ROD packet flood):</b> the drop
 * sends ONE {@link S2CSupplyMarkerPayload}{@code (add=true)} to the dimension's players; the
 * client ({@code veilfx.SupplyBeamClient}) renders the beam locally from then on, so the
 * server never streams marker particles again (v1 built 13 long-distance END_ROD packets per
 * marker per second and fanned each to every player within 512 blocks — the "supply drop
 * lag" packet half; the other half was the emitter light trap, fixed in
 * {@code assets/eclipse/quasar/emitters/altar_beam.json}). Active markers are re-sent to
 * players that log in or (re-)enter the overworld, so beams survive relogs.</p>
 *
 * <p><b>Lifecycle (fixes "the beam never disappears"):</b> v1 markers expired only by time.
 * Now each marker tracks its crate: once a second, while the crate {@link FallingBlockEntity}
 * is alive its Y is recorded; when the entity is gone the landing column is scanned and the
 * marker binds to the landed barrel's {@link BlockPos} (re-announcing the beam base if the
 * crate fell past the predicted surface, e.g. into a ravine). From then on the first
 * {@link PlayerInteractEvent.RightClickBlock} on the barrel (= looting starts) or the barrel
 * position no longer being a barrel (= broken/moved) removes the marker and broadcasts
 * {@code add=false, fadeTicks=}{@value #REMOVE_FADE_TICKS}, fading the beam out client-side
 * within 2 s. The {@value #MARKER_LIFETIME_TICKS}-tick expiry stays as a backstop only.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SupplyBeacon {
    public static final int MIN_DISTANCE_BLOCKS = 50;
    public static final int MAX_DISTANCE_BLOCKS = 100;

    /** Time-based backstop only — loot/break removal (below) is the normal exit. */
    private static final long MARKER_LIFETIME_TICKS = 20L * 180L;
    /** Lifecycle checks run once a second — plenty for a 2 s fade acceptance window. */
    private static final int MARKER_CHECK_TICKS = 20;
    /** Fresh-drop fade-in; {@code fadeTicks > 0} on an add also tells the client "play the burst FX". */
    private static final int ADD_FADE_TICKS = 10;
    /** Loot/break/expiry fade-out (2 s, P2 R7 acceptance: beam vanishes ≤ 2 s after looting). */
    private static final int REMOVE_FADE_TICKS = 40;
    /**
     * How far below the last observed crate position the landing scan looks for the barrel.
     * The crate is polled every {@value #MARKER_CHECK_TICKS} ticks and falling blocks top out
     * around ~1.6 blocks/tick, so the barrel always rests well within this window.
     */
    private static final int LANDING_SCAN_DEPTH = 80;

    /** One live drop: announced beam base + crate/barrel lifecycle state. Transient — a restart retires markers (the crate persists). */
    private static final class Marker {
        /** Beam base position last announced to clients (initially the predicted surface pos). */
        BlockPos beamPos;
        /** Entity id of the falling crate (only consulted while {@link #barrelPos} is null). */
        final UUID crateId;
        /** Last observed crate Y — upper bound for the landing scan. */
        int lastCrateY;
        /** The landed barrel position; {@code null} while the crate is still airborne. */
        @Nullable
        BlockPos barrelPos;
        final long expiryGameTime;

        Marker(BlockPos beamPos, UUID crateId, int spawnY, long expiryGameTime) {
            this.beamPos = beamPos;
            this.crateId = crateId;
            this.lastCrateY = spawnY;
            this.expiryGameTime = expiryGameTime;
        }
    }

    private static final List<Marker> MARKERS = new ArrayList<>();

    private SupplyBeacon() {}

    /**
     * Drops one supply crate at a random spot {@value #MIN_DISTANCE_BLOCKS}–{@value
     * #MAX_DISTANCE_BLOCKS} blocks from the sanctum altar (world spawn if the sanctum is
     * not built). Returns the surface position — for the LOG ONLY, never for players.
     */
    public static BlockPos drop(MinecraftServer server) {
        ServerLevel level = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        BlockPos center = altarPos != null ? altarPos : level.getSharedSpawnPos();
        RandomSource random = level.getRandom();

        double angle = random.nextDouble() * Math.PI * 2.0D;
        double distance = MIN_DISTANCE_BLOCKS + random.nextDouble() * (MAX_DISTANCE_BLOCKS - MIN_DISTANCE_BLOCKS);
        int x = center.getX() + (int) Math.round(Math.cos(angle) * distance);
        int z = center.getZ() + (int) Math.round(Math.sin(angle) * distance);
        // The target chunk may be unloaded (nobody nearby): getHeight would then return the
        // world floor and the crate would spawn deep underground. Ticket-load it first.
        BudgetedBlockWriter.loadWithTicket(level, x >> 4, z >> 4);
        int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING, x, z);
        int spawnY = Math.min(surfaceY + 60, level.getMaxBuildHeight() - 4);

        FallingBlockEntity crate = FallingBlockEntity.fall(level,
                new BlockPos(x, spawnY, z), Blocks.BARREL.defaultBlockState());
        // Merged into the barrel's block entity NBT when the crate lands (vanilla behavior).
        CompoundTag lootData = new CompoundTag();
        lootData.putString("LootTable", "eclipse:supply_crate");
        lootData.putLong("LootTableSeed", random.nextLong());
        crate.blockData = lootData;

        BlockPos surfacePos = new BlockPos(x, surfaceY, z);
        MARKERS.add(new Marker(surfacePos, crate.getUUID(), spawnY,
                level.getGameTime() + MARKER_LIFETIME_TICKS));
        // ONE payload; the client owns the beam visuals from here (P2 R7 protocol).
        PacketDistributor.sendToPlayersInDimension(level,
                new S2CSupplyMarkerPayload(true, surfacePos, ADD_FADE_TICKS));
        EclipseMod.LOGGER.info("Supply beacon crate dropped {} blocks from {} at {} (coordinates stay secret in-game)",
                (int) distance, center.toShortString(), surfacePos.toShortString());
        return surfacePos;
    }

    /**
     * Once-a-second lifecycle pass per marker: expiry backstop, crate tracking → barrel
     * binding, and broken-barrel detection. All block/entity observations are gated on the
     * chunk actually being loaded — an unloaded drop simply pauses its checks (the beam is a
     * client-side visual; nothing needs the chunk kept alive server-side).
     */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (MARKERS.isEmpty() || server.getTickCount() % MARKER_CHECK_TICKS != 0) {
            return;
        }
        ServerLevel level = server.overworld();
        long now = level.getGameTime();
        Iterator<Marker> iterator = MARKERS.iterator();
        while (iterator.hasNext()) {
            Marker marker = iterator.next();
            if (now >= marker.expiryGameTime) {
                iterator.remove();
                broadcastRemove(level, marker);
                continue;
            }
            if (marker.barrelPos == null) {
                if (!trackFallingCrate(level, marker)) {
                    // Crate confirmed gone without a landed barrel (broke into an item drop).
                    iterator.remove();
                    broadcastRemove(level, marker);
                }
            } else if (level.isLoaded(marker.barrelPos)
                    && !level.getBlockState(marker.barrelPos).is(Blocks.BARREL)) {
                iterator.remove();
                broadcastRemove(level, marker);
            }
        }
    }

    /**
     * Tracks the airborne crate and binds the marker to the landed barrel. Returns
     * {@code false} only when the crate is confirmed gone with no barrel in the landing
     * column (the falling block broke — e.g. landed in a slab gap and popped as an item).
     */
    private static boolean trackFallingCrate(ServerLevel level, Marker marker) {
        if (!level.isLoaded(marker.beamPos)) {
            return true; // chunk (and crate) unloaded — nothing to observe this round
        }
        Entity crate = level.getEntity(marker.crateId);
        if (crate != null && crate.isAlive()) {
            marker.lastCrateY = crate.blockPosition().getY();
            return true; // still falling
        }
        // The entity is gone: find where the barrel landed. Falling blocks have no horizontal
        // motion, so scanning the column below the last observed Y always finds it.
        BlockPos.MutableBlockPos cursor =
                new BlockPos.MutableBlockPos(marker.beamPos.getX(), 0, marker.beamPos.getZ());
        int top = Math.min(marker.lastCrateY + 1, level.getMaxBuildHeight() - 1);
        int bottom = Math.max(top - LANDING_SCAN_DEPTH, level.getMinBuildHeight());
        for (int y = top; y >= bottom; y--) {
            cursor.setY(y);
            if (level.getBlockState(cursor).is(Blocks.BARREL)) {
                BlockPos barrelPos = cursor.immutable();
                marker.barrelPos = barrelPos;
                if (!barrelPos.equals(marker.beamPos)) {
                    // Landed past the predicted surface (ravine/cave mouth): snap the beam
                    // base. fadeTicks=0 = silent reposition/resync, no burst FX replay.
                    marker.beamPos = barrelPos;
                    PacketDistributor.sendToPlayersInDimension(level,
                            new S2CSupplyMarkerPayload(true, barrelPos, 0));
                }
                return true;
            }
        }
        return false;
    }

    /**
     * Loot detection (P2 R7c): the FIRST right-click on a marked barrel — the moment looting
     * starts — retires the marker. The event is never cancelled; the barrel opens normally
     * and only the beam goes away.
     */
    @SubscribeEvent
    static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (MARKERS.isEmpty() || !(event.getLevel() instanceof ServerLevel level)
                || level.dimension() != Level.OVERWORLD) {
            return;
        }
        BlockPos pos = event.getPos();
        Iterator<Marker> iterator = MARKERS.iterator();
        while (iterator.hasNext()) {
            Marker marker = iterator.next();
            // Bound markers match exactly; a not-yet-bound marker (clicked within the 1 s
            // binding latency) matches by column if the clicked block really is a barrel.
            boolean hit = pos.equals(marker.barrelPos)
                    || (marker.barrelPos == null
                            && pos.getX() == marker.beamPos.getX()
                            && pos.getZ() == marker.beamPos.getZ()
                            && level.getBlockState(pos).is(Blocks.BARREL));
            if (hit) {
                iterator.remove();
                broadcastRemove(level, marker);
                return;
            }
        }
    }

    /** Beams survive relogs: re-send every active marker to players entering the overworld. */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        resync(event.getEntity());
    }

    /** The client clears its beams on dimension change; re-sync players returning to the overworld. */
    @SubscribeEvent
    static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        resync(event.getEntity());
    }

    private static void resync(Player player) {
        if (MARKERS.isEmpty() || !(player instanceof ServerPlayer serverPlayer)
                || serverPlayer.level().dimension() != Level.OVERWORLD) {
            return;
        }
        for (Marker marker : MARKERS) {
            // fadeTicks=0 on add = "already existing" — the beam snaps in without burst FX.
            PacketDistributor.sendToPlayer(serverPlayer,
                    new S2CSupplyMarkerPayload(true, marker.beamPos, 0));
        }
    }

    private static void broadcastRemove(ServerLevel level, Marker marker) {
        PacketDistributor.sendToPlayersInDimension(level,
                new S2CSupplyMarkerPayload(false, marker.beamPos, REMOVE_FADE_TICKS));
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        MARKERS.clear();
    }
}
