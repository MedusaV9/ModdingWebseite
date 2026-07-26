package dev.projecteclipse.eclipse.gameplay;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.damagesource.DamageTypes;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;

/**
 * No fall damage around the overworld Nether-entrance crater (user decree: "~10 blocks
 * around the hole"). The {@code SpawnProtectionRules} fall-safety pattern — a
 * {@link LivingIncomingDamageEvent} cancel for {@link DamageTypes#FALL} — applied to a
 * cylinder of {@value #SAFE_RADIUS} blocks around {@link BreachGeometry}'s center
 * (crater radius {@value BreachGeometry#CRATER_RADIUS} + the requested 10-block band,
 * full column height: falls INTO the funnel are the whole point of the entrance).
 *
 * <p>Read-only against the {@code worldgen/} package (owned elsewhere): the center comes
 * from {@link BreachGeometry#centerX()}/{@link BreachGeometry#centerZ()} exactly like
 * {@code BreachTransferService}'s server-tick usage, and the zone only arms once
 * {@link FrozenParams#breachOpen()} mirrors the crater's materialization — before the
 * breach exists there is no hole to protect.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BreachFallProtection {
    /** Crater lip ({@value BreachGeometry#CRATER_RADIUS}) + the decreed ~10-block band. */
    private static final int SAFE_RADIUS = BreachGeometry.CRATER_RADIUS + 10;

    private BreachFallProtection() {}

    @SubscribeEvent
    public static void onLivingIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)
                || !event.getSource().is(DamageTypes.FALL)) {
            return;
        }
        ServerLevel level = victim.serverLevel();
        if (!Level.OVERWORLD.equals(level.dimension()) || !FrozenParams.breachOpen()) {
            return;
        }
        double dx = victim.getX() - (BreachGeometry.centerX() + 0.5D);
        double dz = victim.getZ() - (BreachGeometry.centerZ() + 0.5D);
        if (dx * dx + dz * dz <= (double) SAFE_RADIUS * SAFE_RADIUS) {
            event.setCanceled(true);
        }
    }
}
