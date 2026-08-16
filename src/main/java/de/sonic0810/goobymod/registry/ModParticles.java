package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.core.particles.ParticleType;
import net.minecraft.core.particles.SimpleParticleType;
import net.minecraft.core.registries.Registries;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ModParticles {
    public static final DeferredRegister<ParticleType<?>> PARTICLE_TYPES =
            DeferredRegister.create(Registries.PARTICLE_TYPE, GoobyMod.MODID);

    /** Zzz-Partikel fuers Schlafen — schwebt niedlich nach oben. */
    public static final DeferredHolder<ParticleType<?>, SimpleParticleType> ZZZ =
            PARTICLE_TYPES.register("zzz", () -> new SimpleParticleType(false));
    public static final DeferredHolder<ParticleType<?>, SimpleParticleType> HEART_GOLD =
            PARTICLE_TYPES.register("heart_gold", () -> new SimpleParticleType(false));
    public static final DeferredHolder<ParticleType<?>, SimpleParticleType> PAW_PRINT =
            PARTICLE_TYPES.register("paw_print", () -> new SimpleParticleType(false));

    public static void register(IEventBus bus) {
        PARTICLE_TYPES.register(bus);
    }

    private ModParticles() {
    }
}
