package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.item.ItemStack;

/**
 * F-036 server engine for the wand skill tree: node purchases, the rebirth flow and the
 * unlocked-spell resolution every cast/cycle relies on. All entry points revalidate
 * everything (the {@code WandPowers} law): actor state (incl. the WANDFIX-7 cutscene
 * freeze), a HELD owned wand (F-037's server half — no wand in hand, no skilling),
 * node existence, parent ownership and the Wand-XP balance. The client never decides
 * anything.
 *
 * <p><b>Rebirth (F-036):</b> requires ALL {@link WandTree#nodeCount()} nodes owned AND
 * {@link WandTree#rebirthCost} spendable Wand-XP. The tree resets to the chosen path's
 * baseline node, the counter increments (permanent +15% spell power / +10% max
 * Veilladung per rebirth via {@link WandPerks}) and the level snaps back to 1 — the
 * long-haul incremental loop.</p>
 */
public final class WandTreeService {
    private WandTreeService() {}

    // ------------------------------------------------------------------ shared reads

    /**
     * The ordered unlocked-spell list: every spell whose tree node the player owns
     * (canonical {@link WandSpells#all} order — the chosen path's baseline rides its
     * auto-granted s1 node). Empty while pathless.
     */
    public static List<WandSpell> unlockedSpells(ServerPlayer player) {
        WandStore.Progress progress = WandStore.get(player.server).progress(player.getUUID());
        if (progress.path() == WandPath.NONE) {
            return List.of();
        }
        List<WandSpell> unlocked = new ArrayList<>();
        for (WandSpell spell : WandSpells.all()) {
            WandTree.Node node = WandTree.byId(nodeIdOfSpell(spell));
            if (node != null && progress.nodes.contains(node.id())) {
                unlocked.add(spell);
            }
        }
        return unlocked;
    }

    /** The tree node that unlocks {@code spell} ({@code <path>_s<ordinal+1>}). */
    public static String nodeIdOfSpell(WandSpell spell) {
        return spell.path().name().toLowerCase(java.util.Locale.ROOT) + "_s" + (spell.ordinal() + 1);
    }

    /**
     * Migration + first-choice grant: a player with a chosen path always owns that
     * path's s1 baseline node (pre-rework saves have progression but no nodes).
     */
    public static void ensureBaseline(ServerPlayer player) {
        WandStore store = WandStore.get(player.server);
        WandStore.Progress progress = store.progress(player.getUUID());
        if (progress.path() == WandPath.NONE) {
            return;
        }
        String baseline = progress.path().name().toLowerCase(java.util.Locale.ROOT) + "_s1";
        if (progress.nodes.add(baseline)) {
            recalcLevel(player, progress, false);
            store.setDirty();
        }
    }

    // ------------------------------------------------------------------ payload entry points

