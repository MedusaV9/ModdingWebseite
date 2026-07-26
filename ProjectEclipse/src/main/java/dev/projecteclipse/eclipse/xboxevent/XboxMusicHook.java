package dev.projecteclipse.eclipse.xboxevent;

/**
 * TOMBSTONE (tutorial-world music overlap fix). This used to be a reflective bridge that
 * FORCE-played the {@code xbox_nostalgia} cue on every Xbox-dimension entry
 * ({@code MusicCues.play("xbox_nostalgia", player)} → client {@code MusicManager.play}
 * → {@code forcedCue} with infinite ownership). A forced cue outranks the situation
 * ladder, so whenever the client-side era scheduler started a C418 track the forced
 * nostalgia bed kept looping UNDER it — one half of the reported "music overlaps in the
 * tutorial worlds".
 *
 * <p>The bridge predates {@code MusicManager}'s own xbox situation rung, which now picks
 * between {@code XBOX_NOSTALGIA} and {@code XBOX_ERA_TRACK} purely from the player's
 * dimension ({@code client.xbox.XboxEraSounds#xboxCue}) and plays whichever it picks on
 * the manager's single crossfaded voice. With the rung in place the hook was pure double
 * coverage with a broken priority, so its event subscriptions were removed — the class
 * stays as documentation so nobody reintroduces a server-side force-play.</p>
 */
public final class XboxMusicHook {
    private XboxMusicHook() {}
}
