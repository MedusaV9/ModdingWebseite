package de.sonic0810.goobymod.network;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.client.GoobyClientHooks;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyTrick;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Custom-Payload-Layer fuer den nativen Trick-Selection-Screen.
 *
 * <p>Beide Handler laufen auf dem Main-Thread (NeoForge-Default). Der
 * S2C-Handler laedt {@link GoobyClientHooks} erst beim Ausfuehren — auf einem
 * Dedicated Server wird der Client-Pfad nie betreten und damit auch keine
 * Client-Klasse geladen (gleiches Lazy-Muster wie beim Handbuch-Item).</p>
 *
 * <p>Sicherheits-Invarianten der C2S-Auswahl (fail-closed, niemals
 * Clientdaten vertrauen): Sender ist ein echter {@link ServerPlayer}; die
 * Ziel-Entity wird nur in dessen eigener Dimension aufgeloest, muss ein
 * lebender Gooby sein, dem Sender gehoeren, erwachsen sein, innerhalb
 * {@link #TRICK_MENU_RANGE} Bloecken stehen und das Kunststueck trainiert
 * haben. Ablehnungs-Feedback geht ausschliesslich an den Sender (kein
 * Broadcast, keine Paket-Amplifikation), und alle spieler-initiierten
 * Anfragen — C2S-Payload wie {@code /goobytrick} — laufen durch dieselbe
 * Drosselung: hoechstens eine verarbeitete Anfrage pro
 * {@link #SELECT_COOLDOWN_TICKS} Ticks und Spieler, Spam wird still
 * verworfen. Die Wiederholung der bereits aktiven Auswahl ist ein stiller
 * No-op ohne Sounds oder Partikel.</p>
 */
@EventBusSubscriber(modid = GoobyMod.MODID)
public final class GoobyNetwork {
    /** Payload-Protokollversion — bei inkompatiblen Aenderungen erhoehen. */
    public static final String PROTOCOL_VERSION = "1";
    /** Maximale Distanz (Bloecke) fuer Menue-Oeffnung UND Auswahl-Validierung. */
    public static final double TRICK_MENU_RANGE = 64.0;
    /** Mindestabstand (Ticks) zwischen zwei verarbeiteten Auswahl-Anfragen pro Spieler. */
    public static final int SELECT_COOLDOWN_TICKS = 10;
    /** Hartes Limit des Throttle-Speichers — darueber fliegt der aelteste Sender (LRU). */
    public static final int MAX_TRACKED_SELECT_SENDERS = 256;

    /**
     * Tick der letzten verarbeiteten Auswahl-Anfrage pro Sender. Zugriff nur
     * vom Server-Main-Thread (Payload-Handler, Commands und Lifecycle-Events
     * laufen dort), daher unsynchronisiert. Streng gedeckeltes LRU; zusaetzlich
     * raeumen Logout und Server-Stop auf (siehe GoobyEvents). Reiner
     * Laufzeitzustand — wird nie persistiert.
     */
    private static final Map<UUID, Integer> LAST_SELECT_TICK =
            new LinkedHashMap<>(16, 0.75F, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<UUID, Integer> eldest) {
                    return size() > MAX_TRACKED_SELECT_SENDERS;
                }
            };

    /** Ergebnis der serverseitigen Auswahl-Autorisierung (testbar ohne Netz). */
    public enum SelectResult {
        SUCCESS,
        /** Auswahl entspricht bereits dem aktiven Kunststueck — stiller No-op. */
        UNCHANGED,
        /** Anfrage im Cooldown-Fenster — still verworfen, keinerlei Feedback. */
        THROTTLED,
        INVALID_TARGET,
        NOT_OWNER,
        BABY,
        TOO_FAR,
        UNTRAINED;

        public boolean accepted() {
            return this == SUCCESS || this == UNCHANGED;
        }
    }

    @SubscribeEvent
    public static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(PROTOCOL_VERSION);
        registrar.playToClient(TrickMenuPayload.TYPE, TrickMenuPayload.STREAM_CODEC,
                (payload, context) -> GoobyClientHooks.openTrickScreen(payload));
        registrar.playToServer(TrickSelectPayload.TYPE, TrickSelectPayload.STREAM_CODEC,
                (payload, context) -> {
                    if (context.player() instanceof ServerPlayer serverPlayer) {
                        handleSelectRequest(serverPlayer, payload.goobyId(), payload.trick());
                    }
                });
    }

    /**
     * Verschickt die Menuedaten an den Spieler. Clients ohne den Mod-Kanal
     * (z.&nbsp;B. eingebettete Testspieler) erhalten als Fallback das alte
     * klickbare Chat-Menue, das ueber {@code /goobytrick} funktioniert.
     */
    public static void sendTrickMenu(ServerPlayer player, GoobyEntity gooby) {
        TrickMenuPayload payload = TrickMenuPayload.of(gooby);
        if (player.connection != null && player.connection.hasChannel(payload)) {
            PacketDistributor.sendToPlayer(player, payload);
        } else {
            gooby.sendTrickMenu(player);
        }
    }

    /**
     * Gedrosselter Einstiegspunkt fuer ALLE spieler-initiierten Auswahl-Anfragen
     * (C2S-Payload und {@code /goobytrick}). Anfragen im Cooldown-Fenster werden
     * still verworfen: kein Feedback, kein Broadcast, kein Zustandswechsel.
     */
    public static SelectResult handleSelectRequest(ServerPlayer player, UUID goobyId,
            GoobyTrick trick) {
        int now = player.serverLevel().getServer().getTickCount();
        if (!tryAcquireSelectBudget(player.getUUID(), now)) {
            return SelectResult.THROTTLED;
        }
        return trySelectTrick(player, goobyId, trick);
    }

    /**
     * Verbraucht das Auswahl-Budget eines Senders, wenn seit der letzten
     * verarbeiteten Anfrage mindestens {@link #SELECT_COOLDOWN_TICKS} Ticks
     * vergangen sind. Gedrosselte Anfragen verlaengern das Fenster NICHT,
     * damit legitime Eingaben nie dauerhaft ausgesperrt werden. Oeffentlich
     * nur fuer GameTests; ausschliesslich Main-Thread.
     */
    public static boolean tryAcquireSelectBudget(UUID senderId, int gameTick) {
        Integer last = LAST_SELECT_TICK.get(senderId);
        if (last != null && gameTick - last < SELECT_COOLDOWN_TICKS) {
            return false;
        }
        LAST_SELECT_TICK.put(senderId, gameTick);
        return true;
    }

    /** Entfernt den Throttle-Eintrag eines Senders (Logout-Cleanup, GameTests). */
    public static void forgetSelectSender(UUID senderId) {
        LAST_SELECT_TICK.remove(senderId);
    }

    /** Leert den gesamten Throttle-Speicher (Server-Stop). */
    public static void clearSelectThrottle() {
        LAST_SELECT_TICK.clear();
    }

    /** Anzahl aktuell verfolgter Sender — fuer den Map-Bound-GameTest. */
    public static int trackedSelectSenderCount() {
        return LAST_SELECT_TICK.size();
    }

    /**
     * Serverseitige Autorisierung der C2S-Auswahl, OHNE Drosselung — Netzwerk
     * und Command muessen durch {@link #handleSelectRequest} gehen. Wird von
     * GameTests direkt aufgerufen.
     */
    public static SelectResult trySelectTrick(ServerPlayer player, UUID goobyId, GoobyTrick trick) {
        // getEntity() sucht nur in der Dimension des Senders — Cross-Dimension-
        // Anfragen enden hier fail-closed als unbekanntes Ziel.
        Entity entity = player.serverLevel().getEntity(goobyId);
        if (!(entity instanceof GoobyEntity gooby) || !gooby.isAlive()) {
            return deny(player, SelectResult.INVALID_TARGET,
                    Component.translatable("msg.goobymod.trick_menu_invalid"));
        }
        if (!gooby.isOwnedBy(player)) {
            return deny(player, SelectResult.NOT_OWNER,
                    Component.translatable("msg.goobymod.trick_menu_invalid"));
        }
        if (gooby.isBaby()) {
            return deny(player, SelectResult.BABY,
                    Component.translatable("msg.goobymod.baby_no_tricks"));
        }
        if (player.distanceToSqr(gooby) > TRICK_MENU_RANGE * TRICK_MENU_RANGE) {
            return deny(player, SelectResult.TOO_FAR,
                    Component.translatable("msg.goobymod.trick_menu_too_far", gooby.getName()));
        }
        if (gooby.getTrickProficiency(trick) == 0) {
            return deny(player, SelectResult.UNTRAINED,
                    Component.translatable("msg.goobymod.trick_untrained",
                            Component.translatable(trick.translationKey())));
        }
        if (trick == gooby.getSelectedTrick()) {
            // Idempotente Wiederholung: kein Sound, keine Partikel, kein Broadcast.
            return SelectResult.UNCHANGED;
        }
        gooby.selectTrick(player, trick);
        player.serverLevel().sendParticles(ParticleTypes.HAPPY_VILLAGER,
                gooby.getX(), gooby.getY() + 1.2, gooby.getZ(), 6, 0.4, 0.35, 0.4, 0.03);
        return SelectResult.SUCCESS;
    }

    private static SelectResult deny(ServerPlayer player, SelectResult result, Component message) {
        player.displayClientMessage(message, true);
        // Nur der Sender hoert die Ablehnung — kein Broadcast an Umstehende,
        // also auch keine Paket-/Sound-Amplifikation durch Anfrage-Spam.
        player.playNotifySound(ModSounds.GOOBY_WHISTLE_DENIED.get(),
                SoundSource.PLAYERS, 0.6F, 1.0F);
        return result;
    }

    private GoobyNetwork() {
    }
}
