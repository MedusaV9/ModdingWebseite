package dev.projecteclipse.eclipse.ferryman;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.door.DoorRegistry;
import dev.projecteclipse.eclipse.limbo.door.DoorState;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlock;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlockEntity;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorFillerBlock;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The DEAD DOOR at the altar (C10.1): the existing {@code eclipse:respawn_door}
 * multiblock (registry reused via its blocks, never edited) stamped in the overworld at
 * finale arm time. Walking into the {@link #walkVolume walk-through volume} in front of
 * it teleports the player onto the limbo ghost ship behind a
 * {@code PortalTransitionController} fade — {@code ArenaFight} owns that tick check;
 * this class only places/removes the blocks and remembers them in {@link ArenaState}
 * (restart-safe cleanup, the {@code XboxPortal} place/remove discipline).
 *
 * <p>Placement scans the four horizontal directions {@value #DOOR_DISTANCE} blocks out
 * from the altar and stamps the 3×5 aperture into the plane with the most air (front
 * face toward the altar, so the purple spill greets the offering). Cells the door
 * replaces are almost always air on the altar dais; removal restores plain air either
 * way (logged when it had to overwrite terrain).</p>
 *
 * <p><b>Rising assembly (BD-SHIP):</b> the door no longer stamps instantly — {@link
 * #place} records the door in {@link ArenaState} FIRST (the restart anchor), scatters
 * fifteen tagged block-display stones on the dais, floats them up on golden-staggered
 * interpolation start delays, snaps them into the aperture in unison, and only THEN
 * stamps the real multiblock at t={@value #ASSEMBLY_STAMP_TICK} ({@code ArenaFight}'s
 * gate tick drives {@link #tickAssembly}). The walk-through volume is armed the whole
 * time (the gate beat owns crossings, not the blocks). A restart never resumes
 * mid-assembly: {@link #ensureStamped} finds "door recorded, controller missing", sweeps
 * the pieces and stamps instantly — the exact C10.5 mirror.</p>
 */
public final class AltarDoor {
    /** Blocks between the altar and the stamped door plane. */
    private static final int DOOR_DISTANCE = 4;
    /** Depth of the walk-through trigger volume in front of the aperture. */
    private static final double WALK_DEPTH = 1.25D;
    private static final double FX_RANGE = 96.0D;

    // --- rising assembly (BD-SHIP) ---
    /** Command tag on every dead-door assembly piece (restart/removal sweeps). */
    public static final String ASSEMBLY_TAG = "eclipse_altar_door_rise";
    /** Golden angle (radians) — stagger ordering, so the aperture fills in a non-row scatter. */
    private static final float GOLDEN_ANGLE = 2.3999632F;
    /**
     * Assembly tick table: ONE rise push per piece at t={@value #ASSEMBLY_RISE_TICK}
     * (float-up choreographed purely by interpolation start delays, 0–{@value
     * #ASSEMBLY_STAGGER_MAX}t golden-sequence ordered, {@value #ASSEMBLY_RISE_DURATION}t
     * long — the last piece finishes rising before the snap), a unison snap push at
     * t={@value #ASSEMBLY_SNAP_TICK}, the real block stamp at t={@value #ASSEMBLY_STAMP_TICK}.
     */
    private static final int ASSEMBLY_RISE_TICK = 1;
    private static final int ASSEMBLY_RISE_DURATION = 18;
    private static final int ASSEMBLY_STAGGER_MAX = 8;
    private static final int ASSEMBLY_SNAP_TICK = 28;
    private static final int ASSEMBLY_SNAP_DURATION = 6;
    private static final int ASSEMBLY_STAMP_TICK = 36;
    /**
     * The rising stones read as raw grave material (the credits FLYER_PALETTE's "altar
     * stone" family), never a fake door — the GeckoLib door model replaces them at stamp.
     */
    private static final BlockState[] ASSEMBLY_PALETTE = {
            Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState(),
            Blocks.DEEPSLATE_TILES.defaultBlockState(),
            Blocks.BONE_BLOCK.defaultBlockState()};

    /** The single in-flight assembly, or {@code null}. Server thread only, never persisted. */
    @Nullable
    private static Assembly assembly;

    /** Transient rising-assembly state (a restart never resumes it — see {@link #ensureStamped}). */
    private record Assembly(ResourceKey<Level> dimension, BlockPos controller, Direction facing,
            long startedGameTime, List<UUID> pieces) {}

    private AltarDoor() {}

    // ------------------------------------------------------------------ place / remove

    /**
     * Arms the dead door near {@code altarPos}: records it in {@link ArenaState} (the
     * restart anchor, FIRST), then materializes it as a rising assembly — the real block
     * stamp fires {@value #ASSEMBLY_STAMP_TICK}t later in {@link #tickAssembly}. The
     * walk-through volume works off the record, so it is armed from this very tick.
     * Returns {@code false} (no changes) while {@code DoorRegistry} is unbound — the
     * caller falls back to the doorless crossing.
     */
    public static boolean place(ServerLevel level, BlockPos altarPos) {
        if (!DoorRegistry.isBound()) {
            EclipseMod.LOGGER.warn("Altar dead door skipped: respawn door blocks are not registered");
            return false;
        }
        ArenaState state = ArenaState.get(level.getServer());
        if (state.doorPos() != null) {
            // Never two doors — and remove() cancels the old door's assembly BEFORE the
            // new record overwrites it, so there are never two assemblies either.
            remove(level.getServer());
        }
        Direction facing = bestFacing(level, altarPos);
        // Controller = bottom-center of the aperture, front face looking back at the altar.
        BlockPos controller = altarPos.relative(facing, DOOR_DISTANCE);
        Direction doorFacing = facing.getOpposite();
        state.setDoor(level.dimension(), controller, doorFacing);
        sweepAssemblyPieces(level, controller);
        // Arm the record BEFORE spawning: the join-time stray guard consults it, and a
        // piece must be a known live UUID the instant its add fires the join event.
        List<UUID> pieces = new ArrayList<>(RespawnDoorBlock.WIDTH * RespawnDoorBlock.HEIGHT);
        assembly = new Assembly(level.dimension(), controller, doorFacing, level.getGameTime(), pieces);
        spawnAssemblyPieces(level, controller, doorFacing, pieces);

        // The "materialize begins" cue stays at t=0; the door itself creaks at the stamp.
        Vec3 center = doorCenter(controller);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, center));
        level.playSound(null, controller, SoundEvents.END_PORTAL_SPAWN, SoundSource.BLOCKS, 1.0F, 0.4F);
        EclipseMod.LOGGER.info("Altar dead door materializing at {} facing {} ({} rising piece(s), stamp in {}t)",
                controller.toShortString(), doorFacing, RespawnDoorBlock.WIDTH * RespawnDoorBlock.HEIGHT,
                ASSEMBLY_STAMP_TICK);
        return true;
    }

    /** Removes the stamped door (controller removal cascades the fillers) + clears state. */
    public static void remove(MinecraftServer server) {
        cancelAssembly(server); // a door mid-assembly dies with its record
        ArenaState state = ArenaState.get(server);
        BlockPos controller = state.doorPos();
        if (controller == null || state.doorDimension() == null) {
            return;
        }
        ServerLevel level = server.getLevel(state.doorDimension());
        if (level != null) {
            level.getChunk(controller); // force-load: cleanup must never silently miss
            sweepAssemblyPieces(level, controller); // belt-and-braces beyond the UUID list
            Direction facing = state.doorFacing();
            // Controller first (its onRemove cascades live fillers), then a belt-and-braces
            // sweep of all 15 cells for orphans left by a partial stamp.
            if (level.getBlockState(controller).getBlock() instanceof RespawnDoorBlock) {
                level.setBlock(controller, Blocks.AIR.defaultBlockState(), Block.UPDATE_ALL);
            }
            for (int col = 0; col < RespawnDoorBlock.WIDTH; col++) {
                for (int row = 0; row < RespawnDoorBlock.HEIGHT; row++) {
                    BlockPos cell = RespawnDoorBlock.cellPos(controller, facing, col, row);
                    Block block = level.getBlockState(cell).getBlock();
                    if (block instanceof RespawnDoorBlock || block instanceof RespawnDoorFillerBlock) {
                        level.setBlock(cell, Blocks.AIR.defaultBlockState(), Block.UPDATE_ALL);
                    }
                }
            }
            level.playSound(null, controller, SoundEvents.IRON_DOOR_CLOSE, SoundSource.BLOCKS, 1.0F, 0.5F);
            EclipseMod.LOGGER.info("Altar dead door removed at {}", controller.toShortString());
        } else {
            EclipseMod.LOGGER.warn("Altar dead door dimension {} not loaded; clearing the record only",
                    state.doorDimension().location());
        }
        state.clearDoor();
    }

    // ------------------------------------------------------------------ rising assembly (BD-SHIP)

    /**
     * Drives the rising assembly (called every gate tick by {@code ArenaFight.tickGate}):
     * the rise push at t={@value #ASSEMBLY_RISE_TICK}, the unison snap at
     * t={@value #ASSEMBLY_SNAP_TICK} (one deepslate lock-in sound + a brightness flash —
     * fifteen stones locking as one beat), the real stamp at t={@value #ASSEMBLY_STAMP_TICK}.
     */
    public static void tickAssembly(MinecraftServer server) {
        Assembly current = assembly;
        if (current == null) {
            return;
        }
        ServerLevel level = server.getLevel(current.dimension());
        if (level == null) {
            assembly = null;
            return;
        }
        long t = level.getGameTime() - current.startedGameTime();
        if (t == ASSEMBLY_RISE_TICK) {
            pushAssembly(level, current, true);
        } else if (t == ASSEMBLY_SNAP_TICK) {
            pushAssembly(level, current, false);
            level.playSound(null, current.controller(), SoundType.DEEPSLATE_BRICKS.getPlaceSound(),
                    SoundSource.BLOCKS, 1.1F, 0.75F);
        } else if (t >= ASSEMBLY_STAMP_TICK) {
            assembly = null;
            sweepAssemblyPieces(level, current.controller());
            stampBlocks(level, current.controller(), current.facing());
        }
    }

    /**
     * Restart repair seam (the C10.5 mirror): a door recorded without its controller
     * block means the run crashed inside the {@value #ASSEMBLY_STAMP_TICK}t assembly
     * window — sweep the stray pieces and stamp instantly. A restart never resumes
     * mid-assembly. No-op when no door is recorded or the controller already stands.
     */
    public static void ensureStamped(MinecraftServer server) {
        ArenaState state = ArenaState.get(server);
        BlockPos controller = state.doorPos();
        if (controller == null || state.doorDimension() == null) {
            return;
        }
        ServerLevel level = server.getLevel(state.doorDimension());
        if (level == null) {
            return;
        }
        level.getChunk(controller);
        if (level.getBlockState(controller).getBlock() instanceof RespawnDoorBlock) {
            return; // stamped before the stop/crash — nothing mid-assembly to repair
        }
        sweepAssemblyPieces(level, controller);
        stampBlocks(level, controller, state.doorFacing());
        EclipseMod.LOGGER.info("Altar dead door: boot caught a mid-assembly stop — stamped instantly");
    }

    /** Cancels the in-flight assembly (server stop / gate drop): pieces discarded, no stamp. */
    public static void cancelAssembly(MinecraftServer server) {
        Assembly current = assembly;
        assembly = null;
        if (current == null) {
            return;
        }
        ServerLevel level = server.getLevel(current.dimension());
        if (level != null) {
            sweepAssemblyPieces(level, current.controller());
        }
    }

    /**
     * The real multiblock stamp (the old {@code place()} tail): controller + fillers +
     * the BE forced OPEN — plus the door-creak sound, which moved here from arm time
     * because the door should creak when it EXISTS.
     */
    private static void stampBlocks(ServerLevel level, BlockPos controller, Direction doorFacing) {
        int overwritten = countNonAir(level, controller, doorFacing);
        BlockState controllerState = DoorRegistry.RESPAWN_DOOR.get().defaultBlockState()
                .setValue(RespawnDoorBlock.FACING, doorFacing)
                .setValue(RespawnDoorBlock.LIT, true);
        level.setBlock(controller, controllerState, Block.UPDATE_ALL);
        RespawnDoorBlock.placeFillers(level, controller, doorFacing, true);
        if (level.getBlockEntity(controller) instanceof RespawnDoorBlockEntity door) {
            // The BE defaults to CLOSED; this door stands wide open for the whole gate.
            // (The client-side ghost rule still shows it closed to ghosts — they cross fine.)
            door.setDoorState(DoorState.OPEN);
        }
        level.playSound(null, controller, SoundEvents.WOODEN_DOOR_OPEN, SoundSource.BLOCKS, 1.2F, 0.5F);
        EclipseMod.LOGGER.info("Altar dead door stamped at {} facing {} ({} terrain cell(s) overwritten)",
                controller.toShortString(), doorFacing, overwritten);
    }

    /** One ground-scattered display stone per aperture cell (entity anchored AT its cell). */
    private static void spawnAssemblyPieces(ServerLevel level, BlockPos controller,
            Direction doorFacing, List<UUID> pieces) {
        for (int col = 0; col < RespawnDoorBlock.WIDTH; col++) {
            for (int row = 0; row < RespawnDoorBlock.HEIGHT; row++) {
                int index = col * RespawnDoorBlock.HEIGHT + row;
                BlockPos cell = RespawnDoorBlock.cellPos(controller, doorFacing, col, row);
                Display.BlockDisplay piece = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
                piece.setBlockState(ASSEMBLY_PALETTE[
                        (int) (hash01(index + 40) * ASSEMBLY_PALETTE.length) % ASSEMBLY_PALETTE.length]);
                piece.moveTo(cell.getX(), cell.getY(), cell.getZ(), 0.0F, 0.0F);
                piece.addTag(ASSEMBLY_TAG);
                piece.setTransformationInterpolationDelay(0);
                piece.setTransformationInterpolationDuration(0);
                piece.setTransformation(scatterPose(index, row, doorFacing));
                pieces.add(piece.getUUID()); // before addFreshEntity: the join guard must know it
                level.addFreshEntity(piece);
            }
        }
    }

    /** Whether {@code id} is a piece of the CURRENT assembly (the join-time stray guard). */
    public static boolean isLivePiece(UUID id) {
        Assembly current = assembly;
        return current != null && current.pieces().contains(id);
    }

    /**
     * The rise push floats every piece from its dais scatter to a hover 0.25 blocks SHY
     * of its cell at 92% scale with a residual tilt (the snap push then has real work —
     * alignment + the last quarter block + scale — so it reads as a SNAP, not a stop);
     * the float-up choreography is pure interpolation start delay (golden-sequence
     * ordered, one push per piece). The snap push is the exact identity cell pose plus a
     * brightness flash. Killed pieces are skipped; the stamp-time sweep reconciles.
     */
    private static void pushAssembly(ServerLevel level, Assembly current, boolean rise) {
        int index = 0;
        for (UUID id : current.pieces()) {
            int i = index++;
            if (!(level.getEntity(id) instanceof Display.BlockDisplay piece)) {
                continue;
            }
            piece.setTransformationInterpolationDelay(rise ? goldenStagger(i) : 0);
            piece.setTransformationInterpolationDuration(
                    rise ? ASSEMBLY_RISE_DURATION : ASSEMBLY_SNAP_DURATION);
            piece.setTransformation(rise ? risePose(i)
                    : assemblyPose(Vec3.ZERO, new Quaternionf(), 1.0F));
            if (!rise) {
                flashPiece(piece);
            }
        }
    }

    /** Ground scatter: lying on the dais in front of its column, tilted, undersized. */
    private static Transformation scatterPose(int index, int row, Direction facing) {
        double h = hash01(index);
        float golden = (float) Math.IEEEremainder(index * GOLDEN_ANGLE, Math.PI * 2.0D);
        Vec3 front = new Vec3(facing.getStepX(), 0.0D, facing.getStepZ());
        Vec3 across = new Vec3(-front.z, 0.0D, front.x);
        Vec3 offset = front.scale(0.8D + h * 1.2D)
                .add(across.scale(golden / Math.PI * 1.4D))
                .add(0.0D, -row + 0.08D, 0.0D);
        Quaternionf rotation = new Quaternionf()
                .rotationY(golden * 0.35F)
                .rotateX((float) Math.toRadians((18.0D + h * 12.0D) * tiltSign(index)));
        return assemblyPose(offset, rotation, 0.82F);
    }

    /** Hover pose: 0.25 shy of the cell, 92% scale, 8° residual tilt (same axis as scatter). */
    private static Transformation risePose(int index) {
        float golden = (float) Math.IEEEremainder(index * GOLDEN_ANGLE, Math.PI * 2.0D);
        Quaternionf rotation = new Quaternionf()
                .rotationY(golden * 0.06F)
                .rotateX((float) Math.toRadians(8.0D * tiltSign(index)));
        return assemblyPose(new Vec3(0.0D, -0.25D, 0.0D), rotation, 0.92F);
    }

    /** Center-pivot law: block center at cell center + {@code offset}; identity at rest. */
    private static Transformation assemblyPose(Vec3 offset, Quaternionf rotation, float scale) {
        Vector3f center = new Vector3f(0.5F, 0.5F, 0.5F);
        Vector3f translation = new Vector3f((float) offset.x, (float) offset.y, (float) offset.z)
                .add(center)
                .sub(rotation.transform(new Vector3f(center).mul(scale), new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    private static int tiltSign(int index) {
        return (index & 1) == 0 ? 1 : -1;
    }

    /** Golden-sequence stagger in [0, {@value #ASSEMBLY_STAGGER_MAX}] — a pleasing non-row fill. */
    private static int goldenStagger(int index) {
        double frac = index * 0.61803398875D;
        return (int) ((frac - Math.floor(frac)) * (ASSEMBLY_STAGGER_MAX + 1));
    }

    /**
     * Snap flash: brightness override 14/14 through the vanilla save-data path
     * ({@code setBrightnessOverride} is private — the CreditsSequence doctrine). Never
     * cleared: the pieces are discarded {@value #ASSEMBLY_STAMP_TICK}t−{@value
     * #ASSEMBLY_SNAP_TICK}t later at the stamp.
     */
    private static void flashPiece(Display.BlockDisplay piece) {
        CompoundTag data = piece.saveWithoutId(new CompoundTag());
        CompoundTag brightness = new CompoundTag();
        brightness.putInt("sky", 14);
        brightness.putInt("block", 14);
        data.put("brightness", brightness);
        piece.load(data);
    }

    /** Discards every tagged assembly piece around the aperture (tag sweep, never UUID-bound). */
    private static void sweepAssemblyPieces(ServerLevel level, BlockPos controller) {
        List<Entity> strays = level.getEntities((Entity) null,
                new AABB(controller).inflate(6.0D, 8.0D, 6.0D),
                entity -> entity.getTags().contains(ASSEMBLY_TAG));
        if (!strays.isEmpty()) {
            strays.forEach(Entity::discard);
            EclipseMod.LOGGER.info("Altar dead door: {} assembly piece(s) swept", strays.size());
        }
    }

    /** Fixed positional hash in [0,1) — deterministic scatter, no RandomSource. */
    private static double hash01(int index) {
        long h = 0x9E3779B97F4A7C15L * (index + 1);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
    }

    // ------------------------------------------------------------------ walk-through

    /**
     * Trigger volume in front of the recorded door: aperture width × 3 high ×
     * {@value #WALK_DEPTH} deep on the front side. {@code null} while no door stands.
     */
    @Nullable
    public static AABB walkVolume(MinecraftServer server) {
        ArenaState state = ArenaState.get(server);
        BlockPos controller = state.doorPos();
        if (controller == null) {
            return null;
        }
        Direction facing = state.doorFacing();
        Vec3 base = Vec3.atBottomCenterOf(controller.relative(facing));
        Vec3 out = new Vec3(facing.getStepX(), 0.0D, facing.getStepZ());
        Vec3 across = new Vec3(Math.abs(facing.getStepZ()), 0.0D, Math.abs(facing.getStepX()));
        Vec3 a = base.subtract(across.scale(1.5D)).subtract(out.scale(0.25D));
        Vec3 b = base.add(across.scale(1.5D)).add(out.scale(WALK_DEPTH)).add(0.0D, 3.0D, 0.0D);
        return new AABB(a, b);
    }

    // ------------------------------------------------------------------ helpers

    /** Direction from the altar with the most breathable 3×5 plane (ties → EAST first). */
    private static Direction bestFacing(ServerLevel level, BlockPos altarPos) {
        Direction best = Direction.EAST;
        int bestScore = -1;
        for (Direction direction : new Direction[] {Direction.EAST, Direction.WEST,
                Direction.SOUTH, Direction.NORTH}) {
            BlockPos controller = altarPos.relative(direction, DOOR_DISTANCE);
            int score = 15 - countNonAir(level, controller, direction.getOpposite());
            if (score > bestScore) {
                bestScore = score;
                best = direction;
            }
        }
        return best;
    }

    private static int countNonAir(ServerLevel level, BlockPos controller, Direction doorFacing) {
        int nonAir = 0;
        for (int col = 0; col < RespawnDoorBlock.WIDTH; col++) {
            for (int row = 0; row < RespawnDoorBlock.HEIGHT; row++) {
                if (!level.getBlockState(RespawnDoorBlock.cellPos(controller, doorFacing, col, row)).isAir()) {
                    nonAir++;
                }
            }
        }
        return nonAir;
    }

    private static Vec3 doorCenter(BlockPos controller) {
        return Vec3.atCenterOf(controller.above(2));
    }
}
