import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;

/**
 * Shipped-quality PROCEDURAL pixel-art skins for the v2 mobs/bosses — the Batch D final-art
 * pass over the flat-color programmer art of {@code EntitySkinPlaceholder}. Every face rect
 * follows the box-UV layouts frozen in {@code docs/uv/<mob>.md} EXACTLY (same texture sizes,
 * same per-cube origins); only the pixels inside the rects change.
 *
 * <p>Technique (per {@code docs/ASSET_MANIFEST_V2.md} Batch D: "Boxy, readable,
 * Minecraft-native pixel density"): deterministic hash-dithered materials (cloth weave, fur
 * speckle, wood grain, glass/stone sheen), per-face directional shading (top lit, bottom
 * dark, sides mid), a 1px darker outline inside each face rect, and alpha-cutout ragged
 * bottoms on cloth strips. Emissive regions (gazer face, herald inner eye + telegraph
 * shards, sunmote, ferryman eye slit / flame / lantern) are painted UNSHADED at full
 * brightness — they re-render additively via {@code RenderType.eyes}, so the surrounding
 * albedo stays dark to make the glow pass pop.</p>
 *
 * <p>{@code the_other.png} is NOT painted here anymore: it is final art, generated (as an
 * exact two-delta derivative of the shipped {@code eclipsed_player.png} — spec §1.1:
 * pure-black eyes and a faint purple face seam) by
 * {@code scripts/skin_gen/eclipsed_player_v2.py}. See {@link #writeTheOther()}.</p>
 *
 * Run from the ProjectEclipse root:
 * {@code java scripts/placeholder_gen/EntitySkinArtist.java}
 */
public class EntitySkinArtist {
    private static final Path DIR = Path.of("src/main/resources/assets/eclipse/textures/entity");
    /** Fixed dither seed — every run produces byte-identical pixels. */
    private static final int SEED = 0x0EC11B5E;

    private enum Face { TOP, BOTTOM, EAST, NORTH, WEST, SOUTH }

    /** Per-pixel albedo callback; return {@code null} to leave the pixel transparent. */
    @FunctionalInterface
    private interface Paint {
        Color at(Face face, int fx, int fy, int fw, int fh, int gx, int gy);
    }

    public static void main(String[] args) throws IOException {
        Files.createDirectories(DIR);
        writeTheOther();
        writeGazer();
        writeUmbralStalker();
        writeDeckhand();
        writeSunmote();
        writeHerald();
        writeFerryman();
        System.out.println("Painted 6 entity skins in " + DIR + " (the_other.png skipped — final art)");
    }

    // ------------------------------------------------------------------
    // deterministic noise + color helpers
    // ------------------------------------------------------------------

    /** Deterministic integer hash of (x, y, salt) under the fixed {@link #SEED}. */
    private static int hash(int x, int y, int salt) {
        int h = SEED ^ (x * 0x27D4EB2D) ^ (y * 0x9E3779B9) ^ (salt * 0x85EBCA6B);
        h ^= h >>> 15;
        h *= 0x2C1B3C6D;
        h ^= h >>> 12;
        h *= 0x297A2D39;
        h ^= h >>> 15;
        return h;
    }

    /** Hash mapped to [0,1). */
    private static float noise(int x, int y, int salt) {
        return (hash(x, y, salt) >>> 8) / (float) (1 << 24);
    }

