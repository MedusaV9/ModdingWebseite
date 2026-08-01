package dev.projecteclipse.eclipse.client.entity;

import javax.annotation.Nullable;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
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
import software.bernie.geckolib.animation.AnimationProcessor.QueuedAnimation;
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
 *   <li><b>Face identity (MB1):</b> the cowl carries nine stacked emissive cards
 *       ({@code glow_face_0..7} + {@code glow_face_wrath}); exactly ONE bench card is
 *       shown per rower, picked from the synced bench index, so the eight crew members
 *       are individually recognisable instead of eight identical shadows. The wrath
 *       card lights on top of it while the crew is risen.</li>
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
    /**
     * Blade-tip offset at the plunge, in blocks, measured off the POSED skeleton at the
     * exact splash frame (anim 2.85 s = tick 57, the frame {@link #SPLASH_PHASE_TICKS}
     * selects): the outboard face centre of the {@code oar_blade} cube sits at model
     * {@code (-9.07, -8.78, -46.20)} px = {@code 2.89} blocks outboard (model {@code -Z})
     * and {@code -0.57} blocks along the hull (model {@code -X}) for a starboard rower;
     * port mirrors both the sweep and this offset, hence the negation below. The older
     * 2.53/0.41 pair described the blade PIVOT in its REST pose, not the tip at the
     * catch, so the splash landed ~0.35 blocks inboard of where the blade actually
     * entered — and it carried the along-hull term with the WRONG SIGN, putting it a
     * further 1.1 blocks up-hull, i.e. under the next rower's bench.
     */
    private static final double TIP_OUT_BLOCKS = 2.89D;
    private static final double TIP_ALONG_BLOCKS = -0.57D;

    /** How many per-rower face cards the geo carries ({@code glow_face_0..7}). */
    private static final int FACE_VARIANTS = 8;
    /** Bone names, resolved once — {@code preRender} runs per rower per frame. */
    private static final String[] FACE_BONES = new String[FACE_VARIANTS];
    private static final String WRATH_BONE = "glow_face_wrath";

    static {
        for (int i = 0; i < FACE_VARIANTS; i++) {
            FACE_BONES[i] = "glow_face_" + i;
        }
    }

    /**
     * Whether the rower currently being drawn still carries its oar — decided once in
     * {@link #preRender} and read back in {@link #renderRecursively}, which runs for the
     * same entity immediately afterwards (one renderer instance draws one entity at a
     * time; this is the same contract the shared bone-visibility flags rely on).
     */
    private boolean oarShown;

    public DeckhandRenderer(EntityRendererProvider.Context context) {
        super(context, "deckhand", true);
        withUprightDeath(); // Scripted 30t crumple; no vanilla tip-over.
        withGlowmask();     // The face cards are the mob's only emissive geometry.
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
        // MB1: the hostile flag flips on the SAME tick the rise one-shot is triggered
        // (DeckhandEntity.riseHostile), so hiding on isHostile() alone cut the oar away
        // on frame 1 of the rise and the whole hand-off read as a pop. The rise clip
        // dissolves the oar itself (scale 1 -> 0.01 over 0.14–0.50 s), so the bone stays
        // visible for as long as that one-shot runs and the hide only takes over once it
        // is done — by then the oar is already scaled to nothing.
        this.oarShown = !entity.isHostile() || isPlaying(entity, EclipseGeoAnimations.CONTROLLER_ACTION,
                EclipseGeoAnimations.animId("deckhand", DeckhandEntity.ANIM_RISE));
        final boolean showOar = this.oarShown;
        getGeoModel().getBone("oar").ifPresent(oar -> {
            oar.setHidden(!showOar);
            oar.setChildrenHidden(!showOar);
        });
        applyFace(entity);
        if (entity.isHostile() || !entity.isAlive() || entity.isTilt()) {
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
            AnimationController<?> base = controller(entity, EclipseGeoAnimations.CONTROLLER_BASE);
            if (base != null) {
                base.forceAnimationReset();
            }
        }
        // Splash only once the loop is clock-aligned — phase is meaningless before that.
        if (entity.clientRowResetAt != Long.MIN_VALUE) {
            spawnCatchSplash(entity, gameTime, partialTick);
        }
    }

    /** This rower's own controller instance ({@code null} before the first tick). */
    @Nullable
    private AnimationController<?> controller(DeckhandEntity entity, String name) {
        return entity.getAnimatableInstanceCache().getManagerForId(getInstanceId(entity))
                .getAnimationControllers().get(name);
    }

    /**
     * Whether {@code animId} is the clip currently on {@code controllerName} and has not
     * run out yet. {@code hasAnimationFinished()} only reports the STOPPED state, which a
     * play-once clip reaches exactly on its last frame — so this stays true for the whole
     * one-shot and goes false the frame after it ends.
     */
    private boolean isPlaying(DeckhandEntity entity, String controllerName, String animId) {
        AnimationController<?> controller = controller(entity, controllerName);
        if (controller == null || controller.hasAnimationFinished()) {
            return false;
        }
        QueuedAnimation current = controller.getCurrentAnimation();
        return current != null && animId.equals(current.animation().name());
    }

    /**
     * Shows this rower's own soul-light and hides the other seven (MB1). The nine cards
     * are stacked on one spot in the cowl, so exactly one bench card may be visible at a
     * time; the wrath brand layers 0.2 px in front of it while the crew is risen.
     *
     * <p>The baked model — and therefore the bone visibility flags — is SHARED by all
     * eight rowers, which is why this runs per entity per frame right before its draw
     * (same contract as the oar toggle above and as {@code FerrymanGeoRenderer}). The
     * flags survive into the {@code AutoGlowingGeoLayer} re-render pass, so the emissive
     * copy shows the same single card.</p>
     */
    private void applyFace(DeckhandEntity entity) {
        int variant = faceVariant(entity);
        for (int i = 0; i < FACE_VARIANTS; i++) {
            final boolean hidden = i != variant;
            getGeoModel().getBone(FACE_BONES[i]).ifPresent(bone -> bone.setHidden(hidden));
        }
        getGeoModel().getBone(WRATH_BONE).ifPresent(bone -> bone.setHidden(!entity.isHostile()));
    }

    /**
     * Which of the eight face cards this rower burns. Driven by the synced bench index so
     * a given seat always shows the same face (it survives reloads — the index is NBT —
     * and both sides agree). Pre-P6 benchless strays fall back to a stable UUID hash
     * rather than to a shared default, so two strays still differ.
     */
    private static int faceVariant(DeckhandEntity entity) {
        int bench = entity.benchIndex();
        if (bench >= 0) {
            return bench % FACE_VARIANTS;
        }
        return Math.floorMod(entity.getUUID().hashCode(), FACE_VARIANTS);
    }

    /**
     * Client-only splash burst at the water surface under the blade tip, once per stroke.
     * F-104 (IDEA-18 §5): each catch additionally sheds a ghost wake — a few luminous
     * {@code SOUL}/{@code GLOW} flecks at the surface sliding sternward (world {@code -X};
     * bow is {@code +X}, the {@code GhostShipBuilder} v2 silhouette), spread over the
     * next ~1.5 blocks so the eight synchronized blades paint eight short drift lines.
     * Rides the existing call-site guards (tilt drops the sync mark, a hostile rower
     * never rows), zero new assets; {@code reducedFx} halves the fleck count.
     */
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
                spawnGhostWake(entity, x, surfaceY, z);
                return;
            }
            probe.move(0, -1, 0);
        }
    }

    /**
     * F-104 (IDEA-18 §5) — the ghost wake: 4–6 luminous flecks peeling off the catch
     * point and drifting sternward. Mostly {@code SOUL} — its provider honors the passed
     * velocity ({@code RisingParticle}: {@code xd = xd·0.01 + xSpeed}), so the flecks
     * visibly slide {@code -X} — plus one stationary {@code GLOW} glint per catch
     * (its {@code GlowSquidProvider} IGNORES nonzero x/z speeds and would scatter
     * randomly, so it gets zero velocity and merely twinkles where the blade bit).
     */
    private static void spawnGhostWake(DeckhandEntity entity, double x, double surfaceY, double z) {
        boolean reduced = EclipseClientConfig.reducedFx();
        int flecks = reduced ? 2 : 4 + entity.getRandom().nextInt(3);
        for (int p = 0; p < flecks; p++) {
            // Spread astern over ~1.5 blocks so the line reads as a drift trail, not a puff.
            double drift = entity.getRandom().nextDouble() * 1.5D;
            double jitter = (entity.getRandom().nextDouble() - 0.5D) * 0.3D;
            if (p == 0 && !reduced) {
                entity.level().addParticle(ParticleTypes.GLOW,
                        x - drift * 0.3D, surfaceY + 0.05D, z + jitter, 0.0D, 0.0D, 0.0D);
                continue;
            }
            entity.level().addParticle(ParticleTypes.SOUL,
                    x - drift, surfaceY + 0.05D, z + jitter,
                    -0.05D, 0.0D, 0.0D);
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
        // oar between mirrored/unmirrored poses on those frames. MB1: the gate is the
        // "is the oar on screen" flag, not isHostile() — the rise one-shot keeps the oar
        // for half a second after the flag flips, and dropping the mirror for those
        // frames would snap a port oar across the hull right before it dissolves.
        if (this.oarShown && isPortSide(animatable)) {
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
