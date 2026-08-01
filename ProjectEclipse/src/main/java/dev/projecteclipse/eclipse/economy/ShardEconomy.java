package dev.projecteclipse.eclipse.economy;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.BuffMath;
import dev.projecteclipse.eclipse.buffs.BuffState;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.hud.SidebarSyncService;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.economy.ShardPayloads;
import dev.projecteclipse.eclipse.network.rewards.RewardPayloads;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.ritual.AltarAdminState;
import dev.projecteclipse.eclipse.ritual.AltarBlock;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
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
import net.neoforged.neoforge.event.entity.player.ItemEntityPickupEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The altar shard shop (spec §4). UX flow, all action bar + sounds, never chat:
 * <ol>
 *   <li><b>Bank:</b> sneak-right-click the altar with umbral shards ({@link
 *       UmbralShardItem#useOn}) — the whole stack is deposited into the TEAM POOL only
 *       ({@link EclipseWorldState#getShardPool()}). FINAL-DOPA-SOL §3: crediting the
 *       personal balance too let one physical shard buy one unit of personal value AND
 *       one unit of pooled value (double-spend). Personal balances are now funded only
 *       by direct rewards (goals/quests/contracts/admin); the per-player contribution
 *       stays visible through the {@code shards_banked} analytics counter that feeds
 *       the Shard Banker award.</li>
 *   <li><b>Browse:</b> sneak while looking at the altar — the offer list cycles on the
 *       action bar every {@value #CYCLE_INTERVAL_TICKS} ticks.</li>
 *   <li><b>Buy:</b> sneak-punch (left-click) the altar — buys the offer currently shown.
 *       Personal rewards deduct the personal balance; the POOLED offers deduct the
 *       team pool: the Supply Beacon fires {@link SupplyBeacon#drop} at secret
 *       coordinates, Eclipse's Favor grants every online player Regeneration I +
 *       Saturation I until the next dawn ({@link #activateEclipsesFavor}), and the
 *       Double-XP surge starts the server-wide {@value #DOUBLE_XP_BUFF_ID} timed buff
 *       for {@value #DOUBLE_XP_MINUTES} real minutes.</li>
 * </ol>
 *
 * <p>ALTARUI: offers carry stable ids plus {@code minDay}/{@code maxDay} day gates
 * (task 6), operators can pull individual offers via {@code /dev altar offer disable}
 * (task 9 — {@code ritual.AltarAdminState}), and the altar panel UI buys through
 * {@link #buyById} (task 1).</p>
 *
 * <p>Also home of the umbral-pick perk: +50% break speed under open night sky
 * ({@link #onBreakSpeed}). The umbral-blade lifesteal lives in the kill path
 * ({@code lives.LifecycleEvents}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ShardEconomy {
    /**
     * One shop entry; {@code item} is {@code null} for the non-item offers (the pooled
     * team rewards and the Double-XP buff). ALTARUI: {@code id} is the stable handle the
     * {@code /dev altar offer} tree and the altar-panel payload key on; {@code minDay}/
     * {@code maxDay} gate availability by event day ({@code maxDay <= 0} = no ceiling).
     */
    public record Offer(String id, String nameKey, Supplier<? extends Item> item, int cost, boolean pooled,
            int minDay, int maxDay) {
        /** Day-gate check ({@code maxDay <= 0} = open-ended). */
        public boolean availableOnDay(int day) {
            return day >= minDay && (maxDay <= 0 || day <= maxDay);
        }
    }

    /**
     * ALTARFIX2 #4: the registry id of the ONE item that is the shard currency, resolved
     * from the very {@link EclipseItems#UMBRAL_SHARD} holder that {@link #deposit} banks
     * and {@link #deliverShardItems} pays out. The altar panel ships this on every
     * {@code ShopEntry} so the price row can render that item's icon + real display name:
     * the German UI calls three different items "…splitter" (Umbrasplitter, Vitae-Splitter,
     * Glitch-Splitter), so a bare "20 Splitter" was genuinely ambiguous.
     *
     * <p>Which PURSE the number is drawn from still depends on {@link Offer#pooled()}:
     * pooled offers spend {@link EclipseWorldState#getShardPool()} (fed by banking shard
     * ITEMS), personal offers spend the earned {@link #getShards} balance. Both purses
     * are denominated in this same item — the panel labels which one per row.</p>
     */
    public static String currencyItemId() {
        return BuiltInRegistries.ITEM.getKey(EclipseItems.UMBRAL_SHARD.get()).toString();
    }

    public static final int SUPPLY_BEACON_COST = 24;
    /** Pooled cost of the Eclipse's Favor team buff (regen + saturation until the next dawn). */
    public static final int ECLIPSES_FAVOR_COST = 16;
    /** Pooled cost of the Double-XP surge ({@value #DOUBLE_XP_MINUTES} real minutes, team-wide). */
    public static final int DOUBLE_XP_COST = 20;
    /** Real-minute duration of one Double-XP purchase. */
    public static final int DOUBLE_XP_MINUTES = 30;
    /** {@code buffs.json} definition id started by the Double-XP offer ({@code skill_xp} ×2). */
    public static final String DOUBLE_XP_BUFF_ID = "double_skill_xp";

    /** The non-item offers are identity-matched in {@link #buy} to pick their branch. */
    private static final Offer ECLIPSES_FAVOR_OFFER =
            new Offer("eclipses_favor", "item.eclipse.eclipses_favor", null, ECLIPSES_FAVOR_COST, true, 2, 0);
    private static final Offer SUPPLY_BEACON_OFFER =
            new Offer("supply_beacon", "item.eclipse.supply_beacon", null, SUPPLY_BEACON_COST, true, 5, 0);
    /**
     * ALTARUI task 7: 30 real minutes of doubled skill XP. Rides the existing server-wide
     * timed-buff engine ({@code buffs.TimedBuffService} — {@code eclipse_buffs.dat}
     * persistence, relog-safe countdown, TAB-sidebar timer), so the purchase benefits the
     * whole team and is paid from the TEAM pool like the other team-wide effects.
     */
    private static final Offer DOUBLE_XP_OFFER =
            new Offer("double_xp", "shop.eclipse.offer.double_xp", null, DOUBLE_XP_COST, true, 4, 0);

    /**
     * Cheapest first; the pooled team rewards close the loop. ALTARUI task 6 day gates:
     * the dowser is the day-1 starter, the team buffs follow on days 2/4/5, the tools
     * unlock alongside their use cases (day 3 compass for the watcher hunts, day 4 pick,
     * day 6 blade for the night events), and the vitae shard waits until day 8 so the
     * rebirth ladder (not a flat 20-shard heart) carries the early-death economy.
     */
    private static final List<Offer> OFFERS = List.of(
            new Offer("grave_dowser", "item.eclipse.grave_dowser", EclipseItems.GRAVE_DOWSER, 4, false, 1, 0),
            new Offer("compass_of_watcher", "item.eclipse.compass_of_watcher",
                    EclipseItems.COMPASS_OF_WATCHER, 8, false, 3, 0),
            // FIX-ECON: 12 -> 20 so rebirth (8*1.3^n) is always the budget heart and the
            // flat-price vitae never dominates the ladder.
            new Offer("vitae_shard", "item.eclipse.vitae_shard", EclipseItems.VITAE_SHARD, 20, false, 8, 0),
            new Offer("umbral_pick", "item.eclipse.umbral_pick", EclipseItems.UMBRAL_PICK, 12, false, 4, 0),
            new Offer("umbral_blade", "item.eclipse.umbral_blade", EclipseItems.UMBRAL_BLADE, 16, false, 6, 0),
            ECLIPSES_FAVOR_OFFER,
            DOUBLE_XP_OFFER,
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

    // --- WAVE5 (F-105 C) — C7 shard-bank arpeggio (IDEA-12 #8) --------------------------
    // The flat deposit chime becomes a rising ladder: bigger deposits climb further
    // (1 + amount/8 notes, capped at {@value #ARPEGGIO_MAX_NOTES}, one note every
    // {@value #ARPEGGIO_STEP_TICKS} t, pitch 1.2 → 1.8). A 1–7 shard deposit keeps
    // exactly one 1.2-pitch note — behaviourally the old receipt chime.

    /** Ticks between two arpeggio notes. */
    private static final int ARPEGGIO_STEP_TICKS = 3;
    /** Note-count cap ({@code >= 41} shards saturate the ladder). */
    private static final int ARPEGGIO_MAX_NOTES = 6;
    /** Pitch ladder endpoints. */
    private static final float ARPEGGIO_PITCH_LOW = 1.2F;
    private static final float ARPEGGIO_PITCH_HIGH = 1.8F;

    /** One running per-player arpeggio (mutable — driven from {@link #onServerTick}). */
    private static final class Arpeggio {
        final int totalNotes;
        int notesLeft;
        int countdown;

        Arpeggio(int totalNotes) {
            this.totalNotes = totalNotes;
            this.notesLeft = totalNotes;
            this.countdown = 1; // first note on the next server tick (same-second receipt)
        }
    }

    /** Pending deposit arpeggios by player id; cleared in {@code onServerStopped}. */
    private static final Map<UUID, Arpeggio> ARPEGGIO = new HashMap<>();

    /**
     * B14 §4 playtest diagnostic: while on, every personal-balance mutation, team-pool bank
     * and physical shard delivery/pickup is logged with its calling source (toggled by
     * {@code /dev shards trace on|off}). Transient by design — resets on server stop.
     */
    private static volatile boolean traceEnabled = false;

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

    // --- offer table + availability (ALTARUI tasks 6/9) ---

    /** The full configured offer table, including day-locked and dev-disabled entries. */
    public static List<Offer> allOffers() {
        return OFFERS;
    }

    /** The offer with the given stable id, or {@code null}. */
    public static Offer offerById(String offerId) {
        for (Offer offer : OFFERS) {
            if (offer.id().equals(offerId)) {
                return offer;
            }
        }
        return null;
    }

    /** Whether the offer's day window contains the current event day (task 6). */
    public static boolean isOfferUnlocked(MinecraftServer server, Offer offer) {
        return offer.availableOnDay(EclipseWorldState.get(server).getDay());
    }

    /** Whether an operator has pulled the offer from sale ({@code /dev altar offer disable}). */
    public static boolean isOfferEnabled(MinecraftServer server, Offer offer) {
        return !AltarAdminState.get(server).isOfferDisabled(offer.id());
    }

    /**
     * The offers buyable RIGHT NOW: day window open and not dev-disabled. Feeds the
     * action-bar browse cycle and the buy path; the altar panel additionally shows
     * day-locked entries greyed out (but never dev-disabled ones — see
     * {@code ritual.AltarAdminState}).
     */
    public static List<Offer> purchasableOffers(MinecraftServer server) {
        int day = EclipseWorldState.get(server).getDay();
        AltarAdminState admin = AltarAdminState.get(server);
        List<Offer> available = new ArrayList<>();
        for (Offer offer : OFFERS) {
            if (offer.availableOnDay(day) && !admin.isOfferDisabled(offer.id())) {
                available.add(offer);
            }
        }
        return available;
    }

    /**
     * Remaining real seconds of the running Double-XP surge, or {@code 0} while inactive
     * (altar-panel countdown). Reads the persisted buff list directly — the epoch clock
     * matches {@code TimedBuffService}'s default {@code System.currentTimeMillis} source.
     */
    public static int doubleXpRemainingSeconds(MinecraftServer server) {
        long now = System.currentTimeMillis();
        for (BuffMath.ActiveBuff buff : BuffState.get(server).active()) {
            if (DOUBLE_XP_BUFF_ID.equals(buff.id()) && buff.endsAtEpochMillis() > now) {
                return (int) ((buff.endsAtEpochMillis() - now) / 1000L);
            }
        }
        return 0;
    }

    /**
     * ALTARUI panel purchase entry: buys the offer with the given id if it exists and is
     * currently purchasable. Returns {@code false} (with action-bar feedback) for unknown,
     * day-locked or dev-disabled ids — the panel greys those out, but a stale click after
     * a day rollover or an operator toggle must still be refused server-side.
     */
    public static boolean buyById(ServerPlayer player, String offerId, BlockPos altarPos) {
        Offer offer = offerById(offerId);
        if (offer == null || !isOfferEnabled(player.server, offer)) {
            player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.unavailable"), true);
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return false;
        }
        if (!isOfferUnlocked(player.server, offer)) {
            player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.locked_day",
                    Component.translatable(offer.nameKey()), offer.minDay()), true);
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return false;
        }
        buy(player, offer, altarPos);
        return true;
    }

    // --- personal balance ---

    /** The player's banked personal shard balance ({@code eclipse:shards} attachment). */
    public static int getShards(ServerPlayer player) {
        return player.getData(EclipseAttachments.SHARDS);
    }

    /**
     * Adds {@code delta} (may be negative) to the personal balance, clamped to {@code >= 0};
     * returns the new value. Positive gains announce a client "+N Umbrasplitter" toast
     * (D14) — call sites whose gains already ride the {@code RewardMaterializeOverlay}
     * ceremony (quest/award grants) pass {@code announce=false} via the overload.
     */
    public static int addShards(ServerPlayer player, int delta) {
        return addShards(player, delta, true);
    }

    /** {@link #addShards(ServerPlayer, int)} with an explicit gain-toast switch (D14 choke point). */
    public static int addShards(ServerPlayer player, int delta, boolean announce) {
        int value = setShards(player, getShards(player) + delta);
        if (announce && delta > 0) {
            ShardPayloads.sendShardGain(player, delta, value);
        }
        return value;
    }

    public static int setShards(ServerPlayer player, int value) {
        int previous = getShards(player);
        int clamped = Math.max(0, value);
        player.setData(EclipseAttachments.SHARDS, clamped);
        // B14 §3: the balance must move on the HUD in the same second, not on the next
        // periodic push — the debounced dirty hook coalesces bursts into one payload.
        SidebarSyncService.markDirty(player);
        if (clamped != previous) {
            trace(player, "personal balance %+d -> %d", clamped - previous, clamped);
        }
        return clamped;
    }

    // --- physical shard delivery + pickup feedback (B14 §1/§2) ---

    /**
     * B14 §1 reliable delivery: puts {@code count} physical umbral shards straight into the
     * player's inventory (overflow drops at their feet — never at the kill site, where boss
     * arenas burn/despawn items) and shows the receipt on the action bar. {@code overlay}
     * additionally plays the {@code RewardMaterializeOverlay} ceremony (boss payouts); quiet
     * procs (skill-perk bonus shard) keep their own proc toast and pass {@code false}.
     *
     * <p>Deliberately does NOT touch the personal balance: one physical shard stays one
     * unit of TEAM-pool value, spendable once at the altar (FINAL-DOPA-SOL §3).</p>
     */
    public static void deliverShardItems(ServerPlayer player, int count, boolean overlay) {
        if (count <= 0) {
            return;
        }
        ItemStack stack = new ItemStack(EclipseItems.UMBRAL_SHARD.get(), count);
        if (!player.getInventory().add(stack)) {
            player.drop(stack, false);
        }
        player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.shards_received", count), true);
        if (overlay) {
            RewardPayloads.sendRewardGrant(player,
                    List.of(new RewardPayloads.ItemEntry("eclipse:umbral_shard", count)),
                    0, RewardPayloads.SOURCE_AWARD, false);
        }
        trace(player, "delivered %d physical shard(s) to inventory (overlay=%s)", count, overlay);
    }

    /**
     * B14 §2 visible pickup: an umbral shard picked up off the ground cues "erhalten — am
     * Altar einzahlen" on the action bar, so holding ≠ banked is understood. Direct
     * inventory deliveries get the same cue inside {@link #deliverShardItems}.
     */
    @SubscribeEvent
    static void onItemPickup(ItemEntityPickupEvent.Post event) {
        if (!(event.getPlayer() instanceof ServerPlayer player)
                || !event.getOriginalStack().is(EclipseItems.UMBRAL_SHARD.get())) {
            return;
        }
        int pickedUp = event.getOriginalStack().getCount() - event.getCurrentStack().getCount();
        if (pickedUp <= 0) {
            return;
        }
        player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.shards_received", pickedUp), true);
        trace(player, "picked up %d physical shard(s) off the ground", pickedUp);
    }

    // --- /dev shards trace (B14 §4) ---

    public static void setTraceEnabled(boolean enabled) {
        traceEnabled = enabled;
        EclipseMod.LOGGER.info("[shards] trace {}", enabled ? "ON" : "OFF");
    }

    public static boolean isTraceEnabled() {
        return traceEnabled;
    }

    /** One trace line with the calling source frame (first frame outside this class). */
    private static void trace(ServerPlayer player, String format, Object... args) {
        if (!traceEnabled) {
            return;
        }
        String caller = StackWalker.getInstance().walk(frames -> frames
                .map(frame -> frame.getClassName() + "." + frame.getMethodName())
                .filter(name -> !name.startsWith(ShardEconomy.class.getName())
                        && !name.startsWith("java."))
                .findFirst().orElse("?"));
        EclipseMod.LOGGER.info("[shards] {} — {} (source: {})",
                player.getScoreboardName(), String.format(java.util.Locale.ROOT, format, args), caller);
    }

    // --- bank (called by UmbralShardItem#useOn) ---

    /**
     * Deposits the WHOLE held shard stack into the TEAM POOL, chime + action-bar receipt.
     * Pool-only on purpose (FINAL-DOPA-SOL §3 double-spend fix): the personal balance is
     * NOT credited here — one physical shard is one unit of value, spendable once.
     */
    public static void deposit(ServerPlayer player, ItemStack shardStack) {
        int amount = shardStack.getCount();
        if (amount <= 0) {
            return;
        }
        shardStack.shrink(amount);
        int pool = EclipseWorldState.get(player.server).addShardPool(amount);
        player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.deposited_pool", amount, pool), true);
        // WAVE5 (F-105 C) — C7: the fixed 1.2-pitch receipt chime becomes a rising
        // arpeggio scaled by the deposit (queue drained in onServerTick, 1 note / 3 t).
        // The first note plays at pitch 1.2 on the very next tick, so small deposits
        // sound exactly like the old single chime.
        int notes = Math.min(1 + amount / 8, ARPEGGIO_MAX_NOTES);
        ARPEGGIO.put(player.getUUID(), new Arpeggio(notes));
        EclipseMod.LOGGER.debug("[w5c-arpeggio] player={} amount={} notes={}",
                player.getScoreboardName(), amount, notes);
        // B14 §3: resync the depositor's sidebar in the same second as the receipt line.
        SidebarSyncService.markDirty(player);
        trace(player, "banked %d physical shard(s) into the TEAM pool (pool %d)", amount, pool);
        EclipseMod.LOGGER.info("{} banked {} umbral shard(s) into the team pool (pool {})",
                player.getScoreboardName(), amount, pool);
    }

    // --- browse: action-bar offer cycling ---

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        // WAVE5 (F-105 C) — C7: the arpeggio needs the per-tick lane (3 t cadence) and
        // therefore runs BEFORE the 20 t browse/favor gate below. Idle = one isEmpty().
        if (!ARPEGGIO.isEmpty()) {
            tickArpeggio(server);
        }
        if (server.getTickCount() % CYCLE_INTERVAL_TICKS != 0) {
            return;
        }
        tickFavor(server);
        // ALTARUI task 6/9: the cycle only ever shows offers buyable RIGHT NOW — day-locked
        // entries appear greyed in the altar panel instead, dev-disabled ones nowhere.
        List<Offer> available = purchasableOffers(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isShiftKeyDown() && isLookingAtAltar(player)) {
                if (available.isEmpty()) {
                    player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.no_offers"), true);
                    continue;
                }
                int index = BROWSE_INDEX.merge(player.getUUID(), 0,
                        (previous, ignored) -> (previous + 1) % available.size());
                showOffer(player, available.get(index % available.size()));
            } else {
                BROWSE_INDEX.remove(player.getUUID());
            }
        }
    }

    /**
     * WAVE5 (F-105 C) — C7: plays due arpeggio notes. Pitch climbs linearly from
     * {@value #ARPEGGIO_PITCH_LOW} to {@value #ARPEGGIO_PITCH_HIGH} across the queued
     * notes (a single-note queue stays at 1.2 — the legacy receipt). Offline depositors
     * simply drop their queue.
     */
    private static void tickArpeggio(MinecraftServer server) {
        var iterator = ARPEGGIO.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<UUID, Arpeggio> entry = iterator.next();
            Arpeggio arpeggio = entry.getValue();
            if (--arpeggio.countdown > 0) {
                continue;
            }
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            if (player == null) {
                iterator.remove();
                continue;
            }
            int noteIndex = arpeggio.totalNotes - arpeggio.notesLeft;
            float pitch = arpeggio.totalNotes <= 1 ? ARPEGGIO_PITCH_LOW
                    : ARPEGGIO_PITCH_LOW + (ARPEGGIO_PITCH_HIGH - ARPEGGIO_PITCH_LOW)
                            * (noteIndex / (float) (arpeggio.totalNotes - 1));
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 1.0F, pitch);
            arpeggio.notesLeft--;
            arpeggio.countdown = ARPEGGIO_STEP_TICKS;
            if (arpeggio.notesLeft <= 0) {
                iterator.remove();
            }
        }
    }

    private static void showOffer(ServerPlayer player, Offer offer) {
        Component name = Component.translatable(offer.nameKey());
        Component line = offer.pooled()
                ? ServerLang.tr(player, "shop.eclipse.offer_pooled", name, offer.cost(),
                        EclipseWorldState.get(player.server).getShardPool())
                : ServerLang.tr(player, "shop.eclipse.offer", name, offer.cost(), getShards(player));
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
        List<Offer> available = purchasableOffers(serverPlayer.server);
        if (available.isEmpty()) {
            serverPlayer.displayClientMessage(ServerLang.tr(serverPlayer, "shop.eclipse.no_offers"), true);
            return;
        }
        Integer index = BROWSE_INDEX.get(serverPlayer.getUUID());
        if (index == null) {
            // Not browsing yet — show the first offer instead of blind-buying it.
            BROWSE_INDEX.put(serverPlayer.getUUID(), 0);
            showOffer(serverPlayer, available.get(0));
            return;
        }
        // Modulo re-clamp: a day rollover or offer toggle between the last cycle tick and
        // this click may have shrunk the list — never buy past its end.
        buy(serverPlayer, available.get(index % available.size()), event.getPos());
    }

    private static void buy(ServerPlayer player, Offer offer, BlockPos altarPos) {
        MinecraftServer server = player.server;
        Component name = Component.translatable(offer.nameKey());
        if (offer.pooled()) {
            EclipseWorldState state = EclipseWorldState.get(server);
            // One activation per purchase: refuse (free of charge) while the favor still runs.
            if (offer == ECLIPSES_FAVOR_OFFER && isFavorActive(server)) {
                player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.favor_already"), true);
                player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
                return;
            }
            if (state.getShardPool() < offer.cost()) {
                player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.pool_need",
                        offer.cost(), state.getShardPool()), true);
                player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
                return;
            }
            if (offer == DOUBLE_XP_OFFER) {
                // Start BEFORE deducting: the buff engine may refuse (maxActive cap while
                // three OTHER buffs run). EXTEND stacking means a re-buy adds 30 minutes.
                // Persistence + relog-safe countdown + the TAB-sidebar timer all live in
                // TimedBuffService/BuffState — nothing extra to store here.
                if (!TimedBuffApi.Holder.get().start(server, DOUBLE_XP_BUFF_ID, DOUBLE_XP_MINUTES)) {
                    player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.buff_refused"), true);
                    player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
                    return;
                }
                state.addShardPool(-offer.cost());
                player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.bought_pooled", name), true);
                EclipseMod.LOGGER.info("{} spent {} pooled shards on Double XP ({} min; pool now {})",
                        player.getScoreboardName(), offer.cost(), DOUBLE_XP_MINUTES, state.getShardPool());
                return;
            }
            state.addShardPool(-offer.cost());
            if (offer == ECLIPSES_FAVOR_OFFER) {
                activateEclipsesFavor(server, player);
                return;
            }
            SupplyBeacon.drop(server);
            player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.bought_pooled", name), true);
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
            player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.need", offer.cost(), balance), true);
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return;
        }
        addShards(player, -offer.cost());
        ItemStack reward = new ItemStack(offer.item().get());
        if (!player.getInventory().add(reward)) {
            player.drop(reward, false);
        }
        player.displayClientMessage(ServerLang.tr(player, "shop.eclipse.bought", name, getShards(player)), true);
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
            online.displayClientMessage(ServerLang.tr(online, "shop.eclipse.favor_granted"), true);
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
        ARPEGGIO.clear(); // WAVE5 (F-105 C) — C7
        favorExpiryDayTime = 0L;
        favorExpiryGameTime = 0L;
        traceEnabled = false;
    }
}
