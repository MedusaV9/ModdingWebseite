package dev.projecteclipse.eclipse.client.xbox;

import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.music.MusicManager;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.sound.PlaySoundEvent;

/**
 * OLD MUSIC + OLD SOUNDS inside the Xbox tutorial dimensions (C17 fix 5) — everything here
 * points at VANILLA asset files, so no non-redistributable audio is bundled.
 *
 * <p><b>Old music (TUT2 rewrite — "music overlaps in the tutorial worlds")</b>: this class is
 * now a pure SCHEDULER. It owns no sound instance at all; it only answers {@link #xboxCue()}
 * with the cue the xbox situation rung should be playing right now — either
 * {@link MusicCues#XBOX_ERA_TRACK} (a C418 "Volume Alpha" pick from the vanilla
 * {@code eclipse:music.xbox_era} pool) or the {@code xbox_nostalgia} bed that fills the
 * era-style gaps between tracks — or {@code null} for the {@value #HANDOVER_TICKS}-tick
 * silence that separates them. {@code music.MusicManager} plays that answer on its ONE
 * managed voice, and because the rung goes through silence rather than straight from one
 * cue to the other, the bed is at zero before the track's fade-in starts: there is never a
 * second audible voice on this rung, not even for the length of a crossfade.
 *
 * <p>What it used to do: {@code minecraft.getSoundManager().play(...)} on a PARALLEL channel
 * at full volume, while {@code MusicManager#naturalCue} returned {@code null} so the bed
 * started a 40-tick fade-out on the managed channel — two music voices for two seconds on
 * every hand-over, and a hard {@code soundManager.stop()} (its own stop logic, bypassing the
 * MUSICFADE envelope) on the way out. Both are gone: the schedule is state only, and the
 * fades belong to {@code MusicFadeSound}.</p>
 *
 * <p>The scheduler ticks on {@link ClientTickEvent.Pre} on purpose — {@code MusicManager}
 * selects on {@link ClientTickEvent.Post}, so the state it reads is always this tick's, and
 * a track that just ended can never be restarted for one tick before the gap begins.</p>
 *
 * <p><b>Old sounds</b>: a dimension-scoped {@link PlaySoundEvent} replacement map. Only
 * remaps where a LEGACY-style vanilla sound still exists in modern assets:
 * <ul>
 *   <li>{@code block.netherrack.*} / {@code block.nether_bricks.*} → {@code block.stone.*}
 *       — both got bespoke sounds in 1.16; in the console era they used stone sounds
 *       (the classic blocks copy their modern base, so they emit the modern events);</li>
 *   <li>{@code ambient.cave} → {@code eclipse:ambient.xbox_cave} — the era subset
 *       (cave1–13; cave14+ are post-era additions).</li>
 * </ul>
 * Famous era audio that was REMOVED from vanilla assets (the old "oof", pre-1.10 grass
 * steps) cannot be restored without bundling copyrighted files — deliberately skipped.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class XboxEraSounds {

    /** First era track this long after entering (the nostalgia intro bed owns the start). */
    private static final int INTRO_GAP_TICKS = 20 * 45;
    /** Era-style silence-ish gap between tracks (the nostalgia bed fills it). */
    private static final int MIN_GAP_TICKS = 20 * 90;
    private static final int MAX_GAP_TICKS = 20 * 180;
    /** Ticks MusicManager may take to accept the cue before "it never started" counts. */
    private static final int START_GRACE_TICKS = 20;
    /**
     * SEQUENTIAL hand-over window. Before an era track may start, the rung asks for silence
     * for one full {@code MusicManager} fade (40 t) so the bed is already at zero when the
     * track's own fade-in begins: the requirement is "the old cue is faded out BEFORE the new
     * one starts", which a crossfade — two audible voices of the same rung for two seconds —
     * would not meet. The reverse edge needs no window: a non-looping era track has already
     * ended when the bed comes back.
     */
    private static final int HANDOVER_TICKS = 40;

    /** Modern event id → legacy-style replacement event id (vanilla files only). */
    private static final Map<ResourceLocation, ResourceLocation> LEGACY_SOUND_REMAP = Map.ofEntries(
            legacyBlock("netherrack", "break"), legacyBlock("netherrack", "step"),
            legacyBlock("netherrack", "place"), legacyBlock("netherrack", "hit"),
            legacyBlock("netherrack", "fall"),
            legacyBlock("nether_bricks", "break"), legacyBlock("nether_bricks", "step"),
            legacyBlock("nether_bricks", "place"), legacyBlock("nether_bricks", "hit"),
            legacyBlock("nether_bricks", "fall"),
            Map.entry(ResourceLocation.withDefaultNamespace("ambient.cave"),
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.xbox_cave")));

    /** True while an era track is the scheduled cue; false while the bed fills a gap. */
    private static boolean eraTrackScheduled;
    /** Ticks since {@link #eraTrackScheduled} was armed (start-grace / end detection). */
    private static int eraTrackAge;
    /** Latched once MusicManager confirmed the era cue really took the channel. */
    private static boolean eraTrackConfirmed;
    /** Counts down the {@link #HANDOVER_TICKS} silence before an era track may start. */
    private static int handoverTicks;
    private static int gapTicks;
    private static boolean wasInside;

    private XboxEraSounds() {}

    /**
     * The xbox situation rung's cue right now, read by {@code MusicManager#naturalCue}:
     * the era track, the nostalgia bed, or {@code null} during the hand-over silence. The
     * rung never names two cues at once, which is what guarantees a single voice.
     *
     * <p>The END of an era track is detected HERE and not in the tick handler on purpose:
     * {@code MusicManager} clears its finished voice and then asks for the natural cue inside
     * the SAME {@code ClientTickEvent.Post}, so a check that ran a tick earlier would still
     * report the track as scheduled and the manager would immediately start a second one —
     * the era pool would loop back-to-back with no gaps. Called at most twice per tick and
     * idempotent: once disarmed the branch is skipped.</p>
     */
    @Nullable
    public static MusicCues xboxCue() {
        if (handoverTicks > 0) {
            return null;
        }
        if (eraTrackScheduled) {
            boolean live = MusicCues.XBOX_ERA_TRACK.id().equals(MusicManager.currentCueId());
            eraTrackConfirmed |= live;
            // Track finished, or MusicManager never accepted the cue within the grace.
            if (!live && (eraTrackConfirmed || eraTrackAge > START_GRACE_TICKS)) {
                eraTrackScheduled = false;
                eraTrackConfirmed = false;
                gapTicks = nextGap();
            }
        }
        return eraTrackScheduled ? MusicCues.XBOX_ERA_TRACK : MusicCues.XBOX_NOSTALGIA;
    }

    /**
     * Drops the schedule so the next entry starts from the intro bed again. Called on the
     * client dimension-change wipe ({@code SoundEngine.stopAll}) — the era track the engine
     * just deleted must not be waited on for its (never-arriving) natural end.
     */
    public static void reset() {
        eraTrackScheduled = false;
        eraTrackConfirmed = false;
        eraTrackAge = 0;
        handoverTicks = 0;
        gapTicks = INTRO_GAP_TICKS;
        wasInside = false;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Pre event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!(XboxEraFx.inXboxDimension() && minecraft.player != null)) {
            if (wasInside) {
                // No stop call: MusicManager's ladder drops the xbox rung on the same tick
                // and fades the voice out through the MUSICFADE envelope.
                reset();
            }
            return;
        }
        if (!wasInside) {
            wasInside = true;
            eraTrackScheduled = false;
            eraTrackConfirmed = false;
            handoverTicks = 0;
            gapTicks = INTRO_GAP_TICKS;
        }

        // Timekeeping only — the disarm decision lives in xboxCue() (see its doc).
        if (handoverTicks > 0) {
            handoverTicks--;
        } else if (eraTrackScheduled) {
            eraTrackAge++;
        } else if (--gapTicks <= 0) {
            // Arm the track, but hold the rung silent first so the bed's fade-out finishes
            // before the track's fade-in starts (never two voices on this rung).
            eraTrackScheduled = true;
            eraTrackConfirmed = false;
            eraTrackAge = 0;
            handoverTicks = HANDOVER_TICKS;
        }
    }

    /**
     * Respawn / dimension change: {@code Minecraft.setLevel} ran {@code SoundEngine.stopAll}
     * and deleted whatever was streaming, so the schedule restarts from the intro bed. Without
     * this the scheduler would keep waiting for the natural end of a track that no longer
     * exists — the next tutorial world would open on a stale gap instead of its own intro.
     */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        reset();
    }

    /**
     * The dimension-scoped legacy remap. Fires on the client sound engine's play path;
     * the rebuilt instance keeps position/volume/pitch/source so subtitles, attenuation
     * and the user's volume categories behave exactly as before.
     */
    @SubscribeEvent
    static void onPlaySound(PlaySoundEvent event) {
        if (!XboxEraFx.inXboxDimension()) {
            return;
        }
        SoundInstance original = event.getOriginalSound();
        ResourceLocation replacement = LEGACY_SOUND_REMAP.get(original.getLocation());
        if (replacement == null) {
            return;
        }
        // The event fires before the engine resolves the instance; resolve first so the
        // volume/pitch getters are safe to call (the engine re-resolves the replacement).
        if (original.resolve(Minecraft.getInstance().getSoundManager()) == null) {
            return;
        }
        event.setSound(new SimpleSoundInstance(replacement, original.getSource(),
                original.getVolume(), original.getPitch(), RandomSource.create(),
                original.isLooping(), original.getDelay(), original.getAttenuation(),
                original.getX(), original.getY(), original.getZ(), original.isRelative()));
    }

    private static int nextGap() {
        var level = Minecraft.getInstance().level;
        RandomSource random = level != null ? level.random : RandomSource.create();
        return MIN_GAP_TICKS + random.nextInt(MAX_GAP_TICKS - MIN_GAP_TICKS + 1);
    }

    private static Map.Entry<ResourceLocation, ResourceLocation> legacyBlock(String block, String action) {
        return Map.entry(ResourceLocation.withDefaultNamespace("block." + block + "." + action),
                ResourceLocation.withDefaultNamespace("block.stone." + action));
    }
}
