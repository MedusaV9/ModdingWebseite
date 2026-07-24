package dev.projecteclipse.eclipse.progression;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server-side landmark discovery for the handbook map (plans_v5 PLAN-A §A6): a landmark
 * appears on the client map only after some player has PHYSICALLY been near it. This is
 * the anti-spoiler half of the map rework — authored positions exist in
 * {@code disc_map.json} from day one, but the chart only admits what the expedition has
 * actually seen.
 *
 * <p><b>Sweep.</b> A cheap 1 Hz poll (the {@link UnlockSync} precedent; phase-offset so it
 * never lands on the other sweeps' ticks) checks every non-spectator player against the
 * authored landmarks of their dimension's disc profile. Proximity = horizontal distance
 * within {@code landmark.radius() + }{@value #DISCOVERY_MARGIN} blocks; landmarks of
 * not-yet-committed stages are skipped (they physically don't exist yet), and buried
 * sites additionally require the player to actually be underground so walking OVER the
 * mountain does not chart the city sealed inside it.</p>
 *
 * <p><b>Persistence.</b> Discovered ids live in their own tiny SavedData
 * ({@code eclipse_landmark_discovery} in overworld storage — dies with the save;
 * deliberately NOT a new field on the cross-planner shared {@code EclipseWorldState},
 * plans_v3 §1.6 / the {@code SanctumVersionData} pattern).</p>
 *
 * <p><b>Sync (§A6 contract — no new payload type).</b> Each discovered id is exposed as a
 * {@code landmark:<id>} unlock key: {@link UnlockSync#payloadFor} unions
 * {@link #discoveredKeys} into the existing {@link dev.projecteclipse.eclipse.network.gate.S2CUnlockedKeysPayload}
 * snapshot, and a discovery triggers one {@link UnlockSync#broadcastAll} push (the login
 * send is already covered by {@code UnlockSync}'s login hook). The client's
 * {@code ClientUnlockCache.isKeyUnlocked("landmark:...")} is the map tab's read side.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LandmarkDiscoveryService {
    /** Unlock-key namespace of discovered landmarks: {@code landmark:<landmark id>}. */
    public static final String KEY_PREFIX = "landmark:";

    private static final int POLL_INTERVAL_TICKS = 20;
    /** Offset so the poll never shares a tick with UnlockSync (13) / ModGate (50) sweeps. */
    private static final int POLL_PHASE = 7;
    /** Extra reach in blocks beyond the landmark's authored footprint radius. */
    private static final double DISCOVERY_MARGIN = 16.0D;
    /**
     * Sites buried under terrain (the ancient city sits in the mountain's sealed core
     * cavity at y≈−40): horizontal proximity alone would chart them from the surface,
     * so these additionally require the player below this Y before counting as "seen".
     */
    private static final Set<String> UNDERGROUND_IDS = Set.of("eclipse:ancient_city", "eclipse:mineshaft");
    private static final int UNDERGROUND_MAX_Y = 30;

    private LandmarkDiscoveryService() {}

    /** Per-save persisted set of discovered landmark ids. */
    public static final class Data extends SavedData {
        static final String DATA_NAME = "eclipse_landmark_discovery";
        private static final String TAG_DISCOVERED = "discovered";

        private final Set<String> discovered = new LinkedHashSet<>();

        public Data() {}

        static Data load(CompoundTag tag, HolderLookup.Provider registries) {
            Data data = new Data();
            for (Tag entry : tag.getList(TAG_DISCOVERED, Tag.TAG_STRING)) {
                data.discovered.add(entry.getAsString());
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (String id : this.discovered) {
                list.add(StringTag.valueOf(id));
            }
            tag.put(TAG_DISCOVERED, list);
            return tag;
        }
    }

    private static Data data(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, Data.DATA_NAME,
                new SavedData.Factory<>(Data::new, Data::load));
    }

    /** Whether the landmark id has been discovered in this save. */
    public static boolean isDiscovered(MinecraftServer server, String landmarkId) {
        return data(server).discovered.contains(landmarkId);
    }

    /** The {@code landmark:<id>} unlock keys of every discovered landmark (snapshot copy). */
    public static List<String> discoveredKeys(MinecraftServer server) {
        Data data = data(server);
        List<String> keys = new ArrayList<>(data.discovered.size());
        for (String id : data.discovered) {
            keys.add(KEY_PREFIX + id);
        }
        return keys;
    }

    /**
     * Marks a landmark discovered (persist + broadcast). Returns {@code true} when this
     * call actually changed state. Public so dev commands can force-chart a site.
     */
    public static boolean discover(MinecraftServer server, String landmarkId) {
        Data data = data(server);
        if (!data.discovered.add(landmarkId)) {
            return false;
        }
        data.setDirty();
        EclipseMod.LOGGER.info("Landmark {} discovered — broadcasting unlock snapshot", landmarkId);
        UnlockSync.broadcastAll(server);
        return true;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % POLL_INTERVAL_TICKS != POLL_PHASE) {
            return;
        }
        DiscMapData map = DiscMapData.get();
        Data data = data(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator()) {
                continue; // a noclipping spectator must not chart the map for everyone
            }
            DiscProfile profile = WorldStageService.profileOf(player.level().dimension());
            if (profile == null) {
                continue;
            }
            int stage = WorldStageAccess.stage(profile);
            for (DiscMapData.Landmark landmark : map.landmarks(profile)) {
                if (landmark.stage() > stage || data.discovered.contains(landmark.id())) {
                    continue;
                }
                if (UNDERGROUND_IDS.contains(landmark.id()) && player.getY() > UNDERGROUND_MAX_Y) {
                    continue;
                }
                double dx = player.getX() - landmark.x();
                double dz = player.getZ() - landmark.z();
                double reach = landmark.radius() + DISCOVERY_MARGIN;
                if (dx * dx + dz * dz <= reach * reach) {
                    discover(server, landmark.id());
                }
            }
        }
    }
}
