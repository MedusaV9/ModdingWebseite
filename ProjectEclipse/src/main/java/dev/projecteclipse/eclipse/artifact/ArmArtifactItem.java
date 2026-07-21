package dev.projecteclipse.eclipse.artifact;

import dev.projecteclipse.eclipse.network.EclipsePayloads;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;

/**
 * The player's permanent in-game interface artifact ({@code eclipse:arm_artifact}).
 * Always sits in hotbar slot 8 (enforced by {@link ArtifactSlotLock}), cannot be dropped
 * (toss is cancelled in {@link ArtifactSlotLock}) and cannot be nested inside container
 * items ({@link #canFitInsideContainerItems()}).
 *
 * <p><b>Screen-opening flow (chosen path, documented):</b> the server is the single source
 * of truth, so on right-click the server first pushes a fresh
 * {@link dev.projecteclipse.eclipse.network.S2CLivesPayload} +
 * {@link dev.projecteclipse.eclipse.network.S2CDayStatePayload} (day, altar level, goals) and
 * then a {@link dev.projecteclipse.eclipse.network.S2COpenArtifactPayload}. Because payloads
 * on the same connection arrive in order, {@code ClientStateCache} is guaranteed fresh by the
 * time the open instruction arrives and the client opens {@code ArtifactScreen}. The client
 * never opens the screen speculatively from {@code use()}, which keeps this item class free
 * of client-only references.</p>
 */
public class ArmArtifactItem extends Item {
    public ArmArtifactItem(Properties properties) {
        super(properties);
    }

    /** Keeps the artifact out of shulker boxes and bundles. */
    @Override
    public boolean canFitInsideContainerItems() {
        return false;
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        if (player instanceof ServerPlayer serverPlayer) {
            EclipsePayloads.sendArtifactState(serverPlayer, true);
        }
        return InteractionResultHolder.sidedSuccess(player.getItemInHand(hand), level.isClientSide());
    }
}
