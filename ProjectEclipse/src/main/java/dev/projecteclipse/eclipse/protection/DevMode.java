package dev.projecteclipse.eclipse.protection;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import dev.projecteclipse.eclipse.devtools.dev.DevRoot;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * PROGFIX #5 — the single central devmode service: operators and dev-bypass identities
 * obey every normal player restriction BY DEFAULT; a per-player {@code /devmode} toggle
 * (persisted across restarts in {@code eclipse_devmode.dat}) switches ALL of the routed
 * restriction exemptions on for that player until toggled off.
 *
 * <p>Routed consumers (each replaced its ad-hoc op/creative bypass with
 * {@link #isExempt}): {@link LandmarkProtection} (landmark no-build zones),
 * {@code worldgen.structure.SanctumProtection} (altar-area break/place/explosion) and
 * {@link SpawnProtectionRules} (spawn-zone PvP / fluid / vehicle / fall rules — note the
 * fall-damage safety is a BENEFIT, so devmode players take normal fall damage at spawn).</p>
 *
 * <p>The anticheat allowlist / mod check ({@code admin.AntiCheatCheck}) deliberately does
 * NOT consult this service — devmode must never disable the mod check.</p>
 *
 * <p>Command access mirrors {@code /dev}: {@link DevRoot#canUseDev} (vanilla permission 2
 * OR an {@code anticheat.json devBypassUuids} identity, e.g. Sonic0810).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevMode {
    static {
        DevCommandRegistry.register(new DevCommandDoc("devmode", DevCategory.PLAYERS,
                "/devmode", "dev.eclipse.doc.devmode", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevMode() {}

    /**
     * Whether this player currently bypasses the routed restriction systems. {@code false}
     * for null / non-server players and for every player who has not toggled devmode on —
     * ops and creative players included.
     */
    public static boolean isExempt(@Nullable Player player) {
        return player instanceof ServerPlayer serverPlayer
                && Data.get(serverPlayer.server).contains(serverPlayer.getUUID());
    }

    /** Persisted flag lookup by id (offline players included). */
    public static boolean isEnabled(MinecraftServer server, UUID playerId) {
        return Data.get(server).contains(playerId);
    }

    /** Direct write (gametests / future admin surfaces); the command path uses toggle. */
    public static void setEnabled(MinecraftServer server, UUID playerId, boolean enabled) {
        Data.get(server).set(playerId, enabled);
    }

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("devmode")
                .requires(DevRoot::canUseDev)
                .executes(context -> toggle(context.getSource())));
    }

    private static int toggle(CommandSourceStack source) throws CommandSyntaxException {
        ServerPlayer player = source.getPlayerOrException();
        Data data = Data.get(player.server);
        boolean enabled = !data.contains(player.getUUID());
        data.set(player.getUUID(), enabled);
        Component feedback = ServerLang.tr(player, enabled
                ? "command.eclipse.devmode.on" : "command.eclipse.devmode.off");
        source.sendSuccess(() -> feedback, false);
        // Restriction bypasses are audit-worthy: same operator broadcast as the /dev bridges.
        for (ServerPlayer operator : player.server.getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != player) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), ServerLang.tr(operator, enabled
                                ? "command.eclipse.devmode.on" : "command.eclipse.devmode.off")));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} devmode {}", player.getScoreboardName(),
                enabled ? "ON" : "OFF");
        return enabled ? 1 : 0;
    }

    /** Persisted set of devmode-enabled player UUIDs ({@code eclipse_devmode.dat}). */
    public static final class Data extends SavedData {
        public static final String DATA_NAME = "eclipse_devmode";

        private static final String TAG_ENABLED = "enabled";

        private final Set<UUID> enabled = new HashSet<>();

        public Data() {}

        public static Data get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_NAME,
                    new SavedData.Factory<>(Data::new, Data::load));
        }

        public static Data load(CompoundTag tag, HolderLookup.Provider registries) {
            Data data = new Data();
            for (Tag entry : tag.getList(TAG_ENABLED, Tag.TAG_INT_ARRAY)) {
                data.enabled.add(NbtUtils.loadUUID(entry));
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (UUID uuid : this.enabled) {
                list.add(NbtUtils.createUUID(uuid));
            }
            tag.put(TAG_ENABLED, list);
            return tag;
        }

        boolean contains(UUID playerId) {
            return this.enabled.contains(playerId);
        }

        void set(UUID playerId, boolean on) {
            boolean changed = on ? this.enabled.add(playerId) : this.enabled.remove(playerId);
            if (changed) {
                setDirty();
            }
        }
    }
}
