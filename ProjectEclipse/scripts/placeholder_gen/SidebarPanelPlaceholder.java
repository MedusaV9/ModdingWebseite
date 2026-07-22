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
 * Programmer-art placeholders for the W8 sidebar panel (docs/ASSET_MANIFEST_V2.md Batch B):
 * the 64x64 nine-slice panel backdrop (8px corners, rounded dark glass + violet rim) and the
 * five 24x24 row icons (heart / day / altar / players / goal).
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/SidebarPanelPlaceholder.java}
 */
public class SidebarPanelPlaceholder {
    private static final Color RIM = new Color(0xB9, 0x8C, 0xFF, 255);
    private static final Color GLASS = new Color(10, 4, 22, 153); // ~60% black-violet
    private static final Color ICON_LIGHT = new Color(0xE6, 0xD2, 0xFF, 255);
    private static final Color ICON_MID = new Color(0xB9, 0x8C, 0xFF, 255);
    private static final Color ICON_DARK = new Color(0x4A, 0x20, 0x86, 255);

    public static void main(String[] args) throws IOException {
        Path dir = Path.of("src/main/resources/assets/eclipse/textures/gui/sidebar");
        Files.createDirectories(dir);

        writePanel(dir.resolve("panel.png"));
        writeIcon(dir.resolve("icon_heart.png"), SidebarPanelPlaceholder::paintHeart);
        writeIcon(dir.resolve("icon_day.png"), SidebarPanelPlaceholder::paintDay);
        writeIcon(dir.resolve("icon_altar.png"), SidebarPanelPlaceholder::paintAltar);
        writeIcon(dir.resolve("icon_players.png"), SidebarPanelPlaceholder::paintPlayers);
        writeIcon(dir.resolve("icon_goal.png"), SidebarPanelPlaceholder::paintGoal);

        System.out.println("Generated sidebar placeholders in " + dir);
    }

    /** 64x64 nine-slice: rounded dark glass with a thin violet rim; safe to stretch the 8px-inset center. */
    private static void writePanel(Path file) throws IOException {
        BufferedImage img = new BufferedImage(64, 64, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(GLASS);
        g.fillRoundRect(0, 0, 64, 64, 14, 14);
        g.setColor(RIM);
        g.setStroke(new BasicStroke(2.0F));
        g.drawRoundRect(1, 1, 61, 61, 12, 12);
        // Faint inner top highlight (kept inside the 8px corner band so stretching is safe).
        g.setColor(new Color(255, 255, 255, 26));
        g.fillRect(4, 3, 56, 2);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    private interface IconPainter {
        void paint(Graphics2D g);
    }

    private static void writeIcon(Path file, IconPainter painter) throws IOException {
        BufferedImage img = new BufferedImage(24, 24, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_OFF);
        painter.paint(g);
        g.dispose();
        ImageIO.write(img, "png", file.toFile());
    }

    private static void paintHeart(Graphics2D g) {
        int[][] rows = {{4, 9, 14, 19}, {3, 11, 12, 20}, {3, 20}, {4, 19}, {6, 17}, {8, 15}, {10, 13}};
        g.setColor(ICON_MID);
        for (int y = 0; y < rows.length; y++) {
            int[] r = rows[y];
            for (int i = 0; i + 1 < r.length; i += 2) {
                g.fillRect(r[i], 5 + y * 2, r[i + 1] - r[i], 2);
            }
        }
        g.setColor(ICON_LIGHT);
        g.fillRect(6, 7, 3, 3);
    }

    private static void paintDay(Graphics2D g) {
        g.setColor(ICON_MID);
        g.fillOval(4, 4, 16, 16);
        g.setColor(ICON_DARK);
        g.fillOval(7, 4, 16, 16); // occluding disc = eclipse sun
        g.setColor(ICON_LIGHT);
        g.drawOval(4, 4, 15, 15);
    }

    private static void paintAltar(Graphics2D g) {
        g.setColor(ICON_DARK);
        g.fillRect(3, 18, 18, 3);
        g.fillRect(6, 14, 12, 4);
        g.setColor(ICON_MID);
        g.fillRect(9, 9, 6, 5);
        g.setColor(ICON_LIGHT);
        g.fillRect(11, 3, 2, 6); // rising beam
    }

    private static void paintPlayers(Graphics2D g) {
        g.setColor(ICON_DARK);
        g.fillOval(3, 6, 8, 8);
        g.fillRect(2, 14, 10, 7);
        g.setColor(ICON_MID);
        g.fillOval(12, 4, 9, 9);
        g.fillRect(11, 13, 11, 8);
    }

    private static void paintGoal(Graphics2D g) {
        g.setColor(ICON_DARK);
        g.drawRect(3, 3, 17, 17);
        g.setColor(ICON_LIGHT);
        g.fillRect(6, 12, 3, 3);
        g.fillRect(8, 14, 3, 3);
        g.fillRect(10, 12, 3, 3);
        g.fillRect(12, 10, 3, 3);
        g.fillRect(14, 8, 3, 3);
        g.fillRect(16, 6, 3, 3);
    }
}
