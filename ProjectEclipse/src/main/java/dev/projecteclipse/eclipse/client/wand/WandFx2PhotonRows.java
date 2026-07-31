package dev.projecteclipse.eclipse.client.wand;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-070's {@code PhotonFxRegistry} registrar — the wand spell VISUAL OVERHAUL third wave
 * (assets from {@code tools/photon/wandfx2_fx.py}; cue ids at the end of
 * {@code network/fx/FxCues}). Deliberately a NEW class next to {@link WandPhotonFxRows}
 * so the F-038/F-039 rows stay untouched: every row here is {@code Mode.LAYER} garnish
 * with NO Quasar leg — the shipped Quasar/vanilla compositions fired by
 * {@code WandPowers}/{@code WandSpellEffects} stay the photon-less baseline, and a
 * refused Photon spawn changes nothing (degradation law).
 *
 * <p>All one-shots run {@code allowMulti=true} (stacked casts are legitimate; Photon's
 * default dedup would silently eat the second cast's payoff). Zone assets are authored
 * at a fixed radius and scaled by the cue's live {@code a} radius so config retunes stay
 * visually honest; the {@link #tierScale}d muzzle is the one place spell TIER (cue
 * {@code b}) drives size — the F-070 tier-escalation contract.</p>
 *
 * <p><b>Wave-13 A1 movement package.</b> The assets now carry Photon's
 * {@code emission.distanceRate} and {@code inheritVelocity}, both of which are driven by
 * the EXECUTOR's per-tick position delta — they are literally no-ops on a fixed world
 * anchor. The three ENTITY-lane rows (echo blade, guardian, blessing) already ride the
 * caster and get them for free; the muzzle row re-anchors onto the casting player so the
 * cast flash does too (see {@link #casterAt}). The remaining rows are position cues by
 * design (a ground seal or a detonation must not follow the caster) and lean on the
 * asset-side {@code colorBySpeed}/{@code random_gradient} half of the package instead.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class WandFx2PhotonRows {
    /** Per-path muzzle assets, indexed by {@code WandPath.id() - 1} (RISS/GLUT/STERN). */
    private static final ResourceLocation[] MUZZLES = {
            fx("wandfx2_muzzle_riss"), fx("wandfx2_muzzle_glut"), fx("wandfx2_muzzle_stern")};

    // Authored radii the zone assets were built at (wandfx2_fx.py) — live cue radii
    // divide by these to yield the executor scale, clamped to a sane window.
    private static final float BURST_AUTHORED_RADIUS = 3.0F;
    private static final float ASH_AUTHORED_RADIUS = 6.0F;
    private static final float WELL_AUTHORED_RADIUS = 5.0F;
    private static final float MAELSTROM_AUTHORED_RADIUS = 4.5F;
    private static final float ECHO_AUTHORED_RADIUS = 4.5F;
    private static final float SEAL_AUTHORED_RADIUS = 4.5F;

    /** Entity-lane body-center offset (anchor is the EYE; the schild row precedent). */
    private static final double BODY_OFFSET = -0.6D;
    /** Entity-lane feet offset for assets authored above a feet origin (sprung precedent). */
    private static final double FEET_OFFSET = -1.5D;
    /**
     * Squared eye-to-cue distance within which a local player counts as the caster of a
     * {@code CUE_WANDFX2_MUZZLE} (the cue carries a position, not an entity — see
     * {@link #casterAt}). {@code WandPowers.castFlourish} builds the hand point as
     * {@code eye + look*0.55 + side*0.35 - 0.25y}, i.e. never further than ~0.7 blocks
     * from the eye; 1.0 leaves headroom for the client/server position lerp without ever
     * reaching a bystander.
     */
    private static final double MUZZLE_CASTER_RANGE_SQR = 1.0D;

    private WandFx2PhotonRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // ------------------------------------------------------------------ phase 1
        // Muzzle flash: one row, three assets — the leg switches on a = path id and
        // tier-scales on b so a T5 capstone cast flares visibly bigger than a T1 poke.
        // pos = the casting hand point WandPowers.castFlourish already computes.
        //
        // A1 movement package: the muzzle assets carry emission.distanceRate and
        // inheritVelocity, and BOTH read the executor's per-tick position delta — on a
        // fixed world anchor that delta is zero and the two modules are dead weight. So
        // the leg re-anchors the flash onto the casting player (found by proximity, since
        // CUE_WANDFX2_MUZZLE is a position cue and carries no entity) and keeps the hand
        // point as a world-axis offset off the eye. AUTO_ROTATE_NONE deliberately: the
        // muzzle cones fountain along local +Y and would tilt with a LOOK-rotated
        // executor. No caster in range (bystander view of a desynced cast, or a
        // non-player sender) degrades to the old fixed-position spawn.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_MUZZLE,
                MUZZLES[0],
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    int pathIndex = Mth.clamp((int) a - 1, 0, MUZZLES.length - 1);
                    float scale = tierScale(b);
                    PhotonBridge.SpawnOptions options = PhotonBridge.SpawnOptions.DEFAULT
                            .withScale(scale, scale, scale)
                            .withAllowMulti(true);
                    Player caster = entity instanceof Player player ? player : casterAt(pos);
                    if (caster != null) {
                        Vec3 hand = pos.subtract(caster.getEyePosition());
                        return PhotonBridge.spawnOnEntity(MUZZLES[pathIndex], caster,
                                PhotonBridge.AUTO_ROTATE_NONE,
                                options.withOffset(hand.x, hand.y, hand.z));
                    }
                    return PhotonBridge.spawn(MUZZLES[pathIndex], pos, options);
                }));

        // ------------------------------------------------------------------ GLUT
        // Feuerball flight comet: streaks fly along the asset's local +Z; a/b carry the
        // server-computed X/Y Euler pair rotating +Z onto the cast ray (the
        // PlayerFxPhotonRows.heartTheftArc JOML rotationXYZ convention). The vanilla
        // FLAME march in WandSpellEffects stays the photon-less trail baseline.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_GLUT_COMET,
                fx("wandfx2_glut_comet"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT
                                .withRotationDeg(a, b, 0.0D)
                                .withAllowMulti(true))));
        // Shared GLUT detonation (Feuerball impact / Eruptionslinie steps / Flammenfächer
        // mid-arc): core pop + fire ring + physics ember debris chaining the shipped
        // glut_splash/glut_ember_die children. a = blast radius -> executor scale.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_GLUT_BURST,
                fx("wandfx2_glut_burst"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        scaledMulti(a, BURST_AUTHORED_RADIUS))));
        // Aschesturm channel zone: billowing ash bank + ember swirl + floor coals, baked
        // to the authored 60t window. a = zone radius -> executor scale.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_GLUT_ASCHESTURM,
                fx("wandfx2_glut_aschesturm"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        scaledMulti(a, ASH_AUTHORED_RADIUS))));

        // ------------------------------------------------------------------ RISS
        // Gravitationsbrunnen well: orbital streak disc + infall motes + dark core,
        // baked to the authored 80t window. a = well radius -> executor scale.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_RISS_WELL,
                fx("wandfx2_riss_well"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        scaledMulti(a, WELL_AUTHORED_RADIUS))));
        // Void maelstrom (Leerensog / Zugfeld / Schattenriss backstab): hard inhale ->
        // HDR bite at +6t (matching castLeerensog's crunch schedule) -> glitch shards.
        // a = drag radius -> executor scale (Schattenriss sends a small one).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_RISS_MAELSTROM,
                fx("wandfx2_riss_maelstrom"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        scaledMulti(a, MAELSTROM_AUTHORED_RADIUS))));
        // Echoklinge sweep: ENTITY lane on the caster (the blade rides a moving player),
        // re-sent once per beat — allowMulti keeps all three slices alive together.
        // Untracked-caster degrade uses the position anchor.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_RISS_ECHO_BLADE,
                fx("wandfx2_riss_echo_blade"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    PhotonBridge.SpawnOptions options =
                            scaledMulti(a, ECHO_AUTHORED_RADIUS).withOffset(0.0D, BODY_OFFSET, 0.0D);
                    if (entity != null) {
                        return PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE, options);
                    }
                    return PhotonBridge.spawn(photonFx, pos, options);
                }));

        // ------------------------------------------------------------------ STERN
        // Binding seal (Wurzelgriff / Sternenbann): ground ring + counter-orbiting glyph
        // stars + root filaments. a = zone radius -> executor scale.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_STERN_SEAL,
                fx("wandfx2_stern_seal"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        scaledMulti(a, SEAL_AUTHORED_RADIUS))));
        // Nova-Wächter guardian: ENTITY lane — one bright star pacing a head-height
        // orbit for the baked ~120t window (authored above a FEET origin, hence the
        // feet offset off the eye anchor). Strike beats stay the Quasar baseline.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_STERN_GUARDIAN,
                fx("wandfx2_stern_guardian"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    if (entity != null) {
                        return PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE,
                                PhotonBridge.SpawnOptions.DEFAULT
                                        .withOffset(0.0D, FEET_OFFSET, 0.0D)
                                        .withAllowMulti(true));
                    }
                    return PhotonBridge.spawn(photonFx, pos,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                }));
        // Lichtsegen blessing: ENTITY lane — descending light shafts + star-mote rain +
        // dome breath over the caster (also authored above a feet origin).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WANDFX2_STERN_BLESS,
                fx("wandfx2_stern_bless"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> {
                    if (entity != null) {
                        return PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE,
                                PhotonBridge.SpawnOptions.DEFAULT
                                        .withOffset(0.0D, FEET_OFFSET, 0.0D)
                                        .withAllowMulti(true));
                    }
                    return PhotonBridge.spawn(photonFx, pos,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                }));
    }

    /**
     * The player whose casting hand a muzzle cue's position belongs to, or {@code null}
     * when none is close enough. Cheap: the client player list is tiny, and the muzzle
     * fires once per cast.
     */
    @Nullable
    private static Player casterAt(Vec3 pos) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return null;
        }
        Player best = null;
        double bestSqr = MUZZLE_CASTER_RANGE_SQR;
        for (Player player : level.players()) {
            double distSqr = player.getEyePosition().distanceToSqr(pos);
            if (distSqr < bestSqr) {
                bestSqr = distSqr;
                best = player;
            }
        }
        return best;
    }

    /**
     * Muzzle size from the cue's tier float: T1 ≈ 0.9 (feather poke) up to T5 = 1.5
     * (capstone flare). Unknown/zero tiers (pre-cue senders) read as T1.
     */
    private static float tierScale(float tier) {
        int clamped = Mth.clamp((int) tier, 1, 5);
        return 0.75F + 0.15F * clamped;
    }

    /**
     * allowMulti spawn options scaled by {@code liveRadius / authoredRadius}, clamped to
     * [0.4, 2.5] so a hostile config retune can never blow an asset up unreadably.
     * {@code liveRadius <= 0} (pre-cue senders) keeps the authored size.
     */
    private static PhotonBridge.SpawnOptions scaledMulti(float liveRadius, float authoredRadius) {
        PhotonBridge.SpawnOptions options = PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true);
        if (liveRadius > 0.0F) {
            float scale = Mth.clamp(liveRadius / authoredRadius, 0.4F, 2.5F);
            options = options.withScale(scale, scale, scale);
        }
        return options;
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
