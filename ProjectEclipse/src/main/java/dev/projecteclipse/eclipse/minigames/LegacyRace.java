package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.network.protocol.game.ClientboundSetSubtitleTextPacket;
import net.minecraft.network.protocol.game.ClientboundSetTitleTextPacket;
import net.minecraft.network.protocol.game.ClientboundSetTitlesAnimationPacket;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * F-061: the race minigame (game id {@code race}, dimension {@code eclipse:minigame_sky}),
 * rebuilt as a Legacy-console style circuit race on the speedway laid out by
 * {@link RaceTrackBuilder}. It replaces the old "fly through floating rings" course, whose
 * entire ruleset was one endlessly repeating lap: no start procedure, no standings, no
 * finish, no way to lose.
 *
 * <p><b>Heat procedure</b>:</p>
 * <ol>
 *   <li><b>WAITING</b> — everybody forms up on the starting grid; the heat arms
 *       {@value #GRID_HOLD_MILLIS} ms after the first racer arrives, so late entrants can
 *       still make it onto the grid.</li>
 *   <li><b>COUNTDOWN</b> — the field is pinned to its grid slot, the gantry lamps light up
 *       row by row over 3-2-1 titles and rising ticks; lights out is GO.</li>
 *   <li><b>RUNNING</b> — the {@value #HUD_KEY} actionbar shows lap and live position. The
 *       seven checkpoint arches must be passed IN ORDER (segment-tested against the path
 *       actually run, so an ice-boosted racer cannot skip one between two samples) and
 *       crossing the start/finish line closes a lap. Falling off the circuit or into the
 *       river puts the racer back on their last checkpoint.</li>
 *   <li><b>Finish</b> — {@code raceLaps} laps land the podium title, the finish cue, the
 *       payout and a seat in the paddock. Once the winner is home the rest have
 *       {@code raceDnfSeconds} to make it; whoever is still out then is flagged DNF.</li>
 *   <li><b>COOLDOWN</b> — the result line, then the field is put back on the grid for the
 *       next heat while the event window lasts.</li>
 * </ol>
 *
 * <p>Broadcast lines carry times and positions only, never names (the anonymity rules);
 * each racer privately sees their own result.</p>
 */
public final class LegacyRace {

    /** Actionbar key of the live lap/position readout ("Runde 2/3 — Platz 1"). */
    private static final String HUD_KEY = "eclipse.minigame.race.hud";

    /** Grid forming window after the first racer arrives. */
    private static final long GRID_HOLD_MILLIS = 6_000L;
    /** Length of the lights-out countdown. */
    private static final int COUNTDOWN_SECONDS = 3;
    /** Podium/results window before the next heat forms up. */
    private static final long COOLDOWN_MILLIS = 12_000L;
    /** Detection margin around a checkpoint center for the segment test. */
    private static final double CHECKPOINT_RADIUS = 6.0D;
    /** Max checkpoints one 0.5 s sample may advance (the ice straights are fast). */
    private static final int MAX_HOPS_PER_SAMPLE = 2;
    /** Freeze duration re-applied every countdown tick. */
    private static final int FREEZE_TICKS = 40;
    /** Slow-falling grace after a checkpoint rescue. */
    private static final int RESCUE_SLOW_FALL_TICKS = 60;
    /** NEWFX-C3b finish-ribbon cue range around the start/finish gantry. */
    private static final double FINISH_CUE_RANGE = 128.0D;

    /** Heat phase (transient: a crash restarts the heat, the event window survives). */
    private enum Phase { WAITING, COUNTDOWN, RUNNING, COOLDOWN }

    private static Phase phase = Phase.WAITING;
    /** Epoch millis the current phase ends (grid hold, lights out, cooldown). */
    private static long phaseDeadline;
    private static long heatStartMillis;
    private static long firstFinishMillis;
    private static int lastCountdownShown;
    /** Lamps currently powered; {@code -1} forces the next write through. */
    private static int litLamps = -1;

    /** Last sampled position per racer — the anchor of the segment tested against a gate. */
    private static final Map<UUID, Vec3> LAST_POS = new HashMap<>();
    /** Racers that already finished or were flagged DNF in this heat. */
    private static final Set<UUID> RETIRED = new HashSet<>();
    /** Finish order of the CURRENT heat (1-based positions are indices + 1). */
    private static final List<UUID> HEAT_ORDER = new ArrayList<>();

    private LegacyRace() {}

    // ------------------------------------------------------------------ course plumbing

    /** The circuit of the current event instance (deterministic per seed). */
    public static RaceTrackBuilder.Track trackFor(int seed) {
        return RaceTrackBuilder.build(seed);
    }

    /** Block layout handed to the budgeted course writer. */
    public static List<CourseBlocks.Placement> layout(int seed) {
        return trackFor(seed).blocks();
    }

    /** Signboards, written once the budgeted build lands. */
    public static List<MinigameSigns.SignSpec> signs(int seed) {
        return trackFor(seed).signs();
    }

    /** Course bounds for the close-time entity sweep. */
    public static AABB bounds() {
        return RaceTrackBuilder.bounds();
    }

    /** Clears all transient heat state and the cached circuit (server stop / event close). */
    public static void resetTransient() {
        resetHeat();
        litLamps = -1;
        RaceTrackBuilder.invalidateCache();
    }

    private static void resetHeat() {
        phase = Phase.WAITING;
        phaseDeadline = 0L;
        heatStartMillis = 0L;
        firstFinishMillis = 0L;
        lastCountdownShown = 0;
        LAST_POS.clear();
        RETIRED.clear();
        HEAT_ORDER.clear();
    }

    // ------------------------------------------------------------------ entry & kit

    /**
     * The race "kit": no items at all — the circuit is run on foot — but a full food bar,
     * because a racer who entered hungry could not sprint a single meter. The ticket
     * restores their real hunger on exit anyway.
     */
    public static void giveKit(ServerPlayer player) {
        player.getFoodData().setFoodLevel(20);
        player.getFoodData().setSaturation(10.0F);
        player.setHealth(player.getMaxHealth());
        player.inventoryMenu.broadcastChanges();
    }

    /**
     * Places an entrant: on the starting grid while the heat is forming up, in the paddock
     * when a heat is already running (they sit out and join the next one).
     */
    public static void placeIntoRace(ServerLevel sky, MinigameState state, ServerPlayer player) {
        RaceTrackBuilder.Track track = trackFor(state.openCount());
        state.clearRacer(player.getUUID());
        HEAT_ORDER.remove(player.getUUID());
        if (phase == Phase.RUNNING) {
            RETIRED.add(player.getUUID());
            toPaddock(sky, track, player);
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.race.wait_next")
                    .withStyle(ChatFormatting.GRAY), false);
            return;
        }
        RETIRED.remove(player.getUUID());
        toGrid(sky, track, player, gridIndexFor(sky, player));
    }

    /** Grid slot of a single entrant — their index among everyone already in the sky dim. */
    private static int gridIndexFor(ServerLevel sky, ServerPlayer player) {
        int index = 0;
        for (ServerPlayer other : sky.players()) {
            if (other == player) {
                break;
            }
            index++;
        }
        return index;
    }

    private static void toGrid(ServerLevel sky, RaceTrackBuilder.Track track,
            ServerPlayer player, int slot) {
        List<Vec3> spots = track.gridSpots();
        teleport(sky, player, spots.get(Math.floorMod(slot, spots.size())), track.startYaw());
        player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.race.on_grid")
                .withStyle(ChatFormatting.AQUA), true);
    }

    private static void toPaddock(ServerLevel sky, RaceTrackBuilder.Track track,
            ServerPlayer player) {
        teleport(sky, player, track.paddock(), track.paddockYaw());
    }

    private static void teleport(ServerLevel sky, ServerPlayer player, Vec3 spot, float yaw) {
        player.teleportTo(sky, spot.x, spot.y, spot.z, yaw, 0.0F);
        player.setDeltaMovement(Vec3.ZERO);
        player.resetFallDistance();
        LAST_POS.remove(player.getUUID()); // a warp is not a path that was run
    }

    // ------------------------------------------------------------------ heat driver

    /** Per-service-tick (0.5 s) race driver. */
    public static void tick(MinecraftServer server, MinigameState state, List<ServerPlayer> racers) {
        ServerLevel sky = server.getLevel(MinigameDimensions.SKY);
        if (sky == null) {
            return;
        }
        RaceTrackBuilder.Track track = trackFor(state.openCount());
        long now = System.currentTimeMillis();

        Set<UUID> present = new HashSet<>();
        for (ServerPlayer racer : racers) {
            present.add(racer.getUUID());
        }
        LAST_POS.keySet().retainAll(present);
        RETIRED.retainAll(present);
        HEAT_ORDER.retainAll(present);

        if (racers.isEmpty()) {
            // Everybody left: abort the heat so the next entrant gets a clean grid.
            if (phase != Phase.WAITING || phaseDeadline != 0L) {
                EclipseMod.LOGGER.info("Race heat aborted — no racers left on the circuit");
                setStartLights(sky, track, 0);
                resetHeat();
            }
            return;
        }

        switch (phase) {
            case WAITING -> tickWaiting(sky, state, track, racers, now);
            case COUNTDOWN -> tickCountdown(sky, state, track, racers, now);
            case RUNNING -> tickRunning(server, sky, state, track, racers, now);
            case COOLDOWN -> {
                if (now >= phaseDeadline) {
                    formUpGrid(sky, state, track, racers);
                    armCountdown(now);
                }
            }
        }
    }

    private static void tickWaiting(ServerLevel sky, MinigameState state,
            RaceTrackBuilder.Track track, List<ServerPlayer> racers, long now) {
        if (phaseDeadline == 0L) {
            phaseDeadline = now + GRID_HOLD_MILLIS;
            setStartLights(sky, track, 0);
        }
        if (now >= phaseDeadline) {
            formUpGrid(sky, state, track, racers);
            armCountdown(now);
            return;
        }
        long secondsLeft = (phaseDeadline - now) / 1000L + 1L;
        for (ServerPlayer racer : racers) {
            racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.grid_wait",
                    secondsLeft, racers.size()).withStyle(ChatFormatting.YELLOW), true);
        }
    }

    private static void armCountdown(long now) {
        phase = Phase.COUNTDOWN;
        phaseDeadline = now + COUNTDOWN_SECONDS * 1000L;
        lastCountdownShown = COUNTDOWN_SECONDS + 1;
    }

    /** Puts every racer back on the grid and clears their heat bookkeeping. */
    private static void formUpGrid(ServerLevel sky, MinigameState state,
            RaceTrackBuilder.Track track, List<ServerPlayer> racers) {
        RETIRED.clear();
        HEAT_ORDER.clear();
        heatStartMillis = 0L;
        firstFinishMillis = 0L;
        int slot = 0;
        for (ServerPlayer racer : racers) {
            state.clearRacer(racer.getUUID());
            racer.removeAllEffects();
            racer.setRemainingFireTicks(0);
            giveKit(racer);
            toGrid(sky, track, racer, slot++);
        }
        setStartLights(sky, track, 0);
    }

    private static void tickCountdown(ServerLevel sky, MinigameState state,
            RaceTrackBuilder.Track track, List<ServerPlayer> racers, long now) {
        if (now >= phaseDeadline) {
            startHeat(sky, state, track, racers, now);
            return;
        }
        int secondsLeft = (int) Math.ceil((phaseDeadline - now) / 1000.0D);
        for (ServerPlayer racer : racers) {
            // Holding the grid: slowness 250 pins a racer in place without taking the view.
            racer.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN,
                    FREEZE_TICKS, 250, false, false, false));
        }
        if (secondsLeft >= lastCountdownShown) {
            return;
        }
        lastCountdownShown = secondsLeft;
        // Lamps light row by row: 3 → the first third, 1 → all of them, GO → all dark.
        setStartLights(sky, track, Mth.ceil((COUNTDOWN_SECONDS - secondsLeft + 1)
                * track.lightSwitches().size() / (double) COUNTDOWN_SECONDS));
        float pitch = 0.9F + 0.15F * (COUNTDOWN_SECONDS - secondsLeft);
        for (ServerPlayer racer : racers) {
            racer.connection.send(new ClientboundSetTitlesAnimationPacket(0, 15, 5));
            racer.connection.send(new ClientboundSetTitleTextPacket(
                    Component.literal(Integer.toString(secondsLeft))
                            .withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD)));
            racer.connection.send(new ClientboundSetSubtitleTextPacket(
                    ServerLang.tr(racer, "eclipse.minigame.race.title.get_ready")
                            .withStyle(ChatFormatting.GRAY)));
            racer.playNotifySound(EclipseSounds.UI_ROULETTE_TICK.get(),
                    SoundSource.PLAYERS, 0.9F, pitch);
        }
    }

    /** Lights out: releases the field and arms lap 1. */
    private static void startHeat(ServerLevel sky, MinigameState state,
            RaceTrackBuilder.Track track, List<ServerPlayer> racers, long now) {
        phase = Phase.RUNNING;
        phaseDeadline = 0L;
        heatStartMillis = now;
        firstFinishMillis = 0L;
        RETIRED.clear();
        HEAT_ORDER.clear();
        setStartLights(sky, track, 0);
        int totalLaps = MinigameConfig.get().raceLaps();
        for (ServerPlayer racer : racers) {
            racer.removeEffect(MobEffects.MOVEMENT_SLOWDOWN);
            state.setRaceProgress(racer.getUUID(), 1);
            state.setRaceLap(racer.getUUID(), 1);
            state.setRaceLapStart(racer.getUUID(), now);
            LAST_POS.remove(racer.getUUID());
            racer.connection.send(new ClientboundSetTitlesAnimationPacket(0, 20, 8));
            racer.connection.send(new ClientboundSetTitleTextPacket(
                    ServerLang.tr(racer, "eclipse.minigame.race.title.go")
                            .withStyle(ChatFormatting.GREEN, ChatFormatting.BOLD)));
            racer.connection.send(new ClientboundSetSubtitleTextPacket(
                    ServerLang.tr(racer, "eclipse.minigame.race.title.laps", totalLaps)
                            .withStyle(ChatFormatting.GRAY)));
            racer.playNotifySound(EclipseSounds.UI_UNLOCK_STING.get(),
                    SoundSource.PLAYERS, 0.9F, 1.0F);
        }
        EclipseMod.LOGGER.info("Race heat started: {} racer(s), {} lap(s), circuit {} blocks",
                racers.size(), totalLaps, (int) track.lapLength());
    }

    private static void tickRunning(MinecraftServer server, ServerLevel sky, MinigameState state,
            RaceTrackBuilder.Track track, List<ServerPlayer> racers, long now) {
        int gates = track.checkpoints().size();
        int totalLaps = MinigameConfig.get().raceLaps();
        List<ServerPlayer> active = new ArrayList<>();

        for (ServerPlayer racer : racers) {
            if (racer.isSpectator() || RETIRED.contains(racer.getUUID())) {
                continue;
            }
            active.add(racer);
            UUID uuid = racer.getUUID();

            if (racer.getY() < RaceTrackBuilder.FALL_RESCUE_Y) {
                respawnAtCheckpoint(server, state, racer);
                racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.fell")
                        .withStyle(ChatFormatting.AQUA), true);
                continue;
            }
            // Keep the food bar topped up: a race decided by hunger is not a race.
            racer.getFoodData().setFoodLevel(20);
            racer.getFoodData().setSaturation(6.0F);

            Vec3 current = racer.position();
            Vec3 previous = LAST_POS.put(uuid, current);
            if (previous == null) {
                previous = current;
            }
            for (int hop = 0; hop < MAX_HOPS_PER_SAMPLE; hop++) {
                int progress = Math.max(1, state.raceProgress(uuid));
                int target = progress % gates;
                Vec3 gate = track.checkpoints().get(target).center();
                if (distanceToSegment(gate, previous, current) > CHECKPOINT_RADIUS) {
                    break;
                }
                if (target == 0) {
                    if (closeLap(server, state, track, racer, now, totalLaps)) {
                        break; // finished — this racer takes no further gate this sample
                    }
                } else {
                    state.setRaceProgress(uuid, progress + 1);
                    racer.displayClientMessage(ServerLang.tr(racer,
                            "eclipse.minigame.race.checkpoint", target, gates - 1)
                            .withStyle(ChatFormatting.AQUA), true);
                    racer.playNotifySound(SoundEvents.EXPERIENCE_ORB_PICKUP,
                            SoundSource.PLAYERS, 0.8F, 1.4F);
                }
            }
        }

        showStandings(state, track, active, totalLaps);

        long dnfGrace = MinigameConfig.get().raceDnfSeconds() * 1000L;
        if (firstFinishMillis > 0L && now - firstFinishMillis >= dnfGrace) {
            for (ServerPlayer racer : List.copyOf(active)) {
                retire(sky, state, track, racer, true);
            }
        }
        if (active.stream().allMatch(racer -> RETIRED.contains(racer.getUUID()))) {
            finishHeat(server, state, now);
        }
    }

    /**
     * Crossing the start/finish line: banks the lap time and either arms the next lap or
     * finishes the racer.
     *
     * @return true when the racer has completed the whole race distance
     */
    private static boolean closeLap(MinecraftServer server, MinigameState state,
            RaceTrackBuilder.Track track, ServerPlayer racer, long now, int totalLaps) {
        UUID uuid = racer.getUUID();
        long lapStart = state.raceLapStart(uuid);
        long lapMillis = lapStart > 0L ? now - lapStart : 0L;
        boolean newBest = state.offerBestLap(lapMillis);
        int lap = Math.max(1, state.raceLap(uuid));

        racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.own_lap",
                lap, totalLaps, lapTime(lapMillis)).withStyle(ChatFormatting.GOLD), false);
        if (newBest) {
            broadcast(server, Component.translatable("eclipse.minigame.race.best_time",
                    lapTime(lapMillis)).withStyle(ChatFormatting.YELLOW));
        }

        if (lap >= totalLaps) {
            finishRacer(server, state, track, racer, now);
            return true;
        }
        state.setRaceLap(uuid, lap + 1);
        state.setRaceProgress(uuid, 1);
        state.setRaceLapStart(uuid, now);
        racer.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.7F, 1.6F);
        return false;
    }

    /** Podium handling for one finisher: title, cue, payout and a seat in the paddock. */
    private static void finishRacer(MinecraftServer server, MinigameState state,
            RaceTrackBuilder.Track track, ServerPlayer racer, long now) {
        UUID uuid = racer.getUUID();
        long total = heatStartMillis > 0L ? now - heatStartMillis : 0L;
        HEAT_ORDER.add(uuid);
        int position = HEAT_ORDER.size();
        state.addRaceFinisher(uuid);
        if (firstFinishMillis == 0L) {
            firstFinishMillis = now;
            broadcast(server, Component.translatable("eclipse.minigame.race.first_finish",
                    lapTime(total)).withStyle(ChatFormatting.GOLD));
        }

        // NEWFX-C3b: the checkered light-ribbon marks the GANTRY, not the racer — the
        // anonymity rules hold; a = the podium position (1 is the gold-burst variant).
        FxPayloads.sendFxEvent(racer.serverLevel(), FxCues.CUE_RACE_FINISH,
                track.checkpoints().get(0).center(), position, 0.0F, FINISH_CUE_RANGE);

        racer.connection.send(new ClientboundSetTitlesAnimationPacket(0, 50, 15));
        racer.connection.send(new ClientboundSetTitleTextPacket(
                ServerLang.tr(racer, position == 1
                                ? "eclipse.minigame.race.title.winner"
                                : "eclipse.minigame.race.title.finished", position)
                        .withStyle(position == 1 ? ChatFormatting.GOLD : ChatFormatting.YELLOW,
                                ChatFormatting.BOLD)));
        racer.connection.send(new ClientboundSetSubtitleTextPacket(
                ServerLang.tr(racer, "eclipse.minigame.race.title.total", lapTime(total))
                        .withStyle(ChatFormatting.GRAY)));
        racer.playNotifySound(SoundEvents.UI_TOAST_CHALLENGE_COMPLETE,
                SoundSource.PLAYERS, 0.9F, 1.0F);

        if (position <= 3) {
            MinigameConfig.Values config = MinigameConfig.get();
            int shards = config.podiumShards().get(position - 1);
            int xp = config.podiumSkillXp().get(position - 1);
            // FFIX-B: stable per-heat payout id (instance + heat start) — queue, then
            // claim before giving, so a crash replay can never double-pay this position.
            MinigameState.PendingPayout payout = new MinigameState.PendingPayout(
                    "minigame:race:" + state.openCount() + ":" + heatStartMillis
                            + ":place:" + position, shards, xp);
            state.queuePayout(uuid, payout);
            if (MinigameService.grantPayout(state, racer, payout)) {
                racer.displayClientMessage(ServerLang.tr(racer,
                        "eclipse.minigame.race.finish_position", position, shards, xp)
                        .withStyle(ChatFormatting.GOLD), false);
            }
        }
        retire(racer.serverLevel(), state, track, racer, false);
        EclipseMod.LOGGER.info("Race finish: position {} in {} over {} lap(s)",
                position, lapTime(total), MinigameConfig.get().raceLaps());
    }

    /** Parks a racer in the paddock — finished, or (with {@code dnf}) out of time. */
    private static void retire(ServerLevel sky, MinigameState state,
            RaceTrackBuilder.Track track, ServerPlayer racer, boolean dnf) {
        if (!RETIRED.add(racer.getUUID())) {
            return;
        }
        state.clearRacer(racer.getUUID());
        racer.removeAllEffects();
        racer.setHealth(racer.getMaxHealth());
        toPaddock(sky, track, racer);
        if (dnf) {
            racer.connection.send(new ClientboundSetTitlesAnimationPacket(0, 40, 10));
            racer.connection.send(new ClientboundSetTitleTextPacket(
                    ServerLang.tr(racer, "eclipse.minigame.race.title.dnf")
                            .withStyle(ChatFormatting.RED, ChatFormatting.BOLD)));
            racer.connection.send(new ClientboundSetSubtitleTextPacket(Component.empty()));
            racer.displayClientMessage(ServerLang.tr(racer, "eclipse.minigame.race.dnf")
                    .withStyle(ChatFormatting.RED), false);
            racer.playNotifySound(EclipseSounds.UI_TIMER_ZERO.get(),
                    SoundSource.PLAYERS, 0.8F, 1.0F);
        }
    }

    /** Heat over: the result line, then the cooldown before the next grid forms up. */
    private static void finishHeat(MinecraftServer server, MinigameState state, long now) {
        phase = Phase.COOLDOWN;
        phaseDeadline = now + COOLDOWN_MILLIS;
        long best = state.bestLapMillis();
        broadcast(server, Component.translatable("eclipse.minigame.race.heat_over",
                HEAT_ORDER.size(), best > 0L ? lapTime(best) : "--")
                .withStyle(ChatFormatting.GOLD));
        EclipseMod.LOGGER.info("Race heat over: {} finisher(s), best lap {}",
                HEAT_ORDER.size(), lapTime(best));
    }

    // ------------------------------------------------------------------ standings & rescue

    /** Live actionbar: {@code Runde 2/3 — Platz 1} for everyone still out on the circuit. */
    private static void showStandings(MinigameState state, RaceTrackBuilder.Track track,
            List<ServerPlayer> active, int totalLaps) {
        int gates = track.checkpoints().size();
        List<ServerPlayer> running = new ArrayList<>();
        for (ServerPlayer racer : active) {
            if (!RETIRED.contains(racer.getUUID())) {
                running.add(racer);
            }
        }
        running.sort(Comparator.comparingDouble(
                (ServerPlayer racer) -> raceScore(state, track, racer, gates)).reversed());
        int finishedAhead = HEAT_ORDER.size();
        for (int i = 0; i < running.size(); i++) {
            ServerPlayer racer = running.get(i);
            racer.displayClientMessage(ServerLang.tr(racer, HUD_KEY,
                    Mth.clamp(state.raceLap(racer.getUUID()), 1, totalLaps), totalLaps,
                    finishedAhead + i + 1).withStyle(ChatFormatting.AQUA), true);
        }
    }

    /** Monotonic progress score: gates passed, refined by closeness to the next gate. */
    private static double raceScore(MinigameState state, RaceTrackBuilder.Track track,
            ServerPlayer racer, int gates) {
        UUID uuid = racer.getUUID();
        int progress = Math.max(1, state.raceProgress(uuid));
        int lap = Math.max(1, state.raceLap(uuid));
        Vec3 gate = track.checkpoints().get(progress % gates).center();
        double distance = racer.position().distanceTo(gate);
        return (lap - 1) * (double) gates + progress
                - Mth.clamp(distance / 400.0D, 0.0D, 0.999D);
    }

    /**
     * Teleports a fallen racer back to their last passed checkpoint (or the grid, before
     * lights out), facing the next gate, with a short slow-falling grace.
     */
    public static void respawnAtCheckpoint(MinecraftServer server, MinigameState state,
            ServerPlayer racer) {
        ServerLevel sky = server.getLevel(MinigameDimensions.SKY);
        if (sky == null) {
            return;
        }
        RaceTrackBuilder.Track track = trackFor(state.openCount());
        if (phase != Phase.RUNNING || RETIRED.contains(racer.getUUID())) {
            if (phase == Phase.RUNNING) {
                toPaddock(sky, track, racer);
            } else {
                toGrid(sky, track, racer, gridIndexFor(sky, racer));
            }
            return;
        }
        int gates = track.checkpoints().size();
        int progress = Math.max(1, state.raceProgress(racer.getUUID()));
        RaceTrackBuilder.Checkpoint last = track.checkpoints().get((progress - 1) % gates);
        RaceTrackBuilder.Checkpoint next = track.checkpoints().get(progress % gates);
        Vec3 toNext = next.center().subtract(last.center());
        float yaw = toNext.lengthSqr() < 1.0E-6D ? last.yaw()
                : (float) Math.toDegrees(Math.atan2(-toNext.x, toNext.z));
        teleport(sky, racer, last.center(), yaw);
        racer.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                RESCUE_SLOW_FALL_TICKS, 0, false, false, true));
    }

    /**
     * A racer left the dimension (leave command, timeout, dev stop, admin teleport): drop
     * their heat bookkeeping so the standings and the "is anybody still out there" check
     * stay honest.
     */
    public static void onRacerLeft(MinigameState state, UUID uuid) {
        state.clearRacer(uuid);
        LAST_POS.remove(uuid);
        RETIRED.remove(uuid);
        HEAT_ORDER.remove(uuid);
    }

    /** Close-time summary: finisher count and the anonymized best lap of the instance. */
    public static void announceClosingSummary(MinecraftServer server, MinigameState state) {
        if (state.bestLapMillis() > 0L) {
            broadcast(server, Component.translatable("eclipse.minigame.race.closing_best",
                    state.raceFinishersSnapshot().size(), lapTime(state.bestLapMillis()))
                    .withStyle(ChatFormatting.GOLD));
        }
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Drives the gantry lamps. A redstone lamp placed lit without a power source is
     * switched off again by the first neighbour update, so the countdown powers the SWITCH
     * BLOCK above each lamp instead and lets vanilla redstone keep them honest.
     */
    private static void setStartLights(ServerLevel sky, RaceTrackBuilder.Track track, int count) {
        if (litLamps == count) {
            return;
        }
        litLamps = count;
        List<BlockPos> switches = track.lightSwitches();
        for (int i = 0; i < switches.size(); i++) {
            BlockPos pos = switches.get(i);
            if (!sky.isLoaded(pos)) {
                continue;
            }
            sky.setBlock(pos, i < count
                    ? Blocks.REDSTONE_BLOCK.defaultBlockState()
                    : Blocks.POLISHED_BLACKSTONE.defaultBlockState(), 3);
        }
    }

    /** Shortest distance from {@code point} to the segment {@code a → b}. */
    private static double distanceToSegment(Vec3 point, Vec3 a, Vec3 b) {
        Vec3 ab = b.subtract(a);
        double lengthSq = ab.lengthSqr();
        if (lengthSq < 1.0E-6D) {
            return point.distanceTo(a);
        }
        double u = Mth.clamp(point.subtract(a).dot(ab) / lengthSq, 0.0D, 1.0D);
        return point.distanceTo(a.add(ab.scale(u)));
    }

    /** {@code 01:23.456} time formatting (lap and total race times). */
    public static String lapTime(long millis) {
        long clamped = Math.max(0L, millis);
        return String.format(Locale.ROOT, "%02d:%02d.%03d",
                clamped / 60_000L, (clamped / 1000L) % 60L, clamped % 1000L);
    }

    private static void broadcast(MinecraftServer server, Component message) {
        // LANGAUDIT: bake per recipient so the mod locale decides the line.
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.sendSystemMessage(ServerLang.resolve(online, message));
        }
    }
}
