package dev.projecteclipse.eclipse.woah.resonance;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.entity.EntityTypeTest;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.player.AttackEntityEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-04 lifecycle + gameplay service (§2.2, §3.3, §3.4, §3.7): self-enqueue poll
 * (the {@code SkyLauncher.maybeEnqueue} school — deliberately NOT a DiscMapDefaults
 * row, so existing saves get the field on their first Stage-5 boot), strike routing
 * from the interaction hitboxes, the neighbor-graph cascade queue, brightness pulses,
 * the display spawn budget (4/tick) and the tag-based self-heal that rebuilds a
 * {@code /kill}'ed field deterministically from {@link ResonanceFieldData}.
 *
 * <p>Server tick budget (§3.7): with no player within {@value #ACTIVE_RADIUS} blocks of
 * the anchor (cached, re-checked every 20 ticks) everything early-outs except the
 * one-long COOLDOWN comparison in {@link ResonanceMelodyMachine#tickCooldownAlways}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ResonanceFieldService {
    /** Authored anchor (§2.1: r ≈ 396, ≈184° — savanna sector, crystal-steppe band). */
    public static final int ANCHOR_X = -395;
    public static final int ANCHOR_Z = -30;
    /** The field arrives with the final ring (disc radius 440). */
    public static final int REQUIRED_STAGE = 5;

    /** Self-enqueue poll cadence (SkyLauncher's ENQUEUE_POLL_TICKS school). */
    private static final int ENQUEUE_POLL_TICKS = 20;
    /** Display spawn budget per tick (§3.1 — no addFreshEntity burst). */
    private static final int DISPLAY_SPAWNS_PER_TICK = 4;
    /** Activity gate radius + its cache cadence (§3.7). */
    private static final int ACTIVE_RADIUS = 128;
    private static final int ACTIVE_CHECK_TICKS = 20;
    /** Self-heal cadence (SkyLauncher's 200-tick interaction heal). */
    private static final int SELF_HEAL_TICKS = 200;
    /** Per-crystal strike cooldown (double-click guard, §3.2). */
    private static final int STRIKE_COOLDOWN_TICKS = 8;
    /** Cascade: 3 ticks per hop, depth ≤ 2, queue cap 32 (§3.2). */
    private static final int CASCADE_HOP_TICKS = 3;
    private static final int CASCADE_MAX_DEPTH = 2;
    private static final int CASCADE_QUEUE_CAP = 32;
    /** Shell brightness levels: idle / hint / pulse (§5.5, §7.4). */
    private static final int SHELL_IDLE_BLOCK = 10;
    private static final int SHELL_HINT_BLOCK = 12;
    private static final int SHELL_PULSE_BLOCK = 14;
    private static final int PULSE_RESTORE_TICKS = 8;

    private static final AtomicBoolean BOOTSTRAPPED = new AtomicBoolean();

    /** UUIDs of displays spawned THIS session (join-sweep whitelist, ExpansionBorderFx). */
    private static final Set<UUID> SESSION_DISPLAYS = ConcurrentHashMap.newKeySet();
    /** Queued display spawn jobs, drained {@value #DISPLAY_SPAWNS_PER_TICK}/tick. */
    private static final ArrayDeque<ResonanceFieldBuilder.PendingDisplay> SPAWN_QUEUE =
            new ArrayDeque<>();
    /** Pending cascade hops (server thread only). */
    private static final ArrayDeque<Hop> CASCADE = new ArrayDeque<>();
    /** Pending shell-brightness restores: crystalIdx → due gameTime. */
    private static final Map<Integer, Long> PULSE_RESTORES = new HashMap<>();
    /** Last strike gameTime per crystal (8-tick double-click guard). */
    private static final Map<Integer, Long> LAST_STRIKE = new HashMap<>();

    /** Cached §3.7 activity gate. */
    private static boolean playersNear;
    private static long nextActiveCheck = Long.MIN_VALUE;
    /** The crystal currently holding the LISTEN hint glow, −1 = none (§7.4). */
    private static int hintCrystal = -1;

    /** One cascade hop: the note lands at {@code target} when {@code dueTime} passes. */
    private record Hop(long dueTime, int sourceIdx, int targetIdx, int depth) {}

    private ResonanceFieldService() {}

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        StructurePendingRegistry.registerAsyncPlacer(ResonanceFieldBuilder.SITE_ID,
                ResonanceFieldBuilder::placeSite);
        if (BOOTSTRAPPED.compareAndSet(false, true)) {
            EclipseMod.LOGGER.info("ResonanceField registered (self-enqueues at stage {})",
                    REQUIRED_STAGE);
        }
    }

    /** Boot catch-up enqueue + the ExpansionBorderFx boot sweep (rebuild comes lazily). */
    @SubscribeEvent(priority = EventPriority.LOW)
    static void onServerStarted(ServerStartedEvent event) {
        maybeEnqueue(event.getServer());
        int swept = 0;
        for (ServerLevel level : event.getServer().getAllLevels()) {
            List<? extends Display.BlockDisplay> strays = level.getEntities(
                    EntityTypeTest.<Entity, Display.BlockDisplay>forClass(Display.BlockDisplay.class),
                    display -> display.getTags().contains(ResonanceFieldBuilder.CRYSTAL_TAG));
            strays.forEach(Entity::discard);
            swept += strays.size();
        }
        if (swept > 0) {
            EclipseMod.LOGGER.info(
                    "ResonanceField: swept {} persisted display(s) at boot (self-heal rebuilds)",
                    swept);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SESSION_DISPLAYS.clear();
        SPAWN_QUEUE.clear();
        CASCADE.clear();
        PULSE_RESTORES.clear();
        LAST_STRIKE.clear();
        playersNear = false;
        nextActiveCheck = Long.MIN_VALUE;
        hintCrystal = -1;
        ResonanceMelodyMachine.clearSession();
    }

    /**
     * Sweep doctrine (§3.1): a tagged display NOT spawned this session is a persisted
     * leftover or crash stray — discard; the 200-tick self-heal rebuilds it
     * byte-identically from the SavedData seeds.
     */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(ResonanceFieldBuilder.CRYSTAL_TAG)
                && !SESSION_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    /** Login resync — the {@code FxAnchors.onPlayerLoggedIn} pattern (§3.6). */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            ResonanceFieldData data = ResonanceFieldData.get(player.server.overworld());
            if (data.built()) {
                sendFieldTo(player, data);
            }
        }
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % ENQUEUE_POLL_TICKS == 0) {
            maybeEnqueue(server);
        }
        ServerLevel overworld = server.overworld();
        drainSpawnQueue(overworld);
        ResonanceFieldData data = ResonanceFieldData.get(overworld);
        if (!data.built()) {
            return;
        }
        long gameTime = overworld.getGameTime();
        // The one always-on check: COOLDOWN expiry (a single long comparison, §3.7).
        ResonanceMelodyMachine.tickCooldownAlways(overworld, data, gameTime);
        if (gameTime >= nextActiveCheck) {
            nextActiveCheck = gameTime + ACTIVE_CHECK_TICKS;
            playersNear = anyPlayerNear(overworld, data);
        }
        if (!playersNear) {
            return;
        }
        ResonanceMelodyMachine.tick(overworld, data, gameTime);
        drainCascade(overworld, data, gameTime);
        drainPulseRestores(overworld, data, gameTime);
        if (gameTime % SELF_HEAL_TICKS == 0L) {
            selfHeal(overworld, data);
        }
    }

    // ------------------------------------------------------------------ enqueue (§2.2)

    /** Idempotent stage-5 self-enqueue at the authored anchor (SkyLauncher pattern). */
    private static void maybeEnqueue(MinecraftServer server) {
        if (WorldStageService.stage(server, DiscProfile.OVERWORLD) < REQUIRED_STAGE) {
            return;
        }
        enqueueIfNeeded(server.overworld(), authoredAnchor());
    }

    /** The frozen anchor at its deterministic terrain height (§2.1). */
    public static BlockPos authoredAnchor() {
        return new BlockPos(ANCHOR_X,
                DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, ANCHOR_X, ANCHOR_Z),
                ANCHOR_Z);
    }

    /** Dedup'd enqueue — also the {@code /dev woah resonance spawn} entry point. */
    public static void enqueueIfNeeded(ServerLevel overworld, BlockPos anchor) {
        if (StructurePendingRegistry.wasPlaced(ResonanceFieldBuilder.SITE_ID)) {
            return;
        }
        for (PendingSite pending : StructurePendingRegistry.pending()) {
            if (pending.siteId().equals(ResonanceFieldBuilder.SITE_ID)) {
                return;
            }
        }
        StructurePendingRegistry.enqueue(new PendingSite(ResonanceFieldBuilder.SITE_ID,
                ResonanceFieldBuilder.SITE_ID, DiscProfile.OVERWORLD.name(), anchor,
                REQUIRED_STAGE, ResonanceFieldBuilder.FOOTPRINT, overworld.getGameTime()));
    }

    // ------------------------------------------------------------------ strike routing (§3.3)

    /** Attack (left click) on a crystal hitbox = strike; cancel = no damage path. */
    @SubscribeEvent
    static void onAttackEntity(AttackEntityEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || player.isSpectator()) {
            return;
        }
        int idx = hitboxIndex(event.getTarget());
        if (idx >= 0) {
            event.setCanceled(true);
            strike(player, idx);
        }
    }

    /** Use (right click) on a crystal = same strike (accessibility); on the altar = TEACH. */
    @SubscribeEvent
    static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getHand() != InteractionHand.MAIN_HAND
                || !(event.getEntity() instanceof ServerPlayer player)
                || player.isSpectator()) {
            return;
        }
        Entity target = event.getTarget();
        int idx = hitboxIndex(target);
        if (idx >= 0) {
            event.setCanceled(true);
            strike(player, idx);
        } else if (target.getTags().contains(ResonanceFieldBuilder.ALTAR_TAG)) {
            event.setCanceled(true);
            ResonanceFieldData data = ResonanceFieldData.get(player.server.overworld());
            if (data.built()) {
                ResonanceMelodyMachine.onAltarUse(player.serverLevel(), data, player);
            }
        }
    }

    /** Crystal index from the hitbox's {@code eclipse_resonance_idx_<n>} tag, or −1. */
    private static int hitboxIndex(Entity target) {
        if (!target.getTags().contains(ResonanceFieldBuilder.HITBOX_TAG)) {
            return -1;
        }
        for (String tag : target.getTags()) {
            if (tag.startsWith(ResonanceFieldBuilder.HITBOX_IDX_PREFIX)) {
                try {
                    return Integer.parseInt(
                            tag.substring(ResonanceFieldBuilder.HITBOX_IDX_PREFIX.length()));
                } catch (NumberFormatException ignored) {
                    return -1;
                }
            }
        }
        return -1;
    }

    /**
     * The free strike (§3.2 — plays in EVERY state): note layering + glitter cue +
     * glow pulse + neighbor cascade, THEN the puzzle input hook. Only the directly
     * struck crystal enters the melody (§7.4 — cascade echoes never mis-enter).
     */
    public static void strike(ServerPlayer player, int crystalIdx) {
        ServerLevel level = player.serverLevel();
        ResonanceFieldData data = ResonanceFieldData.get(player.server.overworld());
        if (!data.built() || crystalIdx < 0 || crystalIdx >= data.monoliths().size()) {
            return;
        }
        long gameTime = level.getGameTime();
        Long last = LAST_STRIKE.get(crystalIdx);
        if (last != null && gameTime - last < STRIKE_COOLDOWN_TICKS) {
            return;
        }
        LAST_STRIKE.put(crystalIdx, gameTime);
        ResonanceMelodyMachine.playCrystalNote(level, data, crystalIdx, 1.4F);
        // The tactile click only the striking player's action carries (§6.2).
        Vec3 top = ResonanceMelodyMachine.crystalTop(data, crystalIdx);
        level.playSound(null, top.x, top.y, top.z, SoundEvents.AMETHYST_CLUSTER_HIT,
                SoundSource.BLOCKS, 0.8F, 1.0F);
        FxPayloads.sendFxEvent(level, ResonanceCues.CUE_RESONANCE_STRIKE, top,
                data.monoliths().get(crystalIdx).toneIndex, 0.0F, 96.0D);
        pulseCrystal(level, data, crystalIdx);
        enqueueCascade(data, crystalIdx, gameTime);
        ResonanceMelodyMachine.onCrystalStrike(level, data, crystalIdx, player);
    }

    // ------------------------------------------------------------------ cascade (§3.2)

    /** Fills the hop queue: neighbors at depth 1, THEIR neighbors at depth 2, cap 32. */
    private static void enqueueCascade(ResonanceFieldData data, int originIdx, long gameTime) {
        Set<Integer> visited = new HashSet<>();
        visited.add(originIdx);
        List<Hop> wave = new ArrayList<>();
        for (int neighbor : data.monoliths().get(originIdx).neighbors) {
            if (visited.add(neighbor)) {
                wave.add(new Hop(gameTime + CASCADE_HOP_TICKS, originIdx, neighbor, 1));
            }
        }
        List<Hop> secondWave = new ArrayList<>();
        for (Hop hop : wave) {
            for (int neighbor : data.monoliths().get(hop.targetIdx()).neighbors) {
                if (visited.add(neighbor)) {
                    secondWave.add(new Hop(gameTime + CASCADE_HOP_TICKS * 2L, hop.targetIdx(),
                            neighbor, CASCADE_MAX_DEPTH));
                }
            }
        }
        for (Hop hop : wave) {
            if (CASCADE.size() >= CASCADE_QUEUE_CAP) {
                return;
            }
            CASCADE.add(hop);
        }
        for (Hop hop : secondWave) {
            if (CASCADE.size() >= CASCADE_QUEUE_CAP) {
                return;
            }
            CASCADE.add(hop);
        }
    }

    /** Executes due hops: quieter note at the target + traveling pulse cue + mini glow. */
    private static void drainCascade(ServerLevel level, ResonanceFieldData data, long gameTime) {
        while (!CASCADE.isEmpty() && CASCADE.peek().dueTime() <= gameTime) {
            Hop hop = CASCADE.poll();
            if (hop.targetIdx() >= data.monoliths().size()
                    || hop.sourceIdx() >= data.monoliths().size()) {
                continue;
            }
            // §6.2 cascade volume: 0.55 at hop 1, 0.55² ≈ 0.30 at hop 2.
            float volume = (float) Math.pow(0.55D, hop.depth());
            ResonanceMelodyMachine.playCrystalNote(level, data, hop.targetIdx(), volume);
            Vec3 source = ResonanceMelodyMachine.crystalTop(data, hop.sourceIdx());
            Vec3 target = ResonanceMelodyMachine.crystalTop(data, hop.targetIdx());
            // a = yaw toward the target (degrees, vanilla convention: forward for yaw φ
            // is (−sin φ, 0, cos φ) ⇒ φ = atan2(−dx, dz)), b = hop length — the row leg
            // rotates/scales the bead flight (CUE_WARDEN_VOLLEY_TELEGRAPH pattern).
            float yaw = (float) Math.toDegrees(
                    Math.atan2(-(target.x - source.x), target.z - source.z));
            float length = (float) source.distanceTo(target);
            FxPayloads.sendFxEvent(level, ResonanceCues.CUE_RESONANCE_PULSE, source, yaw, length,
                    96.0D);
            pulseCrystal(level, data, hop.targetIdx());
        }
    }

    // ------------------------------------------------------------------ brightness (§5.5)

    /**
     * One glow pulse on a crystal: its shell/core displays flash to
     * {@value #SHELL_PULSE_BLOCK}/15 and restore after {@value #PULSE_RESTORE_TICKS}
     * ticks — exactly 2 brightness roundtrips per event (the "≤ 3 per event" craft law).
     * The full-bright glow needle (15/15) stays untouched; the Photon flare from
     * {@code CUE_RESONANCE_STRIKE} carries the primary visibility (§5.5).
     */
    static void pulseCrystal(ServerLevel level, ResonanceFieldData data, int crystalIdx) {
        setShellBrightness(level, data, crystalIdx, SHELL_PULSE_BLOCK);
        PULSE_RESTORES.put(crystalIdx, level.getGameTime() + PULSE_RESTORE_TICKS);
    }

    private static void drainPulseRestores(ServerLevel level, ResonanceFieldData data,
            long gameTime) {
        if (PULSE_RESTORES.isEmpty()) {
            return;
        }
        List<Integer> done = new ArrayList<>(2);
        for (Map.Entry<Integer, Long> entry : PULSE_RESTORES.entrySet()) {
            if (entry.getValue() <= gameTime) {
                done.add(entry.getKey());
            }
        }
        for (int crystalIdx : done) {
            PULSE_RESTORES.remove(crystalIdx);
            setShellBrightness(level, data, crystalIdx,
                    crystalIdx == hintCrystal ? SHELL_HINT_BLOCK : SHELL_IDLE_BLOCK);
        }
    }

    /**
     * §7.4 LISTEN hint: the next expected crystal holds a subtle constant shell glow
     * ({@value #SHELL_HINT_BLOCK}/15). Config-gated ({@code resonance.hint_glow});
     * −1 clears. Brightness only — readable on reducedFx/photon-less clients too.
     */
    static void setHintCrystal(ServerLevel level, ResonanceFieldData data, int crystalIdx) {
        if (crystalIdx >= 0 && !EclipseConfig.resonanceHintGlow()) {
            crystalIdx = -1;
        }
        if (hintCrystal == crystalIdx) {
            return;
        }
        int previous = hintCrystal;
        hintCrystal = crystalIdx;
        if (previous >= 0 && !PULSE_RESTORES.containsKey(previous)) {
            setShellBrightness(level, data, previous, SHELL_IDLE_BLOCK);
        }
        if (crystalIdx >= 0 && !PULSE_RESTORES.containsKey(crystalIdx)) {
            setShellBrightness(level, data, crystalIdx, SHELL_HINT_BLOCK);
        }
    }

    /** One brightness roundtrip over a crystal's non-glow displays (§5.5). */
    private static void setShellBrightness(ServerLevel level, ResonanceFieldData data,
            int crystalIdx, int block) {
        if (crystalIdx < 0 || crystalIdx >= data.monoliths().size()) {
            return;
        }
        ResonanceFieldData.Monolith monolith = data.monoliths().get(crystalIdx);
        String idxTag = ResonanceFieldBuilder.CRYSTAL_IDX_PREFIX + crystalIdx;
        List<Entity> pieces = level.getEntities((Entity) null,
                new AABB(monolith.basePos).inflate(10.0D, monolith.height + 4.0D, 10.0D),
                entity -> entity instanceof Display.BlockDisplay
                        && entity.getTags().contains(idxTag)
                        && !entity.getTags().contains(ResonanceFieldBuilder.GLOW_TAG));
        for (Entity piece : pieces) {
            DisplayBrightnessFx.set((Display) piece, block, 15);
        }
    }

    // ------------------------------------------------------------------ spawn queue + self-heal

    /** Builder handoff: displays spawn at {@value #DISPLAY_SPAWNS_PER_TICK}/tick (§3.1). */
    static void enqueueDisplaySpawns(List<ResonanceFieldBuilder.PendingDisplay> jobs) {
        SPAWN_QUEUE.addAll(jobs);
    }

    /** Whitelists a display UUID for the {@link #onEntityJoin} sweep (spawn-time call). */
    static void markSessionDisplay(UUID uuid) {
        SESSION_DISPLAYS.add(uuid);
    }

    private static void drainSpawnQueue(ServerLevel overworld) {
        for (int i = 0; i < DISPLAY_SPAWNS_PER_TICK && !SPAWN_QUEUE.isEmpty(); i++) {
            ResonanceFieldBuilder.spawnDisplay(overworld, SPAWN_QUEUE.poll());
        }
    }

    /**
     * §3.3/§3.5 self-heal (200-tick cadence, players near, valley loaded): missing
     * displays → full deterministic rebuild from the seeds; missing interactions →
     * respawn individually (the SkyLauncher "a /kill'ed interaction would silently
     * brick the pad" doctrine).
     */
    private static void selfHeal(ServerLevel level, ResonanceFieldData data) {
        BlockPos anchor = data.anchor();
        if (anchor == null || !SPAWN_QUEUE.isEmpty() || !valleyLoaded(level, anchor)) {
            return;
        }
        AABB valley = new AABB(anchor).inflate(ResonanceFieldBuilder.VALLEY_RADIUS + 8.0D, 80.0D,
                ResonanceFieldBuilder.VALLEY_RADIUS + 8.0D);
        int displays = level.getEntities((Entity) null, valley,
                entity -> entity instanceof Display.BlockDisplay
                        && entity.getTags().contains(ResonanceFieldBuilder.CRYSTAL_TAG)).size();
        int expected = ResonanceFieldBuilder.expectedDisplayCount(data);
        if (displays != expected) {
            EclipseMod.LOGGER.info("ResonanceField self-heal: {}/{} displays — rebuilding",
                    displays, expected);
            ResonanceFieldBuilder.sweepFieldEntities(level, data);
            PULSE_RESTORES.clear();
            hintCrystal = -1;
            enqueueDisplaySpawns(ResonanceFieldBuilder.computeDisplaySpecs(data));
            ResonanceFieldBuilder.spawnInteractions(level, data);
            return;
        }
        // Displays intact — check the interactions individually.
        List<Entity> hitboxes = level.getEntities((Entity) null, valley,
                entity -> entity.getTags().contains(ResonanceFieldBuilder.HITBOX_TAG));
        Set<Integer> present = new HashSet<>();
        for (Entity hitbox : hitboxes) {
            for (String tag : hitbox.getTags()) {
                if (tag.startsWith(ResonanceFieldBuilder.HITBOX_IDX_PREFIX)) {
                    try {
                        present.add(Integer.parseInt(
                                tag.substring(ResonanceFieldBuilder.HITBOX_IDX_PREFIX.length())));
                    } catch (NumberFormatException ignored) {
                        // unparseable stray — the count check below respawns
                    }
                }
            }
        }
        for (int i = 0; i < data.monoliths().size(); i++) {
            if (!present.contains(i)) {
                ResonanceFieldData.Monolith monolith = data.monoliths().get(i);
                ResonanceFieldBuilder.spawnInteraction(level, monolith.basePos,
                        ResonanceFieldBuilder.hitboxWidth(monolith),
                        ResonanceFieldBuilder.hitboxHeight(monolith),
                        ResonanceFieldBuilder.HITBOX_TAG,
                        ResonanceFieldBuilder.HITBOX_IDX_PREFIX + i);
                EclipseMod.LOGGER.info("ResonanceField self-heal: respawned hitbox {}", i);
            }
        }
        BlockPos altar = data.altarPos();
        if (altar != null && level.getEntities((Entity) null, valley,
                entity -> entity.getTags().contains(ResonanceFieldBuilder.ALTAR_TAG)).isEmpty()) {
            ResonanceFieldBuilder.spawnInteraction(level, altar.above(), 2.6F, 3.2F,
                    ResonanceFieldBuilder.ALTAR_TAG, null);
            EclipseMod.LOGGER.info("ResonanceField self-heal: respawned altar hitbox");
        }
    }

    private static boolean valleyLoaded(ServerLevel level, BlockPos anchor) {
        int r = ResonanceFieldBuilder.VALLEY_RADIUS;
        return level.isLoaded(anchor)
                && level.isLoaded(anchor.offset(r, 0, r)) && level.isLoaded(anchor.offset(-r, 0, r))
                && level.isLoaded(anchor.offset(r, 0, -r))
                && level.isLoaded(anchor.offset(-r, 0, -r));
    }

    // ------------------------------------------------------------------ wire (§3.6)

    /** Broadcasts the field payload to the whole dimension (build/state-change/login law). */
    public static void broadcastField(ServerLevel level, ResonanceFieldData data) {
        S2CResonanceFieldPayload payload = buildPayload(level, data);
        if (payload != null) {
            PacketDistributor.sendToPlayersInDimension(level, payload);
        }
    }

    private static void sendFieldTo(ServerPlayer player, ResonanceFieldData data) {
        S2CResonanceFieldPayload payload = buildPayload(player.serverLevel(), data);
        if (payload != null) {
            PacketDistributor.sendToPlayer(player, payload);
        }
    }

    @Nullable
    private static S2CResonanceFieldPayload buildPayload(ServerLevel level,
            ResonanceFieldData data) {
        BlockPos anchor = data.anchor();
        BlockPos altar = data.altarPos();
        if (!data.built() || anchor == null || altar == null) {
            return null;
        }
        List<S2CResonanceFieldPayload.Crystal> crystals =
                new ArrayList<>(data.monoliths().size());
        for (ResonanceFieldData.Monolith monolith : data.monoliths()) {
            crystals.add(new S2CResonanceFieldPayload.Crystal(monolith.basePos, monolith.height,
                    monolith.toneIndex));
        }
        List<S2CResonanceFieldPayload.Edge> edges = new ArrayList<>(12);
        for (int[] edge : ResonanceFieldBuilder.edgeList(data.monoliths())) {
            edges.add(new S2CResonanceFieldPayload.Edge(edge[0], edge[1]));
        }
        int cooldownLeft = (int) Math.max(0L, data.cooldownUntil() - level.getGameTime());
        return new S2CResonanceFieldPayload(anchor, altar, crystals, edges, data.stateOrdinal(),
                cooldownLeft);
    }

    // ------------------------------------------------------------------ helpers

    static int crystalOfTone(ResonanceFieldData data, int toneIndex) {
        List<ResonanceFieldData.Monolith> monoliths = data.monoliths();
        for (int i = 0; i < monoliths.size(); i++) {
            if (monoliths.get(i).toneIndex == toneIndex) {
                return i;
            }
        }
        return -1;
    }

    private static boolean anyPlayerNear(ServerLevel level, ResonanceFieldData data) {
        BlockPos anchor = data.anchor();
        if (anchor == null) {
            return false;
        }
        Vec3 center = Vec3.atCenterOf(anchor);
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceTo(center) <= ACTIVE_RADIUS) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ dev support (§9)

    /** {@code /dev woah resonance status} server-side snapshot. */
    public static String devStatus(ServerLevel level) {
        ResonanceFieldData data = ResonanceFieldData.get(level.getServer().overworld());
        if (!data.built()) {
            boolean pending = StructurePendingRegistry.pending().stream()
                    .anyMatch(site -> site.siteId().equals(ResonanceFieldBuilder.SITE_ID));
            return "not built (pending=" + pending + ", stage="
                    + WorldStageService.stage(level.getServer(), DiscProfile.OVERWORLD)
                    + "/" + REQUIRED_STAGE + ")";
        }
        BlockPos anchor = data.anchor();
        AABB valley = new AABB(anchor).inflate(ResonanceFieldBuilder.VALLEY_RADIUS + 8.0D, 80.0D,
                ResonanceFieldBuilder.VALLEY_RADIUS + 8.0D);
        int displays = level.getEntities((Entity) null, valley,
                entity -> entity.getTags().contains(ResonanceFieldBuilder.CRYSTAL_TAG)).size();
        int hitboxes = level.getEntities((Entity) null, valley,
                entity -> entity.getTags().contains(ResonanceFieldBuilder.HITBOX_TAG)
                        || entity.getTags().contains(ResonanceFieldBuilder.ALTAR_TAG)).size();
        long cooldownLeft = Math.max(0L, data.cooldownUntil() - level.getGameTime());
        return "state=" + ResonanceMelodyMachine.state(data)
                + " progress=" + data.progressIndex() + "/" + data.melody().length
                + " fails=" + data.failCount()
                + " solves=" + data.solveCount()
                + " cooldownLeft=" + cooldownLeft + "t"
                + " displays=" + displays + "/" + ResonanceFieldBuilder.expectedDisplayCount(data)
                + " hitboxes=" + hitboxes + "/" + (data.monoliths().size() + 1)
                + " anchor=" + anchor.toShortString()
                + " queue=" + SPAWN_QUEUE.size();
    }

    /** {@code /dev woah resonance reset}: IDLE + no cooldown + full entity rebuild. */
    public static void devReset(ServerLevel level) {
        ResonanceFieldData data = ResonanceFieldData.get(level.getServer().overworld());
        if (!data.built()) {
            return;
        }
        data.setProgressIndex(0);
        data.setFailCount(0);
        data.setCooldownUntil(0L);
        data.setState(ResonanceMelodyMachine.State.IDLE.ordinal(), level.getGameTime());
        CASCADE.clear();
        PULSE_RESTORES.clear();
        hintCrystal = -1;
        ResonanceFieldBuilder.sweepFieldEntities(level, data);
        SPAWN_QUEUE.clear();
        enqueueDisplaySpawns(ResonanceFieldBuilder.computeDisplaySpecs(data));
        ResonanceFieldBuilder.spawnInteractions(level, data);
        broadcastField(level, data);
    }

    /** {@code /dev woah resonance melody new} hook: optional reroll + immediate TEACH. */
    public static void devTeach(ServerLevel level, boolean reroll) {
        ResonanceFieldData data = ResonanceFieldData.get(level.getServer().overworld());
        if (!data.built()) {
            return;
        }
        if (reroll) {
            data.rerollMelody(level.random.nextLong());
            data.setFailCount(0);
        }
        ResonanceMelodyMachine.beginTeach(level, data, level.getGameTime());
    }

    /** {@code /dev woah resonance solve} hook: forces the finale (FX/reward QA). */
    public static void devSolve(ServerLevel level) {
        ResonanceFieldData data = ResonanceFieldData.get(level.getServer().overworld());
        if (data.built()) {
            ResonanceMelodyMachine.forceFinale(level, data, level.getGameTime());
        }
    }
}
