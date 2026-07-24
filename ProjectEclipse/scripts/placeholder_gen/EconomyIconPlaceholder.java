import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;

/**
 * Programmer-art 16×16 icons + item models for the W13 shard-economy rewards:
 * the Vitae Shard, the two umbral tools, and the two pointer compasses (Compass of the
 * Watcher, Grave Dowser) with their 32 needle frames. The compass frames replicate the
 * vanilla compass override scheme: the base model shows frame 16 (needle up) and the
 * {@code minecraft:angle} predicate (registered client-side in {@code EclipseClient})
 * selects one of 32 frame models — frame k's needle is rotated clockwise by
 * {@code (k-16) * 11.25°} from straight up, matching vanilla's angle→frame mapping.
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/EconomyIconPlaceholder.java}
 */
public class EconomyIconPlaceholder {
    private static final Path TEX_DIR = Path.of("src/main/resources/assets/eclipse/textures/item");
    private static final Path MODEL_DIR = Path.of("src/main/resources/assets/eclipse/models/item");

    public static void main(String[] args) throws IOException {
        Files.createDirectories(TEX_DIR);
        Files.createDirectories(MODEL_DIR);
        writeVitaeShard();
        writeUmbralPick();
        writeUmbralBlade();
        // Watcher compass: night-violet dial, gold needle (the eclipse palette).
        writeCompassFrames("compass_of_watcher", 0xFF241736, 0xFF0F0A18, 0xFF6C5A8E,
                0xFFF2C14E, 0xFFCFC6E4);
        // Grave dowser: bone-grey dial, soul-teal needle (the limbo palette).
        writeCompassFrames("grave_dowser", 0xFF3A3F3C, 0xFF14201B, 0xFF6E7A72,
                0xFF8FF2DE, 0xFFB8BDB4);
        writeStaticModel("vitae_shard", "minecraft:item/generated");
        writeStaticModel("umbral_pick", "minecraft:item/handheld");
        writeStaticModel("umbral_blade", "minecraft:item/handheld");
        writeCompassModels("compass_of_watcher");
        writeCompassModels("grave_dowser");
        System.out.println("Generated 3 static icons + 2x32 compass frames + models in "
                + TEX_DIR + " / " + MODEL_DIR);
    }

    // --- vitae shard: a blood-red crystalline sliver with a bright living core ---

    private static void writeVitaeShard() throws IOException {
        BufferedImage img = newImage();
        int edge = 0xFF7A1626;
        int body = 0xFFC22B44;
        int core = 0xFFFF7A8C;
        int glow = 0xFFFFD2D9;
        // Elongated shard from bottom-left to top-right.
        int[][] outline = {
                {4, 13}, {5, 12}, {5, 11}, {6, 10}, {6, 9}, {7, 8}, {7, 7}, {8, 6}, {8, 5},
                {9, 4}, {9, 3}, {10, 2}, {11, 3}, {11, 4}, {10, 5}, {10, 6}, {9, 7}, {9, 8},
                {8, 9}, {8, 10}, {7, 11}, {7, 12}, {6, 13}, {5, 14},
        };
        for (int[] p : outline) {
            img.setRGB(p[0], p[1], edge);
        }
        int[][] fill = {
                {5, 13}, {6, 11}, {6, 12}, {7, 9}, {7, 10}, {8, 7}, {8, 8}, {9, 5}, {9, 6}, {10, 3}, {10, 4},
        };
        for (int[] p : fill) {
            img.setRGB(p[0], p[1], body);
        }
        img.setRGB(8, 8, core);
        img.setRGB(7, 9, core);
        img.setRGB(9, 6, core);
        img.setRGB(8, 7, glow);
        ImageIO.write(img, "png", TEX_DIR.resolve("vitae_shard.png").toFile());
    }

    // --- umbral pick: obsidian head with violet shard tips on a dark haft ---

    private static void writeUmbralPick() throws IOException {
        BufferedImage img = newImage();
        int head = 0xFF181224;
        int headEdge = 0xFF0E0A16;
        int tip = 0xFFC88AFF;
        int haft = 0xFF2E2338;
        int haftDark = 0xFF1C1524;
        // Curved pick head across the top-right (a shallow arc).
        int[][] headPixels = {
                {5, 3}, {6, 2}, {7, 2}, {8, 2}, {9, 2}, {10, 3}, {11, 3}, {12, 4}, {13, 5},
                {6, 3}, {7, 3}, {8, 3}, {9, 3}, {10, 4}, {11, 4}, {12, 5}, {13, 6},
        };
        for (int[] p : headPixels) {
            img.setRGB(p[0], p[1], head);
        }
        img.setRGB(5, 4, headEdge);
        img.setRGB(12, 6, headEdge);
        // Violet shard tips at both pick points.
        img.setRGB(4, 3, tip);
        img.setRGB(4, 4, tip);
        img.setRGB(13, 7, tip);
        img.setRGB(14, 6, tip);
        // Diagonal haft down-left.
        for (int i = 0; i < 9; i++) {
            img.setRGB(8 - i + 2, 5 + i, haft);
            if (8 - i + 1 >= 0) {
                img.setRGB(8 - i + 1, 5 + i, haftDark);
            }
        }
        ImageIO.write(img, "png", TEX_DIR.resolve("umbral_pick.png").toFile());
    }

    // --- umbral blade: black-glass sword with a violet edge glint ---

