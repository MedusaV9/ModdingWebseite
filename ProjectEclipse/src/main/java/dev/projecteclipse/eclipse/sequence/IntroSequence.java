package dev.projecteclipse.eclipse.sequence;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.cutscene.SequenceReplayable;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CEclipsePhasePayload;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.stormfx.StormRegistry;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.worldgen.stage.FusionSequence;
import dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumVersionData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
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
 * INTRO SEQUENCE v3 (P2 R10, worker W6) — the server-side phase machine of the event-start
 * cinematic. {@code limbo.StartEventCutscene} (or P4's trigger, §6.3) calls
 * {@link #start(MinecraftServer, Map)} once every player stands on their own disc; from
 * there this class owns the show until the sun rises with its permanent purple rim.
 *
 * <p><b>Timeline</b> (R10 frozen tick table; {@code t} = ticks since start):</p>
 * <ol>
 *   <li>{@code ECLIPSE_ON} (t=0..100) — {@code S2CEclipsePhasePayload(TOTAL, 1.0, ramp 100)},
 *       the {@code eclipse.caption.intro.awaken} TITLE caption, {@code event.eclipse_drone},
 *       and a short freeze so nobody wanders before the camera takes over.</li>
 *   <li>{@code FLIGHT} (t=100..1000) — {@link FusionSequence#maybeStartIntroFusion} kicks the
 *       disc fusion, then the world-anchored {@code intro_v3_flight} crane shot plays as a
 *       GLOBAL_TELEPORT group play (anchor = vortex ground center; far players are gathered
 *       behind a fade and returned to their discs after — the R12 chunk-visibility policy,
 *       view distance 12). At t=300 the smoke/storm vortex spawns over the (still grounded,
 *       now hidden) spawn altar via {@link StormRegistry#spawnVortex} (r {@value #VORTEX_RADIUS},
 *       h {@value #VORTEX_HEIGHT}); at t=500 the {@code eclipse:altar_center} FX anchor is
 *       synced. The path's own events carry the captions and the t=960 fade to black;
 *       control returns at t=1000.</li>
 *   <li>{@code APPROACH} (untimed) — players walk; the watcher trips when the FIRST
 *       non-spectator gets within {@value #APPROACH_TRIGGER_BLOCKS} blocks of the smoke
 *       wall.</li>
 *   <li>{@code LIGHTNING} (600 ticks) — {@link IntroLightningPhase}: ramping purple strikes
 *       from the eclipse zenith, kickback with day-1-containment clamping. If the fusion
 *       sweep has not flipped the sanctum to its floating v2 yet, the storm holds at max
 *       fury (strikes every 15 ticks) until the flip lands or
 *       {@value #BURST_FLIP_TIMEOUT_TICKS} ticks pass.</li>
 *   <li>{@code BURST} — the GIANT strike ({@code intensity 1, b=1}), {@code fx/shockwave}
 *       (1.0, 50), vortex {@code DISSIPATE 60}, white→violet screen flash,
 *       {@code eclipse:altar_reveal_burst} at the altar and {@link FloatingDecor#ensure}.</li>
 *   <li>{@code REVEAL} (300 ticks) — {@code intro_v3_reveal} orbit of the floating altar
 *       island (anchor = altar position; nobody is far by now, so the global play only bumps
 *       view distance).</li>
 *   <li>{@code SUNRISE} (200 ticks) — {@code S2CEclipsePhasePayload(ENDING, 0, ramp 200,
 *       permanentRim=true)} + the {@code eclipse.caption.intro.begin} TITLE caption. The
 *       permanent-rim flag persists here (fallback until P4's world flag ships, §6.3) and is
 *       re-sent to every player at login.</li>
 * </ol>
 *
 * <p><b>Freeze/invulnerability</b>: camera phases freeze through the cutscene engine
 * ({@code CutsceneService.play} → {@code FreezeService}, which also grants invulnerability);
 * the ECLIPSE_ON pre-roll freezes explicitly. LIGHTNING deliberately leaves players free —
 * that phase is theirs.</p>
 *
 * <p><b>Restart safety</b>: the phase persists in {@link IntroData}
 * ({@code data/eclipse_intro_sequence.dat}). A restart mid-sequence does NOT resume the
 * cinematic — it skips to the end state (eclipse ended + permanent rim, lingering vortex
 * dissipated, decor ensured once the sanctum is floating) so nobody is ever wedged in a
 * half-played intro. Mid-sequence logins get the current eclipse phase re-synced and are
 * frozen for the remainder of an active camera phase.</p>
 *
 * <p><b>Replay</b> (R12): registered as {@link SequenceReplayable} id {@code "intro"} —
 * {@code /eclipsefx sequence intro <phase>} replays each phase FX-only: no storm registry
 * writes (raw {@link S2CStormStatePayload}s with a reserved id), no teleports (LOCAL plays),
 * no decor spawn, no state commits, kickback disabled.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class IntroSequence implements SequenceReplayable {
    // --- frozen ids ---
    private static final String SEQUENCE_ID = "intro";
    private static final String PATH_FLIGHT = "intro_v3_flight";
    private static final String PATH_REVEAL = "intro_v3_reveal";

    private static final ResourceLocation ALTAR_REVEAL_BURST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_reveal_burst");

    private static final String CAPTION_AWAKEN = "eclipse.caption.intro.awaken";
    private static final String CAPTION_STRIKE = "eclipse.caption.intro.strike";
    private static final String CAPTION_APPROACH = "eclipse.caption.intro.approach";
    private static final String CAPTION_BEGIN = "eclipse.caption.intro.begin";

    // --- eclipse phases (S2CEclipsePhasePayload contract: 0=NONE 1=BUILDUP 2=TOTAL 3=ENDING) ---
    private static final int ECLIPSE_NONE = 0;
    private static final int ECLIPSE_TOTAL = 2;
    private static final int ECLIPSE_ENDING = 3;

    // --- R10 frozen numbers ---
    /** Vortex shell radius / height (R10 phase 2 + R15). */
    public static final float VORTEX_RADIUS = 22.0F;
    public static final float VORTEX_HEIGHT = 48.0F;
    /** First player this close to the smoke wall trips LIGHTNING (R10 "~4-5 blocks"). */
    public static final double APPROACH_TRIGGER_BLOCKS = 5.0D;

    private static final int ECLIPSE_ON_TICKS = 100;
    private static final int FLIGHT_DURATION_TICKS = 900;
    /** Vortex spawn inside FLIGHT (absolute t=300). */
    private static final int VORTEX_SPAWN_TICK = 300;
    /** Altar-anchor sync inside FLIGHT (absolute t=500 — R10's "altar placed, hidden" beat). */
    private static final int ALTAR_ANCHOR_TICK = 500;
    private static final int VORTEX_DISSIPATE_TICKS = 60;
    /** Extra strikes cadence while BURST waits for the floating-island flip. */
    private static final int HOLD_STRIKE_INTERVAL_TICKS = 15;
    /** BURST proceeds without the flip after this long (fusion sweep budget-bound). */
    private static final int BURST_FLIP_TIMEOUT_TICKS = 1200;
    /** Pause between the giant strike and the reveal orbit (lets the flash+collapse read). */
    private static final int BURST_HOLD_TICKS = 40;
    private static final int REVEAL_DURATION_TICKS = 300;
    private static final int SUNRISE_RAMP_TICKS = 200;
    /** Cinematic view-distance bump for the global plays (R12 cap is 12). */
    private static final int VIEW_DISTANCE_CHUNKS = 12;

    /** White half of the burst flash (in, hold, out, argb). */
    private static final S2CScreenFadePayload FLASH_WHITE = new S2CScreenFadePayload(2, 2, 2, 0xFFFFFFFF);
    /** Violet tail of the burst flash, sent {@value #FLASH_VIOLET_DELAY_TICKS} ticks later. */
    private static final S2CScreenFadePayload FLASH_VIOLET = new S2CScreenFadePayload(2, 2, 8, 0xCC8800FF);
    private static final int FLASH_VIOLET_DELAY_TICKS = 4;

    /** Reserved storm id of FX-only replays — never collides with StormRegistry's counter. */
    private static final int REPLAY_STORM_ID = 999_006;

    private static final IntroSequence INSTANCE = new IntroSequence();
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** The single live run, or {@code null}. Server thread only. */
    @Nullable
    private static Run run;
    /** Tick scheduler for one-shot delays (live run + replays). Server thread only. */
    private static final List<Task> TASKS = new ArrayList<>();
    /** FX-only lightning controllers driven for replays. Server thread only. */
    private static final List<IntroLightningPhase> REPLAY_LIGHTNING = new ArrayList<>();

    private IntroSequence() {}

    // ------------------------------------------------------------------ wiring

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (REGISTERED.compareAndSet(false, true)) {
            SequenceReplayable.Registry.register(INSTANCE);
            EclipseMod.LOGGER.info("IntroSequence registered (replay id '{}')", SEQUENCE_ID);
        }
    }

    /** Restart recovery: a world stopped mid-intro skips to the end state (class doc). */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        IntroData data = IntroData.get(server);
        if (data.isStarted() && !data.isCompleted()) {
            EclipseMod.LOGGER.warn("IntroSequence: world restarted mid-intro (phase {}) — skipping to end state",
                    data.phase());
            completeAbandonedRun(server, data);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // Statics must never leak into the next world a singleplayer client opens.
        run = null;
        TASKS.clear();
        REPLAY_LIGHTNING.clear();
    }

    // ------------------------------------------------------------------ phase machine

    private enum Phase { ECLIPSE_ON, FLIGHT, APPROACH, LIGHTNING, BURST, REVEAL, SUNRISE }

    /** The live run. All access on the server thread. */
    private static final class Run {
        final MinecraftServer server;
        final ServerLevel overworld;
        /** Vortex ground center == the spawn altar column at terrain level. */
        final Vec3 center;
        /** Disc centers by player (P4's frozen framing param; currently informational). */
        final Map<UUID, BlockPos> discCenters;

        Phase phase = Phase.ECLIPSE_ON;
        /** Ticks since {@link #start}. */
        int ticks;
        /** Tick this run's current phase was entered at (login freeze estimates). */
        int phaseStartTick;
        /** StormRegistry id of the live vortex; -1 before spawn / after dissipate. */
        int stormId = -1;
        @Nullable
        IntroLightningPhase lightning;
        /** Set once the giant burst fired (BURST is entered exactly once). */
        boolean burstFired;

        Run(MinecraftServer server, ServerLevel overworld, Vec3 center, Map<UUID, BlockPos> discCenters) {
            this.server = server;
            this.overworld = overworld;
            this.center = center;
            this.discCenters = Map.copyOf(discCenters);
        }

        void enter(Phase next) {
            this.phase = next;
            this.phaseStartTick = this.ticks;
            IntroData.get(this.server).setPhase(next.name());
            EclipseMod.LOGGER.info("IntroSequence: phase {} (t={})", next, this.ticks);
        }
    }

    /**
     * Starts the intro sequence. The frozen §6.3 entry point: the caller (P4 /
     * {@code StartEventCutscene}) has already teleported each player to their own disc and
     * passes the disc centers for framing. No-op while a run is already live; a completed
     * world logs and runs again anyway (dev worlds re-fire {@code /start_event} — every
     * world mutation here is idempotent).
     *
     * @return whether a new run started
     */
    public static boolean start(MinecraftServer server, Map<UUID, BlockPos> discCenters) {
        if (run != null) {
            EclipseMod.LOGGER.warn("IntroSequence: already running (phase {}) — ignoring start()", run.phase);
            return false;
        }
        IntroData data = IntroData.get(server);
        if (data.isCompleted()) {
            EclipseMod.LOGGER.warn("IntroSequence: this world already completed the intro — running again (dev re-fire)");
        }
        ServerLevel overworld = server.overworld();
        Vec3 center = vortexCenter(server);
        run = new Run(server, overworld, center, discCenters);
        data.setStarted(true);
        data.setCompleted(false);
        data.setPhase(Phase.ECLIPSE_ON.name());

        // ECLIPSE_ON: total eclipse ramps in overhead while everyone stands on their disc.
        FxPayloads.sendEclipsePhase(server, ECLIPSE_TOTAL, 1.0F, ECLIPSE_ON_TICKS, false);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player,
                    new S2CCaptionPayload(CAPTION_AWAKEN, 80, S2CCaptionPayload.STYLE_TITLE));
            player.playNotifySound(EclipseSounds.EVENT_ECLIPSE_DRONE.get(), SoundSource.AMBIENT, 1.0F, 1.0F);
            // Pre-roll lock (with invulnerability) until the FLIGHT play takes the freeze over.
            FreezeService.freeze(player, ECLIPSE_ON_TICKS + 60, false, 0);
        }
        EclipseMod.LOGGER.info("IntroSequence: started for {} player(s), vortex center {}",
                server.getPlayerList().getPlayerCount(), center);
        return true;
    }

    /** Convenience overload (no framing map). */
    public static boolean start(MinecraftServer server) {
        return start(server, Map.of());
    }

    /** Whether the intro phase machine is currently live. */
    public static boolean isRunning() {
        return run != null;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        tickScheduler(event.getServer());
        tickReplayLightning(event.getServer());
        Run current = run;
        if (current == null) {
            return;
        }
        current.ticks++;
        switch (current.phase) {
            case ECLIPSE_ON -> {
                if (current.ticks >= ECLIPSE_ON_TICKS) {
                    beginFlight(current);
                }
            }
            case FLIGHT -> {
                if (current.ticks == VORTEX_SPAWN_TICK) {
                    spawnVortex(current);
                } else if (current.ticks == ALTAR_ANCHOR_TICK) {
                    syncAltarAnchor(current);
                }
            }
            case APPROACH -> {
                if (current.ticks % 20 == 0) {
                    rescueVoidFallers(current);
                }
                if (firstPlayerNearVortex(current)) {
                    beginLightning(current);
                }
            }
            case LIGHTNING -> {
                if (current.ticks % 20 == 0) {
                    rescueVoidFallers(current);
                }
                tickLightning(current);
            }
            case BURST, REVEAL, SUNRISE -> { /* driven by scheduled tasks / group callbacks */ }
        }
    }

    /** FLIGHT: fusion starts (the camera frames it) and the crane shot plays globally. */
    private static void beginFlight(Run current) {
        current.enter(Phase.FLIGHT);
        FusionSequence.maybeStartIntroFusion(current.server);
        List<ServerPlayer> watchers = List.copyOf(current.server.getPlayerList().getPlayers());
        // GLOBAL_TELEPORT + returnAfter: disc players (~170 blocks out) are gathered to the
        // ring around the vortex center behind a fade so their clients hold the chunks the
        // camera flies over, and are restored to their exact disc spots when the shot ends.
        CutsceneService.play(PATH_FLIGHT, watchers, current.center,
                () -> beginApproach(current), CutsceneService.PlayOptions.global(VIEW_DISTANCE_CHUNKS));
    }

    private static void spawnVortex(Run current) {
        current.stormId = StormRegistry.spawnVortex(current.overworld, current.center,
                VORTEX_RADIUS, VORTEX_HEIGHT, StormRegistry.RAMP_TICKS);
        EclipseMod.LOGGER.info("IntroSequence: vortex {} spawned at {} (r {}, h {})",
                current.stormId, current.center, VORTEX_RADIUS, VORTEX_HEIGHT);
    }

    /**
     * The R10 t=500 beat: the grounded altar already sits hidden inside the opaque vortex
     * (built at server start; the fusion flips it floating later), so the server-side work
     * left is syncing the {@code eclipse:altar_center} FX anchor for lookAts/anchored FX.
     * Idempotent — P4/P6 may set the same anchor again when their integration lands (§6.3).
     */
    private static void syncAltarAnchor(Run current) {
        Vec3 altar = altarCenter(current.server);
        if (altar != null) {
            FxAnchors.set(FxAnchors.ALTAR_CENTER, current.overworld, altar);
        }
    }

    /** APPROACH: control is back; the proximity watcher arms. */
    private static void beginApproach(Run current) {
        if (run != current) {
            return;
        }
        current.enter(Phase.APPROACH);
        // The flight JSON's own fade+caption covered the hand-off. Degrade path: a
        // disabled/missing flight completes its group instantly (before t=300) — the smoke
        // wall must still exist for APPROACH/LIGHTNING, so spawn it now.
        if (current.stormId < 0) {
            spawnVortex(current);
        }
    }

    /** Smoke-wall trigger band: below-disc walkers must NOT trip it, fliers above SHOULD. */
    private static final double APPROACH_TRIGGER_Y_BELOW = 12.0D;

    private static boolean firstPlayerNearVortex(Run current) {
        double triggerDist = VORTEX_RADIUS + APPROACH_TRIGGER_BLOCKS;
        // Anywhere alongside the vortex column (base −12 … top +12) counts; only players
        // far BELOW the disc (void walkers) are excluded.
        double minY = current.center.y - APPROACH_TRIGGER_Y_BELOW;
        double maxY = current.center.y + VORTEX_HEIGHT + APPROACH_TRIGGER_Y_BELOW;
        for (ServerPlayer player : current.overworld.players()) {
            if (player.isSpectator()) {
                continue;
            }
            double dx = player.getX() - current.center.x;
            double dz = player.getZ() - current.center.z;
            if (dx * dx + dz * dz <= triggerDist * triggerDist
                    && player.getY() >= minY && player.getY() <= maxY) {
                EclipseMod.LOGGER.info("IntroSequence: {} reached the smoke wall — LIGHTNING",
                        player.getScoreboardName());
                return true;
            }
        }
        return false;
    }

    /**
     * APPROACH/LIGHTNING void rescue: the fusion sweep may still be filling gaps while
     * players walk toward the vortex — anyone who slips under the disc gets lifted back
     * to the surface over the vortex-side rim with brief slow fall (day-1 containment
     * spirit: the void rejects you, the show must be seen from above).
     */
    private static void rescueVoidFallers(Run current) {
        for (ServerPlayer player : current.overworld.players()) {
            if (player.isSpectator()) {
                continue;
            }
            if (player.getY() < current.center.y - 40.0D) {
                double backX = player.getX();
                double backZ = player.getZ();
                int surfaceY = current.overworld.getHeight(
                        net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING,
                        (int) Math.floor(backX), (int) Math.floor(backZ));
                if (surfaceY <= current.overworld.getMinBuildHeight()
                        || surfaceY < current.center.y - 24.0D) {
                    // Fusion gap or crater column: pull halfway toward the vortex and drop
                    // at disc-surface height with slow fall — never below the safety line,
                    // or the rescue would thrash every check.
                    backX = current.center.x + (backX - current.center.x) * 0.5D;
                    backZ = current.center.z + (backZ - current.center.z) * 0.5D;
                    surfaceY = (int) current.center.y;
                }
                player.teleportTo(current.overworld, backX + 0.0D, surfaceY + 1.0D, backZ,
                        player.getYRot(), player.getXRot());
                player.addEffect(new net.minecraft.world.effect.MobEffectInstance(
                        net.minecraft.world.effect.MobEffects.SLOW_FALLING, 80, 0, true, false));
                player.fallDistance = 0.0F;
                current.overworld.sendParticles(net.minecraft.core.particles.ParticleTypes.PORTAL,
                        player.getX(), player.getY() + 1.0D, player.getZ(), 24, 0.4D, 0.8D, 0.4D, 0.05D);
                EclipseMod.LOGGER.info("IntroSequence: rescued {} from the void (y<{})",
                        player.getScoreboardName(), current.center.y - 40.0D);
            }
        }
    }

    /** LIGHTNING: the ramping-strikes controller runs with live kickback. */
    private static void beginLightning(Run current) {
        current.enter(Phase.LIGHTNING);
        current.lightning = new IntroLightningPhase(current.center, VORTEX_RADIUS, VORTEX_HEIGHT, true);
        for (ServerPlayer player : current.overworld.players()) {
            PacketDistributor.sendToPlayer(player,
                    new S2CCaptionPayload(CAPTION_STRIKE, 90, S2CCaptionPayload.STYLE_WHISPER));
        }
    }

    /**
     * Drives the ramp; once it completes, BURST waits (at max storm fury) for the fusion
     * sweep to flip the sanctum floating — the burst must reveal the ISLAND, not the
     * grounded altar. A budget-starved sweep can never wedge the intro: after
     * {@value #BURST_FLIP_TIMEOUT_TICKS} ticks the burst fires regardless.
     */
    private static void tickLightning(Run current) {
        IntroLightningPhase lightning = current.lightning;
        if (lightning != null && lightning.tick(current.overworld)) {
            return;
        }
        int waited = current.ticks - current.phaseStartTick - IntroLightningPhase.DURATION_TICKS;
        boolean floating = SanctumVersionData.get(current.overworld).version()
                == SanctumVersionData.VERSION_FLOATING;
        if (!floating && waited < BURST_FLIP_TIMEOUT_TICKS) {
            if (waited >= 0 && waited % HOLD_STRIKE_INTERVAL_TICKS == 0 && lightning != null) {
                lightning.strike(current.overworld, 1.0F, false); // hold the fury while we wait
            }
            if (waited == 0) {
                EclipseMod.LOGGER.info("IntroSequence: ramp done but sanctum not floating yet — holding BURST");
            }
            return;
        }
        beginBurst(current);
    }

    /** BURST: the giant strike bursts the vortex open. */
    private static void beginBurst(Run current) {
        if (current.burstFired) {
            return;
        }
        current.burstFired = true;
        current.enter(Phase.BURST);
        MinecraftServer server = current.server;

        IntroLightningPhase lightning = current.lightning != null ? current.lightning
                : new IntroLightningPhase(current.center, VORTEX_RADIUS, VORTEX_HEIGHT, true);
        lightning.strike(current.overworld, 1.0F, true);
        FxPayloads.sendFxEvent(current.overworld, FxPayloads.FX_SHOCKWAVE, current.center, 1.0F, 50.0F, -1.0D);
        if (current.stormId >= 0) {
            StormRegistry.dissipate(current.stormId, VORTEX_DISSIPATE_TICKS);
            current.stormId = -1;
        }
        // White → violet screen flash (R10: 8 ticks total across the two fades).
        PacketDistributor.sendToAllPlayers(FLASH_WHITE);
        schedule(server, FLASH_VIOLET_DELAY_TICKS, () -> PacketDistributor.sendToAllPlayers(FLASH_VIOLET));

        Vec3 altar = altarCenterOr(current.server, current.center);
        PacketDistributor.sendToPlayersInDimension(current.overworld,
                new S2CQuasarPayload(ALTAR_REVEAL_BURST, altar));
        // Reveal dressing: FX anchor + the floating-rubble decor cloud around the island.
        syncAltarAnchor(current);
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos != null) {
            FloatingDecor.ensure(current.overworld, altarPos);
        }
        schedule(server, BURST_HOLD_TICKS, () -> beginReveal(current));
    }

    /** REVEAL: slow orbit of the floating altar island. */
    private static void beginReveal(Run current) {
        if (run != current) {
            return;
        }
        current.enter(Phase.REVEAL);
        Vec3 altar = altarCenterOr(current.server, current.center);
        List<ServerPlayer> watchers = List.copyOf(current.server.getPlayerList().getPlayers());
        // Everyone stands at the smoke wall by now (inside the 128-block gather radius), so
        // the global play only bumps view distance — no teleports, players freeze in place.
        CutsceneService.play(PATH_REVEAL, watchers, altar,
                () -> beginSunrise(current), CutsceneService.PlayOptions.global(VIEW_DISTANCE_CHUNKS));
    }

    /** SUNRISE: the eclipse ends; the sun keeps its purple rim forever. */
    private static void beginSunrise(Run current) {
        if (run != current) {
            return;
        }
        current.enter(Phase.SUNRISE);
        MinecraftServer server = current.server;
        FxPayloads.sendEclipsePhase(server, ECLIPSE_ENDING, 0.0F, SUNRISE_RAMP_TICKS, true);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player,
                    new S2CCaptionPayload(CAPTION_BEGIN, 100, S2CCaptionPayload.STYLE_TITLE));
        }
        IntroData data = IntroData.get(server);
        data.setPermanentRim(true);
        schedule(server, SUNRISE_RAMP_TICKS, () -> finish(current));
    }

    private static void finish(Run current) {
        if (run != current) {
            return;
        }
        IntroData data = IntroData.get(current.server);
        data.setCompleted(true);
        data.setPhase("");
        run = null;
        EclipseMod.LOGGER.info("IntroSequence: complete — permanent sun rim latched");
    }

    // ------------------------------------------------------------------ restart / login safety

    /**
     * A world that restarted mid-intro skips to the end state: eclipse ended with the rim,
     * lingering vortex storms over spawn dissipated, decor ensured (only once the island is
     * actually floating — a pre-fusion abort leaves the grounded altar alone). The fusion
     * sweep itself is P1's persisted machinery and resumes/settles on its own.
     */
    private static void completeAbandonedRun(MinecraftServer server, IntroData data) {
        ServerLevel overworld = server.overworld();
        for (StormRegistry.StormData storm : List.copyOf(StormRegistry.storms(overworld))) {
            StormRegistry.dissipate(storm.stormId(), VORTEX_DISSIPATE_TICKS);
        }
        FxPayloads.sendEclipsePhase(server, ECLIPSE_NONE, 0.0F, 40, true);
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos != null
                && SanctumVersionData.get(overworld).version() == SanctumVersionData.VERSION_FLOATING) {
            FloatingDecor.ensure(overworld, altarPos);
            Vec3 altar = altarCenter(server);
            if (altar != null) {
                FxAnchors.set(FxAnchors.ALTAR_CENTER, overworld, altar);
            }
        }
        data.setPermanentRim(true);
        data.setCompleted(true);
        data.setPhase("");
    }

    /**
     * Login resync: a finished world re-sends the permanent rim (fallback until P4's login
     * re-send ships, §6.3); a live run re-syncs the total eclipse and freezes the joiner for
     * the remainder of an active camera phase so they can't wander through the cinematic.
     */
    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        Run current = run;
        if (current == null) {
            IntroData data = IntroData.get(player.server);
            if (data.isPermanentRim()) {
                PacketDistributor.sendToPlayer(player,
                        new S2CEclipsePhasePayload(ECLIPSE_NONE, 0.0F, 0, true));
            }
            return;
        }
        boolean sunrise = current.phase == Phase.SUNRISE;
        PacketDistributor.sendToPlayer(player, new S2CEclipsePhasePayload(
                sunrise ? ECLIPSE_ENDING : ECLIPSE_TOTAL, sunrise ? 0.0F : 1.0F, 20, sunrise));
        int remaining = switch (current.phase) {
            case ECLIPSE_ON -> ECLIPSE_ON_TICKS - current.ticks;
            case FLIGHT -> FLIGHT_DURATION_TICKS - (current.ticks - current.phaseStartTick);
            case BURST -> BURST_HOLD_TICKS + REVEAL_DURATION_TICKS;
            case REVEAL -> REVEAL_DURATION_TICKS - (current.ticks - current.phaseStartTick);
            default -> 0; // APPROACH/LIGHTNING/SUNRISE: players are free
        };
        if (remaining > 0) {
            FreezeService.freeze(player, remaining + CutsceneService.WATCHDOG_MARGIN_TICKS, false, 0);
        }
    }

    // ------------------------------------------------------------------ geometry

    /** The vortex ground center: the spawn altar column at terrain level (origin fallback). */
    private static Vec3 vortexCenter(MinecraftServer server) {
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null) {
            BlockPos spawn = overworld.getSharedSpawnPos();
            return new Vec3(spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D);
        }
        boolean floating = SanctumVersionData.get(overworld).version() == SanctumVersionData.VERSION_FLOATING;
        int groundY = floating ? FloatingSanctumBuilder.groundY(altarPos)
                : altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        return new Vec3(altarPos.getX() + 0.5D, groundY, altarPos.getZ() + 0.5D);
    }

    /** The altar block center, or {@code null} while the sanctum was never built. */
    @Nullable
    private static Vec3 altarCenter(MinecraftServer server) {
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        return altarPos == null ? null
                : new Vec3(altarPos.getX() + 0.5D, altarPos.getY(), altarPos.getZ() + 0.5D);
    }

    private static Vec3 altarCenterOr(MinecraftServer server, Vec3 fallback) {
        Vec3 altar = altarCenter(server);
        return altar != null ? altar : fallback;
    }

    // ------------------------------------------------------------------ scheduler

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
                task.action().run(); // may schedule again — TASKS is not iterated here
            }
        }
    }

    private static void tickReplayLightning(MinecraftServer server) {
        if (REPLAY_LIGHTNING.isEmpty()) {
            return;
        }
        ServerLevel overworld = server.overworld();
        REPLAY_LIGHTNING.removeIf(controller -> !controller.tick(overworld));
    }

    // ------------------------------------------------------------------ replay (R12, FX-only)

    @Override
    public String sequenceId() {
        return SEQUENCE_ID;
    }

    @Override
    public List<String> phaseIds() {
        return List.of("ECLIPSE_ON", "FLIGHT", "APPROACH", "LIGHTNING", "BURST", "REVEAL", "SUNRISE");
    }

    /**
     * FX-only replays (see class contract): visuals, sounds, captions and camera paths like
     * the live phases, but LOCAL plays only (no gather teleports), raw storm payloads under
     * {@link #REPLAY_STORM_ID} (no registry writes), kickback off, no decor spawn, no
     * {@code IntroData}/{@code EclipseWorldState} writes.
     */
    @Override
    public boolean replay(MinecraftServer server, String phaseId, Collection<ServerPlayer> players) {
        List<ServerPlayer> watchers = List.copyOf(players);
        Vec3 center = vortexCenter(server);
        switch (phaseId.toUpperCase(Locale.ROOT)) {
            case "ECLIPSE_ON" -> {
                FxPayloads.sendEclipsePhase(server, ECLIPSE_TOTAL, 1.0F, ECLIPSE_ON_TICKS, permanentRim(server));
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player,
                            new S2CCaptionPayload(CAPTION_AWAKEN, 80, S2CCaptionPayload.STYLE_TITLE));
                    player.playNotifySound(EclipseSounds.EVENT_ECLIPSE_DRONE.get(), SoundSource.AMBIENT, 1.0F, 1.0F);
                }
                return true;
            }
            case "FLIGHT" -> {
                CutsceneService.play(PATH_FLIGHT, watchers, center, null, CutsceneService.PlayOptions.LOCAL);
                // The vortex rides raw client payloads: spawns mid-flight, gone at the end.
                schedule(server, VORTEX_SPAWN_TICK - ECLIPSE_ON_TICKS, () -> sendReplayStorm(watchers,
                        center, S2CStormStatePayload.STATE_SPAWN, StormRegistry.RAMP_TICKS));
                schedule(server, FLIGHT_DURATION_TICKS, () -> sendReplayStorm(watchers,
                        center, S2CStormStatePayload.STATE_DISSIPATE, VORTEX_DISSIPATE_TICKS));
                return true;
            }
            case "APPROACH" -> {
                captionPlayers(watchers, CAPTION_APPROACH, 130, S2CCaptionPayload.STYLE_SUBTITLE);
                return true;
            }
            case "LIGHTNING" -> {
                captionPlayers(watchers, CAPTION_STRIKE, 90, S2CCaptionPayload.STYLE_WHISPER);
                sendReplayStorm(watchers, center, S2CStormStatePayload.STATE_SPAWN, 20);
                REPLAY_LIGHTNING.add(new IntroLightningPhase(center, VORTEX_RADIUS, VORTEX_HEIGHT, false));
                schedule(server, IntroLightningPhase.DURATION_TICKS + 20, () -> sendReplayStorm(watchers,
                        center, S2CStormStatePayload.STATE_DISSIPATE, VORTEX_DISSIPATE_TICKS));
                return true;
            }
            case "BURST" -> {
                new IntroLightningPhase(center, VORTEX_RADIUS, VORTEX_HEIGHT, false)
                        .strike(server.overworld(), 1.0F, true);
                Vec3 altar = altarCenterOr(server, center);
                for (ServerPlayer player : watchers) {
                    PacketDistributor.sendToPlayer(player,
                            new S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE, center, 1.0F, 50.0F));
                    PacketDistributor.sendToPlayer(player, FLASH_WHITE);
                    PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(ALTAR_REVEAL_BURST, altar));
                }
                schedule(server, FLASH_VIOLET_DELAY_TICKS, () -> {
                    for (ServerPlayer player : watchers) {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player, FLASH_VIOLET);
                        }
                    }
                });
                sendReplayStorm(watchers, center, S2CStormStatePayload.STATE_DISSIPATE, VORTEX_DISSIPATE_TICKS);
                return true;
            }
            case "REVEAL" -> {
                CutsceneService.play(PATH_REVEAL, watchers, altarCenterOr(server, center), null,
                        CutsceneService.PlayOptions.LOCAL);
                return true;
            }
            case "SUNRISE" -> {
                FxPayloads.sendEclipsePhase(server, ECLIPSE_ENDING, 0.0F, SUNRISE_RAMP_TICKS, permanentRim(server));
                captionPlayers(watchers, CAPTION_BEGIN, 100, S2CCaptionPayload.STYLE_TITLE);
                return true;
            }
            default -> {
                return false;
            }
        }
    }

    /** Raw vortex storm payload to the replay watchers only — never touches StormRegistry. */
    private static void sendReplayStorm(Collection<ServerPlayer> players, Vec3 center, int state, int ticks) {
        S2CStormStatePayload payload = new S2CStormStatePayload(REPLAY_STORM_ID, center,
                VORTEX_RADIUS, VORTEX_HEIGHT, S2CStormStatePayload.TYPE_VORTEX, state, ticks);
        for (ServerPlayer player : players) {
            if (!player.hasDisconnected()) {
                PacketDistributor.sendToPlayer(player, payload);
            }
        }
    }

    private static void captionPlayers(Collection<ServerPlayer> players, String langKey, int ticks, int style) {
        for (ServerPlayer player : players) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(langKey, ticks, style));
        }
    }

    /** The persisted post-intro rim flag (replays must not force it on). */
    private static boolean permanentRim(MinecraftServer server) {
        return IntroData.get(server).isPermanentRim();
    }

    // ------------------------------------------------------------------ persisted phase

    /**
     * The intro sequence's own persisted state ({@code data/eclipse_intro_sequence.dat}):
     * {@code started}/{@code completed}/{@code phase} drive the restart-recovery contract
     * (skip to end state, never resume mid-cinematic), {@code permanentRim} is the login
     * re-send fallback until P4's world flag owns it (§6.3).
     */
    public static final class IntroData extends SavedData {
        static final String DATA_NAME = "eclipse_intro_sequence";
        private static final String TAG_STARTED = "started";
        private static final String TAG_COMPLETED = "completed";
        private static final String TAG_PHASE = "phase";
        private static final String TAG_PERMANENT_RIM = "permanentRim";

        private boolean started;
        private boolean completed;
        private String phase = "";
        private boolean permanentRim;

        public IntroData() {}

        static IntroData get(MinecraftServer server) {
            return server.overworld().getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(IntroData::new, IntroData::load), DATA_NAME);
        }

        static IntroData load(CompoundTag tag, HolderLookup.Provider registries) {
            IntroData data = new IntroData();
            data.started = tag.getBoolean(TAG_STARTED);
            data.completed = tag.getBoolean(TAG_COMPLETED);
            data.phase = tag.getString(TAG_PHASE);
            data.permanentRim = tag.getBoolean(TAG_PERMANENT_RIM);
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            tag.putBoolean(TAG_STARTED, this.started);
            tag.putBoolean(TAG_COMPLETED, this.completed);
            tag.putString(TAG_PHASE, this.phase);
            tag.putBoolean(TAG_PERMANENT_RIM, this.permanentRim);
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

        boolean isPermanentRim() {
            return this.permanentRim;
        }

        void setPermanentRim(boolean permanentRim) {
            this.permanentRim = permanentRim;
            setDirty();
        }
    }
}
