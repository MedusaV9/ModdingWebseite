package dev.projecteclipse.eclipse.skin;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CSkinOverridePayload;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server half of the operator skin overrides (F-050 {@code /dev skin}, F-051
 * {@code /dev adminskin}).
 *
 * <p><b>Threading contract.</b> Everything that can block — DNS, HTTP, PNG decode, disk —
 * runs on the single-threaded {@link #IO} worker; every mutation of game state (the cache,
 * the SavedData, packet sends, command feedback) hops back with {@code server.execute}. The
 * server thread must never wait for a skin: a slow Mojang API would otherwise stall the
 * whole tick loop, which is exactly the trap an "async" command usually falls into.</p>
 *
 * <p><b>Restart behaviour.</b> {@link SkinOverrideState} remembers the source URL and the
 * PNG hash; the bytes come back from {@code config/eclipse/skins} at
 * {@link ServerStartedEvent}. Nothing is re-downloaded — an entry whose cache file vanished
 * is dropped with a warning instead.</p>
 *
 * <p><b>Interaction with the anonymity layer.</b> {@code client.mixin.AbstractClientPlayerMixin}
 * normally forces the uniform "eclipsed" skin on every player; an override is the one thing
 * allowed to win over it, which is what makes {@code /dev adminskin} readable as a role
 * marker in the first place.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SkinService {
    /** Hard download cap; also the largest image the payload chunker will ever ship. */
    public static final int MAX_SKIN_BYTES = 256 * 1024;

    /** Guard rail for the login sync: every joining client pulls ALL active overrides. */
    public static final int MAX_OVERRIDES = 64;

    /** The bundled admin skin (F-051), applied by {@code /dev adminskin}. */
    public static final String ADMIN_SKIN_ASSET = "/assets/" + EclipseMod.MOD_ID + "/textures/skins/admin_purple.png";
    public static final String ADMIN_SKIN_SOURCE = "asset:admin_purple";

    private static final ExecutorService IO = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "eclipse-skin-io");
        thread.setDaemon(true);
        return thread;
    });

    /** Live PNG bytes per player; the send path never touches the disk. */
    private static final Map<UUID, byte[]> CACHE = new ConcurrentHashMap<>();

    private SkinService() {}

    // ------------------------------------------------------------------ command entry points

    /**
     * F-050: resolves {@code input} (image URL, NameMC profile link, Mojang texture link or
     * a bare player name), downloads and validates the PNG, then installs it. Returns
     * immediately — all feedback is delivered later on the server thread.
     */
    public static void applyFromInput(CommandSourceStack source, ServerPlayer target, String input) {
        MinecraftServer server = source.getServer();
        UUID targetId = target.getUUID();
        String targetName = target.getGameProfile().getName();
        if (!hasRoom(server, targetId)) {
            source.sendFailure(Component.translatable("dev.eclipse.skin.limit", MAX_OVERRIDES));
            return;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.skin.working", targetName, input), false);
        IO.execute(() -> {
            try {
                SkinUrlResolver.Resolved resolved = SkinUrlResolver.resolve(input);
                byte[] png = SkinImages.normalize(SkinHttp.getBytes(resolved.imageUrl(), MAX_SKIN_BYTES));
                store(server, source, targetId, targetName, png, resolved.slim(), input);
            } catch (SkinException e) {
                fail(server, source, e);
            } catch (RuntimeException e) {
                unexpected(server, source, targetName, e);
            }
        });
    }

    /** F-051: installs the bundled purple admin skin from the mod jar (no network at all). */
    public static void applyAdminSkin(CommandSourceStack source, ServerPlayer target) {
        MinecraftServer server = source.getServer();
        UUID targetId = target.getUUID();
        String targetName = target.getGameProfile().getName();
        if (!hasRoom(server, targetId)) {
            source.sendFailure(Component.translatable("dev.eclipse.skin.limit", MAX_OVERRIDES));
            return;
        }
        IO.execute(() -> {
            try {
                byte[] png = SkinImages.normalize(readAdminSkinAsset());
                store(server, source, targetId, targetName, png, false, ADMIN_SKIN_SOURCE);
            } catch (SkinException e) {
                fail(server, source, e);
            } catch (RuntimeException e) {
                unexpected(server, source, targetName, e);
            }
        });
    }

    /** Drops an override (command + payload); server thread. */
    public static boolean reset(MinecraftServer server, UUID targetId) {
        boolean had = SkinOverrideState.get(server).remove(targetId);
        CACHE.remove(targetId);
        if (had) {
            PacketDistributor.sendToAllPlayers(S2CSkinOverridePayload.reset(targetId));
            IO.execute(() -> SkinStore.delete(targetId));
        }
        return had;
    }

    // ------------------------------------------------------------------ install / sync

    /** IO thread: persist the PNG, then hand the install over to the server thread. */
    private static void store(MinecraftServer server, CommandSourceStack source, UUID targetId,
            String targetName, byte[] png, boolean slim, String sourceLabel) throws SkinException {
        SkinStore.write(targetId, png);
        String sha = SkinStore.sha256(png);
        server.execute(() -> {
            CACHE.put(targetId, png);
            SkinOverrideState.get(server).put(targetId,
                    new SkinOverrideState.Entry(sourceLabel, sha, slim, System.currentTimeMillis()));
            broadcast(targetId, png, slim);
            audit(source, Component.translatable("dev.eclipse.skin.applied", targetName, sourceLabel),
                    "skin " + targetName + " <- " + sourceLabel + " (" + png.length + " B, sha " + sha.substring(0, 8)
                            + ", " + (slim ? "slim" : "classic") + ")");
        });
    }

    /** Sends one override to everyone online, in chunk order. */
    private static void broadcast(UUID targetId, byte[] png, boolean slim) {
        for (S2CSkinOverridePayload part : S2CSkinOverridePayload.split(targetId, png, slim)) {
            PacketDistributor.sendToAllPlayers(part);
        }
    }

    /**
     * Login sync: a joining client knows nothing about running overrides, so it gets every
     * active one (its own included — the override may be on the joining player).
     */
    public static void syncAllTo(ServerPlayer viewer) {
        SkinOverrideState state = SkinOverrideState.get(viewer.server);
        for (Map.Entry<UUID, SkinOverrideState.Entry> entry : state.all().entrySet()) {
            byte[] png = CACHE.get(entry.getKey());
            if (png == null) {
                continue;
            }
            for (S2CSkinOverridePayload part
                    : S2CSkinOverridePayload.split(entry.getKey(), png, entry.getValue().slim())) {
                PacketDistributor.sendToPlayer(viewer, part);
            }
        }
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            try {
                syncAllTo(player);
            } catch (RuntimeException e) {
                // Same defense-in-depth as the EclipsePayloads login syncs: a missing skin
                // is cosmetic, a failed login handler is not.
                EclipseMod.LOGGER.error("Skin override login sync failed for {} — skipped",
                        player.getScoreboardName(), e);
            }
        }
    }

    /** Re-loads persisted overrides from the config cache (never from the network). */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        Map<UUID, SkinOverrideState.Entry> snapshot = new HashMap<>(SkinOverrideState.get(server).all());
        if (snapshot.isEmpty()) {
            return;
        }
        IO.execute(() -> {
            Map<UUID, byte[]> loaded = new HashMap<>();
            for (Map.Entry<UUID, SkinOverrideState.Entry> entry : snapshot.entrySet()) {
                SkinStore.read(entry.getKey()).ifPresent(png -> loaded.put(entry.getKey(), png));
            }
            server.execute(() -> {
                SkinOverrideState state = SkinOverrideState.get(server);
                for (Map.Entry<UUID, SkinOverrideState.Entry> entry : snapshot.entrySet()) {
                    byte[] png = loaded.get(entry.getKey());
                    if (png == null) {
                        EclipseMod.LOGGER.warn(
                                "Skin override for {} has no cached PNG in {} — dropping it (no re-download)",
                                entry.getKey(), SkinStore.directory());
                        state.remove(entry.getKey());
                        continue;
                    }
                    String sha = SkinStore.sha256(png);
                    if (!sha.equals(entry.getValue().sha256())) {
                        EclipseMod.LOGGER.info("Cached skin for {} changed on disk (sha {} != {}) — using the file",
                                entry.getKey(), sha.substring(0, 8), shortSha(entry.getValue().sha256()));
                        state.put(entry.getKey(), new SkinOverrideState.Entry(entry.getValue().source(), sha,
                                entry.getValue().slim(), entry.getValue().updatedEpochMillis()));
                    }
                    CACHE.put(entry.getKey(), png);
                }
                EclipseMod.LOGGER.info("Restored {} skin override(s) from {}", CACHE.size(), SkinStore.directory());
            });
        });
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        // Static caches must die with the save, or a second singleplayer world inherits them.
        CACHE.clear();
    }

    // ------------------------------------------------------------------ helpers

    private static boolean hasRoom(MinecraftServer server, UUID targetId) {
        SkinOverrideState state = SkinOverrideState.get(server);
        return state.get(targetId) != null || state.size() < MAX_OVERRIDES;
    }

    private static byte[] readAdminSkinAsset() throws SkinException {
        try (InputStream stream = SkinService.class.getResourceAsStream(ADMIN_SKIN_ASSET)) {
            if (stream == null) {
                throw new SkinException("dev.eclipse.skin.error.asset_missing", ADMIN_SKIN_ASSET);
            }
            return stream.readAllBytes();
        } catch (IOException e) {
            throw new SkinException("dev.eclipse.skin.error.asset_missing", SkinHttp.describe(e));
        }
    }

    private static void fail(MinecraftServer server, CommandSourceStack source, SkinException e) {
        server.execute(() -> source.sendFailure(Component.translatable(e.langKey(), e.args())));
    }

    private static void unexpected(MinecraftServer server, CommandSourceStack source, String targetName,
            RuntimeException e) {
        EclipseMod.LOGGER.error("Skin pipeline crashed for {}", targetName, e);
        server.execute(() -> source.sendFailure(
                Component.translatable("dev.eclipse.skin.error.network", SkinHttp.describe(e))));
    }

    private static String shortSha(String sha) {
        return sha == null || sha.length() < 8 ? String.valueOf(sha) : sha.substring(0, 8);
    }

    /** Same operator-audit convention as the {@code /dev} command bridges. */
    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }

    /** Audit hook for the reset path, which completes synchronously on the command thread. */
    public static void auditReset(CommandSourceStack source, Component feedback, String logDetail) {
        audit(source, feedback, logDetail);
    }
}
