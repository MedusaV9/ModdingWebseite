package dev.projecteclipse.eclipse.admin;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.common.util.TriState;
import net.neoforged.neoforge.event.entity.item.ItemTossEvent;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.AttackEntityEvent;
import net.neoforged.neoforge.event.entity.player.ItemEntityPickupEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;

/**
 * W4-TOGGLES: server-authoritative GLOBAL + PER-PLAYER action toggles (build, mine, craft,
 * pvp, move, interact, drop, pickup — chat is already sealed by {@code anonymity/ChatBlocker}
 * and deliberately has no toggle). Per-player ALLOW/DENY tri-state overrides beat the global
 * flag; state persists in {@link ActionTogglesState} ({@code eclipse_action_toggles.dat}).
 *
 * <p><b>Zero-cost when idle:</b> every enforcement handler first reads one {@code volatile}
 * bitmask ({@link #activeBits}) — a bit is set only while its action has a global deny or at
 * least one per-player DENY override, so with all toggles off each event costs a single field
 * read and branch (no map lookups, no allocation). The mask is refreshed on server start and
 * after every mutation (all mutations funnel through this class).</p>
 *
 * <p><b>Enforcement paths</b> (existing precedents reused, no shared files edited):</p>
 * <ul>
 *   <li>build — {@code BlockEvent.EntityPlaceEvent} cancel ({@code ModGate} pattern);</li>
 *   <li>mine — {@code BlockEvent.BreakEvent} cancel ({@code SanctumProtection} pattern);</li>
 *   <li>craft — {@code ItemCraftedEvent} is not cancellable, so the crafted result is shrunk
 *       to 0 exactly like {@code progression/RecipeGate} (all-recipes predicate);</li>
 *   <li>pvp — {@code AttackEntityEvent} (melee swing) + {@code LivingIncomingDamageEvent}
 *       (projectiles/indirect). Layers cleanly on {@code protection/SpawnProtectionRules}:
 *       both cancel independently, whichever fires first wins;</li>
 *   <li>move — reuses {@link FreezeService#freeze} (the cutscene rubber-band lock) instead of
 *       duplicating the mechanics. The lock is re-asserted every tick while denied (covering
 *       the mandatory TTL, death, dimension change and relog releases) and released on allow.
 *       NOTE: a FreezeService lock also implies invulnerability + interaction cancels — a
 *       move-denied player is effectively in "statue mode" (documented tradeoff);</li>
 *   <li>interact — {@code PlayerInteractEvent} RightClickBlock/RightClickItem/EntityInteract/
 *       EntityInteractSpecific cancels ({@code FreezeService} pattern);</li>
 *   <li>drop — {@code ItemTossEvent} cancel + stack returned to the inventory (cancelling
 *       alone would destroy the stack — {@code ArtifactSlotLock} precedent);</li>
 *   <li>pickup — {@code ItemEntityPickupEvent.Pre} with {@code TriState.FALSE}
 *       ({@code ModGate} pattern).</li>
 * </ul>
 *
 * <p>Deny feedback is a localized action-bar hint ({@code message.eclipse.toggle.<action>}),
 * throttled to one per player per {@value #HINT_THROTTLE_MILLIS} ms so held right-click,
 * standing on an item pile, or shift-mass-crafting cannot spam. Spectators are always exempt;
 * creative/ops are NOT (grant yourself a per-player ALLOW instead — explicit beats implicit).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ActionTogglesService {
    /** Eclipse accent (mirrors RecipeGate/ModGate hints). */
    private static final int HINT_COLOR = 0xB98CFF;
    private static final long HINT_THROTTLE_MILLIS = 1500L;
    /**
     * FreezeService TTL for the move-lock. The tick handler re-freezes as soon as the
     * watchdog releases, so the value only tunes how often the freeze/release log pair
     * appears for a long-term move-denied player (5 min).
     */
    private static final int MOVE_FREEZE_TTL_TICKS = 6000;

    /** Lock-free early-out mask: bit set while {@link ToggleAction#bit()} has restrictions. */
    private static volatile long activeBits = 0L;

    /** Players whose current FreezeService lock was applied BY THIS SERVICE. Server thread only. */
    private static final Set<UUID> MOVE_LOCKED = new HashSet<>();
    /** Last hint timestamp per player. Server thread only. */
    private static final Map<UUID, Long> LAST_HINT = new HashMap<>();

    private ActionTogglesService() {}

    // --- public API (DevToggleCommands is the only expected caller for mutations) ---

    public static boolean isGlobalAllowed(MinecraftServer server, ToggleAction action) {
        return ActionTogglesState.get(server).isGlobalAllowed(action);
    }

    /** TRUE = allow override, FALSE = deny override, {@code null} = inherit global. */
    @Nullable
    public static Boolean playerOverride(MinecraftServer server, ToggleAction action, UUID player) {
        return ActionTogglesState.get(server).override(action, player);
    }

    /** Effective permission (override beats global). Spectators are exempt at enforcement. */
    public static boolean isAllowed(MinecraftServer server, ToggleAction action, UUID player) {
        return ActionTogglesState.get(server).isAllowed(action, player);
    }

    public static Map<UUID, Boolean> overridesFor(MinecraftServer server, ToggleAction action) {
        return ActionTogglesState.get(server).overridesFor(action);
    }

    public static void setGlobal(MinecraftServer server, ToggleAction action, boolean allowed) {
        ActionTogglesState state = ActionTogglesState.get(server);
        state.setGlobalAllowed(action, allowed);
        refreshCache(state);
        reconcileMoveLocks(server, state);
        EclipseMod.LOGGER.info("ActionToggles: {} globally {}", action.id(), allowed ? "enabled" : "DISABLED");
    }

    /** @param allow TRUE/FALSE to set an ALLOW/DENY override, {@code null} to clear it. */
    public static void setOverride(MinecraftServer server, ToggleAction action, UUID player,
            @Nullable Boolean allow) {
        ActionTogglesState state = ActionTogglesState.get(server);
        state.setOverride(action, player, allow);
        refreshCache(state);
        reconcileMoveLocks(server, state);
        EclipseMod.LOGGER.info("ActionToggles: {} override for {} -> {}", action.id(), player,
                allow == null ? "cleared" : (allow ? "ALLOW" : "DENY"));
    }

    /** Resets every global flag to allowed and drops all overrides (move locks released). */
    public static void clearAll(MinecraftServer server) {
        ActionTogglesState state = ActionTogglesState.get(server);
        state.clearAll();
        refreshCache(state);
        reconcileMoveLocks(server, state);
        EclipseMod.LOGGER.info("ActionToggles: cleared all toggles and overrides");
    }

    // --- cache + move-lock reconciliation ---

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        // Static caches die with the JVM, not the save — rebuild for the new world.
        MOVE_LOCKED.clear();
        LAST_HINT.clear();
        refreshCache(ActionTogglesState.get(event.getServer()));
    }

    private static void refreshCache(ActionTogglesState state) {
        long bits = 0L;
        for (ToggleAction action : ToggleAction.values()) {
            if (state.hasAnyRestriction(action)) {
                bits |= action.bit();
            }
        }
        activeBits = bits;
    }

    /** Releases move locks the moment a mutation re-allows movement (tick path would early-out). */
    private static void reconcileMoveLocks(MinecraftServer server, ActionTogglesState state) {
        if (MOVE_LOCKED.isEmpty()) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (MOVE_LOCKED.contains(player.getUUID())
                    && (player.isSpectator() || state.isAllowed(ToggleAction.MOVE, player.getUUID()))) {
                MOVE_LOCKED.remove(player.getUUID());
                FreezeService.unfreeze(player);
            }
        }
    }

    // --- shared enforcement helpers ---

    /** Fast path: single volatile read; TRUE only while this action might deny someone. */
    private static boolean maybeActive(ToggleAction action) {
        return (activeBits & action.bit()) != 0L;
    }

    /** Full check, only reached while {@link #maybeActive} is true. Spectators are exempt. */
    private static boolean denied(ServerPlayer player, ToggleAction action) {
        if (player.isSpectator()) {
            return false;
        }
        return !ActionTogglesState.get(player.server).isAllowed(action, player.getUUID());
    }

    private static void hint(ServerPlayer player, ToggleAction action) {
        long now = System.currentTimeMillis();
        Long last = LAST_HINT.get(player.getUUID());
        if (last != null && now - last < HINT_THROTTLE_MILLIS) {
            return;
        }
        LAST_HINT.put(player.getUUID(), now);
        player.displayClientMessage(
                Component.translatable(action.denyMessageKey()).withColor(HINT_COLOR), true);
    }

    // --- build / mine ---

    @SubscribeEvent
    public static void onEntityPlace(BlockEvent.EntityPlaceEvent event) {
        if (!maybeActive(ToggleAction.BUILD) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.BUILD)) {
            event.setCanceled(true);
            hint(player, ToggleAction.BUILD);
        }
    }

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!maybeActive(ToggleAction.MINE) || !(event.getPlayer() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.MINE)) {
            event.setCanceled(true);
            hint(player, ToggleAction.MINE);
        }
    }

    // --- craft (ItemCraftedEvent is not cancellable: strip the result, RecipeGate mechanism) ---

    @SubscribeEvent
    public static void onItemCrafted(PlayerEvent.ItemCraftedEvent event) {
        if (!maybeActive(ToggleAction.CRAFT) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.CRAFT)) {
            ItemStack crafted = event.getCrafting();
            crafted.shrink(crafted.getCount());
            hint(player, ToggleAction.CRAFT);
        }
    }

    // --- pvp (melee swing + projectile/indirect; either side denied blocks the exchange) ---

    @SubscribeEvent
    public static void onAttackEntity(AttackEntityEvent event) {
        if (!maybeActive(ToggleAction.PVP)
                || !(event.getEntity() instanceof ServerPlayer attacker)
                || !(event.getTarget() instanceof ServerPlayer victim)) {
            return;
        }
        if (denied(attacker, ToggleAction.PVP) || denied(victim, ToggleAction.PVP)) {
            event.setCanceled(true);
            hint(attacker, ToggleAction.PVP);
        }
    }

    /** Arrows/tridents/TNT-by-player bypass {@code AttackEntityEvent} — cancel the damage too. */
    @SubscribeEvent
    public static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (!maybeActive(ToggleAction.PVP) || !(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        if (!(event.getSource().getEntity() instanceof ServerPlayer attacker) || attacker == victim) {
            return;
        }
        if (denied(attacker, ToggleAction.PVP) || denied(victim, ToggleAction.PVP)) {
            event.setCanceled(true);
            hint(attacker, ToggleAction.PVP);
        }
    }

    // --- move (FreezeService reuse: rubber-band lock re-asserted while denied) ---

    @SubscribeEvent
    public static void onPlayerTickPre(PlayerTickEvent.Pre event) {
        if (!maybeActive(ToggleAction.MOVE) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        UUID id = player.getUUID();
        if (denied(player, ToggleAction.MOVE)) {
            // Re-assert after watchdog TTL/death/dimension-change/relog releases. Never stack
            // on top of a foreign (cutscene) lock — it already prevents movement.
            if (!FreezeService.isFrozen(player)) {
                FreezeService.freeze(player, MOVE_FREEZE_TTL_TICKS);
                if (MOVE_LOCKED.add(id)) {
                    hint(player, ToggleAction.MOVE);
                }
            }
        } else if (MOVE_LOCKED.remove(id)) {
            FreezeService.unfreeze(player);
        }
    }

    // --- interact (right-click use: block, item, entity — FreezeService cancel set) ---

    @SubscribeEvent
    public static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (!maybeActive(ToggleAction.INTERACT) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.INTERACT)) {
            event.setCanceled(true);
            hint(player, ToggleAction.INTERACT);
        }
    }

    @SubscribeEvent
    public static void onRightClickItem(PlayerInteractEvent.RightClickItem event) {
        if (!maybeActive(ToggleAction.INTERACT) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.INTERACT)) {
            event.setCanceled(true);
            hint(player, ToggleAction.INTERACT);
        }
    }

    @SubscribeEvent
    public static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (!maybeActive(ToggleAction.INTERACT) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.INTERACT)) {
            event.setCanceled(true);
            hint(player, ToggleAction.INTERACT);
        }
    }

    @SubscribeEvent
    public static void onEntityInteractSpecific(PlayerInteractEvent.EntityInteractSpecific event) {
        if (!maybeActive(ToggleAction.INTERACT) || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.INTERACT)) {
            event.setCanceled(true);
            hint(player, ToggleAction.INTERACT);
        }
    }

    // --- drop / pickup ---

    @SubscribeEvent
    public static void onItemToss(ItemTossEvent event) {
        if (!maybeActive(ToggleAction.DROP) || !(event.getPlayer() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.DROP)) {
            event.setCanceled(true);
            // Cancelling alone destroys the stack (already removed from the inventory).
            player.getInventory().placeItemBackInInventory(event.getEntity().getItem());
            hint(player, ToggleAction.DROP);
        }
    }

    @SubscribeEvent
    public static void onItemPickup(ItemEntityPickupEvent.Pre event) {
        if (!maybeActive(ToggleAction.PICKUP) || !(event.getPlayer() instanceof ServerPlayer player)) {
            return;
        }
        if (denied(player, ToggleAction.PICKUP)) {
            event.setCanPickup(TriState.FALSE);
            hint(player, ToggleAction.PICKUP);
        }
    }

    // --- bookkeeping ---

    @SubscribeEvent
    public static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            // FreezeService releases its lock on logout itself; forget we owned it.
            MOVE_LOCKED.remove(player.getUUID());
            LAST_HINT.remove(player.getUUID());
        }
    }
}
