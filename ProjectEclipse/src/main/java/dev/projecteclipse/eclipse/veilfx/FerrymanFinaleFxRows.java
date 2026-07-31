package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * FERRYMAN2 {@link PhotonFxRegistry} row registrar — the finale-arc cues
 * (F-044/F-045/F-045b/F-046/F-046b). Assets are authored programmatically by
 * {@code tools/photon/ferryman2_fx.py} (fxlib) into {@code assets/eclipse/fx/*.fx};
 * re-run the script instead of hand-editing the gzip-NBT. Server senders live in
 * {@code ferryman.finale.*} and {@code FerrymanEntity}'s special-attack helper.
 *
 * <p>Quasar fallbacks reuse shipped emitters 1:1 where a read exists (mist wall →
 * {@code growth_dust_wall}, harvest telegraph → {@code contract_omen_ring}, wave →
 * {@code riss_wave_front}, breach → {@code ghost_departure_wisp}, gate veil →
 * {@code door_glow_motes}) — telegraphs MUST stay readable on photon-less clients, so
 * those rows are {@code Mode.REPLACE} (the Quasar leg re-enters whenever the Photon
 * spawn fails). The two yaw-aimed rows ({@code portal_veil}, {@code ferry_wave}) carry
 * the yaw in the payload's {@code a} float and rotate the executor by {@code 180° − a}
 * about Y (the {@code HeraldFerrymanFxRows.oarTearLeg} JOML derivation).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class FerrymanFinaleFxRows {
    /**
     * F-045b key-flight Photon trail (direct client seam, not a registry row — the trail
     * is not payload-driven: the {@code HeraldFerrymanFxRows.HERALD_SHARD_TRAIL}
     * exemption). Consumed by {@link #keyTrail} from {@code PortalKeyEntity.tick()}'s
     * client branch while the synced flying flag is up; the looping asset is
     * entity-bound, so Photon auto-destroys it when the key discards at the keyhole.
     */
    public static final ResourceLocation KEY_TRAIL = fx("key_trail");

    /** Belt-and-braces executor cap for the key ribbon (one key flies at a time). */
    private static final int MAX_ENTITY_EXECUTORS_FOR_TRAIL = 6;

    private FerrymanFinaleFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // F-044 — the dawn day-rift maw over the center island: darker/lazier than the
        // structure rift (slow violet pulse, sinking mote rain). F-102 v3 "Schlund":
        // asset re-authored by tools/photon/rift_mass_fx.py (NOT ferryman2_fx.py any
        // more) — 7-block mouth, three stacked throat shells, dark core, emissive rim.
        // Photon-only garnish is NOT enough here (the rift IS the announce), so the
        // Quasar leg reuses the riss maw shimmer as the photon-less read.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_DAY_RIFT_MAW,
                fx("day_rift_maw"),
                fx("riss_maw_shimmer"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // F-045 — the gate's wavering portal interior (100t one-shot re-fired on the
        // gate entity's 80t cadence; Photon dedups while the runtime lives). a = the
        // gate's yaw so the flat veil plane aligns with the door.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_PORTAL_VEIL,
                fx("portal_soul_veil"),
                fx("door_glow_motes"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                FerrymanFinaleFxRows::yawAlignedLeg));
        // F-046 — one fog-bank segment of the arena mist wall (re-fired per segment on
        // the morph layer's cadence). a = segment yaw.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_ARENA_MIST,
                fx("arena_mist_wall"),
                fx("growth_dust_wall"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                FerrymanFinaleFxRows::yawAlignedLeg));
        // F-046b — Seelenernte ground-circle telegraph (44t one-shot, fired 2 s before
        // the pull). REPLACE: the fairness read must exist on EVERY client, so the
        // contract-omen ring is the photon-less floor.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_FERRY_HARVEST,
                fx("ferry_harvest_ring"),
                fx("contract_omen_ring"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // F-046b — Ruderschlag-Welle crest, yaw-aimed along the boss's facing (a = yaw).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_FERRY_WAVE,
                fx("ferry_wave_crest"),
                fx("riss_wave_front"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.REPLACE,
                false,
                FerrymanFinaleFxRows::yawAlignedLeg));
        // F-045b — gate-breach wisp gush (a = gate yaw, the burst pours out of the
        // door); also reused as the Geisterbeschwörung cast puff.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WISP_GUSH,
                fx("wisp_gush"),
                fx("ghost_departure_wisp"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                FerrymanFinaleFxRows::yawAlignedLeg));
    }

    /**
     * Shared yaw-aligned Photon leg: the payload's {@code a} float carries an entity
     * yaw in degrees; rotate the executor by {@code 180° − a} about Y so the asset's
     * local −Z bulge/plane aligns with that facing (Minecraft forward for yaw φ is
     * (−sin φ, 0, cos φ); JOML rotationY(θ) maps −Z to (−sin θ, 0, −cos θ) ⇒
     * θ = 180° − φ — the {@code BossPhotonFxRows.wardenEyeLaser} derivation).
     */
    private static boolean yawAlignedLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withRotationDeg(0.0D, 180.0D - a, 0.0D));
    }

    /**
     * F-045b client seam ({@code PortalKeyEntity.tick()}, client branch, while flying):
     * one looping violet-gold ribbon riding the key ({@code AutoRotate.NONE}; the loop
     * is safe — entity-bound, Photon auto-destroys it with the key). Photon's per-entity
     * CACHE dedup absorbs the per-tick calls; photon-less clients keep the server's
     * PORTAL/END_ROD breadcrumb particles as the baseline (LAYER semantics in code).
     *
     * @return {@code true} once a ribbon is live (or dedup'd) for this key; {@code false}
     *         = refused/unavailable, retry next tick is free
     */
    public static boolean keyTrail(Entity key) {
        if (PhotonBridge.liveEntityExecutors() >= MAX_ENTITY_EXECUTORS_FOR_TRAIL) {
            return false;
        }
        return PhotonBridge.spawnOnEntity(KEY_TRAIL, key,
                PhotonBridge.AUTO_ROTATE_NONE, (Vec3) null);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
