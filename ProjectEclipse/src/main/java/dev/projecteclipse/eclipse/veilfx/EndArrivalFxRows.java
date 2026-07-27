package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.sequence.endarrival.EndArrivalFxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-077 "Der Altar ruft das End" {@link PhotonFxRegistry} row registrar — the End-arrival
 * cinematic cues ({@code sequence/endarrival/EndArrivalFxCues}). Assets are authored
 * programmatically by {@code tools/photon/end_arrival_fx.py} (fxlib) into
 * {@code assets/eclipse/fx/end_arrival_*.fx}; re-run the script instead of hand-editing
 * the gzip-NBT. The server sender is {@code EndArrivalSequence} (plus
 * {@code EndArrivalDebrisFx} for the arrival puffs).
 *
 * <p>Quasar fallbacks reuse shipped emitters 1:1 — the arrival is THE day-12 world event,
 * so every hero read is {@code Mode.REPLACE} with a photon-less floor: suction →
 * {@code altar_indraw}, rings → {@code altar_levelup_ring}, pillar → {@code altar_beam},
 * maw → {@code riss_maw_shimmer} (the day_rift_maw pairing), wisp → {@code vortex_wisp},
 * puff → {@code rift_spark}, implosion → {@code unlock_burst}, glitter →
 * {@code stern_funke_fall}. On top of that the server composes its own vanilla-particle
 * baseline (REVERSE_PORTAL suction, END_ROD column, DRAGON_BREATH exhale), so even a
 * Veil-less client keeps the full narrative.</p>
 *
 * <p>The two column-shaped assets ({@code pillar}, {@code glitter}) are authored at fixed
 * model heights and Y-scaled onto the REAL altar→rift gap, carried in the payload's
 * {@code a} float (blocks) — see {@link #yScaledColumnLeg}. All eight assets are
 * one-shots; the sequence re-fires the long-lived pillar/maw on a 100 t cadence and
 * Photon's {@code allowMulti=false} dedup absorbs the repeats while covering late
 * joiners.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class EndArrivalFxRows {
    /** Authored beam height of {@code end_arrival_pillar.fx} (keep in step with the generator). */
    private static final double PILLAR_MODEL_HEIGHT = 260.0D;
    /** Authored column height of {@code end_arrival_glitter.fx}. */
    private static final double GLITTER_MODEL_HEIGHT = 240.0D;
    /** Authored column height of {@code end_arrival2_strand_trail.fx} (V2 generator). */
    private static final double TRAIL_MODEL_HEIGHT = 260.0D;
    /** Authored radius of {@code end_arrival2_island_ring.fx} (V2 generator). */
    private static final double RING_MODEL_RADIUS = 60.0D;

    private EndArrivalFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Phase 1 — suction omen at the altar (SEQUENCE: cutscene-burst budget lane).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_SUCTION,
                fx("end_arrival_suction"),
                fx("altar_indraw"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // Phase 2 — energy rings climbing the altar column.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_RINGS,
                fx("end_arrival_rings"),
                fx("altar_levelup_ring"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // Phases 2-3 — THE pillar; a = real altar→rift height in blocks (Y-stretch).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_PILLAR,
                fx("end_arrival_pillar"),
                fx("altar_beam"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                (photonFx, pos, entity, a, b) ->
                        yScaledColumnLeg(photonFx, pos, a, PILLAR_MODEL_HEIGHT)));
        // Phases 2-4 — the giant End-rift maw (the day_rift_maw fallback pairing).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_MAW,
                fx("end_arrival_maw"),
                fx("riss_maw_shimmer"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // Phase 3 — Endergeist wisps between the debris streams (25 t cadence).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_WISP,
                fx("end_arrival_wisp"),
                fx("vortex_wisp"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                EndArrivalFxRows::multiSpawnLeg));
        // Phase 3 — debris arrival puff (rate-limited by EndArrivalDebrisFx server-side).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_PUFF,
                fx("end_arrival_puff"),
                fx("rift_spark"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                EndArrivalFxRows::multiSpawnLeg));
        // Phase 4 — rift-close implosion (flash + shock ring + shard scatter).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_IMPLOSION,
                fx("end_arrival_implosion"),
                fx("unlock_burst"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // Phase 4 — the pillar dissolves into falling glitter; a = real height (Y-stretch).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_GLITTER,
                fx("end_arrival_glitter"),
                fx("stern_funke_fall"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                (photonFx, pos, entity, a, b) ->
                        yScaledColumnLeg(photonFx, pos, a, GLITTER_MODEL_HEIGHT)));

        // --- V2 "GIGANTISMUS" rows (PLAN-F077 §4; assets from end_arrival2_fx.py) ---

        // Beat 1 — rune ring gathering over the altar (~80 t, dies ON the erupt beat).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_GLYPHS,
                fx("end_arrival2_glyphs"),
                fx("altar_levelup_ring"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // Beat 3 — comet-trail sheath around the debris helix strands; a = real
        // altar→rift height (Y-stretch, the pillar law).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_STRAND_TRAIL,
                fx("end_arrival2_strand_trail"),
                fx("altar_beam"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                (photonFx, pos, entity, a, b) ->
                        yScaledColumnLeg(photonFx, pos, a, TRAIL_MODEL_HEIGHT)));
        // Beat 3 — giant wave-complete shock ring; a = ring radius in blocks
        // (XZ-stretch onto the completing annulus; allowMulti: five stamped waves).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_ISLAND_RING,
                fx("end_arrival2_island_ring"),
                fx("unlock_burst"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                EndArrivalFxRows::islandRingLeg));
        // Permanent — the subtle end-rift residue over the finished disc (AMBIENT
        // lane: it plays forever; EndRiftAmbient re-fires it every 600 t and the
        // allowMulti=false dedup turns the ~660 t one-shot into a seamless loop).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                EndArrivalFxCues.CUE_RIFT_AMBIENT,
                fx("end_arrival2_rift_ambient"),
                fx("vortex_wisp"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                false));
    }

    /**
     * Wave-ring leg: the payload's {@code a} float carries the completing wave's ring
     * radius in blocks; stretch the executor's XZ by {@code a / RING_MODEL_RADIUS} so
     * the authored r=60 annulus lands on the actual assembly band. {@code a <= 0}
     * (dev refire) plays unscaled. {@code allowMulti}: all five wave stamps must play
     * even where their lifetimes overlap an FX replay.
     */
    private static boolean islandRingLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        double xzScale = a > 0.5F ? a / RING_MODEL_RADIUS : 1.0D;
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT
                        .withScale(xzScale, 1.0D, xzScale)
                        .withAllowMulti(true));
    }

    /**
     * Column leg: the payload's {@code a} float carries the REAL altar→rift gap in blocks;
     * stretch the executor's Y by {@code a / modelHeight} so the authored column exactly
     * bridges altar top → rift mouth. {@code a <= 0} (dev refire without geometry) plays
     * the asset unscaled.
     */
    private static boolean yScaledColumnLeg(ResourceLocation photonFx, Vec3 pos, float a,
            double modelHeight) {
        double yScale = a > 0.5F ? a / modelHeight : 1.0D;
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withScale(1.0D, yScale, 1.0D));
    }

    /**
     * Repeat-friendly leg for the wisp/puff garnish cues: these fire MANY times at ever
     * new positions during phase 3, so the default single-spawn dedup
     * ({@code allowMulti=false}) would swallow every burst after the first while its
     * ~30-60 t runtime lives. {@code allowMulti=true} lets each stamp play;
     * {@code PhotonBridge}'s live-executor cap still bounds the total.
     */
    private static boolean multiSpawnLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
