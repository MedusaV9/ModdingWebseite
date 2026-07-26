package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

import javax.annotation.Nullable;

/**
 * F-046b — the Ferryman's three FINALE special attacks, owned per boss instance and
 * ticked from {@code FerrymanEntity.tickFight} (base attacks pause while a special is
 * busy — {@link #isBusy} gates the sweep/slam triggers, so telegraphs never overlap).
 *
 * <ul>
 *   <li><b>(a) Seelenernte</b> — a violet floor ring ({@link FxCues#CUE_FERRY_HARVEST})
 *       contracts onto the boss over the {@value #HARVEST_TELEGRAPH_TICKS}t warning
 *       (~2 s; {@value #HARVEST_TELEGRAPH_ENRAGED}t enraged), then every fighter within
 *       {@value #HARVEST_PULL_RADIUS} blocks is YANKED toward the boss and, one beat
 *       later, the AoE strike lands on everyone still inside
 *       {@value #HARVEST_STRIKE_RADIUS} blocks — sprint OUT after the pull to dodge.</li>
 *   <li><b>(b) Ruderschlag-Welle</b> — the boss locks its facing on the target
 *       ({@value #WAVE_TELEGRAPH_TICKS}t stance + crest spray
 *       {@link FxCues#CUE_FERRY_WAVE}), then a water wall marches down the locked lane
 *       at {@value #WAVE_SPEED} b/t ({@value #WAVE_SPEED_ENRAGED} enraged) — sidestep
 *       the lane to dodge; hits knock straight back along it.</li>
 *   <li><b>(c) Geisterbeschwörung</b> — a {@value #SUMMON_CAST_TICKS}t cast gushes
 *       {@value #SUMMON_MIN}–{@value #SUMMON_MAX} violet {@link SoulWispEntity} shades
 *       ({@value #SUMMON_ENRAGED} when enraged) out of the boss, hard-capped at
 *       {@value #WISP_CAP} live wisps within {@value #WISP_CAP_RANGE} blocks; every
 *       wisp carries a {@value #WISP_LIFESPAN_TICKS}t lifespan (despawn guarantee).</li>
 * </ul>
 *
 * <p><b>Enrage (&lt; 50% HP)</b>: cooldown {@value #COOLDOWN_TICKS}t →
 * {@value #COOLDOWN_ENRAGED}t, faster wave, shorter harvest warning, +wisps. The
 * rotation is deterministic (harvest → wave → summon, unavailable kinds skipped), the
 * first special waits {@value #FIRST_DELAY_TICKS}t after the summon so the arena
 * arrival beat lands first. Specials only run in P1/P3 (P2 is the kneel) and only
 * while fighters are present; all state is in-memory — a reload simply restarts the
 * rotation (the arena kneel's "reload restarts the beat" law).</p>
 */
public final class FerrymanSpecialAttacks {
    // --- rotation / pacing ---
    private static final int FIRST_DELAY_TICKS = 200;
    private static final int COOLDOWN_TICKS = 240;
    private static final int COOLDOWN_ENRAGED = 140;
    private static final float ENRAGE_FRACTION = 0.5F;

    // --- (a) Seelenernte ---
    private static final int HARVEST_TELEGRAPH_TICKS = 40;
    private static final int HARVEST_TELEGRAPH_ENRAGED = 30;
    private static final double HARVEST_PULL_RADIUS = 12.0D;
    private static final double HARVEST_PULL_STRENGTH = 0.16D; // × distance, capped
    private static final double HARVEST_PULL_CAP = 1.6D;
    private static final int HARVEST_STRIKE_DELAY = 14;
    private static final double HARVEST_STRIKE_RADIUS = 4.5D;
    private static final float HARVEST_DAMAGE = 9.0F;
    private static final double HARVEST_KNOCKUP = 0.7D;

