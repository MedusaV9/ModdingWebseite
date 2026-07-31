package dev.projecteclipse.eclipse.client.entity.ambient;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.ambient.DriftLanternEntity;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * POLISH1-FXCOUPLING — the MC3 §7 flicker↔Photon coupling, FX side. The Drift Lantern's
 * baked cage glowmask cannot dim (the glow layer depth-rejects the flame bone under the
 * translucent glass — MC3 §6), so the LIGHT side of the flicker is played here: a
 * REVERSE_SUB shadow gulp on each scale trough and a recovery flash + soul puff on the
 * overshoot, anchored at the cage center (bone {@code cage}, y ≈ 12 px = 0.75 b = the
 * mob's exact eye height, hence no offset).
 *
 * <p><b>Timing source of truth</b> is the {@code timeline} block of
 * {@code animation.drift_lantern.flicker} — this class never schedules anything; it is
 * called synchronously from the {@code action} controller's custom-instruction keyframe
 * handler ({@code DriftLanternEntity.wireFlickerTimeline}), so the pulses land
 * frame-exactly on the sheet's own troughs/overshoot with no parallel Java timer to
 * drift. Whoever retimes the {@code glow_flame} curve must drag the timeline along
 * (MC3 §7 law).</p>
 *
 * <p><b>Executor scale carries the keyframe's scale factor</b> (MC3 §7 Randbedingung 4):
 * dips map deeper trough → bigger gulp ({@code ×(1.55 − factor)}: 0.30 → ×1.25,
 * 0.42 → ×1.13, 0.48 → ×1.07), the surge plays at its own overshoot factor (×1.20).
 * {@code allowMulti} is forced: three dips land within 0.4 s on the SAME entity and
 * Photon's per-entity CACHE dedup would silently eat the second and third.</p>
 *
 * <p>Client-only by construction: keyframe handlers only fire from the client render
 * pass, and every spawn sits behind {@link PhotonBridge}'s full guard chain (photon
 * absent / reducedFx / budget → silent no-op; the vanilla SCULK_SOUL trigger puff the
 * server already sends stays the photon-less baseline).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class DriftLanternFx {
    /** Timeline instruction id (after the {@code photon:} prefix) of the trough pulse. */
    public static final String KEY_DIP = "flicker_dip";
    /** Timeline instruction id of the 0.58 s overshoot pulse. */
    public static final String KEY_SURGE = "flicker_surge";

    private static final ResourceLocation DIP = fx("lantern_flicker_dip");
    private static final ResourceLocation SURGE = fx("lantern_flicker_surge");

    private DriftLanternFx() {}

    /**
     * Plays one flicker pulse on {@code lantern}. {@code key} is the timeline
     * instruction id ({@link #KEY_DIP}/{@link #KEY_SURGE} — unknown ids are ignored so
     * future timelines on the shared {@code action} controller cannot misfire here),
     * {@code factor} the {@code glow_flame} scale factor at that keyframe.
     */
    public static void pulse(DriftLanternEntity lantern, String key, float factor) {
        ResourceLocation fxId;
        float scale;
        switch (key) {
            case KEY_DIP -> {
                fxId = DIP;
                scale = 1.55F - factor; // deeper trough = bigger shadow gulp
            }
            case KEY_SURGE -> {
                fxId = SURGE;
                scale = factor;         // the overshoot plays at its own 1.2×
            }
            default -> {
                return;
            }
        }
        PhotonBridge.spawnOnEntity(fxId, lantern, PhotonBridge.AUTO_ROTATE_NONE,
                PhotonBridge.SpawnOptions.DEFAULT
                        .withAllowMulti(true)
                        .withScale(scale, scale, scale));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
