package dev.projecteclipse.eclipse.limbo.door;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ClientGamePacketListener;
import net.minecraft.network.protocol.game.ClientboundBlockEntityDataPacket;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import software.bernie.geckolib.animatable.GeoBlockEntity;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.RawAnimation;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Brain of the Respawn Door (plans_v3 §2.5). Lives only on the multiblock's controller
 * cell and carries:
 *
 * <ul>
 *   <li><b>Global {@link DoorState}</b> — server-authoritative, synced to every client
 *       via plain BE data ({@link #getUpdatePacket}); driven exclusively through
 *       {@link RespawnDoorApi#setGlobalState} (P4's lives flow — no lives logic in
 *       here).</li>
 *   <li><b>Pose resolution</b> for the GeckoLib controller ({@value #CONTROLLER_STATE}):
 *       personal cue &gt; ghost-viewer rule &gt; global state. The ghost rule (ghosts
 *       always SEE the door closed) checks the LOCAL viewer only —
 *       {@code client.entity.door.DoorRenderers.viewerSeesClosed()} is referenced
 *       fully-qualified inside client-only code paths so it never loads on a dedicated
 *       server (repo lazy-resolution pattern, {@code FxPayloads}).</li>
 *   <li><b>Personal cues</b> ({@link #applyClientCue}) — client-local pose overrides fed
 *       by {@link S2CDoorCuePayload} so P3/P4 can play a walk-through open for ONE
 *       player while everyone else keeps the global pose.</li>
 *   <li><b>{@link #getGlowStrength()}</b> — the 0..1 animated purple-spill strength for
 *       P2's Veil light hook (§4.2): seam-breathing while closed, blazing while open,
 *       near-dead while sealed.</li>
 * </ul>
 *
 * <p>Animations ({@code animations/block/respawn_door.animation.json}): looped
 * {@code closed_idle} (seam pulse), {@code open} (hold on last frame), {@code close}
 * (slam, then back to idle), triggerable {@code locked_shudder} (a ghost rattles the
 * handles — {@code triggerAnim(CONTROLLER_STATE, ANIM_LOCKED_SHUDDER)}).</p>
 */
public class RespawnDoorBlockEntity extends BlockEntity implements GeoBlockEntity {
    /** Geo/anim/texture triple id: {@code geo/block/respawn_door.geo.json} etc. */
    public static final String GEO_ID = "respawn_door";
    /** The single animation controller (pose state machine + triggerable shudder). */
    public static final String CONTROLLER_STATE = "state";
    /** Triggerable one-shot: the door strains against its lock (ghost feedback). */
    public static final String ANIM_LOCKED_SHUDDER = "locked_shudder";

    private static final String TAG_DOOR_STATE = "door_state";

    private static final RawAnimation CLOSED_IDLE = EclipseGeoAnimations.loop(GEO_ID, "closed_idle");
    private static final RawAnimation OPEN_HOLD = EclipseGeoAnimations.hold(GEO_ID, "open");
    private static final RawAnimation CLOSE_THEN_IDLE = RawAnimation.begin()
            .thenPlay(EclipseGeoAnimations.animId(GEO_ID, "close"))
            .thenLoop(EclipseGeoAnimations.animId(GEO_ID, "closed_idle"));
    private static final RawAnimation SHUDDER = EclipseGeoAnimations.once(GEO_ID, ANIM_LOCKED_SHUDDER);

    private final AnimatableInstanceCache cache = GeckoLibUtil.createInstanceCache(this);

    /** Global door state (server-authoritative; clients hold the last synced value). */
    private DoorState doorState = DoorState.CLOSED;

    // --- client-only transients (personal cue + stable pose-animation identity) ---
    @Nullable private DoorState clientCuePose;
    @Nullable private DoorState clientLastPose;
    @Nullable private RawAnimation clientPoseAnim;

    public RespawnDoorBlockEntity(BlockPos pos, BlockState state) {
        super(DoorRegistry.RESPAWN_DOOR_BE.get(), pos, state);
    }

    /** Current global state (both sides; the client value is the last synced one). */
    public DoorState doorState() {
        return this.doorState;
    }

    /**
     * Server: swaps the global state, syncs BE data and mirrors {@code LIT} onto all 15
     * multiblock cells (block light only dies while SEALED). Call through
     * {@link RespawnDoorApi#setGlobalState}.
     */
    public void setDoorState(DoorState state) {
        if (this.level == null || this.level.isClientSide || this.doorState == state) {
            return;
        }
        this.doorState = state;
        setChanged();
        BlockState blockState = getBlockState();
        this.level.sendBlockUpdated(this.worldPosition, blockState, blockState, Block.UPDATE_ALL);
        boolean lit = state != DoorState.SEALED;
        if (blockState.hasProperty(RespawnDoorBlock.LIT) && blockState.getValue(RespawnDoorBlock.LIT) != lit) {
            this.level.setBlock(this.worldPosition, blockState.setValue(RespawnDoorBlock.LIT, lit), Block.UPDATE_ALL);
            RespawnDoorBlock.placeFillers(this.level, this.worldPosition,
                    blockState.getValue(RespawnDoorBlock.FACING), lit);
        }
    }

    /**
     * Client: applies a personal pose cue ({@link S2CDoorCuePayload} handler).
     * {@code POSE_OPEN}/{@code POSE_CLOSE} override this viewer's pose until
     * {@code POSE_CLEAR}; {@code POSE_SHUDDER} is a one-shot on top of the current pose.
     */
    public void applyClientCue(int pose) {
        switch (pose) {
            case S2CDoorCuePayload.POSE_OPEN -> this.clientCuePose = DoorState.OPEN;
            case S2CDoorCuePayload.POSE_CLOSE -> this.clientCuePose = DoorState.CLOSED;
            case S2CDoorCuePayload.POSE_SHUDDER -> triggerAnim(CONTROLLER_STATE, ANIM_LOCKED_SHUDDER);
            default -> this.clientCuePose = null; // POSE_CLEAR
        }
    }

    /**
     * Client: the {@link RawAnimation} for this viewer's CURRENT pose, resolving
     * personal cue &gt; ghost rule &gt; global state. Returns identity-stable instances
     * so the animation controller only restarts on real pose flips; a flip away from
     * OPEN routes through the {@code close} slam before settling into the idle loop.
     */
    public RawAnimation clientPoseAnimation() {
        DoorState pose = this.doorState;
        if (pose == DoorState.OPEN
                && dev.projecteclipse.eclipse.client.entity.door.DoorRenderers.viewerSeesClosed()) {
            pose = DoorState.CLOSED; // ghosts never see it open (client-only rule)
        }
        if (this.clientCuePose != null) {
            pose = this.clientCuePose; // explicit server cue outranks the passive rule
        }
        if (pose != this.clientLastPose) {
            boolean fromOpen = this.clientLastPose == DoorState.OPEN;
            this.clientPoseAnim = pose == DoorState.OPEN ? OPEN_HOLD : (fromOpen ? CLOSE_THEN_IDLE : CLOSED_IDLE);
            this.clientLastPose = pose;
        }
        return this.clientPoseAnim == null ? CLOSED_IDLE : this.clientPoseAnim;
    }

    /**
     * Animated 0..1 strength of the purple light spill for P2's Veil area-light hook
     * (§4.2): 0.12 sealed, breathing 0.3..0.8 closed, 1.0 open. Client calls see the
     * viewer-effective pose (cue/ghost rule applied); server calls see the global one.
     */
    public float getGlowStrength() {
        DoorState pose = this.doorState;
        if (this.level != null && this.level.isClientSide) {
            if (pose == DoorState.OPEN
                    && dev.projecteclipse.eclipse.client.entity.door.DoorRenderers.viewerSeesClosed()) {
                pose = DoorState.CLOSED;
            }
            if (this.clientCuePose != null) {
                pose = this.clientCuePose;
            }
        }
        long time = this.level != null ? this.level.getGameTime() : 0L;
        return switch (pose) {
            case SEALED -> 0.12F;
            case OPEN -> 1.0F;
            case CLOSED -> 0.55F + 0.25F * (float) Math.sin(time * 0.08D);
        };
    }

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        // The handler only ever runs on the render side; the client rule class inside
        // clientPoseAnimation() resolves lazily and never loads on a dedicated server.
        controllers.add(new AnimationController<>(this, CONTROLLER_STATE, 4,
                state -> state.setAndContinue(clientPoseAnimation()))
                .triggerableAnim(ANIM_LOCKED_SHUDDER, SHUDDER));
    }

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return this.cache;
    }

    // --- persistence + sync (plain BE data — no custom payload for the global state) ---

    @Override
    protected void saveAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.saveAdditional(tag, registries);
        tag.putInt(TAG_DOOR_STATE, this.doorState.id());
    }

    @Override
    protected void loadAdditional(CompoundTag tag, HolderLookup.Provider registries) {
        super.loadAdditional(tag, registries);
        this.doorState = DoorState.byId(tag.getInt(TAG_DOOR_STATE));
    }

    @Override
    public CompoundTag getUpdateTag(HolderLookup.Provider registries) {
        return saveWithoutMetadata(registries);
    }

    @Override
    public Packet<ClientGamePacketListener> getUpdatePacket() {
        return ClientboundBlockEntityDataPacket.create(this);
    }
}
