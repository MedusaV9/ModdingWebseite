package de.sonic0810.goobymod.network;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyTrick;
import io.netty.handler.codec.DecoderException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * S2C-Menuedaten fuer den nativen Trick-Selection-Screen: Gooby-Identitaet,
 * aktuelle Auswahl und pro Kunststueck Sterne/Trainingsstand/Unlock-Status.
 *
 * <p>Der Codec ist hart gebounded und fail-closed: der Name ist auf
 * {@link #MAX_NAME_LENGTH} Zeichen begrenzt, jede Trick-Id wird gegen
 * {@link GoobyTrick#byIdStrict(int)} geprueft, die Eintragsliste muss exakt
 * einen Eintrag pro Kunststueck in Enum-Reihenfolge enthalten und Sterne
 * liegen in {@code [0, MAX_TRICK_PROFICIENCY]}. Alles andere wirft eine
 * {@link DecoderException} statt still auf Defaults zurueckzufallen.</p>
 */
public record TrickMenuPayload(UUID goobyId, String goobyName, GoobyTrick selected,
        List<TrickEntry> entries) implements CustomPacketPayload {

    public static final int MAX_NAME_LENGTH = 64;

    public static final CustomPacketPayload.Type<TrickMenuPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "trick_menu"));

    public static final StreamCodec<FriendlyByteBuf, TrickMenuPayload> STREAM_CODEC =
            StreamCodec.of(TrickMenuPayload::write, TrickMenuPayload::read);

    /** Ein Menue-Eintrag: Kunststueck, Trainingssterne und Freischalt-Status. */
    public record TrickEntry(GoobyTrick trick, int stars, boolean unlocked) {
    }

    /** Deterministische Momentaufnahme des Servers — Eintraege in Enum-Reihenfolge. */
    public static TrickMenuPayload of(GoobyEntity gooby) {
        List<TrickEntry> entries = new ArrayList<>(GoobyTrick.values().length);
        for (GoobyTrick trick : GoobyTrick.values()) {
            int stars = gooby.getTrickProficiency(trick);
            entries.add(new TrickEntry(trick, stars, stars > 0));
        }
        return new TrickMenuPayload(gooby.getUUID(), truncateName(gooby.getName().getString()),
                gooby.getSelectedTrick(), List.copyOf(entries));
    }

    /**
     * Kuerzt auf {@link #MAX_NAME_LENGTH} UTF-16-Einheiten, aber codepoint-
     * sicher: es wird nie mitten in einem Surrogate-Paar geschnitten, damit
     * kein unpaariges Surrogate im Payload landet (Netty wuerde es als
     * {@code ?} encoden und der Roundtrip waere nicht mehr byte-treu).
     */
    private static String truncateName(String name) {
        if (name.length() <= MAX_NAME_LENGTH) {
            return name;
        }
        int cut = MAX_NAME_LENGTH;
        if (Character.isHighSurrogate(name.charAt(cut - 1))) {
            cut--;
        }
        return name.substring(0, cut);
    }

    private static void write(FriendlyByteBuf buf, TrickMenuPayload payload) {
        buf.writeUUID(payload.goobyId);
        buf.writeUtf(payload.goobyName, MAX_NAME_LENGTH);
        buf.writeVarInt(payload.selected.ordinal());
        buf.writeVarInt(payload.entries.size());
        for (TrickEntry entry : payload.entries) {
            buf.writeVarInt(entry.trick.ordinal());
            buf.writeByte(entry.stars);
            buf.writeBoolean(entry.unlocked);
        }
    }

    private static TrickMenuPayload read(FriendlyByteBuf buf) {
        UUID goobyId = buf.readUUID();
        String goobyName = buf.readUtf(MAX_NAME_LENGTH);
        GoobyTrick selected = readValidatedTrick(buf);
        int count = buf.readVarInt();
        GoobyTrick[] tricks = GoobyTrick.values();
        if (count != tricks.length) {
            throw new DecoderException("Gooby trick menu must carry exactly "
                    + tricks.length + " entries, got " + count);
        }
        List<TrickEntry> entries = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            GoobyTrick trick = readValidatedTrick(buf);
            if (trick.ordinal() != i) {
                throw new DecoderException("Gooby trick menu entries out of order: expected "
                        + tricks[i] + " at index " + i + ", got " + trick);
            }
            int stars = buf.readByte();
            if (stars < 0 || stars > GoobyEntity.MAX_TRICK_PROFICIENCY) {
                throw new DecoderException("Gooby trick stars out of bounds: " + stars);
            }
            boolean unlocked = buf.readBoolean();
            entries.add(new TrickEntry(trick, stars, unlocked));
        }
        return new TrickMenuPayload(goobyId, goobyName, selected, List.copyOf(entries));
    }

    /** Liest eine Trick-Id und lehnt unbekannte Ordinals fail-closed ab. */
    static GoobyTrick readValidatedTrick(FriendlyByteBuf buf) {
        int id = buf.readVarInt();
        GoobyTrick trick = GoobyTrick.byIdStrict(id);
        if (trick == null) {
            throw new DecoderException("Unknown Gooby trick id: " + id);
        }
        return trick;
    }

    @Override
    public Type<? extends CustomPacketPayload> type() {
        return TYPE;
    }
}
