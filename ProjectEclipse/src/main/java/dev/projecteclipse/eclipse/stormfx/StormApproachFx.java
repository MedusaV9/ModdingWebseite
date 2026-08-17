package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.AtmospherePhotonFxRows;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * NEWFX-D5 — <b>Storm Outrunners</b> (PLAN-NEWFX §2): inside the 60→20 block
 * OUTSIDE-approach band, ragged gray wisps tear off the ground and race TOWARD the wall
 * low over the terrain, vanishing into it; closer in, one torn horizontal wind-ribbon
 * whips past at head height — the storm inhales you before you touch it.
 *
 * <p><b>Ownership:</b> this class owns the outside-approach particle layer ONLY. The
 * wall band, interior fog/rain and the crown belong to the storm workers
 * ({@link StormInteriorFx}/{@link StormFxClient}) — nothing here renders once the
 * camera is interior (the shared {@link StormInteriorFx#approachAmount()} feed is
 * already zeroed by any interior coverage, so the hand-off is free).</p>
 *
 * <p><b>Baseline (Quasar cadence, every client):</b> "runner" heads — short-lived
 * {@code eclipse:storm_outrunner_wisp} rag-shedder emitters whose positions this
 * controller drives from behind the player toward the wall shell at
 * ~{@value #RUNNER_SPEED} blocks/tick, hugging the heightmap (the
 * {@code StormFxClient} driven-wisp technique; a Quasar emitter alone cannot know the
 * wall bearing). Cadence scales with the smoothed approach and halves in gusts' wake
 * (the {@code tickRainSheets} gust law, inverted: outrunners sprint WITH the gust).
 * <b>Budget:</b> STORM per runner spawn — reducedFx halves the channel automatically
 * (plan row) and the runner cap drops with the quality tier.</p>
 *
 * <p><b>Garnish (Photon, windowed):</b> ONE head-height wind-ribbon loop — the
 * package's only {@link PhotonFxRegistry} row ({@link FxCues#CUE_STORM_OUTRUNNERS},
 * WINDOWED-only; see {@link AtmospherePhotonFxRows}). Hysteresis: engage while
 * {@code approach > } {@value #RIBBON_ENGAGE}, release below {@value #RIBBON_RELEASE};
 * re-anchoring is release + re-ensure once the player strays
 * {@value #RIBBON_REANCHOR_BLOCKS} blocks from the live anchor (registry law: loops
 * never move). Under reducedFx the bridge refuses the Photon leg and the row has no
 * Quasar leg, so the window releases outright — ribbon off, exactly the plan row.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormApproachFx {
    // --- runner cadence (Quasar baseline) ---
    /** No runners below this smoothed approach (the band edge stays quiet). */
    private static final float RUNNER_MIN_APPROACH = 0.15F;
    /** Spawn interval bounds (ticks): eased from far-band sparse to near-band eager. */
    private static final int RUNNER_INTERVAL_FAR = 26;
    private static final int RUNNER_INTERVAL_NEAR = 12;
    /** Concurrent runner heads at full quality (tier ≤ 1 drops one). */
    private static final int MAX_RUNNERS_FULL = 3;
    /** Ground race speed (blocks/tick) — the top of the storm shear-front grammar. */
    static final double RUNNER_SPEED = 0.65D;
    /** Runners are born this far BEHIND the player (away from the wall, blocks). */
    private static final double RUNNER_START_BEHIND = 6.0D;
    /** …with this much sideways scatter (blocks). */
    private static final double RUNNER_SIDE_SCATTER = 7.0D;
    /** Head height above the heightmap the runner hugs (blocks). */
    private static final double RUNNER_HOVER = 0.7D;
    /** Terrain-follow ease per tick (1 = snap; low = wisps float over ridges). */
    private static final double RUNNER_Y_EASE = 0.35D;
    /** Hard life cap — a pathological runner (unloaded chunks) still dies (ticks). */
    private static final int RUNNER_MAX_TICKS = 140;
    /** The runner vanishes INTO the wall: removed within this shell distance (blocks). */
    private static final double RUNNER_ABSORB_BLOCKS = 1.5D;

    // --- ribbon window (Photon garnish) ---
    static final float RIBBON_ENGAGE = 0.5F;
    static final float RIBBON_RELEASE = 0.3F;
    /** Player drift from the live anchor that forces a release + re-ensure (blocks). */
    static final double RIBBON_REANCHOR_BLOCKS = 6.0D;

    /** One driven runner head. */
    private static final class Runner {
        final ParticleEmitter emitter;
        Vec3 pos;
        /** Horizontal unit direction toward the wall shell point (fixed at spawn). */
        final double dirX;
        final double dirZ;
        /** Storm the runner dives into (absorb test tracks its live center/radius). */
        final StormFxClient.ClientStorm storm;
        int age;

        Runner(ParticleEmitter emitter, Vec3 pos, double dirX, double dirZ,
                StormFxClient.ClientStorm storm) {
            this.emitter = emitter;
            this.pos = pos;
            this.dirX = dirX;
            this.dirZ = dirZ;
            this.storm = storm;
        }
    }

    private static final List<Runner> RUNNERS = new ArrayList<>(MAX_RUNNERS_FULL);
    private static int runnerCountdown;
    /** Anchor the live ribbon loop was ensured at, or {@code null} while released. */
    @Nullable
    private static Vec3 ribbonAnchor;
    /** Ticks until the next ribbon ensure after a refusal (bridge cap / Photon absent). */
    private static int ribbonRetryCooldown;

    private StormApproachFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null) {
            clear();
            return;
        }
        float approach = StormInteriorFx.approachAmount();
        tickRunners(level, approach);
        tickRibbon(player, approach);
        if (approach < RUNNER_MIN_APPROACH) {
            return; // live runners finish their race; nothing new spawns
        }
        StormFxClient.ClientStorm storm = nearestVisibleStorm(player.position());
        if (storm == null) {
            return;
        }
        maybeSpawnRunner(level, player, storm, approach);
    }

    // ------------------------------------------------------------------ runners

    private static void tickRunners(ClientLevel level, float approach) {
        for (Iterator<Runner> it = RUNNERS.iterator(); it.hasNext();) {
            Runner runner = it.next();
            runner.age++;
            double x = runner.pos.x + runner.dirX * RUNNER_SPEED;
            double z = runner.pos.z + runner.dirZ * RUNNER_SPEED;
            // Hug the terrain: ease toward heightmap + hover so ridge lips read as hops.
            double groundY = level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                    Mth.floor(x), Mth.floor(z)) + RUNNER_HOVER;
            double y = Mth.lerp(RUNNER_Y_EASE, runner.pos.y, groundY);
            runner.pos = new Vec3(x, y, z);
            double dx = x - runner.storm.center.x;
            double dz = z - runner.storm.center.z;
            double shellDist = Math.abs(Math.sqrt(dx * dx + dz * dz) - runner.storm.radius);
            boolean absorbed = shellDist <= RUNNER_ABSORB_BLOCKS;
            boolean dead = absorbed || runner.age > RUNNER_MAX_TICKS
                    || isRemoved(runner.emitter);
            if (dead) {
                removeRunner(runner);
                it.remove();
                continue;
            }
            try {
                runner.emitter.setPosition(runner.pos);
            } catch (Throwable t) {
                removeRunner(runner);
                it.remove();
            }
        }
    }

    private static void maybeSpawnRunner(ClientLevel level, LocalPlayer player,
            StormFxClient.ClientStorm storm, float approach) {
        int cap = FxBudget.qualityTier() >= 2 ? MAX_RUNNERS_FULL : MAX_RUNNERS_FULL - 1;
        if (RUNNERS.size() >= cap || --runnerCountdown > 0) {
            return;
        }
        // Cadence eases with approach; a live gust makes the pack sprint (interval −40 %).
        float eased = approach * approach * (3.0F - 2.0F * approach);
        int interval = Math.round(Mth.lerp(eased, RUNNER_INTERVAL_FAR, RUNNER_INTERVAL_NEAR));
        if (StormInteriorFx.gustAmount() > 0.5F) {
            interval = Math.max(6, (int) (interval * 0.6F));
        }
        runnerCountdown = interval;

        RandomSource random = level.random;
        // Bearing storm-center → player = outward; the runner races the OPPOSITE way.
        double outX = player.getX() - storm.center.x;
        double outZ = player.getZ() - storm.center.z;
        double outLen = Math.sqrt(outX * outX + outZ * outZ);
        if (outLen < 1.0E-3D) {
            return; // dead center of a wall storm — no meaningful wall bearing
        }
        outX /= outLen;
        outZ /= outLen;
        double side = (random.nextDouble() * 2.0D - 1.0D) * RUNNER_SIDE_SCATTER;
        // EVAL2-A P3: |side| < ~1.5 launches the runner straight through the camera
        // position — a 2.4-block non-additive quad crossing the near plane reads as the
        // F-107 blade class. Rounding the lane outward (sign kept) preserves the
        // "storm inhales you" scatter while the through-the-lens case disappears.
        if (Math.abs(side) < 1.5D) {
            side = Math.copySign(1.5D, side);
        }
        double behind = RUNNER_START_BEHIND * (0.6D + random.nextDouble() * 0.8D);
        double startX = player.getX() + outX * behind - outZ * side;
        double startZ = player.getZ() + outZ * behind + outX * side;
        double startY = level.getHeight(Heightmap.Types.MOTION_BLOCKING,
                Mth.floor(startX), Mth.floor(startZ)) + RUNNER_HOVER;
        Vec3 start = new Vec3(startX, startY, startZ);
        // Race at the wall shell point nearest the start (small bearing jitter so
        // parallel runners fan instead of stacking on one line).
        double jitter = (random.nextDouble() * 2.0D - 1.0D) * 0.15D;
        double cos = Math.cos(jitter);
        double sin = Math.sin(jitter);
        double dirX = -(outX * cos - outZ * sin);
        double dirZ = -(outZ * cos + outX * sin);

        ParticleEmitter emitter = QuasarSpawner.spawnManaged(
                AtmospherePhotonFxRows.QUASAR_STORM_OUTRUNNER_WISP, start,
                FxBudget.Channel.STORM);
        if (emitter != null) { // budget refusal = silent drop; the cadence just retries
            RUNNERS.add(new Runner(emitter, start, dirX, dirZ, storm));
        }
    }

    private static void removeRunner(Runner runner) {
        try {
            if (!runner.emitter.isRemoved()) {
                runner.emitter.remove();
            }
        } catch (Throwable ignored) {
            // Teardown-order safe (QuasarSpawner.clearAttached pattern).
        }
    }

    private static boolean isRemoved(ParticleEmitter emitter) {
        try {
            return emitter.isRemoved();
        } catch (Throwable t) {
            return true;
        }
    }

    /** Nearest-shell storm passing the visibility gate {@code approachTargetAt} uses. */
    @Nullable
    private static StormFxClient.ClientStorm nearestVisibleStorm(Vec3 pos) {
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        StormFxClient.ClientStorm best = null;
        double bestShell = Double.MAX_VALUE;
        for (int i = 0; i < storms.size(); i++) {
            StormFxClient.ClientStorm storm = storms.get(i);
            if (storm.visibility(1.0F) < 0.5F) {
                continue;
            }
            double dx = pos.x - storm.center.x;
            double dz = pos.z - storm.center.z;
            double shell = Math.abs(Math.sqrt(dx * dx + dz * dz) - storm.radius);
            if (shell < bestShell) {
                bestShell = shell;
                best = storm;
            }
        }
        return best;
    }

    // ------------------------------------------------------------------ ribbon window

    /** Ensure back-off after a Photon refusal, so an absent bridge isn't hammered. */
    private static final int RIBBON_RETRY_TICKS = 40;

    private static void tickRibbon(LocalPlayer player, float approach) {
        boolean wantOpen = ribbonAnchor != null
                ? approach >= RIBBON_RELEASE   // hysteresis: hold until the release edge
                : approach > RIBBON_ENGAGE;
        if (!wantOpen || EclipseClientConfig.reducedFx()) {
            if (ribbonAnchor != null) {
                PhotonFxRegistry.releaseLoop(FxCues.CUE_STORM_OUTRUNNERS, true);
                ribbonAnchor = null;
            }
            ribbonRetryCooldown = 0; // leaving the band re-arms the ensure immediately
            return;
        }
        Vec3 head = player.getEyePosition();
        if (ribbonAnchor != null
                && ribbonAnchor.distanceToSqr(head) > RIBBON_REANCHOR_BLOCKS * RIBBON_REANCHOR_BLOCKS) {
            // Registry law: a live loop never moves — release, then re-ensure fresh.
            PhotonFxRegistry.releaseLoop(FxCues.CUE_STORM_OUTRUNNERS, true);
            ribbonAnchor = null;
        }
        if (ribbonAnchor == null && ribbonRetryCooldown > 0) {
            ribbonRetryCooldown--;
            return;
        }
        Vec3 anchor = ribbonAnchor != null ? ribbonAnchor : head;
        if (PhotonFxRegistry.ensureLoop(FxCues.CUE_STORM_OUTRUNNERS, anchor)) {
            ribbonAnchor = anchor;
        } else {
            // Photon absent/refused: the row has no Quasar leg by design. Back off
            // instead of re-ensuring every tick for the rest of the approach.
            ribbonAnchor = null;
            ribbonRetryCooldown = RIBBON_RETRY_TICKS;
        }
    }

    // ------------------------------------------------------------------ lifecycle

    private static void clear() {
        for (int i = 0; i < RUNNERS.size(); i++) {
            removeRunner(RUNNERS.get(i));
        }
        RUNNERS.clear();
        runnerCountdown = 0;
        ribbonRetryCooldown = 0;
        if (ribbonAnchor != null) {
            PhotonFxRegistry.releaseLoop(FxCues.CUE_STORM_OUTRUNNERS, false);
            ribbonAnchor = null;
        }
    }

    /** Disconnect/respawn wipe (the {@link StormFxClient} lifecycle discipline). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        clear();
    }
}
