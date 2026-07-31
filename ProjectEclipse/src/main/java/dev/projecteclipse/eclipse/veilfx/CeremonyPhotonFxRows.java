package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.ritual.ReviveRitual;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * NEWFX-B's {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the altar/souls/ceremonies package of PLAN-NEWFX §2 (B1–B5). Assets are
 * fxlib-generated ({@code tools/photon/ceremony_fx.py} is the committed source); Quasar
 * fallback emitters live beside the shipped set under
 * {@code assets/eclipse/quasar/emitters/}.
 *
 * <p>Per-row shape (PLAN-NEWFX §2 specs):</p>
 * <ul>
 *   <li><b>B1 dawn toll</b> — custom leg, both layers spawned in-leg so the plan's
 *       reducedFx law ("skip entirely; reduced players keep the pre-plan bells-only
 *       dawn") can gate Photon AND Quasar with one check. Entity lane, personal send.</li>
 *   <li><b>B2 rebirth starfall</b> — the package's one {@code Mode.REPLACE} row: the
 *       Photon file IS the ceremony; the {@code eclipse:rebirth_ring} Quasar leg runs
 *       only when the Photon spawn refuses (photon-less / reducedFx clients). The old
 *       vanilla TOTEM/REVERSE_PORTAL/END_ROD spam was removed at the seam.</li>
 *   <li><b>B3 offering gutter</b> — plain LAYER row. Default {@code allowMulti=false}
 *       doubles as the anti-spam: repeated "already offered" clicks inside the ~40t
 *       runtime dedup the Photon show while the cheap Quasar ash puff still answers
 *       every click (BURST budget caps the worst case).</li>
 *   <li><b>B4 soul departure / B5 revive thunderbloom</b> — plain LAYER rows on the
 *       SEQUENCE channel (rare, dramatic); under reducedFx the Photon leg is off by
 *       {@code PhotonBridge.available()} and the Quasar wisp/ring stays — exactly the
 *       plan's reduced forms.</li>
 *   <li><b>FX-WAVE-13 N9 revive soul thread</b> — three Photon-only rows (one per
 *       tautness stage) on the AMBIENT channel, aimed by the cue's a/b and stacked with
 *       {@code allowMulti} so the 40 t re-send cadence reads as one continuous thread.</li>
 * </ul>
 *
 * <p>FX-WAVE-13 P4 also hangs the escalating dawn rift off the B1 leg: the same cue now
 * opens 0–3 {@code dawn_toll_rift} overlays depending on the day, so the daily beat keeps
 * growing instead of looking identical on day 40 and day 2.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CeremonyPhotonFxRows {
    /**
     * B1 Quasar layer: bell-glint dust shed under the petal triangle. The Photon petals
     * hang ~7 blocks over the EYE anchor; the glint emitter is spawned at feet + this.
     */
    private static final double DAWN_GLINT_HEIGHT = 8.0D;
    /** B1 position-anchor degrade: approximate the missing entity's eye height. */
    private static final double DAWN_EYE_FALLBACK = 1.6D;

    /**
     * FX-WAVE-13 P4 — the escalating dawn rift. One overlay tear in the sky per entry,
     * unlocked by day: nothing for the first week of grace, then the sky visibly keeps
     * splitting further open every few days. Executor {@code scale} deliberately is NOT
     * the escalation knob (it scales the transform, not the World-space particle speeds
     * the bleed is authored around) — more rifts is.
     */
    private static final int[] DAWN_RIFT_UNLOCK_DAY = {6, 10, 13};
    /**
     * Bearing of the nth rift around the player, in degrees. Golden-angle spaced so no
     * two tears ever line up into one bright wall, and none of them sits dead ahead of
     * the spawn-facing player.
     */
    private static final double[] DAWN_RIFT_YAW = {-42.0D, 95.0D, 222.0D};
    /** Ticks between rift openings — the sky tears one seam at a time, not all at once. */
    private static final int DAWN_RIFT_STAGGER = 7;
    /** The escalation overlay asset ({@code tools/photon/ceremony_fx.py}). */
    private static final ResourceLocation DAWN_TOLL_RIFT = fx("dawn_toll_rift");

    /**
     * FX-WAVE-13 N9 — the three tautness stages of the revive soul thread. Index =
     * {@code stage - 1}, matching {@link ReviveRitual#CUE_SOUL_THREAD}; the server picks
     * the stage from the ritual progress and re-sends every 40 t.
     */
    private static final ResourceLocation[] SOUL_THREAD = {
            fx("revive_soul_thread_1"), fx("revive_soul_thread_2"), fx("revive_soul_thread_3")};

    private CeremonyPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // B1 — dawn toll bloom (entity lane, personal; asset paces itself to the bells).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_DAWN_TOLL,
                fx("dawn_toll_bloom"),
                null, // Quasar layer spawned in-leg (reducedFx gates both legs at once)
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                CeremonyPhotonFxRows::dawnTollBloom));
        // B2 — Starfall Rebirth (entity lane on the reborn player, REPLACE hero).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_REBIRTH_CEREMONY,
                fx("rebirth_starfall"),
                quasar("rebirth_ring"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // B3 — offering gutter (position lane at the altar crown, the anti-climax).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_OFFERING_REJECT,
                fx("offering_gutter"),
                quasar("offering_gutter_puff"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B4 — soul departure (position lane at the corpse of a FINAL death).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_GHOST_DEPARTURE,
                fx("ghost_soul_departure"),
                quasar("ghost_departure_wisp"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B5 — revive thunderbloom (position lane at the altar crown, range 96).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_REVIVE_COMPLETE,
                fx("revive_thunderbloom"),
                quasar("revive_thunderbloom_ring"),
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // N9 — revive soul thread: three tautness stages, re-sent by ReviveRitual every
        // 40 t. Photon-only garnish (no Quasar leg — a photon-less client keeps the
        // pre-plan beam column, which is still the whole photon-less read of the ritual)
        // on the AMBIENT channel: this is a 3-minute-long background strand, not a beat.
        for (int stage = 0; stage < SOUL_THREAD.length; stage++) {
            PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                    ReviveRitual.CUE_SOUL_THREAD[stage],
                    SOUL_THREAD[stage],
                    null,
                    FxBudget.Channel.AMBIENT,
                    PhotonFxRegistry.Mode.LAYER,
                    false,
                    CeremonyPhotonFxRows::soulThread));
        }
    }

    /**
     * {@code CUE_SOUL_THREAD_*} leg — FX-WAVE-13 N9. Two things the default leg cannot do:
     * <ul>
     *   <li><b>aim</b> — {@code a}/{@code b} are the X/Y Euler pair that rotates the
     *       asset's local +Z onto the sigil→grave vector (server-solved, see
     *       {@code ReviveRitual.sendSoulThread});</li>
     *   <li><b>{@code allowMulti}</b> — the cue is re-sent from the SAME anchor every
     *       40 t. With the default same-anchor dedup Photon would swallow every re-send
     *       after the first, the 44 t asset would run out, and the thread would blink out
     *       33 s into a 3-minute ritual. Stacking is bounded: 44 t runtime over a 40 t
     *       cadence means at most two overlapping instances, which IS the crossfade.</li>
     * </ul>
     */
    private static boolean soulThread(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true;
        }
        return PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT
                .withRotationDeg(a, b, 0.0D)
                .withAllowMulti(true));
    }

    /**
     * {@code CUE_DAWN_TOLL} leg — PLAN-NEWFX B1. reducedFx skips the WHOLE composition
     * (the ceremony's sun pulse + bells already carry the beat; reduced players keep the
     * exact pre-plan dawn), which is why the Quasar glint layer is spawned here instead
     * of riding the row's quasar column: a LAYER row would play it under reducedFx.
     * Consumed cues always return {@code true} — with a {@code null} row emitter there
     * is no REPLACE re-entry to drive.
     */
    private static boolean dawnTollBloom(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true;
        }
        Vec3 feet = entity != null ? entity.position() : pos;
        // Bell-glint dust under the petal triangle (the photon-less baseline too).
        QuasarSpawner.spawn(quasar("dawn_toll_glint"),
                feet.add(0.0D, DAWN_GLINT_HEIGHT, 0.0D), FxBudget.Channel.SEQUENCE);
        if (entity != null) {
            // The receiving player is always client-tracked (the cue is addressed to
            // them alone), so this is the live path; petals ride the eye anchor.
            PhotonBridge.spawnOnEntity(photonFx, entity,
                    PhotonBridge.AUTO_ROTATE_NONE, (Vec3) null);
        } else {
            PhotonBridge.spawn(photonFx, pos.add(0.0D, DAWN_EYE_FALLBACK, 0.0D));
        }
        openDawnRifts(feet, dawnDay(a));
        return true;
    }

    /**
     * FX-WAVE-13 P4: the day the bloom belongs to. {@code CUE_DAWN_TOLL}'s sender
     * ({@code drama.DawnCeremony}) is photon-blind and still ships {@code a = 0}, so the
     * day comes from the client's own day-state mirror — but an {@code a > 0} is honoured
     * as an override the moment the sender starts filling it in, without a second row or
     * a re-registration.
     */
    private static int dawnDay(float a) {
        return a >= 1.0F ? (int) a : ClientStateCache.day;
    }

    /**
     * FX-WAVE-13 P4: opens the day's sky tears around the dawning player. Position-lane
     * (not entity-attached) on purpose — the tears belong to the SKY, so they must stay
     * where the sun came up while the player walks off. {@code allowMulti} is required:
     * the three seams share one asset id and one anchor and would otherwise dedup down
     * to a single tear.
     */
    private static void openDawnRifts(Vec3 feet, int day) {
        for (int i = 0; i < DAWN_RIFT_UNLOCK_DAY.length; i++) {
            if (day < DAWN_RIFT_UNLOCK_DAY[i]) {
                return; // thresholds ascend: the first miss ends the escalation
            }
            PhotonBridge.spawn(DAWN_TOLL_RIFT, feet, PhotonBridge.SpawnOptions.DEFAULT
                    .withRotationDeg(0.0D, DAWN_RIFT_YAW[i], 0.0D)
                    .withDelay(i * DAWN_RIFT_STAGGER)
                    .withAllowMulti(true));
        }
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    private static ResourceLocation quasar(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
