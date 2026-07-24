import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;

/**
 * Programmer-art skins for the W10 custom mobs, painted region-by-region to EXACTLY the
 * box-UV layouts of the hand-coded models in {@code client/entity/} (documented per mob in
 * {@code docs/uv/<mob>.md}): each cube face gets a distinct flat color + a 1px darker seam
 * outline so the in-game read is unambiguous while real art is produced.
 *
 * <p>{@code the_other.png} is NOT painted from scratch — per spec §1.1 it is generated from
 * the existing anonymity {@code uniform_skin.png}: pure-black 2x2 eyes and a faint purple
 * center seam, applied to BOTH the base face and the (fully opaque) hat-layer face.</p>
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/EntitySkinPlaceholder.java}
 */
public class EntitySkinPlaceholder {
    private static final Path DIR = Path.of("src/main/resources/assets/eclipse/textures/entity");

    public static void main(String[] args) throws IOException {
        Files.createDirectories(DIR);
        writeTheOther();
        writeGazer();
        writeUmbralStalker();
        writeDeckhand();
        writeSunmote();
        writeHerald();
        writeFerryman();
        System.out.println("Generated 7 entity skins in " + DIR);
    }

    // --- the other (64x64, vanilla player-skin layout, derived from uniform_skin.png) ---

    private static void writeTheOther() throws IOException {
        BufferedImage img = ImageIO.read(DIR.resolve("uniform_skin.png").toFile());
        int black = 0xFF000000;
        // Face front is (8,8)-(15,15) on the base layer and (40,8)-(47,15) on the hat layer
        // (opaque, renders on top). 2x2 pure-black eyes replace the pale 1x2 originals.
        for (int layerX : new int[] {8, 40}) {
            for (int y = 11; y <= 12; y++) {
                for (int x : new int[] {1, 2, 5, 6}) {
                    img.setRGB(layerX + x, y, black);
                }
            }
            // Faint purple seam down the face center (columns 3..4 midline, subtle shift).
            int seam = new Color(0x83, 0x67, 0xA8).getRGB() | 0xFF000000;
            for (int y = 8; y <= 15; y++) {
                img.setRGB(layerX + 3, y, seam);
            }
        }
        ImageIO.write(img, "png", DIR.resolve("the_other.png").toFile());
    }

    // --- box-UV painting helpers ---

    /** Paints all six face rects of a box-UV cube in shades of {@code base} + 1px seams. */
    private static void cube(BufferedImage img, int u, int v, int w, int h, int d, Color base) {
        face(img, u + d, v, w, d, shade(base, 1.15F));           // top
        face(img, u + d + w, v, w, d, shade(base, 0.7F));        // bottom
        face(img, u, v + d, d, h, shade(base, 0.85F));           // east (right)
        face(img, u + d, v + d, w, h, base);                     // north (front)
        face(img, u + d + w, v + d, d, h, shade(base, 0.85F));   // west (left)
        face(img, u + d + w + d, v + d, w, h, shade(base, 0.75F)); // south (back)
    }

    /** One flat-color face rect with a 1px darker seam border. */
    private static void face(BufferedImage img, int x, int y, int w, int h, Color fill) {
        int f = fill.getRGB() | 0xFF000000;
        int seam = shade(fill, 0.55F).getRGB() | 0xFF000000;
        for (int yy = y; yy < y + h; yy++) {
            for (int xx = x; xx < x + w; xx++) {
                boolean edge = xx == x || xx == x + w - 1 || yy == y || yy == y + h - 1;
                img.setRGB(xx, yy, edge ? seam : f);
            }
        }
    }

    private static Color shade(Color color, float factor) {
        return new Color(Math.min(255, (int) (color.getRed() * factor)),
                Math.min(255, (int) (color.getGreen() * factor)),
                Math.min(255, (int) (color.getBlue() * factor)));
    }

    private static BufferedImage canvas(int size) {
        return new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
    }

    // --- gazer (64x64) ---

    private static void writeGazer() throws IOException {
        BufferedImage img = canvas(64);
        Color cloak = new Color(0x2A, 0x24, 0x40);
        Color hood = new Color(0x1E, 0x1A, 0x30);
        Color mantle = new Color(0x3A, 0x33, 0x58);
        Color tatter = new Color(0x24, 0x1F, 0x38);
        Color faceGlow = new Color(0xF2, 0xE8, 0xC8);
        cube(img, 0, 0, 10, 18, 6, cloak);      // cloak
        cube(img, 32, 0, 8, 8, 8, hood);        // hood
        cube(img, 32, 16, 6, 6, 1, faceGlow);   // face (emissive pass re-renders this cube)
        cube(img, 0, 24, 3, 8, 1, tatter);      // tatter_left
        cube(img, 10, 24, 3, 8, 1, tatter);     // tatter_right
        cube(img, 0, 40, 12, 3, 8, mantle);     // mantle
        // Two hollow eye slits on the face front (u 33..38, v 17..22 inner area).
        int slit = 0xFF141020;
        for (int y = 19; y <= 20; y++) {
            img.setRGB(34, y, slit);
            img.setRGB(37, y, slit);
        }
        ImageIO.write(img, "png", DIR.resolve("gazer.png").toFile());
    }

