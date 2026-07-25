package dev.projecteclipse.eclipse.stormfx;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-IMPROVE-2 (IDEAS-events #7) — the intro vortex's Photon layer: one
 * {@code eclipse:intro_storm_wall} loop (three climbing beam arcs on the shell + slow
 * wall-glow shreds + the zenith bloom crown) per live VORTEX storm, latched client-side
 * off the SHIPPED storm signals — the {@code S2CStormStatePayload TYPE_VORTEX} lifecycle
 * that {@link StormFxClient} already tracks for the mesh wall/wisps. No new cue, no
 * registry row (the {@code STORM_CROWN_HALO} "per-storm windowed loop owned here, not by
 * {@code PhotonFxRegistry.ensureLoop}" law — storms are many, {@code ensureLoop} manages
 * ONE loop per logical id), and no server change: the live intro, the {@code /eclipsefx
 * sequence intro} replays and the dev-command vortexes all flow through the same client
 * storm list, so every path gets the layer for free.
 *
 * <p><b>Window</b> (mirrors {@code StormFxClient.tickCrownHalo}): attach while the storm
 * is a VORTEX in SPAWN/ACTIVE with visibility &gt; {@value #MIN_VISIBILITY} and the
 * camera inside {@value #ATTACH_RANGE} of the shell; release beyond
 * {@value #RELEASE_RANGE} (hysteresis), on DISSIPATE/EXPLODE (graceful — airborne shreds
 * fade with the mesh wall's own dissipate ramp), on storm removal/dimension change, and
 * whenever the bridge goes unavailable ({@code reducedFx} kills it wholesale). Refused
 * spawns back off {@value #RETRY_TICKS} ticks. LAYER by contract: the Quasar
 * vortex-wisp/arc stack and the mesh wall render untouched underneath — photon-less
 * clients keep today's intro bit-identical.</p>
 *
 * <p>The asset is authored AT the intro vortex's frozen r=22/h=48 dims
 * ({@code IntroSequence.VORTEX_RADIUS/VORTEX_HEIGHT} — {@code PhotonBridge.spawnLoop}
 * has no scale knob, so intrinsic authoring IS the scaling story); a dev vortex spawned
 * at a different radius gets the fixed-size wall, which is fine for a dev command.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class IntroStormWallFx {
    /** Attach gate: camera distance to the shell (the crown-halo ARC_RANGE analogue). */
    private static final double ATTACH_RANGE = 160.0D;
    /** Release only past this (hysteresis — no boundary thrash while walking the rim). */
    private static final double RELEASE_RANGE = ATTACH_RANGE + 20.0D;
    /** Skip while the shell is still (or again) invisible — SPAWN ramp head / fade tail. */
    private static final float MIN_VISIBILITY = 0.2F;
    /** Refused-spawn (executor budget) backoff, the SanctumLightfall/crown-halo cadence. */
    private static final int RETRY_TICKS = 40;
    /** The wall-layer asset ({@code tools/photon/backlog_fx.py} — authored at r=22/h=48). */
    private static final ResourceLocation INTRO_STORM_WALL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "intro_storm_wall");

    /** Per-storm live wall loops, keyed by storm id (client main thread only). */
    private static final Map<Integer, WallLoop> LOOPS = new HashMap<>();

    /** One live wall loop + its retry/anchor bookkeeping. */
    private static final class WallLoop {
        @Nullable
        PhotonBridge.LoopHandle handle;
        @Nullable
        Vec3 anchor;
        int nextRetryTick;
    }

    private static int clientTicks;

    private IntroStormWallFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            // Level gone: the bridge sweep already killed the executors — bookkeeping only.
            LOOPS.clear();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        clientTicks++;
        if (!PhotonBridge.available()) {
            releaseAll(false); // reducedFx / photonFx off: kill the layer wholesale
            return;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();

        for (StormFxClient.ClientStorm storm : StormFxClient.storms()) {
            if (storm.type != S2CStormStatePayload.TYPE_VORTEX) {
                continue;
            }
            WallLoop loop = LOOPS.get(storm.id);
            if (loop != null && loop.handle != null && !loop.handle.alive()) {
                loop.handle = null; // bridge sweep reaped it (level change race)
            }
            double dx = camera.x - storm.center.x;
            double dz = camera.z - storm.center.z;
            double shellDist = Math.abs(Math.sqrt(dx * dx + dz * dz) - storm.radius);
            boolean live = loop != null && loop.handle != null;
            boolean wanted = storm.state != S2CStormStatePayload.STATE_DISSIPATE
                    && storm.state != S2CStormStatePayload.STATE_EXPLODE
                    && storm.visibility(1.0F) > MIN_VISIBILITY
                    && shellDist < (live ? RELEASE_RANGE : ATTACH_RANGE);
            if (!wanted) {
                if (loop != null) {
                    release(loop, true);
                }
                continue;
            }
            if (loop == null) {
                loop = new WallLoop();
                LOOPS.put(storm.id, loop);
            }
            if (loop.handle != null) {
                // Keepalive; re-anchoring a live loop is unsupported — a repositioned
                // storm (replay resync nudge) releases and respawns at the new center.
                if (loop.anchor != null && loop.anchor.distanceToSqr(storm.center) > 0.25D) {
                    release(loop, true);
                }
                continue;
            }
            if (clientTicks < loop.nextRetryTick) {
                continue;
            }
            loop.handle = PhotonBridge.spawnLoop(INTRO_STORM_WALL, storm.center);
            if (loop.handle == null) {
                loop.nextRetryTick = clientTicks + RETRY_TICKS; // budget backoff
            } else {
                loop.anchor = storm.center;
            }
        }

        // Storms that vanished from the client list (dissipate expiry, dimension wipe).
        Iterator<Map.Entry<Integer, WallLoop>> iterator = LOOPS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<Integer, WallLoop> entry = iterator.next();
            if (StormFxClient.find(entry.getKey()) == null) {
                release(entry.getValue(), true);
                iterator.remove();
            }
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        LOOPS.clear(); // PhotonBridge.destroyAll force-kills the executors
    }

    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        releaseAll(false); // dimension change/respawn: StormFxClient wipes its list too
        LOOPS.clear();
    }

    private static void release(WallLoop loop, boolean graceful) {
        PhotonBridge.LoopHandle handle = loop.handle;
        loop.handle = null;
        loop.anchor = null;
        if (handle != null) {
            PhotonBridge.stopLoop(handle, graceful); // idempotent, teardown-order safe
        }
    }

    private static void releaseAll(boolean graceful) {
        for (WallLoop loop : LOOPS.values()) {
            release(loop, graceful);
        }
        LOOPS.clear();
    }
}