    private static Color c(int rgb) {
        return new Color((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
    }

    private static Color mul(Color color, float f) {
        return new Color(
                Math.min(255, Math.max(0, (int) (color.getRed() * f))),
                Math.min(255, Math.max(0, (int) (color.getGreen() * f))),
                Math.min(255, Math.max(0, (int) (color.getBlue() * f))));
    }

    private static Color mix(Color a, Color b, float t) {
        return new Color(
                (int) (a.getRed() + (b.getRed() - a.getRed()) * t),
                (int) (a.getGreen() + (b.getGreen() - a.getGreen()) * t),
                (int) (a.getBlue() + (b.getBlue() - a.getBlue()) * t));
    }

    /**
     * Cloth/fur dither. {@code dir} 0 = fine grain, 1 = vertical streaks (hanging weave),
     * 2 = horizontal bands (waterlogged sag). Amp is the total brightness swing.
     */
    private static Color weave(Color base, int gx, int gy, int salt, int dir, float amp) {
        float streak = switch (dir) {
            case 1 -> noise(gx, gy / 3, salt);
            case 2 -> noise(gx / 3, gy, salt);
            default -> noise(gx, gy, salt);
        };
        float fine = noise(gx, gy, salt + 101);
        float v = 0.72F * streak + 0.28F * fine - 0.5F;
        return mul(base, 1.0F + v * amp);
    }

    /** Vertical wood grain: long tonal runs along y plus rare dark pores. */
    private static Color wood(Color base, int gx, int gy, int salt) {
        float g = noise(gx, gy / 4, salt);
        Color col = g < 0.33F ? mul(base, 0.82F) : g < 0.72F ? base : mul(base, 1.16F);
        if (noise(gx, gy, salt + 5) > 0.96F) {
            col = mul(col, 0.6F);
        }
        return col;
    }

    // ------------------------------------------------------------------
    // box-UV painting core
    // ------------------------------------------------------------------

    /** Directional light: top faces read lit, bottoms shadowed, N/S/E/W mid. */
    private static float dirShade(Face f) {
        return switch (f) {
            case TOP -> 1.18F;
            case BOTTOM -> 0.62F;
            case NORTH -> 1.0F;
            case EAST, WEST -> 0.86F;
            case SOUTH -> 0.74F;
        };
    }

    private static void cube(BufferedImage img, int u, int v, int w, int h, int d, Paint paint) {
        cube(img, u, v, w, h, d, paint, 0.76F, true);
    }

    /**
     * Paints all six face rects of a box-UV cube (order: top, bottom, east, north, west,
     * south — exactly the rect tables in {@code docs/uv/*.md}). {@code outline} multiplies
     * the 1px border inside each face (1.0 = none); {@code shaded} toggles directional
     * shading (off for emissive cubes, which must stay at painted full brightness).
     */
    private static void cube(BufferedImage img, int u, int v, int w, int h, int d, Paint paint,
            float outline, boolean shaded) {
        face(img, u + d, v, w, d, Face.TOP, paint, outline, shaded);
        face(img, u + d + w, v, w, d, Face.BOTTOM, paint, outline, shaded);
        face(img, u, v + d, d, h, Face.EAST, paint, outline, shaded);
        face(img, u + d, v + d, w, h, Face.NORTH, paint, outline, shaded);
        face(img, u + d + w, v + d, d, h, Face.WEST, paint, outline, shaded);
        face(img, u + d + w + d, v + d, w, h, Face.SOUTH, paint, outline, shaded);
    }

    private static void face(BufferedImage img, int x, int y, int w, int h, Face f, Paint paint,
            float outline, boolean shaded) {
        for (int fy = 0; fy < h; fy++) {
            for (int fx = 0; fx < w; fx++) {
                Color col = paint.at(f, fx, fy, w, h, x + fx, y + fy);
                if (col == null) {
                    continue; // transparent (ragged cut / ring hole / open cowl)
                }
                float k = shaded ? dirShade(f) : 1.0F;
                // 1px darker outline inside the rect; skipped on faces too small to hold one.
                if (w > 2 && h > 2 && (fx == 0 || fx == w - 1 || fy == 0 || fy == h - 1)) {
                    k *= outline;
                }
                img.setRGB(x + fx, y + fy, mul(col, k).getRGB() | 0xFF000000);
            }
        }
    }

    // ------------------------------------------------------------------
    // ragged cloth strips (alpha-cutout bottoms)
    // ------------------------------------------------------------------

    /** Per-column bottom cut depths (0..maxCut px) for ragged strip hems. */
    private static int[] raggedCuts(int columns, int maxCut, int salt) {
        int[] cuts = new int[columns];
        for (int i = 0; i < columns; i++) {
            float n = noise(i, 0, salt);
            cuts[i] = n < 0.35F ? 0 : n < 0.75F ? 1 : maxCut;
        }
        cuts[columns / 2] = Math.min(cuts[columns / 2], 1); // keep an anchor column
        return cuts;
    }

    /**
     * True if a strip pixel falls inside its column's ragged cut. The south face mirrors
     * the north silhouette; the bottom face loses every cut column so nothing floats.
     */
    private static boolean cutRagged(Face f, int fx, int fy, int fh, int[] cuts) {
        int last = cuts.length - 1;
        if (f == Face.TOP) {
            return false;
        }
        if (f == Face.BOTTOM) {
            return cuts[Math.min(fx, last)] > 0;
        }
        int col = switch (f) {
            case SOUTH -> last - Math.min(fx, last);
            case EAST -> 0;
            case WEST -> last;
            default -> Math.min(fx, last);
        };
        return fy >= fh - cuts[col];
    }

    /** Hanging cloth strip with a ragged alpha bottom (gazer tatters, ferryman hem strips). */
    private static Paint clothStrip(Color base, int[] cuts, int salt) {
        return (f, fx, fy, fw, fh, gx, gy) -> {
            if (cutRagged(f, fx, fy, fh, cuts)) {
                return null;
            }
            Color col = weave(base, gx, gy, salt, 1, 0.32F);
            if (f != Face.TOP && f != Face.BOTTOM && fy >= fh - 2) {
                col = mul(col, 0.85F); // frayed, damp tip
            }
            return col;
        };
    }

    private static BufferedImage canvas(int size) {
        return new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
    }

    // ------------------------------------------------------------------
    // the other (64x64, vanilla player-skin layout) — RETIRED, see below
    // ------------------------------------------------------------------

    /**
     * DELIBERATE NO-OP (WB-GHOSTFX, per P6-W12 wiring note 4): {@code the_other.png} is
     * final art now, regenerated — with the same two frozen doppelganger deltas (pure-black
     * 2x2 eyes at face cols 1-2/5-6 rows 11-12; {@code #8367A8} seam down face col 3 rows
     * 8-15) at the same coordinates/colors — by {@code scripts/skin_gen/eclipsed_player_v2.py}
     * from the shipped {@code eclipsed_player.png}. The old input this method derived from,
     * {@code uniform_skin.png}, was deleted with the v2 skin, so the previous implementation
     * crashed on {@code ImageIO.read} if this generator was re-run. Kept as a guard so
     * re-running the Batch D painter can never crash on, or clobber, the shipped skin family.
     */
    private static void writeTheOther() {
        System.out.println("the_other.png skipped (final art — owned by scripts/skin_gen/eclipsed_player_v2.py)");
    }

    // ------------------------------------------------------------------
    // gazer (64x64) — tattered void-cloak weave, black hood interior, violet emissive face
    // ------------------------------------------------------------------

    private static void writeGazer() throws IOException {
        BufferedImage img = canvas(64);
        Color cloakC = c(0x2A2440);
        Color hoodC = c(0x1E1A30);
        Color mantleC = c(0x3A3358);
        Color tatterC = c(0x241F38);

        // Cloak: vertical weave streaks, damp darkened hem, ragged 1px hem notches.
        cube(img, 0, 0, 10, 18, 6, (f, fx, fy, fw, fh, gx, gy) -> {
            boolean side = f != Face.TOP && f != Face.BOTTOM;
            if (side && fy == fh - 1 && noise(gx, 7, 11) > 0.62F) {
                return null;
            }
            Color col = weave(cloakC, gx, gy, 10, 1, 0.30F);
            if (side && fy >= fh - 4) {
                col = mul(col, 1.0F - 0.06F * (fy - (fh - 4)));
            }
            return col;
        });

        // Hood: weave shell, pure-black interior behind the floating face plate, and
        // cowl-depth darkening on the columns/rows bordering the open front.
        cube(img, 32, 0, 8, 8, 8, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                boolean rim = fx == 0 || fx == fw - 1 || fy == 0 || fy == fh - 1;
                return rim ? weave(hoodC, gx, gy, 12, 1, 0.25F) : c(0x050308);
            }
            Color col = weave(hoodC, gx, gy, 12, 1, 0.28F);
            boolean frontEdge = (f == Face.EAST && fx == fw - 1) || (f == Face.WEST && fx == 0)
                    || (f == Face.TOP && fy == fh - 1);
            return frontEdge ? mul(col, 0.7F) : col;
        });

        // Face plate: EMISSIVE (GazerRenderer.FaceEyesLayer) — pale violet mask at full
        // brightness, hot center, hairline mask cracks, hollow eye slits per docs/uv.
        Color plate = c(0xE6D9FA);
        Color plateHot = c(0xF7F0FF);
        Color plateDim = c(0xB9A6DC);
        cube(img, 32, 16, 6, 6, 1, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                if ((gx == 34 || gx == 37) && (gy == 19 || gy == 20)) {
                    return c(0x141020); // hollow eye slits
                }
                if (fx == 0 || fx == fw - 1 || fy == 0 || fy == fh - 1) {
                    return mix(plate, plateDim, 0.5F);
                }
                Color col = Math.max(Math.abs(2 * fx - (fw - 1)), Math.abs(2 * fy - (fh - 1))) <= 2
                        ? plateHot : plate;
                return noise(gx, gy, 13) > 0.93F ? mix(col, plateDim, 0.6F) : col;
            }
            return f == Face.SOUTH ? c(0x6A5A8E) : plateDim; // back + 1px edges dimmer
        }, 1.0F, false);

        cube(img, 0, 24, 3, 8, 1, clothStrip(tatterC, raggedCuts(3, 2, 21), 22));
        cube(img, 10, 24, 3, 8, 1, clothStrip(tatterC, raggedCuts(3, 2, 23), 24));

        // Mantle: heavier slab weave with worn sheen flecks on top.
        cube(img, 0, 40, 12, 3, 8, (f, fx, fy, fw, fh, gx, gy) -> {
            Color col = weave(mantleC, gx, gy, 14, 1, 0.26F);
            if (f == Face.TOP && noise(gx, gy, 15) > 0.9F) {
                col = mix(col, c(0x574C82), 0.7F);
            }
            return col;
        });
        ImageIO.write(img, "png", DIR.resolve("gazer.png").toFile());
    }

    // ------------------------------------------------------------------
    // umbral stalker (64x64) — obsidian fur w/ violet speckle, crystal spine, glass jaw
    // ------------------------------------------------------------------

    /** Near-black fur with sparse violet speckle — moon-catching obsidian sheen. */
    private static Paint fur(Color base, int salt) {
        return (f, fx, fy, fw, fh, gx, gy) -> {
            Color col = mul(base, 1.0F + (noise(gx, gy, salt) - 0.5F) * 0.24F);
            float sp = noise(gx, gy, salt + 1);
            if (sp > 0.965F) {
                return mix(col, c(0x8A66D8), 0.75F);
            }
            if (sp > 0.90F) {
                return mix(col, c(0x4E3A78), 0.6F);
            }
            return col;
        };
    }

    private static void writeUmbralStalker() throws IOException {
        BufferedImage img = canvas(64);
        Color bodyC = c(0x221A2E);
        Color headC = c(0x2A2038);
        Color legC = c(0x1C1626);

        cube(img, 0, 0, 8, 7, 14, fur(bodyC, 30));

        // Head: fur plus two violet eye pinpricks (hot dot + dim under-glow smear).
        Paint headFur = fur(headC, 31);
        cube(img, 0, 21, 7, 6, 8, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH && (gx == 10 || gx == 12)) {
                if (gy == 30) {
                    return c(0xE8D8FF);
                }
                if (gy == 31) {
                    return c(0x6A4EA8);
                }
            }
            return headFur.at(f, fx, fy, fw, fh, gx, gy);
        });

        // Jaw shards: black volcanic glass — near-black taper with one violet glint at the
        // root so they still read hanging under the muzzle (brief: "black-glass jaw").
        Paint glass = (f, fx, fy, fw, fh, gx, gy) -> {
            if (fy == 0) {
                return f == Face.NORTH ? c(0x9C86CC) : c(0x3A2E58); // specular glint
            }
            if (fy == fh - 1 && fh >= 3) {
                return c(0x060409); // fang tip fades to black
            }
            return mix(c(0x140E20), c(0x241A38), noise(gx, gy, 33));
        };
        cube(img, 30, 21, 1, 3, 1, glass, 1.0F, true);
        cube(img, 36, 21, 1, 3, 1, glass, 1.0F, true);

        // Legs: darker fur, toe shadow notches on the last row.
        Paint legFur = fur(legC, 32);
        for (int u : new int[] {0, 12, 24, 36}) {
            cube(img, u, 35, 3, 8, 3, (f, fx, fy, fw, fh, gx, gy) -> {
                if (f != Face.TOP && f != Face.BOTTOM && fy == fh - 1 && gx % 2 == 0) {
                    return c(0x0E0A14);
                }
                return legFur.at(f, fx, fy, fw, fh, gx, gy);
            });
        }

        // Spine shards: bright violet crystal — lit/dark facet columns, hot tip, internal
        // crack + sparkle pixels; unshaded so the albedo itself reads as glowing (no
        // emissive layer on this mob per docs/uv).
        Paint crystal = (f, fx, fy, fw, fh, gx, gy) -> {
            if (fy == 0) {
                return c(0xE2D2FF);
            }
            Color col = fx == 0 ? c(0xB08CFF) : c(0x7A55E0);
            if (fy == fh - 1) {
                return mix(col, headC, 0.55F); // rooted in the fur
            }
            if (noise(gx, gy, 35) > 0.88F) {
                return mix(col, c(0x4A2E86), 0.7F);
            }
            if (noise(gx, gy, 36) > 0.9F) {
                return mix(col, c(0xD8C2FF), 0.7F);
            }
            return col;
        };
        cube(img, 44, 0, 2, 4, 2, crystal, 1.0F, false);
        cube(img, 44, 6, 2, 5, 2, crystal, 1.0F, false);
        cube(img, 44, 13, 2, 4, 2, crystal, 1.0F, false);
        ImageIO.write(img, "png", DIR.resolve("umbral_stalker.png").toFile());
    }

    // ------------------------------------------------------------------
    // deckhand (64x64) — grey-violet waterlogged robes, rope bands, hollow black hood
    // ------------------------------------------------------------------

    private static void writeDeckhand() throws IOException {
        BufferedImage img = canvas(64);
        Color robeC = c(0x3B3844);
        Color torsoC = c(0x312E3A);
        Color armC = c(0x363340);
        Color hoodC = c(0x232029);
        Color rope = c(0x6E6254);
        Color ropeD = c(0x5A5044);

        // Torso: horizontal waterlogged sag bands + a rope chest wrap at the waist.
        cube(img, 0, 0, 8, 10, 4, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f != Face.TOP && f != Face.BOTTOM && (fy == 6 || fy == 7)) {
                return (gx + fy) % 3 == 0 ? ropeD : rope; // twisted rope dashes
            }
            return weave(torsoC, gx, gy, 40, 2, 0.26F);
        });

        // Head: pure shadow under the hood, two faint pale eyes. Unshaded/no outline so the
        // hollow stays featureless black. (docs/uv places the eyes at (38,11)+(41,11), but
        // (41,11) falls outside the head's north face (32,8)-(40,16) — painted symmetric at
        // (34,11)+(37,11) instead, vanilla eye columns of an 8px face.)
        cube(img, 24, 0, 8, 8, 8, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH && gy == 11 && (gx == 34 || gx == 37)) {
                return c(0x9C97AC);
            }
            return mul(c(0x0C0B10), 1.0F + (noise(gx, gy, 41) - 0.5F) * 0.1F);
        }, 1.0F, false);

        // Arms: sagging sleeve weave with a rope cuff row above the wrist.
        Paint arm = (f, fx, fy, fw, fh, gx, gy) -> {
            if (f != Face.TOP && f != Face.BOTTOM && fy == 8) {
                return gx % 2 == 0 ? ropeD : rope;
            }
            return weave(armC, gx, gy, 42, 2, 0.24F);
        };
        cube(img, 0, 14, 3, 10, 3, arm);
        cube(img, 12, 14, 3, 10, 3, arm);

        // Robe: rope belt near the top, water-stain gradient toward the deck, mildew flecks.
        cube(img, 24, 16, 8, 8, 6, (f, fx, fy, fw, fh, gx, gy) -> {
            boolean side = f != Face.TOP && f != Face.BOTTOM;
            if (side && (fy == 1 || fy == 2)) {
                return (gx + fy) % 3 == 0 ? ropeD : rope;
            }
            Color col = weave(robeC, gx, gy, 43, 2, 0.28F);
            if (side && fy >= 5) {
                col = mul(col, 0.94F - 0.05F * (fy - 5));
            }
            if (noise(gx, gy, 44) > 0.96F) {
                col = mix(col, c(0x4E5548), 0.6F); // mildew
            }
            return col;
        });

        // Oar shaft: dark waterlogged wood grain.
        cube(img, 56, 16, 1, 22, 1, (f, fx, fy, fw, fh, gx, gy) ->
                wood(c(0x5A452E), gx, gy, 45));

        // Hood: open cowl — 1px fabric rim around a transparent front window so the shadow
        // head + faint eyes behind it stay visible ("hollow hood" brief; the placeholder's
        // opaque front hid the head entirely). Cowl-depth darkening on front-adjacent edges.
        cube(img, 0, 27, 8, 8, 8, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                boolean rim = fx == 0 || fx == fw - 1 || fy == 0 || fy == fh - 1;
                return rim ? weave(hoodC, gx, gy, 46, 2, 0.24F) : null;
            }
            Color col = weave(hoodC, gx, gy, 46, 2, 0.24F);
            boolean frontEdge = (f == Face.EAST && fx == fw - 1) || (f == Face.WEST && fx == 0)
                    || (f == Face.TOP && fy == fh - 1);
            return frontEdge ? mul(col, 0.72F) : col;
        });
        ImageIO.write(img, "png", DIR.resolve("deckhand.png").toFile());
    }

    // ------------------------------------------------------------------
    // sunmote (32x32) — radiant violet-gold core + halo ring, everything fullbright
    // ------------------------------------------------------------------

    private static void writeSunmote() throws IOException {
        BufferedImage img = canvas(32);
        // Whole model is fullbright + gets an additive whole-model eyes pass: no shading,
        // no outlines, no dark pixels anywhere (they go muddy under the additive pass).
        Paint core = (f, fx, fy, fw, fh, gx, gy) -> {
            if ((hash(gx, gy, 60) & 3) == 0) {
                return c(0xF4E6FF); // violet-white shimmer
            }
            return (fx + fy) % 2 == 0 ? c(0xFFF8DC) : c(0xFFE9A8);
        };
        cube(img, 0, 0, 2, 2, 2, core, 1.0F, false);

        // Halo plate: the 2x2 center of the top/bottom faces is cut to alpha so the plate
        // renders as a true ring hugging the core; rim faces stay warm gold.
        Paint halo = (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.TOP || f == Face.BOTTOM) {
                if (fx >= 1 && fx <= 2 && fy >= 1 && fy <= 2) {
                    return null; // ring hole
                }
                boolean corner = (fx == 0 || fx == 3) && (fy == 0 || fy == 3);
                if (corner) {
                    return c(0xF5A83A);
                }
                return (fx + fy) % 2 == 0 ? c(0xFFD25E) : c(0xF8DCEF); // gold/violet inner edge
            }
            return (hash(gx, gy, 61) & 3) == 0 ? c(0xFFE8C8) : c(0xFFD478);
        };
        cube(img, 0, 4, 4, 1, 4, halo, 1.0F, false);
        ImageIO.write(img, "png", DIR.resolve("sunmote.png").toFile());
    }

    // ------------------------------------------------------------------
    // herald (128x128) — obsidian godhead, violet inner eye, stained-glass corona shards
    // ------------------------------------------------------------------

    private static void writeHerald() throws IOException {
        BufferedImage img = canvas(128);

        // Core: black volcanic glass with a faint diagonal polish sheen.
        cube(img, 0, 0, 12, 12, 12, (f, fx, fy, fw, fh, gx, gy) -> {
            Color col = mul(c(0x181224), 1.0F + (noise(gx, gy, 80) - 0.5F) * 0.18F);
            if ((gx + gy) % 7 == 0 && noise(gx, gy, 81) > 0.5F) {
                col = mix(col, c(0x342A52), 0.55F);
            }
            return col;
        });

        // Gold crack veins across the core's north face (12,12)-(24,24): a main fissure
        // with branches, dimming toward the tips; plus stray glints on the top face.
        int vein = c(0xE8A83A).getRGB() | 0xFF000000;
        int veinDim = c(0xA87826).getRGB() | 0xFF000000;
        int[][] trunk = {{17, 12}, {17, 13}, {16, 14}, {16, 15}, {15, 16}, {15, 17},
                {16, 18}, {16, 19}, {17, 20}, {17, 21}, {18, 22}, {18, 23}};
        int[][] branches = {{18, 14}, {19, 13}, {20, 13}, {14, 16}, {17, 18}, {18, 18},
                {19, 19}, {20, 19}, {15, 20}, {14, 21}};
        int[][] tips = {{21, 12}, {13, 15}, {21, 20}, {13, 22}};
        for (int[] p : trunk) {
            img.setRGB(p[0], p[1], vein);
        }
        for (int[] p : branches) {
            img.setRGB(p[0], p[1], vein);
        }
        for (int[] p : tips) {
            img.setRGB(p[0], p[1], veinDim);
        }
        img.setRGB(16, 4, veinDim);
        img.setRGB(20, 8, veinDim);

        // Inner eye: EMISSIVE always (HeraldRenderer.EmissiveLayer) — blazing violet iris
        // rings around a 2x2 void pupil, painted unshaded at full brightness.
        cube(img, 48, 0, 6, 6, 6, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                if (gx >= 56 && gx <= 57 && gy >= 8 && gy <= 9) {
                    return c(0x100A18); // void pupil
                }
                int px = gx < 56 ? 56 : 57;
                int py = gy < 8 ? 8 : 9;
                if (Math.max(Math.abs(gx - px), Math.abs(gy - py)) <= 1) {
                    return c(0xF6E8FF); // white-hot ring around the pupil
                }
                boolean edge = fx == 0 || fx == fw - 1 || fy == 0 || fy == fh - 1;
                return edge ? c(0xC08CFF) : c(0xE4C6FF);
            }
            int ring = Math.max(Math.abs(2 * fx - (fw - 1)), Math.abs(2 * fy - (fh - 1)));
            Color col = ring <= 1 ? c(0xEBD8FF) : ring <= 3 ? c(0xC79CFF) : c(0xA97EE8);
            return f == Face.TOP || f == Face.BOTTOM ? mix(col, c(0x9A70D8), 0.35F) : col;
        }, 1.0F, false);

        // Corona shards: cracked stained glass — bright violet edge column, deeper facet
        // column, hot tip row, dark crack web. Unshaded; they join the eyes pass during
        // volley telegraphs, so the saturated albedo doubles up and flares.
        Paint shard = (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.TOP || f == Face.BOTTOM) {
                return c(0xE0C8FF);
            }
            if (fy == 0) {
                return c(0xF2E6FF);
            }
            Color col = fx == 0 ? c(0xD2AEFF) : c(0xA170F0);
            if (fy == fh - 1) {
                return mix(col, c(0x8A5CD8), 0.5F);
            }
            return noise(gx, gy, 82) > 0.82F ? mix(col, c(0x6A44B8), 0.75F) : col;
        };
        for (int i = 0; i < 8; i++) {
            cube(img, i * 8, 32, 2, 6, 2, shard, 1.0F, false);
        }

        // Tentacles: dark umbral chain — alternating 2-row link bands, faint violet glint
        // per link, each segment darker toward the chain tip (k = seg index within chain).
        for (int s = 0; s < 16; s++) {
            int k = s % 4;
            Color base = mul(c(0x241C36), 1.0F - k * 0.06F);
            cube(img, s * 8, 44, 2, 6, 2, (f, fx, fy, fw, fh, gx, gy) -> {
                if (f == Face.TOP || f == Face.BOTTOM) {
                    return mul(base, 0.9F);
                }
                boolean link = (fy / 2) % 2 == 0;
                Color col = mul(base, link ? 1.14F : 0.82F);
                if (link && fx == 0 && fy % 2 == 0 && noise(gx, gy, 83) > 0.6F) {
                    return mix(col, c(0x4E3E78), 0.7F);
                }
                return col;
            }, 1.0F, true);
        }
        ImageIO.write(img, "png", DIR.resolve("herald.png").toFile());
    }

    // ------------------------------------------------------------------
    // ferryman (128x128) — bone skull in an open cowl, rotted robe, oar, verdigris lantern
    // ------------------------------------------------------------------

    private static void writeFerryman() throws IOException {
        BufferedImage img = canvas(128);
        Color robeC = c(0x202C28);
        Color hoodC = c(0x141B18);
        Color sleeveC = c(0x26332E);
        Color bone = c(0xD8D2BE);
        Color barnacle = c(0x5E7466);

        // Robe body: vertical wool folds (per-column highlight/shadow), barnacle flecks,
        // water-stain gradient toward the hem, ragged 1px hem notches.
        cube(img, 0, 0, 10, 26, 8, (f, fx, fy, fw, fh, gx, gy) -> {
            boolean side = f != Face.TOP && f != Face.BOTTOM;
            if (side && fy == fh - 1 && noise(gx, 7, 70) > 0.6F) {
                return null;
            }
            Color col = weave(robeC, gx, gy, 71, 1, 0.26F);
            float fold = noise(gx, 0, 72);
            if (fold > 0.85F) {
                col = mul(col, 1.12F);
            } else if (fold < 0.12F) {
                col = mul(col, 0.86F);
            }
            if (side && fy > fh / 2) {
                col = mul(col, 1.0F - 0.18F * (fy - fh / 2.0F) / (fh / 2.0F));
            }
            float b = noise(gx, gy, 73);
            if (b > 0.985F) {
                return mix(col, c(0x7E9484), 0.8F);
            }
            if (b > 0.955F) {
                return mix(col, barnacle, 0.7F);
            }
            return col;
        });

        // Ragged hem strips (rotted robe strips — alpha-cutout bottoms).
        for (int i = 0; i < 4; i++) {
            cube(img, 32 + i * 8, 36, 2, 6, 1, clothStrip(c(0x18221E), raggedCuts(2, 2, 74 + i), 78 + i));
        }

        // Hood: the north face is FULLY transparent (open cowl — the skull shows inside,
        // required by docs/uv/ferryman.md); front-adjacent edges darkened for cowl depth.
        cube(img, 40, 0, 9, 9, 9, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                return null;
            }
            Color col = weave(hoodC, gx, gy, 84, 1, 0.24F);
            boolean frontEdge = (f == Face.EAST && fx == fw - 1) || (f == Face.WEST && fx == 0)
                    || (f == Face.TOP && fy == fh - 1);
            return frontEdge ? mul(col, 0.68F) : col;
        });

        // Skull: dithered old bone, hollow 2x2 sockets, nasal pit, worn tooth row, faint
        // hairline cracks on the side faces.
        cube(img, 80, 0, 7, 7, 7, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                boolean socket = (gy == 9 || gy == 10) && (gx == 88 || gx == 89 || gx == 91 || gx == 92);
                if (socket) {
                    return c(0x0E1410);
                }
                if (gx == 90 && gy == 12) {
                    return c(0x0E1410); // nasal pit
                }
                if (gy == 13 && gx >= 88 && gx <= 92) {
                    return gx % 2 == 0 ? c(0xC8C0A8) : c(0x8A8270); // tooth row
                }
                if (gy == 8) {
                    return mul(bone, 0.82F); // brow shadow
                }
            }
            Color col = mul(bone, 1.0F + (noise(gx, gy, 85) - 0.5F) * 0.14F);
            if (f != Face.NORTH && noise(gx, gy, 86) > 0.95F) {
                return mix(col, c(0xA09880), 0.8F);
            }
            return col;
        });

        // Eye slit: EMISSIVE always — burning soul teal, white-hot center pixels.
        cube(img, 108, 0, 5, 2, 1, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH) {
                return fx >= 1 && fx <= 3 ? c(0xE6FFF8) : c(0x8FF2DE);
            }
            return c(0x7EE2CE);
        }, 1.0F, false);

        // Arms: sleeve weave with vertical folds and rare barnacle growth.
        Paint sleeve = (f, fx, fy, fw, fh, gx, gy) -> {
            Color col = weave(sleeveC, gx, gy, 87, 1, 0.24F);
            float fold = noise(gx, 0, 88);
            if (fold > 0.8F) {
                col = mul(col, 1.1F);
            }
            return noise(gx, gy, 89) > 0.975F ? mix(col, barnacle, 0.6F) : col;
        };
        cube(img, 0, 36, 3, 20, 3, sleeve);
        cube(img, 16, 36, 3, 20, 3, sleeve);

        // Oar shaft: ancient wood grain, worn-bright grip band mid-shaft (where the hands
        // ride), two dark knots with lighter rings.
        cube(img, 64, 36, 2, 36, 2, (f, fx, fy, fw, fh, gx, gy) -> {
            if (f == Face.NORTH && gx == 66) {
                if (gy == 47 || gy == 60) {
                    return c(0x2A2014); // knots
                }
                if (gy == 46 || gy == 48 || gy == 59 || gy == 61) {
                    return c(0x5C4A34);
                }
            }
            Color col = wood(c(0x4A3A28), gx, gy, 90);
            if (f != Face.TOP && f != Face.BOTTOM && fy >= 15 && fy <= 21) {
                col = mul(col, 1.12F); // grip wear
            }
            return col;
        });

        // Blade: waterlogged dark wood, worn bright bottom edge, barnacle flecks.
        cube(img, 76, 36, 1, 6, 5, (f, fx, fy, fw, fh, gx, gy) -> {
            Color col = wood(c(0x3C2F20), gx, gy, 93);
            if (f != Face.TOP && f != Face.BOTTOM && fy == fh - 1) {
                return mix(col, c(0x6A5844), 0.5F);
            }
            return noise(gx, gy, 94) > 0.95F ? mix(col, barnacle, 0.6F) : col;
        });

        // Chain: wet iron links — alternating row shading, pale glint on link tops.
        Paint chainP = (f, fx, fy, fw, fh, gx, gy) -> {
            if (fy % 2 == 0) {
                return noise(gx, gy, 95) > 0.7F ? c(0x9AA0AC) : c(0x6E727C);
            }
            return c(0x4E525A);
        };
        for (int k = 0; k < 3; k++) {
            cube(img, 92 + k * 6, 36, 1, 4, 1, chainP);
        }

        // Lantern: verdigris — creeping patina over a bronze frame, glass windows on the
        // side faces showing the flame's teal glow (housing joins the eyes pass while the
        // Lantern Gaze is active, so the panel colors stay saturated).
        cube(img, 92, 44, 4, 5, 4, (f, fx, fy, fw, fh, gx, gy) -> {
            boolean frame = fx == 0 || fx == fw - 1 || fy == 0 || fy == fh - 1;
            if (frame) {
                return mix(c(0x4A3A2E), c(0x4E7A66), noise(gx, gy, 91) * 0.5F);
            }
            if (f != Face.TOP && f != Face.BOTTOM) {
                return fy == 2 ? c(0xD8FFF4) : c(0x9AE8D6); // glass window w/ flame glow
            }
            return mix(c(0x4E7A66), c(0x6E9A82), noise(gx, gy, 92));
        }, 1.0F, true);

        // Soul flame: EMISSIVE always — near-white teal, no dark pixels.
        cube(img, 110, 36, 2, 2, 2, (f, fx, fy, fw, fh, gx, gy) ->
                mix(c(0xE8FFF8), c(0xA8F7E6), noise(gx, gy, 96)), 1.0F, false);
        ImageIO.write(img, "png", DIR.resolve("ferryman.png").toFile());
    }
}
