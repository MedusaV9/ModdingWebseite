package dev.projecteclipse.eclipse.gameplay;

import java.util.LinkedHashSet;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.progression.RecipeGate;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * ALTARUI task 8 — Sophisticated Backpacks must NEVER be craftable, regardless of day or
 * ModGate unlock (the {@code sophisticatedbackpacks} namespace otherwise unseals on day 8,
 * "THE HOARD"). Mechanism: a permanent {@link RecipeGate#registerPlayerLockProvider}
 * provider (the D1 collections pattern) returning EVERY item id registered under the
 * {@value #NAMESPACE} namespace — backpacks of all tiers plus every upgrade, current and
 * future, without hand-listing the 60+ recipe ids in the mod jar. That rides the full
 * existing enforcement stack: the menu-level result guards in
 * {@code progression.CraftGateEnforcement} (3×3 table, 2×2 inventory grid, recipe-book
 * placement), the {@code ItemCraftedEvent} backstop (smithing, modded menus) and per-player
 * EMI recipe hiding via {@code S2CRecipeLocksPayload}.
 *
 * <p>Deliberately NOT covered (reported, needs {@code progression/} which another agent
 * owns): the vanilla Crafter obeys only the GLOBAL gates
 * ({@code CraftGateEnforcement#isAutomationCraftLocked}), so furniture could still
 * assemble a backpack after the day-8 ModGate unseal. Backpack USE stays untouched —
 * only crafting is banned.</p>
 *
 * <p>Providers are cleared on server stop ({@code RecipeGate.onServerStopped}), so this
 * re-registers on every {@link ServerStartedEvent} and re-broadcasts the lock sets like
 * {@code collections.CollectionsService} does. A specific hint line replaces the generic
 * "recipe locked" message when the confiscated result is a backpack item.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BackpackCraftBan {
    /** External mod namespace whose whole item set is craft-banned. */
    private static final String NAMESPACE = "sophisticatedbackpacks";

    /** Registry is frozen long before server start, so the id set is computed once. */
    private static volatile Set<String> bannedItemIds;

    private BackpackCraftBan() {}

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        Set<String> banned = bannedIds();
        // RecipeGate clears its provider lists on server stop; re-register each start.
        RecipeGate.registerPlayerLockProvider(player -> banned);
        RecipeGate.registerLockHintProvider(BackpackCraftBan::hintFor);
        // Re-sync EMI lock sets in case RecipeGate's own broadcast ran before this handler.
        RecipeGate.broadcastAll(event.getServer());
        EclipseMod.LOGGER.info("Backpack craft ban active ({} '{}' item id(s) locked)",
                banned.size(), NAMESPACE);
    }

    /** Every item id under {@value #NAMESPACE} — empty (no-op) when the mod is absent. */
    private static Set<String> bannedIds() {
        Set<String> ids = bannedItemIds;
        if (ids == null) {
            ids = new LinkedHashSet<>();
            for (ResourceLocation id : BuiltInRegistries.ITEM.keySet()) {
                if (NAMESPACE.equals(id.getNamespace())) {
                    ids.add(id.toString());
                }
            }
            ids = Set.copyOf(ids);
            bannedItemIds = ids;
        }
        return ids;
    }

    @Nullable
    private static Component hintFor(ServerPlayer player, ItemStack stack) {
        ResourceLocation id = BuiltInRegistries.ITEM.getKey(stack.getItem());
        return NAMESPACE.equals(id.getNamespace())
                ? Component.translatable("message.eclipse.backpack.craft_banned")
                : null;
    }
}
