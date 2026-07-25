package dev.projecteclipse.eclipse.veilfx.rift;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.AtmospherePhotonFxRows;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * NEWFX-D3 — <b>Rift Draw-In</b> (PLAN-NEWFX §2): dust motes and thin light-streamers
 * within ~4 blocks of an open portal bend and accelerate INTO the rift plane,
 * compressing to sparks at the event line — the portal finally <i>pulls</i>.
 *
 * <p><b>Seam:</b> the client's live rift anchors ({@link RiftFx#rifts()} — xbox and
 * backrooms portals both arrive over the frozen {@code FX_RIFT_OPEN} lane and are the
 * {@code portalLike} styles this targets; bare STRUCTURE tears keep their shipped
 * spark/glow language). Hysteresis window per anchor: materialize within
 * {@value #MATERIALIZE_BLOCKS} blocks, release beyond {@value #RELEASE_BLOCKS}, at most
 * {@value #MAX_CONCURRENT} concurrent (executor-budget courtesy — nearest anchors win).</p>
 *
 * <p><b>Tech (plan row):</b> Photon-first {@code Mode.REPLACE} WINDOWED loops run
 * directly through {@link PhotonBridge#spawnLoop} because the registry keeps ONE
 * {@code LoopState} per logical id and this needs one loop PER anchor (the
 * {@code storm_crown_halo} per-anchor {@code LoopHandle} law — see
 * {@link AtmospherePhotonFxRows}): {@code eclipse:portal_draw_in} preferred, the Quasar
 * point-attractor mote stand-in only while the Photon leg is down. Budget-refused legs
 * retry on the shared {@value #RETRY_TICKS}-tick cadence ({@link RiftFx}'s
 * {@code EMITTER_RETRY_TICKS} law — never per-tick hammering).
 * <b>Budget:</b> AMBIENT. <b>reducedFx:</b> released unconditionally (loop law); the
 * server-side vanilla reverse-portal columns remain the photon-less floor.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RiftDrawIn {
    /** Window engages when the camera is within this many blocks of the tear center. */
    static final double MATERIALIZE_BLOCKS = 24.0D;
    /** …and releases beyond this (hysteresis band — no flutter at the boundary). */
    static final double RELEASE_BLOCKS = 32.0D;
    /** Executor-budget courtesy cap (PLAN cross-check: D3 ≤ 2 of the ≤ 5 D-loops). */
    static final int MAX_CONCURRENT = 2;
    /** Budget-refusal retry cadence, matching {@code RiftFx.EMITTER_RETRY_TICKS}. */
    private static final int RETRY_TICKS = 20;

    /** One live draw-in window riding a rift anchor. */
    private static final class Window {
        final RiftFx.Rift rift;
        @Nullable
        PhotonBridge.LoopHandle photon;
        @Nullable
        ParticleEmitter quasar;
        /** Ticks until the next (re)spawn attempt after a refused leg (0 = may try). */
        int retryCooldown;

        Window(RiftFx.Rift rift) {
            this.rift = rift;
        }
    }

    /** Live windows, at most {@value #MAX_CONCURRENT} (client main thread only). */
    private static final List<Window> WINDOWS = new ArrayList<>(MAX_CONCURRENT);

    private RiftDrawIn() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            releaseAll(false);
            return;
        }
        if (EclipseClientConfig.reducedFx()) {
            releaseAll(false); // loop law: released unconditionally under reducedFx
            return;
        }
        List<RiftFx.Rift> rifts = RiftFx.rifts();
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();

        // Close: dead/closing/foreign-dimension anchors and cameras past the release band.
        for (Iterator<Window> it = WINDOWS.iterator(); it.hasNext();) {
            Window window = it.next();
            RiftFx.Rift rift = window.rift;
            boolean anchorGone = !rifts.contains(rift) || rift.closing()
                    || rift.dimension != level.dimension();
            if (anchorGone || camera.distanceTo(rift.pos) > RELEASE_BLOCKS) {
                // Graceful on a plain walk-away; a collapsing tear kills its pull outright
                // (a rift that is closing must stop inhaling on the same frame).
                release(window, !anchorGone);
                it.remove();
            }
        }

        // Open: nearest eligible portal anchors first, up to the concurrency cap.
        if (WINDOWS.size() < MAX_CONCURRENT) {
            RiftFx.Rift best = null;
            double bestDist = MATERIALIZE_BLOCKS;
            for (int i = 0; i < rifts.size(); i++) {
                RiftFx.Rift rift = rifts.get(i);
                if (!rift.portalLike || rift.closing() || rift.dimension != level.dimension()
                        || hasWindow(rift)) {
                    continue;
                }
                double dist = camera.distanceTo(rift.pos);
                if (dist <= bestDist) {
                    bestDist = dist;
                    best = rift;
                }
            }
            if (best != null) {
                WINDOWS.add(new Window(best));
            }
        }

        // Keep-alive: REPLACE semantics per window on the shared retry cadence.
        for (int i = 0; i < WINDOWS.size(); i++) {
            ensureLegs(WINDOWS.get(i));
        }
    }

    /** Live draw-in windows right now (dev/QA introspection, mirrors the registry's). */
    public static int liveWindows() {
        return WINDOWS.size();
    }

    /**
     * Photon-first REPLACE: spawn/keep the Photon loop; run the Quasar stand-in only
     * while the Photon leg is down (and retire it the moment the leg recovers — the
     * {@code PhotonFxRegistry.ensureLoop} REPLACE choreography, per anchor).
     */
    private static void ensureLegs(Window window) {
        if (window.photon != null && !window.photon.alive()) {
            window.photon = null; // asset expired / executor culled — eligible to respawn
        }
        if (window.quasar != null && isRemoved(window.quasar)) {
            window.quasar = null;
        }
        if (window.retryCooldown > 0) {
            window.retryCooldown--;
            return;
        }
        Vec3 anchor = window.rift.pos;
        if (window.photon == null) {
            window.photon = PhotonBridge.spawnLoop(
                    AtmospherePhotonFxRows.FX_PORTAL_DRAW_IN, anchor);
        }
        if (window.photon != null) {
            if (window.quasar != null) {
                removeQuasar(window);
            }
            return;
        }
        if (window.quasar == null) {
            window.quasar = QuasarSpawner.spawnManaged(
                    AtmospherePhotonFxRows.QUASAR_PORTAL_DRAW_IN_MOTES, anchor,
                    FxBudget.Channel.AMBIENT);
        }
        // Photon refused/absent: back off on the shared cadence whatever the Quasar leg
        // did (a healthy stand-in keeps running through the cooldown; a refused one
        // retries with the next photon attempt) — never per-tick hammering.
        window.retryCooldown = RETRY_TICKS;
    }

    private static boolean hasWindow(RiftFx.Rift rift) {
        for (int i = 0; i < WINDOWS.size(); i++) {
            if (WINDOWS.get(i).rift == rift) {
                return true;
            }
        }
        return false;
    }

    private static void release(Window window, boolean graceful) {
        PhotonBridge.stopLoop(window.photon, graceful);
        window.photon = null;
        removeQuasar(window);
    }

    private static void removeQuasar(Window window) {
        ParticleEmitter emitter = window.quasar;
        window.quasar = null;
        if (emitter != null) {
            try {
                if (!emitter.isRemoved()) {
                    emitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (QuasarSpawner.clearAttached pattern).
            }
        }
    }

    private static boolean isRemoved(ParticleEmitter emitter) {
        try {
            return emitter.isRemoved();
        } catch (Throwable t) {
            return true;
        }
    }

    private static void releaseAll(boolean graceful) {
        if (WINDOWS.isEmpty()) {
            return;
        }
        for (int i = 0; i < WINDOWS.size(); i++) {
            release(WINDOWS.get(i), graceful);
        }
        WINDOWS.clear();
    }

    /** Disconnect reset: legs die with the level; drop handles so nothing goes stale. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        releaseAll(false);
    }
}
