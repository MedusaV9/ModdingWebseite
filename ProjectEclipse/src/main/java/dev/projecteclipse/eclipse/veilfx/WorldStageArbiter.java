package dev.projecteclipse.eclipse.veilfx;

import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * V7-SIGCOMP — the WORLD-STAGE TOKEN (FX-STYLE-GUIDE.md §6.1): {@code CenterStageArbiter}'s
 * outdoor sibling for the §5 signature compositions. HUD hero moments can queue; world
 * moments cannot (a boss dies <i>now</i>), so this token <b>demotes instead of
 * deferring</b>: an S-class composition that fails {@link #tryClaim} plays its reduced
 * form (Photon hero layer dropped for the Quasar sketch, no post spike, no light claim) —
 * it never waits and it is NEVER dropped entirely.
 *
 * <p><b>Scope:</b> one token per {@value #BUBBLE_RADIUS}-block bubble around the camera —
 * world FX outside the bubble never contest (distance already de-emphasizes them) and are
 * always granted the full form. Claims within {@value #SAME_MOMENT_RADIUS} blocks of the
 * live holder's anchor are the SAME fictional moment (layers of one composition, e.g. the
 * altar ceremony's own ring under the Sanctum Bloom claim) and also pass in full without
 * stealing the lease.</p>
 *
 * <p><b>Classes</b> (§6.1): S-MAX (Crown Verdict) preempts a held S token — the only legal
 * preemption; a boss death outranks weather. S claims normally. A-class accents and
 * B-class beds never claim (register them anyway for documentation: {@link #gateCue}
 * passes them through untouched).</p>
 *
 * <p><b>Sound discipline</b> (§6.5): {@link #tryStingSlot} enforces ONE sting per
 * {@value #STING_WINDOW_TICKS}t across all compositions — refused callers drop to their
 * tail alias or stay silent. UI-side stings that bypass this class (e.g. the awards
 * roulette sting) should call {@link #noteSting} so world compositions right behind them
 * stay disciplined.</p>
 *
 * <p>Client tick thread only; state clears on level unload; the tick-counted lease is the
 * failsafe against a crashed owner (the CenterStage contract). Demotions log once per cue
 * id per session (diagnostics, not spam).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WorldStageArbiter {
    /** §6.1 composition classes. Only S / S-MAX contest the token. */
    public enum StageClass { S_MAX, S, A, B }

    /** Soft-gate verdict: DEMOTED = play the reduced form (never a drop). */
    public enum Verdict { FULL, DEMOTED }

    /** Token scope: world FX beyond this camera distance never contest (§6.1). */
    public static final double BUBBLE_RADIUS = 24.0D;
    /** Claims this close to the live holder's anchor read as the same fictional moment. */
    private static final double SAME_MOMENT_RADIUS = 4.0D;
    /** One sting per this many ticks, across ALL compositions (§6.5). */
    public static final int STING_WINDOW_TICKS = 40;
    /** Failsafe cap: no lease may outlive this many ticks whatever a claimant passes. */
    private static final int MAX_LEASE_TICKS = 400;

    /** Per-cue stage class + lease length for the {@link #gateCue} soft gate. */
    private record CueSpec(StageClass stageClass, int leaseTicks) {}

    /** Registered cue classes ({@code FxCues} ids and Quasar-payload emitter ids). */
    private static final Map<ResourceLocation, CueSpec> CUE_SPECS = new ConcurrentHashMap<>();
    /** Cue ids whose demotion was already logged this session (log-once diagnostics). */
    private static final Set<ResourceLocation> LOGGED_DEMOTIONS = ConcurrentHashMap.newKeySet();

    // Client tick thread only.
    private static String owner;
    private static Vec3 ownerPos = Vec3.ZERO;
    private static boolean ownerMax;
    private static int leaseTicks;
    /** Clock tick of the last granted sting slot ({@link Integer#MIN_VALUE} = none yet). */
    private static int lastStingTick = Integer.MIN_VALUE;
    /** Pause-frozen arbiter clock (advances with unpaused client ticks). */
    private static int clock;

    private WorldStageArbiter() {}

    // ------------------------------------------------------------------ registration

    /**
     * Registers the stage class for one cue/emitter id so the {@link #gateCue} soft gate
     * in {@code PhotonFxRegistry.dispatch} and the Quasar payload path can arbitrate it.
     * A / B classes are pass-through by design (accents play freely, beds never claim).
     */
    public static void registerCue(ResourceLocation id, StageClass stageClass, int leaseTicks) {
        CUE_SPECS.put(id, new CueSpec(stageClass, leaseTicks));
    }

    // ------------------------------------------------------------------ token

    /**
     * Claims the world stage for {@code ticks} around {@code pos} (renewing when
     * {@code id} already owns it). {@code sMax = true} is the S-MAX tier: it forcibly
     * releases a held S token (§6.1 — the only legal preemption). Returns {@code false}
     * when another moment holds the frame — the caller MUST then play its demoted form
     * immediately (never queue, never drop).
     */
    public static boolean tryClaim(String id, Vec3 pos, int ticks, boolean sMax) {
        if (!insideBubble(pos)) {
            return true; // outside the 24-block bubble: never contests, nothing recorded
        }
        if (owner != null && !owner.equals(id)) {
            if (!sMax || ownerMax) {
                return false;
            }
            EclipseMod.LOGGER.debug("WorldStageArbiter: S-MAX {} preempts held token {}", id, owner);
        }
        owner = id;
        ownerPos = pos;
        ownerMax = sMax;
        leaseTicks = Math.min(Math.max(1, ticks), MAX_LEASE_TICKS);
        return true;
    }

    /** Whether {@code id} holds the stage right now (mid-composition re-checks). */
    public static boolean holdsStage(String id) {
        return owner != null && owner.equals(id);
    }

    /** Releases the stage if {@code id} owns it (a stranger's release is a no-op). */
    public static void release(String id) {
        if (owner != null && owner.equals(id)) {
            owner = null;
            ownerMax = false;
            leaseTicks = 0;
        }
    }

    // ------------------------------------------------------------------ soft gate

    /**
     * The dispatch soft gate ({@code PhotonFxRegistry.dispatchInternal} + the
     * {@code EclipsePayloads.handleQuasar} Photon-enhancement seam): resolves the cue's
     * registered class and arbitrates. Unregistered / A / B cues, cues outside the camera
     * bubble and same-moment layers always pass FULL. A DEMOTED verdict means "play the
     * reduced form" — Photon hero leg dropped for the Quasar sketch — never a drop.
     */
    public static Verdict gateCue(ResourceLocation id, Vec3 pos) {
        CueSpec spec = CUE_SPECS.get(id);
        if (spec == null || spec.stageClass() == StageClass.A || spec.stageClass() == StageClass.B) {
            return Verdict.FULL;
        }
        if (tryClaim("cue:" + id, pos, spec.leaseTicks(), spec.stageClass() == StageClass.S_MAX)) {
            return Verdict.FULL;
        }
        if (owner != null && pos.distanceToSqr(ownerPos) <= SAME_MOMENT_RADIUS * SAME_MOMENT_RADIUS) {
            return Verdict.FULL; // co-located layer of the holder's own moment
        }
        logDemotion(id);
        return Verdict.DEMOTED;
    }

    /** Log-once demotion diagnostic for manual (non-{@link #gateCue}) claimants. */
    public static void logDemotion(ResourceLocation id) {
        if (LOGGED_DEMOTIONS.add(id)) {
            EclipseMod.LOGGER.info("WorldStageArbiter: {} demoted (stage held by {}) — playing "
                    + "reduced form; further demotions of this id stay silent", id, owner);
        }
    }

    // ------------------------------------------------------------------ sting discipline

    /**
     * Claims the one-sting-per-{@value #STING_WINDOW_TICKS}t slot (§6.5). Refused callers
     * play their tail alias (or stay silent) instead of their bolded sting.
     */
    public static boolean tryStingSlot() {
        if (lastStingTick != Integer.MIN_VALUE && clock - lastStingTick < STING_WINDOW_TICKS) {
            return false;
        }
        lastStingTick = clock;
        return true;
    }

    /** Marks the sting window consumed by a sting played outside this class (UI stings). */
    public static void noteSting() {
        lastStingTick = clock;
    }

    // ------------------------------------------------------------------ tick / reset

    /** Lease countdown failsafe; explicit {@link #release} is the normal path. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            owner = null;
            ownerMax = false;
            leaseTicks = 0;
            lastStingTick = Integer.MIN_VALUE;
            return;
        }
        if (minecraft.isPaused()) {
            return; // claimants freeze while paused — lease and sting window freeze too
        }
        clock++;
        if (owner != null && --leaseTicks <= 0) {
            owner = null;
            ownerMax = false;
        }
    }

    private static boolean insideBubble(Vec3 pos) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            return false;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        return camera.distanceToSqr(pos) <= BUBBLE_RADIUS * BUBBLE_RADIUS;
    }
}
