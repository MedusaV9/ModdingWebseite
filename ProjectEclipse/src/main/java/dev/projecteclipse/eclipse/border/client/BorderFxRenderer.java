package dev.projecteclipse.eclipse.border.client;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.MeshData;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import javax.annotation.Nullable;

import org.joml.Vector3f;
import org.joml.Vector4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.sound.BorderStaticSound;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.SunTracker;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Camera;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * Client visuals of the circular soft border, v2 (P2 R6): <b>localized glitch patches</b>
 * instead of the old ±25° arc strip that read as a long wall stripe. Three layers, all
 * invisible until the camera is within {@code fxRange} (server-synced, default 8) of the
 * ring, and ZERO cost while far (a single d² early-out per frame/tick):
 * <ol>
 *   <li><b>Geometry</b> ({@link RenderLevelStageEvent} AFTER_PARTICLES):
 *       {@value #MIN_CLUSTERS}–{@value #MAX_CLUSTERS} small quad clusters (each quad
 *       {@value #PATCH_MIN_SIZE}–{@value #PATCH_MAX_SIZE} blocks, random offsets/rotations,
 *       additive, {@code border_glitch.png} UV-jittered) pinned to the ring <b>only within
 *       ±{@value #ARC_HALF_DEGREES}° of the player's bearing</b> (further clamped to
 *       ±{@value #ARC_HALF_BLOCKS_CAP} blocks of arc on huge rings) and near the player's
 *       eye height — never a full-height wall. The whole field re-seeds every
 *       {@value #RESEED_MIN_TICKS}–{@value #RESEED_MAX_TICKS} ticks, so patches pop
 *       in/out like datamosh blocks instead of scrolling like a texture wall. Budget
 *       ≤ {@value #MAX_CLUSTERS}×{@value #MAX_QUADS_PER_CLUSTER} quads (§3.5 cap 240).
 *       Vertices are camera-relative; at AFTER_PARTICLES the global modelview stack
 *       already carries the frustum matrix, so the vanilla-border draw pattern
 *       (position_tex_color + {@link BufferUploader#drawWithShader}) applies unchanged.
 *       If depth-sorting artifacts appear under Sodium, switch {@link #RENDER_STAGE} to
 *       AFTER_TRANSLUCENT_BLOCKS — both fire with the same matrices.</li>
 *   <li><b>Particles</b>: {@code BORDER_GLITCH} Quasar bursts at cluster positions
 *       (throttled to one per {@value #QUASAR_INTERVAL_TICKS} client ticks, doubled at
 *       reduced quality) plus blocky {@code border_shard} pops on re-seed — all charged to
 *       {@link FxBudget.Channel#BURST}.</li>
 *   <li><b>Veil post</b>: the per-tick proximity is fed to
 *       {@link EclipseFxState#setBorderProximity} and this class registers the
 *       {@code eclipse:border_glitch} v2 pipeline row (replacing W1's backward-compat row):
 *       uniforms {@code Proximity, Time, GlitchDir, Seed} (§3.3 frozen). {@code GlitchDir}
 *       is the screen-space (NDC) position of the nearest ring point, projected per frame
 *       through {@link SunTracker#worldToNdc} — the shader masks its tearing/datamosh to a
 *       lens around that point, so the post effect stays glued to the border direction
 *       instead of washing the whole screen. {@code Seed} re-rolls with the patch re-seed
 *       (post blocks and world patches pop together) and carries the nether palette flag
 *       (+{@value #SEED_NETHER_OFFSET} = red-shifted variant, same renderer/pipeline).
 *       Hard-gated off under an Iris shaderpack or {@code veilPostFx=false} by
 *       {@code VeilPostController}; the world-space patches are the Iris fallback.</li>
 * </ol>
 *
 * <p>Ring parameters come from {@link ClientStateCache} ({@code S2CBorderPayload}: center,
 * from/to radius, lerp ticks, fx range — both the overworld and the nether ring); the radius
 * animates client-side during stage growth via {@link ClientStateCache#currentBorderRadius}.
 * The vanilla border render is cancelled by {@code client.mixin.LevelRendererMixin}, so
 * these patches are the only border visual.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BorderFxRenderer {
    private static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/environment/border_glitch.png");
    /** Client-local shard emitter (never server-sent, so not a {@link S2CQuasarPayload} constant). */
    private static final ResourceLocation BORDER_SHARD =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border_shard");

    /** Sodium fallback constant (§7 risk 2): swap to AFTER_TRANSLUCENT_BLOCKS if artifacts appear. */
    private static final RenderLevelStageEvent.Stage RENDER_STAGE = RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    // --- patch field tuning (R6 frozen numbers) ---
    private static final double ARC_HALF_DEGREES = 8.0D;
    /** Locality clamp: on huge rings the ±8° band is capped to this many blocks of arc. */
    private static final double ARC_HALF_BLOCKS_CAP = 20.0D;
    private static final int MIN_CLUSTERS = 5;
    private static final int MAX_CLUSTERS = 9;
    private static final int MAX_QUADS_PER_CLUSTER = 6;
    private static final int MIN_QUADS_PER_CLUSTER = 3;
    private static final double PATCH_MIN_SIZE = 2.0D;
    private static final double PATCH_MAX_SIZE = 4.0D;
    /** Cluster centers sit within this band around the player's eye Y (blocks). */
    private static final double CLUSTER_Y_UP = 2.5D;
    private static final double CLUSTER_Y_DOWN = 3.5D;
    /** Quad scatter around its cluster center (blocks, tangential and vertical). */
    private static final double QUAD_SCATTER = 1.6D;
    /** Max in-plane quad rotation (radians, ~±26°). */
    private static final double QUAD_MAX_ROT = 0.45D;
    private static final int RESEED_MIN_TICKS = 6;
    private static final int RESEED_MAX_TICKS = 10;
    /** Horizontal blocks per texture repeat (patches sample chunky sub-regions, not pixel soup). */
    private static final double TEXTURE_TILE_BLOCKS = 8.0D;
    /** Cluster visibility fades out at {@code fxRange × } this (keeps the field player-local). */
    private static final double CLUSTER_FADE_RANGE_MUL = 4.0D;
    private static final int QUASAR_INTERVAL_TICKS = 3;
    /** Nether palette flag on the post {@code Seed} uniform (frozen contract with the shader). */
    private static final float SEED_NETHER_OFFSET = 1000.0F;

    // --- seeded patch field (regenerated every 6–10 ticks; primitive arrays, no render allocs) ---
    private static final int MAX_QUADS = MAX_CLUSTERS * MAX_QUADS_PER_CLUSTER;
    private static final double[] CLUSTER_ANGLE = new double[MAX_CLUSTERS];
    private static final double[] CLUSTER_Y = new double[MAX_CLUSTERS];
    private static final int[] CLUSTER_QUAD_COUNT = new int[MAX_CLUSTERS];
    private static final float[] QUAD_SIZE = new float[MAX_QUADS];
    private static final float[] QUAD_TAN_OFF = new float[MAX_QUADS];
    private static final float[] QUAD_Y_OFF = new float[MAX_QUADS];
    private static final float[] QUAD_ROT = new float[MAX_QUADS];
    private static final float[] QUAD_U0 = new float[MAX_QUADS];
    private static final float[] QUAD_V0 = new float[MAX_QUADS];
    private static final int[] QUAD_PHASE = new int[MAX_QUADS];
    private static int clusterCount;

    /**
     * Game-time throttles. Initialized (and reset on world/server change) to a small
     * negative value, NEVER {@code Long.MIN_VALUE}: {@code gameTime - Long.MIN_VALUE}
     * overflows negative, which silently deadlocks a subtraction-based throttle — the v1
     * renderer had exactly that bug and its Quasar layer never fired.
     */
    private static long lastReseedGameTime = -1000L;
    private static long lastQuasarGameTime = -1000L;
    /** Current randomized reseed interval in ticks (0 forces an immediate first seed). */
    private static int reseedIntervalTicks;
    private static int reseedCounter;

    // --- tick-cached feed for the per-frame GlitchDir projection (render path is alloc-free) ---
    /** Nearest ring point at eye height, or {@code null} while far from the ring. */
    @Nullable
    private static volatile Vec3 ringPoint;
    private static double toBorderX = 1.0D;
    private static double toBorderZ;
    private static boolean netherRing;
    private static float postSeed;
    /** Scratch for {@link SunTracker#worldToNdc} — feeder-only, overwritten every frame. */
    private static final Vector4f GLITCH_NDC = new Vector4f();

    static {
        // v2 pipeline row — replaces VeilPostController's backward-compat border_glitch row
        // regardless of class-load order (W1 contract, docs/plans_v3/wiring/P2-W1_wiring.md).
        VeilPostController.register(new VeilPostController.PipelineSpec(
                VeilPostController.BORDER_GLITCH_POST,
                VeilPostController.PipelinePriority.FEATURE,
                BorderFxRenderer::wantPost,
                BorderFxRenderer::feedPost));
    }

    private BorderFxRenderer() {}

    /** Ring radius for the given client dimension, or {@code <= 0} when no ring applies. */
    private static double ringRadius(ClientLevel level) {
        long now = System.currentTimeMillis();
        if (level.dimension() == Level.OVERWORLD) {
            return ClientStateCache.currentBorderRadius(false, now);
        }
        if (level.dimension() == Level.NETHER) {
            return ClientStateCache.currentBorderRadius(true, now);
        }
        return -1.0D;
    }

    /**
     * FX intensity in [0,1] for a viewpoint: 0 until {@code ringDist < fxRange}, rising to 1
     * on (and beyond) the ring. {@code radius <= 0} always yields 0.
     */
    private static float proximity(double radius, double x, double z) {
        if (radius <= 0.0D) {
            return 0.0F;
        }
        double dx = x - ClientStateCache.borderCenterX;
        double dz = z - ClientStateCache.borderCenterZ;
        double inside = radius - Math.sqrt(dx * dx + dz * dz); // negative when outside
        double fxRange = Math.max(1.0F, ClientStateCache.borderFxRange);
        return (float) Mth.clamp(1.0D - Math.max(0.0D, inside) / fxRange, 0.0D, 1.0D);
    }

    // ------------------------------------------------------------------ post pipeline row

    /**
     * Post strength curve (R6): {@code Proximity^1.5}. Kept in sync with the identical
     * helper in {@code client.AltarAberration} — the two FEATURE passes never overlap
     * geometrically (aberration zone ends at the spawn disc, the ring sits well outside),
     * but if both ever signal, only the stronger runs (mutual throttle, border wins ties).
     */
    private static float borderPostStrength(float proximity) {
        return proximity * Mth.sqrt(proximity);
    }

    /** {@code client.AltarAberration}'s strength metric (R9 curve cap 0.85) — keep in sync. */
    private static float aberrationPostStrength(float aberration) {
        return aberration * 0.85F;
    }

    private static boolean wantPost() {
        float prox = EclipseFxState.borderProximity();
        if (prox <= 0.01F) {
            return false;
        }
        float aberration = EclipseFxState.altarAberration();
        if (aberration <= 0.01F) {
            return true;
        }
        return borderPostStrength(prox) >= aberrationPostStrength(aberration);
    }

    /**
     * Per-frame uniform feed (runs only while the pipeline is active). {@code GlitchDir} is
     * the NDC position of the tick-cached nearest ring point, projected through THIS frame's
     * exact render matrices; when the point is behind the camera the lens parks just off the
     * screen edge on the border's side (only its rim bleeds in — turning your back on the
     * ring softens the effect instead of snapping it off).
     */
    private static void feedPost(PostPipeline pipeline) {
        pipeline.getUniform("Proximity").setFloat(EclipseFxState.borderProximity());
        pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 100_000L) / 1000.0F);
        float glitchX = 1.0F;
        float glitchY = 0.0F;
        Vec3 point = ringPoint;
        if (point != null) {
            if (SunTracker.worldToNdc(point, GLITCH_NDC)) {
                glitchX = Mth.clamp(GLITCH_NDC.x(), -2.5F, 2.5F);
                glitchY = Mth.clamp(GLITCH_NDC.y(), -2.5F, 2.5F);
            } else {
                Camera camera = Minecraft.getInstance().gameRenderer.getMainCamera();
                Vector3f left = camera.getLeftVector();
                double dotLeft = left.x() * toBorderX + left.z() * toBorderZ;
                glitchX = dotLeft > 0.0D ? -1.9F : 1.9F;
                glitchY = -0.15F;
            }
        }
        pipeline.getUniform("GlitchDir").setVector(glitchX, glitchY);
        pipeline.getUniform("Seed").setFloat(postSeed);
    }

    // ------------------------------------------------------------------ per-tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null) {
            EclipseFxState.setBorderProximity(0.0F);
            BorderStaticSound.update(0.0F);
            ringPoint = null;
            clusterCount = 0;
            resetThrottles(); // world/server change: old gameTime bases would stall the throttles
            return;
        }
        double radius = ringRadius(level);
        float prox = proximity(radius, player.getX(), player.getZ());
        EclipseFxState.setBorderProximity(prox);
        // IDEA-07 §3 whisper hook: the static bed loop tracks the same per-tick proximity.
        BorderStaticSound.update(prox);
        if (prox <= 0.01F) {
            ringPoint = null;
            clusterCount = 0; // zero cost while far: no field, no reseeds, no emitters
            resetThrottles(); // re-entering range always seeds on the first tick
            return;
        }

        // Tick-cached nearest ring point + bearing for the per-frame GlitchDir projection.
        double dx = player.getX() - ClientStateCache.borderCenterX;
        double dz = player.getZ() - ClientStateCache.borderCenterZ;
        double dist = Math.sqrt(dx * dx + dz * dz);
        double dirX = dist > 1.0E-4D ? dx / dist : 1.0D;
        double dirZ = dist > 1.0E-4D ? dz / dist : 0.0D;
        toBorderX = dirX;
        toBorderZ = dirZ;
        netherRing = level.dimension() == Level.NETHER;
        ringPoint = new Vec3(ClientStateCache.borderCenterX + dirX * radius, player.getEyeY(),
                ClientStateCache.borderCenterZ + dirZ * radius);

        long gameTime = level.getGameTime();
        RandomSource random = level.random;
        if (gameTime - lastReseedGameTime >= reseedIntervalTicks) {
            double halfArc = Math.min(Math.toRadians(ARC_HALF_DEGREES),
                    ARC_HALF_BLOCKS_CAP / Math.max(radius, 1.0D));
            reseed(random, Math.atan2(dz, dx), halfArc, player.getEyeY(), radius, prox);
            lastReseedGameTime = gameTime;
            reseedIntervalTicks = RESEED_MIN_TICKS + random.nextInt(RESEED_MAX_TICKS - RESEED_MIN_TICKS + 1);
        }

        // Ambient BORDER_GLITCH bursts at cluster positions (kept from v1, now patch-anchored).
        int interval = FxBudget.qualityTier() >= 2 ? QUASAR_INTERVAL_TICKS : QUASAR_INTERVAL_TICKS * 2;
        if (clusterCount > 0 && gameTime - lastQuasarGameTime >= interval && random.nextFloat() <= prox) {
            lastQuasarGameTime = gameTime;
            int cluster = random.nextInt(clusterCount);
            QuasarSpawner.spawn(S2CQuasarPayload.BORDER_GLITCH,
                    clusterPos(cluster, radius), FxBudget.Channel.BURST);
        }
    }

    /**
     * Re-arms both game-time throttles. Called whenever the ring goes out of play (far from
     * the ring, disconnect, dimension hop): {@code gameTime} restarts per world, so a stale
     * base from a previous world could stall the subtraction checks for thousands of ticks.
     */
    private static void resetThrottles() {
        lastReseedGameTime = -1000L;
        lastQuasarGameTime = -1000L;
        reseedIntervalTicks = 0; // next in-range tick seeds immediately
    }

    /**
     * Regenerates the whole patch field around the player's current bearing (the "datamosh
     * popping" beat): cluster count by quality tier, absolute ring angles within the
     * clamped arc, near-eye heights, per-quad size/offset/rotation/UV-jitter. Also rolls the
     * post {@code Seed} (world patches and screen blocks pop together) and fires blocky
     * {@code border_shard} pops at 1–2 fresh cluster positions.
     */
    private static void reseed(RandomSource random, double bearing, double halfArc, double eyeY,
            double radius, float prox) {
        int tier = FxBudget.qualityTier();
        if (tier >= 2) {
            clusterCount = MIN_CLUSTERS + random.nextInt(MAX_CLUSTERS - MIN_CLUSTERS + 1);
        } else if (tier == 1) {
            clusterCount = 4 + random.nextInt(3);
        } else {
            clusterCount = 3;
        }
        // Approach densification (VFXPOLISH-3): the field thickens with smoothstep-eased
        // proximity — a sparse crackle at the fxRange edge rising to the full quality-tier
        // density on the ring, so the push-back boundary reads as a wall of static.
        float density = prox * prox * (3.0F - 2.0F * prox);
        clusterCount = Math.max(2, Math.round(clusterCount * (0.45F + 0.55F * density)));
        for (int c = 0; c < clusterCount; c++) {
            CLUSTER_ANGLE[c] = bearing + (random.nextDouble() * 2.0D - 1.0D) * halfArc;
            CLUSTER_Y[c] = eyeY + random.nextDouble() * (CLUSTER_Y_UP + CLUSTER_Y_DOWN) - CLUSTER_Y_DOWN;
            int quads = MIN_QUADS_PER_CLUSTER
                    + random.nextInt(MAX_QUADS_PER_CLUSTER - MIN_QUADS_PER_CLUSTER + 1);
            CLUSTER_QUAD_COUNT[c] = quads;
            for (int q = 0; q < quads; q++) {
                int i = c * MAX_QUADS_PER_CLUSTER + q;
                QUAD_SIZE[i] = (float) (PATCH_MIN_SIZE + random.nextDouble() * (PATCH_MAX_SIZE - PATCH_MIN_SIZE));
                QUAD_TAN_OFF[i] = (float) ((random.nextDouble() * 2.0D - 1.0D) * QUAD_SCATTER);
                QUAD_Y_OFF[i] = (float) ((random.nextDouble() * 2.0D - 1.0D) * QUAD_SCATTER);
                QUAD_ROT[i] = (float) ((random.nextDouble() * 2.0D - 1.0D) * QUAD_MAX_ROT);
                QUAD_U0[i] = random.nextFloat() * 0.72F;
                QUAD_V0[i] = random.nextFloat() * 0.72F;
                QUAD_PHASE[i] = random.nextInt(0x7FFF);
            }
        }
        reseedCounter++;
        postSeed = (reseedCounter * 61) % 997 + (netherRing ? SEED_NETHER_OFFSET : 0.0F);

        // Blocky shard pops riding the reseed beat (budget-charged; silently dropped over cap).
        if (random.nextFloat() < 0.35F + 0.45F * prox) {
            QuasarSpawner.spawn(BORDER_SHARD, clusterPos(random.nextInt(clusterCount), radius),
                    FxBudget.Channel.BURST);
        }
        if (prox > 0.7F && random.nextFloat() < 0.5F) {
            QuasarSpawner.spawn(BORDER_SHARD, clusterPos(random.nextInt(clusterCount), radius),
                    FxBudget.Channel.BURST);
        }
    }

    /** World position of a seeded cluster on the current ring (tick-path only — allocates). */
    private static Vec3 clusterPos(int cluster, double radius) {
        double angle = CLUSTER_ANGLE[cluster];
        return new Vec3(ClientStateCache.borderCenterX + Math.cos(angle) * radius,
                CLUSTER_Y[cluster],
                ClientStateCache.borderCenterZ + Math.sin(angle) * radius);
    }

    // ------------------------------------------------------------------ per-frame: patches

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RENDER_STAGE) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || clusterCount == 0) {
            return;
        }
        double radius = ringRadius(level);
        Vec3 camera = event.getCamera().getPosition();
        float baseAlpha = proximity(radius, camera.x, camera.z);
        if (baseAlpha <= 0.01F) {
            return; // zero cost when far: nothing built, no state touched
        }

        double centerX = ClientStateCache.borderCenterX;
        double centerZ = ClientStateCache.borderCenterZ;
        double fadeRange = Math.max(1.0F, ClientStateCache.borderFxRange) * CLUSTER_FADE_RANGE_MUL;
        long timeMillis = System.currentTimeMillis();
        int flickerFrame = (int) (timeMillis / 70L);            // ~14 flicker updates/s
        float crawlV = (timeMillis % 1400L) / 1400.0F * 0.06F;  // subtle static crawl inside patches

        // Nether ring: red-shifted palette (R6); overworld: house violet.
        float tintR = netherRing ? 1.0F : 0.85F;
        float tintG = netherRing ? 0.45F : 0.55F;
        float tintB = netherRing ? 0.50F : 1.0F;

        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX_COLOR);
        for (int c = 0; c < clusterCount; c++) {
            double angle = CLUSTER_ANGLE[c];
            double tanX = -Math.sin(angle);
            double tanZ = Math.cos(angle);
            double ringX = centerX + Math.cos(angle) * radius;
            double ringZ = centerZ + Math.sin(angle) * radius;
            double clusterY = CLUSTER_Y[c];
            double cdx = ringX - camera.x;
            double cdy = clusterY - camera.y;
            double cdz = ringZ - camera.z;
            double clusterDist = Math.sqrt(cdx * cdx + cdy * cdy + cdz * cdz);
            float clusterFade = (float) Mth.clamp(1.0D - clusterDist / fadeRange, 0.0D, 1.0D);
            if (clusterFade <= 0.02F) {
                continue;
            }
            int quads = CLUSTER_QUAD_COUNT[c];
            for (int q = 0; q < quads; q++) {
                int i = c * MAX_QUADS_PER_CLUSTER + q;
                float flicker = flicker(QUAD_PHASE[i] + i, flickerFrame);
                boolean hotFlash = flicker > 0.93F;   // brief white-hot pop (invert-flash read)
                float alpha = baseAlpha * clusterFade * (0.25F + 0.75F * flicker);
                if (hotFlash) {
                    alpha = Math.min(1.0F, alpha * 1.6F);
                }
                if (alpha <= 0.01F) {
                    continue;
                }
                float red = hotFlash ? Math.min(1.0F, tintR + 0.4F) : tintR;
                float green = hotFlash ? Math.min(1.0F, tintG + 0.45F) : tintG;
                float blue = hotFlash ? 1.0F : tintB;

                double half = QUAD_SIZE[i] * 0.5D;
                double cosR = Math.cos(QUAD_ROT[i]);
                double sinR = Math.sin(QUAD_ROT[i]);
                // In-plane axes of the wall (tangent × up), rotated by the quad's roll.
                double e1x = tanX * cosR * half;
                double e1y = sinR * half;
                double e1z = tanZ * cosR * half;
                double e2x = -tanX * sinR * half;
                double e2y = cosR * half;
                double e2z = -tanZ * sinR * half;
                double px = ringX + tanX * QUAD_TAN_OFF[i] - camera.x;
                double py = clusterY + QUAD_Y_OFF[i] - camera.y;
                double pz = ringZ + tanZ * QUAD_TAN_OFF[i] - camera.z;

                float uvSpan = (float) (QUAD_SIZE[i] / TEXTURE_TILE_BLOCKS);
                float u0 = QUAD_U0[i];
                float u1 = u0 + uvSpan;
                float v0 = QUAD_V0[i] + crawlV;
                float v1 = v0 + uvSpan;

                buffer.addVertex((float) (px - e1x - e2x), (float) (py - e1y - e2y), (float) (pz - e1z - e2z))
                        .setUv(u0, v0).setColor(red, green, blue, alpha);
                buffer.addVertex((float) (px + e1x - e2x), (float) (py + e1y - e2y), (float) (pz + e1z - e2z))
                        .setUv(u1, v0).setColor(red, green, blue, alpha);
                buffer.addVertex((float) (px + e1x + e2x), (float) (py + e1y + e2y), (float) (pz + e1z + e2z))
                        .setUv(u1, v1).setColor(red, green, blue, alpha);
                buffer.addVertex((float) (px - e1x + e2x), (float) (py - e1y + e2y), (float) (pz - e1z + e2z))
                        .setUv(u0, v1).setColor(red, green, blue, alpha);
            }
        }
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return; // every quad faded/skipped this frame
        }

        RenderSystem.enableBlend();
        RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShaderTexture(0, TEXTURE);
        RenderSystem.setShader(GameRenderer::getPositionTexColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(false);
        BufferUploader.drawWithShader(mesh);
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
    }

    /** Cheap per-quad noise flicker in [0,1] — patches must read as unstable static. */
    private static float flicker(int quadKey, int frame) {
        int hash = quadKey * 668265261 ^ frame * 374761393;
        hash = (hash ^ (hash >>> 13)) * 1274126177;
        return ((hash ^ (hash >>> 16)) & 0xFFFF) / 65535.0F;
    }
}
