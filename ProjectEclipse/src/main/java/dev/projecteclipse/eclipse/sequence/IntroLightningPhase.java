package dev.projecteclipse.eclipse.sequence;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The ramping lightning controller of the intro sequence (P2 R10 phase 4): scheduled
 * purple strikes from the eclipse zenith down onto the vortex top, growing more frequent
 * and more intense over {@value #DURATION_TICKS} ticks, kicking nearby players back from
 * the smoke wall — never off the disc.
 *
 * <p><b>Cadence curve</b> (R10 frozen shape): first strike at local t=0 with intensity
 * {@value #FIRST_INTENSITY} and the loud burst sting; afterwards the interval ramps
 * {@value #INTERVAL_START} → {@value #INTERVAL_END} ticks (eased) while intensity ramps
 * {@value #INTENSITY_START} → 1.0 — matching the plan's 100→70→45→25→15 interval table as
 * a continuous curve. The purple tint rises client-side with the strike intensity (W9's
 * {@code StormFxClient.strikeLightning} palette).</p>
 *
 * <p><b>Per strike</b>: the frozen {@code eclipse:fx/lightning_strike} event (clients
 * reconstruct the source along the sun direction — the bolts visibly come FROM the
 * eclipse), a {@code eclipse:eclipse_lightning_impact} spark burst plus a
 * {@code eclipse:impact_light} emissive flash at the impact (both Quasar one-shots, no
 * dynamic lights — §7 perf trap), one vanilla {@link LightningBolt} with
 * {@code setVisualOnly(true)} at the vortex foot for the world flash, and distance-picked
 * {@code event.lightning_close}/{@code event.lightning_far} stings.</p>
 *
 * <p><b>Kickback + day-1 containment awareness</b>: players within
 * {@value #KICK_RANGE_BEYOND_RADIUS} blocks of the smoke wall get the proven
 * {@code risePlayerAt} impulse pattern ({@value #KICK_HORIZONTAL} horizontal radially away
 * from the vortex + {@value #KICK_VERTICAL} up, {@code hurtMarked = true}). The push
 * vector is clamped inward whenever the predicted landing column would leave the disc
 * footprint (stage-0 discs or the fused-disc radius) — P4's containment is the hard
 * guarantee, this clamp keeps the impulse itself from ever aiming off the rim. Frozen
 * players (replays, stragglers still in a cutscene) are never pushed.</p>
 *
 * <p>FX-only replays construct this with {@code applyKickback=false} and no world
 * mutations happen (the visual-only bolt is transient FX and spawns only in live runs).</p>
 */
public final class IntroLightningPhase {
    /** Length of the ramping-strikes window before the giant burst (R10: t=0..600). */
    public static final int DURATION_TICKS = 600;

    private static final float FIRST_INTENSITY = 0.5F;
    private static final int INTERVAL_START = 100;
    private static final int INTERVAL_END = 15;
    private static final float INTENSITY_START = 0.4F;

    /** Players within this many blocks OUTSIDE the smoke wall get the kickback. */
    public static final double KICK_RANGE_BEYOND_RADIUS = 12.0D;
    private static final double KICK_HORIZONTAL = 0.8D;
    private static final double KICK_VERTICAL = 0.25D;
    /** Horizontal blocks a kick roughly carries a player (containment prediction). */
    private static final double KICK_TRAVEL_BLOCKS = 5.0D;
    /** Safety margin inside the fused-disc rim for the containment clamp. */
    private static final double RIM_MARGIN = 2.0D;
    /** Strikes closer than this play the violent close sting instead of the far rumble. */
    private static final double CLOSE_SOUND_RANGE = 64.0D;

    private static final ResourceLocation LIGHTNING_IMPACT_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "eclipse_lightning_impact");
    private static final ResourceLocation IMPACT_LIGHT_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "impact_light");

    private final Vec3 center;
    private final float radius;
    private final float height;
    private final boolean applyKickback;

    private int ticks;
    private int nextStrikeTick;

    /**
     * @param center        vortex center at ground level (strike target column)
     * @param radius        vortex shell radius (kick range keys off it)
     * @param height        vortex height (strikes hit the top)
     * @param applyKickback {@code false} for FX-only replays (visuals + sounds only)
     */
    public IntroLightningPhase(Vec3 center, float radius, float height, boolean applyKickback) {
        this.center = center;
        this.radius = radius;
        this.height = height;
        this.applyKickback = applyKickback;
    }

    /**
     * Advances the controller one server tick, firing scheduled strikes. Returns
     * {@code true} while the ramp is still running, {@code false} once
     * {@value #DURATION_TICKS} ticks have elapsed (the caller fires the giant burst).
     */
    public boolean tick(ServerLevel level) {
        if (this.ticks >= DURATION_TICKS) {
            return false;
        }
        if (this.ticks == this.nextStrikeTick) {
            float progress = this.ticks / (float) DURATION_TICKS;
            boolean first = this.ticks == 0;
            float intensity = first ? FIRST_INTENSITY
                    : Mth.lerp(progress, INTENSITY_START, 1.0F);
            strike(level, intensity, false);
            if (first) {
                // The loud opening crack: the burst sting on top of the close sting.
                for (ServerPlayer player : level.players()) {
                    player.playNotifySound(EclipseSounds.EVENT_STORM_BURST.get(),
                            SoundSource.AMBIENT, 1.0F, 0.9F);
                }
            }
            // Eased interval ramp: ~100, 70, 45, 25, 15 across the window (R10 table).
            float eased = progress * progress * (3.0F - 2.0F * progress);
            this.nextStrikeTick = this.ticks
                    + Math.max(INTERVAL_END, Math.round(Mth.lerp(eased, INTERVAL_START, INTERVAL_END)));
        }
        this.ticks++;
        return this.ticks < DURATION_TICKS;
    }

    /**
     * Fires one strike NOW: FX event + impact emitters + visual-only vanilla bolt +
     * distance-picked stings + (live runs) the kickback. {@code giant} marks the final
     * burst strike ({@code b=1} on the FX event — W9 renders it huge).
     */
    public void strike(ServerLevel level, float intensity, boolean giant) {
        Vec3 impact = impactPos(level, giant);
        FxPayloads.sendFxEvent(level, FxPayloads.FX_LIGHTNING_STRIKE, impact,
                Mth.clamp(intensity, 0.0F, 1.0F), giant ? 1.0F : 0.0F, 0.0D);
        PacketDistributor.sendToPlayersInDimension(level,
                new S2CQuasarPayload(LIGHTNING_IMPACT_EMITTER, impact));
        PacketDistributor.sendToPlayersInDimension(level,
                new S2CQuasarPayload(IMPACT_LIGHT_EMITTER, impact));

        if (this.applyKickback) {
            spawnVisualBolt(level, impact);
            kickbackNearbyPlayers(level, giant ? 1.0F : intensity);
        }
        playStingByDistance(level, impact, intensity, giant);
    }

    /** Strike impact on the vortex top, jittered off-axis so repeats never stack exactly. */
    private Vec3 impactPos(ServerLevel level, boolean giant) {
        if (giant) {
            return this.center.add(0.0D, this.height, 0.0D); // dead center, straight down
        }
        double angle = level.random.nextDouble() * Math.PI * 2.0D;
        double r = level.random.nextDouble() * this.radius * 0.4D;
        return this.center.add(Math.cos(angle) * r, this.height, Math.sin(angle) * r);
    }

    /** One vanilla bolt at the vortex foot for the world flash — visual only, no fire/damage. */
    private void spawnVisualBolt(ServerLevel level, Vec3 impact) {
        LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(level);
        if (bolt == null) {
            return;
        }
        bolt.moveTo(new Vec3(impact.x, this.center.y, impact.z));
        bolt.setVisualOnly(true);
        level.addFreshEntity(bolt);
    }

    private void playStingByDistance(ServerLevel level, Vec3 impact, float intensity, boolean giant) {
        for (ServerPlayer player : level.players()) {
            boolean close = player.position().distanceTo(impact) <= CLOSE_SOUND_RANGE || giant;
            player.playNotifySound(
                    close ? EclipseSounds.EVENT_LIGHTNING_CLOSE.get() : EclipseSounds.EVENT_LIGHTNING_FAR.get(),
                    SoundSource.AMBIENT,
                    Mth.clamp(0.6F + 0.5F * intensity, 0.0F, 1.2F),
                    giant ? 0.8F : 0.95F + level.random.nextFloat() * 0.1F);
        }
    }

    /**
     * Radial impulse away from the vortex for every unfrozen player near the smoke wall,
     * clamped so the predicted landing column never leaves the disc (see class doc).
     */
    private void kickbackNearbyPlayers(ServerLevel level, float intensity) {
        double maxDist = this.radius + KICK_RANGE_BEYOND_RADIUS;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || FreezeService.isFrozen(player)) {
                continue;
            }
            Vec3 fromCenter = player.position().subtract(this.center).multiply(1.0D, 0.0D, 1.0D);
            double dist = fromCenter.length();
            if (dist > maxDist) {
                continue;
            }
            Vec3 dir = dist > 1.0E-3D ? fromCenter.scale(1.0D / dist) : randomHorizontal(level);
            double strength = KICK_HORIZONTAL * (0.7D + 0.6D * intensity);
            Vec3 predicted = player.position().add(dir.scale(KICK_TRAVEL_BLOCKS));
            if (!isOnDisc(level, predicted.x, predicted.z)) {
                // Containment clamp: aim the push back INWARD instead of off the rim.
                dir = dir.scale(-1.0D);
                strength *= 0.5D;
            }
            player.setDeltaMovement(dir.x * strength, KICK_VERTICAL, dir.z * strength);
            player.hurtMarked = true; // sync the velocity to the client (risePlayerAt pattern)
        }
    }

    private static Vec3 randomHorizontal(ServerLevel level) {
        double angle = level.random.nextDouble() * Math.PI * 2.0D;
        return new Vec3(Math.cos(angle), 0.0D, Math.sin(angle));
    }

    /**
     * Whether a column is on walkable disc terrain: the stage-0 footprint (main disc +
     * player discs — mid-fusion bridge columns count as main-disc-adjacent and pass via
     * the fused radius below) or, from stage 1, the fused disc radius minus a margin.
     */
    private static boolean isOnDisc(ServerLevel level, double x, double z) {
        int stage = WorldStageService.stage(level.getServer(), DiscProfile.OVERWORLD);
        if (DiscGeometry.isInStageZeroFootprint(x, z)) {
            return true;
        }
        if (stage <= 0) {
            return false;
        }
        double fused = DiscGeometry.mainDiscRadius(stage) - RIM_MARGIN;
        return x * x + z * z <= fused * fused;
    }
}
