package dev.projecteclipse.eclipse.xboxevent;

import java.util.function.Consumer;

import io.netty.buffer.ByteBuf;

import dev.projecteclipse.eclipse.EclipseMod;
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
 * Self-registering payload registrar for the Xbox event (own {@link RegisterPayloadHandlersEvent}
 * subscriber, version group {@value #VERSION} — {@code EclipsePayloads} stays untouched, repo
 * convention per plan §1.5).
 *
 * <p><b>Frozen for P3-W11 (timer overlay, next wave)</b>: {@link S2CXboxTimerPayload} is the
 * server-authoritative countdown snapshot (§2.13.5) — clients derive remaining time as
 * {@code endsAtEpochMillis - (serverNowEpochMillis + millisSinceReceive)} (the clock-offset
 * technique of P3's sidebar). Sent on entry, on every {@code /dev xboxevent time} mutation and
 * every 20 s (drift guard) to players INSIDE the event dimension only, plus one final
 * {@code active=false} on exit. When P3's overlay lands it replies {@link C2SXboxAckPayload}
 * with {@code overlayCapable=true}; the server then hides the W9 bossbar fallback for that
 * client.</p>
 *
 * <p><b>Portal transition seam</b>: the entry/exit glitch payload
 * ({@code S2CPortalFxPayload{style:"eclipse:xbox_glitch", holdTicks:30}}) is OWNED by P3-W11
 * (plan §4.3 — a P5-local duplicate payload id is forbidden). Until it lands, W9 sends nothing:
 * {@link #sendPortalTransition(ServerPlayer)} no-ops unless P3/W11 installs a sender via
 * {@link #setPortalTransitionSender(Consumer)} (see the P5-W9 wiring notes).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class XboxPayloads {
    private static final String VERSION = "xbox1";

    /** Frozen style id P3's {@code PortalTransitionController} switches on (P2 R13 chain). */
    public static final String TRANSITION_STYLE = "eclipse:xbox_glitch";
    /** Frozen hold duration (ticks) covering the dimension change behind black. */
    public static final int TRANSITION_HOLD_TICKS = 30;

    private static volatile Consumer<ServerPlayer> portalTransitionSender;

    private XboxPayloads() {}

    /**
     * Server → client countdown snapshot (schema FROZEN for P3-W11, §2.13.5).
     *
     * @param endsAtEpochMillis    wall-clock end of the event window
     * @param serverNowEpochMillis server wall clock at send time (client clock-offset base)
     * @param worldId              manifest world id ({@code tu1|tu12|tu14})
     * @param active               {@code false} = hide overlay (sent on exit / event end)
     */
    public record S2CXboxTimerPayload(long endsAtEpochMillis, long serverNowEpochMillis,
            String worldId, boolean active) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CXboxTimerPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "xbox/timer"));

        public static final StreamCodec<ByteBuf, S2CXboxTimerPayload> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.VAR_LONG, S2CXboxTimerPayload::endsAtEpochMillis,
                ByteBufCodecs.VAR_LONG, S2CXboxTimerPayload::serverNowEpochMillis,
                ByteBufCodecs.STRING_UTF8, S2CXboxTimerPayload::worldId,
                ByteBufCodecs.BOOL, S2CXboxTimerPayload::active,
                S2CXboxTimerPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CXboxTimerPayload> type() {
            return TYPE;
        }
    }

    /**
     * Client → server overlay capability ack (§2.13.5): {@code overlayCapable=true} hides the
     * bossbar fallback for the sending client. Vanilla/overlay-less clients never send it.
     */
    public record C2SXboxAckPayload(boolean overlayCapable) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<C2SXboxAckPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "xbox/ack"));

        public static final StreamCodec<ByteBuf, C2SXboxAckPayload> STREAM_CODEC =
                ByteBufCodecs.BOOL.map(C2SXboxAckPayload::new, C2SXboxAckPayload::overlayCapable);

        @Override
        public CustomPacketPayload.Type<C2SXboxAckPayload> type() {
            return TYPE;
        }
    }

    /**
     * Client-side cache of the last timer snapshot — pure data, no client classes, so it is
     * dedicated-server-safe. P3-W11's overlay may read this or take over the handling.
     */
    public static final class TimerClientState {
        private static volatile long endsAtEpochMillis;
        private static volatile long clockOffsetMillis;
        private static volatile String worldId = "";
        private static volatile boolean active;

        private TimerClientState() {}

        static void update(S2CXboxTimerPayload payload) {
            endsAtEpochMillis = payload.endsAtEpochMillis();
            clockOffsetMillis = payload.serverNowEpochMillis() - System.currentTimeMillis();
            worldId = payload.worldId();
            active = payload.active();
        }

        public static boolean active() {
            return active;
        }

        public static String worldId() {
            return worldId;
        }

        /** Server-authoritative remaining millis, clamped at 0. */
        public static long remainingMillis() {
            if (!active) {
                return 0L;
            }
            long serverNow = System.currentTimeMillis() + clockOffsetMillis;
            return Math.max(0L, endsAtEpochMillis - serverNow);
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CXboxTimerPayload.TYPE, S2CXboxTimerPayload.STREAM_CODEC,
                XboxPayloads::handleTimer);
        registrar.playToServer(C2SXboxAckPayload.TYPE, C2SXboxAckPayload.STREAM_CODEC,
                XboxPayloads::handleAck);
    }

    private static void handleTimer(S2CXboxTimerPayload payload, IPayloadContext context) {
        TimerClientState.update(payload);
    }

    private static void handleAck(C2SXboxAckPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            XboxEventService.onOverlayAck(player, payload.overlayCapable());
        }
    }

    // ------------------------------------------------------------------ send helpers

    public static void sendTimer(ServerPlayer player, S2CXboxTimerPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    /**
     * Installed by P3-W11 / the W11 integration pass once {@code S2CPortalFxPayload} exists;
     * the sender must transmit {@code {style: TRANSITION_STYLE, holdTicks: TRANSITION_HOLD_TICKS}}.
     */
    public static void setPortalTransitionSender(Consumer<ServerPlayer> sender) {
        portalTransitionSender = sender;
    }

    /** Entry/exit transition trigger; silently no-ops until the P3 sender is installed. */
    public static void sendPortalTransition(ServerPlayer player) {
        Consumer<ServerPlayer> sender = portalTransitionSender;
        if (sender != null) {
            sender.accept(player);
        }
    }
}
