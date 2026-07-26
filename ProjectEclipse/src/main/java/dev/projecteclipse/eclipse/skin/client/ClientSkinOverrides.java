package dev.projecteclipse.eclipse.skin.client;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.blaze3d.platform.NativeImage;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CSkinOverridePayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.texture.DynamicTexture;
import net.minecraft.client.resources.PlayerSkin;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client half of F-050/F-051: assembles the chunked {@link S2CSkinOverridePayload} stream,
 * uploads each finished PNG as a {@link DynamicTexture} and answers the skin lookup that
 * {@code client.mixin.AbstractClientPlayerMixin} performs for every rendered player.
 *
 * <p>Because the override is served by the mod, it works for ANY player entity without a
 * Mojang-signed profile texture — the {@link PlayerSkin} handed out here is marked
 * {@code secure} so the client treats it like a normal, allowed skin.</p>
 *
 * <p>Referenced from {@code network.EclipsePayloads} only inside a play-to-client handler
 * body (and from a client mixin), so the dedicated server never classloads it.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ClientSkinOverrides {
    private static final Map<UUID, PlayerSkin> SKINS = new HashMap<>();
    private static final Map<UUID, Assembly> PENDING = new HashMap<>();

    private ClientSkinOverrides() {}

    /** Chunks in flight for one player; payload order on a connection is guaranteed. */
    private static final class Assembly {
        private final byte[][] parts;
        private int received;

        Assembly(int chunkCount) {
            this.parts = new byte[chunkCount][];
        }
    }

    /**
     * The lookup used by the {@code AbstractClientPlayer#getSkin} hook. Null means "no
     * override" — the anonymity uniform skin then applies as usual.
     */
    @Nullable
    public static PlayerSkin get(UUID player) {
        return SKINS.get(player);
    }

    /** Main-thread payload handler (reset marker or one image chunk). */
    public static void handle(S2CSkinOverridePayload payload) {
        if (payload.reset()) {
            PENDING.remove(payload.player());
            release(payload.player());
            return;
        }
        if (payload.chunkCount() <= 0 || payload.chunkIndex() < 0
                || payload.chunkIndex() >= payload.chunkCount()) {
            EclipseMod.LOGGER.warn("Discarding malformed skin chunk {}/{} for {}",
                    payload.chunkIndex(), payload.chunkCount(), payload.player());
            return;
        }
        Assembly assembly = payload.chunkIndex() == 0
                ? new Assembly(payload.chunkCount())
                : PENDING.get(payload.player());
        if (assembly == null || assembly.parts.length != payload.chunkCount()) {
            // A resend started mid-stream (relog, second /dev skin) — wait for its chunk 0.
            PENDING.remove(payload.player());
            return;
        }
        if (assembly.parts[payload.chunkIndex()] == null) {
            assembly.received++;
        }
        assembly.parts[payload.chunkIndex()] = payload.chunk();
        PENDING.put(payload.player(), assembly);
        if (assembly.received < assembly.parts.length) {
            return;
        }
        PENDING.remove(payload.player());
        install(payload.player(), join(assembly), payload.slim());
    }

    private static byte[] join(Assembly assembly) {
        int total = 0;
        for (byte[] part : assembly.parts) {
            total += part.length;
        }
        byte[] png = new byte[total];
        int offset = 0;
        for (byte[] part : assembly.parts) {
            System.arraycopy(part, 0, png, offset, part.length);
            offset += part.length;
        }
        return png;
    }

    private static void install(UUID player, byte[] png, boolean slim) {
        NativeImage image;
        try {
            image = NativeImage.read(png);
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Skin override for {} is not a readable PNG — ignored", player, e);
            return;
        }
        ResourceLocation location = textureId(player);
        Minecraft minecraft = Minecraft.getInstance();
        // Re-registering replaces (and closes) the previous texture under the same id, so a
        // second /dev skin on the same player does not leak a GL handle.
        minecraft.getTextureManager().register(location, new DynamicTexture(image));
        SKINS.put(player, new PlayerSkin(location, null, null, null,
                slim ? PlayerSkin.Model.SLIM : PlayerSkin.Model.WIDE, true));
    }

    private static void release(UUID player) {
        if (SKINS.remove(player) != null) {
            Minecraft.getInstance().getTextureManager().release(textureId(player));
        }
    }

    private static ResourceLocation textureId(UUID player) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skins/" + player);
    }

    /** Overrides are per-server state: leaving one must not carry skins into the next. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        PENDING.clear();
        for (UUID player : Map.copyOf(SKINS).keySet()) {
            release(player);
        }
        SKINS.clear();
    }
}
