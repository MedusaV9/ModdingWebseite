package dev.projecteclipse.eclipse.woah.resonance;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsService;
import dev.projecteclipse.eclipse.analytics.AnalyticsState;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-04 §3.2/§6/§7 — the melody-puzzle statemachine, ticked by
 * {@link ResonanceFieldService} and persisted in {@link ResonanceFieldData}
 * ({@code state} ordinal + {@code stateSince} gameTime, restart-safe by design):
 *
 * <pre>IDLE → TEACH → LISTEN → (FINALE | FAIL) → … → COOLDOWN → IDLE</pre>
 *
 * <p>All timings ride {@code gameTime - stateSince} — no transient tick counters, so a
 * server restart mid-TEACH simply resumes the beat grid. Free strikes (note + cascade)
 * work in EVERY state; only the DIRECTLY struck crystal counts as puzzle input
 * (§7.4 — a cascade echo can never mis-enter). The melody itself never crosses the
 * wire: teach glows arrive as per-note {@code CUE_RESONANCE_STRIKE} cues (leak-free,
 * §3.6).</p>
 */
public final class ResonanceMelodyMachine {
    /** Wire-stable puzzle states ({@code S2CResonanceFieldPayload.state} = ordinal). */
    public enum State { IDLE, TEACH, LISTEN, FINALE, FAIL, COOLDOWN }

    // --- §3.2 timings (ticks) ---
    /** Beat grid of the TEACH playback (0.7 s per note). */
    public static final int TEACH_BEAT_TICKS = 14;
    /** Pause between the last teach note and the LISTEN window. */
    private static final int TEACH_TAIL_TICKS = 20;
    /** LISTEN input window (30 s); timeout falls back to IDLE without a sting. */
    private static final int LISTEN_WINDOW_TICKS = 600;
    /** FAIL recovery before the automatic re-TEACH. */
    private static final int FAIL_RECOVER_TICKS = 40;
    /** Finale direction length (§7.2). */
    public static final int FINALE_TICKS = 160;
    /** Post-solve cooldown (10 min), persisted as absolute gameTime. */
    public static final int COOLDOWN_TICKS = 12000;
    /** IDLE auto-teach interval (60 s) — requires a player near the altar too. */
    private static final int IDLE_AUTO_TEACH_TICKS = 1200;
    /** Altar-use anti-spam window. */
    private static final int ALTAR_USE_COOLDOWN_TICKS = 100;
    /** Melody stays identical for this many fails; the next TEACH rerolls (§3.2 FAIL). */
    private static final int FAILS_BEFORE_REROLL = 3;

    // --- §7.2/§7.3 finale beats ---
    private static final int FINALE_CHORD_TICK = 24;
    private static final int FINALE_REWARD_TICK = 40;
    private static final int FINALE_SWELL_TICK = 60;
    private static final int SOLVE_REWARD_SHARDS = 6;
    private static final int SOLVE_REWARD_XP = 300;

    /** Auto-teach / caption radius around the altar (§3.2 IDLE). */
    private static final double TEACH_PLAYER_RADIUS = 40.0D;
    /** Caption broadcast radius (teach/progress/fail read near the valley center). */
    private static final double CAPTION_RADIUS = 48.0D;

    /** Last altar-use gameTime (anti-spam; transient — a restart forgives the window). */
    private static long lastAltarUse = Long.MIN_VALUE;

    private ResonanceMelodyMachine() {}

    static void clearSession() {
        lastAltarUse = Long.MIN_VALUE;
    }

    static State state(ResonanceFieldData data) {
        State[] states = State.values();
        int ordinal = data.stateOrdinal();
        return ordinal >= 0 && ordinal < states.length ? states[ordinal] : State.IDLE;
    }

    // ------------------------------------------------------------------ tick

