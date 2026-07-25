package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.light.data.PointLightData;
import foundry.veil.api.client.render.light.renderer.LightRenderHandle;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client-side storm state + FX orchestration (P2 W9, R14/R15). Owns the live storm list the
 * {@link StormWallRenderer} draws and the {@link StormInteriorFx} reads, plus every non-mesh
 * effect: lightning bolts, shell arc flashes, vortex wisp emitters and the positional storm
 * churn loop.
 *
 * <p><b>Frozen entry points</b> (called by {@code network.fx.FxPayloads}):</p>
 * <ul>
 *   <li>{@link #handle(S2CStormStatePayload)} — storm lifecycle. SPAWN semantics: {@code ticks
 *       <= }{@link StormRegistry#RAMP_TICKS} is a plain fade/scale-in (the intro vortex's
 *       {@code SPAWN 80}); {@code ticks > RAMP_TICKS} is reveal-style — the storm holds
 *       invisible, pulses a 0.4 {@code rift_glitch} at the end of the
 *       {@link StormRegistry#REVEAL_PAUSE_TICKS pause} (via {@link TransitionFx#glitchPulse}),
 *       waits through the server-driven hammer strikes and ramps its shells over the LAST
 *       {@link StormRegistry#RAMP_TICKS} ticks. The payload field is {@code stormType()}
 *       (record component {@code type} would clash with {@code CustomPacketPayload#type()}).</li>
 *   <li>{@link #strikeLightning(Vec3, Vec3, float)} — a 6-segment jittered ribbon bolt with a
 *       2-tick white core, 6-tick violet decay, impact flash and ONE {@link FxBudget#tryLight
 *       budgeted} point light. No sound here by design: strike audio is the sender's job
 *       (W1 wiring table — W6 plays the giant crack, {@link StormReveal} plays reveal cracks).</li>
 * </ul>
 *
 * <p>Ambient beats (client-scheduled, all through {@link FxBudget.Channel#STORM}): shell arc
 * flashes every 20–60 ticks per storm inside near-LOD range (small surface bolts + a
 * {@code eclipse:storm_arc} burst + a quiet local {@code event.lightning_far}), three spiraling
 * {@code eclipse:vortex_wisp} loop emitters per vortex storm (positions swirled 0.35 rad/s by
 * this class — size-agnostic, unlike a baked JSON vortex radius), and one positional
 * {@code event.storm_loop} instance per storm that tracks the nearest shell point.</p>
 *
 * <p>Storms carry no dimension on the wire: the client list always belongs to the CURRENT
 * level and is wiped on respawn/dimension change ({@link ClientPlayerNetworkEvent.Clone}) and
 * disconnect — {@link StormRegistry} re-syncs the new dimension's storms right after.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormFxClient {
    private static final ResourceLocation STORM_ARC_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_arc");
    private static final ResourceLocation VORTEX_WISP_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "vortex_wisp");
    /**
     * FX-STORM explosion stage 3 support: the {@code border_glitch} strobing-alpha burst
     * IS the "wall fragments dissolve as glitch voxels" read — reused, not duplicated.
     */
    private static final ResourceLocation EXPLOSION_GLITCH_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border_glitch");

    /** Shell arc-flash cadence (R14: "shell-surface arc flashes every 20–60 ticks per storm"). */
    private static final int ARC_MIN_INTERVAL = 20;
    private static final int ARC_MAX_INTERVAL = 60;
    /** Arc flashes/wisps only run while the camera is inside near-LOD range of the shell. */
    private static final float ARC_RANGE = 160.0F;
    /** Lightning bolt lifetime: 2-tick white core + 6-tick violet decay (R14). */
    static final int BOLT_LIFE_TICKS = 8;
    /** Shell arc flash lifetime (short crackle). */
    static final int ARC_LIFE_TICKS = 5;
    /** Live bolt/arc caps — strikes beyond these replace the oldest entry. */
    private static final int MAX_BOLTS = 8;
    private static final int MAX_ARCS = 6;
    /** Vortex wisp emitters per storm (each is rate 3 / count 2 — well inside STORM budget). */
    private static final int MAX_WISPS = 3;
    /** Swirl speed 0.35 rad/s (R14 vortex spec) at 20 ticks/s. */
    private static final float SWIRL_RAD_PER_TICK = 0.0175F;
    /** Wisp vertical drift per tick (wraps inside the storm height). */
    private static final float WISP_RISE_PER_TICK = 0.12F;
    /**
     * PH-WORLD (IDEAS-world #8): crown-halo release distance — attach inside
     * {@link #ARC_RANGE}, release only beyond +20 (hysteresis, no boundary thrash).
     */
    private static final float CROWN_RELEASE_RANGE = ARC_RANGE + 20.0F;
    /** Crown-halo refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
    private static final int CROWN_RETRY_TICKS = 40;
    /** Crown halo height above the shell top (IDEAS-world #8: center + [0, height+2, 0]). */
    private static final double CROWN_ABOVE_SHELL = 2.0D;
    /** Storm loop sound audibility: start within this distance of the shell (sound range is 64). */
    private static final float LOOP_SOUND_RANGE = 56.0F;
    /** Reveal glitch pulse strength (R14: "rift_glitch pulse 0.4"). */
    private static final float REVEAL_GLITCH_STRENGTH = 0.4F;

    // IDEA-15 §1 approach dread ladder: heartbeat + ground-fog tendrils at 60/40/20 blocks.
    /** Heartbeat band — the storm reaches for you before the churn loop fades in at 56. */
    private static final float DREAD_FAR = 60.0F;
    /** Ground tendrils crawl out from the wall base inside this shell distance. */
    private static final float DREAD_MID = 40.0F;
    /** Tendrils reach the player's feet and the heartbeat doubles inside this distance. */
    private static final float DREAD_NEAR = 20.0F;
    /** Heartbeat cadence tightens 50 → 22 ticks over the 60→20 approach. */
    private static final int HEARTBEAT_SLOW_TICKS = 50;
    private static final int HEARTBEAT_FAST_TICKS = 22;
    /** Second thump of the ≤20-block double heartbeat, this many ticks after the first. */
    private static final int HEARTBEAT_ECHO_TICKS = 6;

    /** Live storms of the current client level (tiny list; index-iterated, no iterators in render). */
    private static final List<ClientStorm> STORMS = new ArrayList<>(4);
    /** Live lightning bolts (sky→impact ribbons). */
    private static final List<Bolt> BOLTS = new ArrayList<>(MAX_BOLTS);
    /** Live shell-surface arc crackles (small bolts pinned to a storm shell). */
    private static final List<Bolt> ARCS = new ArrayList<>(MAX_ARCS);

    /** Client tick counter — the shared FX clock for every storm ramp (advances while playing). */
    private static int clientTicks;

    private StormFxClient() {}

    // ------------------------------------------------------------------ frozen entry points

    /** {@code S2CStormStatePayload} dispatch (client main thread — see {@code FxPayloads}). */
    public static void handle(S2CStormStatePayload payload) {
        ClientStorm storm = find(payload.stormId());
        int state = payload.state();
        Vec3 center = payload.center();
        float radius = Math.max(2.0F, payload.radius());
        float height = payload.height() > 0.0F ? payload.height() : StormRegistry.heightFor(radius);
        int type = payload.stormType();
        if (storm != null && state == storm.state) {
            if (storm.center.equals(center) && Float.compare(storm.radius, radius) == 0
                    && Float.compare(storm.height, height) == 0 && storm.type == type) {
                return;
            }
            storm.center = center;
            storm.radius = radius;
            storm.height = height;
            storm.type = type;
            return;
        }
        if (storm == null) {
            if (state == S2CStormStatePayload.STATE_DISSIPATE
                    || state == S2CStormStatePayload.STATE_EXPLODE) {
                return; // never knew it — nothing to fade out / blow up
            }
            storm = new ClientStorm(payload.stormId());
            STORMS.add(storm);
        }
        if (state == S2CStormStatePayload.STATE_EXPLODE
                && storm.state != S2CStormStatePayload.STATE_EXPLODE) {
            // C8 death beat: 15t white-out — full inside the shell, feathering to nothing
            // ~60 blocks out. Debris/expansion run off the state below; audio is server-sent.
            Minecraft minecraft = Minecraft.getInstance();
            if (minecraft.level != null) {
                Vec3 cam = minecraft.gameRenderer.getMainCamera().getPosition();
                double dx = cam.x - center.x;
                double dz = cam.z - center.z;
                double shellDist = Math.sqrt(dx * dx + dz * dz) - radius;
                float strength = shellDist <= 0.0D ? 1.0F
                        : 1.0F - (float) Math.min(1.0D, shellDist / 60.0D);
                StormInteriorFx.explodeWhiteout(strength);
            }
        }
        storm.center = center;
        storm.radius = radius;
        storm.height = height;
        storm.type = type;
        storm.state = state;
        storm.stateStartTick = clientTicks;
        storm.stateTicks = Math.max(1, payload.ticks());
        storm.revealStyle = state == S2CStormStatePayload.STATE_SPAWN
                && payload.ticks() > StormRegistry.RAMP_TICKS;
        storm.glitchStarted = false;
        storm.nextArcTick = clientTicks + ARC_MIN_INTERVAL;
    }

    /**
     * Renders a lightning strike from {@code from} down to {@code to} (world positions;
     * {@code FxPayloads} reconstructs {@code from} along the sun direction). {@code intensity}
     * 0..1 scales width, brightness, flash size and light radius. Visual-only by contract —
     * senders own the audio.
     */
    public static void strikeLightning(Vec3 from, Vec3 to, float intensity) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        float clamped = Mth.clamp(intensity, 0.05F, 1.0F);
        Bolt bolt = new Bolt(level.random.nextLong(), from, to, clientTicks, clamped, false);
        bolt.claimImpactLight();
        addCapped(BOLTS, bolt, MAX_BOLTS);
        // Impact crackle burst (visual support; budget-charged on the STORM channel).
        QuasarSpawner.spawn(STORM_ARC_EMITTER, to, FxBudget.Channel.STORM);
        // IDEA-15 §2: interior strikes lift the fog for a 6-tick silhouette reveal.
        if (StormInteriorFx.interiorAmount() > 0.5F) {
            StormInteriorFx.flash(6);
        }
    }

    // ------------------------------------------------------------------ package reads (renderer/interior)

    /** Live storms — package view for {@link StormWallRenderer} / {@link StormInteriorFx}. */
    static List<ClientStorm> storms() {
        return STORMS;
    }

    static List<Bolt> bolts() {
        return BOLTS;
    }

    static List<Bolt> arcs() {
        return ARCS;
    }

    static int ticks() {
        return clientTicks;
    }

    @Nullable
    static ClientStorm find(int stormId) {
        for (int i = 0; i < STORMS.size(); i++) {
            if (STORMS.get(i).id == stormId) {
                return STORMS.get(i);
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            if (!STORMS.isEmpty() || !BOLTS.isEmpty() || !ARCS.isEmpty()) {
                clearAll();
            }
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        clientTicks++;
        expireBolts(BOLTS, BOLT_LIFE_TICKS);
        expireBolts(ARCS, ARC_LIFE_TICKS);
        if (STORMS.isEmpty()) {
            return;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        for (int i = STORMS.size() - 1; i >= 0; i--) {
            ClientStorm storm = STORMS.get(i);
            if (!tickStorm(minecraft, level, storm, camera)) {
                storm.releaseResources();
                STORMS.remove(i);
            }
        }
    }

    /** @return {@code false} once the storm fully dissipated/exploded and must be dropped. */
    private static boolean tickStorm(Minecraft minecraft, ClientLevel level, ClientStorm storm, Vec3 camera) {
        int elapsed = clientTicks - storm.stateStartTick;
        // State promotion / expiry.
        if (storm.state == S2CStormStatePayload.STATE_SPAWN && elapsed >= storm.stateTicks) {
            storm.state = S2CStormStatePayload.STATE_ACTIVE;
            storm.stateStartTick = clientTicks;
            storm.stateTicks = 1;
            elapsed = 0;
        } else if ((storm.state == S2CStormStatePayload.STATE_DISSIPATE
                || storm.state == S2CStormStatePayload.STATE_EXPLODE) && elapsed >= storm.stateTicks) {
            return false;
        }

        // Reveal beat 2: the 0.4 rift-glitch pulse right after the terror pause (R14). W8's
        // TransitionFx documents glitchPulse(0.4, 20) as exactly this beat; it self-decays.
        if (storm.revealStyle && storm.state == S2CStormStatePayload.STATE_SPAWN
                && !storm.glitchStarted && elapsed >= StormRegistry.REVEAL_PAUSE_TICKS) {
            storm.glitchStarted = true;
            glitchPulseSafe(REVEAL_GLITCH_STRENGTH, StormRegistry.REVEAL_GLITCH_TICKS);
        }

        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dz * dz);
        double shellDist = Math.abs(centerDist - storm.radius);
        float visibility = storm.visibility(1.0F);

        if (storm.state == S2CStormStatePayload.STATE_EXPLODE) {
            // C8 death beat: no arcs/wisps/dread — just the roar fading out and debris
            // riding the expanding shockwave ring. The crown dies with the shell.
            storm.releaseCrownHalo();
            tickLoopSound(minecraft, storm, shellDist, visibility);
            tickExplosionDebris(level, storm);
            return true;
        }

        tickArcs(level, storm, camera, centerDist, shellDist, visibility);
        tickWisps(storm, shellDist, visibility);
        tickCrownHalo(storm, shellDist, visibility);
        tickLoopSound(minecraft, storm, shellDist, visibility);
        tickApproachDread(level, storm, camera, centerDist, shellDist, visibility);
        return true;
    }

    /**
     * C8 explosion debris, staged (FX-STORM multi-stage burst, mirroring the renderer's
     * {@code explodeRadiusScale} curve; EXPLOSION 2.0 upgrades from PLAN-STORM2 §W-D D4 —
     * the renderer's staggered-shell collapse choreography itself is W-A's, this class
     * owns the client debris/FX beats riding it):
     * <ul>
     *   <li><b>implosion</b> (progress &lt; {@link StormWallRenderer#EXPLODE_IMPLODE_FRAC}):
     *       debris tears off the shell and is sucked INTO the center — no smoke column yet.
     *       D4: plus 2 spark-white streaks/tick pulled hard toward the pinch point (the
     *       inward breath has teeth; pairs with D5's fog "gulp" in the interior);</li>
     *   <li><b>flash beat</b> (&lt; 0.30): white owns the frame, the air stays almost clean;</li>
     *   <li><b>expansion</b>: debris ring on the renderer's eased {@code 1 + 1.8·t²} radius
     *       law (D4: ring bursts DOUBLE at quality tier 2 — still raw {@code addParticle},
     *       budget-free) + rising center column + a vertical debris FOUNTAIN during expand
     *       0.3–0.8 climbing from the center toward 0.6·height (the burst has height, not
     *       just radius) + a {@code border_glitch} strobe burst every 5 ticks riding the
     *       ring — the glitch-voxel shard dissolve (tier ≥ 1 only, unchanged).</li>
     * </ul>
     * Raw {@code addParticle} for the dust — a 2 s one-off; only the glitch bursts charge
     * the STORM channel. The clear-sky bloom finish stays {@code StormInteriorFx}'s
     * white-out→bloom tail (untouched contract).
     */
    private static void tickExplosionDebris(ClientLevel level, ClientStorm storm) {
        RandomSource random = level.random;
        float progress = storm.explodeProgress(1.0F);
        boolean reduced = EclipseClientConfig.reducedFx();
        if (progress < StormWallRenderer.EXPLODE_IMPLODE_FRAC) {
            // Stage 1 — implosion suck-in: shell debris streams toward the center.
            int bursts = reduced ? 3 : 6;
            for (int i = 0; i < bursts; i++) {
                double angle = random.nextDouble() * Math.PI * 2.0D;
                double x = storm.center.x + Math.cos(angle) * storm.radius;
                double z = storm.center.z + Math.sin(angle) * storm.radius;
                double y = storm.center.y + random.nextDouble() * storm.height * 0.6D;
                double in = 0.5D + random.nextDouble() * 0.4D;
                level.addParticle(random.nextBoolean() ? ParticleTypes.CLOUD : ParticleTypes.LARGE_SMOKE,
                        x, y, z, -Math.cos(angle) * in, -0.03D, -Math.sin(angle) * in);
            }
            // STORM2 (D4): the suck-in additionally tears spark-white streaks off the
            // shell, faster than the smoke — the charge visibly FEEDS on the wall.
            int sparks = reduced ? 1 : 2;
            for (int i = 0; i < sparks; i++) {
                double angle = random.nextDouble() * Math.PI * 2.0D;
                double y = storm.center.y + 2.0D + random.nextDouble() * storm.height * 0.5D;
                double in = 1.1D + random.nextDouble() * 0.5D;
                level.addParticle(ParticleTypes.ELECTRIC_SPARK,
                        storm.center.x + Math.cos(angle) * storm.radius, y,
                        storm.center.z + Math.sin(angle) * storm.radius,
                        -Math.cos(angle) * in, -0.02D, -Math.sin(angle) * in);
            }
            return;
        }
        if (progress < 0.30F) {
            // Stage 2 — the flash beat: a lone ash flake over the center, nothing else.
            if (clientTicks % 4 == 0) {
                level.addParticle(ParticleTypes.WHITE_ASH,
                        storm.center.x, storm.center.y + 2.0D, storm.center.z,
                        0.0D, 0.1D, 0.0D);
            }
            return;
        }
        // Stage 3 — expanding debris ring (the renderer's eased expansion law).
        // STORM2 (D4): tier 2 doubles the ring bursts — the staggered nested shockwave
        // shells (W-A's explodeRadiusScale stagger) get a matching debris density. Still
        // raw addParticle: budget-free, and reducedFx keeps its old floor untouched.
        float expandT = (progress - StormWallRenderer.EXPLODE_IMPLODE_FRAC)
                / (1.0F - StormWallRenderer.EXPLODE_IMPLODE_FRAC);
        double ringR = storm.radius * (1.0D + 1.8D * expandT * expandT);
        int bursts = reduced ? 5 : (FxBudget.qualityTier() >= 2 ? 20 : 10);
        for (int i = 0; i < bursts; i++) {
            double angle = random.nextDouble() * Math.PI * 2.0D;
            double x = storm.center.x + Math.cos(angle) * ringR;
            double z = storm.center.z + Math.sin(angle) * ringR;
            double y = storm.center.y + 0.5D + random.nextDouble() * storm.height * 0.5D * (1.0D - progress);
            double out = 0.35D + random.nextDouble() * 0.3D;
            level.addParticle(random.nextBoolean() ? ParticleTypes.CLOUD : ParticleTypes.LARGE_SMOKE,
                    x, y, z, Math.cos(angle) * out, 0.05D + random.nextDouble() * 0.1D, Math.sin(angle) * out);
            if (random.nextInt(3) == 0) {
                level.addParticle(ParticleTypes.WHITE_ASH, x, y + 1.0D, z,
                        Math.cos(angle) * out * 0.5D, 0.12D, Math.sin(angle) * out * 0.5D);
            }
        }
        // Glitch-voxel shard support: one strobing border_glitch burst per 5 ticks on the
        // ring (STORM-charged; a budget refusal just skips the beat).
        if (clientTicks % 5 == 0 && FxBudget.qualityTier() >= 1) {
            double angle = random.nextDouble() * Math.PI * 2.0D;
            QuasarSpawner.spawn(EXPLOSION_GLITCH_EMITTER, new Vec3(
                    storm.center.x + Math.cos(angle) * ringR,
                    storm.center.y + 1.5D + random.nextDouble() * 3.0D,
                    storm.center.z + Math.sin(angle) * ringR), FxBudget.Channel.STORM);
        }
        if (clientTicks % 2 == 0) {
            level.addParticle(ParticleTypes.CAMPFIRE_SIGNAL_SMOKE,
                    storm.center.x + (random.nextDouble() - 0.5D) * 4.0D,
                    storm.center.y + 1.0D,
                    storm.center.z + (random.nextDouble() - 0.5D) * 4.0D,
                    0.0D, 0.25D + random.nextDouble() * 0.2D, 0.0D);
        }
        // STORM2 (D4): vertical debris FOUNTAIN during expand 0.3–0.8 — smoke launched
        // from the center climbs toward 0.6·height as the window advances, so the burst
        // reads tall while the ring reads wide. Raw addParticle, reducedFx keeps 1/tick.
        if (expandT >= 0.3F && expandT <= 0.8F) {
            double climb = (expandT - 0.3F) / 0.5F;
            int jets = reduced ? 1 : 3;
            for (int i = 0; i < jets; i++) {
                level.addParticle(i == 0 ? ParticleTypes.CAMPFIRE_SIGNAL_SMOKE : ParticleTypes.LARGE_SMOKE,
                        storm.center.x + (random.nextDouble() - 0.5D) * 3.0D,
                        storm.center.y + 1.0D + random.nextDouble() * storm.height * 0.6D * climb,
                        storm.center.z + (random.nextDouble() - 0.5D) * 3.0D,
                        (random.nextDouble() - 0.5D) * 0.06D,
                        0.35D + random.nextDouble() * 0.25D,
                        (random.nextDouble() - 0.5D) * 0.06D);
            }
        }
    }

    /** Periodic shell-surface arc crackles near the camera bearing (near LOD only, R14). */
    private static void tickArcs(ClientLevel level, ClientStorm storm, Vec3 camera,
            double centerDist, double shellDist, float visibility) {
        if (visibility < 0.35F || shellDist > ARC_RANGE || clientTicks < storm.nextArcTick) {
            return;
        }
        if (storm.type == S2CStormStatePayload.TYPE_SPHERE
                && StormInteriorFx.interiorAmount() > 0.3F) {
            // C8: sphere interiors are LIGHTNING-LESS — StormInteriorFx owns the (silent)
            // silhouette flickers there; arcs + their far-thunder stay an exterior read.
            storm.nextArcTick = clientTicks + ARC_MAX_INTERVAL;
            return;
        }
        RandomSource random = level.random;
        storm.nextArcTick = clientTicks + random.nextIntBetweenInclusive(ARC_MIN_INTERVAL, ARC_MAX_INTERVAL);
        // Arc anchored on the shell surface, biased toward the camera's bearing (±60°).
        double camAngle = Math.atan2(camera.z - storm.center.z, camera.x - storm.center.x);
        double angle = camAngle + (random.nextDouble() - 0.5D) * (Math.PI / 1.5D);
        double baseY = storm.center.y + random.nextDouble() * storm.height * 0.8D;
        double x = storm.center.x + Math.cos(angle) * storm.radius;
        double z = storm.center.z + Math.sin(angle) * storm.radius;
        Vec3 fromPos = new Vec3(x, baseY + 4.0D + random.nextDouble() * 6.0D, z);
        double angle2 = angle + (random.nextDouble() - 0.5D) * 0.35D;
        Vec3 toPos = new Vec3(storm.center.x + Math.cos(angle2) * storm.radius,
                baseY - 2.0D - random.nextDouble() * 5.0D,
                storm.center.z + Math.sin(angle2) * storm.radius);
        addCapped(ARCS, new Bolt(random.nextLong(), fromPos, toPos, clientTicks,
                0.35F + random.nextFloat() * 0.3F, true), MAX_ARCS);
        // STORM-channel charge inside; a budget-dropped crackle stays dropped (no vanilla fallback).
        QuasarSpawner.spawn(STORM_ARC_EMITTER, fromPos, FxBudget.Channel.STORM);
        float volume = (float) Mth.clamp(0.55D * (1.0D - shellDist / ARC_RANGE), 0.05D, 0.55D);
        level.playLocalSound(x, baseY, z, EclipseSounds.EVENT_LIGHTNING_FAR.get(), SoundSource.WEATHER,
                volume, 0.85F + random.nextFloat() * 0.3F, false);
        // IDEA-15 §2: interior arcs give a shorter 4-tick silhouette reveal — the existing
        // 20–60-tick cadence is a free ~2/min scare rhythm.
        if (StormInteriorFx.interiorAmount() > 0.5F) {
            StormInteriorFx.flash(4);
        }
    }

    /**
     * IDEA-15 §1 approach dread ladder — the storm reaches for you before you reach it.
     * Outside only ({@code visibility > 0.5}, {@code interiorAmount() < 0.1} — idea 6's clamp
     * makes that gate trustworthy for vortexes): a faint heartbeat whose cadence tightens
     * 50→22 ticks from 60 blocks in, ground-fog tendrils crawling out from the wall base
     * along the camera bearing inside 40, and inside 20 the tendrils ring the player's feet
     * while the heartbeat doubles into a two-beat thump.
     */
    private static void tickApproachDread(ClientLevel level, ClientStorm storm, Vec3 camera,
            double centerDist, double shellDist, float visibility) {
        if (visibility <= 0.5F || shellDist > DREAD_FAR || centerDist < storm.radius
                || StormInteriorFx.interiorAmount() >= 0.1F
                || storm.state == S2CStormStatePayload.STATE_DISSIPATE) {
            storm.heartbeatEchoTick = -1;
            return;
        }
        RandomSource random = level.random;
        // Second thump of the double heartbeat (scheduled below once inside 20 blocks).
        if (storm.heartbeatEchoTick >= 0 && clientTicks >= storm.heartbeatEchoTick) {
            storm.heartbeatEchoTick = -1;
            playHeartbeat(level, camera, 0.22F, 0.75F);
        }
        float closeness = (float) Mth.clamp((DREAD_FAR - shellDist) / (DREAD_FAR - DREAD_NEAR),
                0.0D, 1.0D);
        // Smoothstep-eased cadence: the tightening accelerates as you close in instead of
        // ramping linearly — the last 20 blocks feel like the storm noticed you.
        float eased = closeness * closeness * (3.0F - 2.0F * closeness);
        if (clientTicks >= storm.nextHeartbeatTick) {
            storm.nextHeartbeatTick = clientTicks
                    + Math.round(Mth.lerp(eased, HEARTBEAT_SLOW_TICKS, HEARTBEAT_FAST_TICKS));
            playHeartbeat(level, camera, 0.25F, 0.8F);
            if (shellDist <= DREAD_NEAR) {
                storm.heartbeatEchoTick = clientTicks + HEARTBEAT_ECHO_TICKS;
            }
        }
        if (shellDist > DREAD_MID) {
            return;
        }
        // Ground tendrils: ~3 fingers/s (raw addParticle — negligible; halved under reducedFx),
        // crawling OUT from the wall base toward the player along the camera bearing. The
        // inward crawl speeds up with the eased closeness — the fingers "reach harder" near.
        int interval = EclipseClientConfig.reducedFx() ? 14 : 7;
        double crawl = 0.010D + 0.012D * eased;
        if (clientTicks % interval == 0) {
            double camAngle = Math.atan2(camera.z - storm.center.z, camera.x - storm.center.x);
            double angle = camAngle + (random.nextDouble() - 0.5D) * 0.5D;
            double reach = storm.radius + random.nextDouble() * shellDist * 0.5D;
            double x = storm.center.x + Math.cos(angle) * reach;
            double z = storm.center.z + Math.sin(angle) * reach;
            double y = storm.center.y + 0.15D + random.nextDouble() * 0.5D;
            level.addParticle(random.nextBoolean()
                            ? ParticleTypes.CAMPFIRE_COSY_SMOKE : ParticleTypes.CLOUD,
                    x, y, z, (camera.x - x) * crawl, 0.01D, (camera.z - z) * crawl);
        }
        // ≤ 20: the fingers reach your feet — a low ring around the player drifting inward.
        if (shellDist <= DREAD_NEAR && clientTicks % 9 == 0) {
            double ringAngle = random.nextDouble() * Math.PI * 2.0D;
            double rx = camera.x + Math.cos(ringAngle) * 2.0D;
            double rz = camera.z + Math.sin(ringAngle) * 2.0D;
            level.addParticle(ParticleTypes.CAMPFIRE_COSY_SMOKE, rx, camera.y - 1.4D, rz,
                    Math.cos(ringAngle) * -0.02D, 0.005D, Math.sin(ringAngle) * -0.02D);
        }
    }

    /** Faint warden-heartbeat thump at the camera (sits under the churn loop at 56). */
    private static void playHeartbeat(ClientLevel level, Vec3 camera, float volume, float pitch) {
        level.playLocalSound(camera.x, camera.y, camera.z, SoundEvents.WARDEN_HEARTBEAT,
                SoundSource.AMBIENT, volume, pitch, false);
    }

    /**
     * Keeps ≤{@value #MAX_WISPS} spiraling {@code vortex_wisp} loop emitters alive per vortex
     * storm and swirls them 0.35 rad/s around the shell — moving the EMITTERS from Java keeps
     * the swirl radius correct for any storm size (a baked JSON vortex radius could not).
     */
    private static void tickWisps(ClientStorm storm, double shellDist, float visibility) {
        boolean wanted = storm.type == S2CStormStatePayload.TYPE_VORTEX
                && storm.state != S2CStormStatePayload.STATE_DISSIPATE
                && visibility > 0.2F && shellDist < ARC_RANGE
                && FxBudget.qualityTier() > 0;
        int cap = FxBudget.qualityTier() >= 2 ? MAX_WISPS : Math.max(1, MAX_WISPS - 1);
        if (!wanted) {
            storm.releaseWisps();
            return;
        }
        storm.wispAngle += SWIRL_RAD_PER_TICK;
        double wispRadius = storm.radius + 1.0D;
        for (int k = 0; k < MAX_WISPS; k++) {
            ParticleEmitter wisp = storm.wisps[k];
            if (k >= cap) {
                if (wisp != null) {
                    storm.releaseWisp(k);
                }
                continue;
            }
            if (wisp == null || wisp.isRemoved()) {
                storm.wisps[k] = null;
                // Budget-refused spawns simply retry next tick (loop emitters are cheap to keep).
                storm.wisps[k] = QuasarSpawner.spawnManaged(VORTEX_WISP_EMITTER,
                        wispPos(storm, wispRadius, k), FxBudget.Channel.STORM);
                continue;
            }
            // FX-STORM: the updraft gusts with the roar-loop clock (interior gusts only).
            storm.wispHeights[k] += WISP_RISE_PER_TICK * (1.0F + k * 0.15F)
                    * (1.0F + 0.5F * StormInteriorFx.gustAmount());
            if (storm.wispHeights[k] > storm.height * 0.9F) {
                storm.wispHeights[k] = 2.0F;
            }
            double angle = storm.wispAngle * (1.0D + k * 0.08D) + k * (Math.PI * 2.0D / MAX_WISPS);
            wisp.setPosition(storm.center.x + Math.cos(angle) * wispRadius,
                    storm.center.y + storm.wispHeights[k],
                    storm.center.z + Math.sin(angle) * wispRadius);
        }
    }

    private static Vec3 wispPos(ClientStorm storm, double wispRadius, int k) {
        double angle = storm.wispAngle * (1.0D + k * 0.08D) + k * (Math.PI * 2.0D / MAX_WISPS);
        return new Vec3(storm.center.x + Math.cos(angle) * wispRadius,
                storm.center.y + storm.wispHeights[k],
                storm.center.z + Math.sin(angle) * wispRadius);
    }

    /**
     * PH-WORLD (IDEAS-world #8): one Photon {@code eclipse:storm_crown_halo} pearl-string
     * loop per SPHERE storm, parked {@value #CROWN_ABOVE_SHELL} above the shell top. This
     * is a per-storm WINDOWED loop (INTEGRATION.md §4) owned HERE, not by
     * {@code PhotonFxRegistry.ensureLoop} (which manages ONE loop per logical id — storms
     * are many): attach inside {@link #ARC_RANGE}, release beyond
     * {@link #CROWN_RELEASE_RANGE} (hysteresis), release on DISSIPATE/EXPLODE/removal and
     * whenever the bridge goes unavailable ({@code reducedFx} kills it wholesale). A
     * refused spawn (executor budget) backs off {@value #CROWN_RETRY_TICKS} ticks — the
     * arc/wisp Quasar stack above stays the photon-less baseline (LAYER, no new Quasar
     * emitter by design).
     */
    private static void tickCrownHalo(ClientStorm storm, double shellDist, float visibility) {
        PhotonBridge.LoopHandle handle = storm.crownHalo;
        if (handle != null && !handle.alive()) {
            storm.crownHalo = null; // bridge sweep (level change) already reaped it
            handle = null;
        }
        boolean wanted = storm.type == S2CStormStatePayload.TYPE_SPHERE
                && storm.state != S2CStormStatePayload.STATE_DISSIPATE
                && visibility > 0.2F
                && shellDist < (handle != null ? CROWN_RELEASE_RANGE : ARC_RANGE)
                && PhotonBridge.available();
        if (!wanted) {
            storm.releaseCrownHalo();
            return;
        }
        Vec3 anchor = storm.center.add(0.0D, storm.height + CROWN_ABOVE_SHELL, 0.0D);
        if (handle != null) {
            // Keepalive: re-anchoring a live loop is unsupported — a resize/reposition
            // payload releases and respawns at the new crown (rare; storms sit still).
            if (storm.crownAnchor != null && storm.crownAnchor.distanceToSqr(anchor) > 0.25D) {
                storm.releaseCrownHalo();
            } else {
                return;
            }
        }
        if (clientTicks < storm.nextCrownRetryTick) {
            return;
        }
        storm.crownHalo = PhotonBridge.spawnLoop(PhotonBridge.STORM_CROWN_HALO, anchor);
        if (storm.crownHalo == null) {
            storm.nextCrownRetryTick = clientTicks + CROWN_RETRY_TICKS; // budget backoff
        } else {
            storm.crownAnchor = anchor;
        }
    }

    /** One positional churn/roar loop per storm, tracking the nearest shell point (fixed range 64). */
    private static void tickLoopSound(Minecraft minecraft, ClientStorm storm, double shellDist, float visibility) {
        StormLoopSound sound = storm.loopSound;
        boolean wanted = shellDist < LOOP_SOUND_RANGE && visibility > 0.05F
                && storm.state != S2CStormStatePayload.STATE_DISSIPATE
                && storm.state != S2CStormStatePayload.STATE_EXPLODE;
        if (wanted) {
            if (sound == null || sound.isStopped()) {
                if (!storm.loopStartedThisApproach) {
                    storm.loopStartedThisApproach = true;
                    sound = new StormLoopSound(storm);
                    storm.loopSound = sound;
                    minecraft.getSoundManager().play(sound);
                }
            } else {
                sound.fadeIn();
            }
            return;
        }
        storm.loopStartedThisApproach = false;
        if (sound != null) {
            sound.fadeOut();
            if (sound.isStopped()) {
                storm.loopSound = null;
            }
        }
    }

    // ------------------------------------------------------------------ housekeeping

    private static void expireBolts(List<Bolt> list, int life) {
        for (int i = list.size() - 1; i >= 0; i--) {
            Bolt bolt = list.get(i);
            if (clientTicks - bolt.startTick >= life) {
                bolt.releaseImpactLight();
                list.remove(i);
            } else {
                bolt.tickImpactLight(clientTicks, life);
            }
        }
    }

    private static void addCapped(List<Bolt> list, Bolt entry, int cap) {
        while (list.size() >= cap) {
            list.remove(0).releaseImpactLight();
        }
        list.add(entry);
    }

    /** W8's TransitionFx is an in-flight sibling; a broken pulse must never kill storm ticking. */
    private static void glitchPulseSafe(float amplitude, int decayTicks) {
        try {
            TransitionFx.glitchPulse(amplitude, decayTicks);
        } catch (Throwable t) {
            EclipseMod.LOGGER.debug("TransitionFx.glitchPulse unavailable; reveal glitch skipped", t);
        }
    }

    private static void clearAll() {
        for (int i = 0; i < STORMS.size(); i++) {
            STORMS.get(i).releaseResources();
        }
        STORMS.clear();
        for (int i = 0; i < BOLTS.size(); i++) {
            BOLTS.get(i).releaseImpactLight();
        }
        BOLTS.clear();
        ARCS.clear();
    }

    /** Disconnect wipes everything; respawn/dimension change wipes storms (server re-syncs). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clearAll();
    }

    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        clearAll();
    }

    // ------------------------------------------------------------------ data model

    /** One client-tracked storm. Mutable on purpose — payloads update in place. */
    static final class ClientStorm {
        final int id;
        Vec3 center = Vec3.ZERO;
        float radius = StormRegistry.DEFAULT_RADIUS;
        float height = StormRegistry.heightFor(StormRegistry.DEFAULT_RADIUS);
        int type = S2CStormStatePayload.TYPE_WALL;
        int state = S2CStormStatePayload.STATE_SPAWN;
        int stateStartTick;
        int stateTicks = 1;
        /** SPAWN with ticks > RAMP_TICKS: hold hidden + glitch pulse + ramp over the last 80. */
        boolean revealStyle;
        boolean glitchStarted;
        int nextArcTick;
        /** Approach-dread heartbeat cadence (IDEA-15 §1; keepalive-proof — handle() skips it). */
        int nextHeartbeatTick;
        /** Scheduled second thump of the ≤20-block double heartbeat (-1 = none pending). */
        int heartbeatEchoTick = -1;
        /** Spiraling vortex wisp emitters (looping; positions driven per tick). */
        final ParticleEmitter[] wisps = new ParticleEmitter[MAX_WISPS];
        final float[] wispHeights = new float[MAX_WISPS];
        float wispAngle;
        /** PH-WORLD #8: per-sphere-storm Photon crown-halo loop (windowed, see tickCrownHalo). */
        @Nullable
        PhotonBridge.LoopHandle crownHalo;
        /** Anchor the live crown was spawned at (re-anchor = release + respawn). */
        @Nullable
        Vec3 crownAnchor;
        /** Earliest tick the crown may retry after a refused (budget) spawn. */
        int nextCrownRetryTick;
        @Nullable
        StormLoopSound loopSound;
        /** One play(...) attempt per approach (LimboAmbience pattern — no retry storms). */
        boolean loopStartedThisApproach;

        ClientStorm(int id) {
            this.id = id;
            this.wispHeights[0] = 4.0F;
            this.wispHeights[1] = 18.0F;
            this.wispHeights[2] = 32.0F;
        }

        /**
         * Shell visibility 0..1: SPAWN ramps in (reveal-style over the LAST
         * {@link StormRegistry#RAMP_TICKS} ticks of the hold), ACTIVE holds 1, DISSIPATE and
         * EXPLODE fade out. Smoothstep-eased; drives shell alpha, height scale, interior fog
         * and audio.
         */
        float visibility(float partialTick) {
            float elapsed = clientTicks + partialTick - stateStartTick;
            switch (state) {
                case S2CStormStatePayload.STATE_SPAWN -> {
                    float ramp = revealStyle
                            ? (elapsed - (stateTicks - StormRegistry.RAMP_TICKS)) / StormRegistry.RAMP_TICKS
                            : elapsed / stateTicks;
                    return smooth(ramp);
                }
                case S2CStormStatePayload.STATE_DISSIPATE, S2CStormStatePayload.STATE_EXPLODE -> {
                    return 1.0F - smooth(elapsed / stateTicks);
                }
                default -> {
                    return 1.0F;
                }
            }
        }

        /** C8 shockwave progress 0..1 while EXPLODE runs (0 otherwise) — drives the expansion. */
        float explodeProgress(float partialTick) {
            if (state != S2CStormStatePayload.STATE_EXPLODE) {
                return 0.0F;
            }
            float elapsed = clientTicks + partialTick - stateStartTick;
            return Mth.clamp(elapsed / stateTicks, 0.0F, 1.0F);
        }

        /**
         * C8 white-hot factor (0 otherwise). FX-STORM retiming: charges up through the
         * implosion suck-in (to 0.55), PEAKS at the pinch release — the flash beat —
         * then decays over ~15 ticks while the shockwave expands.
         */
        float explodeWhite(float partialTick) {
            if (state != S2CStormStatePayload.STATE_EXPLODE) {
                return 0.0F;
            }
            float elapsed = clientTicks + partialTick - stateStartTick;
            float implodeEnd = Math.max(1.0F, stateTicks * StormWallRenderer.EXPLODE_IMPLODE_FRAC);
            if (elapsed < implodeEnd) {
                return Mth.clamp(elapsed / implodeEnd, 0.0F, 1.0F) * 0.55F; // charging glow
            }
            return Mth.clamp(1.0F - (elapsed - implodeEnd) / 15.0F, 0.0F, 1.0F);
        }

        void releaseWisp(int index) {
            ParticleEmitter wisp = wisps[index];
            wisps[index] = null;
            if (wisp != null) {
                try {
                    if (!wisp.isRemoved()) {
                        wisp.remove();
                    }
                } catch (Throwable ignored) {
                    // Teardown-order safe (QuasarSpawner.clearAttached pattern).
                }
            }
        }

        void releaseWisps() {
            for (int k = 0; k < wisps.length; k++) {
                if (wisps[k] != null) {
                    releaseWisp(k);
                }
            }
        }

        /** Stops the crown-halo loop (graceful fade — laid pearls live out their life). */
        void releaseCrownHalo() {
            PhotonBridge.LoopHandle handle = crownHalo;
            crownHalo = null;
            crownAnchor = null;
            if (handle != null) {
                PhotonBridge.stopLoop(handle, true); // idempotent, teardown-order safe
            }
        }

        void releaseResources() {
            releaseWisps();
            releaseCrownHalo();
            StormLoopSound sound = loopSound;
            if (sound != null) {
                sound.forceStop();
                loopSound = null;
            }
        }

        private static float smooth(float x) {
            x = Mth.clamp(x, 0.0F, 1.0F);
            return x * x * (3.0F - 2.0F * x);
        }
    }

    /**
     * One lightning bolt (sky strike) or shell arc crackle. Immutable path endpoints; the
     * jittered polyline is derived per frame from {@code seed} by {@link StormWallRenderer}.
     */
    static final class Bolt {
        final long seed;
        final Vec3 from;
        final Vec3 to;
        final int startTick;
        final float intensity;
        /** {@code true} = small shell-surface crackle (thinner, shorter-lived, no light). */
        final boolean arc;
        @Nullable
        private LightRenderHandle<PointLightData> light;
        private boolean lightBudgeted;

        Bolt(long seed, Vec3 from, Vec3 to, int startTick, float intensity, boolean arc) {
            this.seed = seed;
            this.from = from;
            this.to = to;
            this.startTick = startTick;
            this.intensity = intensity;
            this.arc = arc;
        }

        /** Claims ONE budgeted impact point light (R14) — skipped silently when over budget. */
        void claimImpactLight() {
            if (arc || !FxBudget.tryLight()) {
                return;
            }
            lightBudgeted = true;
            try {
                PointLightData data = new PointLightData()
                        .setPosition(to.x, to.y + 1.5D, to.z)
                        .setColor(0.75F, 0.55F, 1.0F)
                        .setBrightness(0.9F * intensity)
                        .setRadius(Math.min(16.0F, 8.0F + 8.0F * intensity));
                light = VeilRenderSystem.renderer().getLightRenderer().addLight(data);
            } catch (Throwable t) {
                releaseImpactLight();
            }
        }

        /** Decays the impact light with the bolt (white flash → violet ember → out). */
        void tickImpactLight(int now, int life) {
            LightRenderHandle<PointLightData> handle = light;
            if (handle == null) {
                return;
            }
            try {
                float remain = 1.0F - (now - startTick) / (float) life;
                handle.getLightData().setBrightness(0.9F * intensity * Math.max(0.0F, remain));
                handle.markDirty();
            } catch (Throwable t) {
                releaseImpactLight();
            }
        }

        void releaseImpactLight() {
            LightRenderHandle<PointLightData> handle = light;
            light = null;
            if (handle != null) {
                try {
                    handle.free();
                } catch (Throwable ignored) {
                    // Veil may already be tearing down.
                }
            }
            if (lightBudgeted) {
                lightBudgeted = false;
                FxBudget.releaseLight();
            }
        }
    }

    /**
     * The positional storm churn/roar loop (fixed range 64): {@code event.storm_loop} for
     * walls/vortexes, {@code event.storm_sphere_roar} for C8 sphere storms. Follows the
     * nearest shell point so the sound always comes from the wall's direction; volume scales
     * with shell visibility and fades in/out over {@value #FADE_TICKS} ticks (LimboLoopSound
     * pattern). Inside a sphere the roar's pitch sinks with the interior amount — the cheap
     * "lowpass alias" that makes the outside world read muffled through the fog wall.
     */
    static final class StormLoopSound extends AbstractTickableSoundInstance {
        private static final float MAX_VOLUME = 0.85F;
        private static final int FADE_TICKS = 30;
        /** Sphere-interior muffle: pitch sinks by this much at full interior (lowpass alias). */
        private static final float MUFFLE_PITCH_DROP = 0.42F;

        private final ClientStorm storm;
        private int fadeDirection = 1;
        private int fade;

        StormLoopSound(ClientStorm storm) {
            super(storm.type == S2CStormStatePayload.TYPE_SPHERE
                            ? EclipseSounds.EVENT_STORM_SPHERE_ROAR.get()
                            : EclipseSounds.EVENT_STORM_LOOP.get(),
                    SoundSource.WEATHER, SoundInstance.createUnseededRandom());
            this.storm = storm;
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = false;
            updatePosition();
        }

        @Override
        public void tick() {
            if (this.fade < 0) {
                this.stop();
                return;
            }
            this.fade = Math.min(this.fade + this.fadeDirection, FADE_TICKS);
            updatePosition();
            float visibility = storm.visibility(1.0F);
            // FX-STORM: the roar swells with the gust clock — the wind-gust bursts of the
            // interior rain/motes land exactly on the loop's loudest beat.
            this.volume = Math.min(1.0F, MAX_VOLUME * visibility
                    * Mth.clamp(this.fade / (float) FADE_TICKS, 0.0F, 1.0F)
                    * (1.0F + 0.18F * StormInteriorFx.gustAmount()));
            if (storm.type == S2CStormStatePayload.TYPE_SPHERE) {
                // C8 muffled-interior alias: the exterior roar dulls as the fog closes in.
                this.pitch = 1.0F - MUFFLE_PITCH_DROP * StormInteriorFx.interiorAmount();
            }
        }

        private void updatePosition() {
            Minecraft minecraft = Minecraft.getInstance();
            Vec3 listener = minecraft.gameRenderer.getMainCamera().getPosition();
            double dx = listener.x - storm.center.x;
            double dz = listener.z - storm.center.z;
            double dist = Math.sqrt(dx * dx + dz * dz);
            double nx;
            double nz;
            if (dist < 1.0E-3D) {
                nx = 1.0D;
                nz = 0.0D;
            } else {
                nx = dx / dist;
                nz = dz / dist;
            }
            this.x = storm.center.x + nx * storm.radius;
            this.y = Mth.clamp(listener.y, storm.center.y + 2.0D, storm.center.y + storm.height * 0.6D);
            this.z = storm.center.z + nz * storm.radius;
        }

        void fadeIn() {
            this.fade = Math.max(0, this.fade);
            this.fadeDirection = 1;
        }

        void fadeOut() {
            this.fade = Math.min(this.fade, FADE_TICKS);
            this.fadeDirection = -1;
        }

        void forceStop() {
            this.stop();
        }
    }
}
