package dev.projecteclipse.eclipse.client.entity.door;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.limbo.door.DoorRegistry;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlockEntity;
import dev.projecteclipse.eclipse.limbo.door.S2CDoorCuePayload;
import dev.projecteclipse.eclipse.lives.BanService;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.scores.Team;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Registers the {@link RespawnDoorRenderer} (guarded by {@link DoorRegistry#isBound()}
 * so the client boots green while the wiring line is pending — P6-W1 pattern) and hosts
 * the door's two client entry points:
 *
 * <ul>
 *   <li>{@link #viewerSeesClosed()} — the per-viewer ghost rule (plans_v3 §2.5): ghosts
 *       always SEE the door closed regardless of the global OPEN. Checked every frame by
 *       {@code RespawnDoorBlockEntity.clientPoseAnimation()}; a viewer counts as ghost
 *       when the local player is on the {@code eclipse_ghosts} team OR the synced HUD
 *       lives cache reads 0 (either signal alone suffices — they can lag each other by a
 *       tick around bans).</li>
 *   <li>{@link #handleCue} — {@code S2CDoorCuePayload} ingest (called lazily from
 *       {@code limbo.door.DoorPayloads}); applies the personal pose override to the
 *       local door BE.</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DoorRenderers {
    private DoorRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!DoorRegistry.isBound()) {
            EclipseMod.LOGGER.warn(
                    "Respawn door BE type not registered (DoorRegistry wiring line pending) — renderer skipped");
            return;
        }
        event.registerBlockEntityRenderer(DoorRegistry.RESPAWN_DOOR_BE.get(),
                context -> new RespawnDoorRenderer());
    }

    /** Whether the LOCAL viewer is a ghost and must see the door closed (§2.5 rule). */
    public static boolean viewerSeesClosed() {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null) {
            return false;
        }
        if (ClientStateCache.lives <= 0) {
            return true;
        }
        Team team = player.getTeam();
        return team != null && BanService.GHOST_TEAM_NAME.equals(team.getName());
    }

    /** Personal door cue ingest; runs on the client main thread (payload handler). */
    public static void handleCue(S2CDoorCuePayload payload) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level != null && level.getBlockEntity(payload.pos()) instanceof RespawnDoorBlockEntity door) {
            door.applyClientCue(payload.pose());
        }
    }
}
