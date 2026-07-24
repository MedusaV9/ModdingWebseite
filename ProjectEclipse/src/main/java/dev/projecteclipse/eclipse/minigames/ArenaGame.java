package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/**
 * The FFA fight arena (game id {@code arena}, dimension {@code eclipse:minigame_arena}):
 * a generated circular platform (radius {@value #RADIUS}, barrier walls, decorative rim,
 * seeded floor accents) where every entrant fights with the same disposable kit. Kill
 * scoring runs in {@value #ROUND_LABEL} rounds; each round ends with an ANONYMIZED podium
 * ("Champion" language — broadcasts never carry player names, matching the anonymity
 * rules; each player privately sees their own placement) and shard/skill-XP payouts to
 * the top three through the existing {@code ShardEconomy}/{@code SkillsApi} surfaces.
 *
 * <p>Deaths are cancelled upstream by {@code MinigameService} — a slain fighter respawns
 * at the arena center with brief spawn protection; their kit (and everything else) stays,
 * so there is nothing to lose. Layout generation is a pure function of the seed
 * (= {@code MinigameState.openCount()}), so rebuilds are deterministic while accents vary
 * per open.</p>
 */
public final class ArenaGame {
    static final String ROUND_LABEL = "5-minute";

    /** Feet-level spawn at the platform center. */
    public static final BlockPos SPAWN = new BlockPos(0, 64, 0);
    static final int FLOOR_Y = 63;
    static final int RADIUS = 24;
    static final int WALL_RADIUS = 25;
    static final int WALL_HEIGHT = 8;
    /** Respawn scatter radius (avoids center spawn-camping). */
    private static final int RESPAWN_SCATTER = 8;
    /** Post-respawn i-frames (ticks). */
    private static final int SPAWN_PROTECTION_TICKS = 60;
    /** Minimum window remainder to start another round. */
    private static final long NEXT_ROUND_MIN_REMAINING_MILLIS = 60_000L;

    private ArenaGame() {}

    // ------------------------------------------------------------------ layout

    /**
     * Deterministic platform layout for {@code seed}: floor disc + rim + barrier wall +
     * froglight pillars. The FOOTPRINT is identical for every seed (a rebuild fully
     * overwrites the previous open); only cosmetic accents vary.
     */
    public static List<CourseBlocks.Placement> layout(int seed) {
        RandomSource rand = RandomSource.create(seed * 31L + 17L);
        BlockState floorBase = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState floorAccent = Blocks.GILDED_BLACKSTONE.defaultBlockState();
        BlockState floorInlay = Blocks.SEA_LANTERN.defaultBlockState();
        BlockState rim = Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState();
        BlockState wall = Blocks.BARRIER.defaultBlockState();
        BlockState pillar = Blocks.PEARLESCENT_FROGLIGHT.defaultBlockState();

        List<CourseBlocks.Placement> out = new ArrayList<>();
        for (int x = -WALL_RADIUS; x <= WALL_RADIUS; x++) {
            for (int z = -WALL_RADIUS; z <= WALL_RADIUS; z++) {
                double dist = Math.sqrt(x * (double) x + z * (double) z);
                if (dist <= RADIUS - 1) {
                    BlockState state = floorBase;
                    float roll = rand.nextFloat(); // fixed iteration order → deterministic
                    if (roll < 0.06F) {
                        state = floorAccent;
                    } else if (roll < 0.10F && ((int) Math.round(dist)) % 8 == 0) {
                        state = floorInlay;
                    }
                    out.add(new CourseBlocks.Placement(new BlockPos(x, FLOOR_Y, z), state));
                } else if (dist <= RADIUS + 0.5D) {
                    out.add(new CourseBlocks.Placement(new BlockPos(x, FLOOR_Y, z), rim));
                } else if (Math.round(dist) == WALL_RADIUS) {
                    for (int y = 1; y <= WALL_HEIGHT; y++) {
                        out.add(new CourseBlocks.Placement(new BlockPos(x, FLOOR_Y + y, z), wall));
                    }
                }
            }
        }
        // Four 3-high froglight pillars at a seeded base angle — light + orientation cue.
        double baseAngle = rand.nextDouble() * Math.PI * 2.0D;
        for (int i = 0; i < 4; i++) {
            double angle = baseAngle + i * (Math.PI / 2.0D);
            int px = (int) Math.round(Math.cos(angle) * (RADIUS - 4));
            int pz = (int) Math.round(Math.sin(angle) * (RADIUS - 4));
            for (int y = 1; y <= 3; y++) {
                out.add(new CourseBlocks.Placement(new BlockPos(px, FLOOR_Y + y, pz), pillar));
            }
        }
        return out;
    }

