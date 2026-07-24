package dev.projecteclipse.eclipse.network.bestiary;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the receiving player's FULL bestiary knowledge snapshot (W4-BESTIARY),
 * sent by {@code progression.bestiary.BestiaryService} on login and on every progress
 * change. Byte-lean by construction: one entry per mob the player has ANY knowledge of
 * (T0 ids are simply absent — the client defaults to unseen), each entry a bare
 * {@code (path, varint count, byte tier)} triple with the {@code eclipse:} namespace
 * implied. A typical late-game snapshot is ~18 entries ≈ 350 bytes.
 *
 * <p>{@code tierUpId} is non-empty exactly when this send was caused by a tier-up — the
 * client cache plays the unlock sting + action-bar caption for it ({@code tierUpTier} =
 * the tier just reached). Plain syncs (login, mid-tier kill counts) leave it empty.</p>
 *
 * <p>Registered by {@link BestiaryPayloads} (own registrar — NOT {@code EclipsePayloads});
 * the client side hooks in via {@code BestiaryPayloads.setClientHandler}
 * ({@code client.progression.ClientBestiaryCache}).</p>
 */
public record S2CBestiaryPayload(List<Entry> entries, String tierUpId, byte tierUpTier)
        implements CustomPacketPayload {

    /** One mob's knowledge: registry path (ns implied), lifetime count, derived tier. */
    public record Entry(String id, int count, byte tier) {}

    public static final CustomPacketPayload.Type<S2CBestiaryPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "bestiary/sync"));

    public static final StreamCodec<ByteBuf, S2CBestiaryPayload> STREAM_CODEC =
            StreamCodec.of(S2CBestiaryPayload::write, S2CBestiaryPayload::read);

    private static void write(ByteBuf buf, S2CBestiaryPayload payload) {
        ByteBufCodecs.VAR_INT.encode(buf, payload.entries.size());
        for (Entry entry : payload.entries) {
            ByteBufCodecs.STRING_UTF8.encode(buf, entry.id());
            ByteBufCodecs.VAR_INT.encode(buf, entry.count());
            buf.writeByte(entry.tier());
        }
        ByteBufCodecs.STRING_UTF8.encode(buf, payload.tierUpId);
        buf.writeByte(payload.tierUpTier);
    }

    private static S2CBestiaryPayload read(ByteBuf buf) {
        int size = ByteBufCodecs.VAR_INT.decode(buf);
        List<Entry> entries = new ArrayList<>(size);
        for (int i = 0; i < size; i++) {
            String id = ByteBufCodecs.STRING_UTF8.decode(buf);
            int count = ByteBufCodecs.VAR_INT.decode(buf);
            byte tier = buf.readByte();
            entries.add(new Entry(id, count, tier));
        }
        String tierUpId = ByteBufCodecs.STRING_UTF8.decode(buf);
        byte tierUpTier = buf.readByte();
        return new S2CBestiaryPayload(entries, tierUpId, tierUpTier);
    }

    @Override
    public CustomPacketPayload.Type<S2CBestiaryPayload> type() {
        return TYPE;
    }
}
