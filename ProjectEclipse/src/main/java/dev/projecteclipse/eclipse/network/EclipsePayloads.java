package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Networking base for Project: Eclipse. Registers all custom payloads on registrar version "2"
 * and syncs hearts + day state to a player when they log in.
 */
public final class EclipsePayloads {
    private EclipsePayloads() {}

    /** Wires the mod-bus payload registration and the game-bus login sync. Call once from the mod constructor. */
    public static void register(IEventBus modEventBus) {
        modEventBus.addListener(EclipsePayloads::onRegisterPayloadHandlers);
        NeoForge.EVENT_BUS.addListener(EclipsePayloads::onPlayerLoggedIn);
    }

    private static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar("2");
        registrar.playToClient(S2CLivesPayload.TYPE, S2CLivesPayload.STREAM_CODEC, EclipsePayloads::handleLives);
        registrar.playToClient(S2CDayStatePayload.TYPE, S2CDayStatePayload.STREAM_CODEC, EclipsePayloads::handleDayState);
        registrar.playToClient(S2CCutscenePayload.TYPE, S2CCutscenePayload.STREAM_CODEC, EclipsePayloads::handleCutscene);
        registrar.playToClient(S2CHeartBurstPayload.TYPE, S2CHeartBurstPayload.STREAM_CODEC, EclipsePayloads::handleHeartBurst);
        registrar.playToClient(S2CQuasarPayload.TYPE, S2CQuasarPayload.STREAM_CODEC, EclipsePayloads::handleQuasar);
        registrar.playToClient(S2CStagePayload.TYPE, S2CStagePayload.STREAM_CODEC, EclipsePayloads::handleStage);
        registrar.playToClient(S2COpenArtifactPayload.TYPE, S2COpenArtifactPayload.STREAM_CODEC, EclipsePayloads::handleOpenArtifact);
        registrar.playToClient(S2CCutsceneLibraryPayload.TYPE, S2CCutsceneLibraryPayload.STREAM_CODEC, EclipsePayloads::handleCutsceneLibrary);
        registrar.playToClient(S2CCutscenePlayPayload.TYPE, S2CCutscenePlayPayload.STREAM_CODEC, EclipsePayloads::handleCutscenePlay);
        registrar.playToServer(C2SOpenArtifactPayload.TYPE, C2SOpenArtifactPayload.STREAM_CODEC, EclipsePayloads::handleOpenArtifactRequest);
        registrar.playToServer(C2SModlistPayload.TYPE, C2SModlistPayload.STREAM_CODEC, EclipsePayloads::handleModlist);
        registrar.playToServer(C2SCutsceneStatePayload.TYPE, C2SCutsceneStatePayload.STREAM_CODEC, EclipsePayloads::handleCutsceneState);
    }

    /**
     * Sends the player a fresh {@link S2CLivesPayload} + {@link S2CDayStatePayload}, and — when
     * {@code openMenu} — a trailing {@link S2COpenArtifactPayload}. Payload order on one
     * connection is guaranteed, so the client cache is always fresh before the screen opens.
     * Used by the login sync, the arm artifact's right-click and the C2S menu request.
     */
    public static void sendArtifactState(ServerPlayer player, boolean openMenu) {
        EclipseWorldState state = EclipseWorldState.get(player.server);
        int day = state.getDay();
        PacketDistributor.sendToPlayer(player,
                new S2CLivesPayload(LivesApi.get(player)),
                new S2CDayStatePayload(day, state.getAltarLevel(), EclipseConfig.day(day).goals()));
        if (openMenu) {
            PacketDistributor.sendToPlayer(player, new S2COpenArtifactPayload());
        }
    }

    private static void handleLives(S2CLivesPayload payload, IPayloadContext context) {
        ClientStateCache.lives = payload.lives();
    }

    private static void handleDayState(S2CDayStatePayload payload, IPayloadContext context) {
        ClientStateCache.day = payload.day();
        ClientStateCache.altarLevel = payload.altarLevel();
        ClientStateCache.goals = payload.goals();
    }

    private static void handleCutscene(S2CCutscenePayload payload, IPayloadContext context) {
        ClientStateCache.cutscenePhase = payload.phase();
    }

    private static void handleStage(S2CStagePayload payload, IPayloadContext context) {
        if ("nether".equals(payload.dim())) {
            ClientStateCache.stageNether = payload.stage();
            ClientStateCache.stageRadiusNether = payload.radius();
            ClientStateCache.stageAnimatingNether = payload.animating();
        } else {
            ClientStateCache.stageOverworld = payload.stage();
            ClientStateCache.stageRadiusOverworld = payload.radius();
            ClientStateCache.stageAnimatingOverworld = payload.animating();
        }
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleHeartBurst(S2CHeartBurstPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.hearts.client.HeartBurstOverlay.trigger(payload.heartIndex());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleQuasar(S2CQuasarPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.veilfx.QuasarSpawner.spawnOrFallback(payload.emitterId(), payload.pos());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleOpenArtifact(S2COpenArtifactPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.ArtifactScreenOpener.open();
    }

    private static void handleOpenArtifactRequest(C2SOpenArtifactPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            sendArtifactState(player, true);
        }
    }

    /** Anti-cheat modlist report; the check logic lives in {@code admin.AntiCheatCheck}. */
    private static void handleModlist(C2SModlistPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            dev.projecteclipse.eclipse.admin.AntiCheatCheck.handleModlist(payload, player);
        }
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleCutsceneLibrary(S2CCutsceneLibraryPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.ClientCutsceneLibrary.replace(payload.pathsJson());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleCutscenePlay(S2CCutscenePlayPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.ClientCutsceneLibrary.handlePlay(payload);
    }

    /** Cutscene ACKs / skip requests; validation lives in {@code cutscene.CutsceneService}. */
    private static void handleCutsceneState(C2SCutsceneStatePayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            dev.projecteclipse.eclipse.cutscene.CutsceneService.handleClientState(payload, player);
        }
    }

    private static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            sendArtifactState(player, false);
            dev.projecteclipse.eclipse.worldgen.stage.WorldStageService.syncStagesTo(player);
            dev.projecteclipse.eclipse.cutscene.CutsceneService.syncLibraryTo(player);
        }
    }
}