    /**
     * COOLDOWN expiry — the ONE check that runs even with no player near (§3.7 gate:
     * "Nur der cooldownUntil-Vergleich läuft immer").
     */
    static void tickCooldownAlways(ServerLevel level, ResonanceFieldData data, long gameTime) {
        if (state(data) == State.COOLDOWN && gameTime >= data.cooldownUntil()) {
            data.rerollMelody(level.random.nextLong());
            data.setFailCount(0);
            enterState(level, data, State.IDLE, gameTime);
        }
    }

    /** Full statemachine tick; only called while a player is within 128 of the anchor. */
    static void tick(ServerLevel level, ResonanceFieldData data, long gameTime) {
        long inState = gameTime - data.stateSince();
        switch (state(data)) {
            case IDLE -> {
                if (inState >= IDLE_AUTO_TEACH_TICKS && anyPlayerNearAltar(level, data)) {
                    beginTeach(level, data, gameTime);
                }
            }
            case TEACH -> tickTeach(level, data, gameTime, inState);
            case LISTEN -> {
                if (inState >= LISTEN_WINDOW_TICKS) {
                    // Timeout is a soft fade back to IDLE — no sting (§3.2 LISTEN).
                    ResonanceFieldService.setHintCrystal(level, data, -1);
                    enterState(level, data, State.IDLE, gameTime);
                }
            }
            case FAIL -> {
                if (inState == 2L) {
                    failAfterChime(level, data);
                }
                if (inState >= FAIL_RECOVER_TICKS) {
                    beginTeach(level, data, gameTime);
                }
            }
            case FINALE -> tickFinale(level, data, gameTime, inState);
            case COOLDOWN -> { /* expiry handled by tickCooldownAlways */ }
        }
    }

    // ------------------------------------------------------------------ TEACH

