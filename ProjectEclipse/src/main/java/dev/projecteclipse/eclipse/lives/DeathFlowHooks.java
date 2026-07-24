package dev.projecteclipse.eclipse.lives;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorApi;
import dev.projecteclipse.eclipse.network.death.DeathFlowPayloads;
import dev.projecteclipse.eclipse.network.death.DeathFlowPayloads.S2CDeathStatePayload;
import dev.projecteclipse.eclipse.network.death.DeathFlowPayloads.S2CRevivedPayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * WB-DEATH server hooks (P3 §3.7): the ship-respawn/door flow layered ON TOP of the
 * existing death economy — {@link LifecycleEvents} (heart decrement, graves, kill
 * transfer, ban at 0) and {@link BanService} (ghost team/limbo state) are untouched and
 * keep running exactly as before; this class only observes their results and adds the
 * theater around them.
 *
 * <p><b>Event ordering (documented contract):</b></p>
 * <ul>
 *   <li>{@code LivingDeathEvent} at {@link EventPriority#LOW} — runs AFTER
 *       {@code LifecycleEvents.onLivingDeath} (NORMAL) has decremented the heart and,
 *       at 0 hearts, set the BANNED attachment, so the payload carries the post-death
 *       truth. (NeoForge runs HIGH before NORMAL before LOW.)</li>
 *   <li>{@code PlayerRespawnEvent} at {@link EventPriority#LOWEST} — runs AFTER
 *       {@code LifecycleEvents.onPlayerRespawn} (limbo state for banned players + the
 *       deferred hotbar heart-burst replay) and {@code HeartsService.onPlayerRespawn}
 *       (max-health), so the vanilla respawn position we capture as the "real respawn
 *       point" and the ship teleport both happen last.</li>
 * </ul>
 *
 * <p><b>Flow (non-ghost death, hearts ≥ 1 left):</b> death → {@code PHASE_DEATH} payload
 * (custom death screen) → vanilla respawn → capture the vanilla respawn point → teleport
 * onto the limbo ship deck ({@code PHASE_SHIP_WAKE}; the pre-existing pending-heart-loss
 * replay plays the hotbar burst there) → after {@value #SHIP_DOOR_DELAY_TICKS} ticks the
 * Respawn Door swings open for that player alone ({@link RespawnDoorApi#playOpenFor};
 * {@code PHASE_DOOR_OPEN}) → the player walks to the door (proximity), sneaks to skip, or
 * {@value #DOOR_AUTO_TICKS} ticks pass → {@code PHASE_RETURNING} (client fades to black)
 * → teleport to the captured respawn point behind the fade → {@code PHASE_CLEAR}.</p>
 *
 * <p><b>Ghosts (0 hearts):</b> the ban/limbo path already parks them on the ship —
 * this class only resyncs the ghost payloads ({@code PHASE_SHIP_WAKE ghost=true} +
 * {@code S2CGhostStatePayload}) and never opens the door for them.</p>
 *
 * <p><b>Revive:</b> {@link #onRevived} is the public entry point (P4's revive ritual may
 * call it directly, right before {@code BanService.unban} teleports, for a flash-free
 * celebration); until that call is wired, a per-tick unban watch detects any revive
 * (altar ritual, admin, offline-revive login) and runs the celebration: teleport back to
 * the deck, {@code S2CRevivedPayload} (ghost hearts burst one by one client-side), door
 * opens, walk through, home. During the finale mass-revive
 * ({@code EclipseWorldState.isFerrymanDefeated()}) the ship celebration is skipped —
 * {@code FinaleRitual} owns the trip home — and only the payloads are sent.</p>
 *
 * <p><b>Soft-lock proofing:</b> every ship stage ticks toward a hard cap
 * ({@value #SHIP_HARD_CAP_TICKS} / {@value #REVIVE_HARD_CAP_TICKS} ticks) that force-completes
 * the return; a player found outside limbo mid-flow completes immediately; flows survive
 * relogs (state resent on login, {@link #PENDING_TTL_MILLIS} age-out like the existing
 * pending-heart-loss map); the vanilla respawn packet is never intercepted, so even with
 * every payload lost the player still respawns.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DeathFlowHooks {
    /** Death-screen button gate (ticks) for a normal death. */
    public static final int HOLD_TICKS_NORMAL = 30;
    /** Death-screen button gate (ticks) for the ghost variant (a beat longer — it is the last one). */
    public static final int HOLD_TICKS_GHOST = 40;

    /** Ship-wake beat before the door opens (lets the hotbar heart burst play out). */
    private static final int SHIP_DOOR_DELAY_TICKS = 30;
    /** Revive celebration beat before the door opens (client bursts 5 ghost hearts staggered). */
    private static final int REVIVE_BURST_TICKS = 55;
    /** Auto-return this long after the door opened ("walk through, or we carry you"). */
    private static final int DOOR_AUTO_TICKS = 100;
    /** Hard cap on the whole on-ship portion of a death flow (8 s) — forces the return. */
    private static final int SHIP_HARD_CAP_TICKS = 160;
    /** Hard cap for the revive flow (celebration beat + door phase + margin). */
    private static final int REVIVE_HARD_CAP_TICKS = 240;
    /** Fade-out lead before the teleport home (client plays a ~12 tick portal-enter). */
    private static final int RETURN_FADE_TICKS = 14;
    /** Walk-through detection: distance² from the door-front cell center. */
    private static final double DOOR_WALK_DIST_SQ = 2.4D * 2.4D;
    /** Flows older than this are dropped (the player never came back) — LifecycleEvents' TTL. */
    private static final long PENDING_TTL_MILLIS = 60L * 60L * 1000L;

    private enum Stage { AWAIT_RESPAWN, SHIP_WAKE, REVIVE_BURST, DOOR_OPEN, RETURN_FADE }

    /** Per-player flow. Deliberately NOT pruned on logout (relog mid-flow resumes); TTL-pruned instead. */
    private static final Map<UUID, Flow> FLOWS = new HashMap<>();

    /** Online players last seen event-banned; a banned→unbanned flip is a revive. */
    private static final Set<UUID> KNOWN_GHOSTS = new HashSet<>();

    private static final class Flow {
        Stage stage = Stage.AWAIT_RESPAWN;
        boolean ghost;
        boolean revive;
        int heartsRemaining;
        int lostHeartIndex = -1;
        String causeKey = "generic";
        long touchedAtMillis = System.currentTimeMillis();
        int stageTicks;
        int shipTicks;
        GlobalPos homePos;
        float homeYaw;
        float homePitch;

        void enter(Stage next) {
            stage = next;
            stageTicks = 0;
            touchedAtMillis = System.currentTimeMillis();
        }
    }

    private DeathFlowHooks() {}

    // ------------------------------------------------------------------ death

    /** LOW: runs after {@code LifecycleEvents.onLivingDeath} decremented the heart / set the ban. */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        long now = System.currentTimeMillis();
        FLOWS.values().removeIf(flow -> now - flow.touchedAtMillis > PENDING_TTL_MILLIS);

        Flow flow = new Flow();
        flow.heartsRemaining = LivesApi.get(victim);
        flow.ghost = flow.heartsRemaining <= 0;
        // LifecycleEvents: the first now-missing zero-based heart is exactly the new count.
        flow.lostHeartIndex = flow.heartsRemaining;
        flow.causeKey = event.getSource().getMsgId();
        FLOWS.put(victim.getUUID(), flow);

        DeathFlowPayloads.sendDeathState(victim, new S2CDeathStatePayload(
                DeathFlowPayloads.PHASE_DEATH, flow.heartsRemaining, flow.ghost,
                flow.lostHeartIndex, flow.causeKey,
                flow.ghost ? HOLD_TICKS_GHOST : HOLD_TICKS_NORMAL));
    }

    // ------------------------------------------------------------------ respawn → ship

    /** LOWEST: runs after the limbo-state re-apply and the deferred heart-burst replay. */
    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        Flow flow = FLOWS.get(player.getUUID());

        if (BanService.isBanned(player)) {
            // Ghost: BanService.applyLimboState already parked them on the arrival platform.
            // Just resync the client (ghost grade + ghost HUD + "door stays closed" text).
            FLOWS.remove(player.getUUID());
            KNOWN_GHOSTS.add(player.getUUID());
            FxPayloads.sendGhostState(player, true);
            RespawnDoorApi.clearCueFor(player);
            sendPhase(player, DeathFlowPayloads.PHASE_SHIP_WAKE, true);
            return;
        }
        if (flow == null || flow.stage != Stage.AWAIT_RESPAWN) {
            return; // no tracked death (TTL expired / admin respawn) — plain vanilla respawn
        }

        ServerLevel limbo = player.server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            // No limbo, no theater — behave exactly like the pre-WB-DEATH mod.
            EclipseMod.LOGGER.warn("Limbo dimension missing; skipping ship respawn flow for {}",
                    player.getScoreboardName());
            FLOWS.remove(player.getUUID());
            sendPhase(player, DeathFlowPayloads.PHASE_CLEAR, false);
            return;
        }

        // The vanilla respawn already placed them at their REAL respawn point — capture it,
        // then borrow them for the ship wake.
        flow.homePos = GlobalPos.of(player.serverLevel().dimension(), player.blockPosition());
        flow.homeYaw = player.getYRot();
        flow.homePitch = player.getXRot();
        teleportToDeck(player, limbo);
        flow.enter(Stage.SHIP_WAKE);
        flow.shipTicks = 0;
        sendPhase(player, DeathFlowPayloads.PHASE_SHIP_WAKE, false);
    }

    // ------------------------------------------------------------------ tick driver

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        watchForRevives(server);
        if (FLOWS.isEmpty()) {
            return;
        }
        for (Iterator<Map.Entry<UUID, Flow>> iterator = FLOWS.entrySet().iterator(); iterator.hasNext();) {
            Map.Entry<UUID, Flow> entry = iterator.next();
            Flow flow = entry.getValue();
            if (flow.stage == Stage.AWAIT_RESPAWN) {
                continue; // waiting for the respawn click; TTL prunes abandoned entries on the next death
            }
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            if (player == null) {
                continue; // offline mid-flow: resumed by onPlayerLoggedIn, TTL-pruned otherwise
            }
            if (tickShipFlow(player, flow)) {
                iterator.remove();
            }
        }
    }

    /** Advances one on-ship flow; returns {@code true} when the flow is finished. */
    private static boolean tickShipFlow(ServerPlayer player, Flow flow) {
        flow.stageTicks++;
        flow.shipTicks++;
        flow.touchedAtMillis = System.currentTimeMillis();

        ServerLevel limbo = player.server.getLevel(LimboDimension.LIMBO);
        boolean onShip = limbo != null && player.serverLevel().dimension().equals(LimboDimension.LIMBO);

        if (flow.stage != Stage.RETURN_FADE && !onShip) {
            // Someone/something moved them off the ship mid-flow — stop the theater cleanly.
            RespawnDoorApi.clearCueFor(player);
            sendPhase(player, DeathFlowPayloads.PHASE_CLEAR, false);
            return true;
        }

        switch (flow.stage) {
            case SHIP_WAKE -> {
                if (flow.stageTicks >= SHIP_DOOR_DELAY_TICKS) {
                    openDoorFor(player, flow);
                }
            }
            case REVIVE_BURST -> {
                if (flow.stageTicks >= REVIVE_BURST_TICKS) {
                    openDoorFor(player, flow);
                }
            }
            case DOOR_OPEN -> {
                boolean walkedThrough = limbo != null && player.position().distanceToSqr(
                        Vec3.atBottomCenterOf(RespawnDoorApi.doorFrontPos(limbo))) < DOOR_WALK_DIST_SQ;
                if (walkedThrough || flow.stageTicks >= DOOR_AUTO_TICKS) {
                    beginReturn(player, flow);
                }
            }
            case RETURN_FADE -> {
                if (flow.stageTicks >= RETURN_FADE_TICKS) {
                    finishReturn(player, flow);
                    return true;
                }
            }
            default -> { }
        }

        // Absolute failsafe: no ship stage may ever hold the player longer than the cap.
        int hardCap = flow.revive ? REVIVE_HARD_CAP_TICKS : SHIP_HARD_CAP_TICKS;
        if (flow.stage != Stage.RETURN_FADE && flow.shipTicks >= hardCap) {
            EclipseMod.LOGGER.warn("Death flow hard cap hit for {} in stage {} — forcing the return",
                    player.getScoreboardName(), flow.stage);
            beginReturn(player, flow);
        }
        return false;
    }

    private static void openDoorFor(ServerPlayer player, Flow flow) {
        RespawnDoorApi.playOpenFor(player);
        flow.enter(Stage.DOOR_OPEN);
        sendPhase(player, DeathFlowPayloads.PHASE_DOOR_OPEN, false);
    }

    private static void beginReturn(ServerPlayer player, Flow flow) {
        flow.enter(Stage.RETURN_FADE);
        sendPhase(player, DeathFlowPayloads.PHASE_RETURNING, false);
    }

    /** Teleports home behind the client's black fade and terminates the flow. */
    private static void finishReturn(ServerPlayer player, Flow flow) {
        ServerLevel home = flow.homePos != null ? player.server.getLevel(flow.homePos.dimension()) : null;
        if (home != null) {
            BlockPos pos = flow.homePos.pos();
            player.teleportTo(home, pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D,
                    flow.homeYaw, flow.homePitch);
        } else {
            // Captured dimension vanished (or a revive without capture): overworld shared spawn.
            ServerLevel overworld = player.server.overworld();
            BlockPos spawn = overworld.getSharedSpawnPos();
            player.teleportTo(overworld, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                    overworld.getSharedSpawnAngle(), 0.0F);
        }
        RespawnDoorApi.playCloseFor(player);
        RespawnDoorApi.clearCueFor(player);
        sendPhase(player, DeathFlowPayloads.PHASE_CLEAR, false);
    }

    // ------------------------------------------------------------------ revive

    /**
     * Unban watch: {@code BanService.unban} has many callers (altar ritual, finale, admin
     * command) and no event of its own — a banned→unbanned flip on an online player IS the
     * revive. Detected the same server tick, so the celebration teleport follows the
     * unban's spawn teleport within one tick.
     */
    private static void watchForRevives(MinecraftServer server) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            boolean banned = BanService.isBanned(player);
            UUID id = player.getUUID();
            if (banned) {
                KNOWN_GHOSTS.add(id);
            } else if (KNOWN_GHOSTS.remove(id)) {
                onRevived(player);
            }
        }
    }

    /**
     * PUBLIC revive entry point (P3 §5.1 seam): starts the revive celebration for a
     * just-unbanned player — ghost grade released, ghost hearts burst one by one over the
     * hotbar ({@code S2CRevivedPayload}), back on the deck, the door opens for them, walk
     * through (or auto/sneak-skip), portal-fade home. P4's revive ritual may call this
     * directly; the unban watch already routes every {@code BanService.unban} here, and a
     * duplicate call is a no-op while a revive flow is live. Skips the ship theater during
     * the finale mass-revive (FinaleRitual owns the trip home) and for offline/dead players.
     */
    public static void onRevived(ServerPlayer player) {
        if (player == null || BanService.isBanned(player)) {
            return;
        }
        KNOWN_GHOSTS.remove(player.getUUID());
        Flow existing = FLOWS.get(player.getUUID());
        if (existing != null && existing.revive) {
            return; // celebration already running (direct call + unban watch double-fire)
        }
        FxPayloads.sendGhostState(player, false);
        DeathFlowPayloads.sendRevived(player, new S2CRevivedPayload(Math.max(1, LivesApi.get(player))));

        ServerLevel limbo = player.server.getLevel(LimboDimension.LIMBO);
        boolean finaleRevive = EclipseWorldState.get(player.server).isFerrymanDefeated();
        if (limbo == null || finaleRevive || player.isDeadOrDying()) {
            // Hearts still burst client-side wherever they stand; no ship theater.
            FLOWS.remove(player.getUUID());
            return;
        }

        Flow flow = new Flow();
        flow.revive = true;
        flow.heartsRemaining = LivesApi.get(player);
        // Home = wherever the unban path just placed them (overworld shared spawn today).
        flow.homePos = GlobalPos.of(player.serverLevel().dimension(), player.blockPosition());
        flow.homeYaw = player.getYRot();
        flow.homePitch = player.getXRot();
        if (LimboDimension.LIMBO.equals(flow.homePos.dimension())) {
            flow.homePos = null; // still in limbo (unexpected caller state): fall back to world spawn
        }
        teleportToDeck(player, limbo);
        flow.enter(Stage.REVIVE_BURST);
        flow.shipTicks = 0;
        FLOWS.put(player.getUUID(), flow);
        sendPhase(player, DeathFlowPayloads.PHASE_SHIP_WAKE, false);
        EclipseMod.LOGGER.info("Revive celebration started for {}", player.getScoreboardName());
    }

    // ------------------------------------------------------------------ payload input

    /** {@code C2SRespawnReadyPayload} entry (called by {@code DeathFlowPayloads}, server thread). */
    public static void handleRespawnReady(ServerPlayer player, int action) {
        Flow flow = FLOWS.get(player.getUUID());
        if (flow == null) {
            return;
        }
        flow.touchedAtMillis = System.currentTimeMillis();
        if (action == DeathFlowPayloads.ACTION_DOOR_SKIP
                && !BanService.isBanned(player)
                && (flow.stage == Stage.DOOR_OPEN || flow.stage == Stage.SHIP_WAKE
                        || flow.stage == Stage.REVIVE_BURST)) {
            beginReturn(player, flow);
        }
        // ACTION_SCREEN_READY: bookkeeping only — the vanilla PERFORM_RESPAWN packet the
        // client sends alongside does the actual respawn (never blocked, never duplicated).
    }

    // ------------------------------------------------------------------ login / lifecycle

    /**
     * LOWEST: resyncs mid-flow state after a relog — runs after
     * {@code ReviveRitual.onPlayerLoggedIn} (NORMAL) has completed any offline revive, so a
     * ghost revived while offline gets the full celebration on this very login (their UUID
     * is still in {@link #KNOWN_GHOSTS} from this server run; after a restart they simply
     * log in alive, no celebration — acceptable).
     */
    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (BanService.isBanned(player)) {
            KNOWN_GHOSTS.add(player.getUUID());
            FxPayloads.sendGhostState(player, true);
            sendPhase(player, DeathFlowPayloads.PHASE_SHIP_WAKE, true);
            return;
        }
        if (KNOWN_GHOSTS.remove(player.getUUID())) {
            onRevived(player); // revived while offline this run — celebrate now
            return;
        }
        Flow flow = FLOWS.get(player.getUUID());
        if (flow == null) {
            return;
        }
        flow.touchedAtMillis = System.currentTimeMillis();
        switch (flow.stage) {
            case AWAIT_RESPAWN -> {
                // Logged out on the death screen; still dead. Re-arm the (re-)opening screen.
                DeathFlowPayloads.sendDeathState(player, new S2CDeathStatePayload(
                        DeathFlowPayloads.PHASE_DEATH, flow.heartsRemaining, flow.ghost,
                        flow.lostHeartIndex, flow.causeKey,
                        flow.ghost ? HOLD_TICKS_GHOST : HOLD_TICKS_NORMAL));
            }
            case SHIP_WAKE, REVIVE_BURST -> {
                flow.stageTicks = 0;
                flow.shipTicks = 0;
                sendPhase(player, DeathFlowPayloads.PHASE_SHIP_WAKE, false);
            }
            case DOOR_OPEN -> {
                flow.stageTicks = 0;
                flow.shipTicks = 0;
                RespawnDoorApi.playOpenFor(player); // the personal cue did not survive the relog
                sendPhase(player, DeathFlowPayloads.PHASE_DOOR_OPEN, false);
            }
            case RETURN_FADE -> {
                // Relogged mid-fade: complete the return right away.
                finishReturn(player, flow);
                FLOWS.remove(player.getUUID());
            }
            default -> { }
        }
    }

    /** Integrated-server restarts must never leak flows into the next world. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        FLOWS.clear();
        KNOWN_GHOSTS.clear();
    }

    // ------------------------------------------------------------------ helpers

    /** Midship deck cell one block above the planks, facing the stern door (−X → yaw 90). */
    private static void teleportToDeck(ServerPlayer player, ServerLevel limbo) {
        int feetY = GhostShipBuilder.waterlineY(limbo) + 4; // deck planks at waterline+3
        player.teleportTo(limbo, 0.5D, feetY, 0.5D, 90.0F, 0.0F);
    }

    private static void sendPhase(ServerPlayer player, int phase, boolean ghost) {
        DeathFlowPayloads.sendDeathState(player, new S2CDeathStatePayload(
                phase, LivesApi.get(player), ghost, -1, "", 0));
    }
}
