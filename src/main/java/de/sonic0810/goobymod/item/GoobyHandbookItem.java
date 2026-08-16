package de.sonic0810.goobymod.item;

import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.client.GoobyClientHooks;
import de.sonic0810.goobymod.registry.ModItems;
import java.util.List;
import java.util.stream.IntStream;
import net.minecraft.network.chat.Component;
import net.minecraft.server.network.Filterable;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.WrittenBookItem;
import net.minecraft.world.item.component.WrittenBookContent;
import net.minecraft.world.level.Level;

/** Illustrated handbook with a written-book fallback for external readers. */
public final class GoobyHandbookItem extends WrittenBookItem {
    private static final String RECEIVED_TAG = "GoobyModHandbookReceived";
    public static final int PAGE_COUNT = 16;

    public GoobyHandbookItem(Properties properties) {
        super(properties);
    }

    @Override
    public Component getName(ItemStack stack) {
        return Component.translatable("item.goobymod.gooby_handbook");
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack handbook = player.getItemInHand(hand);
        if (level.isClientSide) {
            GoobyClientHooks.openHandbook();
        }
        return InteractionResultHolder.sidedSuccess(handbook, level.isClientSide);
    }

    public static WrittenBookContent content() {
        List<Filterable<Component>> pages = IntStream.rangeClosed(1, PAGE_COUNT)
                .mapToObj(page -> Filterable.passThrough(
                        (Component) Component.translatable("handbook.goobymod.page." + page)))
                .toList();
        return new WrittenBookContent(Filterable.passThrough("Gooby Handbook"),
                "Sonic0810", 0, pages, true);
    }

    /** Gives the handbook exactly once per persistent player profile. */
    public static boolean giveOnce(Player player) {
        if (!GoobyConfig.giveHandbookOnTame() || player.getPersistentData().getBoolean(RECEIVED_TAG)) {
            return false;
        }
        ItemStack handbook = new ItemStack(ModItems.GOOBY_HANDBOOK.get());
        Inventory inventory = player.getInventory();
        boolean inserted = false;
        for (int offset = 1; offset < inventory.items.size(); offset++) {
            int slot = (inventory.selected + offset) % inventory.items.size();
            if (inventory.getItem(slot).isEmpty()) {
                inventory.setItem(slot, handbook);
                inserted = true;
                break;
            }
        }
        if (!inserted) {
            player.drop(handbook, false);
        }
        player.getPersistentData().putBoolean(RECEIVED_TAG, true);
        player.displayClientMessage(Component.translatable("msg.goobymod.handbook_received"), false);
        return true;
    }
}
