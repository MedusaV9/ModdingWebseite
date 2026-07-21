package dev.projecteclipse.eclipse.registry;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.particles.ParticleType;
import net.minecraft.core.registries.Registries;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Particle type registry for Project: Eclipse. No content yet. */
public final class EclipseParticles {
    public static final DeferredRegister<ParticleType<?>> PARTICLES =
            DeferredRegister.create(Registries.PARTICLE_TYPE, EclipseMod.MOD_ID);

    private EclipseParticles() {}

    public static void register(IEventBus modEventBus) {
        PARTICLES.register(modEventBus);
    }
}
