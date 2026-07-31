package dev.projecteclipse.eclipse.client.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-PLAYER's {@code PhotonFxRegistry} registrar (IDEAS-player.md concepts 2/4/5) — the
 * wand L3 power payoffs. Pattern copied from {@code veilfx/PhotonFxRows}; every row is a
 * {@code Mode.LAYER} garnish with NO Quasar leg, because the powers' shipped Quasar
 * compositions fire independently from {@code WandPowers}/{@code WandTickService} and stay
 * the photon-less baseline (degradation law: a refused Photon spawn changes nothing).
 * Two of those independent emitters are retired per PHOTON-QUALITY §6
 * ({@code stern_komet_core}, {@code riss_schlag_maw} emitter-only): the server still
 * sends them, but {@code PhotonBridge.enhanceQuasarCue} suppresses each client-side
 * while the row's Photon executors are live — REPLACE semantics with the Quasar beat as
 * automatic fallback.
 *
 * <p>All three rows carry a custom {@link PhotonFxRegistry.PhotonLeg} because their
 * choreography exceeds one plain spawn — delayed second spawns, sky-offset anchors or the
 * entity lane. All one-shots here run {@code allowMulti=true} per spec: two casts on the
 * same spot inside one effect window are legitimate stacking (Photon's default dedup would
 * silently eat the second cast's payoff).</p>
 *
 * <p>The per-path idle hand auras (IDEAS-player #6) are deliberately NOT rows: they are
 * pure client-side WINDOWED entity loops with zero wire — {@link WandAuraClient} drives
 * {@code PhotonBridge.ensureAttachedFx}/{@code stopAttachedFx} directly.</p>
 *
 * <p>F-038/F-039 second wave: six more LAYER rows for the spell-system highlight cues
 * ({@code FxCues.CUE_WAND_*}; assets from {@code tools/photon/wand2_fx.py}). Same laws
 * as the first three — no Quasar leg (the {@code WandSpellEffects} compositions stay the
 * photon-less baseline), {@code allowMulti=true} everywhere (stacked casts are legit),
 * and every timing knob rides the cue's {@code a} float so the Photon beat lands exactly
 * on the server's damage tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class WandPhotonFxRows {
    /** Komet head spawn height above the aimed point (descent baked into the asset). */
    private static final double KOMET_SPAWN_HEIGHT = 18.0D;
    /**
     * Ticks the {@code stern_komet_fall} head needs for its baked ~18-block descent. MUST
     * stay in sync with {@code KOMET_FALL_TICKS} in {@code tools/photon/gen_player_fx.py}:
     * the fall is delayed by {@code telegraph − this} so the head touches down exactly on
     * the impact/damage tick.
     */
    private static final int KOMET_FALL_TICKS = 13;
    /** Feet offset for the entity-anchored Magmasprung launch eruption (eye − 1.5). */
    private static final double SPRUNG_FEET_OFFSET = -1.5D;
    /**
     * PH-IMPROVE-2: maw-snap delay fallback when the cue carries no openTicks — the
     * shipped {@code WandConfig} default ({@code "openTicks", 25}); the maw asset bakes
     * the same 25t implosion window.
     */
    private static final int RISS_SNAP_DEFAULT_DELAY = 25;
    /**
     * Ereignishorizont collapse fallback when the cue carries no durationTicks — the
     * authored {@code WandSpells} default ({@code "durationTicks", 120}); the vortex
     * asset bakes the same window ({@code HORIZON_WINDOW} in wand2_fx.py).
     */
    private static final int HORIZON_DEFAULT_DURATION = 120;
    /**
     * W13/A2: ticks the {@code wand_horizon_collapse} in-fall needs before its seed
     * particle Birth-chains the kernel snap. MUST stay in sync with
     * {@code HORIZON_COLLAPSE_LEAD} in {@code tools/photon/wand2_fx.py}: the collapse
     * root is delayed by {@code durationTicks − this} so the chain's HDR bite lands
     * exactly on the server's finale damage tick.
     */
    private static final int HORIZON_COLLAPSE_LEAD = 8;
    /** Body-center offset for the entity-anchored Sternenschild dome (eye − 0.6). */
    private static final double SCHILD_BODY_OFFSET = -0.6D;

    private WandPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-player #2 — Kometenschlag: real falling head + ara ribbon and an HDR
        // impact bloom setDelay()ed onto the damage tick. a = telegraphTicks.
        // PHOTON-QUALITY §6 retirement: while these executors are live the
        // stern_komet_core Quasar beats are suppressed client-side
        // (PhotonBridge.enhanceQuasarCue — two comet heads read as double-vision);
        // photon-less/refused casts keep every beat.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_STERN_KOMET,
                fx("stern_komet_fall"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    int telegraph = Math.max(0, (int) a);
                    boolean fall = PhotonBridge.spawn(photonFx,
                            pos.add(0.0D, KOMET_SPAWN_HEIGHT, 0.0D),
                            PhotonBridge.SpawnOptions.DEFAULT
                                    .withDelay(Math.max(0, telegraph - KOMET_FALL_TICKS))
                                    .withAllowMulti(true));
                    boolean impact = PhotonBridge.spawn(fx("stern_komet_impact"), pos,
                            PhotonBridge.SpawnOptions.DEFAULT
                                    .withDelay(telegraph)
                                    .withAllowMulti(true));
                    return fall || impact;
                }));
        // IDEAS-player #4 — Rissschlag: implosion maw (negative radial in-suck) whose
        // swallowed streaks chain Death sub-emitters into eclipse:riss_glitch_pop static
        // bursts at the lips. The ~25t window is baked into the asset; the server's
        // snap-shut beats keep firing on top.
        // PHOTON-QUALITY §6 retirement (emitter-only): while this maw is live the
        // riss_schlag_maw Quasar emitter is suppressed client-side
        // (PhotonBridge.enhanceQuasarCue); shimmer/blink-tear/seam-scar stay LAYER.
        // PH-IMPROVE-2 (IDEAS-player #4 second beat): the maw-close SNAP — a
        // single-frame white-cyan HDR slice + 8 collide-and-die shards spat from the
        // closing lips (eclipse:riss_maw_snap), parked behind setDelay(a = openTicks)
        // so it lands exactly on the server's snap-shut damage tick. a <= 0 (pre-cue
        // senders) degrades to the asset's baked 25t default window.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_RISS_SCHLAG,
                fx("riss_schlag_maw"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    boolean maw = PhotonBridge.spawn(photonFx, pos,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                    int snapDelay = a > 0.0F ? (int) a : RISS_SNAP_DEFAULT_DELAY;
                    boolean snap = PhotonBridge.spawn(fx("riss_maw_snap"), pos,
                            PhotonBridge.SpawnOptions.DEFAULT
                                    .withDelay(snapDelay)
                                    .withAllowMulti(true));
                    return maw || snap;
                }));
        // IDEAS-player #5 — Magmasprung: physics-bouncing magma chunks with Collision
        // (glut_splash) + Death (glut_ember_die) sub-emitters. Launch arrives on the
        // ENTITY lane (the eruption departs with the leaping caster, feet offset);
        // the landing re-send (b = 1) and untracked-caster degrade use the position.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_GLUT_SPRUNG,
                fx("glut_sprung_crater"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    if (entity != null) {
                        return PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE,
                                PhotonBridge.SpawnOptions.DEFAULT
                                        .withOffset(0.0D, SPRUNG_FEET_OFFSET, 0.0D)
                                        .withAllowMulti(true));
                    }
                    return PhotonBridge.spawn(photonFx, pos,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                }));

        // ------------------------------------------------------------------
        // F-038/F-039 spell-system highlight rows (assets: tools/photon/wand2_fx.py).
        // ------------------------------------------------------------------

        // F-038 Umbra-Lanze — endpoint void bite. pos = beam end; the asset bakes the
        // +3t inhale-then-bite window matching WandSpellEffects' damage schedule.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WAND_UMBRA,
                fx("wand_umbra_implosion"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true))));
        // Ereignishorizont — standing vortex (baked ~120t) + the W13/A2 collapse chain:
        // wand_horizon_collapse (in-fall → Birth kernel bite → Birth shockwave, blueprint
        // tyrant_death_fx) is parked behind setDelay(a − HORIZON_COLLAPSE_LEAD) so the
        // kernel's HDR snap lands exactly on the server's finale damage tick even when
        // wand.json retunes durationTicks.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WAND_HORIZON,
                fx("wand_event_horizon"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    boolean vortex = PhotonBridge.spawn(photonFx, pos,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                    int finaleTick = a > 0.0F ? (int) a : HORIZON_DEFAULT_DURATION;
                    boolean collapse = PhotonBridge.spawn(fx("wand_horizon_collapse"), pos,
                            PhotonBridge.SpawnOptions.DEFAULT
                                    .withDelay(Math.max(0, finaleTick - HORIZON_COLLAPSE_LEAD))
                                    .withAllowMulti(true));
                    return vortex || collapse;
                }));
        // Sonnenkern — the whole solar detonation is delayed by a = telegraphTicks so
        // asset-t0 IS the damage tick (stern_komet_impact pattern); the telegraph reads
        // stay the server's Quasar heat-column/ground-ring baseline.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WAND_SONNENKERN,
                fx("wand_sonnenkern"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT
                                .withDelay(Math.max(0, (int) a))
                                .withAllowMulti(true))));
        // Inferno — fire-storm pillar standing on the zone (baked ~140t = the authored
        // durationTicks default); per-eruption ground beats stay the Quasar baseline.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WAND_INFERNO,
                fx("wand_inferno_pillar"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true))));
        // Sternenschild / Novawächter — shield IGNITION beat on the caster (ENTITY
        // lane, body-center offset); the sustained shield stays the Quasar
        // constellation. Untracked-caster degrade uses the position anchor.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WAND_SCHILD,
                fx("wand_star_dome"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    if (entity != null) {
                        return PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE,
                                PhotonBridge.SpawnOptions.DEFAULT
                                        .withOffset(0.0D, SCHILD_BODY_OFFSET, 0.0D)
                                        .withAllowMulti(true));
                    }
                    return PhotonBridge.spawn(photonFx, pos,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                }));
        // Himmelsgericht — the verdict (sky lance + zone ring + star burst), delayed by
        // a = finaleDelay so asset-t0 IS the synced zone-wide damage pulse.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WAND_GERICHT,
                fx("wand_judgment_finale"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT
                                .withDelay(Math.max(0, (int) a))
                                .withAllowMulti(true))));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
