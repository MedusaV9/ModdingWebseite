package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: one camera-shake impulse of the given {@code strength} decaying over
 * {@code ticks} (W12 — the Ferryman's gunwale slam "tilts the ship" for everyone aboard).
 * The client feeds it into {@code cutscene.client.CameraDirector}'s impulse stack, which
 * shakes both the normal gameplay camera and any active cutscene flight.
 *
 * <p>{@code marked = true} is the Lantern Gaze variant: instead of shaking, the receiving
 * player gets the private purple hunt vignette for {@code ticks}
 * ({@code client.hud.MarkVignetteOverlay}) — only the marked player is ever sent it.</p>
 */
public record S2CShakePayload(float strength, int ticks, boolean marked) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CShakePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "shake"));

    public static final StreamCodec<ByteBuf, S2CShakePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.FLOAT, S2CShakePayload::strength,
            ByteBufCodecs.VAR_INT, S2CShakePayload::ticks,
            ByteBufCodecs.BOOL, S2CShakePayload::marked,
            S2CShakePayload::new);

    /** A plain shake impulse (no mark). */
    public static S2CShakePayload shake(float strength, int ticks) {
        return new S2CShakePayload(strength, ticks, false);
    }

    /** The Lantern Gaze mark: private vignette for {@code ticks}, no camera shake. */
    public static S2CShakePayload mark(int ticks) {
        return new S2CShakePayload(0.0F, ticks, true);
    }

    @Override
    public CustomPacketPayload.Type<S2CShakePayload> type() {
        return TYPE;
    }
}
