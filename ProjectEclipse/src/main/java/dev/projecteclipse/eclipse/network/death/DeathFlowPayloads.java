package dev.projecteclipse.eclipse.network.death;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar + payload records for the WB-DEATH custom death/respawn flow
 * (P3 §3.7) — the {@code network.growth.GrowthPayloads} pattern: registers on its own
 * MOD-bus {@link RegisterPayloadHandlersEvent} subscriber under version group
 * {@value #VERSION}, so {@code EclipsePayloads.register(...)} and {@code EclipseMod} stay
 * untouched (NeoForge allows any number of payload registrars). Payload ids are prefixed
 * {@code eclipse:death/} and must NOT additionally be registered in {@code EclipsePayloads}
 * (duplicate registration throws at startup).
 *
 * <p><b>Flow phases</b> carried by {@link S2CDeathStatePayload#phase()} (the server's
 * {@code lives.DeathFlowHooks} state machine drives them; the client's
 * {@code client.death.DeathFlowController} mirrors them):</p>
 * <ol start="0">
 *   <li>{@link #PHASE_CLEAR} — no flow (also the "you are home" terminator).</li>
 *   <li>{@link #PHASE_DEATH} — just died; data for the custom death screen.</li>
 *   <li>{@link #PHASE_SHIP_WAKE} — respawned on the limbo ship deck (ghost = stays).</li>
 *   <li>{@link #PHASE_DOOR_OPEN} — the Respawn Door swung open for this player.</li>
 *   <li>{@link #PHASE_RETURNING} — fade out; the teleport home lands behind the black.</li>
 * </ol>
 *
 * <p>The two S2C handlers dispatch through installed {@link Consumer} hooks (plain types —
 * this class stays loadable on dedicated servers); {@code DeathFlowController} installs
 * them from its client-only static init. The C2S handler delegates straight to
 * {@code lives.DeathFlowHooks} (common code).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DeathFlowPayloads {
    private static final String VERSION = "wbdeath1";

    // --- S2CDeathStatePayload.phase() values ---
    public static final int PHASE_CLEAR = 0;
    public static final int PHASE_DEATH = 1;
    public static final int PHASE_SHIP_WAKE = 2;
    public static final int PHASE_DOOR_OPEN = 3;
    public static final int PHASE_RETURNING = 4;

    // --- C2SRespawnReadyPayload.action() values ---
    /** The custom death screen's respawn button was pressed (bookkeeping/failsafe arm). */
    public static final int ACTION_SCREEN_READY = 0;
    /** Skip the door wait and go home now (sneak on deck during the door phase). */
    public static final int ACTION_DOOR_SKIP = 1;

    /** Client-side death-state consumer installed by {@code DeathFlowController} (main thread). */
    private static volatile Consumer<S2CDeathStatePayload> clientDeathStateHandler;
    /** Client-side revive consumer installed by {@code DeathFlowController} (main thread). */
    private static volatile Consumer<S2CRevivedPayload> clientRevivedHandler;

    private DeathFlowPayloads() {}

    // ------------------------------------------------------------------ payload records

    /**
     * Server → one client: the death-flow phase for THAT player plus everything the death
     * screen renders: hearts remaining after the death, ghost flag (0 hearts — event-banned),
     * the zero-based index of the heart that just shattered ({@code -1} = none lost), the
     * anonymized damage-type key ({@code DamageSource.getMsgId()}; the client maps it onto
     * {@code gui.eclipse.death.cause.<key>} with a generic fallback) and the button
     * hold-gate in ticks.
     */
    public record S2CDeathStatePayload(int phase, int heartsRemaining, boolean ghost,
            int lostHeartIndex, String causeKey, int holdTicks) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CDeathStatePayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "death/state"));

        public static final StreamCodec<ByteBuf, S2CDeathStatePayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CDeathStatePayload::phase,
                        ByteBufCodecs.VAR_INT, S2CDeathStatePayload::heartsRemaining,
                        ByteBufCodecs.BOOL, S2CDeathStatePayload::ghost,
                        ByteBufCodecs.VAR_INT, S2CDeathStatePayload::lostHeartIndex,
                        ByteBufCodecs.STRING_UTF8, S2CDeathStatePayload::causeKey,
                        ByteBufCodecs.VAR_INT, S2CDeathStatePayload::holdTicks,
                        S2CDeathStatePayload::new);

        @Override
        public CustomPacketPayload.Type<S2CDeathStatePayload> type() {
            return TYPE;
        }
    }

    /**
     * Server → one client: this player was just revived from the ghost state (altar ritual,
     * finale mass-revive or admin). {@code heartsRestored} is the real heart count after the
     * revive (1 today). The client bursts its ghost-heart row one by one and releases the
     * ghost HUD.
     */
    public record S2CRevivedPayload(int heartsRestored) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CRevivedPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "death/revived"));

        public static final StreamCodec<ByteBuf, S2CRevivedPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CRevivedPayload::heartsRestored,
                        S2CRevivedPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CRevivedPayload> type() {
            return TYPE;
        }
    }

    /**
     * Client → server: flow input from the death screen / deck controls. The actual respawn
     * still travels on the vanilla {@code PERFORM_RESPAWN} packet (never blocked by this
     * mod); {@link #ACTION_SCREEN_READY} only marks the flow armed, {@link #ACTION_DOOR_SKIP}
     * asks for the immediate teleport home during the door phase.
     */
    public record C2SRespawnReadyPayload(int action) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<C2SRespawnReadyPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "death/ready"));

        public static final StreamCodec<ByteBuf, C2SRespawnReadyPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, C2SRespawnReadyPayload::action,
                        C2SRespawnReadyPayload::new);

        @Override
        public CustomPacketPayload.Type<C2SRespawnReadyPayload> type() {
            return TYPE;
        }
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CDeathStatePayload.TYPE, S2CDeathStatePayload.STREAM_CODEC,
                DeathFlowPayloads::handleDeathState);
        registrar.playToClient(S2CRevivedPayload.TYPE, S2CRevivedPayload.STREAM_CODEC,
                DeathFlowPayloads::handleRevived);
        registrar.playToServer(C2SRespawnReadyPayload.TYPE, C2SRespawnReadyPayload.STREAM_CODEC,
                DeathFlowPayloads::handleRespawnReady);
    }

    // ------------------------------------------------------------------ server send helpers

    /** Sends the current flow phase/state to exactly one player. */
    public static void sendDeathState(ServerPlayer player, S2CDeathStatePayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    /** Sends the revive celebration trigger to exactly one player. */
    public static void sendRevived(ServerPlayer player, S2CRevivedPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    // ------------------------------------------------------------------ client dispatch

    /** Installs the client death-state consumer. Called once from {@code DeathFlowController}'s static init. */
    public static void setClientDeathStateHandler(Consumer<S2CDeathStatePayload> handler) {
        clientDeathStateHandler = handler;
    }

    /** Installs the client revive consumer. Called once from {@code DeathFlowController}'s static init. */
    public static void setClientRevivedHandler(Consumer<S2CRevivedPayload> handler) {
        clientRevivedHandler = handler;
    }

    /** Runs on the client main thread only; no client classes are referenced eagerly. */
    private static void handleDeathState(S2CDeathStatePayload payload, IPayloadContext context) {
        Consumer<S2CDeathStatePayload> handler = clientDeathStateHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Death-state payload (phase {}) dropped — no client handler installed",
                    payload.phase());
        }
    }

    /** Runs on the client main thread only; no client classes are referenced eagerly. */
    private static void handleRevived(S2CRevivedPayload payload, IPayloadContext context) {
        Consumer<S2CRevivedPayload> handler = clientRevivedHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Revived payload dropped — no client handler installed");
        }
    }

    /** Server main thread: flow input delegates to the lives-side hook (common code). */
    private static void handleRespawnReady(C2SRespawnReadyPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            dev.projecteclipse.eclipse.lives.DeathFlowHooks.handleRespawnReady(player, payload.action());
        }
    }
}
