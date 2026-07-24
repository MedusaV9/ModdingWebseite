package dev.projecteclipse.eclipse.border;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.network.S2CBorderPayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.progression.BorderController;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityTeleportEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.EntityTickEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-authoritative circular soft worldborder ({@code docs/ideas/05_systems.md} §2) — one
 * ring per disc dimension (overworld + nether), centered on the shared world spawn (the disc
 * origin, pinned by {@code DiscSpawnPlacement}). The ring radius follows the committed world
 * stage: {@code stageOuterRadius + borderOffset} (general.json, default 12); animated stage
 * growth tick-lerps the radius alongside the {@link RingGrowthService} sweep
 * (area-proportional, up to {@value #GROWTH_LERP_TICKS} ticks, snapping when the sweep
 * finishes early; a sweep resumed after a restart re-derives the mid-lerp radius via
 * {@link #resumeGrowthLerp}). State persists in {@link EclipseWorldState}; clients receive
 * {@link S2CBorderPayload} (center, from/to radius, lerp ticks, fx range) at login (both
 * rings) and on every change (players in the affected dimension) and animate the remainder
 * locally.
 *
 * <p><b>Physics</b> (game bus, cheap d² checks; spectators, frozen players and CREATIVE
 * players skipped — creative flight ignores impulses client-side, so admins would only
 * ever get dragged into the teleport fallback):</p>
 * <ul>
 *   <li>{@code d > R}: horizontal impulse {@code normalize(center−pos) ·
 *       min(1.2, 0.25·(d−R)+0.4)} + 0.3 Y with {@code hurtMarked = true} (the proven
 *       {@code StartEventCutscene.risePlayerAt} velocity-sync pattern); elytra flight is
 *       stopped first; a glitch sound + {@code BORDER_GLITCH} Quasar burst play at the
 *       player (throttled).</li>
 *   <li>{@code d > R+3}: teleport fallback onto the clamped point at {@code R−2} — pulled
 *       into the stage's full-thickness interior when the ring is stage-derived — with a
 *       heightmap ground raycast stepping inward until SOLID ground (two consecutive
 *       non-void steps, so a 1-block rim-crumble fragment is never a landing spot), a
 *       {@code surfaceY} landing and a short Slow Falling grace (covers players moving
 *       "impossibly" — e.g. inside Aeronautics/Sable sub-level airships, which are not
 *       vanilla vehicles; see README known limits).</li>
 *   <li><b>Vehicles</b>: the impulse targets {@code getRootVehicle()}; ridden vehicles are
 *       scanned in {@link EntityTickEvent.Post} (only entities carrying player passengers);
 *       {@value #VEHICLE_VIOLATIONS_TO_EJECT} violations within
 *       {@value #VEHICLE_VIOLATION_WINDOW_TICKS} ticks eject the players and teleport them
 *       alone.</li>
 *   <li><b>Pearls/chorus/{@code /tp}</b>: {@link EntityTeleportEvent.EnderPearl}/
 *       {@link EntityTeleportEvent.ChorusFruit}/{@link EntityTeleportEvent.TeleportCommand}
 *       targets are clamped into {@code R−2} via {@code setTargetX/Z} (never cancelled —
 *       cancelling eats pearls). Operators (permission 2+) bypass the command clamp for
 *       inspection.</li>
 *   <li>Repeat violators ({@literal >}{@value #PUSHBACK_LOG_THRESHOLD} pushbacks/min) are
 *       logged on the anti-cheat channel.</li>
 * </ul>
 *
 * <p><b>Failsafe</b>: the vanilla worldborder is kept at {@code overworld ring + 48}
 * (warning 0, damage 0) through {@link BorderController#applyFailsafe} and hidden client-side
 * by the {@code LevelRendererMixin} cancel of {@code LevelRenderer#renderWorldBorder}. The
 * nether ring relies purely on soft physics (vanilla mirrors the overworld border into other
 * dimensions). A nether ring radius of 0 (stage 0 — no disc yet) disables nether physics.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SoftBorder {
    /** Teleport fallback engages beyond {@code R + } this. */
    private static final double TELEPORT_BAND = 3.0D;
    /** Teleport fallback lands at {@code R − } this (before the inward ground search). */
    private static final double TELEPORT_INSET = 2.0D;
    private static final double MAX_IMPULSE = 1.2D;
    private static final double IMPULSE_BASE = 0.4D;
    private static final double IMPULSE_SCALE = 0.25D;
    private static final double IMPULSE_Y = 0.3D;
    /** Vanilla failsafe border sits this far outside the overworld ring. */
    public static final int FAILSAFE_MARGIN = 48;
    /**
     * Stage-growth radius lerp duration — matches the {@code RingGrowthService} animated
     * pacing target (~75 s); the lerp snaps to the target as soon as the sweep completes.
     */
    private static final int GROWTH_LERP_TICKS = 1500;
    /** Ground raycast: max inward steps (of {@value #GROUND_SEARCH_STEP} blocks) hunting for terrain. */
    private static final int GROUND_SEARCH_STEPS = 24;
    private static final int GROUND_SEARCH_STEP = 4;
    /**
     * Slow Falling granted on every teleport fallback (~3 s): even a solid landing column
     * can neighbor a crumble hole — a soft descent can never kill.
     */
    private static final int FALLBACK_SLOW_FALLING_TICKS = 60;
    private static final int SOUND_THROTTLE_TICKS = 15;
    private static final int VEHICLE_VIOLATION_WINDOW_TICKS = 40;
    private static final int VEHICLE_VIOLATIONS_TO_EJECT = 3;
    /** Consecutive impulse ticks within this window count as ONE violation (debounce). */
    private static final int VEHICLE_VIOLATION_DEBOUNCE_TICKS = 5;
    private static final int PUSHBACK_LOG_WINDOW_TICKS = 1200;
    private static final int PUSHBACK_LOG_THRESHOLD = 5;

    /** In-memory radius animations, one per disc profile (persisted value = the target). */
    private static final Map<DiscProfile, Lerp> LERPS = new HashMap<>();
    /** Per-player pushback counters for the anti-cheat repeat-violator log. */
    private static final Map<UUID, ViolationLog> PUSHBACK_LOG = new HashMap<>();
    /** Per-vehicle (entity id) violation windows for the 3-in-40t eject rule. */
    private static final Map<Integer, VehicleViolations> VEHICLE_LOG = new HashMap<>();
    /** Last glitch-sound game time per player (throttle). */
    private static final Map<UUID, Long> LAST_SOUND = new HashMap<>();

    /** {@code sweepCoupled}: stage-commit lerps snap early once the terrain sweep completes. */
    private record Lerp(double fromRadius, double toRadius, long startGameTime, int durationTicks,
            boolean sweepCoupled) {}

    private static final class ViolationLog {
        long windowStartGameTime;
        int pushbacks;
        boolean warned;
    }

    private static final class VehicleViolations {
        long windowStartGameTime;
        long lastCountedGameTime = Long.MIN_VALUE;
        int violations;
    }

    private SoftBorder() {}

    // --- state / geometry ---

    /**
     * Outermost radius with any terrain at the given stage. Overworld stage 0 is special:
     * the playable footprint reaches the player-disc ring (r 170 + 24), not just the main
     * disc (r 96) — same rule as the {@code RingGrowthService} sweep band.
     */
    public static int stageOuterRadius(DiscProfile profile, int stage) {
        if (stage <= 0 && profile == DiscProfile.OVERWORLD) {
            return DiscGeometry.PLAYER_DISC_RING_RADIUS + DiscGeometry.PLAYER_DISC_RADIUS;
        }
        return StageRadii.radius(profile, stage);
    }

    /** Ring center (world spawn / disc origin), from persisted state. */
    public static Vec3 center(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        return new Vec3(state.getBorderCenterX(), 0.0D, state.getBorderCenterZ());
    }

    /**
     * Current ring radius of the profile, including any in-flight growth animation.
     * {@code <= 0} means the ring is inactive in that dimension (nether before stage 1).
     */
    public static double radius(MinecraftServer server, DiscProfile profile) {
        Lerp lerp = LERPS.get(profile);
        if (lerp != null) {
            ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
            long now = level != null ? level.getGameTime() : lerp.startGameTime();
            return animatedRadius(lerp, now);
        }
        return EclipseWorldState.get(server).getSoftBorderRadius(profile);
    }

    /** Effective FX range in blocks: the world-state override, or general.json {@code borderFxRange}. */
    public static double fxRange(MinecraftServer server) {
        double override = EclipseWorldState.get(server).getBorderFxRange();
        return override > 0.0D ? override : EclipseConfig.borderFxRange();
    }

    /**
     * Area-proportional radius interpolation (\u221a of the lerped squared radii) so the ring
     * visually keeps pace with the ring-growth sweep, which fills area at a constant rate.
     */
    private static double animatedRadius(Lerp lerp, long gameTime) {
        double t = Mth.clamp((gameTime - lerp.startGameTime()) / (double) lerp.durationTicks(), 0.0D, 1.0D);
        double fromSq = lerp.fromRadius() * lerp.fromRadius();
        double toSq = lerp.toRadius() * lerp.toRadius();
        return Math.sqrt(Mth.lerp(t, fromSq, toSq));
    }

    // --- change entry points ---

    /**
     * Stage commit hook ({@code WorldStageService.setStage}): retargets the ring to
     * {@code stageOuterRadius + borderOffset}. Animated commits lerp the radius alongside
     * the terrain sweep; instant commits snap. A target of {@code offset} alone (nether
     * stage 0, outer radius 0) deactivates that ring (radius 0).
     */
    public static void onStageCommit(MinecraftServer server, DiscProfile profile, int stage, boolean animate) {
        int outer = stageOuterRadius(profile, stage);
        double target = outer <= 0 ? 0.0D : outer + EclipseConfig.borderOffset();
        setRing(server, profile, target, animate ? GROWTH_LERP_TICKS * 50L : 0L, true);
    }

    /**
     * Retargets the ring of a profile to {@code radius} blocks over {@code ms} milliseconds
     * ({@code <= 0} snaps). Persists the TARGET immediately (a restart mid-animation resumes
     * at the target), starts/replaces the in-memory lerp, updates the vanilla failsafe
     * (overworld only, same duration) and broadcasts {@link S2CBorderPayload}.
     */
    public static void setRing(MinecraftServer server, DiscProfile profile, double radius, long ms) {
        setRing(server, profile, radius, ms, false);
    }

    /** {@code sweepCoupled} = stage-commit path: the lerp snaps once the terrain sweep ends. */
    private static void setRing(MinecraftServer server, DiscProfile profile, double radius, long ms,
            boolean sweepCoupled) {
        double target = Math.max(0.0D, radius);
        double from = radius(server, profile);
        EclipseWorldState state = EclipseWorldState.get(server);
        state.setSoftBorderRadius(profile, target);
        int durationTicks = (int) Math.max(0L, ms / 50L);
        ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
        if (durationTicks > 0 && level != null && from > 0.0D && target > 0.0D) {
            LERPS.put(profile, new Lerp(from, target, level.getGameTime(), durationTicks, sweepCoupled));
        } else {
            LERPS.remove(profile);
            durationTicks = 0;
        }
        if (profile == DiscProfile.OVERWORLD) {
            BorderController.applyFailsafe(server, target, durationTicks * 50L);
        }
        EclipseMod.LOGGER.info("SoftBorder: {} ring set to radius {} (from {}, {})",
                profile.name(), String.format(java.util.Locale.ROOT, "%.1f", target),
                String.format(java.util.Locale.ROOT, "%.1f", from),
                durationTicks > 0 ? "lerp over " + durationTicks + " ticks" : "instant");
        broadcast(server, profile, from, target, durationTicks);
    }

    /**
     * Restart-resume hook ({@code WorldStageService.onServerStarted}): a sweep interrupted
     * by a restart resumes from its persisted cursor, but the PERSISTED ring radius is the
     * commit TARGET — without this the ring would snap to the final radius while the
     * terrain is still mid-growth, leaving a walkable band of pure void inside the ring.
     * Re-derives the mid-lerp radius from the sweep's column progress (the same
     * area-proportional interpolation the live lerp uses), re-installs the sweep-coupled
     * {@link Lerp} over the remaining duration and broadcasts the mid-lerp payload. The
     * vanilla failsafe stays at the final target (it is an outer safety net, 48 beyond).
     */
    public static void resumeGrowthLerp(MinecraftServer server, DiscProfile profile,
            int fromStage, int toStage, double progress) {
        int fromOuter = stageOuterRadius(profile, fromStage);
        int toOuter = stageOuterRadius(profile, toStage);
        double from = fromOuter <= 0 ? 0.0D : fromOuter + EclipseConfig.borderOffset();
        double target = toOuter <= 0 ? 0.0D : toOuter + EclipseConfig.borderOffset();
        ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
        if (level == null || from <= 0.0D || target <= 0.0D) {
            return; // inactive ring on either end — the persisted snap target stands
        }
        double t = Mth.clamp(progress, 0.0D, 1.0D);
        int remainingTicks = (int) Math.ceil(GROWTH_LERP_TICKS * (1.0D - t));
        if (remainingTicks <= 0) {
            return; // sweep effectively done — the tick handler snaps when it completes
        }
        double current = Math.sqrt(Mth.lerp(t, from * from, target * target));
        EclipseWorldState.get(server).setSoftBorderRadius(profile, target);
        LERPS.put(profile, new Lerp(current, target, level.getGameTime(), remainingTicks, true));
        EclipseMod.LOGGER.info(
                "SoftBorder: resumed {} growth lerp at radius {} ({}% swept) -> {} over {} ticks",
                profile.name(), String.format(java.util.Locale.ROOT, "%.1f", current),
                String.format(java.util.Locale.ROOT, "%.0f", t * 100.0D),
                String.format(java.util.Locale.ROOT, "%.1f", target), remainingTicks);
        broadcast(server, profile, current, target, remainingTicks);
    }

    /** Persists a new FX visibility range (blocks) and re-syncs all clients. */
    public static void setFxRange(MinecraftServer server, double blocks) {
        EclipseWorldState.get(server).setBorderFxRange(Math.max(1.0D, blocks));
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            double radius = radius(server, profile);
            broadcast(server, profile, radius, radius, 0);
        }
    }

    // --- sync ---

    /** Sends both rings' current state to one player (login sync). */
    public static void syncTo(ServerPlayer player) {
        MinecraftServer server = player.server;
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            PacketDistributor.sendToPlayer(player, payload(server, profile));
        }
    }

    /** Ring changes only matter to players IN that ring's dimension (login sync covers the rest). */
    private static void broadcast(MinecraftServer server, DiscProfile profile,
            double fromRadius, double toRadius, int lerpTicks) {
        ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
        if (level == null) {
            return;
        }
        Vec3 center = center(server);
        PacketDistributor.sendToPlayersInDimension(level, new S2CBorderPayload(profile.name(),
                center.x, center.z, (float) fromRadius, (float) toRadius, lerpTicks, (float) fxRange(server)));
    }

    /** Current-state payload for one profile: mid-lerp sends the remaining animation. */
    private static S2CBorderPayload payload(MinecraftServer server, DiscProfile profile) {
        Vec3 center = center(server);
        Lerp lerp = LERPS.get(profile);
        double current = radius(server, profile);
        double target = EclipseWorldState.get(server).getSoftBorderRadius(profile);
        int remaining = 0;
        if (lerp != null) {
            ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
            long now = level != null ? level.getGameTime() : lerp.startGameTime();
            remaining = (int) Math.max(0L, lerp.startGameTime() + lerp.durationTicks() - now);
        }
        return new S2CBorderPayload(profile.name(), center.x, center.z,
                (float) current, (float) target, remaining, (float) fxRange(server));
    }

    // --- lifecycle ---

    /**
     * Activation: pins the ring center to the world spawn, derives any unset ({@code < 0})
     * radius from the committed stage, and enforces the vanilla failsafe. Runs after
     * {@code DiscSpawnPlacement} (HIGH priority) has pinned the spawn itself.
     */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        BlockPos spawn = server.overworld().getSharedSpawnPos();
        state.setBorderCenter(spawn.getX() + 0.5D, spawn.getZ() + 0.5D);
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            double radius = state.getSoftBorderRadius(profile);
            if (radius < 0.0D) {
                int stage = state.getWorldStage(profile);
                int outer = stageOuterRadius(profile, stage);
                radius = outer <= 0 ? 0.0D : outer + EclipseConfig.borderOffset();
                state.setSoftBorderRadius(profile, radius);
                EclipseMod.LOGGER.info("SoftBorder: {} ring derived from stage {}: radius {}",
                        profile.name(), stage, radius);
            }
            EclipseMod.LOGGER.info("SoftBorder active: {} ring radius {} centered on ({}, {}), fx range {}",
                    profile.name(), radius, state.getBorderCenterX(), state.getBorderCenterZ(),
                    fxRange(server));
        }
        BorderController.applyFailsafe(server, state.getSoftBorderRadius(DiscProfile.OVERWORLD), 0L);
    }

    /** Finishes radius lerps: snaps when the paced time elapses OR the terrain sweep completes early. */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (LERPS.isEmpty()) {
            return;
        }
        MinecraftServer server = event.getServer();
        for (DiscProfile profile : LERPS.keySet().toArray(new DiscProfile[0])) {
            Lerp lerp = LERPS.get(profile);
            ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
            if (level == null) {
                LERPS.remove(profile);
                continue;
            }
            long now = level.getGameTime();
            boolean timeUp = now >= lerp.startGameTime() + lerp.durationTicks();
            boolean sweepDone = lerp.sweepCoupled() && !RingGrowthService.isRunning(profile);
            if (timeUp || sweepDone) {
                LERPS.remove(profile);
                double target = lerp.toRadius();
                EclipseMod.LOGGER.info("SoftBorder: {} ring reached radius {} ({})", profile.name(),
                        target, timeUp ? "lerp complete" : "sweep finished early, snapped");
                if (!timeUp) {
                    // Clients were told the full duration; re-sync the snapped value.
                    broadcast(server, profile, target, target, 0);
                    if (profile == DiscProfile.OVERWORLD) {
                        BorderController.applyFailsafe(server, target, 0L);
                    }
                }
            }
        }
    }

    /** UUID-keyed throttle/anti-cheat maps must not grow with every player who ever joined. */
    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        UUID id = event.getEntity().getUUID();
        PUSHBACK_LOG.remove(id);
        LAST_SOUND.remove(id);
    }

    /**
     * Dimension changes re-send both rings and both stages to the traveller: ring/stage
     * broadcasts only go to players IN the affected dimension, so someone in the nether
     * during an overworld commit would otherwise come back with stale border/stage state.
     */
    @SubscribeEvent
    public static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            syncTo(player);
            WorldStageService.syncStagesTo(player);
        }
    }

    /** Statics must never leak into the next world (singleplayer re-opens reuse the JVM). */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        LERPS.clear();
        PUSHBACK_LOG.clear();
        VEHICLE_LOG.clear();
        LAST_SOUND.clear();
    }

    // --- physics: players ---

    @SubscribeEvent
    public static void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !(player.level() instanceof ServerLevel level)) {
            return;
        }
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null || player.isSpectator() || FreezeService.isFrozen(player)) {
            return;
        }
        if (player.getRootVehicle() != player) {
            return; // ridden vehicles are handled (impulsed/ejected) in onEntityTick
        }
        MinecraftServer server = level.getServer();
        double radius = radius(server, profile);
        if (radius <= 0.0D) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        double dx = player.getX() - state.getBorderCenterX();
        double dz = player.getZ() - state.getBorderCenterZ();
        double distSq = dx * dx + dz * dz;
        if (distSq <= radius * radius) {
            return;
        }
        double dist = Math.sqrt(distSq);
        if (player.isCreative()) {
            // Creative flight ignores impulses client-side, so physics would only ever
            // drag admins into the teleport fallback — exempt them, but keep a trace.
            EclipseMod.LOGGER.debug("SoftBorder: creative player {} is beyond the {} ring (d={}, R={}) — exempt",
                    player.getScoreboardName(), profile.name(),
                    String.format(java.util.Locale.ROOT, "%.1f", dist),
                    String.format(java.util.Locale.ROOT, "%.1f", radius));
            return;
        }
        if (dist > radius + TELEPORT_BAND) {
            teleportInside(player, level, profile, dist, dx, dz);
        } else {
            impulseInward(player, level, dist, radius, dx, dz);
            playGlitchFeedback(player, level);
        }
        logPushback(player, level, profile, dist, radius);
    }

    /** Zone 2 impulse on any entity (player or root vehicle): documented pushback formula. */
    private static void impulseInward(Entity entity, ServerLevel level, double dist, double radius,
            double dx, double dz) {
        if (entity instanceof ServerPlayer player && player.isFallFlying()) {
            player.stopFallFlying();
        }
        double strength = Math.min(MAX_IMPULSE, IMPULSE_SCALE * (dist - radius) + IMPULSE_BASE);
        double inv = 1.0D / dist;
        Vec3 velocity = new Vec3(-dx * inv * strength, IMPULSE_Y, -dz * inv * strength);
        entity.setDeltaMovement(velocity);
        entity.hurtMarked = true; // sync the velocity to the client (risePlayerAt pattern)
        EclipseMod.LOGGER.debug("SoftBorder: impulse on {} at d={} (R={}): v=({}, {}, {})",
                entity.getScoreboardName(), String.format(java.util.Locale.ROOT, "%.2f", dist),
                String.format(java.util.Locale.ROOT, "%.1f", radius),
                String.format(java.util.Locale.ROOT, "%.2f", velocity.x),
                String.format(java.util.Locale.ROOT, "%.2f", velocity.y),
                String.format(java.util.Locale.ROOT, "%.2f", velocity.z));
    }

    /**
     * Zone 3 fallback: teleport onto the clamped ring point with an inward ground search.
     * The naive start would be {@code R − 2} — but {@code R = stageOuterRadius +
     * borderOffset}, i.e. ~10 blocks BEYOND the outermost terrain, and the first non-void
     * heightmap hit out there can be a 1-block rim-crumble fragment (a void-death drop).
     * So for a stage-derived ring the search starts at
     * {@code min(R − 2, stageOuterRadius − RIM_REWRITE_MARGIN)} (full-thickness interior,
     * inside the rim taper/crumble band), requires TWO consecutive non-void heightmap
     * steps (the landing column plus its inward neighbor — isolated fragments fail this),
     * lands exactly at {@code surfaceY} (feet on the ground, no drop) and grants ~3 s of
     * Slow Falling as a final safety net.
     */
    private static void teleportInside(ServerPlayer player, ServerLevel level, DiscProfile profile,
            double dist, double dx, double dz) {
        MinecraftServer server = level.getServer();
        double radius = radius(server, profile);
        EclipseWorldState state = EclipseWorldState.get(server);
        double inv = 1.0D / dist;
        double dirX = dx * inv;
        double dirZ = dz * inv;
        double startR = Math.max(0.0D, radius - TELEPORT_INSET);
        int stageOuter = stageOuterRadius(profile, state.getWorldStage(profile));
        if (stageOuter > 0) {
            // Stage-derived ring: pull the start inside the rim rewrite margin, where the
            // terrain function guarantees full-thickness interior columns.
            startR = Math.min(startR,
                    Math.max(0.0D, stageOuter - (double) DiscTerrainFunction.RIM_REWRITE_MARGIN));
        }
        for (int step = 0; step <= GROUND_SEARCH_STEPS; step++) {
            double r = Math.max(0.0D, startR - (double) step * GROUND_SEARCH_STEP);
            double tx = state.getBorderCenterX() + dirX * r;
            double tz = state.getBorderCenterZ() + dirZ * r;
            int surfaceY = groundSurfaceY(level, tx, tz);
            if (surfaceY <= level.getMinBuildHeight()) {
                continue; // void column (rim taper / never-generated) — search further inward
            }
            // Solid-ground requirement: the next step inward must be terrain too, so a
            // lone rim-crumble fragment can never become the landing column.
            double innerR = Math.max(0.0D, r - GROUND_SEARCH_STEP);
            int innerSurfaceY = groundSurfaceY(level,
                    state.getBorderCenterX() + dirX * innerR, state.getBorderCenterZ() + dirZ * innerR);
            if (innerSurfaceY <= level.getMinBuildHeight()) {
                continue;
            }
            player.stopFallFlying();
            player.teleportTo(level, tx, surfaceY, tz, player.getYRot(), player.getXRot());
            player.setDeltaMovement(Vec3.ZERO);
            player.hurtMarked = true;
            player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                    FALLBACK_SLOW_FALLING_TICKS, 0, false, false));
            playGlitchFeedback(player, level);
            EclipseMod.LOGGER.debug("SoftBorder: teleport fallback for {} from d={} to r={} ({}, {}, {})",
                    player.getScoreboardName(), String.format(java.util.Locale.ROOT, "%.1f", dist),
                    String.format(java.util.Locale.ROOT, "%.1f", r),
                    String.format(java.util.Locale.ROOT, "%.1f", tx), surfaceY,
                    String.format(java.util.Locale.ROOT, "%.1f", tz));
            return;
        }
        // No ground found along the ray (should not happen inside the disc) — spawn fallback,
        // onto the heightmap surface (a raw spawn.getY() can float above or sit inside terrain).
        BlockPos spawn = level.getSharedSpawnPos();
        int spawnSurfaceY = groundSurfaceY(level, spawn.getX() + 0.5D, spawn.getZ() + 0.5D);
        if (spawnSurfaceY <= level.getMinBuildHeight()) {
            spawnSurfaceY = spawn.getY();
        }
        player.teleportTo(level, spawn.getX() + 0.5D, spawnSurfaceY, spawn.getZ() + 0.5D,
                player.getYRot(), player.getXRot());
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING,
                FALLBACK_SLOW_FALLING_TICKS, 0, false, false));
        EclipseMod.LOGGER.warn("SoftBorder: no ground found for the {} teleport fallback; sent to spawn",
                player.getScoreboardName());
    }

    /**
     * Heightmap surface Y (first free block above the terrain) of a column;
     * {@code <= getMinBuildHeight()} means the column is void OR its chunk is not loaded.
     * Only already-loaded chunks are consulted ({@code getChunkNow}) — the probe runs on
     * the physics tick path and force-loading here meant up to ~50 sync chunk loads per
     * violator per tick; an unloaded probe step just makes the search continue inward
     * (the spawn-area fallback at the end is always loaded).
     */
    private static int groundSurfaceY(ServerLevel level, double x, double z) {
        int blockX = Mth.floor(x);
        int blockZ = Mth.floor(z);
        LevelChunk chunk = level.getChunkSource().getChunkNow(blockX >> 4, blockZ >> 4);
        if (chunk == null) {
            return Integer.MIN_VALUE;
        }
        return chunk.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, blockX & 15, blockZ & 15) + 1;
    }

    /** Glitch sound (throttled per player) + one BORDER_GLITCH Quasar burst at the player. */
    private static void playGlitchFeedback(ServerPlayer player, ServerLevel level) {
        long now = level.getGameTime();
        Long last = LAST_SOUND.get(player.getUUID());
        if (last != null && now - last < SOUND_THROTTLE_TICKS) {
            return;
        }
        LAST_SOUND.put(player.getUUID(), now);
        level.playSound(null, player.blockPosition(), EclipseSounds.EVENT_BORDER_GLITCH.get(),
                SoundSource.AMBIENT, 0.8F, 0.9F + level.random.nextFloat() * 0.2F);
        PacketDistributor.sendToPlayersNear(level, null, player.getX(), player.getY(), player.getZ(),
                64.0D, new S2CQuasarPayload(S2CQuasarPayload.BORDER_GLITCH, player.position()));
    }

    /** Anti-cheat channel: warns once per minute-window for players with >5 pushbacks/min. */
    private static void logPushback(ServerPlayer player, ServerLevel level, DiscProfile profile,
            double dist, double radius) {
        long now = level.getGameTime();
        ViolationLog log = PUSHBACK_LOG.computeIfAbsent(player.getUUID(), id -> new ViolationLog());
        if (now - log.windowStartGameTime > PUSHBACK_LOG_WINDOW_TICKS) {
            log.windowStartGameTime = now;
            log.pushbacks = 0;
            log.warned = false;
        }
        log.pushbacks++;
        if (log.pushbacks > PUSHBACK_LOG_THRESHOLD && !log.warned) {
            log.warned = true;
            EclipseMod.LOGGER.warn("Anti-cheat: {} hit the {} soft border {} times within a minute "
                            + "(last at d={}, R={})",
                    player.getScoreboardName(), profile.name(), log.pushbacks,
                    String.format(java.util.Locale.ROOT, "%.1f", dist),
                    String.format(java.util.Locale.ROOT, "%.1f", radius));
        }
    }

    // --- physics: vehicles carrying players ---

    @SubscribeEvent
    public static void onEntityTick(EntityTickEvent.Post event) {
        Entity entity = event.getEntity();
        // Cheapest checks first — this fires for every entity every tick.
        if (entity instanceof Player || entity.isPassenger() || entity.getPassengers().isEmpty()
                || !(entity.level() instanceof ServerLevel level)) {
            return;
        }
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null) {
            return;
        }
        ServerPlayer rider = firstPlayerPassenger(entity);
        if (rider == null) {
            return;
        }
        MinecraftServer server = level.getServer();
        double radius = radius(server, profile);
        if (radius <= 0.0D) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        double dx = entity.getX() - state.getBorderCenterX();
        double dz = entity.getZ() - state.getBorderCenterZ();
        double distSq = dx * dx + dz * dz;
        if (distSq <= radius * radius) {
            return;
        }
        double dist = Math.sqrt(distSq);
        long now = level.getGameTime();
        VehicleViolations violations = VEHICLE_LOG.computeIfAbsent(entity.getId(), id -> new VehicleViolations());
        if (now - violations.windowStartGameTime > VEHICLE_VIOLATION_WINDOW_TICKS) {
            violations.windowStartGameTime = now;
            violations.violations = 0;
        }
        if (now - violations.lastCountedGameTime >= VEHICLE_VIOLATION_DEBOUNCE_TICKS) {
            violations.lastCountedGameTime = now;
            violations.violations++;
        }
        if (violations.violations >= VEHICLE_VIOLATIONS_TO_EJECT) {
            VEHICLE_LOG.remove(entity.getId());
            EclipseMod.LOGGER.debug("SoftBorder: vehicle {} re-violated {}x in {}t — ejecting players",
                    entity.getScoreboardName(), VEHICLE_VIOLATIONS_TO_EJECT, VEHICLE_VIOLATION_WINDOW_TICKS);
            for (Entity passenger : entity.getIndirectPassengers()) {
                if (passenger instanceof ServerPlayer player && !player.isCreative()) {
                    player.stopRiding();
                    teleportInside(player, level, profile, dist, dx, dz);
                    logPushback(player, level, profile, dist, radius);
                }
            }
        } else {
            impulseInward(entity, level, dist, radius, dx, dz);
            playGlitchFeedback(rider, level);
            logPushback(rider, level, profile, dist, radius);
        }
    }

    /**
     * First policed (non-creative, non-spectator) player passenger, or {@code null} — a
     * vehicle crewed only by exempt players is itself exempt from the border physics.
     */
    @Nullable
    private static ServerPlayer firstPlayerPassenger(Entity vehicle) {
        for (Entity passenger : vehicle.getIndirectPassengers()) {
            if (passenger instanceof ServerPlayer player && !player.isCreative() && !player.isSpectator()) {
                return player;
            }
        }
        return null;
    }

    // --- teleport clamps (pearls, chorus, /tp) ---

    @SubscribeEvent
    public static void onEnderPearl(EntityTeleportEvent.EnderPearl event) {
        clampTeleport(event, event.getPlayer());
    }

    @SubscribeEvent
    public static void onChorusFruit(EntityTeleportEvent.ChorusFruit event) {
        clampTeleport(event, event.getEntityLiving());
    }

    /** Command teleports are clamped for regular players; operators bypass for inspection. */
    @SubscribeEvent
    public static void onTeleportCommand(EntityTeleportEvent.TeleportCommand event) {
        Entity entity = event.getEntity();
        if (entity instanceof ServerPlayer player && player.hasPermissions(2)) {
            return;
        }
        clampTeleport(event, entity);
    }

    /**
     * Clamps the teleport TARGET into {@code R−2} (never cancels — cancelling eats pearls).
     * The Y is left untouched; the regular physics tick cleans up any residual mismatch.
     */
    private static void clampTeleport(EntityTeleportEvent event, Entity entity) {
        if (entity == null || !(entity.level() instanceof ServerLevel level)) {
            return;
        }
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null) {
            return;
        }
        MinecraftServer server = level.getServer();
        double radius = radius(server, profile);
        if (radius <= 0.0D) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        double dx = event.getTargetX() - state.getBorderCenterX();
        double dz = event.getTargetZ() - state.getBorderCenterZ();
        double distSq = dx * dx + dz * dz;
        double maxR = Math.max(0.0D, radius - TELEPORT_INSET);
        if (distSq <= maxR * maxR) {
            return;
        }
        double dist = Math.sqrt(distSq);
        double scale = maxR / dist;
        event.setTargetX(state.getBorderCenterX() + dx * scale);
        event.setTargetZ(state.getBorderCenterZ() + dz * scale);
        EclipseMod.LOGGER.debug("SoftBorder: clamped a {} teleport of {} from d={} into R-2={}",
                event.getClass().getSimpleName(), entity.getScoreboardName(),
                String.format(java.util.Locale.ROOT, "%.1f", dist),
                String.format(java.util.Locale.ROOT, "%.1f", maxR));
    }
}
