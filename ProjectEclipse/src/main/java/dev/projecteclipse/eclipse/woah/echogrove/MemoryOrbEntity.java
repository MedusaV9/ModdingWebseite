package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.HashMap;
import java.util.Map;

import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-05 memory orb (plan §3.6) — the interactable lights of the grove. Two
 * families share the class via {@link #DATA_KIND}:
 *
 * <ul>
 *   <li><b>0–4 "lost memories"</b> hidden at the five scene sites (§7.1): right-click
 *       collects — implosion cue, one {@code eclipse:memory_mote}, whisper caption,
 *       persisted in {@code EchoGroveState.collectedOrb} (never respawns except via
 *       {@code /dev woah echo reset}), then {@code discard()}.</li>
 *   <li><b>10–14 tree orbs</b> floating at the memory tree: right-click whispers the
 *       lore fragment {@code echo.eclipse.memory.<n>} (caption only to the clicker)
 *       and replays the matching scene once next to the player; right-click WITH a
 *       memory mote deposits it ({@code DATA_LIT}, chime cadence, finale at 5).</li>
 * </ul>
 *
 * <p>Chassis: {@code Mob} like {@code LogoutGhostEntity} (no-AI/no-physics/
 * invulnerable) rather than a bare {@code Entity} — Mob brings the interact
 * plumbing and the attribute boilerplate is two lines. Orbs DO persist
 * ({@link #shouldBeSaved()} default true + {@code setPersistenceRequired}):
 * {@code EchoGroveState.orbUuids} lets repair/reset find them again.</p>
 */
public class MemoryOrbEntity extends Mob {
    public static final String ENTITY_ID = "memory_orb";

    /** 0–4 lost-memory orbs, 10–14 tree orbs (fragment = kind − 10). */
    public static final EntityDataAccessor<Integer> DATA_KIND =
            SynchedEntityData.defineId(MemoryOrbEntity.class, EntityDataSerializers.INT);
    /** Tree orbs glow warmer once "their" fragment has been deposited. */
    public static final EntityDataAccessor<Boolean> DATA_LIT =
            SynchedEntityData.defineId(MemoryOrbEntity.class, EntityDataSerializers.BOOLEAN);

    private static final String TAG_KIND = "EchoKind";
    private static final String TAG_LIT = "EchoLit";

    /** Whisper rate limit: 3 s per orb (the LogoutGhostService rate-limit technique). */
    private static final long WHISPER_COOLDOWN_TICKS = 60L;
    private static final Map<Integer, Long> LAST_USE_BY_ENTITY_ID = new HashMap<>();

    public MemoryOrbEntity(EntityType<? extends MemoryOrbEntity> type, Level level) {
        super(type, level);
        this.setNoAi(true);
        this.noPhysics = true;
        this.setNoGravity(true);
        this.setInvulnerable(true);
        this.setSilent(true);
        this.setPersistenceRequired();
    }

    public static AttributeSupplier.Builder createAttributes() {
        return Mob.createMobAttributes().add(Attributes.MAX_HEALTH, 1.0D);
    }

    @Override
    protected void registerGoals() {
        // Motionless — the pulse lives in the renderer + Photon glow.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        return false;
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_KIND, 0);
        builder.define(DATA_LIT, false);
    }

    @Override
    public void addAdditionalSaveData(net.minecraft.nbt.CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        tag.putInt(TAG_KIND, kind());
        tag.putBoolean(TAG_LIT, isLit());
    }

    @Override
    public void readAdditionalSaveData(net.minecraft.nbt.CompoundTag tag) {
        super.readAdditionalSaveData(tag);
        setKind(tag.getInt(TAG_KIND));
        setLit(tag.getBoolean(TAG_LIT));
    }

    public int kind() {
        return this.entityData.get(DATA_KIND);
    }

    public void setKind(int kind) {
        this.entityData.set(DATA_KIND, kind);
    }

    public boolean isLit() {
        return this.entityData.get(DATA_LIT);
    }

    public void setLit(boolean lit) {
        this.entityData.set(DATA_LIT, lit);
    }

    public boolean isTreeOrb() {
        return kind() >= 10;
    }

    /** Scene index 0–4 behind this orb (both families map onto the five scenes). */
    public int sceneIndex() {
        return isTreeOrb() ? kind() - 10 : kind();
    }

    // ------------------------------------------------------------------ interaction

    @Override
    public InteractionResult mobInteract(Player player, InteractionHand hand) {
        if (this.level().isClientSide() || !(player instanceof ServerPlayer serverPlayer)
                || !(this.level() instanceof ServerLevel level)) {
            return InteractionResult.CONSUME;
        }
        if (hand != InteractionHand.MAIN_HAND) {
            return InteractionResult.PASS;
        }
        if (isTreeOrb()) {
            ItemStack held = player.getItemInHand(hand);
            if (held.is(EchoGroveItems.MEMORY_MOTE.get())) {
                deposit(level, serverPlayer, held);
                return InteractionResult.CONSUME;
            }
            whisper(level, serverPlayer);
            return InteractionResult.CONSUME;
        }
        collect(level, serverPlayer);
        return InteractionResult.CONSUME;
    }

    /** Tree orb without a mote: lore whisper + one amplified scene replay (plan §3.6 no. 1–3). */
    private void whisper(ServerLevel level, ServerPlayer player) {
        long now = level.getGameTime();
        Long last = LAST_USE_BY_ENTITY_ID.get(this.getId());
        if (last != null && now - last < WHISPER_COOLDOWN_TICKS) {
            return;
        }
        LAST_USE_BY_ENTITY_ID.put(this.getId(), now);
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                "echo.eclipse.memory." + sceneIndex(), 120, S2CCaptionPayload.STYLE_WHISPER));
        // Deliberately warm, not scary: one shot, low, slow — no scare ramps (plan §6.4).
        level.playSound(null, this.getX(), this.getY(), this.getZ(),
                EclipseSounds.AMBIENT_GAZER_WHISPER.get(), SoundSource.AMBIENT, 0.35F, 0.7F);
        FxPayloads.sendFxEntityEvent(level, EchoGroveCues.CUE_ECHO_WHISPER, this, 0.0F, 0.0F, 48.0D);
        EchoSceneService.playOnce(level, EchoScenes.sceneIdFor(sceneIndex()), player, 0.6F);
    }

    /** Lost orb: collect into a memory mote (plan §3.6 "Verlorene-Erinnerung"). */
    private void collect(ServerLevel level, ServerPlayer player) {
        EchoGroveState state = EchoGroveState.get(level.getServer());
        FxPayloads.sendFxEvent(level, EchoGroveCues.CUE_ECHO_ORB_COLLECT, this.position(),
                0.0F, 0.0F, 48.0D);
        level.playSound(null, this.getX(), this.getY(), this.getZ(),
                EclipseSounds.AMBIENT_GAZER_WHISPER.get(), SoundSource.AMBIENT, 0.3F, 0.85F);
        ItemStack mote = new ItemStack(EchoGroveItems.MEMORY_MOTE.get());
        if (!player.getInventory().add(mote)) {
            player.drop(mote, false);
        }
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                "echo.eclipse.memory.collected", 100, S2CCaptionPayload.STYLE_WHISPER));
        state.collectOrb(kind());
        EchoGrovePayloads.syncAll(level.getServer());
        this.discard();
    }

    /** Deposit a mote at any tree orb (plan §3.6 "Abgabe"). */
    private void deposit(ServerLevel level, ServerPlayer player, ItemStack held) {
        EchoGroveState state = EchoGroveState.get(level.getServer());
        if (state.deposited() >= 5) {
            whisper(level, player); // quest done — orbs stay endlessly listenable
            return;
        }
        held.shrink(1);
        setLit(true);
        int deposited = state.deposit();
        MemoryFloodService.playDepositChime(level, this.position(), deposited);
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                "echo.eclipse.memory.deposited", 80, S2CCaptionPayload.STYLE_WHISPER));
        EchoGrovePayloads.syncAll(level.getServer());
        if (deposited >= 5) {
            EchoFinaleSequence.start(level, player);
        }
    }
}
