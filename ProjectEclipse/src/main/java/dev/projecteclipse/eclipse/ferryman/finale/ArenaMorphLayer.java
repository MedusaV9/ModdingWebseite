package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ferryman.ArenaBuilder;
import dev.projecteclipse.eclipse.ferryman.ArenaDimension;
import dev.projecteclipse.eclipse.ferryman.ArenaFight;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * F-046 — the SHIP→ARENA morph layer: while the Ferryman fight runs, the arena reads
 * as the ghost ship TRANSFORMED — the ring deck "grows" a rim of dark-oak plank aprons
 * around the whole perimeter (the deck ENLARGES), violet glow rails ride the aprons'
 * outer lips, glow sheaths wrap the four mast pillars, and a fog wall
 * ({@link FxCues#CUE_ARENA_MIST}, re-fired at four perimeter anchors every
 * {@value #MIST_PERIOD}t) closes the horizon. After the fight everything is UNBUILT —
 * the layer is pure {@code BLOCK_DISPLAY} decor over the untouched arena stamp, so the
 * Rückverwandlung is one sweep and a crash can never leave a half-morphed arena.
 *
 * <p><b>Self-contained lifecycle</b> (no {@code ArenaFight} edits): a {@value #STRIDE}t
 * server-tick stride watches {@link ArenaFight#isFightRunning} — rising edge applies
 * the layer (sweep-then-spawn), falling edge sweeps it. The flag is PERSISTED
 * ({@code ArenaState}), so a restart mid-fight re-applies the layer on the first
 * stride; orphans from a crash between fights die in the once-per-boot tag sweep
 * ({@code StormDebrisFx} doctrine — tag over UUID list).</p>
 *
 * <p><b>Pose law</b>: glow pieces breathe on the stateless absolute-clock,
 * one-interpolated-window-per-stride cadence ({@code ArenaBuilder} accent law); plank
 * aprons are static deck and never re-push after their {@value #GROW_TICKS}t grow-in.
 * Every piece carries full brightness + a raised {@code view_range} through the
 * {@link DisplayBrightnessFx} NBT seam (the rim sits ~50 blocks out — past the vanilla
 * 64-block display draw ceiling for players on the far side).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ArenaMorphLayer {
    /** Frozen command tag on every F-046 morph display (orphan sweeps). */
    public static final String TAG = "eclipse_finale_arena_morph";

    /** Fight-watch stride (ticks) — state edge checks + glow breathing cadence. */
    private static final int STRIDE = 20;
    /** Mist-wall re-fire cadence; the {@code arena_mist_wall} asset sustains 140t. */
    private static final int MIST_PERIOD = 120;

    /** Plank apron segment length along the rim (blocks) + outward depth + thickness. */
    private static final int APRON_STEP = 6;
    private static final float APRON_DEPTH = 3.0F;
    private static final float APRON_THICK = 0.55F;
    /** Glow rail cross-section riding each apron's outer lip. */
    private static final float RAIL_SIZE = 0.45F;
    /** Pillar glow sheath: XZ girth (pillar is 1×{@value #PILLAR_HEIGHT}×1). */
    private static final float SHEATH_GIRTH = 1.5F;
    /** Mirrors {@code ArenaBuilder.PILLARS}/{@code PILLAR_HEIGHT} (private there). */
    private static final int[][] PILLARS = {{24, 12}, {24, -12}, {-24, 12}, {-24, -12}};
    private static final int PILLAR_HEIGHT = 12;

    /** Grow-in: one interpolated window from flat (Y ~0) to seated, per piece. */
    private static final int GROW_TICKS = 40;
    /** Glow breathing amplitude (scale fraction) and period (ticks). */
    private static final double BREATH = 0.08D;
    private static final double BREATH_PERIOD = 90.0D;
    /** Golden angle (radians) — per-piece breathing phases (never in lockstep). */
    private static final float GOLDEN_ANGLE = 2.3999632F;

    /** Draw distance {@code × 64} blocks (DisplayBrightnessFx view_range seam). */
    private static final float VIEW_RANGE = 2.5F;

    /** One live piece: base-center seat + rest scale (breathing re-derives the pose). */
    private record Piece(UUID id, Vector3f scale, boolean glows) {}

    private static final List<Piece> PIECES = new ArrayList<>();
    private static boolean applied;
    private static boolean bootSwept;
    private static long appliedAt;

    private ArenaMorphLayer() {}

    // ------------------------------------------------------------------ tick driver

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.overworld().getGameTime() % STRIDE != 0L) {
            return;
        }
        ServerLevel arena = ArenaDimension.get(server);
        if (arena == null) {
            return;
        }
        boolean fighting = ArenaFight.isFightRunning(server);
        if (!bootSwept) {
            bootSwept = true;
            if (!fighting) {
                sweep(arena); // crash orphans from a previous run (tag over UUID list)
            }
        }
        if (fighting && !applied) {
            apply(arena);
        } else if (!fighting && applied) {
            remove(arena);
        } else if (applied) {
            animate(arena);
        }
    }

    // ------------------------------------------------------------------ apply / remove

    /** Builds the morph layer (sweep-then-spawn) and announces it with one deep chime. */
    private static void apply(ServerLevel arena) {
        sweep(arena);
        PIECES.clear();
        appliedAt = arena.getGameTime();
        int deckTop = ArenaBuilder.ringY(arena) + 1; // ring-deck walking surface
        BlockState plank = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        BlockState glow = Blocks.PURPLE_STAINED_GLASS.defaultBlockState();

        // 1. Long-side aprons + rails: march the rim, one segment per APRON_STEP.
        for (int x = -ArenaBuilder.ARENA_HALF_LENGTH + APRON_STEP / 2;
                x <= ArenaBuilder.ARENA_HALF_LENGTH - APRON_STEP / 2; x += APRON_STEP) {
            int half = ArenaBuilder.arenaHalfWidthAt(x);
            for (int side = -1; side <= 1; side += 2) {
                double zApron = side * (half + 0.5D + APRON_DEPTH * 0.5D);
                spawnPiece(arena, new Vec3(x + 0.5D, deckTop - APRON_THICK, zApron),
                        plank, new Vector3f(APRON_STEP, APRON_THICK, APRON_DEPTH), false);
                double zRail = side * (half + 0.5D + APRON_DEPTH - RAIL_SIZE * 0.5D);
                spawnPiece(arena, new Vec3(x + 0.5D, deckTop, zRail),
                        glow, new Vector3f(APRON_STEP, RAIL_SIZE, RAIL_SIZE), true);
            }
        }
        // 2. Bow/stern end caps (aprons run along Z past x ±ARENA_HALF_LENGTH).
        for (int side = -1; side <= 1; side += 2) {
            double xApron = side * (ArenaBuilder.ARENA_HALF_LENGTH + 0.5D + APRON_DEPTH * 0.5D);
            double xRail = side * (ArenaBuilder.ARENA_HALF_LENGTH + 0.5D + APRON_DEPTH - RAIL_SIZE * 0.5D);
            for (int z = -4; z <= 4; z += 4) {
                spawnPiece(arena, new Vec3(xApron, deckTop - APRON_THICK, z + 0.5D),
                        plank, new Vector3f(APRON_DEPTH, APRON_THICK, 4.0F), false);
                spawnPiece(arena, new Vec3(xRail, deckTop, z + 0.5D),
                        glow, new Vector3f(RAIL_SIZE, RAIL_SIZE, 4.0F), true);
            }
        }
        // 3. Violet glow sheaths wrapping the four mast pillars.
        for (int[] cell : PILLARS) {
            spawnPiece(arena, new Vec3(cell[0] + 0.5D, deckTop, cell[1] + 0.5D),
                    glow, new Vector3f(SHEATH_GIRTH, PILLAR_HEIGHT + 1.5F, SHEATH_GIRTH), true);
        }

        applied = true;
        fireMistWall(arena);
        BlockPos center = new BlockPos(0, ArenaBuilder.pitY(arena), 0);
        arena.playSound(null, center, SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.AMBIENT, 1.4F, 0.55F);
        arena.playSound(null, center, SoundEvents.WOOD_PLACE, SoundSource.AMBIENT, 1.2F, 0.6F);
        EclipseMod.LOGGER.info("Arena morph layer (F-046) applied: {} display piece(s), mist wall live",
                PIECES.size());
    }

    /** The Rückverwandlung: list discard + tag sweep (the mist one-shots just expire). */
    private static void remove(ServerLevel arena) {
        int discarded = 0;
        for (Piece piece : PIECES) {
            if (arena.getEntity(piece.id()) instanceof Display.BlockDisplay display) {
                display.discard();
                discarded++;
            }
        }
        PIECES.clear();
        applied = false;
        sweep(arena); // belt-and-braces: UUID-list drift (e.g. /kill) leaves tagged strays
        EclipseMod.LOGGER.info("Arena morph layer (F-046) unbuilt: {} display piece(s) discarded", discarded);
    }

    /** Discards every tagged morph display over the arena footprint (never the spectator ship). */
    private static void sweep(ServerLevel arena) {
        AABB volume = new AABB(-ArenaBuilder.ARENA_HALF_LENGTH - 8.0D, 0.0D,
                -ArenaBuilder.ARENA_HALF_WIDTH - 8.0D,
                ArenaBuilder.ARENA_HALF_LENGTH + 8.0D, 160.0D, ArenaBuilder.ARENA_HALF_WIDTH + 8.0D);
        List<Entity> strays = arena.getEntities((Entity) null, volume,
                entity -> entity.getTags().contains(TAG));
        if (!strays.isEmpty()) {
            strays.forEach(Entity::discard);
            EclipseMod.LOGGER.info("Arena morph layer: {} orphan display(s) swept", strays.size());
        }
    }

    // ------------------------------------------------------------------ animate

    /** Glow breathing + mist re-fires, on the stride's absolute clock. */
    private static void animate(ServerLevel arena) {
        long gameTime = arena.getGameTime();
        if (gameTime - appliedAt >= GROW_TICKS) { // let the grow-in window finish first
            long target = gameTime + STRIDE;
            int index = 0;
            for (Piece piece : PIECES) {
                index++;
                if (!piece.glows()
                        || !(arena.getEntity(piece.id()) instanceof Display.BlockDisplay display)) {
                    continue;
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(STRIDE);
                display.setTransformation(seatPose(piece.scale(), breath(index, target)));
            }
        }
        if (gameTime % MIST_PERIOD == 0L) {
            fireMistWall(arena);
        }
    }

    /** Four fog-bank segments boxing the arena in ({@code a} = segment yaw). */
    private static void fireMistWall(ServerLevel arena) {
        double y = ArenaBuilder.ringY(arena) + 2.0D;
        double xEdge = ArenaBuilder.ARENA_HALF_LENGTH + 6.0D;
        double zEdge = ArenaBuilder.ARENA_HALF_WIDTH + 8.0D;
        // Long sides (bank runs along X → yaw 0/180), then bow/stern (along Z → 90/270).
        FxPayloads.sendFxEvent(arena, FxCues.CUE_ARENA_MIST, new Vec3(0.5D, y, zEdge), 0.0F, 0.0F, 192.0D);
        FxPayloads.sendFxEvent(arena, FxCues.CUE_ARENA_MIST, new Vec3(0.5D, y, -zEdge), 180.0F, 0.0F, 192.0D);
        FxPayloads.sendFxEvent(arena, FxCues.CUE_ARENA_MIST, new Vec3(xEdge, y, 0.5D), 90.0F, 0.0F, 192.0D);
        FxPayloads.sendFxEvent(arena, FxCues.CUE_ARENA_MIST, new Vec3(-xEdge, y, 0.5D), 270.0F, 0.0F, 192.0D);
    }

    // ------------------------------------------------------------------ pieces

    /**
     * One morph piece anchored at {@code seat} = the box's BASE CENTER (XZ-centered, Y
     * bottom). Spawned flat (Y scale ~0 — it "grows out of the deck"; displays have no
     * collision) with one interpolated {@value #GROW_TICKS}t window to the seated pose.
     */
    private static void spawnPiece(ServerLevel arena, Vec3 seat, BlockState state,
            Vector3f scale, boolean glows) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, arena);
        display.setBlockState(state);
        display.moveTo(seat.x, seat.y, seat.z, 0.0F, 0.0F);
        display.addTag(TAG);
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        Transformation seated = seatPose(scale, 1.0F);
        display.setTransformation(new Transformation(seated.getTranslation(),
                seated.getLeftRotation(),
                new Vector3f(seated.getScale().x(), 0.02F, seated.getScale().z()),
                seated.getRightRotation()));
        PIECES.add(new Piece(display.getUUID(), scale, glows)); // before addFreshEntity
        arena.addFreshEntity(display);
        DisplayBrightnessFx.set(display, 15, 15, VIEW_RANGE);
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(GROW_TICKS);
        display.setTransformation(seated);
    }

    /** Base-center box pose at breathing factor {@code b} (1 = rest). */
    private static Transformation seatPose(Vector3f scale, float b) {
        float sx = scale.x() * b;
        float sy = scale.y() * b;
        float sz = scale.z() * b;
        return new Transformation(new Vector3f(-sx * 0.5F, 0.0F, -sz * 0.5F),
                new Quaternionf(), new Vector3f(sx, sy, sz), new Quaternionf());
    }

    /** Golden-angle breathing factor for glow piece {@code index} at {@code gameTime}. */
    private static float breath(int index, long gameTime) {
        return 1.0F + (float) (BREATH
                * Math.sin(gameTime * (Math.PI * 2.0D / BREATH_PERIOD) + index * GOLDEN_ANGLE));
    }
}
