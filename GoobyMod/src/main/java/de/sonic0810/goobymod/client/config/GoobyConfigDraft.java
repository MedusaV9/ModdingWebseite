package de.sonic0810.goobymod.client.config;

import de.sonic0810.goobymod.GoobyClientConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Mutable working copy of {@link GoobyClientConfig}. The config screen edits
 * this draft only; nothing touches the real config until {@link #saveToConfig()}
 * runs (Done button). Cancel simply discards the draft object.
 */
final class GoobyConfigDraft {
    private static final Logger LOGGER = LoggerFactory.getLogger("goobymod/GoobyConfigDraft");

    boolean showCompanionHud;
    int hudOffsetX;
    int hudOffsetY;
    boolean screenEffects;
    boolean cameraShake;
    boolean reducedMotion;
    boolean highContrastBubbles;

    private GoobyConfigDraft() {
    }

    static GoobyConfigDraft fromConfig() {
        GoobyConfigDraft draft = new GoobyConfigDraft();
        draft.showCompanionHud = GoobyClientConfig.showCompanionHud();
        draft.hudOffsetX = GoobyClientConfig.companionHudOffsetX();
        draft.hudOffsetY = GoobyClientConfig.companionHudOffsetY();
        draft.screenEffects = GoobyClientConfig.screenEffects();
        draft.cameraShake = GoobyClientConfig.cameraShake();
        draft.reducedMotion = GoobyClientConfig.reducedMotion();
        draft.highContrastBubbles = GoobyClientConfig.highContrastBubbles();
        return draft;
    }

    void resetToDefaults() {
        this.showCompanionHud = GoobyClientConfig.DEFAULT_SHOW_COMPANION_HUD;
        this.hudOffsetX = GoobyClientConfig.DEFAULT_COMPANION_HUD_OFFSET_X;
        this.hudOffsetY = GoobyClientConfig.DEFAULT_COMPANION_HUD_OFFSET_Y;
        this.screenEffects = GoobyClientConfig.DEFAULT_SCREEN_EFFECTS;
        this.cameraShake = GoobyClientConfig.DEFAULT_CAMERA_SHAKE;
        this.reducedMotion = GoobyClientConfig.DEFAULT_REDUCED_MOTION;
        this.highContrastBubbles = GoobyClientConfig.DEFAULT_HIGH_CONTRAST_BUBBLES;
    }

    /** True when any draft value differs from the currently saved config. */
    boolean isDirty() {
        return this.showCompanionHud != GoobyClientConfig.showCompanionHud()
                || this.hudOffsetX != GoobyClientConfig.companionHudOffsetX()
                || this.hudOffsetY != GoobyClientConfig.companionHudOffsetY()
                || this.screenEffects != GoobyClientConfig.screenEffects()
                || this.cameraShake != GoobyClientConfig.cameraShake()
                || this.reducedMotion != GoobyClientConfig.reducedMotion()
                || this.highContrastBubbles != GoobyClientConfig.highContrastBubbles();
    }

    /** Writes every value, then persists once and fires the config reload event. */
    void saveToConfig() {
        if (!GoobyClientConfig.SPEC.isLoaded()) {
            // Mirrors the isLoaded() guard on the read side; set()/save() would
            // otherwise throw on an unloaded spec.
            LOGGER.warn("Client config is not loaded; discarding config screen changes");
            return;
        }
        GoobyClientConfig.SHOW_COMPANION_HUD.set(this.showCompanionHud);
        GoobyClientConfig.COMPANION_HUD_OFFSET_X.set(this.hudOffsetX);
        GoobyClientConfig.COMPANION_HUD_OFFSET_Y.set(this.hudOffsetY);
        GoobyClientConfig.SCREEN_EFFECTS.set(this.screenEffects);
        GoobyClientConfig.CAMERA_SHAKE.set(this.cameraShake);
        GoobyClientConfig.REDUCED_MOTION.set(this.reducedMotion);
        GoobyClientConfig.HIGH_CONTRAST_BUBBLES.set(this.highContrastBubbles);
        GoobyClientConfig.SPEC.save();
    }
}
