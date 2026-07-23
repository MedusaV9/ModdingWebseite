package dev.projecteclipse.eclipse.devtools.display;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Own dev-only item registrar. The wand is intentionally absent from creative tabs. */
public final class DevToolItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    public static final Supplier<Item> DISPLAY_WAND = ITEMS.register("display_wand",
            () -> new DisplayWandItem(new Item.Properties().stacksTo(1)));

    private DevToolItems() {}

    /** Orchestrator wiring point in the EclipseMod constructor. */
    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }

    private static final class DisplayWandItem extends Item {
        DisplayWandItem(Properties properties) {
            super(properties);
        }

        @Override
        public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
            ItemStack stack = player.getItemInHand(hand);
            if (level.isClientSide) {
                int action = player.isShiftKeyDown()
                        ? C2SDisplayEditPayload.DELETE
                        : C2SDisplayEditPayload.SELECT_OR_PLACE;
                PacketDistributor.sendToServer(new C2SDisplayEditPayload(action));
            }
            return InteractionResultHolder.sidedSuccess(stack, level.isClientSide);
        }
    }
}
