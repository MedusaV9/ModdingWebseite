package dev.projecteclipse.eclipse.entity.boss.rift;

import javax.annotation.Nullable;

import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.phys.Vec3;

/**
 * The Rift Warden's arena/leash anchor ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.4): an immutable pin of the fight's center + floor Y, created once by
 * {@code ensureFightInitialized}/{@link RiftWardenEntity#summonAt} and persisted through
 * NBT so a restarted server resumes the exact same ring. All ring geometry lives here:
 *
 * <ul>
 *   <li>{@value #ARENA_RADIUS}-block combat ring — damage originating outside it is
 *       deflected by the warden ({@code hurt} override; Herald pattern, "no doorway
 *       cheese in a dungeon"), and rift-step destinations are clamped inside it;</li>
 *   <li>{@value #IMPULSE_RADIUS}-block leash — players drifting past it get the
 *       SoftBorder-style inward impulse ({@link #impulseInward}) plus a reverse-portal
 *       particle wall segment facing them ({@link #particleWall}).</li>
 * </ul>
 *
 * <p>Fits any ≥ 20×20 flat room (P1's vault boss-room contract, plan §4.1 dungeon row).</p>
 */
public final class RiftAnchor {
    /** Combat ring: outside-ring damage deflects; blink destinations clamp inside. */
    public static final double ARENA_RADIUS = 12.0D;
    /** Leash ring: beyond this, players get the inward impulse (spec: r=14). */
    public static final double IMPULSE_RADIUS = 14.0D;

    // SoftBorder pushback formula (border/SoftBorder.impulseInward, Herald-audited).
    private static final double MAX_IMPULSE = 1.2D;
    private static final double IMPULSE_BASE = 0.4D;
    private static final double IMPULSE_SCALE = 0.25D;
    private static final double IMPULSE_Y = 0.3D;

    private final Vec3 center;
    private final int groundY;

    public RiftAnchor(Vec3 center, int groundY) {
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
     * it (Y untouched) — keeps every rift-step destination inside the ring.
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
     * (velocity synced via {@code hurtMarked}); returns whether it fired. The amethyst
     * warning chime is throttled by the caller's tick count (~1/s).
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
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.HOSTILE, 0.8F, 0.5F);
        }
        return true;
    }

    /** Reverse-portal wall: the arc segment of the combat ring facing a nearby player. */
    public void particleWall(ServerLevel level, ServerPlayer player) {
        double dist = horizontalDistance(player.position());
        if (dist <= ARENA_RADIUS - 6.0D) {
            return;
        }
        double angle = Math.atan2(player.getZ() - this.center.z, player.getX() - this.center.x);
        for (int i = -2; i <= 2; i++) {
            double a = angle + i * 0.12D;
            level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                    this.center.x + Math.cos(a) * ARENA_RADIUS,
                    this.groundY + 0.5D + level.getRandom().nextDouble() * 3.0D,
                    this.center.z + Math.sin(a) * ARENA_RADIUS,
                    1, 0.05D, 0.4D, 0.05D, 0.0D);
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
    public static RiftAnchor load(CompoundTag compound) {
        if (!compound.contains("ArenaX")) {
            return null;
        }
        return new RiftAnchor(new Vec3(compound.getDouble("ArenaX"),
                compound.getDouble("ArenaY"), compound.getDouble("ArenaZ")),
                compound.getInt("GroundY"));
    }
}
