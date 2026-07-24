import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;

/**
 * Programmer-art 16×16 item icons for the W11 Herald items: the Herald's Lure (a shard
 * bundle knotted around a heart fragment — the recipe made visible) and the Herald Core
 * (a cracked black-glass orb leaking gold light, matching the boss texture palette in
 * {@code docs/uv/herald.md}).
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/ItemIconPlaceholder.java}
 */
public class ItemIconPlaceholder {
    private static final Path DIR = Path.of("src/main/resources/assets/eclipse/textures/item");

    public static void main(String[] args) throws IOException {
        Files.createDirectories(DIR);
        writeHeraldsLure();
        writeHeraldCore();
        writeFerrymanToll();
        System.out.println("Generated 3 item icons in " + DIR);
    }

    // --- herald's lure: 4 violet shards fanned around a small red heart-fragment knot ---

    private static void writeHeraldsLure() throws IOException {
        BufferedImage img = new BufferedImage(16, 16, BufferedImage.TYPE_INT_ARGB);
        int shard = 0xFFC88AFF;
        int shardDark = 0xFF8A5CFF;
        int heart = 0xFFE04858;
        int heartDark = 0xFF8C2430;
        int cord = 0xFF3A2E1E;
        // Four shards fanned to the corners (each a 3px diagonal sliver + dark edge).
        int[][][] shards = {
                {{3, 2}, {4, 3}, {5, 4}}, {{12, 2}, {11, 3}, {10, 4}},
                {{3, 13}, {4, 12}, {5, 11}}, {{12, 13}, {11, 12}, {10, 11}},
        };
        for (int[][] line : shards) {
            for (int i = 0; i < line.length; i++) {
                img.setRGB(line[i][0], line[i][1], i == 0 ? shardDark : shard);
            }
        }
        // Cord ring binding the bundle.
        int[][] ring = {{6, 6}, {7, 5}, {8, 5}, {9, 6}, {10, 7}, {10, 8}, {9, 9}, {8, 10}, {7, 10}, {6, 9}, {5, 8}, {5, 7}};
        for (int[] p : ring) {
            img.setRGB(p[0], p[1], cord);
        }
        // Heart fragment in the middle (2x3 with a notch).
        img.setRGB(7, 7, heart);
        img.setRGB(8, 7, heartDark);
        img.setRGB(7, 8, heart);
        img.setRGB(8, 8, heart);
        img.setRGB(7, 6, heartDark);
        ImageIO.write(img, "png", DIR.resolve("heralds_lure.png").toFile());
    }

    // --- herald core: black-glass orb, gold crack veins, blazing center ---

    private static void writeHeraldCore() throws IOException {
        BufferedImage img = new BufferedImage(16, 16, BufferedImage.TYPE_INT_ARGB);
        int glass = 0xFF181224;
        int glassEdge = 0xFF0E0A16;
        int vein = 0xFFE8A83A;
        int glow = 0xFFFFD86A;
        // Filled circle r=6 around (8,8) with a darker rim.
        for (int y = 0; y < 16; y++) {
            for (int x = 0; x < 16; x++) {
                double d = Math.hypot(x - 7.5, y - 7.5);
                if (d <= 6.0) {
                    img.setRGB(x, y, d >= 5.0 ? glassEdge : glass);
                }
            }
        }
        // Gold crack veins radiating from the center.
        int[][] veins = {{7, 4}, {8, 5}, {6, 6}, {9, 6}, {5, 8}, {10, 9}, {6, 10}, {9, 11}, {8, 9}, {7, 10}};
        for (int[] p : veins) {
            img.setRGB(p[0], p[1], vein);
        }
        // Blazing 2x2 center.
        img.setRGB(7, 7, glow);
        img.setRGB(8, 7, glow);
        img.setRGB(7, 8, glow);
        img.setRGB(8, 8, glow);
        ImageIO.write(img, "png", DIR.resolve("herald_core.png").toFile());
    }

    // --- ferryman toll: a drowned obolus — verdigris coin with a soul-teal skull stamp ---

    private static void writeFerrymanToll() throws IOException {
        BufferedImage img = new BufferedImage(16, 16, BufferedImage.TYPE_INT_ARGB);
        int coin = 0xFF4A6A5C;      // verdigris bronze (matches the Ferryman robe palette)
        int coinEdge = 0xFF2C4238;
        int stamp = 0xFF8FF2DE;     // soul-teal skull stamp (the boss's eye-slit color)
        int socket = 0xFF14201B;
        // Filled circle r=6 around (7.5,7.5) with a darker rim.
        for (int y = 0; y < 16; y++) {
            for (int x = 0; x < 16; x++) {
                double d = Math.hypot(x - 7.5, y - 7.5);
                if (d <= 6.0) {
                    img.setRGB(x, y, d >= 5.0 ? coinEdge : coin);
                }
            }
        }
        // Skull stamp: 4x3 cranium + 2x1 jaw in soul teal, with two dark sockets.
        for (int x = 6; x <= 9; x++) {
            for (int y = 5; y <= 7; y++) {
                img.setRGB(x, y, stamp);
            }
        }
        img.setRGB(7, 8, stamp);
        img.setRGB(8, 8, stamp);
        img.setRGB(7, 9, stamp);
        img.setRGB(8, 9, stamp);
        img.setRGB(6, 6, socket);
        img.setRGB(9, 6, socket);
        // Wear notch on the rim (the toll has changed many cold hands).
        img.setRGB(11, 4, 0x00000000);
        ImageIO.write(img, "png", DIR.resolve("ferryman_toll.png").toFile());
    }
}
