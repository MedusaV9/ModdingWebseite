package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.protection.SpawnProtectionRules;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;

/**
 * The Phasenriss signature — <b>Phasenwelle</b> (W4-WAND spec / IDEA-19 R1): a cone of
 * blocks in front of the caster "de-rezzes" (collision + render vanish) for
 * {@code holdTicks}, then re-materializes <b>block by block</b> in random order with
 * glitch bursts. The world re-rendering itself IS the fantasy.
 *
 * <p><b>Crash safety (FFIX-B / POLISH-SOL-02):</b> every de-rezzed block's state is
 * snapshotted into the {@link Data} SavedData at cast time, and the journal is
 * force-flushed to disk ({@link EclipseSavedData#flushOverworld}) BEFORE the first block
 * can vanish — {@code setDirty()} alone only schedules a save and gives no ordering
 * against the chunk write that contains the air. On server start
 * {@link #restoreAllOnLoad} reconciles EVERY leftover journal entry (including
 * {@code vanished=false} prepare records whose air write reached the chunk while the
 * phase flag didn't) against the actual block — a crash can therefore never permanently
 * eat terrain.</p>
 *
 * <p><b>Hard blacklist</b> (never de-rezzed): block entities (chests, the altar, spawners
 * — inventories must never be voided), anything inside a spawn-protection zone
 * ({@link SpawnProtectionRules}), unbreakables (bedrock etc.), fluids and air. Restore
 * refuses to overwrite non-air (a player built there mid-phase → snapshot is discarded,
 * never grief-overwritten).</p>
 *
 * <p>FX per event: vanish → {@code border_glitch} one-shot, restore →
 * {@code impact_light} micro-pop (both dispatched via {@code S2CQuasarPayload}; the client
 * {@code QuasarSpawner} budget-caps them). Ticked by {@link WandTickService}.</p>
 */
