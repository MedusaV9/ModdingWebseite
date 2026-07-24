package dev.projecteclipse.eclipse.client.drama;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import com.mojang.blaze3d.vertex.PoseStack;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.ItemDisplayContext;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * W4-ISLAND / IDEA-12 #1 — the offering swallow: on the confirm click the server sends
 * one {@code S2CQuasarPayload} whose emitter id rides the offered item
 * ({@link S2CQuasarPayload#offeringSwallow}); this class consumes it (routed from
 * {@code EclipsePayloads.handleQuasar}) and renders the offered item as a billboard
 * spiraling from the offerer's hand into {@link FxAnchors#ALTAR_CENTER} over
 * {@value #FLIGHT_TICKS} ticks, shrinking to zero, with the small
 * {@code eclipse:offering_swallow} trail emitter repositioned along the path.
 *
 * <p><b>Arrival-beat sync</b>: while a swallow is in flight, incoming
 * {@code ALTAR_BEAM} payloads aimed at the flight target are held and re-released the
 * tick the item vanishes into the stone — the light column erupts exactly on arrival.
 * Beams with no matching flight pass through untouched (revive ritual, level-ups while
 * nobody is offering, …).</p>
 *
 * <p><b>Fallbacks</b>: under {@code reducedFx} (or when the altar anchor has not synced)
 * the payload degrades to a plain {@code offering_swallow} burst at the hand via
 * {@code QuasarSpawner.spawnOrFallback} — never a silent drop, and no unknown-id warn
 * spam from the item-suffixed ids. The item billboard itself needs no Veil, so the
 * spiral works even when Quasar is unavailable (only the trail motes disappear).
 * Budgets: one BURST-channel emitter per flight, flights hard-capped at
 * {@value #MAX_FLIGHTS}; per-frame work is zero while no flight is live.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class OfferingSwallowFx {
    /** Hand → altar flight duration (ticks); the beam-hold delay derives from it. */
    public static final int FLIGHT_TICKS = 32;
    /** Peak spiral radius around the flight line (zero at both endpoints). */
    private static final double SPIRAL_RADIUS = 0.9D;
    /** Full spiral turns over the flight. */
    private static final double SPIRAL_TURNS = 2.0D;
    /** Extra vertical arc at mid-flight. */
    private static final double ARC_LIFT = 0.6D;
    /** Item billboard scale at t=0 (shrinks to zero at arrival). */
    private static final float BASE_SCALE = 0.55F;
    /** A held ALTAR_BEAM must land within this of a flight target to be delayed. */
    private static final double BEAM_MATCH_RANGE_SQ = 4.0D * 4.0D;
    /** Concurrency caps (multi-player altar rush safety). */
    private static final int MAX_FLIGHTS = 4;
    private static final int MAX_HELD_BEAMS = 4;
    /** Beam release padding after the item vanishes (ticks). */
    private static final int BEAM_RELEASE_PAD = 2;

    private static final class Flight {
        final ItemStack stack;
        final Vec3 start;
        final Vec3 target;
        final float spiralPhase;
        @Nullable
        ParticleEmitter trail;
        int age;

        Flight(ItemStack stack, Vec3 start, Vec3 target, float spiralPhase,
                @Nullable ParticleEmitter trail) {
            this.stack = stack;
            this.start = start;
            this.target = target;
            this.spiralPhase = spiralPhase;
            this.trail = trail;
        }
    }

    private static final class HeldBeam {
        final Vec3 pos;
        int delay;

        HeldBeam(Vec3 pos, int delay) {
            this.pos = pos;
            this.delay = delay;
        }
    }

    private static final List<Flight> FLIGHTS = new ArrayList<>();
    private static final List<HeldBeam> HELD_BEAMS = new ArrayList<>();

    private OfferingSwallowFx() {}

    // --- payload seam (called from EclipsePayloads.handleQuasar, client main thread) ---

    /**
     * Consumes offering-swallow payloads and (while a swallow is live) altar beams.
     * @return {@code true} when this class handled the payload — the caller must then
     *         NOT forward it to {@code QuasarSpawner.spawnOrFallback}.
     */
    public static boolean intercept(ResourceLocation emitterId, Vec3 pos) {
        ResourceLocation itemId = S2CQuasarPayload.offeringSwallowItem(emitterId);
        if (itemId != null) {
            beginFlight(itemId, pos);
            return true;
        }
        if (S2CQuasarPayload.ALTAR_BEAM.equals(emitterId) && !FLIGHTS.isEmpty()) {
            for (int i = 0; i < FLIGHTS.size(); i++) {
                Flight flight = FLIGHTS.get(i);
                if (flight.target.distanceToSqr(pos) <= BEAM_MATCH_RANGE_SQ
                        && HELD_BEAMS.size() < MAX_HELD_BEAMS) {
                    HELD_BEAMS.add(new HeldBeam(pos,
                            FLIGHT_TICKS - flight.age + BEAM_RELEASE_PAD));
                    return true;
                }
            }
        }
        return false;
    }

    private static void beginFlight(ResourceLocation itemId, Vec3 handPos) {
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null || EclipseClientConfig.reducedFx()) {
            // Degraded beat: one plain trail burst at the hand, beam stays immediate.
            QuasarSpawner.spawnOrFallback(S2CQuasarPayload.OFFERING_SWALLOW, handPos,
                    FxBudget.Channel.BURST);
            return;
        }
        while (FLIGHTS.size() >= MAX_FLIGHTS) {
            finishFlight(FLIGHTS.remove(0));
        }
        ItemStack stack = BuiltInRegistries.ITEM.getOptional(itemId)
                .map(ItemStack::new).orElseGet(() -> new ItemStack(Items.AMETHYST_SHARD));
        Vec3 target = anchor.add(0.0D, 0.9D, 0.0D);
        float phase = (float) (Math.atan2(handPos.z - target.z, handPos.x - target.x));
        ParticleEmitter trail = QuasarSpawner.spawnManaged(
                S2CQuasarPayload.OFFERING_SWALLOW, handPos, FxBudget.Channel.BURST);
        FLIGHTS.add(new Flight(stack, handPos, target, phase, trail));
    }

    // --- tick: advance flights, drag the trail along, release held beams ---

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            clear();
            return;
        }
        if ((FLIGHTS.isEmpty() && HELD_BEAMS.isEmpty()) || minecraft.isPaused()) {
            return;
        }
        Iterator<Flight> flights = FLIGHTS.iterator();
        while (flights.hasNext()) {
            Flight flight = flights.next();
            flight.age++;
            if (flight.age >= FLIGHT_TICKS) {
                flights.remove();
                finishFlight(flight);
                continue;
            }
            if (flight.trail != null) {
                try {
                    if (flight.trail.isRemoved()) {
                        flight.trail = null;
                    } else {
                        flight.trail.setPosition(posAt(flight, flight.age));
                    }
                } catch (Throwable t) {
                    flight.trail = null; // Veil teardown-order safe (LimboAmbience law)
                }
            }
        }
        Iterator<HeldBeam> beams = HELD_BEAMS.iterator();
        while (beams.hasNext()) {
            HeldBeam beam = beams.next();
            if (--beam.delay <= 0) {
                beams.remove();
                QuasarSpawner.spawnOrFallback(S2CQuasarPayload.ALTAR_BEAM, beam.pos,
                        FxBudget.Channel.BURST);
            }
        }
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    /** Ends a flight early or on time; the non-loop trail dies by itself shortly after. */
    private static void finishFlight(Flight flight) {
        if (flight.trail != null) {
            try {
                if (!flight.trail.isRemoved()) {
                    flight.trail.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe.
            }
            flight.trail = null;
        }
    }

    private static void clear() {
        for (int i = 0; i < FLIGHTS.size(); i++) {
            finishFlight(FLIGHTS.get(i));
        }
        FLIGHTS.clear();
        HELD_BEAMS.clear();
    }

    // --- render: the offered item as a shrinking billboard on the spiral ---

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RenderLevelStageEvent.Stage.AFTER_PARTICLES
                || FLIGHTS.isEmpty()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        Vec3 camera = event.getCamera().getPosition();
        PoseStack poseStack = event.getPoseStack();
        MultiBufferSource.BufferSource bufferSource = minecraft.renderBuffers().bufferSource();
        for (int i = 0; i < FLIGHTS.size(); i++) {
            Flight flight = FLIGHTS.get(i);
            double age = Math.min(flight.age + partialTick, FLIGHT_TICKS);
            Vec3 pos = posAt(flight, age);
            float t = (float) (age / FLIGHT_TICKS);
            float scale = BASE_SCALE * (1.0F - t * t);
            if (scale <= 0.01F) {
                continue;
            }
            poseStack.pushPose();
            poseStack.translate(pos.x - camera.x, pos.y - camera.y, pos.z - camera.z);
            poseStack.mulPose(event.getCamera().rotation()); // billboard toward the camera
            poseStack.scale(scale, scale, scale);
            minecraft.getItemRenderer().renderStatic(flight.stack, ItemDisplayContext.GROUND,
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY, poseStack,
                    bufferSource, minecraft.level, 0);
            poseStack.popPose();
        }
        bufferSource.endBatch();
    }

    /**
     * Flight position at fractional age: ease-in-out along hand → altar with a spiral
     * whose radius is zero at both endpoints (starts exactly in the hand, vanishes
     * exactly into the stone) plus a small mid-flight arc lift.
     */
    private static Vec3 posAt(Flight flight, double age) {
        double t = Mth.clamp(age / FLIGHT_TICKS, 0.0D, 1.0D);
        double eased = t * t * (3.0D - 2.0D * t);
        double radius = SPIRAL_RADIUS * Math.sin(Math.PI * t);
        double angle = flight.spiralPhase + t * Math.PI * 2.0D * SPIRAL_TURNS;
        return new Vec3(
                Mth.lerp(eased, flight.start.x, flight.target.x) + Math.cos(angle) * radius,
                Mth.lerp(eased, flight.start.y, flight.target.y)
                        + Math.sin(Math.PI * t) * ARC_LIFT,
                Mth.lerp(eased, flight.start.z, flight.target.z) + Math.sin(angle) * radius);
    }
}
