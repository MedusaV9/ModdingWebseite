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
 *       synchronized ring (shared radius/height/rate, even spacing).</li>
 *   <li><b>Spiral</b> (–{@value #GATHER_END_FRACTION}): the ring corkscrews across the
 *       sky — radius tightening, rate rising — to a gather point over the water off the
 *       island shore ({@link FinaleState#portalPos()}, chosen deterministically once and
 *       persisted).</li>
 *   <li><b>Build</b> (–1.0): piece by piece (golden-hash stagger) the debris flies from
 *       the gather swirl onto its slot on the gate silhouette — two-layer arch outline,
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

    /** Synced-ring geometry (stage 1 target). */
    private static final double SYNC_RADIUS = 38.0D;
    private static final double SYNC_HEIGHT_ABOVE_TOP = 42.0D;
    private static final double SYNC_DEG_PER_TICK = 0.3D;

    /** Portal-site scan band off the altar (stays inside the display culling envelope). */
    private static final int PORTAL_MIN_DIST = 40;
    private static final int PORTAL_MAX_DIST = 64;
    /** Gate silhouette the debris assembles (matches the geo model's ~12.5-block arch). */
    private static final double ARCH_HEIGHT_BLOCKS = 13.0D;
    private static final double ARCH_HALF_WIDTH = 4.5D;
    /** Gather swirl over the gate site (stage 2 target). */
    private static final double GATHER_ABOVE_GATE = 20.0D;

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

        // Stage 1 — sync: free orbit → shared ring (componentwise, wrap-free).
        double sync = smoothstep(p / SYNC_END_FRACTION);
        Vec3 ring = new Vec3(
                islandCenter.x + Math.cos(ringAngle) * SYNC_RADIUS,
                islandTop + SYNC_HEIGHT_ABOVE_TOP,
                islandCenter.z + Math.sin(ringAngle) * SYNC_RADIUS);
        Vec3 pos = lerp(free, ring, sync);
        if (p <= SYNC_END_FRACTION) {
            return pos;
        }

        // Stage 2 — spiral: the ring corkscrews to the gather point over the water.
        double q = smoothstep((p - SYNC_END_FRACTION) / (GATHER_END_FRACTION - SYNC_END_FRACTION));
        double spiralRadius = SYNC_RADIUS * (1.0D - q) + 2.5D * q;
        double spiralAngle = ringAngle + q * q * Math.PI * 4.0D;
        Vec3 spiralCenter = lerp(new Vec3(islandCenter.x, islandTop + SYNC_HEIGHT_ABOVE_TOP,
                islandCenter.z), gather, q);
        pos = new Vec3(
                spiralCenter.x + Math.cos(spiralAngle) * spiralRadius,
                spiralCenter.y,
                spiralCenter.z + Math.sin(spiralAngle) * spiralRadius);
        if (p <= GATHER_END_FRACTION) {
            return pos;
        }

        // Stage 3 — build: staggered dives from the gather swirl onto the arch slots.
        double lock = buildBlend(seed, i, p);
        Vec3 slot = archSlot(i, count, portalPos, altarPos);
        return lerp(pos, slot, lock);
    }

    /** 0..1 lock-in of piece {@code i} during the build stage (golden-hash stagger). */
    private static double buildBlend(long seed, int i, double p) {
        if (p <= GATHER_END_FRACTION) {
            return 0.0D;
        }
        double r = (p - GATHER_END_FRACTION) / (1.0D - GATHER_END_FRACTION);
        double start = 0.7D * hash01(seed, i);
        return smoothstep((r - start) / 0.3D);
    }

    /**
     * Slot of piece {@code i} on the gate silhouette: two jittered layers tracing the
     * arch outline (up the left jamb, over the crown, down the right jamb), in world
     * space through the gate yaw.
     */
    private static Vec3 archSlot(int i, int count, BlockPos portalPos, BlockPos altarPos) {
        float yaw = gateYaw(portalPos, altarPos);
        double u = count <= 1 ? 0.0D : i / (double) count;
        int layer = i % 2; // two depth layers so 350 pieces read as a massive jamb
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
        double lz = (layer == 0 ? -0.8D : 0.8D);
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
