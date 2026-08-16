package de.sonic0810.goobymod.block;

import com.mojang.serialization.MapCodec;
import de.sonic0810.goobymod.block.entity.NutellaJarBlockEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModEntities;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BooleanProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Das platzierte Nutella-Glas. Steht es nachts auf einem Grasblock, hoppelt
 * ein wilder GOOBY heran und schleckt es leer — der zweite Spawn-Weg fuer
 * hasenlose Gegenden!
 *
 * <p>Beim Losschicken eines Goobys wird das Glas ATOMAR reserviert
 * ({@link #CLAIMED} wird im selben Server-Tick VOR dem Spawn gesetzt): weitere
 * randomTicks koennen nie einen zweiten Gooby fuer dasselbe Glas erzeugen.
 * Die persistente UUID-Lease lebt im BlockEntity. Sie uebersteht Chunk-Unloads
 * und heilt sich erst nach Ablauf und serverweiter UUID-Pruefung selbst.
 */
public class NutellaJarBlock extends BaseEntityBlock {
    public static final MapCodec<NutellaJarBlock> CODEC = simpleCodec(NutellaJarBlock::new);

    /** true = ein Gooby ist bereits zu diesem Glas unterwegs (Reservierung). */
    public static final BooleanProperty CLAIMED = BooleanProperty.create("claimed");

    private static final VoxelShape SHAPE = Block.box(5.0, 0.0, 5.0, 11.0, 7.0, 11.0);

    public NutellaJarBlock(Properties properties) {
        super(properties);
        registerDefaultState(this.stateDefinition.any().setValue(CLAIMED, false));
    }

    @Override
    protected MapCodec<? extends BaseEntityBlock> codec() {
        return CODEC;
    }

    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new NutellaJarBlockEntity(pos, state);
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(CLAIMED);
    }

    @Override
    protected VoxelShape getShape(BlockState state, net.minecraft.world.level.BlockGetter level, BlockPos pos,
            CollisionContext context) {
        return SHAPE;
    }

    @Override
    protected boolean canSurvive(BlockState state, LevelReader level, BlockPos pos) {
        return Block.canSupportCenter(level, pos.below(), Direction.UP);
    }

    @Override
    protected void randomTick(BlockState state, ServerLevel level, BlockPos pos, RandomSource random) {
        if (state.getValue(CLAIMED)) {
            // Kein Radius-Scan: erst nach 15 Minuten UND fehlender UUID im ganzen Server freigeben.
            if (!(level.getBlockEntity(pos) instanceof NutellaJarBlockEntity lease)) {
                return;
            }
            lease.ensureLegacyLease(level.getGameTime());
            if (lease.mayRelease(level, level.getGameTime())) {
                lease.clearLease();
                level.setBlock(pos, state.setValue(CLAIMED, false), 3);
            }
            return;
        }
        if (!level.isNight() || !level.getBlockState(pos.below()).is(Blocks.GRASS_BLOCK)) {
            return;
        }
        if (random.nextInt(2) != 0) {
            return;
        }
        BlockPos spawnPos = findSpawnPos(level, pos, random);
        if (spawnPos == null) {
            return;
        }
        GoobyEntity gooby = ModEntities.GOOBY.get().create(level);
        if (gooby == null) {
            return;
        }
        // ATOMAR reservieren, BEVOR der Gooby in die Welt kommt (gleicher Server-Tick,
        // gleicher Thread): jeder weitere randomTick sieht claimed=true und spawnt nichts.
        level.setBlock(pos, state.setValue(CLAIMED, true), 3);
        if (!(level.getBlockEntity(pos) instanceof NutellaJarBlockEntity lease)) {
            level.setBlock(pos, state, 3);
            return;
        }
        lease.claim(gooby.getUUID(), level.getGameTime());
        gooby.moveTo(spawnPos.getX() + 0.5, spawnPos.getY(), spawnPos.getZ() + 0.5,
                random.nextFloat() * 360.0F, 0.0F);
        gooby.finalizeSpawn(level, level.getCurrentDifficultyAt(spawnPos), MobSpawnType.EVENT, null);
        gooby.setJarTarget(pos);
        if (!level.addFreshEntity(gooby)) {
            lease.clearLease();
            level.setBlock(pos, state, 3);
            return;
        }
        GoobyEntity.magicMoment(level, gooby.position().add(0.0, 0.7, 0.0));
        // Kleiner Funkel-Hinweis am Glas: da kommt was Grosses, Rundes, Niedliches!
        level.sendParticles(ParticleTypes.END_ROD, pos.getX() + 0.5, pos.getY() + 0.6, pos.getZ() + 0.5,
                8, 0.25, 0.3, 0.25, 0.02);
    }

    @Nullable
    private static BlockPos findSpawnPos(ServerLevel level, BlockPos jarPos, RandomSource random) {
        for (int attempt = 0; attempt < 12; attempt++) {
            int dx = (5 + random.nextInt(4)) * (random.nextBoolean() ? 1 : -1);
            int dz = (5 + random.nextInt(4)) * (random.nextBoolean() ? 1 : -1);
            BlockPos column = jarPos.offset(dx, 3, dz);
            for (int dy = 0; dy >= -7; dy--) {
                BlockPos candidate = column.above(dy);
                if (level.getBlockState(candidate).isAir()
                        && level.getBlockState(candidate.above()).isAir()
                        && level.getBlockState(candidate.below()).isSolidRender(level, candidate.below())) {
                    return candidate;
                }
            }
        }
        return null;
    }
}
