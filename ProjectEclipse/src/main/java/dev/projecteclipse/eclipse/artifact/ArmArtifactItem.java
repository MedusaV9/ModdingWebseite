package dev.projecteclipse.eclipse.artifact;

import java.util.List;

import dev.projecteclipse.eclipse.network.EclipsePayloads;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.SlotAccess;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.ClickAction;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.Level;

/**
 * The player's permanent in-game interface artifact ({@code eclipse:arm_artifact}).
 * Lives PINNED in inventory slot {@value ArtifactSlotLock#ARTIFACT_SLOT} — the top-right
 * storage slot of the inventory GUI (enforced by {@link ArtifactSlotLock}), cannot be
 * dropped (toss is cancelled there), never enters a death grave
 * ({@link ArtifactDropGuard}, B17) and cannot be nested inside container items
 * ({@link #canFitInsideContainerItems()}).
 *
 * <p><b>Right-click-in-inventory flow (v3, plans_v3 P3 §3.1):</b>
 * {@link #overrideOtherStackedOnMe} is the bundle-pattern hook — it fires when the
 * artifact's slot is clicked with ANY carried stack (including an empty cursor) and it
 * runs on BOTH sides of the container click. Returning {@code true} for BOTH click
 * actions consumes the click, which makes the stack un-pickable by mouse: visual pinning
 * with zero menu mixins (shift-move/number-swap bypass this hook and are reverted by the
 * {@link ArtifactSlotLock} sweep within a second). On {@link ClickAction#SECONDARY} the
 * CLIENT side additionally routes through
 * {@code client.ArtifactScreenOpener#openFromInventory()}, which defers one frame so the
 * container-close packet leaves before the handbook opens. That client-only class is
 * referenced strictly inside the {@code isClientSide} branch (never taken on a dedicated
 * server), the same lazy-classload convention {@code network.EclipsePayloads} documents.</p>
 *
 * <p><b>Held right-click fallback ({@link #use}):</b> the item can sit in the hotbar
 * transiently (fresh grant before the first sweep), so {@code use()} keeps working: the
 * server pushes fresh {@code S2CLivesPayload} + {@code S2CDayStatePayload} and then a
 * {@code S2COpenArtifactPayload}; same-connection ordering guarantees the
 * {@code ClientStateCache} is fresh by the time the open instruction lands.</p>
 */
public class ArmArtifactItem extends Item {
    /** Mirrors the client suite's {@code EclipseUiTheme.ACCENT} (that class is client-only). */
    private static final int TOOLTIP_ACCENT = 0xB98CFF;

    public ArmArtifactItem(Properties properties) {
        super(properties);
    }

    /** Keeps the artifact out of shulker boxes and bundles. */
    @Override
    public boolean canFitInsideContainerItems() {
        return false;
    }

    /**
     * Consumes every mouse click on the artifact's slot (= pinning) and opens the handbook
     * on right-click. {@code stack} is the artifact in the slot, {@code other} the carried
     * stack (possibly empty); see the class javadoc for the full flow.
     */
    @Override
    public boolean overrideOtherStackedOnMe(ItemStack stack, ItemStack other, Slot slot, ClickAction action,
            Player player, SlotAccess access) {
        if (action == ClickAction.SECONDARY && player.level().isClientSide()) {
            dev.projecteclipse.eclipse.client.ArtifactScreenOpener.openFromInventory();
        }
        return true;
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        if (player instanceof ServerPlayer serverPlayer) {
            EclipsePayloads.sendArtifactState(serverPlayer, true);
        }
        return InteractionResultHolder.sidedSuccess(player.getItemInHand(hand), level.isClientSide());
    }

    /** The one-line affordance for the pinned slot: "Right-click: open the ledger". */
    @Override
    public void appendHoverText(ItemStack stack, Item.TooltipContext context, List<Component> tooltipComponents,
            TooltipFlag tooltipFlag) {
        tooltipComponents.add(Component.translatable("item.eclipse.arm_artifact.tooltip").withColor(TOOLTIP_ACCENT));
    }
}
