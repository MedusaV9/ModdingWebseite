package dev.projecteclipse.eclipse.veilfx.rift;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client-side registry + lifecycle of dimensional <b>rift tears</b> (P2 R17 + the W7/W9
 * structure/reveal beats). The two entry points below are the FROZEN handlers dispatched by
 * {@code network/fx/FxPayloads} for the {@code eclipse:fx/rift_open} / {@code
 * eclipse:fx/rift_close} events — signatures must not change (P5-W9's xbox portal and
 * P2-W7's structure drops send those payloads):
 * <ul>
 *   <li>{@link #openRift(Vec3, Vec3, float, int, int)} — {@code pos} = tear center,
 *       {@code normal} = tear plane normal ({@code FxPayloads} passes {@code (0,1,0)};
 *       PORTAL-style rifts re-orient themselves upright, see below), {@code width} = full
 *       tear diameter in blocks, {@code durationTicks} = auto-close delay ({@code 0} = stay
 *       open until {@link #closeRift}), {@code style} = {@link #STYLE_STRUCTURE} /
 *       {@link #STYLE_PORTAL}.</li>
 *   <li>{@link #closeRift(Vec3)} — collapses the rift nearest to {@code pos} (tolerance
 *       {@code max(4, width)} blocks) over {@value #CLOSE_TICKS} ticks.</li>
 * </ul>
 *
 * <p>Each rift is a seeded star-polygon tear ({@value #MIN_ARMS}&ndash;{@value #MAX_ARMS}
 * arms, arm lengths eased out over {@value #OPEN_TICKS} ticks) rendered by
 * {@link RiftRenderer} (world-space geometry — deliberately NOT Iris-gated, it is the
 * shaderpack fallback per §7), plus:</p>
 * <ul>
 *   <li>an {@code eclipse:rift_spark} loop emitter that walks the tear rim every client
 *       tick (edge crackle),</li>
 *   <li>for {@link #STYLE_PORTAL}: an {@code eclipse:portal_surface_motes} loop emitter at
 *       the center (motes swirled + sucked inward via reverse {@code veil:vortex} +
 *       {@code veil:point_attractor}),</li>
 *   <li>a distance-scaled {@link TransitionFx#glitchPulse(float, int)} screen pulse
 *       (≤ {@value #MAX_PULSE} per R11) and the {@code event.rift_open} crackle sound.</li>
 * </ul>
 *
 * <p><b>Portal orientation:</b> the FX payload carries no plane normal, so W1's dispatch
 * hard-codes up. A flat-lying portal reads wrong, so when {@code style == STYLE_PORTAL} and
 * the normal is (near) vertical, the rift re-orients to an upright plane facing the local
 * camera at open time (frozen thereafter; falls back to +Z with no camera). STRUCTURE rifts
 * keep the up normal — they open flat in the sky above the build site (R11).</p>
 *
 * <p>Lifecycle safety: at most {@value #MAX_RIFTS} concurrent rifts (oldest evicted);
 * re-opening within half a width of a live rift replaces it (double-send/resync safe);
 * rifts die instantly on dimension change (their emitters die with the level) and on
 * logout. Loop-emitter handles are managed exactly like {@code LimboAmbience}'s motes:
 * kept, pruned when Veil removes them, {@code remove()}d when the rift closes.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RiftFx {
    /** Structure-drop style (R11): bare tear, no portal surface. */
    public static final int STYLE_STRUCTURE = 0;
    /** Xbox-event portal style (R17): tear + elliptical parallax portal surface + motes. */
    public static final int STYLE_PORTAL = 1;

    /** Arm-length ease-out length when opening (R17: "arm length ease-out over 20 ticks"). */
    static final int OPEN_TICKS = 20;
    /** Collapse length when closing (R11: "rift closes 30 ticks"). */
    static final int CLOSE_TICKS = 30;
    static final int MIN_ARMS = 8;
    static final int MAX_ARMS = 14;

    /** Concurrent rift cap — the renderer's ≤400-tri budget is per rift, this bounds the sum. */
    private static final int MAX_RIFTS = 8;
    private static final float MIN_WIDTH = 1.5F;
    private static final float MAX_WIDTH = 48.0F;
    /** Screen-glitch pulse ceiling (R11 freezes "rift_glitch pulse ≤ 0.5"). */
    private static final float MAX_PULSE = 0.5F;
    /** Full-strength pulse/sound radius; both fade to zero at {@value #PULSE_FALLOFF_BLOCKS}. */
    private static final double PULSE_FULL_BLOCKS = 16.0D;
    private static final double PULSE_FALLOFF_BLOCKS = 64.0D;
    /** Re-try cadence for budget-refused loop emitters (once a second, never per-tick hammering). */
    private static final int EMITTER_RETRY_TICKS = 20;

    private static final ResourceLocation RIFT_SPARK_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_spark");
    private static final ResourceLocation PORTAL_MOTES_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "portal_surface_motes");

    /** Live rifts, oldest first. Mutated only on the client main thread (payloads + tick). */
    private static final List<Rift> RIFTS = new ArrayList<>(MAX_RIFTS);

    /**
     * Client tick counter for rift animation. {@code EclipseFxState.clientTicks()} is
     * package-private to {@code veilfx}, so this subpackage keeps its own counter off the
     * same event — the two advance in lockstep.
     */
    private static int ticks;

    private RiftFx() {}

    // ------------------------------------------------------------------ frozen entry points

    /**
     * Opens (or replaces) a rift tear. FROZEN signature — called by {@code FxPayloads} for
     * {@code eclipse:fx/rift_open} with {@code normal = (0,1,0)}, {@code durationTicks = 0}
     * (stay open until {@link #closeRift}) and {@code style = (int) b}.
     */
    public static void openRift(Vec3 pos, Vec3 normal, float width, int durationTicks, int style) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            return;
        }
        width = Mth.clamp(width <= 0.0F ? 6.0F : width, MIN_WIDTH, MAX_WIDTH);

        // Double-send/login-resync safe: an open on top of a live rift replaces it silently.
        Rift existing = findNearest(pos, Math.max(2.0D, width * 0.5D), true);
        if (existing != null) {
            dispose(existing);
            RIFTS.remove(existing);
        }
        while (RIFTS.size() >= MAX_RIFTS) {
            dispose(RIFTS.remove(0));
        }

        RIFTS.add(new Rift(level.dimension(), pos, orientedNormal(minecraft, pos, normal, style),
                width, durationTicks, style, ticks));

        float falloff = distanceFalloff(minecraft, pos);
        TransitionFx.glitchPulse(Math.min(MAX_PULSE, (0.28F + width * 0.012F) * falloff), 14);
        if (falloff > 0.0F) {
            level.playLocalSound(pos.x, pos.y, pos.z, EclipseSounds.EVENT_RIFT_OPEN.get(),
                    SoundSource.BLOCKS, 0.55F + 0.45F * falloff, 0.95F + level.random.nextFloat() * 0.1F, false);
        }
    }

    /**
     * Starts the {@value #CLOSE_TICKS}-tick collapse of the rift nearest to {@code pos}
     * (tolerance {@code max(4, width)} blocks). FROZEN signature — called by
     * {@code FxPayloads} for {@code eclipse:fx/rift_close}. A miss is a debug no-op:
     * close events for already-evicted/expired rifts are expected during resyncs.
     */
    public static void closeRift(Vec3 pos) {
        Rift rift = findNearest(pos, -1.0D, false);
        if (rift == null) {
            EclipseMod.LOGGER.debug("rift_close at {} matched no open rift", pos);
            return;
        }
        beginClose(rift);
    }

    // ------------------------------------------------------------------ renderer/tick access

    /** Live rifts for {@link RiftRenderer} (render-thread read only; do not mutate). */
    static List<Rift> rifts() {
        return RIFTS;
    }

    /** Shared animation clock ({@code ticks + partialTick}). */
    static float timeNow(float partialTick) {
        return ticks + partialTick;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        ticks++;
        if (RIFTS.isEmpty()) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            clearAll();
            return;
        }
        for (int i = RIFTS.size() - 1; i >= 0; i--) {
            Rift rift = RIFTS.get(i);
            if (rift.dimension != level.dimension() || rift.doneClosing(ticks)) {
                dispose(rift);
                RIFTS.remove(i);
                continue;
            }
            if (!rift.closing() && rift.durationTicks > 0 && ticks - rift.openTick >= rift.durationTicks) {
                beginClose(rift);
                continue;
            }
            rift.tickEmitters(level, ticks);
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clearAll();
    }

    private static void beginClose(Rift rift) {
        rift.startClose(ticks);
        Minecraft minecraft = Minecraft.getInstance();
        float falloff = distanceFalloff(minecraft, rift.pos);
        TransitionFx.glitchPulse(Math.min(MAX_PULSE, 0.22F * falloff + 0.05F), 12);
        ClientLevel level = minecraft.level;
        if (level != null && falloff > 0.0F) {
            // Reverse-crackle read on the same registered sound — §3.5's frozen sound list
            // has no dedicated close event (the W7 slam beat is the sender's job).
            level.playLocalSound(rift.pos.x, rift.pos.y, rift.pos.z, EclipseSounds.EVENT_RIFT_OPEN.get(),
                    SoundSource.BLOCKS, 0.45F + 0.35F * falloff, 0.65F, false);
        }
    }

    /**
     * Nearest live rift to {@code pos}; {@code tolerance < 0} uses each rift's own
     * {@code max(4, width)}. {@code includeClosing = false} skips rifts already collapsing
     * (a close event must never be swallowed by a neighbor that is already closing).
     */
    @Nullable
    private static Rift findNearest(Vec3 pos, double tolerance, boolean includeClosing) {
        Rift best = null;
        double bestDistSq = Double.MAX_VALUE;
        for (int i = 0; i < RIFTS.size(); i++) {
            Rift rift = RIFTS.get(i);
            if (!includeClosing && rift.closing()) {
                continue;
            }
            double limit = tolerance >= 0.0D ? tolerance : Math.max(4.0D, rift.width);
            double distSq = rift.pos.distanceToSqr(pos);
            if (distSq <= limit * limit && distSq < bestDistSq) {
                bestDistSq = distSq;
                best = rift;
            }
        }
        return best;
    }

    /**
     * PORTAL rifts arriving with the payload's default up-normal are stood upright facing
     * the local camera at open time (see class javadoc); every other normal passes through
     * normalized. Zero-length normals fall back to up.
     */
    private static Vec3 orientedNormal(Minecraft minecraft, Vec3 pos, Vec3 normal, int style) {
        if (style == STYLE_PORTAL && Math.abs(normal.y) > 0.9D * normal.length()) {
            Vec3 toCamera = minecraft.gameRenderer.getMainCamera().getPosition().subtract(pos);
            Vec3 flat = new Vec3(toCamera.x, 0.0D, toCamera.z);
            return flat.lengthSqr() > 1.0E-4D ? flat.normalize() : new Vec3(0.0D, 0.0D, 1.0D);
        }
        return normal.lengthSqr() > 1.0E-6D ? normal.normalize() : new Vec3(0.0D, 1.0D, 0.0D);
    }

    /** 1 within {@value #PULSE_FULL_BLOCKS} blocks of the camera, 0 beyond {@value #PULSE_FALLOFF_BLOCKS}. */
    private static float distanceFalloff(Minecraft minecraft, Vec3 pos) {
        double dist = minecraft.gameRenderer.getMainCamera().getPosition().distanceTo(pos);
        return (float) Mth.clamp(1.0D - (dist - PULSE_FULL_BLOCKS) / (PULSE_FALLOFF_BLOCKS - PULSE_FULL_BLOCKS),
                0.0D, 1.0D);
    }

    private static void dispose(Rift rift) {
        rift.removeEmitters();
    }

    private static void clearAll() {
        for (int i = 0; i < RIFTS.size(); i++) {
            RIFTS.get(i).removeEmitters();
        }
        RIFTS.clear();
    }

    // ------------------------------------------------------------------ rift state

    /**
     * One live tear. Geometry inputs are precomputed at construction (seeded star polygon +
     * orthonormal plane basis stored as primitive floats) so {@link RiftRenderer} runs with
     * zero per-frame allocations.
     */
    static final class Rift {
        final ResourceKey<Level> dimension;
        final Vec3 pos;
        final float width;
        final int durationTicks;
        final int style;
        /** Per-rift hash salt for the renderer's flicker jitter. */
        final int seed;
        final int armCount;
        /** Star tip angles (radians, in-plane) and tip/valley radius multipliers. */
        final float[] armAngle;
        final float[] armLength;
        final float[] valleyRadius;
        /** Orthonormal tear-plane basis: n = normal, t/b span the plane. */
        final float nx;
        final float ny;
        final float nz;
        final float tx;
        final float ty;
        final float tz;
        final float bx;
        final float by;
        final float bz;

        final int openTick;
        /** Tick the collapse started, or {@code -1} while open. */
        private int closeTick = -1;
        /** Open amount captured at close start so a mid-open close collapses from there. */
        private float amountAtClose = 1.0F;

        @Nullable
        private ParticleEmitter sparkEmitter;
        @Nullable
        private ParticleEmitter motesEmitter;
        /** Ticks until the next loop-emitter (re)spawn attempt after a budget refusal. */
        private int emitterRetryCooldown;

        private Rift(ResourceKey<Level> dimension, Vec3 pos, Vec3 normal, float width,
                int durationTicks, int style, int openTick) {
            this.dimension = dimension;
            this.pos = pos;
            this.width = width;
            this.durationTicks = Math.max(0, durationTicks);
            this.style = style;
            this.openTick = openTick;
            // Position-derived seed: the payload coordinates are bit-identical on every
            // client, so all players see the same tear shape.
            this.seed = 31 * (31 * Double.hashCode(pos.x) + Double.hashCode(pos.y)) + Double.hashCode(pos.z);

            RandomSource shape = RandomSource.create(this.seed);
            this.armCount = MIN_ARMS + shape.nextInt(MAX_ARMS - MIN_ARMS + 1);
            this.armAngle = new float[this.armCount];
            this.armLength = new float[this.armCount];
            this.valleyRadius = new float[this.armCount];
            float step = (float) (Math.PI * 2.0D) / this.armCount;
            for (int i = 0; i < this.armCount; i++) {
                this.armAngle[i] = i * step + (shape.nextFloat() - 0.5F) * step * 0.55F;
                this.armLength[i] = 0.72F + shape.nextFloat() * 0.28F;
                this.valleyRadius[i] = 0.30F + shape.nextFloat() * 0.16F;
            }

            this.nx = (float) normal.x;
            this.ny = (float) normal.y;
            this.nz = (float) normal.z;
            // Plane basis: cross the normal with the axis it is least aligned with.
            Vec3 helper = Math.abs(normal.y) < 0.9D ? new Vec3(0.0D, 1.0D, 0.0D) : new Vec3(1.0D, 0.0D, 0.0D);
            Vec3 tangent = helper.cross(normal).normalize();
            Vec3 bitangent = normal.cross(tangent);
            this.tx = (float) tangent.x;
            this.ty = (float) tangent.y;
            this.tz = (float) tangent.z;
            this.bx = (float) bitangent.x;
            this.by = (float) bitangent.y;
            this.bz = (float) bitangent.z;
        }

        /** Tear scale in [0,1]: cubic ease-out while opening, hold-then-snap collapse while closing. */
        float openAmount(float now) {
            if (this.closeTick >= 0) {
                float t = Mth.clamp((now - this.closeTick) / CLOSE_TICKS, 0.0F, 1.0F);
                return this.amountAtClose * (1.0F - t * t * t);
            }
            float t = Mth.clamp((now - this.openTick) / OPEN_TICKS, 0.0F, 1.0F);
            float inv = 1.0F - t;
            return 1.0F - inv * inv * inv;
        }

        boolean closing() {
            return this.closeTick >= 0;
        }

        private boolean doneClosing(int now) {
            return this.closeTick >= 0 && now - this.closeTick >= CLOSE_TICKS;
        }

        private void startClose(int now) {
            this.amountAtClose = openAmount(now);
            this.closeTick = now;
        }

        /**
         * Keeps the loop emitters alive and walks the spark emitter along the tear rim (one
         * random rim point per tick — the crackle follows the edge at any width without
         * per-width emitter JSONs). Budget refusals retry once a second.
         */
        private void tickEmitters(ClientLevel level, int now) {
            if (this.closeTick >= 0) {
                // Collapsing: stop feeding new sparks/motes, keep what is airborne.
                removeEmitters();
                return;
            }
            if (this.emitterRetryCooldown > 0) {
                this.emitterRetryCooldown--;
            }
            boolean sparkDead = this.sparkEmitter == null || isRemovedSafe(this.sparkEmitter);
            boolean motesDead = this.style == STYLE_PORTAL
                    && (this.motesEmitter == null || isRemovedSafe(this.motesEmitter));
            if ((sparkDead || motesDead) && this.emitterRetryCooldown <= 0) {
                this.emitterRetryCooldown = EMITTER_RETRY_TICKS;
                if (sparkDead) {
                    this.sparkEmitter = QuasarSpawner.spawnManaged(RIFT_SPARK_EMITTER, this.pos,
                            FxBudget.Channel.SEQUENCE);
                }
                if (motesDead) {
                    this.motesEmitter = QuasarSpawner.spawnManaged(PORTAL_MOTES_EMITTER, this.pos,
                            FxBudget.Channel.SEQUENCE);
                }
            }
            ParticleEmitter spark = this.sparkEmitter;
            if (spark != null && !isRemovedSafe(spark)) {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double radius = this.width * 0.5D * 0.95D * openAmount(now);
                double cos = Math.cos(angle) * radius;
                double sin = Math.sin(angle) * radius;
                try {
                    spark.setPosition(new Vec3(
                            this.pos.x + this.tx * cos + this.bx * sin,
                            this.pos.y + this.ty * cos + this.by * sin,
                            this.pos.z + this.tz * cos + this.bz * sin));
                } catch (Throwable t) {
                    this.sparkEmitter = null; // Veil rejected the handle — next second re-spawns
                }
            }
        }

        private void removeEmitters() {
            removeQuietly(this.sparkEmitter);
            removeQuietly(this.motesEmitter);
            this.sparkEmitter = null;
            this.motesEmitter = null;
        }

        private static boolean isRemovedSafe(ParticleEmitter emitter) {
            try {
                return emitter.isRemoved();
            } catch (Throwable t) {
                return true;
            }
        }

        private static void removeQuietly(@Nullable ParticleEmitter emitter) {
            if (emitter == null) {
                return;
            }
            try {
                if (!emitter.isRemoved()) {
                    emitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (QuasarSpawner.clearAttached pattern): dropping the
                // reference is the part that matters.
            }
        }
    }
}
