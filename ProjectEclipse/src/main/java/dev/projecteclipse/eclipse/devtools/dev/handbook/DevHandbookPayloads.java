package dev.projecteclipse.eclipse.devtools.dev.handbook;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.ConfigRefEntry;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import dev.projecteclipse.eclipse.devtools.dev.DevHandbookBridge;
import dev.projecteclipse.eclipse.devtools.dev.DevReload;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.Style;
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
 * Self-registering payload pair for the Dev Handbook GUI (P5-W2, §2.2) — same pattern as
 * {@code network.growth.GrowthPayloads}: registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION}, so
 * {@code EclipsePayloads} and {@code EclipseMod} stay untouched. Payload ids are prefixed
 * {@code eclipse:devhandbook/}.
 *
 * <p>Flow: {@code /dev} (bare) → {@link dev.projecteclipse.eclipse.devtools.dev.DevRoot} calls
 * {@link DevHandbookBridge#tryOpenHandbook} → the opener installed here sends
 * {@link S2CDevHandbookPayload} (entries already permission-filtered by the registry) → the
 * client caches + opens {@code DevHandbookScreen}. The screen refreshes itself (open, F5,
 * post-reload) via {@link C2SDevHandbookRequestPayload}, whose server handler re-checks
 * permission ≥ 2 and silently drops non-op requests — non-ops receive ZERO registry data.</p>
 *
 * <p>The opener is installed from the payload-registration event (common, both dists), NOT
 * from client setup: on a dedicated server there is no client setup, but the opener must run
 * there to serve remote ops. Vanilla/unmodded clients (no {@code eclipse:devhandbook/sync}
 * channel) get a chat pointer to {@code /dev help} instead — {@code hasChannel} guards the
 * send, so they are never kicked by an unknown payload.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class DevHandbookPayloads {
    private static final String VERSION = "devhandbook1";

    private DevHandbookPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CDevHandbookPayload.TYPE, S2CDevHandbookPayload.STREAM_CODEC,
                DevHandbookPayloads::handleSync);
        registrar.playToServer(C2SDevHandbookRequestPayload.TYPE, C2SDevHandbookRequestPayload.STREAM_CODEC,
                DevHandbookPayloads::handleRequest);
        DevHandbookBridge.setOpener(DevHandbookPayloads::sendHandbook);
    }

    // ------------------------------------------------------------------ server side

    /**
     * Bridge opener + request-handler core: ships the permission-filtered registry snapshot
     * and the config reference table to one op's client.
     */
    private static void sendHandbook(ServerPlayer player, List<DevCommandDoc> entries) {
        if (!player.connection.hasChannel(S2CDevHandbookPayload.TYPE)) {
            // Vanilla / unmodded client: never send an unknown payload; point at the chat listing.
            player.sendSystemMessage(Component
                    .translatableWithFallback("dev.eclipse.handbook.no_client",
                            "The Dev Handbook needs the Eclipse client — use /dev help instead.")
                    .withStyle(Style.EMPTY.withClickEvent(
                            new ClickEvent(ClickEvent.Action.RUN_COMMAND, "/dev help"))));
            return;
        }
        PacketDistributor.sendToPlayer(player,
                new S2CDevHandbookPayload(entries, DevReload.configReferences()));
    }

    /**
     * Client refresh request (screen open / F5 / after {@code /dev reload}). Op-gated
     * server-side: permission &lt; 2 is silently ignored — no error, no data, zero information.
     */
    private static void handleRequest(C2SDevHandbookRequestPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player && player.hasPermissions(2)) {
            sendHandbook(player, DevCommandRegistry.visibleTo(player));
        }
    }

    // ------------------------------------------------------------------ client dispatch

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleSync(S2CDevHandbookPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.devtools.dev.handbook.DevHandbookClient.handleSync(payload);
    }

    // ------------------------------------------------------------------ payloads

    /**
     * Server → client: the serialized dev-command registry (permission-filtered for the
     * receiving op) plus the {@link DevReload#configReferences()} table for the Configs tab.
     * Docs are re-materialized as {@link DevCommandDoc} records client-side; the client
     * resolves {@code descKey}/category/danger lang keys itself (both langs ship in the jar).
     */
    public record S2CDevHandbookPayload(List<DevCommandDoc> entries, List<ConfigRefEntry> configRefs)
            implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CDevHandbookPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "devhandbook/sync"));

        public static final StreamCodec<ByteBuf, S2CDevHandbookPayload> STREAM_CODEC =
                StreamCodec.of(S2CDevHandbookPayload::write, S2CDevHandbookPayload::read);

        private static void write(ByteBuf buf, S2CDevHandbookPayload payload) {
            ByteBufCodecs.VAR_INT.encode(buf, payload.entries.size());
            for (DevCommandDoc doc : payload.entries) {
                ByteBufCodecs.STRING_UTF8.encode(buf, doc.id());
                ByteBufCodecs.VAR_INT.encode(buf, doc.category().ordinal());
                ByteBufCodecs.STRING_UTF8.encode(buf, doc.syntax());
                ByteBufCodecs.STRING_UTF8.encode(buf, doc.descKey());
                buf.writeByte(doc.danger().ordinal());
                buf.writeByte(doc.clickAction().ordinal());
                buf.writeByte(doc.permission());
                buf.writeBoolean(doc.legacy());
            }
            ByteBufCodecs.VAR_INT.encode(buf, payload.configRefs.size());
            for (ConfigRefEntry ref : payload.configRefs) {
                ByteBufCodecs.STRING_UTF8.encode(buf, ref.file());
                ByteBufCodecs.STRING_UTF8.encode(buf, ref.purposeKey());
                ByteBufCodecs.STRING_UTF8.encode(buf, ref.layerKey());
                ByteBufCodecs.VAR_INT.encode(buf, ref.reloadStep());
            }
        }

        private static S2CDevHandbookPayload read(ByteBuf buf) {
            int entryCount = ByteBufCodecs.VAR_INT.decode(buf);
            List<DevCommandDoc> entries = new ArrayList<>(entryCount);
            for (int i = 0; i < entryCount; i++) {
                String id = ByteBufCodecs.STRING_UTF8.decode(buf);
                DevCategory category = enumByOrdinal(DevCategory.values(),
                        ByteBufCodecs.VAR_INT.decode(buf), DevCategory.LEGACY);
                String syntax = ByteBufCodecs.STRING_UTF8.decode(buf);
                String descKey = ByteBufCodecs.STRING_UTF8.decode(buf);
                Danger danger = enumByOrdinal(Danger.values(), buf.readByte(), Danger.SAFE);
                ClickAction clickAction = enumByOrdinal(ClickAction.values(), buf.readByte(), ClickAction.SUGGEST);
                int permission = buf.readByte();
                boolean legacy = buf.readBoolean();
                entries.add(new DevCommandDoc(id, category, syntax, descKey, danger, clickAction,
                        permission, legacy));
            }
            int refCount = ByteBufCodecs.VAR_INT.decode(buf);
            List<ConfigRefEntry> refs = new ArrayList<>(refCount);
            for (int i = 0; i < refCount; i++) {
                refs.add(new ConfigRefEntry(
                        ByteBufCodecs.STRING_UTF8.decode(buf),
                        ByteBufCodecs.STRING_UTF8.decode(buf),
                        ByteBufCodecs.STRING_UTF8.decode(buf),
                        ByteBufCodecs.VAR_INT.decode(buf)));
            }
            return new S2CDevHandbookPayload(List.copyOf(entries), List.copyOf(refs));
        }

        private static <E extends Enum<E>> E enumByOrdinal(E[] values, int ordinal, E fallback) {
            return ordinal >= 0 && ordinal < values.length ? values[ordinal] : fallback;
        }

        @Override
        public CustomPacketPayload.Type<S2CDevHandbookPayload> type() {
            return TYPE;
        }
    }

    /** Client → server: "(re)send me the handbook data". Carries nothing; op-gated in the handler. */
    public record C2SDevHandbookRequestPayload() implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<C2SDevHandbookRequestPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "devhandbook/request"));

        public static final StreamCodec<ByteBuf, C2SDevHandbookRequestPayload> STREAM_CODEC =
                StreamCodec.unit(new C2SDevHandbookRequestPayload());

        @Override
        public CustomPacketPayload.Type<C2SDevHandbookRequestPayload> type() {
            return TYPE;
        }
    }
}
