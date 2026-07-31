package dev.projecteclipse.eclipse.veilfx;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.GazerEntity;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-MOBS' {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the cue-driven one-shots of the {@code IDEAS-mobs.md} batch (#1, #4 hound
 * half, #5 pop, #6 impact half via PH-IMPROVE-2). All rows are {@code Mode.LAYER}
 * garnish with a {@code null} Quasar leg:
 * every trigger point already ships a complete vanilla/Quasar visual (intro card,
 * REVERSE_PORTAL blink pairs, glow-spine + sonic-charge windup tell) that stays
 * bit-identical on photon-less clients.
 *
 * <p>The entity-attached LOOPS of the batch (#6 bolt ribbon, #7 petal orbit, #8 dread
 * aura, #9 gaze beam, #10 wanderer shroud) are deliberately NOT rows here — they carry
 * no wire traffic at all and live in {@link PhotonMobFx}'s attach table instead
 * (IDEAS-mobs §0.2 loop tier).</p>
 *
 * <p>Custom {@code PhotonLeg}s (INTEGRATION §3.5 — grows only when a cue needs it):</p>
 * <ul>
 *   <li><b>shockwave</b> — parks the spawn behind {@code setDelay(
 *       BossIntroOverlay.pendingLockDelayTicks())} so the ground ring erupts on the intro
 *       card's DANGER→TEXT lock flash (deterministic decode formula; delay 0 without a
 *       card). {@code allowMulti} stays false: one ring per intro per arena pos.</li>
 *   <li><b>glitch pop</b> — forces {@code allowMulti=true}: origin + exit of a short
 *       blink can land in the SAME BlockPos and packs blink on independent clocks.</li>
 *   <li><b>hound windup/dash</b> — entity-lane cues; when the hound is tracked the FX
 *       attaches ({@code NONE} at the paws for the collapsing spiral, {@code FORWARD}
 *       so the dash ara ribbon lays along the locked line), else the payload pos anchors
 *       it. Default {@code allowMulti=false} per entity: the 160t cooldown guarantees no
 *       overlap and dedup absorbs duplicate cues.</li>
 * </ul>
 *
 * <p>{@link GazeTetherWatcher} rides along in this file (FX-Wave-13 N12): a cue-less,
 * purely client-local trigger for the {@code gazer_tether_snap} one-shot. It is not a
 * {@code Row} because there is no cue and no packet — see its own javadoc.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class MobPhotonFxRows {
    /** Anchor drop from the hound's eye to its paws (0.9×1.1 hitbox — spiral base). */
    private static final Vec3 HOUND_FEET_OFFSET = new Vec3(0.0D, -0.9D, 0.0D);
    /** Anchor drop from the hound's eye to mid-body (dash ribbon height). */
    private static final Vec3 HOUND_BODY_OFFSET = new Vec3(0.0D, -0.4D, 0.0D);

    private MobPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-mobs #1 — boss-intro name-lock ground shockwave (delay-synced leg).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_BOSS_INTRO_SHOCKWAVE,
                fx("boss_intro_shockwave"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withDelay(
                                dev.projecteclipse.eclipse.client.hud.BossIntroOverlay
                                        .pendingLockDelayTicks()))));
        // IDEAS-mobs #5 — glitch_pop datamosh burst (allowMulti leg).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_GLITCH_POP,
                fx("glitch_pop"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true))));
        // IDEAS-mobs #4 — hound charge spiral (entity lane, rides the rooted hound).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_HOUND_WINDUP,
                fx("hound_lunge_windup"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> entity != null
                        ? PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_NONE, HOUND_FEET_OFFSET)
                        : PhotonBridge.spawn(photonFx, pos)));
        // IDEAS-mobs #4 — hound dash ribbon (entity lane, FORWARD along the dash line).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_HOUND_DASH,
                fx("hound_dash_trail"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> entity != null
                        ? PhotonBridge.spawnOnEntity(photonFx, entity,
                                PhotonBridge.AUTO_ROTATE_FORWARD, HOUND_BODY_OFFSET)
                        : PhotonBridge.spawn(photonFx, pos)));
        // PH-IMPROVE-2 (IDEAS-mobs #6) — shadow-bolt detonation flower (allowMulti leg:
        // a cultist 3-bolt fan can strike the same wall block within 2 ticks and packs
        // volley on independent clocks — the default dedup would eat the siblings).
        // The vanilla WITCH/REVERSE_PORTAL pops in ShadowBoltProjectile.burst stay the
        // untouched photon-less baseline.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_SHADOW_BOLT_IMPACT,
                fx("shadow_bolt_impact"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                (photonFx, pos, entity, a, b) -> PhotonBridge.spawn(photonFx, pos,
                        PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true))));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    /**
     * N12 (FX_CENSUS_WAVE13 §6) — the gaze-tether BREAK watcher.
     *
     * <p>{@code gazer_gaze_beam} is a {@link PhotonMobFx} loop, so the continuous half of
     * N12 (the viscous thread that lags and swings when the hood turns) is baked into the
     * asset's ara physics and needs no code. The discrete half — the tear-off — needs an
     * event, and the gazer has none: it publishes no synced "staring" flag, and the loop
     * tier only knows attach/detach. So the break is derived here, client-locally, from
     * state the client already has. No wire traffic, no server seam, no mob-class edit.</p>
     *
     * <p><b>What counts as a break.</b> The tether is LOCKED while the gazer is inside the
     * loop's own 20-block attach gate, its {@link Entity#getLookAngle()} is within
     * {@value #LOCK_DEG}° of the player's eye, and it can actually see them. It BREAKS the
     * first tick any of those stops holding — the hood whips past {@value #RELEASE_DEG}°,
     * the player ducks behind a wall (the beam's own raycast would collapse on that same
     * tick), the gazer leaves the release band, or it is simply GONE: {@code
     * VanishWhenSeenGoal} discards it the moment the player stares it down, which is the
     * signature break of the whole mob and the one the snap was authored for.</p>
     *
     * <p><b>Why it can't strobe.</b> The cone is hysteretic ({@value #LOCK_DEG}° to arm,
     * {@value #RELEASE_DEG}° to release) and a tether must hold for {@value #LOCK_TICKS}
     * ticks before it is worth tearing, so a hood sweeping across the player on its way
     * somewhere else produces no snap at all. After a break the entry is dropped: the same
     * gazer must earn a fresh lock before it can snap again.</p>
     *
     * <p><b>Never tears a thread that was never drawn.</b> The watcher mirrors the loop
     * row's own gating exactly — {@link Entity#getLookAngle()} is the same vector Photon
     * feeds to {@code AutoRotate.LOOK}, the range is measured from the same origin
     * ({@link net.minecraft.world.entity.Entity#position()}) with the same
     * {@value #TETHER_RANGE}/{@value #RELEASE_RANGE} band, and the nearest-{@value
     * #TETHER_CAP} cap is applied here too. A hood pushed off the cap by a closer one is
     * dropped SILENTLY: {@link PhotonMobFx} fades that loop out gracefully, so nothing
     * tore. Same for a portal or respawn — those ids belong to a world that is gone.</p>
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class GazeTetherWatcher {
        /** Cone half-angle that ARMS a tether (cosine compared against the look dot). */
        private static final double LOCK_DEG = 25.0D;
        /** Wider cone the armed tether survives in — the hysteresis band. */
        private static final double RELEASE_DEG = 45.0D;
        private static final double LOCK_DOT = Math.cos(Math.toRadians(LOCK_DEG));
        private static final double RELEASE_DOT = Math.cos(Math.toRadians(RELEASE_DEG));
        /** Ticks a stare must hold before breaking it is worth a snap (anti-strobe). */
        private static final int LOCK_TICKS = 8;
        /** The gaze loop's attach gate and its release band (see {@link PhotonMobFx}). */
        private static final double TETHER_RANGE = 20.0D;
        private static final double RELEASE_RANGE = 22.0D;
        /** The gaze row's nearest-N cap: only this many hoods actually own a thread. */
        private static final int TETHER_CAP = 2;

        private static final ResourceLocation TETHER_SNAP = fx("gazer_tether_snap");

        /** Live tethers by entity id (client main thread only). */
        private static final Map<Integer, Tether> TETHERS = new HashMap<>();
        /** The world those ids belong to. Weak: the watcher must not pin a dead level. */
        private static WeakReference<ClientLevel> tetherLevel = new WeakReference<>(null);

        /** How long this stare has held, and the eye it hangs off (for a vanish snap). */
        private static final class Tether {
            private int ticks;
            private Vec3 eye = Vec3.ZERO;

            private boolean locked() {
                return this.ticks >= LOCK_TICKS;
            }
        }

        private GazeTetherWatcher() {}

        @SubscribeEvent
        static void onClientTick(ClientTickEvent.Post event) {
            Minecraft minecraft = Minecraft.getInstance();
            ClientLevel level = minecraft.level;
            LocalPlayer player = minecraft.player;
            if (level == null || player == null || !PhotonBridge.available()) {
                TETHERS.clear(); // no thread can be hanging: nothing to tear
                return;
            }
            if (tetherLevel.get() != level) {
                // Portal / respawn. Every id below belongs to a world that is gone and
                // every remembered eye is a coordinate in it, so the vanish branch would
                // tear a thread into thin air at the wrong place. Drop them silently.
                TETHERS.clear();
                tetherLevel = new WeakReference<>(level);
            }
            Vec3 playerEye = player.getEyePosition();
            // The loop row measures from the player's FEET and keeps only the nearest
            // TETHER_CAP hoods, so those are the only gazers with a thread on screen.
            // Anything past the cap must not be able to tear one.
            Vec3 rangeFrom = player.position();
            List<GazerEntity> owners = new ArrayList<>();
            for (Entity entity : level.entitiesForRendering()) {
                if (entity instanceof GazerEntity gazer && gazer.isAlive()
                        && gazer.distanceToSqr(rangeFrom) <= RELEASE_RANGE * RELEASE_RANGE) {
                    owners.add(gazer);
                }
            }
            if (owners.size() > TETHER_CAP) {
                owners.sort((left, right) -> Double.compare(
                        left.distanceToSqr(rangeFrom), right.distanceToSqr(rangeFrom)));
                // Evicted by a closer hood: PhotonMobFx fades that loop out gracefully,
                // nothing tore, so the tether is dropped WITHOUT a snap.
                owners.subList(TETHER_CAP, owners.size()).forEach(g -> TETHERS.remove(g.getId()));
                owners = owners.subList(0, TETHER_CAP);
            }

            Set<Integer> seen = new HashSet<>();
            for (GazerEntity gazer : owners) {
                seen.add(gazer.getId());
                Tether tether = TETHERS.get(gazer.getId());
                boolean locked = tether != null && tether.locked();
                if (holdsGaze(gazer, player, rangeFrom, playerEye, locked)) {
                    if (tether == null) {
                        tether = new Tether();
                        TETHERS.put(gazer.getId(), tether);
                    }
                    tether.ticks = Math.min(tether.ticks + 1, LOCK_TICKS);
                    tether.eye = gazer.getEyePosition();
                } else if (tether != null) {
                    if (locked) {
                        // Still there, just not looking any more: the cord recoils INTO
                        // the hood, so the snap rides the entity. allowMulti because a
                        // re-lock can break again while the last 22 t snap still runs and
                        // Photon's per-entity dedup would eat the second tear.
                        PhotonBridge.spawnOnEntity(TETHER_SNAP, gazer,
                                PhotonBridge.AUTO_ROTATE_NONE,
                                PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                    }
                    TETHERS.remove(gazer.getId());
                }
            }
            // Gone entirely (vanished / discarded / untracked) — the classic gazer break.
            // The entity is unusable, so the snap plays at the eye we last saw.
            Iterator<Map.Entry<Integer, Tether>> iterator = TETHERS.entrySet().iterator();
            while (iterator.hasNext()) {
                Map.Entry<Integer, Tether> entry = iterator.next();
                if (seen.contains(entry.getKey())) {
                    continue;
                }
                if (entry.getValue().locked()) {
                    PhotonBridge.spawn(TETHER_SNAP, entry.getValue().eye,
                            PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
                }
                iterator.remove();
            }
        }

        /** Range gate + hysteretic stare cone + the beam raycast's own line of sight.
         * {@code rangeFrom} is the player's FEET (what the loop row gates on), the cone
         * is measured to the EYE (what the thread actually points at). */
        private static boolean holdsGaze(GazerEntity gazer, LocalPlayer player,
                Vec3 rangeFrom, Vec3 playerEye, boolean locked) {
            double gate = locked ? RELEASE_RANGE : TETHER_RANGE;
            if (gazer.distanceToSqr(rangeFrom) > gate * gate) {
                return false;
            }
            Vec3 toPlayer = playerEye.subtract(gazer.getEyePosition());
            if (toPlayer.lengthSqr() < 1.0E-4D) {
                return true; // inside its own head: no meaningful direction to break
            }
            double dot = gazer.getLookAngle().dot(toPlayer.normalize());
            return dot >= (locked ? RELEASE_DOT : LOCK_DOT) && gazer.hasLineOfSight(player);
        }

        @SubscribeEvent
        static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
            TETHERS.clear(); // a tether can never survive into the next session
            tetherLevel = new WeakReference<>(null);
        }
    }
}
