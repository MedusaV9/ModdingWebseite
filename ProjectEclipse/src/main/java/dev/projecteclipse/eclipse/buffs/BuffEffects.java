package dev.projecteclipse.eclipse.buffs;

import java.util.ArrayList;
import java.util.List;
import java.util.function.LongSupplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.util.ExhaustionScaler;
import dev.projecteclipse.eclipse.economy.SupplyBeacon;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;
import net.neoforged.neoforge.event.level.BlockDropsEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Consumer hooks for timed buff effects (R16/R17): ore/shard doubling, hunger scaler,
 * XP magnet sweep, and supply-drop periodic action.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BuffEffects {
    private static final int SWEEP_INTERVAL_TICKS = 20;

    // statics reset on ServerStopped
    private static int tickCounter = 0;
    private static LongSupplier epochMillis = System::currentTimeMillis;
    private static TimedBuffService service;

    private BuffEffects() {}

    static void bindService(TimedBuffService bound) {
        service = bound;
    }

    /** Test-only clock injection (B9 gametests). */
    public static void setEpochClockForTests(LongSupplier supplier) {
        epochMillis = supplier;
    }

    public static void resetEpochClock() {
        epochMillis = System::currentTimeMillis;
    }

    static long nowEpochMillis() {
        return epochMillis.getAsLong();
    }

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        ExhaustionScaler.registerFactor("buff_half_hunger",
                () -> service != null ? service.multiplier(event.getServer(), "hunger") : 1.0F);
    }

    @SubscribeEvent(priority = EventPriority.LOW)
    static void onBlockDrops(BlockDropsEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || service == null) {
            return;
        }
        if (service.multiplier(level.getServer(), "ore_drops") <= 1.0F + 1.0E-4F) {
            return;
        }
        if (!event.getState().is(BlockTags.COAL_ORES)
                && !event.getState().is(BlockTags.IRON_ORES)
                && !event.getState().is(BlockTags.GOLD_ORES)
                && !event.getState().is(BlockTags.COPPER_ORES)
                && !event.getState().is(BlockTags.DIAMOND_ORES)
                && !event.getState().is(BlockTags.EMERALD_ORES)
                && !event.getState().is(BlockTags.LAPIS_ORES)
                && !event.getState().is(BlockTags.REDSTONE_ORES)) {
            return;
        }
        if (!PlacedBlockCheck.isNatural(level, event.getPos())) {
            return;
        }

        List<ItemEntity> extras = new ArrayList<>();
        for (ItemEntity drop : event.getDrops()) {
            ItemStack stack = drop.getItem();
            if (stack.isEmpty()) {
                continue;
            }
            ItemEntity duplicate = new ItemEntity(level, drop.getX(), drop.getY(), drop.getZ(), stack.copy());
            duplicate.setDefaultPickUpDelay();
            extras.add(duplicate);
        }
        event.getDrops().addAll(extras);
    }

    @SubscribeEvent(priority = EventPriority.LOW)
    static void onLivingDrops(LivingDropsEvent event) {
        if (!(event.getEntity().level() instanceof ServerLevel level) || service == null) {
            return;
        }
        if (service.multiplier(level.getServer(), "shard_drops") <= 1.0F + 1.0E-4F) {
            return;
        }
        var shard = EclipseItems.UMBRAL_SHARD.get();
        List<ItemEntity> extras = new ArrayList<>();
        for (ItemEntity drop : event.getDrops()) {
            if (drop.getItem().is(shard)) {
                ItemEntity duplicate = new ItemEntity(level, drop.getX(), drop.getY(), drop.getZ(),
                        drop.getItem().copy());
                duplicate.setDefaultPickUpDelay();
                extras.add(duplicate);
            }
        }
        event.getDrops().addAll(extras);
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (service == null) {
            return;
        }
        if (++tickCounter < SWEEP_INTERVAL_TICKS) {
            return;
        }
        tickCounter = 0;
        service.runPeriodicAndMagnet(event.getServer(), nowEpochMillis());
    }

    static void pullExperienceOrbs(ServerLevel level, float radius) {
        if (radius <= 0.0F) {
            return;
        }
        double radiusSq = radius * radius;
        for (ServerPlayer player : level.players()) {
            AABB box = player.getBoundingBox().inflate(radius);
            List<ExperienceOrb> orbs = level.getEntitiesOfClass(ExperienceOrb.class, box, orb -> true);
            for (ExperienceOrb orb : orbs) {
                if (player.distanceToSqr(orb) > radiusSq) {
                    continue;
                }
                Vec3 target = player.position().add(0.0D, 0.5D, 0.0D);
                Vec3 delta = target.subtract(orb.position());
                if (delta.lengthSqr() < 0.25D) {
                    continue;
                }
                orb.setDeltaMovement(delta.normalize().scale(0.35D));
            }
        }
    }

    static void fireSupplyDrop(MinecraftServer server) {
        SupplyBeacon.drop(server);
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        tickCounter = 0;
        service = null;
        resetEpochClock();
        ExhaustionScaler.unregisterFactor("buff_half_hunger");
    }
}
