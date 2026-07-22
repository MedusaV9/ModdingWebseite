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
        registrar.playToClient(S2CBorderPayload.TYPE, S2CBorderPayload.STREAM_CODEC, EclipsePayloads::handleBorder);
        registrar.playToClient(S2COpenArtifactPayload.TYPE, S2COpenArtifactPayload.STREAM_CODEC, EclipsePayloads::handleOpenArtifact);
        registrar.playToClient(S2CCutsceneLibraryPayload.TYPE, S2CCutsceneLibraryPayload.STREAM_CODEC, EclipsePayloads::handleCutsceneLibrary);
        registrar.playToClient(S2CCutscenePlayPayload.TYPE, S2CCutscenePlayPayload.STREAM_CODEC, EclipsePayloads::handleCutscenePlay);
        registrar.playToClient(S2CBossbarStylePayload.TYPE, S2CBossbarStylePayload.STREAM_CODEC, EclipsePayloads::handleBossbarStyle);
        registrar.playToClient(S2CGoalProgressPayload.TYPE, S2CGoalProgressPayload.STREAM_CODEC, EclipsePayloads::handleGoalProgress);
        registrar.playToClient(S2CAnnouncePayload.TYPE, S2CAnnouncePayload.STREAM_CODEC, EclipsePayloads::handleAnnounce);
        registrar.playToClient(S2CTimelinePayload.TYPE, S2CTimelinePayload.STREAM_CODEC, EclipsePayloads::handleTimeline);
        registrar.playToClient(S2CMilestonesPayload.TYPE, S2CMilestonesPayload.STREAM_CODEC, EclipsePayloads::handleMilestones);
        registrar.playToClient(S2CShakePayload.TYPE, S2CShakePayload.STREAM_CODEC, EclipsePayloads::handleShake);
        registrar.playToClient(S2COpenGoalEditorPayload.TYPE, S2COpenGoalEditorPayload.STREAM_CODEC, EclipsePayloads::handleOpenGoalEditor);
        registrar.playToServer(C2SOpenArtifactPayload.TYPE, C2SOpenArtifactPayload.STREAM_CODEC, EclipsePayloads::handleOpenArtifactRequest);
        registrar.playToServer(C2SModlistPayload.TYPE, C2SModlistPayload.STREAM_CODEC, EclipsePayloads::handleModlist);
        registrar.playToServer(C2SCutsceneStatePayload.TYPE, C2SCutsceneStatePayload.STREAM_CODEC, EclipsePayloads::handleCutsceneState);
        registrar.playToServer(C2SConfigEditPayload.TYPE, C2SConfigEditPayload.STREAM_CODEC, EclipsePayloads::handleConfigEdit);
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
        if (payload.phase() == S2CCutscenePayload.Phase.SHAKE) {
            // W4 contract: each SHAKE receipt is one ~2 s camera-shake impulse (fusion rumble).
            dev.projecteclipse.eclipse.cutscene.client.CameraDirector.addShakeImpulse();
        }
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

    private static void handleBorder(S2CBorderPayload payload, IPayloadContext context) {
        ClientStateCache.borderCenterX = payload.centerX();
        ClientStateCache.borderCenterZ = payload.centerZ();
        ClientStateCache.borderFxRange = payload.fxRange();
        long now = System.currentTimeMillis();
        if ("nether".equals(payload.dim())) {
            ClientStateCache.borderFromRadiusNether = payload.fromRadius();
            ClientStateCache.borderToRadiusNether = payload.toRadius();
            ClientStateCache.borderLerpTicksNether = payload.lerpTicks();
            ClientStateCache.borderSyncMillisNether = now;
        } else {
            ClientStateCache.borderFromRadiusOverworld = payload.fromRadius();
            ClientStateCache.borderToRadiusOverworld = payload.toRadius();
            ClientStateCache.borderLerpTicksOverworld = payload.lerpTicks();
            ClientStateCache.borderSyncMillisOverworld = now;
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
    private static void handleBossbarStyle(S2CBossbarStylePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.hud.BossbarSkin.setTheme(payload.id(), payload.theme());
    }

    private static void handleGoalProgress(S2CGoalProgressPayload payload, IPayloadContext context) {
        ClientStateCache.goalLines = payload.goalLines();
        ClientStateCache.goalDone = payload.done();
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleAnnounce(S2CAnnouncePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.hud.AnnouncementOverlay.handle(payload);
    }

    private static void handleTimeline(S2CTimelinePayload payload, IPayloadContext context) {
        ClientStateCache.timeline = payload.entries();
    }

    private static void handleMilestones(S2CMilestonesPayload payload, IPayloadContext context) {
        ClientStateCache.milestones = payload.entries();
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleShake(S2CShakePayload payload, IPayloadContext context) {
        if (payload.marked()) {
            // Lantern Gaze mark: private purple hunt vignette for the receiving player.
            dev.projecteclipse.eclipse.client.hud.MarkVignetteOverlay.trigger(payload.ticks());
        } else {
            dev.projecteclipse.eclipse.cutscene.client.CameraDirector
                    .addShakeImpulse(payload.strength(), payload.ticks());
        }
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleCutsceneLibrary(S2CCutsceneLibraryPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.ClientCutsceneLibrary.replace(payload.pathsJson());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleCutscenePlay(S2CCutscenePlayPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.cutscene.client.CameraDirector.handlePlay(payload);
    }

    /** Cutscene ACKs / skip requests; validation lives in {@code cutscene.CutsceneService}. */
    private static void handleCutsceneState(C2SCutsceneStatePayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            dev.projecteclipse.eclipse.cutscene.CutsceneService.handleClientState(payload, player);
        }
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleOpenGoalEditor(S2COpenGoalEditorPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.devtools.client.GoalEditorScreen.open(payload.daysJson());
    }

    /** W14 goal editor writes; perm check + validation live in {@code devtools.ConfigEditor}. */
    private static void handleConfigEdit(C2SConfigEditPayload payload, IPayloadContext context) {
        if (context.player() instanceof ServerPlayer player) {
            dev.projecteclipse.eclipse.devtools.ConfigEditor.handleEdit(payload, player);
        }
    }

    private static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            sendArtifactState(player, false);
            PacketDistributor.sendToPlayer(player, S2CGoalProgressPayload.currentFor(player));
            PacketDistributor.sendToPlayer(player, S2CMilestonesPayload.current());
            dev.projecteclipse.eclipse.timeline.TimelineService.syncTo(player);
            dev.projecteclipse.eclipse.worldgen.stage.WorldStageService.syncStagesTo(player);
            dev.projecteclipse.eclipse.border.SoftBorder.syncTo(player);
            dev.projecteclipse.eclipse.cutscene.CutsceneService.syncLibraryTo(player);
        }
    }
}
