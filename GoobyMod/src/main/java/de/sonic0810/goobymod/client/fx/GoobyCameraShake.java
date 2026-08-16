package de.sonic0810.goobymod.client.fx;

import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ViewportEvent;

/**
 * Gentle camera shake while an own tamed Gooby is in a real alarm state.
 * The trigger, cooldown and distance falloff live in {@link GoobyClientFx};
 * this handler only maps the decaying envelope onto small camera angle
 * offsets. Fully disabled by the cameraShake switch and by reducedMotion.
 */
@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class GoobyCameraShake {
    private static final float MAX_YAW_DEGREES = 0.55F;
    private static final float MAX_PITCH_DEGREES = 0.45F;
    private static final float MAX_ROLL_DEGREES = 0.35F;

    @SubscribeEvent
    public static void onComputeCameraAngles(ViewportEvent.ComputeCameraAngles event) {
        if (!GoobyClientConfig.cameraShake() || GoobyClientConfig.reducedMotion()) {
            return;
        }
        float partialTick = (float) event.getPartialTick();
        float amount = GoobyClientFx.shakeAmount(partialTick);
        if (amount <= 0.001F) {
            return;
        }
        // Squared envelope ("trauma" curve) keeps the tail of the shake soft.
        float strength = amount * amount;
        float time = GoobyClientFx.animationTime(partialTick);
        event.setYaw(event.getYaw() + strength * MAX_YAW_DEGREES * Mth.sin(time * 1.9F));
        event.setPitch(event.getPitch() + strength * MAX_PITCH_DEGREES * Mth.cos(time * 2.3F));
        event.setRoll(event.getRoll() + strength * MAX_ROLL_DEGREES * Mth.sin(time * 1.5F + 0.7F));
    }

    private GoobyCameraShake() {
    }
}
