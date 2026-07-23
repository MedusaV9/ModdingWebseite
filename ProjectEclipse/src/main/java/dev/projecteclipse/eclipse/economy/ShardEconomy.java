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
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
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
 *       Personal rewards deduct the personal balance; the two POOLED offers deduct the
 *       team pool: the Supply Beacon fires {@link SupplyBeacon#drop} at secret
 *       coordinates, and Eclipse's Favor grants every online player Regeneration I +
 *       Saturation I until the next dawn ({@link #activateEclipsesFavor}).</li>
 * </ol>
 *
 * <p>Also home of the umbral-pick perk: +50% break speed under open night sky
 * ({@link #onBreakSpeed}). The umbral-blade lifesteal lives in the kill path
 * ({@code lives.LifecycleEvents}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ShardEconomy {
    /** One shop entry; {@code item} is {@code null} for the pooled team offers (not items). */
    public record Offer(String nameKey, Supplier<? extends Item> item, int cost, boolean pooled) {}

    public static final int SUPPLY_BEACON_COST = 24;
    /** Pooled cost of the Eclipse's Favor team buff (regen + saturation until the next dawn). */
    public static final int ECLIPSES_FAVOR_COST = 16;

    /** The two pooled offers are identity-matched in {@link #buy} to pick their branch. */
    private static final Offer ECLIPSES_FAVOR_OFFER =
            new Offer("item.eclipse.eclipses_favor", null, ECLIPSES_FAVOR_COST, true);
    private static final Offer SUPPLY_BEACON_OFFER =
            new Offer("item.eclipse.supply_beacon", null, SUPPLY_BEACON_COST, true);

    /** Cheapest first; the pooled team rewards close the loop. */
    private static final List<Offer> OFFERS = List.of(
            new Offer("item.eclipse.grave_dowser", EclipseItems.GRAVE_DOWSER, 4, false),
            new Offer("item.eclipse.compass_of_watcher", EclipseItems.COMPASS_OF_WATCHER, 8, false),
            new Offer("item.eclipse.vitae_shard", EclipseItems.VITAE_SHARD, 12, false),
            new Offer("item.eclipse.umbral_pick", EclipseItems.UMBRAL_PICK, 12, false),
            new Offer("item.eclipse.umbral_blade", EclipseItems.UMBRAL_BLADE, 16, false),
            ECLIPSES_FAVOR_OFFER,
            SUPPLY_BEACON_OFFER);

    private static final int CYCLE_INTERVAL_TICKS = 20;
    private static final double BROWSE_REACH_BLOCKS = 6.0D;
    private static final float UMBRAL_PICK_NIGHT_SKY_BONUS = 1.5F;

    /** Eclipse's Favor effect re-application period (a multiple of {@value #CYCLE_INTERVAL_TICKS}). */
    private static final int FAVOR_REFRESH_TICKS = 60;
    /** Per-refresh effect duration — outlives two refresh gaps, lapses ~7 s after dawn cuts the loop. */
    private static final int FAVOR_EFFECT_TICKS = 140;
    /** One in-game day; overworld dawn sits at every multiple of this in {@code dayTime}. */
    private static final long DAY_LENGTH_TICKS = 24000L;

    /** Transient per-player browse cursor; present only while sneaking at the altar. */
    private static final Map<UUID, Integer> BROWSE_INDEX = new HashMap<>();

    /**
     * Absolute overworld {@code dayTime} at which the running Eclipse's Favor expires
     * (the next dawn), or {@code 0} while inactive. Transient by design — mirrors
     * {@link SupplyBeacon}'s marker list: a restart simply drops the remaining buff.
     */
    private static long favorExpiryDayTime = 0L;
    /**
     * Absolute overworld {@code gameTime} ceiling of the running favor (activation +
     * {@value #DAY_LENGTH_TICKS}t): with {@code doDaylightCycle} off, {@code dayTime}
     * never reaches the dawn anchor — the favor expires on whichever comes first.
     */
    private static long favorExpiryGameTime = 0L;

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
        tickFavor(server);
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
            // One activation per purchase: refuse (free of charge) while the favor still runs.
            if (offer == ECLIPSES_FAVOR_OFFER && isFavorActive(server)) {
                player.displayClientMessage(Component.translatable("shop.eclipse.favor_already"), true);
                player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
                return;
            }
            if (state.getShardPool() < offer.cost()) {
                player.displayClientMessage(Component.translatable("shop.eclipse.pool_need",
                        offer.cost(), state.getShardPool()), true);
                player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
                return;
            }
            state.addShardPool(-offer.cost());
            if (offer == ECLIPSES_FAVOR_OFFER) {
                activateEclipsesFavor(server, player);
                return;
            }
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

    // --- Eclipse's Favor: pooled team buff until the next dawn ---

    /** Whether an Eclipse's Favor activation is still running (neither dawn nor the ceiling reached). */
    private static boolean isFavorActive(MinecraftServer server) {
        return favorExpiryDayTime != 0L
                && server.overworld().getDayTime() < favorExpiryDayTime
                && server.overworld().getGameTime() < favorExpiryGameTime;
    }

    /**
     * Activates one Eclipse's Favor purchase: everyone online gets the buff line + sound
     * and the first effect application; {@link #tickFavor} keeps re-applying (also to
     * late joiners) until the overworld crosses the next dawn. Expiry is anchored to
     * {@code dayTime} rather than game time so sleeping through the night ends it too —
     * plus a {@code gameTime} ceiling of one full day, so a {@code doDaylightCycle=off}
     * world (frozen dayTime) still expires the favor.
     */
    private static void activateEclipsesFavor(MinecraftServer server, ServerPlayer buyer) {
        long dayTime = server.overworld().getDayTime();
        favorExpiryDayTime = (dayTime / DAY_LENGTH_TICKS + 1L) * DAY_LENGTH_TICKS;
        favorExpiryGameTime = server.overworld().getGameTime() + DAY_LENGTH_TICKS;
        refreshFavorEffects(server);
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.displayClientMessage(Component.translatable("shop.eclipse.favor_granted"), true);
            online.playNotifySound(SoundEvents.BEACON_POWER_SELECT, SoundSource.MASTER, 0.7F, 1.0F);
        }
        EclipseMod.LOGGER.info("{} spent {} pooled shards on Eclipse's Favor (pool now {}; runs until dayTime {})",
                buyer.getScoreboardName(), ECLIPSES_FAVOR_COST,
                EclipseWorldState.get(server).getShardPool(), favorExpiryDayTime);
    }

    /** Favor keeper (from {@link #onServerTick}): re-applies the effects until dawn/ceiling cuts the loop. */
    private static void tickFavor(MinecraftServer server) {
        if (favorExpiryDayTime == 0L) {
            return;
        }
        if (server.overworld().getDayTime() >= favorExpiryDayTime
                || server.overworld().getGameTime() >= favorExpiryGameTime) {
            // Dawn or the one-day gameTime ceiling (doDaylightCycle off): stop refreshing;
            // the short-lived effects lapse on their own within seconds.
            favorExpiryDayTime = 0L;
            favorExpiryGameTime = 0L;
            EclipseMod.LOGGER.info("Eclipse's Favor expired (dawn or one-day ceiling)");
            return;
        }
        if (server.getTickCount() % FAVOR_REFRESH_TICKS == 0) {
            refreshFavorEffects(server);
        }
    }

    /** One favor application: ambient Regeneration I + Saturation I for every online player. */
    private static void refreshFavorEffects(MinecraftServer server) {
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.addEffect(new MobEffectInstance(MobEffects.REGENERATION, FAVOR_EFFECT_TICKS, 0, true, true));
            online.addEffect(new MobEffectInstance(MobEffects.SATURATION, FAVOR_EFFECT_TICKS, 0, true, true));
        }
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
        favorExpiryDayTime = 0L;
        favorExpiryGameTime = 0L;
    }
}
