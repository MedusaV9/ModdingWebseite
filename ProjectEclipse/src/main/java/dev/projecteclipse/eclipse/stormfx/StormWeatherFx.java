package dev.projecteclipse.eclipse.stormfx;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.light.data.PointLightData;
import foundry.veil.api.client.render.light.renderer.LightRenderHandle;
import net.minecraft.client.Minecraft;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * STORM 2.0 W-B (PLAN-STORM2 §W-B): the intra-wall FLASH SCHEDULER — tick/state half of the
 * weather-in-the-mass package. Owns the deterministic per-storm lightning-inside-the-wall
 * schedule and publishes the frozen §3 cross-package contract:
 *
 * <ul>
 *   <li>{@link #innerFlashAmount(int)} / {@link #innerFlashBearing(int)} /
 *       {@link #innerFlashLat(int)} — read by W-A for the lit-from-within shell pulse;</li>
 *   <li>{@link #innerFlashSerial()} + {@link #innerFlashMax()} — polled by W-C to fire the
 *       HDR Photon intra-bolt vein and by W-D for the {@code InnerFlash} post uniform.</li>
 * </ul>
 *
 * <p><b>Scheduler (B1):</b> per sphere storm, the next flash lands in
 * {@value #FLASH_MIN_INTERVAL}–{@value #FLASH_MAX_INTERVAL} ticks (hashed off storm id +
 * schedule window — deterministic, no RandomSource), lasts {@value #FLASH_TICKS} ticks on a
 * smoothstep envelope, and picks a flash cell at the camera bearing ±{@value #FLASH_BEARING_SPREAD}
 * rad / latFrac {@value #FLASH_LAT_MIN}–{@value #FLASH_LAT_MAX}. The serial bumps on FRESH
 * flashes only ({@code StormInteriorFx.flashSerial} pattern). Effects owned here: ONE
 * {@link FxBudget#tryLight() budgeted} violet point light at the wall surface point
 * (claim/decay/release mirrors {@code StormFxClient.Bolt.claimImpactLight}; tier 2 only —
 * tier 1 is the color-only rung of the §5 ladder) and a
 * {@link StormInteriorFx#flash(int)} silhouette beat when the camera is interior.
 * Gates: {@code TYPE_SPHERE}, {@code STATE_ACTIVE} only (never during EXPLODE), visibility
 * &gt; {@value #FLASH_MIN_VIS}, near LOD (shellDist &lt; {@value #FLASH_RANGE}), quality ≥ 1.
 * Pause-safe by construction (everything clocks off {@link StormFxClient#ticks()}, which
 * freezes while paused); {@code Clone}/{@code LoggingOut} reset every slot.</p>
 *
 * <p><b>Gust time-skew (B6):</b> {@link #weatherTimeSkew()} integrates the roar-loop gust
 * clock ({@link StormInteriorFx#gustAmount()}) into a bounded-drift phase-time so the
 * renderer's stateless closed-form motion (curtain fall, streak orbits) can speed up WITH
 * the gust without multiplying raw game time (which would teleport long-lived phases).</p>
 *
 * <p>Sibling: {@link StormWeatherRenderer} draws the geometry (embedded bolt ribbons, rain
 * curtains, debris streaks, cloud clumps) off this state. Zero Quasar spawns in the whole
 * W-B package — no STORM-channel pressure; the only budgeted resource is the flash light.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
final class StormWeatherFx {
    /** Flash cadence window (ticks) — hashed per storm + schedule window, B1. */
    private static final int FLASH_MIN_INTERVAL = 90;
    private static final int FLASH_MAX_INTERVAL = 260;
    /** Flash envelope length (ticks): smoothstep up, longer smoothstep release. */
    private static final int FLASH_TICKS = 7;
    /** Flash cell picks: bearing = camAngle ± this (rad); latFrac inside [MIN, MAX]. */
    private static final float FLASH_BEARING_SPREAD = 1.2F;
    private static final float FLASH_LAT_MIN = 0.15F;
    private static final float FLASH_LAT_MAX = 0.70F;
    /** Scheduler gates (B1): near-LOD shell distance and minimum shell visibility. */
    private static final float FLASH_RANGE = 160.0F;
    private static final float FLASH_MIN_VIS = 0.6F;
    /** Interior silhouette beat length fed to {@link StormInteriorFx#flash} per flash. */
    private static final int INTERIOR_FLASH_TICKS = 4;
    /** Flash point light: violet, radius 8 + 8·amount (Bolt.claimImpactLight palette family). */
    private static final float LIGHT_R = 0.7F;
    private static final float LIGHT_G = 0.5F;
    private static final float LIGHT_B = 1.0F;
    private static final float LIGHT_BRIGHTNESS = 0.85F;
    /** Light anchor sits at 0.92·r on the flash bearing (the W-C intra-bolt anchor formula). */
    private static final float LIGHT_RADIUS_FRAC = 0.92F;

    /** Tracked sphere storms (parallel arrays — no iterators, no per-tick allocations). */
    private static final int MAX_TRACKED = 8;
    private static final boolean[] SLOT_USED = new boolean[MAX_TRACKED];
    private static final int[] SLOT_STORM_ID = new int[MAX_TRACKED];
    private static final int[] SLOT_NEXT_FLASH = new int[MAX_TRACKED];
    /** Tick the live flash started at; {@code Integer.MIN_VALUE} = no live flash. */
    private static final int[] SLOT_FLASH_START = new int[MAX_TRACKED];
    private static final double[] SLOT_BEARING = new double[MAX_TRACKED];
    private static final float[] SLOT_LAT = new float[MAX_TRACKED];
    @SuppressWarnings("unchecked")
    private static final LightRenderHandle<PointLightData>[] SLOT_LIGHT =
            new LightRenderHandle[MAX_TRACKED];
    private static final boolean[] SLOT_LIGHT_BUDGETED = new boolean[MAX_TRACKED];
    /** Slot liveness sweep scratch (marks slots seen this tick; static — zero alloc). */
    private static final boolean[] SLOT_SEEN = new boolean[MAX_TRACKED];

    /** Bumps once per FRESH flash, any storm (§3 contract; W-C's one-shot trigger). */
    private static int flashSerial;
    /** Accumulated gust phase-time (ticks·gust) — bounded drift for stateless motion. */
    private static float gustSkew;

    private StormWeatherFx() {}

    // ------------------------------------------------------------------ §3 frozen contract

    /** 0..1 envelope of the live intra-wall flash of {@code stormId} (0 = none live). */
    static float innerFlashAmount(int stormId) {
        int slot = slotOf(stormId);
        return slot < 0 ? 0.0F : envelope(slot);
    }

    /** World bearing (rad) of the live flash cell of {@code stormId} (0 if none tracked). */
    static double innerFlashBearing(int stormId) {
        int slot = slotOf(stormId);
        return slot < 0 ? 0.0D : SLOT_BEARING[slot];
    }

    /** latFrac 0..1 of the live flash cell of {@code stormId} (0 if none tracked). */
    static float innerFlashLat(int stormId) {
        int slot = slotOf(stormId);
        return slot < 0 ? 0.0F : SLOT_LAT[slot];
    }

    /** Bumps once per FRESH flash (any storm) — the W-C Photon vein trigger. */
    static int innerFlashSerial() {
        return flashSerial;
    }

    /** Max flash envelope over all storms — the W-D {@code InnerFlash} uniform feed. */
    static float innerFlashMax() {
        float best = 0.0F;
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            if (SLOT_USED[slot]) {
                best = Math.max(best, envelope(slot));
            }
        }
        return best;
    }

    // ------------------------------------------------------------------ renderer reads (W-B internal)

    /**
     * Gust-integrated phase-time (B6): advances by {@code gustAmount} per tick. The renderer
     * adds {@code k · weatherTimeSkew()} to its motion clocks so curtain fall / streak orbits
     * accelerate smoothly with the roar-loop bar instead of jumping when the gust envelope
     * multiplies a large raw {@code time}.
     */
    static float weatherTimeSkew() {
        return gustSkew;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            if (anySlotUsed()) {
                reset();
            }
            return;
        }
        if (minecraft.isPaused()) {
            return; // StormFxClient.ticks() is frozen too — envelopes hold, nothing decays
        }
        gustSkew += StormInteriorFx.gustAmount();
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        if (storms.isEmpty()) {
            if (anySlotUsed()) {
                reset();
            }
            return;
        }
        int now = StormFxClient.ticks();
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            SLOT_SEEN[slot] = false;
        }
        for (int i = 0; i < storms.size(); i++) {
            tickStorm(storms.get(i), camera, now);
        }
        // Storms that vanished (dissipated/exploded out, level resync) free their slots.
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            if (SLOT_USED[slot] && !SLOT_SEEN[slot]) {
                freeSlot(slot);
            }
        }
    }

    private static void tickStorm(StormFxClient.ClientStorm storm, Vec3 camera, int now) {
        // B1 gates: sphere, ACTIVE only (never SPAWN/DISSIPATE/EXPLODE), visible, near LOD,
        // quality ≥ 1 — checked before a slot is even claimed so gated storms cost nothing.
        boolean wanted = storm.type == S2CStormStatePayload.TYPE_SPHERE
                && storm.state == S2CStormStatePayload.STATE_ACTIVE
                && storm.visibility(1.0F) > FLASH_MIN_VIS
                && FxBudget.qualityTier() >= 1;
        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dz * dz);
        if (wanted) {
            wanted = Math.abs(centerDist - storm.radius) < FLASH_RANGE;
        }
        int slot = slotOf(storm.id);
        if (!wanted) {
            if (slot >= 0) {
                freeSlot(slot); // gate dropped mid-flash: light + envelope released together
            }
            return;
        }
        if (slot < 0) {
            slot = claimSlot(storm.id, now);
            if (slot < 0) {
                return; // more than MAX_TRACKED gated storms — beyond spec, skip extras
            }
        }
        SLOT_SEEN[slot] = true;

        int flashStart = SLOT_FLASH_START[slot];
        if (flashStart != Integer.MIN_VALUE) {
            int age = now - flashStart;
            if (age >= FLASH_TICKS) {
                // Flash over: release the light, hash the next cadence off storm + window.
                releaseLight(slot);
                SLOT_FLASH_START[slot] = Integer.MIN_VALUE;
                SLOT_NEXT_FLASH[slot] = now + nextInterval(storm.id, now);
            } else {
                tickLight(slot, envelope(slot));
            }
            return;
        }
        if (now >= SLOT_NEXT_FLASH[slot]) {
            startFlash(slot, storm, camera, now, Math.atan2(dz, dx));
        }
    }

    /** Fires a fresh flash: cell pick, serial bump, budgeted light, interior beat. */
    private static void startFlash(int slot, StormFxClient.ClientStorm storm, Vec3 camera,
            int now, double camAngle) {
        // Deterministic cell pick — hashed off the fresh serial so every flash re-rolls
        // (flashSerial pattern) while frames within one flash stay stable.
        int serial = ++flashSerial;
        SLOT_FLASH_START[slot] = now;
        SLOT_BEARING[slot] = camAngle
                + (hash3(storm.id, serial, 17) - 0.5F) * 2.0F * FLASH_BEARING_SPREAD;
        SLOT_LAT[slot] = FLASH_LAT_MIN
                + hash3(storm.id, serial, 29) * (FLASH_LAT_MAX - FLASH_LAT_MIN);
        // ONE budgeted point light at the wall surface point — §5 ladder: tier 2 only
        // (tier 1 is the color-only rung: W-A's shell pulse still reads, no light, and
        // the renderer skips its ribbons). A tryLight refusal just skips it too.
        if (FxBudget.qualityTier() >= 2) {
            claimLight(slot, storm);
        }
        // IDEA-15 §2 rule (same package): interior flashes lift the fog for a silhouette
        // reveal — exactly the arc/bolt behavior, so the wall lightning reads inside too.
        if (StormInteriorFx.interiorAmount() > 0.5F) {
            StormInteriorFx.flash(INTERIOR_FLASH_TICKS);
        }
    }

    /** Next flash in 90–260 ticks: hash off storm id + the schedule window (deterministic). */
    private static int nextInterval(int stormId, int now) {
        float h = hash3(stormId, now / FLASH_MAX_INTERVAL, 0x51);
        return FLASH_MIN_INTERVAL
                + (int) (h * (FLASH_MAX_INTERVAL - FLASH_MIN_INTERVAL));
    }

    /** Smoothstep flash envelope 0..1: fast attack over 40%, slower release over 60%. */
    private static float envelope(int slot) {
        int start = SLOT_FLASH_START[slot];
        if (start == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float x = (StormFxClient.ticks() - start) / (float) FLASH_TICKS;
        if (x < 0.0F || x >= 1.0F) {
            return 0.0F;
        }
        float t = x < 0.4F ? x / 0.4F : 1.0F - (x - 0.4F) / 0.6F;
        return t * t * (3.0F - 2.0F * t);
    }

    // ------------------------------------------------------------------ flash light (Bolt pattern)

    private static void claimLight(int slot, StormFxClient.ClientStorm storm) {
        if (!FxBudget.tryLight()) {
            return; // over the light budget — the W-A color pulse still reads (B1 fallback)
        }
        SLOT_LIGHT_BUDGETED[slot] = true;
        try {
            double lat = SLOT_LAT[slot] * (Math.PI / 2.0D);
            double horiz = storm.radius * LIGHT_RADIUS_FRAC * Math.cos(lat);
            PointLightData data = new PointLightData()
                    .setPosition(storm.center.x + Math.cos(SLOT_BEARING[slot]) * horiz,
                            storm.center.y + SLOT_LAT[slot] * storm.height,
                            storm.center.z + Math.sin(SLOT_BEARING[slot]) * horiz)
                    .setColor(LIGHT_R, LIGHT_G, LIGHT_B)
                    .setBrightness(LIGHT_BRIGHTNESS * envelope(slot))
                    .setRadius(8.0F + 8.0F * envelope(slot));
            SLOT_LIGHT[slot] = VeilRenderSystem.renderer().getLightRenderer().addLight(data);
        } catch (Throwable t) {
            releaseLight(slot); // Veil unavailable — budget slot returned immediately
        }
    }

    private static void tickLight(int slot, float amount) {
        LightRenderHandle<PointLightData> handle = SLOT_LIGHT[slot];
        if (handle == null) {
            return;
        }
        try {
            handle.getLightData().setBrightness(LIGHT_BRIGHTNESS * amount);
            handle.getLightData().setRadius(8.0F + 8.0F * amount);
            handle.markDirty();
        } catch (Throwable t) {
            releaseLight(slot);
        }
    }

    private static void releaseLight(int slot) {
        LightRenderHandle<PointLightData> handle = SLOT_LIGHT[slot];
        SLOT_LIGHT[slot] = null;
        if (handle != null) {
            try {
                handle.free();
            } catch (Throwable ignored) {
                // Veil may already be tearing down (Bolt.releaseImpactLight pattern).
            }
        }
        if (SLOT_LIGHT_BUDGETED[slot]) {
            SLOT_LIGHT_BUDGETED[slot] = false;
            FxBudget.releaseLight();
        }
    }

    // ------------------------------------------------------------------ slots & housekeeping

    private static int slotOf(int stormId) {
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            if (SLOT_USED[slot] && SLOT_STORM_ID[slot] == stormId) {
                return slot;
            }
        }
        return -1;
    }

    private static int claimSlot(int stormId, int now) {
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            if (!SLOT_USED[slot]) {
                SLOT_USED[slot] = true;
                SLOT_STORM_ID[slot] = stormId;
                SLOT_FLASH_START[slot] = Integer.MIN_VALUE;
                SLOT_BEARING[slot] = 0.0D;
                SLOT_LAT[slot] = 0.0F;
                SLOT_NEXT_FLASH[slot] = now + nextInterval(stormId, now);
                return slot;
            }
        }
        return -1;
    }

    private static void freeSlot(int slot) {
        releaseLight(slot);
        SLOT_USED[slot] = false;
        SLOT_FLASH_START[slot] = Integer.MIN_VALUE;
    }

    private static boolean anySlotUsed() {
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            if (SLOT_USED[slot]) {
                return true;
            }
        }
        return false;
    }

    /** Disconnect/respawn hygiene (B1): no flash, light or skew survives the warp. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        reset();
    }

    private static void reset() {
        for (int slot = 0; slot < MAX_TRACKED; slot++) {
            freeSlot(slot);
        }
        gustSkew = 0.0F;
        // flashSerial deliberately NOT reset: W-C latches the last-seen serial across
        // level changes — a monotonic counter can never re-trigger stale flashes.
    }

    /** Cheap 3-int hash in [0,1) — file-local copy of the shared churn-noise pattern. */
    private static float hash3(int a, int b, int c) {
        int h = a * 668265261 ^ b * 374761393 ^ c * 0x85EBCA77;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0xFFFF) / 65536.0F;
    }
}
