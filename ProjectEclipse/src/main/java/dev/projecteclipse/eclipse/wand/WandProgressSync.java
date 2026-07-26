package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.network.wand.S2CWandProgressPayload;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server half of the {@code S2CWandProgressPayload} sync (V6-FIXWIRE #5). Builds one
 * snapshot per receiver — level/xp from the truth source of the current mode
 * ({@code WandStore} row in PLAYER mode, the player's own wand stack in ITEM mode),
 * charge from the physical wand, config numbers from the server's {@code WandConfig},
 * and the receiver's live per-power cooldowns from {@code WandPowers}.
 *
 * <p>Send points: login ({@code WandEvents}), successful cast + kill bonus + path choice
 * ({@code WandPowers}), dev progression edits ({@code DevWandCommands}), and a
 * whole-server broadcast after {@code /dev reload} re-reads {@code wand.json}
 * (registered next to the reload hook in {@code WandItems.register}).</p>
 */
public final class WandProgressSync {
    private WandProgressSync() {}

    /** Sends the receiver a fresh snapshot of their own wand progression + server tuning. */
    public static void syncTo(ServerPlayer player) {
        WandConfig.Data config = WandConfig.get();
        WandStore store = WandStore.get(player.server);

        int level;
        int xp;
        ItemStack wand = findOwnedWand(player);
        if (store.perItemMode()) {
            // ITEM mode: progression lives on the stack (no wand = nothing leveled yet).
            level = wand != null ? WandSoulbind.levelOf(wand) : 1;
            xp = wand != null ? Math.max(0, wand.getOrDefault(WandItems.WAND_XP.get(), 0)) : 0;
        } else {
            WandStore.Progress progress = store.progress(player.getUUID());
            level = progress.level;
            xp = Math.max(0, progress.xp);
        }
        // WANDFIX-4: the synced max + power rows are the receiver's EFFECTIVE numbers
        // (wand-branch skill perks folded in) so the panel/HUD never display raw config
        // values that this player's casts would not actually pay.
        int chargeMax = WandPerks.chargeMax(player);
        int charge = wand != null
                ? wand.getOrDefault(WandItems.WAND_CHARGE.get(), chargeMax)
                : chargeMax;

        List<Integer> levelCosts = new ArrayList<>(config.xp().levelCosts().length);
        for (int cost : config.xp().levelCosts()) {
            levelCosts.add(cost);
        }

        long now = player.serverLevel().getGameTime();
        Map<String, Long> cooldowns = WandPowers.cooldownsOf(player.getUUID());
        List<S2CWandProgressPayload.PowerRow> rows = new ArrayList<>(config.powers().size());
        for (Map.Entry<String, WandConfig.Power> entry : config.powers().entrySet()) {
            long readyAt = cooldowns.getOrDefault(entry.getKey(), 0L);
            rows.add(new S2CWandProgressPayload.PowerRow(
                    entry.getKey(),
                    WandPerks.effectiveCost(player, entry.getValue()),
                    WandPerks.effectiveCooldownTicks(player, entry.getValue()),
                    (int) Math.max(0L, readyAt - now)));
        }

        PacketDistributor.sendToPlayer(player, new S2CWandProgressPayload(
                level, xp, charge, chargeMax,
                config.xp().perCostPoint(), config.xp().killBonus(), levelCosts, rows));
    }

    /** Post-reload broadcast: every online player gets the fresh {@code wand.json} numbers. */
    public static void syncAll(MinecraftServer server) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            syncTo(player);
        }
    }

    /** The player's OWN wand anywhere in the inventory (charge/item-mode source), or null. */
    private static ItemStack findOwnedWand(ServerPlayer player) {
        ItemStack fallback = null;
        for (int slot = 0; slot < player.getInventory().getContainerSize(); slot++) {
            ItemStack stack = player.getInventory().getItem(slot);
            if (stack.getItem() instanceof EclipseWandItem) {
                if (WandSoulbind.isOwner(player, stack)) {
                    return stack;
                }
                if (fallback == null) {
                    fallback = stack;
                }
            }
        }
        return fallback;
    }
}
