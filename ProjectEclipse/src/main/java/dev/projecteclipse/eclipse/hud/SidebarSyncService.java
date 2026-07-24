package dev.projecteclipse.eclipse.hud;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.network.S2CSidebarStatePayload;
import dev.projecteclipse.eclipse.progression.goals.QuestEngine;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import dev.projecteclipse.eclipse.skills.SkillConfig;
import dev.projecteclipse.eclipse.skills.SkillCurve;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.AdvancementEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.server.ServerLifecycleHooks;

/**
 * Server-authoritative aggregate feed for sidebar v2.
 *
 * <p>Mutation sources call {@link #markDirty(ServerPlayer)} or
 * {@link #markAllDirty(MinecraftServer)}. Available cross-system signals are bound here at
 * server start; the remaining source-owned seams are documented in the worker wiring handoff.
 * Dirty players are sent as one trailing batch after {@value #DEBOUNCE_TICKS} ticks, so a
 * burst of XP, quest and altar changes never turns into a packet per mutation.</p>
 *
 * <p>The payload contains no player names and no online count. Text-bearing quest and buff
 * detail remains in its dedicated, receiver-localized payload; this aggregate only carries
 * counts and stable buff ids. The registered network channel is protocol {@code "2"} and this
 * service pins the aggregate schema revision below for diagnostics.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SidebarSyncService {
    /** Diagnostic schema revision of the current {@link S2CSidebarStatePayload} field order. */
    public static final int PAYLOAD_SCHEMA_VERSION = 1;
    /** Half-second trailing debounce at 20 TPS. */
    public static final int DEBOUNCE_TICKS = 10;
    private static final int MAX_BUFF_IDS = 32;
    private static final int MAX_BUFF_ID_LENGTH = 128;

    // statics reset on ServerStopped
    private static final DebounceBatch DIRTY = new DebounceBatch(DEBOUNCE_TICKS);
    // statics reset on ServerStopped
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();

    private SidebarSyncService() {}

    /**
     * Small pure debounce primitive used by the live service and gametests. Re-marking an id
     * postpones its due tick, which turns continuous mutation into one trailing send.
     */
    public static final class DebounceBatch {
        private final int delayTicks;
        private final java.util.Map<UUID, Long> dueTicks = new java.util.HashMap<>();

        public DebounceBatch(int delayTicks) {
            this.delayTicks = Math.max(1, delayTicks);
        }

        public void mark(UUID uuid, long nowTick) {
            if (uuid != null) {
                dueTicks.put(uuid, nowTick + delayTicks);
            }
        }

        public void markAll(Collection<UUID> uuids, long nowTick) {
            for (UUID uuid : uuids) {
                mark(uuid, nowTick);
            }
        }

        /** Removes and returns every id whose trailing debounce has elapsed. */
        public Set<UUID> drainDue(long nowTick) {
            if (dueTicks.isEmpty()) {
                return Set.of();
            }
            Set<UUID> due = new HashSet<>();
            var iterator = dueTicks.entrySet().iterator();
            while (iterator.hasNext()) {
                var entry = iterator.next();
                if (entry.getValue() <= nowTick) {
                    due.add(entry.getKey());
                    iterator.remove();
                }
            }
            return due;
        }

        public void remove(UUID uuid) {
            dueTicks.remove(uuid);
        }

        public int size() {
            return dueTicks.size();
        }

        public void clear() {
            dueTicks.clear();
        }
    }

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (!SIGNALS_REGISTERED.compareAndSet(false, true)) {
            return;
        }

        // A quest may be team-scoped, so gameplay signals conservatively dirty every
        // recipient. The debounce still emits at most one aggregate payload per burst.
        EclipseSignals.onNaturalBlockMined((player, state, pos) -> markAllDirty(player.server));
        EclipseSignals.onBlockPlaced((player, state, pos) -> markAllDirty(player.server));
        EclipseSignals.onMobKilled((player, victim) -> markAllDirty(player.server));
        EclipseSignals.onPlayerDeath((player, killer) -> markAllDirty(player.server));
        EclipseSignals.onItemCrafted((player, stack) -> markAllDirty(player.server));
        EclipseSignals.onItemSmelted((player, stack) -> markAllDirty(player.server));
        EclipseSignals.onChunkExplored((player, pos) -> markAllDirty(player.server));
        EclipseSignals.onBiomeVisited((player, biome) -> markAllDirty(player.server));
        EclipseSignals.onAltarDeposit((player, item, count, purpose) -> markAllDirty(player.server));
        EclipseSignals.onQuestCompleted((player, spec, scope) -> markAllDirty(player.server));
        EclipseSignals.onSkillLevelUp((player, level) -> markDirty(player));
        EclipseSignals.onBreed((player, child) -> markAllDirty(player.server));
        EclipseSignals.onTrade(player -> markAllDirty(player.server));
        EclipseSignals.onDayRollover((server, endedDay, newDay, phase) -> {
            if (phase == EclipseSignals.DayRolloverPhase.POST) {
                markAllDirty(server);
            }
        });
        EclipseMod.LOGGER.info("SidebarSyncService registered event-driven source listeners");
    }

    /** Advancement XP does not travel through EclipseSignals, so observe its source event. */
    @SubscribeEvent
    static void onAdvancementEarned(AdvancementEvent.AdvancementEarnEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            markDirty(player);
        }
    }

    /** Login is an immediate baseline send; later changes use the debounce. */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            sendNow(player);
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            DIRTY.remove(player.getUUID());
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        flushDue(event.getServer(), event.getServer().getTickCount());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        DIRTY.clear();
        SIGNALS_REGISTERED.set(false);
    }

    /** Queues one receiver for a coalesced aggregate update. Safe from any server-thread source. */
    public static void markDirty(ServerPlayer player) {
        if (player != null) {
            DIRTY.mark(player.getUUID(), player.server.getTickCount());
        }
    }

    /**
     * UUID overload for source APIs that do not retain a player reference. Offline ids are
     * harmless: the flush drops them and login always sends a fresh baseline.
     */
    public static void markDirty(UUID uuid) {
        MinecraftServer server = ServerLifecycleHooks.getCurrentServer();
        if (server != null) {
            DIRTY.mark(uuid, server.getTickCount());
        }
    }

    /** Queues every online player (global day, altar, team-goal or buff mutation). */
    public static void markAllDirty(MinecraftServer server) {
        if (server == null) {
            return;
        }
        List<UUID> online = server.getPlayerList().getPlayers().stream()
                .map(ServerPlayer::getUUID)
                .toList();
        DIRTY.markAll(online, server.getTickCount());
    }

    /** Immediate one-player send used for login and explicit debug refreshes. */
    public static void sendNow(ServerPlayer player) {
        if (player == null || player.connection == null) {
            return;
        }
        PacketDistributor.sendToPlayer(player, buildPayload(player));
        DIRTY.remove(player.getUUID());
    }

    /** Flush hook exposed for integration tests; production calls it from the post-tick event. */
    public static int flushDue(MinecraftServer server, long nowTick) {
        int sent = 0;
        for (UUID uuid : DIRTY.drainDue(nowTick)) {
            ServerPlayer player = server.getPlayerList().getPlayer(uuid);
            if (player != null && player.connection != null) {
                PacketDistributor.sendToPlayer(player, buildPayload(player));
                sent++;
            }
        }
        return sent;
    }

    /** Builds one receiver-specific, defensively-clamped aggregate payload from live services. */
    public static S2CSidebarStatePayload buildPayload(ServerPlayer player) {
        MinecraftServer server = player.server;
        EclipseWorldState world = EclipseWorldState.get(server);
        RealtimeState realtime = RealtimeState.get(server);

        long totalXp = Math.max(0L, SkillsApi.getTotalXp(server, player.getUUID()));
        SkillCurve.Params curve = SkillConfig.get().curve();
        int skillLevel = SkillCurve.levelForXp(totalXp, curve);
        int xpIntoLevel = SkillCurve.xpIntoLevel(totalXp, skillLevel, curve);
        int xpForLevel = SkillCurve.xpForLevel(skillLevel + 1, curve);

        int[] done = new int[3];
        int[] total = new int[3];
        S2CQuestStatePayload quests = QuestEngine.buildPayload(server, player);
        for (S2CQuestStatePayload.QuestEntry entry : quests.entries()) {
            int kind = entry.kind();
            if (kind < 0 || kind >= total.length) {
                continue;
            }
            total[kind]++;
            if (entry.done()) {
                done[kind]++;
            }
        }

        LinkedHashSet<String> cleanBuffIds = new LinkedHashSet<>();
        for (String id : TimedBuffApi.Holder.get().active(server)) {
            if (id != null) {
                String clean = id.trim();
                if (clean.isEmpty() || clean.length() > MAX_BUFF_ID_LENGTH) {
                    continue;
                }
                cleanBuffIds.add(clean);
                if (cleanBuffIds.size() >= MAX_BUFF_IDS) {
                    break;
                }
            }
        }

        boolean armed = realtime.isArmed();
        return new S2CSidebarStatePayload(
                Math.max(1, world.getDay()),
                armed ? Math.max(0L, realtime.getBoundaryEpochMillis()) : 0L,
                armed && realtime.isPaused(),
                Math.max(0, skillLevel),
                Math.max(0, xpIntoLevel),
                Math.max(1, xpForLevel),
                Math.max(0, world.getAltarLevel()),
                done[0], total[0],
                done[1], total[1],
                done[2], total[2],
                List.copyOf(new ArrayList<>(cleanBuffIds)),
                Math.max(0, ShardEconomy.getShards(player)));
    }
}
