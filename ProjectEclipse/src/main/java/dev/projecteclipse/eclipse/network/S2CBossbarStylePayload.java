package dev.projecteclipse.eclipse.network;

import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.UUIDUtil;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: tags one server bossbar (by its {@code BossEvent} UUID) with an Eclipse
 * skin theme, so the client's {@code client.hud.BossbarSkin} cancels + redraws exactly that
 * bar. Sent whenever the server creates a themed {@code ServerBossEvent} (and re-sent to
 * late joiners who are added to a running bar). Bars without a synced theme render vanilla.
 *
 * <p>Themes: {@link #THEME_DAY}, {@link #THEME_GOAL}, {@link #THEME_BOSS} — matching the
 * frame textures under {@code assets/eclipse/textures/gui/bossbar/}.</p>
 */
public record S2CBossbarStylePayload(UUID id, String theme) implements CustomPacketPayload {
    public static final String THEME_DAY = "day";
    public static final String THEME_GOAL = "goal";
    public static final String THEME_BOSS = "boss";

    public static final CustomPacketPayload.Type<S2CBossbarStylePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "bossbar_style"));

    public static final StreamCodec<ByteBuf, S2CBossbarStylePayload> STREAM_CODEC = StreamCodec.composite(
            UUIDUtil.STREAM_CODEC, S2CBossbarStylePayload::id,
            ByteBufCodecs.STRING_UTF8, S2CBossbarStylePayload::theme,
            S2CBossbarStylePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CBossbarStylePayload> type() {
        return TYPE;
    }
}