    // --- umbral stalker (64x64) ---

    private static void writeUmbralStalker() throws IOException {
        BufferedImage img = canvas(64);
        Color body = new Color(0x22, 0x1A, 0x2E);
        Color head = new Color(0x2A, 0x20, 0x38);
        Color leg = new Color(0x1C, 0x16, 0x26);
        Color shard = new Color(0x8A, 0x5C, 0xFF);
        Color jaw = new Color(0xD8, 0xD0, 0xC0);
        cube(img, 0, 0, 8, 7, 14, body);        // body
        cube(img, 0, 21, 7, 6, 8, head);        // head
        cube(img, 30, 21, 1, 3, 1, jaw);        // jaw_left
        cube(img, 36, 21, 1, 3, 1, jaw);        // jaw_right
        int[] legU = {0, 12, 24, 36};
        for (int u : legU) {
            cube(img, u, 35, 3, 8, 3, leg);     // legs FL/FR/HL/HR
        }
        cube(img, 44, 0, 2, 4, 2, shard);       // spine_front
        cube(img, 44, 6, 2, 5, 2, shard);       // spine_mid
        cube(img, 44, 13, 2, 4, 2, shard);      // spine_back
        // Violet eye pinpricks on the head front (u 8..14, v 29..34).
        img.setRGB(10, 30, 0xFFB090FF);
        img.setRGB(12, 30, 0xFFB090FF);
        ImageIO.write(img, "png", DIR.resolve("umbral_stalker.png").toFile());
    }

    // --- deckhand (64x64) ---

    private static void writeDeckhand() throws IOException {
        BufferedImage img = canvas(64);
        Color robe = new Color(0x3A, 0x40, 0x38);
        Color torso = new Color(0x2E, 0x34, 0x30);
        Color headShadow = new Color(0x14, 0x16, 0x12);
        Color hood = new Color(0x26, 0x2B, 0x24);
        Color arm = new Color(0x34, 0x3A, 0x32);
        Color oar = new Color(0x5A, 0x45, 0x2E);
        cube(img, 0, 0, 8, 10, 4, torso);       // torso
        cube(img, 24, 0, 8, 8, 8, headShadow);  // head (all shadow under the hood)
        cube(img, 0, 14, 3, 10, 3, arm);        // arm_right
        cube(img, 12, 14, 3, 10, 3, arm);       // arm_left
        cube(img, 24, 16, 8, 8, 6, robe);       // robe
        cube(img, 56, 16, 1, 22, 1, oar);       // oar shaft
        cube(img, 0, 27, 8, 8, 8, hood);        // hood (0.25 inflated overlay)
        // Two faint pale eyes in the head-front shadow (head front: u 36..43, v 8..15).
        img.setRGB(38, 11, 0xFF9AA88A);
        img.setRGB(41, 11, 0xFF9AA88A);
        ImageIO.write(img, "png", DIR.resolve("deckhand.png").toFile());
    }

    // --- sunmote (32x32) ---

    private static void writeSunmote() throws IOException {
        BufferedImage img = canvas(32);
        Color core = new Color(0xFF, 0xF2, 0xC0);
        Color halo = new Color(0xFF, 0xC2, 0x4A);
        cube(img, 0, 0, 2, 2, 2, core);         // core
        cube(img, 0, 4, 4, 1, 4, halo);         // halo plate
        ImageIO.write(img, "png", DIR.resolve("sunmote.png").toFile());
    }

    // --- herald (128x128, W11 boss — docs/uv/herald.md) ---

    private static void writeHerald() throws IOException {
        BufferedImage img = canvas(128);
        Color core = new Color(0x18, 0x12, 0x24);       // black glass
        Color eye = new Color(0xFF, 0xD8, 0x6A);        // blazing gold (emissive pass)
        Color shard = new Color(0xC8, 0x8A, 0xFF);      // corona violet (glows on telegraph)
        Color tentacle = new Color(0x24, 0x1C, 0x36);   // dark umbral chain
        cube(img, 0, 0, 12, 12, 12, core);              // core
        cube(img, 48, 0, 6, 6, 6, eye);                 // inner_eye
        for (int i = 0; i < 8; i++) {
            cube(img, i * 8, 32, 2, 6, 2, shard);       // shard0..7
        }
        for (int s = 0; s < 16; s++) {
            cube(img, s * 8, 44, 2, 6, 2, tentacle);    // tentacle{t}_seg{k}, t*4+k = s
        }
        // Gold crack veins radiating on the core's front face (u 12..23, v 12..23).
        int vein = new Color(0xE8, 0xA8, 0x3A).getRGB() | 0xFF000000;
        int[][] veins = {{17, 13}, {17, 14}, {16, 15}, {18, 15}, {15, 16}, {19, 16},
                {14, 18}, {20, 18}, {13, 20}, {21, 20}, {17, 21}, {17, 22}};
        for (int[] p : veins) {
            img.setRGB(p[0], p[1], vein);
        }
        // Dark pupil slit on the eye front (u 54..59, v 6..11): 2x2 void center.
        int pupil = 0xFF100A18;
        for (int y = 8; y <= 9; y++) {
            img.setRGB(56, y, pupil);
            img.setRGB(57, y, pupil);
        }
        ImageIO.write(img, "png", DIR.resolve("herald.png").toFile());
    }

