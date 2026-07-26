package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.limbo.OarAnimator;
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
 *   <li><b>Row-phase sync (LIMBOFIX2):</b> the {@code row} loop is authored at exactly
 *       {@code 3.0 s = 60 t}. The {@code base} controller is force-reset ONCE per rowing
 *       session, on the first {@code gameTime % 60 == 0} boundary after the rower enters
 *       the row state — every rower anchors to the same boundary grid, so all 8 stroke
 *       in unison regardless of when each entity spawned or started rendering. The old
 *       every-60t reset was NOT a no-op at the seam: GeckoLib re-anchors the controller
 *       clock after its 4 t transition, so the loop sat permanently 4 t off the grid and
 *       every reset cut the 2.8–3.0 s catch beat into a linear blend — the whole crew
 *       hitched every 3 s.</li>
 *   <li><b>Port-side mirror:</b> one animation cannot serve both gunwales — the fore-aft
 *       sweep (oar bone yaw) and the blade feather (blade roll) would run bow-ward on one
 *       side and stern-ward on the other in world space. Port rowers (facing {@code -Z})
 *       render with those two channels negated so every blade drives toward the stern
 *       together.</li>
 *   <li><b>Blade splash:</b> 2–3 client-only {@code SPLASH} particles at the water
 *       surface under the blade tip on the catch beat (authored at anim 2.8–3.0 s, which
 *       plays at level-clock phase 0–4 t — see {@link #SPLASH_PHASE_TICKS}), once per
 *       60 t cycle — the visual bridge between the plan-sized oar (tip ~1.1 blocks below
 *       the deck) and the waterline ~3 blocks further down.</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
public class DeckhandRenderer extends EclipseGeoRenderer<DeckhandEntity> {
    /**
     * Level-clock phase (ticks into the 60 t cycle) at which the blade re-enters the
     * water. LIMBOFIX2: the row RUNNING clock anchors 4 t after the sync boundary (the
     * controller's transition), so the authored 2.8–3.0 s catch beat plays at level-clock
     * phase 0–4 — {@code 1.0} fires the splash just as the blade dips (was 56.0, which
     * matched the ANIMATION phase but not the 4 t-lagged level-clock phase).
     */
    private static final float SPLASH_PHASE_TICKS = 1.0F;
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
        if (!rowing || !entity.isAlive() || entity.isTilt()) {
            // The row loop is not the active base animation (hostile walk/sag, death or
            // the cutscene tilt): drop the sync mark so the NEXT rowing session aligns
            // itself once at the following 60t boundary.
            entity.clientRowResetAt = Long.MIN_VALUE;
            return;
        }
        long gameTime = entity.level().getGameTime();
        // Shared row clock — LIMBOFIX2 (user bug "die Wesen sind verbuggt"): align the
        // row loop to the level clock ONCE per rowing session instead of force-resetting
        // on EVERY 60t boundary. forceAnimationReset() re-anchors the controller clock
        // AFTER its 4t transition (AnimationController.process sets shouldResetTick again
        // on the TRANSITIONING→RUNNING flip), so the old per-cycle reset left the loop
        // permanently 4t out of phase with the boundary grid — and every reset then
        // REPLACED the authored 2.8–3.0s catch beat (the blade dip) with a linear pose
        // blend: all 8 rowers visibly hitched every 3 seconds, in unison, forever. The
        // one-time reset costs a single 4t blend when a rower first (re)enters the row
        // state; every rower anchors to the same boundary grid, so the crew still strokes
        // in unison regardless of spawn/first-render time.
        if (entity.clientRowResetAt == Long.MIN_VALUE
                && gameTime % DeckhandEntity.ROW_SYNC_PERIOD_TICKS == 0) {
            entity.clientRowResetAt = gameTime;
            AnimationController<?> base = entity.getAnimatableInstanceCache()
                    .getManagerForId(getInstanceId(entity)).getAnimationControllers()
                    .get(EclipseGeoAnimations.CONTROLLER_BASE);
            if (base != null) {
                base.forceAnimationReset();
            }
        }
        // Splash only once the loop is clock-aligned — phase is meaningless before that.
        if (entity.clientRowResetAt != Long.MIN_VALUE) {
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
        // so both gunwales drive stern-ward on the same beat. LIMBOFIX2: the negation is
        // RESTORED after the draw — GeckoLib's GeoModel.handleAnimations early-returns
        // without re-ticking bones whenever the frame time hasn't advanced (paused game,
        // reRender layer passes), so an unrestored in-place negation flip-flopped the
        // oar between mirrored/unmirrored poses on those frames.
        if (!animatable.isHostile() && isPortSide(animatable)) {
            if ("oar".equals(bone.getName())) {
                float rotY = bone.getRotY();
                bone.setRotY(-rotY);
                super.renderRecursively(poseStack, animatable, bone, renderType, bufferSource, buffer,
                        isReRender, partialTick, packedLight, packedOverlay, colour);
                bone.setRotY(rotY);
                return;
            }
            if ("oar_blade".equals(bone.getName())) {
                float rotZ = bone.getRotZ();
                bone.setRotZ(-rotZ);
                super.renderRecursively(poseStack, animatable, bone, renderType, bufferSource, buffer,
                        isReRender, partialTick, packedLight, packedOverlay, colour);
                bone.setRotZ(rotZ);
                return;
            }
        }
        super.renderRecursively(poseStack, animatable, bone, renderType, bufferSource, buffer, isReRender,
                partialTick, packedLight, packedOverlay, colour);
    }

    /**
     * Portside rowers sit at benches 0–3 ({@code -Z}); starboard at 4–7 ({@code +Z}).
     * C3: the mirror derives from the SEAT ASSIGNMENT (synced bench index +
     * {@link OarAnimator#isPortBench}) instead of the live {@code yBodyRot} — the old
     * heuristic flipped the row cycle whenever a look-at dragged the torso across the
     * mirror threshold. Legacy pre-P6 entities without a bench keep the yaw fallback
     * (their body is pinned server-side now, so it is stable there too).
     */
    private static boolean isPortSide(DeckhandEntity entity) {
        int bench = entity.benchIndex();
        if (bench >= 0) {
            return OarAnimator.isPortBench(bench);
        }
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
