package dev.projecteclipse.eclipse.woah.mansiondome;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.glitchzone.GlitchColors;
import dev.projecteclipse.eclipse.glitchzone.GlitchZone;
import dev.projecteclipse.eclipse.glitchzone.GlitchZoneEffects;
import dev.projecteclipse.eclipse.glitchzone.GlitchZoneState;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.VanillaLandmarks;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-01 §3.2 — the single lifecycle/tick owner of the MANSION GLITCH DOME. Arms when
 * the Woodland Mansion site ({@value #MANSION_SITE_ID}, stage 4) reaches
 * {@code Phase.PLACED} (or on the first tick after a restart when it {@code wasPlaced}
 * but the dome is still UNARMED — never rely on stage commits, the mansion has no
 * procedural fallback), probes the roof geometry once, persists everything in
 * {@link MansionDomeState} and from then on:
 *
 * <ul>
 *   <li><b>ACTIVE</b> (1 check/second): self-heals the persistent {@code dome}
 *       {@link GlitchZone} (a {@code /dev glitch clear} kills it) and respawns a missing
 *       emitter — but ONLY once the device chunk's entity section is really loaded
 *       (Deckhand bug-4a law: a single {@code getEntity(uuid) == null} while the section
 *       is cold would duplicate the device).</li>
 *   <li><b>COLLAPSING</b> (every tick — the §5 beats need exact timing): replays the
 *       destruction timeline off {@code collapseStartGameTime}; a restart mid-sequence
 *       catches up all missed beats in one tick (loot only via the {@code lootDropped}
 *       flag).</li>
 *   <li><b>DESTROYED</b> (1 check/second): works off the aftershock schedule (three
 *       fading {@code scanlines} flickers over the mansion), then idles at zero cost.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MansionDomeService {
    /** The mansion's landmark/site id in {@code disc_map.json} / the pending registry. */
    public static final String MANSION_SITE_ID = "eclipse:mansion";
    /** Stamped mansion XZ footprint ({@code StructureStamper.footprintOf}: max(2·40, 80)). */
    private static final int MANSION_FOOTPRINT = 80;

    /** "Permanent" zone-end sentinel: survives {@code removeExpired}, no overflow in
     * {@code temporalStrength} ({@code end − now} stays far below {@code Long.MAX_VALUE}). */
    public static final long PERMANENT_END = Long.MAX_VALUE / 2L;
    /** Server fade-in of the dome zone (the client eases on top). */
    private static final int ZONE_FADE_IN_TICKS = 40;
    /** Zone radius margin past the shell: pushes the 12-block edge band OUTSIDE the hull. */
    private static final int ZONE_RADIUS_PAD = 8;
    /** Shell sphere: centre sits this far above ground (top half reads as the dome). */
    private static final int SHELL_CENTRE_LIFT = 8;
    private static final int SHELL_RADIUS_PAD = 10;
    private static final int SHELL_RADIUS_MIN = 48;
    private static final int SHELL_RADIUS_MAX = 72;
    /** Device + roof ridge must sit safely inside the shell (§2.2 geometry rule). */
    private static final int SHELL_ROOF_CLEARANCE = 6;
    private static final int SHELL_ROOF_PAD = 4;

    // §5 destruction timeline (ticks after the final hit).
    public static final int T_DEVICE_DEATH = 0;
    public static final int T_SHAKE = 10;
    public static final int T_LOOT = 20;
    public static final int T_SHATTER = 30;
    public static final int T_ZONE_FADE = 80;
    public static final int T_FINISH = 150;
    /** Interior glitch fade-out at the {@link #T_ZONE_FADE} beat (3 s). */
    private static final int ZONE_FADE_OUT_TICKS = 60;

    /** Loot at {@link #T_LOOT}: shards + XP (plan §8). */
    private static final int LOOT_GLITCH_SHARDS = 4;
    private static final int LOOT_XP = 500;

    /** Aftershocks: three scanline flickers at +60 s / +180 s / +360 s after DESTROYED. */
    private static final int AFTERSHOCK_COUNT = 3;
    private static final long AFTERSHOCK_BASE_GAP_TICKS = 1200L;
    private static final int AFTERSHOCK_RADIUS = 20;

    /** Transient collapse-beat cursor (restart → −1 → missed beats replay in one tick). */
    private static long lastProcessedElapsed = -1L;
    /** Set on ServerStarted, consumed on the first tick — the pending registry loads its
     * placed-site table in ITS OWN ServerStartedEvent handler and listener order is
     * unspecified, so {@code wasPlaced} is only trustworthy from the first tick on. */
    private static boolean needsReconcile;

    static {
        // Eager: @EventBusSubscriber classloads once per JVM, so this registers exactly once.
        StructurePendingRegistry.addListener((level, site, phase) -> {
            if (phase == StructurePendingRegistry.Phase.PLACED
                    && MANSION_SITE_ID.equals(site.siteId())) {
                armAtMansion(level, site.anchor());
            }
        });
    }

    private MansionDomeService() {}

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        lastProcessedElapsed = -1L;
        needsReconcile = true;
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        lastProcessedElapsed = -1L;
        needsReconcile = false;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        MansionDomeState state = MansionDomeState.get(server);
        long now = server.overworld().getGameTime();
        if (needsReconcile) {
            needsReconcile = false;
            reconcile(server, state);
        }
        if (state.status() == MansionDomeState.STATUS_UNARMED) {
            return;
        }
        ServerLevel level = server.getLevel(state.dimension());
        if (level == null) {
            return;
        }
        if (state.status() == MansionDomeState.STATUS_COLLAPSING) {
            tickCollapse(level, state, now);
        } else if (now % 20L == 0L) {
            if (state.status() == MansionDomeState.STATUS_ACTIVE) {
                selfHeal(level, state, now);
            } else if (state.status() == MansionDomeState.STATUS_DESTROYED) {
                tickAftershocks(level, state, now);
            }
        }
    }

    /** Restart/bestand case (§2.2 #2): mansion already placed but the dome never armed. */
    private static void reconcile(MinecraftServer server, MansionDomeState state) {
        if (state.status() != MansionDomeState.STATUS_UNARMED
                || !StructurePendingRegistry.wasPlaced(MANSION_SITE_ID)) {
            return;
        }
        BlockPos anchor = VanillaLandmarks.landmarkAnchor(DiscProfile.OVERWORLD, MANSION_SITE_ID);
        if (anchor == null) {
            EclipseMod.LOGGER.warn("MansionDome: {} was placed but the landmark anchor is "
                    + "missing from the map — dome stays unarmed", MANSION_SITE_ID);
            return;
        }
        ServerLevel overworld = server.overworld();
        EclipseMod.LOGGER.info("MansionDome: reconcile — {} placed before this build, arming now",
                MANSION_SITE_ID);
        arm(overworld, anchor, MANSION_FOOTPRINT, 0, false);
    }

    /** PLACED-listener entry: the mansion chunks are guaranteed loaded (SitePrep just finished). */
    private static void armAtMansion(ServerLevel level, BlockPos anchor) {
        MansionDomeState state = MansionDomeState.get(level.getServer());
        if (state.status() != MansionDomeState.STATUS_UNARMED) {
            return; // Already armed (or already fought down) — never re-shield.
        }
        arm(level, anchor, MANSION_FOOTPRINT, 0, false);
    }

    // ------------------------------------------------------------------ arming (§2.2)

    /**
     * One-shot arm: probes the roof over the footprint, derives the shell geometry,
     * persists it (never re-guessed), spawns the emitter, creates the {@code dome}
     * glitch zone and broadcasts the snapshot.
     *
     * @param radiusOverride {@code > 0} forces the shell radius ({@code /dev dome arm
     *                       here [radius]} test domes); 0 derives it from the footprint
     */
    public static void arm(ServerLevel level, BlockPos anchor, int footprint,
            int radiusOverride, boolean testDome) {
        MansionDomeState state = MansionDomeState.get(level.getServer());
        long now = level.getServer().overworld().getGameTime();

        // Roof probe: 9×9 heightmap grid over the footprint (one-off sync chunk loads are
        // sanctioned here — same as StructureStamper.registerStart).
        int probeStep = Math.max(2, Math.round(footprint / 10.0F));
        int roofTopY = Integer.MIN_VALUE;
        for (int gx = -4; gx <= 4; gx++) {
            for (int gz = -4; gz <= 4; gz++) {
                int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        anchor.getX() + gx * probeStep, anchor.getZ() + gz * probeStep);
                roofTopY = Math.max(roofTopY, y);
            }
        }
        // Device column: max-Y column of the inner 24×24 (the main roof), stand = first
        // free block (getHeight already answers "highest blocking + 1").
        BlockPos devicePos = anchor;
        int deviceY = Integer.MIN_VALUE;
        int deviceHalf = Math.min(12, Math.max(4, footprint / 6));
        for (int dx = -deviceHalf; dx <= deviceHalf; dx += 4) {
            for (int dz = -deviceHalf; dz <= deviceHalf; dz += 4) {
                int x = anchor.getX() + dx;
                int z = anchor.getZ() + dz;
                int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
                if (y > deviceY) {
                    deviceY = y;
                    devicePos = new BlockPos(x, y, z);
                }
            }
        }

        int groundY = anchor.getY();
        int roofY = Math.max(roofTopY - 1, groundY); // top BLOCK of the roof
        BlockPos centre = new BlockPos(anchor.getX(), groundY + SHELL_CENTRE_LIFT, anchor.getZ());
        float shellRadius = radiusOverride > 0
                ? Mth.clamp(radiusOverride, 12, 96)
                : Mth.clamp(Mth.ceil(footprint * Mth.SQRT_OF_TWO * 0.5F) + SHELL_RADIUS_PAD,
                        SHELL_RADIUS_MIN, SHELL_RADIUS_MAX);
        shellRadius = Math.max(shellRadius,
                (roofY + SHELL_ROOF_CLEARANCE) - centre.getY() + SHELL_ROOF_PAD);

        state.arm(level.dimension(), centre, shellRadius, groundY, roofY, devicePos, testDome);
        discardDevice(level, state);
        spawnDevice(level, state);
        createDomeZone(level.getServer(), state, now);
        MansionDomePayloads.syncDimension(level);
        EclipseMod.LOGGER.info(
                "MansionDome ARMED{}: centre {} r={} groundY={} roofY={} device {} ({} hits)",
                testDome ? " (test)" : "", centre.toShortString(), shellRadius, groundY, roofY,
                devicePos.toShortString(), state.hitsRemaining());
    }

    // ------------------------------------------------------------------ ACTIVE self-heal

    private static void selfHeal(ServerLevel level, MansionDomeState state, long now) {
        // (a) Zone gone (e.g. /dev glitch clear): re-create under a fresh id.
        GlitchZoneState zones = GlitchZoneState.get(level.getServer());
        UUID zoneId = state.zoneId();
        if (zoneId == null || findZone(zones, zoneId) == null) {
            createDomeZone(level.getServer(), state, now);
        }
        // (b) Device gone, chunk REALLY loaded (entity section too) → respawn.
        DomeEmitterEntity device = resolveDevice(level, state);
        if (device == null) {
            BlockPos pos = state.devicePos();
            if (level.isLoaded(pos) && level.areEntitiesLoaded(ChunkPos.asLong(pos))) {
                spawnDevice(level, state);
            }
        } else if (device.hitsRemaining() != state.hitsRemaining()) {
            device.setHitsRemaining(state.hitsRemaining()); // State is the authority.
        }
    }

    // ------------------------------------------------------------------ hits (§3.3/§6)

    /** Called by {@link DomeEmitterEntity#hurt} after the melee/i-frame filter passed. */
    public static void onDeviceHit(DomeEmitterEntity device, ServerPlayer player) {
        if (!(device.level() instanceof ServerLevel level)) {
            return;
        }
        MansionDomeState state = MansionDomeState.get(level.getServer());
        if (state.status() != MansionDomeState.STATUS_ACTIVE) {
            return;
        }
        long now = level.getServer().overworld().getGameTime();
        int hits = Math.max(0, state.hitsRemaining() - 1);
        state.setHitsRemaining(hits);
        device.setHitsRemaining(hits);
        int hitIndex = MansionDomeState.MAX_HITS - hits; // 1..8

        BlockPos pos = device.blockPosition();
        Vec3 centre = device.position().add(0.0D, device.getBbHeight() * 0.6D, 0.0D);
        level.playSound(null, pos, SoundEvents.IRON_GOLEM_HURT, SoundSource.NEUTRAL,
                0.9F, 0.8F + 0.06F * hitIndex);
        level.playSound(null, pos, SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.NEUTRAL,
                0.7F, 0.6F);
        level.playSound(null, pos, EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.AMBIENT,
                0.8F, 1.0F);
        FxPayloads.sendFxEvent(level, DomeCues.CUE_DOME_DEVICE_HIT, centre,
                hits / (float) MansionDomeState.MAX_HITS, 0.0F, 96.0D);
        // Hit impulse: a short datamosh flash inside the dome (max 1 per i-frame window,
        // so MAX_ZONES 64 is never at risk).
        GlitchZoneState.get(level.getServer()).add(new GlitchZone(UUID.randomUUID(),
                level.dimension(), pos, 16.0D, GlitchZoneEffects.DATAMOSH, GlitchColors.DEFAULT,
                now, now + 30L, 0, 10, false));

        if (hits <= 0) {
            beginDestroy(level, state, now);
        }
    }

    // ------------------------------------------------------------------ destruction (§5)

    /** t0 of the destruction sequence: flips COLLAPSING and lets the beat replayer run. */
    public static void beginDestroy(ServerLevel level, MansionDomeState state, long now) {
        if (state.status() != MansionDomeState.STATUS_ACTIVE) {
            return;
        }
        state.setStatus(MansionDomeState.STATUS_COLLAPSING);
        state.setCollapseStartGameTime(now);
        state.setLootDropped(false);
        lastProcessedElapsed = -1L;
        MansionDomePayloads.syncDimension(level);
        EclipseMod.LOGGER.info("MansionDome: destruction sequence started (t0 = {})", now);
    }

    /**
     * Beat replayer: fires every §5 beat whose tick lies in
     * {@code (lastProcessedElapsed, elapsed]} — a restart resumes seamlessly (cursor −1
     * replays everything up to {@code elapsed} in one tick; loot is flag-guarded).
     */
    private static void tickCollapse(ServerLevel level, MansionDomeState state, long now) {
        long elapsed = now - state.collapseStartGameTime();
        if (elapsed < 0L) { // Clock went backwards (dev /time set): restart the sequence.
            state.setCollapseStartGameTime(now);
            elapsed = 0L;
        }
        long cursor = lastProcessedElapsed;
        if (beatDue(cursor, elapsed, T_DEVICE_DEATH)) {
            beatDeviceDeath(level, state, now);
        }
        if (beatDue(cursor, elapsed, T_SHAKE)) {
            beatShake(level, state, 0.6F, 20, 200.0D);
        }
        if (beatDue(cursor, elapsed, T_LOOT)) {
            beatLoot(level, state);
        }
        if (beatDue(cursor, elapsed, T_SHATTER)) {
            beatShatter(level, state);
        }
        if (beatDue(cursor, elapsed, T_ZONE_FADE)) {
            beatZoneFade(level, state, now);
        }
        if (beatDue(cursor, elapsed, T_FINISH)) {
            finishDestroy(level, state, now);
        }
        lastProcessedElapsed = elapsed;
    }

    private static boolean beatDue(long cursor, long elapsed, int beatTick) {
        return cursor < beatTick && elapsed >= beatTick;
    }

    /** t0: device death anim + border-glitch sting + b=1 hit cue + datamosh flash. */
    private static void beatDeviceDeath(ServerLevel level, MansionDomeState state, long now) {
        BlockPos pos = state.devicePos();
        DomeEmitterEntity device = resolveDevice(level, state);
        if (device != null) {
            device.triggerAction(dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations.ANIM_DEATH);
        }
        level.playSound(null, pos, SoundEvents.ANVIL_LAND, SoundSource.NEUTRAL, 1.0F, 0.6F);
        level.playSound(null, pos, EclipseSounds.EVENT_BORDER_GLITCH.get(), SoundSource.AMBIENT,
                1.0F, 0.9F);
        FxPayloads.sendFxEvent(level, DomeCues.CUE_DOME_DEVICE_HIT, Vec3.atCenterOf(pos),
                0.0F, 1.0F, 128.0D);
        GlitchZoneState.get(level.getServer()).add(new GlitchZone(UUID.randomUUID(),
                level.dimension(), pos, 24.0D, GlitchZoneEffects.DATAMOSH, GlitchColors.DEFAULT,
                now, now + 60L, 0, 20, false));
    }

    private static void beatShake(ServerLevel level, MansionDomeState state, float strength,
            int ticks, double range) {
        Vec3 centre = Vec3.atCenterOf(state.centre());
        PacketDistributor.sendToPlayersNear(level, null, centre.x, centre.y, centre.z, range,
                S2CShakePayload.shake(strength, ticks));
    }

    /** t20: shards + vitae + XP at the device (flag-guarded against restart replays). */
    private static void beatLoot(ServerLevel level, MansionDomeState state) {
        if (state.lootDropped()) {
            return;
        }
        state.setLootDropped(true);
        BlockPos pos = state.devicePos();
        Vec3 drop = new Vec3(pos.getX() + 0.5D, pos.getY() + 0.8D, pos.getZ() + 0.5D);
        RandomSource random = level.random;
        for (int i = 0; i < LOOT_GLITCH_SHARDS; i++) {
            dropItem(level, drop, new ItemStack(EclipseItems.GLITCH_SHARD.get()), random);
        }
        dropItem(level, drop, new ItemStack(EclipseItems.VITAE_SHARD.get()), random);
        ExperienceOrb.award(level, drop, LOOT_XP);
        level.playSound(null, pos, SoundEvents.PLAYER_LEVELUP, SoundSource.NEUTRAL, 0.6F, 1.4F);
    }

    private static void dropItem(ServerLevel level, Vec3 pos, ItemStack stack, RandomSource random) {
        ItemEntity item = new ItemEntity(level, pos.x, pos.y, pos.z, stack);
        item.setDeltaMovement((random.nextDouble() - 0.5D) * 0.25D,
                0.25D + random.nextDouble() * 0.15D, (random.nextDouble() - 0.5D) * 0.25D);
        item.setDefaultPickUpDelay();
        level.addFreshEntity(item);
    }

    /** t30: device gone, shell hands over to the BlockDisplay shard show. */
    private static void beatShatter(ServerLevel level, MansionDomeState state) {
        discardDevice(level, state);
        Vec3 centre = Vec3.atCenterOf(state.centre());
        DomeShatterFx.begin(level, centre, state.shellRadius());
        FxPayloads.sendFxEvent(level, DomeCues.CUE_DOME_SHATTER_BURST, centre,
                state.shellRadius(), 0.0F, 512.0D);
        level.playSound(null, centre.x, centre.y, centre.z,
                EclipseSounds.EVENT_STORM_SHATTER.get(), SoundSource.AMBIENT, 3.0F, 0.9F);
        level.playSound(null, centre.x, centre.y, centre.z,
                SoundEvents.GENERIC_EXPLODE.value(), SoundSource.BLOCKS, 3.0F, 0.7F);
        beatShake(level, state, 1.0F, 30, 300.0D);
    }

    /** t80: the interior glitch fades out over 3 s (zone swapped for a fading copy). */
    private static void beatZoneFade(ServerLevel level, MansionDomeState state, long now) {
        UUID zoneId = state.zoneId();
        if (zoneId == null) {
            return;
        }
        GlitchZoneState zones = GlitchZoneState.get(level.getServer());
        GlitchZone zone = findZone(zones, zoneId);
        if (zone == null || zone.endGameTime() != PERMANENT_END) {
            return; // Already fading (restart replay) or manually removed.
        }
        zones.remove(zoneId);
        zones.add(new GlitchZone(zone.id(), zone.dim(), zone.centre(), zone.radius(),
                zone.effect(), zone.colour(), zone.startGameTime(), now + ZONE_FADE_OUT_TICKS,
                0, ZONE_FADE_OUT_TICKS, false));
    }

    /** t150: DESTROYED — mansion open for business; aftershock schedule armed. */
    private static void finishDestroy(ServerLevel level, MansionDomeState state, long now) {
        state.setStatus(MansionDomeState.STATUS_DESTROYED);
        state.setAftershocks(AFTERSHOCK_COUNT, now + AFTERSHOCK_BASE_GAP_TICKS);
        MansionDomePayloads.syncDimension(level);
        EclipseMod.LOGGER.info("MansionDome DESTROYED — mansion unshielded, {} aftershocks armed",
                AFTERSHOCK_COUNT);
    }

    // ------------------------------------------------------------------ aftershocks

    private static void tickAftershocks(ServerLevel level, MansionDomeState state, long now) {
        int remaining = state.aftershocksRemaining();
        if (remaining <= 0 || now < state.nextAftershockGameTime()) {
            return;
        }
        int n = AFTERSHOCK_COUNT - remaining; // 0, 1, 2
        // Deterministic per-save scatter (plan §5: mapSeed ^ centre ^ n).
        RandomSource random = RandomSource.create(
                FrozenParams.mapSeed() ^ state.centre().asLong() ^ n);
        int spread = Math.max(8, Math.round(state.shellRadius() * 0.5F));
        BlockPos pos = state.centre().offset(
                random.nextInt(spread * 2 + 1) - spread, 0,
                random.nextInt(spread * 2 + 1) - spread);
        int duration = 80 + random.nextInt(41); // 80–120 t
        GlitchZoneState.get(level.getServer()).add(new GlitchZone(UUID.randomUUID(),
                level.dimension(), pos, AFTERSHOCK_RADIUS, GlitchZoneEffects.SCANLINES,
                GlitchColors.DEFAULT, now, now + duration, 20, 40, false));
        level.playSound(null, pos, EclipseSounds.EVENT_STORM_FLICKER.get(), SoundSource.AMBIENT,
                0.5F, 0.9F);
        remaining--;
        long nextGap = AFTERSHOCK_BASE_GAP_TICKS * (AFTERSHOCK_COUNT - remaining + 1);
        state.setAftershocks(remaining, remaining > 0 ? now + nextGap : 0L);
    }

    // ------------------------------------------------------------------ dev hooks (§10)

    /** {@code /dev dome hits <n>}: sets the counter on state + live entity. */
    public static void setHits(ServerLevel level, int hits) {
        MansionDomeState state = MansionDomeState.get(level.getServer());
        state.setHitsRemaining(hits);
        DomeEmitterEntity device = resolveDevice(level, state);
        if (device != null) {
            device.setHitsRemaining(state.hitsRemaining());
        }
    }

    /** {@code /dev dome destroy}: full sequence from t0 (only from ACTIVE). */
    public static boolean devDestroy(ServerLevel level) {
        MansionDomeState state = MansionDomeState.get(level.getServer());
        if (state.status() != MansionDomeState.STATUS_ACTIVE) {
            return false;
        }
        state.setHitsRemaining(0);
        beginDestroy(level, state, level.getServer().overworld().getGameTime());
        return true;
    }

    /**
     * {@code /dev dome reset}: back to ACTIVE on the persisted geometry — shard sweep,
     * fresh device, fresh zone, full hits, aftershocks cleared. Needs armed-once state.
     */
    public static boolean reset(ServerLevel level) {
        MansionDomeState state = MansionDomeState.get(level.getServer());
        if (state.status() == MansionDomeState.STATUS_UNARMED) {
            return false;
        }
        long now = level.getServer().overworld().getGameTime();
        DomeShatterFx.clearAll();
        removeZone(level.getServer(), state);
        discardDevice(level, state);
        state.setStatus(MansionDomeState.STATUS_ACTIVE);
        state.setHitsRemaining(MansionDomeState.MAX_HITS);
        state.setCollapseStartGameTime(0L);
        state.setLootDropped(false);
        state.setAftershocks(0, 0L);
        lastProcessedElapsed = -1L;
        spawnDevice(level, state);
        createDomeZone(level.getServer(), state, now);
        MansionDomePayloads.syncDimension(level);
        return true;
    }

    // ------------------------------------------------------------------ shared helpers

    private static void createDomeZone(MinecraftServer server, MansionDomeState state, long now) {
        GlitchZoneState zones = GlitchZoneState.get(server);
        UUID zoneId = UUID.randomUUID();
        boolean added = zones.add(new GlitchZone(zoneId, state.dimension(), state.centre(),
                state.shellRadius() + ZONE_RADIUS_PAD, GlitchZoneEffects.DOME,
                GlitchColors.DEFAULT, now, PERMANENT_END, ZONE_FADE_IN_TICKS, 0, false));
        if (added) {
            state.setZoneId(zoneId);
        } else {
            EclipseMod.LOGGER.warn("MansionDome: glitch-zone cap reached — dome interior "
                    + "effect missing until a slot frees (self-heal retries)");
        }
    }

    private static void removeZone(MinecraftServer server, MansionDomeState state) {
        UUID zoneId = state.zoneId();
        if (zoneId != null) {
            GlitchZoneState.get(server).remove(zoneId);
            state.setZoneId(null);
        }
    }

    @Nullable
    private static GlitchZone findZone(GlitchZoneState zones, UUID id) {
        for (GlitchZone zone : zones.all()) {
            if (zone.id().equals(id)) {
                return zone;
            }
        }
        return null;
    }

    @Nullable
    private static DomeEmitterEntity resolveDevice(ServerLevel level, MansionDomeState state) {
        UUID uuid = state.deviceUuid();
        if (uuid == null) {
            return null;
        }
        Entity entity = level.getEntity(uuid);
        return entity instanceof DomeEmitterEntity device && !device.isRemoved() ? device : null;
    }

    private static void spawnDevice(ServerLevel level, MansionDomeState state) {
        if (!MansionDomeEntities.GLITCH_EMITTER.isBound()) {
            return; // Registrar not wired yet: the WOAH-01 anchor line is missing.
        }
        DomeEmitterEntity device = MansionDomeEntities.GLITCH_EMITTER.get().create(level);
        if (device == null) {
            return;
        }
        BlockPos pos = state.devicePos();
        device.moveTo(pos.getX() + 0.5D, pos.getY(), pos.getZ() + 0.5D, 0.0F, 0.0F);
        device.setHitsRemaining(state.hitsRemaining());
        level.addFreshEntity(device);
        state.setDeviceUuid(device.getUUID());
    }

    private static void discardDevice(ServerLevel level, MansionDomeState state) {
        DomeEmitterEntity device = resolveDevice(level, state);
        if (device != null) {
            device.discard();
        }
        state.setDeviceUuid(null);
    }
}
