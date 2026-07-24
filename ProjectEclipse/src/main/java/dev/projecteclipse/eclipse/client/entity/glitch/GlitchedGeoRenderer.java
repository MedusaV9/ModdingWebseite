package dev.projecteclipse.eclipse.client.entity.glitch;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.glitch.GlitchedMonster;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.cache.object.BakedGeoModel;

/**
 * Shared renderer base for the GLITCHED family — the datamosh presentation layer on
 * top of the frozen {@code EclipseGeoRenderer} (plan §2.3 "glitched" sheet):
 *
 * <ul>
 *   <li><b>Texture flicker:</b> {@link #getTextureLocation} swaps the albedo to
 *       {@code <id>_alt.png} (hue-shifted magenta/cyan + scanline displacement) for
 *       {@value #BURST_MIN_TICKS}–{@value #BURST_MAX_TICKS} t bursts scheduled by a
 *       deterministic hash of (entity id, gameTime window) — irregular per entity, at
 *       most one burst per {@value #WINDOW_TICKS} t window with ~25% quiet windows
 *       (reads as 40–80 t cadence), and burst placement guarantees ≥ 12 t between
 *       bursts (plan quality bar: "unsettling but not seizure-y, interval ≥ 8 t").
 *       The {@code AutoGlowingGeoLayer} resolves its emissive off this same override,
 *       so {@code <id>_alt_glowmask.png} flips in lockstep — the chromatic seams and
 *       heart-core flare with the corruption frame.</li>
 *   <li><b>Pose pop:</b> a rare (~1 in 32 t) single-tick {@code PoseStack} offset in
 *       {@link #preRender} — the whole model renders a few centimeters off for exactly
 *       one tick, like a bad vertex upload. Alive entities only (death holds the
 *       freeze-frame clean).</li>
 *   <li><b>Hit flash (FIX-5, IDEAS-C #2):</b> being hurt forces the corruption frame —
 *       {@code hurtTime ≥ }{@value #HURT_ALT_MIN_HURT_TIME} ORs into the alt-frame
 *       selection, so every hit pops a ~3&nbsp;t datamosh burst in lockstep with the
 *       vanilla red flash (re-hits are throttled by vanilla invulnerability, keeping the
 *       ≥&nbsp;8&nbsp;t seizure guard intact). The first-hurt-frame
 *       {@code eclipse:rift_spark} crackle now lives in the {@code EclipseGeoRenderer}
 *       base ({@code client/entity/geo/HurtSparks}, W4-FEEL hoist) — every custom mob
 *       pops it; this class keeps only the GLITCHED alt-frame extra.</li>
 * </ul>
 *
 * <p>All scheduling is pure function of (entity id, game time): zero per-frame state,
 * consistent across camera cuts and re-renders.</p>
 */
@OnlyIn(Dist.CLIENT)
public abstract class GlitchedGeoRenderer<T extends GlitchedMonster> extends EclipseGeoRenderer<T> {
    /** Scheduling window: at most one alt-burst per window; ~25% windows stay quiet. */
    private static final int WINDOW_TICKS = 40;
    private static final int BURST_MIN_TICKS = 2;
    private static final int BURST_MAX_TICKS = 4;
    /** Burst start offset inside the window ([6, 30]) — keeps ≥ 12 t between bursts. */
    private static final int BURST_OFFSET_MIN = 6;
    private static final int BURST_OFFSET_SPAN = 25;
    /** Pose-pop magnitude, blocks — visible shear without breaking the silhouette. */
    private static final float POP_OFFSET = 0.045F;
    /**
     * Hurt flash: {@code hurtTime} counts 10→0, so requiring ≥ 8 shows the corruption frame
     * for the first ~3 ticks of the flash only (a pop, not a seizure).
     */
    private static final int HURT_ALT_MIN_HURT_TIME = 8;

    private final ResourceLocation baseTexture;
    private final ResourceLocation altTexture;

    protected GlitchedGeoRenderer(EntityRendererProvider.Context context, String geoId,
            boolean turnsHead) {
        super(context, geoId, turnsHead);
        this.baseTexture = ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/entity/" + geoId + ".png");
        this.altTexture = ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/entity/" + geoId + "_alt.png");
        withGlowmask();      // Chromatic seams + heart-core; follows the flicker.
        withUprightDeath();  // Scripted freeze-frame collapse; no vanilla tip-over.
    }

    /** Albedo swap — the glowmask layer resolves off this too (lockstep flicker). */
    @Override
    public ResourceLocation getTextureLocation(T animatable) {
        return isAltFrame(animatable) ? this.altTexture : this.baseTexture;
    }

    @Override
    public void preRender(PoseStack poseStack, T entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender, float partialTick,
            int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender, partialTick,
                packedLight, packedOverlay, colour);
        if (isReRender || !entity.isAlive()) {
            return;
        }
        long popHash = scramble(entity.getId() * 0x9E3779B97F4A7C15L
                ^ entity.level().getGameTime() * 0xC2B2AE3D27D4EB4FL ^ 0x5DEECE66DL);
        if ((popHash & 31L) == 0L) {
            // One-tick vertex-upload glitch: shear the whole model off its anchor.
            poseStack.translate(
                    (((popHash >>> 8) & 7L) - 3.5F) / 3.5F * POP_OFFSET,
                    (((popHash >>> 16) & 7L) - 3.5F) / 3.5F * POP_OFFSET * 0.5F,
                    (((popHash >>> 24) & 7L) - 3.5F) / 3.5F * POP_OFFSET);
        }
    }

    /** Deterministic burst schedule: is the alt (corruption) frame active right now? */
    private boolean isAltFrame(T entity) {
        if (entity.hurtTime >= HURT_ALT_MIN_HURT_TIME) {
            // Hit feedback: corrupting it further — the alt frame pops with the red flash.
            return true;
        }
        long gameTime = entity.level().getGameTime();
        long window = Math.floorDiv(gameTime, WINDOW_TICKS);
        long hash = scramble(entity.getId() * 0x9E3779B97F4A7C15L
                ^ window * 0xD6E8FEB86659FD93L);
        if ((hash & 3L) == 3L) {
            return false; // Quiet window — stretches the felt cadence to 40–80 t.
        }
        long offset = BURST_OFFSET_MIN + ((hash >>> 8) % BURST_OFFSET_SPAN);
        long length = BURST_MIN_TICKS + ((hash >>> 32) % (BURST_MAX_TICKS - BURST_MIN_TICKS + 1));
        long phase = Math.floorMod(gameTime, WINDOW_TICKS);
        return phase >= offset && phase < offset + length;
    }

    /** SplitMix64-style avalanche — cheap, stateless, well distributed. */
    private static long scramble(long x) {
        x ^= x >>> 33;
        x *= 0xFF51AFD7ED558CCDL;
        x ^= x >>> 33;
        x *= 0xC4CEB9FE1A85EC53L;
        x ^= x >>> 33;
        return x;
    }
}
