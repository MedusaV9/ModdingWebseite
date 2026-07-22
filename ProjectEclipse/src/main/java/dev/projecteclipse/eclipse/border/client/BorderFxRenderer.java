package dev.projecteclipse.eclipse.border.client;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.MeshData;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * Client visuals of the circular soft border — three layers, all invisible until the camera
 * is within {@code fxRange} (server-synced, default 8) of the ring, and ZERO cost while far
 * (a single d² early-out per frame/tick):
 * <ol>
 *   <li><b>Geometry</b> ({@link RenderLevelStageEvent} AFTER_PARTICLES): a curved strip of
 *       quads covering ±{@value #ARC_HALF_DEGREES}° of arc nearest the camera, tessellated
 *       every ~{@value #QUAD_ARC_BLOCKS} blocks, ±{@value #HALF_HEIGHT} blocks around the
 *       player's Y. The scrolling {@code border_glitch.png} static is drawn ADDITIVELY with
 *       {@code alpha = (1 − dist/fxRange) · per-quad noise flicker} — unstable static, not a
 *       wall. Budget ≤{@value #MAX_QUADS} quads (the arc narrows on huge rings). Vertices are
 *       camera-relative; at AFTER_PARTICLES the global modelview stack already carries the
 *       frustum matrix, so the vanilla-border draw pattern (position_tex_color +
 *       {@link BufferUploader#drawWithShader}) applies unchanged. If depth-sorting artifacts
 *       appear under Sodium, switch the stage to AFTER_TRANSLUCENT_BLOCKS — both fire with
 *       the same matrices.</li>
 *   <li><b>Particles</b>: {@code BORDER_GLITCH} Quasar emitters spawned along the visible
 *       arc, throttled to at most one emitter per {@value #QUASAR_INTERVAL_TICKS} client
 *       ticks (twice that with {@code reducedFx}) scaled by proximity — well under the
 *       30/s cap.</li>
 *   <li><b>Veil post</b>: the per-tick proximity is fed to
 *       {@link VeilPostController#setBorderProximity}, which drives the
 *       {@code eclipse:border_glitch} chromatic-aberration pipeline (hard-gated off under an
 *       Iris shaderpack or {@code veilPostFx=false}).</li>
 * </ol>
 *
 * <p>Ring parameters come from {@link ClientStateCache} ({@code S2CBorderPayload}); the
 * radius animates client-side during stage growth via
 * {@link ClientStateCache#currentBorderRadius}. The vanilla border render is cancelled by
 * {@code client.mixin.LevelRendererMixin}, so this strip is the only border visual.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BorderFxRenderer {
    private static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/environment/border_glitch.png");

    private static final double ARC_HALF_DEGREES = 25.0D;
    private static final double QUAD_ARC_BLOCKS = 2.0D;
    private static final double HALF_HEIGHT = 12.0D;
    private static final int MAX_QUADS = 200;
    /** Horizontal blocks per texture repeat (chunky static rather than pixel soup). */
    private static final double TEXTURE_TILE_BLOCKS = 16.0D;
    private static final int QUASAR_INTERVAL_TICKS = 3;

    private static long lastQuasarGameTime = Long.MIN_VALUE;

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

    // --- per-tick: Veil post feed + Quasar bursts ---

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null) {
            VeilPostController.setBorderProximity(0.0F);
            return;
        }
        double radius = ringRadius(level);
        float alpha = proximity(radius, player.getX(), player.getZ());
        VeilPostController.setBorderProximity(alpha);
        if (alpha <= 0.05F) {
            return;
        }
        int interval = EclipseClientConfig.reducedFx() ? QUASAR_INTERVAL_TICKS * 2 : QUASAR_INTERVAL_TICKS;
        long gameTime = level.getGameTime();
        if (gameTime - lastQuasarGameTime < interval || level.random.nextFloat() > alpha) {
            return;
        }
        lastQuasarGameTime = gameTime;
        double playerAngle = Math.atan2(player.getZ() - ClientStateCache.borderCenterZ,
                player.getX() - ClientStateCache.borderCenterX);
        double angle = playerAngle + (level.random.nextDouble() - 0.5D) * 2.0D * Math.toRadians(ARC_HALF_DEGREES);
        Vec3 pos = new Vec3(
                ClientStateCache.borderCenterX + Math.cos(angle) * radius,
                player.getY() + (level.random.nextDouble() - 0.5D) * HALF_HEIGHT,
                ClientStateCache.borderCenterZ + Math.sin(angle) * radius);
        QuasarSpawner.spawnOrFallback(S2CQuasarPayload.BORDER_GLITCH, pos);
    }

    // --- per-frame: the glitch strip ---

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_PARTICLES) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null) {
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
        double camAngle = Math.atan2(camera.z - centerZ, camera.x - centerX);
        double angleStep = QUAD_ARC_BLOCKS / radius;
        double halfArc = Math.toRadians(ARC_HALF_DEGREES);
        int columns = (int) Math.ceil(2.0D * halfArc / angleStep);
        if (columns > MAX_QUADS) {
            columns = MAX_QUADS; // huge rings: narrow the covered arc instead of adding quads
            halfArc = columns * angleStep / 2.0D;
        }

        double yBottom = player.getY() - HALF_HEIGHT;
        double yTop = player.getY() + HALF_HEIGHT;
        long timeMillis = System.currentTimeMillis();
        float scrollU = (timeMillis % 8000L) / 8000.0F;         // slow sideways drift
        float scrollV = (timeMillis % 2600L) / 2600.0F;         // faster vertical crawl
        int flickerFrame = (int) (timeMillis / 90L);            // ~11 flicker updates/s

        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX_COLOR);
        for (int i = 0; i < columns; i++) {
            double a0 = camAngle - halfArc + i * angleStep;
            double a1 = a0 + angleStep;
            float x0 = (float) (centerX + Math.cos(a0) * radius - camera.x);
            float z0 = (float) (centerZ + Math.sin(a0) * radius - camera.z);
            float x1 = (float) (centerX + Math.cos(a1) * radius - camera.x);
            float z1 = (float) (centerZ + Math.sin(a1) * radius - camera.z);
            float y0 = (float) (yBottom - camera.y);
            float y1 = (float) (yTop - camera.y);
            float u0 = (float) (a0 * radius / TEXTURE_TILE_BLOCKS) + scrollU;
            float u1 = (float) (a1 * radius / TEXTURE_TILE_BLOCKS) + scrollU;
            float v0 = scrollV;
            float v1 = scrollV + (float) ((yTop - yBottom) / TEXTURE_TILE_BLOCKS);
            float alpha = baseAlpha * flicker(i, flickerFrame);
            buffer.addVertex(x0, y0, z0).setUv(u0, v0).setColor(0.85F, 0.55F, 1.0F, alpha);
            buffer.addVertex(x1, y0, z1).setUv(u1, v0).setColor(0.85F, 0.55F, 1.0F, alpha);
            buffer.addVertex(x1, y1, z1).setUv(u1, v1).setColor(0.85F, 0.55F, 1.0F, alpha);
            buffer.addVertex(x0, y1, z0).setUv(u0, v1).setColor(0.85F, 0.55F, 1.0F, alpha);
        }
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
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

    /** Cheap per-quad noise flicker in [0.35, 1.0] — the strip must read as unstable static. */
    private static float flicker(int quadIndex, int frame) {
        int hash = quadIndex * 668265261 ^ frame * 374761393;
        hash = (hash ^ (hash >>> 13)) * 1274126177;
        float noise = ((hash ^ (hash >>> 16)) & 0xFFFF) / 65535.0F;
        return 0.35F + 0.65F * noise;
    }
}
