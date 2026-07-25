package dev.projecteclipse.eclipse.veilfx;

import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * NEWFX-D4 — <b>Diamond Ring</b> (PLAN-NEWFX §2): at the moment the sun goes fully
 * black, ONE blinding bead of light flares on the rim, streaks a short arc and dies —
 * the eclipse "diamond ring", ~1.5 s, then the drone owns the dark.
 *
 * <p><b>Seam:</b> a client observer on {@link EclipseFxState#eclipseAmount}: a RISING
 * crest through {@value #CREST} fires once per ramp; the trigger re-arms only after the
 * amount falls below {@value #REARM} (the music rung's threshold neighborhood — same
 * hysteresis discipline, so partial dips near totality never double-fire). Joining
 * mid-totality shows nothing: the first sample never counts as a crest.</p>
 *
 * <p><b>Tech (plan row):</b> Photon one-shot {@code eclipse:totality_diamond_ring} +
 * Quasar glint fallback, {@code Mode.LAYER} semantics spawned DIRECTLY through
 * {@link PhotonBridge}/{@link QuasarSpawner} — client-local, no cue crosses the wire
 * (see {@link AtmospherePhotonFxRows}). Anchored {@value #BEAD_DISTANCE_BLOCKS} blocks
 * out from the camera along {@link SunTracker#sunDirWorld} so the bead sits ON the
 * blacked-out disc's rim from this camera's exact vantage; skipped (and consumed — a
 * LATE diamond ring is a wrong diamond ring) when {@link SunTracker#sunOccluded()}
 * reports no sky line to the sun. <b>Budget:</b> SEQUENCE (the eclipse IS the scripted
 * sequence). <b>reducedFx:</b> skip — the world-grade exposure crush already tells the
 * story. <b>Photosensitivity:</b> the asset holds ONE bead with a ≤ 2-tick full-white
 * flash (§3 impact law) easing into the ~1.5 s streak — no strobe, no repeats.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class TotalityPeakFx {
    /** Rising-crest trigger threshold on the eased eclipse amount. */
    static final float CREST = 0.95F;
    /** Hysteresis re-arm: the amount must fall below this before the next crest counts. */
    static final float REARM = 0.6F;
    /** Bead anchor distance from the camera along the sun direction (blocks). */
    static final double BEAD_DISTANCE_BLOCKS = 60.0D;

    /** Armed = the next rising crest fires. Disarmed until the amount dips below REARM. */
    private static boolean armed = true;
    /** Previous tick's eclipse amount; NaN = no sample yet (login/dimension change). */
    private static float lastAmount = Float.NaN;

    private TotalityPeakFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            reset();
            return;
        }
        float amount = EclipseFxState.eclipseAmount(1.0F);
        float previous = lastAmount;
        lastAmount = amount;
        if (!armed) {
            if (amount < REARM) {
                armed = true; // ramp fully receded — the next totality earns a new ring
            }
            return;
        }
        // A crest is a RISING edge through the threshold observed across two samples —
        // a first sample already at totality (login mid-eclipse) is deliberately not one.
        if (Float.isNaN(previous) || previous >= CREST || amount < CREST) {
            return;
        }
        armed = false; // consumed either way: a late/second bead is never played
        if (EclipseClientConfig.reducedFx()) {
            return; // plan row: skip — the exposure crush carries the beat
        }
        if (level.dimension() != Level.OVERWORLD || SunTracker.sunOccluded()) {
            return; // no sight line to the sun rim: nothing to flare on
        }
        Vector3f sunDir = SunTracker.sunDirWorld(1.0F); // shared scratch — read out now
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        Vec3 anchor = camera.add(sunDir.x() * BEAD_DISTANCE_BLOCKS,
                sunDir.y() * BEAD_DISTANCE_BLOCKS, sunDir.z() * BEAD_DISTANCE_BLOCKS);
        // LAYER law: Photon bead + Quasar glint together; either alone still reads.
        PhotonBridge.spawn(AtmospherePhotonFxRows.FX_TOTALITY_DIAMOND_RING, anchor);
        QuasarSpawner.spawn(AtmospherePhotonFxRows.QUASAR_DIAMOND_RING_GLINT, anchor,
                FxBudget.Channel.SEQUENCE);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    private static void reset() {
        armed = true;
        lastAmount = Float.NaN;
    }
}
