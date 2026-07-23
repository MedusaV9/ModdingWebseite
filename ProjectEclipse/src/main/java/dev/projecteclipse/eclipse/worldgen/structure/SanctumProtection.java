package dev.projecteclipse.eclipse.worldgen.structure;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.monster.Enemy;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.FinalizeSpawnEvent;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.level.ExplosionEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Spawn protection around the sanctum altar (docs/ideas/04_content.md §3): within
 * {@value #RADIUS} blocks of the altar, block breaking and placing are cancelled
 * (ops with permission ≥ {@value #EXEMPT_PERMISSION} exempt), explosions lose every
 * affected block inside the zone, and non-eclipse hostile natural spawns are suppressed
 * ({@link FinalizeSpawnEvent}) — the grounds stay unnaturally calm. Blocked players get a
 * v1-style action-bar hint. The altar position is cached from
 * {@link EclipseWorldState#getSanctumAltarPos()} (refreshed on server start by
 * {@link AltarSanctumBuilder}).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SanctumProtection {
    /** Protection radius around the altar block. */
    public static final int RADIUS = 16;
    /** Vanilla permission level that bypasses the protection (ops). */
    private static final int EXEMPT_PERMISSION = 3;

    private static final int RADIUS_SQ = RADIUS * RADIUS;

    @Nullable
    private static BlockPos altarPos;

    private SanctumProtection() {}

    /** Re-caches the protected center from world state (server start / sanctum build). */
    public static void refresh(MinecraftServer server) {
        altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos != null) {
            EclipseMod.LOGGER.info("Sanctum protection active: r={} around {} (break/place/explosions cancelled, hostile spawns suppressed, ops exempt)",
                    RADIUS, altarPos.toShortString());
        }
    }

    /** Statics must never leak into the next world (singleplayer re-opens reuse the JVM). */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        altarPos = null;
    }

    /** Whether a position lies inside the protected sanctum zone of the overworld. */
    public static boolean isProtected(Level level, BlockPos pos) {
        BlockPos altar = altarPos;
        return altar != null && level.dimension() == Level.OVERWORLD
                && pos.distSqr(altar) <= RADIUS_SQ;
    }

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !isProtected(level, event.getPos())) {
            return;
        }
        Player player = event.getPlayer();
        if (isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        hint(player);
    }

    @SubscribeEvent
    public static void onBlockPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !isProtected(level, event.getPos())) {
            return;
        }
        Entity entity = event.getEntity();
        if (entity instanceof Player player && isExempt(player)) {
            return;
        }
        event.setCanceled(true);
        if (entity instanceof Player player) {
            hint(player);
        }
    }

    /** Explosions may still hurt entities, but never break sanctum blocks. */
    @SubscribeEvent
    public static void onExplosionDetonate(ExplosionEvent.Detonate event) {
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        event.getAffectedBlocks().removeIf(pos -> isProtected(level, pos));
    }

    /** Suppresses non-eclipse hostile spawns in the zone (spawn eggs/commands still work). */
    @SubscribeEvent
    public static void onFinalizeSpawn(FinalizeSpawnEvent event) {
        if (event.getSpawnType() == MobSpawnType.COMMAND || event.getSpawnType() == MobSpawnType.SPAWN_EGG
                || event.getSpawnType() == MobSpawnType.BUCKET) {
            return;
        }
        if (!(event.getEntity() instanceof Enemy)) {
            return;
        }
        if ("eclipse".equals(BuiltInRegistries.ENTITY_TYPE.getKey(event.getEntity().getType()).getNamespace())) {
            return;
        }
        ServerLevel level = event.getLevel().getLevel();
        BlockPos spawnPos = BlockPos.containing(event.getX(), event.getY(), event.getZ());
        if (isProtected(level, spawnPos)) {
            event.setSpawnCancelled(true);
        }
    }

    private static boolean isExempt(@Nullable Player player) {
        return player != null && player.hasPermissions(EXEMPT_PERMISSION);
    }

    /** v1-style feedback: action bar + a muffled chime, never chat. */
    private static void hint(@Nullable Player player) {
        if (player instanceof ServerPlayer serverPlayer) {
            serverPlayer.displayClientMessage(Component.translatable("message.eclipse.sanctum_protected"), true);
            serverPlayer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.7F, 0.6F);
        }
    }
}
