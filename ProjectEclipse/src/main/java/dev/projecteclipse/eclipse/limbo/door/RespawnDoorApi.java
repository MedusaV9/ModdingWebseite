package dev.projecteclipse.eclipse.limbo.door;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/**
 * FROZEN server API of the Respawn Door for P3 (death/respawn UI) and P4 (lives flow) —
 * plans_v3 §2.5/§4.3/§4.4. The door is a stage prop: nothing in here runs lives logic.
 *
 * <p><b>Contract summary</b> (mirrored in {@code docs/plans_v3/wiring/P6-W3_wiring.md}):</p>
 * <ul>
 *   <li>{@link #setGlobalState} — P4 drives the world-visible door state. Ghost viewers
 *       still SEE it closed while it is globally OPEN (client-automatic).</li>
 *   <li>{@link #playOpenFor} / {@link #playCloseFor} / {@link #clearCueFor} — personal
 *       walk-through sequence for one revived player ({@link S2CDoorCuePayload}); a cue
 *       outranks the ghost rule on that client until cleared. Collision stays solid for
 *       everyone — teleport the player through via {@link #doorFrontPos} (documented v1
 *       limitation, no per-player collision).</li>
 *   <li>{@link #playLockedShudder} — global "the door refuses" rattle (also fired when a
 *       ghost right-clicks the door).</li>
 *   <li>{@link #doorFrontPos} + {@link #doorFacing} — respawn/cinematic placement. NOTE:
 *       the front cell doubles as the Ferryman's kneel anchor (x=−16, z=0); offset one
 *       block further out if a Ferryman fight is live.</li>
 * </ul>
 *
 * <p>{@link #ensureDoor} and {@link #publishAnchors} run from
 * {@code GhostShipBuilder.onServerStarted}: idempotent multiblock placement/repair into
 * the v2 sterncastle bulkhead and the frozen {@link FxAnchors#SHIP_DOOR} /
 * {@link FxAnchors#SHIP_DECK} positions for P2's door-glow FX. Both no-op (with one log
 * line) until the ship is v2 and {@code DoorRegistry} is wired.</p>
 */
public final class RespawnDoorApi {
    private RespawnDoorApi() {}

    // ------------------------------------------------------------------ frozen geometry

    /** The door's front direction on the ship: toward the bow (+X). */
    public static Direction doorFacing() {
        return Direction.EAST;
    }

    /** The multiblock controller cell: bulkhead plane, bottom-center of the aperture. */
    public static BlockPos controllerPos(ServerLevel limbo) {
        return new BlockPos(GhostShipBuilder.DOOR_X, GhostShipBuilder.waterlineY(limbo) + 4, 0);
    }

    /**
     * Feet-level cell directly in front of the door (the walk-through/respawn spot).
     * Shared with the Ferryman's stern kneel anchor — P4 should offset one block toward
     * the bow while a Ferryman fight is live.
     */
    public static BlockPos doorFrontPos(ServerLevel limbo) {
        return controllerPos(limbo).relative(doorFacing());
    }

    // ------------------------------------------------------------------ boot placement

    /**
     * Places/repairs the 3×5 door multiblock in the v2 sterncastle aperture (idempotent:
     * zero block changes when everything already matches). Skipped with a log line while
     * {@code DoorRegistry} is unwired or the ship is still pre-v2 (both retried next
     * start). An existing controller BE (and its saved {@link DoorState}) is preserved.
     */
    public static void ensureDoor(ServerLevel limbo) {
        if (!DoorRegistry.isBound()) {
            EclipseMod.LOGGER.info(
                    "Respawn door blocks not registered (DoorRegistry wiring line pending) — placement skipped");
            return;
        }
        if (ShipVersionData.get(limbo).version() < ShipVersionData.VERSION_V2) {
            EclipseMod.LOGGER.info("Respawn door placement skipped: ghost ship is not v2 yet");
            return;
        }
        BlockPos controller = controllerPos(limbo);
        boolean lit = globalState(limbo) != DoorState.SEALED;
        BlockState wanted = DoorRegistry.RESPAWN_DOOR.get().defaultBlockState()
                .setValue(RespawnDoorBlock.FACING, doorFacing())
                .setValue(RespawnDoorBlock.LIT, lit);
        int changed = 0;
        if (!limbo.getBlockState(controller).equals(wanted)) {
            limbo.setBlock(controller, wanted, Block.UPDATE_ALL);
            changed++;
        }
        changed += RespawnDoorBlock.placeFillers(limbo, controller, doorFacing(), lit);
        if (changed > 0) {
            EclipseMod.LOGGER.info("Respawn door multiblock placed/repaired at {} ({} cell(s) changed)",
                    controller.toShortString(), changed);
        }
    }

