package dev.projecteclipse.eclipse.sequence;

import java.util.List;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Reveal-time decor of the intro sequence (P2 R10 phase 5): {@value #COUNT} animated
 * floating {@link Display.BlockDisplay} rubble fragments (deepslate/obsidian/amethyst mix,
 * final scales 0.3–1.6) scattered around and UNDER the floating sanctum island, so the
 * torn-out-of-the-ground look reads clearly from ground level — debris hanging in the rip
 * between the crater and the island underside. The 12 orbital ring displays are
 * {@code worldgen.structure.SanctumOrbitals}' job (P6-W5); this class never touches them.
 *
 * <p><b>Idempotent by tag</b> (plan §W6 outline): every fragment carries the command tag
 * {@value #TAG} plus a per-anchor identity tag ({@code eclipse_intro_decor_<i>}).
 * {@link #ensure} tag-scans the island volume, adopts one display per anchor, discards
 * duplicates/strays and spawns whatever is missing — {@code /kill @e[tag=eclipse_intro_decor]}
 * heals on the next ensure/reconcile pass. (The plan wrote the tag as
 * {@code eclipse:intro_decor}; vanilla {@code /tag}/selector strings cannot contain
 * {@code :}, so the underscore form is the frozen id.) Entities are persistent, so the
 * decor survives restarts and {@link #ensure} simply re-adopts it.</p>
 *
 * <p><b>Animation</b> (R10 numbers): per-fragment rotation 0.2–1.0°/tick around a fixed
 * random-ish axis, bob amplitude 0.05–0.25 blocks with periods 80–200 ticks — pushed as
 * ONE interpolated transform per entity every {@value #UPDATE_CADENCE_TICKS} ticks
 * (interpolation duration {@value #UPDATE_CADENCE_TICKS}: smooth at 1/4 rate, the
 * SanctumOrbitals transport pattern via the accesstransformer-opened {@code Display}
 * setters). All pose components are absolute functions of game time, so pushes are
 * stateless and restart-safe. The whole pass early-outs while no player is within
 * {@value #PLAYER_GATE_RANGE} blocks of the altar.</p>
 *
 * <p>Everything is deterministic per anchor index (tiny local hash — no
 * {@code RandomSource}), so ensure/reconcile always rebuilds the identical cloud.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FloatingDecor {
    /** Frozen command tag on every intro-decor display (see class doc re the plan's colon form). */
    public static final String TAG = "eclipse_intro_decor";
    /** Number of rubble fragments (R10 phase 5). */
    public static final int COUNT = 28;

    /** Transform push cadence == interpolation duration (R10: per 4 ticks). */
    public static final int UPDATE_CADENCE_TICKS = 4;
    /** Animation pauses (zero packets) with no player within this range of the altar. */
    public static final double PLAYER_GATE_RANGE = 96.0D;
    /** Full reconcile sweep cadence while animated (adopt/dedupe/top-up). */
    private static final int RECONCILE_CADENCE_TICKS = 200;

    /** Fragment cloud spread: horizontal ring band around the altar column. */
    private static final double MIN_RADIUS = 11.0D;
    private static final double MAX_RADIUS = 23.0D;
    /** Golden angle keeps neighbouring fragments well separated without randomness. */
    private static final double GOLDEN_ANGLE = 2.399963229728653D;

    private static final float MIN_SCALE = 0.3F;
    private static final float MAX_SCALE = 1.6F;
    private static final double SPIN_MIN_DEG_PER_TICK = 0.2D;
    private static final double SPIN_MAX_DEG_PER_TICK = 1.0D;
    private static final double BOB_MIN_AMPLITUDE = 0.05D;
    private static final double BOB_MAX_AMPLITUDE = 0.25D;
    private static final double BOB_MIN_PERIOD_TICKS = 80.0D;
    private static final double BOB_MAX_PERIOD_TICKS = 200.0D;

    /** Tag-scan half extent around the altar column (covers the cloud + margin). */
    private static final int SCAN_XZ_MARGIN = 28;

    /** Rubble palette (plan: deepslate/obsidian/amethyst mix). */
    private static final BlockState[] PALETTE = {
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.AMETHYST_BLOCK.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.CRYING_OBSIDIAN.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState()};

    /** Cached live displays by anchor index; {@code null} until the first ensure/adopt. */
    @Nullable
    private static Display.BlockDisplay[] displays;
    /** Altar the cache belongs to; cleared on server stop. */
    @Nullable
    private static BlockPos cachedAltar;

    private FloatingDecor() {}

    // ------------------------------------------------------------------ public API

    /**
     * Spawns/adopts the full decor cloud around the given (floating-island) altar.
     * Idempotent: repeat calls adopt existing tagged displays instead of duplicating.
     * Safe to call before the island flip too — the cloud is anchored purely off
     * {@code altarPos} geometry.
     */
    public static void ensure(ServerLevel level, BlockPos altarPos) {
        cachedAltar = altarPos.immutable();
        reconcile(level, altarPos);
    }

    /** Discards every tagged decor display (dev revert / replay cleanup). */
    public static void removeAll(ServerLevel level, BlockPos altarPos) {
        int discarded = 0;
        for (Display.BlockDisplay display : scanTagged(level, altarPos)) {
            display.discard();
            discarded++;
        }
        displays = null;
        cachedAltar = null;
        EclipseMod.LOGGER.info("FloatingDecor: discarded {} decor display(s)", discarded);
    }

    /**
     * Boot re-attach: adopts persisted decor so the animation resumes after a restart.
     * No-op (and no spawns) when nothing tagged exists yet — the live sequence spawns the
     * cloud at reveal time via {@link #ensure}.
     */
    public static void adoptExisting(ServerLevel level, BlockPos altarPos) {
        if (!level.isLoaded(altarPos) || !level.areEntitiesLoaded(ChunkPos.asLong(altarPos))) {
            return;
        }
        if (scanTagged(level, altarPos).isEmpty()) {
            return;
        }
        ensure(level, altarPos);
    }

    // ------------------------------------------------------------------ tick loop

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        BlockPos altarPos = cachedAltar;
        if (altarPos == null || server.getTickCount() % UPDATE_CADENCE_TICKS != 0) {
            return;
        }
        ServerLevel overworld = server.overworld();
        if (!playerNear(overworld, altarPos)) {
            return;
        }
        long gameTime = overworld.getGameTime();
        if (displays == null || gameTime % RECONCILE_CADENCE_TICKS < UPDATE_CADENCE_TICKS) {
            reconcile(overworld, altarPos);
        }
        animate(altarPos, gameTime);
    }

    /** World-scoped statics must never leak into the next (singleplayer) world. */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        displays = null;
        cachedAltar = null;
    }

    private static boolean playerNear(ServerLevel overworld, BlockPos altarPos) {
        double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
        for (ServerPlayer player : overworld.players()) {
            if (!player.isSpectator() && player.distanceToSqr(
                    altarPos.getX() + 0.5D, altarPos.getY(), altarPos.getZ() + 0.5D) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ reconcile

    private static void reconcile(ServerLevel level, BlockPos altarPos) {
        if (!level.isLoaded(altarPos) || !level.areEntitiesLoaded(ChunkPos.asLong(altarPos))) {
            return; // entity section still loading — try again next pass
        }
        Display.BlockDisplay[] resolved = new Display.BlockDisplay[COUNT];
        int discarded = 0;
        for (Display.BlockDisplay display : scanTagged(level, altarPos)) {
            int index = identityIndexOf(display);
            if (index < 0 || resolved[index] != null) {
                display.discard(); // stray or duplicate
                discarded++;
            } else {
                resolved[index] = display;
            }
        }
        long gameTime = level.getGameTime();
        int spawned = 0;
        for (int i = 0; i < COUNT; i++) {
            if (resolved[i] != null) {
                continue;
            }
            resolved[i] = spawnFragment(level, altarPos, i, gameTime);
            if (resolved[i] != null) {
                spawned++;
            }
        }
        displays = resolved;
        if (spawned > 0 || discarded > 0) {
            EclipseMod.LOGGER.info("FloatingDecor: spawned {} fragment(s), discarded {} (of {})",
                    spawned, discarded, COUNT);
        }
    }

    private static List<Display.BlockDisplay> scanTagged(ServerLevel level, BlockPos altarPos) {
        int topY = FloatingSanctumBuilder.islandTopY(altarPos);
        int groundY = FloatingSanctumBuilder.groundY(altarPos);
        AABB volume = new AABB(
                altarPos.getX() - SCAN_XZ_MARGIN, groundY - 6.0D, altarPos.getZ() - SCAN_XZ_MARGIN,
                altarPos.getX() + SCAN_XZ_MARGIN, topY + 12.0D, altarPos.getZ() + SCAN_XZ_MARGIN);
        return level.getEntities(EntityType.BLOCK_DISPLAY, volume,
                display -> display.getTags().contains(TAG));
    }

    private static int identityIndexOf(Display.BlockDisplay display) {
        for (int i = 0; i < COUNT; i++) {
            if (display.getTags().contains(TAG + "_" + i)) {
                return i;
            }
        }
        return -1;
    }

    @Nullable
    private static Display.BlockDisplay spawnFragment(ServerLevel level, BlockPos altarPos,
            int index, long gameTime) {
        Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(level);
        if (display == null) {
            EclipseMod.LOGGER.error("FloatingDecor: failed to create block_display #{}", index);
            return null;
        }
        Vec3 anchor = anchorPos(altarPos, index);
        display.moveTo(anchor.x, anchor.y, anchor.z, 0.0F, 0.0F);
        display.setBlockState(PALETTE[(index + (int) (hash01(index, 7) * PALETTE.length)) % PALETTE.length]);
        display.addTag(TAG);
        display.addTag(TAG + "_" + index);
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(poseAt(index, gameTime));
        level.addFreshEntity(display);
        return display;
    }

    /**
     * Deterministic fragment position: golden-angle ring band r 11–23 around the altar
     * column, vertically spread from just above the crater floor up to slightly above the
     * island top — biased low so the rip underside reads from ground level.
     */
    private static Vec3 anchorPos(BlockPos altarPos, int index) {
        double angle = index * GOLDEN_ANGLE + hash01(index, 1) * 0.6D;
        double radius = MIN_RADIUS + (MAX_RADIUS - MIN_RADIUS) * hash01(index, 2);
        int topY = FloatingSanctumBuilder.islandTopY(altarPos);
        int groundY = FloatingSanctumBuilder.groundY(altarPos);
        double vertical = Math.pow(hash01(index, 3), 1.35D); // bias toward the underside
        double y = groundY + 2.0D + (topY + 4.0D - (groundY + 2.0D)) * vertical;
        return new Vec3(
                altarPos.getX() + 0.5D + Math.cos(angle) * radius,
                y,
                altarPos.getZ() + 0.5D + Math.sin(angle) * radius);
    }

    // ------------------------------------------------------------------ animation

    private static void animate(BlockPos altarPos, long gameTime) {
        Display.BlockDisplay[] current = displays;
        if (current == null) {
            return;
        }
        boolean missing = false;
        for (int i = 0; i < current.length; i++) {
            Display.BlockDisplay display = current[i];
            if (display == null || display.isRemoved()) {
                missing = true; // killed/unloaded — the next reconcile pass respawns it
                continue;
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_CADENCE_TICKS);
            display.setTransformation(poseAt(i, gameTime + UPDATE_CADENCE_TICKS));
        }
        if (missing) {
            displays = null;
        }
    }

    /**
     * Absolute pose of one fragment at {@code gameTime}: tumble about a fixed per-index
     * axis + vertical bob, with the scaled block re-centered on its anchor point through
     * the rotation (the SanctumOrbitals {@code T·L·S} math).
     */
    private static Transformation poseAt(int index, long gameTime) {
        float scale = MIN_SCALE + (MAX_SCALE - MIN_SCALE) * (float) Math.pow(hash01(index, 4), 1.3D);
        double spinRate = Math.toRadians(SPIN_MIN_DEG_PER_TICK
                + (SPIN_MAX_DEG_PER_TICK - SPIN_MIN_DEG_PER_TICK) * hash01(index, 5));
        double direction = hash01(index, 6) < 0.5D ? 1.0D : -1.0D;
        float spinAngle = (float) (hash01(index, 8) * Math.PI * 2.0D + direction * spinRate * gameTime);
        Vector3f axis = new Vector3f(
                (float) (hash01(index, 9) * 2.0D - 1.0D),
                (float) (0.5D + hash01(index, 10)),
                (float) (hash01(index, 11) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(spinAngle, axis);

        double amplitude = BOB_MIN_AMPLITUDE
                + (BOB_MAX_AMPLITUDE - BOB_MIN_AMPLITUDE) * hash01(index, 12);
        double period = BOB_MIN_PERIOD_TICKS
                + (BOB_MAX_PERIOD_TICKS - BOB_MIN_PERIOD_TICKS) * hash01(index, 13);
        float bob = (float) (Math.sin((Math.PI * 2.0D / period) * gameTime
                + hash01(index, 14) * Math.PI * 2.0D) * amplitude);

        Vector3f translation = new Vector3f(0.0F, bob, 0.0F);
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        translation.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /** Tiny deterministic hash in [0, 1) — no {@code RandomSource}, fully replayable. */
    private static double hash01(int index, int salt) {
        int h = index * 374761393 + salt * 668265263;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / (double) 0x80000000L;
    }
}
