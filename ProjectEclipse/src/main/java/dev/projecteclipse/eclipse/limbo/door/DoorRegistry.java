package dev.projecteclipse.eclipse.limbo.door;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.material.MapColor;
import net.minecraft.world.level.material.PushReaction;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * P6-W3's own DeferredRegisters for the Respawn Door (plans_v3 §2.5 — frozen §6 ids
 * {@code eclipse:respawn_door}, {@code eclipse:respawn_door_filler}, BE
 * {@code eclipse:respawn_door}). Needs ONE wiring line in the {@code EclipseMod}
 * constructor (see {@code docs/plans_v3/wiring/P6-W3_wiring.md}):
 *
 * <pre>{@code DoorRegistry.register(modEventBus);}</pre>
 *
 * <p>Until that line lands, every consumer is guarded by {@link #isBound()} —
 * {@code RespawnDoorApi.ensureDoor} and the client renderer registration no-op with one
 * log line, so the build and both run configs stay green (P6-W1 pattern).</p>
 *
 * <p>Both blocks: invisible (BER draws), full-cube collision, unbreakable in survival,
 * piston-proof, {@code noOcclusion} (neighbor faces must keep rendering behind the
 * invisible cells), and purple block light 7 while {@code LIT} (all states except
 * SEALED). The BlockItem exists for admin/testing placement only ({@code /give}) — the
 * ship's door is placed by {@code RespawnDoorApi.ensureDoor} at boot.</p>
 */
public final class DoorRegistry {
    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(Registries.BLOCK, EclipseMod.MOD_ID);
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);
    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
            DeferredRegister.create(Registries.BLOCK_ENTITY_TYPE, EclipseMod.MOD_ID);

    public static final DeferredHolder<Block, RespawnDoorBlock> RESPAWN_DOOR =
            BLOCKS.register("respawn_door", () -> new RespawnDoorBlock(doorProperties()));

    public static final DeferredHolder<Block, RespawnDoorFillerBlock> RESPAWN_DOOR_FILLER =
            BLOCKS.register("respawn_door_filler", () -> new RespawnDoorFillerBlock(doorProperties()));

    public static final DeferredHolder<Item, BlockItem> RESPAWN_DOOR_ITEM =
            ITEMS.register("respawn_door",
                    () -> new BlockItem(RESPAWN_DOOR.get(), new Item.Properties()));

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<RespawnDoorBlockEntity>> RESPAWN_DOOR_BE =
            BLOCK_ENTITIES.register("respawn_door",
                    () -> BlockEntityType.Builder.of(RespawnDoorBlockEntity::new, RESPAWN_DOOR.get()).build(null));

    private DoorRegistry() {}

    private static BlockBehaviour.Properties doorProperties() {
        return BlockBehaviour.Properties.of()
                .mapColor(MapColor.COLOR_PURPLE)
                .sound(SoundType.WOOD)
                .strength(-1.0F, 3600000.0F) // survival-unbreakable stage prop (bedrock-grade)
                .noLootTable()
                .noOcclusion()
                .pushReaction(PushReaction.BLOCK)
                .lightLevel(state -> state.getValue(BlockStateProperties.LIT) ? 7 : 0);
    }

    /** The one EclipseMod wiring line (documented in P6-W3_wiring.md). */
    public static void register(IEventBus modEventBus) {
        BLOCKS.register(modEventBus);
        ITEMS.register(modEventBus);
        BLOCK_ENTITIES.register(modEventBus);
    }

    /** Whether the registers have been wired AND bound (safe-guard for all consumers). */
    public static boolean isBound() {
        return RESPAWN_DOOR.isBound() && RESPAWN_DOOR_FILLER.isBound() && RESPAWN_DOOR_BE.isBound();
    }
}
