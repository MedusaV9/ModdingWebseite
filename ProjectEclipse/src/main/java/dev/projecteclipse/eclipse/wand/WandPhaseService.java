package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
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
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.FallingBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * <b>RETIRED (F-038):</b> the Phasenwelle spell was replaced by the Umbra-Lanze
 * ({@code WandSpellEffects.castUmbraLanze} — a piercing beam that never writes a block).
 * NO spell dispatches into this class anymore; it stays alive solely as the journal
 * DRAIN for old saves: {@link #restoreAllOnLoad} and {@link #tick} (both driven by
 * {@code WandTickService}) keep restoring any blocks a pre-rework Phasenwelle left
 * vanished, then the journal simply stays empty forever.
 *
 * <p>Original design (kept for the recovery semantics below):</p>
 *
 * <p>The Phasenriss signature — <b>Phasenwelle</b> (W4-WAND spec / IDEA-19 R1): a cone of
 * blocks in front of the caster "de-rezzes" (collision + render vanish) for
 * {@code holdTicks}, then re-materializes <b>block by block</b> in random order with
 * glitch bursts. The world re-rendering itself IS the fantasy.</p>
 *
 * <p><b>Crash safety (FFIX-B / POLISH-SOL-02, hardened by AUDITFIX-1):</b> the journal is
 * a WRITE-AHEAD log. Casting stores {@code vanished=false} "prepare" records (snapshot at
 * cast time). When a block's turn comes, {@link #tick} re-reads the world, refreshes the
 * snapshot, flips the record to {@code vanished=true} and force-flushes the journal to
 * disk ({@link EclipseSavedData#flushOverworld}) BEFORE the destructive air write —
 * {@code setDirty()} alone only schedules a save and gives no ordering against the chunk
 * write that contains the air, so the on-disk journal can never lag behind a persisted
 * air chunk. On server start {@link #restoreAllOnLoad} reconciles the leftover journal
 * under STRICT rules: prepare records are dropped untouched (the write-ahead order proves
 * their air write never committed — restoring one would duplicate a block mined before
 * its vanish), {@code vanished=true} records are restored only into cells that still hold
 * what the vanish left behind (air), and any other cell content aborts the restore with a
 * log and never drops items (a drop would duplicate whenever the restore DID complete and
 * only its journal removal missed the disk).</p>
 *
 * <p><b>Hard blacklist</b> (never de-rezzed): block entities (chests, the altar, spawners
 * — inventories must never be voided), anything inside a spawn-protection zone
 * ({@link SpawnProtectionRules}), unbreakables (bedrock etc.), fluids and air, gravity
 * blocks (sand/gravel/anvils — a de-rezzed one would re-rez straight into a fall) and
 * blocks CARRYING a gravity block (never leave a sand column hanging over a phased hole).</p>
 *
 * <p><b>Physics safety (WANDFIX-1):</b> vanish and restore both write with
 * {@link #SILENT_FLAGS} ({@code UPDATE_CLIENTS | UPDATE_KNOWN_SHAPE} — NO neighbor
 * updates), so phasing never triggers falling-block physics, support-pops (torches,
 * rails) or fluid flow in the surroundings; the world around the cone is left exactly as
 * untouched as the fantasy promises. Restore never voids terrain: a gravity block that
 * still fell into the hole (outside trigger) is popped as its item drop before the
 * snapshot returns, a player-built block wins the spot but the snapshot pops as its
 * exact block item, and a living entity standing in the hole defers the restore a few
 * ticks (bounded) instead of entombing them.</p>
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

    /**
     * WANDFIX-1 root-cause fix: both phase writes used flag 3 ({@code UPDATE_ALL} =
     * neighbors + clients). The neighbor updates made every adjacent gravity block fall
     * into the fresh hole and popped every supported block (torches, rails) as loose
     * drops; the fallen block then OCCUPIED the restore position, so {@link #restore}
     * discarded the snapshot — permanent terrain loss. {@code UPDATE_KNOWN_SHAPE}
     * suppresses the neighbor/shape cascade entirely: clients still see the swap, but the
     * world physics never learns the block was gone.
     */
    private static final int SILENT_FLAGS = Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE;

    /** Max times one entry postpones its restore because a living entity fills the hole. */
    private static final int MAX_RESTORE_DEFERRALS = 60;
    /** Ticks per entity-occupied restore deferral (60 × 5 = at most 15 s of grace). */
    private static final int RESTORE_DEFER_TICKS = 5;

    private WandPhaseService() {}

    // ------------------------------------------------------------------ casting

    /**
     * Collects and schedules the de-rez cone. Returns {@code false} (no cost) when nothing
     * phaseable is in front of the caster.
     */
    public static boolean castWave(ServerPlayer player, WandConfig.Power power) {
        ServerLevel level = player.serverLevel();
        Data data = Data.get(player.server);
        double length = power.param("length", 12.0F);
        int maxBlocks = (int) power.param("maxBlocks", 32.0F);
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
            player.displayClientMessage(ServerLang.tr(player, "wand.eclipse.msg.no_blocks"), true);
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
        // FFIX-B durable prepare records. The REAL ordering barrier lives in tick() now
        // (AUDITFIX-1): every vanished=true flip is flushed BEFORE its air write, and
        // prepare records are never restored on load. This flush just puts the complete
        // scheduled wave on disk from tick one (cheap, one-shot per cast).
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
        // D11 reality seams (visual-only): two thin glitch scars linger where the
        // scanline passed, flickering out over ~2 s while the cone blocks are still
        // de-rezzed — the wave leaves stitches in the world, not just a sweep.
        WandTickService.schedule(level, 5, () -> WandPowers.sendQuasar(level,
                WandPowers.RISS_SEAM_SCAR, foot.add(march.scale(bandReach * 0.3D)).add(0.0D, 0.4D, 0.0D)));
        WandTickService.schedule(level, 8, () -> WandPowers.sendQuasar(level,
                WandPowers.RISS_SEAM_SCAR, foot.add(march.scale(bandReach * 0.75D)).add(0.0D, 0.4D, 0.0D)));
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                SoundEvents.ENDERMAN_TELEPORT, SoundSource.PLAYERS, 0.9F, 0.55F);
        level.playSound(null, player.getX(), player.getY(), player.getZ(),
                EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.PLAYERS, 0.6F, 1.35F);
        // WANDFIX-2 Phasenschock: living things standing IN the de-rezzed cone lose their
        // footing with the ground — phase-shear damage + Slowness II. The utility wave is
        // now also a zoning tool, not damage-free terrain dressing.
        float shearDamage = power.param("shearDamage", 0.0F)
                * WandPerks.damageMultiplier(player); // WANDFIX-4 damage line
        if (shearDamage > 0.0F) {
            int slowTicks = (int) power.param("shearSlowTicks", 60.0F);
            List<LivingEntity> sheared = level.getEntitiesOfClass(LivingEntity.class,
                    new AABB(origin, origin).inflate(length + 1.0D),
                    e -> e != player && e.isAlive());
            for (LivingEntity victim : sheared) {
                Vec3 toVictim = victim.position().add(0.0D, victim.getBbHeight() * 0.5D, 0.0D)
                        .subtract(origin);
                double along = toVictim.dot(dir);
                if (along < 1.0D || along > length
                        || toVictim.subtract(dir.scale(along)).length() > along * CONE_TAN + 0.5D
                        || SpawnProtectionRules.isInProtectionZone(level, victim.blockPosition())) {
                    continue;
                }
                victim.hurt(player.damageSources().indirectMagic(player, player), shearDamage);
                if (slowTicks > 0) {
                    victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN,
                            slowTicks, 1), player);
                }
                WandPowers.sendQuasar(level, BORDER_GLITCH,
                        victim.position().add(0.0D, 1.0D, 0.0D));
            }
        }
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
        // WANDFIX-1: gravity blocks never phase — a de-rezzed anvil/sand would re-rez
        // straight into a fall (displacement), and one already falling can't be journaled.
        if (state.getBlock() instanceof FallingBlock) {
            return false;
        }
        // WANDFIX-1: never pull the floor out from under a gravity block either. The
        // silent flags stop the IMMEDIATE fall, but any later neighbor update (a mob
        // trample, a player build) would still drop the column into the hole.
        if (level.getBlockState(pos.above()).getBlock() instanceof FallingBlock) {
            return false;
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
        List<Entry> vanishing = null;
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
                // AUDITFIX-1 write-ahead: refresh the snapshot and flip the record NOW,
                // but the destructive air write waits until the whole batch has been
                // flushed to disk below — journal first, chunk second, never the reverse.
                entry.state = current;
                entry.vanished = true;
                dirty = true;
                if (vanishing == null) {
                    vanishing = new ArrayList<>(4);
                }
                vanishing.add(entry);
            } else if (entry.vanished && now >= entry.restoreAt) {
                // WANDFIX-1: never re-rez a block inside a living body — postpone in
                // short bounded steps until the hole is free (or the grace runs out).
                if (entry.restoreDeferrals < MAX_RESTORE_DEFERRALS
                        && !level.getEntitiesOfClass(LivingEntity.class, new AABB(entry.pos),
                                LivingEntity::isAlive).isEmpty()) {
                    entry.restoreAt = now + RESTORE_DEFER_TICKS;
                    entry.restoreDeferrals++;
                    dirty = true;
                    continue;
                }
                restore(level, entry);
                data.entries.remove(i);
                dirty = true;
            }
        }
        if (vanishing != null) {
            // AUDITFIX-1 durability barrier: one synchronous flush per vanish batch (only
            // ticks that actually de-rez pay it) puts the vanished=true flips + refreshed
            // snapshots ON DISK before the first air write. A crash at any later point
            // leaves a journal at least as new as the chunk, so restoreAllOnLoad can trust
            // the vanished flag.
            data.setDirty();
            EclipseSavedData.flushOverworld(server);
            for (Entry entry : vanishing) {
                ServerLevel level = server.getLevel(entry.dimension);
                if (level != null) {
                    applyVanish(level, entry);
                }
            }
        } else if (dirty) {
            data.setDirty();
        }
    }

    /**
     * The destructive half of the vanish transition. Only ever called AFTER the journal
     * flush in {@link #tick} put this entry's {@code vanished=true} record on disk.
     */
    private static void applyVanish(ServerLevel level, Entry entry) {
        level.setBlock(entry.pos, Blocks.AIR.defaultBlockState(), SILENT_FLAGS);
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
    }

    /**
     * Live-session restore (tick lane only — the crash-recovery lane
     * {@link #restoreAllOnLoad} deliberately does NOT share this method, because a
     * reloaded journal may be stale and must never drop anything). Here the entry is
     * authoritative: the write-ahead barrier flushed it before its own air write, and the
     * de-rezzed block's matter exists nowhere but this journal, so WANDFIX-1 terrain
     * conservation stays active — a gravity block that fell into the hole is popped as
     * its drop, and a player-built block wins the spot while the snapshot comes back as
     * its EXACT block item (AUDITFIX-1: {@code new ItemStack(entry.state.getBlock())},
     * never {@code Block.dropResources}, whose loot tables transmute the material — glass
     * drops nothing, stone drops cobblestone, ores depend on the tool). Duplication is
     * impossible on this lane: the cell holds someone else's block and the item we pop is
     * the snapshot's only copy.
     */
    private static void restore(ServerLevel level, Entry entry) {
        BlockState current = level.getBlockState(entry.pos);
        if (current == entry.state) {
            return; // someone rebuilt the identical block — already looks restored, done
        }
        if (!current.isAir() && !current.canBeReplaced()) {
            if (current.getBlock() instanceof FallingBlock && !current.hasBlockEntity()) {
                // WANDFIX-1: a gravity block still found its way into the hole (an outside
                // neighbor update mid-hold). Pop it as its item so nothing is voided, then
                // knit the original block back underneath the drop.
                level.destroyBlock(entry.pos, true);
            } else {
                // A player built here mid-phase — their block wins the spot, but the
                // snapshot returns as its exact block item (see method doc) instead of
                // being voided (WANDFIX-1 terrain conservation).
                Block.popResource(level, entry.pos, new ItemStack(entry.state.getBlock()));
                EclipseMod.LOGGER.debug("Phasenwelle restore at {} blocked by {} — snapshot popped as its exact item",
                        entry.pos, current);
                return;
            }
        }
        level.setBlock(entry.pos, entry.state, SILENT_FLAGS);
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
     * Crash recovery (called from {@code WandTickService} on server start, before any new
     * wave can run): reconciles every leftover journal record against the actual world,
     * then clears the journal. STRICT rules (AUDITFIX-1) — chunk data and SavedData are
     * separate persistence streams, so every pairing of "which write reached the disk"
     * must resolve without duplicating or eating blocks:
     * <ul>
     *   <li>{@code vanished=false} prepare record → drop it, touch nothing. The write-ahead
     *       barrier in {@link #tick} flushes {@code vanished=true} BEFORE the air write, so
     *       a prepare record on disk proves this block's air write never committed; any
     *       difference between cell and snapshot is a legitimate outside change (e.g. the
     *       player mined the block and collected the drop — restoring would DUPLICATE it).</li>
     *   <li>{@code vanished=true}, cell still holds the snapshot → done. Either the air
     *       write never reached the chunk, or the restore already completed and only the
     *       journal removal missed the disk.</li>
     *   <li>{@code vanished=true}, cell is air (exactly what the vanish left behind) →
     *       knit the snapshot back.</li>
     *   <li>{@code vanished=true}, cell holds anything else → ABORT with a warn log. Never
     *       overwrite (a player may have built there), and never drop items — a drop would
     *       duplicate whenever the cell contents came from a completed restore whose
     *       journal removal missed the disk.</li>
     * </ul>
     */
    static void restoreAllOnLoad(MinecraftServer server) {
        Data data = Data.get(server);
        if (data.entries.isEmpty()) {
            return;
        }
        int restored = 0;
        int dropped = 0;
        int aborted = 0;
        for (Entry entry : data.entries) {
            ServerLevel level = server.getLevel(entry.dimension);
            if (level == null) {
                dropped++;
                continue;
            }
            if (!entry.vanished) {
                dropped++; // prepare record: the air write never committed — leave the world alone
                continue;
            }
            BlockState current = level.getBlockState(entry.pos);
            if (current == entry.state) {
                dropped++; // air write or completed restore missed the disk — already correct
                continue;
            }
            if (current.isAir()) {
                level.setBlock(entry.pos, entry.state, SILENT_FLAGS);
                restored++;
            } else {
                aborted++;
                EclipseMod.LOGGER.warn(
                        "Phasenwelle crash recovery: cell {} holds {} instead of air — restore of {} aborted (no drop)",
                        entry.pos, current, entry.state);
            }
        }
        data.entries.clear();
        data.setDirty();
        EclipseMod.LOGGER.info(
                "Phasenwelle crash recovery: {} restored, {} already-correct/prepare record(s) dropped, {} aborted on load",
                restored, dropped, aborted);
    }

    // ------------------------------------------------------------------ persistence

    /** One de-rezzed (or scheduled) block. */
    private static final class Entry {
        final ResourceKey<Level> dimension;
        final BlockPos pos;
        BlockState state;
        final long vanishAt;
        /** Mutable: entity-occupied restores are postponed in {@value #RESTORE_DEFER_TICKS}-tick steps. */
        long restoreAt;
        /** AUDITFIX-1: flipped (and flushed to disk) BEFORE the air write, never after. */
        boolean vanished;
        /** Transient deferral budget (not persisted — a reload simply re-grants the grace). */
        int restoreDeferrals;

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
