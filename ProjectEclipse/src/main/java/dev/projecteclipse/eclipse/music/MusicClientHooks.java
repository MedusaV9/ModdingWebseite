package dev.projecteclipse.eclipse.music;

import net.minecraft.client.Minecraft;

/**
 * Client-only trampoline for the music payload handlers. This class is resolved lazily —
 * it is only loaded when a handler actually executes, which happens exclusively on the
 * client. Keeping every {@code net.minecraft.client} reference here lets the common
 * classes ({@link MusicPayloads}, {@link MusicCues}) pass server-side verification.
 */
final class MusicClientHooks {
    private MusicClientHooks() {}

    static void play(MusicCues cue) {
        MusicManager.play(cue);
    }

    static void stop() {
        MusicManager.stop();
    }

    static void openCredits() {
        Minecraft minecraft = Minecraft.getInstance();
        minecraft.setScreen(new dev.projecteclipse.eclipse.client.menu.CreditsScreen(minecraft.screen));
    }
}
