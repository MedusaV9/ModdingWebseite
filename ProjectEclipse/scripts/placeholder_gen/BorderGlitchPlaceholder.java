import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Random;
import javax.imageio.ImageIO;

/**
 * Generates the 256x256 soft-border glitch texture (seamless in X — it wraps around the
 * ring): purple value noise + horizontal displacement bands + scanlines, per
 * docs/ASSET_MANIFEST_V2.md ("Procedural-by-worker ONLY"). Also installs the border-glitch
 * sound placeholder by copying the project's known-good submerge sample.
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/BorderGlitchPlaceholder.java}
 */
public class BorderGlitchPlaceholder {
    private static final int SIZE = 256;
    /** Value-noise lattice cell size; SIZE must be divisible by it for seamless X tiling. */
    private static final int CELL = 32;
    private static final long SEED = 0xEC11B5EL;

    public static void main(String[] args) throws IOException {
        int cells = SIZE / CELL;
        // Lattice of random values; X wraps modulo the lattice so the noise tiles in X.
        float[][] lattice = new float[cells][cells + 1];
        Random random = new Random(SEED);
        for (int cx = 0; cx < cells; cx++) {
            for (int cy = 0; cy <= cells; cy++) {
                lattice[cx][cy] = random.nextFloat();
            }
        }

        // Per-row horizontal displacement bands (blocky glitch offsets, also X-periodic).
        int[] rowShift = new int[SIZE];
        Random bandRandom = new Random(SEED * 31L);
        for (int y = 0; y < SIZE; ) {
            int bandHeight = 2 + bandRandom.nextInt(7);
            int shift = bandRandom.nextInt(10) < 3 ? (bandRandom.nextInt(49) - 24) : 0;
            for (int i = 0; i < bandHeight && y < SIZE; i++, y++) {
                rowShift[y] = shift;
            }
        }

        BufferedImage image = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < SIZE; y++) {
            for (int x = 0; x < SIZE; x++) {
                int sx = Math.floorMod(x + rowShift[y], SIZE);
                float noise = valueNoise(lattice, sx, y)
                        * 0.6f + valueNoise(lattice, Math.floorMod(sx * 2, SIZE), Math.min(SIZE, y * 2) % SIZE) * 0.4f;
                // Scanlines + occasional bright glitch rows.
                float scan = (y % 3 == 0) ? 0.75f : 1.0f;
                float spike = rowShift[y] != 0 ? 1.35f : 1.0f;
                float v = clamp(noise * scan * spike);
                // Violet gradient: dark #3C096C -> mid #9D4EDD -> bright #E0AAFF.
                int r = (int) (0x3C + (0xE0 - 0x3C) * v);
                int g = (int) (0x09 + (0xAA - 0x09) * v * v);
                int b = (int) (0x6C + (0xFF - 0x6C) * v);
                // Alpha rises with brightness so the additive strip reads as unstable static.
                int a = (int) (40 + 215 * v * v);
                image.setRGB(x, y, (a << 24) | (r << 16) | (g << 8) | b);
            }
        }

        Path texture = Path.of("src/main/resources/assets/eclipse/textures/environment/border_glitch.png");
        Files.createDirectories(texture.getParent());
        ImageIO.write(image, "png", texture.toFile());

        Path sourceSound = Path.of("src/main/resources/assets/eclipse/sounds/event/submerge.ogg");
        Path targetSound = Path.of("src/main/resources/assets/eclipse/sounds/event/border_glitch.ogg");
        Files.copy(sourceSound, targetSound, StandardCopyOption.REPLACE_EXISTING);

        System.out.println("Generated " + texture + " (256x256, seamless in X) and " + targetSound);
    }

    /** Bilinear value noise on the lattice; X wraps (seamless), Y clamps. */
    private static float valueNoise(float[][] lattice, int x, int y) {
        int cells = lattice.length;
        float fx = (float) x / CELL;
        float fy = (float) y / CELL;
        int x0 = (int) fx;
        int y0 = Math.min((int) fy, cells - 1);
        float tx = smooth(fx - x0);
        float ty = smooth(fy - y0);
        float v00 = lattice[x0 % cells][y0];
        float v10 = lattice[(x0 + 1) % cells][y0];
        float v01 = lattice[x0 % cells][y0 + 1];
        float v11 = lattice[(x0 + 1) % cells][y0 + 1];
        return lerp(lerp(v00, v10, tx), lerp(v01, v11, tx), ty);
    }

    private static float smooth(float t) {
        return t * t * (3.0f - 2.0f * t);
    }

    private static float lerp(float a, float b, float t) {
        return a + (b - a) * t;
    }

    private static float clamp(float v) {
        return Math.max(0.0f, Math.min(1.0f, v));
    }
}
