package dev.projecteclipse.eclipse.backrooms;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.TheOtherEntity;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
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
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The Backrooms event state machine (plans_v5 PLAN-C C18, IDEAS-backrooms_finale §A —
 * the {@code XboxEventService} skeleton): dev-triggered lifecycle
 * {@code IDLE → ANNOUNCED → OPEN → CLOSING → IDLE} persisted in {@link BackroomsState}.
 *
 * <ul>
 *   <li><b>ANNOUNCED = budgeted maze stamp</b> (IDEAS §A1): {@value #STAMP_UNITS_PER_TICK}
 *       cells per tick (~{@code 24×24+1} units ≈ 2–3 s) into the {@code eclipse:backrooms}
 *       void dim; OPEN flips only when the stamp finishes. The cursor persists — a crash
 *       mid-stamp resumes, and the seed law rebuilds the identical maze.</li>
 *   <li><b>Portal entries</b> mirror the xbox event: frameless star-rift
 *       ({@link BackroomsPortal}), collision entry, return anchors, per-instance
 *       voluntary-exit lockouts, {@code /backroomsleave} click-confirm.</li>
 *   <li><b>Protected deaths</b>: the HIGHEST-priority {@link LivingDeathEvent} cancel —
 *       no drops, no Eclipse life loss, no lockout ("you no-clipped back out"; the horror
 *       dimension must be safe to be scary, IDEAS §A5).</li>
 *   <li><b>Flicker</b> (IDEAS §A2): every {@value #FLICKER_INTERVAL_TICKS} t, faulty
 *       panels within {@value #FLICKER_PLAYER_RANGE} blocks of a player swap
 *       {@code ochre_froglight ↔ yellow_stained_glass} on their hashed schedule
 *       (photosensitivity-safe: one dark window per 120–279 t period).</li>
 *   <li><b>Mob budget</b> (IDEAS §A3): Wanderers capped at {@value #WANDERER_CAP}
 *       (1 per ~40×40 of the 192×192 maze), ≥{@value #WANDERER_MIN_PLAYER_DISTANCE}
 *       blocks from players, never on the spawn highway cross; 1–2 {@code TheOtherEntity}
 *       cameo ≥{@value #THE_OTHER_MIN_SPAWN_DISTANCE} blocks from the spawn cell
 *       (fixed_time midnight disarms its dawn despawn — zero entity changes).</li>
 *   <li><b>Jumpscare</b>: {@link BackroomsScare#tick} every 10 t while OPEN.</li>
 *   <li><b>T-5:00 exit portal</b> (IDEAS §A5): "an EXIT sign hums to life" — a second
 *       star-rift on a hashed far highway cell; walking out through it upgrades the
 *       walker's reward share ({@value #REWARD_SHARDS_UPGRADED} vs
 *       {@value #REWARD_SHARDS_BASE} umbral shards, direct-to-inventory at close, plus
 *       the Almond Water). CLOSING also starts the {@code TimedBuffApi} participation
 *       buff {@value #REWARD_BUFF_ID}.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BackroomsEventService {

    public static final int DEFAULT_MINUTES = 30;

    private static final long WARN_5M_MILLIS = 5L * 60L * 1000L;
    private static final long WARN_1M_MILLIS = 60L * 1000L;
    private static final long LEAVE_CONFIRM_WINDOW_MILLIS = 15_000L;
    private static final long BOUNCE_MESSAGE_THROTTLE_MILLIS = 3_000L;
    private static final long GRACEFUL_STOP_MILLIS = 10_000L;

    /** Maze-stamp budget per tick during ANNOUNCED (~577 units → ≈2 s of spread work). */
    private static final int STAMP_UNITS_PER_TICK = 16;

    /** Flicker pass cadence (2 t resolves the 3–6 t dark windows crisply). */
    private static final int FLICKER_INTERVAL_TICKS = 2;
    private static final double FLICKER_PLAYER_RANGE = 32.0D;

    /** Spawner pass cadence (the {@code EclipseSpawner} 5 s discipline). */
    private static final int SPAWNER_CADENCE_TICKS = 100;
    /** IDEAS §A3.1: 1 per ~40×40 blocks of the 192×192 maze, cap 6. */
    private static final int WANDERER_CAP = 6;
    private static final double WANDERER_MIN_PLAYER_DISTANCE = 24.0D;
    private static final int THE_OTHER_CAP = 2;
    private static final double THE_OTHER_MIN_SPAWN_DISTANCE = 64.0D;

    /** Participation buff started at CLOSING (the xbox default reward id). */
    private static final String REWARD_BUFF_ID = "double_skill_xp";
    private static final int REWARD_BUFF_MINUTES = 30;
    /** Umbral shards direct-to-inventory at close; EXIT-portal walkers get the upgrade. */
    private static final int REWARD_SHARDS_BASE = 2;
    private static final int REWARD_SHARDS_UPGRADED = 4;

    /** Whisper caption odds per 10 t check after 3 min inside (≈ once per ~5 min). */
    private static final int WHISPER_ODDS = 600;
    private static final long WHISPER_MIN_INSIDE_MILLIS = 3L * 60L * 1000L;

    // ---- transient per-run state (cleared on ServerStoppedEvent; SavedData is per-save) ----
    @Nullable
    private static ServerBossEvent bossBar;
    private static final Map<UUID, Long> PENDING_LEAVE_CONFIRMS = new HashMap<>();
    private static final Map<UUID, Long> LAST_BOUNCE_MESSAGE = new HashMap<>();
    private static long lastSeenRemainingMillis = Long.MAX_VALUE;
    private static long totalWindowMillisHint;
    /** Cached panel list of the current instance's seed (rebuilt lazily after boot). */
    @Nullable
    private static List<BackroomsMaze.Panel> cachedPanels;
    private static long cachedPanelsSeed;

    private BackroomsEventService() {}

    /** Exit paths — pick the right player-facing message. */
    public enum ExitReason { DEATH, LEFT, TIME_UP, CLOSED, EXIT_PORTAL }

    // ================================================================== lifecycle

    /** Crash resume (xbox §2.13.6 law): expired windows close on boot; stamps resume. */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        resumeOnBoot(event.getServer());
    }

    /** Boot-resume logic, callable from gametests. */
    public static void resumeOnBoot(MinecraftServer server) {
        BackroomsState state = BackroomsState.get(server);
        long now = System.currentTimeMillis();
        switch (state.phase()) {
            case OPEN, ANNOUNCED -> {
                if (state.endsAtEpochMillis() <= now) {
                    EclipseMod.LOGGER.info("Backrooms event expired while server was down — closing now");
                    beginClosing(server, state, ExitReason.CLOSED);
                } else {
                    totalWindowMillisHint = Math.max(state.endsAtEpochMillis() - now,
                            DEFAULT_MINUTES * 60_000L);
                    EclipseMod.LOGGER.info("Backrooms event resumes: {} remaining, stamp {}/{}",
                            mmss(state.endsAtEpochMillis() - now), state.stampCursor(),
                            BackroomsMaze.totalStampUnits());
                }
            }
            case CLOSING -> beginClosing(server, state, ExitReason.CLOSED);
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
        cachedPanels = null;
        cachedPanelsSeed = 0L;
        BackroomsScare.reset();
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        BackroomsState state = BackroomsState.get(server);
        if (state.phase() != BackroomsState.Phase.OPEN
                && state.phase() != BackroomsState.Phase.ANNOUNCED) {
            return;
        }

        // Budgeted stamp: every tick during ANNOUNCED until the maze is complete.
        if (state.phase() == BackroomsState.Phase.ANNOUNCED && !state.stampComplete()) {
            tickStamp(server, state);
            return;
        }

        int tickCount = server.getTickCount();
        if (state.phase() == BackroomsState.Phase.OPEN && tickCount % FLICKER_INTERVAL_TICKS == 0) {
            tickFlicker(server, state);
        }
        if (tickCount % 10 != 0) {
            return;
        }

        long now = System.currentTimeMillis();
        long remaining = state.endsAtEpochMillis() - now;
        if (remaining <= 0L) {
            beginClosing(server, state, ExitReason.TIME_UP);
            return;
        }

        if (state.phase() == BackroomsState.Phase.OPEN) {
            checkWarnings(server, state, remaining);
            tickEntryPortal(server, state);
            tickInside(server, state, remaining);
            if (tickCount % SPAWNER_CADENCE_TICKS == 0) {
                tickSpawner(server, state);
            }
        }
        lastSeenRemainingMillis = remaining;
    }

    // ================================================================== start / stop

    /** Outcome of {@link #start}: {@code started=false} → {@code message} is the error. */
    public record StartResult(boolean started, @Nullable Component message) {}

    /**
     * Starts the event: validates the dimension, begins the instance (which reseeds the
     * maze) and enters ANNOUNCED — the budgeted stamp runs over the next ~2 s and the
     * portal spawns + OPEN flips from {@link #tickStamp} once it completes.
     */
    public static StartResult start(MinecraftServer server, int minutes, String operatorName) {
        BackroomsState state = BackroomsState.get(server);
        if (state.phase() == BackroomsState.Phase.OPEN
                || state.phase() == BackroomsState.Phase.ANNOUNCED) {
            return new StartResult(false, Component.translatable("dev.eclipse.backrooms.start.already",
                    mmss(state.endsAtEpochMillis() - System.currentTimeMillis())));
        }
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level == null) {
            return new StartResult(false, Component.translatable("dev.eclipse.backrooms.start.no_level",
                    BackroomsDimension.BACKROOMS.location().toString()));
        }

        int effectiveMinutes = minutes > 0 ? minutes : DEFAULT_MINUTES;
        long now = System.currentTimeMillis();
        state.beginInstance(now + effectiveMinutes * 60_000L);
        totalWindowMillisHint = effectiveMinutes * 60_000L;
        lastSeenRemainingMillis = Long.MAX_VALUE;
        cachedPanels = null;
        BackroomsScare.reset();

        broadcast(server, Component.translatable("eclipse.backrooms.announce.start", effectiveMinutes)
                .withStyle(ChatFormatting.YELLOW));
        EclipseMod.LOGGER.info("Backrooms event started by {}: minutes={}, instance={}, seed={}",
                operatorName, effectiveMinutes, state.instanceId(), Long.toHexString(state.mazeSeed()));
        return new StartResult(true, null);
    }

    /** Runs the stamp budget; flips ANNOUNCED → OPEN (+ portal) when the maze completes. */
    private static void tickStamp(MinecraftServer server, BackroomsState state) {
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level == null) {
            return;
        }
        long seed = state.mazeSeed();
        int cursor = state.stampCursor();
        int total = BackroomsMaze.totalStampUnits();
        int end = Math.min(total, cursor + STAMP_UNITS_PER_TICK);
        for (int unit = cursor; unit < end; unit++) {
            BackroomsMaze.stampUnit(level, seed, unit);
        }
        state.setStampCursor(end);
        if (end >= total) {
            onStampComplete(server, state);
        }
    }

    private static void onStampComplete(MinecraftServer server, BackroomsState state) {
        ServerLevel overworld = server.overworld();
        BlockPos spot = BackroomsPortal.findSpotNearSpawn(overworld);
        if (spot != null) {
            BackroomsPortal.place(overworld, spot);
            state.setPortal(overworld.dimension(), spot);
            state.setPhase(BackroomsState.Phase.OPEN);
            broadcast(server, portalHint(spot));
        } else {
            EclipseMod.LOGGER.warn("Backrooms event: no portal spot near spawn — stays ANNOUNCED; "
                    + "use /dev backrooms portal here");
        }
        EclipseMod.LOGGER.info("Backrooms maze stamped ({} units, instance {})",
                BackroomsMaze.totalStampUnits(), state.instanceId());
    }

    /** {@code /dev backrooms portal here|remove} backing (xbox semantics). */
    @Nullable
    public static Component portalHere(MinecraftServer server, ServerPlayer operator) {
        if (BackroomsDimension.isInBackrooms(operator)) {
            return Component.translatable("dev.eclipse.backrooms.portal.inside");
        }
        BackroomsState state = BackroomsState.get(server);
        if (state.phase() != BackroomsState.Phase.OPEN
                && state.phase() != BackroomsState.Phase.ANNOUNCED) {
            return Component.translatable("dev.eclipse.backrooms.stop.idle");
        }
        if (state.phase() == BackroomsState.Phase.ANNOUNCED && !state.stampComplete()) {
            return Component.translatable("dev.eclipse.backrooms.portal.stamping",
                    state.stampCursor(), BackroomsMaze.totalStampUnits());
        }
        removeEntryPortal(server, state);
        ServerLevel level = (ServerLevel) operator.level();
        BlockPos base = operator.blockPosition();
        BackroomsPortal.place(level, base);
        state.setPortal(level.dimension(), base);
        if (state.phase() == BackroomsState.Phase.ANNOUNCED) {
            state.setPhase(BackroomsState.Phase.OPEN);
        }
        broadcast(server, portalHint(base));
        return null;
    }

    @Nullable
    public static Component portalRemove(MinecraftServer server) {
        BackroomsState state = BackroomsState.get(server);
        if (state.portalPos() == null) {
            return Component.translatable("dev.eclipse.backrooms.portal.none");
        }
        removeEntryPortal(server, state);
        return null;
    }

    /** Graceful stop = short grace window; {@code immediate} closes this tick. */
    @Nullable
    public static Component stop(MinecraftServer server, boolean immediate) {
        BackroomsState state = BackroomsState.get(server);
        if (state.phase() != BackroomsState.Phase.OPEN
                && state.phase() != BackroomsState.Phase.ANNOUNCED) {
            return Component.translatable("dev.eclipse.backrooms.stop.idle");
        }
        if (immediate) {
            beginClosing(server, state, ExitReason.CLOSED);
            return null;
        }
        long now = System.currentTimeMillis();
        long graceEnd = now + GRACEFUL_STOP_MILLIS;
        if (state.endsAtEpochMillis() > graceEnd) {
            state.setEndsAtEpochMillis(graceEnd);
            broadcast(server, Component.translatable("eclipse.backrooms.announce.stopping",
                    GRACEFUL_STOP_MILLIS / 1000L).withStyle(ChatFormatting.YELLOW));
        }
        return null;
    }

    /** {@code /dev backrooms time add|sub|set} — mutates {@code endsAt}, clamped ≥ now. */
    @Nullable
    public static Component timeMutate(MinecraftServer server, char mode, long durationMillis) {
        BackroomsState state = BackroomsState.get(server);
        if (state.phase() != BackroomsState.Phase.OPEN
                && state.phase() != BackroomsState.Phase.ANNOUNCED) {
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
        lastSeenRemainingMillis = Long.MAX_VALUE; // re-arm T-5/T-1 warnings
        return Component.translatable("dev.eclipse.backrooms.time.changed",
                mmss(newRemaining), mmss(oldRemaining));
    }

    // ================================================================== closing

    /**
     * CLOSING (xbox choreography): everyone exits with full inventory, per-player shard +
     * Almond Water rewards land direct-to-inventory (EXIT-portal walkers upgraded), the
     * participation buff starts once, portals despawn, event mobs dissolve. The maze
     * itself stays — the next instance's stamp self-cleans over it.
     */
    private static void beginClosing(MinecraftServer server, BackroomsState state, ExitReason reason) {
        state.setPhase(BackroomsState.Phase.CLOSING);
        broadcast(server, Component.translatable("eclipse.backrooms.announce.end")
                .withStyle(ChatFormatting.GREEN));

        for (ServerPlayer player : insidePlayers(server)) {
            exitToAnchor(server, state, player, reason == ExitReason.CLOSED
                    ? ExitReason.CLOSED : ExitReason.TIME_UP);
        }

        Set<UUID> participants = state.participantsSnapshot();
        if (!participants.isEmpty() && state.markRewardGranted()) {
            grantRewards(server, state, participants);
        }

        removeEntryPortal(server, state);
        removeExitPortal(server, state);
        despawnEventMobs(server);

        removeBossBar();
        PENDING_LEAVE_CONFIRMS.clear();
        LAST_BOUNCE_MESSAGE.clear();
        lastSeenRemainingMillis = Long.MAX_VALUE;
        state.setPhase(BackroomsState.Phase.IDLE);
        EclipseMod.LOGGER.info("Backrooms event closed (instance {}, {} participants)",
                state.instanceId(), participants.size());
    }

    private static void grantRewards(MinecraftServer server, BackroomsState state, Set<UUID> participants) {
        for (UUID uuid : participants) {
            ServerPlayer player = server.getPlayerList().getPlayer(uuid);
            if (player == null) {
                continue; // offline: items only land for online participants (xbox law)
            }
            boolean upgraded = state.isExitUpgraded(uuid);
            int shards = upgraded ? REWARD_SHARDS_UPGRADED : REWARD_SHARDS_BASE;
            giveOrDrop(player, new ItemStack(EclipseItems.UMBRAL_SHARD.get(), shards));
            giveOrDrop(player, BackroomsMaze.almondWater());
            player.displayClientMessage(ServerLang.tr(player,
                    upgraded ? "eclipse.backrooms.reward.upgraded" : "eclipse.backrooms.reward.base",
                    shards).withStyle(ChatFormatting.GOLD), false);
        }
        boolean started = TimedBuffApi.Holder.get().start(server, REWARD_BUFF_ID, REWARD_BUFF_MINUTES);
        if (started) {
            broadcast(server, Component.translatable("eclipse.backrooms.announce.reward",
                    REWARD_BUFF_ID, REWARD_BUFF_MINUTES, participants.size())
                    .withStyle(ChatFormatting.GOLD));
        } else {
            EclipseMod.LOGGER.warn("Backrooms participation reward '{}' ({} min) was refused "
                    + "or TimedBuffApi is not installed", REWARD_BUFF_ID, REWARD_BUFF_MINUTES);
        }
    }

    private static void giveOrDrop(ServerPlayer player, ItemStack stack) {
        if (!player.getInventory().add(stack)) {
            player.drop(stack, false);
        }
    }

    private static void removeEntryPortal(MinecraftServer server, BackroomsState state) {
        BlockPos portalPos = state.portalPos();
        ResourceKey<Level> portalDim = state.portalDimension();
        if (portalPos == null || portalDim == null) {
            return;
        }
        ServerLevel level = server.getLevel(portalDim);
        if (level != null) {
            BackroomsPortal.remove(level, portalPos);
        }
        state.setPortal(null, null);
    }

    private static void removeExitPortal(MinecraftServer server, BackroomsState state) {
        BlockPos exitPos = state.exitPortalPos();
        if (exitPos == null) {
            return;
        }
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level != null) {
            BackroomsPortal.remove(level, exitPos);
        }
        state.setExitPortalPos(null);
    }

    /** Dissolves Wanderers + cameo Others left in the dimension (no drops, quiet poof). */
    private static void despawnEventMobs(MinecraftServer server) {
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level == null) {
            return;
        }
        List<Entity> doomed = new java.util.ArrayList<>();
        for (Entity entity : level.getAllEntities()) {
            if ((entity instanceof GlitchedWandererEntity || entity instanceof TheOtherEntity)
                    && entity.isAlive()) {
                doomed.add(entity);
            }
        }
        for (Entity entity : doomed) {
            level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                    entity.getX(), entity.getY() + 1.0D, entity.getZ(),
                    10, 0.3D, 0.5D, 0.3D, 0.02D);
            entity.discard();
        }
    }

    // ================================================================== portals & entries

    private static void tickEntryPortal(MinecraftServer server, BackroomsState state) {
        BlockPos portalPos = state.portalPos();
        ResourceKey<Level> portalDim = state.portalDimension();
        if (portalPos == null || portalDim == null) {
            return;
        }
        ServerLevel level = server.getLevel(portalDim);
        if (level == null) {
            return;
        }
        BackroomsPortal.ambientTick(level, portalPos, level.getGameTime());
        var box = BackroomsPortal.collisionBox(portalPos);
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (!player.isSpectator() && player.isAlive() && box.intersects(player.getBoundingBox())) {
                tryEnter(server, state, player);
            }
        }
    }

    private static void tryEnter(MinecraftServer server, BackroomsState state, ServerPlayer player) {
        if (state.phase() != BackroomsState.Phase.OPEN) {
            return;
        }
        UUID uuid = player.getUUID();
        if (state.isLockedOut(uuid)) {
            long now = System.currentTimeMillis();
            long last = LAST_BOUNCE_MESSAGE.getOrDefault(uuid, 0L);
            if (now - last >= BOUNCE_MESSAGE_THROTTLE_MILLIS) {
                LAST_BOUNCE_MESSAGE.put(uuid, now);
                player.displayClientMessage(ServerLang.tr(player, "eclipse.backrooms.enter.locked")
                        .withStyle(ChatFormatting.RED), false);
                player.playNotifySound(SoundEvents.VILLAGER_NO, SoundSource.PLAYERS, 0.8F, 1.0F);
            }
            return;
        }
        enter(server, state, player);
    }

    /** Entry sequence: anchor → no-clip transition → teleport to the spawn cross → title. */
    private static void enter(MinecraftServer server, BackroomsState state, ServerPlayer player) {
        ServerLevel target = server.getLevel(BackroomsDimension.BACKROOMS);
        if (target == null) {
            return;
        }
        state.putReturnAnchor(player.getUUID(), new BackroomsState.ReturnAnchor(
                player.level().dimension(), player.getX(), player.getY(), player.getZ(),
                player.getYRot(), player.getXRot()));

        BackroomsPayloads.sendPortalTransition(player);

        BlockPos spawn = BackroomsMaze.cellCenter(BackroomsMaze.SPAWN_CELL, BackroomsMaze.SPAWN_CELL);
        player.teleportTo(target, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                player.getYRot(), 0.0F);
        player.fallDistance = 0.0F;

        state.addParticipant(player.getUUID());
        state.recordEntry(player.getUUID(), System.currentTimeMillis());

        player.connection.send(new ClientboundSetTitlesAnimationPacket(10, 60, 20));
        player.connection.send(new ClientboundSetTitleTextPacket(
                ServerLang.tr(player, "eclipse.backrooms.enter.title").withStyle(ChatFormatting.YELLOW)));
        player.connection.send(new ClientboundSetSubtitleTextPacket(
                ServerLang.tr(player, "eclipse.backrooms.enter.subtitle").withStyle(ChatFormatting.GRAY)));
        player.playNotifySound(EclipseSounds.UI_ERROR_GLITCH.get(), SoundSource.PLAYERS, 0.7F, 0.8F);

        player.displayClientMessage(leaveLine(player), false);
        EclipseMod.LOGGER.info("{} no-clipped into the backrooms (instance {})",
                player.getScoreboardName(), state.instanceId());
    }

    /** Exit sequence: transition cover → teleport to the captured anchor → message. */
    private static void exitToAnchor(MinecraftServer server, BackroomsState state,
            ServerPlayer player, ExitReason reason) {
        BackroomsState.ReturnAnchor anchor = state.returnAnchor(player.getUUID());
        ServerLevel target = anchor == null ? null : server.getLevel(anchor.dimension());

        BackroomsPayloads.sendPortalTransition(player);

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

        String key = switch (reason) {
            case DEATH -> "eclipse.backrooms.exit.death";
            case LEFT -> "eclipse.backrooms.exit.left";
            case TIME_UP -> "eclipse.backrooms.exit.timeup";
            case CLOSED -> "eclipse.backrooms.exit.closed";
            case EXIT_PORTAL -> "eclipse.backrooms.exit.found";
        };
        player.displayClientMessage(ServerLang.tr(player, key).withStyle(ChatFormatting.AQUA), false);
    }

    // ================================================================== inside tick

    /** 10 t housekeeping for the open maze: exit portal, bossbar, ambience, whispers. */
    private static void tickInside(MinecraftServer server, BackroomsState state, long remaining) {
        updateBossBar(server, state, remaining);
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level == null) {
            return;
        }

        // T-5:00: the EXIT sign hums to life (IDEAS §A5) — idempotent (pos persisted).
        if (remaining <= WARN_5M_MILLIS && state.exitPortalPos() == null) {
            spawnExitPortal(server, state, level);
        }

        BlockPos exitPos = state.exitPortalPos();
        if (exitPos != null) {
            BackroomsPortal.ambientTick(level, exitPos, level.getGameTime());
            var box = BackroomsPortal.collisionBox(exitPos);
            for (ServerPlayer player : List.copyOf(level.players())) {
                if (!player.isSpectator() && player.isAlive()
                        && box.intersects(player.getBoundingBox())) {
                    state.markExitUpgraded(player.getUUID());
                    exitToAnchor(server, state, player, ExitReason.EXIT_PORTAL);
                }
            }
        }

        BackroomsScare.tick(server, state, level);
        tickAmbience(server, state, level);
    }

    /** Hashed far highway cell (≥100 blocks from the spawn cross), deterministic per seed. */
    private static void spawnExitPortal(MinecraftServer server, BackroomsState state, ServerLevel level) {
        long seed = state.mazeSeed();
        BlockPos spawnCenter = BackroomsMaze.cellCenter(BackroomsMaze.SPAWN_CELL, BackroomsMaze.SPAWN_CELL);
        BlockPos best = null;
        long bestHash = Long.MIN_VALUE;
        for (int cz = 1; cz < BackroomsMaze.CELLS - 1; cz++) {
            for (int cx = 1; cx < BackroomsMaze.CELLS - 1; cx++) {
                if (!BackroomsMaze.isHighwayCell(seed, cx, cz)) {
                    continue;
                }
                BlockPos center = BackroomsMaze.cellCenter(cx, cz);
                if (center.distSqr(spawnCenter) < 100.0D * 100.0D) {
                    continue;
                }
                long hash = Long.rotateLeft(seed ^ (cx * 0x9E3779B97F4A7C15L) ^ (cz * 0xC2B2AE3D27D4EB4FL), 17);
                if (hash > bestHash) {
                    bestHash = hash;
                    best = center;
                }
            }
        }
        if (best == null) {
            best = BackroomsMaze.cellCenter(1, 1); // degenerate seed: any far corner
        }
        BackroomsPortal.place(level, best);
        state.setExitPortalPos(best);
        broadcastInside(server, Component.translatable("eclipse.backrooms.announce.exit_sign")
                .withStyle(ChatFormatting.YELLOW));
        for (ServerPlayer player : insidePlayers(server)) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.backrooms.caption.exit", 80, S2CCaptionPayload.STYLE_WHISPER));
        }
    }

    /** WET_ROOM drips + distant ballast clunk + the once-per-instance whisper (IDEAS §A6). */
    private static void tickAmbience(MinecraftServer server, BackroomsState state, ServerLevel level) {
        long now = System.currentTimeMillis();
        for (ServerPlayer player : List.copyOf(level.players())) {
            int[] cell = BackroomsMaze.cellOf(player.blockPosition());
            if (cell != null && BackroomsMaze.prefab(state.mazeSeed(), cell[0], cell[1])
                    == BackroomsMaze.Prefab.WET_ROOM) {
                BlockPos min = BackroomsMaze.cellMin(cell[0], cell[1]);
                level.sendParticles(ParticleTypes.DRIPPING_WATER,
                        min.getX() + 1 + level.random.nextInt(6), BackroomsMaze.CEIL_Y - 0.2D,
                        min.getZ() + 1 + level.random.nextInt(6), 2, 0.4D, 0.0D, 0.4D, 0.0D);
            }
            // Distant ballast clunk (§A6.3): ~every 90 s per player, 20–30 blocks away.
            if (level.random.nextInt(180) == 0) {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double distance = 20.0D + level.random.nextDouble() * 10.0D;
                BlockPos clunk = player.blockPosition().offset(
                        (int) (Math.cos(angle) * distance), 0, (int) (Math.sin(angle) * distance));
                level.playSound(null, clunk, EclipseSounds.EVENT_BEAM_HUM.get(),
                        SoundSource.AMBIENT, 0.25F, 0.3F);
            }
            // WHISPER caption (§A6.5): rare, once per instance per player, after 3 min.
            long enteredAt = state.enteredAtEpochMillis(player.getUUID());
            if (enteredAt > 0L && now - enteredAt >= WHISPER_MIN_INSIDE_MILLIS
                    && level.random.nextInt(WHISPER_ODDS) == 0
                    && state.markWhispered(player.getUUID())) {
                PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                        "eclipse.backrooms.whisper", 60, S2CCaptionPayload.STYLE_WHISPER));
            }
        }
    }

    // ================================================================== flicker

    /**
     * Light-block flicker (IDEAS §A2): faulty froglight panels within
     * {@value #FLICKER_PLAYER_RANGE} blocks of a player swap to yellow glass during their
     * hashed dark window and back — REAL light changes, flag 3 (client relight).
     */
    private static void tickFlicker(MinecraftServer server, BackroomsState state) {
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level == null || level.players().isEmpty()) {
            return;
        }
        long seed = state.mazeSeed();
        List<BackroomsMaze.Panel> panels = cachedPanels;
        if (panels == null || cachedPanelsSeed != seed) {
            panels = BackroomsMaze.panels(seed);
            cachedPanels = panels;
            cachedPanelsSeed = seed;
        }
        long gameTime = level.getGameTime();
        double rangeSq = FLICKER_PLAYER_RANGE * FLICKER_PLAYER_RANGE;
        List<ServerPlayer> players = level.players();
        for (BackroomsMaze.Panel panel : panels) {
            if (!panel.faulty()) {
                continue;
            }
            boolean near = false;
            for (ServerPlayer player : players) {
                if (panel.a().distToCenterSqr(player.getX(), player.getY(), player.getZ()) <= rangeSq) {
                    near = true;
                    break;
                }
            }
            if (!near) {
                continue;
            }
            boolean lit = BackroomsMaze.panelLitAt(seed, panel, gameTime);
            var want = lit ? Blocks.OCHRE_FROGLIGHT.defaultBlockState()
                    : Blocks.YELLOW_STAINED_GLASS.defaultBlockState();
            if (!level.getBlockState(panel.a()).is(want.getBlock())) {
                level.setBlock(panel.a(), want, 3);
                level.setBlock(panel.b(), want, 3);
            }
        }
    }

    // ================================================================== mob budget

    /** Wanderer cap {@value #WANDERER_CAP} + 1–2 cameo Others (IDEAS §A3), every 5 s. */
    private static void tickSpawner(MinecraftServer server, BackroomsState state) {
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        if (level == null || level.players().isEmpty() || !BackroomsEntities.GLITCHED_WANDERER.isBound()) {
            return;
        }
        long seed = state.mazeSeed();
        int wanderers = 0;
        int others = 0;
        for (Entity entity : level.getAllEntities()) {
            if (entity instanceof GlitchedWandererEntity) {
                wanderers++;
            } else if (entity instanceof TheOtherEntity) {
                others++;
            }
        }
        if (wanderers < WANDERER_CAP) {
            BlockPos pos = findMazeSpawn(level, seed, WANDERER_MIN_PLAYER_DISTANCE, 0.0D);
            if (pos != null && spawnMob(level, BackroomsEntities.GLITCHED_WANDERER.get(), pos)) {
                EclipseMod.LOGGER.debug("Wanderer {}/{} spawned at {}", wanderers + 1, WANDERER_CAP, pos);
            }
        }
        if (others < THE_OTHER_CAP) {
            BlockPos pos = findMazeSpawn(level, seed, WANDERER_MIN_PLAYER_DISTANCE,
                    THE_OTHER_MIN_SPAWN_DISTANCE);
            if (pos != null && spawnMob(level, EclipseEntities.THE_OTHER.get(), pos)) {
                EclipseMod.LOGGER.debug("The Other cameo spawned at {} (backrooms)", pos);
            }
        }
    }

    /**
     * Random maze cell center: ≥ {@code minPlayerDistance} from every player,
     * ≥ {@code minSpawnDistance} from the spawn cross, never ON the spawn highway cross.
     */
    @Nullable
    private static BlockPos findMazeSpawn(ServerLevel level, long seed,
            double minPlayerDistance, double minSpawnDistance) {
        BlockPos spawnCenter = BackroomsMaze.cellCenter(BackroomsMaze.SPAWN_CELL, BackroomsMaze.SPAWN_CELL);
        for (int attempt = 0; attempt < 16; attempt++) {
            int cx = 1 + level.random.nextInt(BackroomsMaze.CELLS - 2);
            int cz = 1 + level.random.nextInt(BackroomsMaze.CELLS - 2);
            if (cx == BackroomsMaze.SPAWN_CELL && cz == BackroomsMaze.SPAWN_CELL) {
                continue;
            }
            BlockPos center = BackroomsMaze.cellCenter(cx, cz);
            if (minSpawnDistance > 0.0D
                    && center.distSqr(spawnCenter) < minSpawnDistance * minSpawnDistance) {
                continue;
            }
            boolean tooClose = false;
            for (ServerPlayer player : level.players()) {
                if (center.distToCenterSqr(player.getX(), player.getY(), player.getZ())
                        < minPlayerDistance * minPlayerDistance) {
                    tooClose = true;
                    break;
                }
            }
            if (!tooClose && level.getBlockState(center).isAir()) {
                return center;
            }
        }
        return null;
    }

    private static boolean spawnMob(ServerLevel level, EntityType<? extends Mob> type, BlockPos pos) {
        Mob mob = type.create(level);
        if (mob == null) {
            return false;
        }
        mob.moveTo(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D,
                level.random.nextFloat() * 360.0F, 0.0F);
        mob.setPersistenceRequired(); // event-managed lifecycle; despawned at CLOSING
        return level.addFreshEntity(mob);
    }

    // ================================================================== death protection

    /**
     * Cancels player deaths inside the backrooms BEFORE the lives pipeline can run
     * (HIGHEST priority — no drops, no Eclipse life loss, no grave, no lockout; IDEAS §A5
     * "death costs nothing: you no-clipped back out").
     */
    @SubscribeEvent(priority = EventPriority.HIGHEST)
    public static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !BackroomsDimension.isInBackrooms(player)) {
            return;
        }
        event.setCanceled(true);
        player.setHealth(1.0F);
        player.setRemainingFireTicks(0);
        player.removeAllEffects();
        player.fallDistance = 0.0F;

        MinecraftServer server = player.server;
        BackroomsState state = BackroomsState.get(server);
        exitToAnchor(server, state, player, ExitReason.DEATH);
        EclipseMod.LOGGER.info("Protected backrooms death of {} ({}), returned to anchor",
                player.getScoreboardName(), event.getSource().getMsgId());
    }

    // ================================================================== login/logout edges

    /** Logout inside → the exit sequence runs at next login when the event is over. */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        MinecraftServer server = player.server;
        BackroomsState state = BackroomsState.get(server);
        if (BackroomsDimension.isInBackrooms(player)) {
            if (state.phase() == BackroomsState.Phase.OPEN) {
                player.displayClientMessage(leaveLine(player), false);
            } else {
                exitToAnchor(server, state, player, ExitReason.CLOSED);
            }
        } else if (state.returnAnchor(player.getUUID()) != null
                && state.phase() == BackroomsState.Phase.IDLE) {
            state.removeReturnAnchor(player.getUUID()); // stale leftover, already outside
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

    // ================================================================== /backroomsleave

    /** First {@code /backroomsleave}: confirmation click-through; outside: polite no-op. */
    public static int leaveRequested(ServerPlayer player) {
        if (!BackroomsDimension.isInBackrooms(player)) {
            player.displayClientMessage(ServerLang.tr(player, "eclipse.backrooms.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        PENDING_LEAVE_CONFIRMS.put(player.getUUID(),
                System.currentTimeMillis() + LEAVE_CONFIRM_WINDOW_MILLIS);
        MutableComponent confirm = ServerLang.tr(player, "eclipse.backrooms.leave.confirm")
                .withStyle(ChatFormatting.YELLOW);
        confirm.append(Component.literal(" "));
        confirm.append(ServerLang.tr(player, "eclipse.backrooms.leave.confirmbutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.RED).withBold(true).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND,
                                "/backroomsleave confirm"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                ServerLang.tr(player, "eclipse.backrooms.leave.confirm.hover")))));
        player.displayClientMessage(confirm, false);
        return 1;
    }

    /** {@code /backroomsleave confirm}: voluntary exit + lockout for THIS instance. */
    public static int leaveConfirmed(ServerPlayer player) {
        if (!BackroomsDimension.isInBackrooms(player)) {
            player.displayClientMessage(ServerLang.tr(player, "eclipse.backrooms.leave.outside")
                    .withStyle(ChatFormatting.GRAY), false);
            return 0;
        }
        Long window = PENDING_LEAVE_CONFIRMS.remove(player.getUUID());
        if (window == null || window < System.currentTimeMillis()) {
            return leaveRequested(player); // expired → re-ask instead of surprising the player
        }
        MinecraftServer server = player.server;
        BackroomsState state = BackroomsState.get(server);
        boolean activeEvent = state.phase() == BackroomsState.Phase.OPEN;
        if (activeEvent) {
            state.lockOut(player.getUUID());
        }
        exitToAnchor(server, state, player, ExitReason.LEFT);
        EclipseMod.LOGGER.info("{} voluntarily no-clipped out (locked out: {})",
                player.getScoreboardName(), activeEvent);
        return 1;
    }

    // ================================================================== timer & bossbar

    private static void checkWarnings(MinecraftServer server, BackroomsState state, long remaining) {
        if (lastSeenRemainingMillis > WARN_5M_MILLIS && remaining <= WARN_5M_MILLIS) {
            broadcast(server, Component.translatable("eclipse.backrooms.announce.warn5")
                    .withStyle(ChatFormatting.YELLOW));
        }
        if (lastSeenRemainingMillis > WARN_1M_MILLIS && remaining <= WARN_1M_MILLIS) {
            broadcast(server, Component.translatable("eclipse.backrooms.announce.warn1")
                    .withStyle(ChatFormatting.RED));
        }
    }

    private static void updateBossBar(MinecraftServer server, BackroomsState state, long remaining) {
        List<ServerPlayer> inside = insidePlayers(server);
        if (inside.isEmpty() && bossBar == null) {
            return;
        }
        if (bossBar == null) {
            bossBar = new ServerBossEvent(Component.empty(),
                    BossEvent.BossBarColor.YELLOW, BossEvent.BossBarOverlay.PROGRESS);
        }
        bossBar.setName(Component.translatable("bossbar.eclipse.backrooms", mmss(remaining)));
        long total = Math.max(totalWindowMillisHint, 1L);
        bossBar.setProgress(Mth.clamp((float) remaining / total, 0.0F, 1.0F));

        for (ServerPlayer player : inside) {
            bossBar.addPlayer(player); // set-backed: no-op when already shown
        }
        for (ServerPlayer shown : List.copyOf(bossBar.getPlayers())) {
            if (!BackroomsDimension.isInBackrooms(shown)) {
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

    static List<ServerPlayer> insidePlayers(MinecraftServer server) {
        ServerLevel level = server.getLevel(BackroomsDimension.BACKROOMS);
        return level == null ? List.of() : List.copyOf(level.players());
    }

    /** Per-recipient broadcast baked through {@link ServerLang#resolve} (Wave-5 A1 law). */
    private static void broadcast(MinecraftServer server, Component message) {
        server.sendSystemMessage(message);
        for (ServerPlayer player : List.copyOf(server.getPlayerList().getPlayers())) {
            player.sendSystemMessage(ServerLang.resolve(player, message));
        }
    }

    private static void broadcastInside(MinecraftServer server, Component message) {
        for (ServerPlayer player : insidePlayers(server)) {
            player.displayClientMessage(ServerLang.resolve(player, message), false);
        }
    }

    private static Component portalHint(BlockPos pos) {
        String coords = pos.getX() + " " + pos.getY() + " " + pos.getZ();
        return Component.translatable("eclipse.backrooms.announce.portal",
                Component.literal(coords).withStyle(ChatFormatting.YELLOW))
                .withStyle(ChatFormatting.GREEN);
    }

    private static Component leaveLine(ServerPlayer player) {
        MutableComponent line = ServerLang.tr(player, "eclipse.backrooms.enter.leaveline")
                .withStyle(ChatFormatting.GRAY);
        line.append(Component.literal(" "));
        line.append(ServerLang.tr(player, "eclipse.backrooms.enter.leavebutton")
                .withStyle(Style.EMPTY.withColor(ChatFormatting.YELLOW).withUnderlined(true)
                        .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, "/backroomsleave"))
                        .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                ServerLang.tr(player, "eclipse.backrooms.enter.leavebutton.hover")))));
        return line;
    }

    /** {@code 29:59} — bossbar name and dev feedback. */
    public static String mmss(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        return String.format(java.util.Locale.ROOT, "%02d:%02d", totalSeconds / 60L, totalSeconds % 60L);
    }

    // ---- status/dev support ----

    public static BackroomsState stateOf(MinecraftServer server) {
        return BackroomsState.get(server);
    }

    public static boolean isLockedOutNow(MinecraftServer server, Player player) {
        return BackroomsState.get(server).isLockedOut(player.getUUID());
    }
}
