package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.List;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-045 Portal-Formation — the finale-day spectacle: EVERY accumulated day-rift orbit
 * display answers one long multi-stage call ({@value #NORMAL_DURATION_TICKS}t ≈ 75 s;
 * the dev command runs the same math at {@value #FAST_DURATION_TICKS}t):
 *
 * <ol>
 *   <li><b>Sync</b> (0–{@value #SYNC_END_FRACTION}): the free orbits glide into ONE
 *       synchronized ring, STRATIFIED into three sediment tiers by frozen piece scale
 *       (heavy low + wide, light high + tight; shared rate, even spacing).</li>
 *   <li><b>Spiral</b> (–{@value #GATHER_END_FRACTION}): the ring corkscrews across the
 *       sky — radius tightening, rate rising — to a gather point over the water off the
 *       island shore ({@link FinaleState#portalPos()}, chosen deterministically once and
 *       persisted), quantized mid-flight onto {@value #STRAND_COUNT} braided comet
 *       streams.</li>
 *   <li><b>Build</b> (–1.0): piece by piece (golden-hash stagger, inner depth layers
 *       first, crown keystones last) the debris flies from the gather swirl onto its
 *       slot on the gate silhouette — four-layer arch outline,
 *       ~{@value #ARCH_HEIGHT_BLOCKS} blocks tall — and locks in, yaw-aligned with the
 *       door plane.</li>
 * </ol>
 *
 * <p>At the end the debris flashes away and the REAL {@link PortalGateEntity} (GeckoLib
 * arch, pulsing {@code portal_soul_veil} interior) stands in its place; the
 * {@link PortalKeyEntity} materializes hovering over the altar and the arc advances to
 * {@link FinaleState#STAGE_PORTAL_READY}.</p>
 *
 * <p><b>Restart law</b>: {@code STAGE_FORMING} never resumes mid-animation — a boot in
 * that stage calls {@link #completeInstantly} (gate + key stand, swarm swept). From
 * {@code STAGE_PORTAL_READY}/{@code STAGE_DONE} the tick loop re-ensures the gate (and,
 * before the crossing, the key) once the portal chunk's entity section is actually
 * loaded — persisted entities are adopted, never doubled (the SanctumOrbitals
 * load-race lesson).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PortalFormation {
    /** Normal formation length (task band 60–90 s). */
    public static final int NORMAL_DURATION_TICKS = 1500;
    /** Dev fast-forward length ({@code /dev start_ferryman} — task spec 15 s). */
    public static final int FAST_DURATION_TICKS = 300;
    /** Stage boundaries (fractions of the duration). */
    public static final double SYNC_END_FRACTION = 0.32D;
    public static final double GATHER_END_FRACTION = 0.62D;

    /** Synced-ring geometry (stage 1 target) — the MID tier of the stratified ring. */
    private static final double SYNC_RADIUS = 38.0D;
    private static final double SYNC_HEIGHT_ABOVE_TOP = 42.0D;
    private static final double SYNC_DEG_PER_TICK = 0.3D;
    /**
     * FX-Wave-12 stratified sync ring. Stage 1 no longer flattens the whole swarm onto
     * ONE plane at {@value #SYNC_HEIGHT_ABOVE_TOP}: the piece's frozen
     * {@link DayRiftOrbits#scaleOf} decides which of three sediment TIERS it syncs into —
     * heavy slabs settle low and wide, light shards ride high and tight, so the "ring"
     * reads as a stratified cone of sorted debris instead of a flat hoop. Pure retarget
     * math: the same displays, the same cadence, zero extra entities or packets.
     */
    private static final double[] SYNC_TIER_HEIGHT = {34.0D, SYNC_HEIGHT_ABOVE_TOP, 52.0D};
    private static final double[] SYNC_TIER_RADIUS = {
            SYNC_RADIUS + 6.0D, SYNC_RADIUS, SYNC_RADIUS - 6.0D};
    /** Tier cuts on the DayRiftOrbits scale band (0.7–1.7, keystones 2.6). */
    private static final float SYNC_TIER_HEAVY_SCALE = 1.35F;
    private static final float SYNC_TIER_MID_SCALE = 1.0F;

    /**
     * FX-Wave-12 braided spiral. Stage 2 quantizes every piece onto one of
     * {@value #STRAND_COUNT} co-rotating strand lanes ({@code i % 3}) with a trailing
     * comet tail behind each lane head, plus a radial/vertical weave that laces the three
     * streams around each other. Both the quantization and the weave ride a
     * {@code sin(pi q)} bump, so the stage still STARTS exactly on the stage-1 ring pose
     * and still ENDS exactly on the old evenly-spread gather swirl — the braid lives
     * entirely in the middle of the corkscrew, where the eye is actually watching.
     */
    private static final int STRAND_COUNT = 3;
    /**
     * How hard the lanes pull (1 = a piece is dragged all the way onto its lane bearing).
     * Held under 1 on purpose: a full pull can be half a revolution of extra travel on a
     * 38-block ring, which would push a 10-tick push window past the arc its linear tween
     * can still draw as a curve. See the class doc's cadence law.
     */
    private static final double STRAND_QUANTIZE = 0.6D;
    /**
     * How far back along the spiral the tail of a strand trails (fraction of stage 2).
     *
     * <p>The single most expensive knob in this stage, so it is deliberately modest. A
     * trailing piece rides a LAGGED spiral phase, so while the tail retracts it must
     * advance faster than the stage does, and the corkscrew term is quadratic — the
     * catch-up buys extra arc exactly where the whip is already fastest. Measured on
     * the 1500t path, the worst-case gap between a push pair's linear tween and the
     * true curve grows about 0.6 blocks per 0.1 of span.
     */
    private static final double STRAND_TAIL_SPAN = 0.15D;
    /** Extra angular lag of a strand's tail at full extension (radians). */
    private static final double STRAND_TAIL_ARC = 1.0D;
    /** Radial + vertical weave of the three strands around each other (blocks). */
    private static final double BRAID_AMPLITUDE = 3.5D;
    private static final double BRAID_TURNS = 2.0D;
    /** Radius the gather swirl closes to at the end of stage 2. */
    private static final double GATHER_RADIUS = 2.5D;

    /** Portal-site scan band off the altar (stays inside the display culling envelope). */
    private static final int PORTAL_MIN_DIST = 40;
    private static final int PORTAL_MAX_DIST = 64;
    /** Gate silhouette the debris assembles (matches the geo model's ~12.5-block arch). */
    private static final double ARCH_HEIGHT_BLOCKS = 13.0D;
    private static final double ARCH_HALF_WIDTH = 4.5D;
    /** Gather swirl over the gate site (stage 2 target). */
    private static final double GATHER_ABOVE_GATE = 20.0D;

    /**
     * FX-Wave-12 four-layer arch. The silhouette is built from FOUR depth layers instead
     * of two, so the finished jamb reads as a ~3-block-deep masonry wall rather than a
     * cardboard outline. The two inner layers lock first (the core wall stands, then the
     * facing plates onto it), and keystone-sized pieces are pinned to the crown and lock
     * dead last — the arch closes on its keystone, the way an arch actually closes.
     */
    private static final double[] ARCH_LAYER_Z = {-1.4D, -0.5D, 0.5D, 1.4D};
    /**
     * Pieces at or above this frozen scale are keystones: crown arc only, locking last.
     *
     * <p>Keyed off {@link DayRiftOrbits#KEYSTONE_SCALE} (2.6, ~1 index in 12) rather than
     * the flat 1.1 the FX-Wave-12 recipe named. The swarm's ordinary size band is
     * 0.7–1.7, so a 1.1 cut is not a rarity test at all — it selects about 64 % of the
     * swarm, which would pile two thirds of the gate onto the crown arc and leave the
     * jambs bare. The recipe wanted the RARE heavy slabs, and this system already has a
     * name for those.
     */
    private static final float KEYSTONE_SCALE = DayRiftOrbits.KEYSTONE_SCALE - 0.1F;
    /** Build-stage lock stagger budget — jitter + depth + keystone must stay ≤ 0.7. */
    private static final double LOCK_JITTER_SPAN = 0.42D;
    private static final double LOCK_DEPTH_DELAY = 0.14D;
    private static final double LOCK_KEYSTONE_DELAY = 0.14D;
    /** Length of one piece's own dive, as a fraction of the build stage. */
    private static final double LOCK_WINDOW = 0.3D;

    /** Keyframe push spacing during the formation (finer than the idle 40t orbits). */
    private static final int PUSH_SPACING_TICKS = 10;
    /** Key hover height over the altar crown. */
    public static final double KEY_HOVER_ABOVE_ALTAR = 4.0D;

    /** Entity re-ensure cadence while PORTAL_READY/DONE (until the one-shot succeeds). */
    private static final int ENSURE_CADENCE_TICKS = 100;

    private static boolean active;
    private static boolean autoKey;
    private static int ticks;
    private static int duration = NORMAL_DURATION_TICKS;
    private static boolean entitiesEnsured;

    private PortalFormation() {}

    // ------------------------------------------------------------------ public surface

    /**
     * Starts the formation. {@code fast} runs the dev 15 s cut; {@code autoKey} chains
     * straight into the key sequence when the gate stands ({@code /dev start_ferryman}).
     * Dev calls on a young world (empty sky) first seed a test swarm so there is
     * something to form. Returns whether the formation (or, for an already-standing
     * gate with {@code autoKey}, the key sequence) actually started.
     */
    public static boolean begin(MinecraftServer server, boolean fast, boolean autoKeySequence) {
        FinaleState state = FinaleState.get(server);
        if (state.stage() == FinaleState.STAGE_PORTAL_READY && autoKeySequence) {
            return FinaleSequence.startAuto(server); // gate already stands — skip ahead
        }
        if (active || state.stage() != FinaleState.STAGE_ORBITS) {
            EclipseMod.LOGGER.info("PortalFormation.begin ignored (active={}, stage={})",
                    active, state.stage());
            return false;
        }
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null) {
            EclipseMod.LOGGER.warn("PortalFormation.begin aborted: no sanctum altar");
            return false;
        }
        if (state.orbitCount() <= 0) {
            if (!fast) {
                return false; // nothing accumulated and nothing to fake — no show
            }
            state.setOrbitCount(120); // dev fast path: seed a test swarm on the spot
            DayRiftOrbits.invalidate();
        }
        DayRiftOrbits.reconcileNow(overworld);
        if (state.portalPos() == null) {
            state.setPortalPos(choosePortalPos(overworld, altarPos, state.orbitSeed()));
        }
        state.setStage(FinaleState.STAGE_FORMING);
        active = true;
        autoKey = autoKeySequence;
        ticks = 0;
        duration = fast ? FAST_DURATION_TICKS : NORMAL_DURATION_TICKS;
        Vec3 sky = DayRiftOrbits.riftPoint(altarPos);
        overworld.playSound(null, BlockPos.containing(sky), SoundEvents.END_PORTAL_SPAWN,
                SoundSource.AMBIENT, 1.5F, 0.4F);
        overworld.playSound(null, altarPos, EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                SoundSource.AMBIENT, 1.3F, 0.6F);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.caption.finale.formation", 100, S2CCaptionPayload.STYLE_TITLE));
        }
        EclipseMod.LOGGER.info("Portal formation started: {} piece(s), {}t ({}), gate site {}",
                state.orbitCount(), duration, fast ? "FAST" : "normal",
                state.portalPos().toShortString());
        return true;
    }

    /**
     * Boot path (restart law): the formation never resumes mid-animation — sweep the
     * swarm, stand the gate, hang the key, advance to {@code STAGE_PORTAL_READY}.
     */
    public static void completeInstantly(MinecraftServer server) {
        FinaleState state = FinaleState.get(server);
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null) {
            return;
        }
        if (state.portalPos() == null) {
            state.setPortalPos(choosePortalPos(overworld, altarPos, state.orbitSeed()));
        }
        active = false;
        DayRiftOrbits.discardAll(overworld);
        state.setOrbitCount(0);
        state.setStage(FinaleState.STAGE_PORTAL_READY);
        entitiesEnsured = false; // the gated ensure pass will stand gate + key
        EclipseMod.LOGGER.info("Portal formation completed instantly (boot/offline day-14): gate site {}",
                state.portalPos().toShortString());
    }

    /** The standing gate near the persisted site, or {@code null} (loaded entities only). */
    @Nullable
    public static PortalGateEntity findGate(ServerLevel overworld, FinaleState state) {
        BlockPos pos = state.portalPos();
        if (pos == null || !FinaleEntities.PORTAL_GATE.isBound()) {
            return null;
        }
        List<PortalGateEntity> gates = overworld.getEntities(FinaleEntities.PORTAL_GATE.get(),
                new AABB(pos).inflate(12.0D), Entity::isAlive);
        return gates.isEmpty() ? null : gates.get(0);
    }

    /** The waiting key over the altar, or {@code null} (loaded entities only). */
    @Nullable
    public static PortalKeyEntity findKey(ServerLevel overworld, BlockPos altarPos) {
        if (!FinaleEntities.PORTAL_KEY.isBound()) {
            return null;
        }
        List<PortalKeyEntity> keys = overworld.getEntities(FinaleEntities.PORTAL_KEY.get(),
                new AABB(altarPos).inflate(10.0D, 12.0D, 10.0D), Entity::isAlive);
        return keys.isEmpty() ? null : keys.get(0);
    }

    /** Gate yaw: the door plane faces the altar (the approach from the island). */
    public static float gateYaw(BlockPos portalPos, BlockPos altarPos) {
        double dx = altarPos.getX() - portalPos.getX();
        double dz = altarPos.getZ() - portalPos.getZ();
        return (float) (Mth.atan2(dz, dx) * Mth.RAD_TO_DEG) - 90.0F;
    }

    // ------------------------------------------------------------------ tick driver

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        FinaleState state = FinaleState.get(server);
        if (active) {
            tickFormation(server, state);
            return;
        }
        if (state.stage() >= FinaleState.STAGE_PORTAL_READY && !entitiesEnsured
                && server.getTickCount() % ENSURE_CADENCE_TICKS == 0) {
            ensureEntities(server, state);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        active = false;
        autoKey = false;
        ticks = 0;
        entitiesEnsured = false;
    }

    private static void tickFormation(MinecraftServer server, FinaleState state) {
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        BlockPos portalPos = state.portalPos();
        if (altarPos == null || portalPos == null) {
            EclipseMod.LOGGER.warn("Portal formation dropped: altar/portal anchor vanished");
            completeInstantly(server);
            return;
        }
        ticks++;
        double p = ticks / (double) duration;
        if (ticks % PUSH_SPACING_TICKS == 0) {
            pushFormationKeyframes(overworld, state, altarPos, portalPos,
                    Math.min(1.0D, (ticks + PUSH_SPACING_TICKS) / (double) duration));
        }
        // Escalation beats: a swelling quake as the spiral tightens, glassy chimes as
        // pieces lock onto the arch.
        Vec3 gate = gateCenter(portalPos);
        if (ticks % 60 == 0) {
            float strength = (float) (0.2D + 0.5D * p);
            PacketDistributor.sendToPlayersNear(overworld, null, gate.x, gate.y, gate.z, 160.0D,
                    S2CShakePayload.shake(strength, 24));
        }
        if (p > SYNC_END_FRACTION && p - PUSH_SPACING_TICKS / (double) duration <= SYNC_END_FRACTION) {
            overworld.playSound(null, BlockPos.containing(gate), EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                    SoundSource.AMBIENT, 1.5F, 0.7F);
        }
        if (p > GATHER_END_FRACTION && ticks % 15 == 0) {
            overworld.playSound(null, BlockPos.containing(gate), SoundEvents.AMETHYST_BLOCK_PLACE,
                    SoundSource.AMBIENT, 1.1F, 0.6F + (float) (p * 0.5D));
        }
        if (ticks >= duration) {
            finish(server, state, overworld, altarPos, portalPos);
        }
    }

    /** One interpolated push per live piece, targeting formation progress {@code p}. */
    private static void pushFormationKeyframes(ServerLevel overworld, FinaleState state,
            BlockPos altarPos, BlockPos portalPos, double p) {
        Display.BlockDisplay[] pieces = DayRiftOrbits.liveDisplays();
        if (pieces == null) {
            return;
        }
        long seed = state.orbitSeed();
        long gameTime = overworld.getGameTime();
        Vec3 mount = new Vec3(altarPos.getX() + 0.5D,
                FloatingSanctumBuilder.islandTopY(altarPos) + 45, altarPos.getZ() + 0.5D);
        int count = pieces.length;
        float yaw = gateYaw(portalPos, altarPos);
        for (int i = 0; i < count; i++) {
            Display.BlockDisplay display = pieces[i];
            if (display == null || display.isRemoved()) {
                continue;
            }
            Vec3 point = formationPoint(seed, i, count, altarPos, portalPos, gameTime, p);
            float scale = Math.min(DayRiftOrbits.scaleOf(seed, i), 1.15F);
            // Residual tumble unwinds as the arch locks (aligned blocks read as masonry).
            double lockBlend = buildBlend(seed, i, p);
            float spin = (float) ((1.0D - lockBlend) * (i * 0.7D + gameTime * 0.01D));
            Quaternionf rotation = new Quaternionf()
                    .rotationY((float) Math.toRadians(-yaw))
                    .mul(new Quaternionf().rotationAxis(spin,
                            new Vector3f(0.3F, 1.0F, 0.2F).normalize()));
            Vector3f translation = new Vector3f(
                    (float) (point.x - mount.x), (float) (point.y - mount.y), (float) (point.z - mount.z));
            Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(PUSH_SPACING_TICKS);
            display.setTransformation(new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf()));
        }
    }

    /** World-space target of piece {@code i} at formation progress {@code p}. */
    private static Vec3 formationPoint(long seed, int i, int count, BlockPos altarPos,
            BlockPos portalPos, long gameTime, double p) {
        Vec3 free = DayRiftOrbits.orbitPointAt(seed, i, altarPos, gameTime);
        double ringAngle = (i / (double) count) * Math.PI * 2.0D
                + Math.toRadians(SYNC_DEG_PER_TICK) * gameTime;
        double islandTop = FloatingSanctumBuilder.islandTopY(altarPos);
        Vec3 islandCenter = new Vec3(altarPos.getX() + 0.5D, 0.0D, altarPos.getZ() + 0.5D);
        Vec3 gate = gateCenter(portalPos);
        Vec3 gather = gate.add(0.0D, GATHER_ABOVE_GATE, 0.0D);
        int tier = tierOf(DayRiftOrbits.scaleOf(seed, i));
        double tierHeight = SYNC_TIER_HEIGHT[tier];
        double tierRadius = SYNC_TIER_RADIUS[tier];

        // Stage 1 — sync: free orbit → this piece's TIER of the stratified ring
        // (componentwise, wrap-free). Heavy = low + wide, light = high + tight.
        double sync = smoothstep(p / SYNC_END_FRACTION);
        Vec3 ring = new Vec3(
                islandCenter.x + Math.cos(ringAngle) * tierRadius,
                islandTop + tierHeight,
                islandCenter.z + Math.sin(ringAngle) * tierRadius);
        Vec3 pos = lerp(free, ring, sync);
        if (p <= SYNC_END_FRACTION) {
            return pos;
        }

        // Stage 2 — braided spiral: the tiered ring quantizes onto three co-rotating
        // strand lanes, each dragging a comet tail, and the three streams weave around
        // each other on the way to the gather point over the water. `weave` is a
        // sin(pi q) bump, so q = 0 reproduces the stage-1 ring pose exactly and q = 1
        // reproduces the old evenly-spread gather swirl exactly.
        double q = smoothstep((p - SYNC_END_FRACTION) / (GATHER_END_FRACTION - SYNC_END_FRACTION));
        double weave = Math.sin(Math.PI * q);
        double lanePhase = Math.floorMod(i, STRAND_COUNT) * (Math.PI * 2.0D / STRAND_COUNT);
        // 0 = the head of this lane's comet, 1 = the last piece of its tail.
        double tail = strandRank(i, count) * STRAND_TAIL_SPAN * weave;
        double qEff = Math.max(0.0D, q - tail);
        double laneAngle = lanePhase + Math.toRadians(SYNC_DEG_PER_TICK) * gameTime;
        double spiralAngle = ringAngle
                + wrapRadians(laneAngle - ringAngle) * weave * STRAND_QUANTIZE
                // The corkscrew rides qEff, not q: a piece lagging in its comet tail is
                // genuinely EARLIER in the spiral, so it must also whip slower. Driving
                // it off q instead would spin the tail at full rate while it still sits
                // out at ring radius — twice the arc per push window, for nothing.
                + qEff * qEff * Math.PI * 4.0D
                - tail * STRAND_TAIL_ARC;
        double braid = BRAID_AMPLITUDE * weave;
        double braidPhase = qEff * Math.PI * BRAID_TURNS + lanePhase;
        double spiralRadius = tierRadius * (1.0D - qEff) + GATHER_RADIUS * qEff
                + Math.sin(braidPhase) * braid;
        Vec3 spiralCenter = lerp(new Vec3(islandCenter.x, islandTop + tierHeight,
                islandCenter.z), gather, qEff);
        pos = new Vec3(
                spiralCenter.x + Math.cos(spiralAngle) * spiralRadius,
                spiralCenter.y + Math.cos(braidPhase) * braid,
                spiralCenter.z + Math.sin(spiralAngle) * spiralRadius);
        if (p <= GATHER_END_FRACTION) {
            return pos;
        }

        // Stage 3 — build: staggered dives from the gather swirl onto the arch slots.
        double lock = buildBlend(seed, i, p);
        Vec3 slot = archSlot(seed, i, count, portalPos, altarPos);
        return lerp(pos, slot, lock);
    }

    /** Which sediment tier of the stage-1 ring a frozen piece scale belongs to. */
    private static int tierOf(float scale) {
        if (scale >= SYNC_TIER_HEAVY_SCALE) {
            return 0; // heavy slab — the low, wide tier
        }
        return scale >= SYNC_TIER_MID_SCALE ? 1 : 2;
    }

    /** 0 (lane head) .. 1 (lane tail): how far back piece {@code i} rides its strand. */
    private static double strandRank(int i, int count) {
        int laneSize = Math.max(1, (count + STRAND_COUNT - 1) / STRAND_COUNT);
        return Math.min(1.0D, (i / STRAND_COUNT) / (double) laneSize);
    }

    /** Shortest signed angular delta, so the lane quantization never takes the long way. */
    private static double wrapRadians(double radians) {
        double wrapped = radians % (Math.PI * 2.0D);
        if (wrapped >= Math.PI) {
            wrapped -= Math.PI * 2.0D;
        } else if (wrapped < -Math.PI) {
            wrapped += Math.PI * 2.0D;
        }
        return wrapped;
    }

    /**
     * 0..1 lock-in of piece {@code i} during the build stage. FX-Wave-12 layers a
     * DEPTH stagger and a KEYSTONE delay on top of the golden-hash jitter: the two inner
     * depth layers lock before the two outer facing layers, and keystone pieces (which
     * live on the crown) lock dead last, so the arch visibly closes on its crown.
     */
    private static double buildBlend(long seed, int i, double p) {
        if (p <= GATHER_END_FRACTION) {
            return 0.0D;
        }
        double r = (p - GATHER_END_FRACTION) / (1.0D - GATHER_END_FRACTION);
        double start = LOCK_JITTER_SPAN * hash01(seed, i)
                + (isOuterLayer(i) ? LOCK_DEPTH_DELAY : 0.0D)
                + (isKeystone(seed, i) ? LOCK_KEYSTONE_DELAY : 0.0D);
        return smoothstep((r - start) / LOCK_WINDOW);
    }

    /** True for the two facing layers (|z| > 1) — they plate onto the locked core. */
    private static boolean isOuterLayer(int i) {
        return Math.abs(ARCH_LAYER_Z[Math.floorMod(i, ARCH_LAYER_Z.length)]) > 1.0D;
    }

    private static boolean isKeystone(long seed, int i) {
        return DayRiftOrbits.scaleOf(seed, i) >= KEYSTONE_SCALE;
    }

    /**
     * Slot of piece {@code i} on the gate silhouette: FOUR jittered depth layers tracing
     * the arch outline (up the left jamb, over the crown, down the right jamb), in world
     * space through the gate yaw. Keystone-sized pieces skip the perimeter walk and are
     * distributed across the crown arc on a golden-ratio sequence, so the lintel is
     * always the heaviest masonry on the gate.
     */
    private static Vec3 archSlot(long seed, int i, int count, BlockPos portalPos,
            BlockPos altarPos) {
        float yaw = gateYaw(portalPos, altarPos);
        double u;
        if (isKeystone(seed, i)) {
            u = 0.35D + 0.30D * goldenFraction(i);
        } else {
            u = count <= 1 ? 0.0D : i / (double) count;
        }
        int layer = Math.floorMod(i, ARCH_LAYER_Z.length);
        // Perimeter parameterization: 0..0.35 left jamb up, 0.35..0.65 crown arc,
        // 0.65..1.0 right jamb down.
        double lx;
        double ly;
        if (u < 0.35D) {
            double t = u / 0.35D;
            lx = -ARCH_HALF_WIDTH;
            ly = t * (ARCH_HEIGHT_BLOCKS - 3.0D);
        } else if (u < 0.65D) {
            double t = (u - 0.35D) / 0.30D; // 0..1 across the crown
            double arc = Math.PI * (1.0D - t); // π..0 — left top to right top
            lx = Math.cos(arc) * ARCH_HALF_WIDTH;
            ly = (ARCH_HEIGHT_BLOCKS - 3.0D) + Math.sin(arc) * 3.0D;
        } else {
            double t = (u - 0.65D) / 0.35D;
            lx = ARCH_HALF_WIDTH;
            ly = (1.0D - t) * (ARCH_HEIGHT_BLOCKS - 3.0D);
        }
        double lz = ARCH_LAYER_Z[layer];
        // Deterministic jitter so the debris reads as rough masonry, not beads.
        RandomSource jitter = RandomSource.create(hashLong(0x517A_F045L + i * 7919L));
        lx += (jitter.nextDouble() - 0.5D) * 1.2D;
        ly += (jitter.nextDouble() - 0.5D) * 1.0D;
        lz += (jitter.nextDouble() - 0.5D) * 0.6D;
        // Rotate the local (lx, ly, lz) door-plane frame into the world by the yaw:
        // local +X spans the door width, local +Z its normal.
        double rad = Math.toRadians(-yaw);
        double wx = lx * Math.cos(rad) - lz * Math.sin(rad);
        double wz = lx * Math.sin(rad) + lz * Math.cos(rad);
        return new Vec3(portalPos.getX() + 0.5D + wx, portalPos.getY() + ly,
                portalPos.getZ() + 0.5D + wz);
    }

    private static void finish(MinecraftServer server, FinaleState state,
            ServerLevel overworld, BlockPos altarPos, BlockPos portalPos) {
        active = false;
        Vec3 gate = gateCenter(portalPos);
        DayRiftOrbits.discardAll(overworld);
        state.setOrbitCount(0);
        spawnGate(overworld, state, altarPos, portalPos);
        spawnKey(overworld, altarPos);
        state.setStage(FinaleState.STAGE_PORTAL_READY);
        entitiesEnsured = true; // freshly spawned this very tick
        overworld.playSound(null, BlockPos.containing(gate), SoundEvents.END_PORTAL_SPAWN,
                SoundSource.AMBIENT, 1.6F, 0.5F);
        overworld.playSound(null, BlockPos.containing(gate), EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                SoundSource.AMBIENT, 1.5F, 0.5F);
        PacketDistributor.sendToPlayersNear(overworld, null, gate.x, gate.y, gate.z, 160.0D,
                S2CShakePayload.shake(1.0F, 40));
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.caption.finale.gate", 100, S2CCaptionPayload.STYLE_SUBTITLE));
        }
        EclipseMod.LOGGER.info("Portal formation complete: gate stands at {}, key hovers over the altar{}",
                portalPos.toShortString(), autoKey ? " — auto key sequence chained" : "");
        if (autoKey) {
            autoKey = false;
            FinaleSequence.startAuto(server);
        }
    }

    // ------------------------------------------------------------------ entities

    private static void spawnGate(ServerLevel overworld, FinaleState state,
            BlockPos altarPos, BlockPos portalPos) {
        if (!FinaleEntities.PORTAL_GATE.isBound()) {
            EclipseMod.LOGGER.warn("PortalFormation: FinaleEntities not wired — gate skipped");
            return;
        }
        if (findGate(overworld, state) != null) {
            return;
        }
        PortalGateEntity gate = FinaleEntities.PORTAL_GATE.get().create(overworld);
        if (gate == null) {
            return;
        }
        gate.moveTo(portalPos.getX() + 0.5D, portalPos.getY(), portalPos.getZ() + 0.5D,
                gateYaw(portalPos, altarPos), 0.0F);
        gate.setYBodyRot(gate.getYRot());
        gate.setYHeadRot(gate.getYRot());
        overworld.addFreshEntity(gate);
    }

    private static void spawnKey(ServerLevel overworld, BlockPos altarPos) {
        if (!FinaleEntities.PORTAL_KEY.isBound() || findKey(overworld, altarPos) != null) {
            return;
        }
        PortalKeyEntity key = FinaleEntities.PORTAL_KEY.get().create(overworld);
        if (key == null) {
            return;
        }
        key.moveTo(altarPos.getX() + 0.5D, altarPos.getY() + KEY_HOVER_ABOVE_ALTAR,
                altarPos.getZ() + 0.5D, 0.0F, 0.0F);
        overworld.addFreshEntity(key);
        overworld.playSound(null, altarPos, SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.AMBIENT, 1.4F, 0.6F);
    }

    /**
     * PORTAL_READY/DONE boot recovery: once the portal/altar chunks' entity sections are
     * loaded, adopt the persisted gate (and key while the crossing is still ahead),
     * discard duplicates, respawn whatever is missing. One-shot per boot.
     */
    private static void ensureEntities(MinecraftServer server, FinaleState state) {
        if (!FinaleEntities.PORTAL_GATE.isBound()) {
            return;
        }
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        BlockPos portalPos = state.portalPos();
        if (altarPos == null || portalPos == null) {
            entitiesEnsured = true; // nothing to anchor on — do not retry forever
            return;
        }
        if (!overworld.isLoaded(portalPos)
                || !overworld.areEntitiesLoaded(ChunkPos.asLong(portalPos))
                || !overworld.isLoaded(altarPos)
                || !overworld.areEntitiesLoaded(ChunkPos.asLong(altarPos))) {
            return; // retry at the next cadence — adoption needs the persisted entities
        }
        entitiesEnsured = true;
        List<PortalGateEntity> gates = overworld.getEntities(FinaleEntities.PORTAL_GATE.get(),
                new AABB(portalPos).inflate(12.0D), Entity::isAlive);
        for (int i = 1; i < gates.size(); i++) {
            gates.get(i).discard(); // dupes from an old crash — one gate stands
        }
        if (gates.isEmpty()) {
            spawnGate(overworld, state, altarPos, portalPos);
            EclipseMod.LOGGER.info("PortalFormation: standing gate respawned at {} (boot recovery)",
                    portalPos.toShortString());
        }
        List<PortalKeyEntity> keys = overworld.getEntities(FinaleEntities.PORTAL_KEY.get(),
                new AABB(altarPos).inflate(10.0D, 12.0D, 10.0D), Entity::isAlive);
        if (state.stage() == FinaleState.STAGE_PORTAL_READY) {
            for (int i = 1; i < keys.size(); i++) {
                keys.get(i).discard();
            }
            if (keys.isEmpty()) {
                spawnKey(overworld, altarPos);
                EclipseMod.LOGGER.info("PortalFormation: altar key respawned (boot recovery)");
            }
        } else {
            keys.forEach(Entity::discard); // DONE: a consumed key never returns
        }
    }

    // ------------------------------------------------------------------ site + math

    /**
     * Deterministic gate site: walk golden-angle rays off the altar until a column of
     * open water at sea level is found inside the {@value #PORTAL_MIN_DIST}–{@value
     * #PORTAL_MAX_DIST} band ("ein Punkt über dem Wasser nahe der Insel"); the gate's
     * feet stand on the waterline. Fallback: due east at {@value #PORTAL_MAX_DIST}.
     */
    private static BlockPos choosePortalPos(ServerLevel overworld, BlockPos altarPos, long seed) {
        double baseAngle = (seed & 0xFFFF) / 65536.0D * Math.PI * 2.0D;
        for (int step = 0; step < 24; step++) {
            double angle = baseAngle + step * 2.39996322972865332D;
            for (int dist = PORTAL_MIN_DIST; dist <= PORTAL_MAX_DIST; dist += 6) {
                int x = altarPos.getX() + (int) Math.round(Math.cos(angle) * dist);
                int z = altarPos.getZ() + (int) Math.round(Math.sin(angle) * dist);
                int surfaceY = overworld.getHeight(
                        net.minecraft.world.level.levelgen.Heightmap.Types.MOTION_BLOCKING, x, z);
                BlockPos below = new BlockPos(x, surfaceY - 1, z);
                if (overworld.getBlockState(below).is(Blocks.WATER)) {
                    return new BlockPos(x, surfaceY, z);
                }
            }
        }
        int fallbackY = overworld.getSeaLevel();
        return new BlockPos(altarPos.getX() + PORTAL_MAX_DIST, fallbackY, altarPos.getZ());
    }

    private static Vec3 gateCenter(BlockPos portalPos) {
        return new Vec3(portalPos.getX() + 0.5D, portalPos.getY() + ARCH_HEIGHT_BLOCKS * 0.5D,
                portalPos.getZ() + 0.5D);
    }

    private static Vec3 lerp(Vec3 a, Vec3 b, double t) {
        return new Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
    }

    private static double smoothstep(double x) {
        x = Math.max(0.0D, Math.min(1.0D, x));
        return x * x * (3.0D - 2.0D * x);
    }

    /** Low-discrepancy 0..1 sequence — an even spread over any index subsequence. */
    private static double goldenFraction(int i) {
        double x = i * 0.6180339887498949D;
        return x - Math.floor(x);
    }

    private static double hash01(long seed, int i) {
        return (hashLong(seed ^ (i * 0x9E3779B97F4A7C15L)) >>> 11) / (double) (1L << 53);
    }

    private static long hashLong(long h) {
        h ^= h >>> 33;
        h *= 0xFF51AFD7ED558CCDL;
        h ^= h >>> 33;
        return h;
    }
}
