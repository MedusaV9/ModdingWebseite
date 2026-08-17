package de.sonic0810.goobymod.network;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyTrick;
import java.util.UUID;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S-Auswahl aus dem Trick-Selection-Screen: Gooby-UUID plus Trick-Id.
 *
 * <p>Fixe Groesse (16 Byte UUID + 1 VarInt); die Trick-Id wird beim Decoden
 * strikt validiert. Die eigentliche Autorisierung (Sender, Besitz, lebende
 * Entity, Dimension/Distanz, Erwachsenenstatus, Trainingsstand) passiert
 * ausschliesslich serverseitig in {@link GoobyNetwork#trySelectTrick} —
 * Clientdaten werden nie als vertrauenswuerdig behandelt.</p>
 */
public record TrickSelectPayload(UUID goobyId, GoobyTrick trick) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<TrickSelectPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "trick_select"));

    public static final StreamCodec<FriendlyByteBuf, TrickSelectPayload> STREAM_CODEC =
            StreamCodec.of(TrickSelectPayload::write, TrickSelectPayload::read);

    private static void write(FriendlyByteBuf buf, TrickSelectPayload payload) {
        buf.writeUUID(payload.goobyId);
        buf.writeVarInt(payload.trick.ordinal());
    }

    private static TrickSelectPayload read(FriendlyByteBuf buf) {
        return new TrickSelectPayload(buf.readUUID(), TrickMenuPayload.readValidatedTrick(buf));
    }

    @Override
    public Type<? extends CustomPacketPayload> type() {
        return TYPE;
    }
}
