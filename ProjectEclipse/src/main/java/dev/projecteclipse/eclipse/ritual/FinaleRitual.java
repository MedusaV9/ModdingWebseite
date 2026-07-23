package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.GoalTracker;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.Items;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The day-14 finale (spec §2.2): the dragon-egg altar ritual that ships everyone off to
 * the Ferryman, and the mass-revive win cinematic afterwards.
 *
 * <p><b>Start</b>: sneak-right-clicking the altar with a {@link #CATALYST DRAGON_EGG}
 * (vanilla item, so this hooks {@link PlayerInteractEvent.RightClickBlock} rather than an
 * {@code Item#useOn} like the Herald's lure) on day {@value #FINALE_DAY}+ after dusk
 * consumes one egg and runs the arrival timeline: every LIVING player is teleported onto
 * the ghost-ship deck (ghost stragglers are pulled to the ship too), the
 * {@code intro_v3_ship} camera path introduces the ship (W6's deck flyaround — it replaced
 * the deleted v1 {@code intro_submerge}), and at t={@value #SUMMON_TICK} the
 * {@link FerrymanEntity} rises at the stern.</p>
 *
 * <p><b>Victory</b> ({@link #beginVictory}, called by {@code FerrymanEntity.die()}): the
 * "THE CROSSING ENDS" boss announce, then every banned player is revived through the
 * regular {@link BanService#unban} path — staggered {@value #REVIVE_STAGGER_TICKS}t apart
 * (offline ghosts are cleared from the persistent set; {@link ReviveRitual#onPlayerLoggedIn}
 * finishes their unban on next login). Once the queue drains, everyone still in limbo is
 * brought home to the overworld spawn and the {@code finale_return} reverse-intro cutscene
 * plays for every online player. A wipe never reaches this class — the Eclipse-victory
 * ending is announced by {@code FerrymanEntity.checkWipe()} and nobody is revived.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FinaleRitual {
    /**
     * The finale catalyst — DELIBERATELY the hard-wired vanilla dragon egg rather than a
     * config knob: the day-13 "Claim the dragon egg" goal feeds straight into this
     * offering, and the egg's one-of-a-kind vanilla status IS the balance (config-routing
     * was considered and rejected — a swapped catalyst would orphan the dragon arc).
     * This constant is the only place that names the item.
     */
    public static final net.minecraft.world.item.Item CATALYST = Items.DRAGON_EGG;
    /** First day the altar accepts the catalyst. */
    public static final int FINALE_DAY = 14;
    /** Arrival timeline tick at which the Ferryman rises (after the intro flight settles). */
    public static final int SUMMON_TICK = 100;
    /** Victory timeline: delay between two consecutive ghost revives. */
    public static final int REVIVE_STAGGER_TICKS = 10;
    /** Victory timeline: pause between the last revive and the trip home + cutscene. */
    private static final int RETURN_DELAY_TICKS = 30;

    // --- arrival timeline state (server thread only) ---
    private static boolean arrivalRunning;
    private static int arrivalTicks;

    // --- victory timeline state (server thread only) ---
    private static boolean victoryRunning;
    private static int victoryCooldown;
    private static final Deque<UUID> reviveQueue = new ArrayDeque<>();

    private FinaleRitual() {}

    // --- the altar hook ---

    /**
     * Sneak + dragon egg on the altar. Vanilla skips block interaction entirely while
     * sneaking with an item in hand and would otherwise place the egg block, so the event
     * is cancelled whenever it targets the altar; refusals explain themselves on the
     * action bar (day, dusk, boss already afloat, crossing already over).
     */
    @SubscribeEvent
    static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !(event.getLevel() instanceof ServerLevel level)
                || !player.isShiftKeyDown()
                || !event.getItemStack().is(CATALYST)
                || !(level.getBlockEntity(event.getPos()) instanceof AltarBlockEntity)) {
            return;
        }
        event.setCanceled(true); // Never place the egg on the altar.
        if (event.getHand() != InteractionHand.MAIN_HAND) {
            return;
        }
        MinecraftServer server = player.server;
        if (EclipseWorldState.get(server).isFerrymanDefeated()) {
            refuse(player, "ritual.eclipse.finale.done");
            return;
        }
        if (DayScheduler.getDay(server) < FINALE_DAY) {
            refuse(player, "ritual.eclipse.finale.day");
            return;
        }
        if (level.isDay()) {
            refuse(player, "ritual.eclipse.finale.dusk");
            return;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Finale ritual refused: limbo dimension {} is not loaded",
                    LimboDimension.LIMBO.location());
            refuse(player, "ritual.eclipse.finale.day");
            return;
        }
        if (arrivalRunning || ferrymanAlive(limbo)) {
            refuse(player, "ritual.eclipse.finale.already");
            return;
        }
        event.getItemStack().shrink(1);
        player.displayClientMessage(Component.translatable("ritual.eclipse.finale.begun"), true);
        level.playSound(null, event.getPos(), SoundEvents.END_PORTAL_SPAWN, SoundSource.BLOCKS, 1.0F, 0.5F);
        EclipseMod.LOGGER.info("{} deposited the finale catalyst at {} on day {} — the crossing begins",
                player.getScoreboardName(), event.getPos().toShortString(), DayScheduler.getDay(server));
        begin(server);
    }

    private static void refuse(ServerPlayer player, String key) {
        player.displayClientMessage(Component.translatable(key), true);
        player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.8F);
    }

    private static boolean ferrymanAlive(ServerLevel limbo) {
        return !limbo.getEntities(dev.projecteclipse.eclipse.entity.EclipseEntities.FERRYMAN.get(),
                FerrymanEntity::isAlive).isEmpty();
    }

    // --- arrival: everyone to the deck, cutscene, boss ---

    /**
     * Starts the arrival timeline (idempotent while one is running): teleports every
     * living player to the ghost-ship deck, pulls ghost stragglers aboard, plays the
     * {@code intro_v3_ship} flight, then summons the Ferryman at t={@value #SUMMON_TICK}.
     * Also the {@code /eclipse boss ferryman summon} path uses {@link FerrymanEntity#summon}
     * directly instead — this timeline is only for the ritual (with the cinematic).
     */
    public static boolean begin(MinecraftServer server) {
        if (arrivalRunning) {
            EclipseMod.LOGGER.warn("Finale arrival already running; ignoring begin()");
            return false;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Finale arrival aborted: limbo dimension is not loaded");
            return false;
        }
        arrivalRunning = true;
        arrivalTicks = 0;

        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        List<ServerPlayer> shipped = new ArrayList<>();
        int living = 0;
        int ghostsPulled = 0;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (player.isSpectator()) {
                continue;
            }
            if (BanService.isBanned(player)) {
                // Ghosts already haunt limbo; only stragglers get pulled back to the ship.
                if (player.level() != limbo
                        || player.position().distanceToSqr(0.5D, deckY, 0.5D) > 64.0D * 64.0D) {
                    BlockPos arrival = GhostShipBuilder.platformArrivalPos(limbo);
                    player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D,
                            0.0F, 0.0F);
                    ghostsPulled++;
                }
                shipped.add(player);
                continue;
            }
            BlockPos deck = deckSpot(living++);
            player.teleportTo(limbo, deck.getX() + 0.5D, deckY + 1, deck.getZ() + 0.5D, -90.0F, 0.0F);
            shipped.add(player);
        }
        for (ServerPlayer player : shipped) {
            PacketDistributor.sendToPlayer(player,
                    new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
        }
        // Limbo-scoped path: everyone is in limbo now, so the flight plays for all of them.
        // W6: v1 intro_submerge was deleted — the intro_v3_ship deck flyaround (player-
        // anchored, 130t) is the compatible replacement for this arrival beat.
        CutsceneService.play("intro_v3_ship", shipped);
        GoalTracker.onFinaleBegun(server); // day-14 "Offer the egg at dusk" auto-tick
        EclipseMod.LOGGER.info("Finale arrival: {} living player(s) shipped to the deck, {} ghost straggler(s) pulled "
                + "aboard; Ferryman rises in {}t", living, ghostsPulled, SUMMON_TICK);
        return true;
    }

    /** Deterministic deck spread around midship (bow side, clear of masts at |x|=8). */
    private static BlockPos deckSpot(int index) {
        int x = 2 + 2 * (index % 3);
        int z = (index / 3 % 3) - 1;
        return new BlockPos(x, 0, z);
    }

    // --- victory: mass revive + trip home + reverse cutscene ---

    /**
     * The Ferryman is dead: announce the crossing's end and revive EVERY banned player
     * through the standard {@link BanService#unban} path, staggered
     * {@value #REVIVE_STAGGER_TICKS}t apart. Safe with zero banned players — the queue
     * simply drains instantly and everyone just gets the trip home + cutscene.
     */
    public static void beginVictory(MinecraftServer server) {
        if (victoryRunning) {
            EclipseMod.LOGGER.warn("Finale victory already running; ignoring beginVictory()");
            return;
        }
        victoryRunning = true;
        victoryCooldown = REVIVE_STAGGER_TICKS;
        reviveQueue.clear();

        AnnouncementService.announce(server, "announce.eclipse.ferryman.victory.title",
                "announce.eclipse.ferryman.victory.sub", S2CAnnouncePayload.STYLE_BOSS);
        for (net.minecraft.server.level.ServerPlayer player : server.getPlayerList().getPlayers()) {
            dev.projecteclipse.eclipse.music.MusicPayloads.sendPlay(player, "victory_theme");
        }
        List<UUID> banned = new ArrayList<>(EclipseWorldState.get(server).getBanned());
        int offline = 0;
        for (UUID id : banned) {
            if (server.getPlayerList().getPlayer(id) != null) {
                reviveQueue.addLast(id);
            } else {
                // Offline ghost: clear the persistent ban now; ReviveRitual.onPlayerLoggedIn
                // completes the unban (mode, team, effects, spawn) on their next login.
                EclipseWorldState.get(server).removeBanned(id);
                offline++;
            }
        }
        EclipseMod.LOGGER.info("Finale mass-revive: {} online ghost(s) queued ({}t apart), {} offline ghost(s) "
                + "cleared for revive-on-login", reviveQueue.size(), REVIVE_STAGGER_TICKS, offline);
    }

    // --- timelines ---

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (arrivalRunning) {
            tickArrival(server);
        }
        if (victoryRunning) {
            tickVictory(server);
        }
    }

    private static void tickArrival(MinecraftServer server) {
        if (arrivalTicks++ < SUMMON_TICK) {
            return;
        }
        arrivalRunning = false;
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Finale arrival: limbo vanished before the summon tick; no boss spawned");
            return;
        }
        if (ferrymanAlive(limbo)) {
            EclipseMod.LOGGER.info("Finale arrival: a Ferryman is already afloat; skipping the ritual summon");
            return;
        }
        FerrymanEntity.summon(limbo);
    }

    private static void tickVictory(MinecraftServer server) {
        if (--victoryCooldown > 0) {
            return;
        }
        if (!reviveQueue.isEmpty()) {
            victoryCooldown = REVIVE_STAGGER_TICKS;
            UUID next = reviveQueue.pollFirst();
            ServerPlayer ghost = server.getPlayerList().getPlayer(next);
            if (ghost != null && BanService.isBanned(ghost)) {
                BanService.unban(ghost); // Restores survival + 1 life and sends them to spawn.
                ghost.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.MASTER, 1.0F, 1.2F);
                EclipseMod.LOGGER.info("Finale mass-revive: {} revived ({} ghost(s) left in the queue)",
                        ghost.getScoreboardName(), reviveQueue.size());
            } else {
                // Disconnected mid-queue (or already revived): clear the persistent ban like
                // beginVictory's offline path, so ReviveRitual.onPlayerLoggedIn finishes the
                // unban on their next login instead of leaving them a ghost after victory.
                EclipseWorldState.get(server).removeBanned(next);
                EclipseMod.LOGGER.info("Finale mass-revive: queued ghost {} logged out or already revived; "
                        + "ban cleared for revive-on-login", next);
            }
            if (reviveQueue.isEmpty()) {
                victoryCooldown = RETURN_DELAY_TICKS; // Beat of silence before the trip home.
            }
            return;
        }
        victoryRunning = false;
        bringEveryoneHome(server);
    }

    /** Ships the living home from limbo and plays the reverse-intro descent for everyone. */
    private static void bringEveryoneHome(MinecraftServer server) {
        ServerLevel overworld = server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        List<ServerPlayer> online = new ArrayList<>(server.getPlayerList().getPlayers());
        for (ServerPlayer player : online) {
            if (player.level().dimension().equals(LimboDimension.LIMBO)) {
                // Deterministic spread so nobody lands inside anyone else (StartEventCutscene pattern).
                BlockPos column = spawn.offset(2 * (returned % 5 - 2), 0, 2 * (returned / 5 % 5 - 2));
                int y = overworld.getHeight(net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        column.getX(), column.getZ());
                player.teleportTo(overworld, column.getX() + 0.5D, y, column.getZ() + 0.5D,
                        overworld.getSharedSpawnAngle(), 0.0F);
                returned++;
            }
        }
        // Overworld-anchored path: everyone is home now, so the descent plays for all.
        CutsceneService.play("finale_return", online);
        EclipseMod.LOGGER.info("Finale return: {} player(s) brought home from limbo; finale_return cutscene "
                + "started for {} online player(s)", returned, online.size());
    }

    /** Server stop mid-finale: drop the timelines; persistent ban state is already saved. */
    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        if (arrivalRunning || victoryRunning || !reviveQueue.isEmpty()) {
            EclipseMod.LOGGER.info("Finale timelines dropped on server stop (arrival={}, victory={}, queued={})",
                    arrivalRunning, victoryRunning, reviveQueue.size());
        }
        arrivalRunning = false;
        victoryRunning = false;
        reviveQueue.clear();
    }

    // --- restart recovery ---

    /**
     * Restart mid-victory: {@code ferrymanDefeated} IS persisted but the revive timeline is
     * not — without this, ghosts banned at the moment of the kill would stay banned forever.
     * Everyone is offline during server start, so {@link #beginVictory}'s offline path clears
     * every remaining ghost for revive-on-login ({@link ReviveRitual#onPlayerLoggedIn}).
     */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        if (state.isFerrymanDefeated() && !state.getBanned().isEmpty() && !victoryRunning) {
            EclipseMod.LOGGER.info("Finale victory resumed after restart: {} banned ghost(s) still pending revive",
                    state.getBanned().size());
            beginVictory(server);
        }
    }

    /**
     * Restart mid-arrival: the catalyst was consumed but the restart landed inside the
     * {@value #SUMMON_TICK}t summon window, so the boss never rose and the crew is stranded
     * on the deck. The player list is empty during {@link ServerStartedEvent}, so the
     * "living players still in limbo" condition is evaluated as they log back in: finale
     * day reached, crossing not yet won, a LIVING (non-banned) player in limbo, no Ferryman
     * afloat → summon him directly (recovery path, no cinematic re-run).
     */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || arrivalRunning
                || player.isSpectator()
                || BanService.isBanned(player)
                || !player.level().dimension().equals(LimboDimension.LIMBO)) {
            return;
        }
        MinecraftServer server = player.server;
        if (EclipseWorldState.get(server).isFerrymanDefeated()
                || DayScheduler.getDay(server) < FINALE_DAY) {
            return;
        }
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null || ferrymanAlive(limbo)) {
            return;
        }
        EclipseMod.LOGGER.info("Finale arrival recovery: {} rejoined the deck mid-crossing (day {}, no boss "
                + "afloat) — summoning the Ferryman directly", player.getScoreboardName(),
                DayScheduler.getDay(server));
        FerrymanEntity.summon(limbo);
    }
}
