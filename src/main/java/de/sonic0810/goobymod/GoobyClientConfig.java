package de.sonic0810.goobymod;

import net.neoforged.neoforge.common.ModConfigSpec;

/** Local accessibility options; these never alter server gameplay. */
public final class GoobyClientConfig {
    public static final ModConfigSpec SPEC;
    public static final ModConfigSpec.BooleanValue REDUCED_MOTION;
    public static final ModConfigSpec.BooleanValue HIGH_CONTRAST_BUBBLES;
    public static final ModConfigSpec.BooleanValue SHOW_COMPANION_HUD;
    public static final ModConfigSpec.IntValue COMPANION_HUD_OFFSET_X;
    public static final ModConfigSpec.IntValue COMPANION_HUD_OFFSET_Y;
    public static final ModConfigSpec.BooleanValue SCREEN_EFFECTS;
    public static final ModConfigSpec.BooleanValue CAMERA_SHAKE;

    public static final boolean DEFAULT_REDUCED_MOTION = false;
    public static final boolean DEFAULT_HIGH_CONTRAST_BUBBLES = false;
    public static final boolean DEFAULT_SHOW_COMPANION_HUD = true;
    public static final int DEFAULT_COMPANION_HUD_OFFSET_X = 4;
    public static final int DEFAULT_COMPANION_HUD_OFFSET_Y = 4;
    public static final boolean DEFAULT_SCREEN_EFFECTS = true;
    public static final boolean DEFAULT_CAMERA_SHAKE = true;

    static {
        ModConfigSpec.Builder builder = new ModConfigSpec.Builder();
        builder.push("accessibility");
        REDUCED_MOTION = builder
                .comment("Disables cosmetic micro-animations and bubble pop/tail motion.")
                .define("reducedMotion", DEFAULT_REDUCED_MOTION);
        HIGH_CONTRAST_BUBBLES = builder
                .comment("Uses an opaque light panel and dark text for Gooby speech bubbles.")
                .define("highContrastBubbles", DEFAULT_HIGH_CONTRAST_BUBBLES);
        builder.pop();
        builder.push("companionHud");
        SHOW_COMPANION_HUD = builder
                .comment("Shows a compact card with name, mood, command and care bars",
                        "while one of your own tamed Goobys is nearby (purely cosmetic).")
                .define("showCompanionHud", DEFAULT_SHOW_COMPANION_HUD);
        COMPANION_HUD_OFFSET_X = builder
                .comment("Horizontal offset of the companion card from the top-left corner, in GUI pixels.")
                .defineInRange("companionHudOffsetX", DEFAULT_COMPANION_HUD_OFFSET_X, 0, 4096);
        COMPANION_HUD_OFFSET_Y = builder
                .comment("Vertical offset of the companion card from the top-left corner, in GUI pixels.")
                .defineInRange("companionHudOffsetY", DEFAULT_COMPANION_HUD_OFFSET_Y, 0, 4096);
        builder.pop();
        builder.push("screenFx");
        SCREEN_EFFECTS = builder
                .comment("Enables the warm cuddle vignette and the subtle alarm screen pulse.",
                        "The pulse additionally respects reducedMotion.")
                .define("screenEffects", DEFAULT_SCREEN_EFFECTS);
        CAMERA_SHAKE = builder
                .comment("Enables a gentle camera shake when your own Gooby raises a real alarm.",
                        "Also disabled entirely by reducedMotion.")
                .define("cameraShake", DEFAULT_CAMERA_SHAKE);
        builder.pop();
        SPEC = builder.build();
    }

    public static boolean reducedMotion() {
        return SPEC.isLoaded() ? REDUCED_MOTION.get() : DEFAULT_REDUCED_MOTION;
    }

    public static boolean highContrastBubbles() {
        return SPEC.isLoaded() ? HIGH_CONTRAST_BUBBLES.get() : DEFAULT_HIGH_CONTRAST_BUBBLES;
    }

    public static boolean showCompanionHud() {
        return SPEC.isLoaded() ? SHOW_COMPANION_HUD.get() : DEFAULT_SHOW_COMPANION_HUD;
    }

    public static int companionHudOffsetX() {
        return SPEC.isLoaded() ? COMPANION_HUD_OFFSET_X.get() : DEFAULT_COMPANION_HUD_OFFSET_X;
    }

    public static int companionHudOffsetY() {
        return SPEC.isLoaded() ? COMPANION_HUD_OFFSET_Y.get() : DEFAULT_COMPANION_HUD_OFFSET_Y;
    }

    public static boolean screenEffects() {
        return SPEC.isLoaded() ? SCREEN_EFFECTS.get() : DEFAULT_SCREEN_EFFECTS;
    }

    public static boolean cameraShake() {
        return SPEC.isLoaded() ? CAMERA_SHAKE.get() : DEFAULT_CAMERA_SHAKE;
    }

    private GoobyClientConfig() {
    }
}
