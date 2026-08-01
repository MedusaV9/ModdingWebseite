package dev.projecteclipse.eclipse.cutscene.dev;

import java.util.LinkedHashMap;
import java.util.Locale;
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
    /**
     * WAVE5 (F-105 A) A7: mirror of the F-104 streak-hold state. {@code
     * LimboSpecialEffects} exposes only the setter (its flag is private by design),
     * and this class is that setter's single caller — the mirror therefore stays in
     * lockstep and the {@code /eclipsefx holds} inventory can report it read-only
     * without widening the frozen sky-pass surface. Cleared on logout together with
     * the hold itself.
     */
    private static volatile boolean limboStreakHoldOn;

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
            case FxDevPayloads.ACTION_PHOTON_STATUS -> photonStatus();
            case FxDevPayloads.ACTION_PHOTON_TEST -> photonTest(payload.arg(), payload.pos());
            case FxDevPayloads.ACTION_STORM_FLASHHOLD -> stormFlashHold("on".equals(payload.arg()), payload.value());
            case FxDevPayloads.ACTION_STORM_PERFPROBE -> FrameTimeProbe.start(payload.value());
            case FxDevPayloads.ACTION_LIMBO_STREAKHOLD -> limboStreakHold("on".equals(payload.arg()));
            // WAVE5 (F-105 A): A1 wakehold, A2 flickerhold, A7 hold inventory.
            case FxDevPayloads.ACTION_LIMBO_WAKEHOLD -> limboWakeHold("on".equals(payload.arg()));
            case FxDevPayloads.ACTION_TYRANT_FLICKERHOLD -> tyrantFlickerHold(payload.arg());
            case FxDevPayloads.ACTION_HOLDS_STATUS -> holdsStatus();
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

    // --- photon dev commands (PH-CORE) ---

    /** {@code /dev photon status} — PhotonBridge + PhotonFxRegistry state dump. */
    private static void photonStatus() {
        var bridge = dev.projecteclipse.eclipse.veilfx.PhotonBridge.class; // client-only sibling
        boolean loaded = net.neoforged.fml.ModList.get().isLoaded("photon");
        boolean available = dev.projecteclipse.eclipse.veilfx.PhotonBridge.available();
        feedback("Photon bridge (" + bridge.getSimpleName() + "):", ChatFormatting.GOLD);
        feedback("  mod loaded: " + loaded
                + " | photonFx: " + dev.projecteclipse.eclipse.core.config.EclipseClientConfig.photonFx()
                + " | reducedFx: " + dev.projecteclipse.eclipse.core.config.EclipseClientConfig.reducedFx()
                + " | reflection: " + dev.projecteclipse.eclipse.veilfx.PhotonBridge.stateName(),
                loaded ? ChatFormatting.GREEN : ChatFormatting.GRAY);
        feedback("  available now: " + available, available ? ChatFormatting.GREEN : ChatFormatting.RED);
        feedback("  executors: " + dev.projecteclipse.eclipse.veilfx.PhotonBridge.liveExecutors()
                + "/" + dev.projecteclipse.eclipse.veilfx.PhotonBridge.MAX_LIVE_EXECUTORS
                + " live (" + dev.projecteclipse.eclipse.veilfx.PhotonBridge.liveLoops() + " loops), "
                + dev.projecteclipse.eclipse.veilfx.PhotonBridge.refusedCount() + " budget refusals",
                ChatFormatting.GRAY);
        // WAVE5 (F-105 A) A3 / W4A Q2 closeout: template-hygiene counters (healthy: 0/0).
        long scrubs = dev.projecteclipse.eclipse.veilfx.PhotonBridge.hygieneDirtyScrubs();
        long links = dev.projecteclipse.eclipse.veilfx.PhotonBridge.hygieneLinksRemoved();
        feedback("  hygiene: scrubs=" + scrubs + " links=" + links,
                scrubs == 0 && links == 0 ? ChatFormatting.GRAY : ChatFormatting.YELLOW);
        var missing = dev.projecteclipse.eclipse.veilfx.PhotonBridge.missingFxIds();
        if (!missing.isEmpty()) {
            feedback("  missing/broken fx this session: " + missing, ChatFormatting.YELLOW);
        }
        var rows = dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.registeredIds();
        feedback("  registry rows (" + rows.size() + "), "
                + dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.liveLoopWindows()
                + " live loop windows:", ChatFormatting.GOLD);
        for (ResourceLocation id : rows.stream().sorted().toList()) {
            var row = dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.row(id);
            feedback("    " + id + " -> " + row.photonFx() + " (" + row.mode()
                    + (row.loop() ? ", LOOP" : "") + ", quasar "
                    + (row.quasarEmitter() == null ? "none" : row.quasarEmitter()) + ")",
                    ChatFormatting.GRAY);
        }
    }

    /**
     * {@code /dev photon test <fxId>} — a registered cue id goes through the full
     * {@code PhotonFxRegistry.dispatch} lane (Photon + Quasar legs per row mode); anything
     * else spawns directly through {@code PhotonBridge} with {@code allowMulti} so repeated
     * tests always fire.
     */
    private static void photonTest(String fxId, net.minecraft.world.phys.Vec3 pos) {
        ResourceLocation id = ResourceLocation.tryParse(fxId);
        if (id == null) {
            feedback("Bad fx id: " + fxId, ChatFormatting.RED);
            return;
        }
        String at = String.format("%.1f %.1f %.1f", pos.x, pos.y, pos.z);
        if (dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.row(id) != null) {
            boolean consumed = dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry.dispatch(id, pos);
            feedback("cue " + id + (consumed ? " dispatched at " : " NOT consumed at ") + at
                    + " (loop rows are windowed-only and warn instead of playing)",
                    consumed ? ChatFormatting.GREEN : ChatFormatting.RED);
            return;
        }
        boolean spawned = dev.projecteclipse.eclipse.veilfx.PhotonBridge.spawn(id, pos,
                dev.projecteclipse.eclipse.veilfx.PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
        feedback("photon " + id + (spawned ? " spawned at " : " FAILED at ") + at
                + (spawned ? "" : " (photon absent/toggled off, missing .fx, or executor budget"
                + " — see '/dev photon status')"),
                spawned ? ChatFormatting.GREEN : ChatFormatting.RED);
    }

    // --- storm flash hold (POLISH4) ---

    /**
     * {@code /eclipsefx storm flashhold} — flips the client-visual B6 flash-HOLD
     * override ({@code StormFlashDevHold}); the volume feed then forces both flash
     * cells to the held envelope with a slowly cycling vein seed. OFF is the
     * bit-identical shipped path (see the StormFlashDevHold idle rule).
     */
    private static void stormFlashHold(boolean on, float amount) {
        dev.projecteclipse.eclipse.stormfx.StormFlashDevHold.set(on, amount);
        feedback(on
                ? String.format(Locale.ROOT, "storm flashhold ON — both B6 cells held at %.2f,"
                        + " vein seed cycles every 2 s (volume feed only; scheduler untouched)",
                        amount)
                : "storm flashhold OFF — live 7-tick flash scheduler restored (bit-identical)",
                on ? ChatFormatting.GREEN : ChatFormatting.YELLOW);
    }

    // --- limbo streak hold (F-104) ---

    /**
     * {@code /eclipsefx limbo streakhold} — flips the client-visual F-104 shooting-streak
     * HOLD ({@code LimboSpecialEffects.setStreakHold}); the limbo sky pass then draws one
     * green streak frozen mid-flight at a fixed dome spot every frame. The streak
     * schedule rides the SECOND-based sky clock, which {@code tick rate 2} does NOT
     * stretch — the hold is the only way to photograph the 0.9&nbsp;s event on a
     * software-rendered rig. OFF is the bit-identical shipped schedule (no residue).
     */
    private static void limboStreakHold(boolean on) {
        dev.projecteclipse.eclipse.client.sky.LimboSpecialEffects.setStreakHold(on);
        limboStreakHoldOn = on; // WAVE5 (F-105 A) A7: keep the holds-inventory mirror in step.
        feedback(on
                ? "limbo streakhold ON — one green streak held mid-flight at a fixed dome spot"
                        + " (look ~17\u00b0 starboard of the bow heading, ~55\u00b0 up);"
                        + " the sky clock is second-based, so tick rate tweaks cannot stretch it"
                : "limbo streakhold OFF — deterministic streak schedule restored (no residue)",
                on ? ChatFormatting.GREEN : ChatFormatting.YELLOW);
    }

    // --- limbo blade-wake hold (WAVE5 F-105 A, A1) ---

    /**
     * {@code /eclipsefx limbo wakehold} — flips the client-visual blade-wake HOLD
     * ({@code DeckhandRenderer.setLimboWakeHold}): every visible rowing deckhand then
     * re-fires its C2 catch splash + F-104 ghost wake throttled (min. every 10t level
     * time per rower), independent of the 60t row anchor — the only way to photograph
     * the sub-2s wake on a software-rendered rig. Draws as an explicit operator
     * override even under {@code reducedFx} (streakhold precedent). OFF is the
     * bit-identical shipped C2/C2-R2 path (the hold branch is the flag's only
     * consumer).
     */
    private static void limboWakeHold(boolean on) {
        dev.projecteclipse.eclipse.client.entity.DeckhandRenderer.setLimboWakeHold(on);
        feedback(on
                ? "limbo wakehold ON — every visible rower re-fires splash+ghost-wake every ~10t"
                        + " (anchor-independent, full fleck count even under reducedFx);"
                        + " grep \"[w5a-wakehold]\" in the debug log for fire counts"
                : "limbo wakehold OFF — live 60t catch-splash path restored (bit-identical,"
                        + " [c2-splash] keeps running)",
                on ? ChatFormatting.GREEN : ChatFormatting.YELLOW);
    }

    // --- tyrant desperation-flicker hold (WAVE5 F-105 A, A2) ---

    /**
     * {@code /eclipsefx tyrant flickerhold} — overrides the Fog Tyrant's desperation
     * blackout ({@code FogTyrantRenderer.setTyrantFlickerHold}): {@code blackout} pins
     * the emissive dropout permanently, {@code on} stretches the 1–2t stutter to a
     * 20t-on/20t-off cadence, {@code off} restores the live phase-3-gated SplitMix64
     * hash schedule bit-identically. Phase-independent — the hold is the photo aid,
     * the live path stays phase-3-gated.
     */
    private static void tyrantFlickerHold(String mode) {
        int hold = switch (mode) {
            case "blackout" -> dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_BLACKOUT;
            case "on" -> dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_CADENCE;
            default -> dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_OFF;
        };
        dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.setTyrantFlickerHold(hold);
        feedback(switch (hold) {
            case dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_BLACKOUT ->
                    "tyrant flickerhold BLACKOUT — emissive pass held dark (crown/eye slit/storm-core off)";
            case dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_CADENCE ->
                    "tyrant flickerhold ON — stretched 20t-dark/20t-lit blackout cadence";
            default -> "tyrant flickerhold OFF — live phase-3 hash schedule restored (bit-identical)";
        }, hold == dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_OFF
                ? ChatFormatting.YELLOW : ChatFormatting.GREEN);
    }

    // --- dev-hold inventory (WAVE5 F-105 A, A7) ---

    /**
     * {@code /eclipsefx holds} — read-only status of the four client-side dev holds,
     * so a stale hold cannot silently poison later acceptance photos. flashhold reads
     * the existing {@code StormFlashDevHold.active()} getter (Team-B file, read-only);
     * streakhold reads this class's own mirror (see {@link #limboStreakHoldOn}).
     */
    private static void holdsStatus() {
        boolean flash = dev.projecteclipse.eclipse.stormfx.StormFlashDevHold.active();
        boolean streak = limboStreakHoldOn;
        boolean wake = dev.projecteclipse.eclipse.client.entity.DeckhandRenderer.limboWakeHold();
        int flicker = dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.tyrantFlickerHold();
        String flickerName = switch (flicker) {
            case dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_BLACKOUT -> "BLACKOUT";
            case dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_CADENCE -> "ON (20t cadence)";
            default -> "off";
        };
        boolean anyHeld = flash || streak || wake
                || flicker != dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_OFF;
        feedback("Eclipse dev holds (client-side, all clear on logout):", ChatFormatting.GOLD);
        feedback("  storm flashhold  — " + (flash ? "HELD" : "off"),
                flash ? ChatFormatting.GREEN : ChatFormatting.GRAY);
        feedback("  limbo streakhold — " + (streak ? "HELD" : "off"),
                streak ? ChatFormatting.GREEN : ChatFormatting.GRAY);
        feedback("  limbo wakehold   — " + (wake ? "HELD" : "off"),
                wake ? ChatFormatting.GREEN : ChatFormatting.GRAY);
        feedback("  tyrant flickerhold — " + flickerName,
                flicker != dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_OFF
                        ? ChatFormatting.GREEN : ChatFormatting.GRAY);
        if (anyHeld) {
            feedback("  ⚠ switch every hold off before non-hold acceptance photos", ChatFormatting.YELLOW);
        }
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
        // F-104 dev-session hygiene: no streak hold survives a disconnect.
        dev.projecteclipse.eclipse.client.sky.LimboSpecialEffects.setStreakHold(false);
        limboStreakHoldOn = false;
        // WAVE5 (F-105 A) hygiene: wakehold + flickerhold clear with the session too.
        dev.projecteclipse.eclipse.client.entity.DeckhandRenderer.setLimboWakeHold(false);
        dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.setTyrantFlickerHold(
                dev.projecteclipse.eclipse.client.entity.fogboss.FogTyrantRenderer.FLICKER_HOLD_OFF);
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
