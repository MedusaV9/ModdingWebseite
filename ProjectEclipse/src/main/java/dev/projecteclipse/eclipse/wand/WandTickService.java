package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The wand's server-tick engine (game bus, self-registering). Three jobs:
 *
 * <ol>
 *   <li><b>Delayed one-shots</b> via {@link #schedule} — star-shower impacts, comet
 *       telegraphs, rift closes, celebration pops. In-memory only (a stopped server simply
 *       drops pending FX; nothing world-mutating rides this queue).</li>
 *   <li><b>Feuerwelle rings</b> via {@link #startFireWave} — an expanding damage annulus
 *       marched outward over {@code expandTicks}; flame particles ride the front, every
 *       living entity is hit at most once, blocks are NEVER ignited (visual-first law).</li>
 *   <li><b>Magmasprung landings</b> via {@link #trackMagmaJump} — watches the leaping
 *       caster until touchdown, then a fire-slam AoE (fall damage is forgiven once).</li>
 * </ol>
 *
 * <p>The crash-SAFE block engine (Phasenwelle vanish/restore) deliberately does NOT live
 * here — {@link WandPhaseService} persists its schedule in SavedData; this class only
 * drives its {@code tick}/{@code restoreAllOnLoad}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WandTickService {
    private static final List<Task> TASKS = new ArrayList<>();
    private static final List<FireWave> FIRE_WAVES = new ArrayList<>();
    private static final List<MagmaJump> MAGMA_JUMPS = new ArrayList<>();

    private WandTickService() {}

    // ------------------------------------------------------------------ public API

    /** Runs {@code action} after {@code delayTicks} server ticks (skipped if the level unloads). */
    public static void schedule(ServerLevel level, int delayTicks, Runnable action) {
        TASKS.add(new Task(level, Math.max(0, delayTicks), action));
    }

    /** Starts a Feuerwelle ring march around {@code center} (see {@code WandPowers#castFeuerwelle}). */
    public static void startFireWave(ServerPlayer caster, Vec3 center, float maxRadius,
            int expandTicks, float damage, int fireTicks, float knockup) {
        FIRE_WAVES.add(new FireWave(caster.getUUID(), caster.serverLevel(), center,
                Math.max(2.0F, maxRadius), Math.max(5, expandTicks), damage, fireTicks, knockup));
    }

    /** Tracks the Magmasprung caster until landing (see {@code WandPowers#castMagmasprung}). */
    public static void trackMagmaJump(ServerPlayer caster, float damage, float radius,
            float knockback, int fireTicks) {
        MAGMA_JUMPS.add(new MagmaJump(caster.getUUID(), caster.serverLevel(), damage, radius,
                knockback, fireTicks));
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        // Crash recovery FIRST: any Phasenwelle snapshot left from a crash goes back in
        // before players (or a new wave) can touch the terrain.
        WandPhaseService.restoreAllOnLoad(event.getServer());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        TASKS.clear();
        FIRE_WAVES.clear();
        MAGMA_JUMPS.clear();
        WandPowers.clearRuntime();
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        WandPhaseService.tick(event.getServer());
        tickTasks();
        tickFireWaves();
        tickMagmaJumps();
    }

    // ------------------------------------------------------------------ delayed one-shots

    private static void tickTasks() {
        if (TASKS.isEmpty()) {
            return;
        }
        // Snapshot-run due tasks: a task may schedule follow-ups while running.
        List<Task> due = null;
        for (Iterator<Task> it = TASKS.iterator(); it.hasNext(); ) {
            Task task = it.next();
            if (--task.remaining <= 0) {
                it.remove();
                (due == null ? (due = new ArrayList<>()) : due).add(task);
            }
        }
        if (due != null) {
            for (Task task : due) {
                if (task.level.getServer().getLevel(task.level.dimension()) != task.level) {
                    continue; // level unloaded since scheduling — drop the FX quietly
                }
                try {
                    task.action.run();
                } catch (Exception e) {
                    EclipseMod.LOGGER.error("Wand scheduled task failed", e);
                }
            }
        }
    }

    private static final class Task {
        final ServerLevel level;
        final Runnable action;
        int remaining;

        Task(ServerLevel level, int delay, Runnable action) {
            this.level = level;
            this.remaining = delay;
            this.action = action;
        }
    }

    // ------------------------------------------------------------------ Feuerwelle ring

    private static void tickFireWaves() {
        for (Iterator<FireWave> it = FIRE_WAVES.iterator(); it.hasNext(); ) {
            FireWave wave = it.next();
            if (wave.tick()) {
                it.remove();
            }
        }
    }

    /**
     * One expanding flame annulus. Per tick: the ring radius advances linearly to
     * {@code maxRadius}; flame/lava particles trace the CURRENT front (a thin band, so the
     * whole effect stays within particle budget); entities whose flat distance falls inside
     * the swept band get hit once. Terrain untouched by design.
     */
    private static final class FireWave {
        final UUID casterId;
        final ServerLevel level;
        final Vec3 center;
        final float maxRadius;
        final int expandTicks;
        final float damage;
        final int fireTicks;
        final float knockup;
        final Set<Integer> hit = new HashSet<>();
        int age;
        float lastRadius;

        FireWave(UUID casterId, ServerLevel level, Vec3 center, float maxRadius, int expandTicks,
                float damage, int fireTicks, float knockup) {
            this.casterId = casterId;
            this.level = level;
            this.center = center;
            this.maxRadius = maxRadius;
            this.expandTicks = expandTicks;
            this.damage = damage;
            this.fireTicks = fireTicks;
            this.knockup = knockup;
        }

        boolean tick() {
            age++;
            float radius = maxRadius * Math.min(1.0F, age / (float) expandTicks);

            // Flame front: particle count scales with circumference, capped hard.
            int points = Math.min(48, Math.max(10, (int) (radius * 4.0F)));
            for (int i = 0; i < points; i++) {
                double angle = (i / (double) points) * Math.PI * 2.0D + age * 0.09D;
                double x = center.x + Math.cos(angle) * radius;
                double z = center.z + Math.sin(angle) * radius;
                double y = groundY(x, z);
                level.sendParticles(ParticleTypes.FLAME, x, y + 0.15D, z, 1, 0.12D, 0.05D, 0.12D, 0.015D);
                if (level.random.nextInt(6) == 0) {
                    level.sendParticles(ParticleTypes.LAVA, x, y + 0.1D, z, 1, 0.0D, 0.0D, 0.0D, 0.0D);
                }
            }
            if (age % 8 == 0) {
                level.playSound(null, center.x, center.y, center.z,
                        SoundEvents.FIRE_AMBIENT, SoundSource.PLAYERS, 0.8F, 0.8F);
            }

            // Damage: everything living whose flat distance entered [lastRadius, radius].
            ServerPlayer caster = level.getServer().getPlayerList().getPlayer(casterId);
            AABB box = new AABB(center, center).inflate(radius + 1.5D, 4.0D, radius + 1.5D);
            for (LivingEntity victim : level.getEntitiesOfClass(LivingEntity.class, box,
                    e -> e.isAlive() && e.getUUID() != casterId && !hit.contains(e.getId()))) {
                double flat = new Vec3(victim.getX() - center.x, 0.0D, victim.getZ() - center.z).length();
                if (flat > radius + 0.8D || flat < lastRadius - 1.2D
                        || Math.abs(victim.getY() - center.y) > 4.0D) {
                    continue;
                }
                hit.add(victim.getId());
                if (caster != null) {
                    WandPowers.damageAround(caster, victim.position(), 0.5F, damage, 0.0F, fireTicks);
                } else {
                    victim.hurt(level.damageSources().onFire(), damage);
                    victim.setRemainingFireTicks(Math.max(victim.getRemainingFireTicks(), fireTicks));
                }
                victim.push(0.0D, knockup, 0.0D);
            }
            lastRadius = radius;
            return age >= expandTicks;
        }

        private double groundY(double x, double z) {
            // Hug the terrain around the cast height; clamp so cliffs don't teleport the ring.
            int ix = Mth.floor(x);
            int iz = Mth.floor(z);
            double y = level.getHeight(net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING,
                    ix, iz);
            return Mth.clamp(y, center.y - 4.0D, center.y + 4.0D);
        }
    }

    // ------------------------------------------------------------------ Magmasprung landing

    private static void tickMagmaJumps() {
        for (Iterator<MagmaJump> it = MAGMA_JUMPS.iterator(); it.hasNext(); ) {
            MagmaJump jump = it.next();
            if (jump.tick()) {
                it.remove();
            }
        }
    }

    /** Waits for the caster to leave the ground, then slams on touchdown. */
    private static final class MagmaJump {
        final UUID casterId;
        final ServerLevel level;
        final float damage;
        final float radius;
        final float knockback;
        final int fireTicks;
        boolean airborne;
        int age;

        MagmaJump(UUID casterId, ServerLevel level, float damage, float radius, float knockback,
                int fireTicks) {
            this.casterId = casterId;
            this.level = level;
            this.damage = damage;
            this.radius = radius;
            this.knockback = knockback;
            this.fireTicks = fireTicks;
        }

        boolean tick() {
            age++;
            ServerPlayer caster = level.getServer().getPlayerList().getPlayer(casterId);
            if (caster == null || caster.serverLevel() != level || age > 200) {
                return true; // logout / dimension hop / 10 s safety net — no slam
            }
            if (!airborne) {
                if (!caster.onGround()) {
                    airborne = true;
                } else if (age > 10) {
                    return true; // launch never happened (headroom block) — drop quietly
                }
                return false;
            }
            if (!caster.onGround() && !caster.isInWater()) {
                if (age % 2 == 0) {
                    level.sendParticles(ParticleTypes.FLAME, caster.getX(), caster.getY(), caster.getZ(),
                            3, 0.15D, 0.1D, 0.15D, 0.01D);
                }
                return false;
            }
            // Touchdown: fire slam + fall-damage forgiveness for this one landing.
            caster.resetFallDistance();
            Vec3 impact = caster.position();
            WandPowers.damageAround(caster, impact, radius, damage, knockback, fireTicks);
            level.sendParticles(ParticleTypes.FLAME, impact.x, impact.y + 0.2D, impact.z,
                    40, radius * 0.5D, 0.2D, radius * 0.5D, 0.05D);
            level.sendParticles(ParticleTypes.LAVA, impact.x, impact.y + 0.2D, impact.z,
                    8, radius * 0.3D, 0.1D, radius * 0.3D, 0.0D);
            level.playSound(null, impact.x, impact.y, impact.z,
                    SoundEvents.GENERIC_EXPLODE.value(), SoundSource.PLAYERS, 0.7F, 1.3F);
            return true;
        }
    }
}
