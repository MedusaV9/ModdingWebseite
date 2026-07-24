package dev.projecteclipse.eclipse.limbo;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.Level;

/**
 * Constants for the Limbo dimension ({@code eclipse:limbo}) where banned
 * players are sent as green ghosts. The dimension JSON itself is owned by a
 * parallel worker; consumers must handle {@code server.getLevel(LIMBO)}
 * returning {@code null} until it lands (see
 * {@link dev.projecteclipse.eclipse.lives.BanService}).
 */
public final class LimboDimension {
    public static final ResourceKey<Level> LIMBO =
            ResourceKey.create(Registries.DIMENSION, ResourceLocation.fromNamespaceAndPath("eclipse", "limbo"));

    private LimboDimension() {}
}
