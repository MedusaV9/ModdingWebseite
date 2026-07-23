package dev.projecteclipse.eclipse.lang;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.network.S2CGoalProgressPayload;
import dev.projecteclipse.eclipse.timeline.TimelineService;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side locale resolver for Eclipse-baked strings ({@code docs/plans_v3/P3_ui.md} §3.2).
 * Explicit overrides arrive via {@link dev.projecteclipse.eclipse.network.C2SLocalePayload};
 * when absent the player's vanilla {@code clientInformation().language()} is normalized to
 * {@code "en"} or {@code "de"}. P4 should call {@link #pick(Localized, ServerPlayer)} for every
 * per-player goal/title/subtitle line once {@code DayPlan} carries {@link Localized} fields.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LangService {
    /** Session cache keyed by player UUID; persisted copy lives on {@code eclipse:locale_override}. */
    private static final Map<UUID, String> EXPLICIT_OVERRIDES = new ConcurrentHashMap<>();

    private LangService() {}

    /**
     * Effective locale token for server-baked text: {@code "en"} or {@code "de"}. Checks the
     * explicit override (session map + attachment when wired) before vanilla client language.
     */
    public static String locale(ServerPlayer player) {
        String override = explicitOverride(player);
        if (!override.isEmpty()) {
            return normalize(override);
        }
        return normalize(player.clientInformation().language());
    }

    /** Resolves a dual-language config string for the given player. */
    public static String pick(Localized text, ServerPlayer player) {
        return text.pick(locale(player));
    }

    /** Applies a {@link dev.projecteclipse.eclipse.network.C2SLocalePayload} and re-sends cached lines. */
    public static void applyLocale(ServerPlayer player, String locale, boolean explicit) {
        if (explicit && locale != null && !locale.isEmpty() && !"auto".equalsIgnoreCase(locale)) {
            String stored = normalizeClientLocale(locale);
            EXPLICIT_OVERRIDES.put(player.getUUID(), stored);
            LocaleAttachmentStore.set(player, stored);
        } else {
            EXPLICIT_OVERRIDES.remove(player.getUUID());
            LocaleAttachmentStore.clear(player);
        }
        resendLocaleSensitive(player);
    }

    /** Re-broadcasts payloads whose baked strings depend on {@link #locale(ServerPlayer)}. */
    public static void resendLocaleSensitive(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, S2CDayStatePayload.currentFor(player));
        PacketDistributor.sendToPlayer(player, S2CGoalProgressPayload.currentFor(player));
        TimelineService.syncTo(player);
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        String stored = LocaleAttachmentStore.read(player);
        if (!stored.isEmpty()) {
            EXPLICIT_OVERRIDES.put(player.getUUID(), stored);
        }
        PacketDistributor.sendToPlayer(player, S2CDayStatePayload.currentFor(player));
        TimelineService.syncTo(player);
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        EXPLICIT_OVERRIDES.remove(event.getEntity().getUUID());
    }

    private static String explicitOverride(ServerPlayer player) {
        String session = EXPLICIT_OVERRIDES.get(player.getUUID());
        if (session != null && !session.isEmpty()) {
            return session;
        }
        return LocaleAttachmentStore.read(player);
    }

    /** Normalizes vanilla / override codes to {@code en} or {@code de}. */
    public static String normalize(String languageCode) {
        if (languageCode == null || languageCode.isEmpty()) {
            return "en";
        }
        String lower = languageCode.toLowerCase(java.util.Locale.ROOT);
        if (lower.startsWith("de")) {
            return "de";
        }
        return "en";
    }

    /** Normalizes client override tokens to {@code en_us} / {@code de_de}. */
    static String normalizeClientLocale(String token) {
        if (token == null || token.isEmpty() || "auto".equalsIgnoreCase(token)) {
            return "";
        }
        String lower = token.toLowerCase(java.util.Locale.ROOT);
        if (lower.startsWith("de")) {
            return "de_de";
        }
        return "en_us";
    }
}
