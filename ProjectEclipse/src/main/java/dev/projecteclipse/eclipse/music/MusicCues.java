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
    LIMBO_AMBIENCE("limbo_ambience", EclipseMusicSounds.LIMBO_AMBIENCE, true, 0, 200),
    TITLE_THEME("title_theme", EclipseMusicSounds.TITLE_THEME, true, 0),
    EXPANSION_THEME("expansion_theme", EclipseMusicSounds.EXPANSION_THEME, true, 0),
    INTRO_STORM("intro_storm", EclipseMusicSounds.INTRO_STORM, false, 3_000),
    VICTORY_THEME("victory_theme", EclipseMusicSounds.VICTORY_THEME, false, 3_600),
    XBOX_NOSTALGIA("xbox_nostalgia", EclipseMusicSounds.XBOX_NOSTALGIA, true, 0, 100),

    // --- Wave-4 tracks (W4-BOSSJUICE). Boss cues need no linger: MusicManager's
    // BOSS_SEEN_GRACE_MILLIS already bridges bossbar render gaps. ---
    /** Situation rung: eclipse TOTAL phase drone (MusicManager, below boss priority). */
    ECLIPSE_TOTALITY("eclipse_totality", EclipseMusicSounds.ECLIPSE_TOTALITY, true, 0, 100),
    /** Situation rung: inside a fog storm; hysteresis 0.55/0.15 on interiorAmount(). */
    FOG_STORM("fog_storm", EclipseMusicSounds.FOG_STORM, true, 0, 200),
    /** Bossbar-observed rung (entity.eclipse.rift_warden.bossbar). */
    BOSS_RIFT_WARDEN("boss_rift_warden", EclipseMusicSounds.BOSS_RIFT_WARDEN, true, 0),
    /** Bossbar-observed rung (entity.eclipse.fog_tyrant.bossbar). */
    BOSS_FOG_TYRANT("boss_fog_tyrant", EclipseMusicSounds.BOSS_FOG_TYRANT, true, 0),
    /**
     * Looping hunt bed. NOT auto-selected: other workers force it via
     * {@code MusicCues.play("kill_contract", player)} (Pale Night owner / Lantern Gaze
     * override) and release it client-side with {@code MusicCues.release("kill_contract")}
     * — release, unlike stop, never mutes the situation ladder underneath.
     */
    KILL_CONTRACT("kill_contract", EclipseMusicSounds.KILL_CONTRACT, true, 0, 100),
    /**
     * Non-looping ceremonial sting (~45-60 s + tail). Triggered by the wand worker via
     * {@code MusicCues.play("wand_awakening", player)}; hands the channel back to the
     * situation ladder after {@code durationTicks} like INTRO_STORM. WANDFIX-6: the
     * ceremony should color the moment, not own the next minute — ownership shortened
     * to 700t (~35 s; the crossfade tips it out mid-tail) and the sting rides a 0.55
     * gain so it swells in under the scene instead of stomping onto it.
     */
    WAND_AWAKENING("wand_awakening", EclipseMusicSounds.WAND_AWAKENING, false, 700, 0, 0.55F),
    /** Situation rung: final-day dread bed (weakest in-world rung, MusicManager). */
    DAY_FINAL("day_final", EclipseMusicSounds.DAY_FINAL, true, 0, 200);

    private static final List<String> IDS =
            Arrays.stream(values()).map(MusicCues::id).toList();

    private final String id;
    private final Supplier<SoundEvent> sound;
    private final boolean looping;
    private final int durationTicks;
    private final int lingerTicks;
    private final float gain;

    MusicCues(String id, Supplier<SoundEvent> sound, boolean looping, int durationTicks) {
        this(id, sound, looping, durationTicks, 0);
    }

    MusicCues(String id, Supplier<SoundEvent> sound, boolean looping, int durationTicks,
            int lingerTicks) {
        this(id, sound, looping, durationTicks, lingerTicks, 1.0F);
    }

    MusicCues(String id, Supplier<SoundEvent> sound, boolean looping, int durationTicks,
            int lingerTicks, float gain) {
        this.id = id;
        this.sound = sound;
        this.looping = looping;
        this.durationTicks = durationTicks;
        this.lingerTicks = lingerTicks;
        this.gain = gain;
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

    /**
     * Music memory (IDEA-08 #4): how long the situation ladder keeps returning this cue after
     * its rung goes quiet, so brief exits (storm-wall dodges, short totality dips) never
     * restart the loop. Zero = drop immediately. Rung upgrades bypass the linger.
     */
    public int lingerTicks() {
        return lingerTicks;
    }

    /**
     * Per-cue loudness trim applied under {@code MusicConfig.volumeMultiplier()} inside the
     * MusicManager crossfade (WANDFIX-6). 1.0 for almost everything; quiet ceremonial
     * stings (wand_awakening) sit lower so they support a scene instead of leading it.
     */
    public float gain() {
        return gain;
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
        // MusicClientHooks is resolved lazily on first execution (client only); do not
        // use a MusicManager method reference here — it breaks dedicated-server verification.
        cue.ifPresent(value -> MusicClientHooks.play(value));
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

    /** Client payload-handler entry point: fade the custom channel out (default 40 t). */
    public static void stop() {
        MusicClientHooks.stop();
    }

    /**
     * MUSICFADE client entry point: fade the custom channel to silence over {@code ticks}
     * instead of the default 40-tick crossfade. Same muting semantics as {@link #stop()}.
     *
     * <p>A fade cannot outlive a dimension change ({@code SoundEngine.stopAll} runs on
     * every {@code Minecraft.setLevel}), so a sequence that hops dimensions must start its
     * fade early enough to reach zero BEFORE the hop.</p>
     */
    public static void fadeOut(int ticks) {
        MusicClientHooks.fadeOut(ticks);
    }

    /** Server-side bridge for {@link #fadeOut(int)} (sequences own a specific player). */
    public static void fadeOut(ServerPlayer player, int ticks) {
        MusicPayloads.sendFadeOut(player, ticks);
    }

    /**
     * Client entry point: release a forced cue (started via {@link #play}) WITHOUT muting
     * the situation underneath — unlike {@link #stop()}, the ladder resumes immediately,
     * so e.g. dropping {@code kill_contract} mid-fight un-ducks the boss theme at once.
     * Returns false for an unknown id.
     */
    public static boolean release(String id) {
        Optional<MusicCues> cue = fromId(id);
        cue.ifPresent(value -> MusicClientHooks.release(value));
        return cue.isPresent();
    }

    /**
     * Server-side bridge mirroring {@link #release(String)} for event hooks that own a
     * specific player (e.g. the contract window ending mid-boss-fight must un-duck the
     * boss theme rather than mute the whole ladder like {@link #stop(ServerPlayer)}).
     */
    public static boolean release(String id, ServerPlayer player) {
        Optional<MusicCues> cue = fromId(id);
        cue.ifPresent(value -> MusicPayloads.sendRelease(player, value.id()));
        return cue.isPresent();
    }

    /** Server-side bridge for dimension/event exit hooks. */
    public static void stop(ServerPlayer player) {
        MusicPayloads.sendStop(player);
    }
}
