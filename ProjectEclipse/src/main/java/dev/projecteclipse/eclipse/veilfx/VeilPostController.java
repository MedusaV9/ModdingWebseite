package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

import javax.annotation.Nullable;

import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsDimension;
import dev.projecteclipse.eclipse.backrooms.BackroomsLayers;
import dev.projecteclipse.eclipse.backrooms.GlitchedWandererEntity;
import dev.projecteclipse.eclipse.client.sky.EclipseIrisState;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.post.PostPipeline;
import foundry.veil.api.client.render.post.PostProcessingManager;
import foundry.veil.platform.VeilEventPlatform;
import net.minecraft.client.Camera;
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
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Table-driven registry for every Eclipse Veil post pipeline (P2 §3.1 rewrite). Each pipeline
 * is one {@link PipelineSpec} row {@code (id, activationPredicate, uniformFeeder, priority)}:
 * the per-tick loop activates rows whose predicate holds, the {@code preVeilPostProcessing}
 * hook runs the row's feeder each frame, and the controller enforces the global rules:
 * <ul>
 *   <li><b>≤ {@value #MAX_CONCURRENT} concurrent fullscreen passes</b> — when over budget the
 *       lowest {@link PipelinePriority} drops first ({@code GRADE(0) < FEATURE(1) <
 *       TRANSITION(2)}).</li>
 *   <li><b>Run order</b>: grades first, features on top, transitions last (Veil sorts active
 *       pipelines by descending manager priority; rows map to 3000/2000/1000).</li>
 *   <li><b>Hard gate</b>: nothing is added while an Iris shaderpack is active or
 *       {@code veilPostFx} is off ({@link EclipseIrisState#postFxAllowed}); world-space FX
 *       renderers are the Iris fallback (§7).</li>
 *   <li><b>Failure fuse</b>: a pipeline that throws {@value #MAX_FAILURES} times is disabled
 *       for the session (log-once).</li>
 * </ul>
 *
 * <p>W1 registers its own rows here ({@code eclipse:world_grade}, {@code eclipse:sun_halo});
 * every other pipeline registers from its feature class's static init ({@code eclipse:limbo}
 * from {@code LimboAmbience}, {@code eclipse:border_glitch} from {@code BorderFxRenderer},
 * etc.). The W1 backward-compat default rows for limbo/border_glitch were removed once
 * those v2 rows landed (P2-W3/W4 wiring notes sanctioned the deletion — WB-GHOSTFX).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class VeilPostController {
    /** Eviction rank (lowest evicted first) + Veil manager sort priority (higher runs first). */
    public enum PipelinePriority {
        GRADE(0, 3000),
        FEATURE(1, 2000),
        TRANSITION(2, 1000);

        private final int evictionRank;
        private final int managerPriority;

        PipelinePriority(int evictionRank, int managerPriority) {
            this.evictionRank = evictionRank;
            this.managerPriority = managerPriority;
        }
    }

    /**
     * One registry row. {@code activationPredicate} runs once per client tick;
     * {@code uniformFeeder} runs once per frame while the pipeline is active — it must not
     * allocate (set primitives / pre-allocated JOML scratch only).
     */
    public record PipelineSpec(ResourceLocation id, PipelinePriority priority,
            BooleanSupplier activationPredicate, Consumer<PostPipeline> uniformFeeder) {}

    public static final ResourceLocation LIMBO_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "limbo");
    public static final ResourceLocation SUN_HALO_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "sun_halo");
    public static final ResourceLocation BORDER_GLITCH_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border_glitch");
    public static final ResourceLocation WORLD_GRADE_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "world_grade");

    /** ≤ 3 concurrent fullscreen post passes (§3.5). */
    private static final int MAX_CONCURRENT = 3;
    /** A pipeline that throws this many times is disabled for the session (§1.1 audit rule). */
    private static final int MAX_FAILURES = 3;

    private record Row(PipelineSpec spec, int order) {}

    /** Lock-free for the per-frame feeder lookup; registration order lives in {@link Row#order}. */
    private static final Map<ResourceLocation, Row> ROWS = new ConcurrentHashMap<>();
    /** Dev overrides: {@code true} = force-on, {@code false} = force-off (cleared on logout). */
    private static final Map<ResourceLocation, Boolean> OVERRIDES = new ConcurrentHashMap<>();
    private static final Map<ResourceLocation, Integer> FAILURES = new HashMap<>();
    private static final Set<ResourceLocation> DISABLED = ConcurrentHashMap.newKeySet();
    /** Scratch list reused each tick (no per-tick allocations). */
    private static final List<Row> DESIRED = new ArrayList<>(8);
    private static final Comparator<Row> EVICTION_ORDER = Comparator
            .comparingInt((Row row) -> row.spec().priority().evictionRank).reversed()
            .thenComparingInt(Row::order);

    private static int nextOrder;

    static {
        registerBuiltins();
    }

    private VeilPostController() {}

    // ------------------------------------------------------------------ public API (frozen)

    /**
     * Registers (or replaces) a pipeline row. Called from each feature's static init on the
     * client; a feature row always replaces the same-id backward-compat default row no matter
     * which class loads first.
     */
    public static synchronized void register(PipelineSpec spec) {
        ROWS.put(spec.id(), new Row(spec, nextOrder++));
    }

    /**
     * Dev-command override ({@code /eclipsefx post <id> on|off}): {@code true} forces the
     * pipeline on (predicate ignored), {@code false} forces it off. The budget/gate/failure
     * rules still apply. Cleared by {@link #clearOverride} and on logout.
     */
    public static void setEnabled(ResourceLocation pipeline, boolean enabled) {
        OVERRIDES.put(pipeline, enabled);
    }

    /** Returns the pipeline to predicate-driven activation. */
    public static void clearOverride(ResourceLocation pipeline) {
        OVERRIDES.remove(pipeline);
    }

    /** Whether the pipeline is currently running in Veil's post manager. */
    public static boolean isActive(ResourceLocation pipeline) {
        try {
            return VeilRenderSystem.renderer().getPostProcessingManager().isActive(pipeline);
        } catch (Throwable t) {
            return false;
        }
    }

    // ------------------------------------------------------------------ built-in rows

    private static void registerBuiltins() {
        // W1: consolidated night/eclipse grade (R3/R16) — the "sky never darkens" fix. It
        // operates on the final image, so it wins against the user's gamma setting.
        register(new PipelineSpec(WORLD_GRADE_POST, PipelinePriority.GRADE,
                VeilPostController::wantWorldGrade, VeilPostController::feedWorldGrade));
        // W1: screen-space sun halo around the CPU-projected SunScreen point (R2 fix).
        register(new PipelineSpec(SUN_HALO_POST, PipelinePriority.FEATURE,
                VeilPostController::wantSunHalo, VeilPostController::feedSunHalo));
        // eclipse:limbo / eclipse:border_glitch register from LimboAmbience's /
        // BorderFxRenderer's static init (the W1 backward-compat default rows they used to
        // replace are gone — dead at runtime per P2-W3/W4 wiring, removed by WB-GHOSTFX).
    }

    // --- world_grade -------------------------------------------------------------------

    /**
     * The dimensions whose sky/weather story this grade tells (the pre-B5 gate, unchanged).
     * Everything else either owns its own grade (limbo) or, since FX-13 B5, borrows the pass
     * for the dread heartbeat ALONE — see {@link #feedWorldGrade}, which idles every sky
     * lane out there so the borrowed pass cannot smuggle the overworld grade with it.
     */
    private static boolean gradedDimension(@Nullable ClientLevel level) {
        return level != null
                && (level.dimension() == Level.OVERWORLD || level.dimension() == Level.NETHER);
    }

    private static boolean wantWorldGrade() {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return false;
        }
        // FX-13 B5 (census N3): the dread heartbeat is the only lane here that is not a sky
        // story, and its dread zone IS a whole dimension (the backrooms) — so it keeps the
        // pass alive outside the graded dimensions too. limbo stays excluded: it owns its
        // own GRADE pass and two of them would fight over the same frame there.
        boolean dread = easedDread > MIN_DREAD && level.dimension() != LimboDimension.LIMBO;
        if (!gradedDimension(level)) {
            return dread;
        }
        float partialTick = partialTick();
        // F-077 V2: the End-arrival grade feeds keep the pass alive in plain daylight
        // (the day-12 show usually plays at EclipseAmount == NightAmount == 0).
        return nightAmount(level, partialTick) > 0.01F || EclipseFxState.eclipseAmount(partialTick) > 0.01F
                || EclipseFxState.arrivalDim(partialTick) > 0.005F
                || EclipseFxState.endTintPulse(partialTick) > 0.005F
                // FX-12: the day-2 breach show plays at high noon too — the heat feed
                // has to keep the pass alive on its own, exactly like the grade lane.
                || EclipseFxState.netherHeat(partialTick) > 0.005F
                // FX-13 A9: the blood-dusk window OPENS while the sun is still ~17° above
                // the horizon, where dayFactor is 1 and NightAmount is exactly 0 — the
                // lean must keep the pass alive on its own (the FX-12 heat precedent).
                || bloodDusk(level, partialTick) > 0.005F
                // FX-13 B5: the heartbeat fires at high noon just as readily.
                || dread;
    }

    /** FX-12: the heat haze runs at this share of the ember lean (one state value, two uniforms). */
    private static final float HEAT_SHIMMER_SHARE = 0.6F;

    /** Scratch for the horizon projection (feeder-only; never escapes). */
    private static final Vector4f HORIZON_NDC = new Vector4f();
    /** Horizon probe distance — far enough that camera height is angularly negligible. */
    private static final double HORIZON_PROBE_BLOCKS = 4096.0D;

    private static void feedWorldGrade(PostPipeline pipeline) {
        ClientLevel level = Minecraft.getInstance().level;
        float partialTick = partialTick();
        // FX-13 B5: before B5 this pass only ever ran in OVERWORLD/NETHER; now the dread
        // heartbeat can borrow it anywhere (the backrooms ARE the dread zone). Outside the
        // graded dimensions every sky/weather lane therefore feeds its IDLE value — the
        // borrowed pass carries the heartbeat and nothing else, so an eclipse running up
        // top can never crush the yellow rooms. (NightAmount, PhaseTint, BloodDusk and
        // ShadowBands are already dimension-gated inside their own feeds.)
        boolean graded = gradedDimension(level);
        float eclipse = graded ? EclipseFxState.eclipseAmount(partialTick) : 0.0F;
        pipeline.getUniform("EclipseAmount").setFloat(eclipse);
        pipeline.getUniform("NightAmount").setFloat(level == null ? 0.0F : nightAmount(level, partialTick));
        pipeline.getUniform("DesatAmount").setFloat(eclipse * 0.5F);
        pipeline.getUniform("ExposureMul").setFloat(
                graded ? EclipseFxState.exposureMul(partialTick) : 1.0F);
        // v2 (FX team GRADE): grain/breath/seethe clock (limbo hour-wrap pattern), the
        // true-horizon band line, and the reducedFx detail gate.
        pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 3_600_000L) / 1000.0F);
        pipeline.getUniform("HorizonY").setFloat(horizonNdcY());
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
        // v3 (VEIL-REPASS-1): signed color-script lean — dusk/BUILDUP negative,
        // dawn/ENDING positive; the shader tints the violet story from it.
        pipeline.getUniform("PhaseTint").setFloat(phaseTint(level, partialTick));
        // v4 (F-077 V2): End-arrival event uniforms — same feeder, same commit (the
        // additive rule). Both read 0 outside the cinematic (bit-identical frame).
        pipeline.getUniform("ArrivalDim").setFloat(
                graded ? EclipseFxState.arrivalDim(partialTick) : 0.0F);
        pipeline.getUniform("EndTintPulse").setFloat(
                graded ? EclipseFxState.endTintPulse(partialTick) : 0.0F);
        // v5 (FX-12 nether opening): one state value feeds both heat uniforms — the
        // shimmer is the softer half of the same ramp, so they can never disagree.
        float heat = graded ? EclipseFxState.netherHeat(partialTick) : 0.0F;
        pipeline.getUniform("HeatTint").setFloat(heat);
        pipeline.getUniform("HeatShimmer").setFloat(heat * HEAT_SHIMMER_SHARE);
        // v6 (FX-13 A9): totality shadow bands (TotalityPeakFx crescent-window driver —
        // already 0 under reducedFx/rain/occlusion, so it passes through unfiltered) and
        // the day-10+ blood-dusk lean. Both read 0 in idle (bit-identical frame).
        pipeline.getUniform("ShadowBands").setFloat(TotalityPeakFx.shadowBands());
        pipeline.getUniform("BloodDusk").setFloat(bloodDusk(level, partialTick));
        // v7 (FX-13 B5): the finished heartbeat beat — 0 whenever the eased dread is
        // idle, so the shader block is skipped and the frame stays bit-identical.
        pipeline.getUniform("DreadPulse").setFloat(dreadPulseUniform(partialTick));
    }

    // --- v3 (VEIL-REPASS-1): world_grade color script -----------------------------------

    /** Eased eclipse-phase lean (BUILDUP → dusk −0.6, ENDING → dawn +0.6, else 0). */
    private static float easedPhaseLean;
    /** Lean slew per tick: full lean in ~24 ticks — softer than the eclipse ramp itself. */
    private static final float PHASE_LEAN_SLEW = 0.025F;
    /** How far an eclipse phase alone can push the script (the sun edge supplies the rest). */
    private static final float PHASE_LEAN_AMPLITUDE = 0.6F;

    /** Per-tick slew of the eclipse-phase lean toward its phase target (never snaps). */
    private static void tickPhaseLeanEase() {
        int phase = EclipseFxState.eclipsePhase();
        float target = phase == EclipseFxState.PHASE_BUILDUP ? -PHASE_LEAN_AMPLITUDE
                : phase == EclipseFxState.PHASE_ENDING ? PHASE_LEAN_AMPLITUDE : 0.0F;
        if (easedPhaseLean < target) {
            easedPhaseLean = Math.min(target, easedPhaseLean + PHASE_LEAN_SLEW);
        } else if (easedPhaseLean > target) {
            easedPhaseLean = Math.max(target, easedPhaseLean - PHASE_LEAN_SLEW);
        }
    }

    /**
     * Signed color-script lean in [−1, 1] for the {@code world_grade} {@code PhaseTint}
     * uniform: the sun-elevation edge (overworld only — the vanilla celestial angle:
     * {@code sin > 0} is the setting half of the cycle, so dusk leans negative and dawn
     * positive, weighted by how close the sun is to the horizon) plus the eased
     * eclipse-phase lean (BUILDUP is a scripted dusk, ENDING a scripted dawn). Both
     * inputs are continuous, so the combined script can never pop.
     */
    private static float phaseTint(ClientLevel level, float partialTick) {
        float dayTint = 0.0F;
        if (level != null && level.dimension() == Level.OVERWORLD) {
            float angle = SunTracker.sunAngleRadians(level, partialTick);
            float edge = Mth.clamp(1.0F - Math.abs(Mth.cos(angle)) / 0.30F, 0.0F, 1.0F);
            edge = edge * edge * (3.0F - 2.0F * edge);
            dayTint = (Mth.sin(angle) >= 0.0F ? -1.0F : 1.0F) * edge;
        }
        return Mth.clamp(dayTint + easedPhaseLean, -1.0F, 1.0F);
    }

    /**
     * NDC y of the world horizon along the camera yaw: a point at CAMERA height,
     * {@value #HORIZON_PROBE_BLOCKS} blocks along the horizontal forward, projected
     * through this frame's exact render matrices ({@link SunTracker#worldToNdc} — the
     * SunTracker law, so the band tracks pitch and view bobbing). Returns the +10 park
     * (band gaussian dies to zero) while unprojectable: no frame yet, or the camera is
     * pitched so far the horizontal forward leaves the clip volume. One small {@code Vec3}
     * per frame — the {@code LimboAmbience.zenithWorldPoint} feeder precedent.
     */
    private static float horizonNdcY() {
        Camera camera = Minecraft.getInstance().gameRenderer.getMainCamera();
        float yawRad = camera.getYRot() * Mth.DEG_TO_RAD;
        Vec3 far = camera.getPosition().add(
                -Mth.sin(yawRad) * HORIZON_PROBE_BLOCKS, 0.0D, Mth.cos(yawRad) * HORIZON_PROBE_BLOCKS);
        if (SunTracker.worldToNdc(far, HORIZON_NDC)) {
            return Mth.clamp(HORIZON_NDC.y(), -10.0F, 10.0F);
        }
        return 10.0F;
    }

    // --- v6 (FX-13 A9): blood dusk ------------------------------------------------------

    /** Blood-dusk starts on this event day (census N7: "the world knows the end is near"). */
    private static final int BLOOD_DUSK_FIRST_DAY = 10;
    /** Day the lean saturates (10 → 13 ramps {@value #BLOOD_DUSK_MIN} → {@value #BLOOD_DUSK_MAX}). */
    private static final int BLOOD_DUSK_LAST_DAY = 13;
    /** Uniform value on day 10 — dezent, a suspicion at the horizon. */
    private static final float BLOOD_DUSK_MIN = 0.15F;
    /** Uniform value from day 13 on — deutlich, the dusk openly bleeds. */
    private static final float BLOOD_DUSK_MAX = 0.40F;

    /**
     * {@code world_grade BloodDusk} uniform: from event day {@value #BLOOD_DUSK_FIRST_DAY}
     * the dawn/dusk windows lean blood-red, deepening daily until day
     * {@value #BLOOD_DUSK_LAST_DAY}.
     *
     * <p><b>Day source</b>: {@code ClientStateCache.day} — the same server-synced field
     * (S2CDayStatePayload, login re-send included) the sky escalation reads through
     * {@code EclipseSkyState.dayEscalation}; no new packets.</p>
     *
     * <p><b>Window source</b>: the VANILLA {@code level.getSunAngle}, deliberately NOT
     * {@link SunTracker#sunAngleRadians} — that follows the post-altar zenith hold, which
     * pins {@code cos ≈ 1} forever and would close the twilight window for the whole late
     * event. Dusk is a time-of-day story, and per the {@code EclipseSkyState} law the
     * vanilla cycle still owns time of day (moon/stars/sunrise band keep it too). The
     * same ±17°-of-horizon edge as {@link #phaseTint} gates it: dawn AND dusk fire,
     * midday and midnight are exactly 0 (bit-identical frames).</p>
     */
    private static float bloodDusk(ClientLevel level, float partialTick) {
        if (level == null || level.dimension() != Level.OVERWORLD) {
            return 0.0F;
        }
        int day = dev.projecteclipse.eclipse.client.ClientStateCache.day;
        if (day < BLOOD_DUSK_FIRST_DAY) {
            return 0.0F;
        }
        float lean = Mth.lerp(Mth.clamp(
                (day - BLOOD_DUSK_FIRST_DAY) / (float) (BLOOD_DUSK_LAST_DAY - BLOOD_DUSK_FIRST_DAY),
                0.0F, 1.0F), BLOOD_DUSK_MIN, BLOOD_DUSK_MAX);
        float angle = level.getSunAngle(partialTick);
        float edge = Mth.clamp(1.0F - Math.abs(Mth.cos(angle)) / 0.30F, 0.0F, 1.0F);
        edge = edge * edge * (3.0F - 2.0F * edge);
        return lean * edge;
    }

    // --- v7 (FX-13 B5, census N3): heartbeat dread ---------------------------------------

    /** Health (in hearts) at which the dread window starts to open. */
    private static final float DREAD_HEARTS_ENTER = 3.0F;
    /** …and at which it is fully open — a smoothstep half-heart wide, so the line never flickers. */
    private static final float DREAD_HEARTS_OPEN = 2.5F;
    /** Severity ladder floor: at one heart the beat is at full amplitude. */
    private static final float DREAD_HEARTS_LOUD = 1.0F;
    /** Amplitude at the top of the window (2.5 hearts) — "subtil bei 2.5–3 Herzen". */
    private static final float DREAD_HP_SUBTLE = 0.35F;
    /** Dread-zone floor on backrooms level 1 (the Yellow Rooms just hum). */
    private static final float DREAD_ZONE_BASE = 0.20F;
    /** …deepening per level down the stack (level 5, The Hollow, sits at 0.42). */
    private static final float DREAD_ZONE_PER_LEVEL = 0.055F;
    /** Dread with a Wanderer on top of you — the zone's own panic ceiling. */
    private static final float DREAD_ZONE_HUNTED = 0.85F;
    /** Wanderer proximity range feeding {@link #DREAD_ZONE_HUNTED} (the BackroomsBuzz hush law). */
    private static final double DREAD_HUNT_RANGE = 14.0D;
    /** Wanderer scan cadence in ticks (the UmbralVeinsFx backstop-scan law). */
    private static final int DREAD_SCAN_CADENCE = 5;
    /** Rise slew: the beat grows in over ~0.5 s instead of snapping on with the hit. */
    private static final float DREAD_RISE_PER_TICK = 0.10F;
    /** Release slew: ~1 s of fading out after healing up / leaving the zone. */
    private static final float DREAD_FALL_PER_TICK = 0.05F;
    /** Below this the dread is over: the uniform reads exactly 0 and the row is dropped. */
    private static final float MIN_DREAD = 0.002F;
    /** Cycle length at the calm end of the window (ticks) — a resting 55 bpm. */
    private static final float DREAD_PERIOD_CALM_TICKS = 22.0F;
    /** …and at full dread (ticks): ~86 bpm, the "one hit left" tempo. */
    private static final float DREAD_PERIOD_PANIC_TICKS = 14.0F;
    /** Gaussian half-width of the first (LUB) beat, seconds. */
    private static final float DREAD_LUB_SIGMA = 0.075F;
    /** Gaussian half-width of the second (DUB) beat, seconds. */
    private static final float DREAD_DUB_SIGMA = 0.060F;
    /** The DUB is the quieter of the pair. */
    private static final float DREAD_DUB_AMPLITUDE = 0.70F;
    /**
     * S1→S2 spacing in SECONDS, deliberately not a fraction of the cycle: physiologically
     * the interval barely shortens when the heart speeds up, and holding it fixed keeps
     * the fastest beat at 2 peaks / 0.70 s ≈ 2.9 Hz — under the flash ceiling the
     * {@code BackroomsFlickerOverlay} photosensitivity rule draws.
     */
    private static final float DREAD_DUB_DELAY = 0.22F;
    /** Sustain between the beats: the frame releases to this share, it does not strobe. */
    private static final float DREAD_FLOOR = 0.15F;
    /** reducedFx: one steady pressure at this share instead of the beat (no modulation). */
    private static final float DREAD_REDUCED_LEVEL = 0.45F;

    /** Eased dread severity 0..1 — the amplitude AND the tempo of the beat. */
    private static float easedDread;
    /** Heartbeat phase 0..1, accumulated per tick so a tempo change never jumps it. */
    private static float dreadPhase;
    /** Last Wanderer proximity 0..1 (0 = none in range), refreshed on the scan cadence. */
    private static float dreadHunterProximity;
    private static int dreadScanCountdown;

    /**
     * The {@code world_grade DreadPulse} uniform: the FINISHED beat strength, i.e. the
     * eased severity times the heartbeat envelope. Doing the curve here (and not in GLSL)
     * keeps the shader a two-term ALU block and this math testable.
     *
     * <p>Exactly {@code 0.0} while the dread is idle — the shader block is skipped and the
     * frame is bit-identical (the additive-uniform law). Under {@code reducedFx} the beat
     * is flattened to one steady pressure: the danger signal survives, the flicker does
     * not ({@code BackroomsFlickerOverlay}'s "one slow dim instead of the train" rule).</p>
     */
    private static float dreadPulseUniform(float partialTick) {
        if (easedDread <= MIN_DREAD) {
            return 0.0F;
        }
        if (EclipseClientConfig.reducedFx()) {
            return easedDread * DREAD_REDUCED_LEVEL;
        }
        float periodTicks = dreadPeriodTicks();
        float phase = dreadPhase + partialTick / periodTicks;
        phase -= (float) Math.floor(phase);
        return easedDread * (DREAD_FLOOR
                + (1.0F - DREAD_FLOOR) * heartbeatPulse(phase, periodTicks / 20.0F));
    }

    /**
     * The lub-dub curve — deliberately NOT a sine: two gaussian peaks, the loud S1 at
     * {@code t = 0} and the softer S2 {@value #DREAD_DUB_DELAY} s later, then a long
     * diastolic rest for the remainder of the cycle. Peak → 0.14 trough → 0.70 second
     * peak → silence.
     *
     * @param phase         cycle position in {@code [0,1)}
     * @param periodSeconds current cycle length
     * @return beat strength in {@code [0,1]}
     */
    static float heartbeatPulse(float phase, float periodSeconds) {
        float t = phase * periodSeconds;
        float lub = gaussianBeat(cyclicDistance(t, 0.0F, periodSeconds), DREAD_LUB_SIGMA);
        float dub = gaussianBeat(cyclicDistance(t, DREAD_DUB_DELAY, periodSeconds), DREAD_DUB_SIGMA);
        return Math.min(1.0F, lub + DREAD_DUB_AMPLITUDE * dub);
    }

    /** Shortest distance from {@code t} to {@code center} on a ring of length {@code period}. */
    private static float cyclicDistance(float t, float center, float period) {
        float d = Math.abs(t - center);
        return Math.min(d, period - d);
    }

    private static float gaussianBeat(float distance, float sigma) {
        float x = distance / sigma;
        return (float) Math.exp(-x * x);
    }

    /** Current cycle length: {@value #DREAD_PERIOD_CALM_TICKS} t calm → panic. */
    private static float dreadPeriodTicks() {
        return Mth.lerp(easedDread, DREAD_PERIOD_CALM_TICKS, DREAD_PERIOD_PANIC_TICKS);
    }

    /**
     * Per-tick dread slew + phase clock ({@link #tickPhaseLeanEase} law). Frozen while the
     * game is paused, so the beat holds still on the pause screen like every other eased FX
     * clock; the first thud lands the moment the dread starts (the {@code BackroomsDread}
     * pursuit-audio beat).
     */
    private static void tickDreadPulse() {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.isPaused()) {
            return;
        }
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        tickHunterScan(level, player);
        advanceDread(dreadTarget(level, player));
    }

    /**
     * Slew + phase clock — the half of {@link #tickDreadPulse} that touches no client state,
     * so the beat's rise/fall shape can be exercised without a running game.
     */
    static void advanceDread(float target) {
        boolean wasIdle = easedDread <= MIN_DREAD;
        if (easedDread < target) {
            easedDread = Math.min(target, easedDread + DREAD_RISE_PER_TICK);
        } else if (easedDread > target) {
            easedDread = Math.max(target, easedDread - DREAD_FALL_PER_TICK);
        }
        if (wasIdle && easedDread > MIN_DREAD) {
            dreadPhase = 0.0F; // the first thud lands the moment the dread starts
        } else {
            dreadPhase += 1.0F / dreadPeriodTicks();
            dreadPhase -= (float) Math.floor(dreadPhase);
        }
    }

    /** Dread target 0..1: the louder of the two independent sources (the mandate's OR). */
    private static float dreadTarget(@Nullable ClientLevel level, @Nullable LocalPlayer player) {
        if (level == null || player == null || !player.isAlive()
                || player.isSpectator() || player.isCreative()) {
            return 0.0F; // no danger, no dread — ghosts and builders keep a clean frame
        }
        return Math.max(dreadFromHearts(player.getHealth() * 0.5F), dreadFromZone(level, player));
    }

    /**
     * Source (a): the player's own hearts, read straight off {@code Minecraft.player} —
     * ABSOLUTE, not a fraction, because {@code HeartsService} hangs max health off the
     * Leben count (1 Leben = 2 hearts), and "three hearts left" has to mean the same thing
     * at every Leben stand.
     *
     * <p>The window opens over a smoothstep from {@value #DREAD_HEARTS_ENTER} down to
     * {@value #DREAD_HEARTS_OPEN} hearts (a binary line would flicker on regen ticks), and
     * the amplitude then climbs the severity ladder to full at
     * {@value #DREAD_HEARTS_LOUD} heart: 0.18 at 2.75 hearts (a whisper), 0.78 at 1.5,
     * 1.0 at one heart.</p>
     */
    static float dreadFromHearts(float hearts) {
        float window = 1.0F - Mth.clamp((hearts - DREAD_HEARTS_OPEN)
                / (DREAD_HEARTS_ENTER - DREAD_HEARTS_OPEN), 0.0F, 1.0F);
        window = window * window * (3.0F - 2.0F * window);
        float severity = Mth.clamp((DREAD_HEARTS_OPEN - hearts)
                / (DREAD_HEARTS_OPEN - DREAD_HEARTS_LOUD), 0.0F, 1.0F);
        return window * (DREAD_HP_SUBTLE + (1.0F - DREAD_HP_SUBTLE) * severity);
    }

    /**
     * Source (b): dread zones. The backrooms dread system is server-side
     * ({@code BackroomsDread} sends sounds and the flicker envelope, it syncs no level), so
     * the client reads the zone off the two public facts it already has — the dimension
     * ({@code BackroomsDimension.isBackrooms}) and the depth
     * ({@code BackroomsLayers.layerOf}) — plus how close the Wanderer is, exactly the
     * hush-when-stalked signal {@code client.backrooms.BackroomsBuzz} keys its volume off.
     * No new packet, no new hook in a foreign class.
     *
     * <p>The floor stays low ({@value #DREAD_ZONE_BASE} on level 1 …0.42 in The Hollow) so
     * a 20-minute instance does not become one long drone; the beat only swells toward
     * {@value #DREAD_ZONE_HUNTED} while something is actually walking up on you.</p>
     */
    private static float dreadFromZone(ClientLevel level, LocalPlayer player) {
        if (!BackroomsDimension.isBackrooms(level.dimension())) {
            return 0.0F;
        }
        int depth = BackroomsLayers.layerOf(player.getBlockY()).level();
        float base = Math.min(DREAD_ZONE_HUNTED,
                DREAD_ZONE_BASE + DREAD_ZONE_PER_LEVEL * (depth - 1));
        return base + (DREAD_ZONE_HUNTED - base) * dreadHunterProximity;
    }

    /**
     * Refreshes {@link #dreadHunterProximity} every {@value #DREAD_SCAN_CADENCE} ticks
     * while the player is in the backrooms (and zeroes it everywhere else). Client-side
     * entity read only — the slew smooths the cadence steps away.
     */
    private static void tickHunterScan(@Nullable ClientLevel level, @Nullable LocalPlayer player) {
        if (level == null || player == null || !BackroomsDimension.isBackrooms(level.dimension())) {
            dreadHunterProximity = 0.0F;
            dreadScanCountdown = 0;
            return;
        }
        if (--dreadScanCountdown > 0) {
            return;
        }
        dreadScanCountdown = DREAD_SCAN_CADENCE;
        double nearestSqr = DREAD_HUNT_RANGE * DREAD_HUNT_RANGE;
        for (GlitchedWandererEntity wanderer : level.getEntitiesOfClass(
                GlitchedWandererEntity.class, player.getBoundingBox().inflate(DREAD_HUNT_RANGE))) {
            nearestSqr = Math.min(nearestSqr, wanderer.distanceToSqr(player));
        }
        dreadHunterProximity = 1.0F - (float) (Math.sqrt(nearestSqr) / DREAD_HUNT_RANGE);
    }

    /** Dev/QA introspection: the eased dread severity currently driving the beat. */
    public static float dreadSeverity() {
        return easedDread;
    }

    /** R3: {@code clamp(1 − dayFactor) · 0.55} — overworld only (the nether has no day cycle). */
    private static float nightAmount(ClientLevel level, float partialTick) {
        if (level.dimension() != Level.OVERWORLD) {
            return 0.0F;
        }
        float dayFactor = dev.projecteclipse.eclipse.client.sky.OverworldPurpleEffects.dayFactor(level, partialTick);
        return Mth.clamp(1.0F - dayFactor, 0.0F, 1.0F) * 0.55F;
    }

    // --- sun_halo ------------------------------------------------------------------------

    /** Eased CPU occlusion for the halo (~6-tick slew — glow fades instead of popping). */
    private static float easedRimOnly;
    /** RimOnly slew per tick: full binary transition in ~6 ticks (0.3 s). */
    private static final float RIM_ONLY_SLEW = 0.18F;

    private static boolean wantSunHalo() {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || level.dimension() != Level.OVERWORLD) {
            return false;
        }
        return SunTracker.sunScreen().z() > 0.5F && haloStrength(level, partialTick()) > 0.01F;
    }

    private static void feedSunHalo(PostPipeline pipeline) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        pipeline.getUniform("SunScreen").setVector(SunTracker.sunScreen());
        pipeline.getUniform("HaloStrength").setFloat(haloStrength(level, partialTick()));
        // v2 (FX team GRADE): RimOnly is now the ~6-tick eased 0..1 amount (the shader
        // always clamped it, so the semantics only widened — never a breaking change).
        pipeline.getUniform("RimOnly").setFloat(easedRimOnly);
        pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 3_600_000L) / 1000.0F);
        pipeline.getUniform("Detail").setFloat(EclipseClientConfig.reducedFx() ? 0.0F : 1.0F);
        // v3 (VEIL-REPASS-1): halo color temperature rides the synced altar level. The
        // clamp-to-5 normalization is the established client convention (AltarVeilSky,
        // AltarIdleMotes, SanctumHum all read the same ladder).
        pipeline.getUniform("AltarWarmth").setFloat(
                Mth.clamp(dev.projecteclipse.eclipse.client.ClientStateCache.altarLevel, 0, 5) / 5.0F);
        // v4 (FX-13 A9): the black-sun snap rides the TotalityPeakFx crest timeline —
        // the same crest that spawns the Photon diamond ring. 0 outside the peak beat.
        pipeline.getUniform("SunSnap").setFloat(TotalityPeakFx.snapAmount(partialTick()));
    }

    /** Per-tick slew of the binary {@link SunTracker#sunOccluded} probe toward 0/1. */
    private static void tickSunOcclusionEase() {
        float target = SunTracker.sunOccluded() ? 1.0F : 0.0F;
        if (easedRimOnly < target) {
            easedRimOnly = Math.min(target, easedRimOnly + RIM_ONLY_SLEW);
        } else if (easedRimOnly > target) {
            easedRimOnly = Math.max(target, easedRimOnly - RIM_ONLY_SLEW);
        }
    }

    /**
     * Halo strength curve (R1/R2/R10): fades in with sun elevation and out with rain, grows
     * with the eclipse amount (up to a ~0.55-NDC glow), and never drops below the permanent-rim
     * floor of 0.15 once the intro has ended.
     */
    private static float haloStrength(ClientLevel level, float partialTick) {
        float dirY = Mth.cos(SunTracker.sunAngleRadians(level, partialTick));
        float elevation = Mth.clamp(dirY * 6.0F + 0.05F, 0.0F, 1.0F);
        float rain = level.getRainLevel(partialTick);
        float base = (1.0F - rain * 0.85F) * (0.45F + 0.9F * EclipseFxState.eclipseAmount(partialTick));
        if (EclipseFxState.permanentSunRim()) {
            base = Math.max(base, 0.15F);
        }
        return elevation * base;
    }

    // ------------------------------------------------------------------ engine

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Per-frame uniform feed; fires only while one of our pipelines is actually active.
        try {
            VeilEventPlatform.INSTANCE.preVeilPostProcessing((name, pipeline, context) -> {
                Row row = ROWS.get(name);
                if (row == null) {
                    return;
                }
                try {
                    row.spec().uniformFeeder().accept(pipeline);
                } catch (Throwable t) {
                    recordFailure(name, t);
                }
            });
        } catch (Throwable t) {
            EclipseMod.LOGGER.warn("Failed to register Veil post-processing uniform hook; Eclipse post FX disabled", t);
            DISABLED.addAll(ROWS.keySet());
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        tickSunOcclusionEase();
        tickPhaseLeanEase();
        tickDreadPulse();
        boolean gate = EclipseIrisState.postFxAllowed();
        DESIRED.clear();
        if (gate) {
            for (Row row : ROWS.values()) {
                if (DISABLED.contains(row.spec().id())) {
                    continue;
                }
                Boolean forced = OVERRIDES.get(row.spec().id());
                boolean wanted;
                try {
                    wanted = forced != null ? forced : row.spec().activationPredicate().getAsBoolean();
                } catch (Throwable t) {
                    recordFailure(row.spec().id(), t);
                    continue;
                }
                if (wanted) {
                    DESIRED.add(row);
                }
            }
            // Over budget: lowest priority drops first (GRADE < FEATURE < TRANSITION),
            // later registrations drop before earlier ones within the same priority.
            DESIRED.sort(EVICTION_ORDER);
            while (DESIRED.size() > MAX_CONCURRENT) {
                DESIRED.remove(DESIRED.size() - 1);
            }
        }
        for (Row row : ROWS.values()) {
            setPipelineActive(row, DESIRED.contains(row));
        }
    }

    /**
     * Disconnect reset hook: drops fades/overrides and removes every Eclipse pipeline
     * immediately. A Veil call that throws during disconnect teardown must not count toward
     * the {@value #MAX_FAILURES}-strikes session disable — so this path removes quietly, and
     * a limbo session can never leak its grade into the next world.
     */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        OVERRIDES.clear();
        easedPhaseLean = 0.0F; // the color script never leaks into the next session
        easedDread = 0.0F; // …and neither does the heartbeat (FX-13 B5)
        dreadPhase = 0.0F;
        dreadHunterProximity = 0.0F;
        dreadScanCountdown = 0;
        synchronized (VeilPostController.class) {
            for (Row row : ROWS.values()) {
                removeQuietly(row.spec().id());
            }
        }
    }

    /** Best-effort removal that never counts as a pipeline failure (teardown-order safe). */
    private static void removeQuietly(ResourceLocation pipeline) {
        try {
            PostProcessingManager manager = VeilRenderSystem.renderer().getPostProcessingManager();
            if (manager.isActive(pipeline)) {
                manager.remove(pipeline);
            }
        } catch (Throwable ignored) {
            // Veil may already be tearing down; the next-tick gate re-removes if needed.
        }
    }

    private static void setPipelineActive(Row row, boolean wanted) {
        ResourceLocation pipeline = row.spec().id();
        if (DISABLED.contains(pipeline)) {
            return;
        }
        try {
            PostProcessingManager manager = VeilRenderSystem.renderer().getPostProcessingManager();
            boolean active = manager.isActive(pipeline);
            if (wanted && !active) {
                manager.add(row.spec().priority().managerPriority, pipeline);
            } else if (active && !wanted) {
                manager.remove(pipeline);
            }
        } catch (Throwable t) {
            recordFailure(pipeline, t);
        }
    }

    private static float partialTick() {
        return Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
    }

    private static void recordFailure(ResourceLocation pipeline, Throwable t) {
        int count;
        synchronized (FAILURES) {
            count = FAILURES.merge(pipeline, 1, Integer::sum);
        }
        if (count == 1) {
            EclipseMod.LOGGER.warn("Veil post pipeline {} threw; retrying", pipeline, t);
        } else if (count >= MAX_FAILURES && DISABLED.add(pipeline)) {
            EclipseMod.LOGGER.warn("Veil post pipeline {} failed {} times; disabling it for this session", pipeline, count);
            try {
                VeilRenderSystem.renderer().getPostProcessingManager().remove(pipeline);
            } catch (Throwable ignored) {
                // Removing a broken pipeline is best-effort; it is disabled either way.
            }
        }
    }
}
