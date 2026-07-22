package dev.projecteclipse.eclipse.core.config;

import net.neoforged.fml.config.ModConfig;
import net.neoforged.fml.ModContainer;
import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * Client-side cosmetic toggles ({@code eclipse-client.toml}, NeoForge {@link ModConfigSpec},
 * type {@link ModConfig.Type#CLIENT}). Registered from the {@code EclipseMod} constructor via
 * {@link #register(ModContainer)}.
 *
 * <p>All getters are safe to call at any time on either dist: before the config file is
 * loaded (or on a dedicated server, where a CLIENT config never loads) they return the
 * built-in default instead of throwing.</p>
 */
public final class EclipseClientConfig {
    private static final ModConfigSpec.Builder BUILDER = new ModConfigSpec.Builder();

    private static final ModConfigSpec.BooleanValue CUSTOM_MENU = BUILDER
            .comment("Use the custom Eclipse title screen (false = vanilla title screen).")
            .define("customMenu", true);
    private static final ModConfigSpec.BooleanValue SHOW_BOSSBAR_SKIN = BUILDER
            .comment("Skin Eclipse boss bars with the themed frames (false = minimal strip).")
            .define("showBossbarSkin", true);
    private static final ModConfigSpec.BooleanValue SHOW_SIDEBAR = BUILDER
            .comment("Show the Eclipse sidebar status panel.")
            .define("showSidebar", true);
    private static final ModConfigSpec.BooleanValue UI_SOUNDS = BUILDER
            .comment("Play Eclipse UI sounds (hover, page turn, ...).")
            .define("uiSounds", true);
    private static final ModConfigSpec.BooleanValue CUSTOM_CURSOR = BUILDER
            .comment("Use themed mouse cursors in Eclipse screens.")
            .define("customCursor", true);
    private static final ModConfigSpec.BooleanValue VEIL_POST_FX = BUILDER
            .comment("Enable Veil post-processing effects (limbo grade, sun halo, border glitch).",
                    "Automatically disabled while an Iris shaderpack is active regardless of this value.")
            .define("veilPostFx", true);
    private static final ModConfigSpec.BooleanValue REDUCED_FX = BUILDER
            .comment("Reduce non-essential visual effects (screen shake, particles, pulsing overlays).")
            .define("reducedFx", false);

    public static final ModConfigSpec SPEC = BUILDER.build();

    private EclipseClientConfig() {}

    /** Registers the CLIENT config on the given mod container. Call once from the mod constructor. */
    public static void register(ModContainer modContainer) {
        modContainer.registerConfig(ModConfig.Type.CLIENT, SPEC);
    }

    public static boolean customMenu() {
        return get(CUSTOM_MENU, true);
    }

    public static boolean showBossbarSkin() {
        return get(SHOW_BOSSBAR_SKIN, true);
    }

    public static boolean showSidebar() {
        return get(SHOW_SIDEBAR, true);
    }

    public static boolean uiSounds() {
        return get(UI_SOUNDS, true);
    }

    public static boolean customCursor() {
        return get(CUSTOM_CURSOR, true);
    }

    public static boolean veilPostFx() {
        return get(VEIL_POST_FX, true);
    }

    public static boolean reducedFx() {
        return get(REDUCED_FX, false);
    }

    private static boolean get(ModConfigSpec.BooleanValue value, boolean fallback) {
        return SPEC.isLoaded() ? value.get() : fallback;
    }
}
