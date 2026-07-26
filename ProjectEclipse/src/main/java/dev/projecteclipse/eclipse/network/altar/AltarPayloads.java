package dev.projecteclipse.eclipse.network.altar;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.ritual.AltarAdminState;
import dev.projecteclipse.eclipse.ritual.AltarBlockEntity;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * ALTARUI (task 1) — self-registering registrar for the altar panel screen
 * (the {@code network.economy.ShardPayloads} pattern): registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION},
 * so {@code EclipsePayloads.register(...)} stays untouched. Payload ids are prefixed
 * {@code eclipse:altar/} and must NOT additionally be registered in {@code EclipsePayloads}.
 *
 * <p><b>Flow:</b> a plain (non-sneak, empty-hand) right-click on the altar sends one
 * {@link S2CAltarPanelPayload} with {@code openScreen=true} ({@code AltarBlock#useWithoutItem}
 * → {@link #sendPanel}); the client opens {@code client.altar.AltarScreen}. While the screen
 * is open it polls {@link C2SAltarPanelRequestPayload} every couple of seconds (other
 * players' deposits change milestone progress — the server does not track open screens),
 * and buys through {@link C2SAltarBuyPayload}; both answer with a refreshed
 * {@code openScreen=false} snapshot.</p>
 *
 * <p><b>Anti-spoiler contract (task 1, tightened by AUDITFIX-3):</b> the payload only ever
 * carries CURRENT-stage data — the hungering milestone's costs/progress/unlock keys
 * (already public via the Wave-5 A5 {@code S2CMilestonesPayload} reveal rule), the shop
 * table reduced to offers purchasable TODAY, and one server-chosen {@code bossHintId}.
 * Nothing about later stages or later days leaves the server: not-yet-unlocked offers
 * ride along ONLY as the opaque {@link Header#sealedOffers()} count (no id, no name, no
 * price, no unlock day), which the client renders as inert "???" placeholder rows.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AltarPayloads {
    /** Bumped to v2 when AUDITFIX-3 changed the ShopEntry/Header wire shape. */
    private static final String VERSION = "v5altarui2";
    /** Server-side reach check for panel requests and purchases (blocks, squared). */
    private static final double INTERACT_RANGE_SQ = 8.0D * 8.0D;

    /** {@code bossHintId} values the client maps to instruction text blocks. */
    public static final String BOSS_HINT_NONE = "none";
    public static final String BOSS_HINT_HERALD = "herald";
    public static final String BOSS_HINT_HERALD_DONE = "herald_done";
    public static final String BOSS_HINT_FERRYMAN = "ferryman";
    public static final String BOSS_HINT_FERRYMAN_DONE = "ferryman_done";

    private AltarPayloads() {}

    /** One live requirement line of the CURRENT milestone: item, needed count, banked count. */
    public record Requirement(String itemId, int required, long progress) {
        public static final StreamCodec<ByteBuf, Requirement> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.STRING_UTF8, Requirement::itemId,
                ByteBufCodecs.VAR_INT, Requirement::required,
                ByteBufCodecs.VAR_LONG, Requirement::progress,
                Requirement::new);
    }

    /**
     * One CURRENTLY PURCHASABLE shop row; {@code remainingSeconds > 0} shows the running
     * Double-XP countdown on its row. AUDITFIX-3: day-locked offers are never transmitted
     * (they ride only as the opaque {@link Header#sealedOffers()} count) and dev-disabled
     * offers are never sent at all.
     */
    public record ShopEntry(String offerId, String nameKey, int cost, boolean pooled,
            int remainingSeconds) {
        public static final StreamCodec<ByteBuf, ShopEntry> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.STRING_UTF8, ShopEntry::offerId,
                ByteBufCodecs.STRING_UTF8, ShopEntry::nameKey,
                ByteBufCodecs.VAR_INT, ShopEntry::cost,
                ByteBufCodecs.BOOL, ShopEntry::pooled,
                ByteBufCodecs.VAR_INT, ShopEntry::remainingSeconds,
                ShopEntry::new);
    }

    /**
     * Scalar panel state ({@code completed} = ladder finished; {@code sealed} = /dev altar
     * lock; {@code sealedOffers} = how many not-yet-unlocked shop offers exist — AUDITFIX-3:
     * their identity stays server-side, the client only renders that many "???" rows).
     */
    public record Header(int day, int altarLevel, boolean completed, boolean sealed,
            int personalShards, int poolShards, String bossHintId, int sealedOffers) {
        // 8 fields — past the 6-component composite() ceiling, so encode/decode by hand
        // (argument evaluation order is left-to-right, matching the write order).
        public static final StreamCodec<ByteBuf, Header> STREAM_CODEC = StreamCodec.of(
                (buf, header) -> {
                    ByteBufCodecs.VAR_INT.encode(buf, header.day());
                    ByteBufCodecs.VAR_INT.encode(buf, header.altarLevel());
                    ByteBufCodecs.BOOL.encode(buf, header.completed());
                    ByteBufCodecs.BOOL.encode(buf, header.sealed());
                    ByteBufCodecs.VAR_INT.encode(buf, header.personalShards());
                    ByteBufCodecs.VAR_INT.encode(buf, header.poolShards());
                    ByteBufCodecs.STRING_UTF8.encode(buf, header.bossHintId());
                    ByteBufCodecs.VAR_INT.encode(buf, header.sealedOffers());
                },
                buf -> new Header(
                        ByteBufCodecs.VAR_INT.decode(buf),
                        ByteBufCodecs.VAR_INT.decode(buf),
                        ByteBufCodecs.BOOL.decode(buf),
                        ByteBufCodecs.BOOL.decode(buf),
                        ByteBufCodecs.VAR_INT.decode(buf),
                        ByteBufCodecs.VAR_INT.decode(buf),
                        ByteBufCodecs.STRING_UTF8.decode(buf),
                        ByteBufCodecs.VAR_INT.decode(buf)));
    }

    /** Server → one player: full altar-panel snapshot; {@code openScreen} opens the UI. */
    public record S2CAltarPanelPayload(BlockPos pos, boolean openScreen, Header header,
            List<Requirement> requirements, List<String> unlockKeys, List<ShopEntry> offers)
            implements CustomPacketPayload {

        public S2CAltarPanelPayload {
            requirements = List.copyOf(requirements);
            unlockKeys = List.copyOf(unlockKeys);
            offers = List.copyOf(offers);
        }

        public static final CustomPacketPayload.Type<S2CAltarPanelPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar/panel"));

        public static final StreamCodec<ByteBuf, S2CAltarPanelPayload> STREAM_CODEC =
                StreamCodec.composite(
                        BlockPos.STREAM_CODEC, S2CAltarPanelPayload::pos,
                        ByteBufCodecs.BOOL, S2CAltarPanelPayload::openScreen,
                        Header.STREAM_CODEC, S2CAltarPanelPayload::header,
                        Requirement.STREAM_CODEC.apply(ByteBufCodecs.list()),
                        S2CAltarPanelPayload::requirements,
                        ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()),
                        S2CAltarPanelPayload::unlockKeys,
                        ShopEntry.STREAM_CODEC.apply(ByteBufCodecs.list()),
                        S2CAltarPanelPayload::offers,
                        S2CAltarPanelPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CAltarPanelPayload> type() {
            return TYPE;
        }
    }

    /** Client → server: "the panel at {@code pos} is open — send me a fresh snapshot". */
    public record C2SAltarPanelRequestPayload(BlockPos pos) implements CustomPacketPayload {
        public static final CustomPacketPayload.Type<C2SAltarPanelRequestPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar/panel_request"));

        public static final StreamCodec<ByteBuf, C2SAltarPanelRequestPayload> STREAM_CODEC =
                StreamCodec.composite(
                        BlockPos.STREAM_CODEC, C2SAltarPanelRequestPayload::pos,
                        C2SAltarPanelRequestPayload::new);

        @Override
        public CustomPacketPayload.Type<C2SAltarPanelRequestPayload> type() {
            return TYPE;
        }
    }

    /** Client → server: buy {@code offerId} from the panel at {@code pos}. */
    public record C2SAltarBuyPayload(BlockPos pos, String offerId) implements CustomPacketPayload {
        public static final CustomPacketPayload.Type<C2SAltarBuyPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar/buy"));

        public static final StreamCodec<ByteBuf, C2SAltarBuyPayload> STREAM_CODEC =
                StreamCodec.composite(
                        BlockPos.STREAM_CODEC, C2SAltarBuyPayload::pos,
                        ByteBufCodecs.STRING_UTF8, C2SAltarBuyPayload::offerId,
                        C2SAltarBuyPayload::new);

        @Override
        public CustomPacketPayload.Type<C2SAltarBuyPayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CAltarPanelPayload.TYPE, S2CAltarPanelPayload.STREAM_CODEC,
                AltarPayloads::handlePanel);
        registrar.playToServer(C2SAltarPanelRequestPayload.TYPE, C2SAltarPanelRequestPayload.STREAM_CODEC,
                AltarPayloads::handlePanelRequest);
        registrar.playToServer(C2SAltarBuyPayload.TYPE, C2SAltarBuyPayload.STREAM_CODEC,
                AltarPayloads::handleBuy);
    }

    // ------------------------------------------------------------------ server → client

    /**
     * Assembles and sends the panel snapshot for the altar at {@code altarPos}.
     * {@code openScreen=true} for the initial right-click, {@code false} for refreshes.
     */
    public static void sendPanel(ServerPlayer player, BlockPos altarPos, boolean openScreen) {
        if (player.connection == null) {
            return;
        }
        PacketDistributor.sendToPlayer(player, buildPanel(player, altarPos, openScreen));
    }

    private static S2CAltarPanelPayload buildPanel(ServerPlayer player, BlockPos altarPos, boolean openScreen) {
        MinecraftServer server = player.server;
        EclipseWorldState state = EclipseWorldState.get(server);
        int day = state.getDay();
        EclipseConfig.Milestone next = EclipseConfig.milestone(state.getAltarLevel() + 1);

        List<Requirement> requirements = new ArrayList<>();
        List<String> unlockKeys = List.of();
        if (next != null) {
            for (EclipseConfig.ItemCost cost : next.cost()) {
                long progress = state.getMilestoneProgress(
                        AltarBlockEntity.progressKey(next, cost.item()));
                requirements.add(new Requirement(cost.item(), cost.count(),
                        Math.min(progress, cost.count())));
            }
            unlockKeys = next.rewards();
        }

        List<ShopEntry> offers = new ArrayList<>();
        int sealedOffers = 0;
        int doubleXpRemaining = ShardEconomy.doubleXpRemainingSeconds(server);
        for (ShardEconomy.Offer offer : ShardEconomy.allOffers()) {
            if (!ShardEconomy.isOfferEnabled(server, offer)) {
                continue; // dev-disabled: gone, not even a sealed slot (AltarAdminState contract)
            }
            if (!offer.availableOnDay(day)) {
                if (offer.maxDay() > 0 && day > offer.maxDay()) {
                    continue; // expired window: it will never unlock again — hide it
                }
                // AUDITFIX-3 anti-spoiler: a not-yet-unlocked offer leaves the server as
                // NOTHING but +1 on this opaque counter — no id, no name, no price, no day.
                sealedOffers++;
                continue;
            }
            offers.add(new ShopEntry(offer.id(), offer.nameKey(), offer.cost(), offer.pooled(),
                    "double_xp".equals(offer.id()) ? doubleXpRemaining : 0));
        }

        Header header = new Header(day, state.getAltarLevel(), next == null,
                AltarAdminState.get(server).isProgressionLocked(),
                ShardEconomy.getShards(player), state.getShardPool(),
                bossHintId(state, next), sealedOffers);
        return new S2CAltarPanelPayload(altarPos, openScreen, header, requirements, unlockKeys, offers);
    }

    /**
     * Task 2: the server picks WHICH boss instruction block the panel shows, so the
     * client never needs future-stage knowledge. Herald instructions appear once the
     * CURRENT milestone demands a Herald Core or the boss's day (7) has come; the
     * Ferryman's only on finale day 14+. Defeated bosses collapse to their "done" line.
     */
    private static String bossHintId(EclipseWorldState state, EclipseConfig.Milestone next) {
        if (state.isFerrymanDefeated()) {
            return BOSS_HINT_FERRYMAN_DONE;
        }
        if (state.getDay() >= 14) {
            return BOSS_HINT_FERRYMAN;
        }
        if (!state.isHeraldDefeated()) {
            boolean nextNeedsCore = false;
            if (next != null) {
                for (EclipseConfig.ItemCost cost : next.cost()) {
                    if ("eclipse:herald_core".equals(cost.item())) {
                        nextNeedsCore = true;
                        break;
                    }
                }
            }
            return nextNeedsCore || state.getDay() >= 7 ? BOSS_HINT_HERALD : BOSS_HINT_NONE;
        }
        return BOSS_HINT_HERALD_DONE;
    }

    // ------------------------------------------------------------------ client → server

    /** Reach + block sanity: the payload pos must be a loaded altar within interaction range. */
    private static boolean validAltar(ServerPlayer player, BlockPos pos) {
        return player.position().distanceToSqr(Vec3.atCenterOf(pos)) <= INTERACT_RANGE_SQ
                && player.level().isLoaded(pos)
                && player.level().getBlockEntity(pos) instanceof AltarBlockEntity;
    }

    private static void handlePanelRequest(C2SAltarPanelRequestPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player && validAltar(player, payload.pos())) {
            sendPanel(player, payload.pos(), false);
        }
    }

    private static void handleBuy(C2SAltarBuyPayload payload, IPayloadContext context) {
        if (!(context.player() instanceof ServerPlayer player) || !validAltar(player, payload.pos())) {
            return;
        }
        ShardEconomy.buyById(player, payload.offerId(), payload.pos());
        // Win or refuse, answer with a fresh snapshot so the panel reflects reality.
        sendPanel(player, payload.pos(), false);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handlePanel(S2CAltarPanelPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.altar.AltarScreen.handlePanel(payload);
    }
}
