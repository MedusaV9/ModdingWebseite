package dev.projecteclipse.eclipse.worldgen.structure;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.devtools.SpawnTuningData;
import dev.projecteclipse.eclipse.protection.ProtectionConfig;
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
 * {@value #RADIUS} horizontal blocks of the altar column (and the vertical band
 * {@value #VERTICAL_BELOW} below to {@value #VERTICAL_ABOVE} above the altar), block
 * breaking and placing are cancelled (ops with permission ≥ {@value #EXEMPT_PERMISSION}
 * exempt), explosions lose every affected block inside the zone, and non-eclipse hostile
 * natural spawns are suppressed ({@link FinalizeSpawnEvent}) — the grounds stay
 * unnaturally calm. Blocked players get a v1-style action-bar hint. The altar position is
 * cached from {@link EclipseWorldState#getSanctumAltarPos()} (refreshed on server start
 * by {@link AltarSanctumBuilder}).
 *
 * <p>P6-W4: the zone grew from a r=16 sphere to a r=18 cylinder slice so the whole v2
 * floating sanctum stays grief-safe — island ellipse (r 16/14), rim ledges, switchback
 * bridge (max r ≈ 17.5), crater bowl (floor at altar−22) and the W5 orbital rings.
 * {@code isProtected(Level, BlockPos)} keeps its exact signature: it is the frozen
 * block-side interface P4's edge/auto-glide safety rule and P2's FX queries consume.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SanctumProtection {
    /** Horizontal protection radius around the altar column. */
    public static final int RADIUS = 18;
    /** Protected vertical band below the altar (crater floor is altar−22 on the island). */
    public static final int VERTICAL_BELOW = 26;
    /** Protected vertical band above the altar (halos +8, W5 orbital ring +7, pillars). */
    public static final int VERTICAL_ABOVE = 24;
    /** Vanilla permission level that bypasses the protection (ops). */
    private static final int EXEMPT_PERMISSION = 3;

    @Nullable
    private static BlockPos altarPos;

    private SanctumProtection() {}

    /** Re-caches the protected center from world state (server start / sanctum build). */
    public static void refresh(MinecraftServer server) {
        altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos != null) {
            EclipseMod.LOGGER.info("Sanctum protection active: r={} x y[-{}..+{}] around {} (break/place/explosions cancelled, hostile spawns suppressed, ops exempt)",
                    radius(server), VERTICAL_BELOW, VERTICAL_ABOVE, center(server.overworld()).toShortString());
        }
    }

    /** Statics must never leak into the next world (singleplayer re-opens reuse the JVM). */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        altarPos = null;
    }

    /**
     * Center shared by the fixed sanctum build cylinder and configurable gameplay spawn
     * zone. A {@code /dev spawn set} override wins; otherwise the authored altar remains
     * the center.
     */
    @Nullable
    public static BlockPos center(Level level) {
        MinecraftServer server = level.getServer();
        if (server != null) {
            BlockPos override = SpawnTuningData.get(server).spawnOverride();
            if (override != null) {
                return override;
            }
        }
        return altarPos;
    }

    /** Radius of the sanctum build cylinder: saved override, otherwise static r=18. */
    public static int radius(MinecraftServer server) {
        int override = SpawnTuningData.get(server).radiusOverride();
        return override > 0 ? override : RADIUS;
    }

    /** Radius of the broad gameplay zone: saved override, otherwise protection.json (default r=96). */
    public static int spawnRadius(MinecraftServer server) {
        int override = SpawnTuningData.get(server).radiusOverride();
        return override > 0 ? override : Math.max(1, ProtectionConfig.current().spawn().radius());
    }

    /** Whether a position lies inside the fixed-radius protected sanctum build cylinder. */
    public static boolean isProtected(Level level, BlockPos pos) {
        BlockPos center = center(level);
        if (center == null || level.dimension() != Level.OVERWORLD) {
            return false;
        }
        int dx = pos.getX() - center.getX();
        int dz = pos.getZ() - center.getZ();
        int dy = pos.getY() - center.getY();
        MinecraftServer server = level.getServer();
        int activeRadius = server == null ? RADIUS : radius(server);
        return (long) dx * dx + (long) dz * dz <= (long) activeRadius * activeRadius
                && dy >= -VERTICAL_BELOW && dy <= VERTICAL_ABOVE;
    }

    /**
     * Broad gameplay protection from {@code protection.json}: default r=96 with its own
     * absolute vertical range. This is deliberately distinct from {@link #isProtected}.
     */
    public static boolean isSpawnProtected(Level level, BlockPos pos) {
        MinecraftServer server = level.getServer();
        BlockPos center = center(level);
        if (server == null || center == null || level.dimension() != Level.OVERWORLD) {
            return false;
        }
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();
        int dx = pos.getX() - center.getX();
        int dz = pos.getZ() - center.getZ();
        int configuredRadius = spawnRadius(server);
        return (long) dx * dx + (long) dz * dz <= (long) configuredRadius * configuredRadius
                && pos.getY() >= rules.verticalFrom() && pos.getY() <= rules.verticalTo();
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
