package dev.projecteclipse.eclipse.music;

import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.function.Supplier;

import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;

/** Catalog of custom score cues and their playback policy. */
public enum MusicCues {
    BOSS_FERRYMAN("boss_ferryman", EclipseMusicSounds.BOSS_FERRYMAN, true, 0),
    BOSS_HERALD("boss_herald", EclipseMusicSounds.BOSS_HERALD, true, 0),
    LIMBO_AMBIENCE("limbo_ambience", EclipseMusicSounds.LIMBO_AMBIENCE, true, 0),
    TITLE_THEME("title_theme", EclipseMusicSounds.TITLE_THEME, true, 0),
    EXPANSION_THEME("expansion_theme", EclipseMusicSounds.EXPANSION_THEME, true, 0),
    INTRO_STORM("intro_storm", EclipseMusicSounds.INTRO_STORM, false, 3_000),
    VICTORY_THEME("victory_theme", EclipseMusicSounds.VICTORY_THEME, false, 3_600),
    XBOX_NOSTALGIA("xbox_nostalgia", EclipseMusicSounds.XBOX_NOSTALGIA, true, 0);

    private static final List<String> IDS =
            Arrays.stream(values()).map(MusicCues::id).toList();

    private final String id;
    private final Supplier<SoundEvent> sound;
    private final boolean looping;
    private final int durationTicks;

    MusicCues(String id, Supplier<SoundEvent> sound, boolean looping, int durationTicks) {
        this.id = id;
        this.sound = sound;
        this.looping = looping;
        this.durationTicks = durationTicks;
    }

    public String id() {
        return id;
    }

    public SoundEvent sound() {
        return sound.get();
    }

    public boolean looping() {
        return looping;
    }

    /** Duration for non-looping cue ownership; zero means situation-controlled. */
    public int durationTicks() {
        return durationTicks;
    }

    public static List<String> ids() {
        return IDS;
    }

    public static Optional<MusicCues> fromId(String id) {
        if (id == null) {
            return Optional.empty();
        }
        String normalized = id.strip().toLowerCase(Locale.ROOT);
        return Arrays.stream(values()).filter(cue -> cue.id.equals(normalized)).findFirst();
    }

    /** Client payload-handler entry point. Returns false for an unknown id. */
    public static boolean play(String id) {
        Optional<MusicCues> cue = fromId(id);
        cue.ifPresent(MusicManager::play);
        return cue.isPresent();
    }

    /**
     * Server-side bridge for event hooks that own a specific player. Validation happens before
     * sending, while actual playback remains client-only.
     */
    public static boolean play(String id, ServerPlayer player) {
        Optional<MusicCues> cue = fromId(id);
        cue.ifPresent(value -> MusicPayloads.sendPlay(player, value.id()));
        return cue.isPresent();
    }

    /** Client payload-handler entry point: fade the custom channel out. */
    public static void stop() {
        MusicManager.stop();
    }

    /** Server-side bridge for dimension/event exit hooks. */
    public static void stop(ServerPlayer player) {
        MusicPayloads.sendStop(player);
    }
}
