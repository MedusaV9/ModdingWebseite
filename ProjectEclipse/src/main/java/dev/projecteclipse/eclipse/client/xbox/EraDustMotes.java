package dev.projecteclipse.eclipse.client.xbox;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-IMPROVE-2 (IDEAS-events #10, law-cleared) — tutorial-world era atmosphere: chunky
 * 8-bit dust motes hanging in the air around the LOCAL player plus the occasional
 * single-frame hot "dead pixel" blink ({@code eclipse:era_dust_motes} — GPU-instanced,
 * physics-free, {@code maxParticles} well under the sanctioned 256), the "dust in a
 * CRT's light cone" read under the {@code xbox_era.fsh} console grade.
 *
 * <p><b>Law compliance</b> (INTEGRATION.md §4, event-dimension amendment): this is a
 * player-scoped WINDOWED entity loop — the {@code DriftCocoon} D2 pattern — whose window
 * is presence in one of the {@link XboxDimensions} event dimensions. Exactly one loop
 * per client, never payload-fired, driven from this client tick: attach while the local
 * player stands in an xbox dim, release on dimension exit (the seam teleport replaces
 * the player entity — {@code Clone} drops the dead handle and the next tick re-ensures
 * on the replacement while still inside), logout, and {@code reducedFx} (force-release
 * mid-visit; the window never re-opens while the toggle holds). Photon's per-entity
 * CACHE dedup makes the per-tick ensure a cheap no-op while the loop lives.</p>
 *
 * <p><b>Fallback:</b> none by design (IDEAS-events #10) — the era shader grade + the
 * shipped {@code XboxEraFx} beats are the show; photon-less clients keep it untouched.
 * The asset rides the player (local simulation space), so one executor covers the whole
 * visit — no per-chunk anchors, no world scanning.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EraDustMotes {
    private static final ResourceLocation ERA_DUST_MOTES =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "era_dust_motes");

    /** Whether the loop was live last tick (skips the release scan outside the dims). */
    private static boolean wasOpen;

    private EraDustMotes() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null) {
            wasOpen = false; // level gone: the bridge sweep already killed the executor
            return;
        }
        boolean windowOpen = XboxDimensions.isInXboxDimension(player)
                && !EclipseClientConfig.reducedFx();
        if (!windowOpen) {
            if (wasOpen) {
                // Graceful on a normal walk-out; a reducedFx flip forces the kill
                // (loop law — and the bridge gate blocks re-spawns either way).
                PhotonBridge.stopAttachedFx(ERA_DUST_MOTES, player,
                        EclipseClientConfig.reducedFx());
                wasOpen = false;
            }
            return;
        }
        // Re-ensured every tick: cheap LIVE-scan no-op while healthy; a budget-refused
        // spawn simply retries next tick (ambient garnish, no backoff bookkeeping).
        PhotonBridge.ensureAttachedFx(ERA_DUST_MOTES, player,
                PhotonBridge.AUTO_ROTATE_NONE, null);
        wasOpen = true;
    }

    /** Dimension change/respawn: the old player entity (and its executor) is gone. */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        LocalPlayer oldPlayer = event.getOldPlayer();
        if (oldPlayer != null) {
            PhotonBridge.stopAttachedFx(ERA_DUST_MOTES, oldPlayer, true);
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        wasOpen = false;
        LocalPlayer player = Minecraft.getInstance().player;
        if (player != null) {
            PhotonBridge.stopAttachedFx(ERA_DUST_MOTES, player, true);
        }
    }
}
