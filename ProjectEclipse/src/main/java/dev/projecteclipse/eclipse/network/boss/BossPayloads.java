package dev.projecteclipse.eclipse.network.boss;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the W4 boss-spectacle payloads ({@code GatePayloads}
 * pattern): own MOD-bus {@link RegisterPayloadHandlersEvent} subscriber on the shared
 * registrar version {@code "2"} — {@code EclipsePayloads} and {@code EclipseMod} stay
 * untouched. Payload ids are prefixed {@code eclipse:boss/} and must NOT additionally be
 * registered elsewhere (duplicate registration throws at startup).
 *
 * <p>Client dispatch uses an installable {@link Consumer} hook so this class stays loadable
 * on dedicated servers (no eager client-class references). The client owner
 * ({@code client.hud.BossIntroOverlay}) installs its consumer from its own class
 * initialization; payloads received while no handler is installed are dropped
 * (debug-logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class BossPayloads {
    /** Shared payload registrar version (matches the other self-registrar subpackages). */
    private static final String VERSION = "2";
    /**
     * Intro-card broadcast radius around the summon point — generously past every boss's
     * player-scaling range so anyone approaching the arena still gets the card.
     */
    public static final double INTRO_RANGE = 96.0D;

    private static volatile Consumer<S2CBossIntroPayload> clientIntroHandler;

    private BossPayloads() {}

    /**
     * Boss intro title card (IDEA-16 #1): the client decodes {@code nameKey}'s resolved
     * text from {@code GlitchText} noise over the {@code THEME_BOSS} visual language, with
     * {@code subtitleKey} typed underneath. Both are translation keys — localization
     * happens client-side ({@code EclipseLang}); an empty {@code subtitleKey} shows no
     * subtitle line.
     */
    public record S2CBossIntroPayload(String nameKey, String subtitleKey)
            implements CustomPacketPayload {
        public static final CustomPacketPayload.Type<S2CBossIntroPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss/intro"));

        public static final StreamCodec<ByteBuf, S2CBossIntroPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.STRING_UTF8, S2CBossIntroPayload::nameKey,
                        ByteBufCodecs.STRING_UTF8, S2CBossIntroPayload::subtitleKey,
                        S2CBossIntroPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CBossIntroPayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CBossIntroPayload.TYPE, S2CBossIntroPayload.STREAM_CODEC,
                BossPayloads::handleIntro);
    }

    // ------------------------------------------------------------------ server send helpers

    /**
     * Sends the intro card to every player within {@value #INTRO_RANGE} blocks of the
     * summon/arrival point (call from the boss's summon block, after the arrival FX).
     */
    public static void sendIntro(ServerLevel level, Vec3 center, String nameKey, String subtitleKey) {
        S2CBossIntroPayload payload = new S2CBossIntroPayload(nameKey, subtitleKey);
        double rangeSq = INTRO_RANGE * INTRO_RANGE;
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(center) <= rangeSq) {
                PacketDistributor.sendToPlayer(player, payload);
            }
        }
    }

    // ------------------------------------------------------------------ client dispatch

    /** Installed by {@code client.hud.BossIntroOverlay} (client class-load). */
    public static void setClientIntroHandler(Consumer<S2CBossIntroPayload> handler) {
        clientIntroHandler = handler;
    }

    private static void handleIntro(S2CBossIntroPayload payload, IPayloadContext context) {
        Consumer<S2CBossIntroPayload> handler = clientIntroHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Boss intro payload ({}) — no client handler installed",
                    payload.nameKey());
        }
    }
}