public final class WandPhaseService {
    private static final ResourceLocation BORDER_GLITCH =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border_glitch");
    private static final ResourceLocation IMPACT_LIGHT =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "impact_light");

    /** Cone half-angle tangent (~26°) plus a small base radius so the near cone isn't a needle. */
    private static final double CONE_TAN = 0.5D;
    private static final double FX_RANGE = 48.0D;

    private WandPhaseService() {}

    // ------------------------------------------------------------------ casting

    /**
     * Collects and schedules the de-rez cone. Returns {@code false} (no cost) when nothing
     * phaseable is in front of the caster.
     */
    public static boolean castWave(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Data data = Data.get(player.server);
        double length = power.param("length", 10.0F);
        int maxBlocks = (int) power.param("maxBlocks", 24.0F);
        int holdTicks = (int) power.param("holdTicks", 200.0F);
        int restoreEvery = Math.max(1, (int) power.param("restoreEveryTicks", 10.0F));
        int vanishPerTick = Math.max(1, (int) power.param("vanishPerTick", 6.0F));

        Vec3 origin = player.getEyePosition();
        Vec3 dir = player.getLookAngle().normalize();

        record Candidate(BlockPos pos, double along) {}
        List<Candidate> candidates = new ArrayList<>();
        int reach = (int) Math.ceil(length) + 1;
        BlockPos base = player.blockPosition();
        for (BlockPos pos : BlockPos.betweenClosed(base.offset(-reach, -reach, -reach),
                base.offset(reach, reach, reach))) {
            Vec3 center = Vec3.atCenterOf(pos);
            Vec3 toBlock = center.subtract(origin);
            double along = toBlock.dot(dir);
            if (along < 1.0D || along > length) {
                continue;
            }
            double perp = toBlock.subtract(dir.scale(along)).length();
            if (perp > along * CONE_TAN + 0.5D) {
                continue;
            }
            if (!isPhaseable(level, pos, data)) {
                continue;
            }
            candidates.add(new Candidate(pos.immutable(), along));
        }
        if (candidates.isEmpty()) {
            player.displayClientMessage(Component.translatable("wand.eclipse.msg.no_blocks"), true);
            return false;
        }
        candidates.sort(Comparator.comparingDouble(Candidate::along));
        if (candidates.size() > maxBlocks) {
            candidates = candidates.subList(0, maxBlocks);
        }

        // Restore order is a shuffle so the world knits back randomly, not as a sweep.
        List<Candidate> restoreOrder = new ArrayList<>(candidates);
        java.util.Collections.shuffle(restoreOrder, new java.util.Random(level.random.nextLong()));

        long now = level.getGameTime();
        for (int i = 0; i < candidates.size(); i++) {
            Candidate candidate = candidates.get(i);
            long vanishAt = now + (i / vanishPerTick);
            int restoreIndex = restoreOrder.indexOf(candidate);
            long restoreAt = now + holdTicks + (long) restoreIndex * restoreEvery;
            BlockState state = level.getBlockState(candidate.pos());
            data.add(level.dimension(), candidate.pos(), state, vanishAt, restoreAt);
        }
        data.setDirty();
        // FFIX-B (POLISH-SOL-02 / FINAL-SAT-SOL C2): durable prepare barrier — the journal
        // must be ON DISK before the first air write can reach a chunk save. The earliest
        // vanish is this very game tick, so the flush happens here, synchronously.
        EclipseSavedData.flushOverworld(player.server);
        // D10: the de-rez reads as a violet SCANLINE sweeping the cone — three
        // ground-hugging riss_wave_front bands march caster → cone tip while the blocks
        // behind the band dissolve. Audio = detuned teleport under a digital chirp.
        Vec3 foot = player.position().add(0.0D, 0.15D, 0.0D);
        Vec3 flatDir = new Vec3(dir.x, 0.0D, dir.z);
        Vec3 march = flatDir.lengthSqr() > 1.0E-4D ? flatDir.normalize() : Vec3.ZERO;
        double bandReach = length;
        WandPowers.sendQuasar(level, WandPowers.RISS_WAVE_FRONT, foot.add(march.scale(1.5D)));
        WandTickService.schedule(level, 3, () -> WandPowers.sendQuasar(level,
                WandPowers.RISS_WAVE_FRONT, foot.add(march.scale(bandReach * 0.55D))));
        WandTickService.schedule(level, 6, () -> WandPowers.sendQuasar(level,
                WandPowers.RISS_WAVE_FRONT, foot.add(march.scale(bandReach))));
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.ENDERMAN_TELEPORT, SoundSource.PLAYERS, 0.9F, 0.55F);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.6F, 1.35F);
        return true;
    }

    /** Blacklist per spec: block entities, protection zones, unbreakables, fluids, air. */
    private static boolean isPhaseable(ServerLevel level, BlockPos pos, Data data) {
        BlockState state = level.getBlockState(pos);
        if (state.isAir() || state.hasBlockEntity() || !state.getFluidState().isEmpty()) {
            return false;
        }
        if (state.getDestroySpeed(level, pos) < 0.0F) {
            return false; // bedrock-class
        }
        if (SpawnProtectionRules.isInProtectionZone(level, pos)) {
            return false; // altar / sanctum / protected builds
        }
        return !data.contains(level.dimension(), pos);
    }

    // ------------------------------------------------------------------ ticking (WandTickService)

    /** Runs the vanish/restore schedule; called every server tick. */
    static void tick(MinecraftServer server) {
        Data data = Data.get(server);
        if (data.entries.isEmpty()) {
            return;
        }
        boolean dirty = false;
        for (int i = data.entries.size() - 1; i >= 0; i--) {
            Entry entry = data.entries.get(i);
            ServerLevel level = server.getLevel(entry.dimension);
            if (level == null) {
                data.entries.remove(i);
                dirty = true;
                continue;
            }
            long now = level.getGameTime();
            if (!entry.vanished && now >= entry.vanishAt) {
                // The snapshot was taken at cast time; re-read so a block changed in the
                // 1-3 tick stagger window is never restored to a stale state.
                BlockState current = level.getBlockState(entry.pos);
                if (current.isAir() || current.hasBlockEntity()) {
                    data.entries.remove(i); // changed under us — abort this block
                    dirty = true;
                    continue;
                }
                entry.state = current;
                level.setBlock(entry.pos, Blocks.AIR.defaultBlockState(), 3);
                entry.vanished = true;
                dirty = true;
                Vec3 center = Vec3.atCenterOf(entry.pos);
                // Datamosh shimmer per de-rezzed block (the client budget caps the flood);
                // 1-in-6 blocks emit a short digital chirp so the sweep crackles softly.
                WandPowers.sendQuasar(level, BORDER_GLITCH, center);
                if (level.random.nextInt(6) == 0) {
                    level.playSound(null, center.x, center.y, center.z,
                            EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.BLOCKS, 0.4F, 1.65F);
                } else if (level.random.nextInt(4) == 0) {
                    level.playSound(null, center.x, center.y, center.z,
                            SoundEvents.AMETHYST_CLUSTER_STEP, SoundSource.BLOCKS, 0.6F, 0.5F);
                }
            } else if (entry.vanished && now >= entry.restoreAt) {
                restore(level, entry);
                data.entries.remove(i);
                dirty = true;
            }
        }
        if (dirty) {
            data.setDirty();
        }
    }

    private static void restore(ServerLevel level, Entry entry) {
        BlockState current = level.getBlockState(entry.pos);
        if (!current.isAir() && !current.canBeReplaced()) {
            EclipseMod.LOGGER.debug("Phasenwelle restore at {} skipped — position occupied by {}",
                    entry.pos, current);
            return;
        }
        level.setBlock(entry.pos, entry.state, 3);
        Vec3 center = Vec3.atCenterOf(entry.pos);
        WandPowers.sendQuasar(level, IMPACT_LIGHT, center);
        if (level.random.nextInt(8) == 0) {
            // Re-rez chirp: the world knitting back is digital too, not just glassy.
            level.playSound(null, center.x, center.y, center.z,
                    EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.BLOCKS, 0.35F, 1.85F);
        } else if (level.random.nextInt(3) == 0) {
            level.playSound(null, center.x, center.y, center.z,
                    SoundEvents.AMETHYST_BLOCK_PLACE, SoundSource.BLOCKS, 0.5F, 1.4F);
        }
    }

    /**
     * Crash recovery: puts every leftover snapshot back immediately (called from
     * {@code WandTickService} on server start, before any new wave can run). Blocks whose
     * position is occupied are discarded, never overwritten.
     *
     * <p>FFIX-B (POLISH-SOL-02 / FINAL-SAT-SOL C2): reconciles ALL entries, not only
     * {@code vanished=true} ones. Chunk data and SavedData are separate persistence
     * streams, so a crash can persist the air write while the journal still says
     * {@code vanished=false}; {@link #restore} itself is the reconciler — it fills air /
     * replaceables with the snapshot and refuses to overwrite anything solid, so entries
     * whose vanish never reached the chunk are discarded without touching the world.</p>
     */
    static void restoreAllOnLoad(MinecraftServer server) {
        Data data = Data.get(server);
        if (data.entries.isEmpty()) {
            return;
        }
        int restored = 0;
        for (Entry entry : data.entries) {
            ServerLevel level = server.getLevel(entry.dimension);
            if (level == null) {
                continue;
            }
            restore(level, entry);
            restored++;
        }
        data.entries.clear();
        data.setDirty();
        EclipseMod.LOGGER.info("Phasenwelle crash recovery: {} snapshot(s) resolved on load", restored);
    }

    // ------------------------------------------------------------------ persistence

    /** One de-rezzed (or scheduled) block. */
    private static final class Entry {
        final ResourceKey<Level> dimension;
        final BlockPos pos;
        BlockState state;
        final long vanishAt;
        final long restoreAt;
        boolean vanished;

        Entry(ResourceKey<Level> dimension, BlockPos pos, BlockState state, long vanishAt,
                long restoreAt, boolean vanished) {
            this.dimension = dimension;
            this.pos = pos;
            this.state = state;
            this.vanishAt = vanishAt;
            this.restoreAt = restoreAt;
            this.vanished = vanished;
        }
    }

    /** SavedData ({@code data/eclipse_wand_phase.dat}) holding the live snapshots. */
    public static final class Data extends SavedData {
        private static final String DATA_NAME = "eclipse_wand_phase";

        private final List<Entry> entries = new ArrayList<>();

        public static Data get(MinecraftServer server) {
            return EclipseSavedData.getOverworld(server, DATA_NAME,
                    new SavedData.Factory<>(Data::new, Data::load));
        }

        public Data() {}

        public static Data load(CompoundTag tag, HolderLookup.Provider registries) {
            Data data = new Data();
            HolderLookup<net.minecraft.world.level.block.Block> blocks =
                    registries.lookupOrThrow(Registries.BLOCK);
            ListTag list = tag.getList("entries", Tag.TAG_COMPOUND);
            for (int i = 0; i < list.size(); i++) {
                CompoundTag row = list.getCompound(i);
                ResourceLocation dimensionId = ResourceLocation.tryParse(row.getString("dim"));
                if (dimensionId == null) {
                    continue;
                }
                BlockState state = NbtUtils.readBlockState(blocks, row.getCompound("state"));
                data.entries.add(new Entry(
                        ResourceKey.create(Registries.DIMENSION, dimensionId),
                        new BlockPos(row.getInt("x"), row.getInt("y"), row.getInt("z")),
                        state,
                        row.getLong("vanishAt"),
                        row.getLong("restoreAt"),
                        row.getBoolean("vanished")));
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (Entry entry : entries) {
                CompoundTag row = new CompoundTag();
                row.putString("dim", entry.dimension.location().toString());
                row.putInt("x", entry.pos.getX());
                row.putInt("y", entry.pos.getY());
                row.putInt("z", entry.pos.getZ());
                row.put("state", NbtUtils.writeBlockState(entry.state));
                row.putLong("vanishAt", entry.vanishAt);
                row.putLong("restoreAt", entry.restoreAt);
                row.putBoolean("vanished", entry.vanished);
                list.add(row);
            }
            tag.put("entries", list);
            return tag;
        }

        void add(ResourceKey<Level> dimension, BlockPos pos, BlockState state, long vanishAt, long restoreAt) {
            entries.add(new Entry(dimension, pos, state, vanishAt, restoreAt, false));
        }

        boolean contains(ResourceKey<Level> dimension, BlockPos pos) {
            for (Entry entry : entries) {
                if (entry.dimension == dimension && entry.pos.equals(pos)) {
                    return true;
                }
            }
            return false;
        }
    }
}
