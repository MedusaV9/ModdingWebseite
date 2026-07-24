import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import javax.imageio.ImageIO;

/**
 * Generates the 6-frame heart-burst programmer-art sheet and installs a tiny
 * valid placeholder OGG by copying the project's known-good submerge sample.
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/HeartBurstPlaceholder.java}
 */
public class HeartBurstPlaceholder {
    private static final int FRAME = 36;
    private static final int SCALE = 4;
    private static final int[][] HEART = {
            {1, 1, 1, 0, 1, 1, 1},
            {1, 1, 1, 1, 1, 1, 1},
            {1, 1, 1, 1, 1, 1, 1},
            {0, 1, 1, 1, 1, 1, 0},
            {0, 0, 1, 1, 1, 0, 0},
            {0, 0, 0, 1, 0, 0, 0}
    };

    public static void main(String[] args) throws IOException {
        BufferedImage sheet = new BufferedImage(FRAME * 6, FRAME, BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = sheet.createGraphics();
        graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_OFF);

        drawHeart(graphics, 0, new Color(255, 255, 255, 255), new Color(200, 150, 255, 255));
        drawHeart(graphics, 1, new Color(181, 74, 238, 255), new Color(77, 13, 103, 255));
        drawHeart(graphics, 2, new Color(162, 54, 218, 255), new Color(67, 10, 91, 255));
        drawCrack(graphics, 2, 1);
        drawHeart(graphics, 3, new Color(142, 39, 195, 255), new Color(52, 7, 73, 255));
        drawCrack(graphics, 3, 2);
        drawBrokenHeart(graphics, 4);
        drawShards(graphics, 5);
        graphics.dispose();

        Path texture = Path.of("src/main/resources/assets/eclipse/textures/gui/hearts/burst_sheet.png");
        Files.createDirectories(texture.getParent());
        ImageIO.write(sheet, "png", texture.toFile());

        Path sourceSound = Path.of("src/main/resources/assets/eclipse/sounds/event/submerge.ogg");
        Path targetSound = Path.of("src/main/resources/assets/eclipse/sounds/ui/heart_shatter.ogg");
        Files.createDirectories(targetSound.getParent());
        Files.copy(sourceSound, targetSound, StandardCopyOption.REPLACE_EXISTING);

        System.out.println("Generated " + texture + " (216x36) and " + targetSound);
    }

    private static void drawHeart(Graphics2D graphics, int frame, Color fill, Color outline) {
        int originX = frame * FRAME + 4;
        int originY = 5;
        for (int y = 0; y < HEART.length; y++) {
            for (int x = 0; x < HEART[y].length; x++) {
                if (HEART[y][x] == 0) {
                    continue;
                }
                boolean edge = y == 0 || x == 0 || x == HEART[y].length - 1
                        || (y + 1 < HEART.length && HEART[y + 1][x] == 0)
                        || (x > 0 && HEART[y][x - 1] == 0)
                        || (x + 1 < HEART[y].length && HEART[y][x + 1] == 0);
                graphics.setColor(edge ? outline : fill);
                graphics.fillRect(originX + x * SCALE, originY + y * SCALE, SCALE, SCALE);
            }
        }
        graphics.setColor(new Color(232, 174, 255, 220));
        graphics.fillRect(originX + 2 * SCALE, originY + SCALE, SCALE, SCALE);
    }

    private static void drawCrack(Graphics2D graphics, int frame, int severity) {
        int x = frame * FRAME + 18;
        graphics.setColor(new Color(255, 225, 255, 255));
        graphics.fillRect(x, 9, 2, 7);
        graphics.fillRect(x - 3, 15, 5, 2);
        graphics.fillRect(x - 3, 16, 2, 6);
        if (severity > 1) {
            graphics.fillRect(x - 7, 20, 6, 2);
            graphics.fillRect(x + 1, 14, 6, 2);
            graphics.fillRect(x + 5, 15, 2, 7);
        }
    }

    private static void drawBrokenHeart(Graphics2D graphics, int frame) {
        drawHeart(graphics, frame, new Color(126, 25, 176, 235), new Color(43, 4, 65, 255));
        int x = frame * FRAME + 17;
        graphics.setColor(new Color(0, 0, 0, 0));
        graphics.setComposite(java.awt.AlphaComposite.Clear);
        graphics.fillRect(x, 6, 4, 24);
        graphics.setComposite(java.awt.AlphaComposite.SrcOver);
        graphics.setColor(new Color(255, 210, 255, 255));
        graphics.fillRect(x - 1, 9, 2, 18);
        graphics.fillRect(x + 4, 12, 2, 14);
    }

    private static void drawShards(Graphics2D graphics, int frame) {
        int originX = frame * FRAME;
        Color[] colors = {
                new Color(246, 202, 255, 255),
                new Color(191, 89, 244, 255),
                new Color(112, 30, 169, 255)
        };
        for (int i = 0; i < 6; i++) {
            int x = originX + (i % 3) * 6;
            int y = 12 + (i / 3) * 6;
            graphics.setColor(colors[i % colors.length]);
            graphics.fillPolygon(
                    new int[] {x, x + 5, x + 2},
                    new int[] {y + 1, y, y + 5},
                    3);
        }
        graphics.setColor(new Color(116, 27, 169, 220));
        graphics.fillPolygon(new int[] {originX + 25, originX + 32, originX + 28},
                new int[] {6, 10, 18}, 3);
        graphics.fillPolygon(new int[] {originX + 23, originX + 30, originX + 27},
                new int[] {24, 28, 34}, 3);
    }
}
