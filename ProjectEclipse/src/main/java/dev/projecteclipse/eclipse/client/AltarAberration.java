package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
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

    /** Client-side eased zone strength; the fed uniform adds the 0.3 Hz breathing on top. */
    private static float eased;

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
        EclipseFxState.setAltarAberration(eased);
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

    /** 0.3 Hz breathing is baked into the fed value so the shader keeps the ONE frozen uniform. */
    private static void feedPost(PostPipeline pipeline) {
        float seconds = (System.currentTimeMillis() % 100_000L) / 1000.0F;
        float breath = 0.9F + 0.1F * Mth.sin(seconds * (float) (Math.PI * 2.0D) * BREATH_HZ);
        pipeline.getUniform("Aberration").setFloat(EclipseFxState.altarAberration() * breath);
    }
}
