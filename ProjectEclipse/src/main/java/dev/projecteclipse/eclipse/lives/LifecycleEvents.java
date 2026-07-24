package dev.projecteclipse.eclipse.lives;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.snapshot.SnapshotService;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import dev.projecteclipse.eclipse.network.S2CHeartBurstPayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseBlocks;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.GameRules;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The death economy: on a player death we snapshot first, then move a life from
 * the victim to a player killer (or just take one on PvE deaths), place a grave
 * with the drops, and ban the victim once they hit 0 lives. Deaths are never
 * announced in chat ({@code showDeathMessages=false}); the only cue is a global
 * thunder sound played to every online player at their own position. Advancement
 * announcements are likewise forced off ({@code announceAdvancements=false}) —
 * they would broadcast player names.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LifecycleEvents {
    /**
     * Server-session handoff from the death event to that player's next respawn event.
     * Deliberately NOT pruned on logout: a player who disconnects on the death screen
     * respawns AFTER their next login, so the entry must survive the relog for the burst
     * to replay. Stale entries (victim never respawned at all) are age-pruned instead,
     * see {@link #PENDING_HEART_LOSS_TTL_MILLIS}.
     */
    private static final Map<UUID, PendingHeartLoss> PENDING_HEART_LOSSES = new HashMap<>();

    /** Pending bursts older than this (~1 h) are dropped — the victim never came back to respawn. */
    private static final long PENDING_HEART_LOSS_TTL_MILLIS = 60L * 60L * 1000L;

    private record PendingHeartLoss(int previousHearts, int heartIndex, long diedAtMillis) {}

    private LifecycleEvents() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        server.getGameRules().getRule(GameRules.RULE_SHOWDEATHMESSAGES).set(false, server);
        server.getGameRules().getRule(GameRules.RULE_ANNOUNCE_ADVANCEMENTS).set(false, server);
        EclipseMod.LOGGER.info("Eclipse lifecycle active: showDeathMessages=false, announceAdvancements=false");
    }

    @SubscribeEvent
    public static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        SnapshotService.snapshot(victim, "death");

        long now = System.currentTimeMillis();
        PENDING_HEART_LOSSES.values().removeIf(loss -> now - loss.diedAtMillis() > PENDING_HEART_LOSS_TTL_MILLIS);

        int previousHearts = LivesApi.get(victim);
        int remainingHearts = LivesApi.add(victim, -1);
        boolean heartLost = remainingHearts < previousHearts;
        if (heartLost) {
            // The first now-missing zero-based heart is exactly the new count.
            PENDING_HEART_LOSSES.put(victim.getUUID(),
                    new PendingHeartLoss(previousHearts, remainingHearts, now));
        }

        if (heartLost && event.getSource().getEntity() instanceof ServerPlayer killer && killer != victim) {
            // Kill transfer: the killer gains a heart ONLY when the victim actually lost
            // one (a 0-heart ghost death must never mint hearts), hard-capped at the vitae
            // ceiling like the blade bonus (the v1 "uncapped" law is overruled).
            if (LivesApi.get(killer) < HeartsService.MAX_HEARTS) {
                LivesApi.add(killer, +1);
            }
            // W13 umbral blade: one EXTRA heart of lifesteal on a blade kill, same cap.
            if (killer.getMainHandItem().is(EclipseItems.UMBRAL_BLADE.get())
                    && LivesApi.get(killer) < HeartsService.MAX_HEARTS) {
                LivesApi.add(killer, +1);
                EclipseMod.LOGGER.info("{}'s umbral blade drank a heart from {} ({} hearts now)",
                        killer.getScoreboardName(), victim.getScoreboardName(), LivesApi.get(killer));
            }
        }

        playDeathCue(victim.server);

        if (LivesApi.get(victim) <= 0) {
            BanService.ban(victim);
        }
    }

    /** Plays the thunder death cue to every online player at their own position (never chat). */
    private static void playDeathCue(MinecraftServer server) {
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.MASTER, 0.6F, 0.7F);
        }
    }

    @SubscribeEvent
    public static void onLivingDrops(LivingDropsEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim) || !(victim.level() instanceof ServerLevel level)) {
            return;
        }
        List<ItemStack> stacks = new ArrayList<>();
        for (ItemEntity drop : event.getDrops()) {
            ItemStack stack = drop.getItem();
            if (!stack.isEmpty()) {
                stacks.add(stack.copy());
            }
        }
        if (stacks.isEmpty()) {
            return;
        }
        BlockPos gravePos = findGravePos(level, victim.blockPosition());
        if (gravePos == null) {
            EclipseMod.LOGGER.warn("No spot for a grave near {}'s death position {}; keeping vanilla drops",
                    victim.getScoreboardName(), victim.blockPosition());
            return;
        }
        level.setBlockAndUpdate(gravePos, EclipseBlocks.GRAVE.get().defaultBlockState());
        if (level.getBlockEntity(gravePos) instanceof GraveBlockEntity grave) {
            grave.initialize(victim.getUUID(), level.getGameTime(), stacks);
            // W13: track the grave for the Grave Dowser; GraveBlock#onRemove prunes it.
            EclipseWorldState.get(level.getServer())
                    .addGravePosition(victim.getUUID(), GlobalPos.of(level.dimension(), gravePos));
            event.setCanceled(true);
        } else {
            // Should never happen; keep vanilla drops rather than voiding items.
            level.removeBlock(gravePos, false);
            EclipseMod.LOGGER.error("Grave block entity missing at {}; keeping vanilla drops", gravePos);
        }
    }

    /**
     * Re-applies the limbo ghost state after a banned player respawns (death-time
     * bans cannot teleport a corpse), then emits the deferred shatter cues for
     * a heart actually lost by that death.
     */
    @SubscribeEvent
    public static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (player.getData(EclipseAttachments.BANNED)) {
            BanService.applyLimboState(player);
        }

        PendingHeartLoss loss = PENDING_HEART_LOSSES.remove(player.getUUID());
        int heartsNow = LivesApi.get(player);
        if (loss != null && heartsNow < loss.previousHearts()) {
            // W4-HEARTS R2: one burst per heart actually gone since the death (a plain
            // death replays exactly loss.heartIndex(); extra losses while dead — admin
            // edits — shatter too). HeartBurstOverlay's queue staggers them 8 t apart.
            for (int heartIndex = heartsNow; heartIndex < loss.previousHearts(); heartIndex++) {
                PacketDistributor.sendToPlayer(player, new S2CHeartBurstPayload(heartIndex));
            }
            PacketDistributor.sendToPlayer(player,
                    new S2CQuasarPayload(
                            S2CQuasarPayload.HEART_BURST,
                            player.position().add(0.0D, 1.0D, 0.0D)));
        }
    }

    /**
     * The death position if replaceable (Y clamped into build height for void deaths),
     * otherwise the nearest replaceable/air block within a small search box, or
     * {@code null} if there is none.
     */
    private static BlockPos findGravePos(ServerLevel level, BlockPos deathPos) {
        BlockPos base = new BlockPos(deathPos.getX(),
                Mth.clamp(deathPos.getY(), level.getMinBuildHeight(), level.getMaxBuildHeight() - 1),
                deathPos.getZ());
        if (isReplaceable(level, base)) {
            return base;
        }
        for (int radius = 1; radius <= 3; radius++) {
            for (BlockPos candidate : BlockPos.betweenClosed(
                    base.offset(-radius, -1, -radius), base.offset(radius, radius + 1, radius))) {
                if (isReplaceable(level, candidate)) {
                    return candidate.immutable();
                }
            }
        }
        return null;
    }

    private static boolean isReplaceable(ServerLevel level, BlockPos pos) {
        if (level.isOutsideBuildHeight(pos)) {
            return false;
        }
        BlockState state = level.getBlockState(pos);
        return state.isAir() || state.canBeReplaced();
    }
}
