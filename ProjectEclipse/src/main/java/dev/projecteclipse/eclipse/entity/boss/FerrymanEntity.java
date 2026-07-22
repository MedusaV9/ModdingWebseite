package dev.projecteclipse.eclipse.entity.boss;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
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
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The Ferryman — day-14 finale boss on the limbo ghost ship
 * ({@code docs/ideas/04_content.md} §2.2). Summoned by the finale ritual (dragon egg at the
 * altar after dusk on day 14) or {@code /eclipse boss ferryman summon}; never spawns
 * naturally, and it refuses to exist outside {@code eclipse:limbo}.
 *
 * <p><b>Fight</b> (server-scripted, no vanilla goals): 400 HP base scaled
 * ×(1+0.4·(n−1)) for n living players; bossbar WHITE → PURPLE → RED by phase:</p>
 * <ul>
 *   <li><b>P1 Oar</b> (100–66%): melee stalker on the deck; telegraphed 180° oar sweeps
 *       (25t raise + TRIDENT_RIPTIDE_3, 10 dmg + heavy knockback) and periodic gunwale
 *       slams (jump + AoE + {@code S2CShakePayload} ship tilt). Overboard players take a
 *       void-cold water DoT until they climb back onto the deck.</li>
 *   <li><b>P2 Crew</b> (≤66%): kneels invulnerable at the stern; the Deckhand crew rises
 *       hostile and the deck lanterns blow out. LIVING players kill Deckhands; GHOSTS
 *       (banned players) re-light lanterns via a 3 s right-click channel. All required
 *       lanterns lit ends the phase.</li>
 *   <li><b>P3 The Toll</b> (≤33%): plants the oar; the ship sinks one water layer per 30 s
 *       (soft enrage, paused while ≤3 players live) and sweeps alternate with the Lantern
 *       Gaze — the lowest-hearts player is marked (private vignette) and hunted 15 s.</li>
 * </ul>
 *
 * <p><b>Endings</b>: death drops {@code eclipse:ferryman_toll}, sets
 * {@code ferrymanDefeated}, restores the ship and hands off to the mass-revive finale
 * ({@code ritual/FinaleRitual}). A wipe (every living fighter dead) is the Eclipse's
 * victory: announce, everyone stays a ghost.</p>
 */
public class FerrymanEntity extends Monster {
    public static final float BASE_MAX_HEALTH = 400.0F;
    /** Deck X of the stern anchor (bow is +X): three blocks inboard of the stern cap. */
    public static final int STERN_X = -(GhostShipBuilder.HALF_LENGTH - 3);

    private static final double SCALING_RANGE = 64.0D;

