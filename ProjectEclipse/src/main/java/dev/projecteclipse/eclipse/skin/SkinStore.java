package dev.projecteclipse.eclipse.skin;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * The PNG cache behind the skin overrides: {@code config/eclipse/skins/<uuid>.png}.
 *
 * <p>This directory — not the SavedData file — is the source of truth for the image bytes.
 * The SavedData ({@link SkinOverrideState}) only remembers WHERE a skin came from and WHAT
 * it hashed to, so a server restart re-loads skins from disk and never re-downloads them
 * (a dead link or an offline Mojang API must not cost the server its skins).</p>
 *
 * <p>All IO here blocks; call it from the {@code SkinService} worker.</p>
 */
public final class SkinStore {
    private SkinStore() {}

    /** {@code config/eclipse/skins} — created on demand. */
    public static Path directory() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("skins");
    }

    public static Path file(UUID player) {
        return directory().resolve(player + ".png");
    }

    /** Atomic write (temp file + move) so a crash mid-write cannot leave a half PNG behind. */
    public static void write(UUID player, byte[] png) throws SkinException {
        Path target = file(player);
        try {
            Files.createDirectories(target.getParent());
            Path temp = target.resolveSibling(target.getFileName() + ".tmp");
            Files.write(temp, png);
            try {
                Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (IOException atomicUnsupported) {
                Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING);
            }
        } catch (IOException e) {
            throw new SkinException("dev.eclipse.skin.error.save", SkinHttp.describe(e));
        }
    }

    /** Reads a cached skin; empty when the file is gone or unreadable (logged, never thrown). */
    public static Optional<byte[]> read(UUID player) {
        Path path = file(player);
        if (!Files.isRegularFile(path)) {
            return Optional.empty();
        }
        try {
            return Optional.of(Files.readAllBytes(path));
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Skin cache {} is unreadable — dropping the override", path, e);
            return Optional.empty();
        }
    }

    public static void delete(UUID player) {
        try {
            Files.deleteIfExists(file(player));
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Could not delete cached skin {}", file(player), e);
        }
    }

    /** Lower-case SHA-256 of the stored bytes; persisted so a cache swap is detectable. */
    public static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is mandatory on every JRE", e);
        }
    }
}
