package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.night.NightPayloads;
import dev.projecteclipse.eclipse.network.night.S2CNightEventPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * WAVE6 (F-106 A) A1 — the client-side night-event blackboard: one static field synced
 * by {@link S2CNightEventPayload} (consumer seam installed on class-load, the
 * {@code ClientBestiaryCache} pattern). This is the state {@code client/sky/
 * OverworldPurpleEffects} (A2 Umbral moon / Pale bleach), {@code client/sky/StarField}
 * (A3 star dimming) and {@code client/entity/stalker/UmbralNightGlowLayer} (A7 emissive
 * boost) read — deliberately NOT a {@code ClientStateCache} field (that file is
 * W6-frozen, plan §6).
 *
 * <p>All getters are overworld-gated: the Limbo sky shares the {@code StarField} mesh
 * class and the End/arena dimensions must never inherit an overworld night grade, so
 * {@link #mode()} reports {@code none} outside {@code minecraft:overworld} while the
 * raw synced value stays parked for the return trip.</p>
 *
 * <p>Probe: {@code [w6a-nightsync] event=<e> day=<d> (login|nightfall|dawn)} — the
 * first sync of a session is the login re-send by construction; afterwards
 * {@code none} means dawn, anything else nightfall (matches the server's own origin
 * tags on the broadcast lane).</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class NightDreadFx {
    /** Last synced event ({@code EclipseWorldState.NIGHT_EVENT_*} vocabulary). */
    private static volatile String activeEvent = EclipseWorldState.NIGHT_EVENT_NONE;
    /** Day stamp the event was rolled on (0 until first sync). */
    private static volatile int eventDay;
    /** False until the first payload after connect — that one is the login sync. */
    private static boolean syncedThisSession;

    static {
        // Payload consumer seam (BestiaryPayloads pattern): installed on client class-load.
        NightPayloads.setClientHandler(NightDreadFx::handle);
    }

    private NightDreadFx() {}

    /** True while an Umbral Night runs AND the camera is in the overworld. */
    public static boolean isUmbral() {
        return EclipseWorldState.NIGHT_EVENT_UMBRAL.equals(activeEvent) && inOverworld();
    }

    /** True while a Pale Night runs AND the camera is in the overworld. */
    public static boolean isPale() {
        return EclipseWorldState.NIGHT_EVENT_PALE.equals(activeEvent) && inOverworld();
    }

    /** {@code umbral|pale|none} — overworld-gated (reports {@code none} elsewhere). */
    public static String mode() {
        return inOverworld() ? activeEvent : EclipseWorldState.NIGHT_EVENT_NONE;
    }

    /** Day stamp of the synced event (0 before the first sync). */
    public static int eventDay() {
        return eventDay;
    }

    private static boolean inOverworld() {
        ClientLevel level = Minecraft.getInstance().level;
        return level != null && level.dimension() == Level.OVERWORLD;
    }

    /** Client main thread (payload handler). */
    private static void handle(S2CNightEventPayload payload) {
        String origin;
        if (!syncedThisSession) {
            origin = "login";
        } else if (EclipseWorldState.NIGHT_EVENT_NONE.equals(payload.event())) {
            origin = "dawn";
        } else {
            origin = "nightfall";
        }
        syncedThisSession = true;
        activeEvent = payload.event();
        eventDay = payload.day();
        EclipseMod.LOGGER.debug("[w6a-nightsync] event={} day={} ({})",
                payload.event(), payload.day(), origin);
    }

    /** Disconnect reset — the next server may have no (or another) event running. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        activeEvent = EclipseWorldState.NIGHT_EVENT_NONE;
        eventDay = 0;
        syncedThisSession = false;
    }
}
