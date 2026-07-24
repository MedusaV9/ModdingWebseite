package dev.projecteclipse.eclipse.backrooms;

import java.util.function.Consumer;

import io.netty.buffer.ByteBuf;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
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
 * Self-registering payload registrar for the Backrooms event (the {@code XboxPayloads}/
 * {@code GatePayloads} pattern: own MOD-bus {@link RegisterPayloadHandlersEvent} subscriber,
 * version group {@value #VERSION} — {@code EclipsePayloads} stays untouched).
 *
 * <p><b>Jumpscare</b> (IDEAS §A4): {@link S2CJumpscarePayload} is fired by
 * {@code BackroomsScare} at most once per player per instance. Client dispatch goes through
 * an installable {@link Consumer} hook so this class stays loadable on dedicated servers;
 * {@code client.backrooms.JumpscareOverlay} installs its consumer from class init (the
 * {@code PortalTransitionController} seam pattern). The overlay owns the {@code reducedFx}
 * split — the payload itself is identical for both presentation variants.</p>
 *
 * <p><b>Portal transition</b>: unlike W9's xbox seam (which predated the payload), P3's
 * {@code S2CPortalFxPayload} EXISTS now, so {@link #sendPortalTransition(ServerPlayer)}
 * sends it directly with the C18 style id {@value #TRANSITION_STYLE}. Unknown style ids
 * render {@code PortalTransitionController}'s default look — the pale-yellow tint variant
 * is the documented C16/C18 coordination point (see
 * {@code docs/plans_v3/plans_v5/PORTAL_RECIPE.md}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class BackroomsPayloads {
    private static final String VERSION = "backrooms1";

    /** C18 portal style id (the "no-clipping…" transition). */
    public static final String TRANSITION_STYLE = "eclipse:backrooms_noclip";
    /** Hold duration covering the dimension change (the frozen xbox value). */
    public static final int TRANSITION_HOLD_TICKS = 30;

    private static volatile Consumer<S2CJumpscarePayload> clientJumpscareHandler;

    private BackroomsPayloads() {}

    /**
     * Server → client: play THE jumpscare envelope (IDEAS §A4 — 0.8 s single fade, face
     * overlay ≤ 0.85 alpha + sting + one shake impulse; {@code reducedFx} clients render
     * the vignette+sound fallback instead).
     *
     * @param intensity 0..1 presentation scale (1.0 = the designed envelope)
     */
    public record S2CJumpscarePayload(float intensity) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CJumpscarePayload> TYPE =
                new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
                        EclipseMod.MOD_ID, "backrooms/jumpscare"));

        public static final StreamCodec<ByteBuf, S2CJumpscarePayload> STREAM_CODEC =
                ByteBufCodecs.FLOAT.map(S2CJumpscarePayload::new, S2CJumpscarePayload::intensity);

        @Override
        public CustomPacketPayload.Type<S2CJumpscarePayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CJumpscarePayload.TYPE, S2CJumpscarePayload.STREAM_CODEC,
                BackroomsPayloads::handleJumpscare);
    }

    private static void handleJumpscare(S2CJumpscarePayload payload, IPayloadContext context) {
        Consumer<S2CJumpscarePayload> handler = clientJumpscareHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Jumpscare payload — no client handler installed");
        }
    }

    // ------------------------------------------------------------------ send helpers

    public static void sendJumpscare(ServerPlayer player, float intensity) {
        PacketDistributor.sendToPlayer(player, new S2CJumpscarePayload(intensity));
    }

    /** Entry/exit transition cover; call right BEFORE the teleport (P3 §3.11 contract). */
    public static void sendPortalTransition(ServerPlayer player) {
        GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(
                S2CPortalFxPayload.Phase.ENTER, TRANSITION_STYLE, TRANSITION_HOLD_TICKS));
    }

    /** Installed by {@code client.backrooms.JumpscareOverlay} on client class-load. */
    public static void setClientJumpscareHandler(Consumer<S2CJumpscarePayload> handler) {
        clientJumpscareHandler = handler;
    }
}
