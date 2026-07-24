package dev.projecteclipse.eclipse.client.mixin;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import net.minecraft.client.Camera;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.BlockGetter;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Cutscene camera override: after the vanilla camera has fully set up for the frame,
 * {@link CameraDirector} replaces position/rotation while a camera path is active (and adds
 * shake-impulse offsets during the intro fusion rumble). TAIL injection keeps every vanilla
 * feature (fluid fog lookup, third-person zoom clipping) computed before the override; the
 * widened {@code setPosition(Vec3)}/{@code setRotation(yaw, pitch, roll)} setters come from
 * {@code META-INF/accesstransformer.cfg}. If another mod's mixin also wins this TAIL, the
 * {@code ViewportEvent.ComputeCameraAngles} handler in {@code CameraDirector} re-applies
 * yaw/pitch/roll as a fallback (position would then follow the foreign override).
 */
@OnlyIn(Dist.CLIENT)
@Mixin(Camera.class)
public abstract class CameraMixin {
    @Inject(method = "setup", at = @At("TAIL"))
    private void eclipse$applyCutsceneCamera(BlockGetter level, Entity entity, boolean detached,
            boolean inverseView, float partialTick, CallbackInfo callbackInfo) {
        CameraDirector.onCameraSetup((Camera) (Object) this);
    }
}
