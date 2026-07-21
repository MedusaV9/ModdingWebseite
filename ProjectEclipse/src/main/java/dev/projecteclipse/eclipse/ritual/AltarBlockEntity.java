package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.mojang.authlib.GameProfile;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseBlockEntities;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.Containers;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side brain of the altar. Holds only transient per-player interaction
 * state (heart-sacrifice confirmations, revive-sigil selections); all durable
 * progress lives in {@link EclipseWorldState}.
 *
 * <p>Milestone progress is tracked in {@link EclipseWorldState#getMilestoneProgress(String)}
 * under {@code altar_level_<n>} (single-cost milestones) or
 * {@code altar_level_<n>:<item_id>} (one counter per cost entry of multi-cost milestones).</p>
 *
 * <p>All player feedback is action bar + sounds; nothing is ever sent to chat.</p>
 */
public class AltarBlockEntity extends BlockEntity {
    /** Heart sacrifice must be confirmed by a second sneak-right-click within this window (5 s). */
    public static final long HEART_CONFIRM_WINDOW_TICKS = 100L;

    /** Game time of each player's pending (unconfirmed) heart sacrifice. */
    private final Map<UUID, Long> pendingHeartSacrifices = new HashMap<>();
    /** Currently-selected revive target (banned player UUID) per interacting player. */
    private final Map<UUID, UUID> sigilSelections = new HashMap<>();

    public AltarBlockEntity(BlockPos pos, BlockState state) {
        super(EclipseBlockEntities.ALTAR.get(), pos, state);
    }

    // --- milestone sacrifice ---

    /**
     * Right-click with an item: consumes as much of the held stack as the next
     * milestone (current altar level + 1) still needs of that item. Completing
     * all cost entries raises the altar level, syncs it to all clients and plays
     * the subtle global cue (end-portal sound + portal particles, no text).
     */
    public void handleMilestoneDeposit(ServerPlayer player, ItemStack stack) {
        if (!(this.level instanceof ServerLevel serverLevel)) {
            return;
        }
        MinecraftServer server = player.server;
        EclipseWorldState state = EclipseWorldState.get(server);
        EclipseConfig.Milestone milestone = EclipseConfig.milestone(state.getAltarLevel() + 1);
        if (milestone == null) {
            actionBar(player, Component.translatable("ritual.eclipse.altar.complete"));
            return;
        }
        String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        EclipseConfig.ItemCost match = null;
        for (EclipseConfig.ItemCost cost : milestone.cost()) {
            if (cost.item().equals(itemId)
                    && state.getMilestoneProgress(progressKey(milestone, cost.item())) < cost.count()) {
                match = cost;
                break;
            }
        }
        if (match == null) {
            actionBar(player, Component.translatable("ritual.eclipse.altar.wrong_item"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        String key = progressKey(milestone, match.item());
        long remaining = match.count() - state.getMilestoneProgress(key);
        int consumed = (int) Math.min(stack.getCount(), remaining);
        Component itemName = Component.translatable(stack.getItem().getDescriptionId());
        stack.shrink(consumed);
        long updated = state.addMilestoneProgress(key, consumed);

        actionBar(player, Component.translatable("ritual.eclipse.altar.progress", updated, match.count(), itemName));
        serverLevel.playSound(null, this.worldPosition, SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 1.0F, 0.8F);

        if (isMilestoneComplete(state, milestone)) {
            completeMilestone(serverLevel, state, milestone);
        }
    }

    /** Right-click with an empty hand (not sneaking): current level + next requirement on the action bar. */
    public void handleStatusHint(ServerPlayer player) {
        EclipseWorldState state = EclipseWorldState.get(player.server);
        EclipseConfig.Milestone milestone = EclipseConfig.milestone(state.getAltarLevel() + 1);
        if (milestone == null) {
            actionBar(player, Component.translatable("ritual.eclipse.altar.complete"));
            return;
        }
        for (EclipseConfig.ItemCost cost : milestone.cost()) {
            long progress = state.getMilestoneProgress(progressKey(milestone, cost.item()));
            if (progress < cost.count()) {
                Component itemName = costItemName(cost);
                actionBar(player, Component.translatable("ritual.eclipse.altar.status",
                        state.getAltarLevel(), progress, cost.count(), itemName));
                return;
            }
        }
    }

    private boolean isMilestoneComplete(EclipseWorldState state, EclipseConfig.Milestone milestone) {
        for (EclipseConfig.ItemCost cost : milestone.cost()) {
            if (state.getMilestoneProgress(progressKey(milestone, cost.item())) < cost.count()) {
                return false;
            }
        }
        return true;
    }

    private void completeMilestone(ServerLevel serverLevel, EclipseWorldState state, EclipseConfig.Milestone milestone) {
        state.setAltarLevel(milestone.level());
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), state.getAltarLevel()));
        // Subtle global cue: end-portal sound for everyone, portal particles at the altar. No text.
        for (ServerPlayer online : serverLevel.getServer().getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.END_PORTAL_SPAWN, SoundSource.MASTER, 0.4F, 1.3F);
        }
        serverLevel.sendParticles(ParticleTypes.PORTAL,
                this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.2D, this.worldPosition.getZ() + 0.5D,
                150, 0.6D, 0.8D, 0.6D, 0.8D);
        EclipseMod.LOGGER.info("Altar milestone {} completed at {}; rewards {}",
                milestone.level(), this.worldPosition, milestone.rewards());
    }

    /**
     * Progress key for a milestone cost entry: {@code altar_level_<n>} when the
     * milestone has a single cost entry, else {@code altar_level_<n>:<item_id>}.
     */
    private static String progressKey(EclipseConfig.Milestone milestone, String itemId) {
        String base = "altar_level_" + milestone.level();
        return milestone.cost().size() == 1 ? base : base + ":" + itemId;
    }

    private static Component costItemName(EclipseConfig.ItemCost cost) {
        return BuiltInRegistries.ITEM.getOptional(ResourceLocation.parse(cost.item()))
                .map(item -> (Component) Component.translatable(item.getDescriptionId()))
                .orElse(Component.literal(cost.item()));
    }

    // --- heart sacrifice ---

    /**
     * Sneak-right-click with an empty hand. The first click arms a pending
     * sacrifice; a second one within {@link #HEART_CONFIRM_WINDOW_TICKS} takes a
     * life ({@link LivesApi}) and drops one heart fragment on the altar. Players
     * at 1 life or below are blocked with an action-bar hint.
     */
    public void handleHeartSacrifice(ServerPlayer player) {
        if (!(this.level instanceof ServerLevel serverLevel)) {
            return;
        }
        if (LivesApi.get(player) <= 1) {
            pendingHeartSacrifices.remove(player.getUUID());
            actionBar(player, Component.translatable("ritual.eclipse.heart.blocked"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.8F);
            return;
        }
        long now = serverLevel.getGameTime();
        Long pending = pendingHeartSacrifices.get(player.getUUID());
        if (pending == null || now - pending > HEART_CONFIRM_WINDOW_TICKS) {
            pendingHeartSacrifices.put(player.getUUID(), now);
            actionBar(player, Component.translatable("ritual.eclipse.heart.confirm"));
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.BLOCKS, 0.8F, 0.6F);
            return;
        }
        pendingHeartSacrifices.remove(player.getUUID());
        LivesApi.add(player, -1);
        Containers.dropItemStack(serverLevel,
                this.worldPosition.getX() + 0.5D, this.worldPosition.getY() + 1.0D, this.worldPosition.getZ() + 0.5D,
                new ItemStack(EclipseItems.HEART_FRAGMENT.get()));
        serverLevel.playSound(null, this.worldPosition, SoundEvents.WARDEN_HEARTBEAT, SoundSource.BLOCKS, 1.0F, 0.8F);
        actionBar(player, Component.translatable("ritual.eclipse.heart.done"));
        EclipseMod.LOGGER.info("{} sacrificed a life at the altar {} ({} lives left)",
                player.getScoreboardName(), this.worldPosition, LivesApi.get(player));
    }

    // --- revive sigil ---

    /**
     * Right-click with a revive sigil (not sneaking): advances this player's
     * selection through {@link EclipseWorldState#getBanned()} (deterministic
     * order) and shows the selected name on the action bar.
     */
    public void handleSigilCycle(ServerPlayer player) {
        MinecraftServer server = player.server;
        List<UUID> banned = new ArrayList<>(EclipseWorldState.get(server).getBanned());
        if (banned.isEmpty()) {
            sigilSelections.remove(player.getUUID());
            actionBar(player, Component.translatable("ritual.eclipse.revive.none_banned"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        banned.sort(Comparator.comparing(UUID::toString));
        int index = banned.indexOf(sigilSelections.get(player.getUUID()));
        UUID next = banned.get((index + 1) % banned.size());
        sigilSelections.put(player.getUUID(), next);
        actionBar(player, Component.translatable("ritual.eclipse.revive.selected", resolveName(server, next)));
        player.playNotifySound(SoundEvents.EXPERIENCE_ORB_PICKUP, SoundSource.PLAYERS, 0.6F, 1.4F);
    }

    /**
     * Sneak-right-click with a revive sigil (via {@link ReviveSigilItem#useOn}):
     * consumes one sigil and starts the {@link ReviveRitual} for the currently
     * displayed selection.
     */
    public void handleSigilConfirm(ServerPlayer player, ItemStack sigilStack) {
        if (!(this.level instanceof ServerLevel serverLevel)) {
            return;
        }
        MinecraftServer server = player.server;
        if (ReviveRitual.isRunningAt(serverLevel, this.worldPosition)) {
            actionBar(player, Component.translatable("ritual.eclipse.revive.already_running"));
            return;
        }
        UUID target = sigilSelections.get(player.getUUID());
        if (target == null || !EclipseWorldState.get(server).getBanned().contains(target)) {
            actionBar(player, Component.translatable("ritual.eclipse.revive.no_selection"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        String targetName = resolveName(server, target);
        if (ReviveRitual.start(serverLevel, this.worldPosition, player, target, targetName)) {
            sigilStack.shrink(1);
            sigilSelections.remove(player.getUUID());
            actionBar(player, Component.translatable("ritual.eclipse.revive.started"));
        } else {
            actionBar(player, Component.translatable("ritual.eclipse.revive.already_running"));
        }
    }

    // --- helpers ---

    private static void actionBar(ServerPlayer player, Component message) {
        player.displayClientMessage(message, true);
    }

    /** Player name for a UUID: online player, then profile cache, then a short UUID prefix. */
    private static String resolveName(MinecraftServer server, UUID id) {
        ServerPlayer online = server.getPlayerList().getPlayer(id);
        if (online != null) {
            return online.getScoreboardName();
        }
        if (server.getProfileCache() != null) {
            return server.getProfileCache().get(id).map(GameProfile::getName)
                    .orElse(id.toString().substring(0, 8));
        }
        return id.toString().substring(0, 8);
    }
}
