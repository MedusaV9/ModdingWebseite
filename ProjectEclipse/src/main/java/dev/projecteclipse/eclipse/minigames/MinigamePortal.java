package dev.projecteclipse.eclipse.minigames;

import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Minigame event portal — a restyled copy of the proven {@code XboxPortal} construct: one
 * vanilla {@code minecraft:interaction} entity (3×4 trigger volume) framed by decorative
 * vanilla {@code minecraft:block_display} pieces. No custom blocks/entities; every piece
 * carries the {@value #ENTITY_TAG} command tag for restart-safe discovery/removal.
 *
 * <p><b>Restyle vs xbox</b>: the frame reads teal/violet instead of nostalgic obsidian —
 * crying-obsidian pillars, an amethyst top bar with sea-lantern corner accents — and the
 * server-side ambient fallback is a soul-flame column instead of reverse-portal motes.
 * The client rift tear reuses the frozen {@code eclipse:fx/rift_open}/{@code rift_close}
 * events with the existing {@code RiftFx.STYLE_PORTAL} style constant (payload
 * {@code b = 1}), exactly like the xbox portal — same renderer, different frame tint.</p>
 */
public final class MinigamePortal {
    /** Command tag on every portal piece (interaction + displays). */
    public static final String ENTITY_TAG = "eclipse_minigame_portal";

    /** Trigger volume dimensions (same plan-frozen 3×4 as the xbox portal). */
    private static final float WIDTH = 3.0F;
    private static final float HEIGHT = 4.0F;

    /** Frozen P2 §3.2 FX ids — byte-identical to the ids the xbox portal sends. */
    private static final ResourceLocation FX_RIFT_OPEN =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_open");
    private static final ResourceLocation FX_RIFT_CLOSE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_close");
    private static final float RIFT_FX_WIDTH = 5.0F;
    /** {@code b} value = {@code RiftFx.STYLE_PORTAL} (the existing portal style constant). */
    private static final float RIFT_STYLE_PORTAL = 1.0F;
    private static final double FX_RANGE = 128.0D;

    private MinigamePortal() {}

    // ------------------------------------------------------------------ placement

    /**
     * First valid 5×5 flat spot ring-scanned {@code searchMin..searchMax} blocks out from
     * the shared spawn, skipping sanctum-protected positions. {@code null} when the scan
     * fails — caller falls back to {@code /dev minigame portal here}.
     */
    @Nullable
    public static BlockPos findSpotNearSpawn(ServerLevel level) {
        MinigameConfig.Values config = MinigameConfig.get();
        BlockPos spawn = level.getSharedSpawnPos();
        for (int radius = config.portalSearchMinRadius(); radius <= config.portalSearchMaxRadius(); radius++) {
            int steps = Math.max(8, radius * 4);
            for (int step = 0; step < steps; step++) {
                double angle = (Math.PI * 2.0D * step) / steps;
                int x = spawn.getX() + (int) Math.round(Math.cos(angle) * radius);
                int z = spawn.getZ() + (int) Math.round(Math.sin(angle) * radius);
                BlockPos candidate = surfaceAt(level, x, z);
                if (candidate != null && isValidPad(level, candidate)) {
                    return candidate;
                }
            }
        }
        return null;
    }

    @Nullable
    private static BlockPos surfaceAt(ServerLevel level, int x, int z) {
        int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (y <= level.getMinBuildHeight() || y >= level.getMaxBuildHeight() - 6) {
            return null;
        }
        return new BlockPos(x, y, z);
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

    /** Spawns trigger + frame at {@code base} (feet level), records it in state, fires FX. */
    public static void place(ServerLevel level, BlockPos base, MinigameState state) {
        removeEntities(level, base); // idempotent: clear leftovers at the same spot first

        spawnInteraction(level, base);
        spawnFrame(level, base);

        state.setPortal(level.dimension(), base);
        Vec3 center = Vec3.atBottomCenterOf(base);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CFxEventPayload(FX_RIFT_OPEN, center.add(0.0D, HEIGHT / 2.0D, 0.0D),
                        RIFT_FX_WIDTH, RIFT_STYLE_PORTAL));
        level.playSound(null, base, SoundEvents.END_PORTAL_SPAWN, SoundSource.BLOCKS, 0.7F, 1.6F);
        EclipseMod.LOGGER.info("Minigame portal placed at {} in {}", base, level.dimension().location());
    }

    /** Removes all tagged pieces near the recorded portal position and fires the close FX. */
    public static void remove(ServerLevel level, BlockPos base, MinigameState state) {
        removeEntities(level, base);
        Vec3 center = Vec3.atBottomCenterOf(base);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CFxEventPayload(FX_RIFT_CLOSE, center.add(0.0D, HEIGHT / 2.0D, 0.0D),
                        RIFT_FX_WIDTH, 0.0F));
        level.playSound(null, base, SoundEvents.GLASS_BREAK, SoundSource.BLOCKS, 0.6F, 0.8F);
        state.setPortal(null, null);
        EclipseMod.LOGGER.info("Minigame portal removed at {} in {}", base, level.dimension().location());
    }

    private static void removeEntities(ServerLevel level, BlockPos base) {
        // Force the chunk so tagged pieces are discoverable right after boot.
        level.getChunk(base);
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

    // ------------------------------------------------------------------ entities

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
            EclipseMod.LOGGER.error("Could not create minigame portal interaction entity at {}", base);
            return;
        }
        interaction.addTag(ENTITY_TAG);
        level.addFreshEntity(interaction);
    }

    /**
     * Decorative frame (restyled from the xbox obsidian arch): crying-obsidian pillars
     * flanking the 3-wide opening, an amethyst top bar, sea-lantern corner accents.
     */
    private static void spawnFrame(ServerLevel level, BlockPos base) {
        BlockState pillar = Blocks.CRYING_OBSIDIAN.defaultBlockState();
        BlockState bar = Blocks.AMETHYST_BLOCK.defaultBlockState();
        BlockState accent = Blocks.SEA_LANTERN.defaultBlockState();

        for (int y = 0; y < 4; y++) {
            spawnBlockDisplay(level, base.offset(-2, y, 0), pillar);
            spawnBlockDisplay(level, base.offset(2, y, 0), pillar);
        }
        for (int x = -2; x <= 2; x++) {
            boolean corner = Math.abs(x) == 2;
            spawnBlockDisplay(level, base.offset(x, 4, 0), corner ? accent : bar);
        }
    }

    private static void spawnBlockDisplay(ServerLevel level, BlockPos pos, BlockState blockState) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
        display.setBlockState(blockState);
        display.moveTo(pos.getX(), pos.getY(), pos.getZ(), 0.0F, 0.0F);
        display.addTag(ENTITY_TAG);
        level.addFreshEntity(display);
    }

    // ------------------------------------------------------------------ ambient fallback

    /** Cheap always-on server-side FX (called every 10 ticks while the portal exists). */
    public static void ambientTick(ServerLevel level, BlockPos base, long gameTime) {
        Vec3 center = Vec3.atBottomCenterOf(base);
        level.sendParticles(ParticleTypes.SOUL_FIRE_FLAME,
                center.x, center.y + 2.0D, center.z,
                6, WIDTH / 4.0D, 1.4D, WIDTH / 4.0D, 0.01D);
        if (gameTime % 100L == 0L) {
            level.playSound(null, base, SoundEvents.BEACON_AMBIENT, SoundSource.BLOCKS, 0.3F, 1.4F);
        }
    }
}
