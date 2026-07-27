package dev.projecteclipse.eclipse.veilfx.rift;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * RIFT-FX — the volumetric layer of the dimensional tears: feeds the
 * {@code eclipse:rift_volume} post pipeline (a scene-depth-clamped raymarcher, see
 * {@code assets/eclipse/pinwheel/shaders/program/rift_volume.fsh}) with up to
 * {@value #MAX_VOLUME_RIFTS} live rifts per frame. {@link RiftRenderer}'s star-tear
 * geometry stays untouched underneath — it draws with {@code depthMask(false)} (verified:
 * nothing of ours writes depth inside the marching range) and remains the complete
 * fallback whenever this pass is off (Iris shaderpack, {@code veilPostFx} off,
 * {@code reducedFx}, quality tier 0, budget eviction, failure fuse — the
 * {@link VeilPostController} row handles all of those).
 *
 * <p><b>Uniform contract</b> (names frozen with the shader): {@code Rift<i>Center}
 * (camera-relative tear center), {@code Rift<i>Normal} (tear-plane normal — the shader
 * re-derives the same tangent basis {@code RiftFx.Rift} builds), {@code Rift<i>Params} =
 * {@code (radiusBlocks, strength, seed01, styleF)} where radius breathes with the open
 * amount and the delivery {@code recoilScale} pump, and strength is
 * {@code openAmount · distance-fade}; plus {@code RiftCount}, {@code StepCount}
 * ({@value #STEPS_TIER2}/{@value #STEPS_TIER1} by {@link FxBudget#qualityTier()}),
 * {@code Time} (tick-clock seconds, pause-safe) and the global {@code Strength} fade.</p>
 *
 * <p><b>Performance</b>: per-rift analytic ellipsoid bounds with early miss discard,
 * bounded step count, dithered march start, early exit at low transmittance — all in the
 * shader; this class only selects the {@value #MAX_VOLUME_RIFTS} nearest tears inside
 * {@value #VOLUME_RANGE} blocks once per tick (zero per-frame allocations in the feeder).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RiftVolumeFx {
    public static final ResourceLocation RIFT_VOLUME_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_volume");

    /** The raymarcher covers at most this many tears per frame (nearest win). */
    private static final int MAX_VOLUME_RIFTS = 2;
    /** The pass engages while a tear's shell is inside this distance (blocks). */
    private static final double VOLUME_RANGE = 260.0D;
    /** Strength ramps 1 → 0 over [fade-start, range] so the pass never pops at range. */
    private static final double STRENGTH_FADE_START = 200.0D;
    /** Raymarch step budget by quality tier (tier 0 disables the pass entirely). */
    private static final float STEPS_TIER2 = 48.0F;
    private static final float STEPS_TIER1 = 28.0F;
    /** Volume radius breathes from this fraction (tear opening) up to 1.0 (fully open). */
    private static final float RADIUS_CLOSED_FRACTION = 0.35F;
    /**
     * Camera-inside guard (BLACKSCREEN fix). The shader marches from {@code t0 = 0} when
     * the camera sits inside a tear's bounds, so EVERY pixel starts inside the collar
     * mass: transmittance collapses and the frame turns near-black violet — exactly the
     * "black screen when structures spawn" report, because a structure delivery opens a
     * ground tear of up to 24 blocks' width right where the player is standing.
     *
     * <p>Distances are measured in the shader's own squashed rift space (planar / radius,
     * normal / (radius·{@code DEPTH_SCALE})), where {@code 1.30} is the bounds margin the
     * march uses. The volume fades out below {@value #CAMERA_FADE_OUT} and is fully back
     * at {@value #CAMERA_FADE_IN}, so walking into a tear dissolves the raymarched mass
     * smoothly instead of blacking out — {@code RiftRenderer}'s star geometry keeps
     * drawing the tear throughout, so the spectacle stays visible.</p>
     *
     * <p>F-089 hardening: band widened 1.15/1.55 → 1.35/1.90. Standing ~14–19 blocks
     * from a fully open 24-wide ground tear left the near-black violet mass at partial
     * strength across most of a view looking over it — the volume now dissolves earlier
     * as the camera approaches, at no cost to the 30+ block look.</p>
     */
    private static final float CAMERA_FADE_OUT = 1.35F;
    private static final float CAMERA_FADE_IN = 1.90F;
    /** Mirror of the shader's {@code DEPTH_SCALE} — the guard must use the same space. */
    private static final double DEPTH_SCALE = 0.55D;

    /** Selected tears this tick, nearest first ({@code null} slots = pipeline idle). */
    @Nullable
    private static RiftFx.Rift rift0;
    @Nullable
    private static RiftFx.Rift rift1;

    static {
        // Feature-owned registration (the StormVolumeFx seam) — FEATURE priority: the
        // volume composites on top of the grades and under the transitions.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                RIFT_VOLUME_POST,
                VeilPostController.PipelinePriority.FEATURE,
                () -> rift0 != null,
                RiftVolumeFx::feed));
    }

    private RiftVolumeFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            rift0 = null;
            rift1 = null;
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        pickRifts(minecraft.gameRenderer.getMainCamera().getPosition());
    }

    /**
     * Selects the {@value #MAX_VOLUME_RIFTS} nearest live tears by shell distance.
     * Quality tier ≥ 1 and no {@code reducedFx}: per-pixel raymarching is motion-bearing
     * by definition (the StormVolumeFx doctrine) — the star geometry alone is the
     * reduced read.
     */
    private static void pickRifts(Vec3 camera) {
        rift0 = null;
        rift1 = null;
        if (EclipseClientConfig.reducedFx() || FxBudget.qualityTier() < 1) {
            return;
        }
        java.util.List<RiftFx.Rift> rifts = RiftFx.rifts();
        double bestDist0 = VOLUME_RANGE;
        double bestDist1 = VOLUME_RANGE;
        float now = RiftFx.timeNow(0.0F);
        for (int i = 0; i < rifts.size(); i++) {
            RiftFx.Rift rift = rifts.get(i);
            if (rift.openAmount(now) <= 0.01F) {
                continue;
            }
            double shellDist = camera.distanceTo(rift.pos) - rift.width * 0.5D;
            if (shellDist < bestDist0) {
                bestDist1 = bestDist0;
                rift1 = rift0;
                bestDist0 = shellDist;
                rift0 = rift;
            } else if (shellDist < bestDist1) {
                bestDist1 = shellDist;
                rift1 = rift;
            }
        }
    }

    // ------------------------------------------------------------------ uniform feed

    private static void feed(PostPipeline pipeline) {
        Minecraft minecraft = Minecraft.getInstance();
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        float partialTick = minecraft.getTimer().getGameTimeDeltaPartialTick(false);
        float now = RiftFx.timeNow(partialTick);

        RiftFx.Rift first = rift0;
        RiftFx.Rift second = rift1;
        int count = first != null ? (second != null ? 2 : 1) : 0;
        pipeline.getUniform("RiftCount").setFloat(count);
        pipeline.getUniform("Strength").setFloat(1.0F);
        pipeline.getUniform("StepCount").setFloat(
                FxBudget.qualityTier() >= 2 ? STEPS_TIER2 : STEPS_TIER1);
        // Tick clock, not wall clock: pause-safe and continuous (the shader integrates
        // the vortex angle from it — a wall-clock wrap would snap the churn).
        pipeline.getUniform("Time").setFloat(now / 20.0F);
        if (first != null) {
            feedRift(pipeline, "Rift0Center", "Rift0Normal", "Rift0Params", first, camera, now);
        }
        if (second != null) {
            feedRift(pipeline, "Rift1Center", "Rift1Normal", "Rift1Params", second, camera, now);
        }
    }

    /**
     * One tear's uniform triple; strength folds open amount and the distance fade.
     * Uniform names arrive as literals — the feeder contract forbids per-frame
     * allocations, so no string concatenation here.
     */
    private static void feedRift(PostPipeline pipeline, String centerName, String normalName,
            String paramsName, RiftFx.Rift rift, Vec3 camera, float now) {
        float open = rift.openAmount(now);
        double shellDist = camera.distanceTo(rift.pos) - rift.width * 0.5D;
        float fade = (float) Mth.clamp(
                1.0D - (shellDist - STRENGTH_FADE_START) / (VOLUME_RANGE - STRENGTH_FADE_START),
                0.0D, 1.0D);
        // The volume breathes with the tear: radius grows on the open ease and pumps
        // with the delivery recoil (VEIL-REPASS-2's launch compression, shared read).
        float radius = rift.width * 0.5F
                * (RADIUS_CLOSED_FRACTION + (1.0F - RADIUS_CLOSED_FRACTION) * open)
                * rift.recoilScale(now);
        pipeline.getUniform(centerName).setVector(
                (float) (rift.pos.x - camera.x),
                (float) (rift.pos.y - camera.y),
                (float) (rift.pos.z - camera.z));
        pipeline.getUniform(normalName).setVector(rift.nx, rift.ny, rift.nz);
        pipeline.getUniform(paramsName).setVector(radius,
                open * fade * cameraClearance(rift, camera, radius),
                (rift.seed & 0xFFFF) / 65536.0F, rift.style);
    }

    /**
     * Strength multiplier that dissolves the volume as the camera enters a tear — see
     * {@link #CAMERA_FADE_OUT}. Returns 1 whenever the camera is comfortably outside the
     * marched bounds, so the normal look is untouched.
     */
    private static float cameraClearance(RiftFx.Rift rift, Vec3 camera, float radius) {
        if (radius <= 0.0F) {
            return 0.0F;
        }
        double dx = rift.pos.x - camera.x;
        double dy = rift.pos.y - camera.y;
        double dz = rift.pos.z - camera.z;
        // Split the camera offset into the tear's normal axis and its plane; the plane is
        // radially symmetric, so the tangent basis itself is not needed here.
        double alongNormal = dx * rift.nx + dy * rift.ny + dz * rift.nz;
        double planar = Math.sqrt(Math.max(0.0D,
                dx * dx + dy * dy + dz * dz - alongNormal * alongNormal)) / radius;
        double normal = alongNormal / (radius * DEPTH_SCALE);
        double depth = Math.sqrt(planar * planar + normal * normal);
        return (float) Mth.clamp((depth - CAMERA_FADE_OUT) / (CAMERA_FADE_IN - CAMERA_FADE_OUT),
                0.0D, 1.0D);
    }
}
