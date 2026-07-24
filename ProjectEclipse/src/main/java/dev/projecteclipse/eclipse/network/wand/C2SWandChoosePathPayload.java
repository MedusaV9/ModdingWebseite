package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S "lock my wand onto this path" request ({@code eclipse:wand/choose_path}), sent by
 * the client path chooser ({@code client/wand/WandPathScreen}). Server-side
 * {@code wand/WandPowers.handleChoosePath} validates: a wand is held, the sender owns it,
 * and its path is still NONE (the first choice is final — stale/forged requests are
 * silently dropped).
 *
 * @param pathId {@code WandPath} wire id (1 riss / 2 glut / 3 stern; 0 is refused)
 */
public record C2SWandChoosePathPayload(int pathId) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SWandChoosePathPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/choose_path"));

    public static final StreamCodec<io.netty.buffer.ByteBuf, C2SWandChoosePathPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.VAR_INT, C2SWandChoosePathPayload::pathId,
                    C2SWandChoosePathPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SWandChoosePathPayload> type() {
        return TYPE;
    }
}
