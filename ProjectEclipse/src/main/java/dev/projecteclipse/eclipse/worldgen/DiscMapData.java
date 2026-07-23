package dev.projecteclipse.eclipse.worldgen;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;
import javax.imageio.ImageIO;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.world.level.levelgen.XoroshiroRandomSource;
import net.minecraft.world.level.levelgen.synth.SimplexNoise;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Authored control data of the disc map: angular biome sector wedges, landmark list,
 * mountain (center, peak, core cavity), river polylines and whisper wells — loaded from
 * {@code config/eclipse/disc_map.json} (defaults written by code on first run, same
 * lazy-default pattern as {@code EclipseConfig}). This is the "painted map" abstraction:
 * the shipped layout is computed, but an optional heightmap PNG override
 * ({@link #loadHeightmapOverride(Path)}, {@code config/eclipse/disc_heightmap.png})
 * lets humans replace the procedural surface later without code changes.
 *
 * <p>All disc noise is seeded exclusively from {@link #ECLIPSE_SEED}; the vanilla world
 * seed is never consulted, so the map is identical in every world.</p>
 */
public final class DiscMapData {
    /** The fixed seed of the hand-prepared map. NEVER replace with the world seed. */
    public static final long ECLIPSE_SEED = 0xEC1195E0021L;

    /** Size (blocks per side) of the optional heightmap override PNG (1 px = 1 block). */
    public static final int HEIGHTMAP_SIZE = 1024;
    /** Surface Y encoded by a PNG red value of 0 (surfaceY = red + this offset). */
    public static final int HEIGHTMAP_Y_OFFSET = 40;

    /** Max angular wobble (degrees) applied to sector-wedge lookups so seams meander. */
    public static final double SECTOR_WOBBLE_DEG = 5.0D;
    /** Horizontal feature scale (blocks) of the seam wobble noise. */
    private static final double SECTOR_WOBBLE_SCALE = 64.0D;
    /** Blocks over which the wobble amplitude ramps from 0 (at the center cap) to full. */
    private static final double SECTOR_WOBBLE_TAPER = 60.0D;
    /** Angular half-width (degrees) of the relief blend band around each wedge boundary. */
    public static final double SECTOR_BLEND_DEG = 8.0D;
    /** Columns farther than this from every river bounding box short-circuit to "no river". */
    private static final double RIVER_QUERY_MARGIN = 16.0D;

    /**
     * Fixed-seed seam wobble field (salt 8 of the ECLIPSE_SEED noise family — salts 1..7
     * live in {@code DiscTerrainFunction}, 9+ are free). Never reseed from the world.
     */
    private static final SimplexNoise SECTOR_WOBBLE_NOISE =
            new SimplexNoise(new XoroshiroRandomSource(ECLIPSE_SEED + 8L * 0x9E3779B97F4A7C15L));

    /** One angular biome wedge; degrees measured from +X towards +Z, wrap-around allowed. */
    public record Sector(String biome, double startDeg, double endDeg) {
        /** Whether the normalised angle (0..360) falls inside this wedge. */
        public boolean contains(double angleDeg) {
            double start = norm(this.startDeg);
            double end = norm(this.endDeg);
            if (start <= end) {
                return angleDeg >= start && angleDeg < end;
            }
            return angleDeg >= start || angleDeg < end;
        }

        private static double norm(double deg) {
            double d = deg % 360.0D;
            return d < 0.0D ? d + 360.0D : d;
        }
    }

    /** A curated structure/set-piece site consumed by worker 5's StructureStamper. */
    public record Landmark(String id, int x, int z, int radius, int stage) {}

    /** The giant mountain: surface bump to {@code peakY} plus the sealed core cavity. */
    public record Mountain(int x, int z, int peakY, int radius, String coreBiome, String flankBiome,
            int caveY, int caveRadiusXz, int caveRadiusY) {}

    /** Nether lava moat ring with bridge gaps at the listed angles. */
    public record Moat(int radius, int halfWidth, List<Double> bridgeDeg, double bridgeHalfWidthDeg) {
        /** Whether the column at distance {@code r} / angle {@code angleDeg} is open moat channel. */
        public boolean contains(double r, double angleDeg) {
            if (Math.abs(r - this.radius) > this.halfWidth) {
                return false;
            }
            return !withinBridge(angleDeg, 0.0D);
        }

        /**
         * Whether {@code angleDeg} lies within {@code extraDeg} beyond the half-width of any
         * bridge causeway (wrap-safe). Consumers: the moat channel itself ({@code extra=0}),
         * the magma lip that must not cross the causeways, and the fortress-core bridge arms
         * that extend to the moat when they line up with a causeway.
         */
        public boolean withinBridge(double angleDeg, double extraDeg) {
            for (double bridge : this.bridgeDeg) {
                double delta = Math.abs(((angleDeg - bridge) % 360.0D + 540.0D) % 360.0D - 180.0D);
                if (delta <= this.bridgeHalfWidthDeg + extraDeg) {
                    return true;
                }
            }
            return false;
        }
    }

    /** A 2D map point (river polyline node, whisper well, …). */
    public record Point(int x, int z) {}

    /** Control data of one disc profile. {@code mountain}/{@code moat} may be null. */
    public record MapProfile(String centerBiome, int centerRadius, List<Sector> sectors,
            Mountain mountain, Moat moat, List<Landmark> landmarks, List<List<Point>> rivers,
            List<Point> whisperWells) {}

    /**
     * Relief blend towards the sector on the other side of the nearest (wobbled) wedge
     * boundary: {@code t} is the neighbour's lerp weight — 0.5 exactly on the boundary
     * (both sides meet at the average, so the surface is continuous), falling to 0 at
     * {@value #SECTOR_BLEND_DEG}° away. See {@link #sectorBlendAt}.
     */
    public record SectorBlend(String neighborBiome, double t) {}

    /**
     * One authored river polyline with a cached bounding box so the per-column distance
     * query ({@link #riverDistance}) can reject faraway columns with four comparisons.
     */
    private record River(int[] xs, int[] zs, int minX, int minZ, int maxX, int maxZ) {
        static River of(List<Point> points) {
            int[] xs = new int[points.size()];
            int[] zs = new int[points.size()];
            int minX = Integer.MAX_VALUE;
            int minZ = Integer.MAX_VALUE;
            int maxX = Integer.MIN_VALUE;
            int maxZ = Integer.MIN_VALUE;
            for (int i = 0; i < points.size(); i++) {
                xs[i] = points.get(i).x();
                zs[i] = points.get(i).z();
                minX = Math.min(minX, xs[i]);
                minZ = Math.min(minZ, zs[i]);
                maxX = Math.max(maxX, xs[i]);
                maxZ = Math.max(maxZ, zs[i]);
            }
            return new River(xs, zs, minX, minZ, maxX, maxZ);
        }

        /** Squared distance from (x, z) to the nearest point of any polyline segment. */
        double distanceSq(double x, double z) {
            double best = Double.MAX_VALUE;
            for (int i = 0; i < this.xs.length - 1; i++) {
                double ax = this.xs[i];
                double az = this.zs[i];
                double bx = this.xs[i + 1];
                double bz = this.zs[i + 1];
                double abx = bx - ax;
                double abz = bz - az;
                double lenSq = abx * abx + abz * abz;
                double t = lenSq <= 0.0D ? 0.0D
                        : Math.max(0.0D, Math.min(1.0D, ((x - ax) * abx + (z - az) * abz) / lenSq));
                double dx = x - (ax + abx * t);
                double dz = z - (az + abz * t);
                best = Math.min(best, dx * dx + dz * dz);
            }
            return best;
        }
    }

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    private static volatile DiscMapData instance;

    private final MapProfile overworld;
    private final MapProfile nether;
    private final int[] heightmapOverride; // null = procedural surface
    private final List<River> overworldRivers;
    private final List<River> netherRivers;

    private DiscMapData(MapProfile overworld, MapProfile nether, int[] heightmapOverride) {
        this.overworld = overworld;
        this.nether = nether;
        this.heightmapOverride = heightmapOverride;
        this.overworldRivers = buildRivers(overworld);
        this.netherRivers = buildRivers(nether);
    }

    private static List<River> buildRivers(MapProfile profile) {
        List<River> rivers = new ArrayList<>();
        for (List<Point> polyline : profile.rivers()) {
            if (polyline.size() >= 2) {
                rivers.add(River.of(polyline));
            }
        }
        return List.copyOf(rivers);
    }

    /** The loaded map data (frozen per-save when {@link FrozenParams} is active, else global config). */
    public static DiscMapData get() {
        DiscMapData loaded = instance;
        if (loaded == null) {
            synchronized (DiscMapData.class) {
                loaded = instance;
                if (loaded == null) {
                    loaded = load();
                    instance = loaded;
                }
            }
        }
        return loaded;
    }

    /** Installs a frozen per-save snapshot (D9). Called from {@link FrozenParams}. */
    public static void install(DiscMapData data) {
        instance = data;
    }

    /** Clears the JVM-global singleton on server stop so the next save reloads cleanly. */
    public static synchronized void clearInstance() {
        instance = null;
    }

    /** Loads global {@code disc_map.json} and returns the result without touching {@link #instance}. */
    public static DiscMapData reloadForSnapshot() {
        return load();
    }

    /** Serialises both profiles for embedding in {@code worldgen.json}. */
    public static JsonObject toJsonRoot(DiscMapData data) {
        JsonObject root = new JsonObject();
        root.add("overworld", profileToJson(data.overworld));
        root.add("nether", profileToJson(data.nether));
        return root;
    }

    /**
     * Parses a frozen {@code discMap} section. Missing keys fall back to built-in defaults
     * (or {@link DiscMapDefaults} when W1.4 lands — until then, {@link #defaultOverworld()}).
     */
    public static DiscMapData fromJsonRoot(JsonObject root) {
        MapProfile overworld = profileFromJson(root.getAsJsonObject("overworld"), defaultOverworld());
        MapProfile nether = profileFromJson(root.getAsJsonObject("nether"), defaultNether());
        Path dir = FMLPaths.CONFIGDIR.get().resolve("eclipse");
        int[] heightmap = loadHeightmapOverride(dir.resolve("disc_heightmap.png"));
        return new DiscMapData(overworld, nether, heightmap);
    }

    /** Re-reads {@code disc_map.json} (and the optional heightmap PNG) from disk. */
    public static synchronized void reload() {
        instance = load();
    }

    public MapProfile profile(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? this.nether : this.overworld;
    }

    /** Landmark sites of the given profile (worker 5 stamps them by stage). */
    public List<Landmark> landmarks(DiscProfile profile) {
        return profile(profile).landmarks();
    }

    /**
     * Biome id (e.g. {@code minecraft:desert}) of the column (x, z): mountain core/flank
     * first, then the center cap, then the angular wedge. Shared by
     * {@link DiscBiomeSource} and the terrain palette so blocks always match the biome.
     *
     * <p>The wedge lookup angle is perturbed by a fixed-seed simplex wobble of up to
     * ±{@value #SECTOR_WOBBLE_DEG}° ({@link #SECTOR_WOBBLE_NOISE}) so the radial seams
     * meander organically instead of being razor straight. The amplitude tapers to 0
     * towards the center cap (where a degree is only a fraction of a block anyway) and
     * every consumer goes through this method, so biomes, palettes and vegetation stay
     * consistent with each other.</p>
     */
    public String biomeAt(DiscProfile profile, double x, double z) {
        MapProfile map = profile(profile);
        Mountain mountain = map.mountain();
        if (mountain != null) {
            double dx = x - mountain.x();
            double dz = z - mountain.z();
            double dist = Math.sqrt(dx * dx + dz * dz);
            if (dist < mountain.radius() * 0.45D) {
                return mountain.coreBiome();
            }
            if (dist < mountain.radius() * 0.8D) {
                return mountain.flankBiome();
            }
        }
        double r = Math.sqrt(x * x + z * z);
        if (r < map.centerRadius()) {
            return map.centerBiome();
        }
        return DiscMapDefaults.ringBiome(profile,
                sectorBiomeAt(map, wobbledAngleDeg(map, x, z, r)), x, z);
    }

    /** Wedge lookup for an already-wobbled angle; falls back to the center biome in gaps. */
    private static String sectorBiomeAt(MapProfile map, double angleDeg) {
        for (Sector sector : map.sectors()) {
            if (sector.contains(angleDeg)) {
                return sector.biome();
            }
        }
        return map.centerBiome();
    }

    /**
     * The seam-wobbled, normalised (0..360) lookup angle of (x, z): raw atan2 angle plus
     * up to ±{@value #SECTOR_WOBBLE_DEG}° of fixed-seed simplex, tapered to 0 within
     * {@value #SECTOR_WOBBLE_TAPER} blocks of the center cap.
     */
    private static double wobbledAngleDeg(MapProfile map, double x, double z, double r) {
        double angle = Math.toDegrees(Math.atan2(z, x));
        double taper = Math.min(1.0D, Math.max(0.0D, (r - map.centerRadius()) / SECTOR_WOBBLE_TAPER));
        if (taper > 0.0D) {
            angle += SECTOR_WOBBLE_NOISE.getValue(x / SECTOR_WOBBLE_SCALE, z / SECTOR_WOBBLE_SCALE)
                    * SECTOR_WOBBLE_DEG * taper;
        }
        angle %= 360.0D;
        return angle < 0.0D ? angle + 360.0D : angle;
    }

    /**
     * Relief blend info of (x, z), or null when the column is not within
     * ±{@value #SECTOR_BLEND_DEG}° of a (wobbled) sector boundary — or when the wedge
     * lookup does not apply at all (mountain core/flank, center cap). The terrain
     * function lerps {@code surfaceOffset}/{@code surfaceAmp} towards the neighbour so
     * sector steps (e.g. swamp −5 → snowy +6) become slopes instead of instant cliffs.
     * Block palettes deliberately stay crisp; only the relief is blended.
     */
    @Nullable
    public SectorBlend sectorBlendAt(DiscProfile profile, double x, double z) {
        MapProfile map = profile(profile);
        Mountain mountain = map.mountain();
        if (mountain != null) {
            double mdx = x - mountain.x();
            double mdz = z - mountain.z();
            double flankR = mountain.radius() * 0.8D;
            if (mdx * mdx + mdz * mdz < flankR * flankR) {
                return null; // biomeAt bypasses the wedges here
            }
        }
        double r = Math.sqrt(x * x + z * z);
        if (r < map.centerRadius()) {
            return null;
        }
        double angle = wobbledAngleDeg(map, x, z, r);
        for (Sector sector : map.sectors()) {
            if (!sector.contains(angle)) {
                continue;
            }
            // Wrap-safe angular distances to the wedge's start/end boundary.
            double toStart = ((angle - sector.startDeg()) % 360.0D + 360.0D) % 360.0D;
            double toEnd = ((sector.endDeg() - angle) % 360.0D + 360.0D) % 360.0D;
            double d;
            double probeDeg;
            if (toStart <= toEnd) {
                d = toStart;
                probeDeg = sector.startDeg() - 0.5D;
            } else {
                d = toEnd;
                probeDeg = sector.endDeg() + 0.5D;
            }
            if (d >= SECTOR_BLEND_DEG) {
                return null;
            }
            double normProbe = ((probeDeg % 360.0D) + 360.0D) % 360.0D;
            String neighbor = sectorBiomeAt(map, normProbe);
            if (neighbor.equals(sector.biome())) {
                return null;
            }
            return new SectorBlend(neighbor, 0.5D * (1.0D - d / SECTOR_BLEND_DEG));
        }
        return null;
    }

    /**
     * Distance in blocks from (x, z) to the nearest authored river centerline of the
     * profile, or {@code Double.MAX_VALUE} when the column is farther than
     * {@value #RIVER_QUERY_MARGIN} blocks from every river's bounding box (cheap
     * early-out — callers only care about distances up to the channel + bank width).
     */
    public double riverDistance(DiscProfile profile, double x, double z) {
        List<River> rivers = profile == DiscProfile.NETHER ? this.netherRivers : this.overworldRivers;
        double best = Double.MAX_VALUE;
        for (River river : rivers) {
            if (x < river.minX() - RIVER_QUERY_MARGIN || x > river.maxX() + RIVER_QUERY_MARGIN
                    || z < river.minZ() - RIVER_QUERY_MARGIN || z > river.maxZ() + RIVER_QUERY_MARGIN) {
                continue;
            }
            best = Math.min(best, river.distanceSq(x, z));
        }
        return best == Double.MAX_VALUE ? best : Math.sqrt(best);
    }

    /**
     * Painted surface height override at (x, z), or {@code Integer.MIN_VALUE} when no
     * PNG override is installed or the column is outside the painted area.
     */
    public int surfaceOverrideAt(int x, int z) {
        int[] override = this.heightmapOverride;
        if (override == null) {
            return Integer.MIN_VALUE;
        }
        int px = x + HEIGHTMAP_SIZE / 2;
        int pz = z + HEIGHTMAP_SIZE / 2;
        if (px < 0 || pz < 0 || px >= HEIGHTMAP_SIZE || pz >= HEIGHTMAP_SIZE) {
            return Integer.MIN_VALUE;
        }
        return override[pz * HEIGHTMAP_SIZE + px];
    }

    /**
     * Optional-PNG hook: reads a {@value #HEIGHTMAP_SIZE}×{@value #HEIGHTMAP_SIZE}
     * heightmap where pixel (0,0) is world (−512,−512), 1 px = 1 block and
     * {@code surfaceY = red + }{@value #HEIGHTMAP_Y_OFFSET}. Returns null when the file
     * is absent or unreadable (procedural surface is used instead).
     */
    public static int[] loadHeightmapOverride(Path pngFile) {
        if (pngFile == null || !Files.isRegularFile(pngFile)) {
            return null;
        }
        try {
            BufferedImage image = ImageIO.read(pngFile.toFile());
            if (image == null || image.getWidth() != HEIGHTMAP_SIZE || image.getHeight() != HEIGHTMAP_SIZE) {
                EclipseMod.LOGGER.warn("Ignoring disc heightmap override {}: expected a {}x{} PNG",
                        pngFile, HEIGHTMAP_SIZE, HEIGHTMAP_SIZE);
                return null;
            }
            int[] heights = new int[HEIGHTMAP_SIZE * HEIGHTMAP_SIZE];
            for (int pz = 0; pz < HEIGHTMAP_SIZE; pz++) {
                for (int px = 0; px < HEIGHTMAP_SIZE; px++) {
                    int red = (image.getRGB(px, pz) >> 16) & 0xFF;
                    heights[pz * HEIGHTMAP_SIZE + px] = red + HEIGHTMAP_Y_OFFSET;
                }
            }
            EclipseMod.LOGGER.info("Loaded painted disc heightmap override from {}", pngFile);
            return heights;
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to read disc heightmap override {}", pngFile, e);
            return null;
        }
    }

    // --- loading ---

    private static DiscMapData load() {
        Path dir = FMLPaths.CONFIGDIR.get().resolve("eclipse");
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }
        Path file = dir.resolve("disc_map.json");
        MapProfile overworld = defaultOverworld();
        MapProfile nether = defaultNether();
        if (!Files.exists(file)) {
            try {
                JsonObject root = new JsonObject();
                root.addProperty("_comment", "Authored control data of the Eclipse disc map "
                        + "(biome sector wedges, landmarks, mountain, rivers, whisper wells). "
                        + "The terrain itself is procedural from the fixed ECLIPSE_SEED; drop a "
                        + HEIGHTMAP_SIZE + "x" + HEIGHTMAP_SIZE + " disc_heightmap.png next to this "
                        + "file (surfaceY = red + " + HEIGHTMAP_Y_OFFSET + ") to paint surface heights.");
                root.add("overworld", profileToJson(overworld));
                root.add("nether", profileToJson(nether));
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        } else {
            try {
                JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8))
                        .getAsJsonObject();
                overworld = profileFromJson(root.getAsJsonObject("overworld"), defaultOverworld());
                nether = profileFromJson(root.getAsJsonObject("nether"), defaultNether());
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error("Failed to read config {}; using built-in defaults", file, e);
            }
        }
        int[] heightmap = loadHeightmapOverride(dir.resolve("disc_heightmap.png"));
        return new DiscMapData(overworld, nether, heightmap);
    }

    private static MapProfile defaultOverworld() {
        return DiscMapDefaults.overworldDefaults();
    }

    private static MapProfile defaultNether() {
        return DiscMapDefaults.netherDefaults();
    }

    // --- JSON ---

    private static JsonObject profileToJson(MapProfile profile) {
        JsonObject obj = new JsonObject();
        obj.addProperty("centerBiome", profile.centerBiome());
        obj.addProperty("centerRadius", profile.centerRadius());
        JsonArray sectors = new JsonArray();
        for (Sector sector : profile.sectors()) {
            JsonObject s = new JsonObject();
            s.addProperty("biome", sector.biome());
            s.addProperty("startDeg", sector.startDeg());
            s.addProperty("endDeg", sector.endDeg());
            sectors.add(s);
        }
        obj.add("sectors", sectors);
        if (profile.mountain() != null) {
            Mountain m = profile.mountain();
            JsonObject mo = new JsonObject();
            mo.addProperty("x", m.x());
            mo.addProperty("z", m.z());
            mo.addProperty("peakY", m.peakY());
            mo.addProperty("radius", m.radius());
            mo.addProperty("coreBiome", m.coreBiome());
            mo.addProperty("flankBiome", m.flankBiome());
            mo.addProperty("caveY", m.caveY());
            mo.addProperty("caveRadiusXz", m.caveRadiusXz());
            mo.addProperty("caveRadiusY", m.caveRadiusY());
            obj.add("mountain", mo);
        }
        if (profile.moat() != null) {
            Moat moat = profile.moat();
            JsonObject mo = new JsonObject();
            mo.addProperty("radius", moat.radius());
            mo.addProperty("halfWidth", moat.halfWidth());
            JsonArray bridges = new JsonArray();
            moat.bridgeDeg().forEach(bridges::add);
            mo.add("bridgeDeg", bridges);
            mo.addProperty("bridgeHalfWidthDeg", moat.bridgeHalfWidthDeg());
            obj.add("moat", mo);
        }
        JsonArray landmarks = new JsonArray();
        for (Landmark landmark : profile.landmarks()) {
            JsonObject l = new JsonObject();
            l.addProperty("id", landmark.id());
            l.addProperty("x", landmark.x());
            l.addProperty("z", landmark.z());
            l.addProperty("radius", landmark.radius());
            l.addProperty("stage", landmark.stage());
            landmarks.add(l);
        }
        obj.add("landmarks", landmarks);
        JsonArray rivers = new JsonArray();
        for (List<Point> polyline : profile.rivers()) {
            rivers.add(pointsToJson(polyline));
        }
        obj.add("rivers", rivers);
        obj.add("whisperWells", pointsToJson(profile.whisperWells()));
        return obj;
    }

    private static JsonArray pointsToJson(List<Point> points) {
        JsonArray array = new JsonArray();
        for (Point point : points) {
            JsonObject p = new JsonObject();
            p.addProperty("x", point.x());
            p.addProperty("z", point.z());
            array.add(p);
        }
        return array;
    }

    private static MapProfile profileFromJson(JsonObject obj, MapProfile defaults) {
        if (obj == null) {
            return defaults;
        }
        String centerBiome = obj.has("centerBiome") ? obj.get("centerBiome").getAsString() : defaults.centerBiome();
        int centerRadius = obj.has("centerRadius") ? obj.get("centerRadius").getAsInt() : defaults.centerRadius();
        List<Sector> sectors = defaults.sectors();
        if (obj.has("sectors")) {
            List<Sector> parsed = new ArrayList<>();
            for (JsonElement element : obj.getAsJsonArray("sectors")) {
                JsonObject s = element.getAsJsonObject();
                parsed.add(new Sector(s.get("biome").getAsString(),
                        s.get("startDeg").getAsDouble(), s.get("endDeg").getAsDouble()));
            }
            if (!parsed.isEmpty()) {
                sectors = List.copyOf(parsed);
            }
        }
        Mountain mountain = defaults.mountain();
        if (obj.has("mountain")) {
            JsonObject m = obj.getAsJsonObject("mountain");
            mountain = new Mountain(m.get("x").getAsInt(), m.get("z").getAsInt(),
                    m.get("peakY").getAsInt(), m.get("radius").getAsInt(),
                    m.get("coreBiome").getAsString(), m.get("flankBiome").getAsString(),
                    m.get("caveY").getAsInt(), m.get("caveRadiusXz").getAsInt(),
                    m.get("caveRadiusY").getAsInt());
        }
        Moat moat = defaults.moat();
        if (obj.has("moat")) {
            JsonObject m = obj.getAsJsonObject("moat");
            List<Double> bridges = new ArrayList<>();
            m.getAsJsonArray("bridgeDeg").forEach(e -> bridges.add(e.getAsDouble()));
            moat = new Moat(m.get("radius").getAsInt(), m.get("halfWidth").getAsInt(),
                    List.copyOf(bridges), m.get("bridgeHalfWidthDeg").getAsDouble());
        }
        List<Landmark> landmarks = defaults.landmarks();
        if (obj.has("landmarks")) {
            List<Landmark> parsed = new ArrayList<>();
            for (JsonElement element : obj.getAsJsonArray("landmarks")) {
                JsonObject l = element.getAsJsonObject();
                parsed.add(new Landmark(l.get("id").getAsString(), l.get("x").getAsInt(),
                        l.get("z").getAsInt(), l.get("radius").getAsInt(), l.get("stage").getAsInt()));
            }
            landmarks = List.copyOf(parsed);
        }
        List<List<Point>> rivers = defaults.rivers();
        if (obj.has("rivers")) {
            List<List<Point>> parsed = new ArrayList<>();
            for (JsonElement element : obj.getAsJsonArray("rivers")) {
                parsed.add(pointsFromJson(element.getAsJsonArray()));
            }
            rivers = List.copyOf(parsed);
        }
        List<Point> wells = obj.has("whisperWells")
                ? pointsFromJson(obj.getAsJsonArray("whisperWells"))
                : defaults.whisperWells();
        return new MapProfile(centerBiome, centerRadius, sectors, mountain, moat, landmarks, rivers, wells);
    }

    private static List<Point> pointsFromJson(JsonArray array) {
        List<Point> points = new ArrayList<>();
        for (JsonElement element : array) {
            JsonObject p = element.getAsJsonObject();
            points.add(new Point(p.get("x").getAsInt(), p.get("z").getAsInt()));
        }
        return List.copyOf(points);
    }
}