    /** {@code C2SWandNodeBuyPayload} handler — the ONLY way a tree node is bought. */
    public static void handleNodeBuy(ServerPlayer player, String nodeId) {
        ItemStack stack = requireHeldOwnedWand(player);
        if (stack == null) {
            return;
        }
        WandTree.Node node = WandTree.byId(nodeId);
        if (node == null) {
            return; // forged/stale id
        }
        WandStore store = WandStore.get(player.server);
        WandStore.Progress progress = store.progress(player.getUUID());
        if (progress.path() == WandPath.NONE) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.pathless"), true);
            return;
        }
        ensureBaseline(player);
        if (progress.nodes.contains(nodeId)) {
            return; // already owned — stale double-click
        }
        if (!WandTree.parentsOwned(node, progress.nodes)) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.node_locked"), true);
            return;
        }
        if (progress.xp < node.cost()) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.node_poor",
                    node.cost(), progress.xp), true);
            player.serverLevel().playSound(null, player.getX(), player.getY(), player.getZ(),
                    SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.5F, 0.5F);
            return;
        }
        progress.xp -= node.cost();
        progress.nodes.add(nodeId);
        store.setDirty();

        // Feedback: spell unlocks announce + auto-select the fresh spell; stat nodes chime.
        ServerLevel level = player.serverLevel();
        WandSpell unlockedSpell = WandSpells.byKey(node.spellKey());
        if (unlockedSpell != null) {
            stack.set(WandItems.WAND_SPELL.get(), unlockedSpell.key());
            player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.spell_unlocked",
                    Component.translatable(unlockedSpell.langKey())));
            player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.cycle_hint"));
        }
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.PLAYERS, 0.7F,
                unlockedSpell != null ? 1.3F : 1.0F);
        recalcLevel(player, progress, true);
        WandSoulbind.persistToStore(player, stack);
        WandProgressSync.syncTo(player);
    }

    /** {@code C2SWandRebirthPayload} handler — full-tree reset for permanent multipliers. */
    public static void handleRebirth(ServerPlayer player) {
        ItemStack stack = requireHeldOwnedWand(player);
        if (stack == null) {
            return;
        }
        WandStore store = WandStore.get(player.server);
        WandStore.Progress progress = store.progress(player.getUUID());
        if (progress.path() == WandPath.NONE) {
            return;
        }
        ensureBaseline(player);
        if (!WandTree.isMaxed(progress.nodes)) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.rebirth_not_maxed",
                    progress.nodes.size(), WandTree.nodeCount()), true);
            return;
        }
        long cost = WandTree.rebirthCost(progress.rebirths);
        if (progress.xp < cost) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.rebirth_poor",
                    cost, progress.xp), true);
            return;
        }
        progress.xp -= (int) cost;
        progress.nodes.clear();
        progress.rebirths++;
        store.setDirty();
        ensureBaseline(player); // re-grant the chosen path's baseline spell node
        recalcLevel(player, progress, false);
        WandSpell baseline = WandSpells.baselineOf(progress.path());
        if (baseline != null) {
            stack.set(WandItems.WAND_SPELL.get(), baseline.key());
        }
        WandSoulbind.persistToStore(player, stack);

        // Ceremony: the awaken anim + celebration pops + a deep resonate — a rebirth is
        // the wand's biggest single moment, it should land like one.
        ServerLevel level = player.serverLevel();
        EclipseWandItem.triggerWandAnim(player, stack, EclipseWandItem.ANIM_AWAKEN);
        WandPowers.celebrationBurst(level, player.position().add(0.0D, 1.2D, 0.0D));
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.BEACON_ACTIVATE, SoundSource.PLAYERS, 0.9F, 0.8F);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.PLAYERS, 1.0F, 0.55F);
        player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.rebirth_done",
                progress.rebirths,
                Math.round(WandTree.REBIRTH_POWER_PCT * 100.0F * progress.rebirths),
                Math.round(WandTree.REBIRTH_CHARGE_PCT * 100.0F * progress.rebirths)));
        WandProgressSync.syncTo(player);
    }

    /** {@code C2SWandSelectSpellPayload} handler — direct selection from the tree tab. */
    public static void handleSelectSpell(ServerPlayer player, String spellKey) {
        ItemStack stack = requireHeldOwnedWand(player);
        if (stack == null) {
            return;
        }
        WandSpell spell = WandSpells.byKey(spellKey);
        if (spell == null) {
            return;
        }
        ensureBaseline(player);
        List<WandSpell> unlocked = unlockedSpells(player);
        int slot = unlocked.indexOf(spell);
        if (slot < 0) {
            return; // not unlocked — forged/stale request
        }
        WandPowers.selectSpell(player, stack, spell, slot);
        WandProgressSync.syncTo(player);
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Recomputes the derived display level from the owned-node count and mirrors it to
     * the store row + the player's owned wands; {@code celebrate} plays the level-up
     * flourish when the level actually rose (node purchases only — not migrations).
     */
    static void recalcLevel(ServerPlayer player, WandStore.Progress progress, boolean celebrate) {
        int derived = WandTree.levelForNodes(progress.nodes.size());
        if (derived == progress.level) {
            return;
        }
        boolean rose = derived > progress.level;
        progress.level = derived;
        ItemStack wand = WandPowers.findHeldWand(player);
        if (wand != null && WandSoulbind.isOwner(player, wand)) {
            wand.set(WandItems.WAND_LEVEL.get(), derived);
        }
        if (celebrate && rose) {
            ServerLevel level = player.serverLevel();
            if (wand != null) {
                EclipseWandItem.triggerWandAnim(player, wand, EclipseWandItem.ANIM_LEVELUP);
            }
            WandPowers.celebrationBurst(level, player.position().add(0.0D, 1.2D, 0.0D));
            level.playSound(null, player.getX(), player.getY(), player.getZ(),
                    SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.8F, 1.4F);
            player.sendSystemMessage(ServerLang.tr(player, "wand.eclipse.msg.levelup", derived));
        }
    }

    /**
     * The shared validation ladder of every tree entry point: actor gate (WANDFIX-7
     * freeze included), a wand in main/off hand (F-037 server half), ownership, global
     * disable. Returns the held wand stack or null (with feedback where it matters).
     */
    private static ItemStack requireHeldOwnedWand(ServerPlayer player) {
        if (!WandPowers.isActorValid(player)) {
            return null;
        }
        WandStore store = WandStore.get(player.server);
        if (store.isDisabled()) {
            return null;
        }
        ItemStack stack = WandPowers.findHeldWand(player);
        if (stack == null) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.hold_wand"), true);
            return null;
        }
        WandSoulbind.tick(player, stack);
        if (!WandSoulbind.isOwner(player, stack)) {
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.not_owner"), true);
            return null;
        }
        return stack;
    }
}
