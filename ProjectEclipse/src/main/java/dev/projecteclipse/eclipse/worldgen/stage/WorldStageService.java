package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.border.SoftBorder;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.devtools.StageIO;
import dev.projecteclipse.eclipse.network.S2CStagePayload;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.level.LevelEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Single entry point of the world stage system: {@link #setStage} is the only way a stage
 * commits. Order of operations on a commit (worker 3 contract):
 * <ol>
 *   <li>persist the stage in {@link EclipseWorldState},</li>
 *   <li>publish it into the {@link WorldStageAccess} chunkgen seam (worldgen threads see the
 *       new radius before any annulus chunk can generate),</li>
 *   <li>broadcast {@link S2CStagePayload} to the clients in the affected dimension (login
 *       sync covers everyone else),</li>
 *   <li>kick {@link RingGrowthService} to rewrite the already-generated annulus (animated
 *       angular sweep, or instantly-paced when {@code animate=false}; lowering writes the
 *       terrain function's stage-{@code n} output, i.e. air/void beyond the new radius).</li>
 * </ol>
 *
 * <p>Stage radii come from {@code stages.json} ({@code EclipseConfig} pushes them into
 * {@link StageRadii} on every config load). When a sweep finishes, the registered
 * {@linkplain StageListener stage listeners} fire — worker 5's structure stamper subscribes
 * here to place the stage's {@code structures[]}.</p>
 *
 * <p>On world load the persisted stages are published into the seam BEFORE spawn chunks
 * generate ({@link LevelEvent.Load} of the overworld), and an interrupted sweep resumes
 * from its persisted growth cursor on {@link ServerStartedEvent}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WorldStageService {
    /**
     * Fired on the server thread when a stage's terrain work completes (sweep finished, or
     * the commit needed no terrain rewrite). Worker 5 registers its structure stamper here:
     * on a grown stage, place the {@code structures[]} listed for stages
     * {@code fromStage+1..toStage} in {@code stages.json}.
     */
    @FunctionalInterface
    public interface StageListener {
        void onStageTerrainComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage);
    }

    /**
     * Fired on the server thread when a stage commit kicks its terrain sweep (right before
     * {@link RingGrowthService#start}). The cutscene engine's unlock cinematics subscribe
     * here to freeze players and play the {@code unlock_ring} shot during ANIMATED growth.
     */
    @FunctionalInterface
    public interface GrowthStartListener {
        void onStageGrowthStart(ServerLevel level, DiscProfile profile, int fromStage, int toStage,
                boolean animate);
    }

    private static final List<StageListener> LISTENERS = new CopyOnWriteArrayList<>();
    private static final List<GrowthStartListener> GROWTH_START_LISTENERS = new CopyOnWriteArrayList<>();

    private WorldStageService() {}

    /** Registers a stage-completion listener (worker 5 structure stamping, W5 watcher statues, …). */
    public static void addListener(StageListener listener) {
        LISTENERS.add(listener);
    }

    /** Registers a growth-start listener (W6 unlock cinematics + freeze). */
    public static void addGrowthStartListener(GrowthStartListener listener) {
        GROWTH_START_LISTENERS.add(listener);
    }

    /** The disc profile driven by the given dimension, or {@code null} for non-disc dimensions. */
    public static DiscProfile profileOf(ResourceKey<Level> dimension) {
        if (dimension == Level.OVERWORLD) {
            return DiscProfile.OVERWORLD;
        }
        if (dimension == Level.NETHER) {
            return DiscProfile.NETHER;
        }
        return null;
    }

    /** The dimension a disc profile lives in (inverse of {@link #profileOf}). */
    public static ResourceKey<Level> dimensionOf(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? Level.NETHER : Level.OVERWORLD;
    }

    /** The committed (persisted) stage of the given profile. */
    public static int stage(MinecraftServer server, DiscProfile profile) {
        return EclipseWorldState.get(server).getWorldStage(profile);
    }

    /** Highest stage configured in {@code stages.json} for the profile. */
    public static int maxStage(DiscProfile profile) {
        return StageRadii.maxStage(profile);
    }

    /**
     * Commits a world stage and rewrites the terrain between the old and new radius.
     * {@code animate=true} paces the rewrite as a visible angular ring sweep;
     * {@code animate=false} stamps as fast as the per-tick budget allows (still async —
     * never a single-tick world edit). Lowering the stage runs the same sweep in erase
     * mode (the terrain function returns air/void beyond the lowered radius).
     *
     * <p>If a sweep is already running in that dimension it is superseded: the new sweep's
     * rewrite band covers the union of both transitions, so no half-written annulus is left
     * behind. Returns {@code false} when the dimension is not a disc, the stage is already
     * committed with no sweep running, or the value is out of the configured range.</p>
     */
    public static boolean setStage(MinecraftServer server, ResourceKey<Level> dimension, int stage, boolean animate) {
        DiscProfile profile = profileOf(dimension);
        ServerLevel level = server.getLevel(dimension);
        if (profile == null || level == null) {
            EclipseMod.LOGGER.warn("Ignoring stage set for non-disc dimension {}", dimension.location());
            return false;
        }
        if (stage < 0 || stage > maxStage(profile)) {
            EclipseMod.LOGGER.warn("Ignoring out-of-range stage {} for {} (configured 0..{})",
                    stage, profile.name(), maxStage(profile));
            return false;
        }
        // StageIO refuses to save/load during a sweep; the exclusion must hold in the
        // other direction too, or the commit sweep would interleave with the chunks a
        // half-applied snapshot is still rewriting.
        if (StageIO.isApplying(profile)) {
            EclipseMod.LOGGER.warn("Refusing stage set while a snapshot load is applying for {}",
                    profile.name());
            return false;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        int committed = state.getWorldStage(profile);
        // A superseded sweep may have left terrain anywhere between its own fromStage and
        // the committed stage — widen the rewrite band to that sweep's origin.
        Integer interruptedFrom = RingGrowthService.cancel(level, profile);
        int fromStage = interruptedFrom != null ? Math.min(interruptedFrom, committed) : committed;
        if (committed == stage && interruptedFrom == null) {
            broadcastStage(server, profile, stage, false);
            return false;
        }

        state.setWorldStage(profile, stage);
        WorldStageAccess.setStage(profile, stage);
        EclipseMod.LOGGER.info("World stage committed: {} {} -> {} (radius {} -> {}, {})",
                profile.name(), committed, stage, StageRadii.radius(profile, committed),
                StageRadii.radius(profile, stage), animate ? "animated sweep" : "instant stamp");
        broadcastStage(server, profile, stage, true);

        // W7 soft border: retarget the dimension's ring to stageRadius + borderOffset; an
        // animated commit lerps the ring alongside the sweep (snapping on early completion).
        SoftBorder.onStageCommit(server, profile, stage, animate);

        for (GrowthStartListener listener : GROWTH_START_LISTENERS) {
            listener.onStageGrowthStart(level, profile, fromStage, stage, animate);
        }
        RingGrowthService.start(level, profile, fromStage, stage, animate, 0L);
        return true;
    }

    /**
     * Re-stamps the annulus between {@code stage-1} and {@code stage} with the CURRENTLY
     * committed terrain, without changing the committed stage (repair tool behind
     * {@code /eclipse stage rebuild}). Stage 0 re-stamps the whole pre-intro footprint.
     */
    public static boolean rebuildStage(MinecraftServer server, ResourceKey<Level> dimension, int stage) {
        DiscProfile profile = profileOf(dimension);
        ServerLevel level = server.getLevel(dimension);
        if (profile == null || level == null || stage < 0 || stage > maxStage(profile)) {
            return false;
        }
        if (RingGrowthService.isRunning(profile)) {
            EclipseMod.LOGGER.warn("Refusing stage rebuild while a sweep is running for {}", profile.name());
            return false;
        }
        if (StageIO.isApplying(profile)) {
            EclipseMod.LOGGER.warn("Refusing stage rebuild while a snapshot load is applying for {}",
                    profile.name());
            return false;
        }
        int committed = EclipseWorldState.get(server).getWorldStage(profile);
        RingGrowthService.startRebuild(level, profile, stage, committed);
        return true;
    }

    /** Called by {@link RingGrowthService} on the server thread when a sweep completes. */
    static void onSweepComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage) {
        EclipseWorldState.get(level.getServer()).clearGrowthCursor();
        // W1.5 new-ring registry (design D11): record the grown annulus for the P4/P6
        // glitched-mob spawn rules BEFORE the stage listeners run, so a listener placing
        // structures/spawners already sees the fresh-ring rows. Rebuild sweeps never call
        // onSweepComplete; erase/downgrade transitions are filtered by the registry's
        // toStage > fromStage guard.
        NewRingRegistry.onRingCommitted(level, profile, fromStage, toStage);
        broadcastStage(level.getServer(), profile, toStage, false);
        for (StageListener listener : LISTENERS) {
            listener.onStageTerrainComplete(level, profile, fromStage, toStage);
        }
    }

    /** Sends the committed stage of both disc dimensions to one player (login sync). */
    public static void syncStagesTo(ServerPlayer player) {
        EclipseWorldState state = EclipseWorldState.get(player.server);
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            int stage = state.getWorldStage(profile);
            PacketDistributor.sendToPlayer(player, new S2CStagePayload(profile.name(), stage,
                    StageRadii.radius(profile, stage), RingGrowthService.isRunning(profile)));
        }
    }

    /** Stage changes only matter to players IN that dimension ({@link #syncStagesTo} covers logins). */
    private static void broadcastStage(MinecraftServer server, DiscProfile profile, int stage,
            boolean animating) {
        ServerLevel level = server.getLevel(dimensionOf(profile));
        if (level == null) {
            return;
        }
        PacketDistributor.sendToPlayersInDimension(level, new S2CStagePayload(profile.name(), stage,
                StageRadii.radius(profile, stage), animating));
    }

    /**
     * Publishes the persisted stages into the chunkgen seam as soon as the overworld exists —
     * before {@code prepareLevels} generates the first spawn chunk, so no annulus chunk can
     * ever generate at a stale stage.
     */
    @SubscribeEvent
    public static void onLevelLoad(LevelEvent.Load event) {
        if (!(event.getLevel() instanceof ServerLevel level) || level.dimension() != Level.OVERWORLD) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(level.getServer());
        WorldStageAccess.setStage(DiscProfile.OVERWORLD, state.getWorldStage(DiscProfile.OVERWORLD));
        WorldStageAccess.setStage(DiscProfile.NETHER, state.getWorldStage(DiscProfile.NETHER));
        // W1.5/D9: hydrate the worldgen-overhaul SavedData at the same moment — its
        // load() mirrors the breach/end materialization flags into FrozenParams, which
        // worldgen worker threads read per column, so the mirror must be set before
        // prepareLevels generates the first spawn chunk (same reason as the stage seam).
        EclipseWorldgenState.get(level.getServer());
        EclipseMod.LOGGER.info("World stages published to chunkgen seam: overworld {}, nether {}",
                state.getWorldStage(DiscProfile.OVERWORLD), state.getWorldStage(DiscProfile.NETHER));
    }

    /**
     * Resumes an interrupted ring-growth sweep from its persisted cursor. The soft border is
     * re-derived at the sweep's actual progress ({@link SoftBorder#resumeGrowthLerp}) instead
     * of snapping to the persisted final target, and the animating stage state is
     * re-broadcast so already-connected clients (singleplayer host, fast rejoins) show the
     * sweep FX again.
     */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        if (!state.hasGrowthCursor()) {
            return;
        }
        DiscProfile profile = "nether".equals(state.getGrowthDimension())
                ? DiscProfile.NETHER : DiscProfile.OVERWORLD;
        ServerLevel level = server.getLevel(dimensionOf(profile));
        if (level == null) {
            EclipseMod.LOGGER.warn("Cannot resume ring growth: dimension for {} missing", profile.name());
            return;
        }
        int fromStage = state.getGrowthFromStage();
        int toStage = state.getWorldStage(profile);
        EclipseMod.LOGGER.info("Resuming interrupted ring growth: {} stage {} -> {} at column cursor {}",
                profile.name(), fromStage, toStage, state.getGrowthCursor());
        RingGrowthService.start(level, profile, fromStage, toStage, true, state.getGrowthCursor());
        SoftBorder.resumeGrowthLerp(server, profile, fromStage, toStage,
                RingGrowthService.progressFraction(profile));
        broadcastStage(server, profile, toStage, true);
    }

    /**
     * Statics must never leak into the next world (singleplayer re-opens reuse the JVM):
     * the chunkgen seam goes back to its stage-0 default ({@link #onLevelLoad} republishes
     * the next world's persisted stages before its first chunk generates) and the altar
     * poll forgets its last sample so the next world's boot-up read is treated as such.
     */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        WorldStageAccess.setStage(DiscProfile.OVERWORLD, 0);
        WorldStageAccess.setStage(DiscProfile.NETHER, 0);
        lastSeenAltarLevel = Integer.MIN_VALUE;
    }

    // --- stages.json triggers ---

    /**
     * First event day counting as "final" for {@code final_day} stage triggers
     * ({@code docs/ideas/01_world_terrain.md} §C — the day-12 endgame window).
     */
    private static final int FINAL_DAY = 12;

    /** Ticks between altar-level polls for {@code milestone:N} triggers. */
    private static final int ALTAR_POLL_TICKS = 20;

    /** Last altar level acted on ({@link Integer#MIN_VALUE} until the first poll). */
    private static int lastSeenAltarLevel = Integer.MIN_VALUE;

    /** Malformed {@code stages.json} trigger strings already warned about (log once each). */
    private static final Set<String> WARNED_TRIGGERS = new HashSet<>();

    /**
     * Applies every {@code day:N} (N ≤ day) and {@code final_day} (day ≥ {@value #FINAL_DAY})
     * stage trigger of both disc dimensions, raising each dimension to the highest matching
     * stage with an animated sweep. Cumulative and idempotent: called by
     * {@code DayScheduler.setDay} after a day is applied, so a day jump (or a missed
     * real-world auto-advance) catches up in one call. Day triggers never LOWER a stage —
     * reverting terrain stays a manual {@code /eclipse stage set} decision.
     */
    public static void applyDayTriggers(MinecraftServer server, int day) {
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            int target = stage(server, profile);
            for (EclipseConfig.StageEntry entry : stageEntries(profile)) {
                if (entry.stage() > target && dayTriggerMatches(entry.trigger(), day)) {
                    target = entry.stage();
                }
            }
            if (target > stage(server, profile)) {
                EclipseMod.LOGGER.info("Day {} stage trigger: {} -> stage {}", day, profile.name(), target);
                setStage(server, dimensionOf(profile), target, true);
            }
        }
    }

    private static boolean dayTriggerMatches(String trigger, int day) {
        if ("final_day".equals(trigger)) {
            return day >= FINAL_DAY;
        }
        return trigger != null && trigger.startsWith("day:")
                && day >= triggerThreshold(trigger, "day:");
    }

    /**
     * The integer argument of a {@code <prefix>N} trigger, or {@link Integer#MAX_VALUE}
     * (matches nothing) when malformed — a {@code stages.json} typo like {@code day:foo}
     * must never throw out of the day scheduler or the altar poll. Warned once per string.
     */
    private static int triggerThreshold(String trigger, String prefix) {
        try {
            return Integer.parseInt(trigger.substring(prefix.length()));
        } catch (NumberFormatException e) {
            if (WARNED_TRIGGERS.add(trigger)) {
                EclipseMod.LOGGER.warn("Ignoring malformed stage trigger '{}' in stages.json", trigger);
            }
            return Integer.MAX_VALUE;
        }
    }

    /**
     * {@code milestone:N} triggers: watches {@code EclipseWorldState.altarLevel} (polled
     * every {@value #ALTAR_POLL_TICKS} ticks — catches every {@code setAltarLevel} caller,
     * altar ritual and admin command alike) and raises each dimension to the highest stage
     * whose milestone level is reached. Like day triggers this only ever raises.
     */
    @SubscribeEvent
    public static void onAltarPollTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % ALTAR_POLL_TICKS != 0) {
            return;
        }
        int altarLevel = EclipseWorldState.get(server).getAltarLevel();
        if (altarLevel == lastSeenAltarLevel) {
            return;
        }
        boolean firstPoll = lastSeenAltarLevel == Integer.MIN_VALUE;
        lastSeenAltarLevel = altarLevel;
        if (firstPoll || altarLevel <= 0) {
            return; // never fire sweeps from the boot-up sample or a reset
        }
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            int target = stage(server, profile);
            for (EclipseConfig.StageEntry entry : stageEntries(profile)) {
                String trigger = entry.trigger();
                if (entry.stage() > target && trigger != null && trigger.startsWith("milestone:")
                        && altarLevel >= triggerThreshold(trigger, "milestone:")) {
                    target = entry.stage();
                }
            }
            if (target > stage(server, profile)) {
                EclipseMod.LOGGER.info("Altar level {} stage trigger: {} -> stage {}",
                        altarLevel, profile.name(), target);
                setStage(server, dimensionOf(profile), target, true);
            }
        }
    }

    // --- config helpers shared by triggers and commands ---

    /** The configured {@code stages.json} entries of a profile (ordered by stage). */
    public static List<EclipseConfig.StageEntry> stageEntries(DiscProfile profile) {
        return EclipseConfig.stages(profile.name());
    }
}
