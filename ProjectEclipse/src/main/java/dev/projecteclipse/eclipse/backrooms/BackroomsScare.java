package dev.projecteclipse.eclipse.backrooms;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * THE jumpscare — server-side trigger rules (IDEAS-backrooms_finale §A4), evaluated from
 * {@code BackroomsEventService}'s 10 t tick while OPEN:
 *
 * <ul>
 *   <li>Once per player per instance ({@code BackroomsState.markScared} — persisted, the
 *       {@code markRewardGranted()} law: relogs cannot re-arm it).</li>
 *   <li>Player inside &gt; {@value #MIN_INSIDE_MILLIS} ms; a Wanderer within
 *       {@value #PROXIMITY} blocks; in the player's rear 180° arc
 *       ({@code dot(look, toMob) < 0}); currently UNSEEN (the husk gaze test via
 *       {@link GlitchedWandererEntity#isSeenBy}); random gate 1 in {@value #RANDOM_GATE}
 *       per check (expected ~5 min of exposure).</li>
 *   <li>Global {@value #GLOBAL_COOLDOWN_MILLIS} ms cooldown — a group never chain-scares
 *       (one scream at a time reads scarier).</li>
 *   <li>After firing, the Wanderer immediately consumes its blink: teleports
 *       {@value #BLINK_MIN}–{@value #BLINK_MAX} blocks away. No damage — the scare IS
 *       the attack.</li>
 * </ul>
 *
 * <p>Presentation is entirely client-side ({@code S2CJumpscarePayload} →
 * {@code client.backrooms.JumpscareOverlay}), so {@code reducedFx} clients get their
 * vignette+sound fallback without the server caring.</p>
 */
public final class BackroomsScare {
    private static final long MIN_INSIDE_MILLIS = 90_000L;
    private static final double PROXIMITY = 7.0D;
    private static final int RANDOM_GATE = 30;
    private static final long GLOBAL_COOLDOWN_MILLIS = 60_000L;
    private static final double BLINK_MIN = 10.0D;
    private static final double BLINK_MAX = 14.0D;
    private static final int BLINK_ATTEMPTS = 12;

    /** Wall-clock stamp of the last fired scare (transient; reset by the service). */
    private static long lastScareMillis;

    private BackroomsScare() {}

    /** Clears the transient cooldown (event start / server stop). */
    static void reset() {
        lastScareMillis = 0L;
    }

    /** One evaluation pass over all players inside; called every 10 t while OPEN. */
    static void tick(MinecraftServer server, BackroomsState state, ServerLevel level) {
        long now = System.currentTimeMillis();
        if (now - lastScareMillis < GLOBAL_COOLDOWN_MILLIS) {
            return;
        }
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (player.isSpectator() || !player.isAlive() || state.isScared(player.getUUID())) {
                continue;
            }
            long enteredAt = state.enteredAtEpochMillis(player.getUUID());
            if (enteredAt <= 0L || now - enteredAt < MIN_INSIDE_MILLIS) {
                continue;
            }
            if (level.random.nextInt(RANDOM_GATE) != 0) {
                continue;
            }
            GlitchedWandererEntity stalker = findRearStalker(level, player);
            if (stalker == null) {
                continue;
            }
            if (!state.markScared(player.getUUID())) {
                continue; // raced a concurrent mark — the set is the arbiter
            }
            lastScareMillis = now;
            fire(level, player, stalker);
            return; // one scream at a time
        }
    }

    /** A Wanderer ≤ {@value #PROXIMITY} blocks, in the rear arc, currently unseen. */
    private static GlitchedWandererEntity findRearStalker(ServerLevel level, ServerPlayer player) {
        AABB box = player.getBoundingBox().inflate(PROXIMITY);
        Vec3 look = player.getViewVector(1.0F).normalize();
        for (GlitchedWandererEntity wanderer
                : level.getEntitiesOfClass(GlitchedWandererEntity.class, box)) {
            if (!wanderer.isAlive()) {
                continue;
            }
            if (wanderer.distanceToSqr(player) > PROXIMITY * PROXIMITY) {
                continue;
            }
            Vec3 toMob = wanderer.position().subtract(player.position());
            if (toMob.lengthSqr() < 1.0E-4D || look.dot(toMob.normalize()) >= 0.0D) {
                continue; // not in the rear 180° arc
            }
            if (wanderer.isSeenBy(player)) {
                continue; // being watched — no scare while observed (the lookaway rule)
            }
            return wanderer;
        }
        return null;
    }

    /** Send the envelope payload, then the Wanderer blinks 10–14 blocks away. */
    private static void fire(ServerLevel level, ServerPlayer player, GlitchedWandererEntity stalker) {
        BackroomsPayloads.sendJumpscare(player, 1.0F);
        blinkAway(level, stalker);
        EclipseMod.LOGGER.info("Backrooms jumpscare fired on {} (stalker at {})",
                player.getScoreboardName(), stalker.blockPosition().toShortString());
    }

    /** The consumed glitch-blink: ground-snapped hop {@value #BLINK_MIN}–{@value #BLINK_MAX} out. */
    private static void blinkAway(ServerLevel level, GlitchedWandererEntity stalker) {
        Vec3 origin = stalker.position();
        for (int attempt = 0; attempt < BLINK_ATTEMPTS; attempt++) {
            double angle = level.random.nextDouble() * Math.PI * 2.0D;
            double distance = BLINK_MIN + level.random.nextDouble() * (BLINK_MAX - BLINK_MIN);
            double x = stalker.getX() + Math.cos(angle) * distance;
            double y = stalker.getY() + (level.random.nextInt(3) - 1);
            double z = stalker.getZ() + Math.sin(angle) * distance;
            if (stalker.randomTeleport(x, y, z, false)) {
                level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        origin.x, origin.y + 1.0D, origin.z, 14, 0.3D, 0.4D, 0.3D, 0.03D);
                level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        stalker.getX(), stalker.getY() + 1.0D, stalker.getZ(),
                        14, 0.3D, 0.4D, 0.3D, 0.03D);
                level.playSound(null, stalker.blockPosition(), SoundEvents.ENDERMAN_TELEPORT,
                        SoundSource.HOSTILE, 0.5F, 1.2F);
                return;
            }
        }
        // Cramped corridor pocket: the blink fizzles — acceptable; the scare already fired.
    }
}
