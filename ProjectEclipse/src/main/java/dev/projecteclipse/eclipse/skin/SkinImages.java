package dev.projecteclipse.eclipse.skin;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

import javax.imageio.ImageIO;

/**
 * Server-side PNG validation and the vanilla legacy-skin conversion, implemented on
 * {@link BufferedImage} because the dedicated server has no {@code NativeImage}/GL stack.
 *
 * <p>Ported 1:1 from {@code SkinTextureDownloader#processLegacySkin} so a skin looks the
 * same here as it would if the vanilla client had downloaded it itself:</p>
 * <ul>
 *   <li>a 64×32 legacy sheet is grown to 64×64 and the right arm/leg are mirror-copied
 *       into the (new) left arm/leg boxes;</li>
 *   <li>the opaque base regions get their alpha forced to 255, so a skin with a
 *       semi-transparent body does not turn the player into a ghost;</li>
 *   <li>a legacy hat layer that is FULLY opaque (pre-1.8 skins had no alpha channel at all)
 *       is made fully transparent instead of rendering as a solid block around the head.</li>
 * </ul>
 *
 * <p>Both 64×64 and 64×32 inputs go through the same normalization, so what is written to
 * {@code config/eclipse/skins/&lt;uuid&gt;.png} is always a ready-to-bind 64×64 sheet.</p>
 */
public final class SkinImages {
    /** Every Minecraft skin sheet is 64 wide; the height tells legacy and modern apart. */
    public static final int SKIN_WIDTH = 64;

    private static final byte[] PNG_MAGIC = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};

    private SkinImages() {}

    /**
     * Validates {@code raw} as a Minecraft skin PNG and returns the normalized 64×64 sheet.
     *
     * @throws SkinException if the bytes are not a PNG, are not decodable, or do not carry
     *                       64×64 / 64×32 dimensions
     */
    public static byte[] normalize(byte[] raw) throws SkinException {
        int[] size = readPngHeader(raw);
        int width = size[0];
        int height = size[1];
        if (width != SKIN_WIDTH || (height != 64 && height != 32)) {
            throw new SkinException("dev.eclipse.skin.error.bad_size", width, height);
        }
        BufferedImage source;
        try {
            source = ImageIO.read(new ByteArrayInputStream(raw));
        } catch (IOException | RuntimeException e) {
            throw new SkinException("dev.eclipse.skin.error.decode", SkinHttp.describe(e));
        }
        if (source == null) {
            throw new SkinException("dev.eclipse.skin.error.decode", "no PNG reader");
        }

        boolean legacy = height == 32;
        BufferedImage image = new BufferedImage(64, 64, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < SKIN_WIDTH; x++) {
                image.setRGB(x, y, source.getRGB(x, y));
            }
        }
        if (legacy) {
            // Right leg box (0,16) → left leg box (16,48): every face moves +16/+32.
            copyRect(image, 4, 16, 16, 32, 4, 4);
            copyRect(image, 8, 16, 16, 32, 4, 4);
            copyRect(image, 0, 20, 24, 32, 4, 12);
            copyRect(image, 4, 20, 16, 32, 4, 12);
            copyRect(image, 8, 20, 8, 32, 4, 12);
            copyRect(image, 12, 20, 16, 32, 4, 12);
            // Right arm box (40,16) → left arm box (32,48): the destination sits to the LEFT
            // of the source, so these offsets are negative and differ per face.
            copyRect(image, 44, 16, -8, 32, 4, 4);
            copyRect(image, 48, 16, -8, 32, 4, 4);
            copyRect(image, 40, 20, 0, 32, 4, 12);
            copyRect(image, 44, 20, -8, 32, 4, 12);
            copyRect(image, 48, 20, -16, 32, 4, 12);
            copyRect(image, 52, 20, -8, 32, 4, 12);
        }
        setNoAlpha(image, 0, 0, 32, 16);
        if (legacy) {
            setAreaOpaque(image, 32, 0, 64, 32);
        }
        setNoAlpha(image, 0, 16, 64, 32);
        setNoAlpha(image, 16, 48, 48, 64);

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            if (!ImageIO.write(image, "PNG", out)) {
                throw new SkinException("dev.eclipse.skin.error.decode", "no PNG writer");
            }
        } catch (IOException e) {
            throw new SkinException("dev.eclipse.skin.error.decode", SkinHttp.describe(e));
        }
        return out.toByteArray();
    }

    /**
     * Content sniffing: PNG magic plus the IHDR width/height, read straight from the byte
     * stream so a non-image (an HTML error page served with {@code image/png}) is rejected
     * before any decoder touches it.
     */
    public static int[] readPngHeader(byte[] raw) throws SkinException {
        if (raw == null || raw.length < 24) {
            throw new SkinException("dev.eclipse.skin.error.not_png");
        }
        for (int i = 0; i < PNG_MAGIC.length; i++) {
            if (raw[i] != PNG_MAGIC[i]) {
                throw new SkinException("dev.eclipse.skin.error.not_png");
            }
        }
        if (raw[12] != 'I' || raw[13] != 'H' || raw[14] != 'D' || raw[15] != 'R') {
            throw new SkinException("dev.eclipse.skin.error.not_png");
        }
        return new int[] {readInt(raw, 16), readInt(raw, 20)};
    }

    private static int readInt(byte[] raw, int offset) {
        return ((raw[offset] & 0xFF) << 24) | ((raw[offset + 1] & 0xFF) << 16)
                | ((raw[offset + 2] & 0xFF) << 8) | (raw[offset + 3] & 0xFF);
    }

    /** Mirrored copy of a source rect to {@code (x + dx, y + dy)} (vanilla {@code copyRect}). */
    private static void copyRect(BufferedImage image, int x, int y, int dx, int dy, int width, int height) {
        for (int i = 0; i < width; i++) {
            for (int j = 0; j < height; j++) {
                image.setRGB(x + dx + i, y + dy + j, image.getRGB(x + width - 1 - i, y + j));
            }
        }
    }

    /** Forces alpha 255 over a rect given as {@code (x1, y1) → (x2, y2)}, exclusive. */
    private static void setNoAlpha(BufferedImage image, int x1, int y1, int x2, int y2) {
        for (int x = x1; x < x2; x++) {
            for (int y = y1; y < y2; y++) {
                image.setRGB(x, y, image.getRGB(x, y) | 0xFF00_0000);
            }
        }
    }

    /**
     * The pre-1.8 "no alpha channel" hack: if the whole overlay rect is opaque, the artist
     * never meant it as an overlay — clear it instead of rendering a box around the head.
     */
    private static void setAreaOpaque(BufferedImage image, int x1, int y1, int x2, int y2) {
        for (int x = x1; x < x2; x++) {
            for (int y = y1; y < y2; y++) {
                if ((image.getRGB(x, y) >>> 24) < 128) {
                    return;
                }
            }
        }
        for (int x = x1; x < x2; x++) {
            for (int y = y1; y < y2; y++) {
                image.setRGB(x, y, image.getRGB(x, y) & 0x00FF_FFFF);
            }
        }
    }
}