    /** Starts (or restarts) the playback; rerolls the melody after 3+ fails (§3.2). */
    static void beginTeach(ServerLevel level, ResonanceFieldData data, long gameTime) {
        if (data.melody().length == 0 || data.failCount() >= FAILS_BEFORE_REROLL) {
            data.rerollMelody(level.random.nextLong());
            data.setFailCount(0);
        }
        data.setProgressIndex(0);
        ResonanceFieldService.setHintCrystal(level, data, -1);
        enterState(level, data, State.TEACH, gameTime);
        caption(level, data, "eclipse.resonance.caption.teach");
        Vec3 altar = altarCenter(data);
        if (altar != null) {
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.BLOCKS, 0.9F, 1.2F);
        }
    }

    /** One teach note per {@value #TEACH_BEAT_TICKS}-tick beat, then the 20-tick tail. */
    private static void tickTeach(ServerLevel level, ResonanceFieldData data, long gameTime,
            long inState) {
        int[] melody = data.melody();
        if (melody.length == 0) {
            enterState(level, data, State.IDLE, gameTime);
            return;
        }
        if (inState % TEACH_BEAT_TICKS == 0L) {
            int note = (int) (inState / TEACH_BEAT_TICKS);
            if (note < melody.length) {
                int crystal = ResonanceFieldService.crystalOfTone(data, melody[note]);
                if (crystal >= 0) {
                    playCrystalNote(level, data, crystal, 0.9F);
                    // b = 1 → teach pulse: glow flare only, no glitter burst (§3.6).
                    FxPayloads.sendFxEvent(level, ResonanceCues.CUE_RESONANCE_STRIKE,
                            crystalTop(data, crystal), melody[note], 1.0F, 96.0D);
                    ResonanceFieldService.pulseCrystal(level, data, crystal);
                }
            }
        }
        if (inState >= (long) melody.length * TEACH_BEAT_TICKS + TEACH_TAIL_TICKS) {
            enterState(level, data, State.LISTEN, gameTime);
            hintExpected(level, data);
        }
    }

    // ------------------------------------------------------------------ input

    /**
     * Puzzle input hook — called by the service AFTER the free strike (note + cascade)
     * has already played. Only LISTEN consumes input; every other state ignores it.
     */
    static void onCrystalStrike(ServerLevel level, ResonanceFieldData data, int crystalIdx,
            ServerPlayer player) {
        if (state(data) != State.LISTEN) {
            return;
        }
        long gameTime = level.getGameTime();
        int[] melody = data.melody();
        int progress = data.progressIndex();
        if (progress >= melody.length) {
            return; // finale transition already queued this tick
        }
        int struckTone = data.monoliths().get(crystalIdx).toneIndex;
        if (struckTone == melody[progress]) {
            progress++;
            data.setProgressIndex(progress);
            captionProgress(level, data, progress, melody.length);
            if (progress >= melody.length) {
                ResonanceFieldService.setHintCrystal(level, data, -1);
                beginFinale(level, data, gameTime);
            } else {
                hintExpected(level, data);
            }
        } else {
            fail(level, data, gameTime);
        }
    }

    /**
     * Altar interaction (§3.2 IDLE / §7.1.4 replay): starts or replays TEACH; blocked
     * during FINALE and COOLDOWN (cooldown answers with the remaining-time caption).
     */
    static void onAltarUse(ServerLevel level, ResonanceFieldData data, ServerPlayer player) {
        long gameTime = level.getGameTime();
        if (gameTime - lastAltarUse < ALTAR_USE_COOLDOWN_TICKS) {
            return;
        }
        lastAltarUse = gameTime;
        switch (state(data)) {
            case IDLE, LISTEN, FAIL -> beginTeach(level, data, gameTime);
            case COOLDOWN -> {
                long minutesLeft = Math.max(0L, data.cooldownUntil() - gameTime) / 1200L + 1L;
                player.displayClientMessage(ServerLang.tr(player,
                        "eclipse.resonance.caption.cooldown", minutesLeft), true);
            }
            case TEACH, FINALE -> { /* already performing */ }
        }
    }

    // ------------------------------------------------------------------ FAIL

    /** §6.4 dissonance sting + red flicker + input reset; melody survives 3 fails. */
    private static void fail(ServerLevel level, ResonanceFieldData data, long gameTime) {
        data.setFailCount(data.failCount() + 1);
        data.setProgressIndex(0);
        ResonanceFieldService.setHintCrystal(level, data, -1);
        Vec3 altar = altarCenter(data);
        if (altar != null) {
            // Minor-second double tone in the bass — short, ugly, unmistakable (§6.4).
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.NOTE_BLOCK_DIDGERIDOO,
                    SoundSource.BLOCKS, 1.2F, 0.53F);
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.NOTE_BLOCK_DIDGERIDOO,
                    SoundSource.BLOCKS, 1.2F, 0.56F);
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.AMETHYST_BLOCK_BREAK,
                    SoundSource.BLOCKS, 0.8F, 0.7F);
            FxPayloads.sendFxEvent(level, ResonanceCues.CUE_RESONANCE_FAIL, altar, 0.0F, 0.0F,
                    96.0D);
        }
        caption(level, data, "eclipse.resonance.caption.fail");
        enterState(level, data, State.FAIL, gameTime);
    }

    /** The delayed after-chime of the fail sting (2 ticks into FAIL, §6.4). */
    private static void failAfterChime(ServerLevel level, ResonanceFieldData data) {
        Vec3 altar = altarCenter(data);
        if (altar != null) {
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                    SoundSource.BLOCKS, 0.5F, 0.51F);
        }
    }

    // ------------------------------------------------------------------ FINALE

    /** {@code /dev woah resonance solve} — forces the §7.2 finale (FX/reward QA). */
    static void forceFinale(ServerLevel level, ResonanceFieldData data, long gameTime) {
        ResonanceFieldService.setHintCrystal(level, data, -1);
        beginFinale(level, data, gameTime);
    }

    /** t0 of the §7.2 direction: cue + shake; the beats ride {@link #tickFinale}. */
    private static void beginFinale(ServerLevel level, ResonanceFieldData data, long gameTime) {
        enterState(level, data, State.FINALE, gameTime);
        Vec3 altar = altarCenter(data);
        if (altar == null) {
            return;
        }
        FxPayloads.sendFxEvent(level, ResonanceCues.CUE_RESONANCE_FINALE, altar, 0.0F, 0.0F,
                256.0D);
        // One restrained shake, not an earthquake (ExpansionBorderFx.raiseFx school).
        PacketDistributor.sendToPlayersNear(level, null, altar.x, altar.y, altar.z, 64.0D,
                S2CShakePayload.shake(0.18F, 14));
    }

    /** Arpeggio flood (2-tick stagger) → chord (t24) → reward (t40) → swell (t60) → COOLDOWN. */
    private static void tickFinale(ServerLevel level, ResonanceFieldData data, long gameTime,
            long inState) {
        // §6.3.1 arpeggio: tone k sounds at t = 2k (deep → high wave through the valley).
        if (inState % 2 == 0L && inState < ResonanceTones.TONE_COUNT * 2L) {
            int tone = (int) (inState / 2L);
            int crystal = ResonanceFieldService.crystalOfTone(data, tone);
            if (crystal >= 0) {
                playCrystalNote(level, data, crystal, 1.2F);
                ResonanceFieldService.pulseCrystal(level, data, crystal);
            }
        }
        Vec3 altar = altarCenter(data);
        if (inState == FINALE_CHORD_TICK && altar != null) {
            // §6.3.2 the A-E-A-E fifth stack + resonate + sub-fundament.
            for (int tone : ResonanceTones.FINALE_CHORD) {
                int crystal = ResonanceFieldService.crystalOfTone(data, tone);
                if (crystal >= 0) {
                    playCrystalNote(level, data, crystal, 1.6F);
                }
            }
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.BLOCKS, 1.2F, 1.0F);
            level.playSound(null, altar.x, altar.y, altar.z, SoundEvents.BELL_RESONATE,
                    SoundSource.BLOCKS, 0.9F, 0.5F);
        }
        if (inState == FINALE_REWARD_TICK) {
            dropRewards(level, data);
        }
        if (inState == FINALE_SWELL_TICK && altar != null) {
            level.playSound(null, altar.x, altar.y, altar.z, EclipseSounds.EVENT_EMERGE.get(),
                    SoundSource.BLOCKS, 0.7F, 0.9F);
        }
        if (inState >= FINALE_TICKS) {
            data.incrementSolveCount();
            data.setFailCount(0);
            data.setProgressIndex(0);
            data.setCooldownUntil(gameTime + COOLDOWN_TICKS);
            enterState(level, data, State.COOLDOWN, gameTime);
        }
    }

    /** §7.3: 6 umbral shards at the altar, 300 XP split over the 9 crystal feet. */
    private static void dropRewards(ServerLevel level, ResonanceFieldData data) {
        Vec3 altar = altarCenter(data);
        if (altar == null) {
            return;
        }
        ItemEntity shards = new ItemEntity(level, altar.x, altar.y + 0.6D, altar.z,
                new ItemStack(EclipseItems.UMBRAL_SHARD.get(), SOLVE_REWARD_SHARDS));
        shards.setDefaultPickUpDelay();
        level.addFreshEntity(shards);
        List<ResonanceFieldData.Monolith> monoliths = data.monoliths();
        if (!monoliths.isEmpty()) {
            int xpEach = Math.max(1, SOLVE_REWARD_XP / monoliths.size());
            for (ResonanceFieldData.Monolith monolith : monoliths) {
                ExperienceOrb.award(level, Vec3.atBottomCenterOf(monolith.basePos.above()),
                        xpEach);
            }
        }
        boolean firstSolve = data.solveCount() == 0;
        if (firstSolve) {
            ItemEntity vitae = new ItemEntity(level, altar.x, altar.y + 0.8D, altar.z,
                    new ItemStack(EclipseItems.VITAE_SHARD.get()));
            vitae.setDefaultPickUpDelay();
            level.addFreshEntity(vitae);
            for (ServerPlayer player : level.getServer().getPlayerList().getPlayers()) {
                player.displayClientMessage(
                        ServerLang.tr(player, "eclipse.resonance.caption.first_solve"), false);
            }
        }
        // §7.3 stats hook: count the solve for every tracked player in the valley
        // (dynamic counter key, the shards_banked school — award wiring may come later).
        int day = AnalyticsService.currentDay(level.getServer());
        AnalyticsState analytics = AnalyticsState.get(level.getServer());
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceTo(altar) <= 64.0D && AnalyticsService.isTracked(player)) {
                analytics.add(day, player.getUUID(), "resonance_solved", 1L);
            }
        }
        EclipseMod.LOGGER.info("ResonanceField: melody solved (solve #{})", data.solveCount() + 1);
    }

    // ------------------------------------------------------------------ shared sound truth

    /**
     * §6.2 note layering at the crystal (bell + chime, both positional). The
     * {@code NOTE_BLOCK_*} constants are {@code Holder<SoundEvent>} in 1.21.1 Mojang
     * mappings — this uses the Holder overload of {@code Level.playSound} on purpose.
     */
    static void playCrystalNote(ServerLevel level, ResonanceFieldData data, int crystalIdx,
            float bellVolume) {
        ResonanceFieldData.Monolith monolith = data.monoliths().get(crystalIdx);
        Vec3 pos = crystalTop(data, crystalIdx);
        float pitch = ResonanceTones.pitch(monolith.toneIndex);
        level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.NOTE_BLOCK_BELL,
                SoundSource.BLOCKS, bellVolume, pitch);
        level.playSound(null, pos.x, pos.y, pos.z, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.BLOCKS, bellVolume * 0.6F, pitch);
    }

    /** The cue anchor at a crystal's top-mid (§3.6 position lane). */
    static Vec3 crystalTop(ResonanceFieldData data, int crystalIdx) {
        ResonanceFieldData.Monolith monolith = data.monoliths().get(crystalIdx);
        return new Vec3(monolith.basePos.getX() + 0.5D,
                monolith.basePos.getY() + monolith.height * 0.8D,
                monolith.basePos.getZ() + 0.5D);
    }

    // ------------------------------------------------------------------ helpers

    private static void enterState(ServerLevel level, ResonanceFieldData data, State state,
            long gameTime) {
        data.setState(state.ordinal(), gameTime);
        ResonanceFieldService.broadcastField(level, data);
    }

    /** LISTEN hint: the NEXT expected crystal holds a subtle shell glow (§7.4). */
    private static void hintExpected(ServerLevel level, ResonanceFieldData data) {
        int[] melody = data.melody();
        int progress = data.progressIndex();
        if (progress < melody.length) {
            ResonanceFieldService.setHintCrystal(level, data,
                    ResonanceFieldService.crystalOfTone(data, melody[progress]));
        }
    }

    private static boolean anyPlayerNearAltar(ServerLevel level, ResonanceFieldData data) {
        Vec3 altar = altarCenter(data);
        if (altar == null) {
            return false;
        }
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator()
                    && player.position().distanceTo(altar) <= TEACH_PLAYER_RADIUS) {
                return true;
            }
        }
        return false;
    }

    private static void caption(ServerLevel level, ResonanceFieldData data, String key) {
        Vec3 altar = altarCenter(data);
        if (altar == null) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceTo(altar) <= CAPTION_RADIUS) {
                player.displayClientMessage(ServerLang.tr(player, key), true);
            }
        }
    }

    private static void captionProgress(ServerLevel level, ResonanceFieldData data, int progress,
            int total) {
        Vec3 altar = altarCenter(data);
        if (altar == null) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceTo(altar) <= CAPTION_RADIUS) {
                player.displayClientMessage(ServerLang.tr(player,
                        "eclipse.resonance.caption.progress", progress, total), true);
            }
        }
    }

    @javax.annotation.Nullable
    private static Vec3 altarCenter(ResonanceFieldData data) {
        return data.altarPos() == null ? null : Vec3.atCenterOf(data.altarPos().above());
    }
}
