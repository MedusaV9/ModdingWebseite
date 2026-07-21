package dev.projecteclipse.eclipse.client.sky;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ViewportEvent;

/**
 * Purple fog/sky tint in the Overworld (game bus, client only): blends the computed fog color
 * ~35% toward (0.35, 0.10, 0.45) at midday, fading to zero at night. Works with or without
 * shaderpacks (Iris applies the event-adjusted fog color), so it is the layer that keeps the
 * eclipse mood alive when the custom sky yields to Iris.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class OverworldFogTint {
    private static final float PURPLE_R = 0.35F;
    private static final float PURPLE_G = 0.10F;
    private static final float PURPLE_B = 0.45F;
    private static final float MAX_BLEND = 0.35F;

    private OverworldFogTint() {}

    @SubscribeEvent
    static void onComputeFogColor(ViewportEvent.ComputeFogColor event) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || level.dimension() != Level.OVERWORLD) {
            return;
        }
        float blend = MAX_BLEND * OverworldPurpleEffects.dayFactor(level, (float) event.getPartialTick());
        if (blend <= 0.0F) {
            return;
        }
        event.setRed(Mth.lerp(blend, event.getRed(), PURPLE_R));
        event.setGreen(Mth.lerp(blend, event.getGreen(), PURPLE_G));
        event.setBlue(Mth.lerp(blend, event.getBlue(), PURPLE_B));
    }
}
