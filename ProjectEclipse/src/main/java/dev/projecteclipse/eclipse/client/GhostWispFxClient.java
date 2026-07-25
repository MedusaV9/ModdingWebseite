package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PlayerFxPhotonRows;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.scores.Team;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-SOCIAL (IDEAS-player #9): the spectral-wisp window controller — a cold pale-green
 * wisp loop ({@link PlayerFxPhotonRows#GHOST_WISP}) attached to every "green ghost"
 * (banned player: {@code BanService} puts them on the {@code eclipse_ghosts} team),
 * turning the state into lore instead of a potion effect. THIRD-person view only: the
 * local ghost's own screen grade ({@code S2CGhostStatePayload} →
 * {@code EclipseFxState.setGhost}) is a separate, untouched system.
 *
 * <p><b>Zero wire</b> (doc trigger note): the ghost team is client-visible through the
 * vanilla scoreboard sync, so a {@value #ENSURE_CADENCE_TICKS}t pass over
 * {@code level.players()} is the whole trigger — team join → ensure, team leave →
 * graceful stop (the wisps fade out as the ghost is unbanned). A ghost leaving render
 * distance auto-kills its executor (bridge sweep); re-track re-attaches on the next
 * pass. Exactly the CACHE lifecycle the API doc promises.</p>
 *
 * <p><b>REPLACE with a null Quasar leg</b>: no fallback exists — the vanilla glowing
 * outline remains the guaranteed ghost signal on every client. {@code reducedFx}
 * (or photon-off) closing {@code PhotonBridge.available()} force-kills every live wisp
 * on the next pass instead of letting executors outlive the toggle. Budget: ~20 live
 * particles per ghost, ghosts are rare and Limbo-confined.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GhostWispFxClient {
    /** Eye-relative anchor (doc: {@code (0, -0.6, 0)} — chest). */
    private static final Vec3 OFFSET = new Vec3(0.0D, -0.6D, 0.0D);
    /** Ensure cadence in ticks (the §0 ensure-law band: 20–40t). */
    private static final int ENSURE_CADENCE_TICKS = 20;

    private static int tickCounter;

    private GhostWispFxClient() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (++tickCounter % ENSURE_CADENCE_TICKS != 0) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return; // disconnect teardown is PhotonBridge.destroyAll's job
        }
        boolean photonOk = PhotonBridge.available();
        for (Player player : level.players()) {
            if (photonOk && isGhost(player)) {
                PhotonBridge.ensureAttachedFx(PlayerFxPhotonRows.GHOST_WISP, player,
                        PhotonBridge.AUTO_ROTATE_NONE, OFFSET);
            } else {
                // Cheap no-op when nothing is attached; graceful on team leave, force
                // when the guard chain closed (reducedFx accessibility kill).
                PhotonBridge.stopAttachedFx(PlayerFxPhotonRows.GHOST_WISP, player, !photonOk);
            }
        }
    }

    /** The {@code DoorRenderers.viewerSeesClosed} team check, applied to ANY player. */
    private static boolean isGhost(Player player) {
        Team team = player.getTeam();
        return team != null && BanService.GHOST_TEAM_NAME.equals(team.getName());
    }
}
