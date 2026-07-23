package dev.projecteclipse.eclipse.client.handbook;

import java.util.concurrent.ThreadLocalRandom;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.sounds.SoundEvent;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The Eclipse UI sound suite ({@code docs/ideas/03_ui_ux.md} §A "Hover sounds"): thin
 * {@code SimpleSoundInstance.forUI} helpers over the W9 {@code EclipseSounds} UI events,
 * all gated by the {@code uiSounds} client config. Hover calls are meant to be driven by
 * edge detection ({@code EclipseWidget}'s {@code wasHovered} flip), never per-frame.
 * Shared plumbing — W15's menu/settings widgets and the announcement typewriter reuse
 * these directly. Deliberately NOT routed through here: the heart-shatter crack and the
 * mark bell toll (gameplay-critical warnings that must survive {@code uiSounds=false}).
 */
@OnlyIn(Dist.CLIENT)
public final class UiSounds {
    private UiSounds() {}

    /** Interactive element became hovered. Small pitch jitter keeps rows of widgets lively. */
    public static void hover() {
        play(EclipseSounds.UI_HOVER.get(), 0.95F + ThreadLocalRandom.current().nextFloat() * 0.1F, 0.5F);
    }

    /** Handbook page-turn whoosh (tab switch animation). */
    public static void pageTurn() {
        play(EclipseSounds.UI_PAGE_TURN.get(), 0.9F + ThreadLocalRandom.current().nextFloat() * 0.2F, 0.8F);
    }

    /** Tab tongue press. */
    public static void tab() {
        play(EclipseSounds.UI_TAB.get(), 1.0F, 0.7F);
    }

    /** Unlock sting (altar level-up pulse, future unlock reveals). */
    public static void unlockSting() {
        play(EclipseSounds.UI_UNLOCK_STING.get(), 1.0F, 0.9F);
    }

    /**
     * Typewriter tick of the announcement line (every 2nd revealed character). The caller
     * supplies the per-tick pitch jitter; volume matches the other UI blips.
     */
    public static void typewriter(float pitch) {
        play(EclipseSounds.UI_TYPEWRITER.get(), pitch, 0.55F);
    }

    private static void play(SoundEvent sound, float pitch, float volume) {
        if (!EclipseClientConfig.uiSounds()) {
            return;
        }
        Minecraft.getInstance().getSoundManager().play(SimpleSoundInstance.forUI(sound, pitch, volume));
    }
}
