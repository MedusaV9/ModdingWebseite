package dev.projecteclipse.eclipse.veilfx;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client-side resolution table for the {@code FxCues} lane (INTEGRATION.md §3): the server
 * fires a logical cue id over the existing {@code S2CFxEventPayload}; the tail branch in
 * {@code FxPayloads.handleFxEvent} calls {@link #dispatch}, which resolves the cue to a
 * Photon effect (via {@link PhotonBridge}, full guard chain inside) and/or a Quasar
 * fallback emitter — a table lookup instead of new hardcoded seams.
 *
 * <p><b>Row API for content workers</b> (PH-CORE contract): create your own client-only
 * registrar class (copy {@link PhotonFxRows}) and call {@link #registerRow} for each cue
 * during {@code FMLClientSetupEvent}. One row = one logical cue:</p>
 * <pre>{@code
 * PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
 *         FxCues.CUE_MY_MOMENT,                 // logical id crossing the wire (FxCues)
 *         rl("eclipse:my_moment"),              // assets/eclipse/fx/my_moment.fx
 *         rl("eclipse:my_moment_quasar"),       // quasar fallback (nullable)
 *         FxBudget.Channel.BURST,               // charged for the QUASAR leg only
 *         PhotonFxRegistry.Mode.LAYER,          // LAYER on top of quasar | REPLACE quasar
 *         false));                              // loop? (WINDOWED-only law, §4)
 * }</pre>
 *
 * <p><b>Design laws</b> (INTEGRATION.md §3, do not renegotiate): the server stays
 * photon-blind; every failure degrades and never drops below the Quasar/vanilla baseline
 * ({@code Mode.REPLACE} re-enters the Quasar leg when the Photon spawn fails); Photon
 * spawns stay un-charged by {@link FxBudget} (they count against
 * {@link PhotonBridge#MAX_LIVE_EXECUTORS} instead) while the Quasar leg is charged to the
 * row's channel.</p>
 *
 * <p><b>Loop rows (WINDOWED-only law, INTEGRATION.md §4):</b> rows with {@code loop=true}
 * are NEVER payload-fired — {@link #dispatch} consumes them with a one-time WARN and plays
 * nothing. Instead a client-tick controller owning a hysteresis window (the
 * {@code SanctumLightfall} pattern: materialize/release distance band, retry cadence,
 * release on {@code reducedFx}/dimension change/logout) drives {@link #ensureLoop} while
 * the window is open and {@link #releaseLoop} when it closes.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class PhotonFxRegistry {
    /** How the Photon leg relates to the Quasar leg of a row. */
    public enum Mode {
        /** Photon layered ON TOP of the Quasar leg (D12 law — both play). */
        LAYER,
        /** Photon INSTEAD of Quasar; the Quasar leg runs iff the Photon spawn fails. */
        REPLACE
    }

    /**
     * Custom Photon leg for rows whose enhancement is more than one plain
     * {@code PhotonBridge.spawn(photonFx, pos)} — multi-part choreography (delays, extra
     * anchors) or entity attachment. The a/b floats are the payload's cue parameters
     * (semantics documented on the {@code FxCues.CUE_*} constant); {@code entity} is
     * non-null only on the {@code S2CFxEntityEventPayload} lane AND when the client still
     * tracks the entity — implementations MUST degrade to the position anchor otherwise.
     */
    @FunctionalInterface
    public interface PhotonLeg {
        /** @return {@code true} iff a Photon effect actually started (drives REPLACE rows). */
        boolean play(ResourceLocation photonFx, Vec3 pos, @Nullable Entity entity, float a, float b);
    }

    /**
     * One registered cue row.
     *
     * @param logicalId     the wire id ({@code FxCues.CUE_*}) this row consumes
     * @param photonFx      Photon asset id → {@code assets/<ns>/fx/<path>.fx}
     * @param quasarEmitter Quasar fallback emitter id ({@code assets/<ns>/quasar/emitters/…}),
     *                      or {@code null} for a Photon-only garnish (legal for NEW cues:
     *                      pre-row baseline was nothing)
     * @param channel       {@link FxBudget} channel charged for the QUASAR leg only
     * @param mode          {@link Mode#LAYER} or {@link Mode#REPLACE}
     * @param loop          {@code true} = looping asset, WINDOWED-only (never payload-fired)
     * @param photonLeg     custom Photon leg, or {@code null} for the default single spawn
     */
    public record Row(ResourceLocation logicalId, ResourceLocation photonFx,
            @Nullable ResourceLocation quasarEmitter, FxBudget.Channel channel,
            Mode mode, boolean loop, @Nullable PhotonLeg photonLeg) {
        /** Default-leg row: the Photon side is one {@code PhotonBridge.spawn(photonFx, pos)}. */
        public Row(ResourceLocation logicalId, ResourceLocation photonFx,
                @Nullable ResourceLocation quasarEmitter, FxBudget.Channel channel,
                Mode mode, boolean loop) {
            this(logicalId, photonFx, quasarEmitter, channel, mode, loop, null);
        }
    }

    private static final Map<ResourceLocation, Row> TABLE = new ConcurrentHashMap<>();
    /** Loop rows that were (incorrectly) payload-fired — warned once per session. */
    private static final Set<ResourceLocation> WARNED_LOOP_DISPATCH = ConcurrentHashMap.newKeySet();
    /** Live windowed-loop legs per logical id (client main thread only). */
    private static final Map<ResourceLocation, LoopState> LOOPS = new HashMap<>();

    private static final class LoopState {
        @Nullable
        PhotonBridge.LoopHandle photon;
        @Nullable
        ParticleEmitter quasar;
    }

    private PhotonFxRegistry() {}

    // ------------------------------------------------------------------ registration

    /**
     * Registers one cue row (content workers: call from your own client registrar class
     * during {@code FMLClientSetupEvent}). First registration wins — a duplicate logical id
     * is refused with a WARN so two workers cannot silently fight over a cue.
     */
    public static void registerRow(Row row) {
        Row previous = TABLE.putIfAbsent(row.logicalId(), row);
        if (previous != null) {
            EclipseMod.LOGGER.warn("PhotonFxRegistry: duplicate row for {} refused (kept {} -> {})",
                    row.logicalId(), previous.photonFx(), row.photonFx());
        }
    }

    /** The row registered for {@code logicalId}, or {@code null}. */
    @Nullable
    public static Row row(ResourceLocation logicalId) {
        return TABLE.get(logicalId);
    }

    /** Immutable snapshot of every registered logical cue id (dev/QA introspection). */
    public static Set<ResourceLocation> registeredIds() {
        return Set.copyOf(TABLE.keySet());
    }

    // ------------------------------------------------------------------ payload dispatch

    /**
     * {@code FxPayloads.handleFxEvent} tail branch (client main thread).
     * @return {@code true} iff the id was a registered cue (consumed).
     */
    public static boolean dispatch(ResourceLocation id, Vec3 pos) {
        return dispatch(id, pos, 0.0F, 0.0F);
    }

    /** {@link #dispatch(ResourceLocation, Vec3)} with the payload's a/b cue parameters. */
    public static boolean dispatch(ResourceLocation id, Vec3 pos, float a, float b) {
        return dispatchInternal(id, pos, null, a, b);
    }

    /**
     * {@code FxPayloads.handleFxEntityEvent} branch (client main thread): entity-anchored
     * cue lane. {@code entity} may be {@code null} (target not client-tracked) — the row's
     * Photon leg then anchors at {@code pos}, exactly like the position lane; the Quasar
     * fallback leg is always position-anchored.
     * @return {@code true} iff the id was a registered cue (consumed).
     */
    public static boolean dispatchEntity(ResourceLocation id, @Nullable Entity entity,
            Vec3 pos, float a, float b) {
        return dispatchInternal(id, pos, entity, a, b);
    }

    private static boolean dispatchInternal(ResourceLocation id, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        Row row = TABLE.get(id);
        if (row == null) {
            return false;
        }
        if (row.loop()) {
            if (WARNED_LOOP_DISPATCH.add(id)) {
                EclipseMod.LOGGER.warn("PhotonFxRegistry: loop row {} was payload-fired — loops are "
                        + "WINDOWED-only (INTEGRATION.md §4); drive ensureLoop/releaseLoop from a "
                        + "client-tick window instead", id);
            }
            return true;
        }
        boolean photonPlayed; // full guard chain inside the bridge on every branch
        if (row.photonLeg() != null) {
            photonPlayed = row.photonLeg().play(row.photonFx(), pos, entity, a, b);
        } else if (entity != null) {
            photonPlayed = PhotonBridge.spawnOnEntity(row.photonFx(), entity,
                    PhotonBridge.AUTO_ROTATE_NONE, (Vec3) null);
        } else {
            photonPlayed = PhotonBridge.spawn(row.photonFx(), pos);
        }
        if (row.quasarEmitter() != null
                && (row.mode() == Mode.LAYER || !photonPlayed)) {
            QuasarSpawner.spawnOrFallback(row.quasarEmitter(), pos, row.channel());
        }
        return true;
    }

    // ------------------------------------------------------------------ windowed loops

    /**
     * Keeps the loop row {@code logicalId} alive at {@code pos} — call once per tick (or on
     * your retry cadence) WHILE your hysteresis window is open. Re-anchoring a live loop is
     * not supported: release + re-ensure to move it. Legs follow the row mode:
     * {@link Mode#LAYER} runs Photon and Quasar together; {@link Mode#REPLACE} runs Quasar
     * only while the Photon leg is unavailable/refused. The Quasar leg charges the row's
     * budget channel only when a NEW emitter is created (retrying after a refusal is free).
     *
     * @return {@code true} while at least one leg is live and healthy
     */
    public static boolean ensureLoop(ResourceLocation logicalId, Vec3 pos) {
        Row row = TABLE.get(logicalId);
        if (row == null || !row.loop()) {
            EclipseMod.LOGGER.debug("PhotonFxRegistry.ensureLoop({}): no loop row registered", logicalId);
            return false;
        }
        LoopState loopState = LOOPS.computeIfAbsent(logicalId, key -> new LoopState());
        prune(loopState);
        if (loopState.photon == null) {
            loopState.photon = PhotonBridge.spawnLoop(row.photonFx(), pos);
        }
        boolean photonLive = loopState.photon != null;
        boolean wantQuasar = row.quasarEmitter() != null
                && (row.mode() == Mode.LAYER || !photonLive);
        if (wantQuasar && loopState.quasar == null) {
            loopState.quasar = QuasarSpawner.spawnManaged(row.quasarEmitter(), pos, row.channel());
        } else if (!wantQuasar && loopState.quasar != null) {
            // REPLACE row whose Photon leg recovered: retire the stand-in Quasar loop.
            removeQuasar(loopState);
        }
        return photonLive || loopState.quasar != null;
    }

    /** Closes the window for {@code logicalId}: stops both legs (Photon fade if graceful). */
    public static void releaseLoop(ResourceLocation logicalId, boolean graceful) {
        LoopState loopState = LOOPS.remove(logicalId);
        if (loopState == null) {
            return;
        }
        PhotonBridge.stopLoop(loopState.photon, graceful);
        removeQuasar(loopState);
    }

    private static void prune(LoopState loopState) {
        if (loopState.photon != null && !loopState.photon.alive()) {
            loopState.photon = null;
        }
        try {
            if (loopState.quasar != null && loopState.quasar.isRemoved()) {
                loopState.quasar = null;
            }
        } catch (Throwable t) {
            loopState.quasar = null;
        }
    }

    private static void removeQuasar(LoopState loopState) {
        if (loopState.quasar != null) {
            try {
                if (!loopState.quasar.isRemoved()) {
                    loopState.quasar.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (QuasarSpawner.clearAttached pattern).
            }
            loopState.quasar = null;
        }
    }

    /** Live windowed loops right now (dev/QA introspection). */
    public static int liveLoopWindows() {
        return LOOPS.size();
    }

    /** Disconnect reset: legs die with the level; drop the handles so nothing goes stale. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class DisconnectReset {
        private DisconnectReset() {}

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            for (ResourceLocation id : Set.copyOf(LOOPS.keySet())) {
                releaseLoop(id, false);
            }
        }
    }
}
