package dev.projecteclipse.eclipse.woah.resonance;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.WorldgenBlocks;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.TicketType;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/**
 * WOAH-04 §2.3/§3.1/§5 — the resonance-field site placer ({@code AsyncSitePlacer}
 * contract): SitePrep plateau → valley bowl carve → walkable crystal dressing →
 * altar dais → deterministic monolith layout (persisted as seeds) → display/interaction
 * spawn. Display spawning itself is budgeted through
 * {@link ResonanceFieldService#enqueueDisplaySpawns} (4/tick — no
 * {@code addFreshEntity} burst in one tick); everything else runs synchronously inside
 * {@code prepared.whenReady} exactly like {@code SkyLauncher.placeSite}.
 *
 * <p>All geometry is deterministic from {@code level.getSeed() ^ 0x5E50} plus the
 * per-monolith seeds persisted in {@link ResonanceFieldData} — a {@code /kill}'ed
 * display set rebuilds byte-identically (§3.5 self-healing law).</p>
 */
public final class ResonanceFieldBuilder {
    /** Frozen site + structure id (self-enqueued — deliberately NOT a DiscMapDefaults row). */
    public static final String SITE_ID = "eclipse:resonance_field";

    // --- entity tags (tag + radius query beats UUID bookkeeping, §3.5) ---
    /** Every monolith/altar display piece. */
    public static final String CRYSTAL_TAG = "eclipse_resonance_crystal";
    /** Per-crystal display grouping tag prefix ({@code eclipse_resonance_c_<idx>}). */
    public static final String CRYSTAL_IDX_PREFIX = "eclipse_resonance_c_";
    /** Glow-needle displays (the §5.5 brightness-pulse targets). */
    public static final String GLOW_TAG = "eclipse_resonance_glow";
    /** Interaction hitboxes on the monolith shafts. */
    public static final String HITBOX_TAG = "eclipse_resonance_hitbox";
    /** Crystal index carried on the hitbox ({@code eclipse_resonance_idx_<n>}). */
    public static final String HITBOX_IDX_PREFIX = "eclipse_resonance_idx_";
    /** The altar's interaction hitbox. */
    public static final String ALTAR_TAG = "eclipse_resonance_altar";
    /** Altar display composition pieces (§5.4). */
    public static final String ALTAR_DECO_TAG = "eclipse_resonance_altar_deco";
    /** The floating resonance core between the tines (TEACH brightness pulses). */
    public static final String ALTAR_CORE_TAG = "eclipse_resonance_altar_core";

    /** Full XZ extent (the pending rift is sized from it). */
    public static final int FOOTPRINT = 88;
    /** Valley half-extent from the anchor. */
    public static final int VALLEY_RADIUS = 44;
    /** Inner bowl radius — center −{@value #BOWL_DEPTH}, smoothstep to 0 here. */
    public static final int BOWL_RADIUS = 36;
    public static final int BOWL_DEPTH = 7;
    /** Flat rim wall height over r = {@value #BOWL_RADIUS}..{@value #VALLEY_RADIUS}. */
    private static final double RIM_HEIGHT = 2.0D;

    /** §3.1: view_range 4.0 × 64 = 256 blocks — past the 160 tracking horizon. */
    private static final float VIEW_RANGE = 4.0F;
    /** Core/shell brightness (§5.1). */
    private static final int BODY_BLOCK_LIGHT = 10;
    private static final int BODY_SKY_LIGHT = 15;

    /** Site-seed salt (§2.3 step 3). */
    private static final long SEED_SALT = 0x5E50L;

    /** Build-time chunk residency (the {@code ExpansionBorderFx.BOULDER_TICKET} pattern). */
    private static final TicketType<ChunkPos> BUILD_TICKET = TicketType.create(
            "eclipse_resonance_build", Comparator.comparingLong(ChunkPos::toLong), 600);

    /** §5.1 core palette, index²-weighted cumulative rolls. */
    private static final double[] CORE_CUMULATIVE = {0.55D, 0.85D, 0.95D, 1.0D};
    /** §5.1 shell palette cumulative rolls. */
    private static final double[] SHELL_CUMULATIVE = {0.60D, 0.85D, 1.0D};

    /**
     * One display layer to spawn: entity anchor at the owner's base center, ALL
     * geometry in the transformation (the "DisplayPlacerService law" from
     * {@code ExpansionBorderFx.poseOf}); the box is centred on its offset so the
     * lean rotates each slab about itself.
     */
    public record DisplaySpec(BlockState state, Vector3f offset, Vector3f size,
            Quaternionf rotation, int blockLight, int skyLight, boolean glow) {}

    /** One queued spawn job (crystalIdx −1 = altar composition). */
    public record PendingDisplay(BlockPos base, DisplaySpec spec, int crystalIdx) {}

