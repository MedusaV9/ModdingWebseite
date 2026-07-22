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

    /** Looping ambient bed of the Limbo dimension (also wired as the limbo biome's {@code ambient_sound}). */
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
     * the default cutscene JSONs). Mapped in {@code sounds.json} to the submerge recording at
     * a higher pitch until dedicated audio is dropped in.
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

    private EclipseSounds() {}

    public static void register(IEventBus modEventBus) {
        SOUNDS.register(modEventBus);
    }
}
