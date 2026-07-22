package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * One server-driven announcement ({@code docs/ideas/03_ui_ux.md} §E): the client plays a
 * typewriter line above the hotbar (then posts the finished line to chat once) plus a
 * client-local themed bossbar sweep showing the title. Both keys are translation keys —
 * localization happens client-side; an empty {@code subtitleKey} means "type the title".
 *
 * <p>{@code style} selects the sweep's skin theme and accent: {@value #STYLE_DAY},
 * {@value #STYLE_UNLOCK}, {@value #STYLE_GOAL} or {@value #STYLE_BOSS}.</p>
 */
public record S2CAnnouncePayload(String titleKey, String subtitleKey, String style)
        implements CustomPacketPayload {
    public static final String STYLE_DAY = "day";
    public static final String STYLE_UNLOCK = "unlock";
    public static final String STYLE_GOAL = "goal";
    public static final String STYLE_BOSS = "boss";

    public static final CustomPacketPayload.Type<S2CAnnouncePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "announce"));

    public static final StreamCodec<ByteBuf, S2CAnnouncePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CAnnouncePayload::titleKey,
            ByteBufCodecs.STRING_UTF8, S2CAnnouncePayload::subtitleKey,
            ByteBufCodecs.STRING_UTF8, S2CAnnouncePayload::style,
            S2CAnnouncePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CAnnouncePayload> type() {
        return TYPE;
    }
}
