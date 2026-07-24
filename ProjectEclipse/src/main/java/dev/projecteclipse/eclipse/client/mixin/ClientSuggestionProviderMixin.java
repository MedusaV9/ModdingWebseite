package dev.projecteclipse.eclipse.client.mixin;

import java.util.Collection;
import java.util.List;

import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.multiplayer.ClientSuggestionProvider;
import net.minecraft.commands.Commands;
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
 *
 * <p>PLAN-B B17: gated on the LOCAL player's permission level, mirroring the server
 * mixin's {@code ask_server} gate exactly — operators (permission &ge;
 * {@link Commands#LEVEL_GAMEMASTERS}) keep full client-side name completion (vanilla
 * {@code EntityArgument.listSuggestions} computes player-name suggestions from exactly
 * this method, so {@code /give <tab>} works again for ops), while everyone else stays
 * masked. The permission level is server-authoritative (entity-event packet 24-28), so
 * a client cannot unmask itself by faking it without also being able to read the
 * player-info packets directly — the same honest-client threat model as the rest of
 * the anonymity layer.</p>
 */
@OnlyIn(Dist.CLIENT)
@Mixin(ClientSuggestionProvider.class)
public abstract class ClientSuggestionProviderMixin {
    @Inject(method = "getOnlinePlayerNames", at = @At("HEAD"), cancellable = true)
    private void eclipse$hidePlayerNameSuggestions(CallbackInfoReturnable<Collection<String>> callbackInfo) {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null || !player.hasPermissions(Commands.LEVEL_GAMEMASTERS)) {
            callbackInfo.setReturnValue(List.of());
        }
    }
}
