package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-104 Team A (WAVE4 "Combat Feel") {@link PhotonFxRegistry} row registrar — one NEW
 * cue family on combat beats. All four assets are authored programmatically by
 * {@code tools/photon/wave4_combat_fx.py} (fxlib); re-run that script instead of
 * hand-editing the gzip-NBT.
 *
 * <ul>
 *   <li><b>Crit gleam</b> ({@link #CUE_CRIT_GLEAM}) — A3: {@code drama/CombatFeedbackFx}
 *       fires it at the victim's chest on every server-side {@code CriticalHitEvent}
 *       (position lane, LAYERED over the vanilla crit stars + the {@code impact_light}
 *       Quasar pop the same handler broadcasts).</li>
 *   <li><b>Heavy impact</b> ({@link #CUE_HEAVY_IMPACT}) — A4: the &ge;8-damage bucket of
 *       {@code CombatFeedbackFx.onLivingDamagePost} ({@code EclipseGeoMonster} victims
 *       only); {@code a} = final damage, scaling the pop {@value #IMPACT_SCALE_MIN}–
 *       {@value #IMPACT_SCALE_MAX}.</li>
 *   <li><b>Stagger arc</b> ({@link #CUE_STAGGER_ARC}) — A6: dispatched CLIENT-side by
 *       {@code StormHoundRenderer} on the rising edge of the hound's synced
 *       lunge-stagger flag ({@code PhotonFxRegistry.dispatchEntity}, never wire-fired);
 *       the asset's 40t window is exactly {@code ChargedLungeGoal.STAGGER_TICKS}, and
 *       the entity attach means Photon auto-cleans it if the hound dies staggered.</li>
 *   <li><b>Dissolve motes</b> ({@link #CUE_DISSOLVE_MOTES}) — A2: dispatched CLIENT-side
 *       by {@code GlitchedGeoRenderer} the tick a GLITCHED corpse opens its last-10t
 *       alpha de-rez. Deliberately position-anchored even though an entity is at hand:
 *       the corpse is removed ~10t later and an attached executor would die with it —
 *       the motes must OUTLIVE the body (they are what's left of it).</li>
 * </ul>
 *
 * <p>Cue ids follow the {@code Wave3FxRows} two-sided naming precedent: the server hook
 * ({@code CombatFeedbackFx}) re-derives the same {@code FxCues.cue("…")} id inline, so
 * {@code FxCues.java} (frozen/shared) stays untouched.</p>
 *
 * <p>All four rows are Photon-only garnish ({@code Mode.LAYER}, Quasar leg {@code null}):
 * legal for NEW cues, whose pre-row baseline was nothing (the {@code Row} javadoc law).
 * {@code reducedFx} drops all four — crits keep vanilla stars + {@code impact_light},
 * heavy hits keep the scaled CRIT {@code sendParticles} burst, the stagger keeps the
 * server SMOKE/SPARK fizzle + the Quasar loop leg, the dissolve keeps the alpha fade
 * itself + the server portal static. All BURST-channel one-shots; Photon's default
 * same-anchor dedup ({@code allowMulti=false}) stays on everywhere as a free anti-stack
 * guard (two 8-damage hits in one tick at the same chest = one pop, deliberate).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class Wave4CombatFxRows {
    /**
     * WAVE4 #1 — crit sparkle ({@code a}/{@code b} unused; ~0.7 s one-shot at the
     * victim's chest, position lane).
     */
    public static final ResourceLocation CUE_CRIT_GLEAM = FxCues.cue("wave4_crit_gleam");
    /**
     * WAVE4 #2 — heavy-damage payoff ({@code a} = final damage &ge;8, {@code b} unused;
     * ~1.5 s one-shot at the victim's chest, position lane).
     */
    public static final ResourceLocation CUE_HEAVY_IMPACT = FxCues.cue("wave4_heavy_impact");
    /**
     * WAVE4 #3 — hound stagger tell ({@code a}/{@code b} unused; 40 t one-shot around
     * the hound's head, client-local entity dispatch only).
     */
    public static final ResourceLocation CUE_STAGGER_ARC = FxCues.cue("wave4_stagger_arc");
    /**
     * WAVE4 #4 — glitch de-rez motes ({@code a}/{@code b} unused; ~1.5 s one-shot at
     * the corpse's center, client-local position dispatch only).
     */
    public static final ResourceLocation CUE_DISSOLVE_MOTES = FxCues.cue("wave4_dissolve_motes");

    /** Impact scale ramp: an 8-damage hit pops at ~0.94, a 16+-damage one at 1.25. */
    private static final double IMPACT_SCALE_BASE = 0.70D;
    private static final double IMPACT_SCALE_PER_DAMAGE = 0.03D;
    private static final double IMPACT_SCALE_MIN = 0.9D;
    private static final double IMPACT_SCALE_MAX = 1.25D;

    private Wave4CombatFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // #1 — BURST: the highest-frequency wave4 cue (every server crit), hence the
        // leanest asset (13 sprites) and the burst channel's own per-window cap.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CRIT_GLEAM,
                fx("wave4_crit_gleam"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave4CombatFxRows::critGleamLeg));
        // #2 — BURST: rate-limited by the >=8-damage bucket (crit-grade hits only).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_HEAVY_IMPACT,
                fx("wave4_heavy_impact"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave4CombatFxRows::heavyImpactLeg));
        // #3 — BURST: at most one per whiffed lunge per hound (160t lunge cooldown).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_STAGGER_ARC,
                fx("wave4_stagger_arc"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave4CombatFxRows::staggerArcLeg));
        // #4 — BURST: one per GLITCHED death (the fade-start tick is a single frame).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_DISSOLVE_MOTES,
                fx("wave4_dissolve_motes"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave4CombatFxRows::dissolveMotesLeg));
    }

    // ------------------------------------------------------------------ #1 leg

    /** Crit-gleam leg: one anchored pop at the server-sent chest position. */
    private static boolean critGleamLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // vanilla crit stars + the impact_light Quasar pop carry it
        }
        return PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT);
    }

    // ------------------------------------------------------------------ #2 leg

    /** Heavy-impact leg: scales the pop with the final damage ({@code a}). */
    private static boolean heavyImpactLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the scaled CRIT sendParticles burst carries the bucket read
        }
        double scale = Mth.clamp(IMPACT_SCALE_BASE + IMPACT_SCALE_PER_DAMAGE * a,
                IMPACT_SCALE_MIN, IMPACT_SCALE_MAX);
        return PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT
                .withScale(scale, scale, scale));
    }

    // ------------------------------------------------------------------ #3 leg

    /**
     * Stagger-arc leg: attached to the hound (eye anchor ~= the head the halo orbits)
     * so the tell wobbles with the model; Photon auto-destroys it if the hound dies
     * mid-stagger. Degrades to the anchor position when the entity is not at hand.
     */
    private static boolean staggerArcLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // server SMOKE/SPARK fizzle + the rift_spark loop carry it
        }
        if (entity != null) {
            return PhotonBridge.spawnOnEntity(photonFx, entity,
                    PhotonBridge.AUTO_ROTATE_NONE, (Vec3) null);
        }
        return PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT);
    }

    // ------------------------------------------------------------------ #4 leg

    /**
     * Dissolve-motes leg: ALWAYS position-anchored (see the class doc — the corpse is
     * removed mid-effect and an entity attach would cut the motes off with the poof).
     */
    private static boolean dissolveMotesLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the alpha fade itself + the server portal static carry it
        }
        return PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
