package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Altar chromatic-aberration zone (P2 R9): a subtle-to-strong "reality is not normal here"
 * gradient around the altar. Every client tick this computes the zone strength
 * {@code Aberration = clamp(1 − dist/zoneRadius, 0, 1)² · }{@value #MAX_STRENGTH} — 0 at the
 * spawn-area boundary, strongest at the altar itself — slews it over ~{@value #EASE_TICKS}
 * ticks (no popping when the anchor moves or syncs late) and publishes it to
 * {@link EclipseFxState#setAltarAberration}. The {@code eclipse:altar_aberration} pipeline
 * row registered here (FEATURE priority, single frozen uniform {@code Aberration}, §3.3)
 * renders a radial RGB split from the screen center (max ~10 px), a 0.3 Hz breathing
 * modulation (applied CPU-side in the feeder so the shader keeps the one frozen uniform)
 * and ~1% barrel distortion above 0.6 — "not normal", never nauseating.
 *
 * <ul>
 *   <li><b>Center</b>: {@link FxAnchors#ALTAR_CENTER} (published by P4/P6 when the altar —
 *       the P6-W4 floating sanctum — is placed; full 3D distance so hovering above/below
 *       the island reads correctly). Until the anchor syncs, falls back to the world spawn
 *       ({@link ClientStateCache#borderCenterX}/{@code Z} — the disc origin the sanctum is
 *       built on) with horizontal-only distance.</li>
 *   <li><b>Zone radius</b>: the committed stage-0 spawn disc from the synced
 *       {@link ClientStateCache} stage data, capped at {@link DiscGeometry#MAIN_DISC_RADIUS}
 *       so later stage growth never widens the aberration zone beyond the spawn area.</li>
 *   <li><b>Budget</b>: FEATURE priority like {@code eclipse:border_glitch}; the two zones
 *       never overlap geometrically (the ring sits well outside the spawn disc), but if
 *       both ever signal, only the stronger pass runs (mutual throttle — border wins ties;
 *       mirrored predicate in {@code border.client.BorderFxRenderer}).</li>
 *   <li><b>Iris</b>: hard-gated off with every other post pipeline; there is deliberately
 *       no world-space fallback (a grade-style screen effect, §7 risk 1).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarAberration {
    public static final ResourceLocation ALTAR_ABERRATION_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_aberration");

    /** R9 curve cap: {@code (1 − d/r)² · 0.85}. */
    private static final float MAX_STRENGTH = 0.85F;
    /** Zone-strength slew length (R9 "eased 10 ticks"). */
    private static final int EASE_TICKS = 10;
    private static final float SLEW_PER_TICK = MAX_STRENGTH / EASE_TICKS;
    /** Breathing modulation: 0.3 Hz, ±10% (30 whole cycles per 100 s Time wrap — seamless). */
    private static final float BREATH_HZ = 0.3F;
    /** Zone floor for degenerate synced radii (a zone thinner than this reads as a popping toggle). */
    private static final double MIN_ZONE_RADIUS = 24.0D;
    /** Glyph-flash envelope length (v2 [a1]): pops on, eases out over ~0.8 s. */
    private static final int FLASH_TICKS = 16;

    // --- WAVE5 (F-105 C) — C5 reflex pulse + level breath (IDEA-12 #4 + #9) -------------

    /** C5 reflex pulse: strength added per {@link #pulse} notify (the altar "twitches"). */
    private static final float PULSE_ADD = 0.20F;
    /** Linear pulse decay length (~15 ticks). */
    private static final int PULSE_DECAY_TICKS = 15;
    private static final float PULSE_DECAY_PER_TICK = PULSE_ADD / PULSE_DECAY_TICKS;
    /** C5 breath: +0.03 Hz per altar level on top of {@link #BREATH_HZ} (0.01 Hz snapped). */
    private static final float BREATH_HZ_PER_LEVEL = 0.03F;
    /** C5 breath: base ±10% grows +0.8%/level, capped at ±14% (the plan ceiling). */
    private static final float BREATH_AMP_BASE = 0.10F;
    private static final float BREATH_AMP_PER_LEVEL = 0.008F;
    private static final float BREATH_AMP_MAX = 0.14F;

    /** Client-side eased zone strength; the fed uniform adds the 0.3 Hz breathing on top. */
    private static float eased;
    /** WAVE5 (F-105 C) — C5 reflex-pulse level (decays linearly, published on top of {@link #eased}). */
    private static float pulse;
    /** Last {@code [w5c-breath]}-probed snapped frequency ({@code -1} = unlogged). */
    private static float lastLoggedBreathHz = -1.0F;
    /** Remaining glyph-flash ticks (0 = idle); set on skill level-up, drained per tick. */
    private static int flashTicks;
    /** Last skill level seen ({@code -1} = unseeded — the login sync must never flash). */
    private static int lastSeenLevel = -1;

    static {
        // FEATURE row per §3.3; VeilPostController applies the Iris/config gate, the ≤3-pass
        // cap and the failure fuse. Registered from static init (W1 pattern).
        VeilPostController.register(new VeilPostController.PipelineSpec(
                ALTAR_ABERRATION_POST,
                VeilPostController.PipelinePriority.FEATURE,
                AltarAberration::wantPost,
                AltarAberration::feedPost));
    }

    private AltarAberration() {}

    // ------------------------------------------------------------------ per-tick zone feed

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        float target = 0.0F;
        if (level != null && player != null && level.dimension() == Level.OVERWORLD) {
            target = zoneTarget(player);
        }
        // Fixed-rate slew: any change completes within EASE_TICKS, and logging out mid-zone
        // can never leave a stale strength behind (EclipseFxState.clearAll also zeroes it).
        if (eased < target) {
            eased = Math.min(target, eased + SLEW_PER_TICK);
        } else if (eased > target) {
            eased = Math.max(target, eased - SLEW_PER_TICK);
        }
        // WAVE5 (F-105 C) — C5: the reflex pulse rides ON TOP of the zone strength, clamped
        // to MAX_STRENGTH so the frozen single-uniform contract never sees a new ceiling.
        // Published only while INSIDE the zone (eased > 0) — a far-away ALTAR_BEAM payload
        // (512-block view range, world-visible L5 sends) must not flash screens without
        // zone context. Leaving the world zeroes it (the target==0 slew plus this decay).
        if (pulse > 0.0F) {
            pulse = Math.max(0.0F, pulse - PULSE_DECAY_PER_TICK);
        }
        float published = eased > 0.001F ? Math.min(MAX_STRENGTH, eased + pulse) : eased;
        EclipseFxState.setAltarAberration(published);
        tickGlyphFlash(level != null && player != null);
    }

    /**
     * WAVE5 (F-105 C) — C5 (IDEA-12 #4): one client-local reflex notify — the aberration
     * zone "twitches" by {@code amount} (linear ~15 t decay, hard-clamped to
     * {@value #MAX_STRENGTH} at publish). Called from
     * {@code veilfx.QuasarSpawner#spawnOrFallback} whenever an {@code ALTAR_BEAM} payload
     * arrives (deposits, banking, level-ups, verdict blooms — every time the altar is fed
     * or answers). Sheds entirely under {@code reducedFx} (the breath stays flattened, its
     * own bestand rule). The probe logs the RISING edge only, so ritual beam salvos cannot
     * flood the debug log.
     */
    public static void pulse(float amount) {
        if (EclipseClientConfig.reducedFx() || amount <= 0.0F) {
            return;
        }
        boolean freshPulse = pulse <= 0.0F;
        pulse = Math.min(MAX_STRENGTH, pulse + amount);
        if (freshPulse) {
            EclipseMod.LOGGER.debug("[w5c-abpulse] pulse={} eased={}", pulse, eased);
        }
    }

    /**
     * v2 [a1] glyph-flash tracking: watches the same {@link ClientStateCache#skillLevel}
     * state as {@code skills.LevelUpOverlay} with the same seeding rules — the first
     * observation of a session seeds silently (login sync is not a celebration), a
     * downward change (admin xp set) re-seeds without theater, an increase arms the
     * {@value #FLASH_TICKS}-tick flash. Gated like the overlay: {@code
     * levelUpCelebrations} plus {@code reducedFx} (the flash is a pulsing overlay).
     * Only visible near the altar anyway — the pipeline itself needs Aberration > 0.01.
     */
    private static void tickGlyphFlash(boolean inWorld) {
        if (!inWorld) {
            lastSeenLevel = -1;
            flashTicks = 0;
            return;
        }
        int skillLevel = ClientStateCache.skillLevel;
        if (lastSeenLevel < 0 || skillLevel < lastSeenLevel) {
            lastSeenLevel = skillLevel;
        } else if (skillLevel > lastSeenLevel) {
            if (EclipseClientConfig.levelUpCelebrations() && !EclipseClientConfig.reducedFx()) {
                flashTicks = FLASH_TICKS;
            }
            lastSeenLevel = skillLevel;
        }
        if (flashTicks > 0 && !Minecraft.getInstance().isPaused()) {
            flashTicks--;
        }
    }

    /** {@code clamp(1 − dist/zoneRadius, 0, 1)² · 0.85} against the anchor (or spawn fallback). */
    private static float zoneTarget(LocalPlayer player) {
        double dist;
        Vec3 altar = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (altar != null) {
            dist = player.position().distanceTo(altar);
        } else {
            double dx = player.getX() - ClientStateCache.borderCenterX;
            double dz = player.getZ() - ClientStateCache.borderCenterZ;
            dist = Math.sqrt(dx * dx + dz * dz);
        }
        double zoneRadius = Math.max(MIN_ZONE_RADIUS,
                Math.min(ClientStateCache.stageRadiusOverworld, DiscGeometry.MAIN_DISC_RADIUS));
        float linear = (float) Mth.clamp(1.0D - dist / zoneRadius, 0.0D, 1.0D);
        return linear * linear * MAX_STRENGTH;
    }

    // ------------------------------------------------------------------ pipeline row

    /**
     * Post strength metric for the mutual FEATURE throttle — keep in sync with the identical
     * pair of helpers in {@code border.client.BorderFxRenderer} (border wins ties).
     */
    private static float aberrationPostStrength(float aberration) {
        return aberration * 0.85F;
    }

    /** {@code border.client.BorderFxRenderer}'s strength curve ({@code Proximity^1.5}) — keep in sync. */
    private static float borderPostStrength(float proximity) {
        return proximity * Mth.sqrt(proximity);
    }

    private static boolean wantPost() {
        float aberration = EclipseFxState.altarAberration();
        if (aberration <= 0.01F) {
            return false;
        }
        float prox = EclipseFxState.borderProximity();
        if (prox <= 0.01F) {
            return true;
        }
        return aberrationPostStrength(aberration) > borderPostStrength(prox);
    }

    /**
     * 0.3 Hz breathing is baked into the fed value so the frozen Aberration uniform stays
     * a single scalar; under {@code reducedFx} the breath flattens to its MEAN (0.9) —
     * same average zone strength, no pulse. v2 additionally feeds the shared wrap clock,
     * the glyph-flash envelope and the reducedFx detail gate (same commit as the shader
     * uniforms — the additive-uniform rule).
     *
     * <p>WAVE5 (F-105 C) — C5 level breath (IDEA-12 #9): the breathing frequency rises
     * with the synced altar level ({@code 0.3 + 0.03·level} Hz) and the amplitude deepens
     * toward ±{@value #BREATH_AMP_MAX} — a levelled altar breathes faster AND deeper. The
     * frequency is snapped to 0.01 Hz so every value completes a whole number of cycles
     * per 100 s clock wrap (the seam stays invisible, the bestand proof holds).
     * {@code ClientStateCache.altarLevel} is READ-only here.</p>
     */
    private static void feedPost(PostPipeline pipeline) {
        float seconds = (System.currentTimeMillis() % 100_000L) / 1000.0F;
        int altarLevel = Math.max(0, ClientStateCache.altarLevel);
        float breathHz = Math.round((BREATH_HZ + BREATH_HZ_PER_LEVEL * altarLevel) * 100.0F) / 100.0F;
        float breathAmp = Math.min(BREATH_AMP_MAX, BREATH_AMP_BASE + BREATH_AMP_PER_LEVEL * altarLevel);
        if (breathHz != lastLoggedBreathHz) {
            lastLoggedBreathHz = breathHz;
            EclipseMod.LOGGER.debug("[w5c-breath] hz={} amp={} level={}", breathHz, breathAmp, altarLevel);
        }
        float breath = EclipseClientConfig.reducedFx()
                ? 0.9F
                : 0.9F + breathAmp * Mth.sin(seconds * (float) (Math.PI * 2.0D) * breathHz);
        pipeline.getUniform("Aberration").setFloat(EclipseFxState.altarAberration() * breath);
        pipeline.getUniform("Time").setFloat(seconds);
        pipeline.getUniform("GlyphFlash").setFloat(glyphFlash());
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
    }

    /** Glyph-flash envelope 0..1: instant pop on level-up, smoothstep ease-out drain. */
    private static float glyphFlash() {
        if (flashTicks <= 0) {
            return 0.0F;
        }
        float partialTick = Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
        float f = Mth.clamp((flashTicks - partialTick) / FLASH_TICKS, 0.0F, 1.0F);
        return f * f * (3.0F - 2.0F * f);
    }
}
