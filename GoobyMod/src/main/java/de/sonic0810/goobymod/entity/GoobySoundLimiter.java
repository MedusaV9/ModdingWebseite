package de.sonic0810.goobymod.entity;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.ChunkPos;

/** Bounded per-chunk limiter for periodic Gooby ambience. */
public final class GoobySoundLimiter {
    public static final int MAX_BUCKETS = 2048;
    private static final Map<Bucket, Long> LAST_PLAYED = new LinkedHashMap<>(64, 0.75F, true);

    public static synchronized boolean tryAcquire(Level level, BlockPos pos, SoundEvent sound, int cooldownTicks) {
        ResourceLocation dimension = level.dimension().location();
        ResourceLocation soundId = BuiltInRegistries.SOUND_EVENT.getKey(sound);
        return tryAcquire(dimension, ChunkPos.asLong(pos), soundId, level.getGameTime(), cooldownTicks);
    }

    public static synchronized boolean tryAcquire(ResourceLocation dimension, long chunk,
            ResourceLocation sound, long gameTime, int cooldownTicks) {
        Bucket bucket = new Bucket(dimension, chunk, sound);
        Long lastPlayed = LAST_PLAYED.get(bucket);
        if (lastPlayed != null && gameTime >= lastPlayed
                && gameTime - lastPlayed < Math.max(1, cooldownTicks)) {
            return false;
        }
        if (LAST_PLAYED.size() >= MAX_BUCKETS && !LAST_PLAYED.containsKey(bucket)) {
            Iterator<Bucket> oldest = LAST_PLAYED.keySet().iterator();
            if (oldest.hasNext()) {
                LAST_PLAYED.remove(oldest.next());
            }
        }
        LAST_PLAYED.put(bucket, gameTime);
        return true;
    }

    public static synchronized int trackedBucketCount() {
        return LAST_PLAYED.size();
    }

    public static synchronized void clear() {
        LAST_PLAYED.clear();
    }

    private record Bucket(ResourceLocation dimension, long chunk, ResourceLocation sound) {
    }

    private GoobySoundLimiter() {
    }
}
