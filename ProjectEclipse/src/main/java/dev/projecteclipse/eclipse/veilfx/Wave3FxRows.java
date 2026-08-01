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
 * F-103 Team C (WAVE3 "noch mehr Veil×Photon") {@link PhotonFxRegistry} row registrar —
 * three NEW cue families docked onto EXISTING server triggers. All seven assets are
 * authored programmatically by {@code tools/photon/wave3_fx.py} (fxlib); re-run that
 * script instead of hand-editing the gzip-NBT.
 *
 * <ul>
 *   <li><b>Altar purchase bloom</b> ({@link #CUE_ALTAR_BUY}) — the F-074 buy ceremony's
 *       shared t=0 beat ({@code AltarBuyCeremony.beatOpening}) now also fires one
 *       category-tinted Photon bloom over the altar crown: violet helix + gold ankle
 *       wave (TEAM), forge-spark fan + gift hover orbit (GEAR), rose ember fountain +
 *       bell halos (HEART). {@code a} = {@code AltarBuyCeremony.Category} ordinal
 *       (0 TEAM / 1 GEAR / 2 HEART); the asset's internal burst ticks mirror the
 *       ceremony's own script beats (wave 16/52, rise-end 30, bells 24/44/64), so the
 *       Photon layer and the scripted vanilla/Quasar beats land as one event.</li>
 *   <li><b>Vein-clear jackpot</b> ({@link #CUE_VEIN_JACKPOT}) — the W4-FEEL mining
 *       payoff: when the LAST block of a tracked ore vein breaks
 *       ({@code MiningFeelService.onNaturalOreMined}, {@code scan.present() == 1}), a
 *       compact spark pop lands at the closing block under the two-note chime.
 *       {@code a} = vein size (scales the pop), {@code b} = the packed 24-bit ore RGB
 *       already minted for the ore-proc sparkle seam — the leg only buckets it
 *       warm/cool to pick the asset variant (Photon has no runtime tint).</li>
 *   <li><b>Night omen</b> ({@link #CUE_NIGHT_OMEN}) — Pale/Umbral Night onset
 *       ({@code EclipseSpawner.announceNightEvent}): a personal omen at each player's
 *       OWN feet on the {@code FxPayloads.sendFxEventTo} personal-ceremony lane (the
 *       {@code CUE_DAWN_TOLL} / contract-seal-brand law — a range broadcast would
 *       stack N×N copies on clustered players). {@code a} = 0 pale / 1 umbral. Pale =
 *       ivory motes rising out of a ghost veil; Umbral = a reverse gulp of violet
 *       motes dragged down into a creeping near-black fog.</li>
 * </ul>
 *
 * <p>Cue ids follow the {@code CutsceneBeatFxRows}/{@code CreditsSequence} two-sided
 * naming precedent: server hooks re-derive the same {@code FxCues.cue("…")} id inline,
 * so {@code FxCues.java} (frozen/shared) stays untouched.</p>
 *
 * <p>All three rows are Photon-only garnish ({@code Mode.LAYER}, Quasar leg
 * {@code null}): legal for NEW cues, whose pre-row baseline was nothing (the
 * {@code Row} javadoc law). {@code reducedFx} drops all three — the purchase is
 * already carried by the ceremony's scripted beats, the vein clear by chime + toast,
 * the night event by the W8 announcement overlay. All assets are one-shots, so no
 * WINDOWED loop bookkeeping is needed; Photon's default same-anchor dedup
 * ({@code allowMulti=false}) is kept everywhere as a free anti-stack guard (a second
 * purchase bloom inside one ~5 s ceremony life at the same crown is deliberate
 * de-spam, not a loss).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class Wave3FxRows {
    /**
     * WAVE3 #1 — altar purchase bloom ({@code a} = Category ordinal 0 TEAM / 1 GEAR /
     * 2 HEART, {@code b} unused; ~5-6 s one-shot at the altar crown).
     */
    public static final ResourceLocation CUE_ALTAR_BUY = FxCues.cue("wave3_altar_buy");
    /**
     * WAVE3 #2 — vein-clear jackpot ({@code a} = vein size in blocks, {@code b} =
     * packed 24-bit ore RGB; ~3 s one-shot at the closing block's center).
     */
    public static final ResourceLocation CUE_VEIN_JACKPOT = FxCues.cue("wave3_vein_jackpot");
    /**
     * WAVE3 #3 — night-event omen ({@code a} = 0 pale / 1 umbral, {@code b} unused;
     * ~5 s one-shot at the receiving player's feet, personal lane).
     */
    public static final ResourceLocation CUE_NIGHT_OMEN = FxCues.cue("wave3_night_omen");

    /** Jackpot scale ramp: a 3-block vein pops at ~0.89, a 12+-block one at 1.3. */
    private static final double JACKPOT_SCALE_BASE = 0.75D;
    private static final double JACKPOT_SCALE_PER_BLOCK = 0.045D;
    private static final double JACKPOT_SCALE_MIN = 0.85D;
    private static final double JACKPOT_SCALE_MAX = 1.3D;

    private Wave3FxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // #1 — SEQUENCE: one per successful shard-shop buy (AltarBuyCeremony caps
        // concurrent runs at 8 and finishes the oldest early; same-anchor dedup
        // absorbs a burst of team buys at the same crown).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_ALTAR_BUY,
                fx("wave3_buy_team"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave3FxRows::altarBuyLeg));
        // #2 — BURST: naturally rate-limited (a full vein must be mined out per fire)
        // but the highest-frequency wave3 cue, hence the burst channel and the lean
        // 33-sprite asset.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_VEIN_JACKPOT,
                fx("wave3_vein_jackpot_warm"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave3FxRows::veinJackpotLeg));
        // #3 — SEQUENCE: at most one per night (nightfall roll), personal lane means
        // exactly one copy per client, ever.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_NIGHT_OMEN,
                fx("wave3_omen_pale"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                Wave3FxRows::nightOmenLeg));
    }

    // ------------------------------------------------------------------ #1 leg

    /**
     * Altar-buy leg: picks the category variant off {@code a} (the
     * {@code AltarBuyCeremony.Category} ordinal — TEAM 0, GEAR 1, HEART 2; out-of-range
     * degrades to TEAM, matching the row's default asset). The row's {@code photonFx}
     * is that default; the leg re-resolves the sibling ids authored by the same
     * generator.
     */
    private static boolean altarBuyLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the scripted ceremony (Quasar beams, dust, bells) carries it
        }
        ResourceLocation variant = switch ((int) a) {
            case 1 -> fx("wave3_buy_gear");
            case 2 -> fx("wave3_buy_heart");
            default -> photonFx; // TEAM (and any unknown future category)
        };
        return PhotonBridge.spawn(variant, pos);
    }

    // ------------------------------------------------------------------ #2 leg

    /**
     * Vein-jackpot leg: buckets the packed ore RGB ({@code b}, the exact-in-a-float
     * 24-bit int the ore-proc sparkle seam already ships) into the warm or cool asset
     * variant — red-dominant ores (coal/copper/iron/gold/redstone) pop amber-gold,
     * blue-dominant ones (lapis/diamond/emerald + the accent-purple fallback) pop
     * cyan-arc — and scales the pop with the vein size ({@code a}).
     */
    private static boolean veinJackpotLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // chime + "Vein cleared" toast already carry the payoff
        }
        int rgb = (int) b;
        int red = (rgb >> 16) & 0xFF;
        int blue = rgb & 0xFF;
        ResourceLocation variant = red >= blue ? photonFx : fx("wave3_vein_jackpot_cool");
        double scale = Mth.clamp(JACKPOT_SCALE_BASE + JACKPOT_SCALE_PER_BLOCK * a,
                JACKPOT_SCALE_MIN, JACKPOT_SCALE_MAX);
        return PhotonBridge.spawn(variant, pos, PhotonBridge.SpawnOptions.DEFAULT
                .withScale(scale, scale, scale));
    }

    // ------------------------------------------------------------------ #3 leg

    /**
     * Night-omen leg: {@code a} picks pale (0) or umbral (1); the anchor is the
     * receiving player's own feet at send time (the omen is a stamp on the ground the
     * night crossed, not an attachment — the seal-brand precedent).
     */
    private static boolean nightOmenLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the W8 typewriter/sweep announcement carries the event
        }
        ResourceLocation variant = a > 0.5F ? fx("wave3_omen_umbral") : photonFx;
        return PhotonBridge.spawn(variant, pos);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