    // --- (b) Ruderschlag-Welle ---
    private static final int WAVE_TELEGRAPH_TICKS = 24;
    private static final double WAVE_SPEED = 0.55D;
    private static final double WAVE_SPEED_ENRAGED = 0.7D;
    private static final double WAVE_RANGE = 26.0D;
    private static final double WAVE_HALF_WIDTH = 3.0D;
    private static final double WAVE_FRONT_BAND = 1.6D;
    private static final float WAVE_DAMAGE = 7.0F;
    private static final double WAVE_KNOCKBACK = 1.4D;

    // --- (c) Geisterbeschwörung ---
    private static final int SUMMON_CAST_TICKS = 20;
    private static final int SUMMON_MIN = 3;
    private static final int SUMMON_MAX = 5;
    private static final int SUMMON_ENRAGED = 5;
    private static final int WISP_CAP = 8;
    private static final double WISP_CAP_RANGE = 48.0D;
    private static final int WISP_LIFESPAN_TICKS = 900; // 45 s hard despawn

    private enum Kind { HARVEST, WAVE, SUMMON }

    private static final Kind[] ROTATION = {Kind.HARVEST, Kind.WAVE, Kind.SUMMON};

    private final FerrymanEntity boss;

    private int cooldown = FIRST_DELAY_TICKS;
    private int rotationIndex;
    @Nullable
    private Kind active;
    private int timer;
    /** Wave lane (locked at cast start) + march state + once-per-cast hit set. */
    private Vec3 waveOrigin = Vec3.ZERO;
    private Vec3 waveDir = new Vec3(0.0D, 0.0D, 1.0D);
    private float waveYaw;
    private double waveFront;
    private final Set<UUID> waveHit = new HashSet<>();

    public FerrymanSpecialAttacks(FerrymanEntity boss) {
        this.boss = boss;
    }

    /** Whether a special is telegraphing/executing (gates the base sweep/slam triggers). */
    public boolean isBusy() {
        return this.active != null;
    }

    // ------------------------------------------------------------------ tick

    /** Per-tick driver, called from {@code tickFight} after the movement script. */
    public void tick(ServerLevel level, List<ServerPlayer> fighters, @Nullable ServerPlayer target) {
        if (this.active != null) {
            // Hold position through the special: kill the stroll, keep the hover bob.
            this.boss.setDeltaMovement(this.boss.getDeltaMovement().multiply(0.0D, 1.0D, 0.0D));
            switch (this.active) {
                case HARVEST -> tickHarvest(level, fighters);
                case WAVE -> tickWave(level, fighters);
                case SUMMON -> tickSummon(level);
            }
            return;
        }
        if (this.cooldown > 0) {
            this.cooldown--;
            return;
        }
        if (!canStart(fighters)) {
            return;
        }
        for (int attempt = 0; attempt < ROTATION.length; attempt++) {
            Kind kind = ROTATION[this.rotationIndex % ROTATION.length];
            this.rotationIndex++;
            if (start(kind, level, target)) {
                return;
            }
        }
        this.cooldown = 40; // nothing startable (no target / wisp cap): short re-check
    }

    /** Fairness gate: never overlap the sweep telegraph, the P3 gaze or the P2 kneel. */
    private boolean canStart(List<ServerPlayer> fighters) {
        return !fighters.isEmpty()
                && this.boss.getPhase() != 2
                && !this.boss.isTelegraphing()
                && !this.boss.isGazing();
    }

    private boolean enraged() {
        return this.boss.getHealth() < this.boss.getMaxHealth() * ENRAGE_FRACTION;
    }

    private boolean start(Kind kind, ServerLevel level, @Nullable ServerPlayer target) {
        switch (kind) {
            case HARVEST -> startHarvest(level);
            case WAVE -> {
                if (target == null) {
                    return false;
                }
                startWave(level, target);
            }
            case SUMMON -> {
                if (!FinaleEntities.SOUL_WISP.isBound() || countWisps(level) >= WISP_CAP) {
                    return false;
                }
                startSummon(level);
            }
        }
        return true;
    }

    private void finish() {
        this.active = null;
        this.cooldown = enraged() ? COOLDOWN_ENRAGED : COOLDOWN_TICKS;
    }

