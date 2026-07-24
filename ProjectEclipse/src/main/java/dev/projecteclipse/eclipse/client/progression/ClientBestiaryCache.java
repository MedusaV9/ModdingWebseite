package dev.projecteclipse.eclipse.client.progression;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.bestiary.BestiaryPayloads;
import dev.projecteclipse.eclipse.network.bestiary.S2CBestiaryPayload;
import dev.projecteclipse.eclipse.progression.bestiary.BestiaryTiers;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client cache of the player's bestiary knowledge snapshot ({@link S2CBestiaryPayload},
 * sent by {@code progression.bestiary.BestiaryService} on login + every progress change).
 * {@code ClientUnlockCache} pattern: the {@code Dist.CLIENT} subscriber annotation loads
 * the class on client startup, the static initializer installs the {@link BestiaryPayloads}
 * consumer (so the registrar never references client classes), and the logout hook resets
 * state so one server's knowledge never leaks into the next session.
 *
 * <p><b>Tier-up moment</b> (payload carries a non-empty {@code tierUpId}): unlock sting
 * ({@link UiSounds#unlockSting()}) + a toast-ish action-bar caption, e.g. "Bestiary
 * updated: Storm Hound — weaknesses revealed" (per-tier lang keys, en+de via
 * {@link EclipseLang}). Renders through the vanilla overlay-message line — no new HUD
 * element, zero cost while nothing fires.</p>
 *
 * <p>Reads are volatile-map lookups; {@link #generation()} bumps on every snapshot so
 * {@code BestiaryTab} can cache its text layout between changes.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ClientBestiaryCache {
    /** One mob's knowledge as last synced (lifetime count + derived tier). */
    public record Entry(int count, byte tier) {}

    private static volatile Map<String, Entry> entries = Map.of();
    private static volatile int generation;

    static {
        // Payload consumer seam (GrowthPayloads pattern): installed on client class-load.
        BestiaryPayloads.setClientHandler(ClientBestiaryCache::update);
    }

    private ClientBestiaryCache() {}

    /** Knowledge tier for a mob id (registry path); T0 when never synced. */
    public static byte tierFor(String id) {
        Entry entry = entries.get(id);
        return entry == null ? BestiaryTiers.TIER_UNSEEN : entry.tier();
    }

    /** Lifetime kill/sighting count for a mob id; 0 when never synced. */
    public static int countFor(String id) {
        Entry entry = entries.get(id);
        return entry == null ? 0 : entry.count();
    }

    /** Monotonic counter bumped on every snapshot/reset — include in layout caches. */
    public static int generation() {
        return generation;
    }

    /**
     * Display name with graceful degradation (langdrop may land after the mob):
     * {@code bestiary.eclipse.<id>.name} → {@code entity.eclipse.<id>} → prettified id.
     */
    public static String displayName(String id) {
        String bestiaryKey = "bestiary.eclipse." + id + ".name";
        if (EclipseLang.hasKey(bestiaryKey)) {
            return EclipseLang.trString(bestiaryKey);
        }
        String entityKey = "entity.eclipse." + id;
        if (EclipseLang.hasKey(entityKey)) {
            return EclipseLang.trString(entityKey);
        }
        return prettifyId(id);
    }

    /** {@code umbral_stalker} → "Umbral Stalker" (last-resort fallback, never a raw key). */
    public static String prettifyId(String id) {
        StringBuilder pretty = new StringBuilder(id.length());
        for (String word : id.split("_")) {
            if (word.isEmpty()) {
                continue;
            }
            if (pretty.length() > 0) {
                pretty.append(' ');
            }
            pretty.append(word.substring(0, 1).toUpperCase(Locale.ROOT)).append(word.substring(1));
        }
        return pretty.isEmpty() ? id : pretty.toString();
    }

    /** Runs on the client main thread (payload handler). */
    private static void update(S2CBestiaryPayload payload) {
        Map<String, Entry> updated = new HashMap<>(payload.entries().size());
        for (S2CBestiaryPayload.Entry entry : payload.entries()) {
            updated.put(entry.id(), new Entry(entry.count(), entry.tier()));
        }
        entries = Map.copyOf(updated);
        generation++;
        if (!payload.tierUpId().isEmpty()) {
            celebrateTierUp(payload.tierUpId(), payload.tierUpTier());
        }
    }

    /** Sting + action-bar caption for the tier just reached (en+de via EclipseLang). */
    private static void celebrateTierUp(String id, byte tier) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft == null || minecraft.player == null) {
            return;
        }
        UiSounds.unlockSting();
        String key;
        String fallback; // shown until the W4 langdrop is merged — never a raw key
        switch (tier) {
            case BestiaryTiers.TIER_SLAYER -> {
                key = "gui.eclipse.handbook.bestiary.tierup.t3";
                fallback = "Bestiary updated: %s \u2014 weaknesses revealed";
            }
            case BestiaryTiers.TIER_HUNTER -> {
                key = "gui.eclipse.handbook.bestiary.tierup.t2";
                fallback = "Bestiary updated: %s \u2014 field notes added";
            }
            default -> {
                key = "gui.eclipse.handbook.bestiary.tierup.t1";
                fallback = "New bestiary entry: %s";
            }
        }
        Component caption = EclipseLang.hasKey(key)
                ? EclipseLang.tr(key, displayName(id))
                : Component.literal(String.format(Locale.ROOT, fallback, displayName(id)));
        minecraft.gui.setOverlayMessage(caption, false);
    }

    /** Disconnect reset — bestiary knowledge never leaks into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        entries = Map.of();
        generation++;
    }
}