    // --- ferryman (128x128, W12 finale boss — docs/uv/ferryman.md) ---

    private static void writeFerryman() throws IOException {
        BufferedImage img = canvas(128);
        Color robe = new Color(0x20, 0x2C, 0x28);       // drowned green-black wool
        Color strip = new Color(0x18, 0x22, 0x1E);      // ragged hem strips
        Color hood = new Color(0x14, 0x1B, 0x18);       // deep hood shell
        Color skull = new Color(0xD8, 0xD2, 0xBE);      // old bone
        Color eyeSlit = new Color(0x8F, 0xF2, 0xDE);    // soul teal (emissive pass)
        Color sleeve = new Color(0x26, 0x33, 0x2E);
        Color oarWood = new Color(0x4A, 0x3A, 0x28);    // waterlogged shaft
        Color oarBlade = new Color(0x3C, 0x2F, 0x20);
        Color chain = new Color(0x62, 0x66, 0x70);      // wet iron links
        Color lantern = new Color(0x3A, 0x3E, 0x46);    // lantern housing
        Color flame = new Color(0xA8, 0xF7, 0xE6);      // soul flame (emissive pass)
        cube(img, 0, 0, 10, 26, 8, robe);               // body (robe)
        for (int i = 0; i < 4; i++) {
            cube(img, 32 + i * 8, 36, 2, 6, 1, strip);  // strip0..3
        }
        cubeOpenNorth(img, 40, 0, 9, 9, 9, hood);       // hood (front face left transparent)
        cube(img, 80, 0, 7, 7, 7, skull);               // head (skull)
        cube(img, 108, 0, 5, 2, 1, eyeSlit);            // eyes
        cube(img, 0, 36, 3, 20, 3, sleeve);             // arm_right
        cube(img, 16, 36, 3, 20, 3, sleeve);            // arm_left
        cube(img, 64, 36, 2, 36, 2, oarWood);           // oar shaft
        cube(img, 76, 36, 1, 6, 5, oarBlade);           // blade
        for (int k = 0; k < 3; k++) {
            cube(img, 92 + k * 6, 36, 1, 4, 1, chain);  // chain0..2
        }
        cube(img, 92, 44, 4, 5, 4, lantern);            // lantern housing
        cube(img, 110, 36, 2, 2, 2, flame);             // flame
        // Hollow skull sockets + nasal pit on the head front (u 87..93, v 7..13 inner).
        int socket = 0xFF0E1410;
        for (int y = 9; y <= 10; y++) {
            img.setRGB(88, y, socket);
            img.setRGB(89, y, socket);
            img.setRGB(91, y, socket);
            img.setRGB(92, y, socket);
        }
        img.setRGB(90, 12, socket);
        // Pale barnacle flecks down the robe front (u 8..17, v 8..33 inner).
        int fleck = new Color(0x5E, 0x74, 0x66).getRGB() | 0xFF000000;
        int[][] flecks = {{10, 12}, {15, 15}, {12, 19}, {16, 24}, {9, 27}, {13, 30}};
        for (int[] p : flecks) {
            img.setRGB(p[0], p[1], fleck);
        }
        ImageIO.write(img, "png", DIR.resolve("ferryman.png").toFile());
    }

    /**
     * Box-UV cube whose NORTH (front) face stays fully transparent — the Ferryman's hood
     * is an open cowl: the skull inside must show through the front.
     */
    private static void cubeOpenNorth(BufferedImage img, int u, int v, int w, int h, int d, Color base) {
        face(img, u + d, v, w, d, shade(base, 1.15F));             // top
        face(img, u + d + w, v, w, d, shade(base, 0.7F));          // bottom
        face(img, u, v + d, d, h, shade(base, 0.85F));             // east (right)
        face(img, u + d + w, v + d, d, h, shade(base, 0.85F));     // west (left)
        face(img, u + d + w + d, v + d, w, h, shade(base, 0.75F)); // south (back)
    }
}
