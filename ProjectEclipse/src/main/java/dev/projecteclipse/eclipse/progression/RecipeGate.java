package dev.projecteclipse.eclipse.progression;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

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
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Day-tier crafting gate: locked results are stripped on {@link PlayerEvent.ItemCraftedEvent}
 * (including smithing). Locked ids are broadcast to clients for EMI hiding via
 * {@link S2CRecipeLocksPayload}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RecipeGate {
    private static final int HINT_COLOR = 0xB98CFF;
    private static final AtomicBoolean DAY_ROLLOVER_REGISTERED = new AtomicBoolean(false);

    private RecipeGate() {}

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

    /** Flattened item ids for the wire payload (tags expanded). */
    public static List<String> lockedItemIds(MinecraftServer server) {
        return List.copyOf(resolveLocks(server).lockedItemIds());
    }

    public static List<String> lockedRecipeIds(MinecraftServer server) {
        return List.copyOf(resolveLocks(server).lockedRecipeIds());
    }

    public static void syncTo(ServerPlayer player) {
        MinecraftServer server = player.server;
        PacketDistributor.sendToPlayer(player, payloadFor(server));
    }

    public static void broadcastAll(MinecraftServer server) {
        S2CRecipeLocksPayload payload = payloadFor(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, payload);
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
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            syncTo(player);
        }
    }

    @SubscribeEvent
    public static void onItemCrafted(PlayerEvent.ItemCraftedEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        ItemStack crafted = event.getCrafting();
        if (isItemLocked(player.server, crafted)) {
            crafted.shrink(crafted.getCount());
            hint(player);
        }
    }

    private static S2CRecipeLocksPayload payloadFor(MinecraftServer server) {
        LockedSnapshot locks = resolveLocks(server);
        return new S2CRecipeLocksPayload(locks.lockedItemIds(), locks.lockedRecipeIds());
    }

    private static LockedSnapshot resolveLocks(MinecraftServer server) {
        int day = DayScheduler.getDay(server);
        RecipeGateMath.LockedEntries raw = RecipeGateMath.lockedAt(day, RecipeGateConfig.current());
        Set<String> itemIds = new HashSet<>();
        Set<TagKey<Item>> tags = new HashSet<>();
        for (String entry : raw.itemEntries()) {
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
        Set<String> recipeIds = new HashSet<>(raw.recipeIds());
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

    private static void hint(ServerPlayer player) {
        player.displayClientMessage(
                Component.translatable("message.eclipse.recipe.locked").withColor(HINT_COLOR), true);
        player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.7F, 0.55F);
    }

    private record LockedSnapshot(List<String> lockedItemIds, List<String> lockedRecipeIds, Set<TagKey<Item>> lockedTags) {}
}
