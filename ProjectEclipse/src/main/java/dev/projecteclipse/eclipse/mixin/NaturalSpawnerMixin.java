package dev.projecteclipse.eclipse.mixin;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import dev.projecteclipse.eclipse.entity.spawn.SpawnYBands;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.NaturalSpawner;
import net.minecraft.world.level.chunk.LevelChunk;

/**
 * PLAN-B B5 (plans_v5): biases the runtime natural-spawn cycle's random Y roll into the
 * populated disc band. Vanilla's {@code getRandomPosWithin} picks a Y anywhere in
 * {@code [minBuildHeight, WORLD_SURFACE_top]}; on the floating discs most of that range
 * is under-disc void (overworld) or sealed roof mass (nether), so nearly every attempt
 * dies and vanilla biome mobs barely spawn. The band math, off-disc pass-through and the
 * census instrumentation live in {@link SpawnYBands}; this mixin is only the seam.
 */
@Mixin(NaturalSpawner.class)
public abstract class NaturalSpawnerMixin {
    @Inject(method = "getRandomPosWithin", at = @At("RETURN"), cancellable = true)
    private static void eclipse$bandSpawnY(Level level, LevelChunk chunk,
            CallbackInfoReturnable<BlockPos> callbackInfo) {
        BlockPos rolled = callbackInfo.getReturnValue();
        BlockPos banded = SpawnYBands.adjust(level, rolled);
        if (banded != rolled) {
            callbackInfo.setReturnValue(banded);
        }
    }
}
