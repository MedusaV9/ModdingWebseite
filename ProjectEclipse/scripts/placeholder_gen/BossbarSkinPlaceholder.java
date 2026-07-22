import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.GradientPaint;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Point2D;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import javax.imageio.ImageIO;

/**
 * Programmer-art placeholders for the W8 skinned bossbars (docs/ASSET_MANIFEST_V2.md Batch B):
 * three 512x64 theme frames (day/goal/boss), the 512x32 fill strip, the 256x32 seamless-x
 * scrolling energy overlay and the 64x64 radial end-cap glow. Also installs the
 * eclipse:ui.typewriter placeholder OGG if missing (fallback: copy of the submerge sample;
 * the committed tick was generated with
 * {@code ffmpeg -f lavfi -i "sine=frequency=2400:duration=0.05"
 * -af "volume=0.6,afade=t=out:st=0.008:d=0.042" -ar 44100 -ac 1 -c:a libvorbis typewriter.ogg}).
 *
 * The frame's inner window matches BossbarSkin's logical layout: the frame is blitted at
 * 192x15 over a 182x7 fill area inset by (5,4) — i.e. the transparent window in the 512x64
 * texture spans x 13..498, y 17..47 (512/192 ≈ 2.667 px-per-logical).
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/BossbarSkinPlaceholder.java}
 */
public class BossbarSkinPlaceholder {
    private static final int FRAME_W = 512;
    private static final int FRAME_H = 64;
    // Inner transparent window of the frame (the fill strip shows through here).
    private static final int WINDOW_X0 = 13;
    private static final int WINDOW_X1 = 498;
    private static final int WINDOW_Y0 = 17;
    private static final int WINDOW_Y1 = 47;

    public static void main(String[] args) throws IOException {
        Path dir = Path.of("src/main/resources/assets/eclipse/textures/gui/bossbar");
        Files.createDirectories(dir);

        writeFrame(dir.resolve("day_frame.png"), new Color(0xC8, 0xB4, 0xE8), new Color(0x6E, 0x4F, 0xA8), false);
        writeFrame(dir.resolve("goal_frame.png"), new Color(0x9A, 0xF0, 0xE0), new Color(0x2E, 0x8A, 0x7A), false);
        writeFrame(dir.resolve("boss_frame.png"), new Color(0xE8, 0x60, 0x78), new Color(0x7A, 0x10, 0x2A), true);
        writeFill(dir.resolve("fill.png"));
        writeScroll(dir.resolve("scroll.png"));
        writeGlow(dir.resolve("glow.png"));

        Path sourceSound = Path.of("src/main/resources/assets/eclipse/sounds/event/submerge.ogg");
        Path targetSound = Path.of("src/main/resources/assets/eclipse/sounds/ui/typewriter.ogg");
        Files.createDirectories(targetSound.getParent());
        if (!Files.exists(targetSound)) {
            // Fallback only — don't clobber the ffmpeg-generated dry tick (see class javadoc).
            Files.copy(sourceSound, targetSound, StandardCopyOption.REPLACE_EXISTING);
        }

        System.out.println("Generated bossbar placeholders in " + dir + " and " + targetSound);
    }

