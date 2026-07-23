package dev.projecteclipse.eclipse.entity.boss.fog;

import javax.annotation.Nullable;

import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.phys.Vec3;

/**
 * The Fog Tyrant's arena/leash anchor ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.4 — "self-pins arena r=16"; {@code RiftAnchor} precedent, W11's own copy because
 * the radii differ and cross-family file sharing is banned): an immutable pin of the
 * fight's center + floor Y, created once by {@code ensureFightInitialized}/
 * {@link FogTyrantEntity#summonAt} and persisted through NBT so a restarted server
 * resumes the exact same ring.
 *
 * <ul>
 *   <li>{@value #ARENA_RADIUS}-block combat ring — damage originating outside it is
 *       deflected by the tyrant ({@code hurt} override; Herald pattern), and storm-step
 *       destinations are clamped inside it;</li>
 *   <li>{@value #IMPULSE_RADIUS}-block leash — players drifting past it get the
 *       SoftBorder-style inward impulse ({@link #impulseInward}) plus a fog-wall arc
 *       segment facing them ({@link #particleWall}).</li>
 * </ul>
 */
public final class FogTyrantArena {
    /** Combat ring: outside-ring damage deflects; storm-step destinations clamp inside. */
    public static final double ARENA_RADIUS = 16.0D;
    /** Leash ring: beyond this, players get the inward impulse. */
    public static final double IMPULSE_RADIUS = 18.0D;

    // SoftBorder pushback formula (border/SoftBorder.impulseInward, Herald-audited).
    private static final double MAX_IMPULSE = 1.2D;
    private static final double IMPULSE_BASE = 0.4D;
    private static final double IMPULSE_SCALE = 0.25D;
    private static final double IMPULSE_Y = 0.3D;

    private final Vec3 center;
    private final int groundY;

    public FogTyrantArena(Vec3 center, int groundY) {
        this.center = center;
        this.groundY = groundY;
    }

    public Vec3 center() {
        return this.center;
    }

    public int groundY() {
        return this.groundY;
    }

    /** Horizontal (XZ) distance from the arena center. */
    public double horizontalDistance(Vec3 pos) {
        double dx = pos.x - this.center.x;
        double dz = pos.z - this.center.z;
        return Math.sqrt(dx * dx + dz * dz);
    }

    /** True when {@code pos} sits inside the combat ring. */
    public boolean isInside(Vec3 pos) {
        return horizontalDistance(pos) <= ARENA_RADIUS;
    }

    /**
     * Pulls {@code pos} radially onto {@code ARENA_RADIUS − margin} when it lies beyond
     * it (Y untouched) — keeps every storm-step destination inside the ring.
     */
    public Vec3 clampInside(Vec3 pos, double margin) {
        double dist = horizontalDistance(pos);
        double max = ARENA_RADIUS - margin;
        if (dist <= max || dist < 1.0E-4D) {
            return pos;
        }
        double scale = max / dist;
        return new Vec3(this.center.x + (pos.x - this.center.x) * scale, pos.y,
                this.center.z + (pos.z - this.center.z) * scale);
    }

    /**
     * SoftBorder inward shove for a player beyond the {@value #IMPULSE_RADIUS} leash
     * (velocity synced via {@code hurtMarked}); returns whether it fired. The warning
     * chime is throttled by the caller's tick count (~1/s).
     */
    public boolean impulseInward(ServerPlayer player, int tickCount) {
        double dist = horizontalDistance(player.position());
        if (dist <= IMPULSE_RADIUS || dist > IMPULSE_RADIUS + 12.0D) {
            return false;
        }
        double dx = player.getX() - this.center.x;
        double dz = player.getZ() - this.center.z;
        double strength = Math.min(MAX_IMPULSE, IMPULSE_SCALE * (dist - IMPULSE_RADIUS) + IMPULSE_BASE);
        double inv = 1.0D / dist;
        player.setDeltaMovement(new Vec3(-dx * inv * strength, IMPULSE_Y, -dz * inv * strength));
        player.hurtMarked = true; // Sync the velocity to the client (SoftBorder pattern).
        if (tickCount % 20 == 0) {
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.HOSTILE, 0.8F, 0.4F);
        }
        return true;
    }

    /** Storm wall: the fog-and-spark arc segment of the combat ring facing a player. */
    public void particleWall(ServerLevel level, ServerPlayer player) {
        double dist = horizontalDistance(player.position());
        if (dist <= ARENA_RADIUS - 6.0D) {
            return;
        }
        double angle = Math.atan2(player.getZ() - this.center.z, player.getX() - this.center.x);
        for (int i = -2; i <= 2; i++) {
            double a = angle + i * 0.1D;
            double x = this.center.x + Math.cos(a) * ARENA_RADIUS;
            double z = this.center.z + Math.sin(a) * ARENA_RADIUS;
            level.sendParticles(ParticleTypes.CLOUD, x,
                    this.groundY + 0.4D + level.getRandom().nextDouble() * 3.5D, z,
                    1, 0.05D, 0.4D, 0.05D, 0.0D);
            if (level.getRandom().nextInt(3) == 0) {
                level.sendParticles(ParticleTypes.ELECTRIC_SPARK, x,
                        this.groundY + 1.0D + level.getRandom().nextDouble() * 2.5D, z,
                        1, 0.05D, 0.3D, 0.05D, 0.01D);
            }
        }
    }

    // --- persistence (Herald-style raw doubles; restart resumes the exact ring) ---

    public void save(CompoundTag compound) {
        compound.putDouble("ArenaX", this.center.x);
        compound.putDouble("ArenaY", this.center.y);
        compound.putDouble("ArenaZ", this.center.z);
        compound.putInt("GroundY", this.groundY);
    }

    @Nullable
    public static FogTyrantArena load(CompoundTag compound) {
        if (!compound.contains("ArenaX")) {
            return null;
        }
        return new FogTyrantArena(new Vec3(compound.getDouble("ArenaX"),
                compound.getDouble("ArenaY"), compound.getDouble("ArenaZ")),
                compound.getInt("GroundY"));
    }
}
