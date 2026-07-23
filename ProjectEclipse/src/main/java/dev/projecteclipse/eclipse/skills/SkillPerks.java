package dev.projecteclipse.eclipse.skills;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.network.S2CSkillProcPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.BlockTags;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.monster.Enemy;
import net.minecraft.world.food.FoodData;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.common.Tags;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerXpEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Perk EFFECT implementations for every skill tree node (plan §2.3 table). One hook per
 * effect type; all magnitudes come from {@code skilltree.json} node values so balance is
 * live-tunable. Chance perks share one roll helper that folds in S3 (Eclipsed) and fire the
 * proc feedback trio: {@code skill.proc} sound + {@code S2CSkillProcPayload} + an optional
 * clickable chat line (the ONE sanctioned chat feature, R3; opt-out via
 * {@code /skills procmsg off}).
 *
 * <p>Anti-abuse: ore procs (T2/T6) re-check the placed-block chunk attachment directly
 * (A1's {@link PlacedBlockData}) even though the {@code naturalBlockMined} signal is already
 * natural-only — fails SAFE, never mints loot from player-placed blocks.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SkillPerks {
    private static final int SWEEP_INTERVAL_TICKS = 20;

    private static final ResourceLocation DUELIST_ID = rl("skill_duelist");
    private static final ResourceLocation ISLANDER_ID = rl("skill_islander");
    private static final ResourceLocation NIGHT_STRIDE_ID = rl("skill_night_stride");

    // statics reset on ServerStopped (via SkillService.onServerStopped → resetStatics)
    private static final Map<UUID, Long> BULWARK_LAST_PROC_MILLIS = new ConcurrentHashMap<>();
    // statics reset on ServerStopped
    private static final Map<UUID, Float> EXHAUSTION_SNAPSHOT = new ConcurrentHashMap<>();
    // statics reset on ServerStopped
    private static int tickCounter = 0;

    private SkillPerks() {}

    private static ResourceLocation rl(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    // ------------------------------------------------------------------
    // Shared lookups
    // ------------------------------------------------------------------

    private static Set<String> owned(ServerPlayer player) {
        return SkillState.get(player.server).entry(player.getUUID()).ownedNodes;
    }

    /** Summed effect value across owned nodes; 0 when the perk is not owned. */
    public static float effect(ServerPlayer player, String effectType) {
        return SkillTree.effectTotal(SkillTreeConfig.get().nodes(), owned(player), effectType);
    }

    /** Chance-perk roll chance: node base + S3 (proc_chance_add), clamped to [0,1]. */
    public static float procChance(ServerPlayer player, float baseChance) {
        if (baseChance <= 0.0F) {
            return 0.0F;
        }
        return Math.clamp(baseChance + effect(player, "proc_chance_add"), 0.0F, 1.0F);
    }

    /**
     * Placed-block lookup against A1's chunk attachment (O(1) bit test). Local mirror until
     * P4-B5's {@code PlacedBlockTracker} lands — wave-B packages may not reference each other.
     */
    public static boolean isPlaced(ServerLevel level, BlockPos pos) {
        if (!(level.getChunkAt(pos) instanceof LevelChunk chunk)) {
            return false;
        }
        PlacedBlockData data = chunk.getData(EclipseAttachments.PLACED_BLOCKS);
        if (data == null) {
            return false;
        }
        long[] bits = data.sectionBits(level.getSectionIndex(pos.getY()), false);
        if (bits == null) {
            return false;
        }
        int blockIndex = ((pos.getY() & 15) << 8) | ((pos.getZ() & 15) << 4) | (pos.getX() & 15);
        int longIndex = blockIndex >> 6;
        return longIndex < bits.length && ((bits[longIndex] >> (blockIndex & 63)) & 1L) != 0L;
    }

    // ------------------------------------------------------------------
    // Proc feedback (R3): sound + payload + clickable chat line
    // ------------------------------------------------------------------

    /**
     * Fires the full proc feedback trio to one player. Returns whether the CHAT line was
     * sent (false when globally disabled in skills.json or opted out per player) — pinned
     * by the procmsg gametest.
     */
    public static boolean sendProcFeedback(ServerPlayer player, String procId, float magnitude) {
        SkillConfig.Data cfg = SkillConfig.get();
        SoundEvent sound = BuiltInRegistries.SOUND_EVENT
                .getOptional(ResourceLocation.tryParse(cfg.procSound()))
                .orElseGet(EclipseSounds.SKILL_PROC);
        player.serverLevel().playSound(null, player.blockPosition(), sound, SoundSource.PLAYERS, 0.7F, 1.0F);
        PacketDistributor.sendToPlayer(player, new S2CSkillProcPayload(procId, magnitude));

        boolean chatWanted = cfg.procChatLine()
                && SkillState.get(player.server).entry(player.getUUID()).procMsgEnabled;
        if (chatWanted) {
            MutableComponent line = Component.literal("[✦] ").withStyle(ChatFormatting.DARK_PURPLE)
                    .append(Component.translatable("message.eclipse.skill.proc." + procId)
                            .withStyle(ChatFormatting.LIGHT_PURPLE))
                    .append(Component.literal(" "))
                    .append(Component.translatable("message.eclipse.skill.proc.disable")
                            .withStyle(style -> style
                                    .withColor(ChatFormatting.DARK_GRAY)
                                    .withUnderlined(true)
                                    .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND,
                                            "/skills procmsg off"))));
            player.sendSystemMessage(line);
        }
        return chatWanted;
    }

    // ------------------------------------------------------------------
    // Signal-driven hooks (called by SkillService's listeners)
    // ------------------------------------------------------------------

    /** T2 Fortune's Echo + T6 Earthen Bond — natural ore procs. */
    static void onNaturalOreMined(ServerPlayer player, BlockState state, BlockPos pos) {
        ServerLevel level = player.serverLevel();
        float roll = level.random.nextFloat();
        if (shouldDoubleOreDrops(player, state, pos, roll)) {
            List<ItemStack> drops = Block.getDrops(state, level, pos, null, player, player.getMainHandItem());
            for (ItemStack drop : drops) {
                Block.popResource(level, pos, drop);
            }
            if (!drops.isEmpty()) {
                sendProcFeedback(player, "double_ore", 2.0F);
            }
        }
        float bonusRoll = level.random.nextFloat();
        ItemStack bonus = bonusRawOreFor(player, state, pos, bonusRoll);
        if (bonus != null) {
            Block.popResource(level, pos, bonus);
            sendProcFeedback(player, "bonus_ore", 1.0F);
        }
    }

    /**
     * T2 decision (pure given a roll): node owned, block is a {@code c:ores} ore, position
     * NOT player-placed, roll under chance(+S3). Gametests drive this with forced rolls.
     */
    public static boolean shouldDoubleOreDrops(ServerPlayer player, BlockState state, BlockPos pos, float roll) {
        float base = effect(player, "double_ore_drop_chance");
        if (base <= 0.0F || !state.is(Tags.Blocks.ORES)) {
            return false;
        }
        if (isPlaced(player.serverLevel(), pos)) {
            return false;
        }
        return roll < procChance(player, base);
    }

    /** T6 decision: the bonus raw-ore stack, or null. Same natural/placed rules as T2. */
    public static ItemStack bonusRawOreFor(ServerPlayer player, BlockState state, BlockPos pos, float roll) {
        float base = effect(player, "bonus_raw_ore_chance");
        if (base <= 0.0F) {
            return null;
        }
        ItemStack bonus;
        if (state.is(BlockTags.IRON_ORES)) {
            bonus = new ItemStack(Items.RAW_IRON);
        } else if (state.is(BlockTags.COPPER_ORES)) {
            bonus = new ItemStack(Items.RAW_COPPER);
        } else if (state.is(BlockTags.GOLD_ORES)) {
            bonus = new ItemStack(Items.RAW_GOLD);
        } else {
            return null;
        }
        if (isPlaced(player.serverLevel(), pos)) {
            return null;
        }
        return roll < procChance(player, base) ? bonus : null;
    }

    /** U3 Bulwark (absorption on kill, ICD) + U4 Shardseeker (bonus shard on night kills). */
    static void onMobKilled(ServerPlayer player, LivingEntity victim) {
        SkillTreeConfig.Node bulwark = SkillTree.ownedNode(SkillTreeConfig.get().nodes(), owned(player),
                "post_kill_absorption");
        if (bulwark != null) {
            long now = EclipseClock.epochMillis();
            long last = BULWARK_LAST_PROC_MILLIS.getOrDefault(player.getUUID(), 0L);
            long cooldownMillis = (long) (bulwark.cooldown() * 1000.0F);
            if (now - last >= cooldownMillis) {
                BULWARK_LAST_PROC_MILLIS.put(player.getUUID(), now);
                int amplifier = Math.max(0, (int) Math.ceil(bulwark.value() / 2.0F) - 1);
                int durationTicks = (int) (bulwark.duration() * 20.0F);
                player.addEffect(new MobEffectInstance(MobEffects.ABSORPTION, durationTicks, amplifier));
            }
        }

        float shardChance = effect(player, "bonus_shard_on_night_kill");
        if (shardChance > 0.0F && player.serverLevel().isNight()
                && player.serverLevel().random.nextFloat() < procChance(player, shardChance)) {
            Block.popResource(player.serverLevel(), victim.blockPosition(),
                    new ItemStack(EclipseItems.UMBRAL_SHARD.get()));
            sendProcFeedback(player, "bonus_shard", 1.0F);
        }
    }

    /** T5 Smeltmaster — double smelt SKILL XP roll (SkillService grants the second helping). */
    static boolean rollSmeltDouble(ServerPlayer player) {
        float base = effect(player, "smelt_double_xp_chance");
        if (base <= 0.0F || player.serverLevel().random.nextFloat() >= procChance(player, base)) {
            return false;
        }
        sendProcFeedback(player, "smelt_xp", 2.0F);
        return true;
    }

    /** V6 Cartographer — flat bonus XP added to each first-visit biome grant. */
    static float firstBiomeBonus(ServerPlayer player) {
        return effect(player, "first_biome_bonus_xp");
    }

    // ------------------------------------------------------------------
    // NeoForge event hooks
    // ------------------------------------------------------------------

    /** U1 Night's Edge (attacker melee at night) + V3 Featherfall / V4 Soft Landing (victim fall). */
    @SubscribeEvent
    static void onIncomingDamage(LivingIncomingDamageEvent event) {
        // Attacker-side: +melee damage at night, direct hits only (no projectiles).
        if (event.getSource().getEntity() instanceof ServerPlayer attacker
                && event.getSource().getDirectEntity() == attacker
                && attacker.serverLevel().isNight()) {
            float bonus = effect(attacker, "melee_damage_night_pct");
            if (bonus > 0.0F) {
                event.setAmount(event.getAmount() * (1.0F + bonus));
            }
        }

        // Victim-side: fall damage perks.
        if (event.getEntity() instanceof ServerPlayer victim && event.getSource().is(DamageTypeTags.IS_FALL)) {
            float softBlocks = effect(victim, "no_fall_damage_below_blocks");
            if (softBlocks > 0.0F && victim.fallDistance <= softBlocks) {
                event.setCanceled(true);
                return;
            }
            float reduce = effect(victim, "fall_damage_reduce_pct");
            if (reduce > 0.0F) {
                event.setAmount(event.getAmount() * (1.0F - Math.min(reduce, 1.0F)));
            }
        }
    }

    /** U2 Reaper — chance to duplicate non-boss hostile drops. */
    @SubscribeEvent
    static void onLivingDrops(LivingDropsEvent event) {
        if (!(event.getSource().getEntity() instanceof ServerPlayer killer)) {
            return;
        }
        LivingEntity victim = event.getEntity();
        if (!(victim instanceof Enemy) || victim instanceof ServerPlayer) {
            return;
        }
        if (victim.getType().is(Tags.EntityTypes.BOSSES) || isEclipseBoss(victim)) {
            return;
        }
        float base = effect(killer, "double_mob_drop_chance");
        if (base <= 0.0F || event.getDrops().isEmpty()) {
            return;
        }
        if (killer.serverLevel().random.nextFloat() >= procChance(killer, base)) {
            return;
        }
        List<ItemEntity> copies = new ArrayList<>(event.getDrops().size());
        for (ItemEntity drop : event.getDrops()) {
            copies.add(new ItemEntity(drop.level(), drop.getX(), drop.getY(), drop.getZ(),
                    drop.getItem().copy()));
        }
        event.getDrops().addAll(copies);
        sendProcFeedback(killer, "double_loot", 2.0F);
    }

    /** Herald/Ferryman guard even if P6 forgets the {@code c:bosses} tag. */
    private static boolean isEclipseBoss(LivingEntity victim) {
        ResourceLocation id = BuiltInRegistries.ENTITY_TYPE.getKey(victim.getType());
        return EclipseMod.MOD_ID.equals(id.getNamespace())
                && ("herald".equals(id.getPath()) || "ferryman".equals(id.getPath()));
    }

    /** T4 Deep Delver — +break speed below Y=0. */
    @SubscribeEvent
    static void onBreakSpeed(PlayerEvent.BreakSpeed event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        float bonus = effect(player, "break_speed_below0_pct");
        if (bonus <= 0.0F) {
            return;
        }
        int y = event.getPosition().map(BlockPos::getY).orElse(player.blockPosition().getY());
        if (y < 0) {
            event.setNewSpeed(event.getNewSpeed() * (1.0F + bonus));
        }
    }

    /** S1 Awakened — +vanilla XP (positive changes only; orbs, bottles, commands). */
    @SubscribeEvent
    static void onVanillaXpChange(PlayerXpEvent.XpChange event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || event.getAmount() <= 0) {
            return;
        }
        float bonus = effect(player, "vanilla_xp_pct");
        if (bonus > 0.0F) {
            event.setAmount(Math.round(event.getAmount() * (1.0F + bonus)));
        }
    }

    // ------------------------------------------------------------------
    // 20-tick sweep: conditional attribute modifiers (U5/V1/V5) + T3 hunger scaling.
    // O(online players), zero block scans.
    // ------------------------------------------------------------------

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (++tickCounter < SWEEP_INTERVAL_TICKS) {
            return;
        }
        tickCounter = 0;
        for (ServerPlayer player : event.getServer().getPlayerList().getPlayers()) {
            sweepPlayer(player);
        }
        EXHAUSTION_SNAPSHOT.keySet().removeIf(uuid ->
                event.getServer().getPlayerList().getPlayer(uuid) == null);
    }

    private static void sweepPlayer(ServerPlayer player) {
        ServerLevel level = player.serverLevel();

        float duelist = effect(player, "attack_speed_pct");
        applyModifier(player.getAttribute(Attributes.ATTACK_SPEED), DUELIST_ID, duelist, duelist > 0.0F);

        float islander = effect(player, "spawn_island_speed_pct");
        boolean onIsland = islander > 0.0F && SanctumProtection.isProtected(level, player.blockPosition());
        applyModifier(player.getAttribute(Attributes.MOVEMENT_SPEED), ISLANDER_ID, islander, onIsland);

        float nightStride = effect(player, "night_speed_pct");
        boolean night = nightStride > 0.0F && level.isNight();
        applyModifier(player.getAttribute(Attributes.MOVEMENT_SPEED), NIGHT_STRIDE_ID, nightStride, night);

        // T3 Iron Stomach: per-player exhaustion-delta scaling. ExhaustionScaler's factor
        // registry is server-global (Supplier<Float> has no player param), so the per-player
        // perk runs its own snapshot sweep here; when B9's half-hunger buff is also active
        // both scale their own deltas and the factors compose multiplicatively.
        float hungerPct = effect(player, "hunger_drain_pct");
        UUID uuid = player.getUUID();
        if (hungerPct != 0.0F) {
            FoodData food = player.getFoodData();
            float current = food.getExhaustionLevel();
            Float previous = EXHAUSTION_SNAPSHOT.get(uuid);
            if (previous != null) {
                float delta = current - previous;
                if (delta > 0.0F) {
                    float scaled = previous + delta * Math.max(0.0F, 1.0F + hungerPct);
                    food.setExhaustion(scaled);
                    current = scaled;
                }
            }
            EXHAUSTION_SNAPSHOT.put(uuid, current);
        } else {
            EXHAUSTION_SNAPSHOT.remove(uuid);
        }
    }

    private static void applyModifier(AttributeInstance attribute, ResourceLocation id, float value,
            boolean active) {
        if (attribute == null) {
            return;
        }
        if (active) {
            attribute.addOrUpdateTransientModifier(new AttributeModifier(id, value,
                    AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
        } else if (attribute.getModifier(id) != null) {
            attribute.removeModifier(id);
        }
    }

    /** Called from {@code SkillService.onServerStopped} — SP relaunch must not leak state. */
    static void resetStatics() {
        BULWARK_LAST_PROC_MILLIS.clear();
        EXHAUSTION_SNAPSHOT.clear();
        tickCounter = 0;
    }
}
