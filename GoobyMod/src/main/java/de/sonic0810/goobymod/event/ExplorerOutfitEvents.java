package de.sonic0810.goobymod.event;

import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyWardrobe;
import de.sonic0810.goobymod.registry.ModItems;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.TickTask;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;

/**
 * Explorer-Outfit (v5.4): duenner Advancement-Layer ueber dem
 * serverautoritativen Garderoben-Pfad des Entities.
 *
 * <p>Halstuch (NECK) und Rucksack (BACK) werden ueber
 * {@link GoobyEntity#tryEquipAccessory} angelegt — exakt derselbe Pfad, den
 * auch {@code mobInteract} fuer Schal, Fliege, Tasche und Huete nutzt
 * (Policy-Gates, Sync-Grenze, Swap-Drop inkl. Tascheninhalt, volle
 * DataComponents, Konsum und Feedback inklusive). Dieser Handler ergaenzt
 * nur die Vergabe des Set-Advancements direkt nach einem erfolgreichen
 * Equip.</p>
 *
 * <p>Das Faerben des getragenen Halstuchs laeuft komplett ueber
 * {@code mobInteract} → {@link GoobyEntity#tryDyeNeckAccessory}; der
 * Blumenkranz (HEAD) ueber den bestehenden {@code #goobymod:gooby_hats}-Tag.
 * Fuer den Kranz haengt dieser Handler nur eine End-of-Tick-Pruefung an,
 * weil das {@link PlayerInteractEvent.EntityInteract} VOR dem eigentlichen
 * Ausruesten in {@code mobInteract} feuert.</p>
 */
@EventBusSubscriber(modid = GoobyMod.MODID)
public final class ExplorerOutfitEvents {

    @SubscribeEvent
    public static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (!(event.getTarget() instanceof GoobyEntity gooby)) {
            return;
        }
        ItemStack stack = event.getItemStack();
        Player player = event.getEntity();
        boolean clientSide = event.getLevel().isClientSide;
        if (stack.is(ModItems.ADVENTURE_BANDANA.get())) {
            consume(event, clientSide);
            if (!clientSide) {
                equipExplorerAccessory(player, gooby, stack, GoobyWardrobe.Slot.NECK);
            }
        } else if (stack.is(ModItems.PICNIC_BACKPACK.get())) {
            consume(event, clientSide);
            if (!clientSide) {
                equipExplorerAccessory(player, gooby, stack, GoobyWardrobe.Slot.BACK);
            }
        } else if (stack.is(ModItems.FLOWER_CROWN.get()) && !clientSide
                && player instanceof ServerPlayer serverPlayer) {
            // Kein Cancel: der Kranz gehoert dem Tag-Hut-Pfad des Entities.
            // Das Set kann aber mit dem Kranz als LETZTEM Teil komplett
            // werden — deshalb nach Abschluss dieses Ticks nachpruefen.
            scheduleExplorerCheck(serverPlayer, gooby);
        }
    }

    private static void consume(PlayerInteractEvent.EntityInteract event, boolean clientSide) {
        event.setCanceled(true);
        event.setCancellationResult(InteractionResult.sidedSuccess(clientSide));
    }

    /**
     * Delegiert an den serverautoritativen Equip-Pfad des Entities und
     * vergibt bei komplettem Set direkt das Explorer-Advancement. Gibt
     * {@code true} zurueck, wenn das Accessoire tatsaechlich angelegt wurde.
     */
    public static boolean equipExplorerAccessory(Player player, GoobyEntity gooby, ItemStack stack,
            GoobyWardrobe.Slot slot) {
        if (!gooby.tryEquipAccessory(player, stack, slot)) {
            return false;
        }
        if (player instanceof ServerPlayer serverPlayer) {
            grantExplorerOutfitIfComplete(serverPlayer, gooby);
        }
        return true;
    }

    /** Alle drei Explorer-Teile gleichzeitig getragen? */
    public static boolean isExplorerOutfitComplete(GoobyEntity gooby) {
        return gooby.getHatStack().is(ModItems.FLOWER_CROWN.get())
                && gooby.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get())
                && gooby.getBackStack().is(ModItems.PICNIC_BACKPACK.get());
    }

    public static void grantExplorerOutfitIfComplete(ServerPlayer player, GoobyEntity gooby) {
        if (isExplorerOutfitComplete(gooby)) {
            GoobyAdvancements.grant(player, GoobyAdvancements.EXPLORER_OUTFIT);
        }
    }

    /**
     * Prueft das Set NACH der laufenden Interaktion: der TickTask laeuft in
     * der Task-Drain-Phase desselben (oder spaetestens eines der naechsten)
     * Server-Ticks, also garantiert nachdem {@code mobInteract} den Kranz
     * angelegt hat. Die Vergabe selbst ist idempotent.
     */
    private static void scheduleExplorerCheck(ServerPlayer player, GoobyEntity gooby) {
        MinecraftServer server = player.server;
        server.tell(new TickTask(server.getTickCount(), () -> {
            if (gooby.isAlive() && !player.hasDisconnected()) {
                grantExplorerOutfitIfComplete(player, gooby);
            }
        }));
    }

    private ExplorerOutfitEvents() {
    }
}
