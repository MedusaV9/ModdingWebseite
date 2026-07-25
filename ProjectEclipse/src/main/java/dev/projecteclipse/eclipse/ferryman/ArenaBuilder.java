package dev.projecteclipse.eclipse.ferryman;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CampfireBlock;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.world.level.block.WallSkullBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * Deterministic, idempotent builder of the C10 fight arena in
 * {@code eclipse:ferryman_arena}: the ghost ship "remembered at its true size" — a
 * ~97×41 ring deck floating on the same black ocean, with the OLD 39×9 ship footprint
 * sunk two blocks into its center as the fight pit ({@code GhostShipBuilder} idempotence
 * law: fixed constants only, built once, stamped {@link ArenaState#ARENA_V1}, later
 * boots make zero block changes).
 *
 * <p><b>Geometry contracts (consumed by {@code ArenaFight} / {@code FerrymanEntity}):</b></p>
 * <ul>
 *   <li><b>Pit floor</b> at {@code waterline+3} — the SAME plane as the limbo deck, so
 *       every FerrymanEntity fight constant (hover height, sweep/slam Y bands, the P3
 *       sink volume over {@code GhostShipBuilder.halfWidthAt}) transfers unchanged. The
 *       two-block pit bowl contains the first two sink layers; layers 3–4 spill over
 *       the rim cosmetically (spilled water is flowing-only — no new sources can form —
 *       so it self-drains after the fight's footprint restore sweep).</li>
 *   <li><b>Ring deck</b> two blocks above the pit, reachable from the pit through four
 *       three-wide stepped exits (bow/stern/port/starboard).</li>
 *   <li><b>Lantern ring</b> — {@link #lanternRing}: eight soul campfires around the pit
 *       for the arena crew-phase beat ({@code FerrymanEntity} extinguishes/relights them
 *       via {@link #extinguishRing}/{@link #relightRing}; no ghost channel here — the
 *       arena P2 is a timed kneel, the ghosts watch from the spectator ship).</li>
 *   <li><b>Spectator ship</b> — a small railed vessel {@value #SPECTATOR_Z} blocks
 *       abeam (plan said 60; pushed to 80 so respawned NON-banned spectators sit outside
 *       the boss's 64-block fighter/participant ranges and can never stall the wipe
 *       check). {@link #spectatorSpawn} is the arrival cell;
 *       {@link #SPECTATOR_ZONE_MIN_Z} is the "no interference" invulnerability zone
 *       boundary used by {@code ArenaFight}.</li>
 * </ul>
 */
public final class ArenaBuilder {
    /** Arena half length along X (bow +X); total 97 ≈ the plan's "deck ~96". */
    public static final int ARENA_HALF_LENGTH = 48;
    /** Maximum arena half width along Z; total 41 ≈ the plan's "×40". */
    public static final int ARENA_HALF_WIDTH = 20;
    /** Z of the spectator ship's centerline (plan 60 → 80, see class javadoc). */
    public static final int SPECTATOR_Z = 80;
    /** Arena players at/beyond this Z are spectators (invulnerable, out of the fight). */
    public static final double SPECTATOR_ZONE_MIN_Z = 48.0D;

    /** Ring-deck rise above the pit floor (the pit bowl depth). */
    private static final int RING_RISE = 2;
    /** Lantern-ring offsets {x, z} on the ring deck (all clear of the pit + exits). */
    private static final int[][] LANTERN_RING = {
            {30, 4}, {-30, 4}, {30, -4}, {-30, -4}, {8, 16}, {-8, 16}, {8, -16}, {-8, -16}};
    /** Mast-pillar offsets {x, z} — the old masts, rearranged onto the ring deck. */
    private static final int[][] PILLARS = {{24, 12}, {24, -12}, {-24, 12}, {-24, -12}};
    private static final int PILLAR_HEIGHT = 12;

    // --- fight accent displays (BD-SHIP; fight-scoped, never persisted decor) ---
    /** Command tag on every fight accent display (tag sweeps cover UUID-list drift). */
    public static final String ACCENT_TAG = "eclipse_arena_accent";
    /** Golden angle (radians) — per-lantern phase offsets (never in lockstep). */
    private static final float GOLDEN_ANGLE = 2.3999632F;
    /** Ghost helm wheel hover cell — over the stern rise, behind the boss's anchor. */
    private static final int WHEEL_X = -17;
    private static final double WHEEL_HOVER = 7.0D;
    private static final float WHEEL_SCALE = 2.6F;
    /** Wheel turn rate (deg/t) + two incommensurate rate-noise sines (the living feel). */
    private static final double WHEEL_RATE_DEG = 0.5D;
    private static final double WHEEL_NOISE_A_DEG = 4.0D;
    private static final double WHEEL_NOISE_A_PERIOD = 90.0D;
    private static final double WHEEL_NOISE_B_DEG = 2.5D;
    private static final double WHEEL_NOISE_B_PERIOD = 217.0D;
    /** Witness lanterns: hover above the pillar crowns, bob amplitude, slow yaw. */
    private static final double LANTERN_HOVER = 2.4D;
    private static final double LANTERN_BOB = 0.35D;
    private static final double LANTERN_YAW_DEG = 0.2D;

    private ArenaBuilder() {}

    // ------------------------------------------------------------------ geometry

    /** Pit-floor plank Y — identical to the limbo deck plane ({@code waterline+3}). */
    public static int pitY(ServerLevel arena) {
        return GhostShipBuilder.waterlineY(arena) + 3;
    }

    /** Ring-deck plank Y ({@code pit + 2}). */
    public static int ringY(ServerLevel arena) {
        return pitY(arena) + RING_RISE;
    }

    /** The Ferryman's arena summon anchor (feet), C9's overload consumes it. */
    public static Vec3 summonAnchor(ServerLevel arena) {
        return new Vec3(dev.projecteclipse.eclipse.entity.boss.FerrymanEntity.STERN_X + 0.5D,
                pitY(arena) + 1, 0.5D);
    }

    /** Feet-level arrival cell on the spectator ship's deck. */
    public static Vec3 spectatorSpawn(ServerLevel arena) {
        return new Vec3(0.5D, ringY(arena) + 1, SPECTATOR_Z + 0.5D);
    }

    /** Deterministic fighter spread across the pit floor (bow side, clear of the boss). */
    public static Vec3 fighterSpot(ServerLevel arena, int index) {
        int x = 2 + 2 * (index % 3);
        int z = (index / 3 % 3) - 1;
        return new Vec3(x + 0.5D, pitY(arena) + 1, z + 0.5D);
    }

    /** Arena half width at the given X offset (elliptical bow/stern taper). */
    public static int arenaHalfWidthAt(int dx) {
        int d = Math.abs(dx);
        if (d <= 32) {
            return ARENA_HALF_WIDTH;
        }
        if (d <= 40) {
            return 16;
        }
        if (d <= 44) {
            return 10;
        }
        return 5;
    }

    /** Whether the column lies inside the sunken pit (the old ship footprint). */
    private static boolean inPit(int dx, int dz) {
        return Math.abs(dx) <= GhostShipBuilder.HALF_LENGTH
                && Math.abs(dz) <= GhostShipBuilder.halfWidthAt(dx);
    }

    /** The eight crew-phase lantern positions (campfire cells on the ring deck). */
    public static List<BlockPos> lanternRing(ServerLevel arena) {
        int y = ringY(arena) + 1;
        List<BlockPos> positions = new ArrayList<>(LANTERN_RING.length);
        for (int[] spot : LANTERN_RING) {
            positions.add(new BlockPos(spot[0], y, spot[1]));
        }
        return positions;
    }

    // ------------------------------------------------------------------ build

    /** Version-gated build entry: stamps {@link ArenaState#ARENA_V1} exactly once. */
    public static void ensureBuilt(ServerLevel arena) {
        ArenaState state = ArenaState.get(arena.getServer());
        if (state.arenaVersion() >= ArenaState.ARENA_V1) {
            return;
        }
        long start = System.nanoTime();
        build(arena);
        state.setArenaVersion(ArenaState.ARENA_V1);
        EclipseMod.LOGGER.info("Ferryman arena v1 built in {} (pit y={}, ring y={}, spectator ship at z={}) in {} ms",
                ArenaDimension.ARENA.location(), pitY(arena), ringY(arena), SPECTATOR_Z,
                (System.nanoTime() - start) / 1_000_000L);
    }

    /** Unconditional stamp — deterministic block loops, byte-identical on every run. */
    private static void build(ServerLevel arena) {
        int waterline = GhostShipBuilder.waterlineY(arena);
        int keelY = waterline - 2;
        int pitY = waterline + 3;
        int ringY = pitY + RING_RISE;

        hull(arena, keelY, pitY, ringY);
        pitExits(arena, pitY, ringY);
        kingPlank(arena, pitY);
        gunwale(arena, ringY);
        pillars(arena, ringY);
        lanterns(arena, ringY);
        bowStem(arena, waterline, ringY);
        spectatorShip(arena, waterline, ringY);
    }

    /**
     * Solid watertight mass: every arena column filled keel→surface (pit columns top out
     * at the pit floor, ring columns two higher — the difference IS the pit bowl wall).
     * Solid fill (no bilge) keeps the flat-generator ocean out without corner cases.
     */
    private static void hull(ServerLevel arena, int keelY, int pitY, int ringY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        BlockState rib = Blocks.DARK_OAK_LOG.defaultBlockState();
        BlockState wale = Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.X);
        int waterline = keelY + 2;
        for (int dx = -ARENA_HALF_LENGTH; dx <= ARENA_HALF_LENGTH; dx++) {
            int hw = arenaHalfWidthAt(dx);
            boolean ribColumn = Math.floorMod(dx, 6) == 0;
            for (int dz = -hw; dz <= hw; dz++) {
                int top = inPit(dx, dz) ? pitY : ringY;
                boolean sideWall = dz == -hw || dz == hw;
                for (int y = keelY; y <= top; y++) {
                    BlockState state = planks;
                    if (sideWall && y == waterline + 1) {
                        state = wale; // the ship's wale stripe, scaled up
                    } else if (sideWall && ribColumn) {
                        state = rib;
                    }
                    set(arena, dx, y, dz, state);
                }
                // Clear any generator/junk blocks above the deck (fresh dims are void
                // above the ocean, so this is a cheap belt-and-braces no-op there).
                for (int y = top + 1; y <= ringY + 2; y++) {
                    if (!arena.getBlockState(new BlockPos(dx, y, dz)).isAir()) {
                        set(arena, dx, y, dz, Blocks.AIR.defaultBlockState());
                    }
                }
            }
        }
    }

    /**
     * Four 3-wide stepped exits out of the pit bowl (bow/stern along X, port/starboard
     * along Z): two single-block steps a player can walk-jump; the sink water pours
     * through them at layer 1–2, which is deliberate theater.
     */
    private static void pitExits(ServerLevel arena, int pitY, int ringY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        for (int side = -1; side <= 1; side += 2) {
            for (int dz = -1; dz <= 1; dz++) {
                // Bow/stern exits at x = ±20..±21: step pit → +1 → ring.
                int x0 = (GhostShipBuilder.HALF_LENGTH + 1) * side;
                int x1 = (GhostShipBuilder.HALF_LENGTH + 2) * side;
                stepColumn(arena, x0, dz, pitY + 1, ringY, planks);
                stepColumn(arena, x1, dz, pitY + 2, ringY, planks);
            }
            for (int dx = -1; dx <= 1; dx++) {
                // Port/starboard exits at z = ±5..±6 (pit half width 4).
                int z0 = (GhostShipBuilder.HALF_WIDTH + 1) * side;
                int z1 = (GhostShipBuilder.HALF_WIDTH + 2) * side;
                stepColumn(arena, dx, z0, pitY + 1, ringY, planks);
                stepColumn(arena, dx, z1, pitY + 2, ringY, planks);
            }
        }
    }

    /** Rewrites one exit column: solid up to {@code topSolid}, air above to {@code ringY}. */
    private static void stepColumn(ServerLevel arena, int x, int z, int topSolid, int ringY,
            BlockState solid) {
        for (int y = topSolid - 1; y <= topSolid; y++) {
            set(arena, x, y, z, solid);
        }
        for (int y = topSolid + 1; y <= ringY; y++) {
            set(arena, x, y, z, Blocks.AIR.defaultBlockState());
        }
    }

    /** Stripped-log inlay down the pit's centerline — the old king plank, remembered. */
    private static void kingPlank(ServerLevel arena, int pitY) {
        BlockState wale = Blocks.STRIPPED_DARK_OAK_LOG.defaultBlockState()
                .setValue(BlockStateProperties.AXIS, Direction.Axis.X);
        for (int dx = -12; dx <= 13; dx++) {
            set(arena, dx, pitY, 0, wale);
        }
    }

    /** Sparse fence-post rim along the arena edge (every other cell; ends capped). */
    private static void gunwale(ServerLevel arena, int ringY) {
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        for (int dx = -ARENA_HALF_LENGTH; dx <= ARENA_HALF_LENGTH; dx++) {
            if (Math.floorMod(dx, 2) != 0) {
                continue;
            }
            int hw = arenaHalfWidthAt(dx);
            set(arena, dx, ringY + 1, hw, fence);
            set(arena, dx, ringY + 1, -hw, fence);
        }
        for (int dz = -5; dz <= 5; dz += 2) {
            set(arena, ARENA_HALF_LENGTH, ringY + 1, dz, fence);
            set(arena, -ARENA_HALF_LENGTH, ringY + 1, dz, fence);
        }
    }

    /** Four log pillars — the masts, rearranged — each crowned with a soul lantern. */
    private static void pillars(ServerLevel arena, int ringY) {
        BlockState mast = Blocks.DARK_OAK_LOG.defaultBlockState();
        for (int[] pillar : PILLARS) {
            for (int y = ringY + 1; y <= ringY + PILLAR_HEIGHT; y++) {
                set(arena, pillar[0], y, pillar[1], mast);
            }
            set(arena, pillar[0], ringY + PILLAR_HEIGHT + 1, pillar[1],
                    Blocks.SOUL_LANTERN.defaultBlockState());
        }
    }

    /** The eight crew-phase ring lanterns, born lit. */
    private static void lanterns(ServerLevel arena, int ringY) {
        for (BlockPos pos : lanternRing(arena)) {
            set(arena, pos.getX(), pos.getY(), pos.getZ(), litLantern());
        }
    }

    /** Bone stem + skull off the bow tip — the figurehead, remembered at scale. */
    private static void bowStem(ServerLevel arena, int waterline, int ringY) {
        BlockState bone = Blocks.BONE_BLOCK.defaultBlockState();
        for (int y = waterline + 1; y <= ringY + 1; y++) {
            set(arena, ARENA_HALF_LENGTH + 1, y, 0, bone);
        }
        set(arena, ARENA_HALF_LENGTH + 2, ringY + 1, 0, Blocks.SKELETON_WALL_SKULL.defaultBlockState()
                .setValue(WallSkullBlock.FACING, Direction.EAST));
    }

    /**
     * The spectator vessel: a 15×7 railed deck at ring height, {@value #SPECTATOR_Z}
     * blocks abeam — full fence perimeter (nobody drifts back into the fight by
     * accident), corner soul lanterns, and a bow stair pointing at the arena so the
     * fallen watch facing the fight.
     */
    private static void spectatorShip(ServerLevel arena, int waterline, int ringY) {
        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        for (int dx = -7; dx <= 7; dx++) {
            for (int dz = SPECTATOR_Z - 3; dz <= SPECTATOR_Z + 3; dz++) {
                for (int y = waterline - 1; y <= ringY; y++) {
                    set(arena, dx, y, dz, planks);
                }
                for (int y = ringY + 1; y <= ringY + 3; y++) {
                    if (!arena.getBlockState(new BlockPos(dx, y, dz)).isAir()) {
                        set(arena, dx, y, dz, Blocks.AIR.defaultBlockState());
                    }
                }
            }
        }
        for (int dx = -7; dx <= 7; dx++) {
            set(arena, dx, ringY + 1, SPECTATOR_Z - 3, fence);
            set(arena, dx, ringY + 1, SPECTATOR_Z + 3, fence);
        }
        for (int dz = SPECTATOR_Z - 3; dz <= SPECTATOR_Z + 3; dz++) {
            set(arena, -7, ringY + 1, dz, fence);
            set(arena, 7, ringY + 1, dz, fence);
        }
        for (int sideX = -1; sideX <= 1; sideX += 2) {
            set(arena, 6 * sideX, ringY + 2, SPECTATOR_Z - 2, Blocks.SOUL_LANTERN.defaultBlockState());
            set(arena, 6 * sideX, ringY + 2, SPECTATOR_Z + 2, Blocks.SOUL_LANTERN.defaultBlockState());
        }
        // Viewing step at the arena-facing rail (purely decorative).
        for (int dx = -2; dx <= 2; dx++) {
            set(arena, dx, ringY + 1, SPECTATOR_Z - 2, Blocks.DARK_OAK_STAIRS.defaultBlockState()
                    .setValue(StairBlock.FACING, Direction.SOUTH));
        }
    }

    // ------------------------------------------------------------------ crew-phase ring

    /**
     * Blows out {@code count} ring lanterns (the arena P2 opener). Missing/waterlogged
     * cells are re-placed dark first, so the beat always has fuel.
     */
    public static int extinguishRing(ServerLevel arena, int count) {
        int darkened = 0;
        for (BlockPos pos : lanternRing(arena)) {
            if (darkened >= count) {
                break;
            }
            BlockState state = arena.getBlockState(pos);
            if (!state.is(Blocks.SOUL_CAMPFIRE)) {
                arena.setBlockAndUpdate(pos, litLantern());
                state = arena.getBlockState(pos);
            }
            if (state.getValue(CampfireBlock.LIT)) {
                arena.setBlockAndUpdate(pos, state.setValue(CampfireBlock.LIT, false));
                arena.playSound(null, pos, SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 1.0F, 0.6F);
                arena.sendParticles(ParticleTypes.LARGE_SMOKE,
                        pos.getX() + 0.5D, pos.getY() + 0.6D, pos.getZ() + 0.5D, 12, 0.2D, 0.2D, 0.2D, 0.01D);
                darkened++;
            }
        }
        return darkened;
    }

    /** Restores the pristine lit ring (kneel beat end / fight restore). */
    public static int relightRing(ServerLevel arena) {
        int relit = 0;
        for (BlockPos pos : lanternRing(arena)) {
            if (!arena.getBlockState(pos).equals(litLantern())) {
                arena.setBlockAndUpdate(pos, litLantern());
                relit++;
            }
        }
        return relit;
    }

    private static BlockState litLantern() {
        return Blocks.SOUL_CAMPFIRE.defaultBlockState();
    }

    // ------------------------------------------------------------------ fight accents (BD-SHIP)

    /**
     * Spawns the fight's accent displays (sweep-then-spawn) into {@code liveIds} in fixed
     * index order: 0 = the ghost helm wheel (a dark-oak-trapdoor display, the credits-wheel
     * prop at 2.6 scale, hovering over the stern rise — the remembered ship still steers
     * itself through the fight); 1..4 = witness soul-lantern displays above the four
     * pillar crowns. UUIDs are recorded BEFORE {@code addFreshEntity} so the caller's
     * join-time stray guard (the {@code StructureFlightFx} doctrine) never eats a live
     * accent. All accents sit inside the fight's forced pit chunks.
     */
    public static void spawnAccentDisplays(ServerLevel arena, List<UUID> liveIds) {
        sweepAccentDisplays(arena);
        liveIds.clear();
        long gameTime = arena.getGameTime();
        spawnAccent(arena, liveIds, new Vec3(WHEEL_X + 0.5D, pitY(arena) + WHEEL_HOVER, 0.5D),
                Blocks.DARK_OAK_TRAPDOOR.defaultBlockState(), accentPose(0, gameTime));
        for (int i = 0; i < PILLARS.length; i++) {
            Vec3 pos = new Vec3(PILLARS[i][0], ringY(arena) + PILLAR_HEIGHT + 1 + LANTERN_HOVER,
                    PILLARS[i][1]);
            spawnAccent(arena, liveIds, pos, Blocks.SOUL_LANTERN.defaultBlockState(),
                    accentPose(1 + i, gameTime));
        }
    }

    /**
     * One interpolated 20t window per accent (the fight-watch stride IS the cadence —
     * SanctumOrbitals law: pose at {@code gameTime + 20}, stateless absolute clock, so a
     * lagged or re-pushed display glides back on track instead of snapping). Killed
     * accents are skipped (no respawn mid-fight; the next spawn's sweep reconciles).
     */
    public static void animateAccentDisplays(ServerLevel arena, List<UUID> liveIds) {
        long target = arena.getGameTime() + 20L;
        for (int index = 0; index < liveIds.size(); index++) {
            if (arena.getEntity(liveIds.get(index)) instanceof Display.BlockDisplay display) {
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(20);
                display.setTransformation(accentPose(index, target));
            }
        }
    }

    /** Discards every tagged accent display over the arena footprint (never the spectator ship). */
    public static void sweepAccentDisplays(ServerLevel arena) {
        AABB sweep = new AABB(-ARENA_HALF_LENGTH - 2.0D, 0.0D, -ARENA_HALF_WIDTH - 2.0D,
                ARENA_HALF_LENGTH + 2.0D, 128.0D, ARENA_HALF_WIDTH + 2.0D);
        List<Entity> strays = arena.getEntities((Entity) null, sweep,
                entity -> entity.getTags().contains(ACCENT_TAG));
        if (!strays.isEmpty()) {
            strays.forEach(Entity::discard);
            EclipseMod.LOGGER.info("Arena accents: {} display(s) swept", strays.size());
        }
    }

    private static void spawnAccent(ServerLevel arena, List<UUID> liveIds, Vec3 pos,
            BlockState state, Transformation pose) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, arena);
        display.setBlockState(state);
        display.moveTo(pos.x, pos.y, pos.z, 0.0F, 0.0F);
        display.addTag(ACCENT_TAG);
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(pose);
        liveIds.add(display.getUUID()); // before addFreshEntity: the join guard must know it
        arena.addFreshEntity(display);
    }

    /**
     * Absolute accent pose at {@code gameTime} (double math + {@code IEEEremainder} so
     * hour-long fights never accumulate float error). Index 0 — the helm wheel: upright
     * in the YZ plane, turning at {@value #WHEEL_RATE_DEG}°/t with two incommensurate
     * sine noise terms (drifts, hesitates, pulls — never a metronome; worst 20t window
     * ≈ 17°, far under the flattening threshold), spinning on its hub via the
     * credits-wheel center-pivot math. Index 1..4 — witness lanterns: ±{@value
     * #LANTERN_BOB} bob and a {@value #LANTERN_YAW_DEG}°/t yaw, golden-angle phase AND a
     * de-tuned bob period per index so two lanterns can never phase-lock.
     */
    private static Transformation accentPose(int index, long gameTime) {
        if (index == 0) {
            double degrees = WHEEL_RATE_DEG * gameTime
                    + WHEEL_NOISE_A_DEG * Math.sin(gameTime * (Math.PI * 2.0D / WHEEL_NOISE_A_PERIOD))
                    + WHEEL_NOISE_B_DEG * Math.sin(gameTime * (Math.PI * 2.0D / WHEEL_NOISE_B_PERIOD) + 1.7D);
            float spin = (float) Math.toRadians(Math.IEEEremainder(degrees, 360.0D));
            Quaternionf rotation = new Quaternionf()
                    .rotationZ((float) Math.toRadians(90.0D))
                    .rotateY(spin);
            Vector3f half = new Vector3f(WHEEL_SCALE * 0.5F, WHEEL_SCALE * 0.5F, WHEEL_SCALE * 0.5F);
            Vector3f translation = new Vector3f().sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(WHEEL_SCALE, WHEEL_SCALE, WHEEL_SCALE), new Quaternionf());
        }
        int lantern = index - 1;
        float phase = lantern * GOLDEN_ANGLE;
        double bobPeriod = 90.0D + 14.0D * lantern;
        float bob = (float) (LANTERN_BOB * Math.sin(gameTime * (Math.PI * 2.0D / bobPeriod) + phase));
        float yaw = (float) Math.toRadians(Math.IEEEremainder(
                LANTERN_YAW_DEG * gameTime + Math.toDegrees(phase), 360.0D));
        Quaternionf rotation = new Quaternionf().rotationY(yaw);
        Vector3f axis = new Vector3f(0.5F, 0.0F, 0.5F);
        Vector3f translation = new Vector3f(0.0F, bob, 0.0F)
                .add(axis).sub(rotation.transform(axis, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(1.0F, 1.0F, 1.0F), new Quaternionf());
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        // Force-load (GhostShipBuilder pattern): the build can outrun the loaded ring.
        level.getChunk(x >> 4, z >> 4);
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_ALL);
    }
}
