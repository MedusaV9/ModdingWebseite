package dev.projecteclipse.eclipse.contracts;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.awards.AwardConfig;
import dev.projecteclipse.eclipse.awards.AwardService;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.ghosts.LogoutGhostEntity;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.contracts.ContractPayloads;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayApi;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.player.AttackEntityEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * KILL CONTRACTS state machine (IDEA-20 #1): {@code IDLE → SCHEDULED → ANNOUNCED(omen) →
 * ACTIVE → resolved → IDLE}, persisted in {@link ContractState}, crash-resumed on boot
 * (the {@code XboxEventService.resumeOnBoot} shape), pause-aware against
 * {@code RealtimeDayApi} (deadlines shift forward while the real-time day is frozen).
 *
 * <p><b>Daily roll</b> (config-gated, default OFF): at day rollover PRE the odds table is
 * rolled once per day — REAL / PRANK / nothing — and the window start is committed as an
 * absolute {@code EclipseClock} epoch. The PAIR is drawn at omen time from players actually
 * online (fairness rules in {@link #pickPair}), and committed to SavedData BEFORE any
 * reveal is sent, so a crash never re-rolls a different target.</p>
 *
 * <p><b>Resolution matrix</b> (window ACTIVE, REAL): hunter kills target → SUCCESS; window
 * expires → EXPIRED (survivor consolation); hunter kills anyone else → WRONG_KILL
 * (Blutschuld/Vergeltung, contract continues); target dies to anything else → VOIDED
 * (the system refuses to be an executioner); target kills hunter → TABLES_TURNED (full
 * killer advantage flips to the target). Ghost path: a logged-out target's
 * {@code LogoutGhostEntity} IS the target — the hunter banishes it with
 * {@code ghostKillHits} strikes for a reduced ({@code ghostPayoutPct}) payout.</p>
 *
 * <p>Hard invariants (IDEA-20 #6): contracts never touch permanent LIVES, never trigger
 * bans, and every advantage/disadvantage expires at the next rollover via
 * {@link ContractModifierService}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ContractService {

    /** Music seam: soft-guarded — the cue ships as a wiring ask, absence is tolerated. */
    private static final String MUSIC_CUE_ID = "kill_contract";
    private static final float SHAKE_STRENGTH = 0.35F;
    private static final int SHAKE_TICKS = 16;
    private static final int TICK_INTERVAL = 10;
    private static final double PROXIMITY_BONUS_RANGE_SQ = 400.0D * 400.0D;

    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();
    private static final Random RANDOM = new Random();

    // ---- transient per-run state (cleared on ServerStoppedEvent) ----
    private static long lastPauseCheckMillis;
    private static boolean missingCueLogged;

    private ContractService() {}

    // ================================================================== lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("contracts", ContractConfig::reload);
        }
        ContractConfig.reload();
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover(ContractService::onDayRollover);
        }
        resumeOnBoot(event.getServer());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        lastPauseCheckMillis = 0L;
        missingCueLogged = false;
    }

    /**
     * Crash resume: the periodic tick would catch everything anyway, but resolving an
     * already-expired window here keeps the boot log honest and replays the compressed
     * (banner-only) expiry ceremony immediately.
     */
    public static void resumeOnBoot(MinecraftServer server) {
        ContractState state = ContractState.get(server);
        long now = EclipseClock.epochMillis();
        switch (state.phase()) {
            case ACTIVE -> {
                if (state.endsAtEpochMillis() <= now) {
                    EclipseMod.LOGGER.info("Contract window expired while the server was down — resolving now");
                    resolveExpired(server, state);
                } else {
                    EclipseMod.LOGGER.info("Contract window resumes: {} ms remaining (mode {})",
                            state.endsAtEpochMillis() - now, state.mode());
                }
            }
            case ANNOUNCED, SCHEDULED -> EclipseMod.LOGGER.info(
                    "Contract {} resumes in phase {} (starts in {} ms)",
                    state.mode(), state.phase(), Math.max(0L, state.windowStartsAtEpochMillis() - now));
            case IDLE -> { /* nothing */ }
        }
    }

    // ================================================================== daily roll

    /**
     * PRE rollover: a still-running window resolves as EXPIRED first (contracts never span
     * days), then the odds are rolled exactly once for the new day (crash-safe latch).
     */
    private static void onDayRollover(MinecraftServer server, int endedDay, int newDay,
            EclipseSignals.DayRolloverPhase phase) {
        if (phase != EclipseSignals.DayRolloverPhase.PRE) {
            return;
        }
        ContractState state = ContractState.get(server);
        if (state.phase() == ContractState.Phase.ACTIVE) {
            resolveExpired(server, state);
        } else if (state.phase() != ContractState.Phase.IDLE) {
            state.clearContract();
        }
        ContractConfig.Values config = ContractConfig.get();
        if (!config.autoDaily() || state.rolledForDay() == newDay) {
            return;
        }
        state.setRolledForDay(newDay);
        int roll = RANDOM.nextInt(100);
        ContractState.Mode mode;
        if (roll < config.realChancePct()) {
            mode = ContractState.Mode.REAL;
        } else if (roll < config.realChancePct() + config.prankChancePct()) {
            mode = ContractState.Mode.PRANK;
        } else {
            EclipseMod.LOGGER.info("Contract roll for day {}: none (roll {})", newDay, roll);
            return;
        }
        int minMin = Math.min(config.windowStartMinMinutes(), config.windowStartMaxMinutes());
        int maxMin = Math.max(config.windowStartMinMinutes(), config.windowStartMaxMinutes());
        long startDelayMillis = (minMin + (long) RANDOM.nextInt(Math.max(1, maxMin - minMin + 1)))
                * 60_000L;
        state.setMode(mode);
        state.setPair(null, null);
        state.setContractDay(newDay);
        state.setWindowStartsAtEpochMillis(EclipseClock.epochMillis() + startDelayMillis);
        state.setPhase(ContractState.Phase.SCHEDULED);
        EclipseMod.LOGGER.info("Contract roll for day {}: {} scheduled in {} min",
                newDay, mode, startDelayMillis / 60_000L);
    }

    // ================================================================== tick

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % TICK_INTERVAL != 0) {
            return;
        }
        ContractState state = ContractState.get(server);
        if (state.phase() == ContractState.Phase.IDLE) {
            lastPauseCheckMillis = 0L;
            return;
        }
        long now = EclipseClock.epochMillis();
        // Pause-aware deadlines: while the real-time day is frozen, every pending deadline
        // shifts forward by exactly the frozen span (the xbox timeMutate philosophy).
        if (RealtimeDayApi.isPaused(server)) {
            if (lastPauseCheckMillis > 0L) {
                state.shiftDeadlines(now - lastPauseCheckMillis);
            }
            lastPauseCheckMillis = now;
            return;
        }
        lastPauseCheckMillis = now;

        switch (state.phase()) {
            case SCHEDULED -> {
                if (now >= state.windowStartsAtEpochMillis()) {
                    beginOmen(server, state);
                }
            }
            case ANNOUNCED -> {
                if (now >= state.windowStartsAtEpochMillis()) {
                    beginActive(server, state);
                }
            }
            case ACTIVE -> {
                if (now >= state.endsAtEpochMillis()) {
                    resolveExpired(server, state);
                }
            }
            default -> { /* IDLE handled above */ }
        }
    }

    // ================================================================== start / omen / active

    /**
     * Dev/forced start: skips the SCHEDULED wait and runs a short omen. Pass {@code null}
     * players for the fairness auto-draw. Returns a failure line or {@code null} on success.
     */
    @Nullable
    public static Component forceStart(MinecraftServer server, ContractState.Mode mode,
            @Nullable ServerPlayer forcedHunter, @Nullable ServerPlayer forcedTarget, int omenSeconds) {
        ContractState state = ContractState.get(server);
        if (state.phase() == ContractState.Phase.ANNOUNCED
                || state.phase() == ContractState.Phase.ACTIVE) {
            return Component.translatable("dev.eclipse.contract.start.already");
        }
        state.setMode(mode);
        state.setContractDay(EclipseWorldState.get(server).getDay());
        if (mode == ContractState.Mode.REAL) {
            UUID hunter;
            UUID target;
            if (forcedHunter != null && forcedTarget != null) {
                if (forcedHunter.getUUID().equals(forcedTarget.getUUID())) {
                    return Component.translatable("dev.eclipse.contract.start.same_player");
                }
                hunter = forcedHunter.getUUID();
                target = forcedTarget.getUUID();
            } else {
                UUID[] pair = pickPair(server, state);
                if (pair == null) {
                    return Component.translatable("dev.eclipse.contract.start.no_candidates");
                }
                hunter = pair[0];
                target = pair[1];
            }
            state.setPair(hunter, target);
            state.recordPair(hunter, target, state.contractDay());
        } else {
            state.setPair(null, null);
        }
        state.setWindowStartsAtEpochMillis(EclipseClock.epochMillis() + omenSeconds * 1_000L);
        state.setPhase(ContractState.Phase.ANNOUNCED);
        announceOmen(server);
        EclipseMod.LOGGER.info("Contract force-started: mode={}, omen={}s", mode, omenSeconds);
        return null;
    }

    /** Omen (auto path): commit the pair now, announce the wordless dread, arm the window. */
    private static void beginOmen(MinecraftServer server, ContractState state) {
        ContractConfig.Values config = ContractConfig.get();
        if (state.mode() == ContractState.Mode.REAL) {
            if (server.getPlayerList().getPlayerCount() < config.minOnlineForReal()) {
                EclipseMod.LOGGER.info("Contract degraded to PRANK: {} online < {} required",
                        server.getPlayerList().getPlayerCount(), config.minOnlineForReal());
                state.setMode(ContractState.Mode.PRANK);
            } else {
                UUID[] pair = pickPair(server, state);
                if (pair == null) {
                    EclipseMod.LOGGER.info("Contract cancelled: no eligible hunter/target pair");
                    state.clearContract();
                    return;
                }
                state.setPair(pair[0], pair[1]);
                state.recordPair(pair[0], pair[1], state.contractDay());
            }
        }
        state.setWindowStartsAtEpochMillis(EclipseClock.epochMillis()
                + ContractConfig.get().omenSeconds() * 1_000L);
        state.setPhase(ContractState.Phase.ANNOUNCED);
        announceOmen(server);
    }

    private static void announceOmen(MinecraftServer server) {
        AnnouncementService.announce(server, "announce.eclipse.contract.omen.title",
                "announce.eclipse.contract.omen.sub", S2CAnnouncePayload.STYLE_BOSS);
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.BELL_RESONATE, SoundSource.AMBIENT, 0.7F, 0.5F);
        }
    }

    /** ACTIVE start: reveals, armor blackout flag, music. The one anonymity breach fires here. */
    private static void beginActive(MinecraftServer server, ContractState state) {
        ContractConfig.Values config = ContractConfig.get();
        long now = EclipseClock.epochMillis();
        long endsAt = now + config.windowMinutes() * 60_000L;
        state.setEndsAtEpochMillis(endsAt);
        state.setPhase(ContractState.Phase.ACTIVE);
        int windowTicks = config.windowMinutes() * 60 * 20;

        ContractPayloads.sendStateToAll(server, true, endsAt, now);
        if (state.mode() == ContractState.Mode.REAL) {
            ServerPlayer hunter = playerOf(server, state.hunter());
            ServerPlayer target = playerOf(server, state.target());
            if (hunter != null) {
                ContractPayloads.sendHunterReveal(hunter, state.target(), windowTicks, false);
                playMusic(hunter);
            }
            if (target != null) {
                ContractPayloads.sendTargetReveal(target, windowTicks, false);
                PacketDistributor.sendToPlayer(target, S2CShakePayload.mark(60));
                playMusic(target);
            }
            if (target == null) {
                state.setTargetLoggedOut(true);
            }
        } else {
            // PRANK: EVERYONE gets the identical target treatment; nobody is hunted.
            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                ContractPayloads.sendTargetReveal(online, windowTicks, false);
                PacketDistributor.sendToPlayer(online, S2CShakePayload.mark(60));
                playMusic(online);
            }
        }
        EclipseMod.LOGGER.info("Contract window ACTIVE: mode={}, {} min", state.mode(),
                config.windowMinutes());
    }

    // ================================================================== fairness draw

    /**
     * Weighted fair draw over ONLINE players (IDEA-20 #8, trimmed to what is verifiable
     * live): excludes spectators, banned "ghost" players, cutscene-frozen players and
     * 0-lives hunters; targets additionally need ≥2 lives (a contract death must sting,
     * never end a run). Same-pair cooldown and back-to-back-target protection apply;
     * same-dimension (and <400 m) pairs get extra weight when proximity weighting is on.
     *
     * @return {@code [hunter, target]} or {@code null} when no legal pair exists
     */
    @Nullable
    static UUID[] pickPair(MinecraftServer server, ContractState state) {
        ContractConfig.Values config = ContractConfig.get();
        int day = state.contractDay();
        List<ServerPlayer> hunters = new ArrayList<>();
        List<ServerPlayer> targets = new ArrayList<>();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (!isEligible(player)) {
                continue;
            }
            int lives = LivesApi.get(player);
            if (lives >= 1) {
                hunters.add(player);
            }
            if (lives >= 2 && !state.wasRecentTarget(player.getUUID(), day)) {
                targets.add(player);
            }
        }
        record WeightedPair(ServerPlayer hunter, ServerPlayer target, int weight) {}
        List<WeightedPair> pairs = new ArrayList<>();
        int totalWeight = 0;
        for (ServerPlayer hunter : hunters) {
            for (ServerPlayer target : targets) {
                if (hunter.getUUID().equals(target.getUUID())
                        || state.isPairOnCooldown(hunter.getUUID(), target.getUUID(), day,
                                config.pairCooldownDays())) {
                    continue;
                }
                int weight = 1;
                if (config.proximityWeighting()
                        && hunter.level().dimension().equals(target.level().dimension())) {
                    weight += 1;
                    if (hunter.distanceToSqr(target) <= PROXIMITY_BONUS_RANGE_SQ) {
                        weight += 2;
                    }
                }
                pairs.add(new WeightedPair(hunter, target, weight));
                totalWeight += weight;
            }
        }
        if (pairs.isEmpty()) {
            return null;
        }
        int pick = RANDOM.nextInt(totalWeight);
        for (WeightedPair pair : pairs) {
            pick -= pair.weight();
            if (pick < 0) {
                return new UUID[] {pair.hunter().getUUID(), pair.target().getUUID()};
            }
        }
        WeightedPair last = pairs.get(pairs.size() - 1);
        return new UUID[] {last.hunter().getUUID(), last.target().getUUID()};
    }

    private static boolean isEligible(ServerPlayer player) {
        if (player.isSpectator() || FreezeService.isFrozen(player)) {
            return false;
        }
        return !player.getData(EclipseAttachments.BANNED)
                && !EclipseWorldState.get(player.server).isBanned(player.getUUID());
    }

    // ================================================================== kill detection

    /**
     * LOW priority: after the death economy (the {@code FirstBloodService} placement) and
     * never for deaths cancelled by higher-priority protectors (xbox dims).
     */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        MinecraftServer server = victim.server;
        ContractState state = ContractState.get(server);
        if (state.phase() != ContractState.Phase.ACTIVE
                || state.mode() != ContractState.Mode.REAL) {
            return;
        }
        ServerPlayer killer = event.getSource().getEntity() instanceof ServerPlayer sp ? sp : null;
        UUID victimId = victim.getUUID();
        boolean victimIsTarget = victimId.equals(state.target());
        boolean victimIsHunter = victimId.equals(state.hunter());
        boolean killerIsHunter = killer != null && killer.getUUID().equals(state.hunter());
        boolean killerIsTarget = killer != null && killer.getUUID().equals(state.target());

        if (victimIsTarget && killerIsHunter) {
            resolveSuccess(server, state, killer, victim, 100);
        } else if (victimIsTarget) {
            // Environment, mobs or an uninvolved player: the contract is withdrawn.
            resolveVoided(server, state);
        } else if (victimIsHunter && killerIsTarget) {
            resolveTablesTurned(server, state, killer, victim);
        } else if (killerIsHunter) {
            applyWrongKill(server, state, killer, victim);
        }
    }

    /** Blutschuld + Vergeltung (IDEA-20 #5). Non-terminal: the contract keeps running. */
    private static void applyWrongKill(MinecraftServer server, ContractState state,
            ServerPlayer killer, ServerPlayer victim) {
        ContractConfig.Values config = ContractConfig.get();
        ContractConfig.WrongKillValues wk = config.wrongKill();
        int day = state.contractDay();

        ContractModifierService.grantDamageMul(server, killer.getUUID(), wk.killerDamageMul(), day);
        ContractModifierService.grantSkillsMul(server, killer.getUUID(), wk.killerSkillsMul(), day);
        ContractModifierService.grantAwardVoid(server, killer.getUUID(), day);

        ContractModifierService.grantTempHearts(server, victim.getUUID(), wk.victimTempHearts(), day);
        ContractModifierService.grantGrudge(server, victim.getUUID(), killer.getUUID(),
                wk.victimGrudgeMul(), day);

        state.recordWrongKill();

        // Private typewriter lines to exactly the two involved; anonymous thunder for the rest.
        PacketDistributor.sendToPlayer(killer, new S2CAnnouncePayload(
                "announce.eclipse.contract.guilt.title", "eclipse.contract.guilt.killer",
                S2CAnnouncePayload.STYLE_BOSS));
        PacketDistributor.sendToPlayer(victim, new S2CAnnouncePayload(
                "announce.eclipse.contract.guilt.title", "eclipse.contract.guilt.victim",
                S2CAnnouncePayload.STYLE_BOSS));
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(SHAKE_STRENGTH, SHAKE_TICKS));
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.AMBIENT, 0.6F, 0.8F);
        }
        EclipseMod.LOGGER.info("Contract wrong-kill: Blutschuld applied (contract continues)");
    }

    // ================================================================== ghost path

    /**
     * Offline target (IDEA-20 #11): the logout ghost IS the target. The ghost entity is
     * invulnerable by design, so "killing" it is a banishment ritual — {@code ghostKillHits}
     * strikes by the hunter resolve the contract as SUCCESS at {@code ghostPayoutPct}.
     */
    @SubscribeEvent
    static void onAttackEntity(AttackEntityEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer attacker)
                || !(event.getTarget() instanceof LogoutGhostEntity ghost)) {
            return;
        }
        MinecraftServer server = attacker.server;
        ContractState state = ContractState.get(server);
        if (state.phase() != ContractState.Phase.ACTIVE
                || state.mode() != ContractState.Mode.REAL
                || !attacker.getUUID().equals(state.hunter())
                || ghost.getOwnerUuid().isEmpty()
                || !ghost.getOwnerUuid().get().equals(state.target())) {
            return;
        }
        int hits = state.ghostHits() + 1;
        state.setGhostHits(hits);
        ContractConfig.Values config = ContractConfig.get();
        attacker.playNotifySound(SoundEvents.BELL_RESONATE, SoundSource.PLAYERS, 0.5F,
                0.6F + 0.15F * hits);
        if (hits >= config.ghostKillHits()) {
            attacker.displayClientMessage(
                    Component.translatable("eclipse.contract.ghost.success"), false);
            ghost.discard();
            resolveSuccess(server, state, attacker, null, config.ghostPayoutPct());
        }
    }

    // ================================================================== resolutions

    /** SUCCESS: hunter advantage + target disadvantage; {@code payoutPct} scales the loot. */
    private static void resolveSuccess(MinecraftServer server, ContractState state,
            ServerPlayer hunter, @Nullable ServerPlayer deadTarget, int payoutPct) {
        ContractConfig.Values config = ContractConfig.get();
        ContractConfig.SuccessValues sv = config.success();
        int day = state.contractDay();
        UUID targetId = state.target();
        boolean reduced = payoutPct < 100;

        // Hunter advantage (expires at rollover; never touches permanent lives).
        ContractModifierService.grantSkillsMul(server, hunter.getUUID(), sv.hunterSkillsMul(), day);
        ContractModifierService.grantDamageMul(server, hunter.getUUID(), sv.hunterDamageMul(), day);
        if (!reduced && sv.hunterTempHearts() > 0) {
            ContractModifierService.grantTempHearts(server, hunter.getUUID(), sv.hunterTempHearts(), day);
        }
        int shards = Math.max(0, sv.hunterShards() * payoutPct / 100);
        int xp = Math.max(0, sv.hunterXp() * payoutPct / 100);
        ShardEconomy.addShards(hunter, shards);
        SkillsApi.addXp(hunter, "contract", xp);
        if (!sv.hunterGlobalBuffId().isEmpty()) {
            TimedBuffApi.Holder.get().start(server, sv.hunterGlobalBuffId(), 0);
        }

        // Target disadvantage — offline-safe: modifiers key off the UUID, hearts/skills
        // reapply on login through ContractModifierService.
        if (targetId != null) {
            ContractModifierService.grantSkillsMul(server, targetId, sv.targetSkillsMul(), day);
            ContractModifierService.grantDamageMul(server, targetId, sv.targetDamageMul(), day);
        }

        // Ceremony: one deep bell + one shake + one nameless banner (FirstBlood grammar).
        AnnouncementService.announce(server, "announce.eclipse.contract.success.title", "",
                S2CAnnouncePayload.STYLE_BOSS);
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(SHAKE_STRENGTH, SHAKE_TICKS));
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.BELL_RESONATE, SoundSource.AMBIENT, 0.9F, 0.4F);
        }
        ContractPayloads.sendResolve(hunter, ContractPayloads.RESOLVE_FULFILLED);
        if (deadTarget != null) {
            // "It was a contract." — the best story-generator in the system (IDEA-20 #9).
            deadTarget.displayClientMessage(
                    Component.translatable("eclipse.contract.bought"), false);
        }
        finishWindow(server, state, ContractState.Outcome.SUCCESS);
    }

    /** EXPIRED (REAL): survivor consolation. PRANK windows resolve as the theater reveal. */
    private static void resolveExpired(MinecraftServer server, ContractState state) {
        if (state.mode() == ContractState.Mode.PRANK) {
            resolvePrankReveal(server, state);
            return;
        }
        ContractConfig.Values config = ContractConfig.get();
        UUID targetId = state.target();
        if (targetId != null) {
            ServerPlayer target = playerOf(server, targetId);
            if (target != null) {
                SkillsApi.addXp(target, "contract", config.expiry().survivorXp());
                ShardEconomy.addShards(target, config.expiry().survivorShards());
                target.displayClientMessage(
                        Component.translatable("eclipse.contract.survivor"), false);
                ContractPayloads.sendResolve(target, ContractPayloads.RESOLVE_SURVIVED);
            } else {
                AwardService.queueReward(server, targetId, "contract_survived",
                        new AwardConfig.Reward(config.expiry().survivorXp(),
                                config.expiry().survivorShards(), List.of()));
            }
        }
        ServerPlayer hunter = playerOf(server, state.hunter());
        if (hunter != null) {
            ContractPayloads.sendResolve(hunter, ContractPayloads.RESOLVE_LAPSED);
        }
        AnnouncementService.announce(server, "announce.eclipse.contract.expired.title", "",
                S2CAnnouncePayload.STYLE_BOSS);
        finishWindow(server, state, ContractState.Outcome.EXPIRED);
    }

    /** VOIDED: the target died to something that was not the hunt — nobody profits. */
    private static void resolveVoided(MinecraftServer server, ContractState state) {
        ServerPlayer hunter = playerOf(server, state.hunter());
        if (hunter != null) {
            hunter.displayClientMessage(
                    Component.translatable("eclipse.contract.voided.hunter"), false);
            ContractPayloads.sendResolve(hunter, ContractPayloads.RESOLVE_WITHDRAWN);
        }
        finishWindow(server, state, ContractState.Outcome.VOIDED);
    }

    /** TABLES_TURNED: the target killed the hunter — the full killer advantage flips. */
    private static void resolveTablesTurned(MinecraftServer server, ContractState state,
            ServerPlayer target, ServerPlayer deadHunter) {
        ContractConfig.Values config = ContractConfig.get();
        ContractConfig.SuccessValues sv = config.success();
        int day = state.contractDay();

        ContractModifierService.grantSkillsMul(server, target.getUUID(), sv.hunterSkillsMul(), day);
        ContractModifierService.grantDamageMul(server, target.getUUID(), sv.hunterDamageMul(), day);
        if (sv.hunterTempHearts() > 0) {
            ContractModifierService.grantTempHearts(server, target.getUUID(), sv.hunterTempHearts(), day);
        }
        ShardEconomy.addShards(target, sv.hunterShards());
        SkillsApi.addXp(target, "contract", sv.hunterXp());
        ContractModifierService.grantSkillsMul(server, deadHunter.getUUID(), sv.targetSkillsMul(), day);
        ContractModifierService.grantDamageMul(server, deadHunter.getUUID(), sv.targetDamageMul(), day);

        AnnouncementService.announce(server, "announce.eclipse.contract.tables.title", "",
                S2CAnnouncePayload.STYLE_BOSS);
        PacketDistributor.sendToAllPlayers(S2CShakePayload.shake(SHAKE_STRENGTH, SHAKE_TICKS));
        target.displayClientMessage(Component.translatable("eclipse.contract.tables.target"), false);
        deadHunter.displayClientMessage(Component.translatable("eclipse.contract.tables.hunter"), false);
        ContractPayloads.sendResolve(target, ContractPayloads.RESOLVE_SURVIVED);
        ContractPayloads.sendResolve(deadHunter, ContractPayloads.RESOLVE_LAPSED);
        finishWindow(server, state, ContractState.Outcome.TABLES_TURNED);
    }

    /** PRANK exhale: "No one was hunting you. Today." + a stayed-online consolation. */
    private static void resolvePrankReveal(MinecraftServer server, ContractState state) {
        ContractConfig.Values config = ContractConfig.get();
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            ContractPayloads.sendResolve(online, ContractPayloads.RESOLVE_PRANK_REVEAL);
            if (config.prankConsolationShards() > 0) {
                ShardEconomy.addShards(online, config.prankConsolationShards());
                online.displayClientMessage(Component.translatable(
                        "eclipse.contract.prank.consolation", config.prankConsolationShards()), false);
            }
        }
        finishWindow(server, state, ContractState.Outcome.PRANK_REVEAL);
    }

    /** Shared teardown: blackout off, music stopped, tallies committed, back to IDLE. */
    private static void finishWindow(MinecraftServer server, ContractState state,
            ContractState.Outcome outcome) {
        long now = EclipseClock.epochMillis();
        ContractPayloads.sendStateToAll(server, false, now, now);
        if (state.mode() == ContractState.Mode.REAL) {
            stopMusic(playerOf(server, state.hunter()));
            stopMusic(playerOf(server, state.target()));
        } else {
            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                stopMusic(online);
            }
        }
        state.recordOutcome(outcome);
        state.clearContract();
        EclipseMod.LOGGER.info("Contract resolved: {} ({})", outcome, state.tallyLine());
    }

    /** Dev force-stop: a running window resolves as EXPIRED; SCHEDULED/ANNOUNCED cancel. */
    @Nullable
    public static Component forceStop(MinecraftServer server) {
        ContractState state = ContractState.get(server);
        switch (state.phase()) {
            case ACTIVE -> resolveExpired(server, state);
            case SCHEDULED, ANNOUNCED -> state.clearContract();
            case IDLE -> {
                return Component.translatable("dev.eclipse.contract.stop.idle");
            }
        }
        return null;
    }

    // ================================================================== login / logout edges

    /** Mid-window relog: resync the window flag and replay the role reveal (marker only). */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        MinecraftServer server = player.server;
        ContractState state = ContractState.get(server);
        long now = EclipseClock.epochMillis();
        boolean active = state.phase() == ContractState.Phase.ACTIVE;
        ContractPayloads.sendState(player, active, active ? state.endsAtEpochMillis() : now, now);
        if (!active) {
            return;
        }
        int remainingTicks = (int) Math.max(0L, (state.endsAtEpochMillis() - now) / 50L);
        if (state.mode() == ContractState.Mode.REAL) {
            if (player.getUUID().equals(state.hunter())) {
                ContractPayloads.sendHunterReveal(player, state.target(), remainingTicks, true);
                playMusic(player);
            } else if (player.getUUID().equals(state.target())) {
                state.setTargetLoggedOut(false);
                ContractPayloads.sendTargetReveal(player, remainingTicks, true);
                playMusic(player);
            }
        } else {
            ContractPayloads.sendTargetReveal(player, remainingTicks, true);
            playMusic(player);
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        ContractState state = ContractState.get(player.server);
        if (state.phase() == ContractState.Phase.ACTIVE
                && state.mode() == ContractState.Mode.REAL
                && player.getUUID().equals(state.target())) {
            // The logout ghost service spawns the proxy; the ghost path takes over.
            state.setTargetLoggedOut(true);
            EclipseMod.LOGGER.info("Contract target logged out mid-window — the ghost is the target now");
        }
    }

    // ================================================================== helpers

    /** Replays the hunter reveal FX to one client (dev testing, no state change). */
    public static void replayReveal(ServerPlayer viewer, UUID shownTarget, int windowTicks) {
        ContractPayloads.sendHunterReveal(viewer, shownTarget, windowTicks, false);
    }

    /** Soft-guarded music seam: absent cue id logs once at DEBUG, never throws. */
    private static void playMusic(@Nullable ServerPlayer player) {
        if (player == null) {
            return;
        }
        if (!MusicCues.play(MUSIC_CUE_ID, player) && !missingCueLogged) {
            missingCueLogged = true;
            EclipseMod.LOGGER.debug("Music cue '{}' is not registered yet — contract windows stay "
                    + "silent (see W4-CONTRACTS wiring asks)", MUSIC_CUE_ID);
        }
    }

    private static void stopMusic(@Nullable ServerPlayer player) {
        if (player != null && MusicCues.fromId(MUSIC_CUE_ID).isPresent()) {
            MusicCues.stop(player);
        }
    }

    @Nullable
    private static ServerPlayer playerOf(MinecraftServer server, @Nullable UUID uuid) {
        return uuid == null ? null : server.getPlayerList().getPlayer(uuid);
    }

    /** Status snapshot for {@code /dev contract status}. */
    public static ContractState stateOf(MinecraftServer server) {
        return ContractState.get(server);
    }
}
