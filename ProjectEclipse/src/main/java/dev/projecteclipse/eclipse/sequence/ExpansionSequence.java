package dev.projecteclipse.eclipse.sequence;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.awards.AwardService;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.cutscene.CutscenePaths;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.cutscene.SequenceReplayable;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.network.growth.GrowthPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.GrowthPacing;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * MAP-EXPANSION SEQUENCE v2 (P2 R11, worker W7) — the server-side phase machine that turns a
 * committed stage growth into a cinematic event. Replaces the v1 {@code UnlockCinematics}
 * (deleted; its {@link WorldStageService.GrowthStartListener} trigger and the
 * {@code cutscenes.freezeDuringUnlocks} / {@code intro_fusion} guards are absorbed here).
 *
 * <p><b>Timeline per R11</b> (animated GROW commits of the overworld; nether commits run a
 * reduced, cutscene-less variant — see below):</p>
 * <ol>
 *   <li>{@code SKYWARD} (~100 ticks) — every watcher is frozen by the cutscene engine and the
 *       player-anchored {@code expansion_skyward} shot launches their camera skyward (FOV
 *       rush, per-watcher {@code cutscene_veil} punch-through burst at
 *       {@value #SKYWARD_PUNCH_T} of the flight, apex curvature reveal) before tilting up
 *       into the darkening sky while the eclipse grade ramps in
 *       ({@code S2CEclipsePhasePayload} BUILDUP, 0 → 1 over 60
 *       ticks, R16) and {@code event.eclipse_drone} starts (path event). Nether players are
 *       first transported to a safe overworld viewpoint just inside the old rim
 *       ({@link FreezeService#transport}, R12 policy) so they see everything; their origin is
 *       persisted in {@link NetherReturns} for a crash-safe return.</li>
 *   <li>{@code FLYOVER} (~220 ticks) — the world-anchored {@code expansion_flyover} shot plays
 *       as a GLOBAL_TELEPORT group play (far players gathered behind a fade and returned after,
 *       view-distance bump); its play anchor comes from the {@code "growth_front"}
 *       {@linkplain CutsceneService#registerDynamicAnchor dynamic anchor} fed by
 *       {@link RingGrowthService#progressFraction}. Missing/disabled path degrades to the
 *       reshot {@code unlock_ring} orbit at the ring edge nearest each watcher (v1 shape).</li>
 *   <li>{@code GROWTH} — control returns while the ring sweep keeps animating; the client half
 *       of this class ({@link ClientHooks}) consumes {@code S2CGrowthWavePayload} pulses and
 *       walks the {@code growth_dust_wall} curtain emitter along the wave arc (SEQUENCE budget
 *       channel, ≤ 2 spawns per pulse, 96-block spawn radius). P1's own materialize bursts and
 *       rumble shakes continue untouched.</li>
 *   <li>{@code STRUCTURES} — after P1's terrain-done callback (and a
 *       {@value #STRUCTURES_ESTABLISH_TICKS}-tick wide establishing gap so the caption and
 *       the open sky read first), every {@link PendingSite} of the
 *       stage gets a sequential rift-drop beat: close the enqueue-time ground tear, let the
 *       close read for {@value #GROUND_TEAR_HANDOFF_TICKS} ticks, open a
 *       {@code STYLE_STRUCTURE} rift in the sky above the site (width = footprint · 1.7 per the
 *       payload contract), hold {@value #RIFT_HOLD_TICKS} ticks, {@link
 *       StructurePendingRegistry#trigger} the paste, then on PLACED slam:
 *       {@code structure_slam_dust} + {@code fx/shockwave (0.5, 30)} + {@code event.rift_slam}
 *       + shake 0.4, rift closes. Beats are spaced so pastes never stack in one tick; a beat
 *       whose placement never lands times out and only closes its rift (the registry's
 *       auto-delay still guarantees placement — graceful degradation per plan §6.1).</li>
 *   <li>{@code END} — eclipse grade releases (ENDING → 0 over 100 ticks), transported nether
 *       players fade home and lose their invulnerability, and the daily-award head-roulette
 *       timing hook fires ({@link AwardService#sendRevealNow} — P3 renders the overlay). The
 *       chat unlock list needs no work here: {@code timeline.AnnouncementService}'s stage
 *       listener already announces finished GROW sweeps + new unlock keys (localized).</li>
 * </ol>
 *
 * <p><b>Restart safety</b>: all run state is transient — a mid-sequence restart skips straight
 * to the end state (freezes are transient attachments, the registry's persisted pending sites
 * place via auto-delay, the eclipse grade resets client-side on rejoin) except the nether
 * returns, which persist in {@link NetherReturns} and apply at the player's next login.</p>
 *
 * <p><b>Replay</b> (R12): registered as {@link SequenceReplayable} id {@code "expansion"} —
 * {@code /eclipsefx sequence expansion <phase>} replays each phase FX-only (no world mutation,
 * no teleports, no {@code trigger()} calls, no award state writes).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ExpansionSequence implements SequenceReplayable {
    // --- frozen ids ---
    private static final String SEQUENCE_ID = "expansion";
    private static final String PATH_SKYWARD = "expansion_skyward";
    private static final String PATH_FLYOVER = "expansion_flyover";
    private static final String PATH_FALLBACK = "unlock_ring";
    private static final String DYNAMIC_ANCHOR_KEY = "growth_front";

    private static final ResourceLocation GROWTH_DUST_WALL = emitter("growth_dust_wall");
    private static final ResourceLocation STRUCTURE_SLAM_DUST = emitter("structure_slam_dust");
    /** IDEA-14 §2: gravity debris arcing out of the closing sky tear after a slam. */
    private static final ResourceLocation SLAM_DEBRIS = emitter("slam_debris");
    /**
     * IDEA-14 §3: one-shot new-land glow cue (a = innerR, b = outerR of the fresh annulus).
     * Defined here because {@code FxPayloads} is shared — its 2-line {@code handleFxEvent}
     * dispatch (→ {@link ClientHooks#handleNewLandGlow}) is a documented W4-ATMOS wiring ask.
     */
    private static final ResourceLocation FX_NEW_LAND_GLOW =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/new_land_glow");

    private static final String CAPTION_SKYWARD = "eclipse.caption.expansion.skyward";
    private static final String CAPTION_GROWING = "eclipse.caption.expansion.growing";
    private static final String CAPTION_STRUCTURES = "eclipse.caption.expansion.structures";
    private static final String CAPTION_DONE = "eclipse.caption.expansion.done";
    private static final String CAPTION_NETHER_RETURN = "eclipse.caption.expansion.nether_return";

    // --- eclipse phases (S2CEclipsePhasePayload contract: 0=NONE 1=BUILDUP 2=TOTAL 3=ENDING) ---
    private static final int ECLIPSE_BUILDUP = 1;
    private static final int ECLIPSE_TOTAL = 2;
    private static final int ECLIPSE_ENDING = 3;

    // --- beat timing (R11) ---
    /** Rift hold between tear-open and the placement trigger ("40-tick hold"). */
    private static final int RIFT_HOLD_TICKS = 40;
    /** Delay between the slam FX and the rift-close event (lets the slam read first). */
    private static final int RIFT_CLOSE_DELAY_TICKS = 8;
    /** Spacing between consecutive structure beats (staggers paste cost like the registry). */
    private static final int BEAT_SPACING_TICKS = 50;
    /** A triggered beat whose PLACED never lands is abandoned after this (async placers). */
    private static final int BEAT_TIMEOUT_TICKS = 1200;
    /** Sky-rift altitude above the site's surface (STRUCTURE rifts open flat in the sky, R11). */
    private static final int SKY_RIFT_HEIGHT = 26;
    /** Rift width from the pending site's footprint (payload contract: diagonal · 1.2 ≈ · 1.7). */
    private static final float RIFT_WIDTH_PER_FOOTPRINT = 1.7F;

    // --- CUT-EXPANSION camera-facing beat timing (shots 1/2/3/4 — fxteams/CUT-EXPANSION.md) ---
    /** Skyward flight fraction of the cloud punch-through (mirrors the path's veil-fade t). */
    private static final double SKYWARD_PUNCH_T = 0.40D;
    /** Camera altitude above the watcher at the punch (the path's y offset around that t). */
    private static final double SKYWARD_PUNCH_HEIGHT = 30.0D;
    /** Flyover flight fraction at which the camera is lowest (skim deck; anchor-lead aim point). */
    private static final double FLYOVER_SKIM_T = 0.5D;
    /** Wide establishing gap between the STRUCTURES caption and the first tear. */
    private static final int STRUCTURES_ESTABLISH_TICKS = 20;
    /** Ground-tear close → sky-tear open stagger (lets the close animation read first). */
    private static final int GROUND_TEAR_HANDOFF_TICKS = 6;
    /** unlock_ring flight fraction of the god-ray backlight moment (mirrors the bloom-fade t). */
    private static final double RING_HERO_T = 0.58D;
    /** FX-only replay: representative delivery-flight length between the trigger and the slam. */
    private static final int REPLAY_FLIGHT_TICKS = 45;
    /** FX-only replay: landing micro-shake offsets after the trigger moment (live: per piece). */
    private static final int[] REPLAY_LANDING_SHAKES_AT = {16, 28, 38};

    // --- IDEA-14 §2: three-beat crater read (rings + debris; 15 spawns/20 ticks ≤ BURST cap) ---
    /** Expanding dust rings after the slam: inner ring at t+6, outer ring at t+12. */
    private static final int SLAM_RING_1_DELAY = 6;
    private static final int SLAM_RING_2_DELAY = 12;
    private static final int SLAM_RING_POINTS = 6;
    /** Ring radii as fractions of the site footprint. */
    private static final double SLAM_RING_1_RADIUS = 0.35D;
    private static final double SLAM_RING_2_RADIUS = 0.6D;
    /** Debris rain out of the closing sky tear (t+8 / t+20 after the slam). */
    private static final int DEBRIS_DELAY_1 = 8;
    private static final int DEBRIS_DELAY_2 = 20;
    /** Representative footprint used by the FX-only replay's fake beat. */
    private static final int REPLAY_FOOTPRINT = 24;

    // --- PH-RIFT (photon/IDEAS-events.md #4): growth-wavefront front rider ---
    /** Tag on the front-rider display — strays from a crash are swept on entity load. */
    public static final String GROWTH_RIDER_TAG = "eclipse_growth_rider";
    /** Rider sits this far inside the live front radius (height lookup on written terrain). */
    private static final int GROWTH_RIDER_INSET_BLOCKS = 4;
    /** Attach-cue rebroadcast cadence while the rider lives (covers mid-sweep joiners). */
    private static final int GROWTH_RIDER_ANNOUNCE_TICKS = 100;

    /** How far inside the OLD rim transported nether players are parked (safe, pre-existing terrain). */
    private static final int VIEWPOINT_INSET_BLOCKS = 24;
    /** Invuln-only TTL granted to transported nether players; refreshed while the run lives. */
    private static final int NETHER_INVULN_TTL_TICKS = 400;
    private static final int NETHER_INVULN_REFRESH_TICKS = 100;
    /** Watchdog: a run whose sweep/structures stall is force-ended after this many ticks. */
    private static final int RUN_TIMEOUT_TICKS = 20 * 60 * 30;

    private static final S2CScreenFadePayload GATHER_FADE = new S2CScreenFadePayload(8, 30, 18, 0xFF000000);
    private static final S2CScreenFadePayload RETURN_FADE = new S2CScreenFadePayload(8, 20, 16, 0xFF000000);

    private static final ExpansionSequence INSTANCE = new ExpansionSequence();
    private static final AtomicBoolean LISTENERS_REGISTERED = new AtomicBoolean();

    /** Active runs by disc profile. Server thread only. */
    private static final Map<DiscProfile, Run> RUNS = new HashMap<>();
    /** Simple tick scheduler for beat delays. Server thread only. */
    private static final List<Task> TASKS = new ArrayList<>();
    /** Live front-rider UUIDs (stray-sweep doctrine, mirrors StructureFlightFx). */
    private static final Set<UUID> LIVE_RIDERS = new HashSet<>();

    private ExpansionSequence() {}

    private static ResourceLocation emitter(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name);
    }

    // ------------------------------------------------------------------ wiring

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENERS_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addGrowthStartListener(ExpansionSequence::onGrowthStart);
            WorldStageService.addListener(ExpansionSequence::onStageTerrainComplete);
            StructurePendingRegistry.addListener(ExpansionSequence::onSitePhase);
            CutsceneService.registerDynamicAnchor(DYNAMIC_ANCHOR_KEY, ExpansionSequence::resolveGrowthFront);
            SequenceReplayable.Registry.register(INSTANCE);
            EclipseMod.LOGGER.info("ExpansionSequence registered (growth-start + stage + site listeners, "
                    + "dynamic anchor '{}', replay id '{}')", DYNAMIC_ANCHOR_KEY, SEQUENCE_ID);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // Statics must never leak into the next world a singleplayer client opens.
        RUNS.clear();
        TASKS.clear();
        LIVE_RIDERS.clear();
    }

    /** OarAnimator sweep doctrine: a tagged front rider we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(GROWTH_RIDER_TAG)
                && !LIVE_RIDERS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    // ------------------------------------------------------------------ phase machine

    private enum Phase { SKYWARD, FLYOVER, GROWTH, STRUCTURES, END }

    /** One live expansion event of a disc profile. All access on the server thread. */
    private static final class Run {
        final ServerLevel level;
        final DiscProfile profile;
        final int fromStage;
        final int toStage;
        /** Full cinematic treatment (cutscenes + nether transport) — overworld commits only. */
        final boolean cinematic;
        /** World angle (radians) the front viewpoint/anchor sits at (average watcher angle). */
        final double frontAngle;
        final long startedAtTick;

        Phase phase = Phase.SKYWARD;
        boolean terrainComplete;
        /** A front cutscene (flyover OR the ring fallback) carried the growing caption. */
        boolean flyoverPlayed;
        /** STRUCTURES establishing-gap gate: no beat may open before this (CUT-EXPANSION). */
        boolean firstBeatReleased;
        boolean ended;

        /** Sites awaiting their rift-drop beat, in PENDING order. */
        final ArrayDeque<PendingSite> beatQueue = new ArrayDeque<>();
        @Nullable
        Beat activeBeat;

        /** PH-RIFT: invisible front-rider display the wavefront ribbon anchors to (GROWTH). */
        @Nullable
        Display.BlockDisplay growthRider;

        /** Players transported out of the nether for this event (returned at END / next login). */
        final Set<UUID> netherVisitors = new HashSet<>();

        Run(ServerLevel level, DiscProfile profile, int fromStage, int toStage, boolean cinematic,
                double frontAngle) {
            this.level = level;
            this.profile = profile;
            this.fromStage = fromStage;
            this.toStage = toStage;
            this.cinematic = cinematic;
            this.frontAngle = frontAngle;
            this.startedAtTick = level.getServer().getTickCount();
        }
    }

    /** One in-flight structure rift-drop beat. */
    private static final class Beat {
        final PendingSite site;
        final Vec3 riftPos;
        final Vec3 slamPos;

        Beat(PendingSite site, Vec3 riftPos, Vec3 slamPos) {
            this.site = site;
            this.riftPos = riftPos;
            this.slamPos = slamPos;
        }
    }

    /**
     * Growth-start trigger (absorbed from v1 {@code UnlockCinematics}): only ANIMATED, GROWING
     * commits are cinematic; the {@code cutscenes.freezeDuringUnlocks} dev toggle and the
     * intro-fusion stage (the start event owns that cinematography) are respected unchanged.
     */
    private static void onGrowthStart(ServerLevel level, DiscProfile profile, int fromStage,
            int toStage, boolean animate) {
        // Any new commit supersedes a run still in flight for this profile (its sweep was
        // cancelled by WorldStageService) — clean up before deciding whether to start anew.
        Run previous = RUNS.remove(profile);
        if (previous != null) {
            abortRun(previous, "superseded by " + profile.name() + " " + fromStage + " -> " + toStage);
        }
        if (!animate || toStage <= fromStage) {
            if (previous != null) {
                returnNetherVisitors(previous.level.getServer(), previous);
            }
            return; // instant stamps and erases are not cinematic (v1 contract)
        }
        if (!EclipseConfig.freezeDuringUnlocks()) {
            EclipseMod.LOGGER.info("ExpansionSequence: cutscenes.freezeDuringUnlocks is off — skipping");
            if (previous != null) {
                returnNetherVisitors(previous.level.getServer(), previous);
            }
            return;
        }
        EclipseConfig.StageEntry entry = EclipseConfig.stage(profile.name(), toStage);
        if (entry != null && "intro_fusion".equals(entry.trigger())) {
            if (previous != null) {
                returnNetherVisitors(previous.level.getServer(), previous);
            }
            return; // the start-event intro owns that moment
        }

        boolean cinematic = profile == DiscProfile.OVERWORLD;
        Run run = new Run(level, profile, fromStage, toStage, cinematic,
                averageAngle(level.players()));
        if (previous != null) {
            run.netherVisitors.addAll(previous.netherVisitors); // carry the visitors over
        }
        RUNS.put(profile, run);
        EclipseMod.LOGGER.info("ExpansionSequence: {} growth {} -> {} — starting {} run",
                profile.name(), fromStage, toStage, cinematic ? "cinematic" : "reduced (no cutscenes)");
        beginSkyward(run);
    }

    /** SKYWARD: eclipse grade on, nether players brought over, cameras tilt to the sky. */
    private static void beginSkyward(Run run) {
        MinecraftServer server = run.level.getServer();
        run.phase = Phase.SKYWARD;
        FxPayloads.sendEclipsePhase(server, ECLIPSE_BUILDUP, 1.0F, 60, permanentRim(server));

        if (!run.cinematic) {
            // Reduced nether run: grade + caption only; growth FX ride the wave payloads.
            captionDimension(run.level, CAPTION_GROWING, 90);
            beginGrowth(run);
            return;
        }

        gatherNetherPlayers(run);
        captionDimension(run.level, CAPTION_SKYWARD, 90);
        List<ServerPlayer> watchers = List.copyOf(run.level.players());
        // Player-anchored path: every watcher launches skyward from their own feet. The
        // callback runs synchronously when the path is missing/disabled or nobody watches —
        // never softlocks.
        CutsceneService.play(PATH_SKYWARD, watchers, null, () -> beginFlyover(run),
                CutsceneService.PlayOptions.LOCAL);
        scheduleSkywardPunch(server, run, watchers);
    }

    /**
     * CUT-EXPANSION shot 1: the cloud-layer punch-through — one {@code cutscene_veil} wisp
     * burst per watcher at the camera's approximate punch altitude, timed to the skyward
     * path's veil-fade event ({@value #SKYWARD_PUNCH_T} of the flight). The server tick and
     * the client flight clock can drift by the preload hold, but the skyward path is anchored
     * at the watcher's own (already loaded) position, so the hold releases ~immediately and
     * the burst lands inside the fade window. Skipped when the path is missing/disabled — the
     * play callback already ran synchronously and a burst would flash over free gameplay.
     * One spawn per watcher, sent to that watcher only (others' cameras are at their own
     * feet — a remote burst would be subpixel); reducedFx clients budget it like any other
     * one-shot Quasar payload.
     */
    private static void scheduleSkywardPunch(MinecraftServer server, @Nullable Run run,
            List<ServerPlayer> watchers) {
        CutscenePath skyward = CutscenePaths.get(PATH_SKYWARD);
        if (skyward == null || !CutsceneService.isEnabled(server, skyward) || watchers.isEmpty()) {
            return;
        }
        schedule(server, (int) (skyward.durationTicks() * SKYWARD_PUNCH_T), () -> {
            if (run != null && (run.ended || RUNS.get(run.profile) != run)) {
                return;
            }
            for (ServerPlayer watcher : watchers) {
                if (!watcher.hasDisconnected()) {
                    PacketDistributor.sendToPlayer(watcher, new S2CQuasarPayload(
                            S2CQuasarPayload.CUTSCENE_VEIL,
                            watcher.position().add(0.0D, SKYWARD_PUNCH_HEIGHT, 0.0D)));
                }
            }
        });
    }

    /** FLYOVER: global group play toward the {@code growth_front} dynamic anchor. */
    private static void beginFlyover(Run run) {
        if (run.ended || RUNS.get(run.profile) != run) {
            return;
        }
        MinecraftServer server = run.level.getServer();
        run.phase = Phase.FLYOVER;
        FxPayloads.sendEclipsePhase(server, ECLIPSE_TOTAL, 1.0F, 20, permanentRim(server));

        List<ServerPlayer> watchers = List.copyOf(run.level.players());
        CutscenePath flyover = CutscenePaths.get(PATH_FLYOVER);
        if (flyover != null && CutsceneService.isEnabled(server, flyover) && !watchers.isEmpty()) {
            run.flyoverPlayed = true;
            // GLOBAL_TELEPORT + returnAfter: far watchers are gathered behind a fade and
            // restored when their session ends; the transported nether visitors were parked
            // inside the gather radius on purpose, so W2 never re-snapshots them — their
            // return stays ours (NetherReturns) at END.
            CutsceneService.play(PATH_FLYOVER, watchers, null, () -> beginGrowth(run),
                    CutsceneService.PlayOptions.global(12));
            return;
        }

        // Fallback: the reshot unlock_ring hero orbit at the old ring edge nearest each
        // watcher (v1 shape). Per-player plays share no group, so GROWTH is entered on a timer.
        CutscenePath fallback = CutscenePaths.get(PATH_FALLBACK);
        int fallbackTicks = 0;
        if (fallback != null && CutsceneService.isEnabled(server, fallback) && !watchers.isEmpty()) {
            // CUT-EXPANSION beat timing: the growing caption belongs INSIDE the orbit — it
            // used to arrive from beginGrowth only after the shot had already ended.
            run.flyoverPlayed = true;
            captionDimension(run.level, CAPTION_GROWING, 90);
            int edgeRadius = StageRadii.radius(run.profile, run.fromStage);
            int heroTick = (int) (fallback.durationTicks() * RING_HERO_T);
            for (ServerPlayer player : watchers) {
                Vec3 edge = edgeAnchorFor(run.level, player.position(), edgeRadius);
                CutsceneService.play(PATH_FALLBACK, List.of(player), edge, null);
                // Shot 4's god-ray backlight moment: one wisp flare at the orbited edge,
                // timed to the path's bloom-fade beat (RING_HERO_T). Per-watcher anchor and
                // per-watcher send — a single spawn each, budget-trivial.
                schedule(server, heroTick, () -> {
                    if (!run.ended && !player.hasDisconnected()) {
                        PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(
                                S2CQuasarPayload.CUTSCENE_VEIL, edge.add(0.0D, 4.0D, 0.0D)));
                    }
                });
            }
            fallbackTicks = fallback.durationTicks() + 20;
            EclipseMod.LOGGER.info("ExpansionSequence: '{}' unavailable — fell back to '{}' for {} watcher(s)",
                    PATH_FLYOVER, PATH_FALLBACK, watchers.size());
        }
        schedule(server, fallbackTicks, () -> beginGrowth(run));
    }

    /** GROWTH: control returns; the sweep animates on; dust wall rides the wave client-side. */
    private static void beginGrowth(Run run) {
        if (run.ended || RUNS.get(run.profile) != run) {
            return;
        }
        // CutsceneService returns ordinary flyover gathers before this callback; nether
        // visitors deliberately remain at the viewpoint until END.
        run.phase = Phase.GROWTH;
        if (run.cinematic && !run.flyoverPlayed) {
            // Both front shots (flyover AND the ring fallback) carry this caption themselves.
            captionDimension(run.level, CAPTION_GROWING, 90);
        }
        if (run.terrainComplete) {
            beginStructures(run); // tiny sweeps can finish before the cutscenes do
            return;
        }
        // PH-RIFT (IDEAS-events #4): cinematic overworld sweeps get the traveling-wavefront
        // front rider from here (control has returned; the flyover already showed the
        // front). Nether reduced runs skip it — no cinematic. Quasar pulse curtains keep
        // running underneath either way (LAYER law).
        if (run.cinematic) {
            spawnGrowthRider(run);
        }
    }

    /** Stage listener (absorbs v1's completion hook): terrain done → STRUCTURES. */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (toStage <= fromStage) {
            return; // erase sweeps are silent here
        }
        Run run = RUNS.get(profile);
        if (run == null || run.ended) {
            return; // no cinematic run: registry auto-delay + enqueue-time rift cover the visuals
        }
        run.terrainComplete = true;
        // PH-RIFT: the wave has arrived — retire the front rider; the client's
        // EntityEffectExecutor auto-destroys and the release cue fades the curtain.
        discardGrowthRider(run);
        if (run.phase == Phase.GROWTH) {
            beginStructures(run);
        }
        // Earlier phases (cutscene still playing) enter STRUCTURES from beginGrowth.
    }

    /** STRUCTURES: sequential rift-drop beats over every pending site of this stage. */
    private static void beginStructures(Run run) {
        if (run.ended || RUNS.get(run.profile) != run || run.phase == Phase.STRUCTURES) {
            return;
        }
        MinecraftServer server = run.level.getServer();
        run.phase = Phase.STRUCTURES;
        // The stamper enqueues its sites from the same synchronous listener pass that set
        // terrainComplete — give the queue one tick to fill, then start (or end gracefully:
        // a stage without structures skips straight through, R11 degrade requirement).
        schedule(server, 2, () -> {
            if (run.ended || RUNS.get(run.profile) != run) {
                return;
            }
            if (run.beatQueue.isEmpty() && run.activeBeat == null) {
                beginEnd(run);
                return;
            }
            captionDimension(run.level, CAPTION_STRUCTURES, 80);
            // CUT-EXPANSION shot 3: a wide establishing gap — the caption and the open sky
            // get a beat to read before the first tear rips it (was: the same tick). The
            // firstBeatReleased gate also holds back PENDING-listener starts in the window.
            schedule(server, STRUCTURES_ESTABLISH_TICKS, () -> {
                run.firstBeatReleased = true;
                maybeStartNextBeat(run);
            });
        });
    }

    /** Site listener: PENDING feeds the beat queue; PLACED lands the slam. */
    private static void onSitePhase(ServerLevel level, PendingSite site,
            StructurePendingRegistry.Phase phase) {
        Run run = RUNS.get(profileOfDimension(site.dimension()));
        if (run == null || run.ended || run.level != level) {
            return;
        }
        if (phase == StructurePendingRegistry.Phase.PENDING) {
            run.beatQueue.add(site);
            if (run.phase == Phase.STRUCTURES && run.activeBeat == null) {
                maybeStartNextBeat(run);
            }
            return;
        }
        // PLACED
        Beat beat = run.activeBeat;
        if (beat != null && beat.site.siteId().equals(site.siteId())) {
            slamBeat(run, beat);
        } else if (run.beatQueue.removeIf(queued -> queued.siteId().equals(site.siteId()))) {
            // The registry's auto-delay raced our pacing (e.g. very long beat queue): still
            // give the paste its slam and close the enqueue-time ground tear.
            Vec3 slamPos = surfaceCenterOf(level, site);
            FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_CLOSE, groundRiftPosOf(site), 0.0F, 0.0F, -1.0D);
            slamFx(level, slamPos, site.footprint());
            EclipseMod.LOGGER.info("ExpansionSequence: site {} auto-placed before its beat — slam only",
                    site.siteId());
        }
    }

    /** Opens the next beat's sky rift and schedules its placement trigger. */
    private static void maybeStartNextBeat(Run run) {
        if (run.ended || RUNS.get(run.profile) != run || run.activeBeat != null
                || run.phase != Phase.STRUCTURES || !run.firstBeatReleased) {
            return;
        }
        PendingSite site = run.beatQueue.poll();
        if (site == null) {
            if (run.terrainComplete) {
                beginEnd(run);
            }
            return;
        }
        MinecraftServer server = run.level.getServer();
        Vec3 slamPos = surfaceCenterOf(run.level, site);
        Vec3 riftPos = new Vec3(slamPos.x, Math.max(slamPos.y, site.anchor().getY()) + SKY_RIFT_HEIGHT, slamPos.z);
        Beat beat = new Beat(site, riftPos, slamPos);
        run.activeBeat = beat;

        // Replace the enqueue-time ground-level tear (EclipsePayloads' PENDING cue) with our
        // sky tear: close it first — the two are far enough apart that openRift would not.
        // CUT-EXPANSION shot 3 (tear handoff): the close animation gets
        // GROUND_TEAR_HANDOFF_TICKS to read before the sky tear rips open with its shake —
        // the two reads used to land in the same tick and muddied each other. The trigger
        // hold is measured from the sky OPEN, so the beat's establishing width is unchanged.
        FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, groundRiftPosOf(site), 0.0F, 0.0F, -1.0D);
        float width = site.footprint() * RIFT_WIDTH_PER_FOOTPRINT; // RiftFx clamps to its 48 cap
        schedule(server, GROUND_TEAR_HANDOFF_TICKS, () -> {
            if (run.ended || run.activeBeat != beat) {
                return; // aborted/auto-placed inside the handoff window: never open the tear
            }
            FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_OPEN, riftPos, width,
                    0.0F /* STYLE_STRUCTURE */, -1.0D);
            PacketDistributor.sendToPlayersInDimension(run.level, S2CShakePayload.shake(0.2F, 12));
        });
        EclipseMod.LOGGER.info("ExpansionSequence: rift beat for {} ({}) — tear at {} (width {}), trigger in {} ticks",
                site.siteId(), site.structureId(), riftPos, width,
                GROUND_TEAR_HANDOFF_TICKS + RIFT_HOLD_TICKS);

        schedule(server, GROUND_TEAR_HANDOFF_TICKS + RIFT_HOLD_TICKS, () -> {
            if (run.ended || run.activeBeat != beat) {
                return;
            }
            if (!StructurePendingRegistry.trigger(site.siteId())
                    && !StructurePendingRegistry.wasPlaced(site.siteId())) {
                // Placer not merged yet — the registry remembers the request and retries on
                // its scans; our timeout below keeps the sequence from wedging on it.
                EclipseMod.LOGGER.warn("ExpansionSequence: trigger({}) refused (placer missing?) — "
                        + "beat will time out if it never places", site.siteId());
            }
            schedule(server, BEAT_TIMEOUT_TICKS, () -> {
                if (!run.ended && run.activeBeat == beat) {
                    EclipseMod.LOGGER.warn("ExpansionSequence: beat {} timed out waiting for PLACED — closing rift",
                            beat.site.siteId());
                    FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, beat.riftPos, 0.0F, 0.0F, -1.0D);
                    run.activeBeat = null;
                    schedule(server, BEAT_SPACING_TICKS, () -> maybeStartNextBeat(run));
                }
            });
        });
    }

    /** The PLACED half of a beat: slam FX, rift close, then the next beat. */
    private static void slamBeat(Run run, Beat beat) {
        MinecraftServer server = run.level.getServer();
        slamFx(run.level, beat.slamPos, beat.site.footprint());
        // IDEA-14 §2: chunks arc out of the closing sky tear and rain over the fresh paste
        // (both beats land while RiftFx's close animation is still playing).
        schedule(server, DEBRIS_DELAY_1, () -> sendDebris(run.level, beat.riftPos));
        schedule(server, DEBRIS_DELAY_2, () -> sendDebris(run.level, beat.riftPos));
        schedule(server, RIFT_CLOSE_DELAY_TICKS, () ->
                FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, beat.riftPos, 0.0F, 0.0F, -1.0D));
        run.activeBeat = null;
        schedule(server, BEAT_SPACING_TICKS, () -> maybeStartNextBeat(run));
    }

    /**
     * Slam burst: dust + shockwave + thunderous rift-slam + shake (R11 numbers). IDEA-14 §2
     * upgrades the read to expanding dust rings — a shock ring racing outward from the
     * impact at t+6 and t+12 (replaces the old ≥64-footprint corner special case; total
     * spawns 1 + 6 + 6 + 2 debris = 15 over 20 ticks, exactly the client BURST window cap).
     */
    private static void slamFx(ServerLevel level, Vec3 pos, int footprint) {
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, 192.0D,
                new S2CQuasarPayload(STRUCTURE_SLAM_DUST, pos));
        MinecraftServer server = level.getServer();
        schedule(server, SLAM_RING_1_DELAY,
                () -> slamDustRing(level, pos, footprint * SLAM_RING_1_RADIUS));
        schedule(server, SLAM_RING_2_DELAY,
                () -> slamDustRing(level, pos, footprint * SLAM_RING_2_RADIUS));
        FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, pos, 0.5F, 30.0F, -1.0D);
        // PH-EVENTS (IDEAS-events #3): the Photon dust-mushroom cue, same tick as the
        // slam (a = footprint → client executor scale). Photon-less clients no-op; the
        // ≥50t BEAT_SPACING_TICKS cadence keeps this sequence-grade, never high-frequency.
        FxPayloads.sendFxEvent(level, FxCues.CUE_STRUCTURE_SLAM, pos, footprint, 0.0F, -1.0D);
        level.playSound(null, pos.x, pos.y, pos.z, EclipseSounds.EVENT_RIFT_SLAM.get(),
                SoundSource.BLOCKS, 1.2F, 0.94F + level.random.nextFloat() * 0.08F);
        PacketDistributor.sendToPlayersInDimension(level, S2CShakePayload.shake(0.4F, 18));
    }

    /** One ring of {@value #SLAM_RING_POINTS} dust bursts on a circle around the slam. */
    private static void slamDustRing(ServerLevel level, Vec3 center, double radius) {
        if (radius < 2.0D) {
            return; // tiny footprints: the center burst already covers the ring
        }
        for (int k = 0; k < SLAM_RING_POINTS; k++) {
            double angle = k * (Math.PI * 2.0D / SLAM_RING_POINTS);
            Vec3 pos = center.add(Math.cos(angle) * radius, 0.0D, Math.sin(angle) * radius);
            PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, 192.0D,
                    new S2CQuasarPayload(STRUCTURE_SLAM_DUST, pos));
        }
    }

    /** Debris burst at the closing sky tear (gravity emitter — IDEA-14 §2). */
    private static void sendDebris(ServerLevel level, Vec3 riftPos) {
        PacketDistributor.sendToPlayersNear(level, null, riftPos.x, riftPos.y, riftPos.z, 192.0D,
                new S2CQuasarPayload(SLAM_DEBRIS, riftPos));
    }

    /** END: grade off, nether visitors home, award-roulette timing hook. */
    private static void beginEnd(Run run) {
        if (run.ended || RUNS.get(run.profile) != run) {
            return;
        }
        MinecraftServer server = run.level.getServer();
        run.phase = Phase.END;
        run.ended = true;
        RUNS.remove(run.profile, run);
        discardGrowthRider(run); // safety net: watchdog END can arrive before terrain-complete

        captionDimension(run.level, CAPTION_DONE, 80);
        // IDEA-14 §3: fresh-land afterglow — one-shot band-radii cue (a = innerR,
        // b = outerR per the documented float payload contract), fading client-side over
        // ~10 min. Transient by design: a rejoin loses the remaining glow, like the grade.
        int glowInnerR = StageRadii.radius(run.profile, run.fromStage);
        int glowOuterR = StageRadii.radius(run.profile, run.toStage);
        if (glowOuterR > glowInnerR) {
            FxPayloads.sendFxEvent(run.level, FX_NEW_LAND_GLOW, Vec3.ZERO,
                    glowInnerR, glowOuterR, -1.0D);
        }
        boolean lastRun = RUNS.isEmpty();
        if (lastRun) {
            FxPayloads.sendEclipsePhase(server, ECLIPSE_ENDING, 0.0F, 100, permanentRim(server));
        }
        returnNetherVisitors(server, run);
        if (lastRun) {
            // Daily-award head-roulette timing hook (P3 renders the overlay; frozen seam).
            AwardService.sendRevealNow(server);
        }
        EclipseMod.LOGGER.info("ExpansionSequence: {} expansion {} -> {} complete",
                run.profile.name(), run.fromStage, run.toStage);
    }

    /** Fast teardown of a superseded run: rift closed, visitors carried or returned by callers. */
    private static void abortRun(Run run, String reason) {
        run.ended = true;
        discardGrowthRider(run);
        if (run.activeBeat != null) {
            FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, run.activeBeat.riftPos,
                    0.0F, 0.0F, -1.0D);
            run.activeBeat = null;
        }
        run.beatQueue.clear(); // the registry's auto-delay still places the sites
        EclipseMod.LOGGER.info("ExpansionSequence: {} run aborted ({})", run.profile.name(), reason);
    }

    // --------------------------------------------------- growth front rider (PH-RIFT)

    /**
     * Spawns the invisible front-rider display (IDEAS-events #4 entity-anchor verdict): a
     * {@code BLOCK_DISPLAY} with the default AIR state renders nothing (the
     * {@code StructureFlightFx}/XboxPortal invisible-marker pattern — a plain
     * {@code minecraft:marker} is server-only and never syncs to clients, so it cannot
     * anchor a client executor). The rider is announced via {@link FxCues#CUE_GROWTH_RIDER}
     * ({@code a} = entity id, {@code b} = 1); Photon clients attach ONE looping
     * {@code eclipse:growth_front_ribbon} {@code EntityEffectExecutor} to it
     * ({@link ClientHooks#handleGrowthRider}). Photon-less/reduced clients ignore the cue —
     * the Quasar pulse curtains are the unchanged fallback.
     */
    private static void spawnGrowthRider(Run run) {
        if (run.growthRider != null || run.ended) {
            return;
        }
        Vec3 front = growthRiderPos(run);
        Display.BlockDisplay rider = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, run.level);
        rider.moveTo(front.x, front.y, front.z, 0.0F, 0.0F);
        rider.addTag(GROWTH_RIDER_TAG);
        // No teleport-lerp needed (Display#setPosRotInterpolationDuration is private in
        // 1.21.1): the AIR display renders nothing, only the entity position anchors the
        // executor, and the ribbon's inertia/damping physics smooths per-tick anchor steps.
        LIVE_RIDERS.add(rider.getUUID());
        run.level.addFreshEntity(rider);
        run.growthRider = rider;
        FxPayloads.sendFxEvent(run.level, FxCues.CUE_GROWTH_RIDER, front, rider.getId(), 1.0F, -1.0D);
        EclipseMod.LOGGER.info("ExpansionSequence: growth front rider {} spawned at {}",
                rider.getId(), front);
    }

    /**
     * Repositions the rider onto the live wavefront every tick — the same math family as
     * {@link #resolveGrowthFront} (front point at the run's watcher-average angle, snapped
     * to terrain) WITHOUT the flyover camera lead: the ribbon must ride the real front.
     * The attach cue is re-broadcast on a slow cadence for mid-sweep joiners (idempotent
     * client-side).
     */
    private static void tickGrowthRider(Run run, long now) {
        Display.BlockDisplay rider = run.growthRider;
        if (rider == null) {
            return;
        }
        if (run.ended || rider.isRemoved()) {
            discardGrowthRider(run);
            return;
        }
        Vec3 front = growthRiderPos(run);
        rider.moveTo(front.x, front.y, front.z, 0.0F, 0.0F);
        if (now % GROWTH_RIDER_ANNOUNCE_TICKS == 0) {
            FxPayloads.sendFxEvent(run.level, FxCues.CUE_GROWTH_RIDER, front, rider.getId(),
                    1.0F, -1.0D);
        }
    }

    /**
     * Discards the rider and broadcasts the release cue ({@code b} = 0) so clients fade the
     * curtain gracefully (a crash-despawned rider is equally covered by the client bridge's
     * dead-entity sweep — the cue only upgrades the kill to a fade). Idempotent.
     */
    private static void discardGrowthRider(Run run) {
        Display.BlockDisplay rider = run.growthRider;
        if (rider == null) {
            return;
        }
        run.growthRider = null;
        LIVE_RIDERS.remove(rider.getUUID());
        FxPayloads.sendFxEvent(run.level, FxCues.CUE_GROWTH_RIDER, rider.position(),
                rider.getId(), 0.0F, -1.0D);
        if (!rider.isRemoved()) {
            rider.discard();
        }
    }

    /** Current front anchor for the rider: live sweep radius, no lead, slightly inside. */
    private static Vec3 growthRiderPos(Run run) {
        double progress = RingGrowthService.progressFraction(run.profile);
        int fromRadius = StageRadii.radius(run.profile, run.fromStage);
        int toRadius = StageRadii.radius(run.profile, run.toStage);
        double waveR = Mth.lerp(progress, fromRadius, toRadius);
        int anchorR = Math.max(16, (int) waveR - GROWTH_RIDER_INSET_BLOCKS);
        return edgeAnchorFor(run.level, angleToPos(run.frontAngle), anchorR);
    }

    // ------------------------------------------------------------------ nether players (R12)

    /**
     * Transports every nether player to a safe viewpoint just inside the OLD overworld rim
     * (pre-existing terrain — the sweep never rewrites it), facing the incoming growth.
     * Origins persist in {@link NetherReturns} so a crash/logout can never strand anyone.
     */
    private static void gatherNetherPlayers(Run run) {
        MinecraftServer server = run.level.getServer();
        ServerLevel nether = server.getLevel(Level.NETHER);
        if (nether == null || nether.players().isEmpty()) {
            return;
        }
        int viewRadius = Math.max(16, StageRadii.radius(run.profile, run.fromStage) - VIEWPOINT_INSET_BLOCKS);
        List<ServerPlayer> visitors = List.copyOf(nether.players());
        int index = 0;
        for (ServerPlayer player : visitors) {
            NetherReturns.get(server).putIfAbsent(player.getUUID(), new ReturnSnapshot(
                    player.level().dimension(), player.position(), player.getYRot(), player.getXRot()));
            // Spread visitors on a small arc around the front angle so they never stack.
            double angle = run.frontAngle + (index - (visitors.size() - 1) * 0.5D) * 0.02D;
            index++;
            Vec3 spot = edgeAnchorFor(run.level, angleToPos(angle), viewRadius);
            float yaw = (float) Math.toDegrees(Math.atan2(-Math.cos(angle), Math.sin(angle)));
            PacketDistributor.sendToPlayer(player, GATHER_FADE);
            FreezeService.transport(player, run.level, spot, yaw, 10.0F);
            FreezeService.setInvulnerable(player, NETHER_INVULN_TTL_TICKS);
            run.netherVisitors.add(player.getUUID());
            EclipseMod.LOGGER.info("ExpansionSequence: brought {} from the nether to the viewpoint {} (return pending)",
                    player.getScoreboardName(), spot);
        }
    }

    /** Returns every online visitor home (fade + transport); offline rows apply at login. */
    private static void returnNetherVisitors(MinecraftServer server, Run run) {
        for (UUID uuid : run.netherVisitors) {
            ServerPlayer player = server.getPlayerList().getPlayer(uuid);
            if (player == null) {
                continue; // the persisted NetherReturns row applies at their next login
            }
            applyNetherReturn(player, "expansion end");
        }
        run.netherVisitors.clear();
    }

    /** Applies (and clears) a player's persisted nether-return snapshot. No-op without one. */
    private static void applyNetherReturn(ServerPlayer player, String reason) {
        ReturnSnapshot snapshot = NetherReturns.get(player.server).take(player.getUUID());
        if (snapshot == null) {
            return;
        }
        ServerLevel home = player.server.getLevel(snapshot.dimension());
        if (home == null) {
            EclipseMod.LOGGER.warn("ExpansionSequence: return dimension {} of {} is gone — not restoring",
                    snapshot.dimension().location(), player.getScoreboardName());
            return;
        }
        PacketDistributor.sendToPlayer(player, RETURN_FADE);
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(CAPTION_NETHER_RETURN, 60,
                S2CCaptionPayload.STYLE_WHISPER));
        FreezeService.transport(player, home, snapshot.pos(), snapshot.yRot(), snapshot.xRot());
        FreezeService.clearInvulnerable(player);
        EclipseMod.LOGGER.info("ExpansionSequence: returned {} to {} in {} ({})",
                player.getScoreboardName(), snapshot.pos(), snapshot.dimension().location(), reason);
    }

    /**
     * Login: a persisted return row from a mid-event logout/crash is applied immediately —
     * unless this player's event is STILL running, in which case they resume watching from
     * the viewpoint (their overworld position persisted normally) and go home at END.
     */
    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        for (Run run : RUNS.values()) {
            if (!run.ended && run.netherVisitors.contains(player.getUUID())) {
                FreezeService.setInvulnerable(player, NETHER_INVULN_TTL_TICKS);
                return;
            }
        }
        applyNetherReturn(player, "login after interrupted expansion");
    }

    // ------------------------------------------------------------------ tick: scheduler + upkeep

    private record Task(long dueTick, Runnable action) {}

    private static void schedule(MinecraftServer server, int delayTicks, Runnable action) {
        TASKS.add(new Task(server.getTickCount() + Math.max(0, delayTicks), action));
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        long now = server.getTickCount();
        if (!TASKS.isEmpty()) {
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
        if (RUNS.isEmpty()) {
            return;
        }
        // PH-RIFT: ride the front rider along the live wavefront every tick (GROWTH only).
        for (Run run : List.copyOf(RUNS.values())) {
            tickGrowthRider(run, now);
        }
        if (now % NETHER_INVULN_REFRESH_TICKS != 0) {
            return;
        }
        for (Run run : List.copyOf(RUNS.values())) {
            // Visitors watch GROWTH/STRUCTURES unfrozen — keep their no-damage guarantee alive.
            for (UUID uuid : run.netherVisitors) {
                ServerPlayer player = server.getPlayerList().getPlayer(uuid);
                if (player != null) {
                    FreezeService.setInvulnerable(player, NETHER_INVULN_TTL_TICKS);
                }
            }
            if (now - run.startedAtTick > RUN_TIMEOUT_TICKS && !run.ended) {
                EclipseMod.LOGGER.warn("ExpansionSequence: {} run exceeded its watchdog — forcing END",
                        run.profile.name());
                run.terrainComplete = true;
                run.beatQueue.clear();
                run.activeBeat = null;
                beginEnd(run);
            }
        }
    }

    // ------------------------------------------------------------------ geometry helpers

    /** The {@code growth_front} dynamic-anchor resolver (W2 seam): current wavefront point. */
    @Nullable
    private static Vec3 resolveGrowthFront(MinecraftServer server, Collection<ServerPlayer> players) {
        Run run = RUNS.get(DiscProfile.OVERWORLD);
        DiscProfile profile;
        ServerLevel level;
        int fromStage;
        int toStage;
        double angle;
        if (run != null) {
            profile = run.profile;
            level = run.level;
            fromStage = run.fromStage;
            toStage = run.toStage;
            angle = run.frontAngle;
        } else {
            profile = DiscProfile.OVERWORLD;
            level = server.overworld();
            fromStage = toStage = WorldStageService.stage(server, profile);
            angle = averageAngle(players);
        }
        double progress = RingGrowthService.progressFraction(profile);
        int fromRadius = StageRadii.radius(profile, fromStage);
        int toRadius = StageRadii.radius(profile, toStage);
        double waveR = Mth.lerp(progress, fromRadius, toRadius);
        CutscenePath flyover = CutscenePaths.get(PATH_FLYOVER);
        int flyoverTicks = flyover != null ? flyover.durationTicks() : 220;
        // CUT-EXPANSION shot 2 sync: lead the front by its REAL speed — the full sweep width
        // over GrowthPacing.targetTicks, the pacing law RingGrowthService steers toward — for
        // the ticks until the camera is lowest (FLYOVER_SKIM_T), so the rolling front passes
        // beneath the skim deck mid-shot instead of only catching up at the very end. Clamped
        // to the remaining width so the anchor never lands beyond the target rim.
        double remainingWidth = Math.max(0.0D, toRadius - waveR);
        double blocksPerTick = Math.max(0.0D, toRadius - fromRadius)
                / (double) Math.max(1, GrowthPacing.targetTicks());
        double lead = Math.min(remainingWidth, blocksPerTick * flyoverTicks * FLYOVER_SKIM_T);
        waveR += lead;
        // EVAL-V6-CUTBD §3 defect 4: the flyover keyframes are FIXED world-X/Z offsets
        // from the anchor, so the camera's radial distance at the skim depends on the
        // watcher angle (±30 blocks at the lowest keyframe). Project the skim-time
        // keyframe offset onto the radial direction and pull the anchor back by it, so
        // the camera's REAL radius at FLYOVER_SKIM_T sits just inside the led front for
        // EVERY angle — the wave crossing becomes geometry-guaranteed, not angle-luck.
        double skimRadial = 0.0D;
        if (flyover != null) {
            Vec3 skimOffset = pathOffsetAt(flyover, FLYOVER_SKIM_T);
            skimRadial = skimOffset.x * Math.cos(angle) + skimOffset.z * Math.sin(angle);
        }
        // Sit slightly INSIDE the front so the height lookup lands on already-written
        // terrain; the upper clamp keeps the anchor off never-written land past the rim.
        int anchorR = Math.max(16, Math.min(toRadius - 6, (int) (waveR - skimRadial) - 6));
        return edgeAnchorFor(level, angleToPos(angle), anchorR);
    }

    /**
     * Keyframe-space camera offset of {@code path} at flight fraction {@code t} — linear
     * between the bracketing keyframes (a lead/aim estimate for anchor math, not the
     * client's catmullrom render; the few-block spline deviation is inside the anchor's
     * own −6 margin).
     */
    private static Vec3 pathOffsetAt(CutscenePath path, double t) {
        List<CutscenePath.Keyframe> frames = path.keyframes();
        if (frames.isEmpty()) {
            return Vec3.ZERO;
        }
        CutscenePath.Keyframe prev = frames.get(0);
        if (t <= prev.t()) {
            return new Vec3(prev.x(), prev.y(), prev.z());
        }
        for (CutscenePath.Keyframe next : frames) {
            if (t <= next.t()) {
                double span = next.t() - prev.t();
                double f = span > 1.0E-6D ? (t - prev.t()) / span : 1.0D;
                return new Vec3(Mth.lerp(f, prev.x(), next.x()),
                        Mth.lerp(f, prev.y(), next.y()),
                        Mth.lerp(f, prev.z(), next.z()));
            }
            prev = next;
        }
        return new Vec3(prev.x(), prev.y(), prev.z());
    }

    /**
     * The ring point at {@code edgeRadius} nearest to {@code toward} (discs are origin
     * centered), at terrain height — absorbed from v1's {@code edgeAnchorFor}.
     */
    private static Vec3 edgeAnchorFor(ServerLevel level, Vec3 toward, int edgeRadius) {
        double angle = Math.atan2(toward.z, toward.x);
        int x = Mth.floor(Math.cos(angle) * edgeRadius);
        int z = Mth.floor(Math.sin(angle) * edgeRadius);
        level.getChunk(x >> 4, z >> 4); // force-load before the height lookup
        int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (surfaceY <= level.getMinBuildHeight()) {
            surfaceY = level.getSeaLevel(); // void column: anchor at sea level
        }
        return new Vec3(x + 0.5D, surfaceY, z + 0.5D);
    }

    /** Unit-circle position of a world angle (feed for {@link #edgeAnchorFor}'s atan2). */
    private static Vec3 angleToPos(double angle) {
        return new Vec3(Math.cos(angle), 0.0D, Math.sin(angle));
    }

    /** Average world angle of the given players (vector mean; 0 when empty/degenerate). */
    private static double averageAngle(Collection<ServerPlayer> players) {
        double sumX = 0.0D;
        double sumZ = 0.0D;
        for (ServerPlayer player : players) {
            double length = Math.sqrt(player.getX() * player.getX() + player.getZ() * player.getZ());
            if (length > 1.0E-3D) {
                sumX += player.getX() / length;
                sumZ += player.getZ() / length;
            }
        }
        return (sumX * sumX + sumZ * sumZ) > 1.0E-6D ? Math.atan2(sumZ, sumX) : 0.0D;
    }

    /** Surface-snapped center of a pending site (cavity anchors slam at ground level). */
    private static Vec3 surfaceCenterOf(ServerLevel level, PendingSite site) {
        int x = site.anchor().getX();
        int z = site.anchor().getZ();
        level.getChunk(x >> 4, z >> 4);
        int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (surfaceY <= level.getMinBuildHeight()) {
            surfaceY = Math.max(site.anchor().getY(), level.getSeaLevel());
        }
        return new Vec3(x + 0.5D, surfaceY, z + 0.5D);
    }

    /** Where EclipsePayloads' enqueue-time ground tear opened (its exact broadcast position). */
    private static Vec3 groundRiftPosOf(PendingSite site) {
        return new Vec3(site.anchor().getX() + 0.5D, site.anchor().getY() + 1.0D,
                site.anchor().getZ() + 0.5D);
    }

    private static DiscProfile profileOfDimension(String dimensionName) {
        return "nether".equals(dimensionName) ? DiscProfile.NETHER : DiscProfile.OVERWORLD;
    }

    /** Post-intro worlds keep the purple sun rim latched through every phase payload. */
    private static boolean permanentRim(MinecraftServer server) {
        return EclipseWorldState.get(server).isStartEventDone();
    }

    private static void captionDimension(ServerLevel level, String langKey, int durationTicks) {
        PacketDistributor.sendToPlayersInDimension(level,
                new S2CCaptionPayload(langKey, durationTicks, S2CCaptionPayload.STYLE_SUBTITLE));
    }

    // ------------------------------------------------------------------ replay (R12, FX-only)

    @Override
    public String sequenceId() {
        return SEQUENCE_ID;
    }

    @Override
    public List<String> phaseIds() {
        return List.of("SKYWARD", "FLYOVER", "GROWTH", "STRUCTURES", "END");
    }

    /**
     * FX-only replays: visuals, sounds, captions and camera paths exactly like the live phase
     * but no world mutations, no {@code trigger()} calls, no teleports and no award-state
     * writes ({@code AwardService.sendRevealNow} marks reveals seen, so END skips it).
     */
    @Override
    public boolean replay(MinecraftServer server, String phaseId, Collection<ServerPlayer> players) {
        List<ServerPlayer> watchers = List.copyOf(players);
        switch (phaseId) {
            case "SKYWARD" -> {
                FxPayloads.sendEclipsePhase(server, ECLIPSE_BUILDUP, 1.0F, 60, permanentRim(server));
                captionPlayers(watchers, CAPTION_SKYWARD, 90);
                CutsceneService.play(PATH_SKYWARD, watchers, null, null, CutsceneService.PlayOptions.LOCAL);
                scheduleSkywardPunch(server, null, watchers); // punch-through parity (no run)
                return true;
            }
            case "FLYOVER" -> {
                FxPayloads.sendEclipsePhase(server, ECLIPSE_TOTAL, 1.0F, 20, permanentRim(server));
                // LOCAL play (replay may never teleport) — the camera still flies the front.
                CutsceneService.play(PATH_FLYOVER, watchers, resolveGrowthFront(server, watchers),
                        null, CutsceneService.PlayOptions.LOCAL);
                return true;
            }
            case "GROWTH" -> {
                captionPlayers(watchers, CAPTION_GROWING, 90);
                for (ServerPlayer player : watchers) {
                    Vec3 ahead = player.position().add(player.getLookAngle().scale(18.0D).multiply(1, 0, 1));
                    for (int i = 0; i < 3; i++) {
                        Vec3 pos = ahead.add((i - 1) * 9.0D, 0.0D, (i - 1) * 4.0D);
                        PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(GROWTH_DUST_WALL, pos));
                    }
                    PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.15F, 15));
                }
                return true;
            }
            case "STRUCTURES" -> {
                // CUT-EXPANSION shot 3 replay parity: the live show now has BD-STRUCT's
                // delivery flight between the trigger and PLACED, so the replay slam lands
                // REPLAY_FLIGHT_TICKS after the hold, with per-"landing" micro-shakes
                // (0.12/8, StructureFlightFx's landing cadence) filling the flight window.
                int slamAt = RIFT_HOLD_TICKS + REPLAY_FLIGHT_TICKS;
                for (ServerPlayer player : watchers) {
                    Vec3 ground = player.position().add(player.getLookAngle().scale(24.0D).multiply(1, 0, 1));
                    Vec3 rift = ground.add(0.0D, SKY_RIFT_HEIGHT, 0.0D);
                    PacketDistributor.sendToPlayer(player,
                            new S2CFxEventPayload(FxPayloads.FX_RIFT_OPEN, rift, 18.0F, 0.0F));
                    for (int offset : REPLAY_LANDING_SHAKES_AT) {
                        schedule(server, RIFT_HOLD_TICKS + offset, () -> {
                            if (!player.hasDisconnected()) {
                                PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.12F, 8));
                            }
                        });
                    }
                    schedule(server, slamAt, () -> {
                        if (player.hasDisconnected()) {
                            return;
                        }
                        PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(STRUCTURE_SLAM_DUST, ground));
                        PacketDistributor.sendToPlayer(player,
                                new S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE, ground, 0.5F, 30.0F));
                        // PH-EVENTS replay parity (R12): the live slam pairs the shockwave
                        // with the mushroom cue at the site footprint — replay mirrors it.
                        PacketDistributor.sendToPlayer(player, new S2CFxEventPayload(
                                FxCues.CUE_STRUCTURE_SLAM, ground, REPLAY_FOOTPRINT, 0.0F));
                        PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.4F, 18));
                        player.playNotifySound(EclipseSounds.EVENT_RIFT_SLAM.get(), SoundSource.BLOCKS, 1.2F, 1.0F);
                    });
                    // IDEA-14 §2 replay parity (R12): dust rings + debris rain, FX-only.
                    schedule(server, slamAt + SLAM_RING_1_DELAY, () ->
                            replaySlamRing(player, ground, REPLAY_FOOTPRINT * SLAM_RING_1_RADIUS));
                    schedule(server, slamAt + SLAM_RING_2_DELAY, () ->
                            replaySlamRing(player, ground, REPLAY_FOOTPRINT * SLAM_RING_2_RADIUS));
                    schedule(server, slamAt + DEBRIS_DELAY_1, () -> {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(SLAM_DEBRIS, rift));
                        }
                    });
                    schedule(server, slamAt + DEBRIS_DELAY_2, () -> {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(SLAM_DEBRIS, rift));
                        }
                    });
                    schedule(server, slamAt + RIFT_CLOSE_DELAY_TICKS, () -> {
                        if (!player.hasDisconnected()) {
                            PacketDistributor.sendToPlayer(player,
                                    new S2CFxEventPayload(FxPayloads.FX_RIFT_CLOSE, rift, 0.0F, 0.0F));
                        }
                    });
                }
                return true;
            }
            case "END" -> {
                FxPayloads.sendEclipsePhase(server, ECLIPSE_ENDING, 0.0F, 100, permanentRim(server));
                captionPlayers(watchers, CAPTION_DONE, 80);
                return true;
            }
            default -> {
                return false;
            }
        }
    }

    private static void captionPlayers(Collection<ServerPlayer> players, String langKey, int ticks) {
        for (ServerPlayer player : players) {
            PacketDistributor.sendToPlayer(player,
                    new S2CCaptionPayload(langKey, ticks, S2CCaptionPayload.STYLE_SUBTITLE));
        }
    }

    /** Per-player mirror of {@link #slamDustRing} for the FX-only replay (IDEA-14 §2). */
    private static void replaySlamRing(ServerPlayer player, Vec3 center, double radius) {
        if (player.hasDisconnected()) {
            return;
        }
        for (int k = 0; k < SLAM_RING_POINTS; k++) {
            double angle = k * (Math.PI * 2.0D / SLAM_RING_POINTS);
            PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(STRUCTURE_SLAM_DUST,
                    center.add(Math.cos(angle) * radius, 0.0D, Math.sin(angle) * radius)));
        }
    }

    // ------------------------------------------------------------------ persisted nether returns

    /** Where a transported nether visitor came from; applied at END or at their next login. */
    private record ReturnSnapshot(ResourceKey<Level> dimension, Vec3 pos, float yRot, float xRot) {}

    /**
     * Nether-visitor return snapshots, persisted in the overworld's data storage
     * ({@code data/eclipse_expansion_returns.dat}) so a restart or crash mid-expansion still
     * returns every transported player exactly (same pattern as W2's {@code PendingReturns}).
     */
    public static final class NetherReturns extends SavedData {
        static final String DATA_NAME = "eclipse_expansion_returns";
        private static final String TAG_RETURNS = "returns";

        private final Map<UUID, ReturnSnapshot> pending = new HashMap<>();

        public NetherReturns() {}

        static NetherReturns get(MinecraftServer server) {
            return server.overworld().getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(NetherReturns::new, NetherReturns::load), DATA_NAME);
        }

        static NetherReturns load(CompoundTag tag, HolderLookup.Provider registries) {
            NetherReturns data = new NetherReturns();
            for (Tag entry : tag.getList(TAG_RETURNS, Tag.TAG_COMPOUND)) {
                CompoundTag row = (CompoundTag) entry;
                try {
                    data.pending.put(row.getUUID("player"), new ReturnSnapshot(
                            ResourceKey.create(Registries.DIMENSION, ResourceLocation.parse(row.getString("dim"))),
                            new Vec3(row.getDouble("x"), row.getDouble("y"), row.getDouble("z")),
                            row.getFloat("yRot"), row.getFloat("xRot")));
                } catch (RuntimeException e) {
                    EclipseMod.LOGGER.warn("Dropping malformed expansion return entry", e);
                }
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (Map.Entry<UUID, ReturnSnapshot> entry : this.pending.entrySet()) {
                CompoundTag row = new CompoundTag();
                row.putUUID("player", entry.getKey());
                row.putString("dim", entry.getValue().dimension().location().toString());
                row.putDouble("x", entry.getValue().pos().x);
                row.putDouble("y", entry.getValue().pos().y);
                row.putDouble("z", entry.getValue().pos().z);
                row.putFloat("yRot", entry.getValue().yRot());
                row.putFloat("xRot", entry.getValue().xRot());
                list.add(row);
            }
            tag.put(TAG_RETURNS, list);
            return tag;
        }

        /** First origin wins across chained/superseded runs — never re-snapshot a visitor. */
        void putIfAbsent(UUID player, ReturnSnapshot snapshot) {
            if (this.pending.putIfAbsent(player, snapshot) == null) {
                setDirty();
            }
        }

        @Nullable
        ReturnSnapshot take(UUID player) {
            ReturnSnapshot snapshot = this.pending.remove(player);
            if (snapshot != null) {
                setDirty();
            }
            return snapshot;
        }
    }

    // ------------------------------------------------------------------ client: growth dust wall

    /**
     * Client half of GROWTH (single-file deliverable — nested on purpose): installs the
     * {@code S2CGrowthWavePayload} consumer ({@code GrowthPayloads.setClientWaveHandler}, the
     * documented P2 seam) and spawns the {@code growth_dust_wall} curtain along the wave arc.
     *
     * <p>Budget law: at most {@value #MAX_SPAWNS_PER_PULSE} emitters per pulse (pulses arrive
     * every 5 ticks → ≤ 8 spawns/s), only within {@value #SPAWN_RANGE_BLOCKS} blocks of the
     * camera, charged to the SEQUENCE channel — {@code FxBudget} refusals drop silently. The
     * intro fusion's pulses (overworld {@code fromStage == 0}: {@code waveR} is an edge
     * distance, not a radius) are skipped — the start event owns that spectacle.</p>
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class ClientHooks {
        /** Max dust-wall emitters spawned per wavefront pulse. */
        private static final int MAX_SPAWNS_PER_PULSE = 2;
        /** Dust walls only rise near the player — beyond this the curtain would be subpixel. */
        private static final double SPAWN_RANGE_BLOCKS = 96.0D;
        /** Arc spacing of the secondary spawn (blocks along the front). */
        private static final double SECONDARY_SPACING_BLOCKS = 10.0D;

        /** IDEA-14 §1: once-per-sweep underfoot latch — reset when a sweep's pulse 0 arrives. */
        private static boolean frontCrossedPlayer;
        /** IDEA-14 §3: cadence of the new-land upwelling motes (~2 s; reducedFx doubles it). */
        private static final int NEW_LAND_MOTE_INTERVAL_TICKS = 40;
        private static final ResourceLocation MAP_EXPAND_MATERIALIZE = emitter("map_expand_materialize");
        private static int newLandMoteCountdown;

        // --- PH-RIFT (IDEAS-events #4): growth-wavefront front-rider ribbon ---
        /** Photon curtain asset attached to the rider ({@code assets/eclipse/fx/…​.fx}). */
        private static final ResourceLocation GROWTH_FRONT_RIBBON = emitter("growth_front_ribbon");
        /** (Re)attach retry cadence — covers entity-tracking lag, budget refusals, reducedFx. */
        private static final int RIDER_RETRY_TICKS = 20;
        /** Network id of the announced front rider, or {@code -1} when none. */
        private static int growthRiderId = -1;
        /** Live ribbon loop on the rider (bridge sweeps it on entity death/level change). */
        @Nullable
        private static dev.projecteclipse.eclipse.veilfx.PhotonBridge.LoopHandle riderRibbon;
        private static int riderRetryCountdown;

        private ClientHooks() {}

        @SubscribeEvent
        static void onClientSetup(FMLClientSetupEvent event) {
            GrowthPayloads.setClientWaveHandler(ClientHooks::handleWavePulse);
            EclipseMod.LOGGER.info("ExpansionSequence.ClientHooks: growth-wave dust-wall handler installed");
        }

        /** Runs on the client main thread (GrowthPayloads dispatches there). */
        private static void handleWavePulse(dev.projecteclipse.eclipse.network.S2CGrowthWavePayload payload) {
            if ("overworld".equals(payload.dim()) && payload.fromStage() == 0) {
                return; // intro fusion: waveR is an edge distance, not a ring radius
            }
            net.minecraft.client.Minecraft minecraft = net.minecraft.client.Minecraft.getInstance();
            net.minecraft.client.multiplayer.ClientLevel level = minecraft.level;
            net.minecraft.world.entity.player.Player player = minecraft.player;
            if (level == null || player == null || payload.waveR() <= 0) {
                return;
            }

            // IDEA-14 §1: the wave passes THROUGH you — the front is monotonic outward, so
            // the first pulse whose ring reached the player's radius fires one underfoot
            // beat per sweep: the shockwave post pass + a dust wall right at the feet.
            if (payload.pulseIndex() == 0) {
                frontCrossedPlayer = false;
            }
            double playerR = Math.sqrt(player.getX() * player.getX() + player.getZ() * player.getZ());
            if (!frontCrossedPlayer && payload.waveR() >= playerR
                    && playerR >= payload.innerR() - 8.0D) {
                frontCrossedPlayer = true;
                Vec3 feet = player.position();
                dev.projecteclipse.eclipse.veilfx.EclipseFxState.startShockwave(feet, 0.25F, 18);
                dev.projecteclipse.eclipse.veilfx.QuasarSpawner.spawn(GROWTH_DUST_WALL, feet,
                        dev.projecteclipse.eclipse.veilfx.FxBudget.Channel.SEQUENCE);
            }

            // Nearest point of the pulse's arc segment to the player.
            double playerAngle = Math.atan2(player.getZ(), player.getX());
            double angle = clampToArc(playerAngle, payload.waveAngleStart(), payload.waveAngleEnd());
            int spawned = 0;
            for (int i = 0; i < MAX_SPAWNS_PER_PULSE; i++) {
                // 0, then ±spacing alternating by pulse parity, walking along the front arc.
                double arcOffset = i == 0 ? 0.0D
                        : (payload.pulseIndex() % 2 == 0 ? i : -i) * SECONDARY_SPACING_BLOCKS;
                double a = angle + arcOffset / Math.max(8.0D, payload.waveR());
                double x = Math.cos(a) * payload.waveR();
                double z = Math.sin(a) * payload.waveR();
                double distSq = (x - player.getX()) * (x - player.getX())
                        + (z - player.getZ()) * (z - player.getZ());
                if (distSq > SPAWN_RANGE_BLOCKS * SPAWN_RANGE_BLOCKS) {
                    continue;
                }
                int surfaceY = level.getHeight(net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING,
                        net.minecraft.util.Mth.floor(x), net.minecraft.util.Mth.floor(z));
                double y = surfaceY > level.getMinBuildHeight() + 1 ? surfaceY : player.getY();
                boolean ok = dev.projecteclipse.eclipse.veilfx.QuasarSpawner.spawn(GROWTH_DUST_WALL,
                        new Vec3(x, y, z), dev.projecteclipse.eclipse.veilfx.FxBudget.Channel.SEQUENCE);
                if (ok && ++spawned >= MAX_SPAWNS_PER_PULSE) {
                    break;
                }
            }
        }

        /**
         * IDEA-14 §3 entry point of the {@code eclipse:fx/new_land_glow} cue (a = innerR,
         * b = outerR). Wiring ask (W4-ATMOS): {@code FxPayloads.handleFxEvent} must add a
         * 2-line dispatch here — exact diff in {@code docs/plans_v3/wiring/W4-ATMOS_wiring.md}.
         * Until that lands, the cue is logged as an unknown FX id at debug and the glow is
         * simply absent (graceful degrade).
         */
        public static void handleNewLandGlow(float innerR, float outerR) {
            dev.projecteclipse.eclipse.veilfx.EclipseFxState.setNewLandBand(innerR, outerR);
        }

        /**
         * PH-RIFT entry point of the {@link dev.projecteclipse.eclipse.network.fx.FxCues
         * #CUE_GROWTH_RIDER} cue ({@code a} = rider entity id, {@code b} = 1 attach / 0
         * release), dispatched by {@code FxPayloads.handleFxEvent}. Attach is
         * announce-only: the looping {@code eclipse:growth_front_ribbon} executor is
         * (re)attached from {@link #onClientTick} once the rider entity is actually
         * tracked client-side — it may arrive later than the cue or drop out of tracking
         * range mid-sweep. Release fades the curtain gracefully (the wall dissolves as
         * the {@code expansion.done} caption lands); a crash-despawned rider is equally
         * covered by {@code PhotonBridge}'s dead-entity sweep. WINDOWED-loop law: the
         * window is the rider's announced lifetime, owned here.
         */
        public static void handleGrowthRider(int entityId, boolean attach) {
            if (attach) {
                if (growthRiderId != entityId) {
                    releaseRiderRibbon(false); // superseded run announced a NEW rider
                    growthRiderId = entityId;
                }
                return;
            }
            if (entityId < 0 || growthRiderId == entityId) {
                releaseRiderRibbon(true);
            }
        }

        /**
         * Keeps ONE ribbon executor attached to the announced rider. Cheap while healthy
         * (one alive() check); all failure paths (rider not yet tracked, Photon absent,
         * {@code reducedFx}, executor-budget refusal) retry on the
         * {@value #RIDER_RETRY_TICKS}-tick cadence — never per-tick hammering.
         */
        private static void tickRiderRibbon() {
            if (growthRiderId < 0) {
                return;
            }
            net.minecraft.client.multiplayer.ClientLevel level =
                    net.minecraft.client.Minecraft.getInstance().level;
            if (level == null) {
                releaseRiderRibbon(false);
                return;
            }
            // EVAL-V6-PHOTON §5: the reducedFx force-kill law is unconditional — kill a
            // live ribbon the moment availability drops (available() folds in reducedFx
            // and the photon toggles), never just return the live handle. The logical
            // window stays open: toggling back re-attaches on the retry cadence for the
            // rider's remaining lifetime.
            if (!dev.projecteclipse.eclipse.veilfx.PhotonBridge.available()) {
                if (riderRibbon != null) {
                    dev.projecteclipse.eclipse.veilfx.PhotonBridge.stopLoop(riderRibbon, false);
                    riderRibbon = null;
                }
                return;
            }
            if (riderRibbon != null) {
                if (riderRibbon.alive()) {
                    return;
                }
                riderRibbon = null; // pruned: rider untracked/dead, or the level changed
            }
            if (--riderRetryCountdown > 0) {
                return;
            }
            riderRetryCountdown = RIDER_RETRY_TICKS;
            net.minecraft.world.entity.Entity rider = level.getEntity(growthRiderId);
            if (rider != null && rider.isAlive()) {
                riderRibbon = dev.projecteclipse.eclipse.veilfx.PhotonBridge.spawnLoop(
                        GROWTH_FRONT_RIBBON, rider,
                        dev.projecteclipse.eclipse.veilfx.PhotonBridge.AUTO_ROTATE_NONE);
            }
        }

        /** Closes the rider window: stops the ribbon (graceful = fade) and forgets the id. */
        private static void releaseRiderRibbon(boolean graceful) {
            dev.projecteclipse.eclipse.veilfx.PhotonBridge.stopLoop(riderRibbon, graceful);
            riderRibbon = null;
            growthRiderId = -1;
            riderRetryCountdown = 0;
        }

        /**
         * IDEA-14 §3: ambient upwelling motes on the fresh annulus — one AMBIENT-channel
         * {@code map_expand_materialize} spawn per ~2 s at a random surface point near the
         * player, probability × glow so the afterglow visibly thins over the ~10 minutes.
         */
        @SubscribeEvent
        static void onClientTick(net.neoforged.neoforge.client.event.ClientTickEvent.Post event) {
            tickRiderRibbon(); // PH-RIFT: not gated on the glow — the sweep precedes it
            float glow = dev.projecteclipse.eclipse.veilfx.EclipseFxState.newLandGlow();
            if (glow <= 0.0F) {
                return;
            }
            net.minecraft.client.Minecraft minecraft = net.minecraft.client.Minecraft.getInstance();
            net.minecraft.client.multiplayer.ClientLevel level = minecraft.level;
            net.minecraft.world.entity.player.Player player = minecraft.player;
            if (level == null || player == null || minecraft.isPaused()) {
                return;
            }
            if (--newLandMoteCountdown > 0) {
                return;
            }
            newLandMoteCountdown = dev.projecteclipse.eclipse.core.config.EclipseClientConfig.reducedFx()
                    ? NEW_LAND_MOTE_INTERVAL_TICKS * 2 : NEW_LAND_MOTE_INTERVAL_TICKS;
            double playerR = Math.sqrt(player.getX() * player.getX() + player.getZ() * player.getZ());
            if (!dev.projecteclipse.eclipse.veilfx.EclipseFxState.newLandBandContains(playerR)
                    || level.random.nextFloat() > glow) {
                return;
            }
            double angle = level.random.nextDouble() * Math.PI * 2.0D;
            double dist = 6.0D + level.random.nextDouble() * 18.0D;
            double x = player.getX() + Math.cos(angle) * dist;
            double z = player.getZ() + Math.sin(angle) * dist;
            int surfaceY = level.getHeight(net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING,
                    net.minecraft.util.Mth.floor(x), net.minecraft.util.Mth.floor(z));
            if (surfaceY <= level.getMinBuildHeight() + 1) {
                return;
            }
            dev.projecteclipse.eclipse.veilfx.QuasarSpawner.spawn(MAP_EXPAND_MATERIALIZE,
                    new Vec3(x, surfaceY + 1.0D, z),
                    dev.projecteclipse.eclipse.veilfx.FxBudget.Channel.AMBIENT);
        }

        /** The glow band is dimension-local — never carry it across respawn/dimension change. */
        @SubscribeEvent
        static void onClone(net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent.Clone event) {
            dev.projecteclipse.eclipse.veilfx.EclipseFxState.clearNewLandBand();
            frontCrossedPlayer = false;
            // EVAL-V6-PHOTON §5: the rider window is dimension-local too. The bridge
            // sweep only kills the executor — without closing the window here, the stale
            // numeric entity id could re-attach the ribbon to an unrelated entity that
            // reused it in the new level. The server re-announces on any real rider.
            releaseRiderRibbon(false);
        }

        /** Logout reset: the bridge force-destroys executors; drop our handle + rider id. */
        @SubscribeEvent
        static void onLoggingOut(net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent.LoggingOut event) {
            releaseRiderRibbon(false);
        }

        /**
         * Clamps a world angle into the pulse's arc segment. Full-ring pulses
         * ({@code −π..π}) pass the player's own angle through — the wall rises at the
         * nearest front point.
         */
        private static double clampToArc(double angle, float start, float end) {
            if (end - start >= (float) (Math.PI * 2.0D) - 1.0E-3F) {
                return angle;
            }
            double span = wrap(end - start);
            double into = wrap(angle - start);
            if (into >= 0.0D && into <= span) {
                return angle;
            }
            // Outside the segment: snap to the closer endpoint.
            double toStart = Math.abs(wrapSigned(angle - start));
            double toEnd = Math.abs(wrapSigned(angle - end));
            return toStart <= toEnd ? start : end;
        }

        private static double wrap(double angle) {
            double wrapped = angle % (Math.PI * 2.0D);
            return wrapped < 0.0D ? wrapped + Math.PI * 2.0D : wrapped;
        }

        private static double wrapSigned(double angle) {
            double wrapped = wrap(angle);
            return wrapped > Math.PI ? wrapped - Math.PI * 2.0D : wrapped;
        }
    }
}
