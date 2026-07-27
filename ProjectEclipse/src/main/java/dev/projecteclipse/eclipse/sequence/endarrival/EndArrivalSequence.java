package dev.projecteclipse.eclipse.sequence.endarrival;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.cutscene.CutscenePaths;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.end.EndConfig;
import dev.projecteclipse.eclipse.worldgen.end.EndDiscService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-077 "DER ALTAR RUFT DAS END" — the server-authoritative phase machine of the
 * End-arrival cinematic (~50 s). When the End-disc trigger fires,
 * {@code EndDiscService.materialize} hands its very first start to
 * {@link #interceptFirstMaterialize} instead of building straight away, so the sky
 * archipelago is summoned in the middle of a show rather than appearing between two ticks;
 * the REAL disc build (and its existing crash announce: global shake, dragon growl, chat
 * line) starts exactly at the phase-3 boundary, in sync with the debris spectacle.
 *
 * <p><b>Timeline</b> ({@code t} = ticks since the beat clock armed):</p>
 * <ol>
 *   <li>{@code OMEN} (t = 0 … {@value #OMEN_END}, 0–8 s) — Vorzeichen: violet suction
 *       streams collapse onto the altar from the whole surroundings
 *       ({@code CUE_SUCTION} + directed REVERSE_PORTAL baseline), a deep rumble rolls in,
 *       small shake pulses start.</li>
 *   <li>{@code CHARGE} (… {@value #CHARGE_END}, 8–20 s) — Aufladung: the altar trembles
 *       (the {@code erupt} altar-model trigger belongs here — see the WIRING comment),
 *       energy rings climb the column ({@code CUE_RINGS}), the violet pillar fires into
 *       the sky ({@code CUE_PILLAR}, Y-scaled to the real altar→rift gap) and the giant
 *       End-rift maw tears open at the rift point ({@code CUE_MAW}).</li>
 *   <li>{@code SPILL} (… {@value #SPILL_END}, 20–40 s) — der Altar spuckt das End aus:
 *       {@link EndArrivalDebrisFx} streams hundreds of end-stone chunks up the pillar and
 *       out of the rift onto the forming disc band while
 *       {@code EndDiscService.materialize} builds the real thing underneath; Endergeist
 *       wisps dance between the streams and violet obsidian lightning (the client-only
 *       {@code FX_LIGHTNING_STRIKE} ribbon bolt — white core, violet decay, no fire)
 *       strikes around the band.</li>
 *   <li>{@code FINALE} (… {@value #TOTAL_TICKS}, 40–50 s) — the rift snaps shut with an
 *       implosion flash + sky shockwave ring ({@code CUE_IMPLOSION} + the
 *       {@code FX_SHOCKWAVE} Veil radial distortion pulse), the pillar dissolves into
 *       falling glitter ({@code CUE_GLITTER}), a distant dragon roar rolls over the world
 *       and the caption announces the End.</li>
 * </ol>
 *
 * <p><b>Camera</b>: players within {@value #CUTSCENE_RANGE} blocks of the altar get the
 * guided {@code end_arrival} path ({@code PlayOptions.LOCAL} — nobody is teleported,
 * skippable); everyone else watches the sky-sized effects freely. The beat clock arms on
 * the first client preload-ready ACK (the {@code EndShatterSequence} law) with the shared
 * preload-timeout fallback, so the first beat lands after the black hold releases.</p>
 *
 * <p><b>Restart</b>: a server that dies BEFORE phase 3 comes back with
 * {@code materializationStarted} still false — the day trigger simply re-fires and the
 * show restarts from the top (the End has not arrived yet, so replaying the summon is the
 * truthful outcome). A server that dies AFTER phase 3 resumes the budgeted disc build
 * silently via {@code EndDiscService.onServerStarted} (firstStart is false, no intercept)
 * — the house "a restart skips to the end state" rule.</p>
 *
 * <p><b>FX replay</b> ({@code /dev event start endarrival fxonly}) runs the identical show
 * with {@code buildDisc = false}: no block is written and no state flag is committed.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndArrivalSequence {

    // ------------------------------------------------------------------ tick table

    /** Phase 1 ends here (8 s). */
    public static final int OMEN_END = 160;
    /** Phase 2 ends here (20 s). */
    public static final int CHARGE_END = 400;
    /** Phase 3 ends here (40 s). */
    public static final int SPILL_END = 800;
    /** The whole sequence ends here (50 s). */
    public static final int TOTAL_TICKS = 1000;

    // ------------------------------------------------------------------ tuning constants

    /** Charge sub-beats: rings at the boundary, then the pillar, then the maw tears open. */
    private static final int PILLAR_AT = 200;
    private static final int MAW_AT = 240;
    /** Finale sub-beats. */
    private static final int ROAR_AT = SPILL_END + 50;
    private static final int CAPTION_AT = SPILL_END + 70;

    /** The rift point sits this far above the disc surface, directly over the altar. */
    private static final int RIFT_CLEARANCE = 80;
    /** Guided-camera radius around the altar; beyond it the show plays free. */
    private static final double CUTSCENE_RANGE = 128.0D;
    private static final String CUTSCENE_ID = "end_arrival";

    /** Cadence of the shake pulse train (ticks) — the NetherOpeningSequence pattern. */
    private static final int SHAKE_INTERVAL_TICKS = 20;
    private static final float OMEN_SHAKE_MIN = 0.06F;
    private static final float OMEN_SHAKE_MAX = 0.22F;
    private static final float CHARGE_SHAKE_MIN = 0.28F;
    private static final float CHARGE_SHAKE_MAX = 0.60F;
    /** Phase 3 keeps a low simmer — the materialize announce fires its own 2.0 hit. */
    private static final float SPILL_SHAKE = 0.18F;
    private static final float FINALE_SHAKE_PEAK = 0.85F;
    private static final int FINALE_SHAKE_HOLD = 45;
    private static final float FINALE_SHAKE_TAIL = 0.12F;

    /** Photon cue re-fire cadence for the long-lived pillar/maw (dedup absorbs repeats). */
    private static final int LONG_CUE_REFIRE_TICKS = 100;
    /** Wisp / lightning cadences during the spill. */
    private static final int WISP_INTERVAL_TICKS = 25;
    private static final int LIGHTNING_INTERVAL_TICKS = 50;
    /** Server-particle baseline cadence (photon-less clients see these). */
    private static final int BASELINE_PARTICLE_INTERVAL = 8;

    /** Whole-dimension cue broadcast (the show is sky-sized). */
    private static final double CUE_RANGE_ALL = 0.0D;

    /** The one live run (one server, one arrival), or {@code null}. Server thread only. */
    @Nullable
    private static Run active;
    /**
     * Phase-3 re-entry latch: while the sequence itself calls
     * {@code EndDiscService.materialize}, {@link #interceptFirstMaterialize} must wave the
     * call through instead of claiming it again.
     */
    private static boolean buildingDisc;

    private EndArrivalSequence() {}

    // ------------------------------------------------------------------ public API

    /**
     * The {@code EndDiscService.materialize} first-start seam: claims the very first
     * materialization for the cinematic (the disc build then starts at the phase-3
     * boundary via the same method, latched through {@link #buildingDisc}).
     *
     * @return {@code true} = claimed, the caller must NOT build now; {@code false} = build
     *         normally (phase-3 re-entry, or the show could not start)
     */
    public static boolean interceptFirstMaterialize(MinecraftServer server) {
        if (buildingDisc) {
            return false; // the sequence's own phase-3 call: let the build begin
        }
        if (active != null) {
            return true; // show already running; the disc arrives with phase 3
        }
        return begin(server, true);
    }

    /**
     * Starts the arrival show. Refused (returns {@code false}) when one is already running.
     *
     * @param buildDisc {@code true} = phase 3 really materializes the End disc (the
     *                  trigger path); {@code false} = FX only, no block is written and no
     *                  state flag is committed ({@code /dev event start endarrival fxonly})
     */
    public static boolean begin(MinecraftServer server, boolean buildDisc) {
        if (active != null && active.server == server) {
            return false;
        }
        active = new Run(server.overworld(), buildDisc);
        active.start();
        EclipseMod.LOGGER.info(
                "End arrival sequence started (altar {}, rift {}, buildDisc={})",
                active.altarTop, active.rift, buildDisc);
        return true;
    }

    /** Aborts the show: debris is discarded, cutscenes released, no further beats. */
    public static void abort() {
        Run run = active;
        if (run != null) {
            EndArrivalDebrisFx.clearAll();
            List<ServerPlayer> inCutscene = new ArrayList<>();
            for (ServerPlayer player : run.overworld.players()) {
                if (CUTSCENE_ID.equals(CutsceneService.activePathId(player))) {
                    inCutscene.add(player);
                }
            }
            if (!inCutscene.isEmpty()) {
                CutsceneService.abort(inCutscene);
            }
            active = null;
            EclipseMod.LOGGER.info("End arrival sequence aborted");
        }
    }

    /** Whether the show is running right now (dev status / guards). */
    public static boolean isRunning() {
        return active != null;
    }

    /** Ticks elapsed in the running show, or {@code -1} while idle/holding for preload. */
    public static int elapsedTicks() {
        Run run = active;
        return run == null ? -1 : run.tick;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        if (active != null && active.server == event.getServer()) {
            active = null;
        }
        buildingDisc = false;
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        Run run = active;
        if (run == null || run.server != event.getServer()) {
            return;
        }
        if (run.tick()) {
            active = null;
        }
    }

    // ------------------------------------------------------------------ the run

    private static final class Run {
        private final MinecraftServer server;
        private final ServerLevel overworld;
        private final boolean buildDisc;
        /** Pillar base: the altar top center (fallback: terrain under the disc center). */
        private final Vec3 altarTop;
        /** Rift point: {@value #RIFT_CLEARANCE} blocks above the disc surface, over the altar. */
        private final Vec3 rift;
        /** Disc-band center at surface height (island targets ring around this). */
        private final Vec3 discCenter;
        private final double discRadius;
        private final float pillarHeight;
        private final RandomSource random;

        /**
         * Beat clock. {@code -1} = holding for the cutscene preload ACK (the
         * EndShatterSequence arming law); ticks only start counting once armed.
         */
        private int tick = -1;
        private boolean armed;
        private long armDeadline = Long.MAX_VALUE;
        @Nullable
        private Phase announced;

        private enum Phase { OMEN, CHARGE, SPILL, FINALE }

        Run(ServerLevel overworld, boolean buildDisc) {
            this.server = overworld.getServer();
            this.overworld = overworld;
            this.buildDisc = buildDisc;
            EndConfig.Snapshot config = EndConfig.current();
            BlockPos altarPos = EclipseWorldState.get(this.server).getSanctumAltarPos();
            if (altarPos == null) {
                // No sanctum yet (fresh dev world): seat the show on the terrain under the
                // disc center so every beat still has a stage.
                int groundY = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING,
                        config.centerX(), config.centerZ());
                altarPos = new BlockPos(config.centerX(), groundY, config.centerZ());
            }
            this.altarTop = Vec3.atCenterOf(altarPos.above());
            this.rift = new Vec3(this.altarTop.x,
                    config.surfaceY() + RIFT_CLEARANCE, this.altarTop.z);
            this.discCenter = new Vec3(config.centerX() + 0.5D, config.surfaceY(),
                    config.centerZ() + 0.5D);
            this.discRadius = config.radius();
            this.pillarHeight = (float) (this.rift.y - this.altarTop.y);
            this.random = overworld.getRandom();
        }

        /** Play the guided camera and arm the beat clock on the first preload-ready ACK. */
        void start() {
            List<ServerPlayer> near = new ArrayList<>();
            for (ServerPlayer player : this.overworld.players()) {
                if (!player.isSpectator() && player.position().distanceTo(this.altarTop)
                        <= CUTSCENE_RANGE) {
                    near.add(player);
                }
            }
            CutscenePath path = CutscenePaths.get(CUTSCENE_ID);
            int started = 0;
            if (path != null && CutsceneService.isEnabled(this.server, path) && !near.isEmpty()) {
                // LOCAL (nobody is teleported, skippable) with a view-distance bump: the
                // crane shots swing ~190 blocks (12 chunks) out from the viewer (the
                // limbo-ship LOCAL_ONLY + viewDistance precedent).
                started = CutsceneService.play(CUTSCENE_ID, near, this.altarTop, null,
                        new CutsceneService.PlayOptions(
                                CutsceneService.TeleportPolicy.LOCAL_ONLY, 12, false, true));
            }
            if (started > 0) {
                // The first beat waits for the black hold to release (or the timeout).
                this.armDeadline = this.overworld.getGameTime()
                        + CutsceneService.PRELOAD_TIMEOUT_TICKS;
                CutsceneService.onNextClientReady(CUTSCENE_ID, () -> this.armed = true);
            } else {
                this.armed = true; // nobody near / path disabled: run free immediately
            }
        }

        /** @return true once the sequence is finished and may be dropped. */
        boolean tick() {
            if (!this.armed) {
                if (this.overworld.getGameTime() < this.armDeadline) {
                    return false;
                }
                this.armed = true; // preload timeout fallback
            }
            this.tick++;
            Phase phase = phaseAt(this.tick);
            if (phase != this.announced) {
                this.announced = phase;
                enterPhase(phase);
            }
            switch (phase) {
                case OMEN -> tickOmen();
                case CHARGE -> tickCharge();
                case SPILL -> tickSpill();
                default -> tickFinale();
            }
            if (this.tick % SHAKE_INTERVAL_TICKS == 0) {
                shake(shakeAt(this.tick, phase), SHAKE_INTERVAL_TICKS + 5);
            }
            if (this.tick >= TOTAL_TICKS) {
                EndArrivalDebrisFx.clearAll(); // belt-and-braces; collapse already ended it
                EclipseMod.LOGGER.info("End arrival sequence finished");
                return true;
            }
            return false;
        }

        private static Phase phaseAt(int tick) {
            if (tick < OMEN_END) {
                return Phase.OMEN;
            }
            if (tick < CHARGE_END) {
                return Phase.CHARGE;
            }
            if (tick < SPILL_END) {
                return Phase.SPILL;
            }
            return Phase.FINALE;
        }

        private void enterPhase(Phase phase) {
            switch (phase) {
                case OMEN -> {
                    cue(EndArrivalFxCues.CUE_SUCTION, this.altarTop, 0.0F);
                    sound(this.altarTop, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                            SoundSource.AMBIENT, 2.4F, 0.4F);
                    sound(this.altarTop, SoundEvents.AMBIENT_CAVE.value(),
                            SoundSource.AMBIENT, 1.6F, 0.4F);
                    caption("eclipse.caption.end_arrival.omen", 90,
                            S2CCaptionPayload.STYLE_WHISPER);
                }
                case CHARGE -> {
                    // The altar itself physically erupts here (GeckoLib model animation).
                    dev.projecteclipse.eclipse.ritual.AltarModelTriggers.erupt(this.overworld);
                    cue(EndArrivalFxCues.CUE_RINGS, this.altarTop, 0.0F);
                    sound(this.altarTop, SoundEvents.PORTAL_TRIGGER,
                            SoundSource.AMBIENT, 2.4F, 0.55F);
                    sound(this.altarTop, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                            SoundSource.AMBIENT, 2.2F, 0.6F);
                }
                case SPILL -> {
                    if (this.buildDisc) {
                        // The REAL disc build starts here, in sync with the debris show.
                        // announceCrash fires inside (global 2.0 shake, dragon growl,
                        // thunder, the "announce.eclipse.end.arrival" chat line and the
                        // client EndIslandCrashFx timeline) — the phase-3 opening hit.
                        buildingDisc = true;
                        try {
                            EndDiscService.materialize(this.server);
                        } finally {
                            buildingDisc = false;
                        }
                    } else {
                        // FX replay keeps a comparable (local-only) opening hit.
                        shake(1.2F, 60);
                        sound(this.rift, SoundEvents.ENDER_DRAGON_GROWL,
                                SoundSource.HOSTILE, 4.0F, 0.55F);
                    }
                    EndArrivalDebrisFx.begin(this.overworld, this.altarTop, this.rift,
                            this.discCenter, this.discRadius);
                    caption("eclipse.caption.end_arrival.spill", 100,
                            S2CCaptionPayload.STYLE_SUBTITLE);
                }
                default -> {
                    EndArrivalDebrisFx.collapse(this.overworld);
                    cue(EndArrivalFxCues.CUE_IMPLOSION, this.rift, 0.0F);
                    cue(EndArrivalFxCues.CUE_GLITTER, this.altarTop, this.pillarHeight);
                    // Veil-Post radial distortion pulse: the world-anchored screen
                    // shockwave (EclipseFxState.startShockwave). 0.9/45 stays clear of
                    // the (>=1.0, >=50) intro-burst giant signature.
                    FxPayloads.sendFxEvent(this.overworld, FxPayloads.FX_SHOCKWAVE,
                            this.rift, 0.9F, 45.0F, CUE_RANGE_ALL);
                    shake(FINALE_SHAKE_PEAK, FINALE_SHAKE_HOLD);
                    sound(this.rift, EclipseSounds.EVENT_RIFT_THUD.get(),
                            SoundSource.AMBIENT, 4.0F, 0.9F);
                    sound(this.rift, SoundEvents.GENERIC_EXPLODE.value(),
                            SoundSource.AMBIENT, 3.0F, 0.6F);
                    this.overworld.sendParticles(ParticleTypes.EXPLOSION_EMITTER,
                            this.rift.x, this.rift.y, this.rift.z, 2, 4.0D, 4.0D, 4.0D, 0.0D);
                }
            }
        }

        // --- per-phase server ambience (the photon-less baseline: everyone sees this) ---

        private void tickOmen() {
            // Re-fire the suction one-shot on its ~90 t cadence (Photon dedup absorbs).
            if (this.tick > 0 && this.tick % 80 == 0) {
                cue(EndArrivalFxCues.CUE_SUCTION, this.altarTop, 0.0F);
            }
            if (this.tick % BASELINE_PARTICLE_INTERVAL != 0) {
                return;
            }
            // Directed suction streaks: single REVERSE_PORTAL particles born on a shell
            // around the altar with velocity pointing INWARD (count 0 = use delta as
            // velocity — the vanilla directed-particle idiom).
            for (int i = 0; i < 6; i++) {
                double angle = this.random.nextDouble() * Math.PI * 2.0D;
                double dist = 8.0D + this.random.nextDouble() * 10.0D;
                double y = this.altarTop.y + this.random.nextDouble() * 6.0D - 1.0D;
                double x = this.altarTop.x + Math.cos(angle) * dist;
                double z = this.altarTop.z + Math.sin(angle) * dist;
                Vec3 toAltar = new Vec3(this.altarTop.x - x, this.altarTop.y + 1.0D - y,
                        this.altarTop.z - z).normalize();
                this.overworld.sendParticles(ParticleTypes.REVERSE_PORTAL, x, y, z,
                        0, toAltar.x, toAltar.y, toAltar.z, 0.4D);
            }
            this.overworld.sendParticles(ParticleTypes.PORTAL,
                    this.altarTop.x, this.altarTop.y + 0.6D, this.altarTop.z,
                    8, 0.8D, 0.5D, 0.8D, 0.15D);
            if (this.tick % 64 == 0) {
                sound(this.altarTop, SoundEvents.PORTAL_AMBIENT,
                        SoundSource.AMBIENT, 1.4F, 0.5F);
            }
        }

        private void tickCharge() {
            if (this.tick == PILLAR_AT) {
                cue(EndArrivalFxCues.CUE_PILLAR, this.altarTop, this.pillarHeight);
                sound(this.altarTop, SoundEvents.BEACON_ACTIVATE,
                        SoundSource.AMBIENT, 3.0F, 0.55F);
                sound(this.altarTop, EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                        SoundSource.AMBIENT, 3.0F, 0.7F);
                shake(0.65F, 30);
            } else if (this.tick == MAW_AT) {
                cue(EndArrivalFxCues.CUE_MAW, this.rift, 0.0F);
                sound(this.rift, SoundEvents.END_PORTAL_SPAWN,
                        SoundSource.AMBIENT, 4.0F, 0.6F);
                sound(this.rift, EclipseSounds.EVENT_RIFT_DRONE.get(),
                        SoundSource.AMBIENT, 2.6F, 0.5F);
                // A first, smaller distortion ring as the sky tears.
                FxPayloads.sendFxEvent(this.overworld, FxPayloads.FX_SHOCKWAVE,
                        this.rift, 0.5F, 25.0F, CUE_RANGE_ALL);
                caption("eclipse.caption.end_arrival.rift", 90,
                        S2CCaptionPayload.STYLE_SUBTITLE);
            }
            if (this.tick % BASELINE_PARTICLE_INTERVAL == 0) {
                // END_ROD sparks racing UP the (future/live) pillar column.
                if (this.tick >= PILLAR_AT) {
                    for (int i = 0; i < 4; i++) {
                        double frac = this.random.nextDouble();
                        double y = Mth.lerp(frac, this.altarTop.y, this.rift.y);
                        this.overworld.sendParticles(ParticleTypes.END_ROD,
                                this.altarTop.x + (this.random.nextDouble() - 0.5D) * 3.0D, y,
                                this.altarTop.z + (this.random.nextDouble() - 0.5D) * 3.0D,
                                0, 0.0D, 1.0D, 0.0D, 0.9D);
                    }
                }
                this.overworld.sendParticles(ParticleTypes.PORTAL,
                        this.altarTop.x, this.altarTop.y + 0.6D, this.altarTop.z,
                        14, 1.0D, 0.6D, 1.0D, 0.3D);
            }
        }

        private void tickSpill() {
            refireLongCues();
            // Endergeist wisps dancing between the debris streams (random point on the
            // altar→rift column, biased toward the rift where the streams fan out).
            if (this.tick % WISP_INTERVAL_TICKS == 0) {
                double frac = 0.3D + this.random.nextDouble() * 0.7D;
                Vec3 at = new Vec3(
                        Mth.lerp(frac, this.altarTop.x, this.rift.x)
                                + (this.random.nextDouble() - 0.5D) * 24.0D,
                        Mth.lerp(frac, this.altarTop.y, this.rift.y),
                        Mth.lerp(frac, this.altarTop.z, this.rift.z)
                                + (this.random.nextDouble() - 0.5D) * 24.0D);
                cue(EndArrivalFxCues.CUE_WISP, at, 0.0F);
            }
            // Violet obsidian lightning around the forming band (client ribbon bolt:
            // white core, violet decay, no fire, no damage).
            if (this.tick % LIGHTNING_INTERVAL_TICKS == 0) {
                double angle = this.random.nextDouble() * Math.PI * 2.0D;
                double radius = this.discRadius * (0.5D + this.random.nextDouble() * 0.7D);
                Vec3 impact = new Vec3(
                        this.discCenter.x + Math.cos(angle) * radius,
                        this.discCenter.y + 2.0D,
                        this.discCenter.z + Math.sin(angle) * radius);
                FxPayloads.sendFxEvent(this.overworld, FxPayloads.FX_LIGHTNING_STRIKE,
                        impact, 0.8F, 0.0F, CUE_RANGE_ALL);
                sound(impact, SoundEvents.LIGHTNING_BOLT_THUNDER,
                        SoundSource.WEATHER, 2.6F, 0.5F + this.random.nextFloat() * 0.2F);
                sound(impact, EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                        SoundSource.AMBIENT, 1.8F, 0.6F);
            }
            if (this.tick % BASELINE_PARTICLE_INTERVAL == 0) {
                // Rift mouth exhale: dragon breath + portal swirl pouring out.
                this.overworld.sendParticles(ParticleTypes.DRAGON_BREATH,
                        this.rift.x, this.rift.y - 2.0D, this.rift.z,
                        6, 6.0D, 2.5D, 6.0D, 0.02D);
                this.overworld.sendParticles(ParticleTypes.PORTAL,
                        this.rift.x, this.rift.y, this.rift.z, 10, 8.0D, 3.0D, 8.0D, 0.4D);
            }
        }

        private void tickFinale() {
            if (this.tick == ROAR_AT) {
                // The distant dragon: EclipseDragonFight formally begins once the budgeted
                // build completes (minutes later) — this roar is its herald.
                sound(this.rift, SoundEvents.ENDER_DRAGON_GROWL,
                        SoundSource.HOSTILE, 3.4F, 0.5F);
                for (ServerPlayer player : this.overworld.players()) {
                    player.playNotifySound(SoundEvents.ENDER_DRAGON_GROWL,
                            SoundSource.MASTER, 0.8F, 0.5F);
                }
            } else if (this.tick == CAPTION_AT) {
                caption("eclipse.caption.end_arrival.arrived", 110,
                        S2CCaptionPayload.STYLE_TITLE);
            }
            if (this.tick % 5 == 0) {
                // The pillar dissolving: falling END_ROD glitter along the column.
                for (int i = 0; i < 3; i++) {
                    double frac = this.random.nextDouble();
                    double y = Mth.lerp(frac, this.altarTop.y, this.rift.y);
                    this.overworld.sendParticles(ParticleTypes.END_ROD,
                            this.altarTop.x + (this.random.nextDouble() - 0.5D) * 5.0D, y,
                            this.altarTop.z + (this.random.nextDouble() - 0.5D) * 5.0D,
                            0, 0.0D, -1.0D, 0.0D, 0.25D);
                }
            }
        }

        /** Pillar and maw are long one-shots; re-fire on a cadence for late joiners. */
        private void refireLongCues() {
            if (this.tick % LONG_CUE_REFIRE_TICKS == 0) {
                cue(EndArrivalFxCues.CUE_PILLAR, this.altarTop, this.pillarHeight);
                cue(EndArrivalFxCues.CUE_MAW, this.rift, 0.0F);
            }
        }

        /** Shake amplitude for this tick before the client's own distance falloff. */
        private float shakeAt(int tick, Phase phase) {
            return switch (phase) {
                case OMEN -> Mth.lerp(tick / (float) OMEN_END, OMEN_SHAKE_MIN, OMEN_SHAKE_MAX);
                case CHARGE -> Mth.lerp((tick - OMEN_END) / (float) (CHARGE_END - OMEN_END),
                        CHARGE_SHAKE_MIN, CHARGE_SHAKE_MAX);
                case SPILL -> SPILL_SHAKE;
                default -> {
                    int local = tick - SPILL_END;
                    yield local <= FINALE_SHAKE_HOLD ? FINALE_SHAKE_PEAK
                            : Mth.lerp((local - FINALE_SHAKE_HOLD)
                                            / (float) (TOTAL_TICKS - SPILL_END - FINALE_SHAKE_HOLD),
                                    FINALE_SHAKE_PEAK, FINALE_SHAKE_TAIL);
                }
            };
        }

        // --- send helpers ---

        private void cue(net.minecraft.resources.ResourceLocation id, Vec3 pos, float a) {
            FxPayloads.sendFxEvent(this.overworld, id, pos, a, 0.0F, CUE_RANGE_ALL);
        }

        private void shake(float strength, int ticks) {
            PacketDistributor.sendToPlayersInDimension(this.overworld,
                    S2CShakePayload.shake(strength, ticks));
        }

        private void caption(String key, int ticks, int style) {
            PacketDistributor.sendToPlayersInDimension(this.overworld,
                    new S2CCaptionPayload(key, ticks, style));
        }

        private void sound(Vec3 at, SoundEvent sound, SoundSource source, float volume,
                float pitch) {
            this.overworld.playSound(null, at.x, at.y, at.z, sound, source, volume, pitch);
        }
    }
}
