package dev.projecteclipse.eclipse.network.gate;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client portal/dimension-hop transition trigger (P3 §3.11 / §7.3, owner W11).
 * Drives {@code client.loading.PortalTransitionController}'s full-screen glitch → fade-to-black
 * → fade-in choreography around a cross-dimension teleport. Senders transmit it right
 * <em>before</em> the teleport (the ordered play stream guarantees the client sees it before
 * the respawn packet — see {@code xboxevent.XboxEventService}).
 *
 * <ul>
 *   <li>{@link Phase#ENTER} — start the choreography: glitch up, fade to black, hold the black
 *       through the dimension change; the controller releases on its own once the destination
 *       level is received (defensive timeouts included). This is the phase normal senders use.</li>
 *   <li>{@link Phase#HOLD} — refresh/extend an active black hold (optional; keeps a slow
 *       teleport covered without restarting the glitch ramp).</li>
 *   <li>{@link Phase#EXIT} — force the fade-in release now (optional; the controller usually
 *       self-releases on level receipt).</li>
 * </ul>
 *
 * @param phase     choreography phase to apply
 * @param styleId   transition style, e.g. {@code XboxPayloads.TRANSITION_STYLE}
 *                  ({@code "eclipse:xbox_glitch"}); unknown styles render the default look
 * @param holdTicks expected teleport cover time in ticks (frozen xbox value: 30); the
 *                  controller treats it as a minimum hold before its no-screen fallback release
 */
public record S2CPortalFxPayload(Phase phase, String styleId, int holdTicks)
        implements CustomPacketPayload {

    /** Choreography phase. Wire format is the ordinal byte; unknown values decode as ENTER. */
    public enum Phase {
        ENTER, HOLD, EXIT;

        static Phase byId(int id) {
            Phase[] values = values();
            return id >= 0 && id < values.length ? values[id] : ENTER;
        }
    }

    public static final CustomPacketPayload.Type<S2CPortalFxPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "gate/portal_fx"));

    public static final StreamCodec<ByteBuf, S2CPortalFxPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.idMapper(Phase::byId, Phase::ordinal), S2CPortalFxPayload::phase,
            ByteBufCodecs.STRING_UTF8, S2CPortalFxPayload::styleId,
            ByteBufCodecs.VAR_INT, S2CPortalFxPayload::holdTicks,
            S2CPortalFxPayload::new);

    @Override
    public Type<S2CPortalFxPayload> type() {
        return TYPE;
    }
}
