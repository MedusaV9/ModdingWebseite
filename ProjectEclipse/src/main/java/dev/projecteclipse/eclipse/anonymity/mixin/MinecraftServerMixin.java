package dev.projecteclipse.eclipse.anonymity.mixin;

import java.util.List;

import net.minecraft.network.protocol.status.ServerStatus;
import net.minecraft.server.MinecraftServer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * Strips the player sample (up to 12 real profile names + UUIDs) from the public
 * server-list status ping, which needs no authentication to query. Equivalent to
 * forcing {@code hide-online-players=true}, but enforced by the mod instead of
 * relying on a server.properties line nobody must forget. Player count stays visible.
 */
@Mixin(MinecraftServer.class)
public abstract class MinecraftServerMixin {
    @Inject(method = "buildPlayerStatus", at = @At("RETURN"), cancellable = true)
    private void eclipse$hidePlayerSample(CallbackInfoReturnable<ServerStatus.Players> callbackInfo) {
        ServerStatus.Players players = callbackInfo.getReturnValue();
        if (!players.sample().isEmpty()) {
            callbackInfo.setReturnValue(new ServerStatus.Players(players.max(), players.online(), List.of()));
        }
    }
}
