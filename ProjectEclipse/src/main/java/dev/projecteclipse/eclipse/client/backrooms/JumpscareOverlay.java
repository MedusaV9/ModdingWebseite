package dev.projecteclipse.eclipse.client.backrooms;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsPayloads;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * THE jumpscare presentation (IDEAS-backrooms_finale §A4) — the client end of
 * {@code BackroomsPayloads.S2CJumpscarePayload}, installed as the payload consumer from
 * class init (the {@code PortalTransitionController} seam pattern; this class is
 * annotation-loaded on the client, so the seam exists before any payload can arrive).
 *
 * <p><b>Single envelope, no strobe</b> (§A4 hard rules): 2 t in → 8 t hold → 6 t out =
 * 16 t ≈ {@value #ENVELOPE_MILLIS} ms total, ONE event, never re-triggered while
 * active:</p>
 * <ul>
 *   <li><b>Face</b>: {@code textures/gui/backrooms_scare.png} (the Wanderer's own head
 *       front face, python-companion art) at 70% screen height, centered, alpha capped
 *       at {@value #PEAK_ALPHA} — never fully opaque.</li>
 *   <li><b>Sound</b>: {@code WARDEN_SONIC_CHARGE} at 0.9F/0.7F pitch (the
 *       {@code TheOtherEntity.die()} palette — recognizably "the entity family") plus a
 *       {@code ui.error_glitch} burst; UI channel, no positional audio.</li>
 *   <li><b>One</b> {@link CameraDirector#addShakeImpulse(float, int, float)} rattle
 *       impulse — sharp, decays inside the envelope; no new shake code.</li>
 *   <li><b>{@code reducedFx}</b> (§A4 photosensitivity cap): NO face, NO shake — a
 *       {@value #VIGNETTE_PEAK_ALPHA}-alpha dark vignette pulse on the same single
 *       fade envelope plus the sound at 0.5 volume.</li>
 * </ul>
 *
 * <p>GUI layer: registered by {@code EclipseGuiLayers} UNDER {@code CaptionRenderer}'s
 * layer and over the letterbox (§A4 layering — captions must stay readable over the
 * face). Reset on logout.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class JumpscareOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "backrooms_jumpscare");

    private static final ResourceLocation FACE_TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/backrooms_scare.png");
    private static final int FACE_TEXTURE_SIZE = 256;

    /** §A4: 2 t in → 8 t hold → 6 t out, wall-clock (a stalled tick can't freeze it). */
    private static final long ATTACK_MILLIS = 100L;
    private static final long HOLD_END_MILLIS = 500L;
    private static final long ENVELOPE_MILLIS = 800L;
    /** §A4 cap: the face never exceeds 85% alpha. */
    private static final float PEAK_ALPHA = 0.85F;
    /** reducedFx vignette pulse peak (§A4: 25%). */
    private static final float VIGNETTE_PEAK_ALPHA = 0.25F;

    /** Envelope start, wall clock; {@code 0} = idle. */
    private static long startMillis;

    static {
        // Payload consumer seam: installed on client class-load so the common-side
        // BackroomsPayloads never references client classes.
        BackroomsPayloads.setClientJumpscareHandler(payload -> trigger(payload.intensity()));
    }

    private JumpscareOverlay() {}

    /** Payload entry (client main thread). Ignored while an envelope is running. */
    public static void trigger(float intensity) {
        long now = System.currentTimeMillis();
        if (startMillis != 0L && now - startMillis < ENVELOPE_MILLIS) {
            return; // never stack/extend — one envelope, once (§A4)
        }
        startMillis = now;
        boolean reduced = EclipseClientConfig.reducedFx();
        float clamped = Mth.clamp(intensity, 0.0F, 1.0F);

        Minecraft minecraft = Minecraft.getInstance();
        // The sting plays for BOTH variants; reducedFx halves it to 0.5 volume (§A4).
        float volume = (reduced ? 0.5F : 0.9F) * clamped;
        minecraft.getSoundManager().play(SimpleSoundInstance.forUI(
                SoundEvents.WARDEN_SONIC_CHARGE, 0.7F, volume));
        minecraft.getSoundManager().play(SimpleSoundInstance.forUI(
                EclipseSounds.UI_ERROR_GLITCH.get(), 0.55F, volume));

        if (!reduced) {
            // Exactly ONE shake impulse (§A4) — sharp rattle, decays inside the envelope.
            CameraDirector.addShakeImpulse(0.8F * clamped, 16, 1.8F);
        }
        EclipseMod.LOGGER.debug("Backrooms jumpscare envelope started (intensity {}, reducedFx {})",
                clamped, reduced);
    }

    /** GUI-layer body (registered by {@code EclipseGuiLayers} below the caption layer). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        if (startMillis == 0L) {
            return;
        }
        long t = System.currentTimeMillis() - startMillis;
        if (t >= ENVELOPE_MILLIS) {
            startMillis = 0L;
            return;
        }
        // 2t in -> 8t hold -> 6t out: one single-cycle fade, no strobe (§A4).
        float envelope;
        if (t < ATTACK_MILLIS) {
            envelope = t / (float) ATTACK_MILLIS;
        } else if (t < HOLD_END_MILLIS) {
            envelope = 1.0F;
        } else {
            envelope = 1.0F - (t - HOLD_END_MILLIS) / (float) (ENVELOPE_MILLIS - HOLD_END_MILLIS);
        }

        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        if (EclipseClientConfig.reducedFx()) {
            renderVignette(guiGraphics, width, height, VIGNETTE_PEAK_ALPHA * envelope);
            return;
        }

        // Face: 70% of screen height, centered (§A4). Alpha-capped by construction.
        float alpha = PEAK_ALPHA * envelope;
        if (alpha <= 0.01F) {
            return;
        }
        int side = Math.round(height * 0.7F);
        int x = (width - side) / 2;
        int y = (height - side) / 2;
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(FACE_TEXTURE, x, y, side, side,
                0.0F, 0.0F, FACE_TEXTURE_SIZE, FACE_TEXTURE_SIZE, FACE_TEXTURE_SIZE, FACE_TEXTURE_SIZE);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        // Thin dark edge frame under the face — pulls the eye center without more alpha.
        renderVignette(guiGraphics, width, height, 0.3F * envelope);
    }

    /** Soft dark edge wash (the whole reducedFx presentation; a garnish otherwise). */
    private static void renderVignette(GuiGraphics guiGraphics, int width, int height, float alpha) {
        if (alpha <= 0.01F) {
            return;
        }
        int band = Math.max(16, height / 5);
        int solid = argb(alpha, 0x1A, 0x14, 0x02); // near-black with the yellow rot tint
        int clear = argb(0.0F, 0x1A, 0x14, 0x02);
        guiGraphics.fillGradient(0, 0, width, band, solid, clear);
        guiGraphics.fillGradient(0, height - band, width, height, clear, solid);
    }

    private static int argb(float alpha, int red, int green, int blue) {
        return (Mth.floor(Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | (red << 16) | (green << 8) | blue;
    }

    /** Disconnect reset — a scare can never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        startMillis = 0L;
    }
}
