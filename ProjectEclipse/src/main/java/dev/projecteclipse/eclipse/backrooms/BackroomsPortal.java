package dev.projecteclipse.eclipse.backrooms;

import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Backrooms portal — the C16 <b>frameless star-rift</b> build (plans_v5 PLAN-C C18 §5):
 * ONE vanilla {@code minecraft:interaction} entity (3×4 trigger volume) and the rift FX
 * payload; NO block-display frame (that is exactly the frame C16 removes from the xbox
 * portal). All pieces carry {@value #ENTITY_TAG} for restart-safe discovery/removal —
 * the tag sweep also clears any legacy frame displays left at the same spot.
 *
 * <p><b>Style byte</b>: the rift payload's {@code b} value is C16's portal-style channel
 * (0 = structure, 1 = xbox portal). C18 claims {@value #RIFT_STYLE_BACKROOMS} — the
 * yellow-tinted tear variant — as its coordinate; until C7's volumetric renderer maps it,
 * clients render the default rift billboard and the always-on server-side fallback below
 * carries the yellow read ({@code WAX_ON} spark column instead of xbox's reverse-portal
 * purple).</p>
 */
public final class BackroomsPortal {
    /** Command tag on every portal piece. */
    public static final String ENTITY_TAG = "eclipse_backrooms_portal";

    /** Trigger volume dimensions (the plan-frozen xbox 3×4). */
    private static final float WIDTH = 3.0F;
    private static final float HEIGHT = 4.0F;

    /** Frozen P2 §3.2 FX ids (constructed locally — the {@code XboxPortal} precedent). */
    private static final ResourceLocation FX_RIFT_OPEN =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_open");
    private static final ResourceLocation FX_RIFT_CLOSE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_close");
    /** Rift tear diameter ({@code a}); the C16 recommendation for a 3×4 volume. */
    private static final float RIFT_FX_WIDTH = 5.0F;
    /** C18's portal-style byte ({@code b}): 2 = backrooms yellow tear (0=structure, 1=xbox). */
    public static final float RIFT_STYLE_BACKROOMS = 2.0F;
    private static final double FX_RANGE = 128.0D;

    private BackroomsPortal() {}

    // ------------------------------------------------------------------ placement

    /**
     * First valid 5×5 flat spot ring-scanned 8..24 blocks out from the shared spawn,
     * skipping sanctum-protected positions ({@code XboxPortal.findSpotNearSpawn} with the
     * xbox default radii). {@code null} → operator places via {@code /dev backrooms portal here}.
     */
    @Nullable
    public static BlockPos findSpotNearSpawn(ServerLevel level) {
        BlockPos spawn = level.getSharedSpawnPos();
        for (int radius = 8; radius <= 24; radius++) {
            int steps = Math.max(8, radius * 4);
            for (int step = 0; step < steps; step++) {
                double angle = (Math.PI * 2.0D * step) / steps;
                int x = spawn.getX() + (int) Math.round(Math.cos(angle) * radius);
                int z = spawn.getZ() + (int) Math.round(Math.sin(angle) * radius);
                int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
                if (y <= level.getMinBuildHeight() || y >= level.getMaxBuildHeight() - 6) {
                    continue;
                }
                BlockPos candidate = new BlockPos(x, y, z);
                if (isValidPad(level, candidate)) {
                    return candidate;
                }
            }
        }
        return null;
    }

    /** 5×5 pad: corner+center heights within ±1, solid ground, 3×4 air above, not sanctum. */
    private static boolean isValidPad(ServerLevel level, BlockPos center) {
        if (SanctumProtection.isProtected(level, center)) {
            return false;
        }
        int centerY = center.getY();
        for (int dx = -2; dx <= 2; dx += 2) {
            for (int dz = -2; dz <= 2; dz += 2) {
                int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        center.getX() + dx, center.getZ() + dz);
                if (Math.abs(y - centerY) > 1) {
                    return false;
                }
            }
        }
        BlockPos below = center.below();
        if (!level.getBlockState(below).isSolidRender(level, below)) {
            return false;
        }
        BoundingBox airBox = new BoundingBox(
                center.getX() - 1, centerY, center.getZ() - 1,
                center.getX() + 1, centerY + 3, center.getZ() + 1);
        for (BlockPos pos : BlockPos.betweenClosed(
                airBox.minX(), airBox.minY(), airBox.minZ(), airBox.maxX(), airBox.maxY(), airBox.maxZ())) {
            if (!level.getBlockState(pos).getCollisionShape(level, pos).isEmpty()) {
                return false;
            }
        }
        return true;
    }

    // ------------------------------------------------------------------ spawn / despawn

    /** Spawns the frameless star at {@code base} (feet level) and fires the yellow rift FX. */
    public static void place(ServerLevel level, BlockPos base) {
        removeEntities(level, base); // idempotent: sweep leftovers (incl. legacy frames)
        spawnInteraction(level, base);

        Vec3 center = Vec3.atBottomCenterOf(base);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CFxEventPayload(FX_RIFT_OPEN, center.add(0.0D, HEIGHT / 2.0D, 0.0D),
                        RIFT_FX_WIDTH, RIFT_STYLE_BACKROOMS));
        level.playSound(null, base, EclipseSounds.EVENT_RIFT_OPEN.get(), SoundSource.BLOCKS, 0.7F, 0.8F);
        EclipseMod.LOGGER.info("Backrooms portal placed at {} in {}", base, level.dimension().location());
    }

    /** Removes all tagged pieces near {@code base} and fires the close FX. */
    public static void remove(ServerLevel level, BlockPos base) {
        removeEntities(level, base);
        Vec3 center = Vec3.atBottomCenterOf(base);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CFxEventPayload(FX_RIFT_CLOSE, center.add(0.0D, HEIGHT / 2.0D, 0.0D),
                        RIFT_FX_WIDTH, 0.0F));
        level.playSound(null, base, EclipseSounds.EVENT_RIFT_SLAM.get(), SoundSource.BLOCKS, 0.6F, 0.9F);
        EclipseMod.LOGGER.info("Backrooms portal removed at {} in {}", base, level.dimension().location());
    }

    private static void removeEntities(ServerLevel level, BlockPos base) {
        level.getChunk(base); // force the chunk so tagged pieces are discoverable after boot
        AABB sweep = new AABB(base).inflate(6.0D, 8.0D, 6.0D);
        List<Entity> pieces = level.getEntities((Entity) null, sweep,
                entity -> entity.getTags().contains(ENTITY_TAG));
        pieces.forEach(Entity::discard);
    }

    /** Player-entry trigger volume: the interaction entity's 3×4 box around {@code base}. */
    public static AABB collisionBox(BlockPos base) {
        double half = WIDTH / 2.0D;
        return new AABB(
                base.getX() + 0.5D - half, base.getY(), base.getZ() + 0.5D - half,
                base.getX() + 0.5D + half, base.getY() + HEIGHT, base.getZ() + 0.5D + half);
    }

    /** Interaction spawned via NBT — vanilla exposes no public width/height setters. */
    private static void spawnInteraction(ServerLevel level, BlockPos base) {
        CompoundTag tag = new CompoundTag();
        tag.putString("id", "minecraft:interaction");
        tag.putFloat("width", WIDTH);
        tag.putFloat("height", HEIGHT);
        tag.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(base.getX() + 0.5D));
        pos.add(DoubleTag.valueOf(base.getY()));
        pos.add(DoubleTag.valueOf(base.getZ() + 0.5D));
        tag.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(tag, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("Could not create backrooms portal interaction entity at {}", base);
            return;
        }
        interaction.addTag(ENTITY_TAG);
        level.addFreshEntity(interaction);
    }

    // ------------------------------------------------------------------ ambient fallback

    /**
     * Cheap always-on server-side FX (every 10 ticks while the portal exists): a yellow
     * {@code WAX_ON} spark column (the tear reads backrooms-yellow even without C7's
     * volumetric renderer) with a thin reverse-portal core, plus a periodic low hum —
     * {@code EVENT_BEAM_HUM} re-pitched 0.55, the same alias note the buzz loop uses.
     */
    public static void ambientTick(ServerLevel level, BlockPos base, long gameTime) {
        Vec3 center = Vec3.atBottomCenterOf(base);
        level.sendParticles(ParticleTypes.WAX_ON,
                center.x, center.y + 2.0D, center.z,
                8, WIDTH / 4.0D, 1.4D, WIDTH / 4.0D, 0.02D);
        level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                center.x, center.y + 2.0D, center.z,
                2, 0.15D, 1.2D, 0.15D, 0.005D);
        if (gameTime % 100L == 0L) {
            level.playSound(null, base, EclipseSounds.EVENT_BEAM_HUM.get(), SoundSource.BLOCKS,
                    0.35F, 0.55F);
        }
    }
}
