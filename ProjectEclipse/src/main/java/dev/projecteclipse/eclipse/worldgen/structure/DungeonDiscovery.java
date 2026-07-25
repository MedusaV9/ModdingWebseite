package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.progression.UnlockSync;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * NEWFX-C5 server latch: first-discovery tracking for the deterministic underground
 * sites of {@link UndergroundSites#sitesFor} (mineshafts, monster rooms and the custom
 * dungeons). The {@code LandmarkDiscoveryService} pattern, scoped to site anchors: a
 * cheap 1 Hz poll (phase-offset so it never shares a tick with the other sweeps) checks
 * every non-spectator OVERWORLD player against the anchors of all committed stages; the
 * FIRST player within {@value #DISCOVERY_RADIUS} blocks (3-D — the anchors are buried,
 * so walking the surface overhead never counts as "seen") marks the site discovered.
 *
 * <p><b>Discovery moment.</b> {@link #discover} fires the {@code FxCues#CUE_DUNGEON_FOUND}
 * one-shot at the site anchor (position lane, range {@value #CUE_RANGE} — the entrance
 * exhales a slow bank of cold dust and two eye-glint sparks; the discoverer and any
 * spelunking company share it). Dev force-charting via {@code discover(server, siteId,
 * null)} stays FX-less, the {@code LandmarkDiscoveryService.discover} convention.</p>
 *
 * <p><b>Persistence.</b> Discovered site ids live in their own tiny SavedData
 * ({@code eclipse_dungeon_discovery} in overworld storage — the
 * {@code LandmarkDiscoveryService.Data} pattern; deliberately NOT a new field on the
 * cross-planner shared {@code EclipseWorldState}).</p>
 *
 * <p><b>Sync (the A6 contract — no new payload type).</b> Each discovered site id is
 * exposed as a {@code dungeon:<siteId>} unlock key: {@code UnlockSync#payloadFor} unions
 * {@link #discoveredKeys} into the existing snapshot and a discovery triggers one
 * {@code UnlockSync.broadcastAll} push. The client read side is
 * {@code ClientUnlockCache.isKeyUnlocked("dungeon:...")} — the
 * {@code WorldEventPhotonFxRows.DungeonMawIdle} windowed loop controller keys its idle
 * breath windows off it (the anchors themselves are client-recomputable: {@code sitesFor}
 * is a pure function of the frozen map seed, the {@code BreachAmbience} precedent).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DungeonDiscovery {
    /** Unlock-key namespace of discovered underground sites: {@code dungeon:<site id>}. */
    public static final String KEY_PREFIX = "dungeon:";

    private static final int POLL_INTERVAL_TICKS = 20;
    /** Offset off the Landmark (7) / UnlockSync (13) / ModGate (50→10) sweep ticks. */
    private static final int POLL_PHASE = 11;
    /** 3-D discovery reach around the site anchor — inside the entrance, not above it. */
    private static final double DISCOVERY_RADIUS = 24.0D;
    private static final double DISCOVERY_RADIUS_SQ = DISCOVERY_RADIUS * DISCOVERY_RADIUS;
    /** Maw-breath cue broadcast radius (the discoverer + close company). */
    private static final double CUE_RANGE = 48.0D;

    /** Anchor cache of stages 2..committed (rebuilt when the committed stage changes). */
    private static List<PendingSite> cachedSites = List.of();
    private static int cachedStage = -1;

    private DungeonDiscovery() {}

    /** Per-save persisted set of discovered site ids ({@code LandmarkDiscoveryService.Data} pattern). */
    public static final class Data extends SavedData {
        static final String DATA_NAME = "eclipse_dungeon_discovery";
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

    /** Whether the underground site id has been discovered in this save. */
    public static boolean isDiscovered(MinecraftServer server, String siteId) {
        return data(server).discovered.contains(siteId);
    }

    /** The {@code dungeon:<id>} unlock keys of every discovered site (snapshot copy). */
    public static List<String> discoveredKeys(MinecraftServer server) {
        Data data = data(server);
        List<String> keys = new ArrayList<>(data.discovered.size());
        for (String id : data.discovered) {
            keys.add(KEY_PREFIX + id);
        }
        return keys;
    }

    /**
     * Marks a site discovered (persist + unlock broadcast) and — when {@code fxAnchor}
     * is non-null — fires the maw-breath one-shot there. Returns {@code true} when this
     * call actually changed state. Public so dev commands can force-chart a site
     * (pass {@code null} for an FX-less chart, the landmark convention).
     */
    public static boolean discover(MinecraftServer server, String siteId, @Nullable Vec3 fxAnchor) {
        Data data = data(server);
        if (!data.discovered.add(siteId)) {
            return false;
        }
        data.setDirty();
        EclipseMod.LOGGER.info("Underground site {} discovered — broadcasting unlock snapshot", siteId);
        if (fxAnchor != null) {
            FxPayloads.sendFxEvent(server.overworld(), FxCues.CUE_DUNGEON_FOUND,
                    fxAnchor, 0.0F, 0.0F, CUE_RANGE);
        }
        UnlockSync.broadcastAll(server);
        return true;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % POLL_INTERVAL_TICKS != POLL_PHASE) {
            return;
        }
        List<PendingSite> sites = sitesThroughCommittedStage(server);
        if (sites.isEmpty()) {
            return;
        }
        Data data = data(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator() || player.level().dimension() != Level.OVERWORLD) {
                continue; // sites are overworld-only; spectators must not chart for everyone
            }
            for (PendingSite site : sites) {
                if (data.discovered.contains(site.siteId())) {
                    continue;
                }
                Vec3 anchor = Vec3.atCenterOf(site.anchor());
                if (player.position().distanceToSqr(anchor) <= DISCOVERY_RADIUS_SQ) {
                    discover(server, site.siteId(), anchor);
                }
            }
        }
    }

    /**
     * The deterministic underground sites of every committed overworld stage — pure
     * function of the frozen map seed, so the cache only rebuilds on a stage commit.
     * {@code gameTime} is passed as 0: the rows are consumed as anchor lookups only.
     */
    private static List<PendingSite> sitesThroughCommittedStage(MinecraftServer server) {
        int stage = WorldStageAccess.stage(DiscProfile.OVERWORLD);
        if (stage != cachedStage) {
            List<PendingSite> sites = new ArrayList<>();
            for (int s = 2; s <= stage; s++) {
                sites.addAll(UndergroundSites.sitesFor(DiscProfile.OVERWORLD, s, 0L));
            }
            cachedSites = List.copyOf(sites);
            cachedStage = stage;
            EclipseMod.LOGGER.info("Dungeon discovery anchor table rebuilt: {} sites through stage {}",
                    cachedSites.size(), stage);
        }
        return cachedSites;
    }

    /** The cache pins the last save's stage — drop it with the server. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        cachedSites = List.of();
        cachedStage = -1;
    }
}
