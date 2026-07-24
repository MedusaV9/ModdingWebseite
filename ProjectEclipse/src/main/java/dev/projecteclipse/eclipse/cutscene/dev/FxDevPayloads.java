package dev.projecteclipse.eclipse.cutscene.dev;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the ONE dev-only payload of {@code /eclipsefx} (P2 R12).
 * Several {@code FxDevCommands} leaves poke purely client-side systems (Veil post pipeline
 * overrides, uniform overrides, Quasar emitter spawns, the sun-debug HUD) — this bridge
 * carries those actions from the server command to the executing player's client without
 * touching the frozen {@code network/fx/FxPayloads} registrar (NeoForge allows any number
 * of payload registrars; same pattern, own version group {@value #VERSION}).
 *
 * <p>The client logic lives in {@code FxDevClient}, referenced fully-qualified inside the
 * handler body so it never loads on a dedicated server.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class FxDevPayloads {
    private static final String VERSION = "fxdev1";

    // Action discriminators (dev-only wire contract, may change freely between versions).
    public static final int ACTION_POST_ON = 0;
    public static final int ACTION_POST_OFF = 1;
    public static final int ACTION_POST_CLEAR = 2;
    public static final int ACTION_POST_LIST = 3;
    /** {@code arg = "<pipeline>|<uniform>"}, {@code value} = the float to force. */
    public static final int ACTION_UNIFORM = 4;
    /** {@code arg} = emitter id, {@code pos} = spawn position. */
    public static final int ACTION_EMITTER = 5;
    /** Toggles the sun-debug HUD cross. */
    public static final int ACTION_SUN_DEBUG = 6;

    private FxDevPayloads() {}

    /** Server → client dev action (see the {@code ACTION_*} discriminators). */
    public record S2CFxDevActionPayload(int action, String arg, Vec3 pos, float value)
            implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CFxDevActionPayload> TYPE = new CustomPacketPayload.Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fxdev/action"));

        public static final StreamCodec<ByteBuf, S2CFxDevActionPayload> STREAM_CODEC = StreamCodec.of(
                (buf, payload) -> {
                    ByteBufCodecs.VAR_INT.encode(buf, payload.action());
                    ByteBufCodecs.STRING_UTF8.encode(buf, payload.arg());
                    buf.writeDouble(payload.pos().x);
                    buf.writeDouble(payload.pos().y);
                    buf.writeDouble(payload.pos().z);
                    buf.writeFloat(payload.value());
                },
                buf -> new S2CFxDevActionPayload(
                        ByteBufCodecs.VAR_INT.decode(buf),
                        ByteBufCodecs.STRING_UTF8.decode(buf),
                        new Vec3(buf.readDouble(), buf.readDouble(), buf.readDouble()),
                        buf.readFloat()));

        @Override
        public CustomPacketPayload.Type<S2CFxDevActionPayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION).optional();
        registrar.playToClient(S2CFxDevActionPayload.TYPE, S2CFxDevActionPayload.STREAM_CODEC,
                FxDevPayloads::handleAction);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleAction(S2CFxDevActionPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.dev.FxDevClient.handle(payload);
    }

    /** Server-side send helper for {@code FxDevCommands}. */
    public static void sendAction(ServerPlayer player, int action, String arg, Vec3 pos, float value) {
        PacketDistributor.sendToPlayer(player, new S2CFxDevActionPayload(action, arg, pos, value));
    }
}
