package dev.projecteclipse.eclipse.client.wand;

import java.util.UUID;

import net.minecraft.ChatFormatting;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.PlayerInfo;
import net.minecraft.network.chat.Component;

/**
 * Client-only tooltip helpers for the wand ({@code EclipseWandItem#appendHoverText}
 * reaches in via a lazily-loaded fully-qualified reference — never class-loaded on a
 * dedicated server). Resolves the soulbind owner's display name from the tab list; owners
 * that are offline (or on another server) fall back to a neutral "bound" line rather than
 * leaking a raw UUID.
 */
public final class WandClientHints {
    private WandClientHints() {}

    /** Tooltip line naming the soulbind owner (or a neutral fallback when unresolvable). */
    public static Component ownerLine(UUID owner) {
        Minecraft minecraft = Minecraft.getInstance();
        String name = null;
        if (minecraft.player != null && owner.equals(minecraft.player.getUUID())) {
            name = minecraft.player.getGameProfile().getName();
        } else if (minecraft.getConnection() != null) {
            PlayerInfo info = minecraft.getConnection().getPlayerInfo(owner);
            if (info != null) {
                name = info.getProfile().getName();
            }
        }
        return (name != null
                ? Component.translatable("wand.eclipse.tooltip.owner", name)
                : Component.translatable("wand.eclipse.tooltip.owner_offline"))
                .withStyle(ChatFormatting.DARK_GRAY);
    }
}
