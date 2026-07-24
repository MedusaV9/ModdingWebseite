package dev.projecteclipse.eclipse.anonymity.mixin;

import java.util.Set;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.server.players.PlayerList;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Filters only vanilla join/leave announcements at their shared server broadcast point.
 * Other system messages remain available for gameplay and administration.
 */
@Mixin(PlayerList.class)
public abstract class PlayerListMixin {
    @Unique
    private static final Set<String> ECLIPSE$HIDDEN_PLAYER_MESSAGES = Set.of(
            "multiplayer.player.joined",
            "multiplayer.player.joined.renamed",
            "multiplayer.player.left");

    @Inject(
            method = "broadcastSystemMessage(Lnet/minecraft/network/chat/Component;Z)V",
            at = @At("HEAD"),
            cancellable = true)
    private void eclipse$hideJoinLeaveMessages(
            Component message, boolean bypassHiddenChat, CallbackInfo callbackInfo) {
        if (message.getContents() instanceof TranslatableContents contents
                && ECLIPSE$HIDDEN_PLAYER_MESSAGES.contains(contents.getKey())) {
            callbackInfo.cancel();
        }
    }
}
