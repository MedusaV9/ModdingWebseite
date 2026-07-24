package dev.projecteclipse.eclipse.client.credits;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsAutoRunPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.Input;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.MovementInputUpdateEvent;

/**
 * The credits auto-run (IDEAS-backrooms_finale §B2): client-side forced WALK into the
 * sunrise, deliberately NOT server velocity — input injection yields the real walk
 * animation, head bob, footstep audio and FOV that {@code setDeltaMovement} gliding lacks.
 * Armed/disarmed by {@link S2CCreditsAutoRunPayload}; the server keeps a per-player nudge
 * watchdog as the fallback for crashed/vanilla clients ({@code CreditsSequence}).
 *
 * <ul>
 *   <li>{@link MovementInputUpdateEvent} — forces the forward impulse ({@code input.up}),
 *       clears strafe/jump/sneak; sprint is forced OFF every tick (walking reads more
 *       cinematic than sprinting).</li>
 *   <li>Yaw is soft-locked to the payload heading with ±{@value #LOOK_AROUND_DEGREES}° of
 *       free look-around — players can glance at the credits panel and the lightning
 *       without ever turning around.</li>
 *   <li>Self-expiry: the run disarms after the payload's {@code maxTicks} even when the
 *       OFF payload is lost, and always on logout — nobody walks forever.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsAutoRun {
    /** Free look-around band around the locked heading (degrees each way). */
    private static final float LOOK_AROUND_DEGREES = 20.0F;

    static {
        CreditsPayloads.setClientAutoRunHandler(CreditsAutoRun::handle);
    }

    private static boolean active;
    private static float lockedYaw;
    /** Remaining self-expiry budget; counts down every client tick while active. */
    private static int remainingTicks;

    private CreditsAutoRun() {}

    /** Whether the forced walk is currently armed (read by sibling overlays). */
    public static boolean isActive() {
        return active;
    }

    private static void handle(S2CCreditsAutoRunPayload payload) {
        active = payload.active();
        lockedYaw = payload.yawDegrees();
        remainingTicks = payload.maxTicks() > 0 ? payload.maxTicks() : 20 * 60;
        EclipseMod.LOGGER.info("Credits auto-run {} (yaw {}, expiry {}t)",
                active ? "armed" : "disarmed", lockedYaw, remainingTicks);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!active) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null) {
            active = false;
            return;
        }
        if (--remainingTicks <= 0) {
            active = false;
            EclipseMod.LOGGER.info("Credits auto-run self-expired");
            return;
        }
        // Walk, don't sprint: cancel sprint every tick (double-tap/CTRL re-arms it otherwise).
        player.setSprinting(false);
        // Soft yaw lock: clamp into the ±20° band around the run heading (free look inside).
        float delta = Mth.wrapDegrees(player.getYRot() - lockedYaw);
        if (delta > LOOK_AROUND_DEGREES) {
            player.setYRot(lockedYaw + LOOK_AROUND_DEGREES);
        } else if (delta < -LOOK_AROUND_DEGREES) {
            player.setYRot(lockedYaw - LOOK_AROUND_DEGREES);
        }
        player.setXRot(Mth.clamp(player.getXRot(), -35.0F, 35.0F));
    }

    /**
     * The forced forward impulse. Fires after vanilla fills the input from the keyboard, so
     * the injection wins regardless of what keys are (not) held — including with a screen
     * (chat) open, where vanilla zeroed everything.
     */
    @SubscribeEvent
    static void onMovementInputUpdate(MovementInputUpdateEvent event) {
        if (!active) {
            return;
        }
        Input input = event.getInput();
        input.up = true;
        input.down = false;
        input.left = false;
        input.right = false;
        input.forwardImpulse = 1.0F;
        input.leftImpulse = 0.0F;
        input.jumping = false;
        input.shiftKeyDown = false;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        active = false;
    }
}
