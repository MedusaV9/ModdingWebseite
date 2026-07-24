package dev.projecteclipse.eclipse.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.light.data.PointLightData;
import foundry.veil.api.client.render.light.renderer.LightRenderHandle;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Ship-door purple glow (P2 R18(b), W10). While the door glow is on and the
 * {@link FxAnchors#SHIP_DOOR} anchor is published (P6 sets it at the door's visual center),
 * this class maintains:
 * <ul>
 *   <li><b>one</b> budgeted Veil point light ({@link FxBudget#tryLight()} — never more than
 *       one slot held): radius {@value #LIGHT_RADIUS}, violet, brightness pulsing
 *       0.8&ndash;1.2 at 0.5&nbsp;Hz ({@value #PULSE_PERIOD_TICKS}-tick period);</li>
 *   <li>the looping {@code eclipse:door_glow_motes} emitter (rate 6 / count 1, motes drift
 *       upward, steady state &le; 12 live particles), charged to the AMBIENT budget channel.
 *       The emitter JSON is {@code loop: true} and position-based, so the handle from
 *       {@link QuasarSpawner#spawnManaged} is kept and removed explicitly — the
 *       {@code LimboAmbience} reference pattern.</li>
 * </ul>
 *
 * <p><b>Trigger contract (frozen §3.2):</b> {@code network.fx.FxPayloads} dispatches the
 * {@code eclipse:fx/door_glow} FX event to {@link #handleDoorGlow(boolean)} ({@code on} =
 * {@code a > 0.5}). P6 fires the event on door state changes; the desired state is
 * remembered here, so the event and the anchor payload may arrive in any order — FX
 * materialize once both are present (and vanish again if the anchor is removed).</p>
 *
 * <p><b>Gating:</b> lights and Quasar motes are world FX, NOT Veil post pipelines — they
 * deliberately ignore the Iris gate (§7 fallback rule). A {@code d²} proximity gate
 * ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST} blocks, hysteresis so the boundary
 * never flickers) keeps the cost at zero away from the ship and doubles as the cross-
 * dimension guard: anchors carry no dimension client-side, and a level swap also releases
 * everything via the {@code fxLevel} identity check (the Veil light renderer is not
 * level-bound, so a stale light would otherwise survive the hop).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ShipDoorGlow {
    /** Loop emitter at the door (W10-owned JSON: {@code quasar/emitters/door_glow_motes.json}). */
    private static final ResourceLocation MOTES_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "door_glow_motes");

    /** R18(b): light radius 6 (within the §3.5 "radius ≤ 16" law). */
    private static final float LIGHT_RADIUS = 6.0F;
    /** 0.5 Hz pulse = one full cycle every 40 ticks. */
    private static final int PULSE_PERIOD_TICKS = 40;
    /** Brightness swings {@code 1.0 ± 0.2} → the frozen 0.8–1.2 pulse. */
    private static final float PULSE_BASE = 1.0F;
    private static final float PULSE_AMPLITUDE = 0.2F;
    /** Violet, matching the repo purple palette (#B85CFF-ish). */
    private static final float LIGHT_RED = 0.72F;
    private static final float LIGHT_GREEN = 0.36F;
    private static final float LIGHT_BLUE = 1.0F;

    /** FX materialize within this camera distance (blocks)… */
    private static final double MATERIALIZE_DIST = 48.0D;
    /** …and release only beyond this one (hysteresis, no boundary thrash). */
    private static final double RELEASE_DIST = 56.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Anchor re-broadcasts closer than this (squared) don't reposition anything. */
    private static final double ANCHOR_MOVE_EPSILON_SQ = 1.0e-4D;

    /** Desired state from the last {@code door_glow} event (survives anchor/loading races). */
    private static boolean glowOn;
    /** Pulse time base; advances only while unpaused so the throb freezes with the game. */
    private static int pulseTicks;

    @Nullable
    private static ParticleEmitter motes;
    @Nullable
    private static LightRenderHandle<PointLightData> light;
    /** Whether the single {@link FxBudget} light slot is currently held (acceptance: ≤ 1). */
    private static boolean lightSlotHeld;
    /** Session fuse: the Veil light renderer threw once — motes-only from then on (log-once). */
    private static boolean lightUnavailable;
    /** Level the live FX belong to; a swap (dimension hop) releases them immediately. */
    @Nullable
    private static ClientLevel fxLevel;
    /** Anchor position the live FX were placed at (detects P6 re-broadcasts that move it). */
    @Nullable
    private static Vec3 fxAnchor;

    private ShipDoorGlow() {}

    /**
     * Frozen §3.2 client entry — called by {@code network.fx.FxPayloads} for
     * {@code eclipse:fx/door_glow} ({@code on} = {@code a > 0.5}). Turning off releases the
     * light slot and the motes loop immediately; turning on materializes on the next client
     * tick once the {@code eclipse:ship_door} anchor is known and in range.
     */
    public static void handleDoorGlow(boolean on) {
        glowOn = on;
        if (!on) {
            releaseFx();
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            releaseFx();
            return;
        }
        if (fxLevel != null && fxLevel != level) {
            // Dimension hop: the emitter died with the old level, but the Veil light renderer
            // is not level-bound — release everything and re-materialize in the new level.
            releaseFx();
        }
        if (!glowOn) {
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.SHIP_DOOR);
        if (anchor == null) {
            // Event arrived before the anchor payload (or P6 removed the anchor): hold the
            // desired state and keep waiting — no resources are held meanwhile.
            releaseFx();
            return;
        }
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        boolean live = motes != null || light != null;
        if (distSq > (live ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            releaseFx();
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep resources, freeze the pulse
        }
        pulseTicks++;
        ensureMotes(anchor);
        ensureLight(anchor);
        fxAnchor = anchor;
        fxLevel = level;
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern): drop state AND desire. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        glowOn = false;
        releaseFx();
    }

    // ------------------------------------------------------------------ internals

    /** Spawns/repositions the looping motes emitter at the anchor. */
    private static void ensureMotes(Vec3 anchor) {
        ParticleEmitter emitter = motes;
        boolean dead;
        try {
            dead = emitter == null || emitter.isRemoved();
        } catch (Throwable t) {
            dead = true;
        }
        if (dead) {
            // Budget refusal returns null — simply retried next tick (loops re-charge only
            // on creation, so a live loop costs nothing further).
            motes = QuasarSpawner.spawnManaged(MOTES_EMITTER, anchor, FxBudget.Channel.AMBIENT);
        } else if (anchorMoved(anchor)) {
            try {
                emitter.setPosition(anchor);
            } catch (Throwable t) {
                removeMotes(); // re-created at the new position next tick
            }
        }
    }

    /** Claims/creates/pulses the single door point light. */
    private static void ensureLight(Vec3 anchor) {
        if (lightUnavailable) {
            return;
        }
        LightRenderHandle<PointLightData> handle = light;
        boolean invalid;
        try {
            invalid = handle == null || !handle.isValid();
        } catch (Throwable t) {
            invalid = true;
        }
        if (invalid) {
            light = null;
            if (!lightSlotHeld) {
                if (!FxBudget.tryLight()) {
                    return; // pool exhausted (≤16 law) — retried next tick, glow stays motes-only
                }
                lightSlotHeld = true;
            }
            try {
                PointLightData data = new PointLightData();
                data.setRadius(LIGHT_RADIUS);
                data.setColor(LIGHT_RED, LIGHT_GREEN, LIGHT_BLUE);
                data.setBrightness(PULSE_BASE);
                data.setPosition(anchor.x, anchor.y, anchor.z);
                light = VeilRenderSystem.renderer().getLightRenderer().addLight(data);
            } catch (Throwable t) {
                if (lightSlotHeld) {
                    FxBudget.releaseLight();
                    lightSlotHeld = false;
                }
                lightUnavailable = true;
                EclipseMod.LOGGER.warn("Ship door glow point light unavailable; motes-only for this session", t);
                return;
            }
        }
        handle = light;
        if (handle == null) {
            return;
        }
        try {
            PointLightData data = handle.getLightData();
            data.setBrightness(PULSE_BASE
                    + PULSE_AMPLITUDE * Mth.sin(pulseTicks * (Mth.TWO_PI / PULSE_PERIOD_TICKS)));
            data.setPosition(anchor.x, anchor.y, anchor.z);
            handle.markDirty();
        } catch (Throwable t) {
            freeLight(); // handle went stale mid-pulse (renderer reload) — recreate next tick
        }
    }

    /** Releases every held FX resource; the desired {@code glowOn} state is untouched. */
    private static void releaseFx() {
        removeMotes();
        freeLight();
        fxLevel = null;
        fxAnchor = null;
    }

    private static void removeMotes() {
        ParticleEmitter emitter = motes;
        motes = null;
        if (emitter != null) {
            try {
                if (!emitter.isRemoved()) {
                    emitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (LimboAmbience pattern): dropping the reference is
                // the part that matters — Veil frees emitters with the level either way.
            }
        }
    }

    private static void freeLight() {
        LightRenderHandle<PointLightData> handle = light;
        light = null;
        if (handle != null) {
            try {
                handle.free();
            } catch (Throwable ignored) {
                // Best-effort: Veil may already be tearing the renderer down.
            }
        }
        if (lightSlotHeld) {
            FxBudget.releaseLight();
            lightSlotHeld = false;
        }
    }

    private static boolean anchorMoved(Vec3 anchor) {
        Vec3 last = fxAnchor;
        return last == null || last.distanceToSqr(anchor) > ANCHOR_MOVE_EPSILON_SQ;
    }
}
