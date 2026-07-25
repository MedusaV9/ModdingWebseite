package dev.projecteclipse.eclipse.worldgen.structure;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.devtools.SpawnTuningData;
import dev.projecteclipse.eclipse.protection.DevMode;
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
 * breaking and placing are cancelled (only devmode players exempt — {@link DevMode},
 * PROGFIX #5: ops obey the zone until they toggle {@code /devmode}), explosions lose
 * every affected block inside the zone, and non-eclipse hostile
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
 *
 * <p>plans_v5 PLAN-B B10: the break/place/explosion handlers additionally enforce the
 * BROAD {@code protection.json} spawn zone (default r=96) whenever {@code spawn.noBuild}
 * is set (default true; {@code spawn.buildRadius} > 0 overrides the ring size) — the
 * r=19..96 band around the altar is no longer freely minable. Fluid buckets and
 * vehicles/TNT in the broad zone are already cancelled by
 * {@link dev.projecteclipse.eclipse.protection.SpawnProtectionRules} (RightClickBlock +
 * FluidPlaceBlockEvent + EntityJoinLevelEvent); flint-and-steel fire rides the vanilla
 * {@code useOn} snapshot capture into {@code EntityPlaceEvent}, so no extra interact
 * handler is needed here. Before the sanctum builds ({@code altarPos == null}) the zone
 * centers on the authored disc center, so spawn is protected from tick 0.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SanctumProtection {
    /** Horizontal protection radius around the altar column. */
    public static final int RADIUS = 18;
    /** Protected vertical band below the altar (crater floor is altar−22 on the island). */
    public static final int VERTICAL_BELOW = 26;
    /** Protected vertical band above the altar (halos +8, W5 orbital ring +7, pillars). */
    public static final int VERTICAL_ABOVE = 24;
    /**
     * B10 null-altar fallback: the authored disc center — the flat spawn pad sits at
     * y 70 ({@code DiscTerrainFunction.computeSurfaceY}, r &lt; 14 blend) — so the spawn
     * zone is protected from tick 0, before the sanctum builds (or after a failed
     * {@link #refresh}).
     */
    private static final BlockPos FALLBACK_CENTER = new BlockPos(0, 70, 0);

    @Nullable
    private static BlockPos altarPos;

    private SanctumProtection() {}

    /** Re-caches the protected center from world state (server start / sanctum build). */
    public static void refresh(MinecraftServer server) {
        altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos != null) {
            EclipseMod.LOGGER.info("Sanctum protection active: r={} x y[-{}..+{}] around {} (break/place/explosions cancelled, hostile spawns suppressed, devmode exempt)",
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
     * the center. Before the sanctum builds ({@code altarPos == null}) the authored disc
     * center stands in (B10) — a null return used to silently disable ALL protection.
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
        return altarPos != null ? altarPos : FALLBACK_CENTER;
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
        if (server == null) {
            return false;
        }
        return withinSpawnBand(level, pos, spawnRadius(server));
    }

    /** The broad-zone cylinder test at an explicit radius (shared by build gate + spawn zone). */
    private static boolean withinSpawnBand(Level level, BlockPos pos, int radius) {
        BlockPos center = center(level);
        if (center == null || level.dimension() != Level.OVERWORLD) {
            return false;
        }
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();
        int dx = pos.getX() - center.getX();
        int dz = pos.getZ() - center.getZ();
        return (long) dx * dx + (long) dz * dz <= (long) radius * radius
                && pos.getY() >= rules.verticalFrom() && pos.getY() <= rules.verticalTo();
    }

    /**
     * Build gate of the break/place/explosion handlers (B10): the r=18 sanctum cylinder
     * always blocks; with {@code spawn.noBuild} (default true) the broad spawn zone
     * blocks too — {@code spawn.buildRadius} &gt; 0 sizes the no-build ring independently
     * of the PvP/grief ring, 0 reuses {@code spawn.radius}.
     */
    public static boolean isBuildBlocked(Level level, BlockPos pos) {
        if (isProtected(level, pos)) {
            return true;
        }
        ProtectionConfig.SpawnRules rules = ProtectionConfig.current().spawn();
        if (!rules.noBuild()) {
            return false;
        }
        if (rules.buildRadius() > 0) {
            return withinSpawnBand(level, pos, rules.buildRadius());
        }
        return isSpawnProtected(level, pos);
    }

    @SubscribeEvent
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !isBuildBlocked(level, event.getPos())) {
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
        if (!(event.getLevel() instanceof ServerLevel level) || !isBuildBlocked(level, event.getPos())) {
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

    /** Explosions may still hurt entities, but never break sanctum/spawn-zone blocks. */
    @SubscribeEvent
    public static void onExplosionDetonate(ExplosionEvent.Detonate event) {
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        event.getAffectedBlocks().removeIf(pos -> isBuildBlocked(level, pos));
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

    /** PROGFIX #5: only devmode players bypass — ops obey the zone by default. */
    private static boolean isExempt(@Nullable Player player) {
        return DevMode.isExempt(player);
    }

    /** v1-style feedback: action bar + a muffled chime, never chat. */
    private static void hint(@Nullable Player player) {
        if (player instanceof ServerPlayer serverPlayer) {
            serverPlayer.displayClientMessage(ServerLang.tr(serverPlayer, "message.eclipse.sanctum_protected"), true);
            serverPlayer.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 0.7F, 0.6F);
        }
    }
}
