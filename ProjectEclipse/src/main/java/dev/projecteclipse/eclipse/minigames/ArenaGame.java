package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.network.protocol.game.ClientboundSetSubtitleTextPacket;
import net.minecraft.network.protocol.game.ClientboundSetTitleTextPacket;
import net.minecraft.network.protocol.game.ClientboundSetTitlesAnimationPacket;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;

/**
 * The FFA fight arena (game id {@code arena}, dimension {@code eclipse:minigame_arena}):
 * a generated circular platform (radius {@value #RADIUS}, barrier walls, decorative rim,
 * seeded floor accents) where every entrant fights with the same disposable kit. Kill
 * scoring runs in configurable rounds; each round ends with an ANONYMIZED podium
 * ("Champion" language — broadcasts never carry player names, matching the anonymity
 * rules; each player privately sees their own placement) and shard/skill-XP payouts to
 * the top placements through the existing {@code ShardEconomy}/{@code SkillsApi} surfaces.
 *
 * <p><b>Round feel</b> (W-P-ARENA): rounds start with a 3-2-1 title countdown and a
 * FIGHT! stinger; every round start refreshes the kit (fresh arrows/food, full health)
 * and sweeps leftover ground items/arrows so each round is a clean slate; round ends land
 * a ROUND OVER title + stinger before the podium chat lines. Podium places use standard
 * competition ranking, so kill ties share the higher place (and its payout) instead of
 * being ordered arbitrarily.</p>
 *
 * <p><b>Spawn protection</b> (W-P-ARENA): arena join and every respawn grant
 * {@value #SPAWN_PROTECTION_MILLIS}ms of invulnerability with a glow + end-rod particle
 * cue. Attacking someone ends the shield early — no protected-poking. Enforcement lives
 * in {@link #onLivingIncomingDamage} and is scoped to the arena dimension only.</p>
 *
 * <p>Deaths are cancelled upstream by {@code MinigameService} — a slain fighter respawns
 * scattered on the platform; their kit (and everything else) stays, so there is nothing
 * to lose. Players who slip below the floor or past the wall are teleported back in by
 * the per-tick bounds enforcement. Layout generation is a pure function of the seed
 * (= {@code MinigameState.openCount()}), so rebuilds are deterministic while accents vary
 * per open.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ArenaGame {

    /** Feet-level spawn at the platform center. */
    public static final BlockPos SPAWN = new BlockPos(0, 64, 0);
    static final int FLOOR_Y = 63;
    static final int RADIUS = 24;
    static final int WALL_RADIUS = 25;
    static final int WALL_HEIGHT = 8;
    /** Respawn scatter radius (avoids center spawn-camping). */
    private static final int RESPAWN_SCATTER = 8;
    /** Join/respawn protection window (~4s), broken early by attacking. */
    private static final long SPAWN_PROTECTION_MILLIS = 4_000L;
    private static final int SPAWN_PROTECTION_TICKS = (int) (SPAWN_PROTECTION_MILLIS / 50L);
    /** Minimum window remainder to start another round. */
    private static final long NEXT_ROUND_MIN_REMAINING_MILLIS = 60_000L;
    /** Round-start countdown length (3-2-1 titles). */
    private static final int COUNTDOWN_SECONDS = 3;
    /** Players this far below the floor or past the wall are pulled back in. */
    private static final int FALL_RESCUE_DEPTH = 4;

    // ---- transient per-run state (reset by resetTransient(); never persisted) ----
    /** Epoch millis until which a player is spawn-protected. Server thread only. */
    private static final Map<UUID, Long> SPAWN_PROTECTED_UNTIL = new HashMap<>();
    /** Epoch millis the pending round countdown ends ({@code 0} = no countdown armed). */
    private static long countdownEndsAtMillis;
    /** Last countdown number already shown as a title (avoids repeats at tick cadence). */
    private static int lastCountdownShown;

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

    // ------------------------------------------------------------------ spawn protection

    /**
     * Grants the join/respawn shield: {@value #SPAWN_PROTECTION_MILLIS}ms invulnerability
     * with a glow + end-rod burst cue and an actionbar note. Attacking anyone ends it
     * early ({@link #onLivingIncomingDamage}).
     */
    public static void grantSpawnProtection(ServerLevel arena, ServerPlayer player) {
        SPAWN_PROTECTED_UNTIL.put(player.getUUID(),
                System.currentTimeMillis() + SPAWN_PROTECTION_MILLIS);
        player.addEffect(new MobEffectInstance(MobEffects.GLOWING,
                SPAWN_PROTECTION_TICKS, 0, false, false, true));
        arena.sendParticles(ParticleTypes.END_ROD,
                player.getX(), player.getY() + 1.0D, player.getZ(),
                24, 0.4D, 0.7D, 0.4D, 0.02D);
        player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.arena.protect.on",
                SPAWN_PROTECTION_MILLIS / 1000L).withStyle(ChatFormatting.AQUA), true);
    }

    /** Whether the player currently holds an unexpired spawn shield (expired = pruned). */
    private static boolean isSpawnProtected(ServerPlayer player) {
        Long until = SPAWN_PROTECTED_UNTIL.get(player.getUUID());
        if (until == null) {
            return false;
        }
        if (until <= System.currentTimeMillis()) {
            SPAWN_PROTECTED_UNTIL.remove(player.getUUID());
            return false;
        }
        return true;
    }

    /** Silently drops a player's spawn shield (exit/logout hygiene — no message). */
    public static void clearSpawnProtection(ServerPlayer player) {
        SPAWN_PROTECTED_UNTIL.remove(player.getUUID());
    }

    /**
     * Arena-scoped damage rules: a spawn-protected victim takes no damage; a
     * spawn-protected ATTACKER forfeits the shield the moment their hit (melee or
     * projectile — the source entity of an arrow is its shooter) connects.
     */
    @SubscribeEvent
    public static void onLivingIncomingDamage(LivingIncomingDamageEvent event) {
        if (!(event.getEntity().level() instanceof ServerLevel level)
                || level.dimension() != MinigameDimensions.ARENA) {
            return;
        }
        if (event.getSource().getEntity() instanceof ServerPlayer attacker
                && attacker != event.getEntity() && isSpawnProtected(attacker)) {
            SPAWN_PROTECTED_UNTIL.remove(attacker.getUUID());
            attacker.removeEffect(MobEffects.GLOWING);
            attacker.displayClientMessage(ServerLang.tr(attacker,
                    "eclipse.minigame.arena.protect.broken")
                    .withStyle(ChatFormatting.YELLOW), true);
            attacker.playNotifySound(SoundEvents.GLASS_BREAK, SoundSource.PLAYERS, 0.5F, 1.4F);
        }
        if (event.getEntity() instanceof ServerPlayer victim && isSpawnProtected(victim)) {
            event.setCanceled(true);
        }
    }

    /** Clears all transient round/protection state (server stop + event close). */
    public static void resetTransient() {
        SPAWN_PROTECTED_UNTIL.clear();
        countdownEndsAtMillis = 0L;
        lastCountdownShown = 0;
    }

    // ------------------------------------------------------------------ combat & rounds

    /**
     * Handles one protected arena death: credits a player killer on the round scoreboard,
     * respawns the victim scattered on the platform with a fresh spawn shield. Called by
     * {@code MinigameService} AFTER the death event was cancelled.
     */
    public static void onProtectedDeath(MinecraftServer server, MinigameState state,
            ServerPlayer victim, @Nullable ServerPlayer killer) {
        ServerLevel arena = server.getLevel(MinigameDimensions.ARENA);
        if (arena != null) {
            placeIntoArena(arena, victim, true);
            grantSpawnProtection(arena, victim);
        }
        victim.displayClientMessage(ServerLang.tr(victim, "eclipse.minigame.arena.respawn")
                .withStyle(ChatFormatting.AQUA), true);
        if (killer != null && killer != victim) {
            int total = state.addKill(killer.getUUID());
            killer.displayClientMessage(ServerLang.tr(killer,
                    "eclipse.minigame.arena.kill", total), true);
            killer.playNotifySound(SoundEvents.ARROW_HIT_PLAYER, SoundSource.PLAYERS, 0.7F, 1.2F);
        }
    }

    /**
     * Round driver, called every service tick while the arena event is RUNNING: enforces
     * the platform bounds, runs the 3-2-1 countdown into a round when fighters are
     * present, and ends the live round at its deadline with the anonymized podium +
     * payouts. The next round re-arms through a fresh countdown on the following ticks,
     * giving a natural breather between rounds.
     */
    public static void tickRounds(MinecraftServer server, MinigameState state, List<ServerPlayer> inside) {
        long now = System.currentTimeMillis();
        ServerLevel arena = server.getLevel(MinigameDimensions.ARENA);
        if (arena != null) {
            enforceBounds(arena, inside);
        }
        long roundEndsAt = state.roundEndsAtEpochMillis();
        if (roundEndsAt == 0L) {
            tickCountdown(server, state, inside, now);
            return;
        }
        if (now < roundEndsAt) {
            return;
        }
        endRound(server, state, inside, "eclipse.minigame.arena.round_over");
    }

    /**
     * Pulls anyone below the floor or past the wall back onto the platform. Barrier walls
     * make this rare, but knockback clips, teleport glitches and long void falls (death
     * only triggers at the void floor) all funnel through here instead.
     */
    private static void enforceBounds(ServerLevel arena, List<ServerPlayer> inside) {
        for (ServerPlayer player : inside) {
            if (player.isSpectator()) {
                continue;
            }
            double dx = player.getX() - (SPAWN.getX() + 0.5D);
            double dz = player.getZ() - (SPAWN.getZ() + 0.5D);
            boolean outHorizontally = dx * dx + dz * dz
                    > (double) (WALL_RADIUS + 2) * (WALL_RADIUS + 2);
            boolean fellBelow = player.getY() < FLOOR_Y - FALL_RESCUE_DEPTH;
            if (outHorizontally || fellBelow) {
                placeIntoArena(arena, player, true);
                player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.arena.bounds")
                        .withStyle(ChatFormatting.YELLOW), true);
                player.playNotifySound(SoundEvents.ENDERMAN_TELEPORT, SoundSource.PLAYERS, 0.6F, 1.0F);
            }
        }
    }

    /**
     * Between-rounds driver: arms a {@value #COUNTDOWN_SECONDS}s countdown when fighters
     * are present and enough window remains, shows each number once as a title with a
     * rising tick, and starts the round at zero. An emptied arena or a shrunk window
     * cancels the pending countdown.
     */
    private static void tickCountdown(MinecraftServer server, MinigameState state,
            List<ServerPlayer> inside, long now) {
        if (inside.isEmpty() || state.endsAtEpochMillis() - now <= NEXT_ROUND_MIN_REMAINING_MILLIS) {
            countdownEndsAtMillis = 0L;
            return;
        }
        if (countdownEndsAtMillis == 0L) {
            countdownEndsAtMillis = now + COUNTDOWN_SECONDS * 1000L;
            lastCountdownShown = COUNTDOWN_SECONDS + 1;
        }
        if (now >= countdownEndsAtMillis) {
            countdownEndsAtMillis = 0L;
            startRound(server, state, inside, now);
            return;
        }
        int secondsLeft = (int) Math.ceil((countdownEndsAtMillis - now) / 1000.0D);
        if (secondsLeft >= lastCountdownShown) {
            return;
        }
        lastCountdownShown = secondsLeft;
        float pitch = 0.9F + 0.15F * (COUNTDOWN_SECONDS - secondsLeft);
        for (ServerPlayer player : inside) {
            player.connection.send(new ClientboundSetTitlesAnimationPacket(0, 15, 5));
            player.connection.send(new ClientboundSetTitleTextPacket(
                    Component.literal(Integer.toString(secondsLeft))
                            .withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD)));
            player.connection.send(new ClientboundSetSubtitleTextPacket(
                    ServerLang.tr(player, "eclipse.minigame.arena.title.get_ready")
                            .withStyle(ChatFormatting.GRAY)));
            player.playNotifySound(EclipseSounds.UI_ROULETTE_TICK.get(),
                    SoundSource.PLAYERS, 0.8F, pitch);
        }
    }

    /**
     * Round start: clean slate. Sweeps leftover ground items/arrows off the platform,
     * refreshes every fighter's kit (fresh arrows/food, full health/hunger) and lands
     * the FIGHT! title + stinger.
     */
    private static void startRound(MinecraftServer server, MinigameState state,
            List<ServerPlayer> inside, long now) {
        state.clearKills();
        state.setRoundEndsAtEpochMillis(now + MinigameConfig.get().roundMinutes() * 60_000L);
        ServerLevel arena = server.getLevel(MinigameDimensions.ARENA);
        if (arena != null) {
            sweepLeftovers(arena);
        }
        for (ServerPlayer player : inside) {
            player.getInventory().clearContent();
            giveKit(player);
            player.setHealth(player.getMaxHealth());
            player.getFoodData().setFoodLevel(20);
            player.getFoodData().setSaturation(5.0F);
            player.setRemainingFireTicks(0);
            player.connection.send(new ClientboundSetTitlesAnimationPacket(0, 25, 10));
            player.connection.send(new ClientboundSetTitleTextPacket(
                    ServerLang.tr(player, "eclipse.minigame.arena.title.fight")
                            .withStyle(ChatFormatting.RED, ChatFormatting.BOLD)));
            player.connection.send(new ClientboundSetSubtitleTextPacket(
                    ServerLang.tr(player, "eclipse.minigame.arena.round_start",
                            MinigameConfig.get().roundMinutes()).withStyle(ChatFormatting.GRAY)));
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.arena.round_start",
                    MinigameConfig.get().roundMinutes()).withStyle(ChatFormatting.GREEN), false);
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.arena.kit_refresh")
                    .withStyle(ChatFormatting.GRAY), true);
            player.playNotifySound(EclipseSounds.UI_UNLOCK_STING.get(),
                    SoundSource.PLAYERS, 0.8F, 1.0F);
        }
        EclipseMod.LOGGER.info("Arena round started: {} fighters, {} minute(s)",
                inside.size(), MinigameConfig.get().roundMinutes());
    }

    /** Discards leftover non-player entities (dropped items, stuck arrows) on the platform. */
    private static void sweepLeftovers(ServerLevel arena) {
        List<Entity> leftovers = arena.getEntities((Entity) null, bounds(),
                entity -> !(entity instanceof ServerPlayer));
        leftovers.forEach(Entity::discard);
    }

    /**
     * Ends the current round (also invoked by the CLOSING sequence when a round is still
     * live): ROUND OVER title + stinger, anonymized podium broadcast with standard
     * competition ranking (kill ties share the higher place AND its payout — payout ids
     * are per-player, so a shared place cannot collide in the ledger), private
     * placements, scoreboard reset. Safe to call with an empty scoreboard — announces a
     * quiet round instead.
     */
    public static void endRound(MinecraftServer server, MinigameState state,
            List<ServerPlayer> inside, String headerKey) {
        if (state.roundEndsAtEpochMillis() == 0L) {
            return;
        }
        // FFIX-B (H4): stable per-round identity for the payout ids, captured BEFORE the
        // deadline reset — a crash replay of this round derives the exact same ids.
        long roundKey = state.roundEndsAtEpochMillis();
        state.setRoundEndsAtEpochMillis(0L);
        Map<UUID, Integer> scores = state.killsSnapshot();
        List<Map.Entry<UUID, Integer>> ranked = new ArrayList<>(scores.entrySet());
        ranked.removeIf(entry -> entry.getValue() <= 0);
        ranked.sort((a, b) -> Integer.compare(b.getValue(), a.getValue()));

        for (ServerPlayer player : inside) {
            player.connection.send(new ClientboundSetTitlesAnimationPacket(0, 30, 10));
            player.connection.send(new ClientboundSetTitleTextPacket(
                    ServerLang.tr(player, "eclipse.minigame.arena.title.round_over")
                            .withStyle(ChatFormatting.GOLD, ChatFormatting.BOLD)));
            player.connection.send(new ClientboundSetSubtitleTextPacket(Component.empty()));
            player.playNotifySound(EclipseSounds.UI_TIMER_ZERO.get(),
                    SoundSource.PLAYERS, 0.7F, 1.0F);
        }

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
            int index = 0;
            int place = 0; // 0-based podium place (standard competition ranking: 1-2-2-4)
            while (index < ranked.size() && place < 3) {
                int score = ranked.get(index).getValue();
                List<Map.Entry<UUID, Integer>> tied = new ArrayList<>();
                while (index < ranked.size() && ranked.get(index).getValue() == score) {
                    tied.add(ranked.get(index));
                    index++;
                }
                if (tied.size() == 1) {
                    broadcast(server, Component.translatable(podiumKeys[place], score)
                            .withStyle(place == 0 ? ChatFormatting.GOLD : ChatFormatting.YELLOW));
                } else {
                    broadcast(server, Component.translatable("eclipse.minigame.arena.podium.tie",
                            tied.size(), place + 1, score)
                            .withStyle(place == 0 ? ChatFormatting.GOLD : ChatFormatting.YELLOW));
                }
                int shards = config.podiumShards().get(place);
                int xp = config.podiumSkillXp().get(place);
                for (Map.Entry<UUID, Integer> entry : tied) {
                    // FFIX-B (FINAL-SAT-SOL H3/H4): the payout is QUEUED by a stable
                    // per-instance/per-round/per-place id — offline winners keep their
                    // entitlement (paid at next login instead of being silently skipped),
                    // and crash replays cannot double-pay (claim-before-give). The ledger
                    // is keyed per player, so tied players sharing a place id is safe.
                    MinigameState.PendingPayout payout = new MinigameState.PendingPayout(
                            "minigame:arena:" + state.openCount() + ":" + roundKey
                                    + ":place:" + (place + 1),
                            shards, xp);
                    state.queuePayout(entry.getKey(), payout);
                    ServerPlayer winner = server.getPlayerList().getPlayer(entry.getKey());
                    if (winner != null && MinigameService.grantPayout(state, winner, payout)) {
                        winner.displayClientMessage(ServerLang.tr(winner,
                                "eclipse.minigame.arena.podium.private", place + 1,
                                entry.getValue(), shards, xp).withStyle(ChatFormatting.GOLD), false);
                        winner.playNotifySound(SoundEvents.UI_TOAST_CHALLENGE_COMPLETE,
                                SoundSource.PLAYERS, 0.7F, 1.0F);
                    }
                }
                place += tied.size();
            }
        }
        for (ServerPlayer player : inside) {
            player.displayClientMessage(ServerLang.tr(player, "eclipse.minigame.arena.own_score",
                    scores.getOrDefault(player.getUUID(), 0)).withStyle(ChatFormatting.GRAY), false);
        }
        state.clearKills();
        EclipseMod.LOGGER.info("Arena round ended: {} scorers, {} fighters inside",
                ranked.size(), inside.size());
    }

    /** Global announce, pre-baked per recipient (Wave-5 A1); console keeps the raw line. */
    private static void broadcast(MinecraftServer server, Component message) {
        server.sendSystemMessage(message);
        for (ServerPlayer player : List.copyOf(server.getPlayerList().getPlayers())) {
            player.sendSystemMessage(ServerLang.resolve(player, message));
        }
    }
}
