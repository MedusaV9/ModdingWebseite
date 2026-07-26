package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.wand.WandSpell.CastType;

/**
 * The F-039 spell registry: 30 spells, 10 per {@link WandPath}, authored in Java (the
 * "Java-Registry" option of the spec) with per-spell tuning overridable through
 * {@code config/eclipse/wand.json} ({@link WandConfig} — cost + float params, NO
 * cooldowns per F-040). Registration order is the canonical cycle/display order.
 *
 * <p>Ladder design (each path's 10 spells build on each other):</p>
 * <ul>
 *   <li><b>RISS — Raum/Bewegung</b> (void/glitch): Blink → Umbra-Lanze (F-038, the
 *       Phasenwelle replacement) → Rissschlag → Zugfeld → Phasentausch → Echoklinge →
 *       Gravitationsbrunnen → Schattenriss → Leerensog → Ereignishorizont.</li>
 *   <li><b>GLUT — Zerstörung</b> (ember/magma): Glutstoß → Flammenfächer → Feuerball →
 *       Feuerwelle → Magmasprung → Aschesturm → Eruptionslinie → Phönixschwinge →
 *       Sonnenkern → Inferno.</li>
 *   <li><b>STERN — Schutz/Bindung</b> (starlight/marks): Funkenruf → Sternenschild →
 *       Wurzelgriff → Sternschauer → Lichtsegen → Kometenschlag → Spiegelpanzer →
 *       Sternenbann → Nova-Wächter → Himmelsgericht.</li>
 * </ul>
 *
 * <p>Ordinal 0 is the path's baseline spell (granted by choosing the path, re-granted
 * after every rebirth); ordinals 1–9 unlock through their {@link WandTree} spell nodes.
 * Execution lives in {@code WandSpellEffects}; legacy implementations for the carried-over
 * spells stay in {@code WandPowers}.</p>
 */
public final class WandSpells {
    private static final Map<String, WandSpell> BY_KEY = new LinkedHashMap<>();

