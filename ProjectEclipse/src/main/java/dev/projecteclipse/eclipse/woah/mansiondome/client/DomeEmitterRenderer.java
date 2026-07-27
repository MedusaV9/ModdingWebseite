package dev.projecteclipse.eclipse.woah.mansiondome.client;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.woah.mansiondome.DomeEmitterEntity;
import dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeEntities;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.util.Color;

/**
 * WOAH-01 §4.6 — the glitch-emitter device renderer. Asset triple resolves off
 * {@code glitch_emitter} ({@code geo/entity/}, {@code animations/entity/},
 * {@code textures/entity/} + {@code _glowmask.png} — the core and antenna knob glow
 * fullbright via {@link EclipseGeoRenderer#withGlowmask()}).
 *
 * <p>Crack stages, asset-free (plan law — no extra damage texture): at
 * {@code hitsRemaining ≤ 4} the render colour flickers red-ward (the device browns out);
 * at {@code ≤ 2} an additional ±0.02-block position jitter in {@code preRender} makes it
 * physically glitch. Registration: {@code DeckhandRenderer.Registration} self-pattern —
 * the shared {@code EclipseEntityRenderers} stays untouched (parallel-worker law).</p>
 */
@OnlyIn(Dist.CLIENT)
public class DomeEmitterRenderer extends EclipseGeoRenderer<DomeEmitterEntity> {
    /** Crack thresholds (of {@code MansionDomeState.MAX_HITS} = 8). */
    private static final int HITS_TINT = 4;
    private static final int HITS_JITTER = 2;
    private static final float JITTER_BLOCKS = 0.02F;

    public DomeEmitterRenderer(EntityRendererProvider.Context context) {
        super(context, "glitch_emitter");
        withGlowmask();
        this.shadowRadius = 0.9F;
    }

    @Override
    public Color getRenderColor(DomeEmitterEntity entity, float partialTick, int packedLight) {
        int hits = entity.hitsRemaining();
        if (hits > HITS_TINT) {
            return super.getRenderColor(entity, partialTick, packedLight);
        }
        // Red-ward brown-out flicker, harder the more broken the device is (4 → 1 hits).
        float damage = 1.0F - (hits - 1) / (float) HITS_TINT; // 0.25 .. 1.0
        float t = (entity.tickCount + partialTick) * 0.7F;
        float flicker = 0.5F + 0.5F * Mth.sin(t * 5.1F) * Mth.sin(t * 1.7F + 0.9F);
        float drop = 0.35F * damage * flicker;
        return Color.ofRGB(1.0F, 1.0F - drop, 1.0F - drop * 0.9F);
    }

    @Override
    public void preRender(PoseStack poseStack, DomeEmitterEntity entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender,
            float partialTick, int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender,
                partialTick, packedLight, packedOverlay, colour);
        int hits = entity.hitsRemaining();
        if (isReRender || hits > HITS_JITTER || hits <= 0) {
            return;
        }
        // Near-death physical glitch: a per-frame ±0.02 XZ pop (deterministic hash — no
        // Random allocation, stable within a frame via tickCount + partialTick bucket).
        int seed = entity.getId() * 31 + entity.tickCount * 7 + (int) (partialTick * 3.0F);
        float jx = ((Mth.murmurHash3Mixer(seed) & 0xFF) / 127.5F - 1.0F) * JITTER_BLOCKS;
        float jz = ((Mth.murmurHash3Mixer(seed + 1337) & 0xFF) / 127.5F - 1.0F) * JITTER_BLOCKS;
        poseStack.translate(jx, 0.0F, jz);
    }

    /** Renderer self-registration (DeckhandRenderer.Registration pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registration {
        private Registration() {}

        @SubscribeEvent
        static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
            if (MansionDomeEntities.GLITCH_EMITTER.isBound()) {
                event.registerEntityRenderer(MansionDomeEntities.GLITCH_EMITTER.get(),
                        DomeEmitterRenderer::new);
            }
        }
    }
}
