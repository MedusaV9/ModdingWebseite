package dev.projecteclipse.eclipse.xboxevent;

/**
 * TOMBSTONE (tutorial-world music overlap fix). This used to be a reflective bridge that
 * FORCE-played the {@code xbox_nostalgia} cue on every Xbox-dimension entry
 * ({@code MusicCues.play("xbox_nostalgia", player)} → client {@code MusicManager.play}
 * → {@code forcedCue} with infinite ownership). A forced cue bypasses the situation
 * ladder's C17 yield seam ({@code MusicManager.naturalCue} returns {@code null} while
 * {@code XboxEraSounds.eraTrackPlaying()}), so whenever the client-side era scheduler
 * started a C418 track, the forced nostalgia bed kept looping UNDER it — the reported
 * "music overlaps in the tutorial worlds".
 *
 * <p>The bridge predates {@code MusicManager}'s own {@code XBOX_NOSTALGIA} situation
 * rung, which selects the bed purely from the player's dimension and correctly yields
 * to (and resumes between) era tracks. With the rung in place the hook was pure double
 * coverage with a broken priority, so its event subscriptions were removed — the class
 * stays as documentation so nobody reintroduces a server-side force-play.</p>
 */
public final class XboxMusicHook {
    private XboxMusicHook() {}
}