    /** Themed frame: rounded border around a transparent window, riveted end caps, thorns for boss. */
    private static void writeFrame(Path file, Color light, Color dark, boolean thorned) throws IOException {
        BufferedImage img = new BufferedImage(FRAME_W, FRAME_H, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

        // Outer plate.
        g.setColor(new Color(dark.getRed(), dark.getGreen(), dark.getBlue(), 235));
        g.fillRoundRect(2, 8, FRAME_W - 4, FRAME_H - 16, 22, 22);
        g.setColor(new Color(light.getRed(), light.getGreen(), light.getBlue(), 255));
        g.setStroke(new BasicStroke(4.0F));
        g.drawRoundRect(4, 10, FRAME_W - 8, FRAME_H - 20, 20, 20);

        // Punch the fill window out (straight alpha).
        g.setComposite(java.awt.AlphaComposite.Clear);
        g.fillRect(WINDOW_X0, WINDOW_Y0, WINDOW_X1 - WINDOW_X0, WINDOW_Y1 - WINDOW_Y0);
        g.setComposite(java.awt.AlphaComposite.SrcOver);

        // Thin inner bezel around the window.
        g.setColor(new Color(0, 0, 0, 200));
        g.setStroke(new BasicStroke(3.0F));
        g.drawRect(WINDOW_X0, WINDOW_Y0, WINDOW_X1 - WINDOW_X0, WINDOW_Y1 - WINDOW_Y0);

        // End caps: rivet discs (sun-dial / crystal stand-ins).
        g.setColor(light);
        g.fillOval(1, 20, 22, 22);
        g.fillOval(FRAME_W - 23, 20, 22, 22);
        g.setColor(dark);
        g.fillOval(6, 25, 12, 12);
        g.fillOval(FRAME_W - 18, 25, 12, 12);

        if (thorned) {
            g.setColor(light);
            for (int x = 40; x < FRAME_W - 40; x += 48) {
                g.fillPolygon(new int[] {x, x + 8, x + 4}, new int[] {10, 10, 1}, 3);
                g.fillPolygon(new int[] {x, x + 8, x + 4}, new int[] {54, 54, 63}, 3);
            }
        }
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Horizontal violet -> magenta energy gradient with a bright core line. */
    private static void writeFill(Path file) throws IOException {
        BufferedImage img = new BufferedImage(512, 32, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setPaint(new GradientPaint(new Point2D.Float(0, 0), new Color(0x5A, 0x18, 0xA8),
                new Point2D.Float(512, 0), new Color(0xE0, 0x38, 0xC0)));
        g.fillRect(0, 0, 512, 32);
        g.setPaint(new GradientPaint(new Point2D.Float(0, 10), new Color(255, 255, 255, 0),
                new Point2D.Float(0, 16), new Color(0xF2, 0xC8, 0xFF, 150), true));
        g.fillRect(0, 6, 512, 20);
        g.setColor(new Color(0x2A, 0x06, 0x50));
        g.fillRect(0, 0, 512, 3);
        g.fillRect(0, 29, 512, 3);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Seamless-x diagonal energy streaks, bright on transparent (additive-friendly). */
    private static void writeScroll(Path file) throws IOException {
        int w = 256;
        int h = 32;
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        for (int x = 0; x < w; x++) {
            for (int y = 0; y < h; y++) {
                // Sum of two sine bands along (x + y) keeps the pattern seamless in x.
                double a = Math.sin((x + y * 1.6D) * (Math.PI * 2.0D / 64.0D));
                double b = Math.sin((x * 2.0D - y) * (Math.PI * 2.0D / 128.0D) + 1.3D);
                double v = Math.max(0.0D, a * 0.6D + b * 0.4D);
                int alpha = (int) (v * v * 180.0D);
                if (alpha > 8) {
                    int rgb = (alpha << 24) | (0xE8 << 16) | (0xC4 << 8) | 0xFF;
                    img.setRGB(x, y, rgb);
                }
            }
        }
        ImageIO.write(img, "png", file.toFile());
    }

    /** Soft radial end-cap glow. */
    private static void writeGlow(Path file) throws IOException {
        int size = 64;
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        double center = (size - 1) / 2.0D;
        for (int x = 0; x < size; x++) {
            for (int y = 0; y < size; y++) {
                double d = Math.hypot(x - center, y - center) / (size / 2.0D);
                double v = Math.max(0.0D, 1.0D - d);
                int alpha = (int) (v * v * 255.0D);
                if (alpha > 2) {
                    img.setRGB(x, y, (alpha << 24) | (0xF6 << 16) | (0xE2 << 8) | 0xFF);
                }
            }
        }
        ImageIO.write(img, "png", file.toFile());
    }
}