    static {
        // ---------------------------------------------------------------- RISS (Raum/Bewegung)
        register("riss.blink", WandPath.RISS, 1, CastType.INSTANT, 12,
                "range", 16, "veilTicks", 30);
        // F-038: Umbra-Lanze REPLACES Phasenwelle — a piercing beam, zero block writes.
        register("riss.umbra_lanze", WandPath.RISS, 1, CastType.BEAM, 26,
                "range", 24, "damage", 8, "implodeRadius", 3.5F, "implodeDamage", 5,
                "pull", 0.7F, "slowTicks", 50);
        register("riss.rissschlag", WandPath.RISS, 2, CastType.GROUND, 30,
                "range", 24, "width", 5, "damage", 10, "radius", 4.5F, "knockback", 1.2F,
                "openTicks", 25, "pull", 0.65F);
        register("riss.zugfeld", WandPath.RISS, 2, CastType.GROUND, 24,
                "range", 24, "radius", 6, "pull", 0.9F, "damage", 4, "slowTicks", 60);
        register("riss.phasentausch", WandPath.RISS, 3, CastType.INSTANT, 22,
                "range", 20, "veilTicks", 30, "damage", 4);
        register("riss.echoklinge", WandPath.RISS, 3, CastType.AURA, 28,
                "radius", 4.5F, "damage", 5, "hits", 3, "beatTicks", 4, "knockback", 0.6F);
        register("riss.gravitationsbrunnen", WandPath.RISS, 4, CastType.GROUND, 45,
                "range", 24, "radius", 7, "durationTicks", 80, "pull", 0.35F,
                "pulseDamage", 3, "pulseEveryTicks", 20);
        register("riss.schattenriss", WandPath.RISS, 4, CastType.INSTANT, 35,
                "range", 20, "damage", 14, "veilTicks", 40, "slowTicks", 60);
        register("riss.leerensog", WandPath.RISS, 5, CastType.GROUND, 55,
                "range", 24, "radius", 9, "pull", 1.4F, "damage", 12, "slowTicks", 80);
        register("riss.ereignishorizont", WandPath.RISS, 5, CastType.GROUND, 75,
                "range", 28, "radius", 8, "durationTicks", 120, "pull", 0.5F,
                "pulseDamage", 4, "pulseEveryTicks", 15, "finaleDamage", 14,
                "finaleKnockback", 1.6F);

        // ---------------------------------------------------------------- GLUT (Zerstörung)
        register("glut.glutstoss", WandPath.GLUT, 1, CastType.BEAM, 10,
                "range", 12, "damage", 6, "fireSeconds", 4, "pierce", 2);
        register("glut.flammenfaecher", WandPath.GLUT, 1, CastType.INSTANT, 18,
                "range", 7, "arcDegrees", 70, "damage", 7, "fireSeconds", 3,
                "knockback", 0.5F);
        register("glut.feuerball", WandPath.GLUT, 2, CastType.PROJECTILE, 22,
                "range", 28, "speed", 1.4F, "damage", 9, "radius", 3, "fireSeconds", 4,
                "knockback", 0.8F);
        register("glut.feuerwelle", WandPath.GLUT, 2, CastType.AURA, 40,
                "radius", 12, "expandTicks", 40, "damage", 9, "fireSeconds", 4,
                "knockup", 0.42F, "burnBonus", 1.5F);
        register("glut.magmasprung", WandPath.GLUT, 3, CastType.INSTANT, 22,
                "launch", 1.3F, "damage", 8, "radius", 4.5F, "knockback", 1.0F,
                "fireSeconds", 2, "resistSeconds", 5);
        register("glut.aschesturm", WandPath.GLUT, 3, CastType.GROUND, 35,
                "range", 24, "radius", 6, "durationTicks", 60, "pulseDamage", 3,
                "pulseEveryTicks", 15, "fireSeconds", 2, "slowTicks", 50);
        register("glut.eruptionslinie", WandPath.GLUT, 4, CastType.INSTANT, 40,
                "length", 14, "steps", 5, "stepTicks", 3, "damage", 8, "radius", 2.5F,
                "fireSeconds", 3, "knockup", 0.5F);
        register("glut.phoenixschwinge", WandPath.GLUT, 4, CastType.AURA, 45,
                "launch", 1.5F, "radius", 6, "damage", 10, "fireSeconds", 4,
                "knockback", 1.3F, "slowFallSeconds", 6, "resistSeconds", 5);
        register("glut.sonnenkern", WandPath.GLUT, 5, CastType.GROUND, 60,
                "range", 32, "telegraphTicks", 24, "damage", 22, "radius", 6,
                "fireSeconds", 5, "knockup", 1.0F, "knockback", 1.6F);
        register("glut.inferno", WandPath.GLUT, 5, CastType.GROUND, 80,
                "range", 28, "radius", 9, "durationTicks", 140, "eruptions", 10,
                "damage", 7, "hitRadius", 3, "fireSeconds", 4, "knockup", 0.5F);

        // ---------------------------------------------------------------- STERN (Schutz/Bindung)
        register("stern.funkenruf", WandPath.STERN, 1, CastType.GROUND, 10,
                "range", 32, "damage", 6, "radius", 2.5F, "markTicks", 100);
        register("stern.sternenschild", WandPath.STERN, 1, CastType.AURA, 20,
                "absorption", 2, "resistSeconds", 12, "durationSeconds", 15);
        register("stern.wurzelgriff", WandPath.STERN, 2, CastType.GROUND, 25,
                "range", 24, "radius", 4.5F, "damage", 4, "rootTicks", 70,
                "markTicks", 100);
        register("stern.sternschauer", WandPath.STERN, 2, CastType.GROUND, 40,
                "range", 32, "zoneRadius", 8, "count", 14, "telegraphTicks", 30,
                "durationTicks", 60, "damage", 6, "hitRadius", 2.5F, "slowTicks", 40,
                "markBonus", 1.25F);
        register("stern.lichtsegen", WandPath.STERN, 3, CastType.AURA, 30,
                "heal", 6, "regenSeconds", 8, "speedSeconds", 8, "radius", 6);
        register("stern.kometenschlag", WandPath.STERN, 3, CastType.GROUND, 28,
                "range", 32, "damage", 16, "radius", 5, "telegraphTicks", 20,
                "knockback", 1.5F, "knockup", 0.8F, "markBonus", 1.25F);
        register("stern.spiegelpanzer", WandPath.STERN, 4, CastType.AURA, 40,
                "resistSeconds", 8, "novaRadius", 5, "novaDamage", 6, "knockback", 1.5F,
                "markTicks", 100);
        register("stern.sternenbann", WandPath.STERN, 4, CastType.GROUND, 45,
                "range", 28, "radius", 10, "damage", 5, "rootTicks", 100,
                "weaknessTicks", 120, "markTicks", 140);
        register("stern.novawaechter", WandPath.STERN, 5, CastType.AURA, 55,
                "durationTicks", 120, "strikeEveryTicks", 20, "strikeRange", 8,
                "strikeDamage", 6, "markBonus", 1.25F, "markTicks", 60);
        register("stern.himmelsgericht", WandPath.STERN, 5, CastType.GROUND, 80,
                "range", 32, "zoneRadius", 9, "comets", 7, "cometDamage", 10,
                "cometRadius", 3.5F, "stepTicks", 5, "telegraphTicks", 20,
                "finaleDamage", 16, "markBonus", 1.5F, "knockup", 0.8F);
    }

    private WandSpells() {}

    private static void register(String key, WandPath path, int tier, CastType castType,
            int cost, Object... paramPairs) {
        Map<String, Float> params = new LinkedHashMap<>();
        for (int i = 0; i + 1 < paramPairs.length; i += 2) {
            params.put((String) paramPairs[i], ((Number) paramPairs[i + 1]).floatValue());
        }
        int ordinal = (int) BY_KEY.values().stream().filter(s -> s.path() == path).count();
        BY_KEY.put(key, new WandSpell(key, path, tier, ordinal, castType, cost,
                Map.copyOf(params)));
    }

    /** All 30 spells in canonical order (RISS 0–9, GLUT 0–9, STERN 0–9). */
    public static List<WandSpell> all() {
        return List.copyOf(BY_KEY.values());
    }

    /** Spell by key, or null for unknown/legacy keys. */
    @Nullable
    public static WandSpell byKey(@Nullable String key) {
        return key == null ? null : BY_KEY.get(key);
    }

    /** The 10 spells of one path in ladder order (empty for {@link WandPath#NONE}). */
    public static List<WandSpell> ofPath(WandPath path) {
        List<WandSpell> spells = new ArrayList<>(10);
        for (WandSpell spell : BY_KEY.values()) {
            if (spell.path() == path) {
                spells.add(spell);
            }
        }
        return spells;
    }

    /** The baseline (ordinal-0) spell of a path, or null for NONE. */
    @Nullable
    public static WandSpell baselineOf(WandPath path) {
        for (WandSpell spell : BY_KEY.values()) {
            if (spell.path() == path && spell.ordinal() == 0) {
                return spell;
            }
        }
        return null;
    }
}
