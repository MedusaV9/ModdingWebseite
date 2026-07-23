package dev.projecteclipse.eclipse.music;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Dedicated sound-event registrar for the streamed Eclipse score. */
public final class EclipseMusicSounds {
    public static final DeferredRegister<SoundEvent> SOUNDS =
            DeferredRegister.create(Registries.SOUND_EVENT, EclipseMod.MOD_ID);

    public static final Supplier<SoundEvent> BOSS_FERRYMAN = music("boss_ferryman");
    public static final Supplier<SoundEvent> BOSS_HERALD = music("boss_herald");
    public static final Supplier<SoundEvent> LIMBO_AMBIENCE = music("limbo_ambience");
    public static final Supplier<SoundEvent> TITLE_THEME = music("title_theme");
    public static final Supplier<SoundEvent> EXPANSION_THEME = music("expansion_theme");
    public static final Supplier<SoundEvent> INTRO_STORM = music("intro_storm");
    public static final Supplier<SoundEvent> VICTORY_THEME = music("victory_theme");
    public static final Supplier<SoundEvent> XBOX_NOSTALGIA = music("xbox_nostalgia");

    private EclipseMusicSounds() {}

    private static Supplier<SoundEvent> music(String id) {
        String eventId = "music." + id;
        return SOUNDS.register(eventId, () -> SoundEvent.createVariableRangeEvent(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, eventId)));
    }

    public static void register(IEventBus modEventBus) {
        SOUNDS.register(modEventBus);
    }
}
