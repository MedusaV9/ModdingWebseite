package dev.projecteclipse.eclipse.network.paper;

import java.util.List;
import java.util.UUID;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.UUIDUtil;
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
 * WAVE6 (F-106 C) — C5 "Morning Paper": self-registering registrar for the late-riser
 * recap payload ({@code CreditsPayloads}/{@code BossPayloads} pattern — own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION};
 * {@code EclipsePayloads} and the frozen {@code ClientStateCache} stay untouched).
 *
 * <p><b>Why a new payload instead of a {@code recap} flag on
 * {@code S2CAwardRevealPayload}:</b> the reveal payload is routed through the frozen hub
 * ({@code EclipsePayloads.handleAwardReveal} → {@code ClientStateCache.awardRevealDay}) —
 * a flag would either have to survive that cache (a FROZEN-zone write) or bypass it with a
 * second handler for the same type. A compact dedicated payload delivers straight to the
 * paper renderer, ships ~1% of the reveal's bytes (no candidate lists, no stat/reward
 * lines) and leaves the versioned reveal contract byte-identical for every other
 * sender/receiver pair.</p>
 *
 * <p><b>Anonymity (R5)</b> is preserved: winner rows carry UUIDs only — the client shows
 * the localized YOU marker for the local player and glitch shimmer for everyone else.
 * Today's decree lines are deliberately NOT in the payload: the login quest-state sync
 * ({@code S2CQuestStatePayload}) has already cached them client-side.</p>
 *
 * <p>Client dispatch uses an installable {@link Consumer} hook so this class stays
 * loadable on dedicated servers; {@code client.awards.DecreesCard} installs its consumer
 * from its client-only class initialization. Payloads received while no handler is
 * installed are dropped (debug-logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class MorningPaperPayloads {
    private static final String VERSION = "paper1";

    private static volatile Consumer<S2CMorningPaperPayload> paperHandler;

    private MorningPaperPayloads() {}

    // ------------------------------------------------------------------ payload

    /**
     * One anonymized winner row of the recap: the award category title (bilingual
     * literals, R2 anti-datamining convention) plus the winning UUIDs.
     */
    public record WinnerRow(String titleEn, String titleDe, List<UUID> winners) {
        public WinnerRow {
            winners = List.copyOf(winners);
        }

        public static final StreamCodec<ByteBuf, WinnerRow> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.STRING_UTF8, WinnerRow::titleEn,
                ByteBufCodecs.STRING_UTF8, WinnerRow::titleDe,
                UUIDUtil.STREAM_CODEC.apply(ByteBufCodecs.list()), WinnerRow::winners,
                WinnerRow::new);
    }

    /**
     * Server → client: compact "you slept through the ceremony" recap for logins after a
     * rollover. {@code day} is the CURRENT day, {@code awardsDay} the recapped (resolved)
     * one; {@code dayTitle} is the receiver-localized day title
     * ({@code TimelineService.dayTitleKey(day, player)} — either a baked literal or a
     * generic lang key the client resolves itself).
     */
    public record S2CMorningPaperPayload(int day, int awardsDay, String dayTitle,
            List<WinnerRow> winners) implements CustomPacketPayload {
        public S2CMorningPaperPayload {
            winners = List.copyOf(winners);
        }

        public static final Type<S2CMorningPaperPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "paper/morning"));
        public static final StreamCodec<ByteBuf, S2CMorningPaperPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CMorningPaperPayload::day,
                        ByteBufCodecs.VAR_INT, S2CMorningPaperPayload::awardsDay,
                        ByteBufCodecs.STRING_UTF8, S2CMorningPaperPayload::dayTitle,
                        WinnerRow.STREAM_CODEC.apply(ByteBufCodecs.list()),
                        S2CMorningPaperPayload::winners,
                        S2CMorningPaperPayload::new);

        @Override
        public Type<S2CMorningPaperPayload> type() {
            return TYPE;
        }
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CMorningPaperPayload.TYPE, S2CMorningPaperPayload.STREAM_CODEC,
                (payload, context) -> {
                    Consumer<S2CMorningPaperPayload> handler = paperHandler;
                    if (handler != null) {
                        handler.accept(payload);
                    } else {
                        EclipseMod.LOGGER.debug("Morning paper payload — no client handler installed");
                    }
                });
    }

    // ------------------------------------------------------------------ seams

    /** Server send helper ({@code AwardService.onPlayerLoggedIn}). */
    public static void sendPaper(ServerPlayer player, S2CMorningPaperPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    /** Installed by {@code client.awards.DecreesCard} (client class-load). */
    public static void setClientPaperHandler(Consumer<S2CMorningPaperPayload> handler) {
        paperHandler = handler;
    }
}
