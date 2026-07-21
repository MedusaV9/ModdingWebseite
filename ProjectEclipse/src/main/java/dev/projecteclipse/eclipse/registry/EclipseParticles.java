package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.particles.ParticleType;
import net.minecraft.core.particles.SimpleParticleType;
import net.minecraft.core.registries.Registries;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Particle type registry for Project: Eclipse. */
public final class EclipseParticles {
    public static final DeferredRegister<ParticleType<?>> PARTICLES =
            DeferredRegister.create(Registries.PARTICLE_TYPE, EclipseMod.MOD_ID);

    /**
     * Purple wisp emitted near the arm of players carrying the arm artifact. The type is
     * common-side; the sprite provider lives in {@code client.PurpleWispParticle} (Dist.CLIENT).
     */
    public static final Supplier<SimpleParticleType> PURPLE_WISP = PARTICLES.register("purple_wisp",
            () -> new SimpleParticleType(false));

    private EclipseParticles() {}

    public static void register(IEventBus modEventBus) {
        PARTICLES.register(modEventBus);
    }
}
