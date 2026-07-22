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

    private EclipseSounds() {}

    public static void register(IEventBus modEventBus) {
        SOUNDS.register(modEventBus);
    }
}
