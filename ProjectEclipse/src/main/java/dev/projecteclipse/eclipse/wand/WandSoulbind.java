package dev.projecteclipse.eclipse.wand;

import java.util.UUID;

import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.item.ItemStack;

/**
 * Soulbind rules of the Zauberstab (W4-WAND spec §1). Runs from
 * {@code EclipseWandItem#inventoryTick} on the server for EVERY wand stack in a player
 * inventory — pickup, hotbar, container-shuffles all funnel through here within a tick.
 *
 * <p><b>PLAYER mode (default):</b> per-player progression is the truth
 * ({@link WandStore.Progress}). A wand whose {@code wand_owner} differs from the holder
 * CONVERTS into the holder's own wand — owner rewritten, path/level/xp loaded from the
 * holder's persisted row (charge is a property of the physical wand and carries over).
 * While owned, components continuously mirror the store row, so dev-command edits and
 * kill-bonus XP show up on the item without extra plumbing.</p>
 *
 * <p><b>ITEM mode ({@code /dev wand mode item}):</b> progression lives on the stack.
 * Conversion only rewrites the owner (stealing a leveled wand keeps its levels — that is
 * the point); the store row is not consulted.</p>
 *
 * <p><b>Trading ({@code /dev wand trading on}):</b> conversion is suppressed entirely so
 * wands can be handed over or shown around. Non-owners still cannot cast
 * ({@code WandPowers} refuses).</p>
 */
public final class WandSoulbind {
    private WandSoulbind() {}

    /**
     * Per-server-tick ownership upkeep for one wand stack in {@code holder}'s inventory.
     * Cheap when nothing changes (a couple of component reads).
     */
    public static void tick(ServerPlayer holder, ItemStack stack) {
        WandStore store = WandStore.get(holder.server);
        UUID owner = stack.get(WandItems.WAND_OWNER.get());

        if (owner == null) {
            // Freshly crafted / spawned-in wand: first holder attunes it.
            claim(holder, stack, store, true);
            return;
        }
        if (!owner.equals(holder.getUUID())) {
            if (store.tradingEnabled()) {
                return; // deliberate hand-over window — foreign wand stays foreign
            }
            claim(holder, stack, store, false);
            return;
        }
        if (!store.perItemMode()) {
            mirrorFromStore(holder, stack, store);
        }
    }

    /** Rewrites the wand to {@code holder} (fresh claim or conversion). */
    private static void claim(ServerPlayer holder, ItemStack stack, WandStore store, boolean fresh) {
        stack.set(WandItems.WAND_OWNER.get(), holder.getUUID());
        if (store.perItemMode()) {
            // Item-mode conversion keeps the stack's own path/level/xp; just seed defaults.
            ensureItemDefaults(stack);
        } else {
            WandStore.Progress progress = store.progress(holder.getUUID());
            writeProgress(stack, progress);
        }
        clampSelected(stack);
        if (stack.get(WandItems.WAND_CHARGE.get()) == null) {
            stack.set(WandItems.WAND_CHARGE.get(), WandConfig.get().charge().max());
        }
        holder.displayClientMessage(Component.translatable(
                fresh ? "wand.eclipse.msg.attuned" : "wand.eclipse.msg.converted"), true);
        holder.serverLevel().playSound(null, holder.getX(), holder.getY(), holder.getZ(),
                SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.PLAYERS, 0.8F, fresh ? 1.1F : 0.7F);
    }

    /** PLAYER mode: store row → item components (store is the single source of truth). */
    private static void mirrorFromStore(ServerPlayer holder, ItemStack stack, WandStore store) {
        WandStore.Progress progress = store.progress(holder.getUUID());
        Integer path = stack.get(WandItems.WAND_PATH.get());
        Integer level = stack.get(WandItems.WAND_LEVEL.get());
        Integer xp = stack.get(WandItems.WAND_XP.get());
        if (path == null || path != progress.pathId
                || level == null || level != progress.level
                || xp == null || xp != progress.xp) {
            writeProgress(stack, progress);
            clampSelected(stack);
        }
    }

    /** PLAYER mode write-back: item gained progression → persist to the holder's row. */
    public static void persistToStore(ServerPlayer holder, ItemStack stack) {
        WandStore store = WandStore.get(holder.server);
        if (store.perItemMode()) {
            return;
        }
        WandStore.Progress progress = store.progress(holder.getUUID());
        progress.pathId = pathOf(stack).id();
        progress.level = levelOf(stack);
        progress.xp = Math.max(0, stack.getOrDefault(WandItems.WAND_XP.get(), 0));
        store.setDirty();
    }

    private static void writeProgress(ItemStack stack, WandStore.Progress progress) {
        stack.set(WandItems.WAND_PATH.get(), progress.pathId);
        stack.set(WandItems.WAND_LEVEL.get(), Mth.clamp(progress.level, 1, WandPath.MAX_LEVEL));
        stack.set(WandItems.WAND_XP.get(), Math.max(0, progress.xp));
    }

    private static void ensureItemDefaults(ItemStack stack) {
        if (stack.get(WandItems.WAND_PATH.get()) == null) {
            stack.set(WandItems.WAND_PATH.get(), WandPath.NONE.id());
        }
        if (stack.get(WandItems.WAND_LEVEL.get()) == null) {
            stack.set(WandItems.WAND_LEVEL.get(), 1);
        }
        if (stack.get(WandItems.WAND_XP.get()) == null) {
            stack.set(WandItems.WAND_XP.get(), 0);
        }
    }

    /** Keeps the selected-power index inside the unlocked range after level/path edits. */
    public static void clampSelected(ItemStack stack) {
        int level = levelOf(stack);
        int selected = stack.getOrDefault(WandItems.WAND_SELECTED.get(), 0);
        if (pathOf(stack) == WandPath.NONE) {
            stack.set(WandItems.WAND_SELECTED.get(), 0);
        } else if (selected >= level) {
            stack.set(WandItems.WAND_SELECTED.get(), level - 1);
        }
    }

    // ------------------------------------------------------------------ component reads

    public static WandPath pathOf(ItemStack stack) {
        return WandPath.byId(stack.getOrDefault(WandItems.WAND_PATH.get(), WandPath.NONE.id()));
    }

    public static int levelOf(ItemStack stack) {
        return Mth.clamp(stack.getOrDefault(WandItems.WAND_LEVEL.get(), 1), 1, WandPath.MAX_LEVEL);
    }

    public static boolean isOwner(ServerPlayer player, ItemStack stack) {
        UUID owner = stack.get(WandItems.WAND_OWNER.get());
        return owner != null && owner.equals(player.getUUID());
    }
}
