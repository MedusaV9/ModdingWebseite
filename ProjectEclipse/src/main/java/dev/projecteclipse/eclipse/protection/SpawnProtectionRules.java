package dev.projecteclipse.eclipse.protection;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageTypes;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.item.PrimedTnt;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.vehicle.AbstractMinecart;
import net.minecraft.world.entity.vehicle.Boat;
import net.minecraft.world.item.BucketItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.material.Fluids;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.entity.EntityMobGriefingEvent;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.level.BlockEvent;

/**
 * Spawn protection v2 rules that extend P6's {@link SanctumProtection} zone query without
 * editing that class: PvP block, fluid/vehicle griefing, mob griefing, fall-damage safety
 * (with optional edge band), creative/perm exemptions.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SpawnProtectionRules {
    private static final int HINT_COLOR = 0xB98CFF;

    private SpawnProtectionRules() {}

    public static boolean isInProtectionZone(Level level, BlockPos pos) {
        return SanctumProtection.isSpawnProtected(level, pos);
    }

    public static boolean isInFallSafeZone(Level level, BlockPos pos) {
        if (isInProtectionZone(level, pos)) {
            return true;
        }
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();
        int extra = rules.edgeBandExtra();
        if (extra <= 0) {
            return false;
        }
        MinecraftServer server = level.getServer();
        if (server == null) {
            return false;
        }
        return isWithinExpandedCylinder(level, pos,
                SanctumProtection.spawnRadius(server) + extra,
                rules.verticalFrom(), rules.verticalTo());
    }

    @SubscribeEvent
    public static void onLivingIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        ServerLevel level = victim.serverLevel();
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();

        if (rules.noFallDamage() && event.getSource().is(DamageTypes.FALL)
                && isInFallSafeZone(level, victim.blockPosition()) && !isExempt(victim)) {
            event.setCanceled(true);
            return;
        }

        if (!rules.noPvp()) {
            return;
        }
        Entity attacker = event.getSource().getEntity();
        if (!(attacker instanceof ServerPlayer attackerPlayer)) {
            return;
        }
        if (isExempt(victim) || isExempt(attackerPlayer)) {
            return;
        }
        boolean victimInside = isInProtectionZone(level, victim.blockPosition());
        boolean attackerInside = isInProtectionZone(level, attackerPlayer.blockPosition());
        if (victimInside || attackerInside) {
            event.setCanceled(true);
            hint(attackerPlayer, "message.eclipse.protection.pvp");
        }
    }

    @SubscribeEvent
    public static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (event.getLevel().isClientSide() || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (isExempt(player)) {
            return;
        }
        BlockPos target = event.getPos();
        ServerLevel level = (ServerLevel) event.getLevel();
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();
        ItemStack stack = event.getItemStack();

        if (rules.noFluidPlace() && isFluidPlacement(stack) && isInProtectionZone(level, target)) {
            event.setCanceled(true);
            hint(player, "message.eclipse.protection.fluid");
            return;
        }

        if (rules.noVehiclePlace() && isVehicleItem(stack.getItem()) && isInProtectionZone(level, target)) {
            event.setCanceled(true);
            hint(player, "message.eclipse.protection.vehicle");
        }
    }

    @SubscribeEvent
    public static void onFluidPlaceBlock(BlockEvent.FluidPlaceBlockEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        if (!ProtectionConfig.current().spawn().noFluidPlace()) {
            return;
        }
        if (isInProtectionZone(level, event.getPos())) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onEntityJoinLevel(EntityJoinLevelEvent event) {
        if (event.getLevel().isClientSide()) {
            return;
        }
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        Entity entity = event.getEntity();
        BlockPos pos = entity.blockPosition();
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();

        if (rules.noVehiclePlace()) {
            if ((entity instanceof AbstractMinecart || entity instanceof Boat || entity instanceof PrimedTnt)
                    && isInProtectionZone(level, pos)) {
                event.setCanceled(true);
            }
        }
    }

    @SubscribeEvent
    public static void onMobGriefing(EntityMobGriefingEvent event) {
        if (!(event.getEntity().level() instanceof ServerLevel level)) {
            return;
        }
        if (!ProtectionConfig.current().spawn().noMobGriefing()) {
            return;
        }
        if (isInProtectionZone(level, event.getEntity().blockPosition())) {
            event.setCanGrief(false);
        }
    }

    private static boolean isWithinExpandedCylinder(Level level, BlockPos pos, int radius,
            int verticalFrom, int verticalTo) {
        BlockPos center = SanctumProtection.center(level);
        if (center == null || level.dimension() != Level.OVERWORLD) {
            return false;
        }
        int dx = pos.getX() - center.getX();
        int dz = pos.getZ() - center.getZ();
        return (long) dx * dx + (long) dz * dz <= (long) radius * radius
                && pos.getY() >= verticalFrom && pos.getY() <= verticalTo;
    }

    private static boolean isFluidPlacement(ItemStack stack) {
        Item item = stack.getItem();
        if (item instanceof BucketItem bucket) {
            return bucket.content == Fluids.WATER || bucket.content == Fluids.LAVA;
        }
        return stack.is(Items.WATER_BUCKET) || stack.is(Items.LAVA_BUCKET);
    }

    private static boolean isVehicleItem(Item item) {
        return item == Items.TNT_MINECART
                || item == Items.MINECART
                || item == Items.CHEST_MINECART
                || item == Items.HOPPER_MINECART
                || item == Items.FURNACE_MINECART
                || item == Items.OAK_BOAT
                || item == Items.OAK_CHEST_BOAT
                || item == Items.TNT;
    }

    public static boolean isExempt(@Nullable Player player) {
        if (!(player instanceof ServerPlayer serverPlayer)) {
            return false;
        }
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();
        if (rules.exemptCreative() && serverPlayer.isCreative()) {
            return true;
        }
        return serverPlayer.hasPermissions(rules.exemptPermission());
    }

    private static void hint(ServerPlayer player, String key) {
        player.displayClientMessage(Component.translatable(key).withColor(HINT_COLOR), true);
        player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.7F, 0.6F);
    }
}
