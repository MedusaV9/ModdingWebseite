package de.sonic0810.goobymod.block.entity;

import de.sonic0810.goobymod.block.RabbitHutchBlock;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModBlockEntities;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ClientGamePacketListener;
import net.minecraft.network.protocol.game.ClientboundBlockEntityDataPacket;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.RandomSource;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;

/** Persistent comfort, resident, nameplate, and occupancy data for Hutch 2.0. */
public final class RabbitHutchBlockEntity extends BlockEntity {
    public static final int MAX_RESIDENT_NAME_LENGTH = 64;
    private static final List<net.minecraft.world.item.Item> MORNING_GIFTS =
            List.of(Items.CARROT, Items.WHEAT, Items.GOLD_NUGGET);

    private int comfort;
    @Nullable
    private UUID resident;
    private String residentName = "";
    @Nullable
    private UUID occupant;
    private long lastMorningGiftDay = -1L;

    public RabbitHutchBlockEntity(BlockPos pos, BlockState state) {
        super(ModBlockEntities.RABBIT_HUTCH.get(), pos, state);
        this.comfort = state.hasProperty(RabbitHutchBlock.BEDDING)
                ? state.getValue(RabbitHutchBlock.BEDDING) : 0;
    }

    public int getComfort() {
        return this.comfort;
    }

    public void setComfort(int comfort) {
        this.comfort = Math.max(0, Math.min(RabbitHutchBlock.MAX_COMFORT, comfort));
        if (this.level != null && getBlockState().hasProperty(RabbitHutchBlock.BEDDING)
                && getBlockState().getValue(RabbitHutchBlock.BEDDING) != this.comfort) {
            this.level.setBlock(this.worldPosition,
                    getBlockState().setValue(RabbitHutchBlock.BEDDING, this.comfort), 3);
        }
        sync();
    }

    public void bind(GoobyEntity gooby) {
        bind(gooby.getUUID(), gooby.getName().getString());
    }

    public void bind(UUID resident, String residentName) {
        String boundedName = boundName(residentName);
        if (resident.equals(this.resident) && boundedName.equals(this.residentName)) {
            return;
        }
        this.resident = resident;
        this.residentName = boundedName;
        sync();
    }

    public boolean isBoundTo(GoobyEntity gooby) {
        return this.resident != null && this.resident.equals(gooby.getUUID());
    }

    @Nullable
    public UUID getResident() {
        return this.resident;
    }

    public String getResidentName() {
        return this.residentName;
    }

    public void occupy(GoobyEntity gooby) {
        UUID previousOccupant = this.occupant;
        String previousName = this.residentName;
        this.occupant = gooby.getUUID();
        if (isBoundTo(gooby)) {
            this.residentName = boundName(gooby.getName().getString());
        }
        if (Objects.equals(previousOccupant, this.occupant) && previousName.equals(this.residentName)) {
            return;
        }
        sync();
    }

    public void vacate() {
        if (this.occupant == null) {
            return;
        }
        this.occupant = null;
        sync();
    }

    @Nullable
    public UUID getOccupant() {
        return this.occupant;
    }

    public boolean isOccupied() {
        return this.occupant != null;
    }

    public boolean isAvailableFor(GoobyEntity gooby) {
        return (this.resident == null || isBoundTo(gooby))
                && (this.occupant == null || this.occupant.equals(gooby.getUUID()));
    }

    public int wakeSatisfaction() {
        return 10 + this.comfort * 5;
    }

    public ItemStack createMorningGift(RandomSource random) {
        if (this.comfort < RabbitHutchBlock.MAX_COMFORT || random.nextInt(3) != 0) {
            return ItemStack.EMPTY;
        }
        return new ItemStack(MORNING_GIFTS.get(random.nextInt(MORNING_GIFTS.size())));
    }

    public long getLastMorningGiftDay() {
        return this.lastMorningGiftDay;
    }

    public boolean applyMorningComfort(ServerLevel level, GoobyEntity gooby, RandomSource random) {
        gooby.addSatisfaction(wakeSatisfaction());
        long day = level.getDayTime() / 24000L;
        ItemStack gift = day == this.lastMorningGiftDay ? ItemStack.EMPTY : createMorningGift(random);
        if (!gift.isEmpty()) {
            gooby.spawnAtLocation(gift, 0.35F);
            this.lastMorningGiftDay = day;
        }
        vacate();
        return !gift.isEmpty();
    }

    private void sync() {
        setChanged();
        if (this.level != null) {
            this.level.sendBlockUpdated(this.worldPosition, getBlockState(), getBlockState(), 3);
        }
    }

    @Override
    protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.saveAdditional(tag, registries);
        tag.putInt("Comfort", this.comfort);
        if (this.resident != null) {
            tag.putUUID("Resident", this.resident);
        }
        tag.putString("ResidentName", this.residentName);
        if (this.occupant != null) {
            tag.putUUID("Occupant", this.occupant);
        }
        tag.putLong("LastMorningGiftDay", this.lastMorningGiftDay);
    }

    @Override
    protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.loadAdditional(tag, registries);
        this.comfort = Math.max(0, Math.min(RabbitHutchBlock.MAX_COMFORT, tag.getInt("Comfort")));
        this.resident = tag.hasUUID("Resident") ? tag.getUUID("Resident") : null;
        this.residentName = boundName(tag.getString("ResidentName"));
        this.occupant = tag.hasUUID("Occupant") ? tag.getUUID("Occupant") : null;
        this.lastMorningGiftDay = tag.contains("LastMorningGiftDay")
                ? tag.getLong("LastMorningGiftDay") : -1L;
    }

    @Override
    public CompoundTag getUpdateTag(HolderLookup.Provider registries) {
        return saveWithoutMetadata(registries);
    }

    @Override
    public Packet<ClientGamePacketListener> getUpdatePacket() {
        return ClientboundBlockEntityDataPacket.create(this);
    }

    private static String boundName(String name) {
        if (name == null || name.isEmpty()) {
            return "";
        }
        return name.length() <= MAX_RESIDENT_NAME_LENGTH
                ? name : name.substring(0, MAX_RESIDENT_NAME_LENGTH);
    }
}
