package de.sonic0810.goobymod.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Gooby-Wolle: SO weich, dass sie Fallschaden KOMPLETT daempft.
 * Landen wie auf einem Wolkenbauch.
 */
public class GoobyWoolBlock extends Block {
    public GoobyWoolBlock(Properties properties) {
        super(properties);
    }

    @Override
    public void fallOn(Level level, BlockState state, BlockPos pos, Entity entity, float fallDistance) {
        // Kein super-Aufruf: null Fallschaden — nur ein flauschiges Plumps
        if (fallDistance > 1.5F && level instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.CLOUD,
                    entity.getX(), pos.getY() + 1.05, entity.getZ(), 5, 0.25, 0.05, 0.25, 0.02);
            level.playSound(null, pos, SoundEvents.WOOL_FALL, SoundSource.BLOCKS, 0.7F, 0.9F);
        }
    }
}
