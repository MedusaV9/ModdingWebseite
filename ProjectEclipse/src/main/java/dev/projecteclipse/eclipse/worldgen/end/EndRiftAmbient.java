package dev.projecteclipse.eclipse.worldgen.end;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.sequence.endarrival.EndArrivalFxCues;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * F-077 V2 (WP-F) — the permanent end-rift residue over the finished End disc: once
 * {@code EndFightState.materializationComplete()} is set, this ticker re-fires the
 * {@code CUE_RIFT_AMBIENT} one-shot ({@code end_arrival2_rift_ambient.fx}, ~660 t) every
 * {@value #REFIRE_INTERVAL_TICKS} ticks at the disc center — Photon's
 * {@code allowMulti=false} dedup turns the overlap into a seamless ambient, and the
 * AMBIENT budget lane / {@code reducedFx} tier gating apply automatically on the client.
 *
 * <p>Cost discipline: one payload per 30 s, only while a player is within
 * {@value #PRESENCE_RANGE} blocks of the disc center (the presence-gate law — an empty
 * overworld sends nothing). No state, no persistence: a restart simply resumes the
 * cadence. The cue itself is broadcast at {@value #PRESENCE_RANGE} blocks so only
 * players who can see the disc pay for the executor.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndRiftAmbient {
    /** Re-fire cadence (ticks) — comfortably inside the asset's ~660 t lifetime. */
    private static final int REFIRE_INTERVAL_TICKS = 600;
    /** Presence gate + cue broadcast radius around the disc center (blocks). */
    private static final double PRESENCE_RANGE = 512.0D;
    /** The ambient anchor floats this far above the disc surface. */
    private static final double ANCHOR_HEIGHT = 40.0D;

    private EndRiftAmbient() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (event.getServer().getTickCount() % REFIRE_INTERVAL_TICKS != 0) {
            return;
        }
        if (!EndFightState.get(event.getServer()).materializationComplete()) {
            return;
        }
        ServerLevel overworld = event.getServer().overworld();
        EndConfig.Snapshot config = EndConfig.current();
        Vec3 anchor = new Vec3(config.centerX() + 0.5D,
                config.surfaceY() + ANCHOR_HEIGHT, config.centerZ() + 0.5D);
        if (!playerNear(overworld, anchor)) {
            return;
        }
        FxPayloads.sendFxEvent(overworld, EndArrivalFxCues.CUE_RIFT_AMBIENT, anchor,
                0.0F, 0.0F, PRESENCE_RANGE);
    }

    private static boolean playerNear(ServerLevel overworld, Vec3 anchor) {
        double rangeSq = PRESENCE_RANGE * PRESENCE_RANGE;
        for (ServerPlayer player : overworld.players()) {
            if (!player.isSpectator() && player.position().distanceToSqr(anchor) <= rangeSq) {
                return true;
            }
        }
        return false;
    }
}
