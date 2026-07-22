import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Font;
import java.awt.GradientPaint;
import java.awt.Graphics2D;
import java.awt.RadialGradientPaint;
import java.awt.RenderingHints;
import java.awt.geom.Point2D;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;
import javax.imageio.ImageIO;

/**
 * Programmer-art placeholders for the W9 Handbook 2.0 ("The Ledger of the Drowned"),
 * covering docs/ASSET_MANIFEST_V2.md Batch A plus the Batch B altar progress ring the
 * Status tab draws:
 *
 * <ul>
 *   <li>gui/handbook/book_spread.png (2048x1280, alpha) — open two-page ledger</li>
 *   <li>gui/handbook/parchment_tile.png (1024x1024, opaque) — seamless parchment</li>
 *   <li>gui/handbook/tab_{status,timeline,rules,rewards,bestiary,map}.png (64x64)</li>
 *   <li>gui/handbook/hero_{status,timeline,rules,rewards,bestiary,map}.png (1024x768)</li>
 *   <li>gui/handbook/timeline_node_{locked,unlocked,current}.png (96x96)</li>
 *   <li>gui/handbook/divider.png (512x64)</li>
 *   <li>gui/cursor/{arrow,hand,grab}.png (32x32; hotspots (0,0)/(8,0)/(16,16))</li>
 *   <li>gui/icons/altar_ring.png (256x256) — runic ring, progress arc drawn by code</li>
 * </ul>
 *
 * Orchestrator art replaces these byte-for-byte at the exact same paths/dimensions.
 * Run from the ProjectEclipse root: {@code java scripts/placeholder_gen/HandbookPlaceholder.java}
 */
public class HandbookPlaceholder {
    private static final Color ACCENT = new Color(0xB9, 0x8C, 0xFF);
    private static final Color DEEP = new Color(0x14, 0x0B, 0x24);
    private static final Color PARCHMENT_LIGHT = new Color(0x4A, 0x3E, 0x5E);
    private static final Color PARCHMENT_DARK = new Color(0x33, 0x28, 0x47);

    public static void main(String[] args) throws IOException {
        Path handbook = Path.of("src/main/resources/assets/eclipse/textures/gui/handbook");
        Path cursor = Path.of("src/main/resources/assets/eclipse/textures/gui/cursor");
        Path icons = Path.of("src/main/resources/assets/eclipse/textures/gui/icons");
        Files.createDirectories(handbook);
        Files.createDirectories(cursor);
        Files.createDirectories(icons);

        writeBookSpread(handbook.resolve("book_spread.png"));
        writeParchmentTile(handbook.resolve("parchment_tile.png"));

        writeTabIcon(handbook.resolve("tab_status.png"), "status");
        writeTabIcon(handbook.resolve("tab_timeline.png"), "timeline");
        writeTabIcon(handbook.resolve("tab_rules.png"), "rules");
        writeTabIcon(handbook.resolve("tab_rewards.png"), "rewards");
        writeTabIcon(handbook.resolve("tab_bestiary.png"), "bestiary");
        writeTabIcon(handbook.resolve("tab_map.png"), "map");

        writeHero(handbook.resolve("hero_status.png"), "status");
        writeHero(handbook.resolve("hero_timeline.png"), "timeline");
        writeHero(handbook.resolve("hero_rules.png"), "rules");
        writeHero(handbook.resolve("hero_rewards.png"), "rewards");
        writeHero(handbook.resolve("hero_bestiary.png"), "bestiary");
        writeHero(handbook.resolve("hero_map.png"), "map");

        writeTimelineNode(handbook.resolve("timeline_node_locked.png"), 0);
        writeTimelineNode(handbook.resolve("timeline_node_unlocked.png"), 1);
        writeTimelineNode(handbook.resolve("timeline_node_current.png"), 2);

        writeDivider(handbook.resolve("divider.png"));

        writeCursorArrow(cursor.resolve("arrow.png"));
        writeCursorHand(cursor.resolve("hand.png"));
        writeCursorGrab(cursor.resolve("grab.png"));

        writeAltarRing(icons.resolve("altar_ring.png"));

        System.out.println("Generated handbook placeholders in " + handbook + ", " + cursor + " and " + icons);
    }