    /** Course bounds for the close-time entity sweep. */
    public static net.minecraft.world.phys.AABB bounds() {
        return new net.minecraft.world.phys.AABB(
                -WALL_RADIUS - 8, FLOOR_Y - 12, -WALL_RADIUS - 8,
                WALL_RADIUS + 8, FLOOR_Y + WALL_HEIGHT + 16, WALL_RADIUS + 8);
    }

    // ------------------------------------------------------------------ kit & spawn

    /** The standard disposable kit — everything vanishes on exit (ticket restore clears it). */
    public static void giveKit(ServerPlayer player) {
        player.setItemSlot(EquipmentSlot.HEAD, new ItemStack(Items.LEATHER_HELMET));
        player.setItemSlot(EquipmentSlot.CHEST, new ItemStack(Items.LEATHER_CHESTPLATE));
        player.setItemSlot(EquipmentSlot.LEGS, new ItemStack(Items.LEATHER_LEGGINGS));
        player.setItemSlot(EquipmentSlot.FEET, new ItemStack(Items.LEATHER_BOOTS));
        player.getInventory().add(new ItemStack(Items.STONE_SWORD));
        player.getInventory().add(new ItemStack(Items.STONE_AXE));
        player.getInventory().add(new ItemStack(Items.BOW));
        player.getInventory().add(new ItemStack(Items.ARROW, 32));
        player.getInventory().add(new ItemStack(Items.COOKED_BEEF, 8));
        player.inventoryMenu.broadcastChanges();
    }

    /** Teleports the player onto the platform (scattered around the center). */
    public static void placeIntoArena(ServerLevel arena, ServerPlayer player, boolean scatter) {
        double x = SPAWN.getX() + 0.5D;
        double z = SPAWN.getZ() + 0.5D;
        if (scatter) {
            double angle = arena.random.nextDouble() * Math.PI * 2.0D;
            double dist = 2.0D + arena.random.nextDouble() * RESPAWN_SCATTER;
            x += Math.cos(angle) * dist;
            z += Math.sin(angle) * dist;
        }
        player.teleportTo(arena, x, SPAWN.getY(), z,
                arena.random.nextFloat() * 360.0F - 180.0F, 0.0F);
        player.fallDistance = 0.0F;
    }

    // ------------------------------------------------------------------ combat & rounds

    /**
     * Handles one protected arena death: credits a player killer on the round scoreboard,
     * respawns the victim on the platform with brief i-frames. Called by
     * {@code MinigameService} AFTER the death event was cancelled.
     */
    public static void onProtectedDeath(MinecraftServer server, MinigameState state,
            ServerPlayer victim, @Nullable ServerPlayer killer) {
        ServerLevel arena = server.getLevel(MinigameDimensions.ARENA);
        if (arena != null) {
            placeIntoArena(arena, victim, true);
        }
        victim.invulnerableTime = SPAWN_PROTECTION_TICKS;
        victim.displayClientMessage(Component.translatable("eclipse.minigame.arena.respawn")
                .withStyle(ChatFormatting.AQUA), true);
        if (killer != null && killer != victim) {
            int total = state.addKill(killer.getUUID());
            killer.displayClientMessage(Component.translatable("eclipse.minigame.arena.kill", total), true);
            killer.playNotifySound(SoundEvents.ARROW_HIT_PLAYER, SoundSource.PLAYERS, 0.7F, 1.2F);
        }
    }

