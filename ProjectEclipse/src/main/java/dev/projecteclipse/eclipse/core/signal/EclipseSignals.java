package dev.projecteclipse.eclipse.core.signal;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.ChunkPos;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Server-side intra-mod signal bus for high-frequency gameplay events. This is
 * <strong>not</strong> the NeoForge event bus — analytics owns the underlying
 * {@code BlockEvent} / {@code LivingDeathEvent} subscribers and fans out here so
 * downstream systems (skills, goals, buffs, awards) never add duplicate listeners.
 *
 * <p>All listener lists are server-thread only. Lists are cleared on
 * {@link ServerStoppedEvent} to avoid leaking registrations across save reloads
 * in a long-lived JVM.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseSignals {
    /** Day rollover phase: PRE runs before {@code DayScheduler.setDay}; POST after. */
    public enum DayRolloverPhase {
        PRE,
        POST
    }

    /** Altar deposit purpose discriminator for {@link #altarDeposit}. */
    public enum AltarDepositPurpose {
        MILESTONE,
        OFFERING,
        SHARD_BANK
    }

    /**
     * Minimal quest identity surface for {@link #questCompleted}. P4-B2 {@code GoalSpec}
     * implements this interface so the signal layer stays decoupled from the full schema.
     */
    public interface QuestSpecRef {
        /** Stable goal id from goals.json / quests.json. */
        String id();

        /** {@code 0} main, {@code 1} side, {@code 2} personal — matches payload wire encoding. */
        byte kind();
    }

    private static final List<NaturalBlockMinedListener> NATURAL_BLOCK_MINED = new CopyOnWriteArrayList<>();
    private static final List<BlockPlacedListener> BLOCK_PLACED = new CopyOnWriteArrayList<>();
    private static final List<MobKilledListener> MOB_KILLED = new CopyOnWriteArrayList<>();
    private static final List<PlayerDeathListener> PLAYER_DEATH = new CopyOnWriteArrayList<>();
    private static final List<ItemCraftedListener> ITEM_CRAFTED = new CopyOnWriteArrayList<>();
    private static final List<ItemSmeltedListener> ITEM_SMELTED = new CopyOnWriteArrayList<>();
    private static final List<ChunkExploredListener> CHUNK_EXPLORED = new CopyOnWriteArrayList<>();
    private static final List<BiomeVisitedListener> BIOME_VISITED = new CopyOnWriteArrayList<>();
    private static final List<AltarDepositListener> ALTAR_DEPOSIT = new CopyOnWriteArrayList<>();
    private static final List<DayRolloverListener> DAY_ROLLOVER = new CopyOnWriteArrayList<>();
    private static final List<QuestCompletedListener> QUEST_COMPLETED = new CopyOnWriteArrayList<>();
    private static final List<SkillLevelUpListener> SKILL_LEVEL_UP = new CopyOnWriteArrayList<>();
    private static final List<BreedListener> BREED = new CopyOnWriteArrayList<>();
    private static final List<TradeListener> TRADE = new CopyOnWriteArrayList<>();

    @FunctionalInterface public interface NaturalBlockMinedListener {
        void onNaturalBlockMined(ServerPlayer player, BlockState state, BlockPos pos);
    }

    @FunctionalInterface public interface BlockPlacedListener {
        void onBlockPlaced(ServerPlayer player, BlockState state, BlockPos pos);
    }

    @FunctionalInterface public interface MobKilledListener {
        void onMobKilled(ServerPlayer player, LivingEntity victim);
    }

    @FunctionalInterface public interface PlayerDeathListener {
        void onPlayerDeath(ServerPlayer victim, LivingEntity killerOrNull);
    }

    @FunctionalInterface public interface ItemCraftedListener {
        void onItemCrafted(ServerPlayer player, ItemStack stack);
    }

    @FunctionalInterface public interface ItemSmeltedListener {
        void onItemSmelted(ServerPlayer player, ItemStack stack);
    }

    @FunctionalInterface public interface ChunkExploredListener {
        void onChunkExplored(ServerPlayer player, ChunkPos chunkPos);
    }

    @FunctionalInterface public interface BiomeVisitedListener {
        void onBiomeVisited(ServerPlayer player, ResourceLocation biomeId);
    }

    @FunctionalInterface public interface AltarDepositListener {
        void onAltarDeposit(ServerPlayer player, ResourceLocation itemId, int count, AltarDepositPurpose purpose);
    }

    @FunctionalInterface public interface DayRolloverListener {
        void onDayRollover(MinecraftServer server, int endedDay, int newDay, DayRolloverPhase phase);
    }

    @FunctionalInterface public interface QuestCompletedListener {
        void onQuestCompleted(ServerPlayer player, QuestSpecRef spec, String scope);
    }

    @FunctionalInterface public interface SkillLevelUpListener {
        void onSkillLevelUp(ServerPlayer player, int newLevel);
    }

    @FunctionalInterface public interface BreedListener {
        void onBreed(ServerPlayer player, LivingEntity childOrParent);
    }

    @FunctionalInterface public interface TradeListener {
        void onTrade(ServerPlayer player);
    }

    private EclipseSignals() {}

    // --- registration (call from ServerStartedEvent in each consumer package) ---

    public static void onNaturalBlockMined(NaturalBlockMinedListener listener) {
        NATURAL_BLOCK_MINED.add(listener);
    }

    public static void onBlockPlaced(BlockPlacedListener listener) {
        BLOCK_PLACED.add(listener);
    }

    public static void onMobKilled(MobKilledListener listener) {
        MOB_KILLED.add(listener);
    }

    public static Runnable onPlayerDeath(PlayerDeathListener listener) {
        PLAYER_DEATH.add(listener);
        return () -> PLAYER_DEATH.remove(listener);
    }

    public static void onItemCrafted(ItemCraftedListener listener) {
        ITEM_CRAFTED.add(listener);
    }

    public static void onItemSmelted(ItemSmeltedListener listener) {
        ITEM_SMELTED.add(listener);
    }

    public static void onChunkExplored(ChunkExploredListener listener) {
        CHUNK_EXPLORED.add(listener);
    }

    public static void onBiomeVisited(BiomeVisitedListener listener) {
        BIOME_VISITED.add(listener);
    }

    public static void onAltarDeposit(AltarDepositListener listener) {
        ALTAR_DEPOSIT.add(listener);
    }

    public static void onDayRollover(DayRolloverListener listener) {
        DAY_ROLLOVER.add(listener);
    }

    public static void onQuestCompleted(QuestCompletedListener listener) {
        QUEST_COMPLETED.add(listener);
    }

    public static void onSkillLevelUp(SkillLevelUpListener listener) {
        SKILL_LEVEL_UP.add(listener);
    }

    public static void onBreed(BreedListener listener) {
        BREED.add(listener);
    }

    public static void onTrade(TradeListener listener) {
        TRADE.add(listener);
    }

    // --- fire helpers (called by the single owning subscriber per signal) ---

    public static void fireNaturalBlockMined(ServerPlayer player, BlockState state, BlockPos pos) {
        for (NaturalBlockMinedListener listener : NATURAL_BLOCK_MINED) {
            listener.onNaturalBlockMined(player, state, pos);
        }
    }

    public static void fireBlockPlaced(ServerPlayer player, BlockState state, BlockPos pos) {
        for (BlockPlacedListener listener : BLOCK_PLACED) {
            listener.onBlockPlaced(player, state, pos);
        }
    }

    public static void fireMobKilled(ServerPlayer player, LivingEntity victim) {
        for (MobKilledListener listener : MOB_KILLED) {
            listener.onMobKilled(player, victim);
        }
    }

    public static void firePlayerDeath(ServerPlayer victim, LivingEntity killerOrNull) {
        for (PlayerDeathListener listener : PLAYER_DEATH) {
            listener.onPlayerDeath(victim, killerOrNull);
        }
    }

    public static void fireItemCrafted(ServerPlayer player, ItemStack stack) {
        for (ItemCraftedListener listener : ITEM_CRAFTED) {
            listener.onItemCrafted(player, stack.copy());
        }
    }

    public static void fireItemSmelted(ServerPlayer player, ItemStack stack) {
        for (ItemSmeltedListener listener : ITEM_SMELTED) {
            listener.onItemSmelted(player, stack.copy());
        }
    }

    public static void fireChunkExplored(ServerPlayer player, ChunkPos chunkPos) {
        for (ChunkExploredListener listener : CHUNK_EXPLORED) {
            listener.onChunkExplored(player, chunkPos);
        }
    }

    public static void fireBiomeVisited(ServerPlayer player, ResourceLocation biomeId) {
        for (BiomeVisitedListener listener : BIOME_VISITED) {
            listener.onBiomeVisited(player, biomeId);
        }
    }

    public static void fireAltarDeposit(ServerPlayer player, ResourceLocation itemId, int count,
            AltarDepositPurpose purpose) {
        for (AltarDepositListener listener : ALTAR_DEPOSIT) {
            listener.onAltarDeposit(player, itemId, count, purpose);
        }
    }

    public static void fireDayRollover(MinecraftServer server, int endedDay, int newDay, DayRolloverPhase phase) {
        for (DayRolloverListener listener : DAY_ROLLOVER) {
            listener.onDayRollover(server, endedDay, newDay, phase);
        }
    }

    public static void fireQuestCompleted(ServerPlayer player, QuestSpecRef spec, String scope) {
        for (QuestCompletedListener listener : QUEST_COMPLETED) {
            listener.onQuestCompleted(player, spec, scope);
        }
    }

    public static void fireSkillLevelUp(ServerPlayer player, int newLevel) {
        for (SkillLevelUpListener listener : SKILL_LEVEL_UP) {
            listener.onSkillLevelUp(player, newLevel);
        }
    }

    public static void fireBreed(ServerPlayer player, LivingEntity childOrParent) {
        for (BreedListener listener : BREED) {
            listener.onBreed(player, childOrParent);
        }
    }

    public static void fireTrade(ServerPlayer player) {
        for (TradeListener listener : TRADE) {
            listener.onTrade(player);
        }
    }

    /** Drops every listener list. Invoked automatically on server stop. */
    public static void clearAllListeners() {
        NATURAL_BLOCK_MINED.clear();
        BLOCK_PLACED.clear();
        MOB_KILLED.clear();
        PLAYER_DEATH.clear();
        ITEM_CRAFTED.clear();
        ITEM_SMELTED.clear();
        CHUNK_EXPLORED.clear();
        BIOME_VISITED.clear();
        ALTAR_DEPOSIT.clear();
        DAY_ROLLOVER.clear();
        QUEST_COMPLETED.clear();
        SKILL_LEVEL_UP.clear();
        BREED.clear();
        TRADE.clear();
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        clearAllListeners();
        EclipseMod.LOGGER.debug("EclipseSignals listener lists cleared");
    }
}
