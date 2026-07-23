package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.BossEvent;
import net.minecraft.world.Containers;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The 3-minute revive ritual, driven purely by server ticks (no threads).
 * Started via {@link #start}; while running:
 * <ul>
 *   <li>a global RED {@link ServerBossEvent} bossbar ({@code ritual.eclipse.revive.bossbar},
 *       de "Ein Ritual hat begonnen") is shown to every online player (joiners included),
 *       progress = remaining/total;</li>
 *   <li>every {@value #BEAM_INTERVAL_TICKS} ticks {@link BeamEmitter} sends the
 *       end-rod + purple-dust beam column to all players within 512 blocks;</li>
 *   <li>if the confirming player dies, disconnects, changes dimension or moves
 *       more than {@value #MAX_CONFIRMER_DISTANCE} blocks from the altar, the ritual
 *       FAILS and the sigil drops back onto the altar (stealable).</li>
 * </ul>
 * On success the target is unbanned via {@link BanService#unban} (offline targets are
 * removed from the persistent banned set and fully unbanned on their next login, see
 * {@link #onPlayerLoggedIn}) and a global thunder cue plays. The bossbar is removed on
 * completion, failure and server stop. No chat output anywhere.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ReviveRitual {
    /** Total ritual duration: 3 minutes of server ticks. */
    public static final int DURATION_TICKS = 3 * 60 * 20;
    /** Maximum distance the confirming player may move from the altar. */
    public static final double MAX_CONFIRMER_DISTANCE = 16.0D;
    private static final int BEAM_INTERVAL_TICKS = 10;

    private static final List<ReviveRitual> ACTIVE = new ArrayList<>();

    private final ServerLevel level;
    private final BlockPos altarPos;
    private final UUID confirmerId;
    private final UUID targetId;
    private final String targetName;
    private final ServerBossEvent bossEvent;
    private int ticksElapsed;

    private ReviveRitual(ServerLevel level, BlockPos altarPos, UUID confirmerId, UUID targetId, String targetName) {
        this.level = level;
        this.altarPos = altarPos.immutable();
        this.confirmerId = confirmerId;
        this.targetId = targetId;
        this.targetName = targetName;
        this.bossEvent = new ServerBossEvent(Component.translatable("ritual.eclipse.revive.bossbar"),
                BossEvent.BossBarColor.RED, BossEvent.BossBarOverlay.PROGRESS);
        this.bossEvent.setProgress(1.0F);
    }

    /**
     * Starts a ritual at the given altar for the given banned target. Returns
     * {@code false} (and does nothing) if a ritual is already running there.
     */
    public static boolean start(ServerLevel level, BlockPos altarPos, ServerPlayer confirmer,
            UUID targetId, String targetName) {
        if (isRunningAt(level, altarPos)) {
            return false;
        }
        ReviveRitual ritual = new ReviveRitual(level, altarPos, confirmer.getUUID(), targetId, targetName);
        for (ServerPlayer online : level.getServer().getPlayerList().getPlayers()) {
            ritual.bossEvent.addPlayer(online);
        }
        // W8 bossbar skin: tag the countdown bar with the "goal" theme on every client.
        net.neoforged.neoforge.network.PacketDistributor.sendToAllPlayers(
                new S2CBossbarStylePayload(ritual.bossEvent.getId(), S2CBossbarStylePayload.THEME_GOAL));
        ACTIVE.add(ritual);
        EclipseMod.LOGGER.info("Revive ritual started at {} by {} for {} ({})",
                ritual.altarPos, confirmer.getScoreboardName(), targetName, targetId);
        return true;
    }

    /** Whether a ritual is currently running at the given altar position. */
    public static boolean isRunningAt(ServerLevel level, BlockPos pos) {
        for (ReviveRitual ritual : ACTIVE) {
            if (ritual.level == level && ritual.altarPos.equals(pos)) {
                return true;
            }
        }
        return false;
    }

    // --- tick timeline ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (ACTIVE.isEmpty()) {
            return;
        }
        for (Iterator<ReviveRitual> iterator = ACTIVE.iterator(); iterator.hasNext();) {
            if (iterator.next().tick()) {
                iterator.remove();
            }
        }
    }

    /** Advances one tick; returns {@code true} once the ritual finished (success or failure). */
    private boolean tick() {
        ServerPlayer confirmer = this.level.getServer().getPlayerList().getPlayer(this.confirmerId);
        if (confirmer == null || confirmer.isDeadOrDying() || confirmer.level() != this.level
                || confirmer.position().distanceToSqr(Vec3.atCenterOf(this.altarPos))
                        > MAX_CONFIRMER_DISTANCE * MAX_CONFIRMER_DISTANCE) {
            fail("confirmer died, left or strayed too far");
            return true;
        }
        this.ticksElapsed++;
        this.bossEvent.setProgress((float) (DURATION_TICKS - this.ticksElapsed) / DURATION_TICKS);
        if (this.ticksElapsed % BEAM_INTERVAL_TICKS == 0) {
            BeamEmitter.emit(this.level, this.altarPos);
        }
        if (this.ticksElapsed >= DURATION_TICKS) {
            succeed();
            return true;
        }
        return false;
    }

    // --- outcomes ---

    /** Failure: the sigil drops back onto the altar (stealable) and the bossbar disappears. */
    private void fail(String reason) {
        Containers.dropItemStack(this.level,
                this.altarPos.getX() + 0.5D, this.altarPos.getY() + 1.0D, this.altarPos.getZ() + 0.5D,
                new ItemStack(EclipseItems.REVIVE_SIGIL.get()));
        this.level.playSound(null, this.altarPos, SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 1.0F, 0.6F);
        cleanup();
        EclipseMod.LOGGER.info("Revive ritual at {} for {} FAILED ({}); sigil dropped", this.altarPos, this.targetName, reason);
    }

    /**
     * Success: unban the target (deferred to next login if offline), global thunder, remove
     * bossbar. If the target is no longer banned (revived mid-ritual by an admin or the
     * finale), the ritual aborts gracefully instead — sigil refunded onto the altar plus an
     * actionbar note to the ritualist, so the sigil is never consumed for nothing.
     */
    private void succeed() {
        MinecraftServer server = this.level.getServer();
        ServerPlayer target = server.getPlayerList().getPlayer(this.targetId);
        boolean stillBanned = target != null
                ? BanService.isBanned(target)
                : EclipseWorldState.get(server).isBanned(this.targetId);
        if (!stillBanned) {
            // Revived mid-ritual (admin /eclipse revive or the finale mass-revive): nothing
            // left to undo — abort like a failure so the sigil drops back onto the altar,
            // and tell the ritualist why the thunder never came.
            ServerPlayer confirmer = server.getPlayerList().getPlayer(this.confirmerId);
            if (confirmer != null) {
                confirmer.displayClientMessage(
                        Component.translatable("ritual.eclipse.revive.none_banned"), true);
            }
            fail("target no longer banned");
            return;
        }
        if (target != null) {
            BanService.unban(target);
        } else {
            // Offline: clear the persistent ban now; the attachment-based ghost state is
            // reconciled (full unban) the moment the player logs back in, see onPlayerLoggedIn.
            EclipseWorldState.get(server).removeBanned(this.targetId);
        }
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.MASTER, 1.0F, 1.0F);
        }
        cleanup();
        EclipseMod.LOGGER.info("Revive ritual at {} completed: {} ({}) revived{}",
                this.altarPos, this.targetName, this.targetId, target == null ? " (offline; applied on next login)" : "");
    }

    private void cleanup() {
        this.bossEvent.removeAllPlayers();
    }

    // --- global player/server hooks ---

    /**
     * Late joiners see running bossbars; players whose ban was lifted by a ritual
     * while they were offline (attachment still TRUE but no longer in the
     * persistent banned set) are fully unbanned here.
     */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        for (ReviveRitual ritual : ACTIVE) {
            ritual.bossEvent.addPlayer(player);
            // Late joiners need the W8 skin tag too (the bar itself is re-sent by addPlayer).
            net.neoforged.neoforge.network.PacketDistributor.sendToPlayer(player,
                    new S2CBossbarStylePayload(ritual.bossEvent.getId(), S2CBossbarStylePayload.THEME_GOAL));
        }
        if (player.getData(EclipseAttachments.BANNED)
                && !EclipseWorldState.get(player.server).isBanned(player.getUUID())) {
            EclipseMod.LOGGER.info("Applying offline revive for {} on login", player.getScoreboardName());
            BanService.unban(player);
        }
    }

    /** Drop stale bossbar references for disconnecting players. */
    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            for (ReviveRitual ritual : ACTIVE) {
                ritual.bossEvent.removePlayer(player);
            }
        }
    }

    /** Instant failure when the confirming player dies (tick would also catch it, but this is immediate). */
    @SubscribeEvent
    public static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || ACTIVE.isEmpty()) {
            return;
        }
        for (Iterator<ReviveRitual> iterator = ACTIVE.iterator(); iterator.hasNext();) {
            ReviveRitual ritual = iterator.next();
            if (ritual.confirmerId.equals(player.getUUID())) {
                ritual.fail("confirmer died");
                iterator.remove();
            }
        }
    }

    /** Server stop: fail every running ritual so bossbars are removed and no sigil is lost. */
    @SubscribeEvent
    public static void onServerStopping(ServerStoppingEvent event) {
        for (Iterator<ReviveRitual> iterator = ACTIVE.iterator(); iterator.hasNext();) {
            iterator.next().fail("server stopping");
            iterator.remove();
        }
    }
}