    /**
     * Round driver, called every service tick while the arena event is RUNNING: starts a
     * round when fighters are present, ends it at the round deadline with the anonymized
     * podium + payouts, and rolls into the next round while enough window time remains.
     */
    public static void tickRounds(MinecraftServer server, MinigameState state, List<ServerPlayer> inside) {
        long now = System.currentTimeMillis();
        long roundEndsAt = state.roundEndsAtEpochMillis();
        if (roundEndsAt == 0L) {
            if (!inside.isEmpty() && state.endsAtEpochMillis() - now > NEXT_ROUND_MIN_REMAINING_MILLIS) {
                startRound(state, inside, now);
            }
            return;
        }
        if (now < roundEndsAt) {
            return;
        }
        endRound(server, state, inside, "eclipse.minigame.arena.round_over");
        if (state.endsAtEpochMillis() - now > NEXT_ROUND_MIN_REMAINING_MILLIS && !inside.isEmpty()) {
            startRound(state, inside, now);
        } else {
            state.setRoundEndsAtEpochMillis(0L);
        }
    }

    private static void startRound(MinigameState state, List<ServerPlayer> inside, long now) {
        state.clearKills();
        state.setRoundEndsAtEpochMillis(now + MinigameConfig.get().roundMinutes() * 60_000L);
        for (ServerPlayer player : inside) {
            player.displayClientMessage(Component.translatable("eclipse.minigame.arena.round_start",
                    MinigameConfig.get().roundMinutes()).withStyle(ChatFormatting.GREEN), false);
            player.playNotifySound(SoundEvents.PLAYER_LEVELUP, SoundSource.PLAYERS, 0.6F, 1.4F);
        }
    }

    /**
     * Ends the current round (also invoked by the CLOSING sequence when a round is still
     * live): anonymized podium broadcast, private placements, top-3 payouts, scoreboard
     * reset. Safe to call with an empty scoreboard — announces a quiet round instead.
     */
    public static void endRound(MinecraftServer server, MinigameState state,
            List<ServerPlayer> inside, String headerKey) {
        if (state.roundEndsAtEpochMillis() == 0L) {
            return;
        }
        state.setRoundEndsAtEpochMillis(0L);
        Map<UUID, Integer> scores = state.killsSnapshot();
        List<Map.Entry<UUID, Integer>> ranked = new ArrayList<>(scores.entrySet());
        ranked.removeIf(entry -> entry.getValue() <= 0);
        ranked.sort((a, b) -> Integer.compare(b.getValue(), a.getValue()));

        broadcast(server, Component.translatable(headerKey).withStyle(ChatFormatting.GOLD));
        if (ranked.isEmpty()) {
            broadcast(server, Component.translatable("eclipse.minigame.arena.podium.none")
                    .withStyle(ChatFormatting.GRAY));
        } else {
            // Anonymity rule: broadcasts carry counts only, never names.
            String[] podiumKeys = {
                    "eclipse.minigame.arena.podium.first",
                    "eclipse.minigame.arena.podium.second",
                    "eclipse.minigame.arena.podium.third"};
            MinigameConfig.Values config = MinigameConfig.get();
            for (int place = 0; place < 3 && place < ranked.size(); place++) {
                Map.Entry<UUID, Integer> entry = ranked.get(place);
                broadcast(server, Component.translatable(podiumKeys[place], entry.getValue())
                        .withStyle(place == 0 ? ChatFormatting.GOLD : ChatFormatting.YELLOW));
                ServerPlayer winner = server.getPlayerList().getPlayer(entry.getKey());
                if (winner != null) {
                    int shards = config.podiumShards().get(place);
                    int xp = config.podiumSkillXp().get(place);
                    if (shards > 0) {
                        ShardEconomy.addShards(winner, shards);
                    }
                    if (xp > 0) {
                        SkillsApi.addXp(winner, "minigame", xp);
                    }
                    winner.displayClientMessage(Component.translatable(
                            "eclipse.minigame.arena.podium.private", place + 1, entry.getValue(),
                            shards, xp).withStyle(ChatFormatting.GOLD), false);
                    winner.playNotifySound(SoundEvents.UI_TOAST_CHALLENGE_COMPLETE,
                            SoundSource.PLAYERS, 0.7F, 1.0F);
                }
            }
        }
        for (ServerPlayer player : inside) {
            player.displayClientMessage(Component.translatable("eclipse.minigame.arena.own_score",
                    scores.getOrDefault(player.getUUID(), 0)).withStyle(ChatFormatting.GRAY), false);
        }
        state.clearKills();
        EclipseMod.LOGGER.info("Arena round ended: {} scorers, {} fighters inside",
                ranked.size(), inside.size());
    }

    private static void broadcast(MinecraftServer server, Component message) {
        server.getPlayerList().broadcastSystemMessage(message, false);
    }
}
