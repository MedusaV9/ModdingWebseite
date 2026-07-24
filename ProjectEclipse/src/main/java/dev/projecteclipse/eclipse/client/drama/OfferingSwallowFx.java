package dev.projecteclipse.eclipse.client.drama;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.MeshData;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.client.renderer.texture.SpriteContents;
import net.minecraft.client.renderer.texture.TextureAtlasSprite;
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
 * <p><b>W-P-ALTAR2 glow + value tell</b>: the spiraling item carries a soft additive
 * glow fan whose inner color is SAMPLED from the item's own particle sprite (average of
 * the opaque pixels, mixed toward the violet-gold house palette; violet-gold dual tone
 * when sampling fails) and whose brightness follows the offerer-private tier riding the
 * emitter id ({@link S2CQuasarPayload#offeringSwallowTier} — richer offering = brighter
 * swallow; bystanders always see the neutral mid tier). On arrival the swallow pokes
 * {@link AltarCeremonyFx#notifyOfferingSwallowed()} so the L3+ aurora veil briefly
 * brightens map-side (the sky acknowledging the meal).</p>
 *
 * <p><b>Fallbacks</b>: under {@code reducedFx} (or when the altar anchor has not synced)
 * the payload degrades to a plain {@code offering_swallow} burst at the hand via
 * {@code QuasarSpawner.spawnOrFallback} — never a silent drop, and no unknown-id warn
 * spam from the item-suffixed ids. The item billboard itself needs no Veil, so the
 * spiral works even when Quasar is unavailable (only the trail motes disappear).
 * Sprite sampling is try/caught with a violet-gold fallback. Budgets: one BURST-channel
 * emitter per flight, flights hard-capped at {@value #MAX_FLIGHTS}; per-frame work is
 * zero while no flight is live.</p>
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

    // --- W-P-ALTAR2 glow fan (item-color aura around the spiraling item) ---
    /** Glow fan alpha per value-tell tier (junk / mid / rich) — the brightness tell. */
    private static final float[] GLOW_TIER_ALPHA = {0.24F, 0.40F, 0.62F};
    /** Item billboard scale multiplier per tier (subtle: the glow carries the tell). */
    private static final float[] GLOW_TIER_SCALE = {0.94F, 1.0F, 1.08F};
    /** Glow fan radius as a multiple of the current item scale. */
    private static final float GLOW_RADIUS_FACTOR = 1.05F;
    private static final int GLOW_FAN_SEGMENTS = 10;
    /** Dual-tone fallback + rim: warm gold core into the house violet rim. */
    private static final float[] GLOW_FALLBACK_CORE = {1.0F, 0.85F, 0.55F};
    private static final float[] GLOW_RIM = {0.62F, 0.42F, 1.0F};
    /** Sprite sample grid per axis (16 probes across the particle icon). */
    private static final int GLOW_SAMPLE_GRID = 4;

    private static final class Flight {
        final ItemStack stack;
        final Vec3 start;
        final Vec3 target;
        final float spiralPhase;
        /** Value-tell tier 0..2 (offerer-private; bystanders always get 1). */
        final int tier;
        /** Glow core color sampled from the item sprite (violet-gold fallback). */
        final float[] glowColor;
        @Nullable
        ParticleEmitter trail;
        int age;

        Flight(ItemStack stack, Vec3 start, Vec3 target, float spiralPhase, int tier,
                float[] glowColor, @Nullable ParticleEmitter trail) {
            this.stack = stack;
            this.start = start;
            this.target = target;
            this.spiralPhase = spiralPhase;
            this.tier = tier;
            this.glowColor = glowColor;
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
            beginFlight(itemId, pos, S2CQuasarPayload.offeringSwallowTier(emitterId));
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

    private static void beginFlight(ResourceLocation itemId, Vec3 handPos, int tier) {
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
        FLIGHTS.add(new Flight(stack, handPos, target, phase,
                Mth.clamp(tier, 0, 2), sampleItemGlowColor(stack), trail));
    }

    /**
     * W-P-ALTAR2 item-color sampling: averages the opaque pixels of the item's particle
     * sprite (a {@value #GLOW_SAMPLE_GRID}×{@value #GLOW_SAMPLE_GRID} probe grid over the
     * first animation frame), normalizes toward full brightness for additive readability
     * and mixes 30% toward the warm gold house tone so every glow still reads "altar".
     * Dark or unreadable sprites fall back to the violet-gold dual tone.
     */
    private static float[] sampleItemGlowColor(ItemStack stack) {
        try {
            Minecraft minecraft = Minecraft.getInstance();
            TextureAtlasSprite sprite = minecraft.getItemRenderer()
                    .getModel(stack, minecraft.level, null, 0)
                    .getParticleIcon(net.neoforged.neoforge.client.model.data.ModelData.EMPTY);
            SpriteContents contents = sprite.contents();
            NativeImage image = contents.getOriginalImage();
            int width = Math.min(contents.width(), image.getWidth());
            int height = Math.min(contents.height(), image.getHeight());
            long r = 0;
            long g = 0;
            long b = 0;
            int opaque = 0;
            for (int sy = 0; sy < GLOW_SAMPLE_GRID; sy++) {
                for (int sx = 0; sx < GLOW_SAMPLE_GRID; sx++) {
                    int x = (sx * 2 + 1) * width / (GLOW_SAMPLE_GRID * 2);
                    int y = (sy * 2 + 1) * height / (GLOW_SAMPLE_GRID * 2);
                    int abgr = image.getPixelRGBA(x, y); // NativeImage packs ABGR
                    if ((abgr >>> 24) < 48) {
                        continue; // transparent probe
                    }
                    r += abgr & 0xFF;
                    g += (abgr >> 8) & 0xFF;
                    b += (abgr >> 16) & 0xFF;
                    opaque++;
                }
            }
            if (opaque < 3) {
                return GLOW_FALLBACK_CORE;
            }
            float fr = r / (255.0F * opaque);
            float fg = g / (255.0F * opaque);
            float fb = b / (255.0F * opaque);
            // Normalize the dominant channel to 1 (additive glows need brightness) …
            float max = Math.max(fr, Math.max(fg, fb));
            if (max < 0.12F) {
                return GLOW_FALLBACK_CORE; // near-black sprite: keep the dual tone
            }
            fr /= max;
            fg /= max;
            fb /= max;
            // … then fold 30% of the gold house tone in for palette cohesion.
            return new float[]{
                    Mth.lerp(0.3F, fr, GLOW_FALLBACK_CORE[0]),
                    Mth.lerp(0.3F, fg, GLOW_FALLBACK_CORE[1]),
                    Mth.lerp(0.3F, fb, GLOW_FALLBACK_CORE[2])};
        } catch (Throwable t) {
            return GLOW_FALLBACK_CORE; // sprite/atlas unavailable — dual tone fallback
        }
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
                // W-P-ALTAR2: the altar swallowed the item — let the L3+ aurora veil
                // answer with a brief brightening (AltarVeilSky reads the envelope).
                AltarCeremonyFx.notifyOfferingSwallowed();
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
            float scale = BASE_SCALE * (1.0F - t * t) * GLOW_TIER_SCALE[flight.tier];
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
        renderGlowFans(event, poseStack, camera, partialTick);
    }

    /**
     * W-P-ALTAR2 glow fans: an additive camera-facing radial fan around each spiraling
     * item — sampled item color at the core fading into the house violet rim (the
     * violet-gold dual tone when sampling fell back), alpha scaled by the offerer's
     * value-tell tier. One position-color mesh for all flights, drawn additively with
     * {@code depthMask(false)} (the {@code SupplyBeamRenderer} state discipline) so the
     * invisible rim never occludes weather/particles behind it. No texture, no extra
     * particles, zero FX-budget cost.
     */
    private static void renderGlowFans(RenderLevelStageEvent event, PoseStack poseStack,
            Vec3 camera, float partialTick) {
        BufferBuilder buffer = null;
        for (int i = 0; i < FLIGHTS.size(); i++) {
            Flight flight = FLIGHTS.get(i);
            double age = Math.min(flight.age + partialTick, FLIGHT_TICKS);
            float t = (float) (age / FLIGHT_TICKS);
            float radius = BASE_SCALE * (1.0F - t * t) * GLOW_TIER_SCALE[flight.tier]
                    * GLOW_RADIUS_FACTOR;
            if (radius <= 0.02F) {
                continue;
            }
            Vec3 pos = posAt(flight, age);
            // Gentle shimmer so the aura feels alive, phase-split per flight; nudged
            // toward the camera so the additive wash always reads over the item sprite.
            float shimmer = 0.85F + 0.15F * Mth.sin((float) age * 0.55F + flight.spiralPhase);
            float alpha = GLOW_TIER_ALPHA[flight.tier] * shimmer;
            Vec3 toCamera = camera.subtract(pos).normalize().scale(0.08D);
            poseStack.pushPose();
            poseStack.translate(pos.x - camera.x + toCamera.x, pos.y - camera.y + toCamera.y,
                    pos.z - camera.z + toCamera.z);
            poseStack.mulPose(event.getCamera().rotation());
            Matrix4f matrix = poseStack.last().pose();
            if (buffer == null) {
                buffer = Tesselator.getInstance().begin(
                        VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
            }
            float cr = flight.glowColor[0];
            float cg = flight.glowColor[1];
            float cb = flight.glowColor[2];
            for (int seg = 0; seg < GLOW_FAN_SEGMENTS; seg++) {
                float a0 = seg * ((float) Math.PI * 2.0F / GLOW_FAN_SEGMENTS);
                float a1 = (seg + 1) * ((float) Math.PI * 2.0F / GLOW_FAN_SEGMENTS);
                // Degenerate quad = center triangle fan slice: core color → violet rim.
                buffer.addVertex(matrix, 0.0F, 0.0F, 0.0F).setColor(cr, cg, cb, alpha);
                buffer.addVertex(matrix, 0.0F, 0.0F, 0.0F).setColor(cr, cg, cb, alpha);
                buffer.addVertex(matrix, Mth.cos(a0) * radius, Mth.sin(a0) * radius, 0.0F)
                        .setColor(GLOW_RIM[0], GLOW_RIM[1], GLOW_RIM[2], 0.0F);
                buffer.addVertex(matrix, Mth.cos(a1) * radius, Mth.sin(a1) * radius, 0.0F)
                        .setColor(GLOW_RIM[0], GLOW_RIM[1], GLOW_RIM[2], 0.0F);
            }
            poseStack.popPose();
        }
        if (buffer == null) {
            return;
        }
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
        }
        RenderSystem.enableBlend();
        RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(false);
        BufferUploader.drawWithShader(mesh);
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
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
