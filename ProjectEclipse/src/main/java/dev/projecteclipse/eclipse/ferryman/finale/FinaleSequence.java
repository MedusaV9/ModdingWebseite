package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.ferryman.ArenaFight;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-045b Schlüssel-Sequenz — the server-authoritative state machine from "someone
 * touched the key" to "everyone stands on the ghost ship":
 *
 * <ol>
 *   <li><b>FLIGHT</b> ({@value #KEY_FLIGHT_TICKS}t ≈ 10 s): the key rises off the altar
 *       and flies a high bézier arc to the gate keyhole — velocity-scripted (the
 *       Ferryman drift transport), Photon key-trail ribbon client-side plus a vanilla
 *       PORTAL breadcrumb baseline.</li>
 *   <li><b>UNLOCK</b> ({@value #UNLOCK_HOLD_TICKS}t): the key seats itself (deep clunk),
 *       the gate quakes ({@code S2CShakePayload} to everyone near), door-creak + thunder
 *       roll + drowned bell stack, and the geo {@code unlock} one-shot swings the wings
 *       open. At t={@value #BREACH_AT_TICK} the BREACH: {@link FxCues#CUE_WISP_GUSH},
 *       {@value #WISP_MIN}–{@value #WISP_MAX} {@link SoulWispEntity soul wisps} pour out
 *       (hard lifespan — despawn guaranteed) plus a schwall of dark block-displays
 *       (tagged, tracked, discarded at sequence end; crash strays are discarded on load
 *       by the {@code StormDebrisFx} join-guard doctrine).</li>
 *   <li><b>FADE</b> ({@value #FADE_TICKS}t ≈ 8 s): every player's screen drowns in
 *       violet ({@code S2CScreenFadePayload}); at t={@value #SHIP_AT_TICK} the crossing
 *       hands off to {@link ArenaFight#armGateThroughPortal} (everyone shipped to the
 *       limbo deck, short countdown, then the existing arrival → transform → arena
 *       flow) and the arc advances to {@link FinaleState#STAGE_DONE}.</li>
 * </ol>
 *
 * <p><b>Crash law</b>: nothing here persists mid-sequence. The gate's open flag is
 * saved on the entity; a crash anywhere before the handoff leaves the arc at
 * {@code STAGE_PORTAL_READY} — {@link PortalFormation} re-ensures the key on boot and
 * the sequence can simply be started again (a re-unlock on an open gate no-ops).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FinaleSequence {
    /** Command tag on every breach-schwall block display (join-guard sweep). */
    public static final String BREACH_TAG = "eclipse_finale_breach";

    /** Key flight length (task spec ~10 s). */
    public static final int KEY_FLIGHT_TICKS = 200;
    /** Unlock hold: covers the 6 s geo unlock anim's quake + door swing. */
    public static final int UNLOCK_HOLD_TICKS = 110;
    /** Breach beat inside the unlock hold (the wings are opening by then). */
    public static final int BREACH_AT_TICK = 50;
    /** Violet screen drown-out (task spec ~8 s). */
    public static final int FADE_TICKS = 160;
    /** Handoff tick inside the fade (screens are deep violet; the hold covers the hop). */
    public static final int SHIP_AT_TICK = 140;

    public static final int WISP_MIN = 6;
    public static final int WISP_MAX = 10;
    /** Breach-wisp lifespan (they haunt the shore while everyone is shipped away). */
    private static final int WISP_LIFESPAN_TICKS = 900;
    /** Post-handoff wisp wind-down (nobody is left to watch them). */
    private static final int WISP_WINDDOWN_TICKS = 120;
    private static final int BREACH_DISPLAY_COUNT = 14;

    /** Deep-violet drown-out色 (ARGB). */
    private static final int FADE_ARGB = 0xFF5A00A8;
    private static final double NEAR_RANGE = 128.0D;

    // --- FX-WAVE-13 B7: UNLOCK key-photon (census §5 — the unlock read was sound-only) ---
    /**
     * Server tumbler-click stings, tick-matched to the asset's three baked glyph ring
     * snaps (asset t=8/22/36 after the UNLOCK entry; {@link #BREACH_AT_TICK} stays free).
     */
    private static final int[] KEYGLYPH_CLICKS_AT = {8, 22, 36};
    /** Rising click pitch — the lock walking its three tumblers home. */
    private static final float[] KEYGLYPH_CLICK_PITCH = {0.6F, 0.75F, 0.9F};
    /** Glyph-ring anchor sits this far under the keyhole (mid-door, ring radius 3.1). */
    private static final double KEYGLYPH_ANCHOR_BELOW = 1.5D;
    /**
     * B7 cutscene-beat cue (client row: {@code veilfx.CutsceneBeatFxRows}); both sides
     * derive the same {@code FxCues.cue("beat_finale_keyglyphs")} id — the CreditsSequence
     * naming-contract precedent, so {@code FxCues.java} stays untouched.
     */
    private static final ResourceLocation CUE_BEAT_KEYGLYPHS = FxCues.cue("beat_finale_keyglyphs");

    private enum Stage { IDLE, FLIGHT, UNLOCK, FADE }

    private static Stage stage = Stage.IDLE;
    private static int ticks;
    @Nullable
    private static UUID keyId;
    private static Vec3 flightFrom = Vec3.ZERO;
    private static Vec3 keyhole = Vec3.ZERO;
    private static float gateYaw;
    /** Live breach displays (UUID set feeds the join-guard; list keeps spawn order). */
    private static final List<UUID> BREACH_DISPLAYS = new ArrayList<>();
    private static final Set<UUID> LIVE_BREACH = ConcurrentHashMap.newKeySet();

    private static final BlockState[] BREACH_PALETTE = {
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.SCULK.defaultBlockState(),
            Blocks.CRYING_OBSIDIAN.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.AMETHYST_BLOCK.defaultBlockState()
    };

    private FinaleSequence() {}

    // ------------------------------------------------------------------ start surface

    /**
     * {@code PortalKeyEntity} trigger seam (right-click OR walk-in). Refuses while the
     * arc is not {@code STAGE_PORTAL_READY}, a sequence already runs, or the crossing /
     * fight machinery is busy. Returns whether the sequence started.
     */
    public static boolean tryStartKeySequence(ServerPlayer player, PortalKeyEntity key) {
        MinecraftServer server = player.server;
        return start(server, key, player);
    }

    /** Dev-chain entry ({@code /dev start_ferryman}): key + gate resolved from the world. */
    public static boolean startAuto(MinecraftServer server) {
        ServerLevel overworld = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altarPos == null) {
            return false;
        }
        PortalKeyEntity key = PortalFormation.findKey(overworld, altarPos);
        if (key == null) {
            EclipseMod.LOGGER.warn("FinaleSequence.startAuto: no key over the altar");
            return false;
        }
        return start(server, key, null);
    }

    private static boolean start(MinecraftServer server, PortalKeyEntity key,
            @Nullable ServerPlayer initiator) {
        FinaleState state = FinaleState.get(server);
        if (stage != Stage.IDLE || state.stage() != FinaleState.STAGE_PORTAL_READY
                || key.isFlying() || !key.isAlive()
                || ArenaFight.isBusy() || ArenaFight.isFightRunning(server)) {
            return false;
        }
        ServerLevel overworld = server.overworld();
        if (key.level() != overworld) {
            return false;
        }
        PortalGateEntity gate = PortalFormation.findGate(overworld, state);
        if (gate == null) {
            EclipseMod.LOGGER.warn("FinaleSequence: key touched but no gate stands — "
                    + "waiting for the boot ensure pass");
            return false;
        }
        stage = Stage.FLIGHT;
        ticks = 0;
        keyId = key.getUUID();
        flightFrom = key.position();
        gateYaw = gate.getYRot();
        // The keyhole sits mid-door, one block in front of the plane (local −Z).
        Vec3 forward = forwardOf(gateYaw);
        keyhole = gate.position().add(0.0D, 4.5D, 0.0D).add(forward.scale(1.0D));
        key.setFlying(true);
        overworld.playSound(null, key.blockPosition(), SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.AMBIENT, 1.5F, 0.5F);
        overworld.playSound(null, key.blockPosition(), EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                SoundSource.AMBIENT, 1.2F, 0.9F);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                    "eclipse.caption.finale.key", 90, S2CCaptionPayload.STYLE_TITLE));
        }
        EclipseMod.LOGGER.info("Finale key sequence started by {} — {}t flight to the gate",
                initiator != null ? initiator.getScoreboardName() : "(auto)", KEY_FLIGHT_TICKS);
        return true;
    }

    // ------------------------------------------------------------------ tick driver

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (stage == Stage.IDLE) {
            return;
        }
        MinecraftServer server = event.getServer();
        ServerLevel overworld = server.overworld();
        switch (stage) {
            case FLIGHT -> tickFlight(server, overworld);
            case UNLOCK -> tickUnlock(server, overworld);
            case FADE -> tickFade(server, overworld);
            default -> { }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        stage = Stage.IDLE;
        ticks = 0;
        keyId = null;
        BREACH_DISPLAYS.clear();
        LIVE_BREACH.clear();
    }

    /** StormDebrisFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(BREACH_TAG)
                && !LIVE_BREACH.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    private static void tickFlight(MinecraftServer server, ServerLevel overworld) {
        PortalKeyEntity key = keyId != null
                && overworld.getEntity(keyId) instanceof PortalKeyEntity resolved ? resolved : null;
        if (key == null || !key.isAlive()) {
            EclipseMod.LOGGER.warn("Finale key sequence aborted: the key vanished mid-flight");
            reset();
            return;
        }
        ticks++;
        double t = Math.min(1.0D, ticks / (double) KEY_FLIGHT_TICKS);
        Vec3 next = bezier(flightFrom, keyhole, Math.min(1.0D, t + 1.0D / KEY_FLIGHT_TICKS));
        Vec3 vel = next.subtract(key.position());
        if (vel.length() > 1.4D) {
            vel = vel.normalize().scale(1.4D);
        }
        key.setDeltaMovement(vel);
        key.hurtMarked = true;
        if (vel.horizontalDistanceSqr() > 1.0E-4D) {
            float yaw = (float) (Mth.atan2(vel.z, vel.x) * Mth.RAD_TO_DEG) - 90.0F;
            key.setYRot(yaw);
            key.setYBodyRot(yaw);
        }
        if (ticks % 4 == 0) {
            // Photon-less breadcrumb baseline under the client-side key-trail ribbon.
            overworld.sendParticles(ParticleTypes.PORTAL, key.getX(), key.getY() + 1.2D,
                    key.getZ(), 6, 0.25D, 0.35D, 0.25D, 0.05D);
            overworld.sendParticles(ParticleTypes.END_ROD, key.getX(), key.getY() + 1.2D,
                    key.getZ(), 1, 0.1D, 0.1D, 0.1D, 0.01D);
        }
        if (ticks >= KEY_FLIGHT_TICKS || key.position().distanceTo(keyhole) < 1.2D) {
            insertKey(server, overworld, key);
        }
    }

    /** The key seats itself: quake, creak + thunder + bell, geo wings break open. */
    private static void insertKey(MinecraftServer server, ServerLevel overworld, PortalKeyEntity key) {
        FinaleState state = FinaleState.get(server);
        overworld.sendParticles(ParticleTypes.REVERSE_PORTAL, keyhole.x, keyhole.y, keyhole.z,
                40, 0.4D, 0.6D, 0.4D, 0.08D);
        key.discard();
        keyId = null;
        PortalGateEntity gate = PortalFormation.findGate(overworld, state);
        if (gate != null) {
            gate.unlock();
        }
        BlockPos gatePos = BlockPos.containing(keyhole);
        overworld.playSound(null, gatePos, SoundEvents.RESPAWN_ANCHOR_CHARGE,
                SoundSource.AMBIENT, 1.4F, 0.6F);
        // Task spec "Türknarren + Grollen": iron-door creak, thunder roll, drowned bell.
        overworld.playSound(null, gatePos, SoundEvents.IRON_DOOR_OPEN,
                SoundSource.AMBIENT, 1.6F, 0.45F);
        overworld.playSound(null, gatePos, SoundEvents.LIGHTNING_BOLT_THUNDER,
                SoundSource.AMBIENT, 1.2F, 0.4F);
        overworld.playSound(null, gatePos, EclipseSounds.BOSS_FERRYMAN_BELL.get(),
                SoundSource.AMBIENT, 1.4F, 0.5F);
        PacketDistributor.sendToPlayersNear(overworld, null, keyhole.x, keyhole.y, keyhole.z,
                NEAR_RANGE, S2CShakePayload.shake(1.1F, 50));
        PacketDistributor.sendToPlayersNear(overworld, null, keyhole.x, keyhole.y, keyhole.z,
                192.0D, new S2CCaptionPayload("eclipse.caption.finale.unlock", 80,
                        S2CCaptionPayload.STYLE_SUBTITLE));
        // B7 key-photon: the 60t glyph/indraw asset starts WITH the unlock hold — its
        // three baked ring snaps land on the click stings below, its veil indraw ends
        // right before the t=50 breach. a = gate yaw (the house yaw leg stands the
        // rings up in the gate plane); Photon-only LAYER garnish over this baseline.
        FxPayloads.sendFxEvent(overworld, CUE_BEAT_KEYGLYPHS,
                keyhole.add(0.0D, -KEYGLYPH_ANCHOR_BELOW, 0.0D), gateYaw, 0.0F, NEAR_RANGE);
        stage = Stage.UNLOCK;
        ticks = 0;
        EclipseMod.LOGGER.info("Finale key seated: gate unlocking ({}t hold, breach at {}t)",
                UNLOCK_HOLD_TICKS, BREACH_AT_TICK);
    }

    private static void tickUnlock(MinecraftServer server, ServerLevel overworld) {
        ticks++;
        // B7: the three tumbler clicks under the glyph ring snaps (photon-less clients
        // still hear the lock walking home).
        for (int i = 0; i < KEYGLYPH_CLICKS_AT.length; i++) {
            if (ticks == KEYGLYPH_CLICKS_AT[i]) {
                overworld.playSound(null, BlockPos.containing(keyhole),
                        SoundEvents.LODESTONE_COMPASS_LOCK, SoundSource.AMBIENT,
                        1.6F, KEYGLYPH_CLICK_PITCH[i]);
            }
        }
        if (ticks == BREACH_AT_TICK) {
            breach(server, overworld);
        }
        if (ticks >= UNLOCK_HOLD_TICKS) {
            stage = Stage.FADE;
            ticks = 0;
            // The violet drown-out: rises for 6 s, holds through the handoff, releases
            // on the far side (the arrival veil covers the rest).
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                PacketDistributor.sendToPlayer(player,
                        new S2CScreenFadePayload(120, 50, 60, FADE_ARGB));
                PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                        "eclipse.caption.finale.veil", 90, S2CCaptionPayload.STYLE_WHISPER));
            }
            overworld.playSound(null, BlockPos.containing(keyhole), SoundEvents.END_PORTAL_SPAWN,
                    SoundSource.AMBIENT, 1.5F, 0.45F);
            EclipseMod.LOGGER.info("Finale veil rising: handoff to the crossing in {}t", SHIP_AT_TICK);
        }
    }

    /** The gate breaches: wisp gush FX, the soul-wisp swarm, the display schwall. */
    private static void breach(MinecraftServer server, ServerLevel overworld) {
        Vec3 door = keyhole.add(0.0D, -2.0D, 0.0D);
        FxPayloads.sendFxEvent(overworld, FxCues.CUE_WISP_GUSH, door, gateYaw, 0.0F, NEAR_RANGE);
        overworld.playSound(null, BlockPos.containing(door), SoundEvents.VEX_AMBIENT,
                SoundSource.HOSTILE, 1.6F, 0.55F);
        overworld.playSound(null, BlockPos.containing(door), SoundEvents.SCULK_SHRIEKER_SHRIEK,
                SoundSource.AMBIENT, 1.2F, 0.7F);
        overworld.sendParticles(ParticleTypes.SOUL, door.x, door.y, door.z,
                60, 1.2D, 1.6D, 1.2D, 0.06D);
        Vec3 forward = forwardOf(gateYaw);
        int wisps = WISP_MIN + overworld.random.nextInt(WISP_MAX - WISP_MIN + 1);
        if (FinaleEntities.SOUL_WISP.isBound()) {
            for (int i = 0; i < wisps; i++) {
                SoulWispEntity wisp = FinaleEntities.SOUL_WISP.get().create(overworld);
                if (wisp == null) {
                    continue;
                }
                wisp.moveTo(door.x + (overworld.random.nextDouble() - 0.5D) * 2.0D,
                        door.y + overworld.random.nextDouble() * 3.0D,
                        door.z + (overworld.random.nextDouble() - 0.5D) * 2.0D,
                        gateYaw, 0.0F);
                wisp.setLifespan(WISP_LIFESPAN_TICKS);
                overworld.addFreshEntity(wisp);
                wisp.shove(forward.scale(0.35D + overworld.random.nextDouble() * 0.3D)
                        .add((overworld.random.nextDouble() - 0.5D) * 0.3D,
                                0.1D + overworld.random.nextDouble() * 0.2D,
                                (overworld.random.nextDouble() - 0.5D) * 0.3D));
            }
        }
        spawnBreachSchwall(overworld, door, forward);
        EclipseMod.LOGGER.info("Finale breach: {} soul wisp(s) + {} schwall display(s) poured out",
                wisps, BREACH_DISPLAYS.size());
    }

    /** One keyframe per schwall piece: a 60t interpolated outward tumble, then linger. */
    private static void spawnBreachSchwall(ServerLevel overworld, Vec3 door, Vec3 forward) {
        for (int i = 0; i < BREACH_DISPLAY_COUNT; i++) {
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(overworld);
            if (display == null) {
                continue;
            }
            display.moveTo(door.x, door.y + 1.0D, door.z, 0.0F, 0.0F);
            display.setBlockState(BREACH_PALETTE[i % BREACH_PALETTE.length]);
            display.addTag(BREACH_TAG);
            BREACH_DISPLAYS.add(display.getUUID());
            LIVE_BREACH.add(display.getUUID());
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            float scale = 0.4F + overworld.random.nextFloat() * 0.5F;
            display.setTransformation(new Transformation(new Vector3f(),
                    new Quaternionf(), new Vector3f(scale, scale, scale), new Quaternionf()));
            overworld.addFreshEntity(display);
            // One interpolated push: burst out of the door in a widening fan.
            double spread = (i / (double) BREACH_DISPLAY_COUNT - 0.5D) * Math.PI * 0.8D;
            Vec3 dir = rotateY(forward, spread);
            Vector3f target = new Vector3f(
                    (float) (dir.x * (4.0D + (i % 5))),
                    1.5F + (i % 3) * 1.2F,
                    (float) (dir.z * (4.0D + (i % 5))));
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(60);
            display.setTransformation(new Transformation(target,
                    new Quaternionf().rotationAxis((float) (Math.PI * (1.0D + i * 0.13D)),
                            new Vector3f(0.4F, 1.0F, 0.3F).normalize()),
                    new Vector3f(scale, scale, scale), new Quaternionf()));
        }
    }

    private static void tickFade(MinecraftServer server, ServerLevel overworld) {
        ticks++;
        if (ticks == SHIP_AT_TICK) {
            FinaleState state = FinaleState.get(server);
            boolean shipped = ArenaFight.armGateThroughPortal(server);
            state.setStage(FinaleState.STAGE_DONE);
            EclipseMod.LOGGER.info("Finale handoff: crossing {} — arc DONE",
                    shipped ? "armed through the portal" : "REFUSED (machinery busy) — arc closed anyway");
        }
        if (ticks >= FADE_TICKS) {
            cleanup(overworld);
            reset();
        }
    }

    /** Discards the schwall and winds the shore wisps down (nobody is left to watch). */
    private static void cleanup(ServerLevel overworld) {
        int discarded = 0;
        for (UUID id : BREACH_DISPLAYS) {
            if (overworld.getEntity(id) instanceof Display.BlockDisplay display) {
                display.discard();
                discarded++;
            }
        }
        BREACH_DISPLAYS.clear();
        LIVE_BREACH.clear();
        if (FinaleEntities.SOUL_WISP.isBound()) {
            for (SoulWispEntity wisp : overworld.getEntities(FinaleEntities.SOUL_WISP.get(),
                    new net.minecraft.world.phys.AABB(BlockPos.containing(keyhole)).inflate(48.0D),
                    Entity::isAlive)) {
                wisp.setLifespan(WISP_WINDDOWN_TICKS);
            }
        }
        if (discarded > 0) {
            EclipseMod.LOGGER.info("Finale sequence cleanup: {} schwall display(s) discarded", discarded);
        }
    }

    private static void reset() {
        stage = Stage.IDLE;
        ticks = 0;
        keyId = null;
    }

    // ------------------------------------------------------------------ math

    /** Quadratic bézier from the altar hover to the keyhole, cresting ~14 blocks up. */
    private static Vec3 bezier(Vec3 from, Vec3 to, double t) {
        Vec3 control = from.add(to).scale(0.5D).add(0.0D, 14.0D, 0.0D);
        double inv = 1.0D - t;
        return from.scale(inv * inv).add(control.scale(2.0D * inv * t)).add(to.scale(t * t));
    }

    /** Minecraft forward for yaw φ: (−sin φ, 0, cos φ). */
    private static Vec3 forwardOf(float yawDeg) {
        double rad = Math.toRadians(yawDeg);
        return new Vec3(-Math.sin(rad), 0.0D, Math.cos(rad));
    }

    private static Vec3 rotateY(Vec3 v, double angle) {
        double cos = Math.cos(angle);
        double sin = Math.sin(angle);
        return new Vec3(v.x * cos - v.z * sin, v.y, v.x * sin + v.z * cos);
    }
}
