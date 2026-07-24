package dev.projecteclipse.eclipse.progression.bestiary;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsService;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.network.bestiary.BestiaryPayloads;
import dev.projecteclipse.eclipse.network.bestiary.S2CBestiaryPayload;
import it.unimi.dsi.fastutil.objects.Object2LongOpenHashMap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * W4-BESTIARY server driver: per-player kill-count-derived mob knowledge
 * ({@link BestiaryTiers} T0–T3, persisted in {@link BestiaryState}).
 *
 * <p><b>Kills</b> ride the {@link EclipseSignals#onMobKilled} lane (analytics owns the
 * single {@code LivingDeathEvent} subscriber and fans out here — P4 §2.0 rule 6, NO new
 * death subscriber). Every {@code eclipse:} mob kill bumps the killer's lifetime count
 * and re-syncs the snapshot; crossing a threshold flags the payload as a tier-up so the
 * client plays the sting + action-bar caption.</p>
 *
 * <p><b>Encounters</b> (T0 → T1 without a kill) come from a slow proximity scan: every
 * {@value #SCAN_INTERVAL_TICKS} ticks (phase-offset from the analytics/unlock sweeps),
 * one {@value #ENCOUNTER_RANGE}-block AABB query per tracked player marks every living
 * {@code eclipse:} mob inside it as encountered. For {@link BestiaryTiers#isSightingProgress}
 * ids the same scan ALSO accumulates the progress count, throttled to one sighting per
 * mob id per {@value #SIGHTING_COOLDOWN_TICKS} ticks (in-memory; a restart forgiving one
 * cooldown is harmless) — that is how the unkillable gazer and the neutral Orin still
 * reach T3 by observation.</p>
 *
 * <p><b>Sync policy</b>: full snapshot to the player on login, plus a re-send on every
 * progress change (payload is ~350 bytes and eclipse-mob events are rare — see
 * {@link S2CBestiaryPayload}). Multiple tier-ups in one scan pass send one payload
 * carrying the highest new tier as the celebrated one.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BestiaryService {
    /** Encounter radius in blocks (spec: "got within 16 blocks"). */
    public static final double ENCOUNTER_RANGE = 16.0D;
    /** Proximity-scan cadence; phase-offset so it never stacks on the 0/13/20/50 sweeps. */
    private static final int SCAN_INTERVAL_TICKS = 40;
    private static final int SCAN_PHASE = 27;
    /** Min ticks between two counted sightings of the same mob id (60 s). */
    private static final int SIGHTING_COOLDOWN_TICKS = 1200;

    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean(false);
    /** Last counted sighting per player per mob id, in server ticks. Reset on server stop. */
    private static final Map<UUID, Object2LongOpenHashMap<String>> LAST_SIGHTING =
            new ConcurrentHashMap<>();

    private BestiaryService() {}

    // --- lifecycle ---

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onMobKilled(BestiaryService::handleMobKilled);
        }
        EclipseMod.LOGGER.info("Bestiary progression active (T2 at {} kills, T3 at {})",
                BestiaryTiers.DEFAULT_T2_COUNT, BestiaryTiers.DEFAULT_T3_COUNT);
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        LAST_SIGHTING.clear();
    }

    // --- kill lane (fired by analytics for tracked killers only) ---

    /** Kill lane consumer: one lifetime count per {@code eclipse:} victim, then re-sync. */
    static void handleMobKilled(ServerPlayer killer, LivingEntity victim) {
        String id = eclipseMobId(victim);
        if (id == null) {
            return;
        }
        BestiaryState state = BestiaryState.get(killer.server);
        UUID uuid = killer.getUUID();
        byte oldTier = state.tier(uuid, id);
        state.addCount(uuid, id);
        byte newTier = state.tier(uuid, id);
        if (newTier > oldTier) {
            sync(killer, id, newTier);
        } else {
            sync(killer, "", BestiaryTiers.TIER_UNSEEN); // keep the kill counter live
        }
    }

    // --- proximity encounter scan ---

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % SCAN_INTERVAL_TICKS != SCAN_PHASE) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (AnalyticsService.isTracked(player)) {
                scanAround(player, server.getTickCount());
            }
        }
    }

    /** One AABB pass: mark encounters, count throttled sightings, sync when changed. */
    private static void scanAround(ServerPlayer player, int serverTick) {
        List<Mob> nearby = player.serverLevel().getEntitiesOfClass(Mob.class,
                player.getBoundingBox().inflate(ENCOUNTER_RANGE), LivingEntity::isAlive);
        if (nearby.isEmpty()) {
            return;
        }
        BestiaryState state = BestiaryState.get(player.server);
        UUID uuid = player.getUUID();
        boolean changed = false;
        String tierUpId = "";
        byte tierUpTier = BestiaryTiers.TIER_UNSEEN;
        for (Mob mob : nearby) {
            String id = eclipseMobId(mob);
            if (id == null) {
                continue;
            }
            byte oldTier = state.tier(uuid, id);
            if (BestiaryTiers.isSightingProgress(id)) {
                if (!tryCountSighting(uuid, id, serverTick)) {
                    continue;
                }
                state.addCount(uuid, id);
                changed = true;
            } else {
                if (!state.markEncountered(uuid, id)) {
                    continue;
                }
                changed = true;
            }
            byte newTier = state.tier(uuid, id);
            if (newTier > oldTier && newTier > tierUpTier) {
                tierUpId = id;
                tierUpTier = newTier;
            }
        }
        if (changed) {
            sync(player, tierUpId, tierUpTier);
        }
    }

    /** Sighting throttle: true when the per-(player, id) cooldown has elapsed. */
    private static boolean tryCountSighting(UUID player, String id, int serverTick) {
        Object2LongOpenHashMap<String> byId =
                LAST_SIGHTING.computeIfAbsent(player, key -> new Object2LongOpenHashMap<>());
        long last = byId.getOrDefault(id, Long.MIN_VALUE);
        if (last != Long.MIN_VALUE && serverTick - last < SIGHTING_COOLDOWN_TICKS) {
            return false;
        }
        byId.put(id, serverTick);
        return true;
    }

    // --- login sync ---

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            sync(player, "", BestiaryTiers.TIER_UNSEEN);
        }
    }

    // --- send helper ---

    /** Full snapshot to one player; non-empty {@code tierUpId} = celebrate that tier-up. */
    private static void sync(ServerPlayer player, String tierUpId, byte tierUpTier) {
        BestiaryState state = BestiaryState.get(player.server);
        UUID uuid = player.getUUID();
        List<S2CBestiaryPayload.Entry> entries = new ArrayList<>();
        for (String id : state.knownIds(uuid)) {
            entries.add(new S2CBestiaryPayload.Entry(id, state.count(uuid, id), state.tier(uuid, id)));
        }
        BestiaryPayloads.sendTo(player, new S2CBestiaryPayload(entries, tierUpId, tierUpTier));
    }

    /** Registry path when the victim is an {@code eclipse:} mob, else {@code null}. */
    private static String eclipseMobId(LivingEntity entity) {
        ResourceLocation key = BuiltInRegistries.ENTITY_TYPE.getKey(entity.getType());
        return EclipseMod.MOD_ID.equals(key.getNamespace()) ? key.getPath() : null;
    }
}
