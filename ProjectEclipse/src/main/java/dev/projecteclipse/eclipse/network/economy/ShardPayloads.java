package dev.projecteclipse.eclipse.network.economy;

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
 * D14 (W-SHARDS) — self-registering registrar for the personal shard-gain toast payload
 * (the {@code network.rewards.RewardPayloads} pattern): registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION},
 * so {@code EclipsePayloads.register(...)} stays untouched. Payload ids are prefixed
 * {@code eclipse:economy/} and must NOT additionally be registered in
 * {@code EclipsePayloads}.
 *
 * <p>Sender: {@code economy.ShardEconomy.addShards} — the single personal-balance choke
 * point. Grants whose ceremony is already the {@code RewardMaterializeOverlay}
 * (quest/award shard rewards) suppress this payload via {@code announce=false}, so a gain
 * never celebrates twice. Presentation only: a lost packet costs nothing but the toast
 * (the sidebar aggregate carries the authoritative balance).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ShardPayloads {
    private static final String VERSION = "v5shards1";

    private ShardPayloads() {}

    /**
     * Server → one player: "+{@code delta} Umbrasplitter" hotbar toast with the new
     * PERSONAL balance ({@code newBalance}) — never the team pool, which has its own
     * clearly-labeled altar receipts.
     */
    public record S2CShardGainPayload(int delta, int newBalance) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CShardGainPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "economy/shard_gain"));

        public static final StreamCodec<ByteBuf, S2CShardGainPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CShardGainPayload::delta,
                        ByteBufCodecs.VAR_INT, S2CShardGainPayload::newBalance,
                        S2CShardGainPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CShardGainPayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CShardGainPayload.TYPE, S2CShardGainPayload.STREAM_CODEC,
                ShardPayloads::handleShardGain);
    }

    /** Sends one gain toast to its (online) recipient; non-positive deltas send nothing. */
    public static void sendShardGain(ServerPlayer target, int delta, int newBalance) {
        if (delta <= 0 || target.connection == null) {
            return;
        }
        PacketDistributor.sendToPlayer(target, new S2CShardGainPayload(delta, Math.max(0, newBalance)));
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleShardGain(S2CShardGainPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.economy.ShardGainToast.enqueue(payload);
    }
}
