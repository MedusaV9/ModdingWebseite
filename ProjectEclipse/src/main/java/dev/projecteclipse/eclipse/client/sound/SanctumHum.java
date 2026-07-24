package dev.projecteclipse.eclipse.client.sound;

import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.worldgen.structure.FloatingSanctumBuilder;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * IDEA-07 §1 — the sanctum aura hum that swells as you glide up. A single positional loop
 * anchored at the altar column ({@link FxAnchors#ALTAR_CENTER}), volume driven per tick by
 * the already-slewed {@link EclipseFxState#altarAberration()} zone strength times a vertical
 * ramp from the crater floor ({@code FloatingSanctumBuilder.groundY}) to the island rim
 * ({@code FloatingSanctumBuilder.islandTopY}): {@code volume = aberration ×
 * (0.4 + 0.6 × verticalFactor)} — the hum literally crests as you rise past the underside
 * strata. {@code AltarAberration}'s ~10-tick slew means the input can never pop; a small
 * per-tick volume lerp inside the instance covers fast vertical movement (elytra).
 *
 * <p><b>Sound event:</b> resolves the W4-ATMOS ledger id {@code eclipse:ambient.sanctum_hum}
 * from the registry at start time and falls back to the shipped
 * {@code EclipseSounds.AMBIENT_LIMBO_LOOP} pitched {@value #FALLBACK_PITCH} while the alias
 * ask is pending (the {@code UiSounds.play(String, ...)} self-healing pattern — the class
 * hums today and picks the two-layer bed up automatically after the sounds.json merge).</p>
 *
 * <p><b>Glide-notch garnish:</b> the four frozen launch ledges
 * ({@link FloatingSanctumBuilder#glideLedges}, {@code GLIDE_NOTCH_ANGLES 45/135/225/315})
 * each fire a one-shot {@code event.emerge} whoosh (pitch {@value #WHOOSH_PITCH}, vol
 * {@value #WHOOSH_VOLUME}) when the local player crosses the ledge cell at rim height while
 * moving outward — a tiny AABB + velocity-dot check, one cooldown per ledge.</p>
 *
 * <p><b>Lifecycle</b> (IDEA-07 cross-cutting note): {@code LimboAmbience}'s
 * {@code soundStartedThisVisit} one-shot guard + {@code LoggingOut} reset, copied verbatim.
 * One sound instance, nothing charged to {@code FxBudget}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SanctumHum {
    /** W4-ATMOS ledger id (registry + sounds.json ask in W4-ATMOS_wiring.md). */
    private static final ResourceLocation HUM_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.sanctum_hum");
    /** Fallback re-pitch of {@code ambient.limbo_loop} — layer 2 of the pending alias bed. */
    private static final float FALLBACK_PITCH = 1.3F;

    /** Hum engages above this zone strength; below it the visit guard re-arms. */
    private static final float START_THRESHOLD = 0.02F;
    /** Volume floor under the ramp: the hum never fully dies inside the zone (IDEA-07 §1). */
    private static final float BASE_VOLUME_SHARE = 0.4F;
    /** Ticks of continuous silence before a live instance stops itself. */
    private static final int SILENT_STOP_TICKS = 60;

    // --- glide-notch whoosh (event.emerge pitched 1.4 vol 0.6 per IDEA-07 §1) ---
    private static final float WHOOSH_PITCH = 1.4F;
    private static final float WHOOSH_VOLUME = 0.6F;
    /** Horizontal catch radius around a ledge center (the notch slabs are ~2 blocks). */
    private static final double LEDGE_RADIUS = 1.6D;
    /** Vertical catch band above the ledge Y (rim walk surface + a jump). */
    private static final double LEDGE_HEIGHT = 3.0D;
    /** Outward horizontal speed (blocks/tick) that counts as "launching", not loitering. */
    private static final double OUTWARD_SPEED = 0.05D;
    private static final int WHOOSH_COOLDOWN_TICKS = 60;

    /** Per-tick hum volume target, written by the ticker, read by the instance. */
    private static float targetVolume;
    @Nullable
    private static HumSound humSound;
    /** One play(...) attempt per zone visit (LimboAmbience guard — no retry storms). */
    private static boolean soundStartedThisVisit;

    /** Ledges cached off the altar anchor (pure geometry; recomputed when the anchor moves). */
    @Nullable
    private static BlockPos cachedAltarPos;
    @Nullable
    private static List<BlockPos> ledges;
    private static final long[] lastWhooshGameTime = new long[FloatingSanctumBuilder.GLIDE_NOTCH_ANGLES.length];

    private SanctumHum() {}

    // ------------------------------------------------------------------ per-tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        LocalPlayer player = minecraft.player;
        if (level == null || player == null || level.dimension() != Level.OVERWORLD) {
            targetVolume = 0.0F;
            soundStartedThisVisit = false;
            return;
        }
        Vec3 altar = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        float aberration = EclipseFxState.altarAberration();
        if (altar == null || aberration <= START_THRESHOLD) {
            // No positional anchor (pre-sync) or outside the zone: fade out; the guard
            // re-arms so the next approach starts a fresh instance.
            targetVolume = 0.0F;
            if (aberration <= START_THRESHOLD) {
                soundStartedThisVisit = false;
            }
            return;
        }

        // Vertical ramp: crater floor -> island rim (the underside climb is the swell).
        double topY = FloatingSanctumBuilder.islandTopY(BlockPos.containing(altar));
        double groundY = topY - FloatingSanctumBuilder.ISLAND_LIFT;
        float verticalFactor = (float) Mth.clamp(
                (player.getEyeY() - groundY) / FloatingSanctumBuilder.ISLAND_LIFT, 0.0D, 1.0D);
        targetVolume = aberration * (BASE_VOLUME_SHARE + (1.0F - BASE_VOLUME_SHARE) * verticalFactor);

        HumSound sound = humSound;
        if (sound == null || sound.isStopped()) {
            if (!soundStartedThisVisit) {
                soundStartedThisVisit = true;
                sound = new HumSound(altar);
                humSound = sound;
                minecraft.getSoundManager().play(sound);
            }
        } else {
            sound.moveTo(altar);
        }

        tickGlideWhoosh(level, player, altar);
    }

    // ------------------------------------------------------------------ glide notches

    /** One-shot whoosh when the player crosses a launch-ledge cell moving outward. */
    private static void tickGlideWhoosh(ClientLevel level, LocalPlayer player, Vec3 altar) {
        BlockPos altarPos = BlockPos.containing(altar);
        if (!altarPos.equals(cachedAltarPos)) {
            cachedAltarPos = altarPos;
            ledges = FloatingSanctumBuilder.glideLedges(altarPos);
        }
        List<BlockPos> notches = ledges;
        if (notches == null) {
            return;
        }
        long gameTime = level.getGameTime();
        Vec3 motion = player.getDeltaMovement();
        for (int i = 0; i < notches.size(); i++) {
            if (gameTime - lastWhooshGameTime[i] < WHOOSH_COOLDOWN_TICKS) {
                continue;
            }
            BlockPos ledge = notches.get(i);
            double dx = player.getX() - (ledge.getX() + 0.5D);
            double dz = player.getZ() - (ledge.getZ() + 0.5D);
            if (dx * dx + dz * dz > LEDGE_RADIUS * LEDGE_RADIUS) {
                continue;
            }
            double dy = player.getY() - ledge.getY();
            if (dy < -0.5D || dy > LEDGE_HEIGHT) {
                continue;
            }
            // Outward = away from the altar column, horizontally.
            double outX = ledge.getX() + 0.5D - altar.x;
            double outZ = ledge.getZ() + 0.5D - altar.z;
            double len = Math.sqrt(outX * outX + outZ * outZ);
            if (len < 1.0E-3D || (motion.x * outX + motion.z * outZ) / len < OUTWARD_SPEED) {
                continue;
            }
            lastWhooshGameTime[i] = gameTime;
            level.playLocalSound(ledge.getX() + 0.5D, ledge.getY() + 1.0D, ledge.getZ() + 0.5D,
                    EclipseSounds.EVENT_EMERGE.get(), SoundSource.AMBIENT,
                    WHOOSH_VOLUME, WHOOSH_PITCH, false);
        }
    }

    // ------------------------------------------------------------------ lifecycle

    /** Disconnect reset hook (mirrors {@code LimboAmbience.onLoggingOut}). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        HumSound sound = humSound;
        if (sound != null) {
            sound.forceStop();
            humSound = null;
        }
        soundStartedThisVisit = false;
        targetVolume = 0.0F;
        cachedAltarPos = null;
        ledges = null;
        java.util.Arrays.fill(lastWhooshGameTime, 0L);
    }

    /** Registered {@code ambient.sanctum_hum} or the pitched limbo-loop fallback. */
    private static SoundEvent resolveHum() {
        return BuiltInRegistries.SOUND_EVENT.getOptional(HUM_ID)
                .orElseGet(EclipseSounds.AMBIENT_LIMBO_LOOP);
    }

    /**
     * The positional aura loop. Volume chases {@link #targetVolume} with a small per-tick
     * step (aberration is pre-slewed; this only covers fast elytra height changes) and the
     * instance stops itself after {@value #SILENT_STOP_TICKS} silent ticks so an abandoned
     * zone leaves no idle looping instance behind.
     */
    private static final class HumSound extends AbstractTickableSoundInstance {
        private static final float VOLUME_STEP = 0.05F;

        private int silentTicks;

        private HumSound(Vec3 altar) {
            super(resolveHum(), SoundSource.AMBIENT, SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = false;
            this.pitch = BuiltInRegistries.SOUND_EVENT.containsKey(HUM_ID) ? 1.0F : FALLBACK_PITCH;
            moveTo(altar);
        }

        void moveTo(Vec3 altar) {
            this.x = altar.x;
            this.y = altar.y;
            this.z = altar.z;
        }

        @Override
        public void tick() {
            float target = targetVolume;
            if (this.volume < target) {
                this.volume = Math.min(target, this.volume + VOLUME_STEP);
            } else if (this.volume > target) {
                this.volume = Math.max(target, this.volume - VOLUME_STEP);
            }
            if (this.volume <= 0.005F) {
                if (++this.silentTicks >= SILENT_STOP_TICKS) {
                    this.stop();
                }
            } else {
                this.silentTicks = 0;
            }
        }

        /** Disconnect teardown: kill the instance immediately, skipping the fade. */
        void forceStop() {
            this.stop();
        }
    }
}
