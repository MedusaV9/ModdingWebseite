package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.cutscene.SequenceReplayable;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * FINAL CREDITS SEQUENCE (plans_v5 C15, design IDEAS-backrooms_finale §B) — the day-14
 * ending. {@code FinaleRitual.tickVictory} calls {@link #begin} once the revive queue
 * drains, INSTEAD of {@code bringEveryoneHome} (the {@code creditsEnabled} common config
 * falls back to the old {@code finale_return} behavior).
 *
 * <p><b>Timeline</b> ({@code t} = server ticks since {@link #begin}, IDEAS §B1 table):</p>
 * <ol>
 *   <li>t=0 — fade to black (10t rise), {@code victory_theme} stops, the epilogue beach is
 *       pre-stamped while nobody can see it (warm chunks).</li>
 *   <li>t=40 — behind black: everyone teleported to the ghost-ship stern, the <b>helm
 *       double</b> (first online living player; the egg-offerer in spirit) posed on the poop
 *       deck at the block-display ship's wheel; the 140t {@code credits_helm} push-in plays
 *       (its own path event opens the shot from black).</li>
 *   <li>t=200 — fade WHITE, then the <b>disguised white loading screen</b>: portal-FX style
 *       {@code eclipse:credits_white} ({@code PortalTransitionController} holds white,
 *       {@code EclipseLoadingScreen} fakes a vanilla "Building terrain…" line) covers the
 *       teleport to the frozen-sunrise beach in {@code eclipse:epilogue}.</li>
 *   <li>t=300 — beach: {@code day_final} music cue, the right-side credits roll
 *       ({@code CreditsPanel}) and the <b>auto-run</b> east into the sunrise
 *       ({@code CreditsAutoRun} client input injection; a per-player server nudge watchdog
 *       catches crashed/vanilla clients).</li>
 *   <li>t=420 — massive lightning (6 offshore strikes, intensity 0.6→1.0) + 24 flying
 *       {@code BLOCK_DISPLAY} debris arcs overhead toward the sun (the run's greatest hits:
 *       ship planks, altar stone, disc basalt, amethyst).</li>
 *   <li>t=480 — title card "MINECRAFT ECLIPSE COMES BACK IN AVENGERS: DOOMSDAY"
 *       ({@code TitleCardLayer} glitch decode); t=650 burst (shockwave + white flash);
 *       t=665 the deadpan correction card "ECLIPSE : DOOMSDAY" (caption TITLE style).</li>
 *   <li>t=745 — fade to black, auto-run off; t=810 everyone is quietly moved home to the
 *       overworld spawn BEHIND the black (post-credits world state — a disconnect/restart
 *       from here on lands players at spawn, never on the set).</li>
 *   <li>t=1010 — final "ECLIPSE" card over black; t=1065 — {@code S2CCreditsClosePayload}
 *       (40t delay, nonce-guarded) → modded clients close themselves
 *       ({@code CreditsClient}); t=1205 — a DEDICATED server halts ({@code halt(false)}),
 *       stragglers/vanilla clients get a normal disconnect screen.</li>
 * </ol>
 *
 * <p><b>Failure-safety</b> (IDEAS §B5): the machine is purely time-driven (no beat can
 * wedge it); {@link CreditsData} persists started/completed/phase — a restart mid-sequence
 * skips to the end state and NEVER fires the close broadcast; joins/rejoins mid-run are
 * re-synced into the current beat; players left in the epilogue dimension by a crash are
 * returned to the overworld spawn at their next login. {@code /dev credits skip} jumps to
 * the fade-out beat with the close disabled (skip implies rehearsal).</p>
 *
 * <p><b>Replay</b>: registered as {@link SequenceReplayable} id {@code "credits"} —
 * {@code /eclipsefx sequence credits <PHASE>} replays each beat FX-only (no teleports, no
 * entities, no state writes, never a close).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CreditsSequence implements SequenceReplayable {
    // --- frozen ids ---
    private static final String SEQUENCE_ID = "credits";
    private static final String PATH_HELM = "credits_helm";
    /** Mirrors {@code PortalTransitionController.STYLE_CREDITS_WHITE} (client class — never referenced here). */
    private static final String STYLE_CREDITS_WHITE = "eclipse:credits_white";
    private static final String MUSIC_FINALE_CUE = "day_final";

    /** The one-shot epilogue dimension (frozen-sunrise beach; datapack JSONs). */
    public static final ResourceKey<Level> EPILOGUE = ResourceKey.create(Registries.DIMENSION,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "epilogue"));

    private static final String TITLE_DOOMSDAY = "eclipse.credits.title.doomsday";
    private static final String TITLE_CORRECTION = "eclipse.credits.title.correction";
    private static final String TITLE_ECLIPSE = "eclipse.credits.title.eclipse";

    // --- IDEAS §B1 tick table ---
    private static final int T_SHIP = 40;
    /** {@code credits_helm.json} runs 140t: t=40..180, whiteout rises 20t after handback. */
    private static final int T_WHITEOUT = 200;
    private static final int T_PORTAL = 230;
    private static final int T_EPILOGUE = 260;
    private static final int T_BEACH = 300;
    private static final int T_LIGHTNING = 420;
    private static final int LIGHTNING_STRIKES = 6;
    private static final int LIGHTNING_INTERVAL = 12;
    private static final int T_FLYERS_END = 560;
    private static final int T_TITLE = 480;
    private static final int T_BURST = 650;
    private static final int T_CORRECTION = 665;
    private static final int T_FADE_OUT = 745;
    private static final int T_HOME = 810;
    private static final int T_ECLIPSE_CARD = 1010;
    private static final int T_CLOSE = 1065;
    private static final int T_END = 1205;
    /** Close payload countdown on the client (broadcast at {@link #T_CLOSE}). */
    private static final int CLOSE_DELAY_TICKS = 40;
    /** Credits roll span: beach fade-in → just before the final ECLIPSE card. */
    private static final int ROLL_TICKS = T_ECLIPSE_CARD - T_BEACH - 10;

    // --- beach geometry (eclipse:epilogue; stamped once per run behind the black) ---
    /** Top sand layer Y; players walk on {@code +1}. */
    private static final int BEACH_Y = 63;
    private static final int BEACH_WEST_X = -24;
    /** Last sand column; water starts one block east. */
    private static final int BEACH_SAND_EAST_X = 96;
    private static final int BEACH_EAST_X = 150;
    private static final int BEACH_HALF_Z = 30;
    /** Run-lane rails (invisible barriers) — nobody drifts into the water sideways. */
    private static final int LANE_HALF_Z = 11;
    /** Runner start line. */
    private static final int START_X = -8;
    /** East heading (yaw of +X). */
    private static final float RUN_YAW = -90.0F;

    // --- flying debris displays ---
    private static final int FLYER_COUNT = 24;
    private static final String FLYER_TAG = "eclipse_credits_flyer";
    private static final String WHEEL_TAG = "eclipse_credits_wheel";
    /** The run's greatest hits: ship planks, altar stone, disc basalt, amethyst. */
    private static final BlockState[] FLYER_PALETTE = {
            Blocks.DARK_OAK_PLANKS.defaultBlockState(),
            Blocks.DARK_OAK_LOG.defaultBlockState(),
            Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState(),
            Blocks.DEEPSLATE_TILES.defaultBlockState(),
            Blocks.SMOOTH_BASALT.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.AMETHYST_BLOCK.defaultBlockState()};

    /** Server nudge watchdog (IDEAS §B2): stalled after this many ticks without progress. */
    private static final int NUDGE_STALL_TICKS = 20;
    private static final double NUDGE_BLOCKS_PER_TICK = 0.15D;

    private static final CreditsSequence INSTANCE = new CreditsSequence();
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** The single live run, or {@code null}. Server thread only. */
    @Nullable
    private static Run run;
    /** Tick scheduler for FX replays. Server thread only. */
    private static final List<Task> TASKS = new ArrayList<>();

    private CreditsSequence() {}

    // ------------------------------------------------------------------ wiring

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (REGISTERED.compareAndSet(false, true)) {
            SequenceReplayable.Registry.register(INSTANCE);
            EclipseMod.LOGGER.info("CreditsSequence registered (replay id '{}')", SEQUENCE_ID);
        }
    }

    /** Restart recovery: a world stopped mid-credits skips to the end state, never resumes. */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        CreditsData data = CreditsData.get(event.getServer());
        if (data.isStarted() && !data.isCompleted()) {
            EclipseMod.LOGGER.warn("CreditsSequence: world restarted mid-credits (phase {}) — skipping to end "
                    + "state; the close broadcast is NEVER fired after a restart", data.phase());
            data.setCompleted(true);
            data.setPhase("");
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        run = null;
        TASKS.clear();
    }

    // ------------------------------------------------------------------ the run

    /** Human-readable beat names for the persisted phase + FX replays. */
    private enum Phase { HELM, WHITEOUT, BEACH, LIGHTNING, TITLE, CORRECTION, OUTRO }

    private static final class Run {
        final MinecraftServer server;
        final int nonce;
        int ticks;
        /** Cleared by {@code skip()} — a skipped run never closes clients or halts. */
        boolean closeAllowed = true;
        /** The player posed at the wheel for the helm shot. */
        @Nullable
        UUID helmPlayer;
        @Nullable
        Display.BlockDisplay wheel;
        final List<Display.BlockDisplay> flyers = new ArrayList<>();
        /** Auto-run nudge watchdog state (per online player). */
        final Map<UUID, Double> lastX = new HashMap<>();
        final Map<UUID, Integer> stalled = new HashMap<>();

        Run(MinecraftServer server, int nonce) {
            this.server = server;
            this.nonce = nonce;
        }

        void enter(Phase phase) {
            CreditsData.get(this.server).setPhase(phase.name());
            EclipseMod.LOGGER.info("CreditsSequence: phase {} (t={})", phase, this.ticks);
        }
    }

    /**
     * Starts the final credits sequence for the whole server. The {@code FinaleRitual}
     * revive-drain hook: returns {@code false} ONLY when the {@code creditsEnabled} config
     * kill-switch is off (the caller falls back to the pre-credits trip home) or the
     * epilogue dimension is missing; an already-running sequence returns {@code true}
     * (the ending is being handled). A completed world logs and runs again anyway
     * (dev re-fires via {@code /dev credits start}).
     */
    public static boolean begin(MinecraftServer server) {
        if (!CreditsConfig.creditsEnabled()) {
            EclipseMod.LOGGER.info("CreditsSequence: creditsEnabled=false — falling back to the plain finale return");
            return false;
        }
        if (run != null) {
            EclipseMod.LOGGER.warn("CreditsSequence: already running (t={}) — ignoring begin()", run.ticks);
            return true;
        }
        ServerLevel epilogue = server.getLevel(EPILOGUE);
        if (epilogue == null) {
            EclipseMod.LOGGER.error("CreditsSequence: dimension {} is not loaded — falling back to the plain "
                    + "finale return", EPILOGUE.location());
            return false;
        }
        CreditsData data = CreditsData.get(server);
        if (data.isCompleted()) {
            EclipseMod.LOGGER.warn("CreditsSequence: this world already rolled credits — running again (dev re-fire)");
        }
        int nonce = ThreadLocalRandom.current().nextInt(1, Integer.MAX_VALUE);
        run = new Run(server, nonce);
        data.setStarted(true);
        data.setCompleted(false);
        data.setNonce(nonce);
        run.enter(Phase.HELM);

        // t=0: fade to black (held through the helm teleport at T_SHIP, released as the
        // push-in starts), victory theme out, and stamp the beach while nobody can see.
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendBegin(player, nonce);
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(10, 50, 25, 0xFF000000));
            MusicCues.stop(player);
        }
        stampBeach(epilogue);
        EclipseMod.LOGGER.info("CreditsSequence: started for {} player(s) (nonce {})",
                server.getPlayerList().getPlayerCount(), nonce);
        return true;
    }

    /** Whether the credits phase machine is currently live. */
    public static boolean isRunning() {
        return run != null;
    }

    /**
     * GAMEMASTER skip (IDEAS §B5): jump straight to the fade-out beat. The music finale
     * still plays, but the close broadcast and the server halt are disabled — a skip
     * implies rehearsal. Returns {@code false} while no run is live.
     */
    public static boolean skip(MinecraftServer server) {
        Run current = run;
        if (current == null) {
            return false;
        }
        current.closeAllowed = false;
        if (current.ticks < T_FADE_OUT) {
            discardWheel(current);
            discardFlyers(current);
            current.ticks = T_FADE_OUT - 1; // the next tick executes the fade-out beat
        }
        EclipseMod.LOGGER.info("CreditsSequence: skipped to the outro (close disabled)");
        return true;
    }

    // ------------------------------------------------------------------ tick machine

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        tickScheduler(event.getServer());
        Run current = run;
        if (current == null) {
            return;
        }
        current.ticks++;
        int t = current.ticks;
        switch (t) {
            case T_SHIP -> beatShip(current);
            case T_WHITEOUT -> beatWhiteout(current);
            case T_PORTAL -> beatPortal(current);
            case T_EPILOGUE -> beatEpilogue(current);
            case T_BEACH -> beatBeach(current);
            case T_TITLE -> beatTitle(current);
            case T_BURST -> beatBurst(current);
            case T_CORRECTION -> beatCorrection(current);
            case T_FADE_OUT -> beatFadeOut(current);
            case T_HOME -> beatHome(current);
            case T_ECLIPSE_CARD -> beatEclipseCard(current);
            case T_CLOSE -> beatClose(current);
            case T_END -> beatEnd(current);
            default -> { }
        }
        // Overlapping continuous work.
        if (t >= T_LIGHTNING && t <= T_LIGHTNING + (LIGHTNING_STRIKES - 1) * LIGHTNING_INTERVAL
                && (t - T_LIGHTNING) % LIGHTNING_INTERVAL == 0) {
            int index = (t - T_LIGHTNING) / LIGHTNING_INTERVAL;
            beatLightningStrike(current, index);
        }
        if (t >= T_LIGHTNING && t <= T_FLYERS_END && (t - T_LIGHTNING) % 2 == 0) {
            animateFlyers(current, t);
        }
        if (t == T_FLYERS_END) {
            discardFlyers(current);
        }
        if (t > T_BEACH && t < T_FADE_OUT) {
            nudgeStalledRunners(current);
        }
    }

    // ------------------------------------------------------------------ beats

    /** t=40 — behind black: crew to the ship stern, helm double posed, push-in plays. */
    private static void beatShip(Run current) {
        MinecraftServer server = current.server;
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("CreditsSequence: limbo missing — skipping the helm shot");
            current.ticks = T_WHITEOUT - 1;
            return;
        }
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        List<ServerPlayer> online = new ArrayList<>(server.getPlayerList().getPlayers());
        int placed = 0;
        for (ServerPlayer player : online) {
            if (player.isSpectator()) {
                continue;
            }
            if (current.helmPlayer == null) {
                // The helm double: first online living player (the egg-offerer in spirit —
                // FinaleRitual does not record the ritual starter; IDEAS §B1 fallback).
                current.helmPlayer = player.getUUID();
                player.teleportTo(limbo, -18.5D, deckY + 7, 0.5D, RUN_YAW, 4.0F);
            } else {
                // Crew behind the sterncastle on the main deck (FinaleRitual deckSpot spread).
                int x = 2 + 2 * (placed % 3);
                int z = placed / 3 % 3 - 1;
                placed++;
                player.teleportTo(limbo, x + 0.5D, deckY + 1, z + 0.5D, RUN_YAW, 0.0F);
            }
        }
        spawnWheel(current, limbo, deckY);
        // Everyone is already on the ship: LOCAL play, world-anchored at the helm double.
        // play() installs its OWN freeze and releases it on the flight-end ACK — the
        // callback re-locks everyone (survives-dimension-change) so nobody wanders off
        // the deck behind the whiteout; beatEpilogue's transport re-anchors that lock.
        CutsceneService.play(PATH_HELM, online, new Vec3(-18.5D, deckY + 7, 0.5D),
                CreditsSequence::refreezeAfterHelmShot, CutsceneService.PlayOptions.LOCAL);
    }

    /** Flight-end callback: keep everyone posed until the beach releases them. */
    private static void refreezeAfterHelmShot() {
        Run current = run;
        if (current == null || current.ticks >= T_EPILOGUE) {
            return;
        }
        int ttl = T_BEACH - current.ticks + 20;
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            if (!player.isSpectator()) {
                FreezeService.freeze(player, ttl, true, 0);
            }
        }
    }

    /** t=200 — the shot is over: rise to white and hold (the fade hands over to the portal FX). */
    private static void beatWhiteout(Run current) {
        current.enter(Phase.WHITEOUT);
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(30, 40, 20, 0xFFFFFFFF));
    }

    /** t=230 — the disguised white loading screen arms (covers the dimension teleport). */
    private static void beatPortal(Run current) {
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(
                    S2CPortalFxPayload.Phase.ENTER, STYLE_CREDITS_WHITE, 60));
        }
    }

    /** t=260 — behind the white: everyone to the frozen-sunrise beach, facing east. */
    private static void beatEpilogue(Run current) {
        MinecraftServer server = current.server;
        ServerLevel epilogue = server.getLevel(EPILOGUE);
        if (epilogue == null) {
            EclipseMod.LOGGER.error("CreditsSequence: epilogue dimension vanished mid-run — sending everyone home");
            current.ticks = T_FADE_OUT - 1;
            return;
        }
        discardWheel(current);
        List<ServerPlayer> online = server.getPlayerList().getPlayers();
        int placed = 0;
        for (ServerPlayer player : online) {
            if (player.isSpectator()) {
                continue;
            }
            double z = Math.max(-LANE_HALF_Z + 1, Math.min(LANE_HALF_Z - 1, 2 * (placed - online.size() / 2)));
            placed++;
            // transport (not teleportTo): the helm freeze is still live — this re-anchors
            // the lock at the beach so the rubber-band never yanks anyone back to limbo.
            FreezeService.transport(player, epilogue,
                    new Vec3(START_X + 0.5D, BEACH_Y + 1, z + 0.5D), RUN_YAW, 6.0F);
            player.setDeltaMovement(Vec3.ZERO);
            player.fallDistance = 0.0F;
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} player(s) on the epilogue beach", placed);
    }

    /** t=300 — sunrise: the helm freeze releases, music finale, credits roll, auto-run east. */
    private static void beatBeach(Run current) {
        current.enter(Phase.BEACH);
        current.lastX.clear();
        current.stalled.clear();
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            FreezeService.unfreeze(player); // the refreezeAfterHelmShot lock ends here
            MusicCues.play(MUSIC_FINALE_CUE, player);
            CreditsPayloads.sendRoll(player, ROLL_TICKS);
            CreditsPayloads.sendAutoRun(player, true, RUN_YAW, T_FADE_OUT - T_BEACH + 100);
        }
    }

    /** One offshore strike of the t=420 lightning beat, intensity 0.6→1.0 (IDEAS §B1). */
    private static void beatLightningStrike(Run current, int index) {
        if (index == 0) {
            current.enter(Phase.LIGHTNING);
            spawnFlyers(current);
        }
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        float intensity = 0.6F + 0.4F * index / Math.max(1, LIGHTNING_STRIKES - 1);
        double x = BEACH_SAND_EAST_X + 4 + epilogue.random.nextInt(24);
        double z = epilogue.random.nextInt(2 * LANE_HALF_Z * 2) - LANE_HALF_Z * 2;
        Vec3 impact = new Vec3(x, BEACH_Y + 1, z);
        FxPayloads.sendFxEvent(epilogue, FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F, -1.0D);
        LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(epilogue);
        if (bolt != null) {
            bolt.moveTo(impact);
            bolt.setVisualOnly(true);
            epilogue.addFreshEntity(bolt);
        }
        for (ServerPlayer player : epilogue.players()) {
            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                    0.7F + 0.5F * intensity, 0.85F + epilogue.random.nextFloat() * 0.15F);
        }
    }

    /** t=480 — the doomsday card decodes ({@code TitleCardLayer}). */
    private static void beatTitle(Run current) {
        current.enter(Phase.TITLE);
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendTitle(player, TITLE_DOOMSDAY, 70);
        }
    }

    /** t=650 — burst: shockwave + white flash (the intro-BURST mirror). */
    private static void beatBurst(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue != null) {
            Vec3 center = runnersCenter(epilogue);
            FxPayloads.sendFxEvent(epilogue, FxPayloads.FX_SHOCKWAVE, center, 1.0F, 50.0F, -1.0D);
        }
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(8, 6, 10, 0xFFFFFFFF));
    }

    /** t=665 — the deadpan legal-department correction ({@code CaptionRenderer} TITLE style). */
    private static void beatCorrection(Run current) {
        current.enter(Phase.CORRECTION);
        PacketDistributor.sendToAllPlayers(
                new S2CCaptionPayload(TITLE_CORRECTION, 80, S2CCaptionPayload.STYLE_TITLE));
    }

    /** t=745 — fade to black, auto-run releases; the music finale keeps playing. */
    private static void beatFadeOut(Run current) {
        current.enter(Phase.OUTRO);
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendAutoRun(player, false, RUN_YAW, 0);
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(60, 600, 0, 0xFF000000));
        }
        discardFlyers(current);
    }

    /**
     * t=810 — behind the black: everyone home to the overworld spawn (the post-credits
     * world state; {@code bringEveryoneHome}'s deterministic spread). The black cover is
     * re-sent AFTER the hop so the arrival is never visible.
     */
    private static void beatHome(Run current) {
        MinecraftServer server = current.server;
        ServerLevel overworld = server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            // A skip() jumps time — the helm re-freeze may still be live; never teleport
            // a rubber-banded player (the lock would yank them back to the beach anchor).
            FreezeService.unfreeze(player);
            if (!player.level().dimension().equals(EPILOGUE)) {
                continue;
            }
            BlockPos column = spawn.offset(2 * (returned % 5 - 2), 0, 2 * (returned / 5 % 5 - 2));
            int y = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                    column.getX(), column.getZ());
            player.teleportTo(overworld, column.getX() + 0.5D, y, column.getZ() + 0.5D,
                    overworld.getSharedSpawnAngle(), 0.0F);
            returned++;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(0, 600, 0, 0xFF000000));
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} player(s) brought home behind the black", returned);
    }

    /** t=1010 — the single "ECLIPSE" card over black. */
    private static void beatEclipseCard(Run current) {
        PacketDistributor.sendToAllPlayers(
                new S2CCaptionPayload(TITLE_ECLIPSE, 90, S2CCaptionPayload.STYLE_TITLE));
    }

    /**
     * t=1065 — the close broadcast. Completion is persisted FIRST so a crash between here
     * and the halt can never replay the sequence; a skipped (rehearsal) run sends nothing.
     */
    private static void beatClose(Run current) {
        CreditsData data = CreditsData.get(current.server);
        data.setCompleted(true);
        data.setPhase("");
        if (!current.closeAllowed) {
            EclipseMod.LOGGER.info("CreditsSequence: close suppressed (skip/rehearsal)");
            return;
        }
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendClose(player, CLOSE_DELAY_TICKS, current.nonce);
        }
        EclipseMod.LOGGER.info("CreditsSequence: close broadcast sent (delay {}t, nonce {})",
                CLOSE_DELAY_TICKS, current.nonce);
    }

    /** t=1205 — the end: a dedicated server halts; otherwise the fade releases gently. */
    private static void beatEnd(Run current) {
        MinecraftServer server = current.server;
        CreditsData data = CreditsData.get(server);
        data.setCompleted(true);
        data.setPhase("");
        run = null;
        if (current.closeAllowed && server.isDedicatedServer()) {
            EclipseMod.LOGGER.info("CreditsSequence: the crossing is over — halting the server");
            server.halt(false);
            return;
        }
        // Rehearsal / integrated server: hand the screen back instead of dying.
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(0, 20, 60, 0xFF000000));
            CreditsPayloads.sendRoll(player, 0);
        }
        EclipseMod.LOGGER.info("CreditsSequence: complete (no halt — {})",
                current.closeAllowed ? "integrated server" : "skip/rehearsal");
    }

    // ------------------------------------------------------------------ auto-run watchdog

    /**
     * IDEAS §B2 server safety net: any runner whose x has not advanced for
     * {@value #NUDGE_STALL_TICKS} ticks (crashed/vanilla client, AFK) is nudged
     * {@value #NUDGE_BLOCKS_PER_TICK} blocks/t east so the wide shot never shows a statue.
     */
    private static void nudgeStalledRunners(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        for (ServerPlayer player : epilogue.players()) {
            if (player.isSpectator()) {
                continue;
            }
            UUID id = player.getUUID();
            double x = player.getX();
            Double last = current.lastX.put(id, x);
            if (last == null) {
                continue;
            }
            if (x - last < 0.01D) {
                int stalledFor = current.stalled.merge(id, 1, Integer::sum);
                if (stalledFor >= NUDGE_STALL_TICKS && x < BEACH_SAND_EAST_X - 4) {
                    player.teleportTo(epilogue, x + NUDGE_BLOCKS_PER_TICK, player.getY(), player.getZ(),
                            RUN_YAW, player.getXRot());
                    current.lastX.put(id, x + NUDGE_BLOCKS_PER_TICK);
                }
            } else {
                current.stalled.put(id, 0);
            }
        }
    }

    // ------------------------------------------------------------------ props: wheel + flyers

    /** The ship's wheel: one block-display trapdoor stood upright on the poop deck. */
    private static void spawnWheel(Run current, ServerLevel limbo, int deckY) {
        Display.BlockDisplay wheel = EntityType.BLOCK_DISPLAY.create(limbo);
        if (wheel == null) {
            return;
        }
        wheel.moveTo(-17.4D, deckY + 7.1D, 0.5D, 0.0F, 0.0F);
        wheel.setBlockState(Blocks.DARK_OAK_TRAPDOOR.defaultBlockState());
        wheel.addTag(WHEEL_TAG);
        // Stand the flat trapdoor upright in the YZ plane (facing the helmsman, +X) and
        // spin it 45° like a wheel caught mid-turn; centered on its anchor.
        Quaternionf rotation = new Quaternionf()
                .rotationZ((float) Math.toRadians(90.0D))
                .rotateY((float) Math.toRadians(45.0D));
        Vector3f half = new Vector3f(0.55F, 0.55F, 0.55F);
        Vector3f translation = new Vector3f(0.0F, 0.0F, 0.0F).sub(rotation.transform(half, new Vector3f()));
        wheel.setTransformationInterpolationDelay(0);
        wheel.setTransformationInterpolationDuration(0);
        wheel.setTransformation(new Transformation(translation, rotation,
                new Vector3f(1.1F, 1.1F, 1.1F), new Quaternionf()));
        limbo.addFreshEntity(wheel);
        current.wheel = wheel;
    }

    private static void discardWheel(Run current) {
        if (current.wheel != null) {
            current.wheel.discard();
            current.wheel = null;
        }
    }

    /** Launches the debris arcs behind the runners (anchored at each arc's apex column). */
    private static void spawnFlyers(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue == null) {
            return;
        }
        Vec3 center = runnersCenter(epilogue);
        for (int i = 0; i < FLYER_COUNT; i++) {
            Display.BlockDisplay flyer = EntityType.BLOCK_DISPLAY.create(epilogue);
            if (flyer == null) {
                continue;
            }
            double apexX = center.x + 10.0D + hash01(i, 1) * 20.0D;
            double apexY = BEACH_Y + 14.0D + hash01(i, 2) * 16.0D;
            double z = center.z + (hash01(i, 3) * 2.0D - 1.0D) * (LANE_HALF_Z + 6.0D);
            flyer.moveTo(apexX, apexY, z, 0.0F, 0.0F);
            flyer.setBlockState(FLYER_PALETTE[(int) (hash01(i, 4) * FLYER_PALETTE.length) % FLYER_PALETTE.length]);
            flyer.addTag(FLYER_TAG);
            flyer.setTransformationInterpolationDelay(0);
            flyer.setTransformationInterpolationDuration(0);
            flyer.setTransformation(flyerPose(i, 0.0F));
            epilogue.addFreshEntity(flyer);
            current.flyers.add(flyer);
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} debris flyer(s) launched", current.flyers.size());
    }

    /** Interpolated transform push every 2 ticks (FloatingDecor transport pattern). */
    private static void animateFlyers(Run current, int t) {
        if (current.flyers.isEmpty()) {
            return;
        }
        float progress = (t - T_LIGHTNING) / (float) (T_FLYERS_END - T_LIGHTNING);
        for (int i = 0; i < current.flyers.size(); i++) {
            Display.BlockDisplay flyer = current.flyers.get(i);
            if (flyer.isRemoved()) {
                continue;
            }
            flyer.setTransformationInterpolationDelay(0);
            flyer.setTransformationInterpolationDuration(2);
            flyer.setTransformation(flyerPose(i, Math.min(1.0F, progress + 2.0F / (T_FLYERS_END - T_LIGHTNING))));
        }
    }

    /**
     * Absolute pose of one debris fragment at arc progress 0..1: a west→east ballistic arc
     * through the apex anchor (translation ±~38 blocks, parabolic height) with a steady
     * tumble — everything deterministic per index, so replays and re-pushes always agree.
     */
    private static Transformation flyerPose(int index, float progress) {
        float speedJitter = 0.85F + (float) hash01(index, 5) * 0.3F;
        float u = Math.min(1.0F, progress * speedJitter) * 2.0F - 1.0F; // -1 → +1 along the arc
        float xOff = u * (30.0F + (float) hash01(index, 6) * 10.0F);
        float arcHeight = 10.0F + (float) hash01(index, 7) * 8.0F;
        float yOff = -arcHeight * u * u; // 0 at the apex, -h at both ends
        float spin = (float) (hash01(index, 8) * Math.PI * 2.0D
                + progress * (2.0D + hash01(index, 9) * 4.0D) * Math.PI);
        Vector3f axis = new Vector3f(
                (float) (hash01(index, 10) * 2.0D - 1.0D),
                (float) (0.4D + hash01(index, 11)),
                (float) (hash01(index, 12) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        float scale = 0.5F + (float) hash01(index, 13) * 0.8F;
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        Vector3f translation = new Vector3f(xOff, yOff, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale, scale, scale), new Quaternionf());
    }

    private static void discardFlyers(Run current) {
        for (Display.BlockDisplay flyer : current.flyers) {
            flyer.discard();
        }
        current.flyers.clear();
    }

    // ------------------------------------------------------------------ beach stamp

    /**
     * Stamps the epilogue beach set (idempotent — pure {@code setBlock} of the same shape):
     * a sand strip with 2% {@code suspicious_sand} nothing-burgers, a water plane east
     * toward the frozen sunrise, an outer barrier rim that contains the water, and barrier
     * run-lane rails at z ±{@value #LANE_HALF_Z}. Flag {@code UPDATE_CLIENTS} only — no
     * neighbor updates, nothing to react anyway in a void dimension.
     */
    private static void stampBeach(ServerLevel epilogue) {
        long start = System.nanoTime();
        BlockState sand = Blocks.SAND.defaultBlockState();
        BlockState suspicious = Blocks.SUSPICIOUS_SAND.defaultBlockState();
        BlockState water = Blocks.WATER.defaultBlockState();
        BlockState barrier = Blocks.BARRIER.defaultBlockState();
        for (int x = BEACH_WEST_X; x <= BEACH_EAST_X; x++) {
            for (int z = -BEACH_HALF_Z; z <= BEACH_HALF_Z; z++) {
                // Base slab under everything (also the sea floor).
                for (int y = BEACH_Y - 3; y <= BEACH_Y - 1; y++) {
                    set(epilogue, x, y, z, sand);
                }
                boolean rim = x == BEACH_WEST_X || x == BEACH_EAST_X || Math.abs(z) == BEACH_HALF_Z;
                if (x <= BEACH_SAND_EAST_X) {
                    set(epilogue, x, BEACH_Y, z, hash01(x * 31 + z, 15) < 0.02D ? suspicious : sand);
                } else {
                    set(epilogue, x, BEACH_Y, z, rim ? barrier : water);
                }
                if (rim) {
                    for (int y = BEACH_Y + 1; y <= BEACH_Y + 3; y++) {
                        set(epilogue, x, y, z, barrier);
                    }
                }
            }
            // Run-lane rails over the sand (invisible; keep the line together).
            if (x <= BEACH_SAND_EAST_X) {
                for (int y = BEACH_Y + 1; y <= BEACH_Y + 2; y++) {
                    set(epilogue, x, y, LANE_HALF_Z, barrier);
                    set(epilogue, x, y, -LANE_HALF_Z, barrier);
                }
            }
        }
        EclipseMod.LOGGER.info("CreditsSequence: epilogue beach stamped in {} ms",
                (System.nanoTime() - start) / 1_000_000L);
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.getChunk(x >> 4, z >> 4); // force-load (GhostShipBuilder pattern)
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_CLIENTS);
    }

    /** Average runner position on the beach (fallback: the start line). */
    private static Vec3 runnersCenter(ServerLevel epilogue) {
        double x = 0.0D;
        double z = 0.0D;
        int count = 0;
        for (ServerPlayer player : epilogue.players()) {
            if (!player.isSpectator()) {
                x += player.getX();
                z += player.getZ();
                count++;
            }
        }
        return count == 0 ? new Vec3(START_X, BEACH_Y + 1, 0.0D)
                : new Vec3(x / count, BEACH_Y + 1, z / count);
    }

    // ------------------------------------------------------------------ join / rejoin safety

    /**
     * Mid-run joins are folded into the current beat (nonce + fade + roll/auto-run); a
     * player a crash left in the epilogue dimension AFTER the run is returned to the
     * overworld spawn ({@code PendingReturns} covers cutscene teleports, this covers the
     * scripted epilogue hop).
     */
    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        Run current = run;
        if (current == null) {
            if (player.level().dimension().equals(EPILOGUE)) {
                MinecraftServer server = player.server;
                ServerLevel overworld = server.overworld();
                BlockPos spawn = overworld.getSharedSpawnPos();
                int y = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        spawn.getX(), spawn.getZ());
                player.teleportTo(overworld, spawn.getX() + 0.5D, y, spawn.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
                EclipseMod.LOGGER.info("CreditsSequence: {} rescued from the epilogue set at login",
                        player.getScoreboardName());
            }
            return;
        }
        CreditsPayloads.sendBegin(player, current.nonce);
        int t = current.ticks;
        if (t < T_EPILOGUE) {
            // Held black until just past the epilogue teleport, then released — the beach
            // beat (roll + auto-run) still reaches this player because it broadcasts.
            PacketDistributor.sendToPlayer(player,
                    new S2CScreenFadePayload(0, Math.max(20, T_EPILOGUE + 20 - t), 30, 0xFF000000));
        } else if (t < T_FADE_OUT) {
            if (t >= T_BEACH) {
                MusicCues.play(MUSIC_FINALE_CUE, player);
                CreditsPayloads.sendRoll(player, Math.max(40, ROLL_TICKS - (t - T_BEACH)));
                CreditsPayloads.sendAutoRun(player, true, RUN_YAW, T_FADE_OUT - t + 100);
            }
        } else {
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(0, 600, 0, 0xFF000000));
        }
    }

    // ------------------------------------------------------------------ replay (FX-only)

    @Override
    public String sequenceId() {
        return SEQUENCE_ID;
    }

    @Override
    public List<String> phaseIds() {
        return List.of("HELM", "WHITEOUT", "BEACH", "LIGHTNING", "TITLE", "CORRECTION", "OUTRO");
    }

    /**
     * FX-only replays (R12 contract): fades, cards, captions, camera path and sounds like
     * the live beats — but LOCAL plays only, no teleports, no entities, no block writes, no
     * {@link CreditsData} commits and NEVER a close broadcast.
     */
    @Override
    public boolean replay(MinecraftServer server, String phaseId, Collection<ServerPlayer> players) {
        List<ServerPlayer> watchers = List.copyOf(players);
        switch (phaseId.toUpperCase(Locale.ROOT)) {
            case "HELM" -> {
                Vec3 anchor = watchers.isEmpty() ? Vec3.ZERO : watchers.get(0).position();
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(10, 40, 0, 0xFF000000));
                }
                schedule(server, 30, () -> CutsceneService.play(PATH_HELM, watchers, anchor, null,
                        CutsceneService.PlayOptions.LOCAL));
                return true;
            }
            case "WHITEOUT" -> {
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(30, 40, 20, 0xFFFFFFFF));
                    GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(
                            S2CPortalFxPayload.Phase.ENTER, STYLE_CREDITS_WHITE, 40));
                }
                return true;
            }
            case "BEACH" -> {
                for (ServerPlayer player : watchers) {
                    MusicCues.play(MUSIC_FINALE_CUE, player);
                    CreditsPayloads.sendRoll(player, 400);
                }
                return true;
            }
            case "LIGHTNING" -> {
                for (int i = 0; i < LIGHTNING_STRIKES; i++) {
                    int index = i;
                    schedule(server, i * LIGHTNING_INTERVAL, () -> {
                        float intensity = 0.6F + 0.4F * index / (LIGHTNING_STRIKES - 1);
                        for (ServerPlayer player : watchers) {
                            if (player.hasDisconnected()) {
                                continue;
                            }
                            Vec3 impact = player.position().add(30.0D + index * 8.0D, 0.0D,
                                    (index % 2 == 0 ? 1 : -1) * (6.0D + index * 3.0D));
                            PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                                    .S2CFxEventPayload(FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F));
                            player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER,
                                    SoundSource.WEATHER, 0.7F + 0.5F * intensity, 0.9F);
                        }
                    });
                }
                return true;
            }
            case "TITLE" -> {
                for (ServerPlayer player : watchers) {
                    CreditsPayloads.sendTitle(player, TITLE_DOOMSDAY, 70);
                }
                return true;
            }
            case "CORRECTION" -> {
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(8, 6, 10, 0xFFFFFFFF));
                    PacketDistributor.sendToPlayer(player,
                            new S2CCaptionPayload(TITLE_CORRECTION, 80, S2CCaptionPayload.STYLE_TITLE));
                }
                return true;
            }
            case "OUTRO" -> {
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(60, 300, 40, 0xFF000000));
                }
                schedule(server, 200, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player,
                                    new S2CCaptionPayload(TITLE_ECLIPSE, 90, S2CCaptionPayload.STYLE_TITLE));
                        }
                    }
                });
                return true;
            }
            default -> {
                return false;
            }
        }
    }

    // ------------------------------------------------------------------ scheduler (replays)

    private record Task(long dueTick, Runnable action) {}

    private static void schedule(MinecraftServer server, int delayTicks, Runnable action) {
        TASKS.add(new Task(server.getTickCount() + Math.max(0, delayTicks), action));
    }

    private static void tickScheduler(MinecraftServer server) {
        if (TASKS.isEmpty()) {
            return;
        }
        long now = server.getTickCount();
        List<Task> due = null;
        Iterator<Task> iterator = TASKS.iterator();
        while (iterator.hasNext()) {
            Task task = iterator.next();
            if (task.dueTick() <= now) {
                iterator.remove();
                if (due == null) {
                    due = new ArrayList<>(4);
                }
                due.add(task);
            }
        }
        if (due != null) {
            for (Task task : due) {
                task.action().run();
            }
        }
    }

    /** Tiny deterministic hash in [0, 1) (FloatingDecor mixer). */
    private static double hash01(int index, int salt) {
        int h = index * 374761393 + salt * 668265263;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / (double) 0x80000000L;
    }

    // ------------------------------------------------------------------ persisted phase

    /**
     * The credits sequence's own persisted state ({@code data/eclipse_credits_sequence.dat},
     * IntroSequence's {@code IntroData} pattern): {@code started}/{@code completed}/{@code
     * phase} drive the restart contract (skip to end state, never resume, never re-close),
     * {@code nonce} records the last run's close token for diagnostics.
     */
    public static final class CreditsData extends SavedData {
        static final String DATA_NAME = "eclipse_credits_sequence";
        private static final String TAG_STARTED = "started";
        private static final String TAG_COMPLETED = "completed";
        private static final String TAG_PHASE = "phase";
        private static final String TAG_NONCE = "nonce";

        private boolean started;
        private boolean completed;
        private String phase = "";
        private int nonce;

        public CreditsData() {}

        static CreditsData get(MinecraftServer server) {
            return server.overworld().getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(CreditsData::new, CreditsData::load), DATA_NAME);
        }

        static CreditsData load(CompoundTag tag, HolderLookup.Provider registries) {
            CreditsData data = new CreditsData();
            data.started = tag.getBoolean(TAG_STARTED);
            data.completed = tag.getBoolean(TAG_COMPLETED);
            data.phase = tag.getString(TAG_PHASE);
            data.nonce = tag.getInt(TAG_NONCE);
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putBoolean(TAG_STARTED, this.started);
            tag.putBoolean(TAG_COMPLETED, this.completed);
            tag.putString(TAG_PHASE, this.phase);
            tag.putInt(TAG_NONCE, this.nonce);
            return tag;
        }

        boolean isStarted() {
            return this.started;
        }

        void setStarted(boolean started) {
            this.started = started;
            setDirty();
        }

        boolean isCompleted() {
            return this.completed;
        }

        void setCompleted(boolean completed) {
            this.completed = completed;
            setDirty();
        }

        String phase() {
            return this.phase;
        }

        void setPhase(String phase) {
            this.phase = phase;
            setDirty();
        }

        void setNonce(int nonce) {
            this.nonce = nonce;
            setDirty();
        }
    }
}
