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
 *
 * <p><b>P3-W3 settings platform ({@code docs/plans_v3/P3_ui.md} §3.4/§7.1)</b>: this file is
 * the single owner of every {@code eclipse-client.toml} key; the getter names below are the
 * FROZEN §7.1 contract sibling workers code against (W1 {@code UiSounds} even binds
 * {@link #uiSoundVolume()} reflectively — do not rename). The typed
 * {@link ModConfigSpec.ConfigValue} handles are deliberately {@code public}: the settings UI
 * ({@code client.menu.SettingsPanel}) writes through them with {@code set()+save()} — never
 * through {@code SPEC.getValues().valueMap()} string lookups (B13), which would silently break
 * the moment the spec gains sections. Everyone else reads through the null-safe getters.</p>
 */
public final class EclipseClientConfig {
    /** Sidebar anchor edge (§7.1 {@code sidebarSide}, consumed by P3-W5). */
    public enum SidebarSide {
        LEFT, RIGHT
    }

    /** Long sidebar rows: single-line ellipsis or wall-clock marquee (§7.1, P3-W5). */
    public enum SidebarOverflow {
        ELLIPSIS, MARQUEE
    }

    /** Bossbar chrome: full themed frame or frameless rounded strip (§7.1, P3-W6). */
    public enum BossbarStyle {
        ORNATE, SLIM
    }

    private static final ModConfigSpec.Builder BUILDER = new ModConfigSpec.Builder();

    // --- v1 keys (semantics unchanged) ---

    public static final ModConfigSpec.BooleanValue CUSTOM_MENU = BUILDER
            .comment("Use the custom Eclipse title screen (false = vanilla title screen).")
            .define("customMenu", true);
    public static final ModConfigSpec.BooleanValue SHOW_BOSSBAR_SKIN = BUILDER
            .comment("Skin Eclipse boss bars with the themed frames (false = minimal strip).")
            .define("showBossbarSkin", true);
    public static final ModConfigSpec.BooleanValue SHOW_SIDEBAR = BUILDER
            .comment("Show the Eclipse sidebar status panel.")
            .define("showSidebar", true);
    public static final ModConfigSpec.BooleanValue UI_SOUNDS = BUILDER
            .comment("Play Eclipse UI sounds (hover blips, page turns, tab presses, unlock stings,",
                    "announcement typewriter ticks). Gameplay-critical warning cues are deliberately",
                    "NOT gated by this and always play: the heart-shatter crack (a life was lost)",
                    "and the mark bell toll (you are being hunted).")
            .define("uiSounds", true);
    public static final ModConfigSpec.BooleanValue CUSTOM_CURSOR = BUILDER
            .comment("Use themed mouse cursors in Eclipse screens.")
            .define("customCursor", true);
    public static final ModConfigSpec.BooleanValue VEIL_POST_FX = BUILDER
            .comment("Enable Veil post-processing effects (limbo grade, sun halo, border glitch).",
                    "Automatically disabled while an Iris shaderpack is active regardless of this value.")
            .define("veilPostFx", true);
    public static final ModConfigSpec.BooleanValue REDUCED_FX = BUILDER
            .comment("Reduce non-essential visual effects (screen shake, particles, pulsing overlays).")
            .define("reducedFx", false);
    public static final ModConfigSpec.BooleanValue CINEMATIC_VIEW_DISTANCE = BUILDER
            .comment("Allow Eclipse cinematics to temporarily raise your render distance for the",
                    "duration of a cutscene (restored automatically afterwards, even after a crash).")
            .define("cinematicViewDistance", true);

    // --- §7.1 platform keys (P3-W3; getter names frozen) ---

    public static final ModConfigSpec.DoubleValue UI_SOUND_VOLUME = BUILDER
            .comment("Volume of the Eclipse UI sound suite, 0.0-1.0 (scales every uiSounds cue).")
            .defineInRange("uiSoundVolume", 1.0D, 0.0D, 1.0D);
    public static final ModConfigSpec.BooleanValue HEARTBEAT_SOUND = BUILDER
            .comment("Play the low-lives warden heartbeat while you are down to 1-2 hearts.")
            .define("heartbeatSound", true);
    public static final ModConfigSpec.EnumValue<SidebarSide> SIDEBAR_SIDE = BUILDER
            .comment("Screen edge the sidebar panel anchors to: LEFT or RIGHT.")
            .defineEnum("sidebarSide", SidebarSide.RIGHT);
    public static final ModConfigSpec.DoubleValue SIDEBAR_SCALE = BUILDER
            .comment("Render scale of the sidebar panel, 0.6-1.4.")
            .defineInRange("sidebarScale", 1.0D, 0.6D, 1.4D);
    public static final ModConfigSpec.EnumValue<SidebarOverflow> SIDEBAR_OVERFLOW = BUILDER
            .comment("Long sidebar rows: ELLIPSIS trims with '…', MARQUEE scrolls them horizontally.")
            .defineEnum("sidebarOverflow", SidebarOverflow.ELLIPSIS);
    public static final ModConfigSpec.EnumValue<BossbarStyle> BOSSBAR_STYLE = BUILDER
            .comment("Themed bossbar chrome: ORNATE full frame or SLIM frameless strip",
                    "(only applies while showBossbarSkin is true).")
            .defineEnum("bossbarStyle", BossbarStyle.ORNATE);
    public static final ModConfigSpec.BooleanValue SHOW_DAY_TIMER = BUILDER
            .comment("Show the real-time day countdown under the bossbar stack.")
            .define("showDayTimer", true);
    public static final ModConfigSpec.BooleanValue CUSTOM_DEATH_SCREEN = BUILDER
            .comment("Replace the vanilla death screen with the Eclipse death/ghost flow",
                    "(false = vanilla death screen killswitch).")
            .define("customDeathScreen", true);
    public static final ModConfigSpec.BooleanValue CUSTOM_LOADING_SCREENS = BUILDER
            .comment("Replace vanilla world-join/dimension loading screens with the Eclipse ones",
                    "(false = vanilla loading screens killswitch).")
            .define("customLoadingScreens", true);
    public static final ModConfigSpec.BooleanValue PURPLE_HEARTS = BUILDER
            .comment("Render the player health row as Eclipse purple hearts",
                    "(false = vanilla red hearts killswitch).")
            .define("purpleHearts", true);
    public static final ModConfigSpec.BooleanValue PROC_MESSAGES = BUILDER
            .comment("Show skill proc messages in chat.")
            .define("procMessages", true);
    public static final ModConfigSpec.BooleanValue SHOW_CUSTOM_XP_BAR = BUILDER
            .comment("Show the Eclipse skill-XP bar and level numeral above the vanilla XP bar.")
            .define("showCustomXpBar", true);
    public static final ModConfigSpec.BooleanValue LEVEL_UP_CELEBRATIONS = BUILDER
            .comment("Play the client-local level-up celebration (hotbar burst, sting).")
            .define("levelUpCelebrations", true);
    public static final ModConfigSpec.BooleanValue ALLOW_SERVER_RENDER_DISTANCE = BUILDER
            .comment("Allow the event server to adjust your render distance (opt-out).")
            .define("allowServerRenderDistance", true);
    public static final ModConfigSpec.ConfigValue<String> LANG_OVERRIDE = BUILDER
            .comment("Eclipse UI language override: \"auto\" (follow the game language), \"en_us\"",
                    "or \"de_de\". Set in-game via /lang, /sprache or the settings language row.")
            .define("langOverride", "auto", value -> value instanceof String token
                    && ("auto".equals(token) || "en_us".equals(token) || "de_de".equals(token)));

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

    /** P2 R12: player toggle for the temporary cutscene render-distance bump (default ON). */
    public static boolean cinematicViewDistance() {
        return get(CINEMATIC_VIEW_DISTANCE, true);
    }

    // --- §7.1 frozen getters ---

    /**
     * UI sound volume 0..1 (W1 {@code UiSounds} binds this via
     * {@code MethodHandles.publicLookup().findStatic(..., double.class)} — signature frozen).
     */
    public static double uiSoundVolume() {
        return SPEC.isLoaded() ? UI_SOUND_VOLUME.get() : 1.0D;
    }

    /** B12: user opt-out for the low-lives warden heartbeat (W7 {@code HeartBurstOverlay}). */
    public static boolean heartbeatSound() {
        return get(HEARTBEAT_SOUND, true);
    }

    public static SidebarSide sidebarSide() {
        return SPEC.isLoaded() ? SIDEBAR_SIDE.get() : SidebarSide.RIGHT;
    }

    public static double sidebarScale() {
        return SPEC.isLoaded() ? SIDEBAR_SCALE.get() : 1.0D;
    }

    public static SidebarOverflow sidebarOverflow() {
        return SPEC.isLoaded() ? SIDEBAR_OVERFLOW.get() : SidebarOverflow.ELLIPSIS;
    }

    public static BossbarStyle bossbarStyle() {
        return SPEC.isLoaded() ? BOSSBAR_STYLE.get() : BossbarStyle.ORNATE;
    }

    public static boolean showDayTimer() {
        return get(SHOW_DAY_TIMER, true);
    }

    public static boolean customDeathScreen() {
        return get(CUSTOM_DEATH_SCREEN, true);
    }

    public static boolean customLoadingScreens() {
        return get(CUSTOM_LOADING_SCREENS, true);
    }

    /** W4-HEARTS R1: purple player-hearts renderer (read reflectively by PurpleHeartsLayer). */
    public static boolean purpleHearts() {
        return get(PURPLE_HEARTS, true);
    }

    public static boolean procMessages() {
        return get(PROC_MESSAGES, true);
    }

    public static boolean showCustomXpBar() {
        return get(SHOW_CUSTOM_XP_BAR, true);
    }

    public static boolean levelUpCelebrations() {
        return get(LEVEL_UP_CELEBRATIONS, true);
    }

    public static boolean allowServerRenderDistance() {
        return get(ALLOW_SERVER_RENDER_DISTANCE, true);
    }

    /** Eclipse UI language override token: {@code auto}, {@code en_us} or {@code de_de}. */
    public static String langOverride() {
        return SPEC.isLoaded() ? LANG_OVERRIDE.get() : "auto";
    }

    /**
     * Persists the language override (W4 {@code EclipseLang.LangConfigBridge} seam). Invalid
     * tokens fall back to {@code auto}; a no-op before the config file is loaded.
     */
    public static void setLangOverride(String value) {
        if (!SPEC.isLoaded()) {
            return;
        }
        String token = "en_us".equals(value) || "de_de".equals(value) ? value : "auto";
        if (!token.equals(LANG_OVERRIDE.get())) {
            LANG_OVERRIDE.set(token);
            LANG_OVERRIDE.save();
        }
    }

    private static boolean get(ModConfigSpec.BooleanValue value, boolean fallback) {
        return SPEC.isLoaded() ? value.get() : fallback;
    }
}
