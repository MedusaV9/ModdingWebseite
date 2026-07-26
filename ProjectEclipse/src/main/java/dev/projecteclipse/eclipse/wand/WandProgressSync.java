package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.network.wand.S2CWandProgressPayload;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server half of the {@code S2CWandProgressPayload} sync (F-036 rework). Builds one
 * snapshot per receiver: level/xp/rebirths/owned-nodes from the {@link WandStore} row
 * (level/xp from the stack in the {@code /dev wand mode item} niche), charge from the
 * physical wand, and the receiver's EFFECTIVE economy numbers — {@link WandPerks} folds
 * the tree's stat nodes and the rebirth multipliers in, so the panel/HUD never display
 * raw config values this player's casts would not actually pay.
 *
 * <p>Send points: login ({@code WandEvents}), successful cast + kill bonus + path choice
 * ({@code WandPowers}), node purchase / rebirth / tree spell-select
 * ({@code WandTreeService}), dev progression edits ({@code DevWandCommands}), and a
 * whole-server broadcast after {@code /dev reload} re-reads {@code wand.json}
 * (registered next to the reload hook in {@code WandItems.register}).</p>
 */
public final class WandProgressSync {
    private WandProgressSync() {}

    /** Sends the receiver a fresh snapshot of their own wand progression + server tuning. */
    public static void syncTo(ServerPlayer player) {
        WandConfig.Data config = WandConfig.get();
        WandStore store = WandStore.get(player.server);
        WandStore.Progress progress = store.progress(player.getUUID());

        int level;
        int xp;
        ItemStack wand = findOwnedWand(player);
        if (store.perItemMode()) {
            // ITEM mode: display level/xp live on the stack (no wand = nothing yet).
            level = wand != null ? WandSoulbind.levelOf(wand) : 1;
            xp = wand != null ? Math.max(0, wand.getOrDefault(WandItems.WAND_XP.get(), 0)) : 0;
        } else {
            level = progress.level;
            xp = Math.max(0, progress.xp);
        }
        int chargeMax = WandPerks.chargeMax(player);
        int charge = wand != null
                ? wand.getOrDefault(WandItems.WAND_CHARGE.get(), chargeMax)
                : chargeMax;
        float regenPerSecond = config.charge().regenHeldPerSecond()
                * WandPerks.regenMultiplier(player);

        List<S2CWandProgressPayload.SpellRow> rows = new ArrayList<>(WandSpells.all().size());
        for (WandSpell spell : WandSpells.all()) {
            rows.add(new S2CWandProgressPayload.SpellRow(
                    spell.key(),
                    WandPerks.effectiveCost(player, config.power(spell))));
        }

        PacketDistributor.sendToPlayer(player, new S2CWandProgressPayload(
                level, xp, Math.max(0, progress.rebirths), charge, chargeMax,
                regenPerSecond, WandPerks.damageMultiplier(player),
                config.xp().perCostPoint(), config.xp().killBonus(),
                List.copyOf(progress.nodes), rows));
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
