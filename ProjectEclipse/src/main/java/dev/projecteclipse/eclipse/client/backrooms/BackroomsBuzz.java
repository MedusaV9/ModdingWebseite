package dev.projecteclipse.eclipse.client.backrooms;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsDimension;
import dev.projecteclipse.eclipse.backrooms.GlitchedWandererEntity;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.ai.targeting.TargetingConditions;
import net.minecraft.world.level.LightLayer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * The fluorescent mains-buzz bed of the Backrooms (IDEAS-backrooms_finale §A2/§A6) —
 * ONE non-positional client loop, alive only while the local player stands in
 * {@code eclipse:backrooms}. The {@code SanctumHum} skeleton (per-tick target volume,
 * lerped instance, silent-stop, logout teardown, one-play-per-visit guard).
 *
 * <p><b>Sound</b>: the W4-ATMOS-style alias {@code eclipse:ambient.backrooms_buzz}
 * (sounds.json points it at the shipped {@code gazer_whisper} bed pitched
 * {@value #BUZZ_PITCH} — the "alias-pitched existing hum at 0.55" of the C18 spec);
 * while the registry entry is missing the loop self-heals onto
 * {@code EclipseSounds.EVENT_BEAM_HUM} re-pitched to the same note.</p>
 *
 * <p><b>Dip on flicker</b> (§A2): the flicker is REAL light — the server swaps
 * {@code ochre_froglight ↔ yellow_stained_glass} — so the buzz keys its dip off the
 * measured BLOCK light at the player's eye: when the panel over you goes dark the local
 * light level drops and the buzz sags with it ({@value #DARK_VOLUME_SHARE} floor). Zero
 * protocol, perfectly synchronized with what the player sees, and it also reads
 * correctly in the never-lit sealed pockets.</p>
 *
 * <p><b>Hush-when-stalked</b> (§A6.4 dread grammar): a visible-tracked
 * {@link GlitchedWandererEntity} within {@value #HUSH_RANGE} blocks pulls the target
 * volume toward {@value #HUSH_VOLUME_SHARE} — the room goes quiet around the thing, the
 * inverse tell of the husk's static burst.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BackroomsBuzz {
    /** The alias id registered by {@code BackroomsEntities} + shipped in sounds.json. */
    private static final ResourceLocation BUZZ_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.backrooms_buzz");
    /** The C18 alias note: the existing hum bed pitched to the mains-buzz register. */
    private static final float BUZZ_PITCH = 0.55F;
    private static final float BASE_VOLUME = 0.5F;

    /** Volume share under a fully dark ceiling (flicker dip floor). */
    private static final float DARK_VOLUME_SHARE = 0.3F;
    /** Block light level that counts as "fully lit" (froglight panel overhead). */
    private static final float FULL_LIGHT = 12.0F;

    private static final double HUSH_RANGE = 12.0D;
    private static final float HUSH_VOLUME_SHARE = 0.15F;

    private static final int SILENT_STOP_TICKS = 100;

    /** Per-tick volume target, written by the ticker, read by the instance. */
    private static float targetVolume;
    @Nullable
    private static BuzzSound buzzSound;
    /** One play(...) attempt per dimension visit (the SanctumHum guard). */
    private static boolean soundStartedThisVisit;

    private BackroomsBuzz() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null || !BackroomsDimension.isBackrooms(level.dimension())) {
            targetVolume = 0.0F;
            soundStartedThisVisit = false;
            return;
        }

        // Flicker dip: measured block light at the eye — dark window == sagging buzz.
        BlockPos eye = BlockPos.containing(player.getEyePosition());
        float light = level.getBrightness(LightLayer.BLOCK, eye);
        float lit = Mth.clamp(light / FULL_LIGHT, 0.0F, 1.0F);
        float volume = BASE_VOLUME * (DARK_VOLUME_SHARE + (1.0F - DARK_VOLUME_SHARE) * lit);

        // Hush-when-stalked: the closer a Wanderer, the quieter the room.
        GlitchedWandererEntity stalker = level.getNearestEntity(GlitchedWandererEntity.class,
                TargetingConditions.forNonCombat()
                        .ignoreLineOfSight().ignoreInvisibilityTesting().range(HUSH_RANGE),
                player, player.getX(), player.getY(), player.getZ(),
                player.getBoundingBox().inflate(HUSH_RANGE));
        if (stalker != null) {
            float proximity = 1.0F - (float) Mth.clamp(
                    Math.sqrt(stalker.distanceToSqr(player)) / HUSH_RANGE, 0.0D, 1.0D);
            volume = Mth.lerp(proximity, volume, BASE_VOLUME * HUSH_VOLUME_SHARE);
        }
        targetVolume = volume;

        BuzzSound sound = buzzSound;
        if (sound == null || sound.isStopped()) {
            if (!soundStartedThisVisit) {
                soundStartedThisVisit = true;
                sound = new BuzzSound();
                buzzSound = sound;
                minecraft.getSoundManager().play(sound);
            }
        }
    }

    /** Disconnect reset (the SanctumHum {@code LoggingOut} teardown). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        BuzzSound sound = buzzSound;
        if (sound != null) {
            sound.forceStop();
            buzzSound = null;
        }
        soundStartedThisVisit = false;
        targetVolume = 0.0F;
    }

    /** Registered {@code ambient.backrooms_buzz} or the pitched beam-hum fallback. */
    private static SoundEvent resolveBuzz() {
        return BuiltInRegistries.SOUND_EVENT.getOptional(BUZZ_ID)
                .orElseGet(EclipseSounds.EVENT_BEAM_HUM);
    }

    /**
     * The non-positional loop. Volume chases {@link #targetVolume} with a small per-tick
     * step (flicker dips read as a sag, not a click); stops itself after
     * {@value #SILENT_STOP_TICKS} silent ticks (left the dimension) so no idle instance
     * lingers.
     */
    private static final class BuzzSound extends AbstractTickableSoundInstance {
        private static final float VOLUME_STEP = 0.06F;

        private int silentTicks;

        private BuzzSound() {
            super(resolveBuzz(), SoundSource.AMBIENT, SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = true; // glued to the listener's head: the room hums everywhere
            this.x = 0.0D;
            this.y = 0.0D;
            this.z = 0.0D;
            // The alias sounds.json already carries pitch 0.55; the raw fallback needs it here.
            this.pitch = BuiltInRegistries.SOUND_EVENT.containsKey(BUZZ_ID) ? 1.0F : BUZZ_PITCH;
        }

        @Override
        public void tick() {
            float target = targetVolume;
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
