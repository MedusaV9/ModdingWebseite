package dev.projecteclipse.eclipse.glitchzone;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;

/**
 * F-048 — the altar's own glitch. While players stand near the sanctum altar, the world
 * occasionally (see {@link #MIN_INTERVAL_TICKS}..{@link #MAX_INTERVAL_TICKS}) drops a short
 * PURPLE {@code void} zone centred on the altar block, and the void's sonar impulse radiates
 * from the ALTAR instead of from the camera ({@link GlitchZone#originAtCentre}).
 *
 * <p>Mechanically this is not a new subsystem: it creates an ordinary {@link GlitchZone}, so
 * it inherits persistence, the epsilon-gated sync, the spatial edge falloff and the client
 * ease for free — and it inherits the GLITCHZONE silence contract, which is the point. There
 * is no chat line, no title, no boss bar and no subtitle-worthy bang: only a sculk click and
 * a slow heartbeat at the altar, plus reality draining purple for a few seconds. A player who
 * looks away misses it entirely.</p>
 *
 * <p>Ticked from {@link GlitchZoneService#onServerTick} (the feature's single tick driver);
 * the schedule lives in {@link GlitchZoneState} so a restart cannot re-roll the cadence into
 * an immediate fire. Static state here is only the in-flight run (heartbeat clock + the id of
 * the zone we spawned) and is cleared with the service caches.</p>
 */
public final class AltarGlitchAmbience {
    /** The zone this event spawns: the void grade in purple, pinging from the altar. */
    public static final String EFFECT = GlitchZoneEffects.VOID;
    public static final String COLOUR = "purple";

    /** A player must be this close to the altar for the event to be allowed to fire. */
    public static final double TRIGGER_RANGE = 24.0D;
    /**
     * Zone radius. Deliberately larger than {@link #TRIGGER_RANGE} so the trigger distance
     * sits INSIDE the sphere's edge band (band = r·0.25 = 7 blocks): a player at the 24-block
     * trigger ring already sees ~60% strength instead of 0, and walking out during the event
     * fades rather than cuts.
     */
    public static final double ZONE_RADIUS = 28.0D;

    /** Cadence: uniform in [8 min, 15 min] → mean ~11.5 min between eligible fires. */
    public static final int MIN_INTERVAL_TICKS = 8 * 60 * 20;
    public static final int MAX_INTERVAL_TICKS = 15 * 60 * 20;
    /** Hard floor between two fires — also covers a long-deferred date and {@code /dev}. */
    public static final int MIN_GAP_TICKS = 5 * 60 * 20;

    /** Event length: uniform in [8 s, 15 s], inclusive of both ramps. */
    public static final int MIN_DURATION_TICKS = 8 * 20;
    public static final int MAX_DURATION_TICKS = 15 * 20;
    /** Intensity ramps: 2.5 s swell in, 3.5 s drain out (smoothstepped in, linear out). */
    public static final int FADE_IN_TICKS = 50;
    public static final int FADE_OUT_TICKS = 70;

    /** Eligibility is evaluated once a second; the heartbeat runs on its own 2 s clock. */
    private static final int POLL_TICKS = 20;
    /** Date reached but nobody near: re-check in 10 s instead of re-rolling the interval. */
    private static final int RETRY_TICKS = 200;
    private static final int HEARTBEAT_TICKS = 40;

    /** Onset/heartbeat/withdraw volumes — "leise" is a spec, not a taste (all ≤ 0.45). */
    private static final float ONSET_VOLUME = 0.45F;
    private static final float HEARTBEAT_VOLUME = 0.25F;
    private static final float WITHDRAW_VOLUME = 0.30F;

    /** In-flight run (transient): the zone we spawned, where it sits, and its clocks. */
    @Nullable
    private static UUID activeZoneId;
    @Nullable
    private static BlockPos activeAltar;
    private static long activeEndGameTime;
    private static long nextHeartbeatGameTime;
    private static boolean withdrawPlayed;
    /** Transient back-off after an ineligible due date — deliberately NOT persisted. */
    private static long retryAfterGameTime;

    private AltarGlitchAmbience() {}

    /**
     * One server tick of the ambient event. Cheap on the common path: a modulo gate, then a
     * saved-data read and (only when the date is due) a player scan.
     */
    static void tick(MinecraftServer server, GlitchZoneState state, long now) {
        tickActiveRun(server, now);
        if (now % POLL_TICKS != 0L || now < retryAfterGameTime) {
            return;
        }
        long next = state.ambientNextGameTime();
        if (next == 0L) {
            // First boot of this save: arm a date instead of firing immediately.
            state.setAmbientNextGameTime(now + rollInterval(server.overworld().getRandom()));
            return;
        }
        if (now < next || now - state.ambientLastGameTime() < MIN_GAP_TICKS) {
            return;
        }
        if (!fire(server, state, now, false)) {
            // Not eligible right now (nobody near, altar unbuilt/unloaded, altar already
            // glitched). The DUE DATE stays where it is — it was legitimately reached — and
            // the back-off is transient, so no saved-data write happens on this path and an
            // unattended altar cannot dirty the file every ten seconds for a whole session.
            retryAfterGameTime = now + RETRY_TICKS;
        }
    }

