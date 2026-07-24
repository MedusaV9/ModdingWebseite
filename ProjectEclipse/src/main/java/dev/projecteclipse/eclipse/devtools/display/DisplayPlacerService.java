package dev.projecteclipse.eclipse.devtools.display;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtOps;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;

/**
 * Persistent vanilla block-display editor. SavedData is authoritative for every display's
 * entity UUID, block, base position and animation parameters; vanilla entity NBT remains
 * a compatible mirror so the world is still intelligible without Eclipse loaded.
 */
public final class DisplayPlacerService extends SavedData {
    public static final String DATA_NAME = "eclipse_dev_displays";
    public static final String ENTITY_TAG = "eclipse_dev_display";
    public static final String COMPAT_ENTITY_TAG = "eclipse_display";

    public static final float DEFAULT_SPEED_DEG_PER_SEC = 12.0F;
    public static final float DEFAULT_BOB_AMPLITUDE = 0.15F;
    public static final float DEFAULT_BOB_PERIOD_SEC = 4.0F;

    private static final String TAG_ENTRIES = "displays";
    private static final double EDIT_REACH = 16.0D;
    private static final Map<UUID, UUID> SELECTED_BY_PLAYER = new LinkedHashMap<>();

    private final Map<UUID, Entry> entries = new LinkedHashMap<>();

    public DisplayPlacerService() {}

    public record DisplayInfo(UUID uuid, String id, ResourceKey<Level> dimension,
            Vec3 basePos, BlockState blockState, float axisX, float axisY, float axisZ,
            float speedDegPerSec, float bobAmplitude, float bobPeriodSec, float scale, boolean glow) {}

    private static final class Entry {
        final UUID uuid;
        ResourceKey<Level> dimension;
        double x;
        double y;
        double z;
        BlockState blockState;
        float axisX = 0.0F;
        float axisY = 1.0F;
        float axisZ = 0.0F;
        float speedDegPerSec = DEFAULT_SPEED_DEG_PER_SEC;
        float bobAmplitude = DEFAULT_BOB_AMPLITUDE;
        float bobPeriodSec = DEFAULT_BOB_PERIOD_SEC;
        float scale = 1.0F;
        boolean glow;

        Entry(UUID uuid, ResourceKey<Level> dimension, Vec3 pos, BlockState blockState) {
            this.uuid = uuid;
            this.dimension = dimension;
            this.x = pos.x;
            this.y = pos.y;
            this.z = pos.z;
            this.blockState = blockState;
        }

        DisplayInfo info() {
            return new DisplayInfo(uuid, shortId(uuid), dimension, new Vec3(x, y, z), blockState,
                    axisX, axisY, axisZ, speedDegPerSec, bobAmplitude, bobPeriodSec, scale, glow);
        }
    }

