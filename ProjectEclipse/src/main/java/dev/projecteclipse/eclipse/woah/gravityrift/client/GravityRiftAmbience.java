package dev.projecteclipse.eclipse.woah.gravityrift.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftCues;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-02 client ambience manager (plan §4.2): the two WINDOWED Photon loops (the
 * hysteresis attach/release law of {@code StormNearfieldFx}/{@code SanctumLightfall})
 * and the positional rift drone.
 *
 * <ul>
 *   <li><b>Light column</b> ({@link GravityRiftCues#CUE_GRAVITY_COLUMN}) — the
 *       90-block far-field beacon; attach ≤ {@value #COLUMN_ATTACH}, release &gt;
 *       {@value #COLUMN_RELEASE} blocks.</li>
 *   <li><b>Core motes</b> ({@link GravityRiftCues#CUE_GRAVITY_MOTES}) — near-field
 *       "dust falls upward"; attach ≤ {@value #MOTES_ATTACH}, release &gt;
 *       {@value #MOTES_RELEASE}.</li>
 *   <li><b>Drone</b> — one positional loop at the heart (the {@code SanctumHum}
 *       instance recipe): volume ramps over the approach, pitch bends up while an
 *       inversion runs. Resolves the ledger id {@code eclipse:ambient.gravity_hum}
 *       when present, else falls back to the shipped {@code event.rift_drone}
 *       re-pitched (the UiSounds self-healing pattern — see
 *       {@code docs/plans_v3/wiring/woah_gravity_sounds.json}).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GravityRiftAmbience {
    /** Ledger id of the intended dedicated hum bed (sounds.json ask pending). */
    private static final ResourceLocation HUM_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.gravity_hum");
    /** Fallback re-pitch of {@code event.rift_drone} while the alias ask is pending. */
    private static final float FALLBACK_PITCH = 0.75F;

    /** Column loop window (the far-field hook — visible long before the crater). */
    private static final double COLUMN_ATTACH = 150.0D;
    private static final double COLUMN_RELEASE = 170.0D;
    /** Motes loop window (near-field bowl read). */
    private static final double MOTES_ATTACH = 52.0D;
    private static final double MOTES_RELEASE = 64.0D;

    /** Drone volume: full at ≤ {@value #DRONE_FULL}, silent at {@value #DRONE_SILENT}. */
    private static final double DRONE_FULL = 14.0D;
    private static final double DRONE_SILENT = 64.0D;
    /** Drone engages under this distance; below-threshold re-arms the visit guard. */
    private static final float START_THRESHOLD = 0.02F;
    /** Max upward pitch bend at full inversion. */
    private static final float INVERT_PITCH_BEND = 0.35F;

    private static boolean columnLive;
    private static boolean motesLive;

    /** Per-tick drone targets, written by the ticker, read by the instance. */
    private static float targetVolume;
    private static float targetPitchBend;
    @Nullable
    private static DroneSound droneSound;
    /** One play(...) attempt per zone visit (the LimboAmbience guard). */
    private static boolean soundStartedThisVisit;

    private GravityRiftAmbience() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        Vec3 heart = GravityRiftClientState.heartCenter();
        if (minecraft.level == null || heart == null) {
            releaseAll();
            targetVolume = 0.0F;
            soundStartedThisVisit = false;
            return;
        }
        double distance = GravityRiftClientState.cameraDistance();

        // --- windowed Photon loops (hysteresis: attach < release, never flapping) ---
        if (!columnLive && distance <= COLUMN_ATTACH) {
            columnLive = PhotonFxRegistry.ensureLoop(GravityRiftCues.CUE_GRAVITY_COLUMN, heart);
        } else if (columnLive && distance > COLUMN_RELEASE) {
            PhotonFxRegistry.releaseLoop(GravityRiftCues.CUE_GRAVITY_COLUMN, true);
            columnLive = false;
        }
        if (!motesLive && distance <= MOTES_ATTACH) {
            motesLive = PhotonFxRegistry.ensureLoop(GravityRiftCues.CUE_GRAVITY_MOTES, heart);
        } else if (motesLive && distance > MOTES_RELEASE) {
            PhotonFxRegistry.releaseLoop(GravityRiftCues.CUE_GRAVITY_MOTES, true);
            motesLive = false;
        }

        // --- the positional drone -------------------------------------------------
        targetVolume = (float) Mth.clamp(
                (DRONE_SILENT - distance) / (DRONE_SILENT - DRONE_FULL), 0.0D, 1.0D);
        targetPitchBend = GravityRiftClientState.invertAmount() * INVERT_PITCH_BEND;
        if (targetVolume <= START_THRESHOLD) {
            soundStartedThisVisit = false;
            return;
        }
        DroneSound sound = droneSound;
        if (sound == null || sound.isStopped()) {
            if (!soundStartedThisVisit) {
                soundStartedThisVisit = true;
                sound = new DroneSound(heart);
                droneSound = sound;
                minecraft.getSoundManager().play(sound);
            }
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        releaseAll();
        DroneSound sound = droneSound;
        if (sound != null) {
            sound.forceStop();
            droneSound = null;
        }
        soundStartedThisVisit = false;
        targetVolume = 0.0F;
        targetPitchBend = 0.0F;
    }

    private static void releaseAll() {
        if (columnLive) {
            PhotonFxRegistry.releaseLoop(GravityRiftCues.CUE_GRAVITY_COLUMN, false);
            columnLive = false;
        }
        if (motesLive) {
            PhotonFxRegistry.releaseLoop(GravityRiftCues.CUE_GRAVITY_MOTES, false);
            motesLive = false;
        }
    }

    /** Registered {@code ambient.gravity_hum} or the re-pitched rift-drone fallback. */
    private static SoundEvent resolveHum() {
        return BuiltInRegistries.SOUND_EVENT.getOptional(HUM_ID)
                .orElseGet(EclipseSounds.EVENT_RIFT_DRONE);
    }

    /**
     * The positional drone loop ({@code SanctumHum.HumSound} recipe): volume chases the
     * ticker's target, pitch bends up while an inversion runs, and the instance stops
     * itself after {@value #SILENT_STOP_TICKS} silent ticks.
     */
    private static final class DroneSound extends AbstractTickableSoundInstance {
        private static final float VOLUME_STEP = 0.05F;
        private static final int SILENT_STOP_TICKS = 60;

        private final float basePitch;
        private int silentTicks;

        private DroneSound(Vec3 heart) {
            super(resolveHum(), SoundSource.AMBIENT, SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = false;
            this.basePitch = BuiltInRegistries.SOUND_EVENT.containsKey(HUM_ID)
                    ? 1.0F : FALLBACK_PITCH;
            this.pitch = this.basePitch;
            this.x = heart.x;
            this.y = heart.y;
            this.z = heart.z;
        }

        @Override
        public void tick() {
            float target = targetVolume;
            if (this.volume < target) {
                this.volume = Math.min(target, this.volume + VOLUME_STEP);
            } else if (this.volume > target) {
                this.volume = Math.max(target, this.volume - VOLUME_STEP);
            }
            this.pitch = this.basePitch + targetPitchBend;
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
