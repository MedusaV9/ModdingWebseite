package dev.projecteclipse.eclipse.xboxevent;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CFxEventPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Xbox event portal lifecycle (plan §2.13.4, C16 frameless rework): a pure marker
 * construct — one vanilla {@code minecraft:interaction} entity (3×4 trigger volume) and
 * NOTHING else. The decorative block-display frame is gone (C16: "no frame, just the
 * star/rift"); the visual is entirely C7's volumetric star-rift, opened via the frozen
 * {@code S2CFxEventPayload} rift events (§4.2: {@code a} = tear width 4.5–6, {@code b} =
 * style 1 → the layered star-prism with the parallax portal surface in
 * {@code veilfx/rift/RiftRenderer}). The {@value #ENTITY_TAG} command tag stays on the
 * interaction entity AND keeps being swept on placement/removal so legacy frame pieces in
 * existing worlds still clean themselves up.
 *
 * <p><b>Rift visibility (C16 upgrade)</b>: the open payload is per-player resynced from
 * {@link #ambientTick} — players who log in late, teleport in, or walk into range after
 * the placement broadcast get the rift opened for them exactly once ({@link #FX_SYNCED});
 * leaving the level drops the mark (the client kills rifts on dimension change) so
 * returning players resync too. The always-on server-side fallback is a cheap
 * reverse-portal particle column + ambient hum loop, so the portal reads as a portal even
 * for clients without the rift renderer (Iris/reducedFx fallback per §7).</p>
 */
public final class XboxPortal {
    /** Command tag on every portal piece (interaction + displays). */
    public static final String ENTITY_TAG = "eclipse_xbox_portal";

    /** Trigger volume dimensions (plan-frozen 3×4). */
    private static final float WIDTH = 3.0F;
    private static final float HEIGHT = 4.0F;

    /**
     * Frozen P2 §3.2 FX ids (= {@code FxPayloads.FX_RIFT_OPEN/FX_RIFT_CLOSE}); constructed
     * locally because {@code FxPayloads}' client dispatch references sibling P2 packages
     * still in flight this wave — W11 swaps these to the constants during integration
     * (byte-identical ids, see the P5-W9 wiring notes).
     */
    private static final ResourceLocation FX_RIFT_OPEN =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_open");
    private static final ResourceLocation FX_RIFT_CLOSE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/rift_close");
    /**
     * Rift tear diameter sent as payload {@code a} — P2-W8's wiring recommends 4.5–6 for
     * the 3×4 portal (the visual tear should overhang the trigger volume).
     */
    private static final float RIFT_FX_WIDTH = 5.0F;
    /** {@code b} value marking the portal style of {@code rift_open} (0 = structure). */
    private static final float RIFT_STYLE_PORTAL = 1.0F;
    private static final double FX_RANGE = 128.0D;

    /**
     * Players whose client has the rift open for the CURRENT portal (transient per-run
     * state — a fresh boot resyncs everyone, which is correct: their clients have no rift).
     * Guarded by the server thread; cleared on placement/removal.
     */
    private static final Set<UUID> FX_SYNCED = new HashSet<>();

    private XboxPortal() {}

    // ------------------------------------------------------------------ placement

    /**
     * First valid 5×5 flat spot ring-scanned {@code searchMin..searchMax} blocks out from the
     * shared spawn, skipping sanctum-protected positions (§2.10). {@code null} when the scan
     * fails — caller falls back to {@code /dev xboxevent portal here}.
     */
    @Nullable
    public static BlockPos findSpotNearSpawn(ServerLevel level) {
        XboxEventConfig.Values config = XboxEventConfig.get();
        BlockPos spawn = level.getSharedSpawnPos();
        for (int radius = config.portalSearchMinRadius(); radius <= config.portalSearchMaxRadius(); radius++) {
            int steps = Math.max(8, radius * 4);
            for (int step = 0; step < steps; step++) {
                double angle = (Math.PI * 2.0D * step) / steps;
                int x = spawn.getX() + (int) Math.round(Math.cos(angle) * radius);
                int z = spawn.getZ() + (int) Math.round(Math.sin(angle) * radius);
                BlockPos candidate = surfaceAt(level, x, z);
                if (candidate != null && isValidPad(level, candidate)) {
                    return candidate;
                }
            }
        }
        return null;
    }

    @Nullable
    private static BlockPos surfaceAt(ServerLevel level, int x, int z) {
        int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (y <= level.getMinBuildHeight() || y >= level.getMaxBuildHeight() - 6) {
            return null;
        }
        return new BlockPos(x, y, z);
    }

    /** 5×5 pad: corner+center heights within ±1, solid ground, 3×4 air above, not sanctum. */
    private static boolean isValidPad(ServerLevel level, BlockPos center) {
        if (SanctumProtection.isProtected(level, center)) {
            return false;
        }
        int centerY = center.getY();
        for (int dx = -2; dx <= 2; dx += 2) {
            for (int dz = -2; dz <= 2; dz += 2) {
                int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        center.getX() + dx, center.getZ() + dz);
                if (Math.abs(y - centerY) > 1) {
                    return false;
                }
            }
        }
        BlockPos below = center.below();
        if (!level.getBlockState(below).isSolidRender(level, below)) {
            return false;
        }
        BoundingBox airBox = new BoundingBox(
                center.getX() - 1, centerY, center.getZ() - 1,
                center.getX() + 1, centerY + 3, center.getZ() + 1);
        for (BlockPos pos : BlockPos.betweenClosed(
                airBox.minX(), airBox.minY(), airBox.minZ(), airBox.maxX(), airBox.maxY(), airBox.maxZ())) {
            if (!level.getBlockState(pos).getCollisionShape(level, pos).isEmpty()) {
                return false;
            }
        }
        return true;
    }

    // ------------------------------------------------------------------ spawn / despawn

    /**
     * Spawns the frameless portal at {@code base} (feet level): trigger volume only, no
     * decorative frame (C16). Records it in state and opens the star-rift for everyone
     * in range; late arrivals resync from {@link #ambientTick}.
     */
    public static void place(ServerLevel level, BlockPos base, XboxEventState state) {
        removeEntities(level, base); // idempotent: clears leftovers AND legacy frame pieces

        spawnInteraction(level, base);

        state.setPortal(level.dimension(), base);
        FX_SYNCED.clear();
        Vec3 fxCenter = riftCenter(base);
        for (ServerPlayer player : List.copyOf(level.players())) {
            if (player.position().distanceToSqr(fxCenter) <= FX_RANGE * FX_RANGE) {
                sendRiftOpen(player, fxCenter);
            }
        }
        // IDEA-07 §7: the portal speaks the mod's glitch language — EVENT_RIFT_OPEN's own
        // registry comment names "xbox portal — W7/W8" as an intended consumer.
        level.playSound(null, base, EclipseSounds.EVENT_RIFT_OPEN.get(), SoundSource.BLOCKS, 0.7F, 1.0F);
        EclipseMod.LOGGER.info("Xbox portal placed at {} in {}", base, level.dimension().location());
    }

    /** Removes all tagged pieces near the recorded portal position and fires the close FX. */
    public static void remove(ServerLevel level, BlockPos base, XboxEventState state) {
        removeEntities(level, base);
        Vec3 center = Vec3.atBottomCenterOf(base);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CFxEventPayload(FX_RIFT_CLOSE, riftCenter(base), RIFT_FX_WIDTH, 0.0F));
        // IDEA-07 §7: the tear snaps shut with the rift slam instead of vanilla glass.
        level.playSound(null, base, EclipseSounds.EVENT_RIFT_SLAM.get(), SoundSource.BLOCKS, 0.6F, 1.0F);
        state.setPortal(null, null);
        FX_SYNCED.clear();
        EclipseMod.LOGGER.info("Xbox portal removed at {} in {}", base, level.dimension().location());
    }

    private static void removeEntities(ServerLevel level, BlockPos base) {
        // Force the chunk so tagged pieces are discoverable right after boot. The sweep
        // box still covers the old frame footprint so pre-C16 worlds shed their frames.
        level.getChunk(base);
        AABB sweep = new AABB(base).inflate(6.0D, 8.0D, 6.0D);
        List<Entity> pieces = level.getEntities((Entity) null, sweep,
                entity -> entity.getTags().contains(ENTITY_TAG));
        pieces.forEach(Entity::discard);
    }

    /** Rift FX anchor: the visual tear floats at half the trigger height over the base. */
    private static Vec3 riftCenter(BlockPos base) {
        return Vec3.atBottomCenterOf(base).add(0.0D, HEIGHT / 2.0D, 0.0D);
    }

    private static void sendRiftOpen(ServerPlayer player, Vec3 fxCenter) {
        PacketDistributor.sendToPlayer(player, new S2CFxEventPayload(
                FX_RIFT_OPEN, fxCenter, RIFT_FX_WIDTH, RIFT_STYLE_PORTAL));
        FX_SYNCED.add(player.getUUID());
    }

    /** Player-entry trigger volume: the interaction entity's 3×4 box around {@code base}. */
    public static AABB collisionBox(BlockPos base) {
        double half = WIDTH / 2.0D;
        return new AABB(
                base.getX() + 0.5D - half, base.getY(), base.getZ() + 0.5D - half,
                base.getX() + 0.5D + half, base.getY() + HEIGHT, base.getZ() + 0.5D + half);
    }

    // ------------------------------------------------------------------ entities

    /** Interaction spawned via NBT — vanilla exposes no public width/height setters. */
    private static void spawnInteraction(ServerLevel level, BlockPos base) {
        CompoundTag tag = new CompoundTag();
        tag.putString("id", "minecraft:interaction");
        tag.putFloat("width", WIDTH);
        tag.putFloat("height", HEIGHT);
        tag.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(base.getX() + 0.5D));
        pos.add(DoubleTag.valueOf(base.getY()));
        pos.add(DoubleTag.valueOf(base.getZ() + 0.5D));
        tag.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(tag, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("Could not create xbox portal interaction entity at {}", base);
            return;
        }
        interaction.addTag(ENTITY_TAG);
        level.addFreshEntity(interaction);
    }

    // ------------------------------------------------------------------ ambient fallback

    /**
     * W4-ATMOS ledger id of the portal hum (IDEA-07 §7). Resolved from the registry at play
     * time and self-healing (the {@code UiSounds.play(String, ...)} pattern): until the
     * registry + sounds.json ask in {@code docs/plans_v3/wiring/W4-ATMOS_wiring.md} lands,
     * the loop falls back to {@code EVENT_BEAM_HUM} (gazer_whisper @1.2 baked) re-pitched
     * {@value #PORTAL_LOOP_FALLBACK_PITCH} — nearly the alias's gazer_whisper @1.35 target.
     */
    private static final ResourceLocation PORTAL_LOOP_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "event.xbox_portal_loop");
    private static final float PORTAL_LOOP_FALLBACK_PITCH = 1.15F;

    /**
     * Cheap always-on server-side FX (called every 10 ticks while the portal exists):
     * reverse-portal particle column (the Iris/reducedFx fallback), the periodic hum loop,
     * and the C16 per-player rift resync — anyone in the portal's level who has not yet
     * received the open payload gets it once ({@link #FX_SYNCED}); players who left the
     * level are unmarked so their client re-opens the rift when they come back.
     */
    public static void ambientTick(ServerLevel level, BlockPos base, long gameTime) {
        Vec3 center = Vec3.atBottomCenterOf(base);
        level.sendParticles(ParticleTypes.REVERSE_PORTAL,
                center.x, center.y + 2.0D, center.z,
                6, WIDTH / 4.0D, 1.4D, WIDTH / 4.0D, 0.01D);

        resyncRiftFx(level, base);

        if (gameTime % 100L == 0L) {
            // IDEA-07 §7: periodic hum in the mod's glitch language, not an End portal's.
            SoundEvent registered = BuiltInRegistries.SOUND_EVENT.getOptional(PORTAL_LOOP_ID).orElse(null);
            if (registered != null) {
                level.playSound(null, base, registered, SoundSource.BLOCKS, 0.35F, 1.0F);
            } else {
                level.playSound(null, base, EclipseSounds.EVENT_BEAM_HUM.get(), SoundSource.BLOCKS,
                        0.35F, PORTAL_LOOP_FALLBACK_PITCH);
            }
        }
    }

    /**
     * Sends the rift-open payload to unsynced players in range. Exactly-once per stay in
     * the level: the client replaces a same-position rift silently on double-send, but a
     * re-send restarts the 20-tick opening ease — so marked players are never re-sent.
     */
    private static void resyncRiftFx(ServerLevel level, BlockPos base) {
        Vec3 fxCenter = riftCenter(base);
        List<ServerPlayer> players = level.players();
        for (ServerPlayer player : List.copyOf(players)) {
            if (!FX_SYNCED.contains(player.getUUID())
                    && player.position().distanceToSqr(fxCenter) <= FX_RANGE * FX_RANGE) {
                sendRiftOpen(player, fxCenter);
            }
        }
        FX_SYNCED.removeIf(uuid -> {
            for (ServerPlayer player : players) {
                if (player.getUUID().equals(uuid)) {
                    return false;
                }
            }
            return true; // left the level — client killed the rift; resync on return
        });
    }
}
