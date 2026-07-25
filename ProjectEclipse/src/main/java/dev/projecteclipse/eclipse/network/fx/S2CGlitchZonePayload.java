package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the recipient's current GLITCHZONE sample — which glitch effect owns
 * their screen and how hard ({@code glitchzone.GlitchZoneService} sends it only on
 * meaningful changes, never per tick). Dispatched to {@code client.GlitchZoneFx#handle}.
 * {@code effect} is one of {@code glitchzone.GlitchZoneEffects#IDS} or {@code ""} for
 * "no zone" (strength is 0 then); {@code strength} is the 0..1 edge-falloff × fade ramp
 * the client eases toward.
 */
public record S2CGlitchZonePayload(String effect, float strength) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CGlitchZonePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/glitch_zone"));

    public static final StreamCodec<ByteBuf, S2CGlitchZonePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CGlitchZonePayload::effect,
            ByteBufCodecs.FLOAT, S2CGlitchZonePayload::strength,
            S2CGlitchZonePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CGlitchZonePayload> type() {
        return TYPE;
    }
}
