package dev.projecteclipse.eclipse.skin;

import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

/**
 * Turns whatever an operator pastes into {@code /dev skin <player> <url>} into a concrete
 * skin-image URL. Everything in here BLOCKS (Mojang API round-trips) — IO worker only.
 *
 * <p>Accepted inputs:</p>
 * <ul>
 *   <li>a plain Minecraft name ({@code Sonic0810}) — the NameMC path without the link;</li>
 *   <li>a NameMC profile link ({@code https://namemc.com/profile/Sonic0810.1}) — resolved
 *       through the OFFICIAL Mojang API (name → UUID → session profile → {@code textures}
 *       property), never by scraping NameMC's HTML, which is neither stable nor allowed;</li>
 *   <li>a Mojang texture link ({@code https://textures.minecraft.net/texture/<hash>}) and
 *       any other direct image URL — used as-is.</li>
 * </ul>
 *
 * <p>The session profile also carries the model variant, so a slim ("Alex") source skin
 * stays slim on the target player.</p>
 */
public final class SkinUrlResolver {
    /** A resolved source: the image to download plus the model variant it was authored for. */
    public record Resolved(URI imageUrl, boolean slim, String describe) {}

    private static final Pattern PLAYER_NAME = Pattern.compile("[A-Za-z0-9_]{1,16}");

    private static final Set<String> NAMEMC_HOSTS = Set.of("namemc.com", "www.namemc.com");

    /** Mojang API responses are tiny; the cap only exists so a broken endpoint cannot flood us. */
    private static final int JSON_MAX_BYTES = 64 * 1024;

    private static final String NAME_TO_UUID = "https://api.mojang.com/users/profiles/minecraft/";
    private static final String SESSION_PROFILE = "https://sessionserver.mojang.com/session/minecraft/profile/";

    private SkinUrlResolver() {}

    /** Resolves operator input to a downloadable skin image. Blocking. */
    public static Resolved resolve(String rawInput) throws SkinException {
        String input = rawInput == null ? "" : rawInput.strip();
        if (input.isEmpty()) {
            throw new SkinException("dev.eclipse.skin.error.bad_url", input);
        }
        if (PLAYER_NAME.matcher(input).matches()) {
            return fromPlayerName(input);
        }
        URI uri;
        try {
            uri = new URI(input);
        } catch (URISyntaxException e) {
            throw new SkinException("dev.eclipse.skin.error.bad_url", input);
        }
        SkinHttp.assertPublicHost(uri);
        String host = uri.getHost().toLowerCase(Locale.ROOT);
        String path = uri.getPath() == null ? "" : uri.getPath();
        if (NAMEMC_HOSTS.contains(host) && path.startsWith("/profile/")) {
            return fromPlayerName(nameMcProfileName(path));
        }
        // Mojang texture links and plain image links need no resolution step; the PNG
        // validator downstream is what actually decides whether the bytes are a skin.
        return new Resolved(uri, false, input);
    }

    /**
     * NameMC profile paths are {@code /profile/<name>} and — for accounts whose name changed —
     * {@code /profile/<name>.<n>}. Only the name part identifies the account for Mojang.
     */
    private static String nameMcProfileName(String path) throws SkinException {
        String rest = path.substring("/profile/".length());
        int slash = rest.indexOf('/');
        if (slash >= 0) {
            rest = rest.substring(0, slash);
        }
        int dot = rest.indexOf('.');
        if (dot >= 0) {
            rest = rest.substring(0, dot);
        }
        if (!PLAYER_NAME.matcher(rest).matches()) {
            throw new SkinException("dev.eclipse.skin.error.bad_url", path);
        }
        return rest;
    }

    /** name → UUID → session profile → decoded {@code textures} property → skin URL + model. */
    private static Resolved fromPlayerName(String name) throws SkinException {
        JsonObject profile = json(SkinHttp.getUtf8(uri(NAME_TO_UUID + name), JSON_MAX_BYTES));
        if (profile == null || !profile.has("id")) {
            throw new SkinException("dev.eclipse.skin.error.unknown_player", name);
        }
        String uuid = profile.get("id").getAsString();
        JsonObject session = json(SkinHttp.getUtf8(uri(SESSION_PROFILE + uuid), JSON_MAX_BYTES));
        if (session == null || !session.has("properties")) {
            throw new SkinException("dev.eclipse.skin.error.no_texture", name);
        }
        String encoded = null;
        for (JsonElement element : session.getAsJsonArray("properties")) {
            JsonObject property = element.getAsJsonObject();
            if (property.has("name") && "textures".equals(property.get("name").getAsString())) {
                encoded = property.get("value").getAsString();
                break;
            }
        }
        if (encoded == null) {
            throw new SkinException("dev.eclipse.skin.error.no_texture", name);
        }
        JsonObject textures = decodeTextures(encoded, name);
        if (!textures.has("SKIN")) {
            // A player who never uploaded a skin has no SKIN entry — Mojang serves the
            // default Steve/Alex from the client, so there is nothing to mirror.
            throw new SkinException("dev.eclipse.skin.error.no_texture", name);
        }
        JsonObject skin = textures.getAsJsonObject("SKIN");
        if (!skin.has("url")) {
            throw new SkinException("dev.eclipse.skin.error.no_texture", name);
        }
        boolean slim = skin.has("metadata")
                && skin.getAsJsonObject("metadata").has("model")
                && "slim".equalsIgnoreCase(skin.getAsJsonObject("metadata").get("model").getAsString());
        return new Resolved(uri(skin.get("url").getAsString()), slim, name);
    }

    private static JsonObject decodeTextures(String encoded, String name) throws SkinException {
        try {
            String decoded = new String(Base64.getDecoder().decode(encoded), StandardCharsets.UTF_8);
            JsonObject root = json(decoded);
            if (root == null || !root.has("textures")) {
                throw new SkinException("dev.eclipse.skin.error.no_texture", name);
            }
            return root.getAsJsonObject("textures");
        } catch (IllegalArgumentException e) {
            throw new SkinException("dev.eclipse.skin.error.no_texture", name);
        }
    }

    private static JsonObject json(String body) {
        if (body == null || body.isBlank()) {
            return null;
        }
        try {
            JsonElement parsed = JsonParser.parseString(body);
            return parsed.isJsonObject() ? parsed.getAsJsonObject() : null;
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static URI uri(String value) throws SkinException {
        try {
            return new URI(value);
        } catch (URISyntaxException e) {
            throw new SkinException("dev.eclipse.skin.error.bad_url", value);
        }
    }
}
