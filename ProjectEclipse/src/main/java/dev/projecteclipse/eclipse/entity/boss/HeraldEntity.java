package dev.projecteclipse.eclipse.entity.boss;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import dev.projecteclipse.eclipse.entity.UmbralStalkerEntity;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.Component;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The Herald of the Eclipse — day-7 boss ({@code docs/ideas/04_content.md} §2.1): a broken
 * godhead of black glass hovering over the sanctum dais. Summoned by depositing a Herald's
 * Lure at the altar after dusk (or {@code /eclipse boss herald summon}); never spawns
 * naturally.
 *
 * <p><b>Fight</b> (server-scripted, no vanilla goals — {@link #tick()} drives everything):
 * three phases derived from the health fraction, aligned to the PURPLE NOTCHED_6 bossbar
 * (breaks at exactly 2/3 and 1/3):</p>
 * <ul>
 *   <li><b>P1 Volley</b> (100–66%): hovers 8–12 above the dais on a slow strafe orbit;
 *       every {@value #P1_VOLLEY_CADENCE}t a telegraph (corona shards glow +
 *       BEACON_POWER_SELECT, 20t base) then 3 homing {@link HeraldShardProjectile}s;
 *       every {@value #STALKER_INTERVAL}t summons 2 Umbral Stalkers (cap 2+n).</li>
 *   <li><b>P2 Gaze</b> (66–33%): volley cadence slows to {@value #P2_VOLLEY_CADENCE}t;
 *       adds the guardian-style gaze — locks one player (ONLY they hear WARDEN_HEARTBEAT),
 *       {@value #GAZE_CHARGE_TICKS}t charge with a visible wisp beam, then 8 dmg +
 *       Darkness 5 s unless line of sight is broken behind a sanctum pillar at the moment
 *       of firing.</li>
 *   <li><b>P3 Collapse</b> (33–0%): descends to ~3 above the dais, pulls players
 *       {@value #PULL_PER_TICK}/t toward center, expanding damage rings every
 *       {@value #RING_INTERVAL}t (+{@value #RING_GROWTH}/t, jumpable, SOUL_FIRE_FLAME
 *       markers); corona shards detach as HP drops and crash down as {@code boss_slam}
 *       Quasar AoE bursts.</li>
 * </ul>
 *
 * <p><b>Scaling</b> (snapshotted at summon): HP = 300·(1+0.35·(n−1)) for n living players
 * within {@value #SCALING_RANGE} blocks; stalker cap 2+n; telegraph −2t per extra player
 * (floor 12).</p>
 *
 * <p><b>Arena lock</b>: everyone inside r={@value #ARENA_RADIUS} becomes a participant;
 * leaving the ring triggers the SoftBorder inward-impulse formula plus a reverse-portal
 * particle wall. If no player stays within {@value #RESET_RANGE} blocks for
 * {@value #RESET_TICKS}t, the Herald heals to full and despawns (summon item respawns it).
 * Drops: 1 herald core at the corpse + 3 umbral shards at EACH participant's feet; sets
 * {@link EclipseWorldState#setHeraldDefeated} and fires the boss-styled announce.</p>
 */
public class HeraldEntity extends Monster {
    public static final int CORONA_SHARDS = 8;
    public static final float BASE_MAX_HEALTH = 300.0F;
    public static final double ARENA_RADIUS = 15.0D;
    /** How high above the sanctum center the summon sequence drops the boss in. */
    public static final int SUMMON_HEIGHT = 12;

    private static final double SCALING_RANGE = 48.0D;
    private static final int P1_VOLLEY_CADENCE = 60;
    private static final int P2_VOLLEY_CADENCE = 90;
    private static final int TELEGRAPH_BASE_TICKS = 20;
    private static final int TELEGRAPH_FLOOR_TICKS = 12;
    private static final int VOLLEY_SHARDS = 3;
    private static final int STALKER_INTERVAL = 200;
    private static final int GAZE_INTERVAL = 140;
    private static final int GAZE_CHARGE_TICKS = 40;
    private static final float GAZE_DAMAGE = 8.0F;
    private static final int GAZE_DARKNESS_TICKS = 100; // 5 s
    private static final int RING_INTERVAL = 80;
    private static final double RING_GROWTH = 0.4D;
    private static final float RING_DAMAGE = 6.0F;
    private static final double RING_MAX_RADIUS = 16.0D;
    private static final double PULL_PER_TICK = 0.08D;
    private static final int CRASH_DELAY_TICKS = 30;
    private static final float CRASH_DAMAGE = 6.0F;
    private static final double CRASH_RADIUS = 2.5D;
    private static final int RESET_TICKS = 1200; // 60 s
    private static final double RESET_RANGE = 40.0D;
    // SoftBorder pushback formula (border/SoftBorder.impulseInward).
    private static final double MAX_IMPULSE = 1.2D;
    private static final double IMPULSE_BASE = 0.4D;
    private static final double IMPULSE_SCALE = 0.25D;
    private static final double IMPULSE_Y = 0.3D;

    /** Current phase 1..3 (synced; drives model animation speed + shard tilt). */
    private static final EntityDataAccessor<Integer> DATA_PHASE =
            SynchedEntityData.defineId(HeraldEntity.class, EntityDataSerializers.INT);
    /** True while a volley is winding up (shards glow emissive). */
    private static final EntityDataAccessor<Boolean> DATA_TELEGRAPH =
            SynchedEntityData.defineId(HeraldEntity.class, EntityDataSerializers.BOOLEAN);
    /** Corona shards still attached to the ring (P3 detaches them as HP drops). */
    private static final EntityDataAccessor<Integer> DATA_SHARDS_LEFT =
            SynchedEntityData.defineId(HeraldEntity.class, EntityDataSerializers.INT);

    /** One expanding P3 damage ring; each player is hurt at most once per ring. */
    private static final class DamageRing {
        double radius = 0.5D;
        final Set<UUID> hit = new HashSet<>();
    }

    /** A detached corona shard falling toward its crash point (boss_slam AoE). */
    private static final class ShardCrash {
        final Vec3 pos;
        int ticksLeft = CRASH_DELAY_TICKS;

        ShardCrash(Vec3 pos) {
            this.pos = pos;
        }
    }

    private final ServerBossEvent bossEvent = new ServerBossEvent(
            Component.translatable("entity.eclipse.herald.bossbar"),
            BossEvent.BossBarColor.PURPLE, BossEvent.BossBarOverlay.NOTCHED_6);

    // --- server fight state (arena geometry + participants persisted in NBT) ---
    @Nullable
    private Vec3 arenaCenter;
    private int groundY;
    private int scaledPlayers = 1;
    private final Set<UUID> participants = new HashSet<>();

    private float orbitAngle;
    private int volleyTimer = P1_VOLLEY_CADENCE;
    private int telegraphTimer = -1;
    private int stalkerTimer = STALKER_INTERVAL;
    private int gazeTimer = GAZE_INTERVAL;
    private int gazeChargeTimer = -1;
    @Nullable
    private UUID gazeTargetId;
    private int ringTimer = RING_INTERVAL / 2;
    private final List<DamageRing> rings = new ArrayList<>();
    private final List<ShardCrash> crashes = new ArrayList<>();
    private int noPlayerTicks;
    private int lastPhase = 1;

    // Client-side smooth animation clock: advances at the phase speed (x2 in P3) with an
    // eased ramp so the ring spin / bobs never snap on a phase change.
    private float animAge;
    private float animAgePrev;
    private float animSpeed = 1.0F;
    private float shardTilt;
    private float shardTiltPrev;

    public HeraldEntity(EntityType<? extends HeraldEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
        this.xpReward = 50;
    }

    // --- summoning ---

    /**
     * Spawns the Herald {@value #SUMMON_HEIGHT} blocks above the given altar with the full
     * arrival sequence (beam FX + global sound) and snapshots the player-count scaling.
     * {@code groundY} is the dais/arena floor the hover heights and P3 rings measure from.
     */
    public static HeraldEntity summon(ServerLevel level, BlockPos altarPos, int groundY) {
        HeraldEntity herald = EclipseEntities.HERALD.get().create(level);
        if (herald == null) {
            throw new IllegalStateException("Herald entity type failed to instantiate");
        }
        double x = altarPos.getX() + 0.5D;
        double z = altarPos.getZ() + 0.5D;
        herald.moveTo(x, altarPos.getY() + SUMMON_HEIGHT, z, level.getRandom().nextFloat() * 360.0F, 0.0F);
        herald.initFight(level, new Vec3(x, groundY, z), groundY);
        level.addFreshEntity(herald);
        // Arrival: altar beam + end-portal boom + a soul-flame burst around the spawn point.
        PacketDistributor.sendToPlayersNear(level, null, x, altarPos.getY(), z, 96.0D,
                new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, Vec3.atCenterOf(altarPos)));
        level.playSound(null, altarPos, SoundEvents.END_PORTAL_SPAWN, SoundSource.HOSTILE, 1.0F, 0.6F);
        level.playSound(null, altarPos, EclipseSounds.BOSS_HERALD_AMBIENT.get(), SoundSource.HOSTILE, 1.2F, 0.8F);
        level.sendParticles(ParticleTypes.SOUL_FIRE_FLAME, x, herald.getY(), z, 60, 1.2D, 1.2D, 1.2D, 0.05D);
        EclipseMod.LOGGER.info("Herald summoned at ({}, {}, {}) — scaled for {} player(s): {} HP; bossbar {} created",
                x, herald.getY(), z, herald.scaledPlayers, herald.getMaxHealth(), herald.bossEvent.getId());
        return herald;
    }

    /** Pins the arena and applies the summon-time player-count scaling (spec §2.1). */
    private void initFight(ServerLevel level, Vec3 center, int ground) {
        this.arenaCenter = center;
        this.groundY = ground;
        long nearby = level.players().stream()
                .filter(player -> !player.isSpectator() && player.isAlive())
                .filter(player -> player.position().distanceTo(center) <= SCALING_RANGE)
                .count();
        this.scaledPlayers = (int) Math.max(1L, nearby);
        double maxHealth = BASE_MAX_HEALTH * (1.0D + 0.35D * (this.scaledPlayers - 1));
        this.getAttribute(Attributes.MAX_HEALTH).setBaseValue(maxHealth);
        this.setHealth((float) maxHealth);
    }

    /** Lazy arena init for plain {@code /summon eclipse:herald} (acceptance path). */
    private void ensureFightInitialized(ServerLevel level) {
        if (this.arenaCenter != null) {
            return;
        }
        BlockPos surface = level.getHeightmapPos(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, this.blockPosition());
        int ground = Math.min(surface.getY(), this.blockPosition().getY());
        initFight(level, new Vec3(this.getX(), ground, this.getZ()), ground);
        EclipseMod.LOGGER.info("Herald arena auto-pinned at {} (ground {}, {} player(s), {} HP); bossbar {} created",
                this.arenaCenter, ground, this.scaledPlayers, this.getMaxHealth(), this.bossEvent.getId());
    }

    // --- synced state accessors ---

    public int getPhase() {
        return this.entityData.get(DATA_PHASE);
    }

    private void setPhase(int phase) {
        this.entityData.set(DATA_PHASE, Mth.clamp(phase, 1, 3));
    }

    public boolean isTelegraphing() {
        return this.entityData.get(DATA_TELEGRAPH);
    }

    private void setTelegraphing(boolean telegraphing) {
        this.entityData.set(DATA_TELEGRAPH, telegraphing);
    }

    public int getShardsLeft() {
        return this.entityData.get(DATA_SHARDS_LEFT);
    }

    private void setShardsLeft(int shardsLeft) {
        this.entityData.set(DATA_SHARDS_LEFT, Mth.clamp(shardsLeft, 0, CORONA_SHARDS));
    }

    // --- ticking ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            tickClientAnim();
        } else if (this.isAlive() && this.level() instanceof ServerLevel serverLevel) {
            ensureFightInitialized(serverLevel);
            tickFight(serverLevel);
        }
    }

    private void tickFight(ServerLevel level) {
        this.bossEvent.setProgress(this.getHealth() / this.getMaxHealth());
        updatePhase(level);
        updateParticipants(level);
        if (tickReset(level)) {
            return;
        }
        tickMovement();
        tickArenaLock(level);
        int phase = getPhase();
        if (phase < 3) {
            tickVolley(level, phase);
        }
        if (phase == 1) {
            tickStalkerSummons(level);
        }
        if (phase == 2) {
            tickGaze(level);
        }
        if (phase == 3) {
            tickCollapse(level);
        }
    }

    /** Phase = health fraction vs the NOTCHED_6 bar: breaks at exactly 2/3 and 1/3. */
    private void updatePhase(ServerLevel level) {
        float fraction = this.getHealth() / this.getMaxHealth();
        int phase = fraction > 2.0F / 3.0F ? 1 : fraction > 1.0F / 3.0F ? 2 : 3;
        if (phase == this.lastPhase) {
            return;
        }
        EclipseMod.LOGGER.info("Herald phase {} -> {} at {}/{} HP", this.lastPhase, phase,
                String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()),
                String.format(java.util.Locale.ROOT, "%.1f", this.getMaxHealth()));
        this.lastPhase = phase;
        setPhase(phase);
        setTelegraphing(false);
        this.telegraphTimer = -1;
        this.gazeChargeTimer = -1;
        this.gazeTargetId = null;
        level.playSound(null, this.blockPosition(), SoundEvents.WITHER_SPAWN, SoundSource.HOSTILE,
                1.0F, phase == 2 ? 1.2F : 0.7F);
        if (phase == 3) {
            // Collapse opener: slam FX at the boss as it starts its descent.
            PacketDistributor.sendToPlayersNear(level, null, this.getX(), this.getY(), this.getZ(), 96.0D,
                    new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, this.position()));
            this.ringTimer = RING_INTERVAL / 2;
        }
    }

    /** Everyone entering the r=15 ring joins the fight (and stays a participant for drops). */
    private void updateParticipants(ServerLevel level) {
        if (this.arenaCenter == null) {
            return;
        }
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && horizontalDistance(player.position()) <= ARENA_RADIUS
                    && this.participants.add(player.getUUID())) {
                EclipseMod.LOGGER.info("Herald fight: {} entered the arena ({} participant(s))",
                        player.getScoreboardName(), this.participants.size());
            }
        }
    }

    /** No players within 40 blocks for 60 s: heal to full and despawn (lure is re-craftable). */
    private boolean tickReset(ServerLevel level) {
        boolean anyoneNear = level.players().stream().anyMatch(player ->
                !player.isSpectator() && player.isAlive()
                        && player.position().distanceTo(this.position()) <= RESET_RANGE);
        if (anyoneNear) {
            this.noPlayerTicks = 0;
            return false;
        }
        if (++this.noPlayerTicks < RESET_TICKS) {
            return false;
        }
        EclipseMod.LOGGER.info("Herald reset: no players within {} blocks for {} ticks — healing and despawning",
                RESET_RANGE, RESET_TICKS);
        this.setHealth(this.getMaxHealth());
        this.discard();
        return true;
    }

    /** Gravity-free hover script: P1 wide strafe orbit 8–12 up, P2 tighter at 9, P3 sunk to 3. */
    private void tickMovement() {
        if (this.arenaCenter == null) {
            return;
        }
        int phase = getPhase();
        Vec3 desired;
        if (phase == 1) {
            this.orbitAngle += 0.012F;
            double hover = 10.0D + Math.sin(this.tickCount * 0.02D) * 2.0D; // 8..12
            desired = new Vec3(this.arenaCenter.x + Math.cos(this.orbitAngle) * 6.0D,
                    this.groundY + hover,
                    this.arenaCenter.z + Math.sin(this.orbitAngle) * 6.0D);
        } else if (phase == 2) {
            this.orbitAngle += 0.016F;
            desired = new Vec3(this.arenaCenter.x + Math.cos(this.orbitAngle) * 4.0D,
                    this.groundY + 9.0D,
                    this.arenaCenter.z + Math.sin(this.orbitAngle) * 4.0D);
        } else {
            desired = new Vec3(this.arenaCenter.x, this.groundY + 3.0D, this.arenaCenter.z);
        }
        Vec3 toDesired = desired.subtract(this.position()).scale(0.08D);
        if (toDesired.length() > 0.5D) {
            toDesired = toDesired.normalize().scale(0.5D);
        }
        this.setDeltaMovement(toDesired);
        faceCurrentFocus();
    }

    /** Faces the gaze target while charging, else the nearest participant. */
    private void faceCurrentFocus() {
        LivingEntity focus = null;
        if (this.gazeChargeTimer >= 0 && this.level() instanceof ServerLevel serverLevel
                && this.gazeTargetId != null
                && serverLevel.getEntity(this.gazeTargetId) instanceof LivingEntity gazeTarget) {
            focus = gazeTarget;
        } else {
            focus = nearestParticipant();
        }
        if (focus != null) {
            faceTowards(focus.position());
        }
    }

    /** Inward impulse (SoftBorder formula) + reverse-portal particle wall on the r=15 ring. */
    private void tickArenaLock(ServerLevel level) {
        if (this.arenaCenter == null) {
            return;
        }
        for (ServerPlayer player : livingParticipants(level)) {
            double dist = horizontalDistance(player.position());
            if (dist > ARENA_RADIUS && dist < ARENA_RADIUS + 12.0D) {
                double dx = player.getX() - this.arenaCenter.x;
                double dz = player.getZ() - this.arenaCenter.z;
                double strength = Math.min(MAX_IMPULSE, IMPULSE_SCALE * (dist - ARENA_RADIUS) + IMPULSE_BASE);
                double inv = 1.0D / dist;
                player.setDeltaMovement(new Vec3(-dx * inv * strength, IMPULSE_Y, -dz * inv * strength));
                player.hurtMarked = true; // sync the velocity to the client (SoftBorder pattern)
                if (this.tickCount % 20 == 0) {
                    player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.HOSTILE, 0.8F, 0.5F);
                }
            }
            // Particle wall: the arc segment facing each nearby participant.
            if (this.tickCount % 8 == 0 && dist > ARENA_RADIUS - 6.0D) {
                double angle = Math.atan2(player.getZ() - this.arenaCenter.z, player.getX() - this.arenaCenter.x);
                for (int i = -2; i <= 2; i++) {
                    double a = angle + i * 0.12D;
                    level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                            this.arenaCenter.x + Math.cos(a) * ARENA_RADIUS,
                            this.groundY + 0.5D + this.random.nextDouble() * 3.5D,
                            this.arenaCenter.z + Math.sin(a) * ARENA_RADIUS,
                            1, 0.05D, 0.4D, 0.05D, 0.0D);
                }
            }
        }
    }

    // --- P1/P2 volley ---

    private void tickVolley(ServerLevel level, int phase) {
        if (this.telegraphTimer < 0) {
            if (--this.volleyTimer > 0) {
                return;
            }
            // Telegraph: shards glow (synced flag -> emissive pass) + audible tell.
            this.telegraphTimer = Math.max(TELEGRAPH_FLOOR_TICKS,
                    TELEGRAPH_BASE_TICKS - 2 * (this.scaledPlayers - 1));
            setTelegraphing(true);
            level.playSound(null, this.blockPosition(), SoundEvents.BEACON_POWER_SELECT,
                    SoundSource.HOSTILE, 1.2F, 1.3F);
            level.playSound(null, this.blockPosition(), EclipseSounds.BOSS_HERALD_TELEGRAPH.get(),
                    SoundSource.HOSTILE, 1.0F, 1.0F);
            return;
        }
        if (--this.telegraphTimer >= 0) {
            return;
        }
        setTelegraphing(false);
        this.volleyTimer = phase == 1 ? P1_VOLLEY_CADENCE : P2_VOLLEY_CADENCE;
        List<ServerPlayer> targets = livingParticipants(level);
        if (targets.isEmpty()) {
            EclipseMod.LOGGER.info("Herald volley fizzled: no living participants in the arena");
            return;
        }
        Collections.shuffle(targets, new java.util.Random(this.random.nextLong()));
        Vec3 eye = eyePos();
        for (int i = 0; i < VOLLEY_SHARDS; i++) {
            ServerPlayer target = targets.get(i % targets.size());
            Vec3 toTarget = target.getEyePosition().subtract(eye).normalize();
            // Spawn outside the 2.2-wide hitbox so the shard never clips its owner.
            Vec3 from = eye.add(toTarget.scale(2.0D));
            level.addFreshEntity(new HeraldShardProjectile(level, this, target, from));
        }
        level.playSound(null, this.blockPosition(), SoundEvents.SHULKER_SHOOT, SoundSource.HOSTILE, 1.0F, 0.7F);
        EclipseMod.LOGGER.info("Herald volley: fired {} homing shard(s) at {} target(s)",
                VOLLEY_SHARDS, Math.min(VOLLEY_SHARDS, targets.size()));
    }

    // --- P1 stalker summons ---

    private void tickStalkerSummons(ServerLevel level) {
        if (--this.stalkerTimer > 0 || this.arenaCenter == null) {
            return;
        }
        this.stalkerTimer = STALKER_INTERVAL;
        int cap = 2 + this.scaledPlayers;
        List<UmbralStalkerEntity> existing = level.getEntitiesOfClass(UmbralStalkerEntity.class,
                this.getBoundingBox().inflate(48.0D));
        int room = cap - existing.size();
        if (room <= 0) {
            return;
        }
        int spawned = 0;
        for (int i = 0; i < Math.min(2, room); i++) {
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double radius = ARENA_RADIUS - 2.0D;
            BlockPos edge = BlockPos.containing(this.arenaCenter.x + Math.cos(angle) * radius,
                    this.groundY + 1, this.arenaCenter.z + Math.sin(angle) * radius);
            UmbralStalkerEntity stalker = EclipseEntities.UMBRAL_STALKER.get().create(level);
            if (stalker == null) {
                continue;
            }
            stalker.moveTo(edge.getX() + 0.5D, edge.getY(), edge.getZ() + 0.5D,
                    this.random.nextFloat() * 360.0F, 0.0F);
            if (level.addFreshEntity(stalker)) {
                level.sendParticles(ParticleTypes.SOUL, stalker.getX(), stalker.getY() + 0.6D,
                        stalker.getZ(), 12, 0.4D, 0.3D, 0.4D, 0.02D);
                spawned++;
            }
        }
        if (spawned > 0) {
            level.playSound(null, this.blockPosition(), SoundEvents.WOLF_GROWL, SoundSource.HOSTILE, 1.0F, 0.5F);
            EclipseMod.LOGGER.info("Herald summoned {} umbral stalker(s) (cap {}, {} already up)",
                    spawned, cap, existing.size());
        }
    }

    // --- P2 gaze ---

    private void tickGaze(ServerLevel level) {
        if (this.gazeChargeTimer < 0) {
            if (--this.gazeTimer > 0) {
                return;
            }
            List<ServerPlayer> targets = livingParticipants(level);
            if (targets.isEmpty()) {
                this.gazeTimer = 40;
                return;
            }
            ServerPlayer target = targets.get(this.random.nextInt(targets.size()));
            this.gazeTargetId = target.getUUID();
            this.gazeChargeTimer = GAZE_CHARGE_TICKS;
            this.gazeTimer = GAZE_INTERVAL;
            sendPrivateHeartbeat(target);
            EclipseMod.LOGGER.info("Herald gaze locked onto {} ({}t charge)",
                    target.getScoreboardName(), GAZE_CHARGE_TICKS);
            return;
        }
        ServerPlayer target = this.gazeTargetId != null
                ? level.getServer().getPlayerList().getPlayer(this.gazeTargetId) : null;
        if (target == null || !target.isAlive() || target.isSpectator()
                || target.level() != level
                || target.position().distanceTo(this.position()) > ARENA_RADIUS * 2.0D) {
            abortGaze("target lost");
            return;
        }
        // Only the locked player hears the heartbeat (spec: private cue).
        if (this.gazeChargeTimer % 10 == 0) {
            sendPrivateHeartbeat(target);
        }
        // Visible wisp beam: end-rod motes sampled along the eye->target line for everyone.
        if (this.gazeChargeTimer % 2 == 0) {
            Vec3 eye = eyePos();
            Vec3 to = target.getEyePosition().subtract(eye);
            int steps = Mth.clamp((int) (to.length() * 2.0D), 4, 40);
            for (int i = 0; i <= steps; i++) {
                Vec3 point = eye.add(to.scale(i / (double) steps));
                level.sendParticles(ParticleTypes.END_ROD, point.x, point.y, point.z,
                        1, 0.02D, 0.02D, 0.02D, 0.0D);
            }
        }
        if (--this.gazeChargeTimer >= 0) {
            return;
        }
        // Fire moment: LOS decides — a pillar between eye and player is mechanical cover.
        boolean losBroken = isLineOfSightBroken(level, target);
        if (losBroken) {
            level.playSound(null, target.blockPosition(), SoundEvents.SCULK_CLICKING,
                    SoundSource.HOSTILE, 1.0F, 0.6F);
            EclipseMod.LOGGER.info("Herald gaze on {} BROKEN by cover — no damage",
                    target.getScoreboardName());
        } else {
            target.hurt(this.damageSources().mobAttack(this), GAZE_DAMAGE);
            target.addEffect(new MobEffectInstance(MobEffects.DARKNESS, GAZE_DARKNESS_TICKS), this);
            level.playSound(null, target.blockPosition(), SoundEvents.WARDEN_SONIC_BOOM,
                    SoundSource.HOSTILE, 0.6F, 1.4F);
            PacketDistributor.sendToPlayersNear(level, null, target.getX(), target.getY(), target.getZ(),
                    64.0D, new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, target.position()));
            EclipseMod.LOGGER.info("Herald gaze HIT {} for {} + darkness {}t",
                    target.getScoreboardName(), GAZE_DAMAGE, GAZE_DARKNESS_TICKS);
        }
        this.gazeTargetId = null;
        this.gazeChargeTimer = -1;
    }

    private void abortGaze(String reason) {
        EclipseMod.LOGGER.info("Herald gaze aborted: {}", reason);
        this.gazeTargetId = null;
        this.gazeChargeTimer = -1;
    }

    /** WARDEN_HEARTBEAT audible ONLY to the locked player (sound packet straight to them). */
    private void sendPrivateHeartbeat(ServerPlayer target) {
        target.connection.send(new ClientboundSoundPacket(
                net.minecraft.core.registries.BuiltInRegistries.SOUND_EVENT
                        .wrapAsHolder(SoundEvents.WARDEN_HEARTBEAT),
                SoundSource.HOSTILE, target.getX(), target.getY(), target.getZ(),
                1.2F, 0.8F, this.random.nextLong()));
    }

    /** True when a block (sanctum pillar) interrupts the eye->player line at fire time. */
    private boolean isLineOfSightBroken(ServerLevel level, ServerPlayer target) {
        HitResult clip = level.clip(new ClipContext(eyePos(), target.getEyePosition(),
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, this));
        return clip.getType() != HitResult.Type.MISS;
    }

    // --- P3 collapse ---

    private void tickCollapse(ServerLevel level) {
        if (this.arenaCenter == null) {
            return;
        }
        // Constant pull toward the center (jump/sprint outward to fight it).
        for (ServerPlayer player : livingParticipants(level)) {
            double dx = this.arenaCenter.x - player.getX();
            double dz = this.arenaCenter.z - player.getZ();
            double dist = Math.sqrt(dx * dx + dz * dz);
            if (dist > 1.5D) {
                player.setDeltaMovement(player.getDeltaMovement()
                        .add(dx / dist * PULL_PER_TICK, 0.0D, dz / dist * PULL_PER_TICK));
                player.hurtMarked = true;
            }
        }
        tickDamageRings(level);
        tickShardDetach(level);
        tickShardCrashes(level);
    }

    private void tickDamageRings(ServerLevel level) {
        if (--this.ringTimer <= 0) {
            this.ringTimer = RING_INTERVAL;
            this.rings.add(new DamageRing());
            level.playSound(null, BlockPos.containing(this.arenaCenter), SoundEvents.SOUL_ESCAPE.value(),
                    SoundSource.HOSTILE, 2.0F, 0.5F);
            EclipseMod.LOGGER.info("Herald collapse ring spawned (expanding {}/t)", RING_GROWTH);
        }
        for (java.util.Iterator<DamageRing> iterator = this.rings.iterator(); iterator.hasNext();) {
            DamageRing ring = iterator.next();
            ring.radius += RING_GROWTH;
            if (ring.radius > RING_MAX_RADIUS) {
                iterator.remove();
                continue;
            }
            // Floor markers along the circumference (sparser as the ring grows).
            int points = Mth.clamp((int) (ring.radius * 6.0D), 8, 60);
            for (int i = 0; i < points; i++) {
                double angle = i * Math.PI * 2.0D / points;
                level.sendParticles(ParticleTypes.SOUL_FIRE_FLAME,
                        this.arenaCenter.x + Math.cos(angle) * ring.radius,
                        this.groundY + 0.15D,
                        this.arenaCenter.z + Math.sin(angle) * ring.radius,
                        1, 0.05D, 0.02D, 0.05D, 0.0D);
            }
            // Jumpable: only grounded players near the floor get clipped by the ring edge.
            for (ServerPlayer player : livingParticipants(level)) {
                if (!ring.hit.contains(player.getUUID()) && player.onGround()
                        && player.getY() < this.groundY + 1.5D
                        && Math.abs(horizontalDistance(player.position()) - ring.radius) < 0.7D) {
                    ring.hit.add(player.getUUID());
                    player.hurt(this.damageSources().indirectMagic(this, this), RING_DAMAGE);
                    EclipseMod.LOGGER.info("Herald collapse ring hit {} for {}",
                            player.getScoreboardName(), RING_DAMAGE);
                }
            }
        }
    }

    /** Corona shards detach one by one as P3 health drains (8 at 33% -> 0 at death). */
    private void tickShardDetach(ServerLevel level) {
        float fraction = this.getHealth() / this.getMaxHealth();
        int expected = Mth.clamp(Mth.ceil(fraction * 3.0F * CORONA_SHARDS), 0, CORONA_SHARDS);
        if (getShardsLeft() <= expected) {
            return;
        }
        setShardsLeft(getShardsLeft() - 1);
        // The shard crashes onto a participant's position (or a random arena point).
        List<ServerPlayer> targets = livingParticipants(level);
        Vec3 impact;
        if (targets.isEmpty()) {
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double radius = this.random.nextDouble() * 10.0D;
            impact = new Vec3(this.arenaCenter.x + Math.cos(angle) * radius, this.groundY,
                    this.arenaCenter.z + Math.sin(angle) * radius);
        } else {
            ServerPlayer target = targets.get(this.random.nextInt(targets.size()));
            impact = new Vec3(target.getX(), this.groundY, target.getZ());
        }
        this.crashes.add(new ShardCrash(impact));
        level.playSound(null, this.blockPosition(), SoundEvents.AMETHYST_CLUSTER_BREAK,
                SoundSource.HOSTILE, 1.5F, 0.6F);
        EclipseMod.LOGGER.info("Herald corona shard detached ({} left) — crashing at ({}, {}, {}) in {}t",
                getShardsLeft(), String.format(java.util.Locale.ROOT, "%.1f", impact.x),
                String.format(java.util.Locale.ROOT, "%.1f", impact.y),
                String.format(java.util.Locale.ROOT, "%.1f", impact.z), CRASH_DELAY_TICKS);
    }

    private void tickShardCrashes(ServerLevel level) {
        for (java.util.Iterator<ShardCrash> iterator = this.crashes.iterator(); iterator.hasNext();) {
            ShardCrash crash = iterator.next();
            // Warning column while the shard falls.
            level.sendParticles(ParticleTypes.CRIT, crash.pos.x,
                    this.groundY + 0.2D + (CRASH_DELAY_TICKS - crash.ticksLeft) * 0.05D, crash.pos.z,
                    3, 0.3D, 0.1D, 0.3D, 0.0D);
            if (--crash.ticksLeft > 0) {
                continue;
            }
            iterator.remove();
            PacketDistributor.sendToPlayersNear(level, null, crash.pos.x, crash.pos.y, crash.pos.z,
                    96.0D, new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, crash.pos));
            level.playSound(null, BlockPos.containing(crash.pos), SoundEvents.GENERIC_EXPLODE.value(),
                    SoundSource.HOSTILE, 0.8F, 1.2F);
            int hits = 0;
            for (ServerPlayer player : livingParticipants(level)) {
                if (player.position().distanceTo(crash.pos) <= CRASH_RADIUS) {
                    player.hurt(this.damageSources().indirectMagic(this, this), CRASH_DAMAGE);
                    hits++;
                }
            }
            EclipseMod.LOGGER.info("Herald shard crash at ({}, {}, {}) hit {} player(s)",
                    String.format(java.util.Locale.ROOT, "%.1f", crash.pos.x),
                    String.format(java.util.Locale.ROOT, "%.1f", crash.pos.y),
                    String.format(java.util.Locale.ROOT, "%.1f", crash.pos.z), hits);
        }
    }

    // --- participant helpers ---

    /** Tracked participants that are online, alive and still in/near the arena. */
    private List<ServerPlayer> livingParticipants(ServerLevel level) {
        List<ServerPlayer> alive = new ArrayList<>();
        for (UUID id : this.participants) {
            ServerPlayer player = level.getServer().getPlayerList().getPlayer(id);
            if (player != null && player.isAlive() && !player.isSpectator() && player.level() == level
                    && horizontalDistance(player.position()) <= ARENA_RADIUS + 12.0D) {
                alive.add(player);
            }
        }
        return alive;
    }

    @Nullable
    private ServerPlayer nearestParticipant() {
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return null;
        }
        ServerPlayer nearest = null;
        double best = Double.MAX_VALUE;
        for (ServerPlayer player : livingParticipants(serverLevel)) {
            double dist = player.distanceToSqr(this);
            if (dist < best) {
                best = dist;
                nearest = player;
            }
        }
        return nearest;
    }

    private double horizontalDistance(Vec3 pos) {
        if (this.arenaCenter == null) {
            return Double.MAX_VALUE;
        }
        double dx = pos.x - this.arenaCenter.x;
        double dz = pos.z - this.arenaCenter.z;
        return Math.sqrt(dx * dx + dz * dz);
    }

    // --- death / drops ---

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        this.spawnAtLocation(new ItemStack(EclipseItems.HERALD_CORE.get()));
        int rewarded = 0;
        for (UUID id : this.participants) {
            ServerPlayer player = level.getServer().getPlayerList().getPlayer(id);
            if (player != null && player.isAlive() && player.level() == level) {
                // Per spec: 3 umbral shards dropped at EACH participant's feet.
                net.minecraft.world.Containers.dropItemStack(level, player.getX(), player.getY() + 0.2D,
                        player.getZ(), new ItemStack(EclipseItems.UMBRAL_SHARD.get(), 3));
                rewarded++;
            }
        }
        EclipseMod.LOGGER.info("Herald drops: 1 herald_core at the corpse + 3 umbral shards to {} participant(s)",
                rewarded);
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (this.level() instanceof ServerLevel serverLevel) {
            EclipseWorldState state = EclipseWorldState.get(serverLevel.getServer());
            if (!state.isHeraldDefeated()) {
                state.setHeraldDefeated(true);
                AnnouncementService.announce(serverLevel.getServer(),
                        "announce.eclipse.herald.title", "announce.eclipse.herald.sub",
                        dev.projecteclipse.eclipse.network.S2CAnnouncePayload.STYLE_BOSS);
            }
            PacketDistributor.sendToPlayersNear(serverLevel, null, this.getX(), this.getY(), this.getZ(),
                    96.0D, new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, this.position()));
            EclipseMod.LOGGER.info("Herald defeated (source: {}) — heraldDefeated flag set, unlock key 'herald_slain' active",
                    damageSource.getMsgId());
        }
    }

    // --- bossbar (wither pattern + W8 skin payload for every viewer incl. late joiners) ---

    @Override
    public void startSeenByPlayer(ServerPlayer player) {
        super.startSeenByPlayer(player);
        this.bossEvent.addPlayer(player);
        PacketDistributor.sendToPlayer(player,
                new S2CBossbarStylePayload(this.bossEvent.getId(), S2CBossbarStylePayload.THEME_BOSS));
    }

    @Override
    public void stopSeenByPlayer(ServerPlayer player) {
        super.stopSeenByPlayer(player);
        this.bossEvent.removePlayer(player);
    }

    @Override
    public void setCustomName(@Nullable Component name) {
        super.setCustomName(name);
        if (name != null) {
            this.bossEvent.setName(name);
        }
    }

    // --- client animation hooks ---

    /** Advances the smooth animation clock and the P3 shard tilt-out lerp (client only). */
    private void tickClientAnim() {
        float targetSpeed = getPhase() >= 3 ? 2.0F : 1.0F;
        this.animSpeed += (targetSpeed - this.animSpeed) * 0.05F;
        this.animAgePrev = this.animAge;
        this.animAge += this.animSpeed;
        this.shardTiltPrev = this.shardTilt;
        float targetTilt = getPhase() >= 3 ? 0.6F : 0.0F;
        this.shardTilt += (targetTilt - this.shardTilt) * 0.05F;
    }

    /** Smooth model animation age (spec anims run off this; advances x2 in P3). */
    public float animAge(float partialTick) {
        return Mth.lerp(partialTick, this.animAgePrev, this.animAge);
    }

    /** P3 corona tilt-out amount, lerped toward {@code zRot 0.6} per spec. */
    public float shardTilt(float partialTick) {
        return Mth.lerp(partialTick, this.shardTiltPrev, this.shardTilt);
    }

    // --- floating-boss chassis ---

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_PHASE, 1);
        builder.define(DATA_TELEGRAPH, false);
        builder.define(DATA_SHARDS_LEFT, CORONA_SHARDS);
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public void knockback(double strength, double x, double z) {
        // Anchored: the fight's movement script owns the velocity.
    }

    @Override
    public boolean causeFallDamage(float fallDistance, float multiplier, DamageSource source) {
        return false;
    }

    @Override
    public boolean onClimbable() {
        return false;
    }

    @Override
    public void checkDespawn() {
        // Never despawns naturally; tickReset() handles the no-players despawn itself.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    public void travel(Vec3 travelVector) {
        // Gravity-free drift: velocity is set directly by the movement script each tick.
        if (this.isControlledByLocalInstance()) {
            this.move(MoverType.SELF, this.getDeltaMovement());
            this.setDeltaMovement(this.getDeltaMovement().scale(0.91D));
        }
    }

    // --- sounds ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return EclipseSounds.BOSS_HERALD_AMBIENT.get();
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.AMETHYST_BLOCK_HIT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WITHER_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.6F;
    }

    // --- persistence ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt("ShardsLeft", getShardsLeft());
        compound.putInt("ScaledPlayers", this.scaledPlayers);
        if (this.arenaCenter != null) {
            compound.putDouble("ArenaX", this.arenaCenter.x);
            compound.putDouble("ArenaY", this.arenaCenter.y);
            compound.putDouble("ArenaZ", this.arenaCenter.z);
            compound.putInt("GroundY", this.groundY);
        }
        ListTag list = new ListTag();
        for (UUID id : this.participants) {
            list.add(NbtUtils.createUUID(id));
        }
        compound.put("Participants", list);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("ShardsLeft")) {
            setShardsLeft(compound.getInt("ShardsLeft"));
        }
        if (compound.contains("ScaledPlayers")) {
            this.scaledPlayers = Math.max(1, compound.getInt("ScaledPlayers"));
        }
        if (compound.contains("ArenaX")) {
            this.arenaCenter = new Vec3(compound.getDouble("ArenaX"),
                    compound.getDouble("ArenaY"), compound.getDouble("ArenaZ"));
            this.groundY = compound.getInt("GroundY");
        }
        for (Tag entry : compound.getList("Participants", Tag.TAG_INT_ARRAY)) {
            this.participants.add(NbtUtils.loadUUID(entry));
        }
        // Re-derive the phase (synced data + lastPhase) so a reloaded fight resumes cleanly.
        float fraction = this.getMaxHealth() > 0.0F ? this.getHealth() / this.getMaxHealth() : 1.0F;
        this.lastPhase = fraction > 2.0F / 3.0F ? 1 : fraction > 1.0F / 3.0F ? 2 : 3;
        setPhase(this.lastPhase);
        if (this.hasCustomName()) {
            this.bossEvent.setName(this.getDisplayName());
        }
    }

    // --- helpers ---

    /** Look helper for the fight: turns body + head toward a target position. */
    private void faceTowards(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }

    /** World position of the emissive inner eye (gaze + volley origin). */
    public Vec3 eyePos() {
        return new Vec3(this.getX(), this.getY() + 2.5D, this.getZ());
    }
}
