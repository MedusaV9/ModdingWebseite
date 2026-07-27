package dev.projecteclipse.eclipse.woah.resonance.client;

import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.woah.resonance.ResonanceMelodyMachine;
import dev.projecteclipse.eclipse.woah.resonance.S2CResonanceFieldPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * WOAH-04 §4.1 — the client mirror of the resonance-field geometry + puzzle state
 * (the {@code FxAnchors.CLIENT_ANCHORS} school): fed by
 * {@code EclipsePayloads.handleResonanceField}, cleared on logout. The choir
 * ({@link ResonanceChoir}), the Photon windows ({@link ResonanceFieldFx}) and the
 * far-LOD all read ONLY from here — the payload arrives on build, on every state
 * change and on login, never per tick (§3.6).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ResonanceFieldClient {

    /** One immutable synced field snapshot + the client game time it arrived at. */
    public record Snapshot(BlockPos anchor, BlockPos altar,
            List<S2CResonanceFieldPayload.Crystal> crystals,
            List<S2CResonanceFieldPayload.Edge> edges, int state, int cooldownRemainingTicks,
            long receivedGameTime) {

        public ResonanceMelodyMachine.State stateEnum() {
            ResonanceMelodyMachine.State[] states = ResonanceMelodyMachine.State.values();
            return this.state >= 0 && this.state < states.length
                    ? states[this.state] : ResonanceMelodyMachine.State.IDLE;
        }

        /** Client ticks since this snapshot arrived (drives the finale light envelope). */
        public long age() {
            Minecraft minecraft = Minecraft.getInstance();
            return minecraft.level == null ? 0L
                    : minecraft.level.getGameTime() - this.receivedGameTime;
        }

        /** The §4.2 voice anchor of a crystal (top third — where the voice "sits"). */
        public Vec3 voicePos(int index) {
            S2CResonanceFieldPayload.Crystal crystal = this.crystals.get(index);
            return new Vec3(crystal.basePos().getX() + 0.5D,
                    crystal.basePos().getY() + crystal.height() * 0.66D,
                    crystal.basePos().getZ() + 0.5D);
        }

        /** The top-mid cue anchor of a crystal (bahn endpoints, far shafts). */
        public Vec3 topPos(int index) {
            S2CResonanceFieldPayload.Crystal crystal = this.crystals.get(index);
            return new Vec3(crystal.basePos().getX() + 0.5D,
                    crystal.basePos().getY() + crystal.height() * 0.9D,
                    crystal.basePos().getZ() + 0.5D);
        }
    }

    @Nullable
    private static volatile Snapshot snapshot;

    private ResonanceFieldClient() {}

    /** {@code EclipsePayloads} handler branch — client main thread. */
    public static void handle(S2CResonanceFieldPayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        long now = minecraft.level == null ? 0L : minecraft.level.getGameTime();
        snapshot = new Snapshot(payload.anchor(), payload.altar(), payload.crystals(),
                payload.edges(), payload.state(), payload.cooldownRemainingTicks(), now);
        ResonanceFieldFx.onStateSynced(snapshot);
    }

    /** The last synced field, or {@code null} before the first payload / after logout. */
    @Nullable
    public static Snapshot get() {
        return snapshot;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        snapshot = null;
    }
}
