package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CSupplyMarkerPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import foundry.veil.api.client.render.VeilRenderSystem;
import foundry.veil.api.client.render.light.data.PointLightData;
import foundry.veil.api.client.render.light.renderer.LightRenderHandle;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client state of the supply-drop beams (P2 R7, W5). {@link #handle} is the FROZEN entry
 * point {@code network.fx.FxPayloads} dispatches {@code S2CSupplyMarkerPayload} to:
 * <ul>
 *   <li>{@code add=true, fadeTicks>0} — fresh drop: beam fades in over {@code fadeTicks} and
 *       plays the one-shot landing FX ({@code eclipse:altar_beam} burst — now light-module
 *       free — plus the {@code eclipse:supply_spark} spark pop) when the drop is within
 *       {@value #BURST_FX_RANGE} blocks.</li>
 *   <li>{@code add=true, fadeTicks=0} — resync (login/dimension return) or beam-base
 *       reposition (crate landed past the predicted surface): the beam snaps without
 *       replaying burst FX. Beams are keyed by their XZ column, so a reposition updates the
 *       existing beam instead of stacking a second one.</li>
 *   <li>{@code add=false} — loot/break/expiry: fade out over {@code fadeTicks} (0 snaps),
 *       then release everything.</li>
 * </ul>
 *
 * <p><b>Perf contract (the "ultra lag" fix, P2 §1.5/§1.10):</b> the v1 drop attached a Veil
 * point light to every {@code altar_beam} particle (~60 concurrent lights per drop) while the
 * server flooded long-distance END_ROD packets. Now each beam owns at most ONE
 * {@link PointLightData} (radius {@value #LIGHT_RADIUS}, pulsing violet), claimed through
 * {@link FxBudget#tryLight()} only while the camera is within {@value #LIGHT_ATTACH_RANGE}
 * blocks (released beyond {@value #LIGHT_RELEASE_RANGE} — hysteresis so the boundary never
 * flickers), and the geometry beam ({@link SupplyBeamRenderer}) is a handful of quads.</p>
 *
 * <p>Each beam also carries the positional {@code event.beam_hum} loop (fixed 48-block
 * range), volume-tied to the beam's fade so it never pops in or out. Beams clear on
 * disconnect and whenever the local player leaves the overworld — the server re-syncs the
 * active set on every overworld (re-)entry.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SupplyBeamClient {
    private static final ResourceLocation ALTAR_BEAM_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "altar_beam");
    private static final ResourceLocation SUPPLY_SPARK_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "supply_spark");

    /** One-shot landing FX only when the drop is reasonably close (bursts are garnish, not the marker). */
    private static final double BURST_FX_RANGE = 128.0D;
    /** Camera distance within which a beam claims its single budgeted point light. */
    private static final double LIGHT_ATTACH_RANGE = 64.0D;
    /** Camera distance beyond which a held light is returned (hysteresis vs. attach range). */
    private static final double LIGHT_RELEASE_RANGE = 80.0D;
    /** P2 R7 frozen light spec: radius 12, brightness 0.9±0.15, purple. */
    private static final float LIGHT_RADIUS = 12.0F;
    private static final float LIGHT_BRIGHTNESS_BASE = 0.9F;
    private static final float LIGHT_BRIGHTNESS_PULSE = 0.15F;
    /** Fallback fade length when a remove arrives with {@code fadeTicks <= 0} (snap). */
    private static final int SNAP_TICKS = 1;

    /** Live beams (a handful at most — linear scans beat boxing a map key). */
    private static final List<Beam> BEAMS = new ArrayList<>(4);
    /** Latched after the Veil light renderer throws once — beams simply go light-less. */
    private static boolean lightsBroken;

    private SupplyBeamClient() {}

    /** FROZEN dispatch target of {@code eclipse:fx/supply_marker} (called on the client main thread). */
    public static void handle(S2CSupplyMarkerPayload payload) {
        if (payload.add()) {
            add(payload.pos(), payload.fadeTicks());
        } else {
            remove(payload.pos(), payload.fadeTicks());
        }
    }

    /** Live beams for {@link SupplyBeamRenderer} (read-only by convention; never mutate). */
    static List<Beam> beams() {
        return BEAMS;
    }

    private static void add(BlockPos pos, int fadeTicks) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            return;
        }
        Beam existing = findByColumn(pos);
        if (existing != null) {
            // Reposition (crate landed deeper than predicted) or resync refresh: keep the
            // current fade state, just re-anchor and cancel any pending fade-out.
            existing.moveTo(pos);
            existing.cancelFadeOut();
            return;
        }
        boolean fresh = fadeTicks > 0;
        Beam beam = new Beam(pos, fresh ? fadeTicks : 0);
        BEAMS.add(beam);
        beam.startHum(minecraft);
        if (fresh && minecraft.gameRenderer.getMainCamera().getPosition()
                .distanceToSqr(Vec3.atCenterOf(pos)) <= BURST_FX_RANGE * BURST_FX_RANGE) {
            Vec3 base = Vec3.atCenterOf(pos.above());
            QuasarSpawner.spawn(ALTAR_BEAM_EMITTER, base, FxBudget.Channel.BURST);
            QuasarSpawner.spawn(SUPPLY_SPARK_EMITTER, base, FxBudget.Channel.BURST);
        }
    }

    private static void remove(BlockPos pos, int fadeTicks) {
        Beam beam = findByColumn(pos);
        if (beam != null) {
            beam.startFadeOut(Math.max(fadeTicks, SNAP_TICKS));
        }
    }

    @Nullable
    private static Beam findByColumn(BlockPos pos) {
        for (int i = 0; i < BEAMS.size(); i++) {
            Beam beam = BEAMS.get(i);
            if (beam.pos.getX() == pos.getX() && beam.pos.getZ() == pos.getZ()) {
                return beam;
            }
        }
        return null;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (BEAMS.isEmpty()) {
            return;
        }
        // Beams are an overworld feature; the server re-syncs on every overworld (re-)entry,
        // so leaving the dimension (or the game) simply clears the local set.
        if (level == null || level.dimension() != Level.OVERWORLD) {
            clearAll();
            return;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        for (int i = BEAMS.size() - 1; i >= 0; i--) {
            Beam beam = BEAMS.get(i);
            beam.tick(camera);
            if (beam.dead()) {
                beam.release();
                BEAMS.remove(i);
            }
        }
    }

    /** Disconnect reset hook (mirrors {@code QuasarSpawner.DisconnectReset}). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clearAll();
    }

    private static void clearAll() {
        for (int i = 0; i < BEAMS.size(); i++) {
            BEAMS.get(i).release();
        }
        BEAMS.clear();
    }

    /**
     * One live beam: base position, eased visibility (prev/current pair for partial-tick
     * interpolation in the renderer), the optional budgeted point light and the hum loop.
     */
    static final class Beam {
        BlockPos pos;
        /** Beam base center, cached for distance math (updated on {@link #moveTo}). */
        Vec3 baseCenter;
        float prevAlpha;
        float alpha;
        /** Per-beam pulse phase so simultaneous drops don't throb in sync. */
        final float pulsePhase;
        private int fadeInTicks;
        /** {@code > 0} while fading out; reaching 0 removes the beam. */
        private int fadeOutTicks = -1;
        private float fadeOutStep;
        private boolean removed;

        @Nullable
        private LightRenderHandle<PointLightData> light;
        private boolean lightBudgeted;
        @Nullable
        private BeamHumSound hum;
        private int lightTicks;

        private Beam(BlockPos pos, int fadeInTicks) {
            this.pos = pos;
            this.baseCenter = Vec3.atCenterOf(pos);
            this.fadeInTicks = Math.max(0, fadeInTicks);
            this.alpha = this.fadeInTicks > 0 ? 0.0F : 1.0F;
            this.prevAlpha = this.alpha;
            this.pulsePhase = (Mth.murmurHash3Mixer(pos.getX() * 31 + pos.getZ()) & 0xFFFF) / 65535.0F * Mth.TWO_PI;
        }

        void moveTo(BlockPos newPos) {
            this.pos = newPos;
            this.baseCenter = Vec3.atCenterOf(newPos);
        }

        void cancelFadeOut() {
            this.fadeOutTicks = -1;
        }

        void startFadeOut(int ticks) {
            if (this.fadeOutTicks < 0) {
                this.fadeOutTicks = ticks;
                this.fadeOutStep = this.alpha / ticks;
            }
        }

        boolean dead() {
            return this.fadeOutTicks == 0;
        }

        private void tick(Vec3 camera) {
            this.prevAlpha = this.alpha;
            if (this.fadeOutTicks > 0) {
                this.fadeOutTicks--;
                this.alpha = Math.max(0.0F, this.alpha - this.fadeOutStep);
            } else if (this.fadeOutTicks < 0 && this.alpha < 1.0F) {
                this.alpha = this.fadeInTicks > 0
                        ? Math.min(1.0F, this.alpha + 1.0F / this.fadeInTicks)
                        : 1.0F;
            }
            this.lightTicks++;
            tickLight(camera);
        }

        /** Claim/update/release the beam's single budgeted point light by camera distance. */
        private void tickLight(Vec3 camera) {
            double distSq = camera.distanceToSqr(this.baseCenter);
            if (this.light != null && !this.light.isValid()) {
                // Veil freed the handle (level swap teardown) — return the budget slot.
                this.light = null;
                if (this.lightBudgeted) {
                    this.lightBudgeted = false;
                    FxBudget.releaseLight();
                }
            }
            if (this.light == null) {
                if (!lightsBroken && this.fadeOutTicks < 0
                        && distSq <= LIGHT_ATTACH_RANGE * LIGHT_ATTACH_RANGE && FxBudget.tryLight()) {
                    this.lightBudgeted = true;
                    try {
                        PointLightData data = new PointLightData();
                        data.setColor(0.71F, 0.36F, 1.0F);
                        data.setRadius(LIGHT_RADIUS);
                        data.setBrightness(0.0F);
                        this.light = VeilRenderSystem.renderer().getLightRenderer().addLight(data);
                    } catch (Throwable t) {
                        this.lightBudgeted = false;
                        FxBudget.releaseLight();
                        if (!lightsBroken) {
                            lightsBroken = true;
                            EclipseMod.LOGGER.warn("Veil light renderer unavailable; supply beams render without dynamic lights", t);
                        }
                    }
                }
                if (this.light == null) {
                    return;
                }
            }
            if (distSq > LIGHT_RELEASE_RANGE * LIGHT_RELEASE_RANGE) {
                releaseLight();
                return;
            }
            // R7 frozen pulse: brightness 0.9±0.15, scaled with the beam fade. The setters
            // bump the light revision themselves (markDirty is deprecated for data lights).
            float pulse = LIGHT_BRIGHTNESS_BASE
                    + LIGHT_BRIGHTNESS_PULSE * Mth.sin(this.lightTicks * 0.2F + this.pulsePhase);
            PointLightData data = this.light.getLightData();
            data.setPosition(this.baseCenter.x, this.baseCenter.y + 1.5D, this.baseCenter.z);
            data.setBrightness(pulse * this.alpha);
        }

        private void startHum(Minecraft minecraft) {
            if (this.hum == null || this.hum.isStopped()) {
                this.hum = new BeamHumSound(this);
                minecraft.getSoundManager().play(this.hum);
            }
        }

        /** Returns every held resource (light slot, hum loop). Safe to call repeatedly. */
        private void release() {
            this.removed = true;
            releaseLight();
            BeamHumSound sound = this.hum;
            if (sound != null) {
                sound.end();
                this.hum = null;
            }
        }

        private void releaseLight() {
            LightRenderHandle<PointLightData> handle = this.light;
            this.light = null;
            if (handle != null) {
                try {
                    handle.free();
                } catch (Throwable ignored) {
                    // Teardown-order safe: Veil may already have freed its state.
                }
            }
            if (this.lightBudgeted) {
                this.lightBudgeted = false;
                FxBudget.releaseLight();
            }
        }
    }

    /**
     * Positional {@code event.beam_hum} loop at the beam base (fixed 48-block range set at
     * registration). Volume follows the beam's fade, so loot removal winds the hum down over
     * the same 2 s as the visual.
     */
    private static final class BeamHumSound extends AbstractTickableSoundInstance {
        private static final float MAX_VOLUME = 0.8F;

        private final Beam beam;

        private BeamHumSound(Beam beam) {
            super(EclipseSounds.EVENT_BEAM_HUM.get(), SoundSource.AMBIENT,
                    SoundInstance.createUnseededRandom());
            this.beam = beam;
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.x = beam.baseCenter.x;
            this.y = beam.baseCenter.y;
            this.z = beam.baseCenter.z;
        }

        @Override
        public void tick() {
            if (this.beam.removed) {
                this.stop();
                return;
            }
            this.x = this.beam.baseCenter.x;
            this.y = this.beam.baseCenter.y;
            this.z = this.beam.baseCenter.z;
            this.volume = MAX_VOLUME * this.beam.alpha;
        }

        /** External stop for beam removal/disconnect (LimboLoopSound.forceStop pattern). */
        void end() {
            this.stop();
        }
    }
}
