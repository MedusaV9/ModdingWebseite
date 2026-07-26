package dev.projecteclipse.eclipse.skin;

import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Locale;

/**
 * The only outbound HTTP surface of the skin pipeline. Every call here BLOCKS and must
 * therefore run on {@code SkinService}'s IO worker — never on the server thread.
 *
 * <p>Three hard limits are enforced for every request, because an operator command that
 * takes an arbitrary URL is an SSRF primitive otherwise:</p>
 * <ul>
 *   <li>{@link #TIMEOUT} (10 s) for both connect and response;</li>
 *   <li>a caller-supplied byte cap, enforced while streaming (a {@code Content-Length}
 *       header is only a hint — a hostile server can lie and then send gigabytes);</li>
 *   <li>{@link #assertPublicHost} — http/https only, and the host must not resolve to a
 *       loopback / link-local / site-local / any-local address, so {@code /dev skin}
 *       cannot be used to probe the machine the server runs on.</li>
 * </ul>
 */
final class SkinHttp {
    /** Connect + response timeout for every skin-related request. */
    static final Duration TIMEOUT = Duration.ofSeconds(10);

    private static final String USER_AGENT = "ProjectEclipse-Skins/1.0";

    private static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(TIMEOUT)
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    private SkinHttp() {}

    /** GETs a small UTF-8 document (Mojang API JSON). Empty response bodies come back as "". */
    static String getUtf8(URI uri, int maxBytes) throws SkinException {
        return new String(getBytes(uri, maxBytes), StandardCharsets.UTF_8);
    }

    /**
     * GETs at most {@code maxBytes} bytes. A body that is still not finished at the cap is a
     * hard failure (never a silent truncation — a cut-off PNG would fail validation with a
     * confusing message).
     */
    static byte[] getBytes(URI uri, int maxBytes) throws SkinException {
        assertPublicHost(uri);
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(TIMEOUT)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "*/*")
                .GET()
                .build();
        HttpResponse<InputStream> response;
        try {
            response = CLIENT.send(request, HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException e) {
            throw new SkinException("dev.eclipse.skin.error.network", describe(e));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new SkinException("dev.eclipse.skin.error.network", describe(e));
        }
        int status = response.statusCode();
        if (status == 204) {
            return new byte[0];
        }
        if (status < 200 || status >= 300) {
            drain(response);
            throw new SkinException("dev.eclipse.skin.error.http", status, uri.getHost());
        }
        long announced = response.headers().firstValueAsLong("content-length").orElse(-1L);
        if (announced > maxBytes) {
            drain(response);
            throw new SkinException("dev.eclipse.skin.error.too_large", maxBytes / 1024);
        }
        try (InputStream body = response.body()) {
            byte[] bytes = body.readNBytes(maxBytes + 1);
            if (bytes.length > maxBytes) {
                throw new SkinException("dev.eclipse.skin.error.too_large", maxBytes / 1024);
            }
            return bytes;
        } catch (IOException e) {
            throw new SkinException("dev.eclipse.skin.error.network", describe(e));
        }
    }

    /** Rejects non-http(s) schemes and any host that resolves into the server's own networks. */
    static void assertPublicHost(URI uri) throws SkinException {
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        if (!scheme.equals("http") && !scheme.equals("https")) {
            throw new SkinException("dev.eclipse.skin.error.bad_url", String.valueOf(uri));
        }
        String host = uri.getHost();
        if (host == null || host.isBlank()) {
            throw new SkinException("dev.eclipse.skin.error.bad_url", String.valueOf(uri));
        }
        InetAddress[] addresses;
        try {
            addresses = InetAddress.getAllByName(host);
        } catch (UnknownHostException e) {
            throw new SkinException("dev.eclipse.skin.error.network", describe(e));
        }
        for (InetAddress address : addresses) {
            if (address.isLoopbackAddress() || address.isAnyLocalAddress() || address.isLinkLocalAddress()
                    || address.isSiteLocalAddress() || address.isMulticastAddress()) {
                throw new SkinException("dev.eclipse.skin.error.blocked_host", host);
            }
        }
    }

    /** Frees the connection of an error response so the pool can reuse it. */
    private static void drain(HttpResponse<InputStream> response) {
        try (InputStream body = response.body()) {
            body.readNBytes(4096);
        } catch (IOException ignored) {
            // Nothing to recover — the response is already an error path.
        }
    }

    /** Exception text that is useful in chat: message when there is one, class name otherwise. */
    static String describe(Exception e) {
        String message = e.getMessage();
        return message == null || message.isBlank() ? e.getClass().getSimpleName() : message;
    }
}
