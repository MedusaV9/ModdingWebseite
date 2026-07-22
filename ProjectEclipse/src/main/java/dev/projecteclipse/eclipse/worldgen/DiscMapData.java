package dev.projecteclipse.eclipse.worldgen;

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import javax.imageio.ImageIO;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
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
            for (double bridge : this.bridgeDeg) {
                double delta = Math.abs(((angleDeg - bridge) % 360.0D + 540.0D) % 360.0D - 180.0D);
                if (delta <= this.bridgeHalfWidthDeg) {
                    return false;
                }
            }
            return true;
        }
    }

    /** A 2D map point (river polyline node, whisper well, …). */
    public record Point(int x, int z) {}

    /** Control data of one disc profile. {@code mountain}/{@code moat} may be null. */
    public record MapProfile(String centerBiome, int centerRadius, List<Sector> sectors,
            Mountain mountain, Moat moat, List<Landmark> landmarks, List<List<Point>> rivers,
            List<Point> whisperWells) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    private static volatile DiscMapData instance;

    private final MapProfile overworld;
    private final MapProfile nether;
    private final int[] heightmapOverride; // null = procedural surface

    private DiscMapData(MapProfile overworld, MapProfile nether, int[] heightmapOverride) {
        this.overworld = overworld;
        this.nether = nether;
        this.heightmapOverride = heightmapOverride;
    }

    /** The loaded map data (lazily reads {@code config/eclipse/disc_map.json} on first use). */
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
        double angle = Math.toDegrees(Math.atan2(z, x));
        if (angle < 0.0D) {
            angle += 360.0D;
        }
        for (Sector sector : map.sectors()) {
            if (sector.contains(angle)) {
                return sector.biome();
            }
        }
        return map.centerBiome();
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
        List<Sector> sectors = List.of(
                new Sector("minecraft:plains", 337.5D, 22.5D),
                new Sector("minecraft:desert", 22.5D, 67.5D),
                new Sector("minecraft:forest", 67.5D, 112.5D),
                new Sector("minecraft:jungle", 112.5D, 157.5D),
                new Sector("minecraft:savanna", 157.5D, 202.5D),
                new Sector("minecraft:swamp", 202.5D, 247.5D),
                new Sector("minecraft:snowy_slopes", 247.5D, 292.5D),
                new Sector("minecraft:dark_forest", 292.5D, 337.5D));
        // Peak in the snowy N sector, between the N and NE player discs, fully inside the
        // stage-1 fused disc (r ≈ 140 + radius 75 < 225).
        Mountain mountain = new Mountain(54, -129, 280, 75,
                "minecraft:snowy_slopes", "minecraft:grove", 96, 20, 14);
        List<Landmark> landmarks = List.of(
                new Landmark("eclipse:desert_temple", 184, 184, 16, 2),
                new Landmark("eclipse:jungle_temple", -233, 233, 16, 3),
                new Landmark("eclipse:village_plains", 390, 0, 40, 4),
                new Landmark("eclipse:stronghold_emergence", 54, -129, 24, 5));
        List<Point> wells = List.of(new Point(-60, 30), new Point(88, 40), new Point(-30, -70));
        return new MapProfile("minecraft:meadow", 40, sectors, mountain, null,
                landmarks, List.of(), wells);
    }

    private static MapProfile defaultNether() {
        List<Sector> sectors = List.of(
                new Sector("minecraft:nether_wastes", 0.0D, 72.0D),
                new Sector("minecraft:soul_sand_valley", 72.0D, 144.0D),
                new Sector("minecraft:basalt_deltas", 144.0D, 216.0D),
                new Sector("minecraft:crimson_forest", 216.0D, 288.0D),
                new Sector("minecraft:warped_forest", 288.0D, 360.0D));
        Moat moat = new Moat(50, 4, List.of(45.0D, 225.0D), 6.0D);
        List<Landmark> landmarks = List.of(
                new Landmark("eclipse:fortress_core", 0, 0, 40, 1));
        return new MapProfile("minecraft:nether_wastes", 30, sectors, null, moat,
                landmarks, List.of(), List.of());
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
