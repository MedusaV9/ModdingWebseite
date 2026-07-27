package dev.projecteclipse.eclipse.woah;

import net.neoforged.bus.api.IEventBus;

/**
 * Central mod-bus registration hub for the five map "woah features" (F-062;
 * plans under {@code docs/plans_v3/woah/}). Each feature keeps ALL of its code
 * in its own subpackage ({@code woah.mansiondome}, {@code woah.gravityrift},
 * {@code woah.chronostasis}, {@code woah.resonance}, {@code woah.echogrove})
 * and only adds its deferred-register bootstrap line under its own anchor
 * comment below — nothing else in this file is shared state.
 *
 * <p>Game-event listeners self-subscribe via {@code @EventBusSubscriber};
 * client FX rows self-register on {@code FMLClientSetupEvent} (the
 * {@code FerrymanFinaleFxRows} pattern); dev commands self-register their own
 * {@code literal("dev")} tree (Brigadier merges). Placement rows already live
 * in {@code DiscMapDefaults}.</p>
 */
public final class WoahFeatures {

    private WoahFeatures() {}

    public static void register(IEventBus modEventBus) {
        // --- WOAH-01 mansion glitch dome: mod-bus registrations go here ---
        dev.projecteclipse.eclipse.woah.mansiondome.MansionDomeEntities.register(modEventBus);

        // --- WOAH-02 gravity rift: mod-bus registrations go here ---
        // (none needed: no deferred registers — the payload self-registers via its own
        // @EventBusSubscriber RegisterPayloadHandlersEvent registrar, game events
        // self-subscribe via @EventBusSubscriber and the client FX rows/lens post
        // self-register on FMLClientSetupEvent.)

        // --- WOAH-03 chrono stasis: mod-bus registrations go here ---
        dev.projecteclipse.eclipse.woah.chronostasis.ChronoStasisItems.register(modEventBus);

        // --- WOAH-04 resonance field: mod-bus registrations go here ---
        // (none needed: no deferred registers — the payload registers via the sanctioned
        // EclipsePayloads line, game events self-subscribe via @EventBusSubscriber and
        // the client FX rows self-register on FMLClientSetupEvent.)

        // --- WOAH-05 echo grove: mod-bus registrations go here ---
        dev.projecteclipse.eclipse.woah.echogrove.EchoGroveEntities.register(modEventBus);
        dev.projecteclipse.eclipse.woah.echogrove.EchoGroveItems.register(modEventBus);
    }
}