    private static void writeUmbralBlade() throws IOException {
        BufferedImage img = newImage();
        int blade = 0xFF181224;
        int glint = 0xFFC88AFF;
        int guard = 0xFF6C5A8E;
        int grip = 0xFF2E2338;
        // Diagonal blade from top-right to center.
        for (int i = 0; i < 8; i++) {
            img.setRGB(13 - i, 2 + i, blade);
            img.setRGB(12 - i, 2 + i, i % 2 == 0 ? glint : blade);
        }
        img.setRGB(14, 1, glint);
        // Cross guard.
        img.setRGB(5, 9, guard);
        img.setRGB(6, 10, guard);
        img.setRGB(7, 9, guard);
        img.setRGB(6, 8, guard);
        // Grip to bottom-left with a violet pommel.
        img.setRGB(4, 11, grip);
        img.setRGB(3, 12, grip);
        img.setRGB(2, 13, glint);
        ImageIO.write(img, "png", TEX_DIR.resolve("umbral_blade.png").toFile());
    }

    // --- compass frames: shared dial, needle rotated per frame ---

    private static void writeCompassFrames(String name, int dial, int rim, int tick,
            int needleHead, int needleTail) throws IOException {
        for (int frame = 0; frame < 32; frame++) {
            BufferedImage img = newImage();
            // Dial: filled circle r=7 with a darker rim.
            for (int y = 0; y < 16; y++) {
                for (int x = 0; x < 16; x++) {
                    double d = Math.hypot(x - 7.5, y - 7.5);
                    if (d <= 7.0) {
                        img.setRGB(x, y, d >= 6.0 ? rim : dial);
                    }
                }
            }
            // Cardinal ticks.
            img.setRGB(7, 2, tick);
            img.setRGB(8, 2, tick);
            img.setRGB(7, 13, tick);
            img.setRGB(8, 13, tick);
            img.setRGB(2, 7, tick);
            img.setRGB(2, 8, tick);
            img.setRGB(13, 7, tick);
            img.setRGB(13, 8, tick);
            // Needle: frame k = up rotated clockwise by (k-16)*11.25° (vanilla frame order).
            double phi = Math.toRadians(((frame - 16 + 32) % 32) * 11.25D);
            double dx = Math.sin(phi);
            double dy = -Math.cos(phi);
            plotNeedle(img, dx, dy, 5.0D, needleHead);
            plotNeedle(img, -dx, -dy, 3.0D, needleTail);
            img.setRGB(7, 7, needleHead);
            img.setRGB(8, 8, needleTail);
            ImageIO.write(img, "png",
                    TEX_DIR.resolve(String.format("%s_%02d.png", name, frame)).toFile());
        }
    }

    /** Plots a needle ray from the dial center outward (simple stepped line, hard pixels). */
    private static void plotNeedle(BufferedImage img, double dx, double dy, double length, int color) {
        for (double t = 0.5D; t <= length; t += 0.5D) {
            int x = (int) Math.round(7.5D + dx * t);
            int y = (int) Math.round(7.5D + dy * t);
            if (x >= 0 && x < 16 && y >= 0 && y < 16) {
                img.setRGB(x, y, color);
            }
        }
    }

    // --- item models ---

    private static void writeStaticModel(String name, String parent) throws IOException {
        String json = "{\n"
                + "  \"parent\": \"" + parent + "\",\n"
                + "  \"textures\": {\n"
                + "    \"layer0\": \"eclipse:item/" + name + "\"\n"
                + "  }\n"
                + "}\n";
        Files.writeString(MODEL_DIR.resolve(name + ".json"), json);
    }

    /**
     * Base model (shows frame 16, needle up) + vanilla-style {@code angle} overrides + the
     * 32 frame models. The override thresholds replicate {@code minecraft:item/compass}.
     */
    private static void writeCompassModels(String name) throws IOException {
        for (int frame = 0; frame < 32; frame++) {
            String frameName = String.format("%s_%02d", name, frame);
            String json = "{\n"
                    + "  \"parent\": \"minecraft:item/generated\",\n"
                    + "  \"textures\": {\n"
                    + "    \"layer0\": \"eclipse:item/" + frameName + "\"\n"
                    + "  }\n"
                    + "}\n";
            Files.writeString(MODEL_DIR.resolve(frameName + ".json"), json);
        }
        StringBuilder base = new StringBuilder();
        base.append("{\n");
        base.append("  \"parent\": \"minecraft:item/generated\",\n");
        base.append("  \"textures\": {\n");
        base.append(String.format("    \"layer0\": \"eclipse:item/%s_16\"\n", name));
        base.append("  },\n");
        base.append("  \"overrides\": [\n");
        base.append(String.format("    { \"predicate\": { \"angle\": 0.000000 }, \"model\": \"eclipse:item/%s\" },%n", name));
        for (int j = 0; j <= 30; j++) {
            double threshold = (j + 0.5D) / 32.0D;
            int frame = (17 + j) % 32;
            base.append(String.format("    { \"predicate\": { \"angle\": %.6f }, \"model\": \"eclipse:item/%s_%02d\" },%n",
                    threshold, name, frame));
        }
        base.append(String.format("    { \"predicate\": { \"angle\": 0.984375 }, \"model\": \"eclipse:item/%s\" }%n", name));
        base.append("  ]\n");
        base.append("}\n");
        Files.writeString(MODEL_DIR.resolve(name + ".json"), base.toString());
    }

    private static BufferedImage newImage() {
        return new BufferedImage(16, 16, BufferedImage.TYPE_INT_ARGB);
    }
}
