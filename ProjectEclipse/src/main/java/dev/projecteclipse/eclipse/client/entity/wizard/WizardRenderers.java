package dev.projecteclipse.eclipse.client.entity.wizard;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.wizard.WizardEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the wizard family — auto-subscribed, no {@code EclipseMod}
 * wiring needed (house §1.6 pattern, {@code AmbientRenderers} copy). Guarded on
 * {@code DeferredHolder.isBound()} so the client boots green while the
 * {@code WizardEntities.register(modEventBus)} wiring line
 * ({@code docs/plans_v3/wiring/W4-WIZARD_wiring.md}) has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WizardRenderers {
    private WizardRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!WizardEntities.WIZARD_ORIN.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(WizardEntities.WIZARD_ORIN.get(), WizardOrinRenderer::new);
    }
}
