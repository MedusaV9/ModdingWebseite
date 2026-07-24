package dev.projecteclipse.eclipse.backrooms;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;

/**
 * Dimension key for the Backrooms event dimension (plans_v5 PLAN-C C18 / IDEAS §A1) —
 * the {@code MinigameDimensions}/{@code XboxDimensions} void-dim pattern. The datapack
 * JSONs live at {@code data/eclipse/dimension/backrooms.json} (flat void generator) and
 * {@code data/eclipse/dimension_type/backrooms.json}.
 *
 * <p>Dimension-type facts other classes rely on (IDEAS §A1):
 * {@code fixed_time: 18000} (midnight — keeps {@code level.isDay()} false so
 * {@code TheOtherEntity.despawnAtDawn()} never fires and the cameo works with zero
 * entity changes), {@code has_skylight: false}, {@code ambient_light: 0}, height 32
 * (all light comes from the {@code ochre_froglight} panels, so the flicker reads).</p>
 */
public final class BackroomsDimension {
    public static final ResourceKey<Level> BACKROOMS = ResourceKey.create(Registries.DIMENSION,
            ResourceLocation.fromNamespaceAndPath("eclipse", "backrooms"));

    private BackroomsDimension() {}

    public static boolean isBackrooms(ResourceKey<Level> dimension) {
        return BACKROOMS.equals(dimension);
    }

    public static boolean isInBackrooms(Entity entity) {
        return entity != null && isBackrooms(entity.level().dimension());
    }
}
