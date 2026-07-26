package dev.projecteclipse.eclipse.devtools;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.saveddata.SavedData;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * F-067 per-player mining-speed multiplier behind {@code /dev player multiplier mining …}.
 *
 * <p>The boost is one TRANSIENT {@code eclipse:dev_mining_speed} modifier on
 * {@link Attributes#BLOCK_BREAK_SPEED} — the attribute vanilla's
 * {@code Player#getDestroySpeed} multiplies its final dig speed by, so tool tiers,
 * efficiency, haste and the mod's own {@code PlayerEvent.BreakSpeed} listeners
 * ({@code SkillPerks}, {@code ShardEconomy}) all compose with it instead of fighting it.
 * {@code ADD_MULTIPLIED_TOTAL} with {@code factor - 1} turns the attribute's base 1.0 into
 * exactly {@code factor}.</p>
 *
 * <p><b>Persistence</b> mirrors the sibling skills multiplier: the factor lives in per-save
 * {@link SavedData} ({@code eclipse_dev_mining_speed}) keyed by UUID, never in player NBT.
 * The modifier itself is transient and rebuilt on login, respawn and clone — the same
 * discipline {@code ContractModifierService} uses for its temp hearts, and the reason a
 * relog or a death can never leave a stale (or a lost) boost behind.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MiningSpeedService {
    /** Neutral factor: no modifier is present at this value. */
    public static final float NEUTRAL = 1.0F;
    /** Same clamp as {@code SkillsApi.setSecretMultiplier} — operators share one mental model. */
    public static final float MIN_FACTOR = 0.0F;
    public static final float MAX_FACTOR = 100.0F;

    private static final ResourceLocation MODIFIER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "dev_mining_speed");

    private MiningSpeedService() {}

    // ================================================================== API

    /**
     * Sets (and immediately applies) {@code player}'s mining-speed factor. {@code 1.0} clears
     * the boost, including its persisted row.
     *
     * @param factor multiplier on the final dig speed, clamped to
     *               {@code [MIN_FACTOR, MAX_FACTOR]}
     * @return the clamped factor actually stored
     */
    public static float setFactor(MinecraftServer server, UUID uuid, float factor) {
        float clamped = Math.clamp(factor, MIN_FACTOR, MAX_FACTOR);
        MiningSpeedState.get(server).put(uuid, clamped);
        ServerPlayer online = server.getPlayerList().getPlayer(uuid);
        if (online != null) {
            apply(online);
        }
        EclipseMod.LOGGER.debug("Dev mining-speed factor for {} set to {}", uuid, clamped);
        return clamped;
    }

    /** Drops the boost again (equivalent to {@code setFactor(server, uuid, 1.0F)}). */
    public static void clear(MinecraftServer server, UUID uuid) {
        setFactor(server, uuid, NEUTRAL);
    }

    /** Stored factor, or {@link #NEUTRAL} when the player has no boost. Offline-safe. */
    public static float getFactor(MinecraftServer server, UUID uuid) {
        return MiningSpeedState.get(server).get(uuid);
    }

    // ================================================================== lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        // Integrated server / reload: players may already be attached before the first login.
        for (ServerPlayer player : event.getServer().getPlayerList().getPlayers()) {
            apply(player);
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            apply(player);
        }
    }

    @SubscribeEvent
    static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            apply(player);
        }
    }

    @SubscribeEvent
    static void onPlayerClone(PlayerEvent.Clone event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            apply(player);
        }
    }

    /** Rebuilds the single transient modifier from the persisted factor. Idempotent. */
    private static void apply(ServerPlayer player) {
        AttributeInstance attribute = player.getAttribute(Attributes.BLOCK_BREAK_SPEED);
        if (attribute == null) {
            return;
        }
        float factor = getFactor(player.server, player.getUUID());
        if (Math.abs(factor - NEUTRAL) < 1.0E-4F) {
            if (attribute.getModifier(MODIFIER_ID) != null) {
                attribute.removeModifier(MODIFIER_ID);
            }
            return;
        }
        attribute.addOrUpdateTransientModifier(new AttributeModifier(MODIFIER_ID, factor - NEUTRAL,
                AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
    }

    // ================================================================== SavedData

    /**
     * {@code data/eclipse_dev_mining_speed.dat}: UUID → factor. Neutral factors are not stored,
     * so a cleared player leaves no row behind.
     */
    public static final class MiningSpeedState extends SavedData {
        static final String DATA_NAME = "eclipse_dev_mining_speed";
        private static final String TAG_ENTRIES = "entries";

        private final Map<UUID, Float> factors = new HashMap<>();

        public MiningSpeedState() {}

        static MiningSpeedState get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_NAME,
                    new SavedData.Factory<>(MiningSpeedState::new, MiningSpeedState::load));
        }

        static MiningSpeedState load(CompoundTag tag, HolderLookup.Provider registries) {
            MiningSpeedState state = new MiningSpeedState();
            for (Tag element : tag.getList(TAG_ENTRIES, Tag.TAG_COMPOUND)) {
                CompoundTag row = (CompoundTag) element;
                if (row.hasUUID("player")) {
                    state.factors.put(row.getUUID("player"), row.getFloat("factor"));
                }
            }
            return state;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (Map.Entry<UUID, Float> entry : this.factors.entrySet()) {
                CompoundTag row = new CompoundTag();
                row.putUUID("player", entry.getKey());
                row.putFloat("factor", entry.getValue());
                list.add(row);
            }
            tag.put(TAG_ENTRIES, list);
            return tag;
        }

        float get(UUID uuid) {
            return this.factors.getOrDefault(uuid, NEUTRAL);
        }

        void put(UUID uuid, float factor) {
            if (Math.abs(factor - NEUTRAL) < 1.0E-4F) {
                if (this.factors.remove(uuid) != null) {
                    setDirty();
                }
                return;
            }
            Float previous = this.factors.put(uuid, factor);
            if (previous == null || Math.abs(previous - factor) >= 1.0E-4F) {
                setDirty();
            }
        }
    }
}
