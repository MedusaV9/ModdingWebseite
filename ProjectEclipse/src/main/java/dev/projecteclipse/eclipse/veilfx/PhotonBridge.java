package dev.projecteclipse.eclipse.veilfx;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * D12 — optional bridge to the <b>Photon</b> VFX mod (Modrinth {@code photon-editor},
 * Low Drag MC): when the {@code photon} mod is installed on the client, flagship moments
 * get an EXTRA editor-authored Photon effect layered over the existing Quasar visuals;
 * without Photon (or without the effect assets) every call is a silent no-op and the
 * shipped Quasar/vanilla path is exactly what it was before this class existed.
 *
 * <p><b>Deliberately reflection-based, no compile-time dependency.</b> The Modrinth maven
 * coordinate {@code maven.modrinth:photon-editor:mc1.21.1-2.1.5-neoforge} verifiably
 * resolves (pom + jar HTTP 200, checked 2026-07), but this repo's build must stay buildable
 * with zero new remote dependencies, so every touched API point is reflected against
 * signatures verified from the published 2.1.5 jar (javap — see
 * {@code docs/plans_v3/plans_v5/photon/API.md}):</p>
 * <ul>
 *   <li>{@code FXHelper.getFX(ResourceLocation)} — loads/caches an {@code FX} from
 *       {@code assets/<ns>/fx/<path>.fx} (compressed-NBT files, authored in Photon's
 *       in-game editor or via {@code tools/photon/fxlib.py});</li>
 *   <li>{@code new BlockEffectExecutor(FX, Level, BlockPos)} + {@code start()} — plays the
 *       effect anchored at a block position (block center + offset);</li>
 *   <li>{@code new EntityEffectExecutor(FX, Level, Entity, AutoRotate)} + {@code start()}
 *       — attaches the effect to an entity (eye position + offset, auto-cleanup on death);</li>
 *   <li>{@code FXEffectExecutor.setOffset(Vector3f)/setRotation(Quaternionf)/
 *       setScale(Vector3f)/setDelay(int)/setAllowMulti(boolean)/getRuntime()} — shared
 *       executor knobs (inherited by both executor kinds);</li>
 *   <li>{@code FXRuntime.isAlive()} + {@code FXRuntime.destroy(boolean force)} — live
 *       playback introspection and the loop stop path ({@code force=false} = graceful
 *       fade-out, {@code true} = instant kill).</li>
 * </ul>
 *
 * <p><b>Guards</b> (all must pass, in order): {@code ModList.get().isLoaded("photon")}
 * (checked once, the mod set is frozen after load), the {@code photonFx} client toggle,
 * NOT {@code reducedFx}, reflection handles resolved. A reflection failure disables the
 * bridge for the session (one WARN); a missing {@code .fx} asset skips that effect id for
 * the session (one INFO). Photon draws through its own renderer (not Veil/Quasar), so
 * spawns are NOT charged to {@link FxBudget} — instead the bridge enforces its own hard
 * ceiling of {@value #MAX_LIVE_EXECUTORS} live Photon executors (one-shots count until
 * their runtime dies): spawns beyond it are refused (return {@code false}/{@code null}).</p>
 *
 * <p><b>Lifecycle cache:</b> every executor started through the bridge is tracked and
 * swept once per client tick — dead runtime → forgotten; dead/removed entity or a level
 * change (Photon's own mixins clear the particle engine on level swap) → destroyed and
 * forgotten; logout → everything force-destroyed. Loops (looping {@code .fx} assets played
 * via {@link #spawnLoop}) MUST be held as a {@link LoopHandle} and stopped with
 * {@link #stopLoop} — see the WINDOWED-loop law in
 * {@code docs/plans_v3/plans_v5/photon/INTEGRATION.md} §4.</p>
 *
 * <p>Effect ids consumed by the direct (non-registry) seams (drop-in
 * {@code assets/eclipse/fx/<id>.fx}): {@link #ALTAR_LEVELUP}, {@link #EXPANSION_RIFT_GLOW},
 * {@link #OFFERING_SWALLOW_SOUL}, {@link #SUPPLY_DROP_CONTRAIL}, {@link #STORM_CROWN_HALO},
 * {@link #INTRO_BURST_RING} and the four
 * {@code PORTAL_IRIS_OPEN_*}/{@code PORTAL_LOOP_*} ids. Table-driven cues live in
 * {@link PhotonFxRegistry}.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class PhotonBridge {
    /** Extra glow/burst for the altar milestone level-up moment. */
    public static final ResourceLocation ALTAR_LEVELUP = fx("altar_levelup");
    /** Extra glow for expansion (structure-drop) rift tears. */
    public static final ResourceLocation EXPANSION_RIFT_GLOW = fx("expansion_rift_glow");
    /** Muzzle flash per piece-launch surge burst at a delivery tear ({@code RiftFx.tickSurge}). */
    public static final ResourceLocation RIFT_PIECE_FLASH = fx("rift_piece_flash");
    /**
     * PH-PLAYER #1: HDR bloom pop riding the soulbind flash tick. Deliberately the SAME id
     * as the {@code wand_soulbind_flash} Quasar emitter fired by
     * {@code WandPowers.handleChoosePath} — the payload's emitter id doubles as the fx id,
     * so {@link #enhanceQuasarCue} needs no extra mapping (no wire change).
     */
    public static final ResourceLocation WAND_SOULBIND_FLASH = fx("wand_soulbind_flash");
    /**
     * PHOTON-QUALITY §6 retirement: the {@code stern_komet_core} Quasar emitter (the
     * teleport-fake descent beats + impact afterglow dome) is superseded by the Photon
     * falling head ({@code stern_komet_fall}) + delayed impact bloom
     * ({@code stern_komet_impact}) spawned by {@code WandPhotonFxRows}'s
     * {@code CUE_STERN_KOMET} leg. {@link #enhanceQuasarCue} suppresses the emitter while
     * either replacement is live near the strike ({@code stern_funke_fall} stays LAYER —
     * the ground sparkle is complementary).
     */
    private static final ResourceLocation STERN_KOMET_CORE = fx("stern_komet_core");
    private static final ResourceLocation STERN_KOMET_FALL = fx("stern_komet_fall");
    private static final ResourceLocation STERN_KOMET_IMPACT = fx("stern_komet_impact");
    /**
     * PHOTON-QUALITY §6 retirement (emitter-only): the {@code riss_schlag_maw} Quasar
     * emitter (both drew the inhale) — same id as the Photon maw asset spawned by
     * {@code WandPhotonFxRows}'s {@code CUE_RISS_SCHLAG} leg, which
     * {@code WandPowers.castRissschlag} now sends BEFORE the maw payloads.
     * {@code riss_maw_shimmer}/{@code riss_seam_scar}/{@code riss_blink_tear} stay
     * untouched LAYER dressing.
     */
    private static final ResourceLocation RISS_SCHLAG_MAW = fx("riss_schlag_maw");
    /**
     * Suppression radius for the komet retirement: the Photon head anchors at
     * strike + 18 blocks up while the Quasar beats step down (+18 / +9 / ground), so the
     * probe must span the whole descent column — but stay tight enough that a second
     * caster's strike further away keeps its own Quasar baseline when its Photon leg
     * was refused (degradation law).
     */
    private static final double KOMET_SUPPRESS_RANGE = 24.0D;
    /** Suppression radius for the maw retirement (all beats anchor on the tear itself). */
    private static final double MAW_SUPPRESS_RANGE = 8.0D;
    /**
     * PH-ALTAR (IDEAS-mobs #2): converging soul-ribbon spiral inhaled by the altar while
     * an offering swallow is in flight — spawned client-locally by
     * {@code client/drama/OfferingSwallowFx.beginFlight} (the {@code RiftFx.openRift}
     * shape: not payload-driven, so no registry row) with {@code allowMulti=true}.
     */
    public static final ResourceLocation OFFERING_SWALLOW_SOUL = fx("offering_swallow_soul");
    /**
     * PH-MOBS (IDEAS-mobs #3): award-podium star shower — nether-star MODEL particles
     * raining, bouncing off the real floor (the batch's only collision-physics concept)
     * with Collision sub-emitter glints. Spawned client-locally by
     * {@code client/awards/AwardsOverlay.podiumBurst} (already client-only, already
     * exactly-once on the LAND transition); default {@code allowMulti=false} also
     * shields against LAND replays.
     */
    public static final ResourceLocation AWARD_STAR_SHOWER = fx("award_star_shower");
    /**
     * PH-WORLD (IDEAS-world #4): supply-drop descent contrail, attached to the falling
     * crate entity by {@code SupplyBeamClient} ({@link #spawnOnEntity} — client-locally
     * triggered off the shipped supply-marker payload, so no registry row). The crate's
     * landing death auto-destroys the runtime; the asset's own FirstCollision
     * sub-emitter ({@code eclipse:supply_landing_dust}) stamps the landing dust ring.
     */
    public static final ResourceLocation SUPPLY_DROP_CONTRAIL = fx("supply_drop_contrail");
    /**
     * PH-WORLD (IDEAS-world #8): rotating pearl-string halo above sphere-storm crowns.
     * Not a registry row: {@code PhotonFxRegistry.ensureLoop} manages ONE loop per
     * logical id, but each sphere storm needs its own — {@code stormfx/StormFxClient}
     * holds one {@link LoopHandle} per {@code ClientStorm} instead (windowed on the
     * shell-distance band, released with the storm).
     */
    public static final ResourceLocation STORM_CROWN_HALO = fx("storm_crown_halo");
    /**
     * PH-EVENTS (IDEAS-events #1): intro-BURST HDR white-out ring, layered client-locally
     * over the {@code FX_SHOCKWAVE (a>=1.0, b>=50)} giant signature in
     * {@code FxPayloads.handleFxEvent} — the live intro/credits bursts AND their FX-only
     * replays all send that exact payload, so replay parity is free.
     */
    public static final ResourceLocation INTRO_BURST_RING = fx("intro_burst_ring");
    /**
     * PH-EVENTS (IDEAS-events #5a): portal-open iris pop, violet (xbox {@code STYLE_PORTAL}).
     * Spawned by {@code RiftFx.openRift}'s style branch, executor-scaled to the tear width.
     */
    public static final ResourceLocation PORTAL_IRIS_OPEN_XBOX = fx("portal_iris_open_xbox");
    /** PH-EVENTS (IDEAS-events #5a): the wax-gold {@code STYLE_BACKROOMS} iris variant. */
    public static final ResourceLocation PORTAL_IRIS_OPEN_BACKROOMS = fx("portal_iris_open_backrooms");
    /**
     * PH-EVENTS (IDEAS-events #5b): xbox era-pixel mote identity loop. Portal-scoped
     * WINDOWED loop (INTEGRATION.md §4) — {@code RiftFx} owns the window: kept alive on the
     * rift's retry cadence while the tear is open, stopped (graceful fade) on close.
     */
    public static final ResourceLocation PORTAL_LOOP_XBOX = fx("portal_loop_xbox");
    /** PH-EVENTS (IDEAS-events #5c): backrooms fluorescent flicker + haze identity loop. */
    public static final ResourceLocation PORTAL_LOOP_BACKROOMS = fx("portal_loop_backrooms");

    /**
     * Indices into the bridge's NAME-resolved {@code EntityEffectExecutor.AutoRotate}
     * constant table (see {@code resolve()}): each slot is looked up by enum name
     * ({@code NONE, FORWARD, LOOK, XROT}), never by raw ordinal, so a link-compatible
     * Photon that inserts/reorders/renames constants degrades that mode to NONE instead
     * of silently misorienting entity effects (EVAL-V6-PHOTON §7.5).
     */
    public static final int AUTO_ROTATE_NONE = 0;
    public static final int AUTO_ROTATE_FORWARD = 1;
    public static final int AUTO_ROTATE_LOOK = 2;
    public static final int AUTO_ROTATE_XROT = 3;

    /**
     * Hard budget: max concurrently-live Photon executors started through the bridge.
     * Photon bypasses {@link FxBudget} (own render pipeline), so this is the only ceiling;
     * spawns beyond it are refused outright (never queued).
     */
    public static final int MAX_LIVE_EXECUTORS = 24;

    private static final int UNRESOLVED = 0;
    private static final int READY = 1;
    private static final int DISABLED = 2;

    private static volatile int state = UNRESOLVED;
    private static Method getFxMethod;
    private static Constructor<?> blockExecutorCtor;
    private static Method blockStartMethod;
    private static Constructor<?> entityExecutorCtor;
    private static Method entityStartMethod;
    private static Object[] autoRotateConstants;
    private static Method setOffsetMethod;
    private static Method setRotationMethod;
    private static Method setScaleMethod;
    private static Method setDelayMethod;
    private static Method setAllowMultiMethod;
    private static Method getRuntimeMethod;
    private static Method runtimeIsAliveMethod;
    private static Method runtimeDestroyMethod;

    /** Effect ids whose {@code .fx} asset failed to load — skipped for the session. */
    private static final Set<ResourceLocation> MISSING_FX = new HashSet<>();

    /** Every live executor started through the bridge (client main thread only). */
    private static final List<Tracked> LIVE = new ArrayList<>();
    /** Budget refusals this session (dev/QA introspection via {@code /dev photon status}). */
    private static int refusedCount;

    private PhotonBridge() {}

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    // ------------------------------------------------------------------ options

    /**
     * Optional executor knobs, applied (via reflection) before {@code start()} on BOTH
     * executor kinds. All fields optional; start from {@link #DEFAULT} and use the
     * {@code with*} copies.
     *
     * @param offset      extra local offset in blocks (block executors anchor at block
     *                    center + offset; entity executors at eye position + offset)
     * @param rotationDeg XYZ euler degrees (converted to a JOML quaternion like Photon's
     *                    own {@code IFXEffectExecutor} default)
     * @param scale       per-axis scale multiplier
     * @param delayTicks  ticks before emission starts
     * @param allowMulti  {@code true} = allow stacking the same fx id on the same anchor
     *                    while a previous runtime is alive (Photon default dedups silently)
     */
    public record SpawnOptions(@Nullable Vector3f offset, @Nullable Vector3f rotationDeg,
            @Nullable Vector3f scale, int delayTicks, boolean allowMulti) {
        public static final SpawnOptions DEFAULT = new SpawnOptions(null, null, null, 0, false);

        public SpawnOptions withOffset(double x, double y, double z) {
            return new SpawnOptions(new Vector3f((float) x, (float) y, (float) z),
                    rotationDeg, scale, delayTicks, allowMulti);
        }

        public SpawnOptions withRotationDeg(double xDeg, double yDeg, double zDeg) {
            return new SpawnOptions(offset, new Vector3f((float) xDeg, (float) yDeg, (float) zDeg),
                    scale, delayTicks, allowMulti);
        }

        public SpawnOptions withScale(double x, double y, double z) {
            return new SpawnOptions(offset, rotationDeg,
                    new Vector3f((float) x, (float) y, (float) z), delayTicks, allowMulti);
        }

        public SpawnOptions withDelay(int ticks) {
            return new SpawnOptions(offset, rotationDeg, scale, ticks, allowMulti);
        }

        public SpawnOptions withAllowMulti(boolean allow) {
            return new SpawnOptions(offset, rotationDeg, scale, delayTicks, allow);
        }
    }

    /**
     * Opaque handle to a looping Photon effect started via {@link #spawnLoop}; hold it and
     * call {@link #stopLoop} (or rely on the per-tick sweep for death/level-change cleanup).
     */
    public static final class LoopHandle {
        private final Tracked tracked;

        private LoopHandle(Tracked tracked) {
            this.tracked = tracked;
        }

        /** Whether the loop's runtime is still alive (false after stop/sweep/kill). */
        public boolean alive() {
            return LIVE.contains(tracked)
                    && (runtimeAlive(tracked.executor) || withinSpawnGrace(tracked));
        }
    }

    /** One live executor started through the bridge. */
    private static final class Tracked {
        final Object executor;
        final ResourceLocation fxId;
        final Level level;
        @Nullable
        final Entity entity;
        final boolean loop;
        /** Spawn anchor for position executors ({@code null} for entity attaches). */
        @Nullable
        final Vec3 anchorPos;
        /** Bridge tick the executor was started on ({@link #SPAWN_GRACE_TICKS}). */
        final long spawnTick;

        Tracked(Object executor, ResourceLocation fxId, Level level, @Nullable Entity entity,
                boolean loop, @Nullable Vec3 anchorPos) {
            this.executor = executor;
            this.fxId = fxId;
            this.level = level;
            this.entity = entity;
            this.loop = loop;
            this.anchorPos = anchorPos;
            this.spawnTick = clientTicks;
        }
    }

    /**
     * A freshly started runtime reports {@code isAlive() == false} until its emitters have
     * ticked once — and FXRuntime ticks ride the RENDER cadence, so after a render stall the
     * client's catch-up ticks would see every just-spawned loop as dead, prune it, and
     * respawn it each tick (the "Duplicate fx runtime object id" storm: ~9 replaces per
     * frame at llvmpipe frame rates). Executors younger than this many bridge ticks are
     * therefore treated as alive-pending instead of dead. 100 t (5 s) also covers the
     * long render stall of a dimension change (40 t left a 3-respawn tail there).
     */
    private static final int SPAWN_GRACE_TICKS = 100;

    /** Monotonic client-tick counter driving {@link #SPAWN_GRACE_TICKS} (see {@link Sweep}). */
    private static long clientTicks;

    /** True while {@code tracked} is young enough that a not-yet-alive runtime is expected. */
    private static boolean withinSpawnGrace(Tracked tracked) {
        return clientTicks - tracked.spawnTick <= SPAWN_GRACE_TICKS;
    }

    // ------------------------------------------------------------------ availability

    /** Whether the Photon layer may run right now (mod present + toggles). Cheap. */
    public static boolean available() {
        return state != DISABLED
                && ModList.get().isLoaded("photon")
                && EclipseClientConfig.photonFx()
                && !EclipseClientConfig.reducedFx();
    }

    /**
     * {@code S2CQuasarPayload} seam (called from {@code EclipsePayloads.handleQuasar} on the
     * client main thread): plays the Photon enhancement for cues that have one and answers
     * whether the cue's Quasar leg is SUPERSEDED by a live Photon replacement
     * (PHOTON-QUALITY §6 retirements — REPLACE semantics).
     *
     * @return {@code true} = the caller must skip the Quasar leg (a Photon replacement
     *         played/is live for this cue); {@code false} = run the Quasar leg as always
     *         (LAYER cues, retired cues whose Photon leg did not play — the automatic
     *         fallback — and every cue without an enhancement)
     */
    public static boolean enhanceQuasarCue(ResourceLocation emitterId, Vec3 pos) {
        // FX-WAVE-13/B1 hero legs (heart_burst / boss_slam / map_expand_materialize):
        // the full table + REPLACE/LAYER semantics live in Wave13bPhotonFxRows; null
        // means "not a B1 cue" and falls through to the legacy chain below.
        Boolean b1 = Wave13bPhotonFxRows.enhanceQuasarCue(emitterId, pos);
        if (b1 != null) {
            return b1;
        }
        if (S2CQuasarPayload.ALTAR_LEVELUP_RING.equals(emitterId)) {
            // Deliberate LAYER (PHOTON-QUALITY §6 "considered and kept"): ring + bloom
            // both play — D12 "Photon is garnish" law.
            spawn(ALTAR_LEVELUP, pos);
            return false;
        }
        if (WAND_SOULBIND_FLASH.equals(emitterId)) {
            // PH-PLAYER #1: entity attach makes the flash RIDE the player if they move
            // mid-ceremony (offset -0.4 = chest/wand height — the ceremony holds the wand
            // up). Default allowMulti=false is correct: the flash fires once, a duplicate
            // payload inside its ~50t life no-ops harmlessly.
            // PHOTON-QUALITY §6 retirement: same beat, same tick, same shape — the Photon
            // 4-emitter HDR flash REPLACES the Quasar flash whenever it plays (double
            // flash reads as stutter); the wand_soulbind_orbit emitters are a different
            // beat and keep firing untouched.
            Entity holder = nearestPlayer(pos, 8.0D);
            if (holder != null) {
                return spawnOnEntity(WAND_SOULBIND_FLASH, holder, AUTO_ROTATE_NONE,
                        new Vec3(0.0D, -0.4D, 0.0D));
            }
            return spawn(WAND_SOULBIND_FLASH, pos); // untracked holder — block-anchor fallback
        }
        if (STERN_KOMET_CORE.equals(emitterId)) {
            // Retired while the real Photon fall/impact is live near the strike — both at
            // once shows two comet heads. Photon-less/refused casts keep every beat.
            return hasLiveFx(STERN_KOMET_FALL, pos, KOMET_SUPPRESS_RANGE)
                    || hasLiveFx(STERN_KOMET_IMPACT, pos, KOMET_SUPPRESS_RANGE);
        }
        if (RISS_SCHLAG_MAW.equals(emitterId)) {
            // Retired (emitter-only) while the Photon implosion maw is live on the tear.
            return hasLiveFx(RISS_SCHLAG_MAW, pos, MAW_SUPPRESS_RANGE);
        }
        return false;
    }

    /**
     * Whether a bridge-tracked executor for {@code fxId} is currently live within
     * {@code range} blocks of {@code pos} in the current client level (retirement probes:
     * position executors use their spawn anchor, entity attaches their current position).
     */
    public static boolean hasLiveFx(ResourceLocation fxId, Vec3 pos, double range) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return false;
        }
        double rangeSq = range * range;
        for (Tracked tracked : LIVE) {
            if (!tracked.fxId.equals(fxId) || tracked.level != level) {
                continue;
            }
            Vec3 anchor = tracked.entity != null ? tracked.entity.position() : tracked.anchorPos;
            if (anchor != null && anchor.distanceToSqr(pos) <= rangeSq
                    && (runtimeAlive(tracked.executor) || withinSpawnGrace(tracked))) {
                return true;
            }
        }
        return false;
    }

    /** Nearest client-level player to a cue position (payloads carry no entity id). */
    @Nullable
    private static net.minecraft.world.entity.player.Player nearestPlayer(Vec3 pos, double maxRange) {
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return null;
        }
        net.minecraft.world.entity.player.Player best = null;
        double bestDistSq = maxRange * maxRange;
        for (net.minecraft.world.entity.player.Player player : level.players()) {
            double distSq = player.distanceToSqr(pos);
            if (distSq < bestDistSq) {
                bestDistSq = distSq;
                best = player;
            }
        }
        return best;
    }

    // ------------------------------------------------------------------ one-shot spawns

    /**
     * Plays the Photon effect {@code fxId} anchored at {@code pos}'s block position
     * (frozen D12 behavior: plays at block center, no exact sub-block anchoring).
     * @return {@code true} only when a Photon effect actually started (or an identical one
     *         is already live at this anchor — Photon's own dedup); every failure path
     *         (photon absent, toggles off, missing asset, reflection breakage, executor
     *         budget) is a no-op returning {@code false}.
     */
    public static boolean spawn(ResourceLocation fxId, Vec3 pos) {
        return startExecutor(fxId, pos, null, 0, SpawnOptions.DEFAULT, false, false) != START_FAILED;
    }

    /**
     * Like {@link #spawn(ResourceLocation, Vec3)} but with exact sub-block anchoring (the
     * executor's block-center anchor is corrected to {@code pos} before any
     * {@code options.offset}) plus the full {@link SpawnOptions} knob set.
     */
    public static boolean spawn(ResourceLocation fxId, Vec3 pos, SpawnOptions options) {
        return startExecutor(fxId, pos, null, 0, options, true, false) != START_FAILED;
    }

    /**
     * Attaches the Photon effect {@code fxId} to {@code entity} (played at the entity's eye
     * position + offset every frame; Photon auto-destroys it when the entity dies).
     *
     * @param autoRotateOrdinal one of {@link #AUTO_ROTATE_NONE} / {@link #AUTO_ROTATE_FORWARD}
     *                          / {@link #AUTO_ROTATE_LOOK} / {@link #AUTO_ROTATE_XROT}
     * @param offset            extra local offset in blocks, or {@code null}
     * @return {@code true} iff the effect started (same failure semantics as {@link #spawn})
     */
    public static boolean spawnOnEntity(ResourceLocation fxId, Entity entity,
            int autoRotateOrdinal, @Nullable Vec3 offset) {
        SpawnOptions options = offset == null ? SpawnOptions.DEFAULT
                : SpawnOptions.DEFAULT.withOffset(offset.x, offset.y, offset.z);
        return spawnOnEntity(fxId, entity, autoRotateOrdinal, options);
    }

    /** {@link #spawnOnEntity(ResourceLocation, Entity, int, Vec3)} with the full knob set. */
    public static boolean spawnOnEntity(ResourceLocation fxId, Entity entity,
            int autoRotateOrdinal, SpawnOptions options) {
        return startExecutor(fxId, null, entity, autoRotateOrdinal, options, false, false)
                != START_FAILED;
    }

    // ------------------------------------------------------------------ loops

    /**
     * Plays a looping {@code .fx} asset anchored at {@code pos} (exact sub-block anchor) and
     * returns a handle for {@link #stopLoop}. Loops are WINDOWED-only by law (INTEGRATION.md
     * §4): the caller MUST own a hysteresis window (SanctumLightfall pattern) and stop the
     * loop when the window closes — the per-tick sweep only covers death/level-change.
     *
     * @return the handle, or {@code null} when the spawn was refused (any guard, budget, or
     *         Photon's same-anchor dedup — a loop we did not create cannot be managed)
     */
    @Nullable
    public static LoopHandle spawnLoop(ResourceLocation fxId, Vec3 pos) {
        Tracked tracked = startExecutor(fxId, pos, null, 0,
                SpawnOptions.DEFAULT.withAllowMulti(true), true, true);
        return tracked == null || tracked == START_FAILED ? null : new LoopHandle(tracked);
    }

    /**
     * {@link #spawnLoop(ResourceLocation, Vec3)} with the full {@link SpawnOptions} knob
     * set (rotation/scale for yaw-aligned loop legs, e.g. the WOAH-04 resonance light
     * paths). {@code allowMulti} is forced on exactly like the plain loop path — loop
     * ownership must never be stolen by Photon's same-anchor dedup.
     */
    @Nullable
    public static LoopHandle spawnLoop(ResourceLocation fxId, Vec3 pos, SpawnOptions options) {
        Tracked tracked = startExecutor(fxId, pos, null, 0,
                options.withAllowMulti(true), true, true);
        return tracked == null || tracked == START_FAILED ? null : new LoopHandle(tracked);
    }

    /** Entity-attached variant of {@link #spawnLoop(ResourceLocation, Vec3)}. */
    @Nullable
    public static LoopHandle spawnLoop(ResourceLocation fxId, Entity entity, int autoRotateOrdinal) {
        Tracked tracked = startExecutor(fxId, null, entity, autoRotateOrdinal,
                SpawnOptions.DEFAULT.withAllowMulti(true), false, true);
        return tracked == null || tracked == START_FAILED ? null : new LoopHandle(tracked);
    }

    /**
     * PH-PLAYER (IDEAS-player.md §0): idle-loop keepalive primitive mirroring
     * {@code QuasarSpawner.ensureAttached}. Keeps ONE looping {@code fxId} attached to
     * {@code entity}: while a bridge-tracked runtime is alive this is a cheap no-op, so
     * callers ensure on a slow cadence (20–40t) and dedup guarantees exactly one live
     * runtime, self-healing after entity untrack/re-track. The executor keeps Photon's
     * default {@code allowMulti=false}, so even an untracked-but-alive duplicate (e.g.
     * after a bookkeeping loss) is silently absorbed by Photon's per-entity CACHE.
     *
     * <p>WINDOWED-only law applies (INTEGRATION.md §4): the caller MUST own a hysteresis
     * window and call {@link #stopAttachedFx} when it closes.</p>
     *
     * @return {@code true} while an attached runtime is live (or was started/absorbed)
     */
    public static boolean ensureAttachedFx(ResourceLocation fxId, Entity entity,
            int autoRotateOrdinal, @Nullable Vec3 offset) {
        for (Tracked tracked : LIVE) {
            if (tracked.entity == entity && tracked.fxId.equals(fxId)
                    && (runtimeAlive(tracked.executor) || withinSpawnGrace(tracked))) {
                return true; // keepalive no-op — exactly one live runtime per (fx, entity)
            }
        }
        SpawnOptions options = offset == null ? SpawnOptions.DEFAULT
                : SpawnOptions.DEFAULT.withOffset(offset.x, offset.y, offset.z);
        Tracked started = startExecutor(fxId, null, entity, autoRotateOrdinal, options, false, true);
        // null = Photon's own CACHE dedup (an identical live runtime we no longer track).
        return started != START_FAILED;
    }

    /**
     * Stops the entity-attached loop(s) previously kept alive by {@link #ensureAttachedFx}
     * for this exact (fx id, entity) pair. {@code force=false} = graceful fade
     * ({@code destroy(false)}), {@code true} = instant kill. Idempotent.
     */
    public static void stopAttachedFx(ResourceLocation fxId, Entity entity, boolean force) {
        for (int i = LIVE.size() - 1; i >= 0; i--) {
            Tracked tracked = LIVE.get(i);
            if (tracked.entity == entity && tracked.fxId.equals(fxId)) {
                LIVE.remove(i);
                destroyQuietly(tracked, force);
            }
        }
    }

    /**
     * Stops a loop started with {@link #spawnLoop}: {@code graceful=true} lets emitters stop
     * and live particles fade naturally ({@code FXRuntime.destroy(false)});
     * {@code graceful=false} kills everything instantly ({@code destroy(true)}). Idempotent.
     */
    public static void stopLoop(@Nullable LoopHandle handle, boolean graceful) {
        if (handle == null) {
            return;
        }
        if (LIVE.remove(handle.tracked)) {
            destroyQuietly(handle.tracked, !graceful);
        }
    }

    // ------------------------------------------------------------------ spawn core

    /** Sentinel distinguishing "refused/failed" from "dedup no-op success" (null). */
    private static final Tracked START_FAILED =
            new Tracked(new Object(), ResourceLocation.withDefaultNamespace("failed"), null, null,
                    false, null);

    /**
     * Shared spawn path. Anchors at {@code pos} (block executor) when {@code entity} is
     * null, else attaches to {@code entity}. @return the tracked entry, {@code null} for a
     * Photon same-anchor dedup no-op (effect already playing), or {@link #START_FAILED}.
     */
    @Nullable
    private static Tracked startExecutor(ResourceLocation fxId, @Nullable Vec3 pos,
            @Nullable Entity entity, int autoRotateOrdinal, SpawnOptions options,
            boolean exactAnchor, boolean loop) {
        if (!available() || MISSING_FX.contains(fxId)) {
            return START_FAILED;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null || !resolve()) {
            return START_FAILED;
        }
        sweep();
        if (LIVE.size() >= MAX_LIVE_EXECUTORS) {
            refusedCount++;
            EclipseMod.LOGGER.debug("Photon spawn {} refused: {} live executors (cap {})",
                    fxId, LIVE.size(), MAX_LIVE_EXECUTORS);
            return START_FAILED;
        }
        try {
            Object fxObject = getFxMethod.invoke(null, fxId);
            if (fxObject == null) {
                missing(fxId);
                return START_FAILED;
            }
            // F-103 R2 respawn hygiene: every spawn copies from this SHARED template —
            // scrub any live scene-graph residue off it first (see TemplateHygiene).
            TemplateHygiene.scrub(fxId, fxObject);
            Object executor;
            Method start;
            if (entity != null) {
                int ordinal = autoRotateOrdinal >= 0 && autoRotateOrdinal < autoRotateConstants.length
                        ? autoRotateOrdinal : AUTO_ROTATE_NONE;
                executor = entityExecutorCtor.newInstance(fxObject, entity.level(), entity,
                        autoRotateConstants[ordinal]);
                start = entityStartMethod;
            } else {
                executor = blockExecutorCtor.newInstance(fxObject, level, BlockPos.containing(pos));
                start = blockStartMethod;
            }
            applyOptions(executor, pos, options, exactAnchor && entity == null);
            start.invoke(executor);
            if (getRuntimeMethod.invoke(executor) == null) {
                // start() dedup'd silently (allowMulti=false + identical live effect at
                // this anchor): the cue is visually satisfied but we own no runtime.
                return null;
            }
            Tracked tracked = new Tracked(executor, fxId,
                    entity != null ? entity.level() : level, entity, loop,
                    entity == null ? pos : null);
            LIVE.add(tracked);
            return tracked;
        } catch (Throwable t) {
            // Asset-load failures surface here as InvocationTargetExceptions; executor
            // breakage would too. Either way: skip the id for the session, one WARN.
            if (MISSING_FX.add(fxId)) {
                EclipseMod.LOGGER.warn("Photon effect {} failed; skipping it for this session", fxId, t);
            }
            return START_FAILED;
        }
    }

    /** Applies {@link SpawnOptions} through the shared {@code FXEffectExecutor} setters. */
    private static void applyOptions(Object executor, @Nullable Vec3 pos, SpawnOptions options,
            boolean exactAnchor) throws Exception {
        Vector3f offset = null;
        if (exactAnchor && pos != null) {
            // The block executor plays at BlockPos + 0.5 — correct back to the exact Vec3.
            BlockPos bp = BlockPos.containing(pos);
            offset = new Vector3f((float) (pos.x - (bp.getX() + 0.5D)),
                    (float) (pos.y - (bp.getY() + 0.5D)),
                    (float) (pos.z - (bp.getZ() + 0.5D)));
        }
        if (options.offset() != null) {
            offset = offset == null ? new Vector3f(options.offset()) : offset.add(options.offset());
        }
        if (offset != null) {
            setOffsetMethod.invoke(executor, offset);
        }
        if (options.rotationDeg() != null) {
            Vector3f r = options.rotationDeg();
            setRotationMethod.invoke(executor, new Quaternionf().rotationXYZ(
                    (float) Math.toRadians(r.x), (float) Math.toRadians(r.y),
                    (float) Math.toRadians(r.z)));
        }
        if (options.scale() != null) {
            setScaleMethod.invoke(executor, new Vector3f(options.scale()));
        }
        if (options.delayTicks() > 0) {
            setDelayMethod.invoke(executor, options.delayTicks());
        }
        if (options.allowMulti()) {
            setAllowMultiMethod.invoke(executor, true);
        }
    }

    // ------------------------------------------------------------------ sweep / lifecycle

    /**
     * Per-tick sweep of the live-executor cache: dead runtime → forget; dead/removed entity
     * or anchor level no longer the current client level → destroy (force) + forget.
     */
    static void sweep() {
        if (LIVE.isEmpty()) {
            return;
        }
        ClientLevel current = Minecraft.getInstance().level;
        for (int i = LIVE.size() - 1; i >= 0; i--) {
            Tracked tracked = LIVE.get(i);
            if (!runtimeAlive(tracked.executor) && !withinSpawnGrace(tracked)) {
                LIVE.remove(i);
                continue;
            }
            boolean deadEntity = tracked.entity != null
                    && (!tracked.entity.isAlive() || tracked.entity.isRemoved());
            boolean leftDimension = current == null || tracked.level != current
                    || (tracked.entity != null && tracked.entity.level() != current);
            if (deadEntity || leftDimension) {
                LIVE.remove(i);
                destroyQuietly(tracked, true);
            }
        }
    }

    /** Force-destroys and forgets every tracked executor (logout / disconnect reset). */
    static void destroyAll() {
        for (Tracked tracked : LIVE) {
            destroyQuietly(tracked, true);
        }
        LIVE.clear();
    }

    private static boolean runtimeAlive(Object executor) {
        try {
            Object runtime = getRuntimeMethod.invoke(executor);
            return runtime != null && Boolean.TRUE.equals(runtimeIsAliveMethod.invoke(runtime));
        } catch (Throwable t) {
            return false;
        }
    }

    private static void destroyQuietly(Tracked tracked, boolean force) {
        try {
            Object runtime = getRuntimeMethod.invoke(tracked.executor);
            if (runtime != null) {
                runtimeDestroyMethod.invoke(runtime, force);
            }
        } catch (Throwable t) {
            // Teardown-order safe: Photon may have freed its state already — dropping the
            // reference is the part that matters (QuasarSpawner.clearAttached pattern).
        }
    }

    /** Client tick sweep + disconnect reset (kept as an inner class so PhotonBridge itself
     *  never registers event handlers when the mod list lacks photon — sweeps no-op fast). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Sweep {
        private Sweep() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            clientTicks++;
            sweep();
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            destroyAll();
        }
    }

    // ------------------------------------------------------------------ dev/QA introspection

    /** Live executors currently tracked by the bridge (after the last sweep). */
    public static int liveExecutors() {
        return LIVE.size();
    }

    /**
     * How many of the live executors are entity-attached (PH-BOSS-A: the shard-ribbon
     * belt-and-braces gate — IDEAS-boss #5 skips new ribbons past a small cap).
     */
    public static int liveEntityExecutors() {
        int attached = 0;
        for (Tracked tracked : LIVE) {
            if (tracked.entity != null) {
                attached++;
            }
        }
        return attached;
    }

    /** How many of the live executors are loops started via {@link #spawnLoop}. */
    public static int liveLoops() {
        int loops = 0;
        for (Tracked tracked : LIVE) {
            if (tracked.loop) {
                loops++;
            }
        }
        return loops;
    }

    /** Executor-budget refusals this session. */
    public static int refusedCount() {
        return refusedCount;
    }

    /** Immutable snapshot of the session's missing/broken fx ids. */
    public static Set<ResourceLocation> missingFxIds() {
        return Set.copyOf(MISSING_FX);
    }

    /** Human-readable reflection state: UNRESOLVED / READY / DISABLED. */
    public static String stateName() {
        return switch (state) {
            case READY -> "READY";
            case DISABLED -> "DISABLED";
            default -> "UNRESOLVED";
        };
    }

    /** Dirty {@link TemplateHygiene} scrubs this session (healthy sessions: 0). */
    public static long hygieneDirtyScrubs() {
        return TemplateHygiene.dirtyScrubs;
    }

    /** Total live template links removed by {@link TemplateHygiene} (healthy: 0). */
    public static long hygieneLinksRemoved() {
        return TemplateHygiene.linksRemoved;
    }

    // ------------------------------------------------------------------ template hygiene

    /**
     * F-103 R2 — pre-spawn hygiene sweep over the SHARED {@code FXHelper.getFX(loc)}
     * template (the FX every {@code createRuntime()} spawn shallow-copies from).
     *
     * <p><b>Why (javap-verified against photon 2.1.5 / ldlib2 2.2.29):</b> a pristine
     * asset fresh from disk has NO live scene-graph state — every template
     * {@code Transform} has {@code parent() == null}, an empty live {@code children()}
     * list and no {@code getScene()}. If ANY code path ever awakens the cached templates
     * (historically {@code FX.createInternalRuntime()} in the old stormfx tuners; also
     * possible via Photon's own in-game editor), the poison self-perpetuates through the
     * NORMAL spawn path: {@code FXObject.copy(false)} runs
     * {@code Transform.copyTransformFrom(template, true, true)} which copies the LIVE
     * {@code parent(other.parent())}, and {@code Transform.addChildInternal} has no
     * duplicate check on the live {@code children} list — so every spawn grafts one stale
     * copy per object into the template hierarchy (silent leak), and any later
     * {@code setScene} cascade over that hierarchy floods one
     * {@code "Duplicate fx runtime object id … is replaced"} WARN per accumulated copy
     * ({@code FXRuntime.addSceneObjectInternal}). The round-1 tuner fix stopped the
     * poisoning; this sweep closes the remaining vector by GUARANTEEING the template is
     * pristine before every spawn — a poisoned session heals on the next spawn instead of
     * leaking forever.</p>
     *
     * <p><b>What it does</b> (only when dirty — the pristine probe is a handful of
     * reflective reads per spawn): strips every live child off each template transform
     * ({@code Transform.destroy()} detaches with the parent's live list; a belt-and-braces
     * {@code children().clear()} covers detach-refusing edge states), detaches templates
     * from any live parent ({@code destroy()} keeps their own persisted {@code _parentId}
     * and resets the {@code isValid} awake-latch — the exact fresh-from-disk state), pulls
     * them out of any stale scene map ({@code removeSceneObjectInternal} +
     * {@code setSceneInternal(null)}), and restores the persisted {@code _childrenId}
     * order list eroded by {@code removeChildInternal}. Shared {@code ParticleConfig}s
     * (the Channel-A tuner surface) are deliberately untouched.</p>
     *
     * <p><b>Probe:</b> every scrub logs
     * {@code "Photon template hygiene probe: <fx> liveParents=<p> liveChildren=<c>
     * liveScenes=<s>"} at DEBUG — the population measure for QA: all-zero on every line
     * means no accumulation; a dirty scrub additionally WARNs once per fx id. Fail-soft:
     * the first reflective surprise disables the sweep for the session (spawns proceed
     * exactly as before this class existed).</p>
     */
    private static final class TemplateHygiene {
        private static final int UNRESOLVED = 0;
        private static final int READY = 1;
        private static final int DISABLED = 2;
        private static int state = UNRESOLVED;
        private static Method getFxData;            // FX.getFxData()
        private static Method fxDataObjects;        // FXData.objects()
        private static Method objTransform;         // ISceneObject.transform()
        private static Method objGetScene;          // ISceneObject.getScene()
        private static Method objSetSceneInternal;  // ISceneObject.setSceneInternal(IScene)
        private static Method sceneRemoveInternal;  // IScene.removeSceneObjectInternal(ISceneObject)
        private static Method trParent;             // Transform.parent()
        private static Method trChildren;           // Transform.children() — the LIVE list
        private static Method trDestroy;            // Transform.destroy()
        private static Method trGetChildIds;        // Transform._getInternalChildID()
        private static Method trSetChildIds;        // Transform._setInternalChildID(List)

        /** Scrubs that actually had to clean something (healthy sessions: stays 0). */
        private static long dirtyScrubs;
        /** Total live links (parents + children + scenes) removed across all scrubs. */
        private static long linksRemoved;
        /** Fx ids already WARN-reported as dirty (one WARN per id per session). */
        private static final Set<ResourceLocation> WARNED_DIRTY = new HashSet<>();

        private TemplateHygiene() {}

        private static boolean resolve() {
            if (state != UNRESOLVED) {
                return state == READY;
            }
            try {
                Class<?> fxClass = Class.forName("com.lowdragmc.photon.client.fx.FX");
                Class<?> sceneObject = Class.forName(
                        "com.lowdragmc.lowdraglib2.editor.ui.sceneeditor.sceneobject.ISceneObject");
                Class<?> scene = Class.forName(
                        "com.lowdragmc.lowdraglib2.editor.ui.sceneeditor.sceneobject.IScene");
                Class<?> transform = Class.forName("com.lowdragmc.lowdraglib2.math.Transform");
                getFxData = fxClass.getMethod("getFxData");
                fxDataObjects = getFxData.getReturnType().getMethod("objects");
                objTransform = sceneObject.getMethod("transform");
                objGetScene = sceneObject.getMethod("getScene");
                objSetSceneInternal = sceneObject.getMethod("setSceneInternal", scene);
                sceneRemoveInternal = scene.getMethod("removeSceneObjectInternal", sceneObject);
                trParent = transform.getMethod("parent");
                trChildren = transform.getMethod("children");
                trDestroy = transform.getMethod("destroy");
                trGetChildIds = transform.getMethod("_getInternalChildID");
                trSetChildIds = transform.getMethod("_setInternalChildID", List.class);
                state = READY;
                return true;
            } catch (Throwable t) {
                disable(t);
                return false;
            }
        }

        /** Probes {@code fx}'s templates and scrubs any live scene-graph residue. */
        static void scrub(ResourceLocation fxId, Object fx) {
            if (state == DISABLED || !resolve()) {
                return;
            }
            try {
                List<?> objects = (List<?>) fxDataObjects.invoke(getFxData.invoke(fx));
                int liveParents = 0;
                int liveChildren = 0;
                int liveScenes = 0;
                for (Object object : objects) {
                    Object transform = objTransform.invoke(object);
                    if (trParent.invoke(transform) != null) {
                        liveParents++;
                    }
                    liveChildren += ((List<?>) trChildren.invoke(transform)).size();
                    if (objGetScene.invoke(object) != null) {
                        liveScenes++;
                    }
                }
                EclipseMod.LOGGER.debug(
                        "Photon template hygiene probe: {} liveParents={} liveChildren={} liveScenes={}",
                        fxId, liveParents, liveChildren, liveScenes);
                if (liveParents == 0 && liveChildren == 0 && liveScenes == 0) {
                    return; // pristine — the only state this probe should ever see
                }
                // Snapshot the persisted child-order ids FIRST: every detach below runs
                // removeChildInternal, which erodes the parent's _childrenId list.
                Object[] childIdSnapshots = new Object[objects.size()];
                for (int i = 0; i < objects.size(); i++) {
                    childIdSnapshots[i] =
                            trGetChildIds.invoke(objTransform.invoke(objects.get(i)));
                }
                // Pass A: strip every live child (grafted spawn copies AND awakened
                // template-to-template links — both only exist on a poisoned template).
                for (Object object : objects) {
                    Object transform = objTransform.invoke(object);
                    List<?> kids = (List<?>) trChildren.invoke(transform);
                    for (Object kid : new ArrayList<>(kids)) {
                        trDestroy.invoke(kid); // detach + reset the kid's awake-latch
                    }
                    kids.clear(); // belt-and-braces: destroy() skips !isValid parents
                }
                // Pass B: detach templates from any surviving live parent (e.g. a stale
                // internal-runtime root). destroy() keeps the template's own persisted
                // _parentId and resets isValid — the pristine fresh-from-disk state.
                for (Object object : objects) {
                    Object transform = objTransform.invoke(object);
                    if (trParent.invoke(transform) != null) {
                        trDestroy.invoke(transform);
                    }
                }
                // Pass C: pull templates out of any stale scene's object map.
                for (Object object : objects) {
                    Object scene = objGetScene.invoke(object);
                    if (scene != null) {
                        sceneRemoveInternal.invoke(scene, object);
                        objSetSceneInternal.invoke(object, (Object) null);
                    }
                }
                // Pass D: restore the persisted child-order ids eroded by the detaches.
                for (int i = 0; i < objects.size(); i++) {
                    trSetChildIds.invoke(objTransform.invoke(objects.get(i)),
                            childIdSnapshots[i]);
                }
                dirtyScrubs++;
                linksRemoved += liveParents + liveChildren + liveScenes;
                if (WARNED_DIRTY.add(fxId)) {
                    EclipseMod.LOGGER.warn(
                            "Photon template hygiene: {} had live scene-graph state on the shared "
                                    + "FX cache (parents={}, children={}, scenes={}) — scrubbed "
                                    + "before spawn. Some code path awakened the cached templates "
                                    + "(FX.createInternalRuntime on the shared cache is forbidden, "
                                    + "see FX_RESPAWN_HYGIENE_REPORT.md).",
                            fxId, liveParents, liveChildren, liveScenes);
                }
            } catch (Throwable t) {
                disable(t);
            }
        }

        private static void disable(Throwable t) {
            if (state != DISABLED) {
                state = DISABLED;
                EclipseMod.LOGGER.debug(
                        "Photon template hygiene sweep disabled for the session", t);
            }
        }
    }

    // ------------------------------------------------------------------ reflection

    /** Lazily resolves the reflection handles once. @return {@code true} when READY. */
    private static boolean resolve() {
        if (state == READY) {
            return true;
        }
        if (state == DISABLED) {
            return false;
        }
        synchronized (PhotonBridge.class) {
            if (state != UNRESOLVED) {
                return state == READY;
            }
            try {
                Class<?> fxHelper = Class.forName("com.lowdragmc.photon.client.fx.FXHelper");
                Class<?> fxClass = Class.forName("com.lowdragmc.photon.client.fx.FX");
                Class<?> executorBase = Class.forName("com.lowdragmc.photon.client.fx.FXEffectExecutor");
                Class<?> blockExecutor = Class.forName("com.lowdragmc.photon.client.fx.BlockEffectExecutor");
                Class<?> entityExecutor = Class.forName("com.lowdragmc.photon.client.fx.EntityEffectExecutor");
                Class<?> autoRotate = Class.forName("com.lowdragmc.photon.client.fx.EntityEffectExecutor$AutoRotate");
                Class<?> runtime = Class.forName("com.lowdragmc.photon.client.fx.FXRuntime");
                getFxMethod = fxHelper.getMethod("getFX", ResourceLocation.class);
                blockExecutorCtor = blockExecutor.getConstructor(fxClass, Level.class, BlockPos.class);
                blockStartMethod = blockExecutor.getMethod("start");
                entityExecutorCtor = entityExecutor.getConstructor(fxClass, Level.class, Entity.class, autoRotate);
                entityStartMethod = entityExecutor.getMethod("start");
                Object[] autoRotateRaw = autoRotate.getEnumConstants();
                setOffsetMethod = executorBase.getMethod("setOffset", Vector3f.class);
                setRotationMethod = executorBase.getMethod("setRotation", Quaternionf.class);
                setScaleMethod = executorBase.getMethod("setScale", Vector3f.class);
                setDelayMethod = executorBase.getMethod("setDelay", int.class);
                setAllowMultiMethod = executorBase.getMethod("setAllowMulti", boolean.class);
                getRuntimeMethod = executorBase.getMethod("getRuntime");
                runtimeIsAliveMethod = runtime.getMethod("isAlive");
                runtimeDestroyMethod = runtime.getMethod("destroy", boolean.class);
                if (autoRotateRaw == null || autoRotateRaw.length == 0) {
                    throw new IllegalStateException("AutoRotate enum shape changed: "
                            + java.util.Arrays.toString(autoRotateRaw));
                }
                // EVAL-V6-PHOTON §7.5: the public AUTO_ROTATE_* ids map to constants BY
                // NAME, never by raw ordinal — a link-compatible Photon that inserts,
                // reorders or renames constants degrades that mode to NONE instead of
                // reaching READY and silently misorienting entity effects.
                Object none = autoRotateByName(autoRotateRaw, "NONE", autoRotateRaw[0]);
                autoRotateConstants = new Object[] {
                        none,
                        autoRotateByName(autoRotateRaw, "FORWARD", none),
                        autoRotateByName(autoRotateRaw, "LOOK", none),
                        autoRotateByName(autoRotateRaw, "XROT", none)};
                state = READY;
                EclipseMod.LOGGER.info("Photon detected — flagship-effect enhancement layer active");
                return true;
            } catch (Throwable t) {
                disable(t);
                return false;
            }
        }
    }

    /**
     * Resolves one {@code AutoRotate} constant by enum name; a missing/renamed constant
     * (or any reflective surprise) falls back to {@code fallback} — the NONE degrade.
     */
    private static Object autoRotateByName(Object[] constants, String name, Object fallback) {
        try {
            for (Object constant : constants) {
                if (constant instanceof Enum<?> value && value.name().equals(name)) {
                    return constant;
                }
            }
        } catch (Throwable t) {
            // fall through — the caller's fallback is the degrade path
        }
        return fallback;
    }

    private static void missing(ResourceLocation fxId) {
        if (MISSING_FX.add(fxId)) {
            EclipseMod.LOGGER.info(
                    "Photon is loaded but assets/{}/fx/{}.fx is absent — cue stays Quasar-only "
                            + "(author it via tools/photon/fxlib.py or Photon's editor, see docs/BUNDLING.md)",
                    fxId.getNamespace(), fxId.getPath());
        }
    }

    private static void disable(Throwable t) {
        if (state != DISABLED) {
            state = DISABLED;
            EclipseMod.LOGGER.warn(
                    "Photon bridge disabled for this session (API mismatch or load failure)", t);
        }
    }
}
