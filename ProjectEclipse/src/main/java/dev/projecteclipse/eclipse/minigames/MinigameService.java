package dev.projecteclipse.eclipse.minigames;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
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
 * the player: they respawn inside (arena center / last race checkpoint).</p>
 *
 * <p><b>Ticket safety</b>: every entrant gets a {@link MinigameState.Ticket} (anchor +
 * game mode + health/food + full inventory NBT) BEFORE anything else happens. Every exit
 * path — voluntary leave, timeout, dev stop, crash rescue at login — funnels through
 * {@link #exitToTicket}, which restores the ticket and only then deletes it.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MinigameService {

    private static final long WARN_5M_MILLIS = 5L * 60L * 1000L;
    private static final long WARN_1M_MILLIS = 60L * 1000L;
    private static final long LEAVE_CONFIRM_WINDOW_MILLIS = 15_000L;
    private static final long BOUNCE_MESSAGE_THROTTLE_MILLIS = 3_000L;
    private static final long GRACEFUL_STOP_MILLIS = 10_000L;

    // ---- transient per-run state (cleared on ServerStoppedEvent; SavedData is per-save) ----
    @Nullable
    private static ServerBossEvent bossBar;
    private static final Map<UUID, Long> PENDING_LEAVE_CONFIRMS = new HashMap<>();
    private static final Map<UUID, Long> LAST_BOUNCE_MESSAGE = new HashMap<>();
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
        lastSeenRemainingMillis = Long.MAX_VALUE;
        totalWindowMillisHint = 0L;
        courseReady = false;
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

        removePortal(server, state);
        cleanupCourseEntities(server, gameId);

        removeBossBar();
        PENDING_LEAVE_CONFIRMS.clear();
        LAST_BOUNCE_MESSAGE.clear();
        lastSeenRemainingMillis = Long.MAX_VALUE;
        courseReady = false;
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
            if (!player.isSpectator() && player.isAlive() && box.intersects(player.getBoundingBox())) {
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
                player.displayClientMessage(Component.translatable("eclipse.minigame.enter.not_ready")
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

        if (MinigameDimensions.GAME_RACE.equals(gameId)) {
            ElytraRace.placeIntoRace(target, state, player);
        } else {
            ArenaGame.placeIntoArena(target, player, false);
        }
        player.setGameMode(GameType.ADVENTURE);
        player.getInventory().clearContent();
        if (MinigameDimensions.GAME_RACE.equals(gameId)) {
            ElytraRace.giveKit(player);
        } else {
            ArenaGame.giveKit(player);
        }

        player.connection.send(new ClientboundSetTitlesAnimationPacket(10, 60, 20));
        player.connection.send(new ClientboundSetTitleTextPacket(gameName(gameId)));
        player.connection.send(new ClientboundSetSubtitleTextPacket(
                Component.translatable("eclipse.minigame.enter.subtitle").withStyle(ChatFormatting.GRAY)));
        player.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.7F, 0.8F);

        player.displayClientMessage(leaveLine(), false);
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
        if (target != null) {
            MinigameState.ReturnAnchor anchor = ticket.anchor();
            player.teleportTo(target, anchor.x(), anchor.y(), anchor.z(), anchor.yaw(), anchor.pitch());
        } else {
            ServerLevel overworld = server.overworld();
            BlockPos spawn = overworld.getSharedSpawnPos();
            player.teleportTo(overworld, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                    overworld.getSharedSpawnAngle(), 0.0F);
        }
        player.fallDistance = 0.0F;

        if (ticket != null) {
            MinigameState.restoreTicket(player, ticket);
            state.removeTicket(player.getUUID());
        }
        PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        LAST_BOUNCE_MESSAGE.remove(player.getUUID());
        removeFromBossBar(player);

        grantParticipationIfOwed(server, state, player);

        String key = switch (reason) {
            case LEFT -> "eclipse.minigame.exit.left";
            case TIME_UP -> "eclipse.minigame.exit.timeup";
            case CLOSED -> "eclipse.minigame.exit.closed";
        };
        player.displayClientMessage(Component.translatable(key).withStyle(ChatFormatting.AQUA), false);
    }

    /** Once-per-instance participation payout (config: shards + skill XP), paid on exit. */
    private static void grantParticipationIfOwed(MinecraftServer server, MinigameState state,
            ServerPlayer player) {
        if (!state.isParticipant(player.getUUID())
                || !state.markParticipationRewarded(player.getUUID())) {
            return;
        }
        MinigameConfig.Values config = MinigameConfig.get();
        if (config.participationShards() > 0) {
            ShardEconomy.addShards(player, config.participationShards());
        }
        if (config.participationSkillXp() > 0) {
            SkillsApi.addXp(player, "minigame", config.participationSkillXp());
        }
        if (config.participationShards() > 0 || config.participationSkillXp() > 0) {
            player.displayClientMessage(Component.translatable("eclipse.minigame.reward.participation",
                    config.participationShards(), config.participationSkillXp())
                    .withStyle(ChatFormatting.GOLD), false);
        }
    }

    // ================================================================== death protection

    /**
     * Cancels player deaths inside minigame dimensions BEFORE the lives pipeline can run
     * (HIGHEST priority; cancelled events are not delivered to default subscribers):
     * no drops, no Eclipse life loss, no grave, no ban. The victim respawns INSIDE —
     * arena center (killer credited) or last race checkpoint.
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
            player.displayClientMessage(Component.translatable("eclipse.minigame.race.respawn")
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
        String dimGameId = MinigameDimensions.gameIdOf(player.level().dimension());
        if (dimGameId != null) {
            boolean eventStillOn = state.isActive() && state.gameId().equals(dimGameId);
            if (eventStillOn) {
                player.displayClientMessage(leaveLine(), false);
            } else {
                exitToTicket(server, state, player, ExitReason.CLOSED);
            }
        } else if (state.ticket(player.getUUID()) != null) {
            // Crash rescue: outside the dims but the snapshot was never restored.
            MinigameState.restoreTicket(player, state.ticket(player.getUUID()));
            state.removeTicket(player.getUUID());
            grantParticipationIfOwed(server, state, player);
            player.displayClientMessage(Component.translatable("eclipse.minigame.exit.rescued")
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
        removeFromBossBar(player);
    }

    // ================================================================== /minigameleave

    /** First {@code /minigameleave}: confirmation click-through; outside dims: polite no-op. */
    public static int leaveRequested(ServerPlayer player) {
        if (!MinigameDimensions.isInMinigameDimension(player)) {
            player.displayClientMessage(Component.translatable("eclipse.minigame.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        PENDING_LEAVE_CONFIRMS.put(player.getUUID(),
                System.currentTimeMillis() + LEAVE_CONFIRM_WINDOW_MILLIS);
        MutableComponent confirm = Component.translatable("eclipse.minigame.leave.confirm")
                .withStyle(ChatFormatting.YELLOW);
        confirm.append(Component.literal(" "));
        confirm.append(Component.translatable("eclipse.minigame.leave.confirmbutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.RED).withBold(true).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND,
                                "/minigameleave confirm"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                Component.translatable("eclipse.minigame.leave.confirm.hover")))));
        player.displayClientMessage(confirm, false);
        return 1;
    }

    /** {@code /minigameleave confirm}: voluntary exit — re-entry stays open (no lockouts). */
    public static int leaveConfirmed(ServerPlayer player) {
        if (!MinigameDimensions.isInMinigameDimension(player)) {
            player.displayClientMessage(Component.translatable("eclipse.minigame.leave.outside")
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

    private static void broadcast(MinecraftServer server, Component message) {
        server.getPlayerList().broadcastSystemMessage(message, false);
    }

    private static void broadcastInside(MinecraftServer server, MinigameState state, Component message) {
        for (ServerPlayer player : insidePlayers(server, state)) {
            player.displayClientMessage(message, false);
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

    private static Component leaveLine() {
        MutableComponent line = Component.translatable("eclipse.minigame.enter.leaveline")
                .withStyle(ChatFormatting.GRAY);
        line.append(Component.literal(" "));
        line.append(Component.translatable("eclipse.minigame.enter.leavebutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.YELLOW).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, "/minigameleave"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                Component.translatable("eclipse.minigame.enter.leavebutton.hover")))));
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
