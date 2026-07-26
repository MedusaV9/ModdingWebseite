package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the recipient's current GLITCHZONE sample — which glitch effect owns
 * their screen, how hard, in which accent colour, and where its impulse radiates from
 * ({@code glitchzone.GlitchZoneService} sends it only on meaningful changes, never per
 * tick). Dispatched to {@code client.GlitchZoneFx#handle}.
 *
 * @param effect      one of {@code glitchzone.GlitchZoneEffects#IDS}, or {@code ""} for
 *                    "no zone" (strength is 0 then)
 * @param strength    the 0..1 edge-falloff × fade ramp the client eases toward
 * @param colour      accent colour id from {@code glitchzone.GlitchColors}; {@code ""}
 *                    means "the effect's shipped accent" (F-049)
 * @param originValid whether {@code origin} is meaningful — {@code false} = the effect's
 *                    impulse radiates from the camera, the shipped behaviour
 * @param origin      world position the impulse radiates from when {@code originValid}
 *                    (F-048: the altar block, converted to a camera-relative uniform on
 *                    the client); {@link BlockPos#ZERO} otherwise
 */
public record S2CGlitchZonePayload(String effect, float strength, String colour,
        boolean originValid, BlockPos origin) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CGlitchZonePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/glitch_zone"));

    public static final StreamCodec<ByteBuf, S2CGlitchZonePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CGlitchZonePayload::effect,
            ByteBufCodecs.FLOAT, S2CGlitchZonePayload::strength,
            ByteBufCodecs.STRING_UTF8, S2CGlitchZonePayload::colour,
            ByteBufCodecs.BOOL, S2CGlitchZonePayload::originValid,
            BlockPos.STREAM_CODEC, S2CGlitchZonePayload::origin,
            S2CGlitchZonePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CGlitchZonePayload> type() {
        return TYPE;
    }
}
