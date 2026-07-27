package dev.projecteclipse.eclipse.entity.boss.fog;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.stormfx.StormSiege;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.DoubleTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.AttackEntityEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-081 — the TYRANT STATUE: the storm-boss fight now starts when a player STRIKES the
 * statue standing at the storm's heart, never by mere presence. One statue per armed
 * lair ({@link FogBankMarker} delegates here from its watched tick), built from four
 * {@link Display.BlockDisplay} pieces on the tyrant's palette (polished-blackstone
 * plinth, tilted deepslate torso, crying-obsidian head, lightning-rod crown) plus one
 * tagged {@code minecraft:interaction} hitbox — the {@code GravityRiftService}
 * rift-heart hit pattern ({@code AttackEntityEvent} + {@code EntityInteract}, both
 * cancelled, spectators ignored).
 *
 * <p><b>Per-lair state machine:</b> {@code ARMED} (statue stands; idle Photon cue
 * {@code CUE_TYRANT_STATUE_IDLE} + vanilla spark-spiral baseline + one-shot action-bar
 * hint) → {@code AWAKENING} (struck: {@value #AWAKEN_TICKS}t shake / display
 * micro-jitter / rising resonate telegraph, the lair disarms NOW) → {@code FIGHT}
 * (statue burst-discarded, {@link FogTyrantEntity#summonAt} fired — its arrival FX and
 * intro title already exist) → {@code COOLDOWN} (a fight reset re-arms the statue after
 * {@value #REARM_TICKS}t via {@link #onFightReset} — this also closes re-arm gap G-1:
 * abandoned fights re-arm IN-SESSION) → {@code ARMED}. Victory retires the entry
 * outright ({@code FogStormSites.stormEnded} → {@code FogBankMarker.clearLair} →
 * {@link #retireLair}).</p>
 *
 * <p><b>Cleanup doctrine (F-084):</b> every piece + hitbox carries
 * {@link StormSiege#STORM_FX_TAG}, {@value #STATUE_TAG} and a per-lair scope tag
 * ({@link StormSiege#FIGHT_SCOPE_TAG_PREFIX}{@code lair_<x>_<y>_<z>}), and its UUID
 * lives in the session set consulted by {@code StormSiege}'s join sweep
 * ({@link #isLivePiece}) — pieces persisted by a crash are discarded on load and the
 * statue self-heals ({@code ensureArmed} respawns missing pieces, the rift-heart
 * doctrine), pieces unloaded mid-session are re-adopted intact on chunk reload, and
 * {@code /kill @e[tag=eclipse_tyrant_statue]} always works.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class TyrantStatue {
    /** Frozen command tag on every statue display piece AND the interaction hitbox. */
    public static final String STATUE_TAG = "eclipse_tyrant_statue";

    /** Awaken telegraph length (~3 s): hit → shake/jitter/rising chime → summon. */
    private static final int AWAKEN_TICKS = 60;
    /** Cooldown after a fight reset before the statue (and lair) re-arm (30 s). */
    private static final int REARM_TICKS = 600;
    /** Slow-cadence work (orphan sweep, FIGHT backstop) — matches FogBankMarker's tick. */
    private static final int SLOW_CADENCE_TICKS = 40;
    /** Statue-hit → statue entry match radius (hitbox sits ON the lair center). */
    private static final double HIT_MATCH_RANGE = 6.0D;
    /** onFightReset arena-center → statue entry match radius (arena pins AT the lair). */
    private static final double REARM_MATCH_RANGE = 8.0D;
    /** Action-bar hint range for players discovering an armed statue. */
    private static final double HINT_RANGE = 14.0D;
    /** Awaken caption/burst message range. */
    private static final double MESSAGE_RANGE = 32.0D;
    /** Players this close keep the FIGHT backstop honest (chunks surely loaded). */
    private static final double WATCH_RANGE = 64.0D;
    /** Idle-cue broadcast range (matches the tyrant's arena-scale FX range). */
    private static final double IDLE_CUE_RANGE = 64.0D;
    /** Statue display readability inside the dark storm (block light / sky cap). */
    private static final int STATUE_BLOCK_LIGHT = 9;
    private static final int MAX_SKY_LIGHT = 15;
    private static final float VIEW_RANGE = 2.0F;
    /** Interaction hitbox dimensions (covers plinth to crown). */
    private static final float HITBOX_WIDTH = 1.6F;
    private static final float HITBOX_HEIGHT = 3.4F;

    private enum State { ARMED, AWAKENING, FIGHT, COOLDOWN }

    /** One statue piece: palette block + its base pose off the shared mount. */
    private record Piece(BlockState state, Transformation pose) {}

    /**
     * The monarch-in-effigy, bottom to top: plinth, storm-tilted torso, head, crown
     * accent. All pieces mount at ONE fixed entity position (the statue base — the
     * {@code StormDebrisFx} transport law); the poses carry the vertical build.
     */
    private static final Piece[] PIECES = {
            new Piece(Blocks.POLISHED_BLACKSTONE.defaultBlockState(),
                    piecePose(1.25F, 0.0F, 0.0F, 0.0F)),
            new Piece(Blocks.DEEPSLATE.defaultBlockState(),
                    piecePose(0.95F, 1.2F, 7.0F, 0.0F)),
            new Piece(Blocks.CRYING_OBSIDIAN.defaultBlockState(),
                    piecePose(0.65F, 2.25F, 0.0F, 25.0F)),
            new Piece(Blocks.LIGHTNING_ROD.defaultBlockState(),
                    piecePose(0.5F, 2.95F, 0.0F, 45.0F))};

    /** Live statue entries by lair position (session-only; lairs re-derive on boot). */
    private static final Map<GlobalPos, Statue> STATUES = new ConcurrentHashMap<>();
    /** UUIDs of pieces/hitboxes spawned THIS session — the join-sweep adoption set. */
    private static final Set<UUID> LIVE_PIECES = Collections.synchronizedSet(new HashSet<>());

    private TyrantStatue() {}

    // ------------------------------------------------------------------ public seams

    /** Whether {@code id} is a statue piece/hitbox owned by THIS session (join sweep). */
    public static boolean isLivePiece(UUID id) {
        return LIVE_PIECES.contains(id);
    }

    /**
     * The FogBankMarker seam, called on its watched {@value #SLOW_CADENCE_TICKS}t
     * cadence for an armed lair with NO live tyrant nearby: creates the entry, stands /
     * self-heals the statue, stamps the idle dressing (spark spiral + Photon cue — the
     * cadence divides the asset's 200t runtime, so re-sends are seamless dedup no-ops)
     * and hints newcomers. Non-ARMED states tick themselves in {@link #onServerTick}.
     */
    public static void ensureArmed(ServerLevel level, BlockPos lair) {
        Statue statue = STATUES.computeIfAbsent(
                GlobalPos.of(level.dimension(), lair.immutable()), Statue::new);
        if (statue.state != State.ARMED || !level.isLoaded(lair)) {
            return;
        }
        selfHeal(level, statue);
        dressStatue(level, statue);
        hintPlayers(level, statue);
        FxPayloads.sendFxEvent(level, FxCues.CUE_TYRANT_STATUE_IDLE,
                fxCenter(statue), 0.0F, 0.0F, IDLE_CUE_RANGE);
    }

    /**
     * The FogBankMarker seam for a lair with a LIVE tyrant nearby (mid-fight restart
     * resume, or a hand-summoned tyrant beside an armed statue): the entry rides in
     * {@code FIGHT} and any standing statue comes down — never two triggers at once.
     */
    public static void noteFightRunning(ServerLevel level, BlockPos lair) {
        Statue statue = STATUES.computeIfAbsent(
                GlobalPos.of(level.dimension(), lair.immutable()), Statue::new);
        if (statue.state == State.ARMED || statue.state == State.AWAKENING) {
            discardPieces(level, statue);
            statue.state = State.FIGHT;
            EclipseMod.LOGGER.info("TyrantStatue: live tyrant near the lair at {} — statue "
                    + "stands down until the fight resolves", lair.toShortString());
        }
    }

    /**
     * F-082 re-arm hook, called by {@code FogTyrantEntity.resetFight} (wipe AND abandon
     * paths): the statue entry nearest the reset arena goes {@code COOLDOWN} and
     * re-arms (statue + {@code FogBankMarker.markLair}) after {@value #REARM_TICKS}t.
     * No-op for plain-summon fights with no statue entry.
     */
    public static void onFightReset(ServerLevel level, Vec3 arenaCenter) {
        Statue statue = nearestStatue(level, arenaCenter, REARM_MATCH_RANGE, null);
        if (statue == null) {
            return;
        }
        discardPieces(level, statue); // FIGHT holds no pieces; belt for odd states.
        statue.state = State.COOLDOWN;
        statue.timer = REARM_TICKS;
        EclipseMod.LOGGER.info("TyrantStatue: fight reset at {} — statue cooling down, "
                + "re-arms in {}t", statue.lair.pos().toShortString(), REARM_TICKS);
    }

    /**
     * Site retirement (victory {@code stormEnded}, stage rollback, config reload,
     * server stop) — called from {@code FogBankMarker.clearLair}: the entry dies in any
     * state and its pieces discard.
     */
    public static void retireLair(ServerLevel level, BlockPos center) {
        Statue statue = STATUES.remove(GlobalPos.of(level.dimension(), center.immutable()));
        if (statue == null) {
            // Belt: clearLair callers recompute the surface center — match by distance
            // if a future refactor ever drifts it by a block.
            statue = nearestStatue(level, Vec3.atCenterOf(center), 2.0D, null);
            if (statue == null) {
                return;
            }
            STATUES.remove(statue.lair);
        }
        discardPieces(level, statue);
        EclipseMod.LOGGER.info("TyrantStatue: statue at {} retired",
                statue.lair.pos().toShortString());
    }

    // ------------------------------------------------------------------ hit detection

    /** Attack (left click) on the statue hitbox wakes the monarch; cancel = no damage. */
    @SubscribeEvent
    static void onAttackEntity(AttackEntityEvent event) {
        if (event.getEntity() instanceof ServerPlayer player && !player.isSpectator()
                && event.getTarget().getTags().contains(STATUE_TAG)) {
            event.setCanceled(true);
            tryAwaken(player, event.getTarget());
        }
    }

    /** Use (right click) on the statue = same trigger (accessibility, rift-heart law). */
    @SubscribeEvent
    static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getHand() == InteractionHand.MAIN_HAND
                && event.getEntity() instanceof ServerPlayer player && !player.isSpectator()
                && event.getTarget().getTags().contains(STATUE_TAG)) {
            event.setCanceled(true);
            tryAwaken(player, event.getTarget());
        }
    }

    private static void tryAwaken(ServerPlayer player, Entity target) {
        if (!player.isAlive() || !(player.level() instanceof ServerLevel level)) {
            return;
        }
        Statue statue = nearestStatue(level, target.position(), HIT_MATCH_RANGE, State.ARMED);
        if (statue == null) {
            return;
        }
        BlockPos lair = statue.lair.pos();
        boolean tyrantAlready = !level.getEntitiesOfClass(FogTyrantEntity.class,
                new AABB(lair).inflate(FogBankMarker.LIVE_TYRANT_RANGE),
                FogTyrantEntity::isAlive).isEmpty();
        if (tyrantAlready) {
            return; // Never two triggers (FogBankMarker's guard normally prevents this).
        }
        statue.state = State.AWAKENING;
        statue.timer = AWAKEN_TICKS;
        // F-081: the lair disarms at STATUE-HIT time (was: proximity time).
        FogBankMarker.disarmLair(level, lair);
        Vec3 center = fxCenter(statue);
        level.playSound(null, lair, SoundEvents.WARDEN_SONIC_CHARGE,
                SoundSource.HOSTILE, 1.2F, 1.3F);
        level.playSound(null, lair, SoundEvents.AMETHYST_BLOCK_RESONATE,
                SoundSource.HOSTILE, 1.4F, 0.6F);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z,
                48.0D, S2CShakePayload.shake(0.4F, 12));
        messageNear(level, center, "eclipse.storm.statue.awaken");
        EclipseMod.LOGGER.info("TyrantStatue: {} struck the statue at {} — awakening for {}t",
                player.getScoreboardName(), lair.toShortString(), AWAKEN_TICKS);
    }

    // ------------------------------------------------------------------ lifecycle tick

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (STATUES.isEmpty()) {
            return;
        }
        int tickCount = event.getServer().getTickCount();
        for (Statue statue : STATUES.values()) {
            ServerLevel level = event.getServer().getLevel(statue.lair.dimension());
            if (level != null) {
                tickStatue(level, statue, tickCount);
            }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // Session state only: pieces that reached disk are swept by StormSiege's join
        // check next boot (LIVE_PIECES clears here, so they can never be adopted), and
        // reconcileTyrantLair re-marks/re-stands everything on restore.
        STATUES.clear();
        LIVE_PIECES.clear();
    }

    private static void tickStatue(ServerLevel level, Statue statue, int tickCount) {
        switch (statue.state) {
            case ARMED -> {
                if (tickCount % SLOW_CADENCE_TICKS == 0
                        && !FogBankMarker.isLairArmed(level, statue.lair.pos())) {
                    // Lair unmarked underneath a standing statue (site lifecycle churn
                    // without the explicit retire hook) — tear it down.
                    discardPieces(level, statue);
                    STATUES.remove(statue.lair);
                    EclipseMod.LOGGER.info("TyrantStatue: orphaned statue at {} swept "
                            + "(lair no longer armed)", statue.lair.pos().toShortString());
                }
            }
            case AWAKENING -> tickAwakening(level, statue);
            case FIGHT -> {
                // Backstop for resets that never called onFightReset (external discards):
                // once NOTHING tyrant-shaped remains near the lair (a mid-death-cinematic
                // corpse still counts), cool down and re-arm. Watcher-gated so unloaded
                // chunks (entity merely unloaded) can never fake an empty arena.
                if (tickCount % SLOW_CADENCE_TICKS != 0
                        || !anyPlayerWithin(level, fxCenter(statue), WATCH_RANGE)) {
                    return;
                }
                boolean tyrantPresent = !level.getEntitiesOfClass(FogTyrantEntity.class,
                        new AABB(statue.lair.pos()).inflate(FogBankMarker.LIVE_TYRANT_RANGE))
                        .isEmpty();
                if (!tyrantPresent) {
                    statue.state = State.COOLDOWN;
                    statue.timer = REARM_TICKS;
                    EclipseMod.LOGGER.info("TyrantStatue: fight at {} ended without a reset "
                            + "callback — statue cooling down, re-arms in {}t",
                            statue.lair.pos().toShortString(), REARM_TICKS);
                }
            }
            case COOLDOWN -> {
                if (--statue.timer <= 0) {
                    statue.state = State.ARMED;
                    statue.hintedPlayers.clear();
                    // G-1 fix: the lair re-arms IN-SESSION; the statue itself stands on
                    // the next watched ensureArmed pass.
                    FogBankMarker.markLair(level, statue.lair.pos());
                    EclipseMod.LOGGER.info("TyrantStatue: cooldown over — lair at {} re-armed",
                            statue.lair.pos().toShortString());
                }
            }
        }
    }

    /** The ~3 s awaken telegraph: micro-jitter + spark column + rising resonate chime. */
    private static void tickAwakening(ServerLevel level, Statue statue) {
        statue.timer--;
        Vec3 base = statueBase(statue.lair.pos());
        float progress = 1.0F - statue.timer / (float) AWAKEN_TICKS;
        if (statue.timer % 3 == 0) {
            pushJitter(level, statue, 0.02F + progress * 0.1F);
        }
        if (statue.timer % 5 == 0) {
            level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                    base.x, base.y + 1.8D, base.z, 4 + (int) (progress * 8.0F),
                    0.4D, 1.0D, 0.4D, 0.05D);
        }
        if (statue.timer % 10 == 0) {
            level.playSound(null, statue.lair.pos(), SoundEvents.AMETHYST_BLOCK_RESONATE,
                    SoundSource.HOSTILE, 1.3F, 0.6F + progress);
        }
        if (statue.timer <= 0) {
            awaken(level, statue);
        }
    }

    /** The burst beat: statue discards, the monarch rises exactly where it stood. */
    private static void awaken(ServerLevel level, Statue statue) {
        Vec3 center = fxCenter(statue);
        discardPieces(level, statue);
        statue.state = State.FIGHT;
        level.sendParticles(ParticleTypes.CLOUD, center.x, center.y, center.z,
                40, 0.8D, 1.2D, 0.8D, 0.08D);
        level.sendParticles(ParticleTypes.ELECTRIC_SPARK, center.x, center.y, center.z,
                30, 0.6D, 1.4D, 0.6D, 0.15D);
        level.playSound(null, statue.lair.pos(), SoundEvents.LIGHTNING_BOLT_THUNDER,
                SoundSource.HOSTILE, 1.3F, 0.7F);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z,
                48.0D, S2CShakePayload.shake(0.6F, 14));
        FogTyrantEntity.summonAt(level, statue.lair.pos());
        EclipseMod.LOGGER.info("TyrantStatue: statue at {} shattered — the Fog Tyrant answers",
                statue.lair.pos().toShortString());
    }

    // ------------------------------------------------------------------ statue body

    /** Rift-heart self-heal doctrine: missing/killed pieces rebuild the whole statue. */
    private static void selfHeal(ServerLevel level, Statue statue) {
        if (statue.pieceIds.isEmpty()) {
            spawnPieces(level, statue);
            return;
        }
        boolean intact = statue.hitboxId != null && isLiveEntity(level, statue.hitboxId);
        for (int i = 0; intact && i < statue.pieceIds.size(); i++) {
            intact = isLiveEntity(level, statue.pieceIds.get(i));
        }
        if (!intact) {
            discardPieces(level, statue);
            spawnPieces(level, statue);
            EclipseMod.LOGGER.info("TyrantStatue self-heal: rebuilt the statue at {}",
                    statue.lair.pos().toShortString());
        }
    }

    private static boolean isLiveEntity(ServerLevel level, UUID id) {
        Entity entity = level.getEntity(id);
        return entity != null && !entity.isRemoved();
    }

    private static void spawnPieces(ServerLevel level, Statue statue) {
        Vec3 base = statueBase(statue.lair.pos());
        String scopeTag = scopeTag(statue.lair.pos());
        for (Piece piece : PIECES) {
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(level);
            if (display == null) {
                return;
            }
            display.setBlockState(piece.state());
            display.moveTo(base.x, base.y, base.z, 0.0F, 0.0F);
            display.addTag(StormSiege.STORM_FX_TAG);
            display.addTag(STATUE_TAG);
            display.addTag(scopeTag);
            DisplayBrightnessFx.set(display, STATUE_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(piece.pose());
            LIVE_PIECES.add(display.getUUID());
            statue.pieceIds.add(display.getUUID());
            level.addFreshEntity(display);
        }
        spawnHitbox(level, statue, base, scopeTag);
        EclipseMod.LOGGER.info("TyrantStatue: statue stands at {} ({} piece(s) + hitbox)",
                statue.lair.pos().toShortString(), statue.pieceIds.size());
    }

    /**
     * The statue's {@code minecraft:interaction} hitbox — NBT spawn (vanilla has no
     * public width/height setters; the {@code GravityRiftService.spawnHeartInteraction}
     * precedent).
     */
    private static void spawnHitbox(ServerLevel level, Statue statue, Vec3 base, String scopeTag) {
        CompoundTag nbt = new CompoundTag();
        nbt.putString("id", "minecraft:interaction");
        nbt.putFloat("width", HITBOX_WIDTH);
        nbt.putFloat("height", HITBOX_HEIGHT);
        nbt.putBoolean("response", false);
        ListTag pos = new ListTag();
        pos.add(DoubleTag.valueOf(base.x));
        pos.add(DoubleTag.valueOf(base.y));
        pos.add(DoubleTag.valueOf(base.z));
        nbt.put("Pos", pos);
        Entity interaction = EntityType.loadEntityRecursive(nbt, level, entity -> entity);
        if (interaction == null) {
            EclipseMod.LOGGER.error("TyrantStatue: could not create the statue hitbox at {}",
                    statue.lair.pos().toShortString());
            return;
        }
        interaction.addTag(StormSiege.STORM_FX_TAG);
        interaction.addTag(STATUE_TAG);
        interaction.addTag(scopeTag);
        LIVE_PIECES.add(interaction.getUUID());
        statue.hitboxId = interaction.getUUID();
        level.addFreshEntity(interaction);
    }

    private static void discardPieces(ServerLevel level, Statue statue) {
        for (UUID id : statue.pieceIds) {
            discardPiece(level, id);
        }
        statue.pieceIds.clear();
        if (statue.hitboxId != null) {
            discardPiece(level, statue.hitboxId);
            statue.hitboxId = null;
        }
    }

    /** Unloaded pieces just leave the live set — the join sweep reclaims them on load. */
    private static void discardPiece(ServerLevel level, UUID id) {
        LIVE_PIECES.remove(id);
        Entity entity = level.getEntity(id);
        if (entity != null && !entity.isRemoved()) {
            entity.discard();
        }
    }

    // ------------------------------------------------------------------ dressing & hints

    /** Vanilla idle baseline (LAYER law): a slow electric-spark spiral up the column. */
    private static void dressStatue(ServerLevel level, Statue statue) {
        Vec3 base = statueBase(statue.lair.pos());
        double phase = level.getGameTime() * 0.05D;
        for (int i = 0; i < 6; i++) {
            double t = i / 6.0D;
            double angle = phase + t * Math.PI * 2.0D;
            double radius = 0.9D - t * 0.35D;
            level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                    base.x + Math.cos(angle) * radius, base.y + 0.3D + t * 2.8D,
                    base.z + Math.sin(angle) * radius, 1, 0.03D, 0.05D, 0.03D, 0.0D);
        }
        if (level.getRandom().nextInt(3) == 0) {
            level.sendParticles(ParticleTypes.END_ROD,
                    base.x, base.y + 3.1D, base.z, 1, 0.15D, 0.1D, 0.15D, 0.005D);
        }
    }

    /** One action-bar hint per player per armed spell of the statue. */
    private static void hintPlayers(ServerLevel level, Statue statue) {
        Vec3 center = fxCenter(statue);
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && player.position().distanceTo(center) <= HINT_RANGE
                    && statue.hintedPlayers.add(player.getUUID())) {
                player.displayClientMessage(
                        ServerLang.tr(player, "eclipse.storm.statue.hint"), true);
            }
        }
    }

    private static void messageNear(ServerLevel level, Vec3 center, String key) {
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && player.position().distanceTo(center) <= MESSAGE_RANGE) {
                player.displayClientMessage(ServerLang.tr(player, key), true);
            }
        }
    }

    /** Interpolated micro-jitter push on every piece (the awaken "shudder"). */
    private static void pushJitter(ServerLevel level, Statue statue, float amplitude) {
        RandomSource random = level.getRandom();
        for (int i = 0; i < statue.pieceIds.size() && i < PIECES.length; i++) {
            if (!(level.getEntity(statue.pieceIds.get(i)) instanceof Display.BlockDisplay display)
                    || display.isRemoved()) {
                continue;
            }
            Transformation base = PIECES[i].pose();
            Vector3f translation = new Vector3f(base.getTranslation()).add(
                    (random.nextFloat() - 0.5F) * amplitude,
                    0.0F,
                    (random.nextFloat() - 0.5F) * amplitude);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(3);
            display.setTransformation(new Transformation(translation,
                    new Quaternionf(base.getLeftRotation()), new Vector3f(base.getScale()),
                    new Quaternionf(base.getRightRotation())));
        }
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Base pose of one piece: a {@code scale}-sized cube centered on the mount's X/Z at
     * {@code yOffset}, tilted/turned about its own center (translation compensates the
     * corner-anchored block model — the {@code StormSiege.poseFor} recipe).
     */
    private static Transformation piecePose(float scale, float yOffset, float tiltZDeg,
            float yawDeg) {
        Quaternionf rotation = new Quaternionf()
                .rotationY((float) Math.toRadians(yawDeg))
                .rotateZ((float) Math.toRadians(tiltZDeg));
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        Vector3f translation = new Vector3f(0.0F, yOffset + scale * 0.5F, 0.0F)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /** The one fixed mount every piece rides: the block-top center of the lair cell. */
    private static Vec3 statueBase(BlockPos lair) {
        return new Vec3(lair.getX() + 0.5D, lair.getY() + 1.0D, lair.getZ() + 0.5D);
    }

    private static Vec3 fxCenter(Statue statue) {
        return statueBase(statue.lair.pos()).add(0.0D, 1.7D, 0.0D);
    }

    private static String scopeTag(BlockPos lair) {
        return StormSiege.FIGHT_SCOPE_TAG_PREFIX + "lair_"
                + lair.getX() + "_" + lair.getY() + "_" + lair.getZ();
    }

    @Nullable
    private static Statue nearestStatue(ServerLevel level, Vec3 pos, double range,
            @Nullable State wanted) {
        Statue best = null;
        double bestDist = range;
        for (Statue statue : STATUES.values()) {
            if (!statue.lair.dimension().equals(level.dimension())
                    || (wanted != null && statue.state != wanted)) {
                continue;
            }
            double dist = Vec3.atCenterOf(statue.lair.pos()).distanceTo(pos);
            if (dist <= bestDist) {
                bestDist = dist;
                best = statue;
            }
        }
        return best;
    }

    private static boolean anyPlayerWithin(ServerLevel level, Vec3 center, double range) {
        for (ServerPlayer player : level.players()) {
            if (!player.isSpectator() && player.isAlive()
                    && player.position().distanceTo(center) <= range) {
                return true;
            }
        }
        return false;
    }

    /** One per-lair statue entry (session-only). */
    private static final class Statue {
        final GlobalPos lair;
        State state = State.ARMED;
        int timer;
        final List<UUID> pieceIds = new ArrayList<>(PIECES.length);
        @Nullable
        UUID hitboxId;
        final Set<UUID> hintedPlayers = new HashSet<>();

        Statue(GlobalPos lair) {
            this.lair = lair;
        }
    }
}
