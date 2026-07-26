package dev.projecteclipse.eclipse.backrooms;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The DREAD layer of the Backrooms event (F-042 "Scary Part") — everything that makes
 * being hunted <i>audible</i>, evaluated server-side from {@code BackroomsEventService}'s
 * 10 t inside-tick while the event is OPEN. Three independent per-player channels, all
 * cooldown-gated (there is no per-tick work and no block writes anywhere in this class):
 *
 * <ul>
 *   <li><b>Pursuit audio</b>: while a backrooms mob has the player as its target (or, for
 *       the Wanderer, as its {@link GlitchedWandererEntity#pacedPlayer()}) within
 *       {@value #CHASE_RANGE} blocks, that player — and ONLY that player — hears a deep
 *       heartbeat thud plus the mob's own scrape/step, both scaling with distance:
 *       quiet and slow ({@value #CHASE_BEAT_FAR_TICKS} t apart) at 20 blocks, loud and
 *       fast ({@value #CHASE_BEAT_NEAR_TICKS} t apart) under {@value #CHASE_CLOSE_RANGE}.
 *       The heartbeat is non-positional (it is <i>yours</i>); the scrape is positional at
 *       the mob so it tells you which corridor it is coming down. When the pursuit ends
 *       the channel closes on ONE fading thud and resets — nothing keeps ticking.</li>
 *   <li><b>Light flicker</b>: a pursuer inside {@value #FLICKER_CHASE_RANGE} blocks (at
 *       most once per {@value #FLICKER_CHASE_COOLDOWN_TICKS} t), or a plain ambient roll
 *       every {@value #FLICKER_AMBIENT_MIN_TICKS}–{@value #FLICKER_AMBIENT_MAX_TICKS} t,
 *       sends {@code S2CBackroomsFlickerPayload} to the player and everyone within
 *       {@value #FLICKER_SHARE_RANGE} blocks. The flicker itself is drawn CLIENT-side
 *       ({@code client.backrooms.BackroomsFlickerOverlay}) — deliberately NOT a
 *       server-side blockstate sweep, which at this scale would be a per-tick relight
 *       storm. (The tiny hashed froglight↔glass swap of the faulty panels stays as it
 *       was; this is the big room-wide blackout pulse on top of it.)</li>
 *   <li><b>Far dread</b>: every {@value #FAR_SOUND_MIN_TICKS}–{@value #FAR_SOUND_MAX_TICKS}
 *       t one positional footstep/knock 14–26 blocks away in a random direction, sent to
 *       that one player only, so two players never hear the same "someone else is here".</li>
 * </ul>
 *
 * <p>Plus {@link #tickExitBeacon}: The Hollow (level 5) is a nearly lightless hall, so the
 * EXIT portal projects a directional hum toward each player standing on that level.</p>
 *
 * <p>All state is a transient per-UUID map cleared by {@link #reset()} (event start /
 * server stop) and {@link #forget(UUID)} (exit / logout), so nothing leaks across
 * instances and a relog starts silent.</p>
 */
public final class BackroomsDread {

    // ---------------------------------------------------------------- pursuit audio

    /** A pursuer beyond this is not "chasing" for audio purposes (= the 20 t aggro cap). */
    public static final double CHASE_RANGE = 20.0D;
    /** At or below this distance the pursuit audio is at full intensity. */
    public static final double CHASE_CLOSE_RANGE = 5.0D;
    /** Heartbeat spacing at intensity 0 (mob ~20 blocks out). */
    public static final int CHASE_BEAT_FAR_TICKS = 20;
    /** Heartbeat spacing at intensity 1 (mob inside 5 blocks). */
    public static final int CHASE_BEAT_NEAR_TICKS = 10;
    private static final float HEARTBEAT_VOLUME_MIN = 0.25F;
    private static final float HEARTBEAT_VOLUME_MAX = 1.0F;
    private static final float HEARTBEAT_PITCH_MIN = 0.55F;
    private static final float HEARTBEAT_PITCH_MAX = 0.9F;
    private static final float SCRAPE_VOLUME_MIN = 0.35F;
    private static final float SCRAPE_VOLUME_MAX = 1.0F;

    // ---------------------------------------------------------------- flicker

    /** A pursuer closer than this trips the blackout flicker. */
    public static final double FLICKER_CHASE_RANGE = 12.0D;
    /** Never more than one chase-triggered flicker per player per 25 s. */
    public static final int FLICKER_CHASE_COOLDOWN_TICKS = 500;
    /** Ambient flicker cadence: 30 s … 90 s. */
    public static final int FLICKER_AMBIENT_MIN_TICKS = 600;
    public static final int FLICKER_AMBIENT_MAX_TICKS = 1800;
    /** Everyone this close to the trigger sees the same blackout (shared room, shared dark). */
    public static final double FLICKER_SHARE_RANGE = 16.0D;
    /** Envelope length sent to the client: 2 s … 4 s. */
    public static final int FLICKER_MIN_DURATION_TICKS = 40;
    public static final int FLICKER_MAX_DURATION_TICKS = 80;
    private static final float FLICKER_INTENSITY_CHASE = 1.0F;
    private static final float FLICKER_INTENSITY_AMBIENT = 0.65F;

    // ---------------------------------------------------------------- far dread

    /** Distant footstep/knock cadence: 2 min … 4 min per player. */
    public static final int FAR_SOUND_MIN_TICKS = 2400;
    public static final int FAR_SOUND_MAX_TICKS = 4800;
    private static final double FAR_SOUND_MIN_DISTANCE = 14.0D;
    private static final double FAR_SOUND_MAX_DISTANCE = 26.0D;

    // ---------------------------------------------------------------- exit beacon

    /** The Hollow exit hum cadence + the range within which it is audible at all. */
    public static final int EXIT_BEACON_INTERVAL_TICKS = 60;
    public static final double EXIT_BEACON_RANGE = 128.0D;
    /** The hum is projected onto a sphere this close so direction survives the distance. */
    private static final double EXIT_BEACON_PROJECTION = 12.0D;

    /** Per-player transient dread bookkeeping (never persisted — a relog starts silent). */
    private static final Map<UUID, Dread> TRACKS = new HashMap<>();

    private BackroomsDread() {}

    /** Clears every channel (event start / server stop). */
    public static void reset() {
        TRACKS.clear();
    }

    /** Drops one player's channels (exit to the altar, death, logout). */
    public static void forget(UUID uuid) {
        TRACKS.remove(uuid);
    }

    /**
     * One pass over every player inside the dimension; called every 10 t while OPEN.
     * Each channel gates itself on its own next-fire game tick, so the pass is O(players)
     * with a bounded entity query and usually fires nothing at all.
     */
    public static void tick(ServerLevel level) {
        List<ServerPlayer> players = level.players();
        if (players.isEmpty()) {
            if (!TRACKS.isEmpty()) {
                TRACKS.clear();
            }
            return;
        }
        long gameTime = level.getGameTime();
        Set<UUID> present = new HashSet<>(players.size());
        for (ServerPlayer player : List.copyOf(players)) {
            present.add(player.getUUID());
            if (player.isSpectator() || !player.isAlive()) {
                continue;
            }
            Dread dread = TRACKS.computeIfAbsent(player.getUUID(),
                    uuid -> newDread(level.getRandom(), gameTime));
            announceDescent(player, dread);
            Mob hunter = findHunter(level, player);
            if (hunter != null) {
                tickPursuit(level, player, dread, hunter, gameTime);
            } else if (dread.chasing) {
                endPursuit(player, dread);
            }
            if (gameTime >= dread.nextAmbientFlickerTick) {
                triggerFlicker(level, player, gameTime, FLICKER_INTENSITY_AMBIENT);
            }
            if (gameTime >= dread.nextFarSoundTick) {
                playFarDread(level, player);
                dread.nextFarSoundTick = gameTime + roll(level.getRandom(),
                        FAR_SOUND_MIN_TICKS, FAR_SOUND_MAX_TICKS);
            }
        }
        TRACKS.keySet().retainAll(present); // players who left the dimension go quiet
    }

    private static Dread newDread(RandomSource random, long gameTime) {
        Dread dread = new Dread();
        dread.nextAmbientFlickerTick = gameTime
                + roll(random, FLICKER_AMBIENT_MIN_TICKS, FLICKER_AMBIENT_MAX_TICKS);
        dread.nextFarSoundTick = gameTime + roll(random, FAR_SOUND_MIN_TICKS, FAR_SOUND_MAX_TICKS);
        dread.lastFlickerTick = Long.MIN_VALUE / 2L;
        return dread;
    }

    // ================================================================== descent captions

    /**
     * The two F-043 levels name themselves the first time you drop into them — one
     * whisper caption, no chat (user decree). Deepest-seen is transient by design: this
     * is a "where am I" cue, not a persisted milestone.
     */
    private static void announceDescent(ServerPlayer player, Dread dread) {
        int level = BackroomsLayers.layerOf(player.getBlockY()).level();
        if (level <= dread.deepestLevelSeen) {
            return;
        }
        dread.deepestLevelSeen = level;
        String key = switch (level) {
            case 4 -> "eclipse.backrooms.caption.flooded";
            case 5 -> "eclipse.backrooms.caption.hollow";
            default -> null;
        };
        if (key != null) {
            PacketDistributor.sendToPlayer(player,
                    new S2CCaptionPayload(key, 80, S2CCaptionPayload.STYLE_WHISPER));
        }
    }

    // ================================================================== pursuit

    /**
     * The nearest mob inside {@value #CHASE_RANGE} blocks that is actually coming for
     * THIS player — a combat target, or the Wanderer's paced victim (its stalk state is
     * the pursuit long before it ever sets a target).
     */
    @Nullable
    private static Mob findHunter(ServerLevel level, ServerPlayer player) {
        AABB box = player.getBoundingBox().inflate(CHASE_RANGE);
        Mob best = null;
        double bestSqr = CHASE_RANGE * CHASE_RANGE;
        for (Mob mob : level.getEntitiesOfClass(Mob.class, box, Mob::isAlive)) {
            if (!isHunting(mob, player)) {
                continue;
            }
            double sqr = mob.distanceToSqr(player);
            if (sqr < bestSqr) {
                bestSqr = sqr;
                best = mob;
            }
        }
        return best;
    }

    private static boolean isHunting(Mob mob, ServerPlayer player) {
        if (mob.getTarget() == player) {
            return true;
        }
        return mob instanceof GlitchedWandererEntity wanderer && wanderer.pacedPlayer() == player;
    }

    private static void tickPursuit(ServerLevel level, ServerPlayer player, Dread dread,
            Mob hunter, long gameTime) {
        double distance = Math.sqrt(hunter.distanceToSqr(player));
        float intensity = (float) Mth.clamp(
                (CHASE_RANGE - distance) / (CHASE_RANGE - CHASE_CLOSE_RANGE), 0.0D, 1.0D);

        if (!dread.chasing) {
            dread.chasing = true;
            dread.beat = 0;
            dread.nextBeatTick = gameTime; // the first thud lands the moment it notices you
        }
        if (gameTime >= dread.nextBeatTick) {
            player.playNotifySound(SoundEvents.WARDEN_HEARTBEAT, SoundSource.HOSTILE,
                    Mth.lerp(intensity, HEARTBEAT_VOLUME_MIN, HEARTBEAT_VOLUME_MAX),
                    Mth.lerp(intensity, HEARTBEAT_PITCH_MIN, HEARTBEAT_PITCH_MAX));
            // Close in: every beat drags a scrape with it. Far out: every other one.
            if (intensity > 0.5F || (dread.beat & 1) == 0) {
                SoundEvent scrape = (dread.beat & 2) == 0
                        ? SoundEvents.ZOMBIE_STEP : SoundEvents.STONE_HIT;
                sendPositional(level, player, scrape, SoundSource.HOSTILE,
                        hunter.getX(), hunter.getY() + 0.5D, hunter.getZ(),
                        Mth.lerp(intensity, SCRAPE_VOLUME_MIN, SCRAPE_VOLUME_MAX),
                        Mth.lerp(intensity, 0.45F, 0.75F));
            }
            dread.beat++;
            dread.nextBeatTick = gameTime + Math.round(
                    Mth.lerp(intensity, CHASE_BEAT_FAR_TICKS, CHASE_BEAT_NEAR_TICKS));
        }
        if (distance <= FLICKER_CHASE_RANGE
                && gameTime - dread.lastFlickerTick >= FLICKER_CHASE_COOLDOWN_TICKS) {
            triggerFlicker(level, player, gameTime, FLICKER_INTENSITY_CHASE);
        }
    }

    /** Clean close: one fading thud, then the channel is silent until the next pursuit. */
    private static void endPursuit(ServerPlayer player, Dread dread) {
        dread.chasing = false;
        dread.beat = 0;
        dread.nextBeatTick = 0L;
        player.playNotifySound(SoundEvents.WARDEN_HEARTBEAT, SoundSource.HOSTILE, 0.2F, 0.5F);
    }

    // ================================================================== flicker

    /**
     * Fires the client-side blackout pulse for {@code origin} and everyone within
     * {@value #FLICKER_SHARE_RANGE} blocks, and re-arms all of their ambient timers so a
     * shared blackout does not immediately chain into a private one.
     */
    public static void triggerFlicker(ServerLevel level, ServerPlayer origin, long gameTime,
            float intensity) {
        RandomSource random = level.getRandom();
        int duration = roll(random, FLICKER_MIN_DURATION_TICKS, FLICKER_MAX_DURATION_TICKS);
        long pattern = random.nextLong();
        double shareSqr = FLICKER_SHARE_RANGE * FLICKER_SHARE_RANGE;
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (player != origin && player.distanceToSqr(origin) > shareSqr) {
                continue;
            }
            Dread dread = TRACKS.get(player.getUUID());
            if (dread != null) {
                dread.lastFlickerTick = gameTime;
                dread.nextAmbientFlickerTick = gameTime
                        + roll(random, FLICKER_AMBIENT_MIN_TICKS, FLICKER_AMBIENT_MAX_TICKS);
            }
            BackroomsPayloads.sendFlicker(player, duration, intensity, pattern);
        }
    }

    /** {@code /dev backrooms flicker} backing — one pulse on the caller, no cooldown book. */
    public static void debugFlicker(ServerLevel level, ServerPlayer player) {
        triggerFlicker(level, player, level.getGameTime(), FLICKER_INTENSITY_CHASE);
    }

    // ================================================================== far dread

    /** One footstep/knock from a random bearing 14–26 blocks out, for this player alone. */
    private static void playFarDread(ServerLevel level, ServerPlayer player) {
        RandomSource random = level.getRandom();
        double angle = random.nextDouble() * Math.PI * 2.0D;
        double distance = FAR_SOUND_MIN_DISTANCE
                + random.nextDouble() * (FAR_SOUND_MAX_DISTANCE - FAR_SOUND_MIN_DISTANCE);
        double x = player.getX() + Math.cos(angle) * distance;
        double z = player.getZ() + Math.sin(angle) * distance;
        SoundEvent sound = switch (random.nextInt(3)) {
            case 0 -> SoundEvents.ZOMBIE_STEP;
            case 1 -> SoundEvents.WOOD_HIT;
            default -> SoundEvents.WOODEN_DOOR_CLOSE;
        };
        sendPositional(level, player, sound, SoundSource.AMBIENT,
                x, player.getY(), z, 0.7F, 0.5F + random.nextFloat() * 0.2F);
    }

    // ================================================================== exit beacon

    /**
     * The Hollow is nearly lightless, so the EXIT portal has to be findable by EAR: every
     * {@value #EXIT_BEACON_INTERVAL_TICKS} t each player standing on level 5 gets a low
     * hum projected from the portal's bearing (the {@code EclipseSpawner.howlAround}
     * projection trick — direction survives even at 100 blocks).
     */
    public static void tickExitBeacon(ServerLevel level, BlockPos exitPos, long gameTime) {
        Vec3 center = Vec3.atBottomCenterOf(exitPos);
        for (ServerPlayer player : List.copyOf(level.players())) {
            Dread dread = TRACKS.get(player.getUUID());
            if (dread == null || gameTime < dread.nextBeaconTick) {
                continue;
            }
            dread.nextBeaconTick = gameTime + EXIT_BEACON_INTERVAL_TICKS;
            if (BackroomsLayers.layerOf(player.getBlockY()) != BackroomsLayers.Layer.THE_HOLLOW) {
                continue;
            }
            double distance = player.position().distanceTo(center);
            if (distance > EXIT_BEACON_RANGE) {
                continue;
            }
            Vec3 at = distance < 1.0E-4D ? center : player.position().add(
                    center.subtract(player.position()).normalize()
                            .scale(Math.min(distance, EXIT_BEACON_PROJECTION)));
            sendPositional(level, player, EclipseSounds.EVENT_BEAM_HUM.get(), SoundSource.AMBIENT,
                    at.x, at.y, at.z, 0.8F, 0.45F);
        }
    }

    // ================================================================== helpers

    /** Positional one-shot delivered to EXACTLY one player (never {@code level.playSound}). */
    private static void sendPositional(ServerLevel level, ServerPlayer player, SoundEvent sound,
            SoundSource source, double x, double y, double z, float volume, float pitch) {
        Holder<SoundEvent> holder = BuiltInRegistries.SOUND_EVENT.wrapAsHolder(sound);
        player.connection.send(new ClientboundSoundPacket(holder, source, x, y, z,
                volume, pitch, level.getRandom().nextLong()));
    }

    private static int roll(RandomSource random, int min, int max) {
        return min + random.nextInt(Math.max(1, max - min + 1));
    }

    /** Mutable per-player channel state; game-tick stamps, never wall clock. */
    private static final class Dread {
        private long nextBeatTick;
        private long nextAmbientFlickerTick;
        private long nextFarSoundTick;
        private long nextBeaconTick;
        private long lastFlickerTick;
        private int beat;
        private int deepestLevelSeen;
        private boolean chasing;
    }
}
