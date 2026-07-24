package dev.projecteclipse.eclipse.anonymity.mixin;

import net.minecraft.commands.Commands;
import net.minecraft.network.protocol.game.ServerboundCommandSuggestionPacket;
import net.minecraft.network.protocol.game.ServerboundEditBookPacket;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.network.ServerGamePacketListenerImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Server-authoritative packet blocks for two name leaks the event handlers cannot reach:
 *
 * <ul>
 *   <li><b>Book editing</b> — {@code handleEditBook} writes player text and, on signing,
 *       stamps the WRITTEN_BOOK_CONTENT author with the sender's profile name. The
 *       {@code TextInputBlocker} use-event cancel keeps the edit screen from opening, but
 *       the screen is purely client-initiated, so the packet itself must be dropped too.</li>
 *   <li><b>Command tab-completion</b> — argument suggestions are computed server-side
 *       ({@code minecraft:ask_server}) and would offer every online player's name to
 *       anyone typing e.g. {@code /msg }. Dropped for sources below permission level 2;
 *       client-side literal completion is unaffected, ops keep full completion.</li>
 * </ul>
 *
 * <p>Accepted limitation (same honest-client threat model as {@code AntiCheatCheck} and
 * {@code TabListHider}): player-info packets still carry profile names, so a modified
 * client can read them regardless. These blocks close every surface a vanilla-behaving
 * client can reach.</p>
 */
@Mixin(ServerGamePacketListenerImpl.class)
public abstract class ServerGamePacketListenerImplMixin {
    @Shadow
    public ServerPlayer player;

    @Inject(method = "handleEditBook", at = @At("HEAD"), cancellable = true)
    private void eclipse$blockBookEditing(ServerboundEditBookPacket packet, CallbackInfo callbackInfo) {
        callbackInfo.cancel();
    }

    @Inject(method = "handleCustomCommandSuggestions", at = @At("HEAD"), cancellable = true)
    private void eclipse$blockNameSuggestions(
            ServerboundCommandSuggestionPacket packet, CallbackInfo callbackInfo) {
        if (!this.player.hasPermissions(Commands.LEVEL_GAMEMASTERS)) {
            callbackInfo.cancel();
        }
    }
}
