package dev.projecteclipse.eclipse.network.rewards;

import java.util.List;

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
 * W4-CEREMONY / IDEA-11 #1 — self-registering registrar for the reward-materialization
 * payload (the {@code network.hearts.HeartsPayloads} pattern): registers on its own
 * MOD-bus {@link RegisterPayloadHandlersEvent} subscriber under version group
 * {@value #VERSION}, so {@code EclipsePayloads.register(...)} stays untouched. Payload
 * ids are prefixed {@code eclipse:rewards/} and must NOT additionally be registered in
 * {@code EclipsePayloads} (duplicate registration throws at startup).
 *
 * <p>Senders: {@code progression.goals.QuestEngine.grantRewardContents} (the single quest
 * shard/item choke point — also reached by the {@code deliverPendingRewards} login replay,
 * which sets {@code replay=true}) and {@code awards.AwardService.deliverPending} (daily
 * award rewards; login/restart claims are replays, the immediate-online claim after a live
 * resolve is not). skill-XP-only rewards send nothing — the XP strip and
 * {@code LevelUpOverlay} already own that celebration.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RewardPayloads {
    private static final String VERSION = "w4ceremony1";

    /** {@code sourceKind}: quest/goal reward ({@code QuestEngine}). */
    public static final int SOURCE_QUEST = 0;
    /** {@code sourceKind}: daily award reward ({@code AwardService}). */
    public static final int SOURCE_AWARD = 1;

    private RewardPayloads() {}

    // ------------------------------------------------------------------ payload records

    /** One granted item line: registry id + total count (splitting into stacks is client-side). */
    public record ItemEntry(String itemId, int count) {
        public static final StreamCodec<ByteBuf, ItemEntry> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.STRING_UTF8, ItemEntry::itemId,
                        ByteBufCodecs.VAR_INT, ItemEntry::count,
                        ItemEntry::new);
    }

    /**
     * Server → one rewarded player: "these items/shards just landed in your inventory" —
     * the client materializes the stack ({@code client.rewards.RewardMaterializeOverlay}).
     * {@code replay=true} marks login-replay deliveries (queued offline rewards): the client
     * plays the calm fade-only variant, mirroring the {@code AwardsOverlay}
     * {@code LATE_JOIN_GRACE_TICKS} rule. Carries no source names (anonymity law); the
     * actual grant already happened server-side — this is presentation only, so a lost
     * packet costs nothing but the flourish.
     */
    public record S2CRewardGrantPayload(List<ItemEntry> items, int shards, int sourceKind,
            boolean replay) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CRewardGrantPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rewards/grant"));

        public static final StreamCodec<ByteBuf, S2CRewardGrantPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ItemEntry.STREAM_CODEC.apply(ByteBufCodecs.list()), S2CRewardGrantPayload::items,
                        ByteBufCodecs.VAR_INT, S2CRewardGrantPayload::shards,
                        ByteBufCodecs.VAR_INT, S2CRewardGrantPayload::sourceKind,
                        ByteBufCodecs.BOOL, S2CRewardGrantPayload::replay,
                        S2CRewardGrantPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CRewardGrantPayload> type() {
            return TYPE;
        }
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CRewardGrantPayload.TYPE, S2CRewardGrantPayload.STREAM_CODEC,
                RewardPayloads::handleRewardGrant);
    }

    // ------------------------------------------------------------------ server send helper

    /** Sends one reward materialization to its (online) recipient; empty grants send nothing. */
    public static void sendRewardGrant(ServerPlayer target, List<ItemEntry> items, int shards,
            int sourceKind, boolean replay) {
        if ((items == null || items.isEmpty()) && shards <= 0) {
            return; // xp-only / empty rewards have nothing to materialize
        }
        PacketDistributor.sendToPlayer(target,
                new S2CRewardGrantPayload(List.copyOf(items == null ? List.of() : items),
                        shards, sourceKind, replay));
    }

    // ------------------------------------------------------------------ client dispatch

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleRewardGrant(S2CRewardGrantPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.rewards.RewardMaterializeOverlay.enqueue(payload);
    }
}
