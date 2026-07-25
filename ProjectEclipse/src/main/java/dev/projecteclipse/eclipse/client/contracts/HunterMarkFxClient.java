package dev.projecteclipse.eclipse.client.contracts;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PlayerFxPhotonRows;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-SOCIAL (IDEAS-player #8): the hunter's target-locked pulse-ring window controller —
 * a blood-orange sonar ping at the target's feet plus slow head chevrons
 * ({@link PlayerFxPhotonRows#CONTRACT_MARK}), rendered ONLY on the hunter's own client,
 * turning the hunt from GPS-text into sightline drama.
 *
 * <p><b>Anonymity law</b> ({@code ContractPayloads} javadoc): the target's identity
 * travels only in the hunter-role reveal payload, so this controller's single source of
 * truth is {@link ContractRevealOverlay#hunterMarkTarget()} (non-null only on the
 * hunter's client while the role survives) gated by
 * {@code ContractClientState.windowActive()}. Nothing here is ever synced — other
 * clients cannot leak the mark.</p>
 *
 * <p><b>Window</b> ({@value #ENSURE_CADENCE_TICKS}t cadence, WINDOWED-only law): while
 * the ACTIVE window runs, resolve the target among {@code level.players()} and
 * {@code ensureAttachedFx}; the target leaving render distance auto-kills the executor
 * (bridge sweep) and re-track re-attaches on the next pass (the CACHE lifecycle the API
 * doc promises). Window end / resolve clears the role → graceful stop; {@code reducedFx}
 * or photon-off closing {@code PhotonBridge.available()} force-kills the live ring.
 * REPLACE with a null Quasar leg: no fallback exists — photon-less hunters keep today's
 * overlay-only experience. Budget: ≤ 6 live particles, the cheapest loop in the file.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class HunterMarkFxClient {
    /** Eye-relative anchor (doc: {@code (0, -1.4, 0)} — feet; the chevrons offset up in-asset). */
    private static final Vec3 OFFSET = new Vec3(0.0D, -1.4D, 0.0D);
    /** Ensure cadence in ticks (doc: "a 20t ensure scans level.players()"). */
    private static final int ENSURE_CADENCE_TICKS = 20;

    private static int tickCounter;
    /** The player the mark is currently attached to (for the stop edge), or {@code null}. */
    @Nullable
    private static Player markedPlayer;

    private HunterMarkFxClient() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (++tickCounter % ENSURE_CADENCE_TICKS != 0) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            markedPlayer = null;
            return;
        }
        UUID targetUuid = ContractClientState.windowActive()
                ? ContractRevealOverlay.hunterMarkTarget() : null;
        boolean photonOk = PhotonBridge.available();
        Player target = targetUuid != null ? level.getPlayerByUUID(targetUuid) : null;
        if (targetUuid == null || !photonOk || (markedPlayer != null && markedPlayer != target)) {
            if (markedPlayer != null) {
                // Graceful on window end/resolve; force when the guard chain closed.
                PhotonBridge.stopAttachedFx(PlayerFxPhotonRows.CONTRACT_MARK, markedPlayer, !photonOk);
                markedPlayer = null;
            }
            if (targetUuid == null || !photonOk) {
                return;
            }
        }
        if (target != null && target.isAlive()) {
            markedPlayer = PhotonBridge.ensureAttachedFx(PlayerFxPhotonRows.CONTRACT_MARK,
                    target, PhotonBridge.AUTO_ROTATE_NONE, OFFSET) ? target : null;
        } else {
            // Target out of render distance (or dead): the executor auto-died via the
            // bridge sweep — keep the window open and re-attach on re-track.
            markedPlayer = null;
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        markedPlayer = null; // PhotonBridge.destroyAll tears the executor down
    }
}
