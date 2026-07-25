package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
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
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
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
import net.minecraft.world.entity.Entity;
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
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
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
 *   <li>t=0 — fade to black (10t rise), {@code victory_theme} stops, the epilogue beach
 *       starts pre-stamping through {@code BudgetedBlockWriter} while nobody can see it
 *       (warm chunks; the black/white fades give it ~260 ticks of cover, it needs about
 *       a dozen).</li>
 *   <li>t=40 — behind black: everyone teleported to the ghost-ship stern, the <b>helm
 *       double</b> (first online living player; the egg-offerer in spirit) posed on the poop
 *       deck at the block-display ship's wheel; the 140t {@code credits_helm} push-in plays
 *       (its own path event opens the shot from black).</li>
 *   <li>t=200 — fade WHITE, then the <b>disguised white loading screen</b>: portal-FX style
 *       {@code eclipse:credits_white} ({@code PortalTransitionController} holds white,
 *       {@code EclipseLoadingScreen} fakes a vanilla "Building terrain…" line) covers the
 *       teleport to the frozen-sunrise beach in {@code eclipse:epilogue}.</li>
 *   <li>t=300 — beach: {@code day_final} music cue and the right-side credits roll
 *       ({@code CreditsPanel}; it fades in client-side after a 3 s sunrise-first hold).
 *       The <b>auto-run</b> east into the sunrise arms at t=340 — 2 s of stillness on the
 *       horizon first ({@code CreditsAutoRun} client input injection; a per-player server
 *       nudge watchdog catches crashed/vanilla clients once the run is armed).</li>
 *   <li>t=420 — massive lightning (6 offshore strikes, intensity 0.6→1.0) + 24 flying
 *       {@code BLOCK_DISPLAY} debris arcs overhead toward the sun (the run's greatest hits:
 *       ship planks, altar stone, disc basalt, amethyst).</li>
 *   <li>t=480 — title card "MINECRAFT ECLIPSE COMES BACK IN AVENGERS: DOOMSDAY"
 *       ({@code TitleCardLayer} glitch decode); t=650 burst (shockwave + tight white
 *       flash, out by 666); t=665 the CORRECTION phase — the deadpan card
 *       "ECLIPSE : DOOMSDAY" (caption TITLE style) is held 500 ms and lands at t=676
 *       after a beat of total stillness.</li>
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
    /** Hands-settle wheel micro-anim: grip turn / relax-back run ticks (path t≈0.78/0.86). */
    private static final int WHEEL_SETTLE_AT = 148;
    private static final int WHEEL_RELAX_AT = 160;
    /** The wheel's rest spin ("caught mid-turn"); the settle nudges a few degrees off it. */
    private static final float WHEEL_REST_SPIN_DEGREES = 45.0F;
    /**
     * BD-SHIP living helm: the wheel turns continuously at {@value
     * #WHEEL_TURN_DEG_PER_TICK}°/t with two incommensurate sine rate-noise terms — it
     * drifts, hesitates and pulls like a helm riding a swell, never a metronome. Pushed
     * as 4t interpolation windows (~5–11° each) on the run clock (stateless absolute
     * poses). Every {@value #WHEEL_GLINT_PERIOD}t (≈ one 45° spoke crossing at the base
     * rate) a {@value #WHEEL_GLINT_RAMP}t sine brightness ramp sweeps 6→15→6 and clears
     * back to natural light — moonlight catching a spoke.
     */
    private static final float WHEEL_TURN_DEG_PER_TICK = 0.85F;
    private static final float WHEEL_NOISE_A_DEG = 6.5F;
    private static final float WHEEL_NOISE_A_PERIOD = 46.0F;
    private static final float WHEEL_NOISE_B_DEG = 4.0F;
    private static final float WHEEL_NOISE_B_PERIOD = 117.0F;
    private static final int WHEEL_GLINT_PERIOD = 50;
    private static final int WHEEL_GLINT_RAMP = 14;
    private static final int T_PORTAL = 230;
    private static final int T_EPILOGUE = 260;
    private static final int T_BEACH = 300;
    /**
     * FXTEAM CUT-CREDITS breathing room: the auto-run arms this many ticks AFTER the
     * beach beat — 2 s of everyone standing still on the sunrise horizon before the
     * march begins. The nudge watchdog waits out the same hold.
     */
    private static final int RUN_HOLD_TICKS = 40;
    private static final int T_LIGHTNING = 420;
    private static final int LIGHTNING_STRIKES = 6;
    private static final int LIGHTNING_INTERVAL = 12;
    /**
     * FXTEAM CUT-CREDITS near-far ladder: per-strike distance past the surf line
     * (blocks). Far strikes get delayed, low, quiet thunder; the final strike is the
     * closest AND strongest (the intensity ramp peaks with it).
     */
    private static final int[] STRIKE_DEPTHS = {64, 10, 34, 78, 16, 6};
    private static final int T_FLYERS_END = 560;
    private static final int T_TITLE = 480;
    private static final int T_BURST = 650;
    private static final int T_CORRECTION = 665;
    /**
     * FXTEAM CUT-CREDITS deadpan beat: the correction card is dispatched this many ticks
     * after {@link #T_CORRECTION}, buying 10t (500 ms) of pure stillness between the
     * burst flash dying (t=666) and the card fading up (t=676).
     */
    private static final int CORRECTION_STILL_TICKS = 11;
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
    /** Golden angle (radians) — flyer tumble phases: neighbors maximally de-phased (BD-SHIP). */
    private static final float GOLDEN_ANGLE = 2.3999632F;
    /** BD-SHIP flyer stagger: launch delays spread over this fraction of the flight span. */
    private static final float FLYER_STAGGER_MAX = 0.3F;
    /**
     * BD-SHIP scale envelope: flyers grow in over the first {@value #FLYER_SCALE_RAMP}
     * of their (staggered) flight and shrink out over the last — pre-launch holds are
     * invisible and the {@code T_FLYERS_END} discard never pops a block out of the sky.
     * The floor is never exactly 0 (a zero scale column degenerates the client
     * interpolator's affine decomposition).
     */
    private static final float FLYER_SCALE_RAMP = 0.12F;
    private static final float FLYER_SCALE_FLOOR = 0.02F;
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
    /**
     * UUIDs of wheel/flyer displays spawned THIS session; tagged joiners outside it are
     * crash strays ({@code StructureFlightFx.onEntityJoin} doctrine, POL-S-05).
     */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

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
        // In-memory only: orphaned displays that made it to disk are swept by the
        // join-time stray check on next boot (the StructureFlightFx pattern).
        LIVE_DISPLAYS.clear();
    }

    /** StructureFlightFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && (entity.getTags().contains(WHEEL_TAG) || entity.getTags().contains(FLYER_TAG))
                && !LIVE_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
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
        /** FXTEAM CUT-CREDITS ground shadows under the low debris arcs (≤ half the flyers). */
        final List<ShadowPuck> shadows = new ArrayList<>();
        /** Budgeted beach-stamp cursor (started at t=0; the epilogue beat blocks on it). */
        final BeachStamp beachStamp = new BeachStamp();
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
        // push-in starts), victory theme out, and start the budgeted beach stamp while
        // nobody can see it — the black/helm/white cover gives ~T_EPILOGUE ticks, the
        // stamp needs about a dozen (POL-S-02).
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendBegin(player, nonce);
            PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(10, 50, 25, 0xFF000000));
            MusicCues.stop(player);
        }
        startBeachStamp(run, epilogue);
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
        if (t > T_SHIP && t < T_EPILOGUE && (t - T_SHIP) % 4 == 0) {
            animateWheel(current, t); // BD-SHIP: the helm never stands still on camera
        }
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
        // Watchdog starts after the deliberate 2 s sunrise hold — statues are intentional
        // until the auto-run has been armed.
        if (t > T_BEACH + RUN_HOLD_TICKS && t < T_FADE_OUT) {
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
        // FXTEAM CUT-CREDITS hands-settle beat (path t≈0.77 ≈ run tick 148, synced with
        // the t=0.77 "wheel" whisper — EVAL-V6-CUTBD §3 defect 5 moved the caption from
        // t=0.72/run≈141 onto the grip): the grip pull now rides the continuous rotation
        // as a deterministic offset envelope — see gripOffset() (BD-SHIP transport;
        // the CUT-CREDITS timing constants WHEEL_SETTLE_AT/WHEEL_RELAX_AT still rule).
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

    /**
     * t=200 — the shot is over: rise to white and hold (the fade hands over to the portal
     * FX). FXTEAM CUT-CREDITS retime: 36/44/20 — the rise is a touch gentler and the
     * release ends exactly at {@link #T_BEACH} (t=300), so the sunrise finishes revealing
     * the same tick {@code day_final} starts.
     */
    private static void beatWhiteout(Run current) {
        current.enter(Phase.WHITEOUT);
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(36, 44, 20, 0xFFFFFFFF));
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
            discardWheel(current);
            current.ticks = T_FADE_OUT - 1;
            return;
        }
        if (!current.beachStamp.done) {
            // The budgeted stamp had ~T_EPILOGUE ticks of cover; a saturated writer queue
            // can still leave a remainder — finish it now, never drop runners into void.
            EclipseMod.LOGGER.warn("CreditsSequence: beach stamp incomplete at arrival ({} of {} columns) "
                    + "— finishing synchronously", current.beachStamp.cursor, BeachStamp.TOTAL_COLUMNS);
            current.beachStamp.advance(epilogue, Integer.MAX_VALUE);
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

    /**
     * t=300 — sunrise: the helm freeze releases, music finale, credits roll. FXTEAM
     * CUT-CREDITS: the auto-run arms {@value #RUN_HOLD_TICKS}t later — the shot holds on
     * the horizon for 2 s before anyone moves (the panel likewise fades in on its own 3 s
     * delay, client-side).
     */
    private static void beatBeach(Run current) {
        current.enter(Phase.BEACH);
        current.lastX.clear();
        current.stalled.clear();
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            FreezeService.unfreeze(player); // the refreezeAfterHelmShot lock ends here
            MusicCues.play(MUSIC_FINALE_CUE, player);
            CreditsPayloads.sendRoll(player, ROLL_TICKS);
        }
        schedule(current.server, RUN_HOLD_TICKS, () -> {
            // A skip() during the hold jumps past the fade-out: never arm the walk then.
            if (run != current || current.ticks >= T_FADE_OUT) {
                return;
            }
            for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
                if (!player.hasDisconnected()) {
                    CreditsPayloads.sendAutoRun(player, true, RUN_YAW,
                            T_FADE_OUT - T_BEACH - RUN_HOLD_TICKS + 100);
                }
            }
        });
    }

    /**
     * One offshore strike of the t=420 lightning beat, intensity 0.6→1.0 (IDEAS §B1).
     * FXTEAM CUT-CREDITS depth staggering: strike distances walk a deterministic
     * near↔far ladder ({@link #STRIKE_DEPTHS}, blocks past the surf line, sides
     * alternating), and the thunder arrives LATE by distance (~17 blocks/tick of sound
     * travel) — far bolts rumble low and quiet a beat after their flash, the climactic
     * last strike cracks close, loud and immediate.
     */
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
        int depth = STRIKE_DEPTHS[index % STRIKE_DEPTHS.length];
        double x = BEACH_SAND_EAST_X + depth + hash01(index, 21) * 6.0D;
        double z = (index % 2 == 0 ? 1 : -1) * (8.0D + hash01(index, 22) * 26.0D);
        Vec3 impact = new Vec3(x, BEACH_Y + 1, z);
        FxPayloads.sendFxEvent(epilogue, FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F, -1.0D);
        // PH-EVENTS (IDEAS-events #2): the per-strike Photon beam cue — same impact, same
        // intensity in a (client maps it to executor scale). Its own cue by design, never
        // piggybacked on FX_LIGHTNING_STRIKE (that id also fires at 15t cadence during the
        // intro's LIGHTNING hold — frequency law); photon-less clients no-op on it.
        FxPayloads.sendFxEvent(epilogue, FxCues.CUE_CREDITS_STRIKE, impact, intensity, 0.0F, -1.0D);
        LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(epilogue);
        if (bolt != null) {
            bolt.moveTo(impact);
            bolt.setVisualOnly(true);
            epilogue.addFreshEntity(bolt);
        }
        // Light now, sound later: far strikes lose top end (lower pitch, softer volume).
        boolean far = depth > 40;
        float volume = (0.7F + 0.5F * intensity) * (far ? 0.72F : 1.0F);
        float pitch = (far ? 0.72F : 0.9F) + (float) hash01(index, 23) * 0.12F;
        schedule(current.server, 1 + depth / 17, () -> {
            ServerLevel level = current.server.getLevel(EPILOGUE);
            if (run != current || level == null) {
                return;
            }
            for (ServerPlayer player : level.players()) {
                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.WEATHER,
                        volume, pitch);
            }
        });
    }

    /** t=480 — the doomsday card decodes ({@code TitleCardLayer}). */
    private static void beatTitle(Run current) {
        current.enter(Phase.TITLE);
        for (ServerPlayer player : current.server.getPlayerList().getPlayers()) {
            CreditsPayloads.sendTitle(player, TITLE_DOOMSDAY, 70);
        }
    }

    /**
     * t=650 — burst: shockwave + white flash (the intro-BURST mirror). FXTEAM
     * CUT-CREDITS: the flash envelope tightened 8/6/10 → 6/4/6 so the screen is fully
     * clean by t=666 — the correction card needs dead air in front of it.
     */
    private static void beatBurst(Run current) {
        ServerLevel epilogue = current.server.getLevel(EPILOGUE);
        if (epilogue != null) {
            Vec3 center = runnersCenter(epilogue);
            FxPayloads.sendFxEvent(epilogue, FxPayloads.FX_SHOCKWAVE, center, 1.0F, 50.0F, -1.0D);
            // PH-EVENTS (IDEAS-events #6): DOOMSDAY confetti mesh shards over the runners.
            // Its own cue — NOT keyed off FX_SHOCKWAVE (the (1.0, 50) giant signature is
            // claimed by the intro burst ring's client seam; two Photon layers on one
            // generic id is the if-chain smell the registry exists to kill).
            FxPayloads.sendFxEvent(epilogue, FxCues.CUE_CREDITS_BURST, center, 0.0F, 0.0F, -1.0D);
        }
        PacketDistributor.sendToAllPlayers(new S2CScreenFadePayload(6, 4, 6, 0xFFFFFFFF));
    }

    /**
     * t=665 — the deadpan legal-department correction ({@code CaptionRenderer} TITLE
     * style). FXTEAM CUT-CREDITS comedy timing: the phase enters on schedule, but the
     * card itself is held {@value #CORRECTION_STILL_TICKS}t so it lands at t=676 — a full
     * 500 ms of NOTHING (flash gone at 666, world still, music running) before
     * "ECLIPSE : DOOMSDAY" fades up like a legal department clearing its throat.
     */
    private static void beatCorrection(Run current) {
        current.enter(Phase.CORRECTION);
        schedule(current.server, CORRECTION_STILL_TICKS, () -> {
            if (run != current) {
                return; // a skip() mid-stillness moved on — never card over the outro
            }
            PacketDistributor.sendToAllPlayers(
                    new S2CCaptionPayload(TITLE_CORRECTION, 80, S2CCaptionPayload.STYLE_TITLE));
        });
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

    /**
     * t=1010 — the single "ECLIPSE" card over black. FXTEAM CUT-CREDITS: hold 90 → 75 so
     * the card is fully out by t≈1085 and the last second before the client close
     * (t=1105) is PURE black — {@code CreditsClient} lays the faint heartbeat under it.
     */
    private static void beatEclipseCard(Run current) {
        PacketDistributor.sendToAllPlayers(
                new S2CCaptionPayload(TITLE_ECLIPSE, 75, S2CCaptionPayload.STYLE_TITLE));
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
        // Belt-and-braces: normal beats already discarded these, but an aborted path
        // (epilogue vanished, skip) must never leave a tagged display behind.
        discardWheel(current);
        discardFlyers(current);
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
        wheel.setTransformationInterpolationDelay(0);
        wheel.setTransformationInterpolationDuration(0);
        wheel.setTransformation(wheelPose(wheelAngle(T_SHIP)));
        LIVE_DISPLAYS.add(wheel.getUUID());
        limbo.addFreshEntity(wheel);
        current.wheel = wheel;
    }

    /**
     * The wheel's transform at a given spin: the flat trapdoor stood upright in the YZ
     * plane (facing the helmsman, +X), rotated {@code spinDegrees} like a wheel caught
     * mid-turn, centered on its anchor (the translation must be recomputed per spin —
     * it counter-rotates the block's half extent).
     */
    private static Transformation wheelPose(float spinDegrees) {
        Quaternionf rotation = new Quaternionf()
                .rotationZ((float) Math.toRadians(90.0D))
                .rotateY((float) Math.toRadians(spinDegrees));
        Vector3f half = new Vector3f(0.55F, 0.55F, 0.55F);
        Vector3f translation = new Vector3f(0.0F, 0.0F, 0.0F).sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(1.1F, 1.1F, 1.1F), new Quaternionf());
    }

    /**
     * BD-SHIP living helm driver (every 4t while the wheel is on stage): one 4t
     * interpolation window toward the absolute pose at {@code t + 4} — a lookahead
     * piecewise-linear sampling of the noisy angle curve, worst window ≈ 11° (far under
     * the ~90° flattening law). No-op once the wheel is gone (helm-skip path discards
     * it before the window ends). Also drives the spoke-glint brightness ramp.
     */
    private static void animateWheel(Run current, int t) {
        Display.BlockDisplay wheel = current.wheel;
        if (wheel == null || wheel.isRemoved()) {
            return;
        }
        wheel.setTransformationInterpolationDelay(0);
        wheel.setTransformationInterpolationDuration(4);
        wheel.setTransformation(wheelPose(wheelAngle(t + 4)));
        applyWheelGlint(wheel, t);
    }

    /**
     * Absolute wheel angle (degrees) at run tick {@code t}: rest spin + steady turn +
     * two incommensurate rate-noise sines + the CUT-CREDITS hands-settle grip envelope.
     * A pure function of the run clock, so re-pushes always agree (stateless-push law).
     */
    private static float wheelAngle(int t) {
        float run = t - T_SHIP;
        return WHEEL_REST_SPIN_DEGREES
                + WHEEL_TURN_DEG_PER_TICK * run
                + WHEEL_NOISE_A_DEG * (float) Math.sin(run * (Math.PI * 2.0D / WHEEL_NOISE_A_PERIOD))
                + WHEEL_NOISE_B_DEG * (float) Math.sin(run * (Math.PI * 2.0D / WHEEL_NOISE_B_PERIOD) + 2.1D)
                + gripOffset(t);
    }

    /**
     * FXTEAM CUT-CREDITS hands-settle beat as a deterministic envelope on the turning
     * wheel: the grip pulls the wheel 9° down-left over 10t at {@link #WHEEL_SETTLE_AT}
     * (the dolly reaching the wheel), relaxes back to −6.5° over 14t at
     * {@link #WHEEL_RELAX_AT}, and holds. The timings and magnitudes are the original
     * nudge beat's — only the transport changed (it rides the continuous rotation now).
     */
    private static float gripOffset(int t) {
        if (t < WHEEL_SETTLE_AT) {
            return 0.0F;
        }
        if (t < WHEEL_RELAX_AT) {
            return -9.0F * Math.min(1.0F, (t - WHEEL_SETTLE_AT) / 10.0F);
        }
        return -6.5F - 2.5F * Math.max(0.0F, 1.0F - (t - WHEEL_RELAX_AT) / 14.0F);
    }

    /**
     * Spoke-light glint: a {@value #WHEEL_GLINT_RAMP}t sine brightness ramp (6→15→6,
     * block+sky) every {@value #WHEEL_GLINT_PERIOD}t, then the override is CLEARED back
     * to natural light. Fixed-period on the run clock rather than true spoke-crossing
     * detection: the rate noise would make an {@code angle mod 45°} trigger double-blink,
     * while a 50t cycle at the mean crossing rate reads identically and is branch-free.
     */
    private static void applyWheelGlint(Display.BlockDisplay wheel, int t) {
        int cycle = (t - T_SHIP) % WHEEL_GLINT_PERIOD;
        if (cycle < WHEEL_GLINT_RAMP) {
            float env = (float) Math.sin(Math.PI * cycle / (double) WHEEL_GLINT_RAMP);
            int light = 6 + Math.round(9.0F * env);
            applyBrightnessOverride(wheel, light, light);
        } else if (cycle < WHEEL_GLINT_RAMP + 4) {
            clearBrightnessOverride(wheel);
        }
    }

    private static void discardWheel(Run current) {
        if (current.wheel != null) {
            LIVE_DISPLAYS.remove(current.wheel.getUUID());
            current.wheel.discard();
            current.wheel = null;
        }
    }

    /**
     * Launches the debris arcs behind the runners (anchored at each arc's apex column).
     * FXTEAM CUT-CREDITS: every fragment is dimmed via a display brightness override
     * (sky 7 / block 4 — backlit silhouettes against the sunrise instead of fullbright
     * floating blocks), and the LOW arcs (apex roll < 0.5, ~half) each drag a flattened
     * tinted-glass "shadow puck" along the sand underneath, clamped to the sand strip so
     * no shadow ever hovers over water.
     */
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
            applyBrightnessOverride(flyer, 7, 4);
            LIVE_DISPLAYS.add(flyer.getUUID());
            epilogue.addFreshEntity(flyer);
            current.flyers.add(flyer);
            if (hash01(i, 2) < 0.5D) {
                spawnShadowPuck(current, epilogue, i, apexX, z);
            }
        }
        EclipseMod.LOGGER.info("CreditsSequence: {} debris flyer(s) launched ({} shadow puck(s))",
                current.flyers.size(), current.shadows.size());
    }

    /**
     * {@code Display.setBrightnessOverride} is private — round-trip the entity through
     * its own save NBT with a {@code brightness} compound instead (the vanilla data path,
     * so nothing reflective and nothing version-fragile beyond the tag name).
     */
    private static void applyBrightnessOverride(Display.BlockDisplay display, int sky, int block) {
        CompoundTag data = display.saveWithoutId(new CompoundTag());
        CompoundTag brightness = new CompoundTag();
        brightness.putInt("sky", sky);
        brightness.putInt("block", block);
        data.put("brightness", brightness);
        display.load(data);
    }

    /**
     * Clears the override back to natural light through the same save-data round trip —
     * the vanilla read path resets the override when the {@code brightness} compound is
     * absent. No-op (no round trip) while no override is set.
     */
    private static void clearBrightnessOverride(Display.BlockDisplay display) {
        CompoundTag data = display.saveWithoutId(new CompoundTag());
        if (data.contains("brightness")) {
            data.remove("brightness");
            display.load(data);
        }
    }

    /**
     * One flattened tinted-glass display riding the sand under a low debris arc — the
     * "shadows-ish" ground read. Same {@link #FLYER_TAG} (the stray sweep covers it),
     * same discard lifecycle as the flyers.
     */
    private static void spawnShadowPuck(Run current, ServerLevel epilogue, int index,
            double apexX, double z) {
        Display.BlockDisplay puck = EntityType.BLOCK_DISPLAY.create(epilogue);
        if (puck == null) {
            return;
        }
        puck.moveTo(apexX, BEACH_Y + 1.03D, z, 0.0F, 0.0F);
        puck.setBlockState(Blocks.TINTED_GLASS.defaultBlockState());
        puck.addTag(FLYER_TAG);
        puck.setTransformationInterpolationDelay(0);
        puck.setTransformationInterpolationDuration(0);
        // Clamp the puck's east travel to the sand strip (never a shadow on open water).
        float maxDx = (float) (BEACH_SAND_EAST_X - 2 - apexX);
        puck.setTransformation(shadowPose(index, 0.0F, maxDx));
        LIVE_DISPLAYS.add(puck.getUUID());
        epilogue.addFreshEntity(puck);
        current.shadows.add(new ShadowPuck(puck, index, maxDx));
    }

    /** Interpolated transform push every 2 ticks (FloatingDecor transport pattern). */
    private static void animateFlyers(Run current, int t) {
        if (current.flyers.isEmpty() && current.shadows.isEmpty()) {
            return;
        }
        float progress = (t - T_LIGHTNING) / (float) (T_FLYERS_END - T_LIGHTNING);
        float pushed = Math.min(1.0F, progress + 2.0F / (T_FLYERS_END - T_LIGHTNING));
        for (int i = 0; i < current.flyers.size(); i++) {
            Display.BlockDisplay flyer = current.flyers.get(i);
            if (flyer.isRemoved()) {
                continue;
            }
            flyer.setTransformationInterpolationDelay(0);
            flyer.setTransformationInterpolationDuration(2);
            flyer.setTransformation(flyerPose(i, pushed));
        }
        for (ShadowPuck shadow : current.shadows) {
            if (shadow.display().isRemoved()) {
                continue;
            }
            shadow.display().setTransformationInterpolationDelay(0);
            shadow.display().setTransformationInterpolationDuration(2);
            shadow.display().setTransformation(shadowPose(shadow.index(), pushed, shadow.maxDx()));
        }
    }

    /**
     * Absolute pose of one debris fragment at beat progress 0..1: a west→east ballistic
     * arc through the apex anchor (translation ±~38 blocks, parabolic height) —
     * everything deterministic per index, so replays and re-pushes always agree.
     * BD-SHIP motion pass: launches are STAGGERED (per-flyer delay up to
     * {@value #FLYER_STAGGER_MAX} of the span, arcs renormalized so every piece still
     * lands by {@code T_FLYERS_END} — late starters fly faster arcs); the tumble carries
     * a golden-angle phase (neighboring flyers can never spin in sync) and DAMPS to
     * ~35% of its launch rate by landing (debris stabilizing, not a pinwheel); the
     * scale envelope hides pre-launch holds and the end-of-beat discard.
     */
    private static Transformation flyerPose(int index, float progress) {
        float p = staggeredProgress(index, progress);
        float u = p * 2.0F - 1.0F; // -1 → +1 along the arc
        float xOff = u * (30.0F + (float) hash01(index, 6) * 10.0F);
        float arcHeight = 10.0F + (float) hash01(index, 7) * 8.0F;
        float yOff = -arcHeight * u * u; // 0 at the apex, -h at both ends
        float spin = index * GOLDEN_ANGLE
                + (float) ((2.0D + hash01(index, 9) * 4.0D) * Math.PI) * dampedTumble(p);
        Vector3f axis = new Vector3f(
                (float) (hash01(index, 10) * 2.0D - 1.0D),
                (float) (0.4D + hash01(index, 11)),
                (float) (hash01(index, 12) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        float scale = (0.5F + (float) hash01(index, 13) * 0.8F) * scaleEnvelope(p);
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        Vector3f translation = new Vector3f(xOff, yOff, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /** Per-flyer staggered arc progress: hold, then a renormalized 0..1 flight. */
    private static float staggeredProgress(int index, float progress) {
        float delay = (float) hash01(index, 14) * FLYER_STAGGER_MAX;
        return Math.max(0.0F, Math.min(1.0F, (progress - delay) / (1.0F - delay)));
    }

    /**
     * Damped tumble integral: reaches exactly 1 at p=1 (total spin magnitude unchanged)
     * while the instantaneous rate decays linearly to ~35% of its launch value.
     */
    private static float dampedTumble(float p) {
        return (p - 0.325F * p * p) / 0.675F;
    }

    /** In/out scale ramp over the first/last {@value #FLYER_SCALE_RAMP} of the flight. */
    private static float scaleEnvelope(float p) {
        float env = Math.min(p, 1.0F - p) / FLYER_SCALE_RAMP;
        return Math.max(FLYER_SCALE_FLOOR, Math.min(1.0F, env));
    }

    private static void discardFlyers(Run current) {
        for (Display.BlockDisplay flyer : current.flyers) {
            LIVE_DISPLAYS.remove(flyer.getUUID());
            flyer.discard();
        }
        current.flyers.clear();
        for (ShadowPuck shadow : current.shadows) {
            LIVE_DISPLAYS.remove(shadow.display().getUUID());
            shadow.display().discard();
        }
        current.shadows.clear();
    }

    /** One ground-shadow display bound to its flyer's deterministic arc index. */
    private record ShadowPuck(Display.BlockDisplay display, int index, float maxDx) {}

    /**
     * Ground-shadow pose mirroring {@link #flyerPose}'s horizontal travel (same
     * staggered-progress/u/xOff math, east travel clamped to the sand strip), flattened
     * to a 0.045-high slab. The footprint swells up to +50% while its debris is at apex
     * (highest = biggest, softest-reading shadow), counter-spins slowly at 30% of the
     * (damped, golden-phased) debris tumble, and rides the same scale envelope so a
     * pre-launch or landed flyer never drags a visible puck.
     */
    private static Transformation shadowPose(int index, float progress, float maxDx) {
        float p = staggeredProgress(index, progress);
        float u = p * 2.0F - 1.0F;
        float xOff = Math.min(u * (30.0F + (float) hash01(index, 6) * 10.0F), maxDx);
        float heightFrac = 1.0F - u * u; // 1 at apex, 0 at both ends (mirrors -h·u²)
        float spin = (index * GOLDEN_ANGLE
                + (float) ((2.0D + hash01(index, 9) * 4.0D) * Math.PI) * dampedTumble(p)) * 0.3F;
        float base = 0.5F + (float) hash01(index, 13) * 0.8F;
        float footprint = base * (0.9F + 0.5F * heightFrac) * scaleEnvelope(p);
        Quaternionf rotation = new Quaternionf().rotationY(spin);
        Vector3f scale = new Vector3f(footprint, 0.045F, footprint);
        Vector3f half = new Vector3f(footprint * 0.5F, 0.0F, footprint * 0.5F);
        Vector3f translation = new Vector3f(xOff, 0.0F, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    // ------------------------------------------------------------------ beach stamp

    /**
     * Queues the epilogue beach stamp through {@link BudgetedBlockWriter} (POL-S-02): the
     * ~44.6k writes are spread over budgeted column slices behind the t=0 black and t=200
     * white fades instead of one synchronous tick. The job drops itself if the run it
     * belongs to ends first; {@link #beatEpilogue} finishes any remainder synchronously
     * before the teleport (the runners must never land on a half-stamped set).
     */
    private static void startBeachStamp(Run owner, ServerLevel epilogue) {
        long start = System.nanoTime();
        BudgetedBlockWriter.enqueue(epilogue, budget -> {
            if (run != owner) {
                return true; // the run ended/was replaced — drop the one-shot job
            }
            return owner.beachStamp.advance(epilogue, budget);
        }, () -> EclipseMod.LOGGER.info("CreditsSequence: epilogue beach stamped in {} ms (budgeted)",
                (System.nanoTime() - start) / 1_000_000L),
                error -> EclipseMod.LOGGER.error(
                        "CreditsSequence: budgeted beach stamp failed — the epilogue beat will retry "
                                + "synchronously", error));
    }

    /**
     * Resumable cursor of the epilogue beach set (idempotent — pure {@code setBlock} of
     * the same shape): a sand strip with 2% {@code suspicious_sand} nothing-burgers, a
     * water plane east toward the frozen sunrise, an outer barrier rim that contains the
     * water, and barrier run-lane rails at z ±{@value #LANE_HALF_Z}. One logical operation
     * is one (x, z) column (at most 8 writes), so a {@code BudgetedBlockWriter} slice
     * stays around 4–5k writes. Column order matches the old synchronous loop (x outer,
     * z inner) — the layout stays byte-identical and deterministic. Flag
     * {@code UPDATE_CLIENTS} only — no neighbor updates, nothing to react anyway in a
     * void dimension.
     */
    private static final class BeachStamp {
        static final int SPAN_Z = 2 * BEACH_HALF_Z + 1;
        static final int TOTAL_COLUMNS = (BEACH_EAST_X - BEACH_WEST_X + 1) * SPAN_Z;

        int cursor;
        boolean done;

        /** Stamps up to {@code columnBudget} columns; returns {@code true} once complete. */
        boolean advance(ServerLevel epilogue, int columnBudget) {
            if (this.done) {
                return true;
            }
            BlockState sand = Blocks.SAND.defaultBlockState();
            BlockState suspicious = Blocks.SUSPICIOUS_SAND.defaultBlockState();
            BlockState water = Blocks.WATER.defaultBlockState();
            BlockState barrier = Blocks.BARRIER.defaultBlockState();
            int end = (int) Math.min((long) this.cursor + columnBudget, TOTAL_COLUMNS);
            for (; this.cursor < end; this.cursor++) {
                int x = BEACH_WEST_X + this.cursor / SPAN_Z;
                int z = -BEACH_HALF_Z + this.cursor % SPAN_Z;
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
                // Run-lane rails over the sand (invisible; keep the line together).
                if (Math.abs(z) == LANE_HALF_Z && x <= BEACH_SAND_EAST_X) {
                    for (int y = BEACH_Y + 1; y <= BEACH_Y + 2; y++) {
                        set(epilogue, x, y, z, barrier);
                    }
                }
            }
            this.done = this.cursor >= TOTAL_COLUMNS;
            return this.done;
        }
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
                    // Mirrors the live near-far ladder: flash on the interval, thunder
                    // arriving late/low/quiet by depth (FXTEAM CUT-CREDITS).
                    int depth = STRIKE_DEPTHS[index % STRIKE_DEPTHS.length];
                    boolean far = depth > 40;
                    schedule(server, i * LIGHTNING_INTERVAL, () -> {
                        float intensity = 0.6F + 0.4F * index / (LIGHTNING_STRIKES - 1);
                        for (ServerPlayer player : watchers) {
                            if (player.hasDisconnected()) {
                                continue;
                            }
                            Vec3 impact = player.position().add(14.0D + depth, 0.0D,
                                    (index % 2 == 0 ? 1 : -1) * (8.0D + hash01(index, 22) * 26.0D));
                            PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                                    .S2CFxEventPayload(FxPayloads.FX_LIGHTNING_STRIKE, impact, intensity, 0.0F));
                            // PH-EVENTS replay parity (R12): the live ladder pairs every
                            // strike with its Photon beam cue — so does the replay.
                            PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                                    .S2CFxEventPayload(FxCues.CUE_CREDITS_STRIKE, impact, intensity, 0.0F));
                        }
                    });
                    schedule(server, i * LIGHTNING_INTERVAL + 1 + depth / 17, () -> {
                        float intensity = 0.6F + 0.4F * index / (LIGHTNING_STRIKES - 1);
                        for (ServerPlayer player : watchers) {
                            if (!player.hasDisconnected()) {
                                player.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER,
                                        SoundSource.WEATHER,
                                        (0.7F + 0.5F * intensity) * (far ? 0.72F : 1.0F),
                                        (far ? 0.72F : 0.9F) + (float) hash01(index, 23) * 0.12F);
                            }
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
                    // Replay parity (EVAL-V6-PHOTON §4): the live beatBurst leads with the
                    // giant FX_SHOCKWAVE(1.0, 50) — the exact signature the client seam
                    // layers the Photon INTRO_BURST_RING onto — so the FX-only replay
                    // sends it too, anchored at the watcher.
                    PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                            .S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE, player.position(), 1.0F, 50.0F));
                    PacketDistributor.sendToPlayer(player, new S2CScreenFadePayload(6, 4, 6, 0xFFFFFFFF));
                    // PH-EVENTS replay parity (R12): the live burst pairs this flash with
                    // the confetti cue (beatBurst) — replay anchors it at the watcher.
                    PacketDistributor.sendToPlayer(player, new dev.projecteclipse.eclipse.network.fx
                            .S2CFxEventPayload(FxCues.CUE_CREDITS_BURST, player.position(), 0.0F, 0.0F));
                }
                // Same 500 ms deadpan stillness between flash-out and card as the live
                // beat (flash dies at 16t here since both fire together; card at 26t).
                schedule(server, 26, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player,
                                    new S2CCaptionPayload(TITLE_CORRECTION, 80, S2CCaptionPayload.STYLE_TITLE));
                        }
                    }
                });
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
                                    new S2CCaptionPayload(TITLE_ECLIPSE, 75, S2CCaptionPayload.STYLE_TITLE));
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
