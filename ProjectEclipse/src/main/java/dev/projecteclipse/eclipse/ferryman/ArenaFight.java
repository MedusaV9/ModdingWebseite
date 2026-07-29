package dev.projecteclipse.eclipse.ferryman;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.util.SpawnReturns;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.GoalTracker;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.ritual.FinaleRitual;
import dev.projecteclipse.eclipse.xboxevent.XboxPayloads;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The C10 crossing orchestrator (server thread only). Stage machine:
 *
 * <ol>
 *   <li><b>GATE</b> — armed by {@code FinaleRitual}'s catalyst deposit
 *       ({@link #armGate}): the {@link AltarDoor dead door} stands at the altar; walking
 *       into it ships a player to the limbo ghost-ship deck behind a portal fade. The
 *       gate holds until every living (non-ghost) online player stands on the deck OR
 *       the {@value #GATE_TIMEOUT_TICKS}t timeout; either way a
 *       {@value #GATE_COUNTDOWN_TICKS}t countdown runs (action-bar seconds + final
 *       bells), then stragglers are pulled aboard and the door is removed.</li>
 *   <li><b>ARRIVAL</b> — the {@code intro_v3_ship} deck flyaround (the old
 *       {@code FinaleRitual} arrival beat), held for {@value #ARRIVAL_HOLD_TICKS}t
 *       (the old {@code SUMMON_TICK}).</li>
 *   <li><b>TRANSFORM</b> — {@value #TRANSFORM_TICKS}t transformation beat on the ship:
 *       deck/mast pieces lift as {@code BLOCK_DISPLAY}s spiraling upward (C7 flight
 *       animator transport: keyframed interpolated pose pushes per piece, CUT-END
 *       staggered — per-piece launch delays, masts corkscrewing later and harder than
 *       the deck; BD-SHIP eased arcs, golden-angle spiral phases and a roll-into-place
 *       1.05 overshoot), escalating shakes, veil, then a wind-gust veil-peel burst rides the
 *       white-out ({@code S2CPortalFxPayload}) that covers the {@code FreezeService.transport}
 *       of every fighter into {@code eclipse:ferryman_arena} (ghosts land on the
 *       spectator ship). The Ferryman rises there through C9's anchor-parameterized
 *       {@code summon} overload — his bossbar carries the {@code boss_ferryman} music
 *       cue with him (client-side bossbar hook, dimension-agnostic).</li>
 *   <li><b>FIGHT</b> — the boss owns the fight; this class only keeps the pit chunks
 *       force-loaded (so the boss's own wipe/reset watchdogs tick without players),
 *       shields spectators (players beyond z {@value ArenaBuilder#SPECTATOR_ZONE_MIN_Z}),
 *       and watches for the three endings: victory ({@code FinaleRitual.beginVictory}
 *       already fired from {@code FerrymanEntity.die}; the trip home leaves from the
 *       arena), or wipe/reset (boss gone without the defeat flag → everyone still in the
 *       arena is returned and the crossing re-arms from the altar).</li>
 * </ol>
 *
 * <p><b>Restart law</b> (plan C10.5): a restart never resumes mid-gate/mid-transform —
 * {@link #onServerStarted} either re-enters the FIGHT watch (fight flag + persisted
 * boss) or falls back to the gate (a still-standing altar door re-arms; players stranded
 * in limbo/arena re-arm on login via {@link #onPlayerLoggedIn}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ArenaFight {
    /** Gate hold: the door stays open at most this long (90 s). */
    public static final int GATE_TIMEOUT_TICKS = 1800;
    /** Departure countdown (10 s) — runs once everyone crossed or the timeout nears. */
    public static final int GATE_COUNTDOWN_TICKS = 200;
    /** Arrival flyaround hold before the transformation (the old {@code SUMMON_TICK}). */
    public static final int ARRIVAL_HOLD_TICKS = 100;
    /** Transformation beat length on the limbo ship. */
    public static final int TRANSFORM_TICKS = 60;
    /** Transform tick at which the white-out fires (hold covers the arena transport). */
    private static final int WHITEOUT_TICK = 25;
    private static final int WHITEOUT_HOLD_TICKS = 45;
    /** Command tag on every transformation block-display piece (restart sweep). */
    public static final String MORPH_TAG = "eclipse_ferry_morph";
    /** Golden angle (radians) — phyllotaxis phase offsets for the morph spiral (BD-SHIP). */
    private static final float GOLDEN_ANGLE = 2.3999632F;
    /**
     * Morph keyframe transport (BD-SHIP): pushes every {@value #MORPH_KEY_SPACING}t from
     * t={@value #MORPH_LAUNCH_TICK} sample an eased arc-and-roll trajectory —
     * piecewise-linear interpolation windows approximate the curve while every window
     * stays under the ~90° rotation flattening threshold (VFXPOLISH-3 window law).
     * Every piece reaches its formation pose ×1.05 at t={@value #MORPH_ARRIVE_TICK} and
     * settles to the exact pose by t={@value #MORPH_SETTLE_TICK} (roll into place).
     */
    private static final int MORPH_LAUNCH_TICK = 2;
    private static final int MORPH_KEY_SPACING = 8;
    private static final int MORPH_ARRIVE_TICK = 50;
    private static final int MORPH_SETTLE_TICK = TRANSFORM_TICKS - 2;
    /** "Aboard" bounding box half-extents around the limbo ship origin. */
    private static final double ABOARD_HALF_X = 26.0D;
    private static final double ABOARD_HALF_Z = 16.0D;
    /** Post-recovery grace before a "boss missing" fight end may fire (entity load lag). */
    private static final int FIGHT_WATCH_GRACE_TICKS = 200;
    /** FIGHT watch: everyone gone from the arena this long ends an abandoned fight. */
    private static final int FIGHT_ABANDON_TICKS = 2400;

    private enum Stage { IDLE, GATE, ARRIVAL, TRANSFORM, FIGHT }

    // --- transient stage state (server thread only; a restart re-derives everything) ---
    private static Stage stage = Stage.IDLE;
    private static int gateTicks;
    private static int countdownTicks = -1;
    private static int arrivalTicks;
    private static int transformTicks;
    private static int fightGraceTicks;
    private static int arenaEmptyTicks;
    private static final List<UUID> morphDisplays = new ArrayList<>();
    /** Deck pieces occupy {@code morphDisplays[0..morphDeckPieces)}; mast pieces follow. */
    private static int morphDeckPieces;
    /** Fight-scoped arena accent displays (BD-SHIP; spawned/animated/swept via ArenaBuilder). */
    private static final List<UUID> accentDisplays = new ArrayList<>();
    /**
     * THE current fight's boss (set at summon; adopted on restart-resume when the
     * persisted boss streams in). Any OTHER Ferryman joining the arena is an orphan of
     * an ended/crashed run and gets discarded by the join-time stray guard — never
     * killed ({@code die()} would fire the whole victory theater).
     */
    private static UUID fightBossUuid;
    /**
     * True only inside the {@code finishTransform} summon call: the fresh boss's OWN
     * join event fires synchronously inside {@code addFreshEntity} — before the
     * {@code fightBossUuid} assignment lands and while the stage still reads TRANSFORM —
     * so the guard adopts that one join instead of judging it.
     */
    private static boolean summoningFightBoss;

    private ArenaFight() {}

    // ------------------------------------------------------------------ public surface

    /** Whether any crossing stage is live (gate/arrival/transform/fight watch). */
    public static boolean isBusy() {
        return stage != Stage.IDLE;
    }

    /** Whether the arena fight itself runs (persisted; drives the spectator branch). */
    public static boolean isFightRunning(MinecraftServer server) {
        return ArenaState.get(server).isFightRunning();
    }

    /**
     * Arms the crossing from the altar (catalyst already consumed by
     * {@code FinaleRitual}): builds the arena if needed, stamps the dead door and opens
     * the wait-for-all gate. Falls back to the doorless gate (everyone shipped
     * immediately, countdown still runs) when the door blocks are unavailable.
     */
    public static void armGate(ServerLevel altarLevel, BlockPos altarPos) {
        MinecraftServer server = altarLevel.getServer();
        if (stage != Stage.IDLE) {
            EclipseMod.LOGGER.warn("Ferry gate already busy ({}); ignoring armGate", stage);
            return;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Ferry gate aborted: limbo dimension is not loaded");
            return;
        }
        sweepMorphDisplays(limbo);
        ServerLevel arena = ArenaDimension.get(server);
        if (arena != null) {
            ArenaBuilder.ensureBuilt(arena);
            ArenaBuilder.sweepAccentDisplays(arena); // belt-and-braces: accents are fight-scoped
        } else {
            EclipseMod.LOGGER.warn("Ferry arena dimension {} is not loaded — the fight will stay on the limbo ship",
                    ArenaDimension.ARENA.location());
        }
        stage = Stage.GATE;
        gateTicks = 0;
        countdownTicks = -1;
        GoalTracker.onFinaleBegun(server); // day-14 "Offer the egg at dusk" auto-tick
        boolean doorPlaced = AltarDoor.place(altarLevel, altarPos);
        if (!doorPlaced) {
            shipStragglers(server, limbo); // doorless fallback: the old direct crossing
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    doorPlaced ? "eclipse.caption.ferry.door" : "eclipse.caption.ferry.wait",
                    100, S2CCaptionPayload.STYLE_TITLE));
        }
        EclipseMod.LOGGER.info("Ferry gate armed at the altar ({} door): {}t timeout, {}t countdown",
                doorPlaced ? "dead" : "NO", GATE_TIMEOUT_TICKS, GATE_COUNTDOWN_TICKS);
    }

    /**
     * Re-arms the gate for players ALREADY on the limbo deck (restart/login recovery —
     * the catalyst was consumed in a previous run, no altar door): the wait-for-all hold
     * and countdown run exactly as after a door crossing.
     */
    public static void armGateAboard(MinecraftServer server) {
        if (stage != Stage.IDLE || ArenaState.get(server).isFightRunning()) {
            return;
        }
        ServerLevel arena = ArenaDimension.get(server);
        if (arena != null) {
            ArenaBuilder.ensureBuilt(arena);
            ArenaBuilder.sweepAccentDisplays(arena); // belt-and-braces: accents are fight-scoped
        }
        stage = Stage.GATE;
        gateTicks = 0;
        countdownTicks = -1;
        EclipseMod.LOGGER.info("Ferry gate re-armed aboard (recovery): crossing resumes from the wait-for-all hold");
    }

    /**
     * FERRYMAN2 handoff ({@code finale.FinaleSequence}): the key already opened the
     * PORTAL GATE on the shore, the screens are purple — everyone is shipped to the
     * limbo deck IMMEDIATELY (no altar door, the portal WAS the door) and the crossing
     * resumes from the wait-for-all hold (countdown starts on the next aboard check).
     * Returns whether the crossing was armed (false = machinery busy, caller logs it).
     */
    public static boolean armGateThroughPortal(MinecraftServer server) {
        if (stage != Stage.IDLE || ArenaState.get(server).isFightRunning()) {
            EclipseMod.LOGGER.warn("Ferry portal handoff refused: crossing busy (stage {}, fight {})",
                    stage, ArenaState.get(server).isFightRunning());
            return false;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Ferry portal handoff aborted: limbo dimension is not loaded");
            return false;
        }
        sweepMorphDisplays(limbo);
        ServerLevel arena = ArenaDimension.get(server);
        if (arena != null) {
            ArenaBuilder.ensureBuilt(arena);
            ArenaBuilder.sweepAccentDisplays(arena); // belt-and-braces: accents are fight-scoped
        } else {
            EclipseMod.LOGGER.warn("Ferry arena dimension {} is not loaded — the fight will stay on the limbo ship",
                    ArenaDimension.ARENA.location());
        }
        stage = Stage.GATE;
        gateTicks = 0;
        countdownTicks = -1;
        GoalTracker.onFinaleBegun(server); // idempotent team beat (portal path bypasses armGate)
        shipStragglers(server, limbo);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.caption.ferry.wait", 100, S2CCaptionPayload.STYLE_TITLE));
        }
        EclipseMod.LOGGER.info("Ferry gate armed THROUGH THE PORTAL: everyone shipped, {}t countdown pending",
                GATE_COUNTDOWN_TICKS);
        return true;
    }

    /**
     * FIN-5 mid-fight transformation, called by {@code FerrymanEntity.onPhaseChanged} at
     * the P3 toll break: the arena TRANSFORMS during the fight — a ribcage of bone teeth
     * erupts around the pit rim ({@link ArenaBuilder#spawnEscalationDisplays}, appended
     * to the fight-scoped accent list so the stray guard / animate stride / end-of-fight
     * sweep all cover it) under an arena-wide quake, deep bell and caption. No-op
     * outside the FIGHT watch (legacy limbo fights and test summons never reach it).
     */
    public static void escalateArena(ServerLevel arena) {
        if (stage != Stage.FIGHT) {
            return;
        }
        int spawned = ArenaBuilder.spawnEscalationDisplays(arena, accentDisplays);
        if (spawned == 0) {
            return; // already erupted this fight (phase yo-yo via healing/test commands)
        }
        int pitY = ArenaBuilder.pitY(arena);
        PacketDistributor.sendToPlayersNear(arena, null, 0.5D, pitY + 2.0D, 0.5D, 128.0D,
                S2CShakePayload.shake(0.9F, 30));
        PacketDistributor.sendToPlayersNear(arena, null, 0.5D, pitY + 2.0D, 0.5D, 128.0D,
                new S2CCaptionPayload("eclipse.caption.ferry.bones", 90, S2CCaptionPayload.STYLE_SUBTITLE));
        BlockPos center = new BlockPos(0, pitY, 0);
        // FX-12 parity: the rib eruption gets the shared boss roar ring the Herald/Ferryman
        // breaks fire (the row ignores a/b — 0/0 is the convention). The planned world_grade
        // dim thump is deliberately NOT sent here: eclipse:ferryman_arena is neither the
        // overworld nor the nether, so VeilPostController.wantWorldGrade never activates the
        // pass in this dimension — the cue would be dead weight that could only misfire on a
        // player who leaves the arena inside the release window.
        FxPayloads.sendFxEvent(arena, FxCues.CUE_BOSS_ROAR,
                new Vec3(0.5D, pitY + 1.0D, 0.5D), 0.0F, 0.0F, 128.0D);
        arena.playSound(null, center, SoundEvents.END_PORTAL_SPAWN, SoundSource.HOSTILE, 1.2F, 0.35F);
        arena.playSound(null, center, EclipseSounds.BOSS_FERRYMAN_BELL.get(), SoundSource.HOSTILE, 1.4F, 0.5F);
        EclipseMod.LOGGER.info("Arena fight: P3 escalation — {} bone rib display(s) rising, quake + bell sent",
                spawned);
    }

    /**
     * Mid-fight respawn seam for {@code DeathFlowHooks}: while the arena fight runs,
     * dead/banned players respawn on the spectator ship instead of the limbo door flow.
     * Returns whether the redirect happened.
     */
    public static boolean redirectRespawnToSpectator(ServerPlayer player) {
        MinecraftServer server = player.server;
        if (!ArenaState.get(server).isFightRunning()) {
            return false;
        }
        ServerLevel arena = ArenaDimension.get(server);
        if (arena == null) {
            return false;
        }
        Vec3 spot = ArenaBuilder.spectatorSpawn(arena);
        player.teleportTo(arena, spot.x, spot.y, spot.z, 180.0F, 10.0F); // facing the fight (−Z)
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                "eclipse.caption.ferry.spectator", 90, S2CCaptionPayload.STYLE_WHISPER));
        EclipseMod.LOGGER.info("Arena fight: {} respawned onto the spectator ship ({})",
                player.getScoreboardName(), BanService.isBanned(player) ? "ghost" : "fallen, hearts left");
        return true;
    }

    // ------------------------------------------------------------------ tick driver

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        switch (stage) {
            case GATE -> tickGate(server);
            case ARRIVAL -> tickArrival(server);
            case TRANSFORM -> tickTransform(server);
            case FIGHT -> {
                tickEruptionDriver(server);
                tickFightWatch(server);
            }
            default -> { }
        }
    }

    /**
     * FXWAVE-9 #1: 4t fine-window driver for the P3 rib eruption (the 20t fight-watch
     * stride swallowed half a rise in one interpolation glide — the "pop"). No-op
     * outside the eruption envelope; ArenaBuilder owns all the choreography state.
     */
    private static void tickEruptionDriver(MinecraftServer server) {
        if (server.getTickCount() % 4 != 0) {
            return;
        }
        ServerLevel arena = ArenaDimension.get(server);
        if (arena != null) {
            ArenaBuilder.tickEruption(arena, accentDisplays);
        }
    }

    // ------------------------------------------------------------------ GATE

    private static void tickGate(MinecraftServer server) {
        // BD-SHIP: the dead door's rising assembly only ever runs inside the GATE stage
        // (if the gate drops, AltarDoor.remove cancels the assembly with it).
        AltarDoor.tickAssembly(server);
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Ferry gate dropped: limbo vanished mid-gate");
            AltarDoor.remove(server);
            stage = Stage.IDLE;
            return;
        }
        gateTicks++;
        tickDoorCrossings(server, limbo);

        if (countdownTicks < 0) {
            boolean timeoutNear = gateTicks >= GATE_TIMEOUT_TICKS - GATE_COUNTDOWN_TICKS;
            boolean allAboard = gateTicks % 20 == 0 && allLivingAboard(server, limbo);
            if (allAboard || timeoutNear) {
                countdownTicks = GATE_COUNTDOWN_TICKS;
                for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                    PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                            "eclipse.caption.ferry.depart", 70, S2CCaptionPayload.STYLE_SUBTITLE));
                }
                EclipseMod.LOGGER.info("Ferry gate countdown started ({}): {}t",
                        allAboard ? "every living player is aboard" : "timeout reached", GATE_COUNTDOWN_TICKS);
            }
            return;
        }
        if (countdownTicks % 20 == 0 && countdownTicks > 0) {
            int seconds = countdownTicks / 20;
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                player.displayClientMessage(
                        ServerLang.tr(player, "message.eclipse.ferry.countdown", seconds), true);
                if (seconds <= 3) {
                    player.playNotifySound(EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                            SoundSource.AMBIENT, 0.8F, 1.0F + (3 - seconds) * 0.15F);
                }
            }
        }
        if (--countdownTicks <= 0) {
            closeGate(server, limbo);
        }
    }

    /** Ships every living player standing in the dead door's walk-through volume. */
    private static void tickDoorCrossings(MinecraftServer server, ServerLevel limbo) {
        AABB volume = AltarDoor.walkVolume(server);
        if (volume == null) {
            return;
        }
        ArenaState state = ArenaState.get(server);
        ServerLevel doorLevel = state.doorDimension() != null ? server.getLevel(state.doorDimension()) : null;
        if (doorLevel == null) {
            return;
        }
        for (ServerPlayer player : new ArrayList<>(doorLevel.players())) {
            if (player.isSpectator() || !player.isAlive() || !volume.contains(player.position())) {
                continue;
            }
            crossToShip(player, limbo);
        }
    }

    /** One player through the door: portal fade → deck (living) / arrival platform (ghost). */
    private static void crossToShip(ServerPlayer player, ServerLevel limbo) {
        GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(S2CPortalFxPayload.Phase.ENTER,
                XboxPayloads.TRANSITION_STYLE, XboxPayloads.TRANSITION_HOLD_TICKS));
        if (BanService.isBanned(player)) {
            BlockPos arrival = GhostShipBuilder.platformArrivalPos(limbo);
            player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D, 0.0F, 0.0F);
        } else {
            int aboard = countLivingAboard(limbo);
            BlockPos deck = deckSpot(aboard);
            int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
            player.teleportTo(limbo, deck.getX() + 0.5D, deckY + 1, deck.getZ() + 0.5D, -90.0F, 0.0F);
        }
        PacketDistributor.sendToPlayer(player,
                new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                "eclipse.caption.ferry.crossed", 70, S2CCaptionPayload.STYLE_WHISPER));
        EclipseMod.LOGGER.info("Ferry gate: {} walked through the dead door ({})",
                player.getScoreboardName(), BanService.isBanned(player) ? "ghost" : "living");
    }

    /** Deterministic deck spread around midship (the old FinaleRitual spots). */
    private static BlockPos deckSpot(int index) {
        int x = 2 + 2 * (index % 3);
        int z = (index / 3 % 3) - 1;
        return new BlockPos(x, 0, z);
    }

    private static boolean isAboard(ServerPlayer player, ServerLevel limbo) {
        return player.serverLevel() == limbo
                && Math.abs(player.getX()) <= ABOARD_HALF_X
                && Math.abs(player.getZ()) <= ABOARD_HALF_Z;
    }

    private static int countLivingAboard(ServerLevel limbo) {
        int aboard = 0;
        for (ServerPlayer player : limbo.players()) {
            if (player.isAlive() && !player.isSpectator() && !BanService.isBanned(player)
                    && isAboard(player, limbo)) {
                aboard++;
            }
        }
        return aboard;
    }

    /** Wait-for-all condition: ≥1 living player aboard AND no living player elsewhere. */
    private static boolean allLivingAboard(MinecraftServer server, ServerLevel limbo) {
        int aboard = 0;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator() || BanService.isBanned(player) || !player.isAlive()) {
                continue;
            }
            if (!isAboard(player, limbo)) {
                return false;
            }
            aboard++;
        }
        return aboard > 0;
    }

    /** Pulls every straggler aboard (living → deck, ghosts far from the ship → platform). */
    private static void shipStragglers(MinecraftServer server, ServerLevel limbo) {
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        int living = countLivingAboard(limbo);
        int pulled = 0;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator()) {
                continue;
            }
            if (BanService.isBanned(player)) {
                if (player.serverLevel() != limbo
                        || player.position().distanceToSqr(0.5D, deckY, 0.5D) > 64.0D * 64.0D) {
                    BlockPos arrival = GhostShipBuilder.platformArrivalPos(limbo);
                    player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D,
                            0.0F, 0.0F);
                    pulled++;
                }
                continue;
            }
            if (!isAboard(player, limbo)) {
                GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(S2CPortalFxPayload.Phase.ENTER,
                        XboxPayloads.TRANSITION_STYLE, XboxPayloads.TRANSITION_HOLD_TICKS));
                BlockPos deck = deckSpot(living++);
                player.teleportTo(limbo, deck.getX() + 0.5D, deckY + 1, deck.getZ() + 0.5D, -90.0F, 0.0F);
                pulled++;
            }
        }
        if (pulled > 0) {
            EclipseMod.LOGGER.info("Ferry gate: {} straggler(s) pulled aboard", pulled);
        }
    }

    private static void closeGate(MinecraftServer server, ServerLevel limbo) {
        countdownTicks = -1;
        shipStragglers(server, limbo);
        AltarDoor.remove(server);
        List<ServerPlayer> aboard = new ArrayList<>(limbo.players());
        for (ServerPlayer player : aboard) {
            PacketDistributor.sendToPlayer(player,
                    new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
        }
        // W6: the intro_v3_ship deck flyaround is the arrival beat (limbo-scoped play).
        CutsceneService.play("intro_v3_ship", aboard);
        stage = Stage.ARRIVAL;
        arrivalTicks = 0;
        EclipseMod.LOGGER.info("Ferry gate closed: {} player(s) aboard, arrival flyaround playing — "
                + "transformation in {}t", aboard.size(), ARRIVAL_HOLD_TICKS);
    }

    // ------------------------------------------------------------------ ARRIVAL

    private static void tickArrival(MinecraftServer server) {
        if (arrivalTicks++ < ARRIVAL_HOLD_TICKS) {
            return;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Ferry arrival dropped: limbo vanished before the transformation");
            stage = Stage.IDLE;
            return;
        }
        ServerLevel arena = ArenaDimension.get(server);
        if (arena == null) {
            if (ferrymanAlive(limbo)) {
                // Legacy limbo fights have no fight flag — a boss afloat may be mid-fight.
                EclipseMod.LOGGER.info("Ferry arrival: a Ferryman is already afloat; skipping the crossing");
                stage = Stage.IDLE;
                return;
            }
            // No arena dimension: legacy limbo fight (the pre-C10 flow), no transform.
            FerrymanEntity.summon(limbo);
            stage = Stage.IDLE;
            EclipseMod.LOGGER.info("Ferry arrival: arena missing — Ferryman summoned on the limbo ship (legacy)");
            return;
        }
        if (ArenaState.get(server).isFightRunning() && (ferrymanAlive(limbo) || ferrymanAlive(arena))) {
            EclipseMod.LOGGER.info("Ferry arrival: a Ferryman is already afloat; skipping the crossing");
            stage = Stage.IDLE;
            return;
        }
        // Modern flow with the fight flag OFF: a boss still afloat is an orphan of an
        // ended/aborted run (armGate* refuses to arm while a fight runs; an instant
        // victory-latch end leaves the entity behind without cleanPit) — the crossing
        // is authoritative, sweep the strays instead of aborting the whole show.
        discardBoss(limbo);
        discardBoss(arena);
        beginTransform(server, limbo);
    }

    // ------------------------------------------------------------------ TRANSFORM

    private static void beginTransform(MinecraftServer server, ServerLevel limbo) {
        stage = Stage.TRANSFORM;
        transformTicks = 0;
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        Vec3 center = new Vec3(0.5D, deckY + 2.0D, 0.5D);
        for (ServerPlayer player : limbo.players()) {
            // Freeze THROUGH the dimension hop; released explicitly after the transport.
            FreezeService.freeze(player, TRANSFORM_TICKS + 100, true, 0);
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.caption.ferry.transform", 80, S2CCaptionPayload.STYLE_WHISPER));
        }
        spawnMorphDisplays(limbo, deckY);
        PacketDistributor.sendToPlayersNear(limbo, null, center.x, center.y, center.z, 96.0D,
                new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, center));
        PacketDistributor.sendToPlayersNear(limbo, null, center.x, center.y, center.z, 96.0D,
                S2CShakePayload.shake(0.7F, TRANSFORM_TICKS));
        limbo.playSound(null, BlockPos.containing(center), SoundEvents.END_PORTAL_SPAWN,
                SoundSource.AMBIENT, 1.4F, 0.4F);
        EclipseMod.LOGGER.info("Ferry transformation beat started: {} morph display piece(s), {}t to the arena",
                morphDisplays.size(), TRANSFORM_TICKS);
    }

    /**
     * The morph FX layer: deterministic deck-plank and mast pieces spawned as block
     * displays over the real (untouched) ship blocks — the "real block swap" is the
     * pre-stamped arena itself, so a crash mid-beat never leaves a half-ship.
     */
    private static void spawnMorphDisplays(ServerLevel limbo, int deckY) {
        morphDisplays.clear();
        for (int dx = -18; dx <= 18; dx += 3) {
            for (int dz = -4; dz <= 4; dz += 4) {
                if (Math.abs(dz) > GhostShipBuilder.halfWidthAt(dx)) {
                    continue;
                }
                spawnMorphPiece(limbo, new Vec3(dx, deckY, dz), Blocks.DARK_OAK_PLANKS.defaultBlockState());
            }
        }
        morphDeckPieces = morphDisplays.size(); // CUT-END: pieces past this index are masts
        for (int mastX : GhostShipBuilder.MAST_X) {
            for (int dy = 2; dy <= 8; dy += 3) {
                spawnMorphPiece(limbo, new Vec3(mastX, deckY + dy, 0), Blocks.DARK_OAK_LOG.defaultBlockState());
            }
        }
    }

    private static void spawnMorphPiece(ServerLevel limbo, Vec3 pos, BlockState state) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, limbo);
        display.setBlockState(state);
        display.moveTo(pos.x, pos.y, pos.z, 0.0F, 0.0F);
        display.addTag(MORPH_TAG);
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(new Transformation(new Vector3f(), new Quaternionf(),
                new Vector3f(1.0F, 1.0F, 1.0F), new Quaternionf()));
        morphDisplays.add(display.getUUID()); // before addFreshEntity: the join guard must know it
        limbo.addFreshEntity(display);
    }

    private static void tickTransform(MinecraftServer server) {
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Ferry transformation dropped: limbo vanished mid-beat");
            stage = Stage.IDLE;
            return;
        }
        transformTicks++;
        if (transformTicks >= MORPH_LAUNCH_TICK && transformTicks <= MORPH_SETTLE_TICK - MORPH_KEY_SPACING
                && (transformTicks - MORPH_LAUNCH_TICK) % MORPH_KEY_SPACING == 0) {
            pushMorphKeyframe(limbo, transformTicks);
        }
        if (transformTicks % 15 == 0) {
            // CUT-END shot 5: the shakes ESCALATE with the spiral instead of ticking flat.
            int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
            float rising = 0.35F + 0.4F * (transformTicks / (float) TRANSFORM_TICKS);
            PacketDistributor.sendToPlayersNear(limbo, null, 0.5D, deckY + 2.0D, 0.5D, 96.0D,
                    S2CShakePayload.shake(rising, 16));
        }
        if (transformTicks == WHITEOUT_TICK) {
            // CUT-END shot 5: the shroud veil PEELS — one wind-gust burst (whoosh + sharp
            // shake + a last veil one-shot ABOVE the deck, so the peel reads up-and-away)
            // rides the exact white-out instant that swallows the ship.
            int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
            Vec3 gust = new Vec3(0.5D, deckY + 8.0D, 0.5D);
            limbo.playSound(null, BlockPos.containing(gust), EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                    SoundSource.AMBIENT, 1.6F, 0.85F);
            PacketDistributor.sendToPlayersNear(limbo, null, gust.x, gust.y, gust.z, 96.0D,
                    new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, gust));
            PacketDistributor.sendToPlayersNear(limbo, null, gust.x, gust.y, gust.z, 96.0D,
                    S2CShakePayload.shake(0.9F, 14));
            for (ServerPlayer player : limbo.players()) {
                GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(S2CPortalFxPayload.Phase.ENTER,
                        XboxPayloads.TRANSITION_STYLE, WHITEOUT_HOLD_TICKS));
            }
        }
        if (transformTicks >= TRANSFORM_TICKS) {
            finishTransform(server, limbo);
        }
    }

    /**
     * One keyframe push per piece — the CUT-END stagger kept (deck planks launch first
     * over a 0–8t spread, masts follow over 6–16t with alternating-handed corkscrews and
     * a tight radial drift), now sampled along a BD-SHIP eased trajectory: outward drift
     * eases OUT while the rise eases IN-OUT (the path bows outward low, then climbs — a
     * genuine ARC), deck pieces roll a half turn about their horizontal tangent axis and
     * the ensemble's drift directions swirl apart on golden-angle phases. Pieces still at
     * their pre-launch fraction re-push their identity pose (equal synched values — the
     * transformation never dirties, so held pieces cost no motion).
     * The window ending at t={@value #MORPH_ARRIVE_TICK} targets the formation ×1.05;
     * the last window settles it exactly — the roll-into-place overshoot.
     *
     * <p>Per-piece launch (EVAL-V6-CUTBD §3, defect 2): a piece whose launch tick falls
     * INSIDE the current window rides a client-side interpolation DELAY of
     * {@code launch − pushTick} and tweens only the remaining {@code windowEnd − launch}
     * ticks — so every piece really starts moving at ITS OWN launch tick instead of the
     * window's push tick (which had collapsed the 0–8/6–16t stagger into two cohorts).</p>
     *
     * <p>Note for the corkscrew retune: the previous single-window ±2.75π push was
     * quaternion-slerp-flattened to ≤135° on the client (one interpolation window can
     * only ever show the shortest arc); ±1.2π across eased 8t windows is the same
     * visible energy, actually rendered.</p>
     */
    private static void pushMorphKeyframe(ServerLevel limbo, int pushTick) {
        int windowEnd = Math.min(pushTick + MORPH_KEY_SPACING, MORPH_SETTLE_TICK);
        boolean settle = pushTick >= MORPH_ARRIVE_TICK;
        int index = 0;
        for (UUID id : morphDisplays) {
            if (!(limbo.getEntity(id) instanceof Display.BlockDisplay display)) {
                index++;
                continue;
            }
            boolean mast = index >= morphDeckPieces;
            double h = hash01(index);
            int launch = MORPH_LAUNCH_TICK + (mast ? 6 + (int) (h * 10.0D) : (int) (h * 8.0D));
            float s = settle ? 1.0F
                    : Math.max(0.0F, Math.min(1.0F,
                            (windowEnd - launch) / (float) (MORPH_ARRIVE_TICK - launch)));
            float overshoot = !settle && windowEnd >= MORPH_ARRIVE_TICK ? 1.05F : 1.0F;
            // Launch inside this window → hold (launch − pushTick)t of delay, tween the
            // rest. Pre-launch pieces (s == 0) keep delay 0 + the full window so their
            // identity re-push stays an equal-value no-op that never dirties.
            int hold = s > 0.0F
                    ? Math.max(0, Math.min(launch - pushTick, windowEnd - pushTick - 1))
                    : 0;
            display.setTransformationInterpolationDelay(hold);
            display.setTransformationInterpolationDuration(windowEnd - pushTick - hold);
            display.setTransformation(morphPose(display, index, mast, h, s, overshoot));
            index++;
        }
    }

    /** Absolute morph pose at eased path fraction {@code s} (deterministic per index). */
    private static Transformation morphPose(Display.BlockDisplay display, int index, boolean mast,
            double h, float s, float overshoot) {
        float rise = (mast ? (float) (10.0D + h * 6.0D) : (float) (6.0D + h * 8.0D)) * overshoot;
        float drift = (mast ? (float) (0.8D + h * 1.2D) : (float) (2.0D + h * 3.0D)) * overshoot;
        // Golden-angle phase in (-π, π]: the ensemble's spiral ordering.
        float golden = (float) Math.IEEEremainder(index * GOLDEN_ANGLE, Math.PI * 2.0D);
        float spinTotal = mast
                ? (float) ((h * 2.0D - 1.0D) * Math.PI * 1.2D)
                : golden * 0.35F + (float) ((h * 2.0D - 1.0D) * Math.PI * 0.35D);
        if (mast && ((index + 1) & 1) == 0) {
            spinTotal = -spinTotal; // CUT-END alternating corkscrew handedness
        }
        Vec3 radial = new Vec3(display.getX(), 0.0D, display.getZ());
        Vec3 dir = radial.lengthSqr() > 1.0E-4D ? radial.normalize() : new Vec3(1.0D, 0.0D, 0.0D);
        // Deck drift directions swirl apart on golden phases — the rising spiral.
        float swirl = mast ? 0.0F : golden * 0.4F * easeInOut(s);
        double cos = Math.cos(swirl);
        double sin = Math.sin(swirl);
        Vec3 out = new Vec3(dir.x * cos - dir.z * sin, 0.0D, dir.x * sin + dir.z * cos)
                .scale(drift * easeOut(s));
        // Masts ease IN-OUT (corkscrew "later and harder", and the ±1.2π total would
        // bust the ~90° window law with ease-out's initial slope on the hardest piece).
        float yaw = spinTotal * (mast ? easeInOut(s) : easeOut(s));
        Quaternionf rotation = new Quaternionf().rotationY(yaw);
        if (!mast) {
            // Planks ROLL a half turn about the horizontal tangent (overshoot rides it).
            float roll = (float) Math.PI * easeInOut(s) * overshoot;
            rotation.mul(new Quaternionf().rotationAxis(roll,
                    new Vector3f((float) -dir.z, 0.0F, (float) dir.x)));
        }
        return new Transformation(
                new Vector3f((float) out.x, rise * easeInOut(s), (float) out.z),
                rotation, new Vector3f(1.0F, 1.0F, 1.0F), new Quaternionf());
    }

    /** Smoothstep ease-in-out. */
    private static float easeInOut(float s) {
        return s * s * (3.0F - 2.0F * s);
    }

    /** Quadratic ease-out. */
    private static float easeOut(float s) {
        return 1.0F - (1.0F - s) * (1.0F - s);
    }

    private static void finishTransform(MinecraftServer server, ServerLevel limbo) {
        sweepMorphDisplays(limbo);
        ServerLevel arena = ArenaDimension.get(server);
        if (arena == null) {
            // The arena vanished mid-beat (datapack yank): fall back to the limbo fight.
            for (ServerPlayer player : limbo.players()) {
                FreezeService.unfreeze(player);
            }
            FerrymanEntity.summon(limbo);
            stage = Stage.IDLE;
            EclipseMod.LOGGER.warn("Ferry transformation: arena missing at transport time — legacy limbo fight");
            return;
        }
        ArenaBuilder.ensureBuilt(arena);
        int fighters = 0;
        int spectators = 0;
        for (ServerPlayer player : new ArrayList<>(limbo.players())) {
            if (player.isSpectator()) {
                continue;
            }
            if (BanService.isBanned(player)) {
                Vec3 spot = ArenaBuilder.spectatorSpawn(arena);
                FreezeService.transport(player, arena, spot, 180.0F, 10.0F);
                spectators++;
            } else {
                Vec3 spot = ArenaBuilder.fighterSpot(arena, fighters++);
                FreezeService.transport(player, arena, spot, 90.0F, 0.0F); // facing the stern rise
            }
            FreezeService.unfreeze(player);
            PacketDistributor.sendToPlayer(player,
                    new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
        }
        discardBoss(arena); // a stray that streamed in after the arrival sweep (async entities)
        summoningFightBoss = true;
        try {
            fightBossUuid = FerrymanEntity.summon(arena, ArenaBuilder.summonAnchor(arena), -90.0F).getUUID();
        } finally {
            summoningFightBoss = false;
        }
        forcePitChunks(arena, true);
        ArenaBuilder.spawnAccentDisplays(arena, accentDisplays); // fight dressing (BD-SHIP)
        ArenaState.get(server).setFightRunning(true);
        stage = Stage.FIGHT;
        fightGraceTicks = FIGHT_WATCH_GRACE_TICKS;
        arenaEmptyTicks = 0;
        EclipseMod.LOGGER.info("Ferry crossing complete: {} fighter(s) + {} spectator ghost(s) transported to {}; "
                + "the Ferryman rises in the arena", fighters, spectators, ArenaDimension.ARENA.location());
    }

    // ------------------------------------------------------------------ FIGHT watch

    private static void tickFightWatch(MinecraftServer server) {
        if (server.getTickCount() % 20 != 0) {
            return;
        }
        if (fightGraceTicks > 0) {
            fightGraceTicks -= 20;
        }
        if (EclipseWorldState.get(server).isFerrymanDefeated()) {
            // Victory: FerrymanEntity.die already fired FinaleRitual.beginVictory; the
            // mass revive + trip home (now arena-aware) run there.
            endFight(server, "victory — FinaleRitual owns the revive and the trip home", false);
            return;
        }
        ServerLevel arena = ArenaDimension.get(server);
        if (arena == null) {
            endFight(server, "arena dimension vanished", true);
            return;
        }
        // BD-SHIP accents ride the watch stride (one 20t window per display per second;
        // at worst one wasted push on the very tick the fight ends — endFight sweeps).
        ArenaBuilder.animateAccentDisplays(arena, accentDisplays);
        arenaEmptyTicks = arena.players().isEmpty() ? arenaEmptyTicks + 20 : 0;
        boolean bossGone = fightGraceTicks <= 0 && !ferrymanAlive(arena);
        if (bossGone) {
            // Wipe or reset: the boss announced/restored on its own way out (checkWipe /
            // tickReset) — return everyone and re-arm the crossing from the altar.
            returnArenaPlayers(server, arena);
            endFight(server, "the Ferryman is gone (wipe/reset) — crossing re-arms from the altar", true);
            return;
        }
        if (arenaEmptyTicks >= FIGHT_ABANDON_TICKS) {
            // Everyone left/logged out long ago; the forced pit chunks kept the boss
            // ticking so its own reset usually fires first — this is the backstop.
            endFight(server, "arena abandoned", true);
        }
    }

    private static void endFight(MinecraftServer server, String reason, boolean cleanPit) {
        ServerLevel arena = ArenaDimension.get(server);
        if (arena != null) {
            ArenaBuilder.sweepAccentDisplays(arena); // by tag, before the chunks unforce
            forcePitChunks(arena, false);
            if (cleanPit) {
                discardBoss(arena);
                ArenaBuilder.relightRing(arena);
                drainPit(arena);
            }
        }
        accentDisplays.clear();
        fightBossUuid = null;
        ArenaState.get(server).setFightRunning(false);
        stage = Stage.IDLE;
        arenaEmptyTicks = 0;
        EclipseMod.LOGGER.info("Arena fight ended: {}", reason);
    }

    /** Returns everyone still in the arena: ghosts → limbo platform, living → world spawn. */
    private static void returnArenaPlayers(MinecraftServer server, ServerLevel arena) {
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        ServerLevel overworld = server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        for (ServerPlayer player : new ArrayList<>(arena.players())) {
            if (BanService.isBanned(player) && limbo != null) {
                BlockPos arrival = GhostShipBuilder.platformArrivalPos(limbo);
                player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D,
                        0.0F, 0.0F);
            } else {
                BlockPos column = spawn.offset(2 * (returned % 5 - 2), 0, 2 * (returned / 5 % 5 - 2));
                int y = SpawnReturns.homeY(overworld, column);
                player.teleportTo(overworld, column.getX() + 0.5D, y, column.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
            }
            returned++;
        }
        if (returned > 0) {
            EclipseMod.LOGGER.info("Arena fight: {} player(s) returned out of the arena", returned);
        }
    }

    /** Belt-and-braces: any boss left behind by an abnormal end is discarded. */
    private static void discardBoss(ServerLevel arena) {
        for (FerrymanEntity ferryman : arena.getEntities(EclipseEntities.FERRYMAN.get(), Entity::isAlive)) {
            ferryman.discard();
            EclipseMod.LOGGER.info("Arena fight cleanup: stray Ferryman discarded");
        }
    }

    /** Drains leftover P3 sink water from the pit (spilled flowing water self-drains). */
    private static void drainPit(ServerLevel arena) {
        int pitY = ArenaBuilder.pitY(arena);
        int drained = 0;
        for (int layer = 1; layer <= 4; layer++) {
            for (int dx = -GhostShipBuilder.HALF_LENGTH; dx <= GhostShipBuilder.HALF_LENGTH; dx++) {
                int hw = GhostShipBuilder.halfWidthAt(dx);
                for (int dz = -hw; dz <= hw; dz++) {
                    BlockPos pos = new BlockPos(dx, pitY + layer, dz);
                    if (arena.getBlockState(pos).is(Blocks.WATER)) {
                        arena.setBlockAndUpdate(pos, Blocks.AIR.defaultBlockState());
                        drained++;
                    }
                }
            }
        }
        if (drained > 0) {
            EclipseMod.LOGGER.info("Arena fight cleanup: {} leftover sink-water block(s) drained", drained);
        }
    }

    /** Keeps the pit area loaded+ticking so the boss's own watchdogs run without players. */
    private static void forcePitChunks(ServerLevel arena, boolean forced) {
        for (int cx = -2; cx <= 1; cx++) {
            for (int cz = -1; cz <= 0; cz++) {
                arena.setChunkForced(cx, cz, forced);
            }
        }
    }

    // ------------------------------------------------------------------ spectator guard

    /** "No interference" shield: arena players in the spectator zone take no damage. */
    @SubscribeEvent
    static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !ArenaDimension.isInArena(player)
                || player.getZ() < ArenaBuilder.SPECTATOR_ZONE_MIN_Z
                || event.getSource().is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return;
        }
        if (ArenaState.get(player.server).isFightRunning()) {
            event.setCanceled(true);
        }
    }

    // ------------------------------------------------------------------ restart recovery

    /**
     * Restart law: never resume mid-gate/mid-transform. A persisted boss + fight flag
     * re-enters the FIGHT watch; a still-standing altar door re-arms the gate; anything
     * else clears back to IDLE (login recovery re-arms aboard as players return).
     */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo != null) {
            sweepMorphDisplays(limbo);
        }
        ArenaState state = ArenaState.get(server);
        ServerLevel arena = ArenaDimension.get(server);
        if (state.isFightRunning()) {
            if (arena != null) {
                // Re-force the pit chunks (the stop hook released them — F-080 S6) so the
                // persisted boss loads with them; the grace window covers async loading.
                forcePitChunks(arena, true);
                stage = Stage.FIGHT;
                fightGraceTicks = FIGHT_WATCH_GRACE_TICKS;
                arenaEmptyTicks = 0;
                // Fresh accent set for the resumed fight; persisted strays that load in
                // later are caught by the join-time guard (they are not in the new list).
                ArenaBuilder.spawnAccentDisplays(arena, accentDisplays);
                EclipseMod.LOGGER.info("Arena fight resumed after restart (fight watch re-entered)");
            } else {
                state.setFightRunning(false);
                EclipseMod.LOGGER.warn("Arena fight flag cleared after restart: arena dimension missing");
            }
            return;
        }
        if (state.doorPos() != null) {
            if (EclipseWorldState.get(server).isFerrymanDefeated()) {
                AltarDoor.remove(server); // stale door from a pre-victory run
            } else {
                // A crash inside the rising-assembly window never resumes mid-assembly:
                // stamp instantly and sweep the pieces (the C10.5 mirror, BD-SHIP).
                AltarDoor.ensureStamped(server);
                stage = Stage.GATE;
                gateTicks = 0;
                countdownTicks = -1;
                if (arena != null) {
                    ArenaBuilder.ensureBuilt(arena);
                }
                EclipseMod.LOGGER.info("Ferry gate re-armed after restart: the altar dead door still stands at {}",
                        state.doorPos().toShortString());
            }
        }
    }

    /**
     * Mid-crossing login recovery (the old FinaleRitual seam, gate-shaped): the catalyst
     * was consumed but the boss never rose — a living player logging back into limbo (or
     * stranded in a boss-less arena) re-arms the wait-for-all gate instead of the old
     * direct summon, so the crossing always restarts from the gate.
     */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || player.isSpectator()) {
            return;
        }
        MinecraftServer server = player.server;
        if (stage != Stage.IDLE || ArenaState.get(server).isFightRunning()
                || EclipseWorldState.get(server).isFerrymanDefeated()
                || DayScheduler.getDay(server) < FinaleRitual.FINALE_DAY) {
            return;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        ServerLevel arena = ArenaDimension.get(server);
        if (limbo == null || ferrymanAlive(limbo) || (arena != null && ferrymanAlive(arena))) {
            return;
        }
        if (arena != null && ArenaDimension.isInArena(player)) {
            // Stranded in a boss-less arena (abnormal end mid-run): back to the deck.
            int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
            BlockPos deck = deckSpot(countLivingAboard(limbo));
            player.teleportTo(limbo, deck.getX() + 0.5D, deckY + 1, deck.getZ() + 0.5D, -90.0F, 0.0F);
            armGateAboard(server);
            EclipseMod.LOGGER.info("Ferry recovery: {} pulled from the boss-less arena back to the deck; "
                    + "gate re-armed", player.getScoreboardName());
            return;
        }
        if (!BanService.isBanned(player) && player.level().dimension().equals(LimboDimension.LIMBO)) {
            armGateAboard(server);
            EclipseMod.LOGGER.info("Ferry recovery: {} rejoined the deck mid-crossing (day {}, no boss afloat) — "
                    + "gate re-armed", player.getScoreboardName(), DayScheduler.getDay(server));
        }
    }

    /** Server stop mid-crossing: transient stages drop; ArenaState already persists. */
    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        if (stage != Stage.IDLE) {
            EclipseMod.LOGGER.info("Ferry crossing stage {} dropped on server stop (re-derived next start)", stage);
        }
        AltarDoor.cancelAssembly(event.getServer()); // discard pieces pre-save (BD-SHIP)
        // F-080 (S6): never persist the pit force-load into the ForcedChunks saved data —
        // a mid-fight stop would otherwise leave eclipse:ferryman_arena ticking forced
        // chunks on every future boot. The mid-fight restart recovery re-forces them
        // (onServerStarted), so the resumed fight watch loses nothing.
        ServerLevel arena = ArenaDimension.get(event.getServer());
        if (arena != null) {
            forcePitChunks(arena, false);
        }
        stage = Stage.IDLE;
        countdownTicks = -1;
        morphDisplays.clear();
        accentDisplays.clear();
        fightBossUuid = null;
    }

    /**
     * Join-time stray guard for the fight accents ({@code StructureFlightFx} doctrine,
     * BD-SHIP): a tagged accent display loading in that THIS session did not spawn is a
     * crash leftover (or an async chunk load racing the resume respawn) — discard it.
     * Same guard for altar-door assembly pieces: their persisted bodies can stream in
     * AFTER {@code AltarDoor.ensureStamped}'s boot sweep ran over a not-yet-loaded chunk.
     * REPASS-BD closed the same seam for MORPH pieces — the boot {@code sweepMorphDisplays}
     * only reaches limbo chunks already loaded at start.
     */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (event.getLevel().isClientSide()) {
            return;
        }
        if (entity.getTags().contains(ArenaBuilder.ACCENT_TAG)
                && !accentDisplays.contains(entity.getUUID())) {
            entity.discard();
        } else if (entity.getTags().contains(AltarDoor.ASSEMBLY_TAG)
                && !AltarDoor.isLivePiece(entity.getUUID())) {
            entity.discard();
        } else if (entity.getTags().contains(MORPH_TAG)
                && !morphDisplays.contains(entity.getUUID())) {
            // REPASS-BD: crash-persisted morph pieces streaming in from a chunk the
            // boot sweep could not reach — same async-load seam as the other families.
            entity.discard();
        } else if (entity instanceof FerrymanEntity ferryman && ArenaDimension.isInArena(ferryman)) {
            // Boss identity guard (same async-load seam): a persisted Ferryman can
            // stream in AFTER the arrival/summon sweeps ran over its still-loading
            // entity section — two bosses, two bossbars. THE fight's boss is the one
            // this session summoned; on restart-resume (fight watch re-entered, no
            // summon) the first one in is adopted instead.
            if (summoningFightBoss || (stage == Stage.FIGHT && fightBossUuid == null)) {
                fightBossUuid = ferryman.getUUID();
            } else if (!ferryman.getUUID().equals(fightBossUuid)) {
                ferryman.discard();
                EclipseMod.LOGGER.info("Arena stray guard: orphaned Ferryman {} discarded on load",
                        ferryman.getUUID());
            }
        }
    }

    // ------------------------------------------------------------------ helpers

    private static boolean ferrymanAlive(ServerLevel level) {
        return !level.getEntities(EclipseEntities.FERRYMAN.get(), FerrymanEntity::isAlive).isEmpty();
    }

    /** Discards every tagged morph display around the ship (crash-leftover sweep). */
    private static void sweepMorphDisplays(ServerLevel limbo) {
        morphDisplays.clear();
        morphDeckPieces = 0;
        AABB sweep = new AABB(-32.0D, 0.0D, -32.0D, 32.0D, 128.0D, 32.0D);
        List<Entity> strays = limbo.getEntities((Entity) null, sweep,
                entity -> entity.getTags().contains(MORPH_TAG));
        if (!strays.isEmpty()) {
            strays.forEach(Entity::discard);
            EclipseMod.LOGGER.info("Ferry transformation: {} stray morph display(s) swept", strays.size());
        }
    }

    /** Fixed positional hash in [0,1) — deterministic morph choreography, no RandomSource. */
    private static double hash01(int index) {
        long h = 0x9E3779B97F4A7C15L * (index + 1);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
    }
}
