package dev.projecteclipse.eclipse.client.mixin;

import java.util.Collection;
import java.util.List;

import net.minecraft.client.multiplayer.ClientSuggestionProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * Empties the client-side online-player-name list used for suggestions. Even with
 * server suggestions gated (see {@code ServerGamePacketListenerImplMixin}), the chat
 * input tab-completes plain words against these locally known names — the popup would
 * spell out the whole roster despite chat itself being blocked. Player-info packets
 * stay untouched; only the name suggestions are masked.
 */
@OnlyIn(Dist.CLIENT)
@Mixin(ClientSuggestionProvider.class)
public abstract class ClientSuggestionProviderMixin {
    @Inject(method = "getOnlinePlayerNames", at = @At("HEAD"), cancellable = true)
    private void eclipse$hidePlayerNameSuggestions(CallbackInfoReturnable<Collection<String>> callbackInfo) {
        callbackInfo.setReturnValue(List.of());
    }
}