    /** Current phase 1..3 (synced; drives bossbar color + model poses). */
    private static final EntityDataAccessor<Integer> DATA_PHASE =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.INT);
    /** True while an oar sweep is winding up (client raises the oar overhead). */
    private static final EntityDataAccessor<Boolean> DATA_TELEGRAPH =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);
    /** True while kneeling invulnerable at the stern (P2 crew mechanic). */
    private static final EntityDataAccessor<Boolean> DATA_KNEELING =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);
    /** True while the oar is planted on the deck (P3 idle pose). */
    private static final EntityDataAccessor<Boolean> DATA_PLANTED =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);
    /** True while the Lantern Gaze mark is active (the lantern joins the emissive pass). */
    private static final EntityDataAccessor<Boolean> DATA_GAZING =
            SynchedEntityData.defineId(FerrymanEntity.class, EntityDataSerializers.BOOLEAN);

    private final ServerBossEvent bossEvent = new ServerBossEvent(
            Component.translatable("entity.eclipse.ferryman.bossbar"),
            BossEvent.BossBarColor.WHITE, BossEvent.BossBarOverlay.PROGRESS);

    // --- server fight state ---
    @Nullable
    private Vec3 shipCenter;
    private int deckY;
    private int scaledPlayers = 1;
    private int lastPhase = 1;

    // Client-side smooth animation clock + pose blend weights (raise/kneel/plant).
    private float animAge;
    private float animAgePrev;
    private float raiseLerp;
    private float raiseLerpPrev;
    private float kneelLerp;
    private float kneelLerpPrev;
    private float plantLerp;
    private float plantLerpPrev;

    public FerrymanEntity(EntityType<? extends FerrymanEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
        this.xpReward = 100;
    }

    // --- summoning ---

    /**
     * Spawns the Ferryman at the ghost ship's stern (feet one block above the deck) with
     * the arrival FX, and snapshots the living-player scaling. {@code limbo} must be the
     * Limbo dimension — the ship geometry (deck height, bounds) is derived from
     * {@link GhostShipBuilder}.
     */
    public static FerrymanEntity summon(ServerLevel limbo) {
        FerrymanEntity ferryman = dev.projecteclipse.eclipse.entity.EclipseEntities.FERRYMAN.get().create(limbo);
        if (ferryman == null) {
            throw new IllegalStateException("Ferryman entity type failed to instantiate");
        }
        int deck = GhostShipBuilder.waterlineY(limbo) + 3;
        double x = STERN_X + 0.5D;
        double z = 0.5D;
        ferryman.moveTo(x, deck + 1, z, 90.0F, 0.0F); // faces the bow (+X)
        ferryman.initFight(limbo, new Vec3(0.5D, deck, 0.5D), deck);
        limbo.addFreshEntity(ferryman);
        PacketDistributor.sendToPlayersNear(limbo, null, x, deck + 1, z, 96.0D,
                new S2CQuasarPayload(S2CQuasarPayload.BOSS_SLAM, ferryman.position()));
        limbo.playSound(null, ferryman.blockPosition(), SoundEvents.END_PORTAL_SPAWN, SoundSource.HOSTILE, 1.0F, 0.4F);
        limbo.playSound(null, ferryman.blockPosition(), EclipseSounds.BOSS_FERRYMAN_AMBIENT.get(),
                SoundSource.HOSTILE, 1.2F, 1.0F);
        limbo.sendParticles(ParticleTypes.SOUL, x, deck + 2.0D, z, 80, 1.0D, 1.4D, 1.0D, 0.04D);
        EclipseMod.LOGGER.info("Ferryman summoned at the stern ({}, {}, {}) — scaled for {} player(s): {} HP; bossbar {} created",
                x, deck + 1, z, ferryman.scaledPlayers, ferryman.getMaxHealth(), ferryman.bossEvent.getId());
        return ferryman;
    }

    /** Pins the ship geometry and applies the living-player scaling (spec §2.2). */
    private void initFight(ServerLevel limbo, Vec3 center, int deck) {
        this.shipCenter = center;
        this.deckY = deck;
        long living = limbo.getServer().getPlayerList().getPlayers().stream()
                .filter(player -> !player.isSpectator() && player.isAlive())
                .filter(player -> !dev.projecteclipse.eclipse.lives.BanService.isBanned(player))
                .filter(player -> player.level() != limbo
                        || player.position().distanceTo(center) <= SCALING_RANGE)
                .count();
        this.scaledPlayers = (int) Math.max(1L, living);
        double maxHealth = BASE_MAX_HEALTH * (1.0D + 0.4D * (this.scaledPlayers - 1));
        this.getAttribute(Attributes.MAX_HEALTH).setBaseValue(maxHealth);
        this.setHealth((float) maxHealth);
    }

    /** Lazy geometry init for plain {@code /summon eclipse:ferryman} in limbo. */
    private void ensureFightInitialized(ServerLevel level) {
        if (this.shipCenter != null) {
            return;
        }
        int deck = GhostShipBuilder.waterlineY(level) + 3;
        initFight(level, new Vec3(0.5D, deck, 0.5D), deck);
        EclipseMod.LOGGER.info("Ferryman ship geometry auto-pinned (deck y={}, {} player(s), {} HP); bossbar {} created",
                deck, this.scaledPlayers, this.getMaxHealth(), this.bossEvent.getId());
    }

    // --- synced state accessors ---

    public int getPhase() {
        return this.entityData.get(DATA_PHASE);
    }

    protected void setPhase(int phase) {
        this.entityData.set(DATA_PHASE, Mth.clamp(phase, 1, 3));
    }

    public boolean isTelegraphing() {
        return this.entityData.get(DATA_TELEGRAPH);
    }

    protected void setTelegraphing(boolean telegraphing) {
        this.entityData.set(DATA_TELEGRAPH, telegraphing);
    }

    public boolean isKneeling() {
        return this.entityData.get(DATA_KNEELING);
    }

    protected void setKneeling(boolean kneeling) {
        this.entityData.set(DATA_KNEELING, kneeling);
    }

    public boolean isPlanted() {
        return this.entityData.get(DATA_PLANTED);
    }

    protected void setPlanted(boolean planted) {
        this.entityData.set(DATA_PLANTED, planted);
    }

    public boolean isGazing() {
        return this.entityData.get(DATA_GAZING);
    }

    protected void setGazing(boolean gazing) {
        this.entityData.set(DATA_GAZING, gazing);
    }

    // --- ticking ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            tickClientAnim();
        } else if (this.isAlive() && this.level() instanceof ServerLevel serverLevel) {
            if (!serverLevel.dimension().equals(dev.projecteclipse.eclipse.limbo.LimboDimension.LIMBO)) {
                // The Ferryman exists only on the ghost ship.
                EclipseMod.LOGGER.warn("Ferryman discarded: spawned outside {}",
                        dev.projecteclipse.eclipse.limbo.LimboDimension.LIMBO.location());
                this.discard();
                return;
            }
            ensureFightInitialized(serverLevel);
            this.bossEvent.setProgress(this.getHealth() / this.getMaxHealth());
            updatePhase(serverLevel);
            tickFight(serverLevel);
        }
    }

    /** Phase = health fraction: breaks at exactly 2/3 and 1/3 (bossbar WHITE→PURPLE→RED). */
    private void updatePhase(ServerLevel level) {
        float fraction = this.getHealth() / this.getMaxHealth();
        int phase = fraction > 2.0F / 3.0F ? 1 : fraction > 1.0F / 3.0F ? 2 : 3;
        if (phase == this.lastPhase) {
            return;
        }
        EclipseMod.LOGGER.info("Ferryman phase {} -> {} at {}/{} HP", this.lastPhase, phase,
                String.format(java.util.Locale.ROOT, "%.1f", this.getHealth()),
                String.format(java.util.Locale.ROOT, "%.1f", this.getMaxHealth()));
        int previous = this.lastPhase;
        this.lastPhase = phase;
        setPhase(phase);
        applyBossbarColor(phase);
        level.playSound(null, this.blockPosition(), SoundEvents.WITHER_SPAWN, SoundSource.HOSTILE,
                1.0F, phase == 2 ? 1.1F : 0.6F);
        onPhaseChanged(level, previous, phase);
    }

    /** Fight-side reaction to a phase break; the fight logic (crew, toll) hooks in here. */
    protected void onPhaseChanged(ServerLevel level, int previousPhase, int newPhase) {
        setTelegraphing(false);
    }

    /** Per-tick fight script; the chassis only holds position until the fight logic lands. */
    protected void tickFight(ServerLevel level) {
        // Chassis: hover in place one block above the deck.
        if (this.shipCenter != null) {
            double targetY = this.deckY + 1.0D;
            this.setDeltaMovement(new Vec3(0.0D, (targetY - this.getY()) * 0.1D, 0.0D));
        }
    }

    /** WHITE (P1) → PURPLE (P2) → RED (P3) per spec §2.2. */
    private void applyBossbarColor(int phase) {
        this.bossEvent.setColor(switch (phase) {
            case 2 -> BossEvent.BossBarColor.PURPLE;
            case 3 -> BossEvent.BossBarColor.RED;
            default -> BossEvent.BossBarColor.WHITE;
        });
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

    /** Advances the smooth clock and eases the raise/kneel/plant pose weights (client only). */
    private void tickClientAnim() {
        this.animAgePrev = this.animAge;
        this.animAge += getPhase() >= 3 ? 1.4F : 1.0F;
        this.raiseLerpPrev = this.raiseLerp;
        this.raiseLerp += ((isTelegraphing() ? 1.0F : 0.0F) - this.raiseLerp) * 0.16F;
        this.kneelLerpPrev = this.kneelLerp;
        this.kneelLerp += ((isKneeling() ? 1.0F : 0.0F) - this.kneelLerp) * 0.08F;
        this.plantLerpPrev = this.plantLerp;
        this.plantLerp += ((isPlanted() ? 1.0F : 0.0F) - this.plantLerp) * 0.08F;
    }

    /** Smooth model animation age (rowing idle, chain swing; advances ×1.4 in P3). */
    public float animAge(float partialTick) {
        return Mth.lerp(partialTick, this.animAgePrev, this.animAge);
    }

    /** 0..1 blend toward the raised-oar telegraph pose. */
    public float raiseAmount(float partialTick) {
        return Mth.lerp(partialTick, this.raiseLerpPrev, this.raiseLerp);
    }

    /** 0..1 blend toward the P2 kneel-at-the-stern pose. */
    public float kneelAmount(float partialTick) {
        return Mth.lerp(partialTick, this.kneelLerpPrev, this.kneelLerp);
    }

    /** 0..1 blend toward the P3 planted-oar pose. */
    public float plantAmount(float partialTick) {
        return Mth.lerp(partialTick, this.plantLerpPrev, this.plantLerp);
    }

    // --- floating-boss chassis ---

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_PHASE, 1);
        builder.define(DATA_TELEGRAPH, false);
        builder.define(DATA_KNEELING, false);
        builder.define(DATA_PLANTED, false);
        builder.define(DATA_GAZING, false);
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
    public void checkDespawn() {
        // Never despawns naturally; the fight's own reset handles abandonment.
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
        return EclipseSounds.BOSS_FERRYMAN_AMBIENT.get();
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.DROWNED_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WARDEN_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.7F;
    }

    // --- persistence ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt("ScaledPlayers", this.scaledPlayers);
        if (this.shipCenter != null) {
            compound.putDouble("ShipX", this.shipCenter.x);
            compound.putDouble("ShipY", this.shipCenter.y);
            compound.putDouble("ShipZ", this.shipCenter.z);
            compound.putInt("DeckY", this.deckY);
        }
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("ScaledPlayers")) {
            this.scaledPlayers = Math.max(1, compound.getInt("ScaledPlayers"));
        }
        if (compound.contains("ShipX")) {
            this.shipCenter = new Vec3(compound.getDouble("ShipX"),
                    compound.getDouble("ShipY"), compound.getDouble("ShipZ"));
            this.deckY = compound.getInt("DeckY");
        }
        // Re-derive the phase so a reloaded fight resumes with the right bar color.
        float fraction = this.getMaxHealth() > 0.0F ? this.getHealth() / this.getMaxHealth() : 1.0F;
        this.lastPhase = fraction > 2.0F / 3.0F ? 1 : fraction > 1.0F / 3.0F ? 2 : 3;
        setPhase(this.lastPhase);
        applyBossbarColor(this.lastPhase);
        if (this.hasCustomName()) {
            this.bossEvent.setName(this.getDisplayName());
        }
    }

    // --- shared helpers for the fight logic ---

    @Nullable
    protected Vec3 shipCenter() {
        return this.shipCenter;
    }

    protected int deckY() {
        return this.deckY;
    }

    protected int scaledPlayers() {
        return this.scaledPlayers;
    }

    protected ServerBossEvent bossEvent() {
        return this.bossEvent;
    }

    /** Look helper for the fight: turns body + head toward a target position. */
    protected void faceTowards(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }
}
