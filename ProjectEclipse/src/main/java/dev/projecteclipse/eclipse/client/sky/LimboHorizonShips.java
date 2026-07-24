package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * IDEA-18 §2 — distant silhouette ships that vanish when observed. Two to three flat black
 * ship silhouettes (hull + masts from a static triangle table, plus one soul-green stern
 * lantern point) sit at fixed azimuths on the Limbo horizon at sky distance. The moment the
 * camera centers one ({@code dot(look, dirToShip)} past ~0.88), it fades out with a ONE-WAY
 * latch — once fully faded it holds invisible for 1200–2400 ticks, then re-seeds a new
 * azimuth from an {@code ECLIPSE_SEED}-derived hash of its sighting counter (deterministic;
 * no {@code level.random}, identical on every client).
 *
 * <p>Drawn from {@link LimboSpecialEffects#renderSky} inside the stars' no-fog window, so
 * the Iris guard and fog restore come for free. Purely cosmetic: no entities, no server
 * traffic, no per-frame heap allocations (§3.5 — scratch is pre-allocated).</p>
 */
@OnlyIn(Dist.CLIENT)
final class LimboHorizonShips {
    private static final int SHIP_COUNT = 3;
    /** Same celestial plane distance the disc/stars use. */
    private static final float DISTANCE = 100.0F;
    /** Look-dot fade band: fully visible below 0.88, fully faded at 0.97 (IDEA-18 §2). */
    private static final float FADE_DOT_START = 0.88F;
    private static final float FADE_DOT_END = 0.97F;
    /** Invisible hold after a sighting: 1200 + hash·1200 ticks (60–120 s). */
    private static final int RESEED_MIN_TICKS = 1200;
    private static final int RESEED_RANGE_TICKS = 1200;
    /** Silhouettes sit this far above the horizon plane (units on the sky sphere). */
    private static final float HORIZON_LIFT = 2.0F;

    /**
     * Silhouette triangle table, ship-local units: pairs of (along, up) per vertex, three
     * vertices per triangle — a low hull with a raised bow, plus main/fore/stern masts.
     */
    private static final float[] SILHOUETTE = {
            // hull (two triangles)
            -7.0F, 1.4F, 7.0F, 1.9F, 5.5F, -0.6F,
            -7.0F, 1.4F, 5.5F, -0.6F, -5.6F, -0.6F,
            // bow rise
            7.0F, 1.9F, 8.4F, 3.1F, 6.2F, 1.5F,
            // main mast
            -0.8F, 1.4F, 0.8F, 1.4F, 0.0F, 9.5F,
            // fore mast
            3.2F, 1.6F, 4.4F, 1.6F, 3.8F, 7.0F,
            // stern mast (shortest)
            -4.6F, 1.2F, -3.4F, 1.2F, -4.0F, 6.2F,
    };
    /** Stern lantern (along, up) and half-size of its little glowing quad. */
    private static final float LANTERN_ALONG = -6.2F;
    private static final float LANTERN_UP = 2.6F;
    private static final float LANTERN_HALF = 0.45F;

    /** Per-ship state (deterministic; mutated only from the render thread). */
    private static final float[] azimuth = new float[SHIP_COUNT];
    private static final float[] dirX = new float[SHIP_COUNT];
    private static final float[] dirY = new float[SHIP_COUNT];
    private static final float[] dirZ = new float[SHIP_COUNT];
    private static final float[] fade = new float[SHIP_COUNT];
    private static final boolean[] latched = new boolean[SHIP_COUNT];
    private static final long[] reseedAtGameTime = new long[SHIP_COUNT];
    private static final int[] sightings = new int[SHIP_COUNT];
    private static boolean seeded;

    private LimboHorizonShips() {}

    /**
     * Draws the horizon ships. Caller contract ({@code renderSky}): fog is OFF, blending is
     * enabled, and the caller resets shader + shader color afterwards. Expects the
     * position-color shader to be active.
     */
    static void draw(Matrix4f pose, ClientLevel level, Camera camera) {
        if (!seeded) {
            seeded = true;
            for (int i = 0; i < SHIP_COUNT; i++) {
                reseed(i);
                fade[i] = 1.0F;
            }
        }
        long gameTime = level.getGameTime();
        Vector3f look = camera.getLookVector();

        BufferBuilder builder = null;
        for (int i = 0; i < SHIP_COUNT; i++) {
            if (latched[i]) {
                if (gameTime < reseedAtGameTime[i]) {
                    continue;
                }
                latched[i] = false;
                reseed(i);
                fade[i] = 1.0F;
            }
            // One-way fade latch: alpha only ever falls while a sighting is in progress.
            float dot = look.x() * dirX[i] + look.y() * dirY[i] + look.z() * dirZ[i];
            float target = 1.0F - smoothstep(FADE_DOT_START, FADE_DOT_END, dot);
            if (target < fade[i]) {
                fade[i] = target;
            }
            if (fade[i] <= 0.01F) {
                fade[i] = 0.0F;
                latched[i] = true;
                sightings[i]++;
                reseedAtGameTime[i] = gameTime + RESEED_MIN_TICKS
                        + (int) (hash01(i * 197 + 31, sightings[i]) * RESEED_RANGE_TICKS);
                continue;
            }
            if (builder == null) {
                builder = Tesselator.getInstance().begin(
                        VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
            }
            emitShip(builder, pose, i, fade[i]);
        }
        if (builder != null) {
            BufferUploader.drawWithShader(builder.buildOrThrow());
        }
    }

    /** One ship: 6 near-black triangles + a soul-green stern lantern (two lantern tris). */
    private static void emitShip(BufferBuilder builder, Matrix4f pose, int i, float alpha) {
        float cos = Mth.cos(azimuth[i]);
        float sin = Mth.sin(azimuth[i]);
        // right axis of the silhouette plane (perpendicular to the view direction, horizontal)
        float rightX = -sin;
        float rightZ = cos;
        float baseX = cos * DISTANCE;
        float baseZ = sin * DISTANCE;
        float hullAlpha = 0.85F * alpha;
        for (int v = 0; v < SILHOUETTE.length; v += 2) {
            float along = SILHOUETTE[v];
            float up = SILHOUETTE[v + 1] + HORIZON_LIFT;
            builder.addVertex(pose, baseX + rightX * along, up, baseZ + rightZ * along)
                    .setColor(0.010F, 0.016F, 0.022F, hullAlpha);
        }
        // Stern lantern: a tiny bright quad as two triangles (0.9-alpha soul green).
        float lx = LANTERN_ALONG;
        float ly = LANTERN_UP + HORIZON_LIFT;
        float lanternAlpha = 0.9F * alpha;
        float x0 = baseX + rightX * (lx - LANTERN_HALF);
        float x1 = baseX + rightX * (lx + LANTERN_HALF);
        float z0 = baseZ + rightZ * (lx - LANTERN_HALF);
        float z1 = baseZ + rightZ * (lx + LANTERN_HALF);
        builder.addVertex(pose, x0, ly - LANTERN_HALF, z0).setColor(0.35F, 0.9F, 0.45F, lanternAlpha);
        builder.addVertex(pose, x1, ly - LANTERN_HALF, z1).setColor(0.35F, 0.9F, 0.45F, lanternAlpha);
        builder.addVertex(pose, x1, ly + LANTERN_HALF, z1).setColor(0.35F, 0.9F, 0.45F, lanternAlpha);
        builder.addVertex(pose, x0, ly - LANTERN_HALF, z0).setColor(0.35F, 0.9F, 0.45F, lanternAlpha);
        builder.addVertex(pose, x1, ly + LANTERN_HALF, z1).setColor(0.35F, 0.9F, 0.45F, lanternAlpha);
        builder.addVertex(pose, x0, ly + LANTERN_HALF, z0).setColor(0.35F, 0.9F, 0.45F, lanternAlpha);
    }

    /** New deterministic azimuth from the sighting counter; refreshes the cached direction. */
    private static void reseed(int i) {
        azimuth[i] = (float) (hash01(i, sightings[i]) * Math.PI * 2.0D);
        float cos = Mth.cos(azimuth[i]);
        float sin = Mth.sin(azimuth[i]);
        // Normalized direction to the (slightly lifted) silhouette center for the look-dot.
        float lift = (HORIZON_LIFT + 4.0F) / DISTANCE;
        float inv = (float) (1.0D / Math.sqrt(1.0D + lift * lift));
        dirX[i] = cos * inv;
        dirY[i] = lift * inv;
        dirZ[i] = sin * inv;
    }

    /** Fixed-seed hash 0..1 (LimboSeascape.hash01 mixer; deterministic on every client). */
    private static double hash01(int a, int b) {
        long h = DiscMapData.ECLIPSE_SEED ^ (a * 341873128712L + b * 132897987541L + 0x51D7B0A5L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }
}
