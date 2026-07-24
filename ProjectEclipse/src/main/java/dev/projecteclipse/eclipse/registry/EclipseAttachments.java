package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import com.mojang.serialization.Codec;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutsceneLock;
import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.attachment.AttachmentType;
import net.neoforged.neoforge.registries.DeferredRegister;
import net.neoforged.neoforge.registries.NeoForgeRegistries;

/** Data attachment type registry for Project: Eclipse. */
public final class EclipseAttachments {
    public static final DeferredRegister<AttachmentType<?>> ATTACHMENTS =
            DeferredRegister.create(NeoForgeRegistries.ATTACHMENT_TYPES, EclipseMod.MOD_ID);

    /** Remaining lives of a player. Default 5, persisted, kept across death. */
    public static final Supplier<AttachmentType<Integer>> LIVES = ATTACHMENTS.register(
            "lives",
            () -> AttachmentType.builder(() -> 5).serialize(Codec.INT).copyOnDeath().build());

    /** Epoch millis of the player's first overworld join; 0 = never joined yet. */
    public static final Supplier<AttachmentType<Long>> FIRST_OVERWORLD_JOIN = ATTACHMENTS.register(
            "first_overworld_join",
            () -> AttachmentType.builder(() -> 0L).serialize(Codec.LONG).copyOnDeath().build());

    /** Whether the player is event-banned (e.g. out of lives). */
    public static final Supplier<AttachmentType<Boolean>> BANNED = ATTACHMENTS.register(
            "banned",
            () -> AttachmentType.builder(() -> false).serialize(Codec.BOOL).copyOnDeath().build());

    /**
     * Cutscene/unlock freeze lock — deliberately TRANSIENT: no {@code serialize}, no
     * {@code copyOnDeath}, so a restart, relog or death can never leave a player frozen.
     * Only {@code cutscene.FreezeService} reads or writes it.
     */
    public static final Supplier<AttachmentType<CutsceneLock>> CUTSCENE_LOCK = ATTACHMENTS.register(
            "cutscene_lock",
            () -> AttachmentType.builder(CutsceneLock::new).build());

    /**
     * Personal umbral-shard balance banked at the altar shop (W13 economy). Credited by
     * sneak-depositing umbral shards at the altar, spent on personal rewards; survives
     * death so a kill can never rob the victim's bank. Only {@code economy.ShardEconomy}
     * should write it (plus the {@code /eclipse shards} admin command).
     */
    public static final Supplier<AttachmentType<Integer>> SHARDS = ATTACHMENTS.register(
            "shards",
            () -> AttachmentType.builder(() -> 0).serialize(Codec.INT).copyOnDeath().build());

    /**
     * Per-player daily goal completion (W13): {@code (day << 8) | bitmask}, bit i = goal
     * line i of that day ticked. Encoding the day makes stale progress self-invalidating —
     * {@code progression.GoalTracker} reads the mask as 0 whenever the stored day differs
     * from the current event day. Only {@code GoalTracker} should write it.
     */
    public static final Supplier<AttachmentType<Integer>> GOAL_PROGRESS = ATTACHMENTS.register(
            "goal_progress",
            () -> AttachmentType.builder(() -> 0).serialize(Codec.INT).copyOnDeath().build());

    /**
     * Per-chunk player-placed block bitsets (P4 analytics). Used by {@code PlacedBlockTracker}
     * to distinguish natural vs player-placed blocks for XP, goals, and awards. Not copied on
     * death — chunk-scoped persistence only.
     */
    public static final Supplier<AttachmentType<PlacedBlockData>> PLACED_BLOCKS = ATTACHMENTS.register(
            "placed_blocks",
            () -> AttachmentType.builder(PlacedBlockData::empty)
                    .serialize(PlacedBlockData.CODEC)
                    .build());

    private EclipseAttachments() {}

    public static void register(IEventBus modEventBus) {
        ATTACHMENTS.register(modEventBus);
    }
}
