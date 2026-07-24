package dev.projecteclipse.eclipse.client.xbox;

import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.sound.PlaySoundEvent;

/**
 * OLD MUSIC + OLD SOUNDS inside the Xbox tutorial dimensions (C17 fix 5) — everything here
 * points at VANILLA asset files, so no non-redistributable audio is bundled.
 *
 * <p><b>Old music</b>: a client-side scheduler streams tracks from the
 * {@code eclipse:music.xbox_era} pool (the C418 "Volume Alpha" in-game tracks that still ship
 * in vanilla: calm/hal/nuance/piano) with era-style gaps. The custom {@code xbox_nostalgia}
 * bed (C19) stays the INTRO and the between-tracks filler: {@code music.MusicManager}'s xbox
 * rung yields the channel while {@link #eraTrackPlaying()} — see the one-branch seam in
 * {@code MusicManager#naturalCue}. While an era track streams, this class also mutes
 * vanilla's own scheduler (same rule MusicManager applies for its cues) so modern
 * post-C418 biome music can never start over it.</p>
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
    /** Grace before "engine never accepted the instance" counts as the track ending. */
    private static final int START_GRACE_TICKS = 10;

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

    @Nullable
    private static SoundInstance eraTrack;
    private static int eraTrackAge;
    private static int gapTicks;
    private static boolean wasInside;

    private XboxEraSounds() {}

    /** Whether an actual C418-era track owns the music channel (MusicManager yields). */
    public static boolean eraTrackPlaying() {
        return eraTrack != null;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        boolean inside = XboxEraFx.inXboxDimension() && minecraft.player != null;
        if (!inside) {
            if (wasInside) {
                stopEraTrack(minecraft);
                wasInside = false;
            }
            return;
        }
        if (!wasInside) {
            wasInside = true;
            gapTicks = INTRO_GAP_TICKS;
        }

        if (eraTrack != null) {
            eraTrackAge++;
            if (eraTrackAge > START_GRACE_TICKS && !minecraft.getSoundManager().isActive(eraTrack)) {
                eraTrack = null; // track finished (or the engine refused it) — start a gap
                gapTicks = nextGap(minecraft);
            } else {
                // Same double-play guard MusicManager applies for its cues: vanilla's
                // scheduler must never start modern biome music over an era track.
                minecraft.getMusicManager().stopPlaying();
            }
            return;
        }
        if (--gapTicks <= 0) {
            eraTrack = SimpleSoundInstance.forMusic(EclipseSounds.MUSIC_XBOX_ERA.get());
            eraTrackAge = 0;
            minecraft.getSoundManager().play(eraTrack);
        }
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

    private static void stopEraTrack(Minecraft minecraft) {
        if (eraTrack != null) {
            minecraft.getSoundManager().stop(eraTrack);
            eraTrack = null;
        }
        gapTicks = 0;
    }

    private static int nextGap(Minecraft minecraft) {
        RandomSource random = minecraft.level != null ? minecraft.level.random : RandomSource.create();
        return MIN_GAP_TICKS + random.nextInt(MAX_GAP_TICKS - MIN_GAP_TICKS + 1);
    }

    private static Map.Entry<ResourceLocation, ResourceLocation> legacyBlock(String block, String action) {
        return Map.entry(ResourceLocation.withDefaultNamespace("block." + block + "." + action),
                ResourceLocation.withDefaultNamespace("block.stone." + action));
    }
}
