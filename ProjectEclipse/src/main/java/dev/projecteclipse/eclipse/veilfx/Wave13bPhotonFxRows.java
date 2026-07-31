package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * FX-WAVE-13 team B1 registrar — Photon hero legs for three of the ten Quasar-only lanes
 * (FX_CENSUS_WAVE13 §3): the heart-fragment deposit, every boss ground slam, and the
 * ring-expansion chunk materialization. Assets are authored programmatically by
 * {@code tools/photon/wave13b_fx.py} (fxlib) into {@code assets/eclipse/fx/hero_*.fx} —
 * re-run the script instead of hand-editing the gzip-NBT. Emitter tables, timings and
 * palettes: {@code docs/plans_v3/session_0730/B1_HEROLEGS_REPORT.md}.
 *
 * <p><b>Why this is not a {@link PhotonFxRegistry} row set.</b> {@link PhotonFxRegistry}
 * rows consume {@code FxCues} ids arriving on {@code S2CFxEventPayload}. These three cues
 * ride the OTHER lane — {@code S2CQuasarPayload} → {@code EclipsePayloads.handleQuasar} —
 * whose only Photon seam is the hard-coded chain in
 * {@link PhotonBridge#enhanceQuasarCue}. This class therefore mirrors the row contract by
 * hand in {@link #enhanceQuasarCue}: same LAYER/REPLACE semantics, same
 * degrade-never-below-baseline law, but keyed on the Quasar emitter id.</p>
 *
 * <p><b>Integrator hook</b> (conflict law §7.4 — {@code PhotonBridge} is shared core, so
 * B1 does not edit it): one delegation at the top of
 * {@code PhotonBridge.enhanceQuasarCue}. The {@code Boolean} return keeps the hook
 * order-neutral — {@code null} means "not one of mine, keep walking the chain", so the
 * four existing branches stay bit-identical:</p>
 * <pre>{@code
 * Boolean b1 = Wave13bPhotonFxRows.enhanceQuasarCue(emitterId, pos);
 * if (b1 != null) {
 *     return b1;
 * }
 * }</pre>
 *
 * <p><b>Modes per leg.</b> {@code heart_burst} is LAYER: the Quasar sketch's seven
 * literal heart sprites say "a heart" in a way the abstract Photon shards cannot, and the
 * two read as one object (the hero leg borrows the sketch's {@code #F3C9FF} mid stop).
 * {@code boss_slam} and {@code map_expand_materialize} are REPLACE: their Quasar emitters
 * occupy exactly the beat the Photon leg rebuilt (colliding debris / block cubes drawn
 * into a point attractor) and both are {@code additive: true} from {@code #FFFFFF} — the
 * stacking law's textbook case of vanilla white drowning the Photon body. Both re-enter
 * automatically whenever the Photon leg does not play (photon-less client, reducedFx,
 * executor cap, missing asset).</p>
 *
 * <p><b>Stage classes</b> (§6.1, {@link WorldStageArbiter}): {@code BOSS_SLAM} is already
 * registered S-class by {@link SignaturePhotonFxRows} (first registration wins — not
 * touched here), so {@code handleQuasar}'s soft gate sheds this hero layer under a
 * contested frame before the hook is ever reached. B1 adds the two missing classes for
 * documentation: heart bursts are A-class accents and materialization is a B-class bed;
 * both are pass-through by design and never claim the token.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class Wave13bPhotonFxRows {
    /** Heart-fragment deposit: flash → shards → indraw → acceptance → afterglow (72t). */
    public static final ResourceLocation HERO_HEART_BURST = fx("hero_heart_burst");
    /** Boss ground slam: double shock ring + ballistic chips + settling dust (130t). */
    public static final ResourceLocation HERO_BOSS_SLAM = fx("hero_boss_slam");
    /** Ring expansion: materialization columns + dissolving glint veil (86t). */
    public static final ResourceLocation HERO_EXPAND_MATERIALIZE = fx("hero_expand_materialize");

    /** A-class accent lease for the heart cue (pass-through; documented, never claims). */
    private static final int HEART_LEASE_TICKS = 24;
    /** B-class bed lease for the materialization cue (pass-through; never claims). */
    private static final int EXPAND_LEASE_TICKS = 20;

    /**
     * Minimum spacing between two live materialization heroes, in blocks.
     *
     * <p>{@code RingGrowthService} fires {@code map_expand_materialize} at up to one
     * surface point every 5 ticks for the whole growth sweep. The asset lives 86 t, so an
     * unthrottled hero leg would hold ~17 of the bridge's {@value PhotonBridge#MAX_LIVE_EXECUTORS}
     * executors on this one cue and starve every other effect on screen. Instead the leg
     * declines when a sibling is already live within this radius and lets the cheap Quasar
     * sparkle carry that column — dense frontiers get hero columns at a readable spacing
     * plus the Quasar bed between them, which is also the better picture.</p>
     */
    private static final double EXPAND_SPACING_BLOCKS = 14.0D;

    private Wave13bPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        WorldStageArbiter.registerCue(S2CQuasarPayload.HEART_BURST,
                WorldStageArbiter.StageClass.A, HEART_LEASE_TICKS);
        WorldStageArbiter.registerCue(S2CQuasarPayload.MAP_EXPAND_MATERIALIZE,
                WorldStageArbiter.StageClass.B, EXPAND_LEASE_TICKS);
    }

    /**
     * {@code PhotonBridge.enhanceQuasarCue} delegation (client main thread) — see the
     * class doc for the one-line hook.
     *
     * @return {@code null} when {@code emitterId} is not a B1 leg (caller keeps walking
     *         its chain); {@code TRUE} when the Quasar leg must be skipped (a REPLACE
     *         hero leg played); {@code FALSE} when the Quasar leg must run (LAYER legs,
     *         and REPLACE legs whose Photon spawn was refused — the baseline law)
     */
    @Nullable
    public static Boolean enhanceQuasarCue(ResourceLocation emitterId, Vec3 pos) {
        if (S2CQuasarPayload.HEART_BURST.equals(emitterId)) {
            playHeartBurst(pos);
            return Boolean.FALSE; // LAYER — the Quasar heart sprites keep flying
        }
        if (S2CQuasarPayload.BOSS_SLAM.equals(emitterId)) {
            return playBossSlam(pos);
        }
        if (S2CQuasarPayload.MAP_EXPAND_MATERIALIZE.equals(emitterId)) {
            return playExpandMaterialize(pos);
        }
        return null;
    }

    /**
     * Heart-fragment deposit hero leg (LAYER). Exact sub-block anchoring: the cue fires at
     * the altar crown {@code +1.2}, at a buyer's chest or over a corpse, and the default
     * block-centre anchor would drop the core flash up to half a block off the fragment.
     *
     * @return {@code true} iff the Photon leg played (the LAYER caller ignores it; exposed
     *         for the same-shape call sites that want to know)
     */
    public static boolean playHeartBurst(Vec3 pos) {
        return PhotonBridge.spawn(HERO_HEART_BURST, pos, PhotonBridge.SpawnOptions.DEFAULT);
    }

    /**
     * Boss ground-slam hero leg (REPLACE). {@code allowMulti}: the Ferryman slams
     * repeatedly from the same deck position and the Herald's corona shards crash in
     * clusters — inside the asset's 130 t life Photon's same-anchor dedup would silently
     * eat the second and third slam.
     *
     * @return {@code TRUE} = Photon played, skip Quasar; {@code FALSE} = run the Quasar
     *         baseline (bridge refusal)
     */
    public static Boolean playBossSlam(Vec3 pos) {
        return PhotonBridge.spawn(HERO_BOSS_SLAM, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
    }

    /**
     * Chunk-materialization hero leg (REPLACE), throttled by {@link #EXPAND_SPACING_BLOCKS}.
     * Also the entry point for the two client-local senders that bypass
     * {@code handleQuasar} entirely ({@code ExpansionSequence}'s flyover garnish and
     * {@code RiftFx}'s rift ambient both call {@code QuasarSpawner.spawn} directly) —
     * those may adopt it with a one-line swap, see the B1 report §2.
     *
     * @return {@code TRUE} = Photon played, skip Quasar; {@code FALSE} = run the Quasar
     *         baseline (too close to a live sibling, or a bridge refusal)
     */
    public static Boolean playExpandMaterialize(Vec3 pos) {
        if (PhotonBridge.hasLiveFx(HERO_EXPAND_MATERIALIZE, pos, EXPAND_SPACING_BLOCKS)) {
            return Boolean.FALSE;
        }
        return PhotonBridge.spawn(HERO_EXPAND_MATERIALIZE, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
