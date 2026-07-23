package dev.projecteclipse.eclipse.client.mixin;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.client.resources.PlayerSkin;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * Replaces every local and remote client-player skin with one bundled texture:
 * the "eclipsed" figure (charcoal hooded robe, glowing purple eye slit), always
 * on the WIDE (classic) model. Covers the own player too (F5, inventory preview),
 * and the {@code null} cape/elytra textures hide capes and custom elytra wings.
 * Player-info packets remain intact so remote player entities continue to render.
 *
 * <p>Deliberately NOT gated by an {@code EclipseClientConfig} toggle: like
 * {@code ChatBlocker}/{@code NameTagHider}/{@code TabListHider} this is
 * anonymity-critical, and a local config edit must never unmask players.</p>
 */
@OnlyIn(Dist.CLIENT)
@Mixin(AbstractClientPlayer.class)
public abstract class AbstractClientPlayerMixin {
    @Unique
    private static final PlayerSkin ECLIPSE$UNIFORM_SKIN = new PlayerSkin(
            ResourceLocation.fromNamespaceAndPath(
                    EclipseMod.MOD_ID, "textures/entity/eclipsed_player.png"),
            null,
            null,
            null,
            PlayerSkin.Model.WIDE,
            true);

    @Inject(method = "getSkin", at = @At("HEAD"), cancellable = true)
    private void eclipse$useUniformSkin(CallbackInfoReturnable<PlayerSkin> callbackInfo) {
        callbackInfo.setReturnValue(ECLIPSE$UNIFORM_SKIN);
    }
}