    /**
     * Fires the event now if the world allows it. {@code forced} skips only the minimum-gap
     * check (the {@code /dev glitch altar} path) — an operator still cannot conjure the
     * event without a built, loaded altar.
     *
     * @return whether a zone was created
     */
    public static boolean fire(MinecraftServer server, GlitchZoneState state, long now, boolean forced) {
        BlockPos altar = altarPos(server);
        if (altar == null) {
            return false;
        }
        ServerLevel overworld = server.overworld();
        if (!overworld.isLoaded(altar)) {
            return false;
        }
        if (!forced && !anyoneNear(overworld, altar)) {
            return false;
        }
        if (alreadyGlitched(state, altar, now)) {
            return false;
        }

        RandomSource random = overworld.getRandom();
        int duration = MIN_DURATION_TICKS
                + random.nextInt(MAX_DURATION_TICKS - MIN_DURATION_TICKS + 1);
        GlitchZone zone = new GlitchZone(UUID.randomUUID(), overworld.dimension(), altar,
                ZONE_RADIUS, EFFECT, COLOUR, now, now + duration,
                FADE_IN_TICKS, FADE_OUT_TICKS, true);
        if (!state.add(zone)) {
            return false; // zone cap reached; the operator's zones win
        }
        state.markAmbientFired(now, now + duration + rollInterval(random));

        activeZoneId = zone.id();
        activeAltar = altar;
        activeEndGameTime = zone.endGameTime();
        nextHeartbeatGameTime = now + HEARTBEAT_TICKS;
        withdrawPlayed = false;
        retryAfterGameTime = 0L;

        // Onset: a sculk sensor waking plus one slow heart. Ambient source, low volume —
        // vanilla attenuates it to nothing well before the zone edge, which is intended:
        // the sound belongs to the altar, the glitch belongs to the area.
        overworld.playSound(null, altar, SoundEvents.SCULK_CLICKING, SoundSource.AMBIENT,
                ONSET_VOLUME, 0.55F);
        overworld.playSound(null, altar, SoundEvents.WARDEN_HEARTBEAT, SoundSource.AMBIENT,
                HEARTBEAT_VOLUME + 0.10F, 0.70F);

        EclipseMod.LOGGER.info("Altar glitch ambience fired at {} for {} t (id {}{})",
                altar.toShortString(), duration, zone.id(), forced ? ", forced" : "");
        return true;
    }

    /** Heartbeat + withdraw click while our zone is live; clears the run when it expires. */
    private static void tickActiveRun(MinecraftServer server, long now) {
        BlockPos altar = activeAltar;
        if (activeZoneId == null || altar == null) {
            return;
        }
        if (now >= activeEndGameTime) {
            activeZoneId = null;
            activeAltar = null;
            return;
        }
        ServerLevel overworld = server.overworld();
        if (!withdrawPlayed && now >= activeEndGameTime - FADE_OUT_TICKS) {
            withdrawPlayed = true;
            overworld.playSound(null, altar, SoundEvents.SCULK_CLICKING_STOP,
                    SoundSource.AMBIENT, WITHDRAW_VOLUME, 0.60F);
            return;
        }
        if (now >= nextHeartbeatGameTime) {
            nextHeartbeatGameTime = now + HEARTBEAT_TICKS;
            overworld.playSound(null, altar, SoundEvents.WARDEN_HEARTBEAT,
                    SoundSource.AMBIENT, HEARTBEAT_VOLUME, 0.70F);
        }
    }

    /** The sanctum altar block, or {@code null} while the sanctum has not been built. */
    @Nullable
    public static BlockPos altarPos(MinecraftServer server) {
        return EclipseWorldState.get(server).getSanctumAltarPos();
    }

    /** Whether a non-spectator player stands within {@link #TRIGGER_RANGE} of the altar. */
    private static boolean anyoneNear(ServerLevel overworld, BlockPos altar) {
        double rangeSqr = TRIGGER_RANGE * TRIGGER_RANGE;
        for (ServerPlayer player : overworld.players()) {
            if (player.isSpectator()) {
                continue;
            }
            if (player.distanceToSqr(altar.getX() + 0.5D, altar.getY() + 0.5D, altar.getZ() + 0.5D)
                    <= rangeSqr) {
                return true;
            }
        }
        return false;
    }

    /** Never stack the ambience on top of a zone that already owns the altar's screen. */
    private static boolean alreadyGlitched(GlitchZoneState state, BlockPos altar, long now) {
        for (GlitchZone zone : state.all()) {
            if (zone.endGameTime() <= now) {
                continue;
            }
            double distSqr = zone.centre().distSqr(altar);
            if (distSqr <= zone.radius() * zone.radius()) {
                return true;
            }
        }
        return false;
    }

    private static int rollInterval(RandomSource random) {
        return MIN_INTERVAL_TICKS + random.nextInt(MAX_INTERVAL_TICKS - MIN_INTERVAL_TICKS + 1);
    }

    /** Ticks until the next eligible fire, for {@code /dev glitch altar} status output. */
    public static long ticksUntilNext(GlitchZoneState state, long now) {
        long earliest = Math.max(state.ambientNextGameTime(),
                state.ambientLastGameTime() + MIN_GAP_TICKS);
        return Math.max(0L, earliest - now);
    }

    /** Transient run reset — called from the service's server-stopped hook. */
    static void reset() {
        activeZoneId = null;
        activeAltar = null;
        activeEndGameTime = 0L;
        nextHeartbeatGameTime = 0L;
        withdrawPlayed = false;
        retryAfterGameTime = 0L;
    }
}
