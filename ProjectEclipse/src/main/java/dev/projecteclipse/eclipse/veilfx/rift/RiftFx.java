package dev.projecteclipse.eclipse.veilfx.rift;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import foundry.veil.api.quasar.particle.ParticleEmitter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client-side registry + lifecycle of dimensional <b>rift tears</b> (P2 R17 + the W7/W9
 * structure/reveal beats). The two entry points below are the FROZEN handlers dispatched by
 * {@code network/fx/FxPayloads} for the {@code eclipse:fx/rift_open} / {@code
 * eclipse:fx/rift_close} events — signatures must not change (P5-W9's xbox portal and
 * P2-W7's structure drops send those payloads):
 * <ul>
 *   <li>{@link #openRift(Vec3, Vec3, float, int, int)} — {@code pos} = tear center,
 *       {@code normal} = tear plane normal ({@code FxPayloads} passes {@code (0,1,0)};
 *       PORTAL-style rifts re-orient themselves upright, see below), {@code width} = full
 *       tear diameter in blocks, {@code durationTicks} = auto-close delay ({@code 0} = stay
 *       open until {@link #closeRift}), {@code style} = {@link #STYLE_STRUCTURE} /
 *       {@link #STYLE_PORTAL} / {@link #STYLE_BACKROOMS}.</li>
 *   <li>{@link #closeRift(Vec3)} — collapses the rift nearest to {@code pos} (tolerance
 *       {@code max(4, width)} blocks) over {@value #CLOSE_TICKS} ticks.</li>
 * </ul>
 *
 * <p>Each rift is a seeded star-polygon tear ({@value #MIN_ARMS}&ndash;{@value #MAX_ARMS}
 * arms, arm lengths eased out over {@value #OPEN_TICKS} ticks) rendered by
 * {@link RiftRenderer} (world-space geometry — deliberately NOT Iris-gated, it is the
 * shaderpack fallback per §7), plus:</p>
 * <ul>
 *   <li>an {@code eclipse:rift_spark} loop emitter that walks the tear rim every client
 *       tick (edge crackle),</li>
 *   <li>for portal-like styles ({@link #STYLE_PORTAL}/{@link #STYLE_BACKROOMS}): an
 *       {@code eclipse:portal_surface_motes} loop emitter at the center (motes orbit-trailed
 *       + sucked inward via reverse {@code veil:vortex} + {@code veil:point_attractor}),</li>
 *   <li>a distance-scaled {@link TransitionFx#glitchPulse(float, int)} screen pulse
 *       (≤ {@value #MAX_PULSE} per R11) and the {@code event.rift_open} crackle sound.</li>
 * </ul>
 *
 * <p><b>Portal orientation:</b> the FX payload carries no plane normal, so W1's dispatch
 * hard-codes up. A flat-lying portal reads wrong, so when the style is portal-like and
 * the normal is (near) vertical, the rift re-orients to an upright plane facing the local
 * camera at open time (frozen thereafter; falls back to +Z with no camera). STRUCTURE rifts
 * keep the up normal — they open flat in the sky above the build site (R11).</p>
 *
 * <p><b>FXTEAM-RIFT additions</b> (see {@code docs/plans_v3/plans_v5/fxteams/RIFT.md}):</p>
 * <ul>
 *   <li><b>Backrooms mapping</b> — C18's reserved style byte {@value #STYLE_BACKROOMS} now
 *       renders as the upright portal star in the WAX-GOLD palette (per-rift hot/mid/dim
 *       tint triple picked at construction; every other style keeps the violet read).</li>
 *   <li><b>Entry moment</b> — portal-like rifts watch for any player crossing the star
 *       ({@code width·}{@value Rift#ENTRY_RADIUS_FRACTION} of the center, 3 s per-rift
 *       cooldown): iris-open flash + streamers in {@link RiftRenderer}, a client-local
 *       {@code event.rift_whoosh}, one extra rim-spark burst, and a small glitch pulse
 *       when the entrant is the local player.</li>
 *   <li><b>Delivery surge</b> — an {@code openRift} that REPLACES a live STRUCTURE rift
 *       is exactly {@code StructureFlightFx}'s delivery re-open (the client-visible
 *       signature of "pieces are about to launch"). The new rift runs a surge:
 *       {@value Rift#SURGE_INHALE_TICKS} ticks of the motes emitter parked at the mouth
 *       (sparks visibly SUCKED IN) plus one {@code map_expand_materialize} burst every
 *       {@value Rift#SURGE_BURST_PERIOD} ticks for {@value Rift#SURGE_BURST_TICKS} ticks —
 *       the same cadence the server launches piece batches on, so each launch reads as a
 *       spark burst OUT of the mouth. All surge spawns ride the SEQUENCE channel;
 *       {@code reducedFx} skips the inhale loop and halves the burst cadence.</li>
 * </ul>
 *
 * <p><b>VEIL-REPASS-2:</b> each delivery launch burst also anchors {@link
 * Rift#recoilScale} — the WHOLE tear compresses {@value Rift#RECOIL_AMOUNT} at the burst
 * tick and rebounds over {@value Rift#RECOIL_TICKS} ticks (the renderer multiplies its
 * open scale), so the launch cadence reads as the rift pumping its pieces out.</p>
 *
 * <p>Lifecycle safety: at most {@value #MAX_RIFTS} concurrent rifts (oldest evicted);
 * re-opening within half a width of a live rift replaces it (double-send/resync safe);
 * rifts die instantly on dimension change (their emitters die with the level) and on
 * logout. Loop-emitter handles are managed exactly like {@code LimboAmbience}'s motes:
 * kept, pruned when Veil removes them, {@code remove()}d when the rift closes.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RiftFx {
    /** Structure-drop style (R11): bare tear, no portal surface. */
    public static final int STYLE_STRUCTURE = 0;
    /** Xbox-event portal style (R17): tear + elliptical parallax portal surface + motes. */
    public static final int STYLE_PORTAL = 1;
    /**
     * Backrooms portal style — C18's reserved coordinate ({@code BackroomsPortal.
     * RIFT_STYLE_BACKROOMS}), now mapped: the upright portal star in the wax-gold palette.
     */
    public static final int STYLE_BACKROOMS = 2;

    /** Arm-length ease-out length when opening (R17: "arm length ease-out over 20 ticks"). */
    static final int OPEN_TICKS = 20;
    /** Collapse length when closing (R11: "rift closes 30 ticks"). */
    static final int CLOSE_TICKS = 30;
    static final int MIN_ARMS = 8;
    static final int MAX_ARMS = 14;

    /** Concurrent rift cap — the renderer's ≤400-tri budget is per rift, this bounds the sum. */
    private static final int MAX_RIFTS = 8;
    private static final float MIN_WIDTH = 1.5F;
    /**
     * RIFT-FX: raised 48 → 72 (user: "not big enough"). Large-footprint deliveries
     * (village/mansion/ancient city) actually reach their server-computed adaptive width
     * now instead of clamping; the renderer's per-rift geometry budget is width-invariant
     * (fixed arm count), and the volumetric pass ({@link RiftVolumeFx}) scales analytically.
     */
    private static final float MAX_WIDTH = 72.0F;
    /** Screen-glitch pulse ceiling (R11 freezes "rift_glitch pulse ≤ 0.5"). */
    private static final float MAX_PULSE = 0.5F;
    /** Full-strength pulse/sound radius; both fade to zero at {@value #PULSE_FALLOFF_BLOCKS}. */
    private static final double PULSE_FULL_BLOCKS = 16.0D;
    private static final double PULSE_FALLOFF_BLOCKS = 64.0D;
    /** Re-try cadence for budget-refused loop emitters (once a second, never per-tick hammering). */
    private static final int EMITTER_RETRY_TICKS = 20;
    /**
     * Tear width the portal iris/loop {@code .fx} assets are authored for
     * ({@code tools/photon/events_fx.py PORTAL_WIDTH} — both portal senders broadcast
     * {@code FX_RIFT_OPEN a=5.0}); other widths get {@code setScale(width / this)}.
     */
    private static final float PORTAL_FX_AUTHORED_WIDTH = 5.0F;

    // --- v2 ambient corruption feed (GLITCH team → eclipse:rift_glitch RiftAmount/RiftCenter) ---
    /** Ambient corruption is full within this many blocks of a tear center (plus width/2). */
    private static final double AMBIENT_FULL_BLOCKS = 6.0D;
    /** …and fades to zero by this many (plus width/2). */
    private static final double AMBIENT_FALLOFF_BLOCKS = 26.0D;
    /** Ambient ceiling: standing at a tear is a simmer, never a transition-grade glitch. */
    private static final float MAX_AMBIENT = 0.6F;

    private static final ResourceLocation RIFT_SPARK_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_spark");
    private static final ResourceLocation PORTAL_MOTES_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "portal_surface_motes");
    /** Delivery-surge launch bursts (FXTEAM-RIFT): the materialize twinkle, at the mouth. */
    private static final ResourceLocation MATERIALIZE_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "map_expand_materialize");

    /** Live rifts, oldest first. Mutated only on the client main thread (payloads + tick). */
    private static final List<Rift> RIFTS = new ArrayList<>(MAX_RIFTS);

    // --- PH-IMPROVE-2 (IDEAS-world #6a Option B): end-crack glow suppression ---
    /**
     * Positions where the {@code eclipse:end_crack_bleed} Photon leg just played
     * ({@code WorldPhotonFxRows} records them via {@link #suppressStructureGlow}): the
     * {@code FX_RIFT_OPEN} arriving right behind the cue (same server tick, one line later
     * in {@code EndShatterSequence}) skips its generic {@code EXPANSION_RIFT_GLOW} for
     * that tear — the bleed IS that tear's Photon layer (REPLACE-by-suppression; the tear
     * geometry, sparks, pulse and sound all stay). Entries expire after
     * {@value #GLOW_SUPPRESS_WINDOW_TICKS}t so a dropped rift-open can never leak a
     * suppression onto an unrelated future tear. Client main thread only.
     */
    private static final List<GlowSuppression> GLOW_SUPPRESSIONS = new ArrayList<>(4);
    /** Cue pos → rift-open pos match tolerance (both senders use the same flash Vec3). */
    private static final double GLOW_SUPPRESS_TOLERANCE = 4.0D;
    /** Freshness window — the paired payloads land on the same client tick in practice. */
    private static final int GLOW_SUPPRESS_WINDOW_TICKS = 20;

    private record GlowSuppression(Vec3 pos, int tick) {}

    /**
     * Client tick counter for rift animation. {@code EclipseFxState.clientTicks()} is
     * package-private to {@code veilfx}, so this subpackage keeps its own counter off the
     * same event — the two advance in lockstep.
     */
    private static int ticks;

    private RiftFx() {}

    // ------------------------------------------------------------------ frozen entry points

    /**
     * Opens (or replaces) a rift tear. FROZEN signature — called by {@code FxPayloads} for
     * {@code eclipse:fx/rift_open} with {@code normal = (0,1,0)}, {@code durationTicks = 0}
     * (stay open until {@link #closeRift}) and {@code style = (int) b}.
     */
    public static void openRift(Vec3 pos, Vec3 normal, float width, int durationTicks, int style) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            return;
        }
        width = Mth.clamp(width <= 0.0F ? 6.0F : width, MIN_WIDTH, MAX_WIDTH);

        // Double-send/login-resync safe: an open on top of a live rift replaces it silently.
        Rift existing = findNearest(pos, Math.max(2.0D, width * 0.5D), true);
        // FXTEAM-RIFT: a STRUCTURE tear replaced by another STRUCTURE open is the delivery
        // re-open of StructureFlightFx (adaptive-width surge) — the only sender that stacks
        // opens on a live tear. The replacement rift plays the inhale/launch-burst surge.
        boolean surge = existing != null && !existing.closing()
                && existing.style == STYLE_STRUCTURE && style == STYLE_STRUCTURE;
        if (existing != null) {
            dispose(existing);
            RIFTS.remove(existing);
        }
        while (RIFTS.size() >= MAX_RIFTS) {
            dispose(RIFTS.remove(0));
        }

        Rift rift = new Rift(level.dimension(), pos, orientedNormal(minecraft, pos, normal, style),
                width, durationTicks, style, ticks);
        if (surge) {
            rift.surgeTick = ticks;
        }
        RIFTS.add(rift);

        // D12 + PH-EVENTS (IDEAS-events #5a): optional Photon layer over the tear (no-op
        // without the photon mod). Style branch sanctioned by INTEGRATION.md §3.5 law 4
        // (openRift stays a non-registry seam): STRUCTURE tears keep the frozen glow;
        // portal styles open with the palette-matched iris pop instead, executor-scaled
        // from the authored width to this tear's width. allowMulti stays false: a resync
        // re-open replays the iris only for the (late-joining) client that received it.
        if (rift.portalLike) {
            float irisScale = width / PORTAL_FX_AUTHORED_WIDTH;
            PhotonBridge.spawn(style == STYLE_BACKROOMS
                            ? PhotonBridge.PORTAL_IRIS_OPEN_BACKROOMS
                            : PhotonBridge.PORTAL_IRIS_OPEN_XBOX,
                    pos, PhotonBridge.SpawnOptions.DEFAULT
                            .withScale(irisScale, irisScale, irisScale));
        } else if (!consumeGlowSuppression(pos)) {
            // PH-IMPROVE-2: skipped only when the end_crack_bleed leg just played here —
            // see GLOW_SUPPRESSIONS. Every other structure tear keeps the frozen glow.
            PhotonBridge.spawn(PhotonBridge.EXPANSION_RIFT_GLOW, pos);
        }

        float falloff = distanceFalloff(minecraft, pos);
        TransitionFx.glitchPulse(Math.min(MAX_PULSE, (0.28F + width * 0.012F) * falloff), 14);
        if (falloff > 0.0F) {
            level.playLocalSound(pos.x, pos.y, pos.z, EclipseSounds.EVENT_RIFT_OPEN.get(),
                    SoundSource.BLOCKS, 0.55F + 0.45F * falloff, 0.95F + level.random.nextFloat() * 0.1F, false);
        }
    }

    /**
     * PH-IMPROVE-2 seam for {@code WorldPhotonFxRows}' {@code CUE_END_CRACK} leg (client
     * main thread): records that the end-crack light-bleed just played at {@code pos} so
     * the paired {@code FX_RIFT_OPEN} skips its generic glow — see
     * {@link #GLOW_SUPPRESSIONS}. Call ONLY after the Photon spawn actually played:
     * photon-less/refused clients must keep the full shipped rift stack.
     */
    public static void suppressStructureGlow(Vec3 pos) {
        GLOW_SUPPRESSIONS.add(new GlowSuppression(pos, ticks));
    }

    /** Consumes (and prunes) a fresh in-tolerance suppression entry for {@code pos}. */
    private static boolean consumeGlowSuppression(Vec3 pos) {
        boolean hit = false;
        for (int i = GLOW_SUPPRESSIONS.size() - 1; i >= 0; i--) {
            GlowSuppression entry = GLOW_SUPPRESSIONS.get(i);
            if (ticks - entry.tick() > GLOW_SUPPRESS_WINDOW_TICKS) {
                GLOW_SUPPRESSIONS.remove(i);
            } else if (!hit && entry.pos().distanceToSqr(pos)
                    <= GLOW_SUPPRESS_TOLERANCE * GLOW_SUPPRESS_TOLERANCE) {
                GLOW_SUPPRESSIONS.remove(i);
                hit = true;
            }
        }
        return hit;
    }

    /**
     * Starts the {@value #CLOSE_TICKS}-tick collapse of the rift nearest to {@code pos}
     * (tolerance {@code max(4, width)} blocks). FROZEN signature — called by
     * {@code FxPayloads} for {@code eclipse:fx/rift_close}. A miss is a debug no-op:
     * close events for already-evicted/expired rifts are expected during resyncs.
     */
    public static void closeRift(Vec3 pos) {
        Rift rift = findNearest(pos, -1.0D, false);
        if (rift == null) {
            EclipseMod.LOGGER.debug("rift_close at {} matched no open rift", pos);
            return;
        }
        beginClose(rift);
    }

    // ------------------------------------------------------------------ renderer/tick access

    /** Live rifts for {@link RiftRenderer} (render-thread read only; do not mutate). */
    static List<Rift> rifts() {
        return RIFTS;
    }

    /** Shared animation clock ({@code ticks + partialTick}). */
    static float timeNow(float partialTick) {
        return ticks + partialTick;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        ticks++;
        if (RIFTS.isEmpty()) {
            TransitionFx.setRiftAmbient(0.0F, null); // ambient corruption feed winds down
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            clearAll();
            return;
        }
        for (int i = RIFTS.size() - 1; i >= 0; i--) {
            Rift rift = RIFTS.get(i);
            if (rift.dimension != level.dimension() || rift.doneClosing(ticks)) {
                dispose(rift);
                RIFTS.remove(i);
                continue;
            }
            if (!rift.closing() && rift.durationTicks > 0 && ticks - rift.openTick >= rift.durationTicks) {
                beginClose(rift);
                continue;
            }
            rift.tickEmitters(level, ticks);
            rift.tickEntryWatch(level, ticks);
        }
        publishAmbient();
    }

    /**
     * v2 ambient corruption feed (GLITCH team): the strongest live rift is published once
     * per tick to {@link TransitionFx#setRiftAmbient} — the {@code eclipse:rift_glitch}
     * {@code RiftAmount}/{@code RiftCenter} layers (voxel-sort streaks, mirror shards,
     * time-jitter echo). Distance falloff is full within {@value #AMBIENT_FULL_BLOCKS}
     * blocks of the tear center plus width/2, zero by {@value #AMBIENT_FALLOFF_BLOCKS}
     * plus width/2, scaled by the tear's open amount (opening ramps in, collapse winds
     * down) and capped at {@value #MAX_AMBIENT}. Forced 0 under {@code reducedFx}: the
     * ambient layers are non-essential by definition — the functional transition envelope
     * (GlitchAmount/FadeAmount) is a separate feed and is untouched by this.
     */
    private static void publishAmbient() {
        if (EclipseClientConfig.reducedFx()) {
            TransitionFx.setRiftAmbient(0.0F, null);
            return;
        }
        Vec3 camera = Minecraft.getInstance().gameRenderer.getMainCamera().getPosition();
        Rift best = null;
        float bestAmount = 0.0F;
        for (int i = 0; i < RIFTS.size(); i++) {
            Rift rift = RIFTS.get(i);
            double full = AMBIENT_FULL_BLOCKS + rift.width * 0.5D;
            double dist = camera.distanceTo(rift.pos);
            float falloff = (float) Mth.clamp(
                    1.0D - (dist - full) / (AMBIENT_FALLOFF_BLOCKS - AMBIENT_FULL_BLOCKS),
                    0.0D, 1.0D);
            float amount = falloff * rift.openAmount(ticks) * MAX_AMBIENT;
            if (amount > bestAmount) {
                bestAmount = amount;
                best = rift;
            }
        }
        TransitionFx.setRiftAmbient(bestAmount, best != null ? best.pos : null);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clearAll();
    }

    private static void beginClose(Rift rift) {
        rift.startClose(ticks);
        Minecraft minecraft = Minecraft.getInstance();
        float falloff = distanceFalloff(minecraft, rift.pos);
        TransitionFx.glitchPulse(Math.min(MAX_PULSE, 0.22F * falloff + 0.05F), 12);
        ClientLevel level = minecraft.level;
        if (level != null && falloff > 0.0F) {
            // Reverse-crackle read on the same registered sound — §3.5's frozen sound list
            // has no dedicated close event (the W7 slam beat is the sender's job).
            level.playLocalSound(rift.pos.x, rift.pos.y, rift.pos.z, EclipseSounds.EVENT_RIFT_OPEN.get(),
                    SoundSource.BLOCKS, 0.45F + 0.35F * falloff, 0.65F, false);
        }
    }

    /**
     * Nearest live rift to {@code pos}; {@code tolerance < 0} uses each rift's own
     * {@code max(4, width)}. {@code includeClosing = false} skips rifts already collapsing
     * (a close event must never be swallowed by a neighbor that is already closing).
     */
    @Nullable
    private static Rift findNearest(Vec3 pos, double tolerance, boolean includeClosing) {
        Rift best = null;
        double bestDistSq = Double.MAX_VALUE;
        for (int i = 0; i < RIFTS.size(); i++) {
            Rift rift = RIFTS.get(i);
            if (!includeClosing && rift.closing()) {
                continue;
            }
            double limit = tolerance >= 0.0D ? tolerance : Math.max(4.0D, rift.width);
            double distSq = rift.pos.distanceToSqr(pos);
            if (distSq <= limit * limit && distSq < bestDistSq) {
                bestDistSq = distSq;
                best = rift;
            }
        }
        return best;
    }

    /**
     * Portal-like rifts arriving with the payload's default up-normal are stood upright
     * facing the local camera at open time (see class javadoc); every other normal passes
     * through normalized. Zero-length normals fall back to up.
     */
    private static Vec3 orientedNormal(Minecraft minecraft, Vec3 pos, Vec3 normal, int style) {
        if ((style == STYLE_PORTAL || style == STYLE_BACKROOMS)
                && Math.abs(normal.y) > 0.9D * normal.length()) {
            Vec3 toCamera = minecraft.gameRenderer.getMainCamera().getPosition().subtract(pos);
            Vec3 flat = new Vec3(toCamera.x, 0.0D, toCamera.z);
            return flat.lengthSqr() > 1.0E-4D ? flat.normalize() : new Vec3(0.0D, 0.0D, 1.0D);
        }
        return normal.lengthSqr() > 1.0E-6D ? normal.normalize() : new Vec3(0.0D, 1.0D, 0.0D);
    }

    /** 1 within {@value #PULSE_FULL_BLOCKS} blocks of the camera, 0 beyond {@value #PULSE_FALLOFF_BLOCKS}. */
    private static float distanceFalloff(Minecraft minecraft, Vec3 pos) {
        double dist = minecraft.gameRenderer.getMainCamera().getPosition().distanceTo(pos);
        return (float) Mth.clamp(1.0D - (dist - PULSE_FULL_BLOCKS) / (PULSE_FALLOFF_BLOCKS - PULSE_FULL_BLOCKS),
                0.0D, 1.0D);
    }

    private static void dispose(Rift rift) {
        rift.removeEmitters();
    }

    private static void clearAll() {
        for (int i = 0; i < RIFTS.size(); i++) {
            RIFTS.get(i).removeEmitters();
        }
        RIFTS.clear();
        GLOW_SUPPRESSIONS.clear();
    }

    // ------------------------------------------------------------------ rift state

    /**
     * One live tear. Geometry inputs are precomputed at construction (seeded star polygon +
     * orthonormal plane basis stored as primitive floats) so {@link RiftRenderer} runs with
     * zero per-frame allocations.
     */
    static final class Rift {
        /** Entry trigger distance from the star center, as a fraction of the tear width. */
        static final float ENTRY_RADIUS_FRACTION = 0.35F;
        /** Renderer window of the iris-open flash after {@link #entryFlashTick}. */
        static final int ENTRY_FLASH_TICKS = 12;
        /** Min ticks between entry flashes of one rift (a conga line must not strobe it). */
        static final int ENTRY_COOLDOWN_TICKS = 60;
        /** Surge: how long the inhale motes loop sits at the mouth after a delivery re-open. */
        static final int SURGE_INHALE_TICKS = 20;
        /** Surge: launch-burst window and cadence (mirrors StructureFlightFx's 6-tick batches). */
        static final int SURGE_BURST_TICKS = 36;
        static final int SURGE_BURST_PERIOD = 6;
        /** VEIL-REPASS-2 launch recoil: rebound window (ticks) after each launch burst. */
        static final int RECOIL_TICKS = 8;
        /** Peak whole-tear compression at the launch instant (the frontier's 4%). */
        static final float RECOIL_AMOUNT = 0.04F;

        final ResourceKey<Level> dimension;
        final Vec3 pos;
        final float width;
        final int durationTicks;
        final int style;
        /** Portal-like styles get the surface discs, motes, ping and entry flash. */
        final boolean portalLike;
        /** Per-style palette triple (hot core / mid saturation / dim void), FXTEAM-RIFT. */
        final float hotR;
        final float hotG;
        final float hotB;
        final float midR;
        final float midG;
        final float midB;
        final float dimR;
        final float dimG;
        final float dimB;
        /** Per-rift hash salt for the renderer's flicker jitter. */
        final int seed;
        final int armCount;
        /** Star tip angles (radians, in-plane) and tip/valley radius multipliers. */
        final float[] armAngle;
        final float[] armLength;
        final float[] valleyRadius;
        /** Orthonormal tear-plane basis: n = normal, t/b span the plane. */
        final float nx;
        final float ny;
        final float nz;
        final float tx;
        final float ty;
        final float tz;
        final float bx;
        final float by;
        final float bz;

        final int openTick;
        /** Tick the collapse started, or {@code -1} while open. */
        private int closeTick = -1;
        /** Open amount captured at close start so a mid-open close collapses from there. */
        private float amountAtClose = 1.0F;
        /** Tick of the last player entry (renderer flash anchor); far past when none. */
        int entryFlashTick = -10_000;
        /** Tick the delivery surge started (structure re-open), or far past when none. */
        int surgeTick = -10_000;
        /** Tick of the last launch burst (renderer recoil anchor); far past when none. */
        int lastLaunchTick = -10_000;

        @Nullable
        private ParticleEmitter sparkEmitter;
        @Nullable
        private ParticleEmitter motesEmitter;
        /** Surge-only inhale loop parked at the mouth; removed when the inhale window ends. */
        @Nullable
        private ParticleEmitter inhaleEmitter;
        /**
         * PH-EVENTS (IDEAS-events #5b/#5c): the portal identity loop (xbox era pixels /
         * backrooms fluorescent flicker + haze). Portal-scoped WINDOWED loop
         * (INTEGRATION.md §4): the rift IS the window — kept alive on the shared retry
         * cadence while the tear is open, stopped with a graceful fade when it closes.
         */
        @Nullable
        private PhotonBridge.LoopHandle photonLoop;
        /** Ticks until the next loop-emitter (re)spawn attempt after a budget refusal. */
        private int emitterRetryCooldown;

        private Rift(ResourceKey<Level> dimension, Vec3 pos, Vec3 normal, float width,
                int durationTicks, int style, int openTick) {
            this.dimension = dimension;
            this.pos = pos;
            this.width = width;
            this.durationTicks = Math.max(0, durationTicks);
            this.style = style;
            this.portalLike = style == STYLE_PORTAL || style == STYLE_BACKROOMS;
            if (style == STYLE_BACKROOMS) {
                // C18 wax-gold: warm hot core, amber mid, near-black umber void.
                this.hotR = 1.0F; this.hotG = 0.96F; this.hotB = 0.86F;
                this.midR = 0.98F; this.midG = 0.74F; this.midB = 0.30F;
                this.dimR = 0.10F; this.dimG = 0.06F; this.dimB = 0.01F;
            } else {
                // The frozen violet read (values lifted from the pre-FXTEAM constants).
                this.hotR = 1.0F; this.hotG = 0.965F; this.hotB = 1.0F;
                this.midR = 0.62F; this.midG = 0.30F; this.midB = 0.98F;
                this.dimR = 0.045F; this.dimG = 0.0F; this.dimB = 0.10F;
            }
            this.openTick = openTick;
            // Position-derived seed: the payload coordinates are bit-identical on every
            // client, so all players see the same tear shape.
            this.seed = 31 * (31 * Double.hashCode(pos.x) + Double.hashCode(pos.y)) + Double.hashCode(pos.z);

            RandomSource shape = RandomSource.create(this.seed);
            this.armCount = MIN_ARMS + shape.nextInt(MAX_ARMS - MIN_ARMS + 1);
            this.armAngle = new float[this.armCount];
            this.armLength = new float[this.armCount];
            this.valleyRadius = new float[this.armCount];
            float step = (float) (Math.PI * 2.0D) / this.armCount;
            for (int i = 0; i < this.armCount; i++) {
                this.armAngle[i] = i * step + (shape.nextFloat() - 0.5F) * step * 0.55F;
                this.armLength[i] = 0.72F + shape.nextFloat() * 0.28F;
                this.valleyRadius[i] = 0.30F + shape.nextFloat() * 0.16F;
            }

            this.nx = (float) normal.x;
            this.ny = (float) normal.y;
            this.nz = (float) normal.z;
            // Plane basis: cross the normal with the axis it is least aligned with.
            Vec3 helper = Math.abs(normal.y) < 0.9D ? new Vec3(0.0D, 1.0D, 0.0D) : new Vec3(1.0D, 0.0D, 0.0D);
            Vec3 tangent = helper.cross(normal).normalize();
            Vec3 bitangent = normal.cross(tangent);
            this.tx = (float) tangent.x;
            this.ty = (float) tangent.y;
            this.tz = (float) tangent.z;
            this.bx = (float) bitangent.x;
            this.by = (float) bitangent.y;
            this.bz = (float) bitangent.z;
        }

        /** Tear scale in [0,1]: cubic ease-out while opening, hold-then-snap collapse while closing. */
        float openAmount(float now) {
            if (this.closeTick >= 0) {
                float t = Mth.clamp((now - this.closeTick) / CLOSE_TICKS, 0.0F, 1.0F);
                return this.amountAtClose * (1.0F - t * t * t);
            }
            float t = Mth.clamp((now - this.openTick) / OPEN_TICKS, 0.0F, 1.0F);
            float inv = 1.0F - t;
            return 1.0F - inv * inv * inv;
        }

        boolean closing() {
            return this.closeTick >= 0;
        }

        /**
         * VEIL-REPASS-2 piece-launch recoil: whole-tear scale factor — an instant
         * {@value #RECOIL_AMOUNT} compression at each launch-burst tick, rebounding on a
         * quadratic ease-out over {@value #RECOIL_TICKS} ticks. The full launch cadence
         * ({@value #SURGE_BURST_PERIOD} t) re-triggers before the rebound completes, so a
         * delivery volley reads as the rift PUMPING its pieces out. 1 while idle.
         */
        float recoilScale(float now) {
            float age = now - this.lastLaunchTick;
            if (age < 0.0F || age >= RECOIL_TICKS) {
                return 1.0F;
            }
            float rebound = age / RECOIL_TICKS;
            return 1.0F - RECOIL_AMOUNT * (1.0F - rebound) * (1.0F - rebound);
        }

        private boolean doneClosing(int now) {
            return this.closeTick >= 0 && now - this.closeTick >= CLOSE_TICKS;
        }

        private void startClose(int now) {
            this.amountAtClose = openAmount(now);
            this.closeTick = now;
        }

        /**
         * Keeps the loop emitters alive and walks the spark emitter along the tear rim (one
         * random rim point per tick — the crackle follows the edge at any width without
         * per-width emitter JSONs). Budget refusals retry once a second.
         */
        private void tickEmitters(ClientLevel level, int now) {
            if (this.closeTick >= 0) {
                // Collapsing: stop feeding new sparks/motes, keep what is airborne.
                removeEmitters();
                return;
            }
            tickSurge(now);
            if (this.emitterRetryCooldown > 0) {
                this.emitterRetryCooldown--;
            }
            // PH-EVENTS: reducedFx flipped ON mid-session must retire a live identity loop
            // (the bridge's available() gate only blocks NEW spawns, never running ones).
            boolean photonLoopWanted = this.portalLike && !EclipseClientConfig.reducedFx();
            if (!photonLoopWanted && this.photonLoop != null) {
                PhotonBridge.stopLoop(this.photonLoop, false);
                this.photonLoop = null;
            }
            boolean sparkDead = this.sparkEmitter == null || isRemovedSafe(this.sparkEmitter);
            boolean motesDead = this.portalLike
                    && (this.motesEmitter == null || isRemovedSafe(this.motesEmitter));
            boolean photonLoopDead = photonLoopWanted
                    && (this.photonLoop == null || !this.photonLoop.alive());
            if ((sparkDead || motesDead || photonLoopDead) && this.emitterRetryCooldown <= 0) {
                this.emitterRetryCooldown = EMITTER_RETRY_TICKS;
                if (sparkDead) {
                    this.sparkEmitter = QuasarSpawner.spawnManaged(RIFT_SPARK_EMITTER, this.pos,
                            FxBudget.Channel.SEQUENCE);
                }
                if (motesDead) {
                    this.motesEmitter = QuasarSpawner.spawnManaged(PORTAL_MOTES_EMITTER, this.pos,
                            FxBudget.Channel.SEQUENCE);
                }
                if (photonLoopDead) {
                    // Identity loop per style (IDEAS-events #5b/#5c) — LAYER garnish over
                    // the Quasar motes above; refusals (photon absent, executor budget)
                    // simply leave the handle null for the next once-a-second retry.
                    this.photonLoop = PhotonBridge.spawnLoop(this.style == STYLE_BACKROOMS
                            ? PhotonBridge.PORTAL_LOOP_BACKROOMS
                            : PhotonBridge.PORTAL_LOOP_XBOX, this.pos);
                }
            }
            ParticleEmitter spark = this.sparkEmitter;
            if (spark != null && !isRemovedSafe(spark)) {
                double angle = level.random.nextDouble() * Math.PI * 2.0D;
                double radius = this.width * 0.5D * 0.95D * openAmount(now);
                double cos = Math.cos(angle) * radius;
                double sin = Math.sin(angle) * radius;
                try {
                    spark.setPosition(new Vec3(
                            this.pos.x + this.tx * cos + this.bx * sin,
                            this.pos.y + this.ty * cos + this.by * sin,
                            this.pos.z + this.tz * cos + this.bz * sin));
                } catch (Throwable t) {
                    this.sparkEmitter = null; // Veil rejected the handle — next second re-spawns
                }
            }
        }

        /**
         * FXTEAM-RIFT delivery surge: for {@value #SURGE_INHALE_TICKS} ticks after a
         * structure re-open the motes loop (vortex + attractor = visibly sucked IN) sits at
         * the mouth, then is removed; for {@value #SURGE_BURST_TICKS} ticks a materialize
         * one-shot pops OUT of the mouth every {@value #SURGE_BURST_PERIOD} ticks — the
         * exact batch-launch cadence of {@code StructureFlightFx}. SEQUENCE channel; budget
         * refusals drop silently. {@code reducedFx} skips the inhale and halves the bursts.
         */
        private void tickSurge(int now) {
            int surgeAge = now - this.surgeTick;
            if (surgeAge < 0 || surgeAge > SURGE_BURST_TICKS) {
                if (this.inhaleEmitter != null) {
                    removeQuietly(this.inhaleEmitter);
                    this.inhaleEmitter = null;
                }
                return;
            }
            boolean reduced = EclipseClientConfig.reducedFx();
            if (surgeAge < SURGE_INHALE_TICKS && !reduced) {
                if (this.inhaleEmitter == null || isRemovedSafe(this.inhaleEmitter)) {
                    this.inhaleEmitter = QuasarSpawner.spawnManaged(PORTAL_MOTES_EMITTER,
                            this.pos, FxBudget.Channel.SEQUENCE);
                }
            } else if (this.inhaleEmitter != null) {
                removeQuietly(this.inhaleEmitter);
                this.inhaleEmitter = null;
            }
            int period = reduced ? SURGE_BURST_PERIOD * 2 : SURGE_BURST_PERIOD;
            if (surgeAge % period == 0) {
                // VEIL-REPASS-2: anchor the whole-tear recoil compression on this burst
                // (RiftRenderer reads recoilScale — pure scale math, zero extra geometry,
                // so it stays live under reducedFx like the entry flash: launch feedback).
                this.lastLaunchTick = now;
                QuasarSpawner.spawn(MATERIALIZE_EMITTER, this.pos, FxBudget.Channel.SEQUENCE);
                // PH-RIFT (IDEAS-world #3): optional Photon muzzle flash layered on each
                // launch burst (no-op without the photon mod; reducedFx already skipped
                // inside available()). allowMulti because the flash's smoke tail (14-22t)
                // keeps the previous runtime alive past the 6t cadence — the default
                // same-BlockPos dedup would silently eat every following flash.
                PhotonBridge.spawn(PhotonBridge.RIFT_PIECE_FLASH, this.pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
            }
        }

        /**
         * FXTEAM-RIFT entry moment: any player crossing within
         * {@code width · }{@value #ENTRY_RADIUS_FRACTION} of a portal-like star triggers the
         * iris-open flash ({@link RiftRenderer} reads {@link #entryFlashTick}), a
         * client-local whoosh, one extra rim-spark burst, and — when the entrant is the
         * local player — a small glitch pulse (spark burst and glitch pulse are both
         * skipped under {@code reducedFx}: the reduced entry is the iris fan only).
         * Per-rift cooldown
         * {@value #ENTRY_COOLDOWN_TICKS} ticks so a conga line cannot strobe the star.
         */
        private void tickEntryWatch(ClientLevel level, int now) {
            if (!this.portalLike || this.closeTick >= 0
                    || now - this.entryFlashTick < ENTRY_COOLDOWN_TICKS
                    || now - this.openTick < OPEN_TICKS) {
                return;
            }
            double radius = this.width * ENTRY_RADIUS_FRACTION;
            List<AbstractClientPlayer> players = level.players();
            for (int i = 0; i < players.size(); i++) {
                AbstractClientPlayer player = players.get(i);
                if (player.isSpectator()
                        || player.position().add(0.0D, player.getBbHeight() * 0.5D, 0.0D)
                                .distanceToSqr(this.pos) > radius * radius) {
                    continue;
                }
                this.entryFlashTick = now;
                Minecraft minecraft = Minecraft.getInstance();
                float falloff = distanceFalloff(minecraft, this.pos);
                if (falloff > 0.0F) {
                    level.playLocalSound(this.pos.x, this.pos.y, this.pos.z,
                            EclipseSounds.EVENT_RIFT_WHOOSH.get(), SoundSource.BLOCKS,
                            0.5F + 0.4F * falloff, 1.05F + level.random.nextFloat() * 0.1F, false);
                }
                // Reduced FX keeps the entry to the iris fan alone: no extra rim-spark
                // burst and no local glitch pulse (fan-only reduced entry contract).
                if (!EclipseClientConfig.reducedFx()) {
                    QuasarSpawner.spawn(RIFT_SPARK_EMITTER, this.pos, FxBudget.Channel.BURST);
                    if (player == minecraft.player) {
                        TransitionFx.glitchPulse(0.18F, 8);
                    }
                }
                return;
            }
        }

        private void removeEmitters() {
            removeQuietly(this.sparkEmitter);
            removeQuietly(this.motesEmitter);
            removeQuietly(this.inhaleEmitter);
            this.sparkEmitter = null;
            this.motesEmitter = null;
            this.inhaleEmitter = null;
            // Graceful stop (destroy(false)): emitters cease, airborne haze/motes fade out
            // over the tear's 30t collapse — never an instant pop. Dimension-change and
            // logout hard kills stay the bridge sweep's job.
            PhotonBridge.stopLoop(this.photonLoop, true);
            this.photonLoop = null;
        }

        private static boolean isRemovedSafe(ParticleEmitter emitter) {
            try {
                return emitter.isRemoved();
            } catch (Throwable t) {
                return true;
            }
        }

        private static void removeQuietly(@Nullable ParticleEmitter emitter) {
            if (emitter == null) {
                return;
            }
            try {
                if (!emitter.isRemoved()) {
                    emitter.remove();
                }
            } catch (Throwable ignored) {
                // Teardown-order safe (QuasarSpawner.clearAttached pattern): dropping the
                // reference is the part that matters.
            }
        }
    }
}
