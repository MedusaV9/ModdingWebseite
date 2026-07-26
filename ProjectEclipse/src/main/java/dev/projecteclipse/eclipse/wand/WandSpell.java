package dev.projecteclipse.eclipse.wand;

import java.util.Locale;
import java.util.Map;

/**
 * One data-driven Zauberstab spell definition (F-039). The 30 spells (10 per
 * {@link WandPath}) live in the {@link WandSpells} registry; this record carries
 * everything the server dispatch, the tree UI and the HUD need:
 *
 * <ul>
 *   <li>{@code key} — the stable id, {@code "<path>.<name>"} (e.g. {@code riss.blink}).
 *       Doubles as the {@code config/eclipse/wand.json} tuning key and the data-component
 *       value of the wand's selected spell.</li>
 *   <li>{@code path}/{@code tier}/{@code ordinal} — position in the path's ladder
 *       (tier 1–5, ordinal 0–9; ordinal 0 is the baseline spell granted by choosing the
 *       path, everything else unlocks through its {@link WandTree} node).</li>
 *   <li>{@code castType} — display taxonomy (instant/projectile/beam/aura/ground);
 *       execution is dispatched by key in {@code WandSpellEffects}.</li>
 *   <li>{@code defaultCost}/{@code defaultParams} — authored tuning; the live values
 *       come from {@link WandConfig} (hot-reloadable) with these as fallback.</li>
 * </ul>
 *
 * <p>Lang keys: {@code wand.eclipse.spell.<path>.<name>} (+ {@code .desc}); cast type:
 * {@code wand.eclipse.cast.<type>}.</p>
 */
public record WandSpell(
        String key,
        WandPath path,
        int tier,
        int ordinal,
        CastType castType,
        int defaultCost,
        Map<String, Float> defaultParams) {

    /** Display taxonomy of how a spell is delivered (F-039 spec). */
    public enum CastType {
        INSTANT, PROJECTILE, BEAM, AURA, GROUND;

        /** Lang key of the cast-type label ({@code wand.eclipse.cast.<type>}). */
        public String langKey() {
            return "wand.eclipse.cast." + name().toLowerCase(Locale.ROOT);
        }
    }

    /** Short name half of the key ({@code "blink"} for {@code "riss.blink"}). */
    public String shortName() {
        return key.substring(key.indexOf('.') + 1);
    }

    /** Lang key of the spell display name ({@code wand.eclipse.spell.<path>.<name>}). */
    public String langKey() {
        return "wand.eclipse.spell." + key;
    }

    /** Lang key of the one-line effect description. */
    public String descKey() {
        return langKey() + ".desc";
    }

    /** True for the path's ordinal-0 baseline spell (unlocked by choosing the path). */
    public boolean baseline() {
        return ordinal == 0;
    }
}