    // ------------------------------------------------------------------ (a) Seelenernte

    private void startHarvest(ServerLevel level) {
        this.active = Kind.HARVEST;
        this.timer = enraged() ? HARVEST_TELEGRAPH_ENRAGED : HARVEST_TELEGRAPH_TICKS;
        Vec3 pos = this.boss.position();
        FxPayloads.sendFxEvent(level, FxCues.CUE_FERRY_HARVEST, pos, 0.0F, 0.0F, 96.0D);
        level.playSound(null, this.boss.blockPosition(), SoundEvents.WARDEN_SONIC_CHARGE,
                SoundSource.HOSTILE, 1.3F, 0.6F);
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, 96.0D,
                new S2CCaptionPayload("eclipse.caption.ferry.harvest", 50,
                        S2CCaptionPayload.STYLE_SUBTITLE));
        EclipseMod.LOGGER.info("Ferryman Seelenernte: {}t violet-ring telegraph", this.timer);
    }

    private void tickHarvest(ServerLevel level, List<ServerPlayer> fighters) {
        this.timer--;
        if (this.timer == 0) {
            // The pull: everyone in the ring is yanked toward the boss (hurtMarked sync).
            int pulled = 0;
            for (ServerPlayer player : fighters) {
                Vec3 to = this.boss.position().subtract(player.position());
                double dist = to.length();
                if (dist > HARVEST_PULL_RADIUS || dist < 1.0E-3D) {
                    continue;
                }
                double strength = Math.min(HARVEST_PULL_CAP, dist * HARVEST_PULL_STRENGTH);
                player.setDeltaMovement(to.normalize().scale(strength).add(0.0D, 0.25D, 0.0D));
                player.hurtMarked = true;
                pulled++;
            }
            level.playSound(null, this.boss.blockPosition(), SoundEvents.TRIDENT_RIPTIDE_3.value(),
                    SoundSource.HOSTILE, 1.2F, 0.55F);
            this.timer = -HARVEST_STRIKE_DELAY; // negative counts up to the strike
            EclipseMod.LOGGER.info("Ferryman Seelenernte pull: {} fighter(s) yanked, strike in {}t",
                    pulled, HARVEST_STRIKE_DELAY);
            return;
        }
        if (this.timer < 0) {
            this.timer++;
            if (this.timer == 0) {
                strikeHarvest(level, fighters);
                finish();
            }
        }
    }

    private void strikeHarvest(ServerLevel level, List<ServerPlayer> fighters) {
        Vec3 pos = this.boss.position();
        int hits = 0;
        for (ServerPlayer player : fighters) {
            Vec3 away = player.position().subtract(pos);
            if (away.length() > HARVEST_STRIKE_RADIUS) {
                continue;
            }
            player.hurt(this.boss.damageSources().mobAttack(this.boss), HARVEST_DAMAGE);
            Vec3 flat = new Vec3(away.x, 0.0D, away.z);
            Vec3 dir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : new Vec3(0.0D, 0.0D, 1.0D);
            player.setDeltaMovement(dir.scale(0.9D).add(0.0D, HARVEST_KNOCKUP, 0.0D));
            player.hurtMarked = true;
            hits++;
        }
        level.sendParticles(ParticleTypes.SCULK_SOUL, pos.x, pos.y + 1.0D, pos.z,
                40, HARVEST_STRIKE_RADIUS * 0.5D, 0.6D, HARVEST_STRIKE_RADIUS * 0.5D, 0.05D);
        level.playSound(null, this.boss.blockPosition(), SoundEvents.GENERIC_EXPLODE.value(),
                SoundSource.HOSTILE, 0.9F, 0.55F);
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, 96.0D,
                S2CShakePayload.shake(0.7F, 12));
        EclipseMod.LOGGER.info("Ferryman Seelenernte strike: {} fighter(s) hit for {}", hits, HARVEST_DAMAGE);
    }

    // ------------------------------------------------------------------ (b) Ruderschlag-Welle

    private void startWave(ServerLevel level, ServerPlayer target) {
        this.active = Kind.WAVE;
        this.timer = WAVE_TELEGRAPH_TICKS;
        this.waveOrigin = this.boss.position();
        Vec3 flat = new Vec3(target.getX() - this.waveOrigin.x, 0.0D, target.getZ() - this.waveOrigin.z);
        this.waveDir = flat.lengthSqr() > 1.0E-4D ? flat.normalize() : new Vec3(0.0D, 0.0D, 1.0D);
        this.waveYaw = (float) Math.toDegrees(Math.atan2(-this.waveDir.x, this.waveDir.z));
        this.waveFront = 0.0D;
        this.waveHit.clear();
        lockYaw();
        FxPayloads.sendFxEvent(level, FxCues.CUE_FERRY_WAVE, this.waveOrigin, this.waveYaw, 0.0F, 96.0D);
        level.playSound(null, this.boss.blockPosition(), SoundEvents.DROWNED_SHOOT,
                SoundSource.HOSTILE, 1.4F, 0.5F);
        PacketDistributor.sendToPlayersNear(level, null, this.waveOrigin.x, this.waveOrigin.y,
                this.waveOrigin.z, 96.0D, new S2CCaptionPayload("eclipse.caption.ferry.wave", 50,
                        S2CCaptionPayload.STYLE_SUBTITLE));
        EclipseMod.LOGGER.info("Ferryman Ruderschlag-Welle: lane locked on {} (yaw {}), {}t stance",
                target.getScoreboardName(), String.format(java.util.Locale.ROOT, "%.0f", this.waveYaw),
                WAVE_TELEGRAPH_TICKS);
    }

    /** The boss visibly squares up on the locked lane through the whole telegraph. */
    private void lockYaw() {
        this.boss.setYRot(this.waveYaw);
        this.boss.yBodyRot = this.waveYaw;
        this.boss.yHeadRot = this.waveYaw;
    }

    private void tickWave(ServerLevel level, List<ServerPlayer> fighters) {
        if (this.timer > 0) {
            this.timer--;
            lockYaw();
            if (this.timer == 0) {
                this.waveFront = 1.5D; // launch just ahead of the oar
                level.playSound(null, this.boss.blockPosition(), SoundEvents.PLAYER_SPLASH_HIGH_SPEED,
                        SoundSource.HOSTILE, 1.5F, 0.6F);
            }
            return;
        }
        double speed = enraged() ? WAVE_SPEED_ENRAGED : WAVE_SPEED;
        this.waveFront += speed;
        Vec3 front = this.waveOrigin.add(this.waveDir.scale(this.waveFront));
        Vec3 side = new Vec3(-this.waveDir.z, 0.0D, this.waveDir.x);
        // Server-light spray: a handful of splash puffs across the crest per tick.
        for (int i = -2; i <= 2; i++) {
            Vec3 puff = front.add(side.scale(i * WAVE_HALF_WIDTH * 0.45D));
            level.sendParticles(ParticleTypes.SPLASH, puff.x, puff.y + 0.6D, puff.z,
                    4, 0.3D, 0.25D, 0.3D, 0.1D);
        }
        for (ServerPlayer player : fighters) {
            if (this.waveHit.contains(player.getUUID())) {
                continue;
            }
            Vec3 rel = player.position().subtract(this.waveOrigin);
            double along = rel.x * this.waveDir.x + rel.z * this.waveDir.z;
            double perp = Math.abs(rel.x * side.x + rel.z * side.z);
            if (Math.abs(along - this.waveFront) <= WAVE_FRONT_BAND && perp <= WAVE_HALF_WIDTH
                    && Math.abs(player.getY() - this.waveOrigin.y) <= 4.0D) {
                player.hurt(this.boss.damageSources().mobAttack(this.boss), WAVE_DAMAGE);
                player.setDeltaMovement(this.waveDir.scale(WAVE_KNOCKBACK).add(0.0D, 0.5D, 0.0D));
                player.hurtMarked = true;
                this.waveHit.add(player.getUUID());
                level.playSound(null, player.blockPosition(), SoundEvents.PLAYER_SPLASH,
                        SoundSource.HOSTILE, 1.2F, 0.8F);
            }
        }
        if (this.waveFront >= WAVE_RANGE) {
            EclipseMod.LOGGER.info("Ferryman Ruderschlag-Welle spent at {} blocks: {} fighter(s) caught",
                    (int) this.waveFront, this.waveHit.size());
            finish();
        }
    }

    // ------------------------------------------------------------------ (c) Geisterbeschwörung

    private void startSummon(ServerLevel level) {
        this.active = Kind.SUMMON;
        this.timer = SUMMON_CAST_TICKS;
        Vec3 pos = this.boss.position();
        level.playSound(null, this.boss.blockPosition(), SoundEvents.EVOKER_PREPARE_SUMMON,
                SoundSource.HOSTILE, 1.4F, 0.6F);
        PacketDistributor.sendToPlayersNear(level, null, pos.x, pos.y, pos.z, 96.0D,
                new S2CCaptionPayload("eclipse.caption.ferry.wisps", 50,
                        S2CCaptionPayload.STYLE_SUBTITLE));
        EclipseMod.LOGGER.info("Ferryman Geisterbeschwörung: {}t cast", SUMMON_CAST_TICKS);
    }

    private void tickSummon(ServerLevel level) {
        this.timer--;
        if (this.timer > 0) {
            if (this.timer % 4 == 0) {
                Vec3 pos = this.boss.position();
                level.sendParticles(ParticleTypes.SOUL, pos.x, pos.y + 1.5D, pos.z,
                        6, 0.8D, 0.8D, 0.8D, 0.02D);
            }
            return;
        }
        int budget = Math.max(0, WISP_CAP - countWisps(level));
        int want = enraged() ? SUMMON_ENRAGED
                : SUMMON_MIN + this.boss.getRandom().nextInt(SUMMON_MAX - SUMMON_MIN + 1);
        int count = Math.min(want, budget);
        Vec3 pos = this.boss.position();
        for (int i = 0; i < count; i++) {
            SoulWispEntity wisp = FinaleEntities.SOUL_WISP.get().create(level);
            if (wisp == null) {
                break;
            }
            double angle = (Math.PI * 2.0D / Math.max(1, count)) * i
                    + this.boss.getRandom().nextDouble() * 0.6D;
            Vec3 out = new Vec3(Math.cos(angle), 0.0D, Math.sin(angle));
            Vec3 spawn = pos.add(out.scale(2.5D)).add(0.0D, 1.5D, 0.0D);
            wisp.moveTo(spawn.x, spawn.y, spawn.z,
                    (float) Math.toDegrees(Math.atan2(-out.x, out.z)), 0.0F);
            wisp.setLifespan(WISP_LIFESPAN_TICKS);
            level.addFreshEntity(wisp);
            wisp.shove(out.scale(0.35D).add(0.0D, 0.15D, 0.0D));
        }
        FxPayloads.sendFxEvent(level, FxCues.CUE_WISP_GUSH, pos.add(0.0D, 1.5D, 0.0D),
                this.boss.getYRot(), 0.0F, 96.0D);
        level.playSound(null, this.boss.blockPosition(), SoundEvents.VEX_CHARGE,
                SoundSource.HOSTILE, 1.3F, 0.7F);
        EclipseMod.LOGGER.info("Ferryman Geisterbeschwörung: {} wisp(s) gushed (cap {} within {} blocks)",
                count, WISP_CAP, (int) WISP_CAP_RANGE);
        finish();
    }

    private int countWisps(ServerLevel level) {
        if (!FinaleEntities.SOUL_WISP.isBound()) {
            return WISP_CAP;
        }
        return level.getEntities(FinaleEntities.SOUL_WISP.get(),
                this.boss.getBoundingBox().inflate(WISP_CAP_RANGE), Entity::isAlive).size();
    }
}
