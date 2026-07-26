package dev.projecteclipse.eclipse.minigames;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.network.chat.Style;
import net.minecraft.network.protocol.game.ClientboundSetSubtitleTextPacket;
import net.minecraft.network.protocol.game.ClientboundSetTitleTextPacket;
import net.minecraft.network.protocol.game.ClientboundSetTitlesAnimationPacket;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The portal minigame event state machine (W4-MINIGAMES) — a deliberate mirror of the
 * proven {@code XboxEventService} architecture: dev-triggered lifecycle
 * {@code IDLE → OPEN → RUNNING → CLOSING → IDLE} persisted in {@link MinigameState},
 * portal collision entries, the extendable window timer with a bossbar countdown,
 * protected deaths and ticket-based inventory safety.
 *
 * <p><b>Death protection mechanics</b> (identical to xbox): the {@link LivingDeathEvent}
 * intercept runs at {@link EventPriority#HIGHEST} and CANCELS player deaths inside
 * minigame dimensions. Cancelled events are not delivered to default subscribers, so the
 * lives pipeline ({@code lives.LifecycleEvents}: snapshot, life loss, kill transfer,
 * grave, ban) never runs and {@code LivingDropsEvent} never fires — inventory, Eclipse
 * lives and hearts stay untouched. Unlike xbox, a protected minigame death does NOT exit
 * the player: they respawn inside (scattered arena respawn with a brief spawn shield /
 * last race checkpoint).</p>
 *
 * <p><b>Ticket safety</b>: every entrant gets a {@link MinigameState.Ticket} (anchor +
 * game mode + health/food + full inventory NBT) BEFORE anything else happens, and the
 * ticket is force-flushed to disk before the real inventory is cleared (FFIX-B C3).
 * Every exit path — voluntary leave, timeout, dev stop, crash rescue at login, and any
 * foreign teleport out of a minigame dimension (FFIX-B H1) — restores the ticket and
 * only then deletes it. Podium/participation payouts ride the persisted
 * {@link MinigameState.PendingPayout} ledger (queue by stable instance-scoped id, claim
 * before give), so offline winners are paid at next login and crash replays cannot
 * double-pay (FFIX-B H2–H4).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MinigameService {

    private static final long WARN_5M_MILLIS = 5L * 60L * 1000L;
    private static final long WARN_1M_MILLIS = 60L * 1000L;
    private static final long LEAVE_CONFIRM_WINDOW_MILLIS = 15_000L;
    private static final long BOUNCE_MESSAGE_THROTTLE_MILLIS = 3_000L;
    private static final long GRACEFUL_STOP_MILLIS = 10_000L;
    /** NEWFX-C3a: gate fanfare/collapse cue broadcast radius around the portal frame. */
    private static final double GATE_CUE_RANGE = 96.0D;

    // ---- transient per-run state (cleared on ServerStoppedEvent; SavedData is per-save) ----
    @Nullable
    private static ServerBossEvent bossBar;
    private static final Map<UUID, Long> PENDING_LEAVE_CONFIRMS = new HashMap<>();
    private static final Map<UUID, Long> LAST_BOUNCE_MESSAGE = new HashMap<>();
    /**
     * Reentrancy guard for {@link #onPlayerChangedDimension}: players currently being
     * teleported OUT by {@link #exitToTicket} itself (their ticket is restored right
     * after the teleport — the watchdog must not double-restore mid-flight). FFIX-B H1.
     */
    private static final Set<UUID> EXIT_IN_PROGRESS = new HashSet<>();
    /**
     * The leave-flow fix: the ticket anchor is captured the moment the player touches the
     * portal volume, so {@link #exitToTicket} lands them back INSIDE the collision box and
     * the next 10 t portal pass would swallow them again (minigames have no lockout to
     * mask it). Players in this set must first STEP OUT of the portal volume once before
     * the portal may take them again; cleared as soon as they stand clear.
     */
    private static final Set<UUID> AWAITING_PORTAL_CLEAR = new HashSet<>();
    private static long lastSeenRemainingMillis = Long.MAX_VALUE;
    private static long totalWindowMillisHint;
    /** Course generation finished for the current instance (entries bounce until true). */
    private static volatile boolean courseReady;

    private MinigameService() {}

    /** Exit paths — pick the right player-facing message. Deaths never exit (respawn inside). */
    public enum ExitReason { LEFT, TIME_UP, CLOSED }

    /** Common-setup hookups (MOD bus): config bootstrap. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            MinigameConfig.bootstrap();
        }
    }

    // ================================================================== lifecycle

    /** Crash resume: a persisted event whose window passed closes on boot. */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        resumeOnBoot(event.getServer());
    }

    /** Boot-resume logic, callable from gametests. */
    public static void resumeOnBoot(MinecraftServer server) {
        MinigameState state = MinigameState.get(server);
        long now = System.currentTimeMillis();
        switch (state.phase()) {
            case OPEN, RUNNING -> {
                if (state.endsAtEpochMillis() <= now) {
                    EclipseMod.LOGGER.info("Minigame event {} expired while server was down — closing now",
                            state.gameId());
                    beginClosing(server, state, ExitReason.TIME_UP);
                } else {
                    totalWindowMillisHint = Math.max(state.endsAtEpochMillis() - now,
                            MinigameConfig.get().defaultMinutes() * 60_000L);
                    // Rebuild the current course (idempotent: same persisted seed) so a
                    // crash mid-build can never leave a half-formed platform.
                    startCourseBuild(server, state, state.gameId());
                    EclipseMod.LOGGER.info("Minigame event {} resumes: {} remaining",
                            state.gameId(), mmss(state.endsAtEpochMillis() - now));
                }
            }
            case CLOSING -> {
                EclipseMod.LOGGER.info("Minigame event {} was mid-CLOSING at shutdown — finishing close",
                        state.gameId());
                beginClosing(server, state, ExitReason.CLOSED);
            }
            case IDLE -> { /* nothing */ }
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        bossBar = null;
        PENDING_LEAVE_CONFIRMS.clear();
        LAST_BOUNCE_MESSAGE.clear();
        EXIT_IN_PROGRESS.clear();
        AWAITING_PORTAL_CLEAR.clear();
        lastSeenRemainingMillis = Long.MAX_VALUE;
        totalWindowMillisHint = 0L;
        courseReady = false;
        ArenaGame.resetTransient();
        ElytraRace.resetTransient();
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % 10 != 0) {
            return;
        }
        MinigameState state = MinigameState.get(server);
        if (!state.isActive()) {
            return;
        }

        long now = System.currentTimeMillis();
        long remaining = state.endsAtEpochMillis() - now;
        if (remaining <= 0L) {
            beginClosing(server, state, ExitReason.TIME_UP);
            return;
        }

        checkWarnings(server, state, remaining);
        tickPortal(server, state);
        updateBossBar(server, state, remaining);

        if (state.phase() == MinigameState.Phase.RUNNING && courseReady) {
            List<ServerPlayer> inside = insidePlayers(server, state);
            if (MinigameDimensions.GAME_ARENA.equals(state.gameId())) {
                ArenaGame.tickRounds(server, state, inside);
            } else if (MinigameDimensions.GAME_RACE.equals(state.gameId())) {
                ElytraRace.tick(server, state, inside);
            }
        }
        lastSeenRemainingMillis = remaining;
    }

    // ================================================================== start / stop / mutate

    /** Outcome of {@link #start}: {@code started=false} → {@code message} is the error. */
    public record StartResult(boolean started, @Nullable Component message) {}

    /**
     * Starts the event: validates the game id and loaded dimension, opens the instance
     * (bumping the seed), kicks off the budgeted course build (clear-old-then-build-new)
     * and spawns the portal near spawn. When no portal spot is found the event still
     * OPENs and the result carries a warning — the operator places the portal manually
     * via {@code /dev minigame portal here}.
     */
    public static StartResult start(MinecraftServer server, String gameId, int minutes, String operatorName) {
        MinigameState state = MinigameState.get(server);
        if (state.isActive()) {
            return new StartResult(false, Component.translatable("dev.eclipse.minigame.start.already",
                    state.gameId(), mmss(state.endsAtEpochMillis() - System.currentTimeMillis())));
        }
        ResourceKey<Level> dimension = MinigameDimensions.byGameId(gameId);
        if (dimension == null) {
            return new StartResult(false, Component.translatable("dev.eclipse.minigame.start.unknown_game",
                    gameId, String.join(", ", List.of(
                            MinigameDimensions.GAME_ARENA, MinigameDimensions.GAME_RACE))));
        }
        ServerLevel level = server.getLevel(dimension);
        if (level == null) {
            return new StartResult(false, Component.translatable("dev.eclipse.minigame.start.no_level",
                    dimension.location().toString()));
        }

        int effectiveMinutes = minutes > 0 ? minutes : MinigameConfig.get().defaultMinutes();
        long now = System.currentTimeMillis();
        // FFIX-B (H2): defense in depth — beginClosing already settles, but saves written
        // before this fix may still carry unsettled participants of the PREVIOUS instance.
        settleParticipation(state);
        state.beginInstance(gameId, now + effectiveMinutes * 60_000L);
        totalWindowMillisHint = effectiveMinutes * 60_000L;
        lastSeenRemainingMillis = Long.MAX_VALUE;

        startCourseBuild(server, state, gameId);

        broadcast(server, Component.translatable("eclipse.minigame.announce.start",
                gameName(gameId), effectiveMinutes).withStyle(ChatFormatting.GREEN));

        ServerLevel overworld = server.overworld();
        BlockPos spot = MinigamePortal.findSpotNearSpawn(overworld);
        if (spot != null) {
            MinigamePortal.place(overworld, spot, state);
            // NEWFX-C3a (b=0): the gate fanfare — the fresh portal frame ignites
            // edge-running light that leaps off as confetti-sparks (range 96, the
            // spawn-area audience). The collapse pair fires in beginClosing.
            sendGateCue(overworld, spot, 0.0F);
            broadcast(server, portalHint(spot));
        } else {
            EclipseMod.LOGGER.warn("Minigame event {}: no portal spot within {}..{} blocks of spawn",
                    gameId, MinigameConfig.get().portalSearchMinRadius(),
                    MinigameConfig.get().portalSearchMaxRadius());
        }
        EclipseMod.LOGGER.info("Minigame event started by {}: game={}, minutes={}, seed={}",
                operatorName, gameId, effectiveMinutes, state.openCount());
        return new StartResult(true, spot == null
                ? Component.translatable("dev.eclipse.minigame.portal.nospot",
                        MinigameConfig.get().portalSearchMinRadius(),
                        MinigameConfig.get().portalSearchMaxRadius())
                : null);
    }

    /** {@code /dev minigame portal here|remove} backing (the xbox portal-here pattern). */
    @Nullable
    public static Component portalHere(MinecraftServer server, ServerPlayer operator) {
        if (MinigameDimensions.isInMinigameDimension(operator)) {
            return Component.translatable("dev.eclipse.minigame.portal.in_minigame_dim");
        }
        MinigameState state = MinigameState.get(server);
        if (!state.isActive()) {
            return Component.translatable("dev.eclipse.minigame.stop.idle");
        }
        removePortal(server, state);
        ServerLevel level = (ServerLevel) operator.level();
        BlockPos base = operator.blockPosition();
        MinigamePortal.place(level, base, state);
        broadcast(server, portalHint(base));
        return null;
    }

    @Nullable
    public static Component portalRemove(MinecraftServer server) {
        MinigameState state = MinigameState.get(server);
        if (state.portalPos() == null) {
            return Component.translatable("dev.eclipse.minigame.portal.none");
        }
        removePortal(server, state);
        return null;
    }

    /** Graceful stop = short grace window; {@code immediate} closes this tick. */
    @Nullable
    public static Component stop(MinecraftServer server, boolean immediate) {
        MinigameState state = MinigameState.get(server);
        if (!state.isActive()) {
            return Component.translatable("dev.eclipse.minigame.stop.idle");
        }
        if (immediate) {
            beginClosing(server, state, ExitReason.CLOSED);
            return null;
        }
        long now = System.currentTimeMillis();
        long graceEnd = now + GRACEFUL_STOP_MILLIS;
        if (state.endsAtEpochMillis() > graceEnd) {
            state.setEndsAtEpochMillis(graceEnd);
            broadcast(server, Component.translatable("eclipse.minigame.announce.stopping",
                    gameName(state.gameId()), GRACEFUL_STOP_MILLIS / 1000L)
                    .withStyle(ChatFormatting.YELLOW));
        }
        return null;
    }

    /**
     * {@code /dev minigame time add|sub|set} — mutates {@code endsAt}, clamped ≥ now.
     * Returns the success feedback line, or {@code null} when no event is running.
     */
    @Nullable
    public static Component timeMutate(MinecraftServer server, char mode, long durationMillis) {
        MinigameState state = MinigameState.get(server);
        if (!state.isActive()) {
            return null;
        }
        long now = System.currentTimeMillis();
        long oldRemaining = Math.max(0L, state.endsAtEpochMillis() - now);
        long newEndsAt = switch (mode) {
            case '+' -> state.endsAtEpochMillis() + durationMillis;
            case '-' -> state.endsAtEpochMillis() - durationMillis;
            default -> now + durationMillis;
        };
        state.setEndsAtEpochMillis(Math.max(now, newEndsAt));
        long newRemaining = Math.max(0L, state.endsAtEpochMillis() - now);
        totalWindowMillisHint = Math.max(totalWindowMillisHint, newRemaining);
        lastSeenRemainingMillis = Long.MAX_VALUE; // re-arm T-5/T-1 warnings against the new window
        broadcastInside(server, state, Component.translatable("eclipse.minigame.announce.time_changed",
                mmss(newRemaining)).withStyle(ChatFormatting.YELLOW));
        return Component.translatable("dev.eclipse.minigame.time.changed",
                mmss(newRemaining), mmss(oldRemaining));
    }

    // ================================================================== course build

    /**
     * Budgeted clear-then-build: clears the PREVIOUS layout of this dimension (recomputed
     * from the persisted seed) when it differs, then writes the new one. {@code
     * courseReady} gates portal entries until the build lands. Crash-safe: seeds persist,
     * jobs are idempotent block writes.
     */
    private static void startCourseBuild(MinecraftServer server, MinigameState state, String gameId) {
        ServerLevel level = server.getLevel(MinigameDimensions.byGameId(gameId));
        if (level == null) {
            return;
        }
        courseReady = false;
        int newSeed = state.openCount();
        int oldSeed = state.builtSeed(gameId);
        Runnable build = () -> {
            state.setBuiltSeed(gameId, newSeed);
            CourseBlocks.enqueueBuild(level, layoutFor(gameId, newSeed), () -> {
                courseReady = true;
                EclipseMod.LOGGER.info("Minigame course ready: game={}, seed={}", gameId, newSeed);
            });
        };
        if (oldSeed >= 0 && oldSeed != newSeed) {
            CourseBlocks.enqueueClear(level, layoutFor(gameId, oldSeed), build);
        } else {
            build.run();
        }
    }

    private static List<CourseBlocks.Placement> layoutFor(String gameId, int seed) {
        return MinigameDimensions.GAME_RACE.equals(gameId)
                ? ElytraRace.courseFor(seed).blocks()
                : ArenaGame.layout(seed);
    }

    // ================================================================== closing

    /**
     * CLOSING sequence: settle a live arena round (anonymized final podium) / announce the
     * race summary, exit everyone through their tickets, despawn the portal, sweep leftover
     * non-player entities from the course, return to IDLE. Safe to re-run after a crash.
     */
    private static void beginClosing(MinecraftServer server, MinigameState state, ExitReason reason) {
        state.setPhase(MinigameState.Phase.CLOSING);
        // FFIX-B (H2): queue every participant's entitlement — online or not — before any
        // of this instance's bookkeeping can be discarded by a later beginInstance.
        settleParticipation(state);
        String gameId = state.gameId();
        broadcast(server, Component.translatable("eclipse.minigame.announce.end", gameName(gameId))
                .withStyle(ChatFormatting.GREEN));

        List<ServerPlayer> inside = insidePlayers(server, state);
        if (MinigameDimensions.GAME_ARENA.equals(gameId)) {
            ArenaGame.endRound(server, state, inside, "eclipse.minigame.arena.round_final");
        } else if (MinigameDimensions.GAME_RACE.equals(gameId)) {
            ElytraRace.announceClosingSummary(server, state);
        }

        for (ServerPlayer player : inside) {
            exitToTicket(server, state, player, reason);
        }

        // NEWFX-C3a (b=1): the collapse — the frame light unwinds and implodes to one
        // point. Fired at the recorded portal spot BEFORE the frame despawns so the
        // implosion reads as the portal's own exit; a portal-less event stays silent.
        BlockPos closingPortal = state.portalPos();
        ResourceKey<Level> closingDim = state.portalDimension();
        if (closingPortal != null && closingDim != null) {
            ServerLevel portalLevel = server.getLevel(closingDim);
            if (portalLevel != null) {
                sendGateCue(portalLevel, closingPortal, 1.0F);
            }
        }
        removePortal(server, state);
        cleanupCourseEntities(server, gameId);

        removeBossBar();
        PENDING_LEAVE_CONFIRMS.clear();
        LAST_BOUNCE_MESSAGE.clear();
        lastSeenRemainingMillis = Long.MAX_VALUE;
        courseReady = false;
        ArenaGame.resetTransient();
        state.setPhase(MinigameState.Phase.IDLE);
        EclipseMod.LOGGER.info("Minigame event {} closed (seed {}, {} participants)",
                gameId, state.openCount(), state.participantsSnapshot().size());
    }

    /** Discards leftover non-player entities (items, arrows, rockets) from the course area. */
    private static void cleanupCourseEntities(MinecraftServer server, String gameId) {
        ResourceKey<Level> dimension = MinigameDimensions.byGameId(gameId);
        ServerLevel level = dimension == null ? null : server.getLevel(dimension);
        if (level == null) {
            return;
        }
        var bounds = MinigameDimensions.GAME_RACE.equals(gameId)
                ? ElytraRace.bounds() : ArenaGame.bounds();
        List<Entity> leftovers = level.getEntities((Entity) null, bounds,
                entity -> !(entity instanceof ServerPlayer));
        leftovers.forEach(Entity::discard);
        EclipseMod.LOGGER.info("Minigame close swept {} leftover entities from {}",
                leftovers.size(), level.dimension().location());
    }

    /**
     * NEWFX-C3a sender: the {@code CUE_MINIGAME_GATE} fanfare ({@code b} = 0) / collapse
     * ({@code b} = 1) at the portal frame center ({@code MinigamePortal} frames are 3×4
     * on the base block — mid-frame is base + 2). Range {@value #GATE_CUE_RANGE}: the
     * spawn-plaza audience the portal hint already addresses.
     */
    private static void sendGateCue(ServerLevel level, BlockPos portalBase, float b) {
        dev.projecteclipse.eclipse.network.fx.FxPayloads.sendFxEvent(level,
                dev.projecteclipse.eclipse.network.fx.FxCues.CUE_MINIGAME_GATE,
                new net.minecraft.world.phys.Vec3(portalBase.getX() + 0.5D,
                        portalBase.getY() + 2.0D, portalBase.getZ() + 0.5D),
                0.0F, b, GATE_CUE_RANGE);
    }

    private static void removePortal(MinecraftServer server, MinigameState state) {
        BlockPos portalPos = state.portalPos();
        ResourceKey<Level> portalDim = state.portalDimension();
        if (portalPos == null || portalDim == null) {
            return;
        }
        ServerLevel level = server.getLevel(portalDim);
        if (level != null) {
            MinigamePortal.remove(level, portalPos, state);
        } else {
            state.setPortal(null, null);
        }
    }

    // ================================================================== portal & entries

    private static void tickPortal(MinecraftServer server, MinigameState state) {
        BlockPos portalPos = state.portalPos();
        ResourceKey<Level> portalDim = state.portalDimension();
        if (portalPos == null || portalDim == null) {
            return;
        }
        ServerLevel level = server.getLevel(portalDim);
        if (level == null) {
            return;
        }
        MinigamePortal.ambientTick(level, portalPos, level.getGameTime());
        var box = MinigamePortal.collisionBox(portalPos);
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (player.isSpectator() || !player.isAlive()) {
                continue;
            }
            boolean inVolume = box.intersects(player.getBoundingBox());
            if (AWAITING_PORTAL_CLEAR.contains(player.getUUID())) {
                if (!inVolume) {
                    AWAITING_PORTAL_CLEAR.remove(player.getUUID()); // stepped clear — re-armed
                }
                continue; // fresh exit still standing in the frame: never re-swallow
            }
            if (inVolume) {
                tryEnter(server, state, player);
            }
        }
    }

    private static void tryEnter(MinecraftServer server, MinigameState state, ServerPlayer player) {
        if (!state.isActive()) {
            return;
        }
        if (!courseReady) {
            UUID uuid = player.getUUID();
            long now = System.currentTimeMillis();
            long last = LAST_BOUNCE_MESSAGE.getOrDefault(uuid, 0L);
            if (now - last >= BOUNCE_MESSAGE_THROTTLE_MILLIS) {
                LAST_BOUNCE_MESSAGE.put(uuid, now);
                player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.enter.not_ready")
                        .withStyle(ChatFormatting.YELLOW), false);
                player.playNotifySound(SoundEvents.VILLAGER_NO, SoundSource.PLAYERS, 0.8F, 1.0F);
            }
            return;
        }
        enter(server, state, player);
    }

    /**
     * Entry sequence: TICKET FIRST (anchor + mode + health/food + full inventory), then
     * teleport, adventure mode, kit, title. There are no lockouts — leaving and
     * re-entering is always allowed while the event is open.
     */
    private static void enter(MinecraftServer server, MinigameState state, ServerPlayer player) {
        String gameId = state.gameId();
        ResourceKey<Level> dimension = MinigameDimensions.byGameId(gameId);
        ServerLevel target = dimension == null ? null : server.getLevel(dimension);
        if (target == null) {
            return;
        }

        state.putTicket(player.getUUID(), MinigameState.captureTicket(player));
        state.addParticipant(player.getUUID());
        if (state.phase() == MinigameState.Phase.OPEN) {
            state.setPhase(MinigameState.Phase.RUNNING);
        }
        // FFIX-B (FINAL-SAT-SOL C3 / POLISH-SOL-08): the ticket must be ON DISK before
        // the player's real inventory is destroyed below. setDirty() alone only schedules
        // a save — player NBT and SavedData are separate persistence streams, so a crash
        // could otherwise persist the kit-equipped player with no ticket to rescue them.
        EclipseSavedData.flushOverworld(server);

        if (MinigameDimensions.GAME_RACE.equals(gameId)) {
            ElytraRace.placeIntoRace(target, state, player);
        } else {
            // Scattered join (never the exact center) — simultaneous entrants must not
            // pile into one block; the join shield covers the landing (W-P-ARENA).
            ArenaGame.placeIntoArena(target, player, true);
        }
        player.setGameMode(GameType.ADVENTURE);
        player.getInventory().clearContent();
        if (MinigameDimensions.GAME_RACE.equals(gameId)) {
            ElytraRace.giveKit(player);
        } else {
            ArenaGame.giveKit(player);
            ArenaGame.grantSpawnProtection(target, player);
        }

        player.connection.send(new ClientboundSetTitlesAnimationPacket(10, 60, 20));
        player.connection.send(new ClientboundSetTitleTextPacket(
                ServerLang.resolve(player, gameName(gameId))));
        player.connection.send(new ClientboundSetSubtitleTextPacket(
                ServerLang.tr(player, "eclipse.minigame.enter.subtitle").withStyle(ChatFormatting.GRAY)));
        player.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.7F, 0.8F);

        player.displayClientMessage(leaveLine(player), false);
        EclipseMod.LOGGER.info("{} entered minigame {} (seed {})",
                player.getScoreboardName(), gameId, state.openCount());
    }

    /**
     * THE exit path — every route out (leave command, timeout, dev stop, login rescue)
     * funnels here: teleport to the ticket anchor, restore inventory/mode/health/food,
     * delete the ticket, pay the once-per-instance participation reward.
     */
    private static void exitToTicket(MinecraftServer server, MinigameState state,
            ServerPlayer player, ExitReason reason) {
        MinigameState.Ticket ticket = state.ticket(player.getUUID());
        ServerLevel target = null;
        if (ticket != null) {
            target = server.getLevel(ticket.anchor().dimension());
        }
        EXIT_IN_PROGRESS.add(player.getUUID());
        try {
            if (target != null) {
                MinigameState.ReturnAnchor anchor = ticket.anchor();
                player.teleportTo(target, anchor.x(), anchor.y(), anchor.z(), anchor.yaw(), anchor.pitch());
            } else {
                ServerLevel overworld = server.overworld();
                BlockPos spawn = overworld.getSharedSpawnPos();
                player.teleportTo(overworld, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
            }
        } finally {
            EXIT_IN_PROGRESS.remove(player.getUUID());
        }
        player.fallDistance = 0.0F;
        // The anchor usually sits inside the portal volume (captured at entry) — hold the
        // portal off this player until they physically step out of the frame once.
        AWAITING_PORTAL_CLEAR.add(player.getUUID());

        if (ticket != null) {
            MinigameState.restoreTicket(player, ticket);
            state.removeTicket(player.getUUID());
        }
        PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        LAST_BOUNCE_MESSAGE.remove(player.getUUID());
        ArenaGame.clearSpawnProtection(player);
        removeFromBossBar(player);

        grantParticipationIfOwed(server, state, player);

        String key = switch (reason) {
            case LEFT -> "eclipse.minigame.exit.left";
            case TIME_UP -> "eclipse.minigame.exit.timeup";
            case CLOSED -> "eclipse.minigame.exit.closed";
        };
        player.displayClientMessage(ServerLang.tr(player, key).withStyle(ChatFormatting.AQUA), false);
    }

    /**
     * Once-per-instance participation payout (config: shards + skill XP), settled through
     * the persisted payout ledger (FFIX-B, FINAL-SAT-SOL H2/H4): queued by an
     * instance-scoped id and durably claimed BEFORE the grant, so a crash can neither
     * duplicate nor lose it. {@code markParticipationRewarded} stays as the legacy
     * per-instance bookkeeping but no longer gates the payout — the ledger does.
     */
    private static void grantParticipationIfOwed(MinecraftServer server, MinigameState state,
            ServerPlayer player) {
        if (!state.isParticipant(player.getUUID())) {
            return;
        }
        state.markParticipationRewarded(player.getUUID());
        MinigameState.PendingPayout payout = participationPayout(state.openCount());
        if (payout == null) {
            return;
        }
        state.queuePayout(player.getUUID(), payout);
        if (grantPayout(state, player, payout)) {
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.reward.participation",
                    payout.shards(), payout.skillXp())
                    .withStyle(ChatFormatting.GOLD), false);
        }
    }

    /** The current instance's participation payout, or {@code null} when configured to 0/0. */
    @Nullable
    private static MinigameState.PendingPayout participationPayout(int instanceId) {
        MinigameConfig.Values config = MinigameConfig.get();
        if (config.participationShards() <= 0 && config.participationSkillXp() <= 0) {
            return null;
        }
        return new MinigameState.PendingPayout("minigame:participation:" + instanceId,
                config.participationShards(), config.participationSkillXp());
    }

    /**
     * FFIX-B (FINAL-SAT-SOL H2): queues the current instance's participation payout for
     * EVERY participant — online or not — so entitlements outlive the instance
     * bookkeeping that {@code beginInstance} clears. Offline participants are paid at
     * their next login. Idempotent by stable payout id (safe on close replays).
     */
    private static void settleParticipation(MinigameState state) {
        MinigameState.PendingPayout payout = participationPayout(state.openCount());
        if (payout == null) {
            return;
        }
        for (UUID participant : state.participantsSnapshot()) {
            state.queuePayout(participant, payout);
        }
    }

    /**
     * Applies one queued payout with the AwardService claim-before-give pattern (FFIX-B,
     * FINAL-SAT-SOL H4): the durable delivered-marker is written FIRST, so crash replays
     * and login retries can never apply the same stable payout id twice. Package-private
     * — {@link ArenaGame}/{@link ElytraRace} route their podium payouts through here.
     */
    static boolean grantPayout(MinigameState state, ServerPlayer player,
            MinigameState.PendingPayout payout) {
        if (!state.claimPayout(player.getUUID(), payout.id())) {
            return false;
        }
        if (payout.shards() > 0) {
            ShardEconomy.addShards(player, payout.shards());
        }
        if (payout.skillXp() > 0) {
            SkillsApi.addXp(player, "minigame", payout.skillXp());
        }
        return true;
    }

    /** Login delivery of queued payouts (offline podium/participation — FFIX-B H2/H3). */
    private static void deliverPendingPayouts(MinigameState state, ServerPlayer player) {
        for (MinigameState.PendingPayout payout
                : List.copyOf(state.pendingPayouts(player.getUUID()))) {
            if (grantPayout(state, player, payout)) {
                player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.reward.late",
                        payout.shards(), payout.skillXp()).withStyle(ChatFormatting.GOLD), false);
            }
        }
    }

    // ================================================================== death protection

    /**
     * Cancels player deaths inside minigame dimensions BEFORE the lives pipeline can run
     * (HIGHEST priority; cancelled events are not delivered to default subscribers):
     * no drops, no Eclipse life loss, no grave, no ban. The victim respawns INSIDE —
     * scattered on the arena with a spawn shield (killer credited) or at the last race
     * checkpoint.
     */
    @SubscribeEvent(priority = EventPriority.HIGHEST)
    public static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !MinigameDimensions.isInMinigameDimension(player)) {
            return;
        }
        event.setCanceled(true);
        player.setHealth(player.getMaxHealth());
        player.setRemainingFireTicks(0);
        player.removeAllEffects();
        player.fallDistance = 0.0F;

        MinecraftServer server = player.server;
        MinigameState state = MinigameState.get(server);
        String dimGameId = MinigameDimensions.gameIdOf(player.level().dimension());
        boolean activeHere = state.isActive() && state.gameId().equals(dimGameId);
        if (!activeHere) {
            // Stale player in a minigame dim without a running event: rescue them out.
            exitToTicket(server, state, player, ExitReason.CLOSED);
        } else if (MinigameDimensions.GAME_RACE.equals(dimGameId)) {
            ElytraRace.respawnAtCheckpoint(server, state, player);
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.race.respawn")
                    .withStyle(ChatFormatting.AQUA), true);
        } else {
            ServerPlayer killer = event.getSource().getEntity() instanceof ServerPlayer sourcePlayer
                    ? sourcePlayer : null;
            ArenaGame.onProtectedDeath(server, state, player, killer);
        }
        EclipseMod.LOGGER.info("Protected minigame death of {} ({}), respawned inside={}",
                player.getScoreboardName(), event.getSource().getMsgId(), activeHere);
    }

    // ================================================================== login/logout edges

    /**
     * Login rescue (the xbox pattern, extended by ticket restore): players saved inside a
     * minigame dim while the matching event is gone exit through their ticket; players
     * saved OUTSIDE while still owning a ticket get their inventory restored in place —
     * no exit path can strand a snapshot.
     */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        MinecraftServer server = player.server;
        MinigameState state = MinigameState.get(server);
        // FFIX-B (H2/H3): payouts queued while this player was offline land first.
        deliverPendingPayouts(state, player);
        String dimGameId = MinigameDimensions.gameIdOf(player.level().dimension());
        if (dimGameId != null) {
            boolean eventStillOn = state.isActive() && state.gameId().equals(dimGameId);
            if (eventStillOn) {
                player.displayClientMessage(leaveLine(player), false);
            } else {
                exitToTicket(server, state, player, ExitReason.CLOSED);
            }
        } else if (state.ticket(player.getUUID()) != null) {
            // Crash rescue: outside the dims but the snapshot was never restored.
            MinigameState.restoreTicket(player, state.ticket(player.getUUID()));
            state.removeTicket(player.getUUID());
            grantParticipationIfOwed(server, state, player);
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.exit.rescued")
                    .withStyle(ChatFormatting.AQUA), false);
            EclipseMod.LOGGER.info("Restored stranded minigame ticket for {} at login",
                    player.getScoreboardName());
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        LAST_BOUNCE_MESSAGE.remove(player.getUUID());
        AWAITING_PORTAL_CLEAR.remove(player.getUUID());
        ArenaGame.clearSpawnProtection(player);
        removeFromBossBar(player);
    }

    /**
     * FFIX-B (FINAL-SAT-SOL H1): catches EVERY dimension exit that does not run through
     * {@link #exitToTicket} — admin teleport, other systems' transports, anything. A
     * ticket holder leaving a minigame dimension for a non-minigame one gets their real
     * inventory restored IN PLACE (the foreign teleport's destination is respected, like
     * the login-rescue path) and their ticket released, so the disposable kit can never
     * leak into the outside world. {@code EXIT_IN_PROGRESS} excludes our own exits.
     */
    @SubscribeEvent
    public static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || MinigameDimensions.gameIdOf(event.getFrom()) == null
                || MinigameDimensions.gameIdOf(event.getTo()) != null
                || EXIT_IN_PROGRESS.contains(player.getUUID())) {
            return;
        }
        MinecraftServer server = player.server;
        MinigameState state = MinigameState.get(server);
        MinigameState.Ticket ticket = state.ticket(player.getUUID());
        if (ticket == null) {
            return;
        }
        MinigameState.restoreTicket(player, ticket);
        state.removeTicket(player.getUUID());
        PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        LAST_BOUNCE_MESSAGE.remove(player.getUUID());
        ArenaGame.clearSpawnProtection(player);
        removeFromBossBar(player);
        grantParticipationIfOwed(server, state, player);
        player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.exit.rescued")
                .withStyle(ChatFormatting.AQUA), false);
        EclipseMod.LOGGER.info("Minigame ticket restored for {} after a foreign dimension exit to {}",
                player.getScoreboardName(), event.getTo().location());
    }

    // ================================================================== /minigameleave

    /** First {@code /minigameleave}: confirmation click-through; outside dims: polite no-op. */
    public static int leaveRequested(ServerPlayer player) {
        if (!MinigameDimensions.isInMinigameDimension(player)) {
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        PENDING_LEAVE_CONFIRMS.put(player.getUUID(),
                System.currentTimeMillis() + LEAVE_CONFIRM_WINDOW_MILLIS);
        MutableComponent confirm = ServerLang.tr(player, "eclipse.minigame.leave.confirm")
                .withStyle(ChatFormatting.YELLOW);
        confirm.append(Component.literal(" "));
        confirm.append(ServerLang.tr(player, "eclipse.minigame.leave.confirmbutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.RED).withBold(true).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND,
                                "/minigameleave confirm"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                ServerLang.tr(player, "eclipse.minigame.leave.confirm.hover")))));
        player.displayClientMessage(confirm, false);
        return 1;
    }

    /** {@code /minigameleave confirm}: voluntary exit — re-entry stays open (no lockouts). */
    public static int leaveConfirmed(ServerPlayer player) {
        if (!MinigameDimensions.isInMinigameDimension(player)) {
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        Long window = PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        if (window == null || window < System.currentTimeMillis()) {
            return leaveRequested(player); // expired → re-ask instead of surprising the player
        }
        MinecraftServer server = player.server;
        MinigameState state = MinigameState.get(server);
        exitToTicket(server, state, player, ExitReason.LEFT);
        EclipseMod.LOGGER.info("{} voluntarily left the minigame event", player.getScoreboardName());
        return 1;
    }

    // ================================================================== timer & bossbar

    private static void checkWarnings(MinecraftServer server, MinigameState state, long remaining) {
        if (lastSeenRemainingMillis > WARN_5M_MILLIS && remaining <= WARN_5M_MILLIS) {
            broadcast(server, Component.translatable("eclipse.minigame.announce.warn5",
                    gameName(state.gameId())).withStyle(ChatFormatting.YELLOW));
        }
        if (lastSeenRemainingMillis > WARN_1M_MILLIS && remaining <= WARN_1M_MILLIS) {
            broadcast(server, Component.translatable("eclipse.minigame.announce.warn1",
                    gameName(state.gameId())).withStyle(ChatFormatting.RED));
        }
    }

    /** Bossbar countdown for everyone inside — the xbox timer surface, minigame-tinted. */
    private static void updateBossBar(MinecraftServer server, MinigameState state, long remaining) {
        List<ServerPlayer> inside = insidePlayers(server, state);
        if (inside.isEmpty() && bossBar == null) {
            return;
        }
        if (bossBar == null) {
            bossBar = new ServerBossEvent(Component.empty(),
                    BossEvent.BossBarColor.BLUE, BossEvent.BossBarOverlay.PROGRESS);
        }
        bossBar.setName(Component.translatable("bossbar.eclipse.minigame",
                gameName(state.gameId()), mmss(remaining)));
        long total = Math.max(totalWindowMillisHint, 1L);
        bossBar.setProgress(Mth.clamp((float) remaining / total, 0.0F, 1.0F));

        java.util.Set<UUID> wanted = new java.util.HashSet<>();
        for (ServerPlayer player : inside) {
            wanted.add(player.getUUID());
            bossBar.addPlayer(player); // set-backed: no-op when already shown
        }
        for (ServerPlayer shown : List.copyOf(bossBar.getPlayers())) {
            if (!wanted.contains(shown.getUUID())) {
                bossBar.removePlayer(shown);
            }
        }
    }

    private static void removeBossBar() {
        if (bossBar != null) {
            bossBar.removeAllPlayers();
            bossBar = null;
        }
    }

    private static void removeFromBossBar(ServerPlayer player) {
        if (bossBar != null) {
            bossBar.removePlayer(player);
        }
    }

    // ================================================================== helpers

    /** Players inside the ACTIVE event's dimension. */
    private static List<ServerPlayer> insidePlayers(MinecraftServer server, MinigameState state) {
        ResourceKey<Level> dimension = MinigameDimensions.byGameId(state.gameId());
        if (dimension == null) {
            return List.of();
        }
        ServerLevel level = server.getLevel(dimension);
        return level == null ? List.of() : List.copyOf(level.players());
    }

    /**
     * Global announce, pre-baked per recipient through {@link ServerLang#resolve} so every
     * player reads it in their {@code /lang} locale (Wave-5 A1); the dedicated-server
     * console still gets the raw line for the log.
     */
    private static void broadcast(MinecraftServer server, Component message) {
        server.sendSystemMessage(message);
        for (ServerPlayer player : List.copyOf(server.getPlayerList().getPlayers())) {
            player.sendSystemMessage(ServerLang.resolve(player, message));
        }
    }

    private static void broadcastInside(MinecraftServer server, MinigameState state, Component message) {
        for (ServerPlayer player : insidePlayers(server, state)) {
            player.displayClientMessage(ServerLang.resolve(player, message), false);
        }
    }

    /** Game display name (translatable — clients resolve per-locale). */
    public static Component gameName(String gameId) {
        return Component.translatable("eclipse.minigame.game."
                + (MinigameDimensions.byGameId(gameId) != null ? gameId : "unknown"));
    }

    private static Component portalHint(BlockPos pos) {
        String coords = pos.getX() + " " + pos.getY() + " " + pos.getZ();
        return Component.translatable("eclipse.minigame.announce.portal",
                Component.literal(coords).withStyle(ChatFormatting.AQUA))
                .withStyle(ChatFormatting.GREEN);
    }

    private static Component leaveLine(ServerPlayer player) {
        MutableComponent line = ServerLang.tr(player, "eclipse.minigame.enter.leaveline")
                .withStyle(ChatFormatting.GRAY);
        line.append(Component.literal(" "));
        line.append(ServerLang.tr(player, "eclipse.minigame.enter.leavebutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.YELLOW).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, "/minigameleave"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                ServerLang.tr(player, "eclipse.minigame.enter.leavebutton.hover")))));
        return line;
    }

    /** {@code 29:59} — used by the bossbar name and dev feedback. */
    public static String mmss(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        return String.format(java.util.Locale.ROOT, "%02d:%02d", totalSeconds / 60L, totalSeconds % 60L);
    }

    // ---- status/dev support (used by DevMinigameCommands) ----

    public static MinigameState stateOf(MinecraftServer server) {
        return MinigameState.get(server);
    }

    /** Whether the current instance's course finished generating (status/debug). */
    public static boolean isCourseReady() {
        return courseReady;
    }
}
