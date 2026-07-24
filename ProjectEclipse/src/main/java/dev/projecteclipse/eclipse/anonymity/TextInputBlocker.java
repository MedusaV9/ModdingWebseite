package dev.projecteclipse.eclipse.anonymity;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.AnvilUpdateEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.level.BlockEvent;

/**
 * Blocks vanilla text-entry surfaces that could reveal player-authored text.
 *
 * <p>Also covers Supplementaries' sign-like text blocks (way signs, blackboards, notice
 * boards, doormats, speaker blocks): their edit GUIs extend plain {@code Screen} — NOT
 * vanilla {@code AbstractSignEditScreen} — so the vanilla sign tag never matches them.
 * Matching is a pure registry-id namespace/path string check (zero compile-time
 * dependency), cancelling both placement and interaction server-side.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class TextInputBlocker {
    private TextInputBlocker() {}

    private static final String SUPPLEMENTARIES_NAMESPACE = "supplementaries";

    @SubscribeEvent
    public static void onAnvilUpdate(AnvilUpdateEvent event) {
        if (!(event.getPlayer() instanceof ServerPlayer)) {
            return;
        }

        String requestedName = event.getName();
        if (requestedName != null
                && !requestedName.isEmpty()
                && !requestedName.equals(event.getLeft().getHoverName().getString())) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onSignPlaced(BlockEvent.EntityPlaceEvent event) {
        if (event.getEntity() instanceof ServerPlayer
                && (event.getPlacedBlock().is(BlockTags.ALL_SIGNS)
                        || isModdedTextBlock(event.getPlacedBlock()))) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onSignUsed(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        BlockState state = player.level().getBlockState(event.getPos());
        if (state.is(BlockTags.ALL_SIGNS) || isModdedTextBlock(state) || isModdedTextItem(event.getItemStack())) {
            event.setCanceled(true);
        }
    }

    /**
     * Cancels on BOTH logical sides: unlike the sign editor (opened by a server packet),
     * the book edit screen is opened purely client-side, so the client-side cancel is what
     * keeps it from appearing. {@code ServerGamePacketListenerImplMixin} additionally drops
     * any edit/sign packet a bypassing client sends anyway — signing would stamp the
     * player's profile name as the book author.
     */
    @SubscribeEvent
    public static void onBookUsed(PlayerInteractEvent.RightClickItem event) {
        if (event.getItemStack().is(Items.WRITABLE_BOOK)
                || event.getItemStack().is(Items.WRITTEN_BOOK)
                || isModdedTextItem(event.getItemStack())) {
            event.setCanceled(true);
        }
    }

    /** Supplementaries text surfaces: way signs, blackboards, notice boards, doormats, speakers. */
    private static boolean isTextSurfacePath(String path) {
        return path.contains("sign") || path.contains("board")
                || path.contains("doormat") || path.contains("speaker");
    }

    private static boolean isModdedTextBlock(BlockState state) {
        ResourceLocation id = BuiltInRegistries.BLOCK.getKey(state.getBlock());
        return SUPPLEMENTARIES_NAMESPACE.equals(id.getNamespace()) && isTextSurfacePath(id.getPath());
    }

    private static boolean isModdedTextItem(ItemStack stack) {
        if (stack.isEmpty()) {
            return false;
        }
        ResourceLocation id = BuiltInRegistries.ITEM.getKey(stack.getItem());
        return SUPPLEMENTARIES_NAMESPACE.equals(id.getNamespace()) && isTextSurfacePath(id.getPath());
    }
}
