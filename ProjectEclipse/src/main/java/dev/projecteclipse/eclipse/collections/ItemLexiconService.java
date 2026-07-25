package dev.projecteclipse.eclipse.collections;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.collections.CollectionsPayloads;
import dev.projecteclipse.eclipse.network.collections.S2CItemLexiconPayload;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;

/**
 * Server side of the {@link ItemLexicon} (uipolish): records the first time a player
 * CARRIES a roster item and syncs the discovered set to that player's handbook.
 *
 * <p>Discovery is a periodic inventory sweep ({@value #SCAN_INTERVAL_TICKS} ticks per
 * player) rather than an event hook on purpose: ground pickup, crafting, {@code /give},
 * chest loot AND the shard shop's direct-to-inventory delivery
 * ({@code ShardEconomy#deliverShardItems}) all land in the same code path, where the
 * sanctioned {@code EclipseSignals.onItemCollected} pickup lane is thrower-null +
 * allowlist bound and would miss most of them. ~41 stack reads per player every 2 s is
 * noise; the 2 s cadence is the accepted discovery latency.</p>
 *
 * <p>Discoveries persist in {@link CollectionsState} (the collections store of record) as
 * a monotonic per-player set — nothing is ever un-discovered. A mid-session discovery
 * announces with one quiet chat line ({@code message.eclipse.collection.discovered}); the
 * login sweep records silently so a returning player's backlog never floods the chat.
 * Sync is the tiny full-set {@link S2CItemLexiconPayload} on login and on every new
 * discovery (≤ {@code ItemLexicon.size()} ids — cheaper than a delta protocol).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ItemLexiconService {
    /** Inventory sweep cadence (2 s), phase-spread per player by entity tick count. */
    private static final int SCAN_INTERVAL_TICKS = 40;

    private ItemLexiconService() {}

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            scan(player, false); // silent: backlog of already-carried items, no chat flood
            syncTo(player);
        }
    }

    @SubscribeEvent
    static void onPlayerTick(PlayerTickEvent.Post event) {
        if (event.getEntity() instanceof ServerPlayer player
                && player.tickCount % SCAN_INTERVAL_TICKS == 0) {
            scan(player, true);
        }
    }

    /** Sweeps the full inventory; every tracked, not-yet-recorded item becomes an entry. */
    private static void scan(ServerPlayer player, boolean announce) {
        CollectionsState state = CollectionsState.get(player.server);
        CollectionsState.Entry entry = state.entry(player.getUUID());
        List<String> found = new ArrayList<>();
        Inventory inventory = player.getInventory();
        for (int slot = 0; slot < inventory.getContainerSize(); slot++) {
            ItemStack stack = inventory.getItem(slot);
            if (stack.isEmpty()) {
                continue;
            }
            String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
            if (ItemLexicon.tracked(itemId) && entry.discoveredItems.add(itemId)) {
                found.add(itemId);
            }
        }
        if (found.isEmpty()) {
            return;
        }
        state.setDirty();
        if (announce) {
            for (String itemId : found) {
                // ServerLang bakes the translatable item-name arg per-player (Wave-5 A1).
                player.sendSystemMessage(ServerLang.tr(player, "message.eclipse.collection.discovered",
                        Component.translatable(BuiltInRegistries.ITEM
                                .get(ResourceLocation.parse(itemId)).getDescriptionId())));
            }
            syncTo(player);
        }
    }

    /** Full discovered-set snapshot to one player (login + every new discovery). */
    private static void syncTo(ServerPlayer player) {
        CollectionsState.Entry entry = CollectionsState.get(player.server).entry(player.getUUID());
        CollectionsPayloads.sendTo(player, new S2CItemLexiconPayload(List.copyOf(entry.discoveredItems)));
    }
}
