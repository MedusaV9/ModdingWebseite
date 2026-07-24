package dev.projecteclipse.eclipse.ferryman;

import javax.annotation.Nullable;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;

/**
 * Dimension key of the Ferryman fight arena ({@code eclipse:ferryman_arena}, PLAN-C
 * C10) — the {@code minigames/MinigameDimensions} void-dim pattern. The datapack JSON
 * lives at {@code data/eclipse/dimension/ferryman_arena.json} (limbo dimension type for
 * the midnight sky/fog, flat void generator); the actual arena blocks are stamped by
 * {@link ArenaBuilder}.
 */
public final class ArenaDimension {
    public static final ResourceKey<Level> ARENA = ResourceKey.create(Registries.DIMENSION,
            ResourceLocation.fromNamespaceAndPath("eclipse", "ferryman_arena"));

    private ArenaDimension() {}

    public static boolean isArena(ResourceKey<Level> dimension) {
        return ARENA.equals(dimension);
    }

    public static boolean isInArena(Entity entity) {
        return entity != null && isArena(entity.level().dimension());
    }

    /** The arena level, or {@code null} until the datapack dimension is loaded. */
    @Nullable
    public static ServerLevel get(MinecraftServer server) {
        return server.getLevel(ARENA);
    }
}
