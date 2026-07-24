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

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.sky.EclipseIrisState;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.post.PostPipeline;
import foundry.veil.api.client.render.post.PostProcessingManager;
import foundry.veil.platform.VeilEventPlatform;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
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

    private static boolean wantWorldGrade() {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return false;
        }
        boolean gradedDimension = level.dimension() == Level.OVERWORLD || level.dimension() == Level.NETHER;
        if (!gradedDimension) {
            return false; // limbo owns its own grade
        }
        float partialTick = partialTick();
        return nightAmount(level, partialTick) > 0.01F || EclipseFxState.eclipseAmount(partialTick) > 0.01F;
    }

    private static void feedWorldGrade(PostPipeline pipeline) {
        ClientLevel level = Minecraft.getInstance().level;
        float partialTick = partialTick();
        float eclipse = EclipseFxState.eclipseAmount(partialTick);
        pipeline.getUniform("EclipseAmount").setFloat(eclipse);
        pipeline.getUniform("NightAmount").setFloat(level == null ? 0.0F : nightAmount(level, partialTick));
        pipeline.getUniform("DesatAmount").setFloat(eclipse * 0.5F);
        pipeline.getUniform("ExposureMul").setFloat(EclipseFxState.exposureMul(partialTick));
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
        pipeline.getUniform("RimOnly").setFloat(SunTracker.sunOccluded() ? 1.0F : 0.0F);
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
