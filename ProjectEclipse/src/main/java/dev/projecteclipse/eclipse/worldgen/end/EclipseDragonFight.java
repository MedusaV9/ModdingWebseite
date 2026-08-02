package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CopyOnWriteArrayList;

import javax.annotation.Nullable;

import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.boss.BossPayloads;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.goals.QuestApi;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.boss.enderdragon.EndCrystal;
import net.minecraft.world.entity.boss.enderdragon.EnderDragon;
import net.minecraft.world.entity.boss.enderdragon.phases.EnderDragonPhase;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityTravelToDimensionEvent;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Lightweight overworld controller for the real vanilla {@link EnderDragon}. It does
 * not instantiate the dimension-bound vanilla {@code EndDragonFight}: fight origin,
 * phase watchdog, crystal healing, boss bar and rewards are all managed here.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseDragonFight {
    private static final String DRAGON_MARKER = "eclipseEndDiscDragon";
    private static final int CRYSTAL_SCAN_TICKS = 10;
    private static final int SAVE_TICKS = 20;
    private static final int WATCHDOG_TICKS = 40;
    private static final int LANDING_RETRY_TICKS = 160;
    private static final int ENTITY_TICKET_TICKS = 100;
    private static final int DEATH_ANIMATION_TICKS = 200;
    private static final double BOSS_BAR_RANGE = 192.0D;

    /** P2/P4/analytics seam fired once after rewards and portal placement. */
    @FunctionalInterface
    public interface Listener {
        void onDragonVictory(MinecraftServer server, BlockPos center);
    }

    private static final CopyOnWriteArrayList<Listener> LISTENERS = new CopyOnWriteArrayList<>();

    // WAVE6 (F-106 B) B1/B2/B4: dragon-stage constants. Card keys ship via the WAVE6B
    // langdrop; the wisp cue id is re-derived on BOTH sides (FxCues frozen — the client
    // row registrar in veilfx/Wave6DragonFxRows derives the same id as its loop-row
    // logical id AND FxAnchors key, the SmallCueFxRows two-sided precedent).
    private static final String DRAGON_CARD_KEY = "entity.eclipse.dragon.card";
    private static final String DRAGON_CARD_SUB_KEY = "entity.eclipse.dragon.card.sub";
    private static final ResourceLocation CUE_CRYSTAL_BURST = FxCues.cue("wave6_crystal_burst");
    private static final ResourceLocation CUE_DRAGON_WISP = FxCues.cue("wave6_dragon_wisp");
    /** B2: broadcast range of the crystal-burst cue payload (spires stand disc-wide). */
    private static final double CRYSTAL_BEAT_RANGE = 160.0D;
    /** B2: old-vs-new scan match distance — a crystal that "moved" this far is dead. */
    private static final double CRYSTAL_MATCH_DIST_SQ = 4.0D * 4.0D;
    /** B3: shake radius around the perch touch-down. */
    private static final double PERCH_SHAKE_RANGE = 48.0D;
    /** B4: tick stagger between the three victory light pillars. */
    private static final int REQUIEM_PILLAR_STAGGER_TICKS = 20;

    @Nullable
    private static EnderDragon activeDragon;
    @Nullable
    private static ServerBossEvent bossBar;
    private static int lastCrystalCount = -1;
    /** Log-once guard for the F-023 dragon-day gate (per JVM; carries no world state). */
    private static boolean WARNED_EARLY_DRAGON;
    /**
     * WAVE6 (F-106 B) B1: transient intro-card latch. The card fires only on a genuinely
     * FRESH fight (no persisted dragon yet); a restart re-attach resets this latch but the
     * persisted {@code dragonId} keeps {@code freshFight} false, so no second card can fire.
     */
    private static boolean introCardSent;
    /** WAVE6 (F-106 B) B2: previous crystal-scan snapshot (positions of living crystals). */
    private static List<Vec3> lastCrystalPositions = List.of();
    /** WAVE6 (F-106 B) B3: perch flank latch — true while the dragon sits (1 beat per landing). */
    private static boolean perchLatched;
    /**
     * WAVE6 (F-106 B) B4: last crescendo pulse game time (transient; cadence ≤30t).
     * {@link Long#MIN_VALUE} is the "never pulsed" sentinel and MUST be guarded before
     * any {@code gameTime - lastCrescendoGameTime} subtraction — the difference
     * overflows strongly negative for every realistic game time (the Herald precedent
     * avoids this with a small int sentinel, {@code lastCrescendoTick = -1000}).
     */
    private static long lastCrescendoGameTime = Long.MIN_VALUE;
    /** WAVE6 (F-106 B) B4: victory light pillars still owed (staggered over the tick loop). */
    private static int requiemPillarsPending;
    private static long requiemNextPillarGameTime;

    private EclipseDragonFight() {}

    public static void addListener(Listener listener) {
        LISTENERS.addIfAbsent(listener);
    }

    /**
     * Starts or reattaches the fight. Safe after any restart and idempotent when the
     * tracked dragon is already active.
     */
    public static void begin(MinecraftServer server) {
        ServerLevel level = server.overworld();
        EndFightState state = EndFightState.get(server);
        if (!EclipseWorldgenState.get(server).endDiscMaterialized()
                || !state.materializationComplete()) {
            return;
        }
        if (state.dragonKilled()) {
            ensureVictoryBlocks(level);
            clearBossBar();
            // WAVE6 (F-106 B) B4: FxAnchors are transient (in-memory) — re-publish the
            // requiem wisp anchor over the egg on every start of an already-won save.
            publishRequiemAnchor(level);
            return;
        }
        if (!dragonDayReached(server, state)) {
            return;
        }
        // WAVE6 (F-106 B) B1: decided BEFORE any resolve/spawn writes state.dragonId —
        // only a fight that never had a dragon (nor a death in flight) gets the card.
        boolean freshFight = state.dragonId() == null && state.deathStartedGameTime() < 0L;

        loadCrystalChunks(level);
        if (EndConfig.current().crystalRespawn()) {
            EndSpires.respawnMissingCrystals(level, state, EndConfig.current().crystalCount());
        } else {
            EndSpires.livingCrystals(level, state);
        }

        EnderDragon dragon = resolveSavedDragon(level, state);
        if (dragon == null && state.deathStartedGameTime() >= 0L) {
            completeVictory(level, state);
            return;
        }
        if (dragon == null) {
            dragon = spawnDragon(level, state);
        } else {
            configureDragon(dragon);
            activeDragon = dragon;
            state.updateDragon(dragon.getUUID(), dragon.blockPosition(), dragon.getHealth());
        }
        ensureBossBar();
        lastCrystalCount = state.crystalsRemaining();
        // WAVE6 (F-106 B) B1: ONE intro card per fight (BossIntroOverlay/BossbarSkin are
        // public API — byte-untouched). Restart re-attach: freshFight is false (persisted
        // dragonId), so only the skip probe fires; the transient latch additionally
        // guards repeated begin() calls inside one session.
        if (freshFight && !introCardSent) {
            introCardSent = true;
            BossPayloads.sendIntro(level, Vec3.atCenterOf(center()),
                    DRAGON_CARD_KEY, DRAGON_CARD_SUB_KEY);
            EclipseMod.LOGGER.debug("[w6b-dragoncard] sent begin");
        } else {
            EclipseMod.LOGGER.debug("[w6b-dragoncard] sent skip-reattach");
        }
        EclipseMod.LOGGER.info("Eclipse dragon fight active: dragon {}, {} crystal(s)",
                dragon.getUUID(), state.crystalsRemaining());
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        begin(event.getServer());
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        EndFightState state = EndFightState.get(server);
        if (!EclipseWorldgenState.get(server).endDiscMaterialized()) {
            clearBossBar();
            return;
        }
        // WAVE6 (F-106 B) B4: the staggered requiem pillars fire AFTER dragonKilled flips,
        // so their drain runs before the killed early-return below.
        tickRequiemPillars(server.overworld());
        if (!state.materializationComplete() || state.dragonKilled()
                || !dragonDayReached(server, state)) {
            return;
        }
        tickFight(server.overworld(), state);
    }

    /**
     * F-023: the sky shard arrives on the authored day-12 slot, but the dragon only wakes
     * on {@code end.json dragonDay} (day 13, {@code days.json} "DAY 13 — THE DRAGON") —
     * before this the two beats fired within the same second, because the materialization
     * writer's completion started the fight directly. The gate only holds while no dragon
     * has ever been spawned, so an admin lowering the day mid-fight can never orphan a
     * live boss (and a resumed save reattaches to it whatever the clock says).
     */
    private static boolean dragonDayReached(MinecraftServer server, EndFightState state) {
        if (state.dragonId() != null || state.deathStartedGameTime() >= 0L) {
            return true;
        }
        int dragonDay = EndConfig.current().dragonDay();
        if (DayScheduler.getDay(server) >= dragonDay) {
            return true;
        }
        if (!WARNED_EARLY_DRAGON) {
            WARNED_EARLY_DRAGON = true;
            EclipseMod.LOGGER.info("End disc stands, but the dragon sleeps until day {} (day {} now)",
                    dragonDay, DayScheduler.getDay(server));
        }
        return false;
    }

    @SubscribeEvent
    public static void onDragonDamage(LivingDamageEvent.Pre event) {
        if (!(event.getEntity() instanceof EnderDragon dragon)
                || !isManaged(dragon)
                || !(dragon.level() instanceof ServerLevel level)) {
            return;
        }
        EndFightState state = EndFightState.get(level.getServer());
        if (!EclipseWorldgenState.get(level.getServer()).endDiscMaterialized()
                || state.crystalsRemaining() <= 0) {
            return;
        }
        // Crystals sustain the dragon at one health; destroying all of them unlocks the kill.
        float maximumDamage = Math.max(0.0F, dragon.getHealth() - 1.0F);
        event.setNewDamage(Math.min(event.getNewDamage(), maximumDamage));
    }

    @SubscribeEvent
    public static void onDragonDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof EnderDragon dragon)
                || !isManaged(dragon)
                || !(dragon.level() instanceof ServerLevel level)) {
            return;
        }
        EndFightState state = EndFightState.get(level.getServer());
        if (!EclipseWorldgenState.get(level.getServer()).endDiscMaterialized()) {
            return;
        }
        state.markDeathStarted(level.getGameTime());
        dragon.setFightOrigin(center());
        dragon.getPhaseManager().setPhase(EnderDragonPhase.DYING);
        if (bossBar != null) {
            bossBar.setProgress(0.0F);
            bossBar.removeAllPlayers();
        }
        EclipseMod.LOGGER.info("Eclipse dragon death animation started at fight origin {}", center());
    }

    /**
     * The lit basin uses real End portal blocks for the visual. Cancel their vanilla
     * overworld→End transition and redirect players to the sanctum spawn instead.
     */
    @SubscribeEvent
    public static void onDimensionTravel(EntityTravelToDimensionEvent event) {
        Entity entity = event.getEntity();
        if (!Level.END.equals(event.getDimension())
                || !(entity.level() instanceof ServerLevel source)
                || !Level.OVERWORLD.equals(source.dimension())
                || !EclipseWorldgenState.get(source.getServer()).endDiscMaterialized()
                || !EndFightState.get(source.getServer()).dragonKilled()
                || !insideExitPortal(entity.blockPosition())) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof ServerPlayer player) {
            BlockPos spawn = source.getSharedSpawnPos();
            player.teleportTo(source,
                    spawn.getX() + 0.5D, spawn.getY() + 0.1D, spawn.getZ() + 0.5D,
                    source.getSharedSpawnAngle(), 0.0F);
            player.fallDistance = 0.0F;
            player.setDeltaMovement(Vec3.ZERO);
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeDragon = null;
        lastCrystalCount = -1;
        clearBossBar();
        // WAVE6 (F-106 B): transient stage state (FxAnchors clears itself on server stop).
        introCardSent = false;
        lastCrystalPositions = List.of();
        perchLatched = false;
        lastCrescendoGameTime = Long.MIN_VALUE;
        requiemPillarsPending = 0;
        requiemNextPillarGameTime = 0L;
    }

    private static void tickFight(ServerLevel level, EndFightState state) {
        EnderDragon dragon = resolveLiveDragon(level, state);
        if (dragon == null) {
            if (state.deathStartedGameTime() >= 0L) {
                completeVictory(level, state);
            } else {
                begin(level.getServer());
            }
            return;
        }

        if (dragon.getHealth() <= 0.0F || dragon.dragonDeathTime > 0
                || state.deathStartedGameTime() >= 0L) {
            state.markDeathStarted(level.getGameTime());
            tickDeathSequence(level, state, dragon);
            return;
        }

        long gameTime = level.getGameTime();
        dragon.setFightOrigin(center());
        syncBossBar(level, dragon);
        // WAVE6 (F-106 B) B3: per-tick phase-flank sampling — the 40t watchdog cadence
        // would alias short sitting windows, the flank latch keeps it at 1 beat/landing.
        tickPerchBeat(level, dragon);
        // WAVE6 (F-106 B) B4: sub-10% heartbeat ladder (W5-A5 idiom, HP-staggered cadence).
        tickCrescendo(level, dragon, gameTime);

        if (gameTime % CRYSTAL_SCAN_TICKS == 0L) {
            List<EndCrystal> crystals = EndSpires.livingCrystals(level, state);
            for (EndCrystal crystal : crystals) {
                crystal.setBeamTarget(dragon.blockPosition());
            }
            if (!crystals.isEmpty() && dragon.getHealth() < dragon.getMaxHealth()) {
                // Vanilla heals from a nearby selected crystal; this controller-level heal
                // guarantees the authored pillar set remains meaningful across custom phases.
                dragon.heal(1.0F);
            }
            if (lastCrystalCount > 0 && crystals.isEmpty()) {
                level.getServer().getPlayerList().broadcastSystemMessage(
                        Component.translatable("announce.eclipse.end.crystals_destroyed"), false);
                dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
            }
            // WAVE6 (F-106 B) B2: the scan already diffs lastCrystalCount — on a drop,
            // locate the fallen crystal(s) via the before/after position snapshot and fire
            // the burst there. A restart starts from an EMPTY snapshot, so re-attach can
            // never replay a beat for crystals that died while the server was down.
            if (lastCrystalCount > 0 && crystals.size() < lastCrystalCount
                    && !lastCrystalPositions.isEmpty()) {
                fireCrystalBeats(level, crystals);
            }
            lastCrystalPositions = snapshotCrystalPositions(crystals);
            lastCrystalCount = crystals.size();
        }

        if (gameTime % WATCHDOG_TICKS == 0L) {
            watchdog(dragon, state.crystalsRemaining());
        }
        if (state.crystalsRemaining() == 0 && gameTime % LANDING_RETRY_TICKS == 0L) {
            // Landing retry: heals a dragon that drifted back into a flight phase
            // (HOLDING_PATTERN/STRAFE/...) without ever perching. It must NOT touch an
            // approach or landing already in progress — on the custom disc a landing
            // legitimately takes longer than one retry window, and re-forcing
            // LANDING_APPROACH restarts the descent (observed 2↔3 phase bouncing).
            var currentPhase = dragon.getPhaseManager().getCurrentPhase();
            var phase = currentPhase.getPhase();
            if (!currentPhase.isSitting()
                    && phase != EnderDragonPhase.LANDING_APPROACH
                    && phase != EnderDragonPhase.LANDING) {
                dragon.getPhaseManager().setPhase(EnderDragonPhase.LANDING_APPROACH);
            }
        }
        if (gameTime % ENTITY_TICKET_TICKS == 0L) {
            loadCrystalChunks(level);
            BudgetedBlockWriter.loadWithTicket(
                    level, dragon.blockPosition().getX() >> 4, dragon.blockPosition().getZ() >> 4);
        }
        if (gameTime % SAVE_TICKS == 0L) {
            state.updateDragon(dragon.getUUID(), dragon.blockPosition(), dragon.getHealth());
        }
    }

    private static void watchdog(EnderDragon dragon, int crystalsRemaining) {
        EndConfig.Snapshot config = EndConfig.current();
        double dx = dragon.getX() - config.centerX();
        double dz = dragon.getZ() - config.centerZ();
        double maxRadius = config.radius() + 72.0D;
        boolean outside = dx * dx + dz * dz > maxRadius * maxRadius
                || dragon.getY() < config.surfaceY() - 24
                || dragon.getY() > config.surfaceY() + 120;
        if (outside) {
            dragon.moveTo(
                    config.centerX() + 0.5D,
                    config.surfaceY() + 48.0D,
                    config.centerZ() + 0.5D,
                    dragon.getYRot(), dragon.getXRot());
            dragon.setDeltaMovement(Vec3.ZERO);
            dragon.getPhaseManager().setPhase(EnderDragonPhase.HOLDING_PATTERN);
            EclipseMod.LOGGER.warn("Eclipse dragon left fight bounds; returned to {}", center());
            return;
        }
        if (!config.simpleDragonAi() || crystalsRemaining <= 0) {
            return;
        }
        var phase = dragon.getPhaseManager().getCurrentPhase().getPhase();
        if (phase != EnderDragonPhase.HOLDING_PATTERN
                && phase != EnderDragonPhase.STRAFE_PLAYER) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.HOLDING_PATTERN);
        }
    }

    // ------------------------------------------------------------ WAVE6 (F-106 B) beats

    /** B2: transient position snapshot of the living crystals (scan-cadence sized). */
    private static List<Vec3> snapshotCrystalPositions(List<EndCrystal> crystals) {
        List<Vec3> positions = new ArrayList<>(crystals.size());
        for (EndCrystal crystal : crystals) {
            positions.add(crystal.position());
        }
        return List.copyOf(positions);
    }

    /**
     * B2 crystal-destruction beat: every OLD snapshot position without a survivor nearby
     * is where a crystal died this scan window — fire the {@code wave6_crystal_burst}
     * one-shot there (Photon garnish; the vanilla crystal explosion is the photon-less
     * baseline) plus a distant low-pitched glass sting to every bossbar viewer.
     */
    private static void fireCrystalBeats(ServerLevel level, List<EndCrystal> survivors) {
        for (Vec3 old : lastCrystalPositions) {
            boolean survived = false;
            for (EndCrystal crystal : survivors) {
                if (crystal.position().distanceToSqr(old) <= CRYSTAL_MATCH_DIST_SQ) {
                    survived = true;
                    break;
                }
            }
            if (survived) {
                continue;
            }
            FxPayloads.sendFxEvent(level, CUE_CRYSTAL_BURST, old, 0.0F, 0.0F, CRYSTAL_BEAT_RANGE);
            if (bossBar != null) {
                for (ServerPlayer viewer : List.copyOf(bossBar.getPlayers())) {
                    viewer.playNotifySound(SoundEvents.GLASS_BREAK, SoundSource.HOSTILE,
                            0.9F, 0.55F);
                }
            }
            EclipseMod.LOGGER.debug("[w6b-crystal] remaining={} at={}",
                    survivors.size(), BlockPos.containing(old).toShortString());
        }
    }

    /**
     * B3 perch/landing beat: flank into a sitting {@code EnderDragonPhase} (touch-down on
     * the perch) fires ONE ground shock ring (END_ROD + violet dust, server-side
     * particles) and a {@code S2CShakePayload} to players within
     * {@value #PERCH_SHAKE_RANGE} blocks. The latch releases when the dragon lifts off.
     */
    private static void tickPerchBeat(ServerLevel level, EnderDragon dragon) {
        boolean sitting = dragon.getPhaseManager().getCurrentPhase().isSitting();
        if (!sitting) {
            perchLatched = false;
            return;
        }
        if (perchLatched) {
            return;
        }
        perchLatched = true;
        Vec3 base = dragon.position();
        DustParticleOptions violet = new DustParticleOptions(new Vector3f(0.55F, 0.30F, 0.85F), 1.4F);
        for (int i = 0; i < 20; i++) {
            double angle = Math.PI * 2.0D * i / 20.0D;
            double cos = Math.cos(angle);
            double sin = Math.sin(angle);
            level.sendParticles(ParticleTypes.END_ROD,
                    base.x + cos * 4.0D, base.y + 0.3D, base.z + sin * 4.0D,
                    2, 0.15D, 0.1D, 0.15D, 0.01D);
            level.sendParticles(violet,
                    base.x + cos * 2.5D, base.y + 0.4D, base.z + sin * 2.5D,
                    2, 0.1D, 0.15D, 0.1D, 0.0D);
        }
        PacketDistributor.sendToPlayersNear(level, null, base.x, base.y, base.z,
                PERCH_SHAKE_RANGE, S2CShakePayload.shake(0.8F, 20));
        EclipseMod.LOGGER.debug("[w6b-perch] phase={}",
                dragon.getPhaseManager().getCurrentPhase().getPhase());
    }

    /**
     * B4 sub-10%-HP heartbeat crescendo (W5-A5 idiom, {@code HeraldEntity}
     * {@code tickHeartbeatCrescendo} precedent): every living, non-spectator player within
     * {@value #BOSS_BAR_RANGE} blocks of the fight center hears WARDEN_HEARTBEAT on a
     * cadence that falls with the boss — 30t → 20t → 12t, HP-staggered.
     */
    private static void tickCrescendo(ServerLevel level, EnderDragon dragon, long gameTime) {
        float fraction = dragon.getHealth() / dragon.getMaxHealth();
        int cadence = fraction > 0.10F ? -1 : fraction > 0.0666F ? 30 : fraction > 0.0333F ? 20 : 12;
        if (cadence < 0) {
            return;
        }
        // Sentinel-guard BEFORE the elapsed-tick subtraction: gameTime - Long.MIN_VALUE
        // overflows strongly negative, which silently swallowed every pulse. With the
        // guard, the first pulse fires immediately on entering the sub-10% zone.
        if (lastCrescendoGameTime != Long.MIN_VALUE
                && gameTime - lastCrescendoGameTime < cadence) {
            return;
        }
        lastCrescendoGameTime = gameTime;
        Vec3 center = Vec3.atCenterOf(center());
        for (ServerPlayer player : level.players()) {
            if (player.isAlive() && !player.isSpectator()
                    && player.position().distanceToSqr(center) <= BOSS_BAR_RANGE * BOSS_BAR_RANGE) {
                player.connection.send(new ClientboundSoundPacket(
                        BuiltInRegistries.SOUND_EVENT.wrapAsHolder(SoundEvents.WARDEN_HEARTBEAT),
                        SoundSource.HOSTILE, player.getX(), player.getY(), player.getZ(),
                        1.2F, 0.8F, level.getRandom().nextLong()));
            }
        }
        EclipseMod.LOGGER.debug("[w6b-crescendo] hp={} cadence={}",
                String.format(Locale.ROOT, "%.3f", fraction), cadence);
    }

    /** B4: the requiem wisp anchor floats just above the dragon egg (surface + 5 block). */
    private static void publishRequiemAnchor(ServerLevel level) {
        BlockPos center = center();
        int surface = EndDiscGeometry.surfaceYAt(center.getX(), center.getZ());
        Vec3 anchor = new Vec3(center.getX() + 0.5D, surface + 6.5D, center.getZ() + 0.5D);
        FxAnchors.set(CUE_DRAGON_WISP, level, anchor);
        EclipseMod.LOGGER.debug("[w6b-requiem] anchored={}", BlockPos.containing(anchor).toShortString());
    }

    /**
     * B4 victory requiem, pillar half: three staggered light pillars over the portal
     * center ({@value #REQUIEM_PILLAR_STAGGER_TICKS}t apart, one small triangle around the
     * egg). Server-side vanilla particles — the photon-less baseline of the requiem; the
     * {@code wave6_dragon_wisp} WINDOWED loop is the client-side Photon garnish.
     */
    private static void tickRequiemPillars(ServerLevel level) {
        if (requiemPillarsPending <= 0 || level.getGameTime() < requiemNextPillarGameTime) {
            return;
        }
        int index = 3 - requiemPillarsPending;
        requiemPillarsPending--;
        requiemNextPillarGameTime = level.getGameTime() + REQUIEM_PILLAR_STAGGER_TICKS;
        BlockPos center = center();
        int surface = EndDiscGeometry.surfaceYAt(center.getX(), center.getZ());
        double angle = Math.toRadians(90.0D + index * 120.0D);
        double x = center.getX() + 0.5D + Math.cos(angle) * 2.5D;
        double z = center.getZ() + 0.5D + Math.sin(angle) * 2.5D;
        for (int dy = 1; dy <= 16; dy++) {
            level.sendParticles(ParticleTypes.END_ROD, x, surface + dy, z,
                    3, 0.12D, 0.2D, 0.12D, 0.005D);
        }
        level.playSound(null, BlockPos.containing(x, surface + 1, z),
                SoundEvents.BEACON_ACTIVATE, SoundSource.HOSTILE, 1.2F, 0.75F + 0.1F * index);
    }

    private static void tickDeathSequence(
            ServerLevel level, EndFightState state, EnderDragon dragon) {
        clearBossBar();
        dragon.setFightOrigin(center());
        if (dragon.getPhaseManager().getCurrentPhase().getPhase() != EnderDragonPhase.DYING) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.DYING);
        }
        // Keep a broken non-End death path visually centered on the podium.
        if (dragon.position().distanceToSqr(Vec3.atCenterOf(center())) > 48.0D * 48.0D) {
            dragon.moveTo(
                    center().getX() + 0.5D,
                    center().getY() + 12.0D,
                    center().getZ() + 0.5D,
                    dragon.getYRot(), dragon.getXRot());
        }
        state.updateDragon(dragon.getUUID(), dragon.blockPosition(), 0.0F);
        long elapsed = level.getGameTime() - state.deathStartedGameTime();
        boolean timedOut = elapsed >= DEATH_ANIMATION_TICKS + 20L;
        if (timedOut && !dragon.isRemoved()) {
            // A non-End phase implementation can stall because no vanilla
            // EndDragonFight owns it. Never leave an immortal zero-health dragon behind.
            dragon.discard();
        }
        if (dragon.dragonDeathTime >= DEATH_ANIMATION_TICKS - 1
                || dragon.isRemoved()
                || timedOut) {
            completeVictory(level, state);
        }
    }

    private static void loadCrystalChunks(ServerLevel level) {
        for (BlockPos pos : EndSpires.crystalPositions(EndConfig.current().crystalCount())) {
            BudgetedBlockWriter.loadWithTicket(level, pos.getX() >> 4, pos.getZ() >> 4);
        }
    }

    private static EnderDragon spawnDragon(ServerLevel level, EndFightState state) {
        EndConfig.Snapshot config = EndConfig.current();
        EnderDragon dragon = EntityType.ENDER_DRAGON.create(level);
        if (dragon == null) {
            throw new IllegalStateException("Vanilla Ender Dragon entity type failed to instantiate");
        }
        dragon.moveTo(
                config.centerX() + 0.5D,
                config.surfaceY() + 48.0D,
                config.centerZ() + 0.5D,
                level.getRandom().nextFloat() * 360.0F,
                0.0F);
        configureDragon(dragon);
        float restored = state.dragonHealth() > 0.0F
                ? Math.min(state.dragonHealth(), config.dragonHealth())
                : config.dragonHealth();
        dragon.setHealth(restored);
        level.addFreshEntity(dragon);
        activeDragon = dragon;
        state.updateDragon(dragon.getUUID(), dragon.blockPosition(), dragon.getHealth());
        return dragon;
    }

    private static void configureDragon(EnderDragon dragon) {
        EndConfig.Snapshot config = EndConfig.current();
        AttributeInstance maxHealth = dragon.getAttribute(Attributes.MAX_HEALTH);
        if (maxHealth != null) {
            maxHealth.setBaseValue(config.dragonHealth());
        }
        if (dragon.getHealth() > config.dragonHealth()) {
            dragon.setHealth(config.dragonHealth());
        }
        dragon.setFightOrigin(center());
        dragon.setPersistenceRequired();
        dragon.getPersistentData().putBoolean(DRAGON_MARKER, true);
        if (dragon.getPhaseManager().getCurrentPhase().getPhase() == EnderDragonPhase.HOVERING) {
            dragon.getPhaseManager().setPhase(EnderDragonPhase.HOLDING_PATTERN);
        }
    }

    @Nullable
    private static EnderDragon resolveSavedDragon(ServerLevel level, EndFightState state) {
        if (state.dragonPos() != null) {
            BudgetedBlockWriter.loadWithTicket(
                    level, state.dragonPos().getX() >> 4, state.dragonPos().getZ() >> 4);
        }
        if (state.dragonId() != null) {
            Entity entity = level.getEntity(state.dragonId());
            if (entity instanceof EnderDragon dragon && isManaged(dragon) && !dragon.isRemoved()) {
                return dragon;
            }
        }
        EndConfig.Snapshot config = EndConfig.current();
        AABB bounds = new AABB(
                config.centerX() - config.radius() - 96,
                config.surfaceY() - 64,
                config.centerZ() - config.radius() - 96,
                config.centerX() + config.radius() + 96,
                config.surfaceY() + 160,
                config.centerZ() + config.radius() + 96);
        List<EnderDragon> found =
                level.getEntitiesOfClass(EnderDragon.class, bounds, EclipseDragonFight::isManaged);
        return found.isEmpty() ? null : found.get(0);
    }

    @Nullable
    private static EnderDragon resolveLiveDragon(ServerLevel level, EndFightState state) {
        if (activeDragon != null && !activeDragon.isRemoved()) {
            return activeDragon;
        }
        EnderDragon resolved = resolveSavedDragon(level, state);
        activeDragon = resolved;
        return resolved;
    }

    private static boolean isManaged(EnderDragon dragon) {
        return dragon.getPersistentData().getBoolean(DRAGON_MARKER);
    }

    private static void ensureBossBar() {
        if (bossBar != null) {
            return;
        }
        bossBar = new ServerBossEvent(
                Component.translatable("boss.eclipse.ender_dragon"),
                BossEvent.BossBarColor.PURPLE,
                BossEvent.BossBarOverlay.PROGRESS);
        bossBar.setDarkenScreen(true);
        bossBar.setPlayBossMusic(true);
        bossBar.setCreateWorldFog(true);
    }

    private static void syncBossBar(ServerLevel level, EnderDragon dragon) {
        ensureBossBar();
        if (bossBar == null) {
            return;
        }
        bossBar.setProgress(Mth.clamp(dragon.getHealth() / dragon.getMaxHealth(), 0.0F, 1.0F));
        Vec3 center = Vec3.atCenterOf(center());
        for (ServerPlayer player : level.players()) {
            boolean eligible = player.isAlive()
                    && !player.isSpectator()
                    && player.position().distanceToSqr(center) <= BOSS_BAR_RANGE * BOSS_BAR_RANGE;
            if (eligible) {
                // WAVE6 (F-106 B) B1: THEME_BOSS skin payload for every NEWLY added bar
                // viewer (the four house bosses' startSeenByPlayer idiom) — covers fight
                // start, walk-ins, relogs and restart re-attach alike.
                boolean fresh = !bossBar.getPlayers().contains(player);
                bossBar.addPlayer(player);
                if (fresh) {
                    PacketDistributor.sendToPlayer(player, new S2CBossbarStylePayload(
                            bossBar.getId(), S2CBossbarStylePayload.THEME_BOSS));
                }
            } else {
                bossBar.removePlayer(player);
            }
        }
        for (ServerPlayer player : List.copyOf(bossBar.getPlayers())) {
            if (player.level() != level) {
                bossBar.removePlayer(player);
            }
        }
    }

    private static void clearBossBar() {
        if (bossBar != null) {
            bossBar.removeAllPlayers();
            bossBar = null;
        }
    }

    private static void completeVictory(ServerLevel level, EndFightState state) {
        if (state.dragonKilled()) {
            return;
        }
        state.setDragonKilled();
        QuestApi.completeTeamBeat(level.getServer(), "dragon_defeated");
        activeDragon = null;
        clearBossBar();
        ensureVictoryBlocks(level);

        EndConfig.Snapshot config = EndConfig.current();
        Vec3 rewardPos = new Vec3(
                config.centerX() + 0.5D,
                EndDiscGeometry.surfaceYAt(config.centerX(), config.centerZ()) + 7.0D,
                config.centerZ() + 0.5D);
        if (config.victoryXp() > 0) {
            ExperienceOrb.award(level, rewardPos, config.victoryXp());
        }
        level.getServer().getPlayerList().broadcastSystemMessage(
                Component.translatable("announce.eclipse.end.victory"), false);
        level.playSound(null, center(), SoundEvents.END_PORTAL_SPAWN,
                SoundSource.HOSTILE, 2.0F, 0.75F);
        PacketDistributor.sendToPlayersInDimension(
                level, S2CShakePayload.shake(1.2F, 40));
        // WAVE6 (F-106 B) B4 victory requiem: arm the three staggered light pillars and
        // publish the wisp anchor (the WINDOWED loop window opens client-side only while
        // a player stands close; reducedFx skips it there).
        requiemPillarsPending = 3;
        requiemNextPillarGameTime = level.getGameTime() + 10L;
        publishRequiemAnchor(level);

        for (Listener listener : LISTENERS) {
            try {
                listener.onDragonVictory(level.getServer(), center());
            } catch (Exception e) {
                EclipseMod.LOGGER.error("End dragon victory listener failed", e);
            }
        }
        EclipseMod.LOGGER.info(
                "Eclipse dragon defeated: {} XP, egg and sanctum portal placed; "
                        + "AnalyticsApi is read-only, so analytics may subscribe through Listener",
                config.victoryXp());
    }

    private static void ensureVictoryBlocks(ServerLevel level) {
        BlockPos center = center();
        int surface = EndDiscGeometry.surfaceYAt(center.getX(), center.getZ());
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                int distanceSq = dx * dx + dz * dz;
                if (distanceSq > 0 && distanceSq <= 4) {
                    level.setBlock(
                            new BlockPos(center.getX() + dx, surface, center.getZ() + dz),
                            Blocks.END_PORTAL.defaultBlockState(),
                            Block.UPDATE_ALL);
                }
            }
        }
        level.setBlock(
                new BlockPos(center.getX(), surface + 5, center.getZ()),
                Blocks.DRAGON_EGG.defaultBlockState(),
                Block.UPDATE_ALL);
    }

    private static boolean insideExitPortal(BlockPos pos) {
        EndConfig.Snapshot config = EndConfig.current();
        int dx = pos.getX() - config.centerX();
        int dz = pos.getZ() - config.centerZ();
        int surface = EndDiscGeometry.surfaceYAt(config.centerX(), config.centerZ());
        return dx * dx + dz * dz <= 9
                && pos.getY() >= surface - 1
                && pos.getY() <= surface + 2;
    }

    private static BlockPos center() {
        EndConfig.Snapshot config = EndConfig.current();
        return new BlockPos(config.centerX(), config.surfaceY(), config.centerZ());
    }
}