    /** Open waterlogged ledger: dark leather cover, two violet parchment pages, spine shadow, vignette. */
    private static void writeBookSpread(Path file) throws IOException {
        int w = 2048;
        int h = 1280;
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

        // Leather cover plate.
        g.setColor(new Color(0x1A, 0x10, 0x2E));
        g.fillRoundRect(8, 8, w - 16, h - 16, 90, 90);
        g.setColor(new Color(0x2A, 0x1B, 0x4A));
        g.setStroke(new BasicStroke(10.0F));
        g.drawRoundRect(20, 20, w - 40, h - 40, 76, 76);

        // Two parchment pages with a violet tint.
        int margin = 56;
        int pageW = w / 2 - margin - 18;
        g.setPaint(new GradientPaint(0, 0, PARCHMENT_LIGHT, 0, h, PARCHMENT_DARK));
        g.fillRoundRect(margin, margin, pageW, h - 2 * margin, 40, 40);
        g.fillRoundRect(w / 2 + 18, margin, pageW, h - 2 * margin, 40, 40);

        // Page edge stacks (closed leaves).
        g.setStroke(new BasicStroke(3.0F));
        for (int i = 0; i < 7; i++) {
            g.setColor(new Color(0x5A, 0x4C, 0x74, 120 - i * 12));
            g.drawRoundRect(margin - 6 - i * 4, margin - 6 - i * 3, pageW + 10 + i * 4, h - 2 * margin + 12 + i * 6, 40, 40);
            g.drawRoundRect(w / 2 + 18 - 4, margin - 6 - i * 3, pageW + 10 + i * 4, h - 2 * margin + 12 + i * 6, 40, 40);
        }

        // Spine shadow down the center.
        g.setPaint(new GradientPaint(w / 2.0F - 90, 0, new Color(0, 0, 0, 0), w / 2.0F, 0, new Color(0, 0, 0, 170)));
        g.fillRect(w / 2 - 90, margin, 90, h - 2 * margin);
        g.setPaint(new GradientPaint(w / 2.0F, 0, new Color(0, 0, 0, 170), w / 2.0F + 90, 0, new Color(0, 0, 0, 0)));
        g.fillRect(w / 2, margin, 90, h - 2 * margin);

        // Ornate eclipse emblem on the spine.
        g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 180));
        g.setStroke(new BasicStroke(6.0F));
        g.drawOval(w / 2 - 34, h / 2 - 34, 68, 68);
        g.setColor(new Color(0x0A, 0x05, 0x14));
        g.fillOval(w / 2 - 24, h / 2 - 24, 48, 48);
        g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 230));
        g.fillOval(w / 2 - 8, h / 2 - 30, 14, 14);

        // Faint water stains on the pages.
        Random random = new Random(9L);
        for (int i = 0; i < 26; i++) {
            int cx = margin + random.nextInt(w - 2 * margin);
            int cy = margin + random.nextInt(h - 2 * margin);
            int r = 30 + random.nextInt(120);
            g.setColor(new Color(0x6A, 0x4F, 0xA0, 10 + random.nextInt(14)));
            g.fillOval(cx - r, cy - r, 2 * r, 2 * r);
        }

        // Vignetted edges.
        g.setPaint(new RadialGradientPaint(new Point2D.Float(w / 2.0F, h / 2.0F), w * 0.62F,
                new float[] {0.62F, 1.0F}, new Color[] {new Color(0, 0, 0, 0), new Color(0, 0, 0, 130)}));
        g.fillRoundRect(8, 8, w - 16, h - 16, 90, 90);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Seamless tileable aged parchment (sine-sum noise keeps every edge continuous). */
    private static void writeParchmentTile(Path file) throws IOException {
        int size = 1024;
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_RGB);
        for (int x = 0; x < size; x++) {
            for (int y = 0; y < size; y++) {
                double u = x * (Math.PI * 2.0D / size);
                double v = y * (Math.PI * 2.0D / size);
                // Low-contrast fiber noise from tile-periodic sines.
                double n = Math.sin(u * 7 + Math.cos(v * 3) * 2) * 0.5D
                        + Math.sin(v * 11 + Math.cos(u * 5) * 1.5D) * 0.3D
                        + Math.sin((u + v) * 17) * 0.2D;
                double stain = Math.max(0.0D, Math.sin(u * 2 + 1.2D) * Math.sin(v * 2 + 0.4D)) * 0.35D;
                int r = clamp((int) (0x46 + n * 8 - stain * 18));
                int gg = clamp((int) (0x3A + n * 7 - stain * 12));
                int b = clamp((int) (0x58 + n * 9 - stain * 6));
                img.setRGB(x, y, (r << 16) | (gg << 8) | b);
            }
        }
        ImageIO.write(img, "png", file.toFile());
    }

    /** Flat emblem-style 64x64 tab icons, one motif per tab id. */
    private static void writeTabIcon(Path file, String id) throws IOException {
        BufferedImage img = new BufferedImage(64, 64, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(ACCENT);
        g.setStroke(new BasicStroke(4.0F));
        switch (id) {
            case "status" -> { // eclipsed sun disc with a thin corona
                g.drawOval(10, 10, 44, 44);
                g.setColor(DEEP);
                g.fillOval(16, 16, 32, 32);
                g.setColor(ACCENT);
                g.fillOval(38, 14, 10, 10);
            }
            case "timeline" -> { // horizontal spine with nodes, one glowing
                g.drawLine(6, 32, 58, 32);
                g.fillOval(12, 26, 12, 12);
                g.fillOval(44, 26, 12, 12);
                g.setColor(Color.WHITE);
                g.fillOval(28, 22, 16, 16);
            }
            case "rules" -> { // scroll with a purple wax seal
                g.drawRoundRect(14, 8, 36, 48, 10, 10);
                g.drawLine(20, 20, 44, 20);
                g.drawLine(20, 30, 44, 30);
                g.fillOval(34, 38, 16, 16);
            }
            case "rewards" -> { // faceted crystal shard cluster
                g.fillPolygon(new int[] {32, 42, 36, 28}, new int[] {6, 26, 52, 26}, 4);
                g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 150));
                g.fillPolygon(new int[] {18, 26, 22, 12}, new int[] {22, 34, 54, 36}, 4);
                g.fillPolygon(new int[] {46, 54, 50, 42}, new int[] {24, 36, 54, 38}, 4);
            }
            case "bestiary" -> { // hooded silhouette with black eyes
                g.fillOval(16, 8, 32, 32);
                g.fillPolygon(new int[] {16, 48, 54, 10}, new int[] {24, 24, 58, 58}, 4);
                g.setColor(DEEP);
                g.fillOval(24, 20, 6, 8);
                g.fillOval(34, 20, 6, 8);
            }
            default -> { // map: concentric rings with a center dot
                g.drawOval(8, 8, 48, 48);
                g.drawOval(18, 18, 28, 28);
                g.fillOval(29, 29, 6, 6);
            }
        }
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** 1024x768 painterly-vista stand-in: theme gradient + simple scene shapes + label. */
    private static void writeHero(Path file, String id) throws IOException {
        int w = 1024;
        int h = 768;
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

        g.setPaint(new GradientPaint(0, 0, new Color(0x2A, 0x18, 0x50, 235), 0, h, new Color(0x0C, 0x06, 0x1A, 235)));
        g.fillRoundRect(0, 0, w, h, 60, 60);

        // Occluded violet sun shared by every vista.
        g.setPaint(new RadialGradientPaint(new Point2D.Float(w / 2.0F, h * 0.32F), 190,
                new float[] {0.0F, 0.7F, 1.0F},
                new Color[] {new Color(0xE0, 0xC8, 0xFF, 200), new Color(0x8A, 0x5C, 0xE0, 120), new Color(0, 0, 0, 0)}));
        g.fillOval(w / 2 - 190, (int) (h * 0.32F) - 190, 380, 380);
        g.setColor(new Color(0x08, 0x04, 0x12));
        g.fillOval(w / 2 - 110, (int) (h * 0.32F) - 110, 220, 220);

        g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 190));
        g.setStroke(new BasicStroke(8.0F));
        switch (id) {
            case "status" -> { // floating island disc with a tiny altar glow
                g.fillOval(w / 2 - 300, h - 300, 600, 110);
                g.setColor(new Color(0x1E, 0x12, 0x38));
                g.fillOval(w / 2 - 280, h - 290, 560, 80);
                g.setColor(Color.WHITE);
                g.fillOval(w / 2 - 10, h - 300, 20, 34);
            }
            case "timeline" -> { // ghost ship on a black sea
                g.setColor(new Color(0x05, 0x03, 0x0C));
                g.fillRect(0, h - 200, w, 200);
                g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 160));
                g.fillPolygon(new int[] {w / 2 - 160, w / 2 + 160, w / 2 + 110, w / 2 - 110},
                        new int[] {h - 220, h - 220, h - 160, h - 160}, 4);
                g.drawLine(w / 2, h - 220, w / 2, h - 420);
                g.fillPolygon(new int[] {w / 2, w / 2 + 130, w / 2}, new int[] {h - 420, h - 330, h - 260}, 3);
            }
            case "rules" -> { // chained rune tablet
                g.fillRoundRect(w / 2 - 150, h / 2 - 60, 300, 380, 30, 30);
                g.setColor(new Color(0x14, 0x0B, 0x24));
                for (int i = 0; i < 5; i++) {
                    g.fillRect(w / 2 - 110, h / 2 + i * 64 - 20, 220, 18);
                }
                g.setColor(new Color(0x8A, 0x8A, 0x9A, 200));
                g.drawLine(w / 2 - 150, h / 2 - 40, 60, h - 60);
                g.drawLine(w / 2 + 150, h / 2 - 40, w - 60, h - 60);
            }
            case "rewards" -> { // dais with floating crystal shards
                g.fillArc(w / 2 - 260, h - 240, 520, 160, 0, 180);
                for (int i = 0; i < 5; i++) {
                    int cx = w / 2 - 160 + i * 80;
                    int cy = h - 340 - (i % 2) * 60;
                    g.fillPolygon(new int[] {cx, cx + 22, cx + 11}, new int[] {cy + 60, cy + 60, cy}, 3);
                }
            }
            case "bestiary" -> { // shadowed silhouettes with glinting eyes
                g.setColor(new Color(0x0A, 0x06, 0x16, 235));
                g.fillOval(160, h - 420, 180, 420);
                g.fillOval(430, h - 360, 160, 380);
                g.fillOval(680, h - 460, 200, 480);
                g.setColor(Color.WHITE);
                g.fillOval(230, h - 360, 10, 10);
                g.fillOval(260, h - 360, 10, 10);
                g.fillOval(500, h - 300, 8, 8);
                g.fillOval(760, h - 400, 12, 12);
            }
            default -> { // map: top-down disc with ring seams
                for (int r = 90; r <= 330; r += 80) {
                    g.drawOval(w / 2 - r, h / 2 - r + 60, 2 * r, 2 * r);
                }
                g.fillOval(w / 2 - 12, h / 2 + 48, 24, 24);
            }
        }

        g.setColor(new Color(255, 255, 255, 70));
        g.setFont(new Font(Font.SERIF, Font.BOLD, 44));
        g.drawString(id.toUpperCase(), 40, h - 36);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Rune circle node: 0 = locked (dark, cracked), 1 = unlocked (lit), 2 = current (blazing corona). */
    private static void writeTimelineNode(Path file, int state) throws IOException {
        int size = 96;
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

        Color ring = state == 0 ? new Color(0x4A, 0x3C, 0x66) : ACCENT;
        if (state == 2) {
            g.setPaint(new RadialGradientPaint(new Point2D.Float(48, 48), 46,
                    new float[] {0.55F, 1.0F},
                    new Color[] {new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 160), new Color(0, 0, 0, 0)}));
            g.fillOval(2, 2, 92, 92);
        }
        g.setColor(new Color(0x12, 0x0A, 0x20, 230));
        g.fillOval(16, 16, 64, 64);
        g.setColor(ring);
        g.setStroke(new BasicStroke(5.0F));
        g.drawOval(16, 16, 64, 64);
        // Rune ticks around the circle.
        for (int i = 0; i < 8; i++) {
            double a = i * Math.PI / 4;
            int x0 = 48 + (int) (Math.cos(a) * 26);
            int y0 = 48 + (int) (Math.sin(a) * 26);
            int x1 = 48 + (int) (Math.cos(a) * 32);
            int y1 = 48 + (int) (Math.sin(a) * 32);
            g.drawLine(x0, y0, x1, y1);
        }
        if (state == 0) { // crack
            g.setStroke(new BasicStroke(3.0F));
            g.setColor(new Color(0x0A, 0x05, 0x14));
            g.drawPolyline(new int[] {34, 46, 42, 56}, new int[] {24, 44, 58, 74}, 4);
        } else {
            g.setColor(state == 2 ? Color.WHITE : new Color(0xD8, 0xC4, 0xFF));
            g.fillOval(41, 41, 14, 14);
        }
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** 512x64 ornamental divider with a center eclipse motif. */
    private static void writeDivider(Path file) throws IOException {
        BufferedImage img = new BufferedImage(512, 64, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setPaint(new GradientPaint(0, 32, new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 0),
                180, 32, new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 220)));
        g.fillRect(10, 30, 210, 4);
        g.setPaint(new GradientPaint(512 - 180, 32, new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 220),
                502, 32, new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 0)));
        g.fillRect(292, 30, 210, 4);
        g.setColor(ACCENT);
        g.setStroke(new BasicStroke(4.0F));
        g.drawOval(238, 14, 36, 36);
        g.setColor(new Color(0x0A, 0x05, 0x14));
        g.fillOval(246, 22, 20, 20);
        g.setColor(ACCENT);
        g.fillOval(262, 16, 8, 8);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Pale violet arrow blade, tip exactly at the (0,0) hotspot, dark outline. */
    private static void writeCursorArrow(Path file) throws IOException {
        BufferedImage img = new BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        int[] xs = {0, 0, 6, 9, 14, 10, 16};
        int[] ys = {0, 21, 16, 24, 22, 14, 12};
        g.setColor(new Color(0x0C, 0x06, 0x18));
        g.fillPolygon(xs, ys, xs.length);
        g.setColor(new Color(0xD8, 0xC4, 0xFF));
        int[] xi = {2, 2, 6, 8, 11, 8, 12};
        int[] yi = {3, 17, 14, 20, 19, 12, 10};
        g.fillPolygon(xi, yi, xi.length);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Pointing hand, fingertip at the (8,0) hotspot. */
    private static void writeCursorHand(Path file) throws IOException {
        BufferedImage img = new BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(new Color(0x0C, 0x06, 0x18));
        g.fillRoundRect(6, 0, 6, 16, 5, 5); // index finger, tip at (8,0)
        g.fillRoundRect(4, 10, 18, 16, 8, 8); // fist
        g.setColor(new Color(0xD8, 0xC4, 0xFF));
        g.fillRoundRect(7, 1, 4, 14, 4, 4);
        g.fillRoundRect(5, 11, 16, 14, 7, 7);
        g.setColor(new Color(0x8A, 0x6C, 0xC8));
        g.drawLine(12, 13, 12, 20);
        g.drawLine(16, 13, 16, 20);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** Grabbing fist centered on the (16,16) hotspot. */
    private static void writeCursorGrab(Path file) throws IOException {
        BufferedImage img = new BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(new Color(0x0C, 0x06, 0x18));
        g.fillRoundRect(7, 9, 19, 16, 9, 9);
        g.setColor(new Color(0xD8, 0xC4, 0xFF));
        g.fillRoundRect(8, 10, 17, 14, 8, 8);
        g.setColor(new Color(0x8A, 0x6C, 0xC8));
        for (int i = 0; i < 4; i++) {
            g.drawLine(10 + i * 4, 11, 10 + i * 4, 16);
        }
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    /** 256x256 circular progress ring with runic segment marks; code draws the fill arc over it. */
    private static void writeAltarRing(Path file) throws IOException {
        int size = 256;
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(new Color(0x2A, 0x1C, 0x48, 220));
        g.setStroke(new BasicStroke(18.0F));
        g.drawOval(24, 24, 208, 208);
        g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 90));
        g.setStroke(new BasicStroke(2.5F));
        g.drawOval(14, 14, 228, 228);
        // Runic segment marks every 30 degrees.
        g.setStroke(new BasicStroke(4.0F));
        for (int i = 0; i < 12; i++) {
            double a = i * Math.PI / 6 - Math.PI / 2;
            int x0 = 128 + (int) (Math.cos(a) * 92);
            int y0 = 128 + (int) (Math.sin(a) * 92);
            int x1 = 128 + (int) (Math.cos(a) * 116);
            int y1 = 128 + (int) (Math.sin(a) * 116);
            g.setColor(new Color(ACCENT.getRed(), ACCENT.getGreen(), ACCENT.getBlue(), 160));
            g.drawLine(x0, y0, x1, y1);
        }
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    private static int clamp(int v) {
        return Math.max(0, Math.min(255, v));
    }
}
