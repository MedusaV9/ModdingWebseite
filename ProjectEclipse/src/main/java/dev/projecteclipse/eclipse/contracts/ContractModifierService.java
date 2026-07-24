package dev.projecteclipse.eclipse.contracts;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayApi;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Per-player contract modifiers (IDEA-20 #5/#6): the advantage/disadvantage ledger behind
 * SUCCESS/EXPIRY/WRONG_KILL. Nothing here EVER touches {@code EclipseAttachments.LIVES},
 * {@code BanService} or drops a player below one effective heart — "massive but never
 * run-ending" is enforced structurally.
 *
 * <p><b>Two expiry scopes (D3):</b> ADVANTAGES (hunter/survivor buffs) stay day-scoped and
 * clear at the next day rollover, as before. DEBUFFS (Blutschuld, the target's scar,
 * negative temp hearts, the Vergeltung grudge) additionally carry
 * {@link Entry#expiresAtEpochMillis} — the CONTRACT WINDOW end — and are purged by a
 * periodic epoch sweep ({@value #SWEEP_INTERVAL_TICKS} ticks) long before the ~24 h real
 * day ends. {@code 0} = day-scoped only (also how pre-D3 saves load, NBT-compatible).
 * Whichever scope expires first wins: epoch rows are still dropped at rollover.
 * The sweep is pause-aware: while {@code RealtimeDayApi.isPaused} the stored epochs shift
 * forward with the frozen wall clock, via the same persisted-anchor pattern as
 * {@code ContractState.shiftDeadlines} (FFIX-B).</p>
 *
 * <p><b>Damage modifiers are event-scaled, not attributes</b> (the IDEA-20 #5 stance): a
 * {@link LivingIncomingDamageEvent} listener multiplies OUTGOING player damage, so nothing
 * is synced to any client and the Vergeltung grudge ("+35% only against your murderer")
 * stays invisible until it cuts. Temp hearts use one transient MAX_HEALTH modifier
 * ({@code eclipse:contract_hearts}) rebuilt on login/respawn/clone — never serialized into
 * player NBT, mirroring {@code hearts.HeartsService}. Skills use the existing persisted
 * {@code SkillsApi.setSecretMultiplier} and are restored when the entry expires.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ContractModifierService {

    /** Modifier kinds persisted in {@link ModifierState}. */
    public enum Kind {
        /** Outgoing damage multiplier (Blutschuld 0.8×, target scar 0.85×, hunter edge 1.1×). */
        DAMAGE_MUL,
        /** Outgoing damage multiplier applied ONLY against {@code other} (Vergeltung). */
        GRUDGE,
        /** Temporary bonus/malus hearts (transient MAX_HEALTH modifier, ±1). */
        TEMP_HEARTS,
        /** Secret skills XP multiplier — applied via {@code SkillsApi}, restored on expiry. */
        SKILLS_MUL,
        /** Daily-award eligibility void marker (queried by the awards integration ask). */
        AWARD_VOID;

        static Kind byName(String name) {
            for (Kind kind : values()) {
                if (kind.name().equalsIgnoreCase(name)) {
                    return kind;
                }
            }
            return DAMAGE_MUL;
        }
    }

    /**
     * One ledger row. {@code other} is only used by {@link Kind#GRUDGE}.
     * {@code expiresAtEpochMillis > 0} = window-scoped (purged by the epoch sweep as soon
     * as the wall clock passes it); {@code 0} = day-scoped only (rollover purge).
     */
    public record Entry(UUID holder, Kind kind, float value, @Nullable UUID other,
            int expiresAfterDay, long expiresAtEpochMillis) {

        /** Day-scoped convenience constructor (pre-D3 call shape). */
        public Entry(UUID holder, Kind kind, float value, @Nullable UUID other, int expiresAfterDay) {
            this(holder, kind, value, other, expiresAfterDay, 0L);
        }
    }

    private static final ResourceLocation CONTRACT_HEARTS_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "contract_hearts");
    /** Epoch-sweep cadence (5 s) — debuffs may outlive their window by at most this. */
    private static final int SWEEP_INTERVAL_TICKS = 100;
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();

    private ContractModifierService() {}

    // ================================================================== lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover(ContractModifierService::onDayRollover);
        }
        // FFIX-B boot resume: a pause that spanned the downtime shifts every stored epoch
        // by the offline span BEFORE any expiry decision (the ContractState.resumeOnBoot
        // pattern) — the wall clock must not consume a frozen debuff while nobody played.
        ModifierState state = ModifierState.get(server);
        long anchor = state.pauseAnchorEpochMillis();
        if (anchor > 0L) {
            long now = EclipseClock.epochMillis();
            EclipseMod.LOGGER.info("Contract modifier epochs shifted by {} ms of paused downtime",
                    now - anchor);
            state.shiftEpochDeadlines(now - anchor);
            state.setPauseAnchorEpochMillis(RealtimeDayApi.isPaused(server) ? now : 0L);
        }
        // Rebuild transient heart modifiers for players already present (integrated server).
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            applyTempHearts(player);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
    }

    /** POST rollover: purge expired entries, restore their skills multipliers and hearts. */
    private static void onDayRollover(MinecraftServer server, int endedDay, int newDay,
            EclipseSignals.DayRolloverPhase phase) {
        if (phase != EclipseSignals.DayRolloverPhase.POST) {
            return;
        }
        List<Entry> expired = ModifierState.get(server).removeExpired(newDay);
        if (expired.isEmpty()) {
            return;
        }
        restoreExpiredHolders(server, expired);
        EclipseMod.LOGGER.info("Contract modifiers expired at day {}: {} entr(y/ies) cleared",
                newDay, expired.size());
    }

    // ================================================================== epoch sweep (D3)

    /**
     * The 100-tick epoch sweep. While the realtime day is paused every stored epoch is
     * shifted forward by the frozen span instead (persisted anchor, FFIX-B) — a debuff
     * never burns down during a pause.
     */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % SWEEP_INTERVAL_TICKS != 0) {
            return;
        }
        ModifierState state = ModifierState.get(server);
        long now = EclipseClock.epochMillis();
        if (RealtimeDayApi.isPaused(server)) {
            long anchor = state.pauseAnchorEpochMillis();
            if (anchor > 0L) {
                state.shiftEpochDeadlines(now - anchor);
            }
            state.setPauseAnchorEpochMillis(now);
            return;
        }
        state.setPauseAnchorEpochMillis(0L);
        sweepExpired(server);
    }

    /**
     * Purges every window-scoped entry whose epoch deadline has passed and restores the
     * holders' skills multipliers / temp hearts. Also called by
     * {@code ContractService.finishWindow} so a resolving window clears already-expired
     * debuffs immediately instead of waiting for the next sweep tick.
     *
     * @return the purged rows (gametest surface)
     */
    public static List<Entry> sweepExpired(MinecraftServer server) {
        List<Entry> expired = ModifierState.get(server).removeEpochExpired(EclipseClock.epochMillis());
        if (!expired.isEmpty()) {
            restoreExpiredHolders(server, expired);
            EclipseMod.LOGGER.info("Contract modifiers window-expired: {} entr(y/ies) cleared",
                    expired.size());
        }
        return expired;
    }

    /**
     * Shared restore path for both sweeps: skills multipliers fall back to the LAST still
     * live {@link Kind#SKILLS_MUL} entry of the holder (grant order = last write wins,
     * matching {@code grantSkillsMul}'s immediate apply), else 1.0; temp hearts are
     * rebuilt from the live ledger for online holders.
     */
    private static void restoreExpiredHolders(MinecraftServer server, List<Entry> expired) {
        Set<UUID> skillsHolders = new HashSet<>();
        Set<UUID> heartHolders = new HashSet<>();
        for (Entry entry : expired) {
            if (entry.kind() == Kind.SKILLS_MUL) {
                skillsHolders.add(entry.holder());
            } else if (entry.kind() == Kind.TEMP_HEARTS) {
                heartHolders.add(entry.holder());
            }
        }
        for (UUID uuid : skillsHolders) {
            float remaining = 1.0F;
            for (Entry live : ModifierState.get(server).entries()) {
                if (live.kind() == Kind.SKILLS_MUL && live.holder().equals(uuid)) {
                    remaining = live.value();
                }
            }
            SkillsApi.setSecretMultiplier(server, uuid, remaining);
        }
        for (UUID uuid : heartHolders) {
            ServerPlayer online = server.getPlayerList().getPlayer(uuid);
            if (online != null) {
                applyTempHearts(online);
            }
        }
    }

    // ================================================================== grants

    public static void grantDamageMul(MinecraftServer server, UUID holder, float mul, int expiresAfterDay) {
        if (Math.abs(mul - 1.0F) < 1.0E-4F) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.DAMAGE_MUL, mul, null, expiresAfterDay));
    }

    /** Window-scoped damage debuff/buff: expires at {@code expiresAtEpochMillis} (D3). */
    public static void grantDamageMulUntil(MinecraftServer server, UUID holder, float mul,
            long expiresAtEpochMillis) {
        if (Math.abs(mul - 1.0F) < 1.0E-4F) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.DAMAGE_MUL, mul, null,
                currentDay(server), expiresAtEpochMillis));
    }

    public static void grantGrudge(MinecraftServer server, UUID holder, UUID versus, float mul,
            int expiresAfterDay) {
        if (Math.abs(mul - 1.0F) < 1.0E-4F) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.GRUDGE, mul, versus, expiresAfterDay));
    }

    /** Window-scoped Vergeltung grudge: expires at {@code expiresAtEpochMillis} (D3). */
    public static void grantGrudgeUntil(MinecraftServer server, UUID holder, UUID versus, float mul,
            long expiresAtEpochMillis) {
        if (Math.abs(mul - 1.0F) < 1.0E-4F) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.GRUDGE, mul, versus,
                currentDay(server), expiresAtEpochMillis));
    }

    /**
     * Grants ±hearts until rollover. Applied immediately when online and alive; a dead
     * holder (the wrong-kill victim) picks it up on respawn. Net negative hearts are
     * clamped so the effective maximum never drops below one heart.
     */
    public static void grantTempHearts(MinecraftServer server, UUID holder, int hearts,
            int expiresAfterDay) {
        if (hearts == 0) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.TEMP_HEARTS, hearts, null, expiresAfterDay));
        applyTempHeartsIfOnline(server, holder);
    }

    /** Window-scoped temp hearts (the wrong-kill victim malus): epoch expiry (D3). */
    public static void grantTempHeartsUntil(MinecraftServer server, UUID holder, int hearts,
            long expiresAtEpochMillis) {
        if (hearts == 0) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.TEMP_HEARTS, hearts, null,
                currentDay(server), expiresAtEpochMillis));
        applyTempHeartsIfOnline(server, holder);
    }

    /** Sets the secret skills multiplier now and records the reset-at-rollover entry. */
    public static void grantSkillsMul(MinecraftServer server, UUID holder, float mul,
            int expiresAfterDay) {
        if (Math.abs(mul - 1.0F) < 1.0E-4F) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.SKILLS_MUL, mul, null, expiresAfterDay));
        SkillsApi.setSecretMultiplier(server, holder, mul);
    }

    /** Window-scoped skills malus/buff: restored by the epoch sweep (D3). */
    public static void grantSkillsMulUntil(MinecraftServer server, UUID holder, float mul,
            long expiresAtEpochMillis) {
        if (Math.abs(mul - 1.0F) < 1.0E-4F) {
            return;
        }
        ModifierState.get(server).add(new Entry(holder, Kind.SKILLS_MUL, mul, null,
                currentDay(server), expiresAtEpochMillis));
        SkillsApi.setSecretMultiplier(server, holder, mul);
    }

    public static void grantAwardVoid(MinecraftServer server, UUID holder, int expiresAfterDay) {
        ModifierState.get(server).add(new Entry(holder, Kind.AWARD_VOID, 0.0F, null, expiresAfterDay));
    }

    private static int currentDay(MinecraftServer server) {
        return EclipseWorldState.get(server).getDay();
    }

    private static void applyTempHeartsIfOnline(MinecraftServer server, UUID holder) {
        ServerPlayer online = server.getPlayerList().getPlayer(holder);
        if (online != null && online.isAlive()) {
            applyTempHearts(online);
        }
    }

    // ================================================================== queries

    /**
     * Whether {@code uuid}'s daily-award eligibility is voided for {@code day} (Blutschuld).
     * Stable query surface for the awards integration one-liner (see the wiring doc) —
     * {@code AwardService} is not editable from this package.
     */
    public static boolean isAwardVoided(MinecraftServer server, UUID uuid, int day) {
        for (Entry entry : ModifierState.get(server).entries()) {
            if (entry.kind() == Kind.AWARD_VOID && entry.holder().equals(uuid)
                    && day <= entry.expiresAfterDay()) {
                return true;
            }
        }
        return false;
    }

    /**
     * Human-readable ledger rows for one player ({@code /dev contract status}).
     * Window-scoped rows print their remaining wall-clock time (D3).
     */
    public static List<String> describe(MinecraftServer server, UUID uuid) {
        List<String> lines = new ArrayList<>();
        long now = EclipseClock.epochMillis();
        for (Entry entry : ModifierState.get(server).entries()) {
            if (!entry.holder().equals(uuid)) {
                continue;
            }
            String scope = entry.expiresAtEpochMillis() > 0L
                    ? " (" + mmss(entry.expiresAtEpochMillis() - now) + " left)"
                    : " (until day " + entry.expiresAfterDay() + " ends)";
            lines.add(entry.kind() + "=" + entry.value()
                    + (entry.other() != null ? " vs " + entry.other() : "") + scope);
        }
        return lines;
    }

    private static String mmss(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        return String.format(Locale.ROOT, "%02d:%02d", totalSeconds / 60L, totalSeconds % 60L);
    }

    /** Total active entry count (status line). */
    public static int entryCount(MinecraftServer server) {
        return ModifierState.get(server).entries().size();
    }

    /** Dev/test reset: drops every entry and restores skills multipliers + hearts. */
    public static void clearAll(MinecraftServer server) {
        ModifierState state = ModifierState.get(server);
        Set<UUID> holders = new HashSet<>();
        for (Entry entry : state.entries()) {
            holders.add(entry.holder());
            if (entry.kind() == Kind.SKILLS_MUL) {
                SkillsApi.setSecretMultiplier(server, entry.holder(), 1.0F);
            }
        }
        state.clear();
        for (UUID uuid : holders) {
            ServerPlayer online = server.getPlayerList().getPlayer(uuid);
            if (online != null) {
                applyTempHearts(online);
            }
        }
    }

    // ================================================================== damage seam

    /**
     * Outgoing-damage scaling: Blutschuld/scar multipliers plus the directed Vergeltung
     * grudge. Runs for player attackers only; server-side math, nothing synced — the
     * murderer never knows the knife exists until it cuts.
     */
    @SubscribeEvent
    static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getSource().getEntity() instanceof ServerPlayer attacker)) {
            return;
        }
        MinecraftServer server = attacker.server;
        UUID attackerId = attacker.getUUID();
        UUID victimId = event.getEntity().getUUID();
        float mul = 1.0F;
        for (Entry entry : ModifierState.get(server).entries()) {
            if (!entry.holder().equals(attackerId)) {
                continue;
            }
            if (entry.kind() == Kind.DAMAGE_MUL) {
                mul *= entry.value();
            } else if (entry.kind() == Kind.GRUDGE && victimId.equals(entry.other())) {
                mul *= entry.value();
            }
        }
        if (Math.abs(mul - 1.0F) >= 1.0E-4F) {
            event.setAmount(Math.max(0.0F, event.getAmount() * mul));
        }
    }

    // ================================================================== temp hearts

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            applyTempHearts(player);
        }
    }

    @SubscribeEvent
    static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            applyTempHearts(player);
        }
    }

    @SubscribeEvent
    static void onPlayerClone(PlayerEvent.Clone event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            applyTempHearts(player);
        }
    }

    /**
     * Rebuilds the one transient contract-hearts modifier from the ledger. The malus is
     * clamped so max health never drops below 2.0 (one heart) even stacked with the
     * {@code HeartsService} lives projection — the #6 hard invariant.
     */
    private static void applyTempHearts(ServerPlayer player) {
        AttributeInstance maxHealth = player.getAttribute(Attributes.MAX_HEALTH);
        if (maxHealth == null) {
            return;
        }
        int hearts = 0;
        for (Entry entry : ModifierState.get(player.server).entries()) {
            if (entry.kind() == Kind.TEMP_HEARTS && entry.holder().equals(player.getUUID())) {
                hearts += (int) entry.value();
            }
        }
        if (hearts == 0) {
            maxHealth.removeModifier(CONTRACT_HEARTS_ID);
        } else {
            double bonus = hearts * 2.0D;
            if (bonus < 0.0D) {
                // Never let the contract malus push effective max health below one heart.
                double withoutContract = maxHealth.getValue()
                        - currentContractBonus(maxHealth);
                bonus = Math.max(bonus, 2.0D - withoutContract);
                if (bonus >= 0.0D) {
                    maxHealth.removeModifier(CONTRACT_HEARTS_ID);
                    return;
                }
            }
            maxHealth.addOrUpdateTransientModifier(new AttributeModifier(
                    CONTRACT_HEARTS_ID, bonus, AttributeModifier.Operation.ADD_VALUE));
        }
        float lowerBound = player.isAlive() ? 1.0F : 0.0F;
        player.setHealth(Mth.clamp(player.getHealth(), lowerBound, player.getMaxHealth()));
    }

    private static double currentContractBonus(AttributeInstance maxHealth) {
        AttributeModifier existing = maxHealth.getModifier(CONTRACT_HEARTS_ID);
        return existing != null ? existing.amount() : 0.0D;
    }

    // ================================================================== SavedData

    /**
     * The ledger file ({@code data/eclipse_contract_modifiers.dat}) — separate from
     * {@link ContractState} so modifier churn never dirties the contract state machine.
     * Public (with public mutators) for the D3 gametest surface only.
     */
    public static final class ModifierState extends SavedData {
        static final String DATA_NAME = "eclipse_contract_modifiers";

        private final List<Entry> entries = new ArrayList<>();
        /**
         * FFIX-B: epoch millis of the last pause-aware epoch shift while
         * {@code RealtimeDayApi.isPaused}. Persisted so boot resume can shift epochs by
         * the OFFLINE span of a pause. {@code 0} = not paused / no anchor.
         */
        private long pauseAnchorEpochMillis;

        public static ModifierState get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_NAME,
                    new SavedData.Factory<>(ModifierState::new, ModifierState::load));
        }

        public ModifierState() {}

        public static ModifierState load(CompoundTag tag, HolderLookup.Provider registries) {
            ModifierState state = new ModifierState();
            for (Tag element : tag.getList("entries", Tag.TAG_COMPOUND)) {
                CompoundTag entry = (CompoundTag) element;
                if (!entry.hasUUID("holder")) {
                    continue;
                }
                state.entries.add(new Entry(
                        entry.getUUID("holder"),
                        Kind.byName(entry.getString("kind")),
                        entry.getFloat("value"),
                        entry.hasUUID("other") ? entry.getUUID("other") : null,
                        entry.getInt("expiresAfterDay"),
                        // Absent on pre-D3 saves: getLong returns 0 = day-scoped only.
                        entry.getLong("expiresAtEpoch")));
            }
            state.pauseAnchorEpochMillis = tag.getLong("pauseAnchor");
            return state;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (Entry entry : entries) {
                CompoundTag row = new CompoundTag();
                row.putUUID("holder", entry.holder());
                row.putString("kind", entry.kind().name());
                row.putFloat("value", entry.value());
                if (entry.other() != null) {
                    row.putUUID("other", entry.other());
                }
                row.putInt("expiresAfterDay", entry.expiresAfterDay());
                if (entry.expiresAtEpochMillis() > 0L) {
                    row.putLong("expiresAtEpoch", entry.expiresAtEpochMillis());
                }
                list.add(row);
            }
            tag.put("entries", list);
            if (pauseAnchorEpochMillis > 0L) {
                tag.putLong("pauseAnchor", pauseAnchorEpochMillis);
            }
            return tag;
        }

        public List<Entry> entries() {
            return List.copyOf(entries);
        }

        public void add(Entry entry) {
            entries.add(entry);
            setDirty();
        }

        /** Removes and returns every entry that expired before {@code newDay}. */
        public List<Entry> removeExpired(int newDay) {
            List<Entry> expired = new ArrayList<>();
            entries.removeIf(entry -> {
                if (newDay > entry.expiresAfterDay()) {
                    expired.add(entry);
                    return true;
                }
                return false;
            });
            if (!expired.isEmpty()) {
                setDirty();
            }
            return expired;
        }

        /** Removes and returns every window-scoped entry whose epoch passed (D3 sweep). */
        public List<Entry> removeEpochExpired(long nowEpochMillis) {
            List<Entry> expired = new ArrayList<>();
            entries.removeIf(entry -> {
                if (entry.expiresAtEpochMillis() > 0L
                        && nowEpochMillis >= entry.expiresAtEpochMillis()) {
                    expired.add(entry);
                    return true;
                }
                return false;
            });
            if (!expired.isEmpty()) {
                setDirty();
            }
            return expired;
        }

        /** Pause-aware shift: pushes every window-scoped deadline forward (FFIX-B). */
        public void shiftEpochDeadlines(long deltaMillis) {
            if (deltaMillis <= 0L) {
                return;
            }
            boolean shifted = false;
            for (int i = 0; i < entries.size(); i++) {
                Entry entry = entries.get(i);
                if (entry.expiresAtEpochMillis() > 0L) {
                    entries.set(i, new Entry(entry.holder(), entry.kind(), entry.value(),
                            entry.other(), entry.expiresAfterDay(),
                            entry.expiresAtEpochMillis() + deltaMillis));
                    shifted = true;
                }
            }
            if (shifted) {
                setDirty();
            }
        }

        public long pauseAnchorEpochMillis() {
            return pauseAnchorEpochMillis;
        }

        public void setPauseAnchorEpochMillis(long epochMillis) {
            if (this.pauseAnchorEpochMillis == epochMillis) {
                return;
            }
            this.pauseAnchorEpochMillis = epochMillis;
            setDirty();
        }

        void clear() {
            if (!entries.isEmpty()) {
                entries.clear();
                setDirty();
            }
        }
    }
}
