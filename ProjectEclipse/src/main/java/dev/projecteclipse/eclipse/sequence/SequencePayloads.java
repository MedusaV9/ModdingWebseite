package dev.projecteclipse.eclipse.sequence;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering payload registrar of the W6 sequence package (repo pattern from
 * {@code network.fx.FxPayloads} — NeoForge allows any number of registrars, so the frozen
 * {@code EclipsePayloads}/{@code FxPayloads} files stay untouched). One payload:
 *
 * <p>{@link S2CPortalHopPayload} — server-side trigger for W8's frozen client transition
 * ({@code veilfx.TransitionFx.playPortalEnter/Exit}, P2 R13). The limbo → overworld hop of
 * the reworked {@code limbo.StartEventCutscene} sends {@code enter} a moment before the
 * scripted teleport (glitch → hold-black covers the dimension change — the vanilla
 * dimension screen is never the visible surface) and {@code exit} once the players stand
 * on their discs. The client class is resolved lazily inside the handler body so it never
 * loads on a dedicated server.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class SequencePayloads {
    private static final String VERSION = "seq1";

    private SequencePayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CPortalHopPayload.TYPE, S2CPortalHopPayload.STREAM_CODEC,
                SequencePayloads::handlePortalHop);
    }

    /** Sends the enter half of the portal transition (glitch up → fade to black, holds). */
    public static void sendPortalEnter(ServerPlayer player, int ticks) {
        PacketDistributor.sendToPlayer(player, new S2CPortalHopPayload(true, ticks));
    }

    /** Sends the exit half (release the black with a glitch tail-off). */
    public static void sendPortalExit(ServerPlayer player, int ticks) {
        PacketDistributor.sendToPlayer(player, new S2CPortalHopPayload(false, ticks));
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handlePortalHop(S2CPortalHopPayload payload, IPayloadContext context) {
        if (payload.enter()) {
            dev.projecteclipse.eclipse.veilfx.TransitionFx.playPortalEnter(payload.ticks());
        } else {
            dev.projecteclipse.eclipse.veilfx.TransitionFx.playPortalExit(payload.ticks());
        }
    }

    /**
     * Server → client: one half of the R13 glitch/fade portal transition. {@code enter}
     * selects {@code playPortalEnter(ticks)} (fade to black, stays black) vs
     * {@code playPortalExit(ticks)} (release with glitch tail).
     */
    public record S2CPortalHopPayload(boolean enter, int ticks) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CPortalHopPayload> TYPE = new CustomPacketPayload.Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "seq/portal_hop"));

        public static final StreamCodec<ByteBuf, S2CPortalHopPayload> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.BOOL, S2CPortalHopPayload::enter,
                ByteBufCodecs.VAR_INT, S2CPortalHopPayload::ticks,
                S2CPortalHopPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CPortalHopPayload> type() {
            return TYPE;
        }
    }
}
