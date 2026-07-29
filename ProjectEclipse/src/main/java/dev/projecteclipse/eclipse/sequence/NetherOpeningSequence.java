package dev.projecteclipse.eclipse.sequence;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.nether.NetherOpenPayloads;
import dev.projecteclipse.eclipse.network.nether.S2CNetherOpenPayload;
import dev.projecteclipse.eclipse.network.nether.S2CNetherOpenPayload.Phase;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import dev.projecteclipse.eclipse.worldgen.nether.BreachBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * THE NETHER OPENS (day 2) — the server-authoritative phase machine of the breach-opening
 * cinematic. The world-stage day trigger commits nether stage 1 on the day-2 rollover;
 * {@code BreachBuilder.onStageTerrainComplete} hands that moment to {@link #begin} instead
 * of carving straight away, so the hole is torn open in the middle of a ~47 s show rather
 * than appearing between two ticks.
 *
 * <p><b>Timeline</b> ({@code t} = ticks since {@link #begin}):</p>
 * <ol>
 *   <li>{@code OMEN} (t = 0 … {@value #OMEN_TICKS}) — the ground breathes: ash and glint
 *       particles well up out of the still-closed desert, cave/lava drones roll in, and a
 *       {@value #RUMBLE_INTERVAL_TICKS}-tick {@link Phase#RUMBLE} pulse train starts the
 *       camera shake at {@value #OMEN_SHAKE_MIN} … {@value #OMEN_SHAKE_MAX}.</li>
 *   <li>{@code TREMOR} (… {@value #TREMOR_END}) — the quake: {@link NetherUpheavalFx} kicks
 *       waves of real ground blocks loose as block displays, the client stamps
 *       {@code nether_quake_fissure} cracks around the rim, and quarry sounds roll in
 *       swells while the shake climbs to {@value #TREMOR_SHAKE_MAX}.</li>
 *   <li>{@code RUPTURE} (… {@value #RUPTURE_END}) — the pit tears open: the block-display
 *       fountain launches, {@code nether_eruption} fires, the explosion/anchor/ghast sound
 *       stack lands, and (unless this is an FX replay) {@link BreachBuilder#openNow} starts
 *       actually excavating the funnel underneath the debris.</li>
 *   <li>{@code AFTERMATH} (… {@value #TOTAL_TICKS}) — the show hands over: the swarm is
 *       released and the permanent plume takes the anchor. From here
 *       {@code client.nether.NetherPitPlume} owns the smoke-and-fire cloud, gated on the
 *       carved geometry, so it survives restarts without any new sync.</li>
 * </ol>
 *
 * <p><b>Multiplayer</b>: every beat is ONE broadcast to the overworld; the client scales
 * shake and FX by its own distance to the crater. <b>Restart</b>: a server that dies
 * mid-show comes back with {@code breachOpen} still false and {@code BreachBuilder}'s
 * bootstrap catch-up carves the crater silently — the house "a restart skips to the end
 * state" rule. <b>FX replay</b> ({@code /dev nether replay_fx}) runs the identical show with
 * {@code carve = false}: no block is written and no flag is committed.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class NetherOpeningSequence {

    // ------------------------------------------------------------------ tick table

    /** Phase 1 length (12 s). */
    public static final int OMEN_TICKS = 240;
    /** Phase 2 ends here (18 s of quake). */
    public static final int TREMOR_END = 600;
    /** Phase 3 ends here (14 s of rupture). */
    public static final int RUPTURE_END = 880;
    /** The whole sequence ends here (~47 s). */
    public static final int TOTAL_TICKS = 940;

    // ------------------------------------------------------------------ tuning constants

    /** Cadence of the {@link Phase#RUMBLE} shake pulses (ticks). */
    private static final int RUMBLE_INTERVAL_TICKS = 20;
    /** Shake amplitude band of phase 1 (before the client's own distance falloff). */
    private static final float OMEN_SHAKE_MIN = 0.10F;
    private static final float OMEN_SHAKE_MAX = 0.32F;
    /** … of phase 2 (climbing with the quake). */
    private static final float TREMOR_SHAKE_MIN = 0.34F;
    private static final float TREMOR_SHAKE_MAX = 0.80F;
    /** … of phase 3 (one full-strength hit, then a decay to the smoulder). */
    private static final float RUPTURE_SHAKE_PEAK = 1.0F;
    private static final float RUPTURE_SHAKE_TAIL = 0.22F;
    /** Ticks the rupture holds peak shake before decaying. */
    private static final int RUPTURE_SHAKE_HOLD = 70;
    /** Quake-wave pressure handed to {@link NetherUpheavalFx} at the start/end of phase 2. */
    private static final float TREMOR_PRESSURE_MIN = 0.25F;
    private static final float TREMOR_PRESSURE_MAX = 1.0F;
    /** Server-particle cadence of phase 1 / phase 2 (ticks). */
    private static final int OMEN_PARTICLE_INTERVAL = 10;
    /** Quarry-sound probe cadence in phase 2; the swell decides whether it fires. */
    private static final int QUARRY_PROBE_INTERVAL = 8;
    /** Period of the quarry swell (ticks) — sounds arrive in waves, not evenly. */
    private static final double QUARRY_SWELL_PERIOD = 70.0D;

    /** The one live sequence (one server, one opening), or {@code null}. Server thread only. */
    @Nullable
    private static Run active;

    private NetherOpeningSequence() {}

    // ------------------------------------------------------------------ public API

    /**
     * Starts the opening show. Refused (returns {@code false}) when a show is already
     * running or {@code minecraft:the_nether} is missing — callers that need the crater
     * regardless must fall back to {@link BreachBuilder#openNow}.
     *
     * @param carve {@code true} = phase 3 really excavates the funnel (the day-2 path and
     *              {@code /dev nether open}); {@code false} = FX only, no block is written
     *              and no state flag is committed ({@code /dev nether replay_fx})
     */
    public static boolean begin(MinecraftServer server, boolean carve) {
        if (active != null && active.server == server) {
            return false;
        }
        ServerLevel overworld = server.overworld();
        if (carve && server.getLevel(net.minecraft.world.level.Level.NETHER) == null) {
            EclipseMod.LOGGER.warn("Cannot open the Nether breach: minecraft:the_nether is unavailable");
            return false;
        }
        active = new Run(overworld, carve);
        EclipseMod.LOGGER.info("Nether opening sequence started at {} (carve={})",
                active.center.toShortString(), carve);
        return true;
    }

    /** Aborts the show: displays are discarded, no further beats are sent. */
    public static void abort() {
        if (active != null) {
            NetherUpheavalFx.clearAll();
            NetherUpheavalFx.setHopWavePressure(0.0F);
            active = null;
            EclipseMod.LOGGER.info("Nether opening sequence aborted");
        }
    }

    /** Whether the show is running right now (dev status / guards). */
    public static boolean isRunning() {
        return active != null;
    }

    /** Current beat for {@code /dev nether status}, or {@code null} while idle. */
    @Nullable
    public static Phase currentPhase() {
        Run run = active;
        return run == null ? null : phaseAt(run.tick);
    }

    /** Ticks elapsed in the running show, or {@code -1} while idle. */
    public static int elapsedTicks() {
        Run run = active;
        return run == null ? -1 : run.tick;
    }

    /** Whether the running show will actually carve the crater (false = FX replay). */
    public static boolean isCarving() {
        Run run = active;
        return run != null && run.carve;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        if (active != null && active.server == event.getServer()) {
            active = null;
        }
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        Run run = active;
        if (run == null || run.server != event.getServer()) {
            return;
        }
        if (run.tick()) {
            active = null;
        }
    }

    private static Phase phaseAt(int tick) {
        if (tick < OMEN_TICKS) {
            return Phase.OMEN;
        }
        if (tick < TREMOR_END) {
            return Phase.TREMOR;
        }
        if (tick < RUPTURE_END) {
            return Phase.RUPTURE;
        }
        return Phase.AFTERMATH;
    }

    // ------------------------------------------------------------------ the run

    private static final class Run {
        private final MinecraftServer server;
        private final ServerLevel overworld;
        private final boolean carve;
        private final BlockPos center;
        private final double radius;
        private final RandomSource random;

        private int tick = -1;
        @Nullable
        private Phase announced;

        private Run(ServerLevel overworld, boolean carve) {
            this.server = overworld.getServer();
            this.overworld = overworld;
            this.carve = carve;
            this.center = BreachBuilder.breachCenter();
            this.radius = BreachGeometry.CRATER_RADIUS;
            this.random = overworld.getRandom();
        }

        /** @return true once the sequence is finished and may be dropped. */
        private boolean tick() {
            this.tick++;
            Phase phase = phaseAt(this.tick);
            if (phase != this.announced) {
                this.announced = phase;
                enterPhase(phase);
            }
            switch (phase) {
                case OMEN -> tickOmen();
                case TREMOR -> tickTremor();
                case RUPTURE -> tickRupture();
                default -> tickAftermath();
            }
            if (this.tick % RUMBLE_INTERVAL_TICKS == 0) {
                broadcast(Phase.RUMBLE, shakeAt(this.tick, phase));
            }
            return this.tick >= TOTAL_TICKS;
        }

        private void enterPhase(Phase phase) {
            switch (phase) {
                case OMEN -> {
                    broadcast(Phase.OMEN, 0.0F);
                    // Deep pre-tremor drone: the mod's own rumble cue, pitched right down.
                    sound(this.center, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                            SoundSource.AMBIENT, 2.0F, 0.45F);
                    sound(this.center, SoundEvents.AMBIENT_CAVE.value(),
                            SoundSource.AMBIENT, 1.6F, 0.42F);
                }
                case TREMOR -> {
                    broadcast(Phase.TREMOR, 0.0F);
                    NetherUpheavalFx.setHopWavePressure(TREMOR_PRESSURE_MIN);
                    NetherUpheavalFx.beginTremor(this.overworld, this.center, this.radius);
                    sound(this.center, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                            SoundSource.AMBIENT, 2.0F, 0.6F);
                }
                case RUPTURE -> {
                    broadcast(Phase.RUPTURE, 0.0F);
                    NetherUpheavalFx.setHopWavePressure(0.0F); // the fountain takes over
                    NetherUpheavalFx.erupt(this.overworld, this.center, this.radius);
                    // The user's ask, verbatim: explosion + respawn anchor + ghast.
                    sound(this.center, SoundEvents.GENERIC_EXPLODE.value(),
                            SoundSource.BLOCKS, 4.0F, 0.5F);
                    sound(this.center, SoundEvents.RESPAWN_ANCHOR_DEPLETE.value(),
                            SoundSource.BLOCKS, 3.0F, 0.5F);
                    sound(this.center, SoundEvents.GHAST_SCREAM,
                            SoundSource.HOSTILE, 3.0F, 0.55F);
                    // FX-12: the Veil radial-distortion ring the rupture never had (the
                    // End-arrival finale idiom). 0.9/45 stays clear of the reserved
                    // (>=1.0, >=50) intro-burst giant signature; dimension-wide (-1) so
                    // the shock reads for everyone the phase broadcast reaches.
                    FxPayloads.sendFxEvent(this.overworld, FxPayloads.FX_SHOCKWAVE,
                            Vec3.atCenterOf(this.center), 0.9F, 45.0F, -1.0D);
                    this.overworld.sendParticles(ParticleTypes.EXPLOSION_EMITTER,
                            this.center.getX() + 0.5D, this.center.getY() + 2.0D,
                            this.center.getZ() + 0.5D, 3, this.radius * 0.4D, 1.0D,
                            this.radius * 0.4D, 0.0D);
                    if (this.carve) {
                        // The real excavation starts UNDER the debris (its own budgeted job,
                        // with its own QUAKE/OPEN/SETTLED breach payloads + storm moment).
                        BreachBuilder.openNow(this.overworld);
                    }
                }
                default -> {
                    broadcast(Phase.AFTERMATH, 0.0F);
                    NetherUpheavalFx.release();
                    sound(this.center, SoundEvents.RESPAWN_ANCHOR_DEPLETE.value(),
                            SoundSource.AMBIENT, 1.4F, 0.4F);
                }
            }
        }

        // --- per-phase server ambience (the photon-less baseline: everyone sees this) ---

        private void tickOmen() {
            if (this.tick % OMEN_PARTICLE_INTERVAL != 0) {
                return;
            }
            for (int i = 0; i < 5; i++) {
                double angle = this.random.nextDouble() * Math.PI * 2.0D;
                double dist = Math.sqrt(this.random.nextDouble()) * this.radius;
                double x = this.center.getX() + 0.5D + Math.cos(angle) * dist;
                double z = this.center.getZ() + 0.5D + Math.sin(angle) * dist;
                this.overworld.sendParticles(ParticleTypes.ASH, x, this.center.getY() + 1.2D, z,
                        3, 0.6D, 0.4D, 0.6D, 0.01D);
                this.overworld.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                        x, this.center.getY() + 0.8D, z, 1, 0.4D, 0.1D, 0.4D, 0.008D);
                if (this.random.nextFloat() < 0.35F) {
                    this.overworld.sendParticles(ParticleTypes.LAVA, x, this.center.getY() + 0.6D,
                            z, 1, 0.15D, 0.05D, 0.15D, 0.0D);
                }
            }
            if (this.tick % 60 == 0) {
                sound(this.center, SoundEvents.LAVA_AMBIENT, SoundSource.AMBIENT, 1.6F, 0.5F);
            }
        }

        private void tickTremor() {
            float progress = (this.tick - OMEN_TICKS) / (float) (TREMOR_END - OMEN_TICKS);
            NetherUpheavalFx.setHopWavePressure(Mth.lerp(progress,
                    TREMOR_PRESSURE_MIN, TREMOR_PRESSURE_MAX));
            if (this.tick % OMEN_PARTICLE_INTERVAL == 0) {
                for (int i = 0; i < 6; i++) {
                    double angle = this.random.nextDouble() * Math.PI * 2.0D;
                    double dist = Math.sqrt(this.random.nextDouble()) * this.radius;
                    double x = this.center.getX() + 0.5D + Math.cos(angle) * dist;
                    double z = this.center.getZ() + 0.5D + Math.sin(angle) * dist;
                    this.overworld.sendParticles(ParticleTypes.LARGE_SMOKE,
                            x, this.center.getY() + 1.0D, z, 2, 0.5D, 0.3D, 0.5D, 0.02D);
                    this.overworld.sendParticles(ParticleTypes.SMALL_FLAME,
                            x, this.center.getY() + 0.7D, z, 1, 0.3D, 0.1D, 0.3D, 0.005D);
                }
            }
            if (this.tick % QUARRY_PROBE_INTERVAL != 0) {
                return;
            }
            // Quarry sounds in swells: the wave decides how likely the next crack is.
            double swell = 0.5D + 0.5D * Math.sin(this.tick / QUARRY_SWELL_PERIOD * Math.PI * 2.0D);
            if (this.random.nextDouble() > swell * (0.35D + 0.65D * progress)) {
                return;
            }
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double dist = this.random.nextDouble() * this.radius;
            BlockPos at = new BlockPos(
                    (int) Math.round(this.center.getX() + Math.cos(angle) * dist),
                    this.center.getY(),
                    (int) Math.round(this.center.getZ() + Math.sin(angle) * dist));
            sound(at, this.random.nextBoolean() ? SoundEvents.DEEPSLATE_BREAK
                            : SoundEvents.STONE_BREAK,
                    SoundSource.BLOCKS, 2.4F, 0.45F + this.random.nextFloat() * 0.2F);
        }

        private void tickRupture() {
            int local = this.tick - TREMOR_END;
            // Aftershock stack: two echoes behind the main hit, then a fading ghast wail.
            if (local == 18) {
                sound(this.center, SoundEvents.GENERIC_EXPLODE.value(),
                        SoundSource.BLOCKS, 2.6F, 0.42F);
            } else if (local == 46) {
                sound(this.center, SoundEvents.GHAST_WARN, SoundSource.HOSTILE, 2.4F, 0.5F);
            } else if (local == 120) {
                sound(this.center, EclipseSounds.EVENT_END_SHATTER_RUMBLE.get(),
                        SoundSource.AMBIENT, 2.0F, 0.5F);
            }
            if (this.tick % 4 != 0) {
                return;
            }
            double falloff = Math.max(0.15D, 1.0D - local / (double) (RUPTURE_END - TREMOR_END));
            int count = (int) Math.ceil(8 * falloff);
            for (int i = 0; i < count; i++) {
                double angle = this.random.nextDouble() * Math.PI * 2.0D;
                double dist = Math.sqrt(this.random.nextDouble()) * this.radius * 0.8D;
                double x = this.center.getX() + 0.5D + Math.cos(angle) * dist;
                double z = this.center.getZ() + 0.5D + Math.sin(angle) * dist;
                this.overworld.sendParticles(ParticleTypes.FLAME, x, this.center.getY() + 1.5D, z,
                        2, 0.4D, 0.3D, 0.4D, 0.25D * falloff);
                this.overworld.sendParticles(ParticleTypes.LARGE_SMOKE,
                        x, this.center.getY() + 2.5D, z, 3, 0.8D, 0.6D, 0.8D, 0.12D);
                this.overworld.sendParticles(ParticleTypes.LAVA, x, this.center.getY() + 1.0D, z,
                        1, 0.3D, 0.2D, 0.3D, 0.0D);
            }
        }

        private void tickAftermath() {
            if (this.tick % 20 != 0) {
                return;
            }
            for (int i = 0; i < 4; i++) {
                double angle = this.random.nextDouble() * Math.PI * 2.0D;
                double dist = this.random.nextDouble() * this.radius * 0.7D;
                this.overworld.sendParticles(ParticleTypes.LARGE_SMOKE,
                        this.center.getX() + 0.5D + Math.cos(angle) * dist,
                        this.center.getY() + 3.0D,
                        this.center.getZ() + 0.5D + Math.sin(angle) * dist,
                        2, 0.8D, 0.5D, 0.8D, 0.03D);
            }
        }

        /** Shake amplitude for this tick before the client's own distance falloff. */
        private float shakeAt(int tick, Phase phase) {
            return switch (phase) {
                case OMEN -> Mth.lerp(tick / (float) OMEN_TICKS, OMEN_SHAKE_MIN, OMEN_SHAKE_MAX);
                case TREMOR -> Mth.lerp((tick - OMEN_TICKS) / (float) (TREMOR_END - OMEN_TICKS),
                        TREMOR_SHAKE_MIN, TREMOR_SHAKE_MAX);
                case RUPTURE -> {
                    int local = tick - TREMOR_END;
                    yield local <= RUPTURE_SHAKE_HOLD ? RUPTURE_SHAKE_PEAK
                            : Mth.lerp((local - RUPTURE_SHAKE_HOLD)
                                            / (float) (RUPTURE_END - TREMOR_END - RUPTURE_SHAKE_HOLD),
                                    RUPTURE_SHAKE_PEAK, RUPTURE_SHAKE_TAIL);
                }
                default -> RUPTURE_SHAKE_TAIL * 0.5F;
            };
        }

        private void broadcast(Phase phase, float intensity) {
            NetherOpenPayloads.send(this.overworld,
                    new S2CNetherOpenPayload(phase, this.center, intensity));
        }

        private void sound(BlockPos at, SoundEvent sound, SoundSource source, float volume,
                float pitch) {
            this.overworld.playSound(null, at, sound, source, volume, pitch);
        }
    }
}
