import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;

/**
 * Programmer-art for docs/ASSET_MANIFEST_V2.md Batch C. Every output uses the
 * manifest's exact path and dimensions so final art remains a byte-for-byte drop-in.
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/TitleScreenPlaceholder.java}
 */
public class TitleScreenPlaceholder {
    private static final int PARALLAX_WIDTH = 1024;
    private static final int PARALLAX_HEIGHT = 512;

    public static void main(String[] args) throws IOException {
        Path dir = Path.of("src/main/resources/assets/eclipse/textures/gui/title");
        Files.createDirectories(dir);
        writeParallax(dir.resolve("parallax_far.png"), 0);
        writeParallax(dir.resolve("parallax_mid.png"), 1);
        writeParallax(dir.resolve("parallax_near.png"), 2);
        writeWisp(dir.resolve("wisp.png"));
        writeFlare(dir.resolve("flare_sweep.png"));
        writeGear(dir.resolve("gear.png"));
        System.out.println("Generated title-screen v2 placeholders in " + dir);
    }

    /** X-periodic mist/noise so the runtime's horizontally repeated layers have no seam. */
    private static void writeParallax(Path file, int layer) throws IOException {
        BufferedImage image = new BufferedImage(PARALLAX_WIDTH, PARALLAX_HEIGHT, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < PARALLAX_HEIGHT; y++) {
            double v = y * Math.PI * 2.0D / PARALLAX_HEIGHT;
            for (int x = 0; x < PARALLAX_WIDTH; x++) {
                double u = x * Math.PI * 2.0D / PARALLAX_WIDTH;
                double broad = Math.sin(u * (2 + layer) + Math.sin(v * 2.0D) * 1.5D);
                double detail = Math.sin(u * (5 + layer * 2) - v * (2 + layer)) * 0.55D
                        + Math.cos(u * (9 + layer) + v * 3.0D) * 0.25D;
                double cloud = Math.max(0.0D, (broad + detail) * 0.5D + 0.34D);
                double vertical;
                if (layer == 2) {
                    // Near smoke frames the top/bottom and leaves the menu center readable.
                    vertical = Math.pow(Math.abs(y / (PARALLAX_HEIGHT - 1.0D) * 2.0D - 1.0D), 1.5D);
                } else {
                    double center = layer == 0 ? 0.38D : 0.58D;
                    double dy = y / (double) PARALLAX_HEIGHT - center;
                    vertical = Math.exp(-(dy * dy) / (layer == 0 ? 0.11D : 0.065D));
                }
                double strength = cloud * vertical;
                int maxAlpha = layer == 0 ? 70 : layer == 1 ? 105 : 145;
                int alpha = clamp((int) (strength * maxAlpha));
                int red = layer == 2 ? 28 : 88 + layer * 10;
                int green = layer == 2 ? 18 : 58 + layer * 8;
                int blue = layer == 2 ? 44 : 132 + layer * 12;
                image.setRGB(x, y, (alpha << 24) | (red << 16) | (green << 8) | blue);
            }
        }
        ImageIO.write(image, "png", file.toFile());
    }

    /** 32x32 soft violet mote, transparent and blend-friendly. */
    private static void writeWisp(Path file) throws IOException {
        int size = 32;
        BufferedImage image = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        double center = (size - 1) / 2.0D;
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                double dx = (x - center) / 13.0D;
                double dy = (y - center) / 10.0D;
                double distance = Math.sqrt(dx * dx + dy * dy);
                double glow = Math.max(0.0D, 1.0D - distance);
                int alpha = clamp((int) (glow * glow * 245.0D));
                int red = clamp((int) (180 + glow * 70));
                int green = clamp((int) (105 + glow * 115));
                image.setRGB(x, y, (alpha << 24) | (red << 16) | (green << 8) | 255);
            }
        }
        ImageIO.write(image, "png", file.toFile());
    }

    /** 512x128 white-violet horizontal flare with a hot core and broad feathered ends. */
    private static void writeFlare(Path file) throws IOException {
        int width = 512;
        int height = 128;
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        double cx = (width - 1) / 2.0D;
        double cy = (height - 1) / 2.0D;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                double horizontal = Math.max(0.0D, 1.0D - Math.abs(x - cx) / cx);
                double vertical = Math.exp(-Math.pow((y - cy) / 8.5D, 2.0D));
                double halo = Math.exp(-Math.pow((y - cy) / 30.0D, 2.0D)) * 0.22D;
                double glow = horizontal * (vertical + halo);
                int alpha = clamp((int) (glow * 255.0D));
                int green = clamp((int) (205 + vertical * 50.0D));
                image.setRGB(x, y, (alpha << 24) | (255 << 16) | (green << 8) | 255);
            }
        }
        ImageIO.write(image, "png", file.toFile());
    }

    /** 48x48 filigree-style settings gear icon. */
    private static void writeGear(Path file) throws IOException {
        int size = 48;
        BufferedImage image = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        graphics.translate(size / 2.0D, size / 2.0D);
        graphics.setColor(new Color(8, 4, 18, 230));
        graphics.fillOval(-15, -15, 30, 30);
        graphics.setColor(new Color(185, 140, 255, 245));
        graphics.setStroke(new BasicStroke(4.0F, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        graphics.drawOval(-13, -13, 26, 26);
        for (int i = 0; i < 8; i++) {
            double angle = i * Math.PI / 4.0D;
            int x0 = (int) Math.round(Math.cos(angle) * 13.0D);
            int y0 = (int) Math.round(Math.sin(angle) * 13.0D);
            int x1 = (int) Math.round(Math.cos(angle) * 19.0D);
            int y1 = (int) Math.round(Math.sin(angle) * 19.0D);
            graphics.drawLine(x0, y0, x1, y1);
        }
        graphics.setColor(new Color(12, 6, 26));
        graphics.fillOval(-6, -6, 12, 12);
        graphics.setColor(new Color(230, 214, 255));
        graphics.setStroke(new BasicStroke(2.0F));
        graphics.drawOval(-6, -6, 12, 12);
        graphics.dispose();
        ImageIO.write(image, "png", file.toFile());
    }

    private static int clamp(int value) {
        return Math.max(0, Math.min(255, value));
    }
}
