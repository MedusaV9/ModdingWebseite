package dev.projecteclipse.eclipse.villagers;

import java.util.Iterator;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.protection.ProtectionConfig;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.npc.Villager;
import net.minecraft.world.entity.npc.VillagerData;
import net.minecraft.world.entity.npc.VillagerProfession;
import net.minecraft.world.entity.npc.VillagerTrades;
import net.minecraft.world.entity.npc.WanderingTrader;
import net.minecraft.world.entity.animal.horse.TraderLlama;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.trading.MerchantOffer;
import net.minecraft.world.item.trading.MerchantOffers;
import net.minecraft.world.level.GameRules;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.event.village.VillagerTradesEvent;
import net.neoforged.neoforge.event.village.WandererTradesEvent;

/**
 * Villager and wandering-trader restrictions: no librarians, no enchanted-book trades,
 * no natural wandering traders (spawn eggs / commands still allowed).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class VillagerRestrictions {
    private static final int SWEEP_INTERVAL_TICKS = 100;
    private static final AtomicBoolean GAMERULE_APPLIED = new AtomicBoolean(false);

    private VillagerRestrictions() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        ProtectionConfig.VillagerRules rules = ProtectionConfig.current().villagers();
        if (rules.disableWanderingTrader() && GAMERULE_APPLIED.compareAndSet(false, true)) {
            event.getServer().getGameRules().getRule(GameRules.RULE_DO_TRADER_SPAWNING).set(false, event.getServer());
            EclipseMod.LOGGER.info("Wandering trader spawning disabled (doTraderSpawning=false)");
        }
    }

    @SubscribeEvent
    public static void onVillagerTrades(VillagerTradesEvent event) {
        ProtectionConfig.VillagerRules rules = ProtectionConfig.current().villagers();
        if (rules.blockLibrarian() && event.getType() == VillagerProfession.LIBRARIAN) {
            event.getTrades().clear();
            return;
        }
        if (rules.blockEnchantedBookTrades()) {
            stripEnchantedBookListings(event.getTrades());
        }
    }

    @SubscribeEvent
    public static void onWandererTrades(WandererTradesEvent event) {
        if (!ProtectionConfig.current().villagers().blockEnchantedBookTrades()) {
            return;
        }
        stripEnchantedBookListings(event.getGenericTrades());
        stripEnchantedBookListings(event.getRareTrades());
    }

    @SubscribeEvent
    public static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getLevel().isClientSide() || !(event.getTarget() instanceof Villager villager)) {
            return;
        }
        if (!(event.getEntity().level() instanceof ServerLevel level)) {
            return;
        }
        ProtectionConfig.VillagerRules rules = ProtectionConfig.current().villagers();
        if (rules.blockEnchantedBookTrades()) {
            filterMerchantOffers(villager.getOffers());
        }
        if (rules.blockLibrarian()) {
            demoteLibrarian(level, villager);
        }
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (event.getServer().getTickCount() % SWEEP_INTERVAL_TICKS != 0) {
            return;
        }
        ProtectionConfig.VillagerRules rules = ProtectionConfig.current().villagers();
        if (!rules.blockLibrarian() && !rules.blockEnchantedBookTrades()) {
            return;
        }
        for (ServerLevel level : event.getServer().getAllLevels()) {
            // Entity-list iteration, NOT an AABB query: a world-sized AABB walks the whole
            // section grid (and trips Sable's abnormal-AABB guard every sweep).
            for (Villager villager : level.getEntities(EntityType.VILLAGER, v -> v.isAlive())) {
                if (rules.blockEnchantedBookTrades()) {
                    filterMerchantOffers(villager.getOffers());
                }
                if (rules.blockLibrarian()) {
                    demoteLibrarian(level, villager);
                }
            }
        }
    }

    @SubscribeEvent
    public static void onEntityJoinLevel(EntityJoinLevelEvent event) {
        if (event.getLevel().isClientSide() || event.loadedFromDisk()) {
            return;
        }
        if (!ProtectionConfig.current().villagers().disableWanderingTrader()) {
            return;
        }
        Entity entity = event.getEntity();
        if (entity instanceof WanderingTrader trader) {
            if (shouldCancelNaturalTrader(trader.getSpawnType())) {
                event.setCanceled(true);
            }
            return;
        }
        if (entity instanceof TraderLlama llama) {
            Entity leash = llama.getLeashHolder();
            if (leash instanceof WanderingTrader && shouldCancelNaturalTrader(llama.getSpawnType())) {
                event.setCanceled(true);
            }
        }
    }

    public static boolean shouldCancelNaturalTrader(MobSpawnType spawnType) {
        if (spawnType == null) {
            return true;
        }
        return switch (spawnType) {
            case NATURAL, PATROL, REINFORCEMENT, JOCKEY, EVENT, SPAWNER, STRUCTURE -> true;
            default -> false;
        };
    }

    static void stripEnchantedBookListings(it.unimi.dsi.fastutil.ints.Int2ObjectMap<List<VillagerTrades.ItemListing>> trades) {
        for (int level : trades.keySet()) {
            List<VillagerTrades.ItemListing> listings = trades.get(level);
            if (listings == null) {
                continue;
            }
            listings.removeIf(VillagerRestrictions::listingInvolvesEnchantedBook);
        }
    }

    static void stripEnchantedBookListings(List<VillagerTrades.ItemListing> listings) {
        listings.removeIf(VillagerRestrictions::listingInvolvesEnchantedBook);
    }

    private static boolean listingInvolvesEnchantedBook(VillagerTrades.ItemListing listing) {
        // The canonical enchanted-book listing can be identified without instantiating an
        // offer (instantiating requires a live trader entity for several vanilla listings).
        if (listing instanceof VillagerTrades.EnchantBookForEmeralds) {
            return true;
        }
        try {
            MerchantOffer offer = listing.getOffer(null, net.minecraft.util.RandomSource.create());
            return offer != null && offerIsEnchantedBook(offer);
        } catch (RuntimeException e) {
            // Listing needs a live trader to build its sample offer (e.g. treasure maps).
            // It cannot be classified statically; the runtime offer filter
            // (filterMerchantOffers) still strips any enchanted book it might produce.
            return false;
        }
    }

    public static void filterMerchantOffers(MerchantOffers offers) {
        if (offers == null || offers.isEmpty()) {
            return;
        }
        Iterator<MerchantOffer> iterator = offers.iterator();
        while (iterator.hasNext()) {
            MerchantOffer offer = iterator.next();
            if (offerIsEnchantedBook(offer)) {
                iterator.remove();
            }
        }
    }

    static boolean offerIsEnchantedBook(MerchantOffer offer) {
        if (stackIsEnchantedBook(offer.getResult())) {
            return true;
        }
        if (stackIsEnchantedBook(offer.getCostA())) {
            return true;
        }
        ItemStack costB = offer.getCostB();
        return !costB.isEmpty() && stackIsEnchantedBook(costB);
    }

    private static boolean stackIsEnchantedBook(ItemStack stack) {
        return !stack.isEmpty() && stack.is(Items.ENCHANTED_BOOK);
    }

    private static void demoteLibrarian(ServerLevel level, Villager villager) {
        VillagerData data = villager.getVillagerData();
        if (data.getProfession() != VillagerProfession.LIBRARIAN) {
            return;
        }
        villager.setVillagerData(data.setProfession(VillagerProfession.NONE).setLevel(1));
        villager.setOffers(null);
        level.sendParticles(ParticleTypes.POOF, villager.getX(), villager.getY() + 1.0D, villager.getZ(),
                6, 0.25D, 0.25D, 0.25D, 0.02D);
    }
}
