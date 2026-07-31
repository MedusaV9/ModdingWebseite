package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * FX-WAVE-13 team C4's {@link PhotonFxRegistry} row registrar — the two NEW small-cue
 * effects of census §6 ({@code docs/plans_v3/session_0730/FX_CENSUS_WAVE13.md}). Both
 * assets are authored programmatically by {@code tools/photon/wave13c_smallcues_fx.py}
 * (fxlib); re-run that script instead of hand-editing the gzip-NBT.
 *
 * <ul>
 *   <li><b>N8 contract seal brand</b> ({@link #CUE_CONTRACT_SEAL_BRAND}) — the seal
 *       glyph sears itself into the ground at the contract resolution and glimmers for
 *       60 s. Server half: {@code contracts/ContractService.finishWindow}, the single
 *       funnel every resolution path already passes through, one send per ONLINE player
 *       at that player's own feet — the same personal-anonymity lane the neighbouring
 *       {@code CUE_CONTRACT_OMEN} release ripple uses, so the brand cannot be used to
 *       triangulate who the hunter or the target was.</li>
 *   <li><b>N14 sanctum confession</b> ({@link #CUE_SANCTUM_CONFESSION}) — entering the
 *       L5 Sanctum, script glyphs rise out of the crater like prayers and are drunk by
 *       the Lightfall column. Client-only: {@link SanctumConfession} below owns the
 *       window, so there is no packet and no server edit at all.</li>
 * </ul>
 *
 * <p>Cue ids follow the {@code CutsceneBeatFxRows}/{@code CreditsSequence} two-sided
 * precedent: both sides derive the same {@code FxCues.cue("…")} id (the server holds a
 * private constant, this registrar re-derives it), so {@code FxCues.java} — which is
 * NOT C4 ground this wave — stays untouched.</p>
 *
 * <p>Both rows are Photon-only garnish ({@code Mode.LAYER}, Quasar leg {@code null}):
 * legal for NEW cues, whose pre-row baseline was nothing (the {@code Row} javadoc law).
 * {@code reducedFx} drops both — the contract resolution is already carried by the omen
 * release ripple, the banner and the music stop, and the Sanctum by its own lightfall.
 * The bridge's own guard chain enforces that; the brand leg checks it explicitly too so
 * a reduced client never even computes its scale.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class SmallCueFxRows {
    /**
     * N8 — contract resolution brand ({@code eclipse:contract_seal_brand}, 60 s
     * one-shot). {@code a} = the receiving player's yaw in degrees at the resolution
     * (the rune is stamped in the direction they were facing, so two players standing
     * together do not get two identically-aligned sigils); {@code b} = 1 when the
     * window ended in blood (SUCCESS / TABLES_TURNED), 0 for a lapse (EXPIRED / VOIDED
     * / the prank reveal).
     */
    public static final ResourceLocation CUE_CONTRACT_SEAL_BRAND = FxCues.cue("contract_seal_brand");
    /**
     * N14 — L5 Sanctum confession ({@code eclipse:sanctum_confession}, 10 s one-shot),
     * fired client-locally by {@link SanctumConfession}; never sent over the wire.
     */
    public static final ResourceLocation CUE_SANCTUM_CONFESSION = FxCues.cue("sanctum_confession");

    /** N8: a brand burned over a kill is bigger than one left by a window that lapsed. */
    private static final double BRAND_SCALE_BLOOD = 1.15D;
    private static final double BRAND_SCALE_LAPSE = 0.85D;

    private SmallCueFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // N8 — SEQUENCE: at most one per contract window (a window resolves exactly
        // once), and it lands in the same beat as the omen release ripple.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CONTRACT_SEAL_BRAND,
                fx("contract_seal_brand"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                SmallCueFxRows::sealBrandLeg));
        // N14 — SEQUENCE: one per sanctum entry, and the window's hysteresis band plus
        // the L5 gate make re-entry spam impossible. Registered even though the cue is
        // fired client-locally: the row is what carries the reducedFx/budget policy and
        // what `/photon` dev introspection lists.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_SANCTUM_CONFESSION,
                fx("sanctum_confession"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                SmallCueFxRows::confessionLeg));
    }

    // ------------------------------------------------------------------ N8 leg

    /**
     * N8 leg: stamp the brand flat on the ground under the receiving player, rotated to
     * their facing and scaled by the outcome. The asset's own emitters are
     * {@code Horizontal}, so the executor's Y rotation spins the sigil in the ground
     * plane rather than tipping it; X/Z scale widens the burn while Y stays 1 (the
     * smoke and the ember lift are authored in absolute blocks).
     *
     * <p>{@code allowMulti} is deliberately NOT set: a second brand on the same anchor
     * inside one 60 s life would be a second contract resolving at the identical block,
     * which cannot happen (windows are strictly serial) — so Photon's same-anchor dedup
     * is a free guard against a double-send.</p>
     */
    private static boolean sealBrandLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (EclipseClientConfig.reducedFx()) {
            return true; // the omen release ripple + banner already carry the resolution
        }
        double scale = b > 0.5F ? BRAND_SCALE_BLOOD : BRAND_SCALE_LAPSE;
        // House yaw leg (FerrymanFinaleFxRows / CutsceneBeatFxRows): 180° − a about Y
        // aligns the asset's local −Z with the reported facing. Entity yaws are not
        // range-normalized on the wire (a spinning player accumulates), so wrap first.
        double yaw = 180.0D - Mth.wrapDegrees(a);
        return PhotonBridge.spawn(photonFx, pos, PhotonBridge.SpawnOptions.DEFAULT
                .withRotationDeg(0.0D, yaw, 0.0D)
                .withScale(scale, 1.0D, scale));
    }

    // ------------------------------------------------------------------ N14 leg

    /**
     * N14 leg. Shared by the row and by {@link SanctumConfession}, which calls it
     * directly: {@code PhotonFxRegistry.dispatch} reports only whether the cue was
     * REGISTERED, and the window controller needs to know whether the effect actually
     * STARTED so it can retry a budget refusal instead of silently arming itself off.
     *
     * @return whether a Photon effect started
     */
    private static boolean confessionLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        return !EclipseClientConfig.reducedFx() && PhotonBridge.spawn(photonFx, pos);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    // ------------------------------------------------------------------ N14 window

    /**
     * N14 window controller — the {@code WorldEventPhotonFxRows.DungeonMawIdle} /
     * {@code SanctumLightfall} pattern, except that the payload is a ONE-SHOT rather
     * than a loop: the confession fires once when the camera crosses into the sanctum
     * and re-arms only after it has left past the release distance.
     *
     * <p>The gate is deliberately the SAME gate {@code client/sanctum/SanctumLightfall}
     * uses for the column the glyphs climb into — overworld, {@link FxAnchors#ALTAR_CENTER}
     * synced, not {@code reducedFx}, and the physical float probe
     * ({@value #FLOAT_PROBE_BELOW} below the anchor must be loaded AND air, which is only
     * ever true once the island actually floats). Both offsets are re-derived from the
     * published {@link AltarSanctumBuilder} / {@link FloatingSanctumBuilder} constants,
     * so this class stays in lockstep with the column instead of pinning a copy of it.
     * On top of that sits the L5 gate: {@code ClientStateCache.altarLevel >= 5}.</p>
     *
     * <p>The distance band is much tighter than the lightfall's own 96/110 — that band
     * is "can see the landmark", this one is "is IN the sanctum". Idle cost outside the
     * band: one distance check per tick.</p>
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class SanctumConfession {
        /** The confession needs the consecrated sanctum, not merely an altar. */
        static final int REQUIRED_ALTAR_LEVEL = 5;
        /** Fires on crossing INTO this radius of the altar anchor (blocks)… */
        static final double MATERIALIZE_DIST = 26.0D;
        /** …and only re-arms past this one (hysteresis — no doorway-shuffle spam). */
        static final double RELEASE_DIST = 40.0D;
        private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
        private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;

        /**
         * Column head: {@code SanctumLightfall} pours from here (altar anchor minus
         * {@code ALTAR_ABOVE_GROUND + 9}). The asset is authored around this point —
         * its glyphs are born 7 below it, on the crater floor the updraft rises from.
         */
        private static final int LIGHTFALL_BELOW_ANCHOR = AltarSanctumBuilder.ALTAR_ABOVE_GROUND + 9;
        /** Floating-gate probe: in the island/ground air gap (SanctumLightfall's probe). */
        private static final int FLOAT_PROBE_BELOW =
                AltarSanctumBuilder.ALTAR_ABOVE_GROUND + FloatingSanctumBuilder.ISLAND_LIFT - 3;
        /** Refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
        private static final int RETRY_TICKS = 40;
        /**
         * Give up after this many refusals per entry. A refusal here means Photon is
         * absent or the executor budget is saturated; retrying for the whole time the
         * player stands in their own sanctum would be a permanent 40-tick heartbeat for
         * an effect that is, by design, a greeting.
         */
        private static final int MAX_ATTEMPTS = 4;

        /** True while the camera is inside the band (armed = has not fired this entry). */
        private static boolean inside;
        private static boolean fired;
        private static int attempts;
        private static int retryCountdown;

        private SanctumConfession() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            Minecraft minecraft = Minecraft.getInstance();
            ClientLevel level = minecraft.level;
            if (level == null || level.dimension() != Level.OVERWORLD
                    || EclipseClientConfig.reducedFx()
                    || ClientStateCache.altarLevel < REQUIRED_ALTAR_LEVEL) {
                reset();
                return;
            }
            Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
            if (anchor == null) {
                reset();
                return;
            }
            double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
            if (distSq > (inside ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
                reset(); // walked out past the release band: re-arm for the next entry
                return;
            }
            if (minecraft.isPaused()) {
                return; // hold the window, freeze the cadence
            }
            inside = true;
            if (fired || attempts >= MAX_ATTEMPTS) {
                return;
            }
            if (--retryCountdown > 0) {
                return;
            }
            retryCountdown = RETRY_TICKS;
            if (!floating(level, anchor)) {
                return; // island not floating (yet) — there is no column to pray into
            }
            attempts++;
            Vec3 columnHead = anchor.add(0.0D, -LIGHTFALL_BELOW_ANCHOR, 0.0D);
            if (confessionLeg(fx("sanctum_confession"), columnHead, null, 0.0F, 0.0F)) {
                fired = true;
                EclipseMod.LOGGER.debug("SanctumConfession fired at {} (altar L{})",
                        columnHead, ClientStateCache.altarLevel);
            }
        }

        /** Disconnect reset — a fresh session is a fresh entry. */
        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            reset();
        }

        /** SanctumLightfall's physical float gate, re-derived from the same constants. */
        private static boolean floating(ClientLevel level, Vec3 anchor) {
            BlockPos probe = BlockPos.containing(anchor).below(FLOAT_PROBE_BELOW);
            return level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                    SectionPos.blockToSectionCoord(probe.getZ()))
                    && level.getBlockState(probe).isAir();
        }

        private static void reset() {
            inside = false;
            fired = false;
            attempts = 0;
            retryCountdown = 0;
        }
    }
}
