package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.player.Player;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-SOCIAL (IDEAS-player #10): the edge-glide trail's client controller — a wingtip
 * ara-ribbon pair ({@code eclipse:glide_trail} Photon asset,
 * {@code AutoRotate.FORWARD} so the ±0.5 X wingtip offsets track the flight vector)
 * REPLACING the existing {@code eclipse:glide_trail} Quasar loop, which re-enters
 * automatically whenever the Photon leg is unavailable or refused (registry law 2 —
 * two trails at once would be mud, per the doc's honest-REPLACE recommendation).
 *
 * <p><b>Window:</b> the existing {@code FX_GLIDE_START}/{@code FX_GLIDE_STOP} event
 * edges (via {@code FxPayloads.handleFxEvent}) open/close the window through
 * {@link #attach}/{@link #detach} — spawn frequency stays event-driven, the loop-law
 * intent the doc calls out. Between the edges a 20t maintenance pass keeps exactly one
 * leg alive per glider: it re-ensures the Photon ribbon (self-healing after entity
 * untrack/re-track, {@code PhotonBridge.ensureAttachedFx} dedup), retires the Quasar
 * stand-in when Photon recovers, and — the {@code reducedFx} kill — force-stops the
 * Photon leg the moment the bridge guards close mid-glide (a live executor would
 * otherwise outlive the toggle; the Quasar baseline then owns the trail again, its own
 * budget/reduced handling untouched).</p>
 *
 * <p>{@link #detach} is graceful ({@code destroy(false)}): emission stops and the ribbon
 * tail dissolves naturally — exactly the landing read the doc asks for.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GlideTrailFx {
    /** Quasar loop emitter (asset owned by W6 — the pre-Photon baseline, unchanged). */
    public static final ResourceLocation GLIDE_TRAIL_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glide_trail");

    /** Eye-relative ribbon anchor (doc: {@code (0, -0.3, 0)} — shoulder height). */
    private static final double OFFSET_Y = -0.3D;
    /** Maintenance cadence in ticks (the §0 ensure-law band: 20–40t). */
    private static final int ENSURE_CADENCE_TICKS = 20;

    /** Players currently inside a START→STOP glide window (client main thread only). */
    private static final List<Player> GLIDERS = new ArrayList<>();
    private static int tickCounter;

    private GlideTrailFx() {}

    /** {@code FX_GLIDE_START} edge: opens the window and starts the preferred leg now. */
    public static void attach(Player glider) {
        if (!GLIDERS.contains(glider)) {
            GLIDERS.add(glider);
        }
        maintain(glider); // event edge = immediate leg, not up to a cadence later
    }

    /** {@code FX_GLIDE_STOP} edge: closes the window; the Photon ribbon tail fades out. */
    public static void detach(Player glider) {
        GLIDERS.remove(glider);
        PhotonBridge.stopAttachedFx(PlayerFxPhotonRows.GLIDE_TRAIL_FX, glider, false);
        QuasarSpawner.removeAttached(GLIDE_TRAIL_EMITTER, glider);
    }

    /** One leg-election pass for one glider (REPLACE: Photon first, Quasar re-entry). */
    private static void maintain(Player glider) {
        if (PhotonBridge.available()) {
            boolean photonLive = PhotonBridge.ensureAttachedFx(PlayerFxPhotonRows.GLIDE_TRAIL_FX,
                    glider, PhotonBridge.AUTO_ROTATE_FORWARD,
                    new net.minecraft.world.phys.Vec3(0.0D, OFFSET_Y, 0.0D));
            if (photonLive) {
                // Photon owns the trail: retire a Quasar stand-in from a photon-less start.
                QuasarSpawner.removeAttached(GLIDE_TRAIL_EMITTER, glider);
                return;
            }
        } else {
            // reducedFx / photonFx-off flipped mid-glide: a live executor outlives the
            // guard chain, so the kill must be explicit (force — accessibility toggle).
            PhotonBridge.stopAttachedFx(PlayerFxPhotonRows.GLIDE_TRAIL_FX, glider, true);
        }
        QuasarSpawner.ensureAttached(GLIDE_TRAIL_EMITTER, glider);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (GLIDERS.isEmpty() || ++tickCounter % ENSURE_CADENCE_TICKS != 0) {
            return;
        }
        var level = Minecraft.getInstance().level;
        for (int i = GLIDERS.size() - 1; i >= 0; i--) {
            Player glider = GLIDERS.get(i);
            if (level == null || glider.isRemoved() || glider.level() != level) {
                // Missed STOP (death/dimension change/untrack): both legs die on their
                // own sweeps; just drop the stale window so bookkeeping cannot leak.
                GLIDERS.remove(i);
                continue;
            }
            maintain(glider);
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        GLIDERS.clear(); // legs are torn down by PhotonBridge.destroyAll + Quasar's own reset
    }
}
