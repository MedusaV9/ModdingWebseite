package dev.projecteclipse.eclipse.client.sky;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterDimensionSpecialEffectsEvent;

/**
 * Registers the Eclipse {@code DimensionSpecialEffects} (mod bus, client only):
 * <ul>
 *   <li>{@code eclipse:overworld} — {@link OverworldPurpleEffects}, referenced by our
 *       {@code data/minecraft/dimension_type/overworld.json} override (all vanilla values kept,
 *       only {@code effects} changed).</li>
 *   <li>{@code eclipse:limbo} — {@link LimboSpecialEffects}, referenced by
 *       {@code data/eclipse/dimension_type/limbo.json}.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseDimensionEffects {
    private EclipseDimensionEffects() {}

    @SubscribeEvent
    static void onRegisterDimensionSpecialEffects(RegisterDimensionSpecialEffectsEvent event) {
        event.register(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "overworld"), new OverworldPurpleEffects());
        event.register(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo"), new LimboSpecialEffects());
    }
}
