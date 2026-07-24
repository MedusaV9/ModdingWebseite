package dev.projecteclipse.eclipse.cutscene.dev;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.platform.VeilEventPlatform;
import net.minecraft.ChatFormatting;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.RenderGuiEvent;
import org.joml.Vector4f;

/**
 * Client executor for {@code /eclipsefx}'s client-side dev actions (P2 R12), fed by
 * {@link FxDevPayloads}: Veil post pipeline force-on/off ({@code VeilPostController}
 * overrides), per-uniform float overrides (applied through an own
 * {@code preVeilPostProcessing} hook — note a value also fed per-frame by the pipeline's own
 * feeder may win depending on hook order; plain debug uniforms stick), Quasar emitter test
 * spawns, and the sun-debug HUD cross ({@code /eclipsefx sun debug}) that draws a crosshair
 * at {@link SunTracker#sunScreen()} so the CPU projection can be compared against the
 * rendered disc/halo by eye (W1 acceptance: ≤ 0.5° apart while sprint-strafing).
 *
 * <p>All state is dev-session-scoped and clears on logout.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FxDevClient {
    /** Pipelines probed by {@code post list} (registered rows + planned feature ids). */
    private static final ResourceLocation[] KNOWN_PIPELINES = {
            VeilPostController.WORLD_GRADE_POST,
            VeilPostController.SUN_HALO_POST,
            VeilPostController.LIMBO_POST,
            VeilPostController.BORDER_GLITCH_POST,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "shockwave"),
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_aberration"),
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "storm_interior"),
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_glitch"),
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ghost_grade"),
    };

    /** Forced uniform floats by pipeline → (uniform → value). Applied pre-post-processing. */
    private static final Map<ResourceLocation, Map<String, Float>> UNIFORM_OVERRIDES = new ConcurrentHashMap<>();
    private static volatile boolean sunDebugHud;

    private FxDevClient() {}

    /** Entry point from {@link FxDevPayloads} (client main thread). */
    public static void handle(FxDevPayloads.S2CFxDevActionPayload payload) {
        switch (payload.action()) {
            case FxDevPayloads.ACTION_POST_ON -> setPost(payload.arg(), Boolean.TRUE);
            case FxDevPayloads.ACTION_POST_OFF -> setPost(payload.arg(), Boolean.FALSE);
            case FxDevPayloads.ACTION_POST_CLEAR -> setPost(payload.arg(), null);
            case FxDevPayloads.ACTION_POST_LIST -> listPipelines();
            case FxDevPayloads.ACTION_UNIFORM -> setUniform(payload.arg(), payload.value());
            case FxDevPayloads.ACTION_EMITTER -> spawnEmitter(payload.arg(), payload);
            case FxDevPayloads.ACTION_SUN_DEBUG -> toggleSunDebug();
            default -> EclipseMod.LOGGER.warn("FxDevClient: unknown dev action {}", payload.action());
        }
    }

    // --- post pipeline overrides ---

    private static void setPost(String pipelineId, Boolean forced) {
        ResourceLocation id = ResourceLocation.tryParse(pipelineId);
        if (id == null) {
            feedback("Bad pipeline id: " + pipelineId, ChatFormatting.RED);
            return;
        }
        if (forced == null) {
            VeilPostController.clearOverride(id);
            feedback("post " + id + " → predicate-driven", ChatFormatting.YELLOW);
        } else {
            VeilPostController.setEnabled(id, forced);
            feedback("post " + id + " → forced " + (forced ? "ON" : "OFF")
                    + " (takes effect if the pipeline is registered)", forced ? ChatFormatting.GREEN : ChatFormatting.RED);
        }
    }

    private static void listPipelines() {
        feedback("Eclipse post pipelines (active in Veil right now):", ChatFormatting.GOLD);
        for (ResourceLocation id : KNOWN_PIPELINES) {
            boolean active = VeilPostController.isActive(id);
            feedback("  " + id + " — " + (active ? "ACTIVE" : "off"),
                    active ? ChatFormatting.GREEN : ChatFormatting.GRAY);
        }
    }

    // --- uniform overrides ---

    private static void setUniform(String arg, float value) {
        int split = arg.indexOf('|');
        if (split <= 0 || split >= arg.length() - 1) {
            feedback("Bad uniform arg: " + arg, ChatFormatting.RED);
            return;
        }
        ResourceLocation pipeline = ResourceLocation.tryParse(arg.substring(0, split));
        String uniform = arg.substring(split + 1);
        if (pipeline == null) {
            feedback("Bad pipeline id in: " + arg, ChatFormatting.RED);
            return;
        }
        UNIFORM_OVERRIDES.computeIfAbsent(pipeline, key -> new ConcurrentHashMap<>()).put(uniform, value);
        feedback("uniform " + pipeline + " " + uniform + " = " + value
                + " (per-frame feeders may still win for fed uniforms)", ChatFormatting.GREEN);
    }

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        try {
            VeilEventPlatform.INSTANCE.preVeilPostProcessing((name, pipeline, context) -> {
                Map<String, Float> overrides = UNIFORM_OVERRIDES.get(name);
                if (overrides == null || overrides.isEmpty()) {
                    return;
                }
                for (Map.Entry<String, Float> entry : overrides.entrySet()) {
                    try {
                        pipeline.getUniform(entry.getKey()).setFloat(entry.getValue());
                    } catch (Throwable t) {
                        // Dev tool: a bad uniform name must never break the pipeline.
                    }
                }
            });
        } catch (Throwable t) {
            EclipseMod.LOGGER.warn("FxDevClient: uniform-override hook unavailable", t);
        }
    }

    // --- emitter test spawns ---

    private static void spawnEmitter(String emitterId, FxDevPayloads.S2CFxDevActionPayload payload) {
        ResourceLocation id = ResourceLocation.tryParse(emitterId);
        if (id == null) {
            feedback("Bad emitter id: " + emitterId, ChatFormatting.RED);
            return;
        }
        boolean spawned = QuasarSpawner.spawn(id, payload.pos());
        feedback("emitter " + id + (spawned ? " spawned at " : " FAILED (missing/budget) at ")
                + String.format("%.1f %.1f %.1f", payload.pos().x, payload.pos().y, payload.pos().z),
                spawned ? ChatFormatting.GREEN : ChatFormatting.RED);
    }

    // --- sun debug HUD ---

    private static void toggleSunDebug() {
        sunDebugHud = !sunDebugHud;
        feedback("sun debug HUD " + (sunDebugHud ? "ON" : "OFF"), ChatFormatting.GOLD);
    }

    /**
     * Drawn via {@code RenderGuiEvent.Post} (outside the layered GUI system, so cutscene HUD
     * suppression never hides it): magenta cross + readout at the CPU-projected sun point.
     */
    @SubscribeEvent
    static void onRenderGui(RenderGuiEvent.Post event) {
        if (!sunDebugHud) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            return;
        }
        GuiGraphics guiGraphics = event.getGuiGraphics();
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        Vector4f sun = SunTracker.sunScreen();
        boolean visible = sun.z() > 0.5F;
        String readout = String.format("SunScreen ndc=(%.3f, %.3f) r=%.3f %s%s",
                sun.x(), sun.y(), sun.w(),
                visible ? "visible" : "off-screen/behind",
                SunTracker.sunOccluded() ? " OCCLUDED" : "");
        guiGraphics.drawString(minecraft.font, readout, 4, height - 12, 0xFFFF55FF, true);
        if (!visible) {
            return;
        }
        int x = Math.round((sun.x() * 0.5F + 0.5F) * width);
        int y = Math.round((1.0F - (sun.y() * 0.5F + 0.5F)) * height);
        int argb = 0xFFFF55FF;
        guiGraphics.hLine(x - 6, x + 6, y, argb);
        guiGraphics.vLine(x, y - 6, y + 6, argb);
        // Ring of the projected radius (w = NDC radius → half-height pixels).
        int radius = Math.max(2, Math.round(sun.w() * 0.5F * height));
        guiGraphics.hLine(x - radius, x - radius + 2, y, argb);
        guiGraphics.hLine(x + radius - 2, x + radius, y, argb);
        guiGraphics.vLine(x, y - radius, y - radius + 2, argb);
        guiGraphics.vLine(x, y + radius - 2, y + radius, argb);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        sunDebugHud = false;
        UNIFORM_OVERRIDES.clear();
        // VeilPostController clears its own overrides on logout.
    }

    private static void feedback(String message, ChatFormatting color) {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player != null) {
            player.displayClientMessage(Component.literal(message).withStyle(color), false);
        } else {
            EclipseMod.LOGGER.info("FxDevClient: {}", message);
        }
    }

    /** Insertion-ordered copy of the active uniform overrides (debug/inspection). */
    public static Map<ResourceLocation, Map<String, Float>> uniformOverrides() {
        Map<ResourceLocation, Map<String, Float>> copy = new LinkedHashMap<>();
        UNIFORM_OVERRIDES.forEach((id, map) -> copy.put(id, Map.copyOf(map)));
        return copy;
    }
}
