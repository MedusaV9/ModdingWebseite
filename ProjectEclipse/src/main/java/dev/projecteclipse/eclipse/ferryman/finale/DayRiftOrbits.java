package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.ritual.FinaleRitual;
import dev.projecteclipse.eclipse.sequence.endarrival.EndArrivalFxCues;
import dev.projecteclipse.eclipse.wand.WandTickService;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-044 Tagesriss — the accumulating day-rift debris swarm over the center island.
 *
 * <p><b>The beat</b>: at every event-day rollover ({@link EclipseSignals#onDayRollover},
 * POST phase) a NEW Photon rift opens in the sky over the island
 * ({@link FxCues#CUE_DAY_RIFT_MAW} — lazier/darker/violet-pulsing than the structure
 * rift, ~560t) and {@value #FIRST_DAY_COUNT}/+{@value #DAILY_MIN}–{@value #DAILY_MAX}
 * dark block-displays (obsidian,
 * sculk, deepslate, violet accents) fall out of it and swing into slow orbits around
 * the island (heights {@value #HEIGHT_MIN}–{@value #HEIGHT_MAX} over the island top,
 * radii {@value #RADIUS_MIN}–{@value #RADIUS_MAX}), accumulating day over day up to the
 * hard cap of {@value #CAP}.</p>
 *
 * <p><b>Persistence law (the task's own words)</b>: the ENTITIES are never the truth —
 * only {@link FinaleState#orbitCount()} + {@link FinaleState#orbitSeed()} persist, and
 * every parameter of piece {@code i} (radius, height, phase, speed, block, scale,
 * tumble) is a pure function of {@code (seed, i)}. Boot/reconcile
 * ({@code SanctumOrbitals} adopt/dedupe/top-up law, identity tag
 * {@code eclipse_finale_orbit_<i>}) adopts one persisted display per index, discards
 * strays/duplicates/out-of-cap orphans and respawns whatever is missing — the tag sweep
 * covers {@code /kill}ed or hand-copied displays too.</p>
 *
 * <p><b>Transport</b> (SanctumOrbitals): all displays mount at ONE fixed open-air point
 * over the island top (one always-loaded spawn chunk owns the whole swarm; open-sky
 * light sample) — the orbit offset lives entirely in the transformation translation.
 * One interpolated pose push per display per {@value #UPDATE_CADENCE_TICKS}t, absolute
 * in game time (stateless; a paused swarm glides back on track), and ZERO packets while
 * no player is within {@value #PLAYER_GATE_RANGE} blocks. Because radii reach
 * {@value #RADIUS_MAX} (≫ the vanilla 64-block display draw distance and the 4-block
 * culling fallback box), every spawn stamps {@code view_range}/{@code width}/{@code
 * height} through the {@link DisplayBrightnessFx} NBT seam so the swarm neither pops
 * out at distance nor frustum-culls when the mount anchor is off-screen.</p>
 *
 * <p><b>Handoff</b>: on the finale day ({@code FinaleRitual.FINALE_DAY}) the rollover
 * hands the whole swarm to {@link PortalFormation} instead of dropping another beat;
 * from {@code STAGE_FORMING} on, this class stops animating (the formation owns the
 * displays) and any leftovers after {@code STAGE_PORTAL_READY} are swept.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DayRiftOrbits {
    /** Frozen command tag marking every day-rift orbit display (scans/cleanup). */
    public static final String TAG = "eclipse_finale_orbit";

    /**
     * Hard performance cap on the accumulated swarm. F-102 "Rift-Masse": raised from
     * the original task-spec ~350 — cost stays one always-loaded mount chunk and one
     * interpolated pose push per display per {@value #UPDATE_CADENCE_TICKS}t (player
     * gated), so it scales linearly and ~11 packets/tick averaged is still trivial.
     */
    public static final int CAP = 450;
    /** Day-1 drop (F-102: was the task-spec ~20 — the opening beat must already read
     *  as a swarm pouring out of the widened maw, not a sprinkle). */
    public static final int FIRST_DAY_COUNT = 30;
    /** Daily drop band from day 2 on (F-102 raised from the task-spec 15–30). */
    public static final int DAILY_MIN = 22;
    public static final int DAILY_MAX = 42;

    /** Orbit band over the island top (task spec 30–60). */
    public static final int HEIGHT_MIN = 30;
    public static final int HEIGHT_MAX = 60;
    /** Orbit radius band (task spec 25–70). */
    public static final int RADIUS_MIN = 25;
    public static final int RADIUS_MAX = 70;

    /** Transform push cadence == interpolation duration (the SanctumOrbitals 40t law). */
    public static final int UPDATE_CADENCE_TICKS = 40;
    /** Full reconcile sweep cadence (adopt/dedupe/top-up) while a player is near. */
    private static final int RECONCILE_CADENCE_TICKS = 600;
    /** Animation pauses (zero packets, zero scans) with no player within this range. */
    private static final double PLAYER_GATE_RANGE = 160.0D;

    /** Slow orbit band: 1–2.4°/s (~2.5–6 min per revolution — "langsamer Orbit"). */
    private static final double ORBIT_DEG_PER_TICK_MIN = 0.05D;
    private static final double ORBIT_DEG_PER_TICK_MAX = 0.12D;
    /** Vertical bob amplitude; period stays over the ~90° window-flattening floor. */
    private static final double BOB_AMPLITUDE = 0.8D;
    private static final double BOB_BASE_PERIOD_TICKS = 160.0D;
    /** Per-piece tumble rate band (deg/tick). */
    private static final double SPIN_DEG_PER_TICK_MIN = 0.05D;
    private static final double SPIN_DEG_PER_TICK_MAX = 0.16D;
    private static final float SCALE_MIN = 0.7F;
    private static final float SCALE_MAX = 1.7F;
    /** Rare heavy slab (FX-Wave-11): ~1 index in {@value #KEYSTONE_EVERY} is a keystone. */
    public static final float KEYSTONE_SCALE = 2.6F;
    private static final int KEYSTONE_EVERY = 12;
    /** Scatter around the size-derived band so the sorting reads as sediment, not stairs. */
    private static final double HEIGHT_JITTER = 3.0D;
    private static final double SPEED_JITTER = 0.01D;

    /** Rift maw height over the island top; drops blend into orbit over ~30 s. */
    public static final int RIFT_ABOVE_TOP = 72;
    private static final int DROP_BLEND_TICKS = 560;
    /** Per-piece drop stagger inside one beat (the maw "rains" for ~25 s). */
    private static final int DROP_STAGGER_TOTAL_TICKS = 500;
    /**
     * F-102: drop birth annulus across the v3 maw's widened mouth (matches the asset's
     * 1.5–5.5-block drip ring), so the fallout visibly pours out of the WHOLE mouth
     * instead of one center point. Deterministic per piece — no new state.
     */
    private static final double SPILL_R_MIN = 1.5D;
    private static final double SPILL_R_MAX = 5.5D;

    /**
     * FX-12 rollover pressure: the {@code world_grade} violet lean the maw opens under
     * (the {@code EndArrivalFxCues} tint lane — beat-agnostic) and its scheduled release.
     */
    private static final float RIFT_TINT = 0.3F;
    private static final float RIFT_TINT_RAMP = 25.0F;
    private static final int RIFT_TINT_HOLD_TICKS = 30;
    private static final float RIFT_TINT_RELEASE = 80.0F;

    /** Mount height over the island top (open sky; mid-orbit-band anchor). */
    private static final int MOUNT_ABOVE_TOP = 45;
    /** view_range × 64 blocks draw distance (the swarm spans ±70 around the mount). */
    private static final float DISPLAY_VIEW_RANGE = 4.0F;
    /** Culling-box halves (NBT width/height) covering the whole translation envelope. */
    private static final float CULL_WIDTH = 2.0F * (RADIUS_MAX + 4);
    private static final float CULL_HEIGHT = RIFT_ABOVE_TOP + MOUNT_ABOVE_TOP + 16;

    /** Dark-palette debris blocks (violet accents ~1 in 5, deterministic per index). */
    private static final BlockState[] PALETTE = {
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.SCULK.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.POLISHED_DEEPSLATE.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.SCULK.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.CRYING_OBSIDIAN.defaultBlockState(), // violet accent
            Blocks.AMETHYST_BLOCK.defaultBlockState()   // violet accent
    };

    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();

    /** Cached live displays by index; {@code null} until the first reconcile. */
    @Nullable
    private static Display.BlockDisplay[] displays;
    private static boolean reconciled;
    /** Post-formation leftover sweep ran this boot (belt-and-braces orphan guard). */
    private static boolean sweptAfterFormation;
    /** Transient per-index drop birth game time (live beat only; lost on restart — fine). */
    private static final Map<Integer, Long> DROP_BIRTH_TICKS = new HashMap<>();

    private DayRiftOrbits() {}

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover(DayRiftOrbits::onDayRollover);
        }
        MinecraftServer server = event.getServer();
        FinaleState state = FinaleState.get(server);
        if (state.stage() == FinaleState.STAGE_FORMING) {
            // Restart law: never resume mid-animation — the boot finishes it instantly.
            PortalFormation.completeInstantly(server);
            return;
        }
        if (state.stage() != FinaleState.STAGE_ORBITS) {
            return; // PORTAL_READY/DONE: PortalFormation.ensure* re-checks the entities.
        }
        int day = DayScheduler.getDay(server);
        if (day >= FinaleRitual.FINALE_DAY && state.orbitCount() > 0) {
            // The finale day dawned while the server was down — the formation's
            // spectacle cannot be replayed for nobody; finish it instantly.
            PortalFormation.completeInstantly(server);
        } else if (day >= 1 && day > state.lastRiftDay()) {
            // Catch-up: an offline rollover still accumulates exactly one beat.
            riftBeat(server, day);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        displays = null;
        reconciled = false;
        sweptAfterFormation = false;
        DROP_BIRTH_TICKS.clear();
    }

    private static void onDayRollover(MinecraftServer server, int endedDay, int newDay,
            EclipseSignals.DayRolloverPhase phase) {
        if (phase != EclipseSignals.DayRolloverPhase.POST) {
            return;
        }
        FinaleState state = FinaleState.get(server);
        if (state.stage() != FinaleState.STAGE_ORBITS) {
            return;
        }
        if (newDay >= FinaleRitual.FINALE_DAY && state.orbitCount() > 0) {
            // F-045: the last dawn — every orbit piece answers the formation call.
            PortalFormation.begin(server, false, false);
        } else if (newDay >= 1) {
            riftBeat(server, newDay);
        }
    }

    // ------------------------------------------------------------------ the daily beat

    /** One rift beat for {@code day}: maw FX + a staggered drop of new orbit pieces. */
    private static void riftBeat(MinecraftServer server, int day) {
        FinaleState state = FinaleState.get(server);
        if (day <= state.lastRiftDay()) {
            return; // dedup: rollover + boot catch-up can both fire on one boot
        }
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null) {
            return; // no sanctum yet — the sky has nothing to circle
        }
        state.setLastRiftDay(day);
        int before = state.orbitCount();
        if (before >= CAP) {
            return; // hard cap: the sky is full, the beat stays silent
        }
        int add = day <= 1 ? FIRST_DAY_COUNT
                : DAILY_MIN + RandomSource.create(state.orbitSeed() ^ (long) day * 8121L)
                        .nextInt(DAILY_MAX - DAILY_MIN + 1);
        int after = Math.min(CAP, before + add);
        state.setOrbitCount(after);

        Vec3 rift = riftPoint(altarPos);
        long gameTime = overworld.getGameTime();
        int added = after - before;
        for (int i = before; i < after; i++) {
            // Staggered births: the maw "rains" pieces across most of its ~30 s life.
            DROP_BIRTH_TICKS.put(i, gameTime + 20L
                    + (long) ((i - before) * (DROP_STAGGER_TOTAL_TICKS / (double) Math.max(1, added))));
        }
        FxPayloads.sendFxEvent(overworld, FxCues.CUE_DAY_RIFT_MAW, rift, 0.0F, 0.0F, 256.0D);
        overworld.playSound(null, BlockPos.containing(rift), EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                SoundSource.AMBIENT, 1.4F, 0.55F);
        PacketDistributor.sendToPlayersNear(overworld, null, rift.x, rift.y, rift.z, 192.0D,
                new S2CCaptionPayload("eclipse.caption.finale.rift", 80, S2CCaptionPayload.STYLE_WHISPER));
        // FX-12: the rollover gets PRESSURE — a violet sky lean over the maw and one soft
        // ground shove at the caption's own 192-block radius. The tint lane is a HOLD, so
        // the release is scheduled (sending it in the same tick would cancel the ramp).
        FxPayloads.sendFxEvent(overworld, EndArrivalFxCues.CUE_TINT, rift,
                RIFT_TINT, RIFT_TINT_RAMP, 256.0D);
        WandTickService.schedule(overworld, RIFT_TINT_HOLD_TICKS,
                () -> FxPayloads.sendFxEvent(overworld, EndArrivalFxCues.CUE_TINT, rift,
                        0.0F, RIFT_TINT_RELEASE, 256.0D));
        PacketDistributor.sendToPlayersNear(overworld, null, rift.x, rift.y, rift.z, 192.0D,
                S2CShakePayload.shake(0.3F, 18));
        reconciled = false; // next gated pass adopts + spawns the new indices
        EclipseMod.LOGGER.info("Day rift beat (day {}): +{} orbit display(s), swarm {} / cap {}",
                day, added, after, CAP);
    }

    // ------------------------------------------------------------------ tick loop

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % UPDATE_CADENCE_TICKS != 0) {
            return;
        }
        FinaleState state = FinaleState.get(server);
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null) {
            return;
        }
        if (state.stage() >= FinaleState.STAGE_PORTAL_READY) {
            sweepLeftoversOnce(overworld, altarPos);
            return;
        }
        if (state.stage() != FinaleState.STAGE_ORBITS) {
            return; // STAGE_FORMING: PortalFormation owns every pose push
        }
        if (state.orbitCount() <= 0 || !playerNear(overworld, altarPos)) {
            return;
        }
        long gameTime = overworld.getGameTime();
        if (!reconciled || gameTime % RECONCILE_CADENCE_TICKS < UPDATE_CADENCE_TICKS) {
            reconcile(overworld, altarPos, state, false);
        }
        animate(overworld, altarPos, state, gameTime);
    }

    private static boolean playerNear(ServerLevel overworld, BlockPos altarPos) {
        double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
        for (ServerPlayer player : overworld.players()) {
            if (!player.isSpectator() && player.distanceToSqr(
                    altarPos.getX() + 0.5D, altarPos.getY(), altarPos.getZ() + 0.5D) <= rangeSq) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ reconcile

    /**
     * Adopt/dedupe/top-up against the persisted count (SanctumOrbitals law): one display
     * per index via the identity tag, strays/dupes/indices ≥ count discarded, missing
     * indices respawned deterministically from the seed. The first pass of a boot waits
     * for the altar chunk's entity section so persisted displays are adopted, not doubled.
     */
    private static void reconcile(ServerLevel overworld, BlockPos altarPos,
            FinaleState state, boolean force) {
        if (!overworld.isLoaded(altarPos)
                || !overworld.areEntitiesLoaded(ChunkPos.asLong(altarPos))) {
            return;
        }
        int count = Math.min(CAP, state.orbitCount());
        Display.BlockDisplay[] resolved = new Display.BlockDisplay[count];
        int adopted = 0;
        int discarded = 0;
        for (Display.BlockDisplay display : scanTagged(overworld, altarPos)) {
            int index = indexOf(display, count);
            if (force || index < 0 || resolved[index] != null) {
                display.discard();
                discarded++;
            } else {
                resolved[index] = display;
                adopted++;
            }
        }
        long gameTime = overworld.getGameTime();
        long seed = state.orbitSeed();
        Vec3 mount = mountPos(altarPos);
        int spawned = 0;
        for (int i = 0; i < count; i++) {
            if (resolved[i] != null) {
                continue;
            }
            Display.BlockDisplay display = spawnDisplay(overworld, mount, seed, i, gameTime, altarPos);
            if (display != null) {
                resolved[i] = display;
                spawned++;
            }
        }
        displays = resolved;
        reconciled = true;
        if (spawned > 0 || discarded > 0 || force) {
            EclipseMod.LOGGER.info("DayRiftOrbits: adopted {}, spawned {}, discarded {} (swarm {})",
                    adopted, spawned, discarded, count);
        }
    }

    private static List<Display.BlockDisplay> scanTagged(ServerLevel overworld, BlockPos altarPos) {
        return overworld.getEntities(EntityType.BLOCK_DISPLAY, scanVolume(altarPos),
                display -> display.getTags().contains(TAG));
    }

    private static AABB scanVolume(BlockPos altarPos) {
        int topY = FloatingSanctumBuilder.islandTopY(altarPos);
        return new AABB(
                altarPos.getX() - (RADIUS_MAX + 12), topY - 8.0D, altarPos.getZ() - (RADIUS_MAX + 12),
                altarPos.getX() + (RADIUS_MAX + 12), topY + RIFT_ABOVE_TOP + 24.0D,
                altarPos.getZ() + (RADIUS_MAX + 12));
    }

    /** Resolves a scanned display back to its swarm index via the identity tag, or −1. */
    private static int indexOf(Display.BlockDisplay display, int count) {
        for (String tag : display.getTags()) {
            if (tag.startsWith(TAG + "_")) {
                try {
                    int index = Integer.parseInt(tag.substring(TAG.length() + 1));
                    return index >= 0 && index < count ? index : -1;
                } catch (NumberFormatException ignored) {
                    return -1;
                }
            }
        }
        return -1;
    }

    /** The one fixed mount point (open sky over the island top, always-loaded chunk). */
    private static Vec3 mountPos(BlockPos altarPos) {
        return new Vec3(altarPos.getX() + 0.5D,
                FloatingSanctumBuilder.islandTopY(altarPos) + MOUNT_ABOVE_TOP,
                altarPos.getZ() + 0.5D);
    }

    /** The rift maw's sky point (the CUE_DAY_RIFT_MAW anchor and the drop origin). */
    public static Vec3 riftPoint(BlockPos altarPos) {
        return new Vec3(altarPos.getX() + 0.5D,
                FloatingSanctumBuilder.islandTopY(altarPos) + RIFT_ABOVE_TOP,
                altarPos.getZ() + 0.5D);
    }

    @Nullable
    private static Display.BlockDisplay spawnDisplay(ServerLevel overworld, Vec3 mount,
            long seed, int index, long gameTime, BlockPos altarPos) {
        Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(overworld);
        if (display == null) {
            EclipseMod.LOGGER.error("DayRiftOrbits: failed to create block_display #{}", index);
            return null;
        }
        display.moveTo(mount.x, mount.y, mount.z, 0.0F, 0.0F);
        display.setBlockState(blockFor(seed, index));
        display.addTag(TAG);
        display.addTag(TAG + "_" + index);
        // Draw distance + culling envelope + sky-lit brightness in ONE NBT round-trip
        // (the DisplayBrightnessFx seam; setViewRange/setWidth are private in Mojmap).
        var tag = display.saveWithoutId(new net.minecraft.nbt.CompoundTag());
        tag.putFloat("view_range", DISPLAY_VIEW_RANGE);
        tag.putFloat("width", CULL_WIDTH);
        tag.putFloat("height", CULL_HEIGHT);
        var brightness = new net.minecraft.nbt.CompoundTag();
        brightness.putInt("block", 4);
        brightness.putInt("sky", 15);
        tag.put("brightness", brightness);
        display.load(tag);
        // Born already in pose (no interpolation on the first frame).
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(poseAt(seed, index, mount, gameTime, altarPos));
        overworld.addFreshEntity(display);
        return display;
    }

    private static BlockState blockFor(long seed, int index) {
        return PALETTE[(int) Math.floorMod(mix(seed, index), PALETTE.length)];
    }

    // ------------------------------------------------------------------ motion

    private static void animate(ServerLevel overworld, BlockPos altarPos,
            FinaleState state, long gameTime) {
        Display.BlockDisplay[] current = displays;
        if (current == null) {
            return;
        }
        Vec3 mount = mountPos(altarPos);
        long seed = state.orbitSeed();
        boolean missing = false;
        for (int i = 0; i < current.length; i++) {
            Display.BlockDisplay display = current[i];
            if (display == null || display.isRemoved()) {
                missing = true;
                continue;
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(UPDATE_CADENCE_TICKS);
            display.setTransformation(poseAt(seed, i, mount,
                    gameTime + UPDATE_CADENCE_TICKS, altarPos));
        }
        if (missing) {
            reconciled = false;
        }
    }

    /**
     * Absolute orbit pose of piece {@code index} at {@code gameTime}: a slow circle
     * around the island axis (per-piece radius/height/speed/direction from the frozen
     * seed), gentle bob, tumble about a fixed tilted axis — plus the drop-in blend for
     * pieces born this session (rift maw → sag below the line → swing into orbit).
     */
    private static Transformation poseAt(long seed, int index, Vec3 mount,
            long gameTime, BlockPos altarPos) {
        OrbitParams p = paramsFor(seed, index);
        double angle = p.phase + p.direction * Math.toRadians(p.degPerTick) * gameTime;
        double bob = Math.sin((Math.PI * 2.0D / p.bobPeriod) * gameTime + p.phase * 3.0D)
                * BOB_AMPLITUDE;
        double px = mount.x + Math.cos(angle) * p.radius;
        double py = FloatingSanctumBuilder.islandTopY(altarPos) + p.height + bob;
        double pz = mount.z + Math.sin(angle) * p.radius;

        float scale = p.scale;
        Long birth = DROP_BIRTH_TICKS.get(index);
        if (birth != null) {
            if (gameTime >= birth + DROP_BLEND_TICKS) {
                DROP_BIRTH_TICKS.remove(index); // blended in; back to the pure orbit law
            } else {
                Vec3 rift = riftPoint(altarPos);
                double s = smoothstep(Math.max(0.0D, (gameTime - birth) / (double) DROP_BLEND_TICKS));
                if (gameTime < birth) {
                    s = 0.0D;
                }
                // F-102 choreography: the piece is born somewhere on the widened mouth
                // annulus (deterministic from its own params), FALLS first — the
                // horizontal blend is eased quadratically, so early blend is almost
                // pure vertical drop out of the maw — dips under the orbit line on the
                // sag, then swings sideways up into its orbit slot.
                double spillAngle = p.phase * 5.0D;
                double spillFrac = clamp(
                        (p.bobPeriod / BOB_BASE_PERIOD_TICKS - 1.0D) / 0.8D, 0.0D, 1.0D);
                double spillR = SPILL_R_MIN + spillFrac * (SPILL_R_MAX - SPILL_R_MIN);
                double sh = s * s;
                px = rift.x + Math.cos(spillAngle) * spillR * (1.0D - s) + (px - rift.x) * sh;
                py = rift.y + (py - rift.y) * s - Math.sin(s * Math.PI) * 10.0D;
                pz = rift.z + Math.sin(spillAngle) * spillR * (1.0D - s) + (pz - rift.z) * sh;
                scale = (float) (0.1D + (p.scale - 0.1D) * Math.min(1.0D, s * 3.0D));
            }
        }

        Vector3f translation = new Vector3f(
                (float) (px - mount.x), (float) (py - mount.y), (float) (pz - mount.z));
        Vector3f axis = new Vector3f(
                (float) Math.sin(p.phase * 2.0D), 1.1F, (float) Math.cos(p.phase * 2.0D)).normalize();
        float spin = (float) (p.phase * 5.0D
                - p.direction * Math.toRadians(p.spinDegPerTick) * gameTime);
        Quaternionf rotation = new Quaternionf().rotationAxis(spin, axis);
        // Re-center the [0,scale]^3 block mesh on the orbit point through the rotation.
        Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
        translation.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation,
                new Vector3f(scale, scale, scale), new Quaternionf());
    }

    /**
     * The free-orbit POINT of piece {@code index} at {@code gameTime} (world coords,
     * no drop blend) — {@link PortalFormation}'s blend source so the handoff glide
     * starts exactly where the orbit law would have the piece.
     */
    public static Vec3 orbitPointAt(long seed, int index, BlockPos altarPos, long gameTime) {
        OrbitParams p = paramsFor(seed, index);
        double angle = p.phase + p.direction * Math.toRadians(p.degPerTick) * gameTime;
        double bob = Math.sin((Math.PI * 2.0D / p.bobPeriod) * gameTime + p.phase * 3.0D)
                * BOB_AMPLITUDE;
        return new Vec3(
                altarPos.getX() + 0.5D + Math.cos(angle) * p.radius,
                FloatingSanctumBuilder.islandTopY(altarPos) + p.height + bob,
                altarPos.getZ() + 0.5D + Math.sin(angle) * p.radius);
    }

    /** The frozen per-piece scale (PortalFormation keeps it through the glide). */
    public static float scaleOf(long seed, int index) {
        return paramsFor(seed, index).scale;
    }

    /**
     * Deterministic per-piece orbit parameters — a pure function of (seed, index).
     *
     * <p><b>FX-Wave-11 sediment sorting</b>: height and angular speed are no longer
     * rolled independently of the size. They are DERIVED from the scale, so the swarm
     * settles like sediment in water — the heavy pieces sink to the bottom of the band
     * and crawl ({@value #HEIGHT_MIN} blocks at {@value #ORBIT_DEG_PER_TICK_MIN} deg/t),
     * the small shards ride high and whip around ({@value #HEIGHT_MAX} at
     * {@value #ORBIT_DEG_PER_TICK_MAX}). Reading the swarm bottom-up therefore reads it
     * heaviest-first, which is what makes the sky look SORTED instead of sprinkled.
     * A small deterministic jitter around each derived value keeps the correlation from
     * looking like stairs. Roughly one index in {@value #KEYSTONE_EVERY} (a bit of the
     * same {@link #mix} hash the palette uses) is a KEYSTONE slab at
     * {@value #KEYSTONE_SCALE}× scale, pinned to the lowest and slowest band with no
     * jitter — the few anchors the eye measures the rest of the swarm against.</p>
     *
     * <p>Still zero extra packets and unchanged cadence/caps: everything below is
     * arithmetic on {@code (seed, index)}, so the same pair always yields the same
     * pose and boot/reconcile keeps adopting the persisted displays.</p>
     */
    private static OrbitParams paramsFor(long seed, int index) {
        long hash = mix(seed, index);
        RandomSource random = RandomSource.create(hash);
        double radius = RADIUS_MIN + random.nextDouble() * (RADIUS_MAX - RADIUS_MIN);
        double heightJitter = (random.nextDouble() * 2.0D - 1.0D) * HEIGHT_JITTER;
        double phase = random.nextDouble() * Math.PI * 2.0D;
        double speedJitter = (random.nextDouble() * 2.0D - 1.0D) * SPEED_JITTER;
        double direction = random.nextBoolean() ? 1.0D : -1.0D;
        double bobPeriod = BOB_BASE_PERIOD_TICKS * (1.0D + random.nextDouble() * 0.8D);
        double spin = SPIN_DEG_PER_TICK_MIN
                + random.nextDouble() * (SPIN_DEG_PER_TICK_MAX - SPIN_DEG_PER_TICK_MIN);
        boolean keystone = Math.floorMod(hash, KEYSTONE_EVERY) == 0;
        float scale = keystone ? KEYSTONE_SCALE
                : SCALE_MIN + random.nextFloat() * (SCALE_MAX - SCALE_MIN);
        // 0 = the lightest shard, 1 = the heaviest slab (a keystone clamps in at 1).
        double mass = clamp((scale - SCALE_MIN) / (SCALE_MAX - SCALE_MIN), 0.0D, 1.0D);
        double height = clamp(HEIGHT_MAX - mass * (HEIGHT_MAX - HEIGHT_MIN)
                + (keystone ? 0.0D : heightJitter), HEIGHT_MIN, HEIGHT_MAX);
        double degPerTick = clamp(ORBIT_DEG_PER_TICK_MAX
                        - mass * (ORBIT_DEG_PER_TICK_MAX - ORBIT_DEG_PER_TICK_MIN)
                        + (keystone ? 0.0D : speedJitter),
                ORBIT_DEG_PER_TICK_MIN, ORBIT_DEG_PER_TICK_MAX);
        return new OrbitParams(radius, height, phase, degPerTick, direction, bobPeriod, spin, scale);
    }

    private record OrbitParams(double radius, double height, double phase, double degPerTick,
            double direction, double bobPeriod, double spinDegPerTick, float scale) {}

    private static long mix(long seed, int index) {
        long h = seed ^ (index * 0x9E3779B97F4A7C15L + 0x1CE_F044L);
        h ^= h >>> 33;
        h *= 0xFF51AFD7ED558CCDL;
        h ^= h >>> 33;
        return h;
    }

    private static double clamp(double x, double min, double max) {
        return Math.max(min, Math.min(max, x));
    }

    private static double smoothstep(double x) {
        x = Math.max(0.0D, Math.min(1.0D, x));
        return x * x * (3.0D - 2.0D * x);
    }

    // ------------------------------------------------------------------ handoff surface

    /** Live display snapshot for {@link PortalFormation} (index-aligned; nulls skipped). */
    @Nullable
    public static Display.BlockDisplay[] liveDisplays() {
        return displays;
    }

    /** Forces the next gated pass to re-adopt/top-up (after count changes). */
    public static void invalidate() {
        reconciled = false;
    }

    /**
     * Immediate full reconcile for {@link PortalFormation#begin} (dev fast path seeds a
     * swarm and needs it standing NOW, not at the next 40t/600t boundary).
     */
    public static void reconcileNow(ServerLevel overworld) {
        BlockPos altarPos = EclipseWorldState.get(overworld.getServer()).getSanctumAltarPos();
        if (altarPos != null) {
            reconcile(overworld, altarPos, FinaleState.get(overworld.getServer()), false);
        }
    }

    /** Discards every live + tagged orbit display (the formation consumed the swarm). */
    public static void discardAll(ServerLevel overworld) {
        BlockPos altarPos = EclipseWorldState.get(overworld.getServer()).getSanctumAltarPos();
        int discarded = 0;
        if (displays != null) {
            for (Display.BlockDisplay display : displays) {
                if (display != null && !display.isRemoved()) {
                    display.discard();
                    discarded++;
                }
            }
        }
        if (altarPos != null) {
            for (Display.BlockDisplay stray : scanTagged(overworld, altarPos)) {
                stray.discard();
                discarded++;
            }
        }
        displays = null;
        reconciled = false;
        DROP_BIRTH_TICKS.clear();
        if (discarded > 0) {
            EclipseMod.LOGGER.info("DayRiftOrbits: {} orbit display(s) discarded (handoff/sweep)", discarded);
        }
    }

    /** One-per-boot orphan sweep once the arc is past the orbit stage. */
    private static void sweepLeftoversOnce(ServerLevel overworld, BlockPos altarPos) {
        if (sweptAfterFormation) {
            return;
        }
        if (!overworld.isLoaded(altarPos)
                || !overworld.areEntitiesLoaded(ChunkPos.asLong(altarPos))) {
            return; // retry at the next cadence boundary
        }
        sweptAfterFormation = true;
        List<Display.BlockDisplay> strays = new ArrayList<>(scanTagged(overworld, altarPos));
        strays.forEach(Display.BlockDisplay::discard);
        if (!strays.isEmpty()) {
            EclipseMod.LOGGER.info("DayRiftOrbits: {} post-formation orphan display(s) swept", strays.size());
        }
    }
}
