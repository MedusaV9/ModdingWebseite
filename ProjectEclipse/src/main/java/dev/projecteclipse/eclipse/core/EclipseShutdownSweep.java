package dev.projecteclipse.eclipse.core;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ferryman.finale.DayRiftOrbits;
import dev.projecteclipse.eclipse.ritual.CreditsSequence;
import dev.projecteclipse.eclipse.sequence.NetherUpheavalFx;
import dev.projecteclipse.eclipse.sequence.StormDebrisFx;
import dev.projecteclipse.eclipse.sequence.endarrival.EndArrivalDebrisFx;
import dev.projecteclipse.eclipse.stormfx.StormSiege;
import dev.projecteclipse.eclipse.woah.echogrove.EchoOverlayBuilder;
import dev.projecteclipse.eclipse.woah.echogrove.EchoSceneService;
import dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftOrbitals;
import dev.projecteclipse.eclipse.woah.mansiondome.DomeShatterFx;
import dev.projecteclipse.eclipse.worldgen.end.EndIslandCrashFx;
import dev.projecteclipse.eclipse.worldgen.stage.ExpansionBorderFx;
import dev.projecteclipse.eclipse.worldgen.stage.StructureFlightFx;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;

/**
 * F-080 shutdown sweep: force-clears every live FX display swarm on
 * {@link ServerStoppingEvent} — BEFORE the final save and the per-level close loop of
 * {@code MinecraftServer.stopServer()}, where a still-live thousand-display swarm can
 * wedge the chunk/entity flush forever (the "stuck in SAVING" hang, PLAN-F080 RC-1).
 *
 * <p>Every service keeps its own {@code ServerStoppedEvent} handler untouched as the
 * idempotent static-reset second pass, and the join-time tag sweeps keep covering
 * whatever a hard kill still persisted to disk. This sweep only pulls the DISCARD half
 * of each service's existing abort path forward to the last moment the entities are
 * cheap to drop.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseShutdownSweep {

    private EclipseShutdownSweep() {}

    @SubscribeEvent
    public static void onServerStopping(ServerStoppingEvent event) {
        MinecraftServer server = event.getServer();

        // Single-instance cinematic swarms: clearAll() is their existing abort path.
        if (StormDebrisFx.isActive()) {
            StormDebrisFx.clearAll();
            EclipseMod.LOGGER.info("ShutdownSweep: StormDebrisFx swarm discarded");
        }
        if (EndArrivalDebrisFx.isActive()) {
            EndArrivalDebrisFx.clearAll();
            EclipseMod.LOGGER.info("ShutdownSweep: EndArrivalDebrisFx stream discarded");
        }
        if (NetherUpheavalFx.isActive()) {
            int pieces = NetherUpheavalFx.livePieces();
            NetherUpheavalFx.clearAll();
            EclipseMod.LOGGER.info("ShutdownSweep: NetherUpheavalFx discarded {} piece(s)", pieces);
        }
        if (DomeShatterFx.isActive()) {
            DomeShatterFx.clearAll();
            EclipseMod.LOGGER.info("ShutdownSweep: DomeShatterFx burst discarded");
        }
        if (EndIslandCrashFx.isActive()) {
            EndIslandCrashFx.clearAll();
            EclipseMod.LOGGER.info("ShutdownSweep: EndIslandCrashFx cluster discarded");
        }

        // Multi-instance / reconcile-based services: the forceClearNow hooks reuse each
        // service's existing discard path and report how many displays they dropped.
        int siegeDisplays = StormSiege.forceClearNow();
        if (siegeDisplays > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: StormSiege discarded {} display(s)", siegeDisplays);
        }
        int boulderShards = ExpansionBorderFx.forceClearNow(server);
        if (boulderShards > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: ExpansionBorderFx gates released, {} boulder shard(s) discarded",
                    boulderShards);
        }
        int flightPieces = StructureFlightFx.forceClearNow();
        if (flightPieces > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: StructureFlightFx discarded {} delivery piece(s) "
                    + "(pending rows persist; placement re-runs next boot)", flightPieces);
        }
        int riftOrbitals = GravityRiftOrbitals.forceClearNow(server);
        if (riftOrbitals > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: GravityRiftOrbitals discarded {} orbital(s) "
                    + "(next boot's reconcile respawns them)", riftOrbitals);
        }
        int creditsDisplays = CreditsSequence.forceClearNow();
        if (creditsDisplays > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: CreditsSequence aborted, {} display(s) discarded",
                    creditsDisplays);
        }
        // DayRiftOrbits.discardAll logs its own discard line; the persisted orbit count
        // rebuilds the swarm through the next boot's reconcile pass.
        DayRiftOrbits.discardAll(server.overworld());

        // Echo grove: memory scenes + overlay pool (rebuilt lazily on the next boot).
        int echoActors = EchoSceneService.actorCount();
        EchoSceneService.discardAll();
        if (echoActors > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: EchoSceneService discarded {} actor display(s)", echoActors);
        }
        int overlayPool = EchoOverlayBuilder.poolSize();
        EchoOverlayBuilder.discardPool();
        if (overlayPool > 0) {
            EclipseMod.LOGGER.info("ShutdownSweep: EchoOverlayBuilder discarded {} overlay display(s)", overlayPool);
        }
    }
}
