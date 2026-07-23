package dev.projecteclipse.eclipse.veilfx;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * One source of truth for the sun (P2 §3.1/R2, FROZEN API). Updated once per frame from the
 * {@link RenderLevelStageEvent} AFTER_SKY matrices — the <b>exact</b> matrices the sky pass
 * renders with, view bobbing and all. This is the sun-halo misalignment fix: the old
 * {@code sun_halo.fsh} reconstructed rays from Veil's {@code veil:camera} block, which
 * deliberately strips view bobbing from its modelview, so the post halo and the sky-pass sun
 * quad disagreed every frame while walking. Now both read from here and cannot diverge:
 * <ul>
 *   <li>{@code clip = Proj · ModelView · vec4(dir, 0)} with the event's matrices;</li>
 *   <li>sun in front ⇔ {@code clip.w > 0}; {@code ndc = clip.xy / clip.w};</li>
 *   <li>angular radius {@code w = tan(5°) · Proj[1][1]} in NDC-y units (matches the 90-unit
 *       eclipse sun quad at sky distance).</li>
 * </ul>
 *
 * <p>All results live in pre-allocated scratch objects — zero per-frame heap allocations.
 * Callers must consume the returned vectors immediately (they are overwritten every
 * frame/call).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SunTracker {
    /** Sun angular radius (5° — matches the 90-unit sun quad at the 100-unit sky distance). */
    private static final float SUN_ANGULAR_RADIUS = (float) Math.toRadians(5.0D);
    /** CPU occlusion probe length in blocks (anything solid this close blots the sun out). */
    private static final double OCCLUSION_PROBE_BLOCKS = 96.0D;

    /** x,y = NDC pos; z = 1 when in front of camera else 0; w = angular radius in NDC-y units. */
    private static final Vector4f SUN_SCREEN = new Vector4f(0.0F, 0.0F, 0.0F, 0.09F);
    private static final Vector3f SUN_DIR = new Vector3f(0.0F, 1.0F, 0.0F);
    /** This frame's {@code Proj · ModelView} (camera-relative world → clip). */
    private static final Matrix4f FRAME_MVP = new Matrix4f();
    private static final Vector4f SCRATCH = new Vector4f();
    private static Vec3 frameCameraPos = Vec3.ZERO;
    private static boolean haveFrame;
    private static boolean occluded;

    private SunTracker() {}

    /**
     * Sun direction in world space: {@code (-sin θ, cos θ, 0)} — the vanilla celestial frame
     * ({@code rotY(-90°) · rotX(θ)} applied to local up). Returns a shared scratch vector.
     */
    public static Vector3f sunDirWorld(float partialTick) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return SUN_DIR.set(0.0F, 1.0F, 0.0F);
        }
        float angle = sunAngleRadians(level, partialTick);
        return SUN_DIR.set(-Mth.sin(angle), Mth.cos(angle), 0.0F);
    }

    /**
     * The vanilla celestial angle θ in radians. Shared helper so the sky-pass sun quad
     * ({@code OverworldPurpleEffects}) and {@link #sunDirWorld} rotate from the SAME number.
     */
    public static float sunAngleRadians(ClientLevel level, float partialTick) {
        return level.getSunAngle(partialTick);
    }

    /**
     * x,y = NDC pos; z = 1 when in front of camera else 0; w = angular radius in NDC-y units.
     * Never null; z=0 when invalid (no level, not overworld, sun behind camera). Shared
     * scratch vector — read, do not store.
     */
    public static Vector4f sunScreen() {
        return SUN_SCREEN;
    }

    /** Cheap occlusion probe result from the last client tick (block raycast toward the sun). */
    public static boolean sunOccluded() {
        return occluded;
    }

    /**
     * Projects a world position through this frame's exact render matrices. On success
     * {@code dest.xy} holds NDC coordinates ({@code dest.z/w} are clip-space leftovers);
     * returns {@code false} when no frame was captured yet or the point is behind the camera.
     * Used by {@code EclipseFxState#shockwaveParams} and available to every sibling FX system.
     */
    public static boolean worldToNdc(Vec3 worldPos, Vector4f dest) {
        if (!haveFrame) {
            return false;
        }
        dest.set((float) (worldPos.x - frameCameraPos.x),
                (float) (worldPos.y - frameCameraPos.y),
                (float) (worldPos.z - frameCameraPos.z), 1.0F);
        FRAME_MVP.transform(dest);
        if (dest.w <= 1.0E-4F) {
            return false;
        }
        dest.x /= dest.w;
        dest.y /= dest.w;
        return true;
    }

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_SKY) {
            return;
        }
        // Cache this frame's matrices in every dimension — worldToNdc consumers (shockwave,
        // captions) are not overworld-only even though the sun is.
        FRAME_MVP.set(event.getProjectionMatrix()).mul(event.getModelViewMatrix());
        frameCameraPos = event.getCamera().getPosition();
        haveFrame = true;

        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || level.dimension() != Level.OVERWORLD) {
            SUN_SCREEN.z = 0.0F;
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float angle = sunAngleRadians(level, partialTick);
        // Directions (w = 0) ignore the camera translation — exactly the sky-pass transform.
        SCRATCH.set(-Mth.sin(angle), Mth.cos(angle), 0.0F, 0.0F);
        FRAME_MVP.transform(SCRATCH);
        if (SCRATCH.w <= 1.0E-4F) {
            SUN_SCREEN.z = 0.0F; // behind the camera
            return;
        }
        float radius = (float) Math.tan(SUN_ANGULAR_RADIUS) * event.getProjectionMatrix().m11();
        SUN_SCREEN.set(SCRATCH.x / SCRATCH.w, SCRATCH.y / SCRATCH.w, 1.0F, radius);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD || minecraft.player == null) {
            occluded = false;
            return;
        }
        float angle = sunAngleRadians(level, 1.0F);
        float dirY = Mth.cos(angle);
        if (dirY <= 0.0F) {
            occluded = true; // below the horizon counts as occluded (halo idles off at night)
            return;
        }
        Vec3 eye = minecraft.player.getEyePosition();
        Vec3 toSun = new Vec3(-Mth.sin(angle) * OCCLUSION_PROBE_BLOCKS,
                dirY * OCCLUSION_PROBE_BLOCKS, 0.0D);
        HitResult hit = level.clip(new ClipContext(eye, eye.add(toSun),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, minecraft.player));
        occluded = hit.getType() != HitResult.Type.MISS;
    }
}
