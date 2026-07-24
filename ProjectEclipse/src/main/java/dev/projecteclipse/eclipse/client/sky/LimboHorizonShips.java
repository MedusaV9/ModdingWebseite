package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * IDEA-18 §2 — distant silhouette ships that vanish when observed. Two to three flat black
 * ship silhouettes (hull + masts from a static triangle table, plus one soul-green stern
 * lantern point) ride the Limbo horizon at sky distance. The moment the camera centers one
 * ({@code dot(look, dirToShip)} past ~0.88), it fades out with a ONE-WAY latch — once fully
 * faded it holds invisible for 1200–2400 ticks, then re-seeds a new azimuth from an
 * {@code ECLIPSE_SEED}-derived hash of its sighting counter (deterministic; no
 * {@code level.random}, identical on every client).
 *
 * <p>PLAN-C C2 (sailing illusion, item 6): silhouettes are no longer pinned — each one
 * materializes AHEAD (within ±{@code 60°} of the bow heading, +X) and slides slowly astern
 * down its own side of the horizon over ~90 s, melting away near the stern and requeueing
 * ahead. Together with C1's {@code VoyageOffset} caustic stream and the
 * {@code LimboSpecialEffects} drift cues, the horizon itself appears to move past the
 * anchored ship.</p>
 *
 * <p>v4 (FXTEAM-LIMBO) — the <b>passing lantern</b>: rarely (every 4–8 minutes,
 * deterministic per event counter), a single tiny warm-amber light crosses ~30–50° of the
 * horizon over 30–45 s with a slow bob, then is gone. Deliberately NOT gaze-latched — the
 * silhouette ships vanish when observed, the lantern is the one thing out there that lets
 * itself be watched (and it is warm, the only non-violet/non-soul-green light in limbo:
 * someone else is sailing). Skipped entirely under {@code reducedFx} (garnish ladder), and
 * its schedule self-heals across world swaps / game-time rewinds.</p>
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
    /** Eased re-appear length after a reseed (ticks) — a ship must never pop into view. */
    private static final int APPEAR_TICKS = 60;
    /** Hold the reseed while the fresh azimuth is this close to the gaze center (dot). */
    private static final float APPEAR_GAZE_GUARD = FADE_DOT_START - 0.06F;
    /** Silhouettes sit this far above the horizon plane (units on the sky sphere). */
    private static final float HORIZON_LIFT = 2.0F;
    /** C2 sailing drift: silhouettes slide astern (bow +X → stern −X) over ~90 s. */
    private static final float DRIFT_RAD_PER_TICK = (float) (Math.PI / 2400.0D);
    /** Fresh silhouettes materialize within ±60° of the bow heading (+X). */
    private static final float SPAWN_AHEAD_HALF_ARC = (float) Math.toRadians(60.0D);
    /** Eased melt-away band before the stern; culled + requeued at a quarter of it. */
    private static final float STERN_CULL_ARC = (float) Math.toRadians(22.0D);

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
    /** Game time of the last (re-)appearance; drives the eased fade-in multiplier. */
    private static final long[] appearedAtGameTime = new long[SHIP_COUNT];
    private static final int[] sightings = new int[SHIP_COUNT];
    /** C2: +1 drifts astern over the port side (+Z), −1 over starboard (−Z). */
    private static final float[] driftSign = new float[SHIP_COUNT];
    /** Game time the drift was last advanced (clamps lag spikes to ≤ 20 t of motion). */
    private static long lastDriftGameTime = Long.MIN_VALUE;
    private static boolean seeded;

    // ---- v4 passing lantern -------------------------------------------------------------
    /** Ticks between lantern events: {@value} + hash·{@value} (4–8 minutes). */
    private static final int LANTERN_GAP_TICKS = 4800;
    /** Crossing duration: 600 + hash·300 ticks (30–45 s). */
    private static final int LANTERN_MIN_DURATION = 600;
    private static final int LANTERN_DURATION_RANGE = 300;
    /** Crossing arc: 0.5 + hash·0.35 rad (~29–49°). */
    private static final float LANTERN_MIN_ARC = 0.5F;
    private static final float LANTERN_ARC_RANGE = 0.35F;
    /** The lantern rides slightly above the ships' hull line and bobs ±0.25 units. */
    private static final float LANTERN_EVENT_UP = 1.4F;
    private static final float LANTERN_CORE_HALF = 0.4F;
    private static final float LANTERN_HALO_HALF = 1.5F;

    private static boolean lanternActive;
    private static long lanternStart;
    private static int lanternDuration;
    private static float lanternAz0;
    private static float lanternAz1;
    /** Game time of the next lantern trigger; {@code MIN_VALUE} = not yet scheduled. */
    private static long lanternNextAt = Long.MIN_VALUE;
    /** Event counter — the only input to the deterministic per-event hashes. */
    private static int lanternEvents;

    private LimboHorizonShips() {}

    /**
     * Draws the horizon ships. Caller contract ({@code renderSky}): fog is OFF, blending is
     * enabled, and the caller resets shader + shader color afterwards. Expects the
     * position-color shader to be active.
     */
    static void draw(Matrix4f pose, ClientLevel level, Camera camera) {
        long gameTime = level.getGameTime();
        if (!seeded) {
            seeded = true;
            lastDriftGameTime = gameTime;
            for (int i = 0; i < SHIP_COUNT; i++) {
                reseed(i);
                fade[i] = 1.0F;
            }
        }
        // C2 sailing drift: elapsed game time since the last frame, clamped so a lag spike
        // (or a world swap rewinding game time) can never teleport a ship across the sky.
        long driftTicks = Math.max(0L, Math.min(20L, gameTime - lastDriftGameTime));
        lastDriftGameTime = gameTime;
        Vector3f look = camera.getLookVector();

        BufferBuilder builder = null;
        for (int i = 0; i < SHIP_COUNT; i++) {
            if (latched[i]) {
                if (gameTime < reseedAtGameTime[i]) {
                    continue;
                }
                // reseed() is idempotent for a fixed sighting counter, so the candidate
                // direction can be computed before committing. Hold the reseed while the
                // player is looking near the fresh azimuth — a ship must materialize
                // off-gaze (per-client, like the fade; the azimuth stays deterministic).
                reseed(i);
                float candidateDot = look.x() * dirX[i] + look.y() * dirY[i] + look.z() * dirZ[i];
                if (candidateDot > APPEAR_GAZE_GUARD) {
                    continue;
                }
                latched[i] = false;
                fade[i] = 1.0F;
                appearedAtGameTime[i] = gameTime;
            }
            // C2: slide astern down this ship's side of the horizon (sailing illusion).
            if (driftTicks > 0L) {
                azimuth[i] += driftSign[i] * DRIFT_RAD_PER_TICK * driftTicks;
                refreshDirection(i);
            }
            float toStern = angleToStern(azimuth[i]);
            if (toStern <= STERN_CULL_ARC * 0.25F) {
                // Fully astern: hold invisible briefly, then materialize ahead again.
                fade[i] = 0.0F;
                latched[i] = true;
                sightings[i]++;
                reseedAtGameTime[i] = gameTime + 100
                        + (int) (hash01(i * 197 + 31, sightings[i]) * 400.0D);
                continue;
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
            // Eased fade-in after (re-)appearing: smoothstep over APPEAR_TICKS, so a fresh
            // silhouette breathes in from nothing instead of popping to full alpha.
            float appear = Mth.clamp((gameTime - appearedAtGameTime[i]) / (float) APPEAR_TICKS,
                    0.0F, 1.0F);
            appear = appear * appear * (3.0F - 2.0F * appear);
            // Eased melt-away toward the stern so a drifting silhouette never pops out.
            float sternFade = smoothstep(STERN_CULL_ARC * 0.25F, STERN_CULL_ARC, toStern);
            emitShip(builder, pose, i, fade[i] * appear * sternFade);
        }
        // v4: the passing lantern shares the ships' buffer and no-fog window.
        builder = tickAndDrawLantern(builder, pose, gameTime);
        if (builder != null) {
            BufferUploader.drawWithShader(builder.buildOrThrow());
        }
    }

    /**
     * v4 — the rare passing lantern: a tiny warm-amber light (core + soft halo) crossing a
     * hash-picked horizon arc with a gentle bob. Runs off absolute game time with
     * self-healing guards (a world swap that rewinds the clock re-arms the schedule within
     * a minute instead of parking it hours out). Returns the (possibly newly created)
     * builder so a lantern with no ships on screen still draws.
     */
    private static BufferBuilder tickAndDrawLantern(BufferBuilder builder, Matrix4f pose,
            long gameTime) {
        if (EclipseClientConfig.reducedFx()) {
            lanternActive = false; // garnish tier: drop the event, keep the schedule
            return builder;
        }
        if (lanternNextAt == Long.MIN_VALUE) {
            lanternNextAt = gameTime + 1800 + (int) (hash01(911, lanternEvents) * 3600.0D);
        }
        if (lanternNextAt - gameTime > LANTERN_GAP_TICKS * 2L) {
            lanternNextAt = gameTime + 1200; // clock rewound (world swap) — re-arm soon
        }
        if (!lanternActive) {
            if (gameTime < lanternNextAt) {
                return builder;
            }
            lanternActive = true;
            lanternStart = gameTime;
            lanternDuration = LANTERN_MIN_DURATION
                    + (int) (hash01(913, lanternEvents) * LANTERN_DURATION_RANGE);
            lanternAz0 = (float) (hash01(917, lanternEvents) * Math.PI * 2.0D);
            float arc = LANTERN_MIN_ARC + (float) hash01(919, lanternEvents) * LANTERN_ARC_RANGE;
            lanternAz1 = lanternAz0 + (hash01(923, lanternEvents) < 0.5D ? -arc : arc);
        }
        float t01 = (gameTime - lanternStart) / (float) lanternDuration;
        if (t01 >= 1.0F || t01 < 0.0F) { // done, or the clock rewound mid-crossing
            lanternActive = false;
            lanternEvents++;
            lanternNextAt = gameTime + LANTERN_GAP_TICKS
                    + (int) (hash01(929, lanternEvents) * LANTERN_GAP_TICKS);
            return builder;
        }

        float az = Mth.lerp(t01, lanternAz0, lanternAz1);
        float envelope = Mth.sin(t01 * (float) Math.PI); // breathe in, cross, breathe out
        float cos = Mth.cos(az);
        float sin = Mth.sin(az);
        float rightX = -sin;
        float rightZ = cos;
        float baseX = cos * DISTANCE;
        float baseZ = sin * DISTANCE;
        // Slow bob (6 s period; 120-tick mod = exactly one cycle, so the wrap is seamless).
        float up = HORIZON_LIFT + LANTERN_EVENT_UP
                + 0.25F * Mth.sin((gameTime % 120L) * ((float) Math.PI / 60.0F));

        if (builder == null) {
            builder = Tesselator.getInstance().begin(
                    VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        }
        // Warm amber — deliberately the only non-violet/non-soul-green light in limbo.
        // Halo first (a 4-triangle diamond gradient: bright center, transparent rim — a
        // uniform-alpha quad would read as a hard square at this size), then the core dot.
        emitLanternHalo(builder, pose, baseX, baseZ, rightX, rightZ, up,
                LANTERN_HALO_HALF, 0.98F, 0.80F, 0.45F, 0.22F * envelope);
        emitLanternQuad(builder, pose, baseX, baseZ, rightX, rightZ, up,
                LANTERN_CORE_HALF, 0.95F, 0.72F, 0.38F, 0.75F * envelope);
        return builder;
    }

    /** One small solid quad (two triangles) in the horizon silhouette plane — the core dot. */
    private static void emitLanternQuad(BufferBuilder builder, Matrix4f pose,
            float baseX, float baseZ, float rightX, float rightZ, float up,
            float half, float r, float g, float b, float alpha) {
        float x0 = baseX - rightX * half;
        float x1 = baseX + rightX * half;
        float z0 = baseZ - rightZ * half;
        float z1 = baseZ + rightZ * half;
        builder.addVertex(pose, x0, up - half, z0).setColor(r, g, b, alpha);
        builder.addVertex(pose, x1, up - half, z1).setColor(r, g, b, alpha);
        builder.addVertex(pose, x1, up + half, z1).setColor(r, g, b, alpha);
        builder.addVertex(pose, x0, up - half, z0).setColor(r, g, b, alpha);
        builder.addVertex(pose, x1, up + half, z1).setColor(r, g, b, alpha);
        builder.addVertex(pose, x0, up + half, z0).setColor(r, g, b, alpha);
    }

    /**
     * Soft diamond glow: four triangles sharing a bright center vertex, alpha 0 at the
     * left/top/right/bottom rim points (no scratch arrays — §3.5, this runs per frame).
     */
    private static void emitLanternHalo(BufferBuilder builder, Matrix4f pose,
            float baseX, float baseZ, float rightX, float rightZ, float up,
            float half, float r, float g, float b, float centerAlpha) {
        float lx = baseX - rightX * half;
        float lz = baseZ - rightZ * half;
        float rx = baseX + rightX * half;
        float rz = baseZ + rightZ * half;
        float topY = up + half;
        float botY = up - half;
        // left → top
        builder.addVertex(pose, baseX, up, baseZ).setColor(r, g, b, centerAlpha);
        builder.addVertex(pose, lx, up, lz).setColor(r, g, b, 0.0F);
        builder.addVertex(pose, baseX, topY, baseZ).setColor(r, g, b, 0.0F);
        // top → right
        builder.addVertex(pose, baseX, up, baseZ).setColor(r, g, b, centerAlpha);
        builder.addVertex(pose, baseX, topY, baseZ).setColor(r, g, b, 0.0F);
        builder.addVertex(pose, rx, up, rz).setColor(r, g, b, 0.0F);
        // right → bottom
        builder.addVertex(pose, baseX, up, baseZ).setColor(r, g, b, centerAlpha);
        builder.addVertex(pose, rx, up, rz).setColor(r, g, b, 0.0F);
        builder.addVertex(pose, baseX, botY, baseZ).setColor(r, g, b, 0.0F);
        // bottom → left
        builder.addVertex(pose, baseX, up, baseZ).setColor(r, g, b, centerAlpha);
        builder.addVertex(pose, baseX, botY, baseZ).setColor(r, g, b, 0.0F);
        builder.addVertex(pose, lx, up, lz).setColor(r, g, b, 0.0F);
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

    /**
     * New deterministic azimuth from the sighting counter. C2: fresh silhouettes always
     * materialize AHEAD — within ±60° of the bow heading (+X) — and then drift astern down
     * the side of the horizon they seeded on ({@code driftSign}).
     */
    private static void reseed(int i) {
        azimuth[i] = (float) ((hash01(i, sightings[i]) - 0.5D) * 2.0D * SPAWN_AHEAD_HALF_ARC);
        driftSign[i] = Mth.sin(azimuth[i]) >= 0.0F ? 1.0F : -1.0F;
        refreshDirection(i);
    }

    /** Refreshes the cached unit direction after the azimuth changed (reseed or drift). */
    private static void refreshDirection(int i) {
        float cos = Mth.cos(azimuth[i]);
        float sin = Mth.sin(azimuth[i]);
        // Normalized direction to the (slightly lifted) silhouette center for the look-dot.
        float lift = (HORIZON_LIFT + 4.0F) / DISTANCE;
        float inv = (float) (1.0D / Math.sqrt(1.0D + lift * lift));
        dirX[i] = cos * inv;
        dirY[i] = lift * inv;
        dirZ[i] = sin * inv;
    }

    /** Absolute angular distance from the given azimuth to the stern heading (π, −X). */
    private static float angleToStern(float az) {
        float d = (az - (float) Math.PI) % ((float) Math.PI * 2.0F);
        if (d > (float) Math.PI) {
            d -= (float) Math.PI * 2.0F;
        } else if (d < -(float) Math.PI) {
            d += (float) Math.PI * 2.0F;
        }
        return Math.abs(d);
    }

    /**
     * Fixed-seed hash 0..1 (LimboSeascape.hash01 mixer; deterministic on every client).
     * v4: package-private — {@link LimboSpecialEffects#drawCoronalWisp} shares the mixer
     * (with its own salts) for the coronal-mass wisp schedule.
     */
    static double hash01(int a, int b) {
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
