package dev.projecteclipse.eclipse.xboxevent;

import java.util.LinkedHashMap;
import java.util.Map;

import javax.annotation.Nullable;

import net.minecraft.resources.ResourceKey;
import net.minecraft.world.level.Level;

/**
 * TUT2 — the per-ERA COLOUR GRADE of every Xbox tutorial world, one row per world id.
 *
 * <p>This table replaced the bundled "retro" block textures. The console-era look used to be
 * baked into ~220 hand-made {@code eclipse:block/classic/*} PNGs; those are gone (the classic
 * blocks render with vanilla textures now, see {@code tools/classicblocks/gen_assets.py}) and
 * the era reads purely as a CLIENT-SIDE post grade — {@code client.xbox.XboxEraFx} eases these
 * numbers into the {@code eclipse:xbox_era} pipeline and nothing outside an Xbox dimension is
 * ever touched. A grade also costs no download and stays correct when a resource pack changes
 * the blocks underneath.</p>
 *
 * <p>The rows follow the console's life along the three looks the brief asked for — an
 * over-saturated green ALPHA, a warm yellow BETA and a neutral, contrast-boosted early
 * RELEASE — extended by two later rows so all seven worlds stay tellable apart:</p>
 *
 * <table border="1">
 * <caption>Era grades</caption>
 * <tr><th>world</th><th>look</th><th>reads as</th></tr>
 * <tr><td>tu1  (2012)</td><td>ALPHA</td><td>hard vivid green, washed blacks, heavy vignette</td></tr>
 * <tr><td>tu12 (2012)</td><td>ALPHA</td><td>the same green, one step calmer</td></tr>
 * <tr><td>tu14 (2013)</td><td>BETA</td><td>warm amber/yellow cast, blue pulled down</td></tr>
 * <tr><td>tu19 (2014)</td><td>BETA</td><td>warm but lighter; contrast starting to come back</td></tr>
 * <tr><td>tu31 (2015)</td><td>RELEASE_EARLY</td><td>near neutral, punchier contrast, light vignette</td></tr>
 * <tr><td>tu69 (2018)</td><td>RELEASE_LATE</td><td>faintly cool, clean contrast, barely any vignette</td></tr>
 * <tr><td>tu75 (2019)</td><td>SUNSET</td><td>cool desaturated dusk, vignette almost gone</td></tr>
 * </table>
 *
 * <p>Common (not client-only) on purpose: {@code /dev xboxevent status} names the look of the
 * running world, which is how an operator checks the grade without a screenshot.</p>
 */
public enum XboxEraProfile {
    TU1("tu1", 2012, Look.ALPHA, 0.871F, 1.113F, 0.818F, 0.34F, 0.98F, 1.35F),
    TU12("tu12", 2012, Look.ALPHA, 0.905F, 1.052F, 0.892F, 0.26F, 1.00F, 1.20F),
    TU14("tu14", 2013, Look.BETA, 1.083F, 1.009F, 0.807F, 0.16F, 1.03F, 1.05F),
    TU19("tu19", 2014, Look.BETA, 1.033F, 0.999F, 0.908F, 0.11F, 1.05F, 0.95F),
    TU31("tu31", 2015, Look.RELEASE_EARLY, 0.922F, 0.944F, 1.021F, 0.03F, 1.12F, 0.85F),
    TU69("tu69", 2018, Look.RELEASE_LATE, 0.898F, 0.944F, 1.071F, 0.00F, 1.08F, 0.70F),
    TU75("tu75", 2019, Look.SUNSET, 0.867F, 0.934F, 1.098F, -0.06F, 1.05F, 0.55F);

    /** The era archetypes; {@link #translationKey()} feeds {@code /dev xboxevent status}. */
    public enum Look {
        ALPHA,
        BETA,
        RELEASE_EARLY,
        RELEASE_LATE,
        SUNSET;

        public String translationKey() {
            return "eclipse.xbox.era." + name().toLowerCase(java.util.Locale.ROOT);
        }
    }

    private static final Map<String, XboxEraProfile> BY_WORLD_ID = new LinkedHashMap<>();

    static {
        for (XboxEraProfile profile : values()) {
            BY_WORLD_ID.put(profile.worldId, profile);
        }
    }

    private final String worldId;
    private final int year;
    private final Look look;
    private final float tintR;
    private final float tintG;
    private final float tintB;
    private final float saturation;
    private final float contrast;
    private final float vignette;

    XboxEraProfile(String worldId, int year, Look look, float tintR, float tintG, float tintB,
            float saturation, float contrast, float vignette) {
        this.worldId = worldId;
        this.year = year;
        this.look = look;
        this.tintR = tintR;
        this.tintG = tintG;
        this.tintB = tintB;
        this.saturation = saturation;
        this.contrast = contrast;
        this.vignette = vignette;
    }

    public String worldId() {
        return worldId;
    }

    public int year() {
        return year;
    }

    public Look look() {
        return look;
    }

    /**
     * Per-channel gain applied after the shared console LUT (1.0 = untouched).
     *
     * <p>The numbers are SOLVED, not eyeballed: the shared grade already carries a warm cast
     * (its mid-tone LUT row is {@code 1.040, 1.015, 0.940}), so a literal {@code 1,1,1} here
     * still renders warm and the "neutral early release" look would be indistinguishable from
     * the beta one. Each row is instead fitted so that a flat 50% grey comes out of the whole
     * pipeline at the era's intended colour — alpha {@code ~(121,162,95)}, beta
     * {@code ~(160,143,98)}, early release exactly neutral {@code (134,134,134)}, then
     * progressively cooler for the late rows.</p>
     */
    public float tintR() {
        return tintR;
    }

    public float tintG() {
        return tintG;
    }

    public float tintB() {
        return tintB;
    }

    /** Extra saturation on top of the shared grade's lift; negative desaturates. */
    public float saturation() {
        return saturation;
    }

    /** Contrast multiplier around 0.5 luma (1.0 = untouched). */
    public float contrast() {
        return contrast;
    }

    /** Scale on the shared grade's pillarbox + corner falloff (1.0 = the C17 strength). */
    public float vignette() {
        return vignette;
    }

    @Nullable
    public static XboxEraProfile byWorldId(@Nullable String worldId) {
        return worldId == null ? null : BY_WORLD_ID.get(worldId);
    }

    /** The grade for an Xbox dimension, or {@code null} for any other dimension. */
    @Nullable
    public static XboxEraProfile byDimension(@Nullable ResourceKey<Level> dimension) {
        return dimension == null ? null : byWorldId(XboxDimensions.worldIdOf(dimension));
    }
}
