package dev.projecteclipse.eclipse.client.wizard;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.structure.WizardObservatory;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-IMPROVE-2 (IDEAS-world #10) — Orin's observatory hearth ambience: gusty ember
 * sparks curling out of the copper dome seam, one thin smoke wisp rising off the vent,
 * and warm dust motes hanging in the lantern light behind the portholes
 * ({@code eclipse:wizard_hearth}, all offsets baked in the asset against the
 * deterministic {@link WizardObservatory#buildAt} geometry). This is the WINDOWED-loop
 * controller mandated by INTEGRATION.md §4 — the {@code BreachAmbience}/{@code
 * SanctumLightfall} window school verbatim: a materialize/release hysteresis band
 * ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}, the doc's 48/60), a
 * {@value #RETRY_TICKS}-tick probe/retry cadence, unconditional release on
 * {@code reducedFx} / dimension change / logout.
 *
 * <p><b>Anchor, zero new sync:</b> the hut anchor is client-derivable — the authored
 * {@code disc_map.json} mountain center with the LOWEST deterministic
 * {@link DiscTerrainFunction#surfaceY} of the {@value WizardObservatory#FOOTPRINT}²
 * footprint, which is bit-exactly {@code WizardObservatory.summitAnchor()} (and
 * {@code SitePrep.preparePlateau} keeps that Y as the plateau, so the stamped hut floor
 * IS this Y). Computed once and cached — {@code DiscMapData} is frozen per save.</p>
 *
 * <p><b>Built gate</b> (the SanctumLightfall physical-probe law — whether the hut is
 * actually stamped is a server flag the client can't read): the loop only runs while
 * the block {@value #DOME_CAP_ABOVE} above the anchor is loaded AND waxed cut copper —
 * the dome's cap block, the highest center-column write of {@code buildAt}, and a
 * combination that never occurs naturally on the summit. Self-correcting: stage-erase
 * removes the cap, the probe fails, the loop releases.</p>
 *
 * <p><b>Fallback / budget:</b> the registry row has no Quasar leg by design (IDEAS-world
 * #10 fallback table: pure garnish — absence is today's behavior; photon-less clients
 * keep the hut exactly as shipped). Cost while open: ≤ 90 tiny particles + one trail
 * strip at ONE landmark, cull box + hard {@code maxParticles} in the asset. Idle cost
 * while far: one distance check per tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ObservatoryAmbience {
    /** Window materializes within this camera distance of the hut (IDEAS-world #10)… */
    private static final double MATERIALIZE_DIST = 48.0D;
    /** …and releases only beyond this one (hysteresis — no boundary thrash). */
    private static final double RELEASE_DIST = 60.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /**
     * Built-probe height above the anchor: {@code buildAt} caps the dome with a single
     * {@code WAXED_CUT_COPPER} at {@code y0 + 8} in the center column.
     */
    private static final int DOME_CAP_ABOVE = 8;
    /** Probe / refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
    private static final int RETRY_TICKS = 40;
    /** Footprint half-extent (mirrors the private {@code WizardObservatory.HALF}). */
    private static final int HALF = WizardObservatory.FOOTPRINT / 2;

    /** Whether the window is currently open (drives the hysteresis band). */
    private static boolean open;
    private static int retryCountdown;
    /** Lazily derived summit anchor (hut floor center); null = no mountain authored. */
    @Nullable
    private static BlockPos cachedAnchor;
    private static boolean anchorResolved;

    private ObservatoryAmbience() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            close(false);
            return;
        }
        BlockPos anchor = summitAnchor();
        if (anchor == null) {
            return; // no mountain authored in disc_map.json — no hut ever
        }
        Vec3 root = new Vec3(anchor.getX() + 0.5D, anchor.getY(), anchor.getZ() + 0.5D);
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(root);
        if (distSq > (open ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            close(true); // walked away: graceful fade, not a pop
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        if (--retryCountdown > 0) {
            return;
        }
        // Physical probe: the dome-cap copper only exists once the hut is stamped.
        BlockPos probe = anchor.above(DOME_CAP_ABOVE);
        if (!level.hasChunk(SectionPos.blockToSectionCoord(probe.getX()),
                SectionPos.blockToSectionCoord(probe.getZ()))
                || !level.getBlockState(probe).is(Blocks.WAXED_CUT_COPPER)) {
            close(false); // hut not built (yet) — keep probing on the cadence
            retryCountdown = RETRY_TICKS;
            return;
        }
        open = true;
        // Healthy leg: re-ensure every tick (idempotent prune + re-spawn of a pruned
        // leg). Refused (photon absent / missing asset / executor budget): back off.
        retryCountdown = PhotonFxRegistry.ensureLoop(FxCues.CUE_WIZARD_HEARTH, root)
                ? 1 : RETRY_TICKS;
    }

    /**
     * The client-side twin of {@code WizardObservatory.summitAnchor()}: mountain center
     * at the LOWEST deterministic surface Y of the footprint. Cached — the disc map and
     * the terrain function are both frozen per save.
     */
    @Nullable
    private static BlockPos summitAnchor() {
        if (anchorResolved) {
            return cachedAnchor;
        }
        anchorResolved = true;
        DiscMapData.Mountain mountain = DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        if (mountain == null) {
            cachedAnchor = null;
            return null;
        }
        int minY = Integer.MAX_VALUE;
        for (int dx = -HALF; dx <= HALF; dx++) {
            for (int dz = -HALF; dz <= HALF; dz++) {
                minY = Math.min(minY, DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD,
                        mountain.x() + dx, mountain.z() + dz));
            }
        }
        cachedAnchor = new BlockPos(mountain.x(), minY, mountain.z());
        return cachedAnchor;
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern; registry releases too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        close(false);
        // The next server may run a different frozen disc map — re-derive on demand.
        anchorResolved = false;
        cachedAnchor = null;
    }

    private static void close(boolean graceful) {
        if (open) {
            PhotonFxRegistry.releaseLoop(FxCues.CUE_WIZARD_HEARTH, graceful);
        }
        open = false;
        retryCountdown = 0;
    }
}