    private ResonanceFieldBuilder() {}

    // ------------------------------------------------------------------ placement

    /** {@code AsyncSitePlacer} entry — registered by {@link ResonanceFieldService}. */
    public static void placeSite(ServerLevel level, PendingSite site, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        BlockPos anchor = site.anchor();
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                anchor.getX() - VALLEY_RADIUS, anchor.getZ() - VALLEY_RADIUS,
                anchor.getX() + VALLEY_RADIUS, anchor.getZ() + VALLEY_RADIUS, anchor);
        prepared.whenReady(() -> {
            int plateauY = prepared.plateauY();
            ticketValley(level, anchor);
            carveBowl(level, anchor, plateauY);
            RandomSource random = RandomSource.create(level.getSeed() ^ SEED_SALT);
            List<ResonanceFieldData.Monolith> monoliths = rollLayout(random, anchor, plateauY);
            BlockPos altarPos = new BlockPos(anchor.getX(), plateauY - BOWL_DEPTH, anchor.getZ());
            dressValley(level, random, anchor, plateauY, monoliths);
            buildDais(level, altarPos);
            SitePrep.touchBounds(prepared, anchor.getX() - VALLEY_RADIUS,
                    anchor.getZ() - VALLEY_RADIUS, anchor.getX() + VALLEY_RADIUS,
                    anchor.getZ() + VALLEY_RADIUS);
            SitePrep.finish(level, prepared);

            ResonanceFieldData data = ResonanceFieldData.get(level.getServer().overworld());
            data.setGeometry(new BlockPos(anchor.getX(), plateauY, anchor.getZ()),
                    altarPos, plateauY, monoliths);
            if (data.melody().length == 0) {
                data.rerollMelody(random.nextLong());
            }

            sweepFieldEntities(level, data);
            spawnInteractions(level, data);
            ResonanceFieldService.enqueueDisplaySpawns(computeDisplaySpecs(data));
            FxAnchors.set(ResonanceCues.RESONANCE_CENTER, level,
                    Vec3.atCenterOf(altarPos.above()));
            ResonanceFieldService.broadcastField(level, data);
            EclipseMod.LOGGER.info("ResonanceField: valley built at {} ({} monoliths, altar {})",
                    anchor.toShortString(), monoliths.size(), altarPos.toShortString());
            onComplete.run();
        }, onFailure);
    }

    /** Bowl profile: floor offset (blocks, ±) relative to the plateau at radius r. */
    public static double bowlOffset(double r) {
        if (r <= BOWL_RADIUS) {
            double t = r / BOWL_RADIUS;
            double smooth = t * t * (3.0D - 2.0D * t);
            return -BOWL_DEPTH * (1.0D - smooth);
        }
        if (r <= VALLEY_RADIUS) {
            double u = (r - BOWL_RADIUS) / (double) (VALLEY_RADIUS - BOWL_RADIUS);
            return RIM_HEIGHT * Math.sin(Math.PI * u);
        }
        return 0.0D;
    }

    /** Build-time chunk tickets over the ~6×6-chunk valley (TTL 600 — no permanent load). */
    private static void ticketValley(ServerLevel level, BlockPos anchor) {
        for (int cx = (anchor.getX() - VALLEY_RADIUS) >> 4;
                cx <= (anchor.getX() + VALLEY_RADIUS) >> 4; cx++) {
            for (int cz = (anchor.getZ() - VALLEY_RADIUS) >> 4;
                    cz <= (anchor.getZ() + VALLEY_RADIUS) >> 4; cz++) {
                ChunkPos pos = new ChunkPos(cx, cz);
                level.getChunkSource().addRegionTicket(BUILD_TICKET, pos, 2, pos);
                level.getChunk(cx, cz);
            }
        }
    }

    /**
     * §2.3 step 2: radial bowl — center −{@value #BOWL_DEPTH}, smoothstep to 0 at
     * r = {@value #BOWL_RADIUS}, then the flat +2 rim wall (reads as a kettle). The
     * whole valley floor gets the crystal-steppe palette mix (index²-weighted).
     */
    private static void carveBowl(ServerLevel level, BlockPos anchor, int plateauY) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -VALLEY_RADIUS; dx <= VALLEY_RADIUS; dx++) {
            for (int dz = -VALLEY_RADIUS; dz <= VALLEY_RADIUS; dz++) {
                double r = Math.sqrt(dx * dx + dz * dz);
                if (r > VALLEY_RADIUS) {
                    continue;
                }
                int x = anchor.getX() + dx;
                int z = anchor.getZ() + dz;
                int target = plateauY + (int) Math.round(bowlOffset(r));
                // Clear everything from the new floor up to just above the plateau/rim.
                for (int y = target + 1; y <= plateauY + (int) RIM_HEIGHT + 2; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isAir()) {
                        set(level, cursor, Blocks.AIR.defaultBlockState());
                    }
                }
                // Palette surface + 2 filler layers below (the bowl must read authored).
                set(level, cursor.set(x, target, z), floorBlock(x, target, z));
                for (int y = target - 1; y >= target - 2; y--) {
                    set(level, cursor.set(x, y, z), floorBlock(x, y, z));
                }
            }
        }
    }

    /**
     * §2.3 step 2 floor mix — deterministic per column (calcite 45 %, smooth basalt
     * 25 %, amethyst 12 %, tuff 10 %, luster crystal 8 %).
     */
    private static BlockState floorBlock(int x, int y, int z) {
        double roll = hash01(x, y, z);
        if (roll < 0.45D) {
            return Blocks.CALCITE.defaultBlockState();
        }
        if (roll < 0.70D) {
            return Blocks.SMOOTH_BASALT.defaultBlockState();
        }
        if (roll < 0.82D) {
            return Blocks.AMETHYST_BLOCK.defaultBlockState();
        }
        if (roll < 0.92D) {
            return Blocks.TUFF.defaultBlockState();
        }
        return WorldgenBlocks.LUSTER_CRYSTAL.get().defaultBlockState();
    }

    /**
     * §2.3 step 3: walkable REAL-block dressing — 12–16 ground clusters (budding
     * amethyst core, clusters on top, prism-sprout tufts around) plus 2–4 knee-high
     * climbable amethyst/luster spikes. Deterministic from the site random.
     */
    private static void dressValley(ServerLevel level, RandomSource random, BlockPos anchor,
            int plateauY, List<ResonanceFieldData.Monolith> monoliths) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int clusters = 12 + random.nextInt(5);
        for (int i = 0; i < clusters; i++) {
            BlockPos spot = pickDressingSpot(random, anchor, plateauY, monoliths);
            if (spot == null) {
                continue;
            }
            set(level, cursor.set(spot), Blocks.BUDDING_AMETHYST.defaultBlockState());
            set(level, cursor.set(spot.above()), Blocks.AMETHYST_CLUSTER.defaultBlockState());
            int extras = 2 + random.nextInt(5);
            for (int e = 0; e < extras; e++) {
                int ox = random.nextInt(3) - 1;
                int oz = random.nextInt(3) - 1;
                if (ox == 0 && oz == 0) {
                    continue;
                }
                BlockPos ground = floorAt(anchor, plateauY, spot.getX() + ox, spot.getZ() + oz);
                if (random.nextFloat() < 0.4F) {
                    set(level, cursor.set(ground), Blocks.AMETHYST_BLOCK.defaultBlockState());
                    if (random.nextBoolean()) {
                        set(level, cursor.set(ground.above()),
                                Blocks.AMETHYST_CLUSTER.defaultBlockState());
                    }
                } else {
                    set(level, cursor.set(ground.above()),
                            WorldgenBlocks.PRISM_SPROUTS.get().defaultBlockState());
                }
            }
        }
        int spikes = 2 + random.nextInt(3);
        for (int i = 0; i < spikes; i++) {
            BlockPos spot = pickDressingSpot(random, anchor, plateauY, monoliths);
            if (spot == null) {
                continue;
            }
            int spikeHeight = 2 + random.nextInt(3);
            for (int y = 0; y < spikeHeight; y++) {
                BlockState state = y == spikeHeight - 1 && random.nextBoolean()
                        ? WorldgenBlocks.LUSTER_CRYSTAL.get().defaultBlockState()
                        : Blocks.AMETHYST_BLOCK.defaultBlockState();
                set(level, cursor.set(spot.getX(), spot.getY() + 1 + y, spot.getZ()), state);
            }
        }
    }

    /** A dressing spot on the bowl floor clear of the dais (r > 6) and monolith feet. */
    @Nullable
    private static BlockPos pickDressingSpot(RandomSource random, BlockPos anchor, int plateauY,
            List<ResonanceFieldData.Monolith> monoliths) {
        for (int attempt = 0; attempt < 12; attempt++) {
            double angle = random.nextDouble() * Math.PI * 2.0D;
            double r = 7.0D + random.nextDouble() * 26.0D;
            int x = anchor.getX() + (int) Math.round(Math.cos(angle) * r);
            int z = anchor.getZ() + (int) Math.round(Math.sin(angle) * r);
            boolean clear = true;
            for (ResonanceFieldData.Monolith monolith : monoliths) {
                long mdx = x - monolith.basePos.getX();
                long mdz = z - monolith.basePos.getZ();
                if (mdx * mdx + mdz * mdz < 25L) {
                    clear = false;
                    break;
                }
            }
            if (clear) {
                return floorAt(anchor, plateauY, x, z);
            }
        }
        return null;
    }

    /** The bowl floor position of a column (pure function of the carve profile). */
    private static BlockPos floorAt(BlockPos anchor, int plateauY, int x, int z) {
        double r = Math.sqrt((double) (x - anchor.getX()) * (x - anchor.getX())
                + (double) (z - anchor.getZ()) * (z - anchor.getZ()));
        return new BlockPos(x, plateauY + (int) Math.round(bowlOffset(r)), z);
    }

    /** §2.3 step 4: the 5×5 dais — polished basalt disc, calcite rim, amethyst center. */
    private static void buildDais(ServerLevel level, BlockPos altarPos) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 > 6) {
                    continue;
                }
                BlockState floor;
                if (dx == 0 && dz == 0) {
                    floor = Blocks.AMETHYST_BLOCK.defaultBlockState();
                } else if (d2 >= 4) {
                    floor = Blocks.CALCITE.defaultBlockState();
                } else {
                    floor = Blocks.POLISHED_BASALT.defaultBlockState();
                }
                set(level, cursor.set(altarPos.getX() + dx, altarPos.getY(),
                        altarPos.getZ() + dz), floor);
                for (int dy = 1; dy <= 6; dy++) {
                    cursor.set(altarPos.getX() + dx, altarPos.getY() + dy, altarPos.getZ() + dz);
                    if (!level.getBlockState(cursor).isAir()) {
                        set(level, cursor, Blocks.AIR.defaultBlockState());
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ layout

    /**
     * §3.1: 9 monoliths on an irregular double ring — 5 on r ≈ 26 (angle jitter ±12°),
     * 4 on r ≈ 15; 2×L opposite each other on the outer ring (silhouette anchors),
     * 3×M outer, 4×S inner. Lowest tones on the tallest crystals (§6.1).
     */
    static List<ResonanceFieldData.Monolith> rollLayout(RandomSource random, BlockPos anchor,
            int plateauY) {
        record Slot(double angle, double radius, int sizeClass) {}
        List<Slot> slots = new ArrayList<>(ResonanceTones.TONE_COUNT);
        double outerPhase = random.nextDouble() * Math.PI * 2.0D;
        for (int i = 0; i < 5; i++) {
            double angle = outerPhase + i * (Math.PI * 2.0D / 5.0D)
                    + Math.toRadians(random.nextDouble() * 24.0D - 12.0D);
            double radius = 24.0D + random.nextDouble() * 4.0D;
            // L at outer slots 0 and 2 (~144° apart — the opposing silhouette anchors).
            int sizeClass = (i == 0 || i == 2) ? 2 : 1;
            slots.add(new Slot(angle, radius, sizeClass));
        }
        double innerPhase = outerPhase + Math.PI / 4.0D;
        for (int i = 0; i < 4; i++) {
            double angle = innerPhase + i * (Math.PI / 2.0D)
                    + Math.toRadians(random.nextDouble() * 24.0D - 12.0D);
            double radius = 13.5D + random.nextDouble() * 3.0D;
            slots.add(new Slot(angle, radius, 0));
        }

        record Rolled(int sizeClass, BlockPos base, float height, float girth,
                long tiltSeed, long layerSeed, double angle) {}
        List<Rolled> rolled = new ArrayList<>(slots.size());
        for (Slot slot : slots) {
            float height;
            float girth;
            switch (slot.sizeClass()) {
                case 2 -> {
                    height = 36.0F + random.nextFloat() * 4.0F;
                    girth = 4.8F + random.nextFloat() * 1.2F;
                }
                case 1 -> {
                    height = 26.0F + random.nextFloat() * 6.0F;
                    girth = 3.8F + random.nextFloat() * 1.0F;
                }
                default -> {
                    height = 20.0F + random.nextFloat() * 4.0F;
                    girth = 3.0F + random.nextFloat() * 0.8F;
                }
            }
            int x = anchor.getX() + (int) Math.round(Math.cos(slot.angle()) * slot.radius());
            int z = anchor.getZ() + (int) Math.round(Math.sin(slot.angle()) * slot.radius());
            double r = Math.sqrt((double) (x - anchor.getX()) * (x - anchor.getX())
                    + (double) (z - anchor.getZ()) * (z - anchor.getZ()));
            BlockPos base = new BlockPos(x, plateauY + (int) Math.round(bowlOffset(r)), z);
            rolled.add(new Rolled(slot.sizeClass(), base, height, girth,
                    random.nextLong(), random.nextLong(), slot.angle()));
        }

        // Tone assignment: tallest → tone 0 (lowest). Mass = depth, intuitively readable.
        List<Rolled> byHeight = new ArrayList<>(rolled);
        byHeight.sort(Comparator.comparingDouble(Rolled::height).reversed());
        int[] toneOf = new int[rolled.size()];
        for (int tone = 0; tone < byHeight.size(); tone++) {
            toneOf[rolled.indexOf(byHeight.get(tone))] = tone;
        }

        // Neighbor graph: per crystal the 2 nearest + the angular ring closure (~12 edges).
        Set<Long> edges = new LinkedHashSet<>();
        for (int i = 0; i < rolled.size(); i++) {
            List<Integer> others = new ArrayList<>();
            for (int j = 0; j < rolled.size(); j++) {
                if (j != i) {
                    others.add(j);
                }
            }
            int self = i;
            others.sort(Comparator.comparingDouble(j ->
                    rolled.get(self).base().distSqr(rolled.get(j).base())));
            edges.add(edgeKey(i, others.get(0)));
            edges.add(edgeKey(i, others.get(1)));
        }
        List<Integer> ring = new ArrayList<>();
        for (int i = 0; i < rolled.size(); i++) {
            ring.add(i);
        }
        ring.sort(Comparator.comparingDouble(i -> rolled.get(i).angle()));
        for (int i = 0; i < ring.size(); i++) {
            edges.add(edgeKey(ring.get(i), ring.get((i + 1) % ring.size())));
        }

        List<ResonanceFieldData.Monolith> monoliths = new ArrayList<>(rolled.size());
        for (int i = 0; i < rolled.size(); i++) {
            List<Integer> neighbors = new ArrayList<>(3);
            for (long key : edges) {
                int a = (int) (key >> 32);
                int b = (int) key;
                if (a == i) {
                    neighbors.add(b);
                } else if (b == i) {
                    neighbors.add(a);
                }
            }
            Rolled r = rolled.get(i);
            monoliths.add(new ResonanceFieldData.Monolith(r.sizeClass(), r.base(), r.height(),
                    r.girth(), r.tiltSeed(), r.layerSeed(), toneOf[i],
                    neighbors.stream().mapToInt(Integer::intValue).toArray()));
        }
        return monoliths;
    }

    private static long edgeKey(int a, int b) {
        int lo = Math.min(a, b);
        int hi = Math.max(a, b);
        return ((long) lo << 32) | (hi & 0xFFFFFFFFL);
    }

    /** Undirected edge list (index pairs) derived from the persisted neighbor arrays. */
    public static List<int[]> edgeList(List<ResonanceFieldData.Monolith> monoliths) {
        Set<Long> keys = new LinkedHashSet<>();
        for (int i = 0; i < monoliths.size(); i++) {
            for (int neighbor : monoliths.get(i).neighbors) {
                keys.add(edgeKey(i, neighbor));
            }
        }
        List<int[]> edges = new ArrayList<>(keys.size());
        for (long key : keys) {
            edges.add(new int[] {(int) (key >> 32), (int) key});
        }
        return edges;
    }

    // ------------------------------------------------------------------ display specs

    /** All display spawn jobs of the field (monolith layers + altar composition). */
    public static List<PendingDisplay> computeDisplaySpecs(ResonanceFieldData data) {
        List<PendingDisplay> jobs = new ArrayList<>(110);
        List<ResonanceFieldData.Monolith> monoliths = data.monoliths();
        for (int i = 0; i < monoliths.size(); i++) {
            ResonanceFieldData.Monolith monolith = monoliths.get(i);
            for (DisplaySpec spec : monolithSpecs(monolith)) {
                jobs.add(new PendingDisplay(monolith.basePos, spec, i));
            }
        }
        BlockPos altar = data.altarPos();
        if (altar != null) {
            for (DisplaySpec spec : altarSpecs()) {
                jobs.add(new PendingDisplay(altar.above(), spec, -1));
            }
        }
        return jobs;
    }

    /**
     * §5.2 layer set of one monolith, deterministic from its persisted seeds:
     * tapered core segments (each 4–10° yaw-stepped, XZ-jittered), tinted-glass facet
     * shells on golden-angle offsets tipped 3–8° outward, the full-bright glow
     * needle(s) and a half-buried basalt/calcite plinth skirt. A global 2–10° lean
     * quaternion multiplies onto every layer — the whole crystal leans, not just
     * the tip (§5.2).
     */
    static List<DisplaySpec> monolithSpecs(ResonanceFieldData.Monolith monolith) {
        RandomSource tiltRandom = RandomSource.create(monolith.tiltSeed);
        double tiltDeg = 2.0D + tiltRandom.nextDouble() * 8.0D;
        double tiltAxisAngle = tiltRandom.nextDouble() * Math.PI * 2.0D;
        Quaternionf tilt = new Quaternionf().rotationAxis(
                (float) Math.toRadians(tiltDeg),
                (float) Math.cos(tiltAxisAngle), 0.0F, (float) Math.sin(tiltAxisAngle));

        RandomSource random = RandomSource.create(monolith.layerSeed);
        float height = monolith.height;
        float girth = monolith.girth;
        int coreSegments;
        int shells;
        int glowNeedles;
        switch (monolith.sizeClass) {
            case 2 -> {
                coreSegments = 5;
                shells = 7;
                glowNeedles = 2;
            }
            case 1 -> {
                coreSegments = 4;
                shells = 5;
                glowNeedles = 1;
            }
            default -> {
                coreSegments = 3;
                shells = 4;
                glowNeedles = 1;
            }
        }

        List<DisplaySpec> specs = new ArrayList<>(coreSegments + shells + glowNeedles + 1);

        // Core segments: per-axis boxes, stacked with ~25 % overlap, tapering to the tip.
        float step = height / coreSegments;
        float yaw = random.nextFloat() * Mth.TWO_PI;
        for (int i = 0; i < coreSegments; i++) {
            float t = coreSegments == 1 ? 0.0F : i / (float) (coreSegments - 1);
            boolean tip = i == coreSegments - 1;
            float taper = tip ? 0.25F : 1.0F - 0.65F * t;
            float segHeight = step * 1.35F;
            float sx = girth * taper * (0.8F + random.nextFloat() * 0.4F);
            float sz = girth * taper * (0.8F + random.nextFloat() * 0.4F);
            yaw += Math.toRadians(4.0D + random.nextDouble() * 6.0D);
            float jitter = girth * 0.15F;
            Vector3f offset = new Vector3f(
                    (random.nextFloat() - 0.5F) * 2.0F * jitter,
                    step * (i + 0.5F),
                    (random.nextFloat() - 0.5F) * 2.0F * jitter);
            Quaternionf rotation = new Quaternionf(tilt).rotateY(yaw);
            if (tip) {
                // The tip leans a further 6° — the silhouette must never read as a
                // scaled cube (the boulder lesson).
                rotation.rotateX((float) Math.toRadians(6.0D));
            }
            specs.add(new DisplaySpec(coreBlock(random), tilt.transform(offset, new Vector3f()),
                    new Vector3f(sx, segHeight, sz), rotation,
                    BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        }

        // Facet shells: narrow long boxes on golden-angle offsets, tipped outward —
        // tinted glass mostly, so the bright core reads THROUGH the dark facets.
        float goldenPhase = random.nextFloat() * Mth.TWO_PI;
        for (int i = 0; i < shells; i++) {
            float angle = goldenPhase + i * 2.3999632F;
            float shellLength = height * (0.55F + random.nextFloat() * 0.20F);
            float sx = 0.5F + random.nextFloat() * 0.4F;
            float sz = 0.5F + random.nextFloat() * 0.4F;
            float radius = girth * 0.55F;
            Vector3f offset = new Vector3f(
                    Mth.cos(angle) * radius,
                    shellLength * 0.5F + height * 0.06F,
                    Mth.sin(angle) * radius);
            // Tip 3–8° outward: rotate about the horizontal axis perpendicular to the
            // radial direction (axis = (−sin, 0, cos) tips +Y toward (cos, sin)).
            float outward = (float) Math.toRadians(3.0D + random.nextDouble() * 5.0D);
            Quaternionf rotation = new Quaternionf(tilt)
                    .rotateAxis(outward, -Mth.sin(angle), 0.0F, Mth.cos(angle))
                    .rotateY(random.nextFloat() * Mth.TWO_PI);
            specs.add(new DisplaySpec(shellBlock(random), tilt.transform(offset, new Vector3f()),
                    new Vector3f(sx, shellLength, sz), rotation,
                    BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        }

        // Glow needle(s): the luminous violet core — full-bright override (§5.1; the
        // TextDisplay trick stays a fallback option if this ever reads too flat).
        for (int i = 0; i < glowNeedles; i++) {
            float centerT = glowNeedles == 1 ? 0.38F : (i == 0 ? 0.28F : 0.68F);
            float needleHeight = height * (glowNeedles == 1 ? 0.55F : 0.38F);
            Vector3f offset = new Vector3f(0.0F, height * centerT, 0.0F);
            Quaternionf rotation = new Quaternionf(tilt).rotateY(random.nextFloat() * Mth.TWO_PI);
            specs.add(new DisplaySpec(Blocks.AMETHYST_BLOCK.defaultBlockState(),
                    tilt.transform(offset, new Vector3f()),
                    new Vector3f(girth * 0.30F, needleHeight, girth * 0.30F), rotation,
                    15, 15, true));
        }

        // Plinth skirt, half in the ground — sells the rooting (the anti-"sky box"
        // lesson from the ExpansionBorderFx v1 postmortem). Grounded: no tilt.
        specs.add(new DisplaySpec(
                random.nextFloat() < 0.5F ? Blocks.SMOOTH_BASALT.defaultBlockState()
                        : Blocks.CALCITE.defaultBlockState(),
                new Vector3f(0.0F, 0.1F, 0.0F),
                new Vector3f(girth * 1.5F, 2.4F, girth * 1.5F),
                new Quaternionf().rotateY(random.nextFloat() * Mth.TWO_PI),
                BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        return specs;
    }

    private static BlockState coreBlock(RandomSource random) {
        double roll = random.nextDouble();
        if (roll < CORE_CUMULATIVE[0]) {
            return Blocks.AMETHYST_BLOCK.defaultBlockState();
        }
        if (roll < CORE_CUMULATIVE[1]) {
            return Blocks.TINTED_GLASS.defaultBlockState();
        }
        if (roll < CORE_CUMULATIVE[2]) {
            return Blocks.PURPLE_STAINED_GLASS.defaultBlockState();
        }
        return WorldgenBlocks.LUSTER_CRYSTAL.get().defaultBlockState();
    }

    private static BlockState shellBlock(RandomSource random) {
        double roll = random.nextDouble();
        if (roll < SHELL_CUMULATIVE[0]) {
            return Blocks.TINTED_GLASS.defaultBlockState();
        }
        if (roll < SHELL_CUMULATIVE[1]) {
            return Blocks.PURPLE_STAINED_GLASS.defaultBlockState();
        }
        return Blocks.AMETHYST_BLOCK.defaultBlockState();
    }

    /**
     * §5.4 tuning-fork altar: two polished-deepslate tines with a 3° V-spread, an
     * amethyst crossbar, the floating full-bright resonance core between the tines
     * and two tinted-glass cuffs — 6 displays, anchored one block above the dais
     * center.
     */
    static List<DisplaySpec> altarSpecs() {
        List<DisplaySpec> specs = new ArrayList<>(6);
        float spread = (float) Math.toRadians(3.0D);
        specs.add(new DisplaySpec(Blocks.POLISHED_DEEPSLATE.defaultBlockState(),
                new Vector3f(-0.9F, 2.6F, 0.0F), new Vector3f(0.6F, 4.5F, 0.6F),
                new Quaternionf().rotateZ(spread), BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        specs.add(new DisplaySpec(Blocks.POLISHED_DEEPSLATE.defaultBlockState(),
                new Vector3f(0.9F, 2.6F, 0.0F), new Vector3f(0.6F, 4.5F, 0.6F),
                new Quaternionf().rotateZ(-spread), BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        specs.add(new DisplaySpec(Blocks.AMETHYST_BLOCK.defaultBlockState(),
                new Vector3f(0.0F, 0.55F, 0.0F), new Vector3f(2.2F, 0.5F, 0.7F),
                new Quaternionf(), BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        // The floating resonance core (TEACH pulses ride its brightness, §5.5).
        specs.add(new DisplaySpec(Blocks.AMETHYST_BLOCK.defaultBlockState(),
                new Vector3f(0.0F, 3.2F, 0.0F), new Vector3f(0.5F, 0.5F, 0.5F),
                new Quaternionf().rotateY((float) Math.toRadians(45.0D)), 15, 15, true));
        specs.add(new DisplaySpec(Blocks.TINTED_GLASS.defaultBlockState(),
                new Vector3f(-0.9F, 1.6F, 0.0F), new Vector3f(0.9F, 0.4F, 0.9F),
                new Quaternionf(), BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        specs.add(new DisplaySpec(Blocks.TINTED_GLASS.defaultBlockState(),
                new Vector3f(0.9F, 1.6F, 0.0F), new Vector3f(0.9F, 0.4F, 0.9F),
                new Quaternionf(), BODY_BLOCK_LIGHT, BODY_SKY_LIGHT, false));
        return specs;
    }

    /** Displays per monolith size class + altar — the self-heal count check reads this. */
    public static int expectedDisplayCount(ResonanceFieldData data) {
        int count = data.altarPos() != null ? 6 : 0;
        for (ResonanceFieldData.Monolith monolith : data.monoliths()) {
            count += switch (monolith.sizeClass) {
                case 2 -> 15;
                case 1 -> 11;
                default -> 9;
            };
        }
        return count;
    }

    // ------------------------------------------------------------------ entity spawn

    /** Spawns one queued display job (called by the service's 4/tick budget loop). */
    static void spawnDisplay(ServerLevel level, PendingDisplay job) {
        DisplaySpec spec = job.spec();
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
        display.setBlockState(spec.state());
        display.moveTo(job.base().getX() + 0.5D, job.base().getY(), job.base().getZ() + 0.5D,
                0.0F, 0.0F);
        display.addTag(CRYSTAL_TAG);
        if (job.crystalIdx() >= 0) {
            display.addTag(CRYSTAL_IDX_PREFIX + job.crystalIdx());
        } else {
            display.addTag(ALTAR_DECO_TAG);
        }
        if (spec.glow()) {
            display.addTag(job.crystalIdx() >= 0 ? GLOW_TAG : ALTAR_CORE_TAG);
        }
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        // Box centred on its offset so the lean rotates the slab about itself.
        Vector3f half = new Vector3f(spec.size()).mul(0.5F).rotate(spec.rotation());
        Vector3f translation = new Vector3f(spec.offset()).sub(half);
        Transformation transformation = new Transformation(translation, spec.rotation(),
                new Vector3f(spec.size()), new Quaternionf());
        display.setTransformation(transformation);
        DisplayBrightnessFx.set(display, spec.blockLight(), spec.skyLight(), VIEW_RANGE);
        ResonanceFieldService.markSessionDisplay(display.getUUID());
        // W13-C3 tremor ledger: the wave choreographer restores THIS exact pose.
        ResonanceWaveFx.registerBase(display.getUUID(), transformation);
        level.addFreshEntity(display);
    }

    // ------------------------------------------------------------------ interactions

    /**
     * §3.3: one {@code minecraft:interaction} per monolith (girth-based width, height
     * capped at 14 — the shaft is the instrument, not the sky) + one on the altar.
     * NBT spawn — vanilla has no public width/height setters
     * ({@code SkyLauncher.spawnPadInteraction} precedent).
     */
    static void spawnInteractions(ServerLevel level, ResonanceFieldData data) {
        List<ResonanceFieldData.Monolith> monoliths = data.monoliths();
        for (int i = 0; i < monoliths.size(); i++) {
            ResonanceFieldData.Monolith monolith = monoliths.get(i);
            spawnInteraction(level, monolith.basePos, hitboxWidth(monolith),
                    hitboxHeight(monolith), HITBOX_TAG, HITBOX_IDX_PREFIX + i);
        }
        BlockPos altar = data.altarPos();
        if (altar != null) {
            spawnInteraction(level, altar.above(), 2.6F, 3.2F, ALTAR_TAG, null);
        }
    }

    static float hitboxWidth(ResonanceFieldData.Monolith monolith) {
        return Mth.clamp(monolith.girth + 1.5F, 3.5F, 6.5F);
    }

    static float hitboxHeight(ResonanceFieldData.Monolith monolith) {
        return Math.min(monolith.height * 0.55F, 14.0F);
    }

    static void spawnInteraction(ServerLevel level, BlockPos base, float width, float height,
            String tag, @Nullable String indexTag) {
        CompoundTag nbt = new CompoundTag();
        nbt.putString("id", "minecraft:interaction");
        nbt.putFloat("width", width);
        nbt.putFloat("height", height);
        nbt.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(base.getX() + 0.5D));
        pos.add(DoubleTag.valueOf(base.getY()));
        pos.add(DoubleTag.valueOf(base.getZ() + 0.5D));
        nbt.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(nbt, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("ResonanceField: could not create interaction entity at {}",
                    base);
            return;
        }
        interaction.addTag(tag);
        if (indexTag != null) {
            interaction.addTag(indexTag);
        }
        level.addFreshEntity(interaction);
    }

    /** Discards every tagged field entity in the valley (pre-build / rebuild sweep). */
    static void sweepFieldEntities(ServerLevel level, ResonanceFieldData data) {
        BlockPos anchor = data.anchor();
        if (anchor == null) {
            return;
        }
        List<Entity> pieces = level.getEntities((Entity) null,
                new net.minecraft.world.phys.AABB(anchor).inflate(VALLEY_RADIUS + 8.0D, 80.0D,
                        VALLEY_RADIUS + 8.0D),
                entity -> entity.getTags().contains(CRYSTAL_TAG)
                        || entity.getTags().contains(HITBOX_TAG)
                        || entity.getTags().contains(ALTAR_TAG));
        pieces.forEach(Entity::discard);
        ResonanceWaveFx.clearBases(); // W13-C3: the respawn re-registers every pose
    }

    /** Silent write; SitePrep.finish() handles the budgeted relight/resend. */
    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
    }

    /** Deterministic 0..1 column hash (the {@code FallbackBuilders.hash01} recipe). */
    private static double hash01(int x, int y, int z) {
        long hash = x * 3129871L ^ z * 116129781L ^ y;
        hash = hash * hash * 42317861L + hash * 11L;
        return ((hash >> 16) & 0xFFFFFFL) / (double) 0x1000000;
    }
}
