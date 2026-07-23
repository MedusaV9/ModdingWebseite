package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.cache.object.GeoBone;

/**
 * Deckhand renderer — GeckoLib rewrite (P6-W2). The asset triple resolves off the id
 * {@code deckhand}; head tracking targets the {@code head} bone (the crew still eyes
 * passing ghosts). On top of the frozen {@link EclipseGeoRenderer} base this adds the
 * bug-4c/4d client half:
 *
 * <ul>
 *   <li><b>Oar drop:</b> the {@code oar} bone chain is hidden while the deckhand is
 *       hostile (a risen fighter leaves its oar at the bench — v1 model behavior).</li>
 *   <li><b>Row-phase sync:</b> the {@code row} loop is authored at exactly
 *       {@code 3.0 s = 60 t}, so restarting the {@code base} controller whenever
 *       {@code gameTime % 60 == 0} pins every rower's animation clock to the shared
 *       level clock — all 8 stroke in unison regardless of when each entity spawned or
 *       started rendering (plan §2.3 sheet). At the natural loop seam the restart is a
 *       no-op; a drifted client snaps by at most the 4 t controller blend.</li>
 *   <li><b>Port-side mirror:</b> one animation cannot serve both gunwales — the fore-aft
 *       sweep (oar bone yaw) and the blade feather (blade roll) would run bow-ward on one
 *       side and stern-ward on the other in world space. Port rowers (facing {@code -Z})
 *       render with those two channels negated so every blade drives toward the stern
 *       together.</li>
 *   <li><b>Blade splash:</b> 2–3 client-only {@code SPLASH} particles at the water
 *       surface under the blade tip on the catch beat (loop phase ≥ 2.8 s), once per
 *       60 t cycle — the visual bridge between the plan-sized oar (tip ~1.1 blocks below
 *       the deck) and the waterline ~3 blocks further down.</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
public class DeckhandRenderer extends EclipseGeoRenderer<DeckhandEntity> {
    /** Loop phase (in ticks of the 60 t cycle) at which the blade re-enters the water. */
    private static final float SPLASH_PHASE_TICKS = 56.0F;
    /** Blade-tip offset at the plunge, model-space blocks: outboard (-Z) and along (+X). */
    private static final double TIP_OUT_BLOCKS = 2.53D;
    private static final double TIP_ALONG_BLOCKS = 0.41D;

    public DeckhandRenderer(EntityRendererProvider.Context context) {
        super(context, "deckhand", true);
        withUprightDeath(); // Scripted 30t crumple; no vanilla tip-over.
        this.shadowRadius = 0.4F;
    }

    @Override
    public void preRender(PoseStack poseStack, DeckhandEntity entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender, float partialTick,
            int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender, partialTick,
                packedLight, packedOverlay, colour);
        if (isReRender) {
            return;
        }
        // A risen deckhand drops its oar at the bench; it pops back when the crew calms.
        boolean rowing = !entity.isHostile();
        getGeoModel().getBone("oar").ifPresent(oar -> {
            oar.setHidden(!rowing);
            oar.setChildrenHidden(!rowing);
        });
        if (!rowing || !entity.isAlive()) {
            return;
        }
        long gameTime = entity.level().getGameTime();
        // Shared row clock: restart the base controller on every 60t boundary (once per
        // tick — preRender runs per frame). setHidden above is unaffected by animations.
        if (gameTime % DeckhandEntity.ROW_SYNC_PERIOD_TICKS == 0 && entity.clientRowResetAt != gameTime) {
            entity.clientRowResetAt = gameTime;
            AnimationController<?> base = entity.getAnimatableInstanceCache()
                    .getManagerForId(getInstanceId(entity)).getAnimationControllers()
                    .get(EclipseGeoAnimations.CONTROLLER_BASE);
            if (base != null) {
                base.forceAnimationReset();
            }
        }
        if (!entity.isTilt()) {
            spawnCatchSplash(entity, gameTime, partialTick);
        }
    }

    /** Client-only splash burst at the water surface under the blade tip, once per stroke. */
    private void spawnCatchSplash(DeckhandEntity entity, long gameTime, float partialTick) {
        float phase = (gameTime % DeckhandEntity.ROW_SYNC_PERIOD_TICKS) + partialTick;
        long cycle = gameTime / DeckhandEntity.ROW_SYNC_PERIOD_TICKS;
        if (phase < SPLASH_PHASE_TICKS || entity.clientSplashCycle == cycle) {
            return;
        }
        entity.clientSplashCycle = cycle;
        float yawRad = entity.yBodyRot * Mth.DEG_TO_RAD;
        // Model -Z (outboard) and +X (bow for starboard; mirrored for port) in world space.
        double fwdX = -Mth.sin(yawRad);
        double fwdZ = Mth.cos(yawRad);
        double along = isPortSide(entity) ? -TIP_ALONG_BLOCKS : TIP_ALONG_BLOCKS;
        double x = entity.getX() + fwdX * TIP_OUT_BLOCKS + fwdZ * along;
        double z = entity.getZ() + fwdZ * TIP_OUT_BLOCKS - fwdX * along;
        // Find the water surface below the blade tip (the oar is plan-sized, not literal).
        BlockPos.MutableBlockPos probe = BlockPos.containing(x, entity.getY() + 0.5D, z).mutable();
        for (int i = 0; i < 7; i++) {
            if (!entity.level().getFluidState(probe).isEmpty()) {
                double surfaceY = probe.getY() + 0.9D;
                for (int p = 0; p < 3; p++) {
                    entity.level().addParticle(ParticleTypes.SPLASH,
                            x + (entity.getRandom().nextDouble() - 0.5D) * 0.4D, surfaceY,
                            z + (entity.getRandom().nextDouble() - 0.5D) * 0.4D,
                            0.0D, 0.06D, 0.0D);
                }
                return;
            }
            probe.move(0, -1, 0);
        }
    }

    @Override
    public void renderRecursively(PoseStack poseStack, DeckhandEntity animatable, GeoBone bone,
            RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender,
            float partialTick, int packedLight, int packedOverlay, int colour) {
        // Port-side mirror (bug 4d): negate the oar's fore-aft sweep + the blade feather
        // so both gunwales drive stern-ward on the same beat. Only while the oar is shown
        // (row/tilt keyframe both channels every frame, so no flip can accumulate).
        if (!animatable.isHostile() && isPortSide(animatable)) {
            if ("oar".equals(bone.getName())) {
                bone.setRotY(-bone.getRotY());
            } else if ("oar_blade".equals(bone.getName())) {
                bone.setRotZ(-bone.getRotZ());
            }
        }
        super.renderRecursively(poseStack, animatable, bone, renderType, bufferSource, buffer, isReRender,
                partialTick, packedLight, packedOverlay, colour);
    }

    /** Portside rowers face {@code -Z} (bench yaw 180); starboard face {@code +Z} (yaw 0). */
    private static boolean isPortSide(DeckhandEntity entity) {
        return Mth.cos(entity.yBodyRot * Mth.DEG_TO_RAD) < 0.0F;
    }

    /**
     * Renderer self-registration — P6-W2 moved the deckhand lines out of
     * {@code EclipseEntityRenderers} (GeckoLib needs no layer definitions; plan §2.1).
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registration {
        private Registration() {}

        @SubscribeEvent
        static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
            event.registerEntityRenderer(EclipseEntities.DECKHAND.get(), DeckhandRenderer::new);
        }
    }
}
