package dev.projecteclipse.eclipse.progression;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BiFunction;
import java.util.function.Function;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.network.S2CRecipeLocksPayload;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.crafting.RecipeHolder;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Crafting gate: locked results are stripped on {@link PlayerEvent.ItemCraftedEvent}
 * (including smithing). Locked ids are sent to clients for EMI hiding via
 * {@link S2CRecipeLocksPayload}.
 *
 * <p><b>Lock sources compose as a union</b> (D1, IDEAS-collections §4.2): the global
 * day-tier locks from {@code recipegate.json} PLUS any registered per-player lock
 * providers ({@link #registerPlayerLockProvider} — the collections system contributes
 * the {@code unlockItems} of every not-yet-reached tier). {@code syncTo(player)} and the
 * wire payload were per-player from day one, so per-player locks need no wire change.
 * Hint providers ({@link #registerLockHintProvider}) let the owning system replace the
 * generic "recipe locked" line with an actionable one ("Locked — reach Iron Collection
 * II"). Provider lists are cleared on server stop; owners re-register on
 * {@code ServerStartedEvent} like their signal listeners.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RecipeGate {
    private static final int HINT_COLOR = 0xB98CFF;
    private static final AtomicBoolean DAY_ROLLOVER_REGISTERED = new AtomicBoolean(false);

    /** Per-player lock entry providers (ids or {@code #tags}); cleared on server stop. */
    private static final List<Function<ServerPlayer, Set<String>>> PLAYER_LOCK_PROVIDERS =
            new CopyOnWriteArrayList<>();
    /** Per-player lock hint providers ({@code null} = not this system's lock); cleared on stop. */
    private static final List<BiFunction<ServerPlayer, ItemStack, Component>> HINT_PROVIDERS =
            new CopyOnWriteArrayList<>();

    private RecipeGate() {}

    // ------------------------------------------------------------------ provider registration (D1)

    /**
     * Registers a per-player lock provider returning recipegate-syntax entries (item ids
     * or {@code #tags}) that are locked for THAT player in addition to the day locks.
     * Register from {@code ServerStartedEvent}; the list clears on server stop.
     */
    public static void registerPlayerLockProvider(Function<ServerPlayer, Set<String>> provider) {
        PLAYER_LOCK_PROVIDERS.add(provider);
    }

    /**
     * Registers a locked-craft hint provider consulted when a craft is confiscated and the
     * GLOBAL day gate alone does not explain it. Return {@code null} when the stack is not
     * this system's lock; the first non-null hint wins.
     */
    public static void registerLockHintProvider(BiFunction<ServerPlayer, ItemStack, Component> provider) {
        HINT_PROVIDERS.add(provider);
    }

    // ------------------------------------------------------------------ lock queries

    /** GLOBAL day-tier check only (EMI/devtools surface). Per-player callers use {@link #isItemLockedFor}. */
    public static boolean isItemLocked(MinecraftServer server, ItemStack stack) {
        if (stack.isEmpty()) {
            return false;
        }
        ResourceLocation itemId = BuiltInRegistries.ITEM.getKey(stack.getItem());
        LockedSnapshot locks = resolveLocks(server);
        if (locks.lockedItemIds().contains(itemId.toString())) {
            return true;
        }
        for (TagKey<Item> tag : locks.lockedTags()) {
            if (stack.is(tag)) {
                return true;
            }
        }
        return false;
    }

    /** Day locks ∪ per-player provider locks — the craft-enforcement truth (D1 §4.2). */
    public static boolean isItemLockedFor(ServerPlayer player, ItemStack stack) {
        if (stack.isEmpty()) {
            return false;
        }
        if (isItemLocked(player.server, stack)) {
            return true;
        }
        return entriesMatch(stack, providerEntriesFor(player));
    }

    /** Whether the day config declares raw locked recipe ids at all (cheap pre-check). */
    public static boolean hasRecipeIdLocks(MinecraftServer server) {
        return !RecipeGateMath.lockedAt(DayScheduler.getDay(server), RecipeGateConfig.current())
                .recipeIds().isEmpty();
    }

    /**
     * Raw config {@code recipes}-entry lock check (day tiers, no tag/recipe-scan expansion).
     * EVAL-DOPA-S #1: these ids were previously sent to EMI only; the menu-level guards in
     * {@code CraftGateEnforcement} now enforce them server-side too.
     */
    public static boolean isRecipeIdLocked(MinecraftServer server, ResourceLocation recipeId) {
        return RecipeGateMath.lockedAt(DayScheduler.getDay(server), RecipeGateConfig.current())
                .recipeIds().contains(recipeId.toString());
    }

    /** Public seam for the menu-level guards: locked-craft feedback line + chime. */
    public static void hintLocked(ServerPlayer player, ItemStack stack) {
        hint(player, stack.copy());
    }

    /** Flattened GLOBAL item ids (tags expanded) — day locks only, EMI/devtools surface. */
    public static List<String> lockedItemIds(MinecraftServer server) {
        return List.copyOf(resolveLocks(server).lockedItemIds());
    }

    public static List<String> lockedRecipeIds(MinecraftServer server) {
        return List.copyOf(resolveLocks(server).lockedRecipeIds());
    }

    // ------------------------------------------------------------------ sync

    public static void syncTo(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, payloadFor(player));
    }

    /** Per-player payloads since D1 — every player may see a different lock set. */
    public static void broadcastAll(MinecraftServer server) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            syncTo(player);
        }
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (DAY_ROLLOVER_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover((server, endedDay, newDay, phase) -> {
                if (phase == EclipseSignals.DayRolloverPhase.POST) {
                    broadcastAll(server);
                }
            });
        }
        broadcastAll(event.getServer());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // Providers re-register from their owners' ServerStartedEvent (EclipseSignals pattern).
        PLAYER_LOCK_PROVIDERS.clear();
        HINT_PROVIDERS.clear();
    }

    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            syncTo(player);
        }
    }

    /**
     * Post-take backstop (smithing, modded menus). EVAL-DOPA-S #1: the PRIMARY enforcement
     * moved to the menu level — {@code CraftGateEnforcement} + the {@code gameplay.mixin}
     * seams empty a gated crafting-grid result before any pickup/quick-move path can read
     * it, block gated recipe-book placement, and gate the Crafter. This handler cannot be
     * relied on alone: quick-move transfers before {@code onTake}, so the shrink only
     * confiscates the plain-click path.
     */
    @SubscribeEvent
    public static void onItemCrafted(PlayerEvent.ItemCraftedEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        ItemStack crafted = event.getCrafting();
        if (isItemLockedFor(player, crafted)) {
            hint(player, crafted.copy());
            crafted.shrink(crafted.getCount());
        }
    }

    // ------------------------------------------------------------------ resolution

    private static S2CRecipeLocksPayload payloadFor(ServerPlayer player) {
        LockedSnapshot locks = resolveLocksFor(player);
        return new S2CRecipeLocksPayload(locks.lockedItemIds(), locks.lockedRecipeIds());
    }

    /** GLOBAL day-tier snapshot (no player context). */
    private static LockedSnapshot resolveLocks(MinecraftServer server) {
        RecipeGateMath.LockedEntries raw = RecipeGateMath.lockedAt(DayScheduler.getDay(server),
                RecipeGateConfig.current());
        return buildSnapshot(server, raw.itemEntries(), raw.recipeIds());
    }

    /** Day entries ∪ provider entries for one player, expanded to the wire shape. */
    private static LockedSnapshot resolveLocksFor(ServerPlayer player) {
        MinecraftServer server = player.server;
        RecipeGateMath.LockedEntries raw = RecipeGateMath.lockedAt(DayScheduler.getDay(server),
                RecipeGateConfig.current());
        Set<String> itemEntries = new LinkedHashSet<>(raw.itemEntries());
        itemEntries.addAll(providerEntriesFor(player));
        return buildSnapshot(server, itemEntries, raw.recipeIds());
    }

    private static Set<String> providerEntriesFor(ServerPlayer player) {
        if (PLAYER_LOCK_PROVIDERS.isEmpty()) {
            return Set.of();
        }
        Set<String> entries = new LinkedHashSet<>();
        for (Function<ServerPlayer, Set<String>> provider : PLAYER_LOCK_PROVIDERS) {
            Set<String> provided = provider.apply(player);
            if (provided != null) {
                entries.addAll(provided);
            }
        }
        return entries;
    }

    /** Raw entries (ids or {@code #tags}) → expanded item ids + locked recipe ids. */
    private static LockedSnapshot buildSnapshot(MinecraftServer server, Collection<String> itemEntries,
            Collection<String> rawRecipeIds) {
        Set<String> itemIds = new HashSet<>();
        Set<TagKey<Item>> tags = new HashSet<>();
        for (String entry : itemEntries) {
            if (entry.startsWith("#")) {
                ResourceLocation tagId = ResourceLocation.tryParse(entry.substring(1));
                if (tagId != null) {
                    tags.add(TagKey.create(Registries.ITEM, tagId));
                }
            } else {
                itemIds.add(entry);
            }
        }
        var itemRegistry = server.registryAccess().registryOrThrow(Registries.ITEM);
        for (TagKey<Item> tag : tags) {
            itemRegistry.getTag(tag).ifPresentOrElse(
                    holders -> holders.forEach(holder ->
                            itemIds.add(BuiltInRegistries.ITEM.getKey(holder.value()).toString())),
                    () -> EclipseMod.LOGGER.debug("Recipe gate tag {} not present in registry", tag.location()));
        }
        Set<String> recipeIds = new HashSet<>(rawRecipeIds);
        // Also mark recipes whose result item is locked (for EMI recipe-id hiding).
        var recipeManager = server.getRecipeManager();
        for (RecipeHolder<?> holder : recipeManager.getRecipes()) {
            ItemStack result = holder.value().getResultItem(server.registryAccess());
            if (!result.isEmpty() && isItemLockedBySnapshot(result, itemIds, tags)) {
                recipeIds.add(holder.id().toString());
            }
        }
        return new LockedSnapshot(new ArrayList<>(itemIds), new ArrayList<>(recipeIds), tags);
    }

    private static boolean isItemLockedBySnapshot(ItemStack stack, Set<String> lockedItemIds, Set<TagKey<Item>> lockedTags) {
        ResourceLocation itemId = BuiltInRegistries.ITEM.getKey(stack.getItem());
        if (lockedItemIds.contains(itemId.toString())) {
            return true;
        }
        for (TagKey<Item> tag : lockedTags) {
            if (stack.is(tag)) {
                return true;
            }
        }
        return false;
    }

    /** Cheap raw-entry match (no tag expansion) for the per-craft enforcement path. */
    private static boolean entriesMatch(ItemStack stack, Set<String> entries) {
        if (entries.isEmpty()) {
            return false;
        }
        String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        if (entries.contains(itemId)) {
            return true;
        }
        for (String entry : entries) {
            if (entry.startsWith("#")) {
                ResourceLocation tagId = ResourceLocation.tryParse(entry.substring(1));
                if (tagId != null && stack.is(TagKey.create(Registries.ITEM, tagId))) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Locked-craft feedback. When the GLOBAL day gate alone explains the confiscation the
     * generic line plays; otherwise the hint providers get a shot at an actionable line
     * ("Locked — reach Iron Collection II", D1 §3) before falling back to the generic one.
     */
    private static void hint(ServerPlayer player, ItemStack stack) {
        Component line = null;
        if (!isItemLocked(player.server, stack)) {
            line = providerHintFor(player, stack);
        }
        if (line == null) {
            line = Component.translatable("message.eclipse.recipe.locked");
        }
        player.displayClientMessage(line.copy().withColor(HINT_COLOR), true);
        player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.7F, 0.55F);
    }

    @Nullable
    private static Component providerHintFor(ServerPlayer player, ItemStack stack) {
        for (BiFunction<ServerPlayer, ItemStack, Component> provider : HINT_PROVIDERS) {
            Component hint = provider.apply(player, stack);
            if (hint != null) {
                return hint;
            }
        }
        return null;
    }

    private record LockedSnapshot(List<String> lockedItemIds, List<String> lockedRecipeIds, Set<TagKey<Item>> lockedTags) {}
}
