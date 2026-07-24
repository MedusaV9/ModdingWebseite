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
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
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
 *   <li>{@code SKYWARD} (~80 ticks) — every watcher is frozen by the cutscene engine and the
 *       player-anchored {@code expansion_skyward} shot tilts their camera up at the sky while
 *       the eclipse grade ramps in ({@code S2CEclipsePhasePayload} BUILDUP, 0 → 1 over 60
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
 *   <li>{@code STRUCTURES} — after P1's terrain-done callback, every {@link PendingSite} of the
 *       stage gets a sequential rift-drop beat: close the enqueue-time ground tear, open a
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
        boolean flyoverPlayed;
        boolean ended;

        /** Sites awaiting their rift-drop beat, in PENDING order. */
        final ArrayDeque<PendingSite> beatQueue = new ArrayDeque<>();
        @Nullable
        Beat activeBeat;

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
        captionDimension(run.level, CAPTION_SKYWARD, 70);
        List<ServerPlayer> watchers = List.copyOf(run.level.players());
        // Player-anchored path: every watcher tilts up from their own feet. The callback runs
        // synchronously when the path is missing/disabled or nobody watches — never softlocks.
        CutsceneService.play(PATH_SKYWARD, watchers, null, () -> beginFlyover(run),
                CutsceneService.PlayOptions.LOCAL);
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

        // Fallback: the reshot unlock_ring orbit at the old ring edge nearest each watcher
        // (v1 shape). Per-player plays share no group, so GROWTH is entered on a timer.
        CutscenePath fallback = CutscenePaths.get(PATH_FALLBACK);
        int fallbackTicks = 0;
        if (fallback != null && CutsceneService.isEnabled(server, fallback)) {
            int edgeRadius = StageRadii.radius(run.profile, run.fromStage);
            for (ServerPlayer player : watchers) {
                CutsceneService.play(PATH_FALLBACK, List.of(player),
                        edgeAnchorFor(run.level, player.position(), edgeRadius), null);
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
            captionDimension(run.level, CAPTION_GROWING, 90); // flyover carries this caption itself
        }
        if (run.terrainComplete) {
            beginStructures(run); // tiny sweeps can finish before the cutscenes do
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
            maybeStartNextBeat(run);
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
                || run.phase != Phase.STRUCTURES) {
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
        FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, groundRiftPosOf(site), 0.0F, 0.0F, -1.0D);
        float width = site.footprint() * RIFT_WIDTH_PER_FOOTPRINT; // RiftFx clamps to its 48 cap
        FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_OPEN, riftPos, width,
                0.0F /* STYLE_STRUCTURE */, -1.0D);
        PacketDistributor.sendToPlayersInDimension(run.level, S2CShakePayload.shake(0.2F, 12));
        EclipseMod.LOGGER.info("ExpansionSequence: rift beat for {} ({}) — tear at {} (width {}), trigger in {} ticks",
                site.siteId(), site.structureId(), riftPos, width, RIFT_HOLD_TICKS);

        schedule(server, RIFT_HOLD_TICKS, () -> {
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
        schedule(server, RIFT_CLOSE_DELAY_TICKS, () ->
                FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, beat.riftPos, 0.0F, 0.0F, -1.0D));
        run.activeBeat = null;
        schedule(server, BEAT_SPACING_TICKS, () -> maybeStartNextBeat(run));
    }

    /** Slam burst: dust + shockwave + thunderous rift-slam + shake (R11 numbers). */
    private static void slamFx(ServerLevel level, Vec3 pos, int footprint) {
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, 192.0D,
                new S2CQuasarPayload(STRUCTURE_SLAM_DUST, pos));
        if (footprint >= 64) {
            // Big footprints get corner dust so the curtain reads across the whole site.
            double d = footprint / 4.0D;
            for (int corner = 0; corner < 4; corner++) {
                Vec3 offset = new Vec3((corner & 1) == 0 ? -d : d, 0.0D, (corner & 2) == 0 ? -d : d);
                PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, 192.0D,
                        new S2CQuasarPayload(STRUCTURE_SLAM_DUST, pos.add(offset)));
            }
        }
        FxPayloads.sendFxEvent(level, FxPayloads.FX_SHOCKWAVE, pos, 0.5F, 30.0F, -1.0D);
        level.playSound(null, pos.x, pos.y, pos.z, EclipseSounds.EVENT_RIFT_SLAM.get(),
                SoundSource.BLOCKS, 1.2F, 0.94F + level.random.nextFloat() * 0.08F);
        PacketDistributor.sendToPlayersInDimension(level, S2CShakePayload.shake(0.4F, 18));
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

        captionDimension(run.level, CAPTION_DONE, 80);
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
        if (run.activeBeat != null) {
            FxPayloads.sendFxEvent(run.level, FxPayloads.FX_RIFT_CLOSE, run.activeBeat.riftPos,
                    0.0F, 0.0F, -1.0D);
            run.activeBeat = null;
        }
        run.beatQueue.clear(); // the registry's auto-delay still places the sites
        EclipseMod.LOGGER.info("ExpansionSequence: {} run aborted ({})", run.profile.name(), reason);
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
        if (RUNS.isEmpty() || now % NETHER_INVULN_REFRESH_TICKS != 0) {
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
        double remainingWidth = Math.max(0.0D, toRadius - waveR);
        double lead = Math.min(remainingWidth,
                flyoverTicks / (double) Math.max(1, GrowthPacing.targetTicks()) * remainingWidth);
        waveR += lead;
        // Sit slightly INSIDE the front so the height lookup lands on already-written terrain.
        int anchorR = Math.max(16, (int) waveR - 6);
        return edgeAnchorFor(level, angleToPos(angle), anchorR);
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
                captionPlayers(watchers, CAPTION_SKYWARD, 70);
                CutsceneService.play(PATH_SKYWARD, watchers, null, null, CutsceneService.PlayOptions.LOCAL);
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
                for (ServerPlayer player : watchers) {
                    Vec3 ground = player.position().add(player.getLookAngle().scale(24.0D).multiply(1, 0, 1));
                    Vec3 rift = ground.add(0.0D, SKY_RIFT_HEIGHT, 0.0D);
                    PacketDistributor.sendToPlayer(player,
                            new S2CFxEventPayload(FxPayloads.FX_RIFT_OPEN, rift, 18.0F, 0.0F));
                    schedule(server, RIFT_HOLD_TICKS, () -> {
                        if (player.hasDisconnected()) {
                            return;
                        }
                        PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(STRUCTURE_SLAM_DUST, ground));
                        PacketDistributor.sendToPlayer(player,
                                new S2CFxEventPayload(FxPayloads.FX_SHOCKWAVE, ground, 0.5F, 30.0F));
                        PacketDistributor.sendToPlayer(player, S2CShakePayload.shake(0.4F, 18));
                        player.playNotifySound(EclipseSounds.EVENT_RIFT_SLAM.get(), SoundSource.BLOCKS, 1.2F, 1.0F);
                    });
                    schedule(server, RIFT_HOLD_TICKS + RIFT_CLOSE_DELAY_TICKS, () -> {
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
