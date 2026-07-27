package dev.projecteclipse.eclipse.woah.chronostasis.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-03 clock tick (plan §4.6): the near-silence of the zone carries a single deep
 * clock beat whose period STRETCHES toward the center — 1.7 s at the rim, 3 s at the
 * Chronosphere (time itself gets more viscous). Pure client logic off
 * {@link ChronoZoneState}; nothing is synced.
 *
 * <p>Sound recipe (plan §6, no new OGG assets — layered live from existing events; the
 * intended {@code event.chrono_tick} sounds.json row is documented in
 * {@code docs/plans_v3/wiring/woah_chrono_sounds.json}): vanilla {@code note_block.bass}
 * at pitch ~0.5 for the dull strike + {@code eclipse:event/submerge} at pitch 1.8, low
 * volume, for the deep body. "Muffled, almost mute" is staged, not filtered: the rain
 * mixin removes ambient rain sounds, this beat is nearly the only source left, and the
 * pitch sinks toward the center ({@code LastMinuteHush} precedent for silence-as-drama).
 * The beat pauses for the JOLT window (the woom replaces it) and mutes entirely during
 * DISCHARGE/REWIND.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ChronoTickSound {
    /** Beat period at the rim (ticks). */
    private static final float PERIOD_EDGE = 34.0F;
    /** Beat period at the center (ticks) — slower near the sphere. */
    private static final float PERIOD_CENTER = 60.0F;
    /** Audible above this eased amount. */
    private static final float MIN_AMOUNT = 0.05F;

    private static float countdown;

    private ChronoTickSound() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || minecraft.isPaused()) {
            return;
        }
        float amount = ChronoZoneState.amount();
        if (amount <= MIN_AMOUNT || ChronoZoneState.dischargeActive()) {
            countdown = 0.0F; // re-arm at the rim; mute through discharge/rewind
            return;
        }
        if (ChronoZoneState.joltActive()) {
            return; // the woom replaces the beat; countdown resumes where it paused
        }
        if (countdown > 0.0F) {
            countdown--;
            return;
        }
        // distanceRatio: 0 at the center, 1 at the rim → slower toward the center.
        countdown = Mth.lerp(ChronoZoneState.distanceRatio(), PERIOD_CENTER, PERIOD_EDGE);
        Vec3 anchor = ChronoZoneState.anchorPos();
        if (anchor == null) {
            return;
        }
        float volume = 0.4F + 0.5F * amount;
        float pitch = 0.9F - 0.25F * amount;
        level.playLocalSound(anchor.x, anchor.y, anchor.z,
                SoundEvents.NOTE_BLOCK_BASS.value(), SoundSource.AMBIENT,
                volume * 0.9F, pitch * 0.55F, false);
        level.playLocalSound(anchor.x, anchor.y, anchor.z,
                EclipseSounds.EVENT_SUBMERGE.get(), SoundSource.AMBIENT,
                volume * 0.25F, 1.8F, false);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        countdown = 0.0F;
    }
}
