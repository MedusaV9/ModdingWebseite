package dev.projecteclipse.eclipse.client.mixin;

import com.mojang.blaze3d.vertex.PoseStack;

import dev.projecteclipse.eclipse.client.contracts.ContractClientState;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.layers.HumanoidArmorLayer;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * KILL CONTRACTS armor blackout (IDEA-20 #4): while the contract window is live,
 * worn armor stops rendering on every PLAYER — hunters cannot pre-filter targets by
 * netherite silhouette, and the target cannot spot the hunter by gear either. The gate
 * is {@link ContractClientState#windowActive()}, which every client tracks via the
 * broadcast {@code S2CContractStatePayload} (the mod is mandatory, so all clients
 * black out in lockstep).
 *
 * <p>Scope is deliberately {@link AbstractClientPlayer} only: GeckoLib mobs use their
 * own renderers (never this vanilla layer), and armor stands / zombies etc. keep their
 * armor — only the anonymized player silhouette is equalized. Inventory-screen and F5
 * views run through the same layer, so the local player sees their own armor vanish
 * too, which is the intended "everyone is a bare hood" reading. Item drops, armor
 * slots and protection values are untouched — this is render-only suppression.</p>
 *
 * <p>Injected at HEAD of the LivingEntity render overload (the {@code Entity} variant
 * in the class file is only the synthetic bridge), cancellable, zero overhead when no
 * window is active.</p>
 */
@OnlyIn(Dist.CLIENT)
@Mixin(HumanoidArmorLayer.class)
public abstract class HumanoidArmorLayerMixin<T extends LivingEntity, M extends HumanoidModel<T>, A extends HumanoidModel<T>> {
    @Inject(
            method = "render(Lcom/mojang/blaze3d/vertex/PoseStack;Lnet/minecraft/client/renderer/MultiBufferSource;ILnet/minecraft/world/entity/LivingEntity;FFFFFF)V",
            at = @At("HEAD"),
            cancellable = true)
    private void eclipse$blackoutArmorDuringContractWindow(PoseStack poseStack,
            MultiBufferSource bufferSource, int packedLight, T livingEntity, float limbSwing,
            float limbSwingAmount, float partialTick, float ageInTicks, float netHeadYaw,
            float headPitch, CallbackInfo callbackInfo) {
        if (livingEntity instanceof AbstractClientPlayer && ContractClientState.windowActive()) {
            callbackInfo.cancel();
        }
    }
}
