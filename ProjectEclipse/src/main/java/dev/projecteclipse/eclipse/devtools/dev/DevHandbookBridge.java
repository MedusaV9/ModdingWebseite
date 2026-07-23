package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.function.BiConsumer;

import net.minecraft.server.level.ServerPlayer;

/**
 * Optional hook for P5-W2 to open the Dev Handbook GUI from {@code /dev} (bare).
 * When no opener is registered, {@link DevRoot} falls back to chat help.
 */
public final class DevHandbookBridge {
    private static BiConsumer<ServerPlayer, List<DevCommandDoc>> opener;

    private DevHandbookBridge() {}

    /** Called once by P5-W2 during client/server payload registration. */
    public static void setOpener(BiConsumer<ServerPlayer, List<DevCommandDoc>> handler) {
        opener = handler;
    }

    /**
     * @return {@code true} if a handbook GUI was opened; {@code false} if the caller should fall back
     */
    public static boolean tryOpenHandbook(ServerPlayer player, List<DevCommandDoc> entries) {
        if (opener == null) {
            return false;
        }
        opener.accept(player, entries);
        return true;
    }
}
