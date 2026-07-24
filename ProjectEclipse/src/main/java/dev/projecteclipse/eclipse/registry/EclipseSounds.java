package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Sound event registry for Project: Eclipse. */
public final class EclipseSounds {
    public static final DeferredRegister<SoundEvent> SOUNDS =
            DeferredRegister.create(Registries.SOUND_EVENT, EclipseMod.MOD_ID);

    /** Looping ambient bed of the Limbo dimension, played and faded by {@code veilfx.LimboAmbience}. */
    public static final Supplier<SoundEvent> AMBIENT_LIMBO_LOOP = SOUNDS.register(
            "ambient.limbo_loop",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.limbo_loop")));

    /** One-shot cue played when the ghost ship submerges during the start event. */
    public static final Supplier<SoundEvent> EVENT_SUBMERGE = SOUNDS.register(
            "event.submerge",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.submerge")));

    /**
     * One-shot cue at the end of the intro rise / finale return camera paths (referenced by
     * the default cutscene JSONs): a reverse-swell rising into a bright airy release.
     */
    public static final Supplier<SoundEvent> EVENT_EMERGE = SOUNDS.register(
            "event.emerge",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.emerge")));

    /** Glass-crack cue played locally when a permanent heart shatters after respawn. */
    public static final Supplier<SoundEvent> UI_HEART_SHATTER = SOUNDS.register(
            "ui.heart_shatter",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.heart_shatter")));

    /** Digital-static burst played when the soft border pushes an entity back (W7). */
    public static final Supplier<SoundEvent> EVENT_BORDER_GLITCH = SOUNDS.register(
            "event.border_glitch",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.border_glitch")));

    /** Single dry tick of the announcement typewriter line (W8; every 2nd revealed char). */
    public static final Supplier<SoundEvent> UI_TYPEWRITER = SOUNDS.register(
            "ui.typewriter",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.typewriter")));

    // W9 UI suite — played via client.handbook.UiSounds (SimpleSoundInstance.forUI,
    // gated by the uiSounds client config).

    /** Soft blip when an interactive UI element becomes hovered (edge-detected). */
    public static final Supplier<SoundEvent> UI_HOVER = SOUNDS.register(
            "ui.hover",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.hover")));

    /** Paper whoosh of the handbook page-turn animation. */
    public static final Supplier<SoundEvent> UI_PAGE_TURN = SOUNDS.register(
            "ui.page_turn",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.page_turn")));

    /** Short two-tone click when a handbook tab tongue is pressed. */
    public static final Supplier<SoundEvent> UI_TAB = SOUNDS.register(
            "ui.tab",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.tab")));

    /** Rising chime sting for UI-visible unlocks (altar ring level-up pulse). */
    public static final Supplier<SoundEvent> UI_UNLOCK_STING = SOUNDS.register(
            "ui.unlock_sting",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.unlock_sting")));

    /** Whisper loop of the Gazer (W10) — audible only within ~12 blocks (ambient sound). */
    public static final Supplier<SoundEvent> AMBIENT_GAZER_WHISPER = SOUNDS.register(
            "ambient.gazer_whisper",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.gazer_whisper"),
                    12.0F));

    // W11 Herald boss suite.

    /** Low glassy drone of the Herald (its mob ambient sound during the fight). */
    public static final Supplier<SoundEvent> BOSS_HERALD_AMBIENT = SOUNDS.register(
            "boss.herald_ambient",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_ambient")));

    /** Rising chime cue at the start of every volley telegraph (the "shoot me now" tell). */
    public static final Supplier<SoundEvent> BOSS_HERALD_TELEGRAPH = SOUNDS.register(
            "boss.herald_telegraph",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_telegraph")));

    // W12 Ferryman boss suite.

    /** Hollow, waterlogged groan of the Ferryman (its mob ambient sound during the fight). */
    public static final Supplier<SoundEvent> BOSS_FERRYMAN_AMBIENT = SOUNDS.register(
            "boss.ferryman_ambient",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.ferryman_ambient")));

    /** Sunken bell toll: crew-phase entry and each lantern re-lit by a ghost. */
    public static final Supplier<SoundEvent> BOSS_FERRYMAN_BELL = SOUNDS.register(
            "boss.ferryman_bell",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.ferryman_bell")));

    // P4 gameplay feedback (R3/R5/R6/R8).

    /** Short chime when a skill proc fires (double drop, etc.). */
    public static final Supplier<SoundEvent> SKILL_PROC = SOUNDS.register(
            "skill.proc",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill.proc")));

    /** Level-up sting when skill XP crosses a level boundary. */
    public static final Supplier<SoundEvent> SKILL_LEVELUP = SOUNDS.register(
            "skill.levelup",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill.levelup")));

    /** Daily award category reveal sting. */
    public static final Supplier<SoundEvent> AWARD_STING = SOUNDS.register(
            "award.sting",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "award.sting")));

    /** Altar personal offering accepted. */
    public static final Supplier<SoundEvent> OFFERING_ACCEPT = SOUNDS.register(
            "offering.accept",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "offering.accept")));

    /** Heart extractor use-finish cue (R8). */
    public static final Supplier<SoundEvent> RITUAL_EXTRACT = SOUNDS.register(
            "ritual.extract",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ritual.extract")));

    // P2-W1 FX suite (§3.5) — every entry maps to an EXISTING ogg in sounds.json as a
    // placeholder (P2 commits no new binary assets); consumers: W6 intro lightning, W9
    // storms, W7/W8 rifts, W5 supply beam, W2 captions.

    /** Violent close-range lightning crack (intro strikes within ~40 blocks). */
    public static final Supplier<SoundEvent> EVENT_LIGHTNING_CLOSE = SOUNDS.register(
            "event.lightning_close",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.lightning_close")));

    /** Rolling far-off lightning rumble (storm shells, distant intro strikes). */
    public static final Supplier<SoundEvent> EVENT_LIGHTNING_FAR = SOUNDS.register(
            "event.lightning_far",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.lightning_far")));

    /** Positional churn loop of a fog-storm wall/vortex (64-block falloff, W9). */
    public static final Supplier<SoundEvent> EVENT_STORM_LOOP = SOUNDS.register(
            "event.storm_loop",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_loop"),
                    64.0F));

    /** One-shot storm burst: vortex dissipate / giant-strike release (W6/W9). */
    public static final Supplier<SoundEvent> EVENT_STORM_BURST = SOUNDS.register(
            "event.storm_burst",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.storm_burst")));

    /** Rift tear-open crackle (structure drops, xbox portal — W7/W8). */
    public static final Supplier<SoundEvent> EVENT_RIFT_OPEN = SOUNDS.register(
            "event.rift_open",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_open")));

    /** Structure slam when a rift drops its payload (W7). */
    public static final Supplier<SoundEvent> EVENT_RIFT_SLAM = SOUNDS.register(
            "event.rift_slam",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.rift_slam")));

    /** Low eclipse drone bed while the world grade is crushed (W6/W7 sequences). */
    public static final Supplier<SoundEvent> EVENT_ECLIPSE_DRONE = SOUNDS.register(
            "event.eclipse_drone",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.eclipse_drone")));

    /** Supply-beam hum loop at the drop marker (W5, 48-block presence). */
    public static final Supplier<SoundEvent> EVENT_BEAM_HUM = SOUNDS.register(
            "event.beam_hum",
            () -> SoundEvent.createFixedRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.beam_hum"),
                    48.0F));

    /** Caption typewriter tick (alias of {@code ui.typewriter}; W2 CaptionRenderer). */
    public static final Supplier<SoundEvent> UI_CAPTION_TICK = SOUNDS.register(
            "ui.caption_tick",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ui.caption_tick")));

    // W4-ATMOS sound suite (IDEA-07 §1/§2/§3/§7) — all aliases of shipped oggs.

    /** Sanctum aura hum loop (client.sound.SanctumHum resolves it at runtime, self-healing). */
    public static final Supplier<SoundEvent> AMBIENT_SANCTUM_HUM = SOUNDS.register(
            "ambient.sanctum_hum",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.sanctum_hum")));

    /** Soft-border static whisper loop (client.sound.BorderStaticSound, relative bed). */
    public static final Supplier<SoundEvent> AMBIENT_BORDER_STATIC = SOUNDS.register(
            "ambient.border_static",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.border_static")));

    /** Distant low howl layered under the Herald summon roar (heard disc-wide). */
    public static final Supplier<SoundEvent> BOSS_HERALD_ROAR_FAR = SOUNDS.register(
            "boss.herald_roar_far",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_roar_far")));

    /** Muffled far-shell volley telegraph for players kiting outside the arena. */
    public static final Supplier<SoundEvent> BOSS_HERALD_TELEGRAPH_FAR = SOUNDS.register(
            "boss.herald_telegraph_far",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "boss.herald_telegraph_far")));

    /** Periodic hum of the xbox portal (xboxevent.XboxPortal resolves it at runtime). */
    public static final Supplier<SoundEvent> EVENT_XBOX_PORTAL_LOOP = SOUNDS.register(
            "event.xbox_portal_loop",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.xbox_portal_loop")));

    // --- Quiet-Eclipse UI kit (P3-W1 ledger; UiSounds resolves these by id at runtime) ---

    /** Generic widget press. */
    public static final Supplier<SoundEvent> UI_CLICK = uiEvent("ui.click");
    /** Toggle flip. */
    public static final Supplier<SoundEvent> UI_TOGGLE = uiEvent("ui.toggle");
    /** Slider drag notch. */
    public static final Supplier<SoundEvent> UI_SLIDER = uiEvent("ui.slider");
    /** Journey-gate / error glitch burst. */
    public static final Supplier<SoundEvent> UI_ERROR_GLITCH = uiEvent("ui.error_glitch");
    /** Skill level-up celebration. */
    public static final Supplier<SoundEvent> UI_LEVEL_UP = uiEvent("ui.level_up");
    /** Skill node purchase. */
    public static final Supplier<SoundEvent> UI_SKILL_BUY = uiEvent("ui.skill_buy");
    /** Award roulette tick. */
    public static final Supplier<SoundEvent> UI_ROULETTE_TICK = uiEvent("ui.roulette_tick");
    /** Award roulette winner sting. */
    public static final Supplier<SoundEvent> UI_ROULETTE_WIN = uiEvent("ui.roulette_win");
    /** Day timer reaching 00:00. */
    public static final Supplier<SoundEvent> UI_TIMER_ZERO = uiEvent("ui.timer_zero");
    /** Ship door creak of the death-flow door beat (W1-ledger id, closed by W4-ATMOS). */
    public static final Supplier<SoundEvent> UI_DOOR_OPEN = uiEvent("ui.door_open");
    /** Ghost-heart burst on revive. */
    public static final Supplier<SoundEvent> UI_GHOST_BURST = uiEvent("ui.ghost_burst");
    // W4-FEEL ui ledger (aliases; UiSounds self-heals until these land).
    /** Sidebar goal-complete stamp (pitch-salted at the call site). */
    public static final Supplier<SoundEvent> UI_GOAL_STAMP = uiEvent("ui.goal_stamp");
    /** Skill-tree purchase cascade whoosh (one per cascade). */
    public static final Supplier<SoundEvent> UI_SKILL_UNLOCK = uiEvent("ui.skill_unlock");
    /** Settings toggle knob-dock tick (ON 1.1 / OFF 0.75). */
    public static final Supplier<SoundEvent> UI_TOGGLE_SETTLE = uiEvent("ui.toggle_settle");

    private static Supplier<SoundEvent> uiEvent(String id) {
        return SOUNDS.register(id, () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, id)));
    }

    private EclipseSounds() {}

    public static void register(IEventBus modEventBus) {
        SOUNDS.register(modEventBus);
    }
}
