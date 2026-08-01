package dev.projecteclipse.eclipse.client.entity.glitch;

import java.util.HashSet;
import java.util.Set;

import javax.annotation.Nullable;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.glitch.GlitchedMonster;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.veilfx.Wave4CombatFxRows;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.util.Color;

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
 *   <li><b>Pose pop / glitch blink (MOB-GLITCH pass):</b> a rare (~1 in 32 t)
 *       {@code PoseStack} offset in {@link #preRender} — the whole model renders a few
 *       centimeters off, like a bad vertex upload. The shear now survives only the
 *       FIRST {@value #POP_HOLD_PARTIAL} of its tick (~1–2 rendered frames at 60 fps,
 *       vs. the previous full-tick ≈3+ frame hold), and while it is live the
 *       {@link GlitchGhostLayer} re-renders a translucent magenta copy past the popped
 *       anchor and a cyan copy mirrored behind it — the chromatic ghost that makes the
 *       blink read as an RGB tear instead of a plain lag hitch. Alive entities only
 *       (death holds the freeze-frame clean).</li>
 *   <li><b>Hit flash (FIX-5, IDEAS-C #2):</b> being hurt forces the corruption frame —
 *       {@code hurtTime ≥ }{@value #HURT_ALT_MIN_HURT_TIME} ORs into the alt-frame
 *       selection, so every hit pops a ~3&nbsp;t datamosh burst in lockstep with the
 *       vanilla red flash (re-hits are throttled by vanilla invulnerability, keeping the
 *       ≥&nbsp;8&nbsp;t seizure guard intact). The first-hurt-frame
 *       {@code eclipse:rift_spark} crackle now lives in the {@code EclipseGeoRenderer}
 *       base ({@code client/entity/geo/HurtSparks}, W4-FEEL hoist) — every custom mob
 *       pops it; this class keeps only the GLITCHED alt-frame extra.</li>
 *   <li><b>Death dissolve (W4 A2, IDEA-02 #8):</b> over the LAST
 *       {@value #DISSOLVE_FADE_TICKS} t of the kind's scripted death window
 *       ({@code GlitchedMonster.deathDissolveWindow()}) the body de-rezzes — vertex
 *       alpha ramps from 1 down to {@value #DISSOLVE_MIN_ALPHA} via
 *       {@link #getRenderColor}, with {@link #getRenderType} switching to
 *       {@code entityTranslucent} for the fade (cutout ignores vertex alpha). The tick
 *       the fade opens, one {@code wave4_dissolve_motes} Photon cue pops at the corpse
 *       center (position-anchored — the entity is removed mid-effect): the body
 *       scatters INTO cyan/magenta pixel motes instead of popping out under the poof.
 *       The server-side POOF broadcast stays (it lands on a ~5%-alpha ghost and reads
 *       as residue under the motes).</li>
 * </ul>
 *
 * <p>All scheduling is pure function of (entity id, game time): zero per-frame state,
 * consistent across camera cuts and re-renders — the one exception is the dissolve
 * cue's fired-once set (the {@code HurtSparks} dedup-window pattern: {@code preRender}
 * runs every frame, the cue must fire once per corpse).</p>
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
     * Fraction of the pop tick the shear stays visible. Frames render with
     * {@code partialTick} sweeping 0→1 inside a tick, so gating on {@code < 0.4}
     * caps the hold at ~20 ms — 1–2 frames at 60 fps (the "blink", not a hitch).
     */
    private static final float POP_HOLD_PARTIAL = 0.4F;
    /**
     * Hurt flash: {@code hurtTime} counts 10→0, so requiring ≥ 8 shows the corruption frame
     * for the first ~3 ticks of the flash only (a pop, not a seizure).
     */
    private static final int HURT_ALT_MIN_HURT_TIME = 8;
    /** A2 de-rez: alpha fades over the LAST this-many ticks of the death window. */
    private static final int DISSOLVE_FADE_TICKS = 10;
    /** Fade floor — a faint ghost holds the silhouette until the removal clears it. */
    private static final float DISSOLVE_MIN_ALPHA = 0.05F;
    /** Dissolve-cue dedup safety valve (HurtSparks law: cleared wholesale). */
    private static final int DISSOLVE_MAX_TRACKED = 128;

    /** Corpse ids whose dissolve cue already fired (render thread only). */
    private static final Set<Integer> DISSOLVE_FIRED = new HashSet<>();

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
        addRenderLayer(new GlitchGhostLayer<>(this)); // Chromatic ghost on pop frames.
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
        if (isReRender) {
            return;
        }
        maybeFireDissolve(entity);
        float[] pop = popOffset(entity, partialTick);
        if (pop != null) {
            // Sub-tick vertex-upload glitch: shear the whole model off its anchor.
            poseStack.translate(pop[0], pop[1], pop[2]);
        }
    }

    // --- W4 A2 death dissolve ---

    /** Body de-rez: white with the fade alpha while the dissolve window is open. */
    @Override
    public Color getRenderColor(T animatable, float partialTick, int packedLight) {
        float alpha = dissolveAlpha(animatable, partialTick);
        if (alpha >= 1.0F) {
            return super.getRenderColor(animatable, partialTick, packedLight);
        }
        return Color.ofRGBA(1.0F, 1.0F, 1.0F, alpha);
    }

    /** Cutout ignores vertex alpha — the fade needs the translucent pipeline. */
    @Override
    public RenderType getRenderType(T animatable, ResourceLocation texture,
            @Nullable MultiBufferSource bufferSource, float partialTick) {
        if (dissolveAlpha(animatable, partialTick) < 1.0F) {
            return RenderType.entityTranslucent(texture);
        }
        return super.getRenderType(animatable, texture, bufferSource, partialTick);
    }

    /**
     * The de-rez ramp: 1.0 until the last {@value #DISSOLVE_FADE_TICKS} t of the
     * kind's death window open, then a linear slide to {@value #DISSOLVE_MIN_ALPHA}
     * right as the server-side removal lands. {@code deathTime} ticks client-side too
     * ({@code GlitchedMonster.tickDeath} increments before its server-only branch).
     */
    static float dissolveAlpha(GlitchedMonster entity, float partialTick) {
        if (entity.deathTime <= 0) {
            return 1.0F;
        }
        int fadeStart = entity.deathDissolveWindow() - DISSOLVE_FADE_TICKS;
        float progress = (entity.deathTime + partialTick - fadeStart) / DISSOLVE_FADE_TICKS;
        if (progress <= 0.0F) {
            return 1.0F;
        }
        return Mth.clamp(1.0F - progress * (1.0F - DISSOLVE_MIN_ALPHA),
                DISSOLVE_MIN_ALPHA, 1.0F);
    }

    /**
     * Fires the {@code wave4_dissolve_motes} cue ONCE per corpse the frame its fade
     * opens — position-anchored via the registry's position lane (the corpse is
     * removed ~{@value #DISSOLVE_FADE_TICKS} t later; an entity attach would cut the
     * motes off with the poof). The fired-set is the {@code HurtSparks} dedup pattern:
     * a wholesale-valve clear can at worst re-fire into Photon's same-anchor dedup.
     */
    private static void maybeFireDissolve(GlitchedMonster entity) {
        if (entity.deathTime < entity.deathDissolveWindow() - DISSOLVE_FADE_TICKS) {
            return;
        }
        if (DISSOLVE_FIRED.size() >= DISSOLVE_MAX_TRACKED) {
            DISSOLVE_FIRED.clear();
        }
        if (DISSOLVE_FIRED.add(entity.getId())) {
            PhotonFxRegistry.dispatch(Wave4CombatFxRows.CUE_DISSOLVE_MOTES,
                    entity.position().add(0.0D, entity.getBbHeight() * 0.5D, 0.0D),
                    0.0F, 0.0F);
        }
    }

    /**
     * The shared pop schedule (also read by {@link GlitchGhostLayer}): a ~1-in-32-tick
     * hash gate, live only for the first {@value #POP_HOLD_PARTIAL} of the tick and
     * only on living entities. Returns the shear vector, or {@code null} when idle.
     * Pure function of (entity id, game time) — zero per-frame state.
     */
    @Nullable
    static float[] popOffset(GlitchedMonster entity, float partialTick) {
        if (!entity.isAlive() || partialTick >= POP_HOLD_PARTIAL) {
            return null;
        }
        long popHash = scramble(entity.getId() * 0x9E3779B97F4A7C15L
                ^ entity.level().getGameTime() * 0xC2B2AE3D27D4EB4FL ^ 0x5DEECE66DL);
        if ((popHash & 31L) != 0L) {
            return null;
        }
        return new float[] {
                (((popHash >>> 8) & 7L) - 3.5F) / 3.5F * POP_OFFSET,
                (((popHash >>> 16) & 7L) - 3.5F) / 3.5F * POP_OFFSET * 0.5F,
                (((popHash >>> 24) & 7L) - 3.5F) / 3.5F * POP_OFFSET};
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