    /**
     * Publishes the frozen FX anchors once the v2 ship exists: {@code eclipse:ship_door}
     * = center of the door's front plane, {@code eclipse:ship_deck} = midship feet
     * level. P2's {@code ShipDoorGlow} and limbo ambience key off these.
     */
    public static void publishAnchors(ServerLevel limbo) {
        if (ShipVersionData.get(limbo).version() < ShipVersionData.VERSION_V2) {
            return;
        }
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        FxAnchors.set(FxAnchors.SHIP_DOOR, limbo,
                new Vec3(GhostShipBuilder.DOOR_X + 1.0D, deckY + 3.5D, 0.5D));
        FxAnchors.set(FxAnchors.SHIP_DECK, limbo, new Vec3(0.5D, deckY + 1.0D, 0.5D));
    }

    // ------------------------------------------------------------------ P3/P4 surface

    /** Current global door state ({@link DoorState#CLOSED} while the door is absent). */
    public static DoorState globalState(ServerLevel limbo) {
        return limbo.getBlockEntity(controllerPos(limbo)) instanceof RespawnDoorBlockEntity door
                ? door.doorState() : DoorState.CLOSED;
    }

    /**
     * P4: sets the world-visible door state (syncs to every client via BE data, flips
     * the purple block light, plays the transition sound at the door). No-op while the
     * door is absent or already in {@code state}.
     */
    public static void setGlobalState(ServerLevel limbo, DoorState state) {
        BlockPos pos = controllerPos(limbo);
        if (!(limbo.getBlockEntity(pos) instanceof RespawnDoorBlockEntity door)) {
            EclipseMod.LOGGER.warn("Respawn door state change to {} ignored: no door at {}", state,
                    pos.toShortString());
            return;
        }
        DoorState previous = door.doorState();
        if (previous == state) {
            return;
        }
        door.setDoorState(state);
        if (state == DoorState.OPEN) {
            limbo.playSound(null, pos, SoundEvents.WOODEN_DOOR_OPEN, SoundSource.BLOCKS, 1.2F, 0.5F);
        } else if (previous == DoorState.OPEN) {
            limbo.playSound(null, pos, SoundEvents.IRON_DOOR_CLOSE, SoundSource.BLOCKS, 1.0F, 0.6F);
        }
        EclipseMod.LOGGER.info("Respawn door global state {} -> {}", previous, state);
    }

    /**
     * P3/P4: plays the personal open sequence for ONE revived player — their client
     * alone swings the door wide (hold) with the heavy-door sound; everyone else keeps
     * their own view. Pair with a teleport through {@link #doorFrontPos} and end the
     * moment with {@link #playCloseFor} or {@link #clearCueFor}.
     */
    public static void playOpenFor(ServerPlayer player) {
        sendCue(player, S2CDoorCuePayload.POSE_OPEN);
        player.playNotifySound(SoundEvents.WOODEN_DOOR_OPEN, SoundSource.BLOCKS, 1.2F, 0.5F);
        player.playNotifySound(SoundEvents.RESPAWN_ANCHOR_CHARGE, SoundSource.BLOCKS, 0.8F, 1.1F);
    }

    /** P3/P4: personal close slam (ends a {@link #playOpenFor} sequence). */
    public static void playCloseFor(ServerPlayer player) {
        sendCue(player, S2CDoorCuePayload.POSE_CLOSE);
        player.playNotifySound(SoundEvents.IRON_DOOR_CLOSE, SoundSource.BLOCKS, 1.0F, 0.6F);
    }

    /** P3/P4: silently drops the player's personal pose override (back to global view). */
    public static void clearCueFor(ServerPlayer player) {
        sendCue(player, S2CDoorCuePayload.POSE_CLEAR);
    }

    /** Global "the door refuses" rattle + sound (ghost knocks, denied revives). */
    public static void playLockedShudder(ServerLevel limbo) {
        BlockPos pos = controllerPos(limbo);
        if (limbo.getBlockEntity(pos) instanceof RespawnDoorBlockEntity door) {
            door.triggerAnim(RespawnDoorBlockEntity.CONTROLLER_STATE, RespawnDoorBlockEntity.ANIM_LOCKED_SHUDDER);
            limbo.playSound(null, pos, SoundEvents.IRON_DOOR_CLOSE, SoundSource.BLOCKS, 0.7F, 0.45F);
        }
    }

    private static void sendCue(ServerPlayer player, int pose) {
        ServerLevel limbo = player.getServer().getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            return;
        }
        DoorPayloads.sendCue(player, new S2CDoorCuePayload(controllerPos(limbo), pose));
    }
}