    public static DisplayPlacerService get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(DisplayPlacerService::new, DisplayPlacerService::load),
                DATA_NAME);
    }

    public static DisplayPlacerService load(CompoundTag tag, HolderLookup.Provider registries) {
        DisplayPlacerService service = new DisplayPlacerService();
        for (Tag raw : tag.getList(TAG_ENTRIES, Tag.TAG_COMPOUND)) {
            CompoundTag saved = (CompoundTag) raw;
            try {
                UUID uuid = saved.getUUID("uuid");
                ResourceLocation dimensionId = ResourceLocation.parse(saved.getString("dimension"));
                ResourceKey<Level> dimension = ResourceKey.create(Registries.DIMENSION, dimensionId);
                BlockState state = BlockState.CODEC.parse(NbtOps.INSTANCE, saved.get("blockState"))
                        .result().orElse(Blocks.STONE.defaultBlockState());
                Entry entry = new Entry(uuid, dimension,
                        new Vec3(saved.getDouble("x"), saved.getDouble("y"), saved.getDouble("z")), state);
                entry.axisX = saved.getFloat("axisX");
                entry.axisY = saved.getFloat("axisY");
                entry.axisZ = saved.getFloat("axisZ");
                if (entry.axisX * entry.axisX + entry.axisY * entry.axisY + entry.axisZ * entry.axisZ < 1.0e-6F) {
                    entry.axisY = 1.0F;
                }
                entry.speedDegPerSec = saved.getFloat("speedDegPerSec");
                entry.bobAmplitude = saved.getFloat("bobAmplitude");
                entry.bobPeriodSec = Math.max(0.1F, saved.getFloat("bobPeriodSec"));
                entry.scale = Math.max(0.05F, saved.getFloat("scale"));
                entry.glow = saved.getBoolean("glow");
                service.entries.put(uuid, entry);
            } catch (RuntimeException e) {
                EclipseMod.LOGGER.warn("Ignoring malformed persisted dev display {}", saved, e);
            }
        }
        return service;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (Entry entry : entries.values()) {
            CompoundTag saved = new CompoundTag();
            saved.putUUID("uuid", entry.uuid);
            saved.putString("dimension", entry.dimension.location().toString());
            saved.putDouble("x", entry.x);
            saved.putDouble("y", entry.y);
            saved.putDouble("z", entry.z);
            saved.put("blockState", BlockState.CODEC.encodeStart(NbtOps.INSTANCE, entry.blockState).getOrThrow());
            saved.putFloat("axisX", entry.axisX);
            saved.putFloat("axisY", entry.axisY);
            saved.putFloat("axisZ", entry.axisZ);
            saved.putFloat("speedDegPerSec", entry.speedDegPerSec);
            saved.putFloat("bobAmplitude", entry.bobAmplitude);
            saved.putFloat("bobPeriodSec", entry.bobPeriodSec);
            saved.putFloat("scale", entry.scale);
            saved.putBoolean("glow", entry.glow);
            list.add(saved);
        }
        tag.put(TAG_ENTRIES, list);
        return tag;
    }

    public Collection<DisplayInfo> displays() {
        return entries.values().stream().map(Entry::info)
                .sorted(Comparator.comparing(DisplayInfo::id)).toList();
    }

    @Nullable
    public DisplayInfo resolve(String id) {
        String normalized = id.toLowerCase(Locale.ROOT);
        Entry exact = null;
        for (Entry entry : entries.values()) {
            if (entry.uuid.toString().equalsIgnoreCase(normalized) || shortId(entry.uuid).equals(normalized)) {
                return entry.info();
            }
            if (entry.uuid.toString().startsWith(normalized)) {
                if (exact != null) {
                    return null;
                }
                exact = entry;
            }
        }
        return exact == null ? null : exact.info();
    }

    public DisplayInfo place(ServerLevel level, Vec3 pos, BlockState blockState) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
        display.setBlockState(blockState);
        display.moveTo(pos.x, pos.y, pos.z, 0.0F, 0.0F);
        display.addTag(ENTITY_TAG);
        display.addTag(COMPAT_ENTITY_TAG);
        level.addFreshEntity(display);

        Entry entry = new Entry(display.getUUID(), level.dimension(), pos, blockState);
        entries.put(entry.uuid, entry);
        applyAnimation(display, entry, level.getGameTime());
        setDirty();
        return entry.info();
    }

    /**
     * Wand primary action: select a tagged display under the crosshair, otherwise place
     * the off-hand BlockItem at the looked-at surface.
     */
    public boolean selectOrPlace(ServerPlayer player) {
        DisplayInfo target = targeted(player);
        if (target != null) {
            SELECTED_BY_PLAYER.put(player.getUUID(), target.uuid());
            player.displayClientMessage(net.minecraft.network.chat.Component.translatable(
                    "dev.eclipse.display.selected", target.id()), true);
            return true;
        }
        if (!(player.getOffhandItem().getItem() instanceof BlockItem blockItem)) {
            player.displayClientMessage(net.minecraft.network.chat.Component.translatable(
                    "dev.eclipse.display.wand.need_block"), true);
            return false;
        }
        HitResult hit = player.pick(EDIT_REACH, 1.0F, false);
        Vec3 placeAt;
        if (hit instanceof BlockHitResult blockHit) {
            placeAt = blockHit.getLocation().add(
                    blockHit.getDirection().getStepX() * 0.01D,
                    blockHit.getDirection().getStepY() * 0.01D,
                    blockHit.getDirection().getStepZ() * 0.01D);
        } else {
            placeAt = player.getEyePosition().add(player.getLookAngle().scale(4.0D));
        }
        DisplayInfo placed = place(player.serverLevel(), placeAt, blockItem.getBlock().defaultBlockState());
        SELECTED_BY_PLAYER.put(player.getUUID(), placed.uuid());
        player.displayClientMessage(net.minecraft.network.chat.Component.translatable(
                "dev.eclipse.display.placed", placed.id()), true);
        return true;
    }

    /** Sneak-wand action: delete the crosshair target, or the player's selected display. */
    public boolean deleteTargetedOrSelected(ServerPlayer player) {
        DisplayInfo targeted = targeted(player);
        UUID id = targeted != null ? targeted.uuid() : SELECTED_BY_PLAYER.get(player.getUUID());
        if (id == null || !delete(player.server, id)) {
            player.displayClientMessage(net.minecraft.network.chat.Component.translatable(
                    "dev.eclipse.display.delete.none"), true);
            return false;
        }
        SELECTED_BY_PLAYER.remove(player.getUUID(), id);
        player.displayClientMessage(net.minecraft.network.chat.Component.translatable(
                "dev.eclipse.display.deleted", shortId(id)), true);
        return true;
    }

    @Nullable
    public DisplayInfo targeted(ServerPlayer player) {
        Vec3 start = player.getEyePosition();
        Vec3 end = start.add(player.getLookAngle().scale(EDIT_REACH));
        DisplayInfo best = null;
        double bestDistance = Double.MAX_VALUE;
        for (Entry entry : entries.values()) {
            if (!entry.dimension.equals(player.level().dimension())) {
                continue;
            }
            Entity entity = player.serverLevel().getEntity(entry.uuid);
            if (!(entity instanceof Display.BlockDisplay display)) {
                continue;
            }
            Optional<Vec3> intersection = display.getBoundingBox().inflate(0.4D).clip(start, end);
            if (intersection.isPresent()) {
                double distance = start.distanceToSqr(intersection.get());
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = entry.info();
                }
            }
        }
        return best;
    }

    public boolean select(ServerPlayer player, String id) {
        DisplayInfo info = resolve(id);
        if (info == null) {
            return false;
        }
        SELECTED_BY_PLAYER.put(player.getUUID(), info.uuid());
        return true;
    }

    public boolean update(String id, String parameter, float a, float b, float c) {
        DisplayInfo info = resolve(id);
        if (info == null) {
            return false;
        }
        Entry entry = entries.get(info.uuid());
        switch (parameter.toLowerCase(Locale.ROOT)) {
            case "axis" -> {
                float lengthSq = a * a + b * b + c * c;
                if (lengthSq < 1.0e-6F) {
                    return false;
                }
                float invLength = (float) (1.0D / Math.sqrt(lengthSq));
                entry.axisX = a * invLength;
                entry.axisY = b * invLength;
                entry.axisZ = c * invLength;
            }
            case "speed" -> entry.speedDegPerSec = a;
            case "bob", "bobamp" -> entry.bobAmplitude = Math.max(0.0F, a);
            case "period", "bobperiod" -> entry.bobPeriodSec = Math.max(0.1F, a);
            case "scale" -> entry.scale = Math.max(0.05F, Math.min(16.0F, a));
            case "glow" -> entry.glow = a > 0.5F;
            default -> {
                return false;
            }
        }
        setDirty();
        return true;
    }

    public boolean move(MinecraftServer server, String id, Vec3 pos) {
        DisplayInfo info = resolve(id);
        if (info == null) {
            return false;
        }
        Entry entry = entries.get(info.uuid());
        entry.x = pos.x;
        entry.y = pos.y;
        entry.z = pos.z;
        ServerLevel level = server.getLevel(entry.dimension);
        if (level != null && level.getEntity(entry.uuid) instanceof Display.BlockDisplay display) {
            display.moveTo(pos.x, pos.y, pos.z, display.getYRot(), display.getXRot());
        }
        setDirty();
        return true;
    }

    public boolean delete(MinecraftServer server, String id) {
        DisplayInfo info = resolve(id);
        return info != null && delete(server, info.uuid());
    }

    private boolean delete(MinecraftServer server, UUID uuid) {
        Entry entry = entries.get(uuid);
        if (entry == null) {
            return false;
        }
        ServerLevel level = server.getLevel(entry.dimension);
        if (level == null) {
            return false; // keep SavedData tracking until the dimension is available for cleanup
        }
        level.getChunk((int) Math.floor(entry.x) >> 4, (int) Math.floor(entry.z) >> 4);
        Entity entity = level.getEntity(uuid);
        if (entity != null) {
            entity.discard();
        }
        entries.remove(uuid);
        SELECTED_BY_PLAYER.values().removeIf(uuid::equals);
        setDirty();
        return true;
    }

    /** Ticket-loads tracked chunks before discard so cleanup leaves no tagged orphan entities. */
    public int clear(MinecraftServer server) {
        List<UUID> ids = new ArrayList<>(entries.keySet());
        Set<UUID> removedIds = new HashSet<>();
        int removed = 0;
        for (UUID id : ids) {
            if (delete(server, id)) {
                removed++;
                removedIds.add(id);
            }
        }
        // Defensive orphan sweep for loaded legacy/corrupt entries that retained the
        // entity tag but lost SavedData tracking.
        for (ServerLevel level : server.getAllLevels()) {
            List<Entity> tagged = new ArrayList<>();
            for (Entity entity : level.getAllEntities()) {
                if (entity.getTags().contains(ENTITY_TAG)) {
                    tagged.add(entity);
                }
            }
            for (Entity entity : tagged) {
                entity.discard();
                if (removedIds.add(entity.getUUID())) {
                    removed++;
                }
            }
        }
        return removed;
    }

    /** Called every two ticks by DisplayAnimator. */
    void tick(MinecraftServer server) {
        for (Entry entry : entries.values()) {
            ServerLevel level = server.getLevel(entry.dimension);
            if (level == null) {
                continue;
            }
            net.minecraft.core.BlockPos pos = net.minecraft.core.BlockPos.containing(entry.x, entry.y, entry.z);
            if (!level.hasChunkAt(pos)) {
                continue;
            }
            Entity entity = level.getEntity(entry.uuid);
            Display.BlockDisplay display;
            if (entity == null) {
                display = respawn(level, entry);
            } else if (entity instanceof Display.BlockDisplay blockDisplay) {
                display = blockDisplay;
            } else {
                EclipseMod.LOGGER.warn("Dev display UUID {} is occupied by {}; animation skipped",
                        entry.uuid, entity.getType());
                continue;
            }
            display.addTag(ENTITY_TAG);
            display.addTag(COMPAT_ENTITY_TAG);
            applyAnimation(display, entry, level.getGameTime());
        }
    }

    private Display.BlockDisplay respawn(ServerLevel level, Entry entry) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
        display.setUUID(entry.uuid);
        display.setBlockState(entry.blockState);
        display.moveTo(entry.x, entry.y, entry.z, 0.0F, 0.0F);
        display.addTag(ENTITY_TAG);
        display.addTag(COMPAT_ENTITY_TAG);
        level.addFreshEntity(display);
        EclipseMod.LOGGER.info("Respawned missing persisted dev display {} in {}",
                shortId(entry.uuid), entry.dimension.location());
        return display;
    }

    private static void applyAnimation(Display.BlockDisplay display, Entry entry, long gameTime) {
        float seconds = gameTime / 20.0F;
        float angleRadians = (float) Math.toRadians(entry.speedDegPerSec * seconds);
        Vector3f axis = new Vector3f(entry.axisX, entry.axisY, entry.axisZ).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(angleRadians, axis);
        float bob = entry.bobAmplitude * (float) Math.sin(
                Math.PI * 2.0D * seconds / Math.max(0.1F, entry.bobPeriodSec));
        // Minecraft blocks occupy local [0,1]^3. Rotate the scaled half-extent and
        // translate it back so rotation stays centered on the entity origin.
        Vector3f centered = new Vector3f(
                -0.5F * entry.scale, -0.5F * entry.scale, -0.5F * entry.scale).rotate(rotation);
        centered.y += bob;
        Transformation transformation = new Transformation(
                centered,
                rotation,
                new Vector3f(entry.scale, entry.scale, entry.scale),
                new Quaternionf());
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(DisplayAnimator.TICK_INTERVAL);
        display.setTransformation(transformation);
        display.setGlowingTag(entry.glow);
    }

    static void clearTransientSelections() {
        SELECTED_BY_PLAYER.clear();
    }

    private static String shortId(UUID uuid) {
        return uuid.toString().substring(0, 8);
    }
}
