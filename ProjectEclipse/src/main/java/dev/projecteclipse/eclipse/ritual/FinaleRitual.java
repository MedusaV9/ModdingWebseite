package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.ferryman.ArenaDimension;
import dev.projecteclipse.eclipse.ferryman.ArenaFight;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.Items;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The day-14 finale (spec §2.2): the dragon-egg altar ritual that opens the crossing to
 * the Ferryman, and the mass-revive win cinematic afterwards.
 *
 * <p><b>Start</b>: sneak-right-clicking the altar with a {@link #CATALYST DRAGON_EGG}
 * (vanilla item, so this hooks {@link PlayerInteractEvent.RightClickBlock} rather than an
 * {@code Item#useOn} like the Herald's lure) on day {@value #FINALE_DAY}+ after dusk
 * consumes one egg and arms the C10 crossing ({@link ArenaFight#armGate}): a dead door
 * rises beside the altar, players walk through onto the ghost-ship deck, and once every
 * living player has crossed (or the gate times out) the ship transforms and the
 * {@link FerrymanEntity} rises in the {@code eclipse:ferryman_arena} dimension. The old
 * instant-teleport arrival timeline lives on inside {@code ferryman.ArenaFight} as the
 * legacy fallback when the arena dimension is missing.</p>
 *
 * <p><b>Victory</b> ({@link #beginVictory}, called by {@code FerrymanEntity.die()}): the
 * "THE CROSSING ENDS" boss announce, then every banned player is revived through the
 * regular {@link BanService#unban} path — staggered {@value #REVIVE_STAGGER_TICKS}t apart
 * (offline ghosts are cleared from the persistent set; {@link ReviveRitual#onPlayerLoggedIn}
 * finishes their unban on next login). Once the queue drains, everyone still in limbo or
 * the fight arena is brought home to the overworld spawn and the {@code finale_return}
 * reverse-intro cutscene plays for every online player. A wipe never reaches this class —
 * the Eclipse-victory ending is announced by {@code FerrymanEntity.checkWipe()} and nobody
 * is revived ({@code ArenaFight}'s fight watch then returns the arena crowd).</p>
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
    /** Victory timeline: delay between two consecutive ghost revives. */
    public static final int REVIVE_STAGGER_TICKS = 10;
    /** Victory timeline: pause between the last revive and the trip home + cutscene. */
    private static final int RETURN_DELAY_TICKS = 30;

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
        ServerLevel arena = ArenaDimension.get(server);
        if (ArenaFight.isBusy() || ArenaFight.isFightRunning(server)
                || ferrymanAlive(limbo) || (arena != null && ferrymanAlive(arena))) {
            refuse(player, "ritual.eclipse.finale.already");
            return;
        }
        event.getItemStack().shrink(1);
        player.displayClientMessage(ServerLang.tr(player, "ritual.eclipse.finale.begun"), true);
        level.playSound(null, event.getPos(), SoundEvents.END_PORTAL_SPAWN, SoundSource.BLOCKS, 1.0F, 0.5F);
        EclipseMod.LOGGER.info("{} deposited the finale catalyst at {} on day {} — the crossing begins",
                player.getScoreboardName(), event.getPos().toShortString(), DayScheduler.getDay(server));
        ArenaFight.armGate(level, event.getPos());
    }

    private static void refuse(ServerPlayer player, String key) {
        player.displayClientMessage(ServerLang.tr(player, key), true);
        player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.8F);
    }

    private static boolean ferrymanAlive(ServerLevel level) {
        return !level.getEntities(dev.projecteclipse.eclipse.entity.EclipseEntities.FERRYMAN.get(),
                FerrymanEntity::isAlive).isEmpty();
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
        if (victoryRunning) {
            tickVictory(event.getServer());
        }
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
        // C15: the revive-drain chains into the final credits sequence. begin() returns false
        // when credits are disabled (config) or the epilogue dimension is missing — in that
        // case we keep the pre-credits behavior: trip home + finale_return descent.
        if (CreditsSequence.begin(server)) {
            return;
        }
        bringEveryoneHome(server);
    }

    /** Ships the living home from limbo/the fight arena and plays the reverse-intro descent. */
    private static void bringEveryoneHome(MinecraftServer server) {
        ServerLevel overworld = server.overworld();
        BlockPos spawn = overworld.getSharedSpawnPos();
        int returned = 0;
        List<ServerPlayer> online = new ArrayList<>(server.getPlayerList().getPlayers());
        for (ServerPlayer player : online) {
            if (player.level().dimension().equals(LimboDimension.LIMBO)
                    || ArenaDimension.isInArena(player)) {
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

    /** Server stop mid-finale: drop the timeline; persistent ban state is already saved. */
    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        if (victoryRunning || !reviveQueue.isEmpty()) {
            EclipseMod.LOGGER.info("Finale victory timeline dropped on server stop (queued={})",
                    reviveQueue.size());
        }
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

    // Mid-crossing login recovery (a living player rejoins the deck with no boss afloat)
    // moved to ferryman.ArenaFight.onPlayerLoggedIn with C10: the gate re-arms and the
    // crossing resumes instead of the old direct summon (two handlers would race).
}
