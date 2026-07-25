package dev.projecteclipse.eclipse.client.drama;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsDimension;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import dev.projecteclipse.eclipse.ferryman.ArenaDimension;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.ai.targeting.TargetingConditions;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * V7-SIGCOMP C10 — DEEP RUMBLE, the sub-visual subterranean dread bed
 * (FX-STYLE-GUIDE.md §5 C10): ceiling dust motes + pebble hops (the windowed
 * {@code CUE_SIG_DEEP_RUMBLE} loop row), a low rumble sound bed (the composition IS this
 * sound; visuals garnish it) and a ~1% frame "breathing" via the existing camera shake at
 * ultra-low amplitude. B-class: it never claims the {@code WorldStageArbiter} token and
 * deliberately fails the "did you see it?" test — players should <i>feel</i> it.
 *
 * <p><b>Windows</b> (hysteresis, client-computable truth only):</p>
 * <ul>
 *   <li><b>Tyrant lair</b> — a living {@link FogTyrantEntity} within
 *       {@value #TYRANT_ENGAGE_RANGE} blocks (release beyond {@value #TYRANT_RELEASE_RANGE};
 *       the boss entity is the lair's anchor truth).</li>
 *   <li><b>Ferry arena</b> — the local player stands in {@code eclipse:ferry_arena}.</li>
 *   <li><b>Backrooms</b> — the local player stands in {@code eclipse:backrooms}.</li>
 * </ul>
 *
 * <p><b>Reduced ladder</b> (§6.7, C10 is the tier-0 reference): tier 2 = dust + pebbles +
 * thud singles + breathing + rumble; tier 1 = the loop row's Quasar stand-in (Photon dies
 * inside the bridge, AMBIENT rates halve automatically) + rumble — no pebble thuds, no
 * breathing; tier 0 = rumble sound ONLY (AMBIENT is off; the warning stays functional).
 * The loop anchor is the player, re-anchored by release + re-ensure after
 * {@value #REANCHOR_DISTANCE} blocks of travel (loops cannot be moved — registry law).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DeepRumbleFx {
    /** Tyrant-lair window hysteresis band (blocks to a living Fog Tyrant). */
    private static final double TYRANT_ENGAGE_RANGE = 36.0D;
    private static final double TYRANT_RELEASE_RANGE = 44.0D;
    /** Loop re-anchor travel threshold (release + re-ensure; loops cannot be moved). */
    private static final double REANCHOR_DISTANCE = 8.0D;
    /** Rumble bed target volume while a window is open (a bed, ducked by design). */
    private static final float RUMBLE_VOLUME = 0.34F;
    /** The end-shatter rumble pitched into the sub register. */
    private static final float RUMBLE_PITCH = 0.5F;
    /** Pebble-hop thud singles: random cadence window in ticks (tier 2 only). */
    private static final int THUD_MIN_INTERVAL = 24;
    private static final int THUD_MAX_INTERVAL = 44;
    /** Frame breathing: one ultra-low shake impulse per cycle (~1% amplitude, tier 2). */
    private static final int BREATH_INTERVAL_TICKS = 45;
    private static final float BREATH_STRENGTH = 0.012F;
    private static final int BREATH_TICKS = 40;
    private static final float BREATH_FREQ = 0.3F;
    private static final int SILENT_STOP_TICKS = 100;

    // Client tick thread only.
    private static boolean windowOpen;
    private static float targetVolume;
    @Nullable
    private static Vec3 loopAnchor;
    private static int thudCountdown;
    private static int breathCountdown;
    @Nullable
    private static RumbleSound rumbleSound;

    private DeepRumbleFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        boolean inWindow = windowCondition(level, player);
        // Hysteresis is carried by the tyrant band; the dimension windows are binary.
        windowOpen = inWindow;
        if (!windowOpen) {
            targetVolume = 0.0F;
            releaseLoop(true);
            return;
        }
        targetVolume = RUMBLE_VOLUME;
        ensureRumbleSound(minecraft);

        int tier = FxBudget.qualityTier();
        if (tier <= 0) {
            releaseLoop(true); // tier 0: the bed is sound-only (AMBIENT is off anyway)
        } else {
            Vec3 playerPos = player.position();
            if (loopAnchor != null && loopAnchor.distanceToSqr(playerPos)
                    > REANCHOR_DISTANCE * REANCHOR_DISTANCE) {
                releaseLoop(true); // re-anchor: release now, re-ensure below
            }
            if (loopAnchor == null) {
                loopAnchor = playerPos;
            }
            PhotonFxRegistry.ensureLoop(FxCues.CUE_SIG_DEEP_RUMBLE, loopAnchor);
        }

        // Tier-2 garnish: pebble-hop thud singles + the 1% frame breathing.
        if (tier >= 2) {
            if (--thudCountdown <= 0) {
                thudCountdown = THUD_MIN_INTERVAL
                        + level.random.nextInt(THUD_MAX_INTERVAL - THUD_MIN_INTERVAL + 1);
                Vec3 at = player.position().add(
                        (level.random.nextDouble() - 0.5D) * 6.0D, -0.5D,
                        (level.random.nextDouble() - 0.5D) * 6.0D);
                level.playLocalSound(at.x, at.y, at.z, EclipseSounds.EVENT_RIFT_THUD.get(),
                        SoundSource.AMBIENT, 0.22F,
                        0.62F + level.random.nextFloat() * 0.16F, false);
            }
            if (--breathCountdown <= 0) {
                breathCountdown = BREATH_INTERVAL_TICKS;
                CameraDirector.addShakeImpulse(BREATH_STRENGTH, BREATH_TICKS, BREATH_FREQ);
            }
        }
    }

    /** The three C10 windows: tyrant lair proximity, ferry arena, backrooms. */
    private static boolean windowCondition(ClientLevel level, LocalPlayer player) {
        if (BackroomsDimension.isBackrooms(level.dimension())
                || ArenaDimension.isArena(level.dimension())) {
            return true;
        }
        double range = windowOpen ? TYRANT_RELEASE_RANGE : TYRANT_ENGAGE_RANGE;
        FogTyrantEntity tyrant = level.getNearestEntity(FogTyrantEntity.class,
                TargetingConditions.forNonCombat()
                        .ignoreLineOfSight().ignoreInvisibilityTesting().range(range),
                player, player.getX(), player.getY(), player.getZ(),
                player.getBoundingBox().inflate(range));
        return tyrant != null && tyrant.isAlive();
    }

    private static void ensureRumbleSound(Minecraft minecraft) {
        RumbleSound sound = rumbleSound;
        if (sound == null || sound.isStopped()) {
            sound = new RumbleSound();
            rumbleSound = sound;
            minecraft.getSoundManager().play(sound);
        }
    }

    private static void releaseLoop(boolean graceful) {
        if (loopAnchor != null) {
            PhotonFxRegistry.releaseLoop(FxCues.CUE_SIG_DEEP_RUMBLE, graceful);
            loopAnchor = null;
        }
    }

    private static void reset() {
        windowOpen = false;
        targetVolume = 0.0F;
        releaseLoop(false);
        thudCountdown = 0;
        breathCountdown = 0;
    }

    /** Disconnect reset (the BackroomsBuzz {@code LoggingOut} teardown). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        RumbleSound sound = rumbleSound;
        if (sound != null) {
            sound.forceStop();
            rumbleSound = null;
        }
        reset();
    }

    /**
     * The non-positional rumble bed (the BackroomsBuzz skeleton): volume chases
     * {@link #targetVolume} with a small per-tick step so window edges read as a swell,
     * not a click; stops itself after {@value #SILENT_STOP_TICKS} silent ticks.
     */
    private static final class RumbleSound extends AbstractTickableSoundInstance {
        private static final float VOLUME_STEP = 0.02F;

        private int silentTicks;

        private RumbleSound() {
            super(EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(), SoundSource.AMBIENT,
                    SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = true; // the ground itself hums — glued to the listener
            this.x = 0.0D;
            this.y = 0.0D;
            this.z = 0.0D;
            this.pitch = RUMBLE_PITCH;
        }

        @Override
        public void tick() {
            float target = Mth.clamp(targetVolume, 0.0F, 1.0F);
            if (this.volume < target) {
                this.volume = Math.min(target, this.volume + VOLUME_STEP);
            } else if (this.volume > target) {
                this.volume = Math.max(target, this.volume - VOLUME_STEP);
            }
            if (this.volume <= 0.005F) {
                if (++this.silentTicks >= SILENT_STOP_TICKS) {
                    this.stop();
                }
            } else {
                this.silentTicks = 0;
            }
        }

        void forceStop() {
            this.stop();
        }
    }
}
