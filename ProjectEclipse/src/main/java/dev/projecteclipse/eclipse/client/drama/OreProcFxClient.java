package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.particles.DustParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.joml.Vector3f;

/**
 * Client body of the {@code eclipse:fx/ore_proc} one-shot (W4-FEEL, IDEA-03 #3/#4): a
 * small ore-colored dust ring plus a couple of rising glints at the block that just paid
 * out extra drops (T2 Fortune's Echo / T6 Earthen Bond procs, the {@code ore_drops}
 * buff), so the eye sees the jackpot where it happened instead of only hearing it.
 *
 * <p>Dispatch: {@code FxPayloads.handleFxEvent} routes the id here — that file is FROZEN
 * and shared, so the exact 4-line branch ships as a diff in
 * {@code docs/plans_v3/wiring/W4-FEEL_wiring.md} (payload: {@code a} = magnitude,
 * {@code b} = packed 24-bit RGB). Until it lands, the id falls into the debug-log arm —
 * a silent no-op, nothing breaks.</p>
 *
 * <p>Budget: vanilla {@code addParticle} one-shots (≤ 14 particles), no Quasar emitter —
 * far below the BURST channel's concerns. {@code reducedFx} skips entirely. Stateless.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class OreProcFxClient {
    /** Fallback tint when the payload carries no color — Quiet-Eclipse accent purple. */
    private static final int ACCENT_RGB = 0xB98CFF;
    /** Ring radius in blocks around the block center. */
    private static final double RING_RADIUS = 0.45D;
    private static final int BASE_RING_COUNT = 6;
    private static final int MAX_RING_COUNT = 12;
    private static final int GLINT_COUNT = 2;

    private OreProcFxClient() {}

    /** Client main thread (payload handler). {@code magnitude} = extra copies minted. */
    public static void handle(Vec3 pos, float magnitude, float packedRgb) {
        if (EclipseClientConfig.reducedFx()) {
            return;
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        int rgb = (int) packedRgb;
        if (rgb <= 0 || rgb > 0xFFFFFF) {
            rgb = ACCENT_RGB;
        }
        DustParticleOptions dust = new DustParticleOptions(new Vector3f(
                ((rgb >> 16) & 0xFF) / 255.0F,
                ((rgb >> 8) & 0xFF) / 255.0F,
                (rgb & 0xFF) / 255.0F), 0.6F);

        RandomSource random = level.random;
        int ringCount = Mth.clamp(BASE_RING_COUNT + Math.round(magnitude) * 2,
                BASE_RING_COUNT, MAX_RING_COUNT);
        for (int i = 0; i < ringCount; i++) {
            double angle = (Math.PI * 2.0D * i) / ringCount + random.nextDouble() * 0.5D;
            double cos = Math.cos(angle);
            double sin = Math.sin(angle);
            level.addParticle(dust,
                    pos.x + cos * RING_RADIUS,
                    pos.y + (random.nextDouble() - 0.35D) * 0.4D,
                    pos.z + sin * RING_RADIUS,
                    cos * 0.02D, 0.03D, sin * 0.02D);
        }
        // Item-glint pop: two bright motes drifting up out of the drop pile.
        for (int i = 0; i < GLINT_COUNT; i++) {
            level.addParticle(ParticleTypes.END_ROD,
                    pos.x + (random.nextDouble() - 0.5D) * 0.35D,
                    pos.y - 0.1D,
                    pos.z + (random.nextDouble() - 0.5D) * 0.35D,
                    0.0D, 0.04D + random.nextDouble() * 0.03D, 0.0D);
        }
    }
}
