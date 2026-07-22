package dev.projecteclipse.eclipse.economy;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.ritual.AltarBlock;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.HitResult;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The altar shard shop (spec §4). UX flow, all action bar + sounds, never chat:
 * <ol>
 *   <li><b>Bank:</b> sneak-right-click the altar with umbral shards ({@link
 *       UmbralShardItem#useOn}) — the whole stack is deposited, crediting the personal
 *       {@code eclipse:shards} balance AND the team pool ({@link
 *       EclipseWorldState#getShardPool()}).</li>
 *   <li><b>Browse:</b> sneak while looking at the altar — the offer list cycles on the
 *       action bar every {@value #CYCLE_INTERVAL_TICKS} ticks.</li>
 *   <li><b>Buy:</b> sneak-punch (left-click) the altar — buys the offer currently shown.
 *       Personal rewards deduct the personal balance; the pooled Supply Beacon deducts the
 *       team pool and fires {@link SupplyBeacon#drop} at secret coordinates.</li>
 * </ol>
 *
 * <p>Also home of the umbral-pick perk: +50% break speed under open night sky
 * ({@link #onBreakSpeed}). The umbral-blade lifesteal lives in the kill path
 * ({@code lives.LifecycleEvents}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ShardEconomy {
    /** One shop entry; {@code item} is {@code null} for the pooled supply beacon (not an item). */
    public record Offer(String nameKey, Supplier<? extends Item> item, int cost, boolean pooled) {}

    public static final int SUPPLY_BEACON_COST = 24;

    /** Cheapest first; the pooled team reward closes the loop. */
    private static final List<Offer> OFFERS = List.of(
            new Offer("item.eclipse.grave_dowser", EclipseItems.GRAVE_DOWSER, 4, false),
            new Offer("item.eclipse.compass_of_watcher", EclipseItems.COMPASS_OF_WATCHER, 8, false),
            new Offer("item.eclipse.vitae_shard", EclipseItems.VITAE_SHARD, 12, false),
            new Offer("item.eclipse.umbral_pick", EclipseItems.UMBRAL_PICK, 12, false),
            new Offer("item.eclipse.umbral_blade", EclipseItems.UMBRAL_BLADE, 16, false),
            new Offer("item.eclipse.supply_beacon", null, SUPPLY_BEACON_COST, true));

    private static final int CYCLE_INTERVAL_TICKS = 20;
    private static final double BROWSE_REACH_BLOCKS = 6.0D;
    private static final float UMBRAL_PICK_NIGHT_SKY_BONUS = 1.5F;

    /** Transient per-player browse cursor; present only while sneaking at the altar. */
    private static final Map<UUID, Integer> BROWSE_INDEX = new HashMap<>();

    private ShardEconomy() {}

    // --- personal balance ---

    /** The player's banked personal shard balance ({@code eclipse:shards} attachment). */
    public static int getShards(ServerPlayer player) {
        return player.getData(EclipseAttachments.SHARDS);
    }

    /** Adds {@code delta} (may be negative) to the personal balance, clamped to {@code >= 0}; returns the new value. */
    public static int addShards(ServerPlayer player, int delta) {
        return setShards(player, getShards(player) + delta);
    }

    public static int setShards(ServerPlayer player, int value) {
        int clamped = Math.max(0, value);
        player.setData(EclipseAttachments.SHARDS, clamped);
        return clamped;
    }

    // --- bank (called by UmbralShardItem#useOn) ---

    /** Deposits the WHOLE held shard stack: personal balance + team pool, chime + action-bar receipt. */
    public static void deposit(ServerPlayer player, ItemStack shardStack) {
        int amount = shardStack.getCount();
        if (amount <= 0) {
            return;
        }
        shardStack.shrink(amount);
        int balance = addShards(player, amount);
        int pool = EclipseWorldState.get(player.server).addShardPool(amount);
        player.displayClientMessage(Component.translatable("shop.eclipse.deposited", amount, balance, pool), true);
        player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 1.0F, 1.2F);
        EclipseMod.LOGGER.info("{} banked {} umbral shard(s) (balance {}, pool {})",
                player.getScoreboardName(), amount, balance, pool);
    }

    // --- browse: action-bar offer cycling ---

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % CYCLE_INTERVAL_TICKS != 0) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isShiftKeyDown() && isLookingAtAltar(player)) {
                int index = BROWSE_INDEX.merge(player.getUUID(), 0,
                        (previous, ignored) -> (previous + 1) % OFFERS.size());
                showOffer(player, OFFERS.get(index));
            } else {
                BROWSE_INDEX.remove(player.getUUID());
            }
        }
    }

    private static void showOffer(ServerPlayer player, Offer offer) {
        Component name = Component.translatable(offer.nameKey());
        Component line = offer.pooled()
                ? Component.translatable("shop.eclipse.offer_pooled", name, offer.cost(),
                        EclipseWorldState.get(player.server).getShardPool())
                : Component.translatable("shop.eclipse.offer", name, offer.cost(), getShards(player));
        player.displayClientMessage(line, true);
    }

    /** Server-side ray trace: is the player's crosshair on an altar block within browse reach? */
    private static boolean isLookingAtAltar(ServerPlayer player) {
        HitResult hit = player.level().clip(new ClipContext(
                player.getEyePosition(),
                player.getEyePosition().add(player.getLookAngle().scale(BROWSE_REACH_BLOCKS)),
                ClipContext.Block.OUTLINE, ClipContext.Fluid.NONE, player));
        return hit instanceof BlockHitResult blockHit
                && player.level().getBlockState(blockHit.getBlockPos()).getBlock() instanceof AltarBlock;
    }

    // --- buy: sneak-punch the altar ---

    @SubscribeEvent
    static void onLeftClickBlock(PlayerInteractEvent.LeftClickBlock event) {
        Player player = event.getEntity();
        Level level = event.getLevel();
        if (!player.isShiftKeyDown() || !(level.getBlockState(event.getPos()).getBlock() instanceof AltarBlock)) {
            return;
        }
        // Swallow the punch on both sides so the altar is never attacked/mined by a buy click.
        event.setCanceled(true);
        if (!(player instanceof ServerPlayer serverPlayer)
                || event.getAction() != PlayerInteractEvent.LeftClickBlock.Action.START) {
            return;
        }
        Integer index = BROWSE_INDEX.get(serverPlayer.getUUID());
        if (index == null) {
            // Not browsing yet — show the first offer instead of blind-buying it.
            BROWSE_INDEX.put(serverPlayer.getUUID(), 0);
            showOffer(serverPlayer, OFFERS.get(0));
            return;
        }
        buy(serverPlayer, OFFERS.get(index), event.getPos());
    }

    private static void buy(ServerPlayer player, Offer offer, BlockPos altarPos) {
        MinecraftServer server = player.server;
        Component name = Component.translatable(offer.nameKey());
        if (offer.pooled()) {
            EclipseWorldState state = EclipseWorldState.get(server);
            if (state.getShardPool() < offer.cost()) {
                player.displayClientMessage(Component.translatable("shop.eclipse.pool_need",
                        offer.cost(), state.getShardPool()), true);
                player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
                return;
            }
            state.addShardPool(-offer.cost());
            SupplyBeacon.drop(server);
            player.displayClientMessage(Component.translatable("shop.eclipse.bought_pooled", name), true);
            // Global cue, no coordinates: everyone hears the beacon charge (spec: coords stay secret).
            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                online.playNotifySound(SoundEvents.BEACON_ACTIVATE, SoundSource.MASTER, 0.7F, 1.0F);
            }
            EclipseMod.LOGGER.info("{} spent {} pooled shards on a supply beacon (pool now {})",
                    player.getScoreboardName(), offer.cost(), state.getShardPool());
            return;
        }
        int balance = getShards(player);
        if (balance < offer.cost()) {
            player.displayClientMessage(Component.translatable("shop.eclipse.need", offer.cost(), balance), true);
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        addShards(player, -offer.cost());
        ItemStack reward = new ItemStack(offer.item().get());
        if (!player.getInventory().add(reward)) {
            player.drop(reward, false);
        }
        player.displayClientMessage(Component.translatable("shop.eclipse.bought", name, getShards(player)), true);
        player.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.BLOCKS, 0.5F, 1.6F);
        EclipseMod.LOGGER.info("{} bought {} for {} shards at the altar {} ({} left)",
                player.getScoreboardName(), offer.nameKey(), offer.cost(), altarPos.toShortString(), getShards(player));
    }

    // --- umbral pick: +50% break speed under open night sky ---

    @SubscribeEvent
    static void onBreakSpeed(PlayerEvent.BreakSpeed event) {
        Player player = event.getEntity();
        if (!player.getMainHandItem().is(EclipseItems.UMBRAL_PICK.get())) {
            return;
        }
        Level level = player.level();
        BlockPos pos = event.getPosition().orElse(player.blockPosition());
        if (level.isNight() && level.canSeeSky(pos.above())) {
            event.setNewSpeed(event.getOriginalSpeed() * UMBRAL_PICK_NIGHT_SKY_BONUS);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        BROWSE_INDEX.clear();
    }
}
