package dev.projecteclipse.eclipse.xboxevent;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.classicblocks.ClassicBlockItems;
import dev.projecteclipse.eclipse.classicblocks.ClassicChestLoot;
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
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.ItemStack;
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
 * The Xbox-360 tutorial event state machine (plan §2.13.3–2.13.6): dev-triggered lifecycle
 * {@code IDLE → ANNOUNCED → OPEN → CLOSING → IDLE} persisted in {@link XboxEventState},
 * portal collision entries, the 30:00 timer with bossbar fallback (§2.13.5), protected
 * deaths (no item loss, no Eclipse life loss), voluntary exit with per-instance lockouts,
 * and the participation reward via {@code TimedBuffApi} (called through the P4-A1 Holder).
 *
 * <p><b>Death protection mechanics</b>: the {@link LivingDeathEvent} intercept runs at
 * {@link EventPriority#HIGHEST} and CANCELS player deaths inside Xbox dimensions. Because
 * subscribers do not receive cancelled events by default, the existing lives pipeline
 * ({@code lives.LifecycleEvents}: snapshot, life loss, kill transfer, grave, ban) never
 * runs, and {@code LivingDropsEvent} never fires (the entity did not die) — so inventory,
 * Eclipse lives and hearts stay untouched. {@link XboxEventApi#isProtectedDeath} stays the
 * stable query for P4's future {@code DeathFlowHooks} short-circuit (§4.4).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class XboxEventService {

    private static final long WARN_5M_MILLIS = 5L * 60L * 1000L;
    private static final long WARN_1M_MILLIS = 60L * 1000L;
    private static final long PERIODIC_SYNC_MILLIS = 20_000L;
    private static final long LEAVE_CONFIRM_WINDOW_MILLIS = 15_000L;
    private static final long BOUNCE_MESSAGE_THROTTLE_MILLIS = 3_000L;
    private static final long GRACEFUL_STOP_MILLIS = 10_000L;

    // ---- transient per-run state (cleared on ServerStoppedEvent; SavedData is per-save) ----
    @Nullable
    private static ServerBossEvent bossBar;
    private static final Set<UUID> OVERLAY_ACKED = new HashSet<>();
    private static final Map<UUID, Long> PENDING_LEAVE_CONFIRMS = new HashMap<>();
    private static final Map<UUID, Long> LAST_BOUNCE_MESSAGE = new HashMap<>();
    private static long lastPeriodicSyncMillis;
    private static long lastSeenRemainingMillis = Long.MAX_VALUE;
    private static long totalWindowMillisHint;

    private XboxEventService() {}

    /** Exit paths — pick the right player-facing message. */
    public enum ExitReason { DEATH, DEATH_LOCKED, LEFT, LEFT_UNLOCKED, TIME_UP, CLOSED }

    /** Common-setup hookups (MOD bus): chest-loot provider + config bootstrap. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            ClassicChestLoot.setProvider(XboxEventService::lootFor);
            XboxEventConfig.bootstrap();
        }
    }

    // ================================================================== lifecycle

    /** Crash resume (§2.13.6): a persisted event whose window passed closes on boot. */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        resumeOnBoot(event.getServer());
    }

    /** Boot-resume logic, callable from gametests (crash-resume acceptance §3 P5-W9). */
    public static void resumeOnBoot(MinecraftServer server) {
        XboxEventState state = XboxEventState.get(server);
        long now = System.currentTimeMillis();
        switch (state.phase()) {
            case OPEN, ANNOUNCED -> {
                if (state.endsAtEpochMillis() <= now) {
                    EclipseMod.LOGGER.info("Xbox event {} expired while server was down — closing now",
                            state.worldId());
                    beginClosing(server, state);
                } else {
                    totalWindowMillisHint = Math.max(state.endsAtEpochMillis() - now,
                            XboxEventConfig.get().defaultMinutes() * 60_000L);
                    EclipseMod.LOGGER.info("Xbox event {} resumes: {} remaining",
                            state.worldId(), mmss(state.endsAtEpochMillis() - now));
                }
            }
            case CLOSING -> {
                EclipseMod.LOGGER.info("Xbox event {} was mid-CLOSING at shutdown — finishing close",
                        state.worldId());
                beginClosing(server, state, ExitReason.CLOSED);
            }
            case IDLE -> { /* nothing */ }
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        bossBar = null;
        OVERLAY_ACKED.clear();
        PENDING_LEAVE_CONFIRMS.clear();
        LAST_BOUNCE_MESSAGE.clear();
        lastPeriodicSyncMillis = 0L;
        lastSeenRemainingMillis = Long.MAX_VALUE;
        totalWindowMillisHint = 0L;
        XboxWorldsManifest.clearRuntimeCaches();
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % 10 != 0) {
            return;
        }
        XboxEventState state = XboxEventState.get(server);
        if (state.phase() != XboxEventState.Phase.OPEN
                && state.phase() != XboxEventState.Phase.ANNOUNCED) {
            return;
        }

        long now = System.currentTimeMillis();
        long remaining = state.endsAtEpochMillis() - now;
        if (remaining <= 0L) {
            beginClosing(server, state);
            return;
        }

        if (state.phase() == XboxEventState.Phase.OPEN) {
            checkWarnings(server, state, remaining);
            tickPortal(server, state);
            updateBossBar(server, state, remaining);
            if (now - lastPeriodicSyncMillis >= PERIODIC_SYNC_MILLIS) {
                lastPeriodicSyncMillis = now;
                syncTimerToInside(server, state);
            }
        }
        lastSeenRemainingMillis = remaining;
    }

    // ================================================================== start / stop / mutate

    /** Outcome of {@link #start}: {@code started=false} → {@code message} is the error. */
    public record StartResult(boolean started, @Nullable Component message) {}

    /**
     * Starts the event (plan §2.13.3): validates world id, loaded dimension and installed
     * region payload, announces, spawns the portal near spawn and opens. When no portal
     * spot is found the event stays ANNOUNCED and the result carries a warning — the
     * operator places the portal manually via {@code /dev xboxevent portal here}.
     */
    public static StartResult start(MinecraftServer server, String worldId, int minutes, String operatorName) {
        XboxEventState state = XboxEventState.get(server);
        if (state.phase() == XboxEventState.Phase.OPEN || state.phase() == XboxEventState.Phase.ANNOUNCED) {
            return new StartResult(false, Component.translatable("dev.eclipse.xbox.start.already",
                    state.worldId(), mmss(state.endsAtEpochMillis() - System.currentTimeMillis())));
        }
        XboxEventConfig.Values config = XboxEventConfig.get();
        ResourceKey<Level> dimension = XboxDimensions.byWorldId(worldId);
        if (!config.worlds().contains(worldId) || dimension == null
                || XboxWorldsManifest.byId(worldId).isEmpty()) {
            return new StartResult(false, Component.translatable("dev.eclipse.xbox.start.unknown_world",
                    worldId, String.join(", ", config.worlds())));
        }
        ServerLevel level = server.getLevel(dimension);
        if (level == null) {
            return new StartResult(false, Component.translatable("dev.eclipse.xbox.start.no_level",
                    dimension.location().toString()));
        }
        if (!XboxWorldInstaller.isInstalled(server, worldId)) {
            return new StartResult(false,
                    Component.translatable("dev.eclipse.xbox.start.not_installed", worldId));
        }

        int effectiveMinutes = minutes > 0 ? minutes : config.defaultMinutes();
        long now = System.currentTimeMillis();
        state.beginInstance(worldId, now + effectiveMinutes * 60_000L);
        totalWindowMillisHint = effectiveMinutes * 60_000L;
        lastSeenRemainingMillis = Long.MAX_VALUE;
        lastPeriodicSyncMillis = 0L;

        broadcast(server, Component.translatable("eclipse.xbox.announce.start",
                worldName(worldId), effectiveMinutes).withStyle(ChatFormatting.GREEN));

        ServerLevel overworld = server.overworld();
        BlockPos spot = XboxPortal.findSpotNearSpawn(overworld);
        if (spot != null) {
            XboxPortal.place(overworld, spot, state);
            state.setPhase(XboxEventState.Phase.OPEN);
            broadcast(server, portalHint(spot));
        } else {
            EclipseMod.LOGGER.warn("Xbox event {}: no portal spot within {}..{} blocks of spawn",
                    worldId, config.portalSearchMinRadius(), config.portalSearchMaxRadius());
        }
        EclipseMod.LOGGER.info("Xbox event started by {}: world={}, minutes={}, instance={}",
                operatorName, worldId, effectiveMinutes, state.instanceId());
        return new StartResult(true, spot == null
                ? Component.translatable("dev.eclipse.xbox.portal.nospot",
                        config.portalSearchMinRadius(), config.portalSearchMaxRadius())
                : null);
    }

    /**
     * {@code /dev xboxevent portal here|remove} backing. {@code here} relocates (or first
     * places) the portal at the operator's feet and opens an ANNOUNCED event.
     */
    @Nullable
    public static Component portalHere(MinecraftServer server, ServerPlayer operator) {
        if (XboxDimensions.isInXboxDimension(operator)) {
            return Component.translatable("dev.eclipse.xbox.portal.in_xbox_dim");
        }
        XboxEventState state = XboxEventState.get(server);
        if (state.phase() != XboxEventState.Phase.OPEN && state.phase() != XboxEventState.Phase.ANNOUNCED) {
            return Component.translatable("dev.eclipse.xbox.stop.idle");
        }
        removePortal(server, state);
        ServerLevel level = (ServerLevel) operator.level();
        BlockPos base = operator.blockPosition();
        XboxPortal.place(level, base, state);
        if (state.phase() == XboxEventState.Phase.ANNOUNCED) {
            state.setPhase(XboxEventState.Phase.OPEN);
        }
        broadcast(server, portalHint(base));
        return null;
    }

    @Nullable
    public static Component portalRemove(MinecraftServer server) {
        XboxEventState state = XboxEventState.get(server);
        if (state.portalPos() == null) {
            return Component.translatable("dev.eclipse.xbox.portal.none");
        }
        removePortal(server, state);
        return null;
    }

    /** Graceful stop = short grace window; {@code immediate} closes this tick (§2.13.3). */
    @Nullable
    public static Component stop(MinecraftServer server, boolean immediate) {
        XboxEventState state = XboxEventState.get(server);
        if (state.phase() != XboxEventState.Phase.OPEN && state.phase() != XboxEventState.Phase.ANNOUNCED) {
            return Component.translatable("dev.eclipse.xbox.stop.idle");
        }
        if (immediate) {
            beginClosing(server, state, ExitReason.CLOSED);
            return null;
        }
        long now = System.currentTimeMillis();
        long graceEnd = now + GRACEFUL_STOP_MILLIS;
        if (state.endsAtEpochMillis() > graceEnd) {
            state.setEndsAtEpochMillis(graceEnd);
            broadcast(server, Component.translatable("eclipse.xbox.announce.stopping",
                    worldName(state.worldId()), GRACEFUL_STOP_MILLIS / 1000L).withStyle(ChatFormatting.YELLOW));
            syncTimerToInside(server, state);
        }
        return null;
    }

    /**
     * {@code /dev xboxevent time add|sub|set} — mutates {@code endsAt}, clamped ≥ now.
     * Returns the success feedback line, or {@code null} when no event is running.
     */
    @Nullable
    public static Component timeMutate(MinecraftServer server, char mode, long durationMillis) {
        XboxEventState state = XboxEventState.get(server);
        if (state.phase() != XboxEventState.Phase.OPEN && state.phase() != XboxEventState.Phase.ANNOUNCED) {
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
        syncTimerToInside(server, state);
        broadcastInside(server, state, Component.translatable("eclipse.xbox.announce.time_changed",
                mmss(newRemaining)).withStyle(ChatFormatting.YELLOW));
        return Component.translatable("dev.eclipse.xbox.time.changed", mmss(newRemaining), mmss(oldRemaining));
    }

    // ================================================================== closing

    /**
     * CLOSING sequence (§2.13.3/§2.13.6): exit everyone with full inventory, grant the
     * participation reward through the {@code TimedBuffApi} Holder, despawn the portal,
     * stage the world reset marker, return to IDLE. Safe to re-run after a crash mid-close.
     */
    private static void beginClosing(MinecraftServer server, XboxEventState state) {
        beginClosing(server, state, ExitReason.TIME_UP);
    }

    private static void beginClosing(MinecraftServer server, XboxEventState state, ExitReason reason) {
        state.setPhase(XboxEventState.Phase.CLOSING);
        String worldId = state.worldId();
        broadcast(server, Component.translatable("eclipse.xbox.announce.end", worldName(worldId))
                .withStyle(ChatFormatting.GREEN));

        for (ServerPlayer player : insidePlayers(server, state)) {
            exitToAnchor(server, state, player, reason);
        }

        Set<UUID> participants = state.participantsSnapshot();
        if (!participants.isEmpty()) {
            grantReward(server, state, participants.size());
        }

        removePortal(server, state);

        try {
            XboxWorldInstaller.stageReset(server, worldId);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Could not stage xbox world reset for {}", worldId, e);
        }

        removeBossBar();
        PENDING_LEAVE_CONFIRMS.clear();
        LAST_BOUNCE_MESSAGE.clear();
        lastSeenRemainingMillis = Long.MAX_VALUE;
        state.setPhase(XboxEventState.Phase.IDLE);
        EclipseMod.LOGGER.info("Xbox event {} closed (instance {}, {} participants)",
                worldId, state.instanceId(), participants.size());
    }

    private static void grantReward(MinecraftServer server, XboxEventState state, int participantCount) {
        XboxEventConfig.Values config = XboxEventConfig.get();
        String buffId = state.rewardBuffIdOverride().isEmpty()
                ? config.rewardBuffId() : state.rewardBuffIdOverride();
        int minutes = state.rewardMinutesOverride() > 0
                ? state.rewardMinutesOverride() : config.rewardMinutes();
        boolean started = TimedBuffApi.Holder.get().start(server, buffId, minutes);
        if (started) {
            broadcast(server, Component.translatable("eclipse.xbox.announce.reward",
                    buffId, minutes, participantCount).withStyle(ChatFormatting.GOLD));
        } else {
            EclipseMod.LOGGER.warn(
                    "Xbox participation reward '{}' ({} min) was refused or TimedBuffApi is not installed yet",
                    buffId, minutes);
        }
    }

    private static void removePortal(MinecraftServer server, XboxEventState state) {
        BlockPos portalPos = state.portalPos();
        ResourceKey<Level> portalDim = state.portalDimension();
        if (portalPos == null || portalDim == null) {
            return;
        }
        ServerLevel level = server.getLevel(portalDim);
        if (level != null) {
            XboxPortal.remove(level, portalPos, state);
        } else {
            state.setPortal(null, null);
        }
    }

    // ================================================================== portal & entries

    private static void tickPortal(MinecraftServer server, XboxEventState state) {
        BlockPos portalPos = state.portalPos();
        ResourceKey<Level> portalDim = state.portalDimension();
        if (portalPos == null || portalDim == null) {
            return;
        }
        ServerLevel level = server.getLevel(portalDim);
        if (level == null) {
            return;
        }
        XboxPortal.ambientTick(level, portalPos, level.getGameTime());
        var box = XboxPortal.collisionBox(portalPos);
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (!player.isSpectator() && player.isAlive() && box.intersects(player.getBoundingBox())) {
                tryEnter(server, state, player);
            }
        }
    }

    private static void tryEnter(MinecraftServer server, XboxEventState state, ServerPlayer player) {
        if (state.phase() != XboxEventState.Phase.OPEN) {
            return;
        }
        UUID uuid = player.getUUID();
        if (state.isLockedOut(uuid)) {
            long now = System.currentTimeMillis();
            long last = LAST_BOUNCE_MESSAGE.getOrDefault(uuid, 0L);
            if (now - last >= BOUNCE_MESSAGE_THROTTLE_MILLIS) {
                LAST_BOUNCE_MESSAGE.put(uuid, now);
                player.displayClientMessage(Component.translatable("eclipse.xbox.enter.locked")
                        .withStyle(ChatFormatting.RED), false);
                player.playNotifySound(SoundEvents.VILLAGER_NO, SoundSource.PLAYERS, 0.8F, 1.0F);
            }
            return;
        }
        enter(server, state, player);
    }

    /** Entry sequence (§2.13.4): anchor → transition payload → teleport → title + leave line. */
    private static void enter(MinecraftServer server, XboxEventState state, ServerPlayer player) {
        String worldId = state.worldId();
        XboxWorldsManifest.WorldEntry entry = XboxWorldsManifest.byId(worldId).orElse(null);
        ResourceKey<Level> dimension = XboxDimensions.byWorldId(worldId);
        if (entry == null || dimension == null) {
            return;
        }
        ServerLevel target = server.getLevel(dimension);
        if (target == null) {
            return;
        }

        state.putReturnAnchor(player.getUUID(), new XboxEventState.ReturnAnchor(
                player.level().dimension(), player.getX(), player.getY(), player.getZ(),
                player.getYRot(), player.getXRot()));

        XboxPayloads.sendPortalTransition(player); // no-op until P3-W11's payload lands (§4.3)

        BlockPos spawn = entry.spawn();
        player.teleportTo(target, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                entry.spawnYaw(), 0.0F);
        player.fallDistance = 0.0F;

        state.addParticipant(player.getUUID());

        player.connection.send(new ClientboundSetTitlesAnimationPacket(10, 60, 20));
        player.connection.send(new ClientboundSetTitleTextPacket(worldName(worldId)));
        player.connection.send(new ClientboundSetSubtitleTextPacket(
                Component.translatable("eclipse.xbox.enter.subtitle").withStyle(ChatFormatting.GRAY)));
        player.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.7F, 0.6F);

        player.displayClientMessage(leaveLine(), false);
        sendTimer(state, player, true);
        EclipseMod.LOGGER.info("{} entered xbox world {} (instance {})",
                player.getScoreboardName(), worldId, state.instanceId());
    }

    /** Exit sequence: transition payload → teleport to the captured anchor → message. */
    private static void exitToAnchor(MinecraftServer server, XboxEventState state,
            ServerPlayer player, ExitReason reason) {
        XboxEventState.ReturnAnchor anchor = state.returnAnchor(player.getUUID());
        ServerLevel target = null;
        if (anchor != null) {
            target = server.getLevel(anchor.dimension());
        }

        XboxPayloads.sendPortalTransition(player);

        if (target != null) {
            player.teleportTo(target, anchor.x(), anchor.y(), anchor.z(), anchor.yaw(), anchor.pitch());
        } else {
            ServerLevel overworld = server.overworld();
            BlockPos spawn = overworld.getSharedSpawnPos();
            player.teleportTo(overworld, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                    overworld.getSharedSpawnAngle(), 0.0F);
        }
        player.fallDistance = 0.0F;
        state.removeReturnAnchor(player.getUUID());
        PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        removeFromBossBar(player);
        sendTimer(state, player, false);

        String key = switch (reason) {
            case DEATH -> "eclipse.xbox.exit.death";
            case DEATH_LOCKED -> "eclipse.xbox.exit.death_locked";
            case LEFT -> "eclipse.xbox.exit.left";
            case LEFT_UNLOCKED -> "eclipse.xbox.exit.left_unlocked";
            case TIME_UP -> "eclipse.xbox.exit.timeup";
            case CLOSED -> "eclipse.xbox.exit.closed";
        };
        player.displayClientMessage(Component.translatable(key).withStyle(ChatFormatting.AQUA), false);
    }

    // ================================================================== death protection

    /**
     * Cancels player deaths inside Xbox dimensions BEFORE the lives pipeline can run
     * (HIGHEST priority; cancelled events are not delivered to default subscribers):
     * no drops, no Eclipse life loss, no grave, no ban — just the exit sequence (§2.13.6).
     */
    @SubscribeEvent(priority = EventPriority.HIGHEST)
    public static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !XboxDimensions.isInXboxDimension(player)) {
            return;
        }
        event.setCanceled(true);
        player.setHealth(1.0F);
        player.setRemainingFireTicks(0);
        player.removeAllEffects();
        player.fallDistance = 0.0F;

        MinecraftServer server = player.server;
        XboxEventState state = XboxEventState.get(server);
        boolean lockedOut = isActiveEventForPlayer(state, player)
                && state.lockoutMode().locksDeath();
        if (lockedOut) {
            state.lockOut(player.getUUID());
        }
        exitToAnchor(server, state, player,
                lockedOut ? ExitReason.DEATH_LOCKED : ExitReason.DEATH);
        EclipseMod.LOGGER.info("Protected xbox death of {} ({}), returned to anchor (locked out: {})",
                player.getScoreboardName(), event.getSource().getMsgId(), lockedOut);
    }

    // ================================================================== login/logout edges

    /** Logout inside → the exit sequence runs at next login when the event is over (§2.13.6). */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        MinecraftServer server = player.server;
        XboxEventState state = XboxEventState.get(server);
        String dimWorldId = XboxDimensions.worldIdOf(player.level().dimension());
        if (dimWorldId != null) {
            boolean eventStillOn = state.phase() == XboxEventState.Phase.OPEN
                    && state.worldId().equals(dimWorldId);
            if (eventStillOn) {
                sendTimer(state, player, true);
                player.displayClientMessage(leaveLine(), false);
            } else {
                exitToAnchor(server, state, player, ExitReason.CLOSED);
            }
        } else if (state.returnAnchor(player.getUUID()) != null
                && state.phase() == XboxEventState.Phase.IDLE) {
            state.removeReturnAnchor(player.getUUID()); // stale leftover, already outside
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        OVERLAY_ACKED.remove(player.getUUID());
        PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        LAST_BOUNCE_MESSAGE.remove(player.getUUID());
        removeFromBossBar(player);
    }

    // ================================================================== /xboxleave

    /** First {@code /xboxleave}: confirmation click-through; outside dims: polite no-op. */
    public static int leaveRequested(ServerPlayer player) {
        if (!XboxDimensions.isInXboxDimension(player)) {
            player.displayClientMessage(Component.translatable("eclipse.xbox.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        XboxEventState state = XboxEventState.get(player.server);
        boolean willLockOut = isActiveEventForPlayer(state, player)
                && state.lockoutMode().locksVoluntaryExit();
        PENDING_LEAVE_CONFIRMS.put(player.getUUID(),
                System.currentTimeMillis() + LEAVE_CONFIRM_WINDOW_MILLIS);
        MutableComponent confirm = Component.translatable(willLockOut
                ? "eclipse.xbox.leave.confirm"
                : "eclipse.xbox.leave.confirm_unlocked")
                .withStyle(ChatFormatting.YELLOW);
        confirm.append(Component.literal(" "));
        confirm.append(Component.translatable("eclipse.xbox.leave.confirmbutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.RED).withBold(true).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, "/xboxleave confirm"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                Component.translatable(willLockOut
                                        ? "eclipse.xbox.leave.confirm.hover"
                                        : "eclipse.xbox.leave.confirm_unlocked.hover")))));
        player.displayClientMessage(confirm, false);
        return 1;
    }

    /** {@code /xboxleave confirm}: voluntary exit + lockout for THIS instance (§2.13.6). */
    public static int leaveConfirmed(ServerPlayer player) {
        if (!XboxDimensions.isInXboxDimension(player)) {
            player.displayClientMessage(Component.translatable("eclipse.xbox.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        Long window = PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        if (window == null || window < System.currentTimeMillis()) {
            return leaveRequested(player); // expired → re-ask instead of surprising the player
        }
        MinecraftServer server = player.server;
        XboxEventState state = XboxEventState.get(server);
        boolean activeEvent = isActiveEventForPlayer(state, player);
        boolean lockedOut = activeEvent && state.lockoutMode().locksVoluntaryExit();
        if (lockedOut) {
            state.lockOut(player.getUUID());
        }
        exitToAnchor(server, state, player,
                lockedOut ? ExitReason.LEFT : ExitReason.LEFT_UNLOCKED);
        EclipseMod.LOGGER.info("{} voluntarily left the xbox event (locked out: {})",
                player.getScoreboardName(), lockedOut);
        return 1;
    }

    // ================================================================== timer sync & bossbar

    /** Overlay ack (§2.13.5): P3's overlay hides the bossbar fallback for capable clients. */
    public static void onOverlayAck(ServerPlayer player, boolean overlayCapable) {
        if (overlayCapable) {
            OVERLAY_ACKED.add(player.getUUID());
            removeFromBossBar(player);
        } else {
            OVERLAY_ACKED.remove(player.getUUID());
        }
    }

    private static void syncTimerToInside(MinecraftServer server, XboxEventState state) {
        for (ServerPlayer player : insidePlayers(server, state)) {
            sendTimer(state, player, true);
        }
    }

    private static void sendTimer(XboxEventState state, ServerPlayer player, boolean active) {
        XboxPayloads.sendTimer(player, new XboxPayloads.S2CXboxTimerPayload(
                state.endsAtEpochMillis(), System.currentTimeMillis(), state.worldId(), active));
    }

    private static void checkWarnings(MinecraftServer server, XboxEventState state, long remaining) {
        if (lastSeenRemainingMillis > WARN_5M_MILLIS && remaining <= WARN_5M_MILLIS) {
            broadcast(server, Component.translatable("eclipse.xbox.announce.warn5",
                    worldName(state.worldId())).withStyle(ChatFormatting.YELLOW));
        }
        if (lastSeenRemainingMillis > WARN_1M_MILLIS && remaining <= WARN_1M_MILLIS) {
            broadcast(server, Component.translatable("eclipse.xbox.announce.warn1",
                    worldName(state.worldId())).withStyle(ChatFormatting.RED));
        }
    }

    private static void updateBossBar(MinecraftServer server, XboxEventState state, long remaining) {
        List<ServerPlayer> inside = insidePlayers(server, state);
        if (inside.isEmpty() && bossBar == null) {
            return;
        }
        if (bossBar == null) {
            bossBar = new ServerBossEvent(Component.empty(),
                    BossEvent.BossBarColor.GREEN, BossEvent.BossBarOverlay.PROGRESS);
        }
        bossBar.setName(Component.translatable("bossbar.eclipse.xbox",
                worldName(state.worldId()), mmss(remaining)));
        long total = Math.max(totalWindowMillisHint, 1L);
        bossBar.setProgress(Mth.clamp((float) remaining / total, 0.0F, 1.0F));

        Set<UUID> wanted = new HashSet<>();
        for (ServerPlayer player : inside) {
            if (!OVERLAY_ACKED.contains(player.getUUID())) {
                wanted.add(player.getUUID());
                bossBar.addPlayer(player); // set-backed: no-op when already shown
            }
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

    // ================================================================== chest loot hook

    /**
     * {@code ClassicChestLoot} provider (installed in common setup, W8 wiring): recorded
     * baked stacks for a classic chest position inside an Xbox dimension, consumed exactly
     * once per event instance; empty elsewhere. Block items are classic-mapped at spill
     * time; music discs and other non-block items stay vanilla (playable souvenirs, §2.14).
     */
    public static List<ItemStack> lootFor(ServerLevel level, BlockPos pos) {
        String worldId = XboxDimensions.worldIdOf(level.dimension());
        if (worldId == null) {
            return List.of();
        }
        List<ItemStack> recorded = XboxWorldsManifest.loot(level.getServer(), worldId).get(pos);
        if (recorded == null || recorded.isEmpty()) {
            return List.of();
        }
        XboxEventState state = XboxEventState.get(level.getServer());
        if (!state.consumeChestPosition(worldId, pos)) {
            return List.of();
        }
        List<ItemStack> spilled = new ArrayList<>(recorded.size());
        for (ItemStack stack : recorded) {
            spilled.add(classicMapped(stack));
        }
        return spilled;
    }

    private static ItemStack classicMapped(ItemStack original) {
        if (original.getItem() instanceof BlockItem blockItem) {
            var vanillaId = net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(blockItem);
            if ("minecraft".equals(vanillaId.getNamespace())) {
                var classic = ClassicBlockItems.all().get(vanillaId.getPath());
                if (classic != null) {
                    return new ItemStack(classic.get(), original.getCount());
                }
            }
        }
        return original.copy();
    }

    // ================================================================== helpers

    /** Players inside the ACTIVE event dimension (other xbox dims are dev-only). */
    private static List<ServerPlayer> insidePlayers(MinecraftServer server, XboxEventState state) {
        ResourceKey<Level> dimension = XboxDimensions.byWorldId(state.worldId());
        if (dimension == null) {
            return List.of();
        }
        ServerLevel level = server.getLevel(dimension);
        return level == null ? List.of() : List.copyOf(level.players());
    }

    private static boolean isActiveEventForPlayer(XboxEventState state, ServerPlayer player) {
        return state.phase() == XboxEventState.Phase.OPEN
                && state.worldId().equals(XboxDimensions.worldIdOf(player.level().dimension()));
    }

    private static void broadcast(MinecraftServer server, Component message) {
        server.getPlayerList().broadcastSystemMessage(message, false);
    }

    private static void broadcastInside(MinecraftServer server, XboxEventState state, Component message) {
        for (ServerPlayer player : insidePlayers(server, state)) {
            player.displayClientMessage(message, false);
        }
    }

    /** World display name: translatable key (W7 langdrop) or the literal manifest name. */
    public static Component worldName(String worldId) {
        XboxWorldsManifest.WorldEntry entry = XboxWorldsManifest.byId(worldId).orElse(null);
        if (entry == null) {
            return Component.literal(worldId);
        }
        return XboxEventConfig.get().announceKeys()
                ? Component.translatable(entry.nameKey())
                : Component.literal(entry.displayNameEn());
    }

    private static Component portalHint(BlockPos pos) {
        String coords = pos.getX() + " " + pos.getY() + " " + pos.getZ();
        return Component.translatable("eclipse.xbox.announce.portal",
                Component.literal(coords).withStyle(ChatFormatting.AQUA))
                .withStyle(ChatFormatting.GREEN);
    }

    private static Component leaveLine() {
        MutableComponent line = Component.translatable("eclipse.xbox.enter.leaveline")
                .withStyle(ChatFormatting.GRAY);
        line.append(Component.literal(" "));
        line.append(Component.translatable("eclipse.xbox.enter.leavebutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.YELLOW).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, "/xboxleave"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                Component.translatable("eclipse.xbox.enter.leavebutton.hover")))));
        return line;
    }

    /** {@code 29:59} — used by the bossbar name and dev feedback. */
    public static String mmss(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        return String.format(java.util.Locale.ROOT, "%02d:%02d", totalSeconds / 60L, totalSeconds % 60L);
    }

    // ---- status/dev support (used by DevXboxCommands) ----

    public static XboxEventState stateOf(MinecraftServer server) {
        return XboxEventState.get(server);
    }

    /** Whether {@code player} may currently re-enter (status/debug convenience). */
    public static boolean isLockedOutNow(MinecraftServer server, Player player) {
        return XboxEventState.get(server).isLockedOut(player.getUUID());
    }
}
