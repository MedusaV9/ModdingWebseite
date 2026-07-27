package dev.projecteclipse.eclipse.network.credits;

import java.util.function.Consumer;

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
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the C15 final-credits payloads ({@code BossPayloads} /
 * {@code GatePayloads} pattern): own MOD-bus {@link RegisterPayloadHandlersEvent} subscriber
 * under version group {@value #VERSION} — {@code EclipsePayloads} stays untouched. Payload
 * ids are prefixed {@code eclipse:credits/}.
 *
 * <p>Client dispatch uses installable {@link Consumer} hooks so this class stays loadable on
 * dedicated servers (no eager client-class references). The client owner
 * ({@code client.credits.CreditsClient}) installs its consumers from its own class
 * initialization; payloads received while no handler is installed are dropped
 * (debug-logged).</p>
 *
 * <p><b>The nonce contract</b> (IDEAS-backrooms_finale §B3): {@link S2CCreditsBeginPayload}
 * carries the credits instance id; {@link S2CCreditsClosePayload} repeats it. A client that
 * never saw the matching begin (logged in on a different server, joined after a restart)
 * ignores the close — {@code Minecraft.stop()} can only ever fire on a client that sat
 * through this exact credits run.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class CreditsPayloads {
    private static final String VERSION = "credits2";

    private static volatile Consumer<S2CCreditsBeginPayload> beginHandler;
    private static volatile Consumer<S2CCreditsAutoRunPayload> autoRunHandler;
    private static volatile Consumer<S2CCreditsRollPayload> rollHandler;
    private static volatile Consumer<S2CCreditsTitlePayload> titleHandler;
    private static volatile Consumer<S2CCreditsClosePayload> closeHandler;
    private static volatile Consumer<S2CCreditsFovPayload> fovHandler;
    private static volatile Consumer<S2CCreditsSkyPayload> skyHandler;
    private static volatile Consumer<S2CCreditsPulsePayload> pulseHandler;
    private static volatile Consumer<S2CCreditsJetPayload> jetHandler;

    private CreditsPayloads() {}

    // ------------------------------------------------------------------ payloads

    /** Sequence start marker: the client latches {@code nonce} for the later close check. */
    public record S2CCreditsBeginPayload(int nonce) implements CustomPacketPayload {
        public static final Type<S2CCreditsBeginPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/begin"));
        public static final StreamCodec<ByteBuf, S2CCreditsBeginPayload> STREAM_CODEC =
                ByteBufCodecs.VAR_INT.map(S2CCreditsBeginPayload::new, S2CCreditsBeginPayload::nonce);

        @Override
        public Type<S2CCreditsBeginPayload> type() {
            return TYPE;
        }
    }

    /**
     * Forced-walk toggle (IDEAS §B2): {@code active} arms/disarms the client input
     * injection, {@code yawDegrees} is the locked run heading (free ±20° look-around),
     * {@code maxTicks} is the client-side self-expiry watchdog (a lost OFF payload may
     * never leave a player running forever).
     */
    public record S2CCreditsAutoRunPayload(boolean active, float yawDegrees, int maxTicks)
            implements CustomPacketPayload {
        public static final Type<S2CCreditsAutoRunPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/auto_run"));
        public static final StreamCodec<ByteBuf, S2CCreditsAutoRunPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.BOOL, S2CCreditsAutoRunPayload::active,
                        ByteBufCodecs.FLOAT, S2CCreditsAutoRunPayload::yawDegrees,
                        ByteBufCodecs.VAR_INT, S2CCreditsAutoRunPayload::maxTicks,
                        S2CCreditsAutoRunPayload::new);

        @Override
        public Type<S2CCreditsAutoRunPayload> type() {
            return TYPE;
        }
    }

    /**
     * Starts the right-side credits text scroll (IDEAS §B4) over {@code durationTicks}.
     * Line content is client-side: lang keys {@code eclipse.credits.roll.1..N} read until
     * the first missing key. {@code durationTicks <= 0} stops a running scroll.
     */
    public record S2CCreditsRollPayload(int durationTicks) implements CustomPacketPayload {
        public static final Type<S2CCreditsRollPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/roll"));
        public static final StreamCodec<ByteBuf, S2CCreditsRollPayload> STREAM_CODEC =
                ByteBufCodecs.VAR_INT.map(S2CCreditsRollPayload::new, S2CCreditsRollPayload::durationTicks);

        @Override
        public Type<S2CCreditsRollPayload> type() {
            return TYPE;
        }
    }

    /**
     * Full-screen title card ({@code client.credits.TitleCardLayer}): {@code titleKey}
     * arrives in one of three styles — {@link #STYLE_DECODE} decodes from glitch noise
     * (BossIntroOverlay recipe, gold credits theme), {@link #STYLE_GENTLE} (FIN-6 end
     * cards) is a slow, silent fade-in/out over black, and {@link #STYLE_FINALE}
     * (F-072 V3, the "Minecraft Eclipse" closer) MATERIALIZES the title letter by
     * letter out of converging particle dust with a slow kerning breath and a settling
     * chromatic fringe. {@code holdTicks} is the post-arrival hold.
     */
    public record S2CCreditsTitlePayload(String titleKey, int holdTicks, int style)
            implements CustomPacketPayload {
        public static final int STYLE_DECODE = 0;
        public static final int STYLE_GENTLE = 1;
        public static final int STYLE_FINALE = 2;

        public static final Type<S2CCreditsTitlePayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/title"));
        public static final StreamCodec<ByteBuf, S2CCreditsTitlePayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.STRING_UTF8, S2CCreditsTitlePayload::titleKey,
                        ByteBufCodecs.VAR_INT, S2CCreditsTitlePayload::holdTicks,
                        ByteBufCodecs.VAR_INT, S2CCreditsTitlePayload::style,
                        S2CCreditsTitlePayload::new);

        @Override
        public Type<S2CCreditsTitlePayload> type() {
            return TYPE;
        }
    }

    /**
     * FIN-6 eclipse-explosion zoom: the client ramps {@code CameraDirector}'s external
     * FOV multiplier toward {@code targetScale} over {@code rampTicks} (a slow push into
     * the ever-brighter burst). {@code targetScale = 1} with a short ramp resets it.
     */
    public record S2CCreditsFovPayload(float targetScale, int rampTicks) implements CustomPacketPayload {
        public static final Type<S2CCreditsFovPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/fov"));
        public static final StreamCodec<ByteBuf, S2CCreditsFovPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.FLOAT, S2CCreditsFovPayload::targetScale,
                        ByteBufCodecs.VAR_INT, S2CCreditsFovPayload::rampTicks,
                        S2CCreditsFovPayload::new);

        @Override
        public Type<S2CCreditsFovPayload> type() {
            return TYPE;
        }
    }

    /**
     * F-056/F-058 credits sky override ({@code client.credits.CreditsSkyFx}): {@code mode}
     * 0 = OFF (everything eases back to vanilla), 1 = COLLAPSE (the island-shatter beat —
     * the sky darkens toward {@code intensity} and the stars come out), 2 = SPACE (the
     * black-hole finale — pure space dome, dense stars, no sun/moon; {@code intensity}
     * additionally drives the client black-hole layers: the {@code eclipse:black_hole}
     * post distortion/desaturation strength). {@code rampTicks} eases every scalar;
     * {@code holeX/holeY/holeZ} is the black hole's world center (only read in SPACE
     * mode — the post pass projects it to screen space per frame).
     */
    public record S2CCreditsSkyPayload(int mode, float intensity, int rampTicks,
            double holeX, double holeY, double holeZ) implements CustomPacketPayload {
        public static final int MODE_OFF = 0;
        public static final int MODE_COLLAPSE = 1;
        public static final int MODE_SPACE = 2;

        public static final Type<S2CCreditsSkyPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/sky"));
        public static final StreamCodec<ByteBuf, S2CCreditsSkyPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CCreditsSkyPayload::mode,
                        ByteBufCodecs.FLOAT, S2CCreditsSkyPayload::intensity,
                        ByteBufCodecs.VAR_INT, S2CCreditsSkyPayload::rampTicks,
                        ByteBufCodecs.DOUBLE, S2CCreditsSkyPayload::holeX,
                        ByteBufCodecs.DOUBLE, S2CCreditsSkyPayload::holeY,
                        ByteBufCodecs.DOUBLE, S2CCreditsSkyPayload::holeZ,
                        S2CCreditsSkyPayload::new);

        @Override
        public Type<S2CCreditsSkyPayload> type() {
            return TYPE;
        }
    }

    /**
     * F-072 V3 — one black-hole "gulp" impulse ({@code client.credits.CreditsSkyFx}):
     * {@code strength} 0..1 drives a short attack/decay envelope the
     * {@code eclipse:black_hole} post pass reads as its {@code Pulse} uniform — the
     * event horizon swells and the photon rings flare exactly on the server's
     * deterministic swallow beats ({@code CreditsSequence.devourPulse}) and the smaller
     * horizon flashes. Fire-and-forget; a lost packet just skips one flare.
     */
    public record S2CCreditsPulsePayload(float strength) implements CustomPacketPayload {
        public static final Type<S2CCreditsPulsePayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/pulse"));
        public static final StreamCodec<ByteBuf, S2CCreditsPulsePayload> STREAM_CODEC =
                ByteBufCodecs.FLOAT.map(S2CCreditsPulsePayload::new, S2CCreditsPulsePayload::strength);

        @Override
        public Type<S2CCreditsPulsePayload> type() {
            return TYPE;
        }
    }

    /**
     * F-090/F-093 — one black-hole JET burst impulse ({@code client.credits.CreditsSkyFx}):
     * {@code strength} 0..1 drives a second attack/decay envelope the
     * {@code eclipse:black_hole} post pass reads as its {@code JetPulse} uniform — the
     * polar jets FLARE and strobe exactly when {@code CreditsSequence} shreds a
     * sub-plate along the jet axis ({@code CreditsMapRipAct.jetBurst}, paired with the
     * {@code credits4_jetburst} Photon streams). Fire-and-forget like the gulp pulse;
     * a lost packet just skips one strobe.
     */
    public record S2CCreditsJetPayload(float strength) implements CustomPacketPayload {
        public static final Type<S2CCreditsJetPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/jet"));
        public static final StreamCodec<ByteBuf, S2CCreditsJetPayload> STREAM_CODEC =
                ByteBufCodecs.FLOAT.map(S2CCreditsJetPayload::new, S2CCreditsJetPayload::strength);

        @Override
        public Type<S2CCreditsJetPayload> type() {
            return TYPE;
        }
    }

    /**
     * The client-close broadcast (IDEAS §B3): after {@code delayTicks} the client calls
     * {@code Minecraft.stop()} — guarded client-side (nonce match, never in
     * singleplayer/LAN, {@code allowFinaleClose} kill-switch).
     */
    public record S2CCreditsClosePayload(int delayTicks, int nonce) implements CustomPacketPayload {
        public static final Type<S2CCreditsClosePayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits/close"));
        public static final StreamCodec<ByteBuf, S2CCreditsClosePayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CCreditsClosePayload::delayTicks,
                        ByteBufCodecs.VAR_INT, S2CCreditsClosePayload::nonce,
                        S2CCreditsClosePayload::new);

        @Override
        public Type<S2CCreditsClosePayload> type() {
            return TYPE;
        }
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CCreditsBeginPayload.TYPE, S2CCreditsBeginPayload.STREAM_CODEC,
                (payload, context) -> dispatch(beginHandler, payload, "begin"));
        registrar.playToClient(S2CCreditsAutoRunPayload.TYPE, S2CCreditsAutoRunPayload.STREAM_CODEC,
                (payload, context) -> dispatch(autoRunHandler, payload, "auto_run"));
        registrar.playToClient(S2CCreditsRollPayload.TYPE, S2CCreditsRollPayload.STREAM_CODEC,
                (payload, context) -> dispatch(rollHandler, payload, "roll"));
        registrar.playToClient(S2CCreditsTitlePayload.TYPE, S2CCreditsTitlePayload.STREAM_CODEC,
                (payload, context) -> dispatch(titleHandler, payload, "title"));
        registrar.playToClient(S2CCreditsClosePayload.TYPE, S2CCreditsClosePayload.STREAM_CODEC,
                (payload, context) -> dispatch(closeHandler, payload, "close"));
        registrar.playToClient(S2CCreditsFovPayload.TYPE, S2CCreditsFovPayload.STREAM_CODEC,
                (payload, context) -> dispatch(fovHandler, payload, "fov"));
        registrar.playToClient(S2CCreditsSkyPayload.TYPE, S2CCreditsSkyPayload.STREAM_CODEC,
                (payload, context) -> dispatch(skyHandler, payload, "sky"));
        registrar.playToClient(S2CCreditsPulsePayload.TYPE, S2CCreditsPulsePayload.STREAM_CODEC,
                (payload, context) -> dispatch(pulseHandler, payload, "pulse"));
        registrar.playToClient(S2CCreditsJetPayload.TYPE, S2CCreditsJetPayload.STREAM_CODEC,
                (payload, context) -> dispatch(jetHandler, payload, "jet"));
    }

    private static <T extends CustomPacketPayload> void dispatch(Consumer<T> handler, T payload, String name) {
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Credits payload '{}' — no client handler installed", name);
        }
    }

    // ------------------------------------------------------------------ server send helpers

    public static void sendBegin(ServerPlayer player, int nonce) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsBeginPayload(nonce));
    }

    public static void sendAutoRun(ServerPlayer player, boolean active, float yawDegrees, int maxTicks) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsAutoRunPayload(active, yawDegrees, maxTicks));
    }

    public static void sendRoll(ServerPlayer player, int durationTicks) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsRollPayload(durationTicks));
    }

    public static void sendTitle(ServerPlayer player, String titleKey, int holdTicks) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsTitlePayload(
                titleKey, holdTicks, S2CCreditsTitlePayload.STYLE_DECODE));
    }

    /** FIN-6 end card: slow silent fade-in/out instead of the glitch decode. */
    public static void sendGentleTitle(ServerPlayer player, String titleKey, int holdTicks) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsTitlePayload(
                titleKey, holdTicks, S2CCreditsTitlePayload.STYLE_GENTLE));
    }

    /** F-072 V3 closer card: letters materialize from dust, kerning breathes in. */
    public static void sendFinaleTitle(ServerPlayer player, String titleKey, int holdTicks) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsTitlePayload(
                titleKey, holdTicks, S2CCreditsTitlePayload.STYLE_FINALE));
    }

    /** F-072 V3: one black-hole gulp impulse (the post pass's {@code Pulse} envelope). */
    public static void sendPulse(ServerPlayer player, float strength) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsPulsePayload(strength));
    }

    /** F-090/F-093: one jet-burst impulse (the post pass's {@code JetPulse} envelope). */
    public static void sendJet(ServerPlayer player, float strength) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsJetPayload(strength));
    }

    public static void sendClose(ServerPlayer player, int delayTicks, int nonce) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsClosePayload(delayTicks, nonce));
    }

    /** FIN-6: ramp the client FOV multiplier toward {@code targetScale} over {@code rampTicks}. */
    public static void sendFov(ServerPlayer player, float targetScale, int rampTicks) {
        PacketDistributor.sendToPlayer(player, new S2CCreditsFovPayload(targetScale, rampTicks));
    }

    /** F-056/F-058: drive the credits sky override (see {@link S2CCreditsSkyPayload}). */
    public static void sendSky(ServerPlayer player, S2CCreditsSkyPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    // ------------------------------------------------------------------ client dispatch seams

    /** Installed by {@code client.credits.CreditsClient} (client class-load). */
    public static void setClientBeginHandler(Consumer<S2CCreditsBeginPayload> handler) {
        beginHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsAutoRun} (client class-load). */
    public static void setClientAutoRunHandler(Consumer<S2CCreditsAutoRunPayload> handler) {
        autoRunHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsPanel} (client class-load). */
    public static void setClientRollHandler(Consumer<S2CCreditsRollPayload> handler) {
        rollHandler = handler;
    }

    /** Installed by {@code client.credits.TitleCardLayer} (client class-load). */
    public static void setClientTitleHandler(Consumer<S2CCreditsTitlePayload> handler) {
        titleHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsClient} (client class-load). */
    public static void setClientCloseHandler(Consumer<S2CCreditsClosePayload> handler) {
        closeHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsClient} (client class-load). */
    public static void setClientFovHandler(Consumer<S2CCreditsFovPayload> handler) {
        fovHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsSkyFx} (client class-load). */
    public static void setClientSkyHandler(Consumer<S2CCreditsSkyPayload> handler) {
        skyHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsSkyFx} (client class-load). */
    public static void setClientPulseHandler(Consumer<S2CCreditsPulsePayload> handler) {
        pulseHandler = handler;
    }

    /** Installed by {@code client.credits.CreditsSkyFx} (client class-load). */
    public static void setClientJetHandler(Consumer<S2CCreditsJetPayload> handler) {
        jetHandler = handler;
    }
}
