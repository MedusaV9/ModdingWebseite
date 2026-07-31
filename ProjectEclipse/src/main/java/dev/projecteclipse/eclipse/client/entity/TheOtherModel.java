package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.entity.TheOtherEntity;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.PartPose;
import net.minecraft.client.model.geom.builders.CubeDeformation;
import net.minecraft.client.model.geom.builders.CubeListBuilder;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.geom.builders.MeshDefinition;
import net.minecraft.client.model.geom.builders.PartDefinition;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The Other's humanoid model (MOB-GLITCH): the EXACT vanilla mesh — the doppelganger
 * must stay silhouette-identical to the uniform-skinned players at a glance (spec §1.1
 * regression guard, census law §5-G7) — plus three tiny FLOATING FRAGMENT cubes parented
 * to the head and body. The fragments sample the uniform skin's own texture regions
 * (torn-off chunks, not new art) and stay {@code visible = false} while the mannequin is
 * passive, so the disguise holds until the REVEAL:
 *
 * <ul>
 *   <li><b>Looming idle</b> (passive + standing): the vanilla idle arm-bob is zeroed —
 *       arms dead-straight, mannequin-still — with a slight whole-torso lean-in and the
 *       stare tipped a few degrees down THROUGH the player. A person who breathes
 *       wrong.</li>
 *   <li><b>Reveal</b> (aggro — {@code isAggressive()} syncs with the melee goal, the
 *       same beat as the 180° head snap): the fragments TEAR OUT of the silhouette over
 *       {@value #DETACH_TICKS} ticks (overshoot-and-settle, with a front-loaded tumble
 *       kick), then settle into three STAGGERED ORBITS — three different orbit planes,
 *       mutually incommensurate periods, per-entity phase seeds and a counter-rotating
 *       hip — so no two fragments (and no two Others) ever move in lockstep. The
 *       silhouette stays; the personhood does not.</li>
 *   <li><b>Retract</b> (aggro dropped): the fragments freeze their orbits and get pulled
 *       back into the silhouette over {@value #RETRACT_TICKS} ticks while shrinking —
 *       the mask reassembles instead of the shards popping off-screen.</li>
 * </ul>
 *
 * <p>MC4 polish note (frame-leak law): vanilla {@code HumanoidModel.setupAnim} never
 * writes {@code head.zRot}, so every channel this model touches that vanilla does not
 * reset each frame ({@code head.zRot}, all fragment channels) is written ABSOLUTELY on
 * every {@code setupAnim} call in both branches — a {@code +=} there accumulates per
 * FRAME and leaks across entities through the shared model instance.</p>
 */
@OnlyIn(Dist.CLIENT)
public class TheOtherModel extends HumanoidModel<TheOtherEntity> {
    /** Fragment indices into the kinematics tables. */
    static final int FRAG_CROWN = 0;
    static final int FRAG_SHOULDER = 1;
    static final int FRAG_HIP = 2;

    /**
     * Rest offsets of the fragments (model space, y-down; vanilla right = −x), chosen
     * to CLEAR the limb volumes (arms occupy |x| 4–8 for y 2–14): crown floats above
     * the head's right corner, shoulder hangs outboard of the right arm, hip hovers
     * behind the left hip. Crown lives in HEAD space, the other two in BODY space.
     */
    private static final float[][] FRAG_REST = {
            {-5.5F, -11.5F, 0.0F},  // crown
            {-10.0F, 1.0F, 0.5F},   // shoulder
            {5.8F, 9.5F, 4.5F},     // hip
    };
    /**
     * Emergence points INSIDE the silhouette (head box |x|,|z| ≤ 4 / y −8..0; body
     * |x| ≤ 4, |z| ≤ 2): at reveal start each fragment sits here — visually still part
     * of the body — and tears outward to its rest offset.
     */
    private static final float[][] FRAG_EMERGE = {
            {-2.5F, -7.0F, 0.0F},   // upper right of the head
            {-6.0F, 1.0F, 0.5F},    // out of the right shoulder/arm root
            {3.0F, 10.0F, 2.0F},    // out of the left hip's back face
    };
    /**
     * Orbit angular speeds (rad/tick). Deliberately mutually incommensurate
     * (0.113/0.0787 ≈ 1.44, 0.0787/0.0593 ≈ 1.33, 0.113/0.0593 ≈ 1.91): the three
     * fragments drift through ever-changing constellations instead of a repeating
     * pattern (near-repeat > 1 min, harness §5 of the MC4 report).
     */
    private static final float[] ORBIT_SPEED = {0.113F, 0.0787F, 0.0593F};
    /** Secondary bob/sway speeds — a second, unrelated frequency per fragment. */
    private static final float[] BOB_SPEED = {0.073F, 0.053F, 0.089F};
    /** Orbit radii / bob amplitudes in model pixels — suspension drift, not a carousel. */
    private static final float[] ORBIT_RADIUS = {1.1F, 0.85F, 0.9F};
    private static final float[] BOB_AMPLITUDE = {0.5F, 0.3F, 0.4F};
    /** Lazy tumble rates (rad/tick); the hip counter-rotates against crown/shoulder. */
    private static final float[] TUMBLE_SPEED = {0.021F, 0.017F, -0.013F};
    /** Wobble (secondary rotation axis) speeds — slow, sub-tumble. */
    private static final float[] WOBBLE_SPEED = {0.045F, 0.049F, 0.041F};
    private static final float[] WOBBLE_AMPLITUDE = {0.18F, 0.15F, 0.16F};

    /**
     * Detach window (ticks): fragments tear out, overshoot ~10% past rest, settle.
     * Aliased from the entity — single source of truth shared with the client clocks
     * (the re-aggro backdate in {@code TheOtherEntity.tick} depends on these values).
     */
    static final float DETACH_TICKS = TheOtherEntity.REVEAL_DETACH_TICKS;
    /**
     * Retract window (ticks): on aggro loss the fragments SUCK BACK into the silhouette
     * (frozen orbit, smoothstepped pull to the emergence points, shrinking) instead of
     * vanishing in one frame — the mask reassembles.
     */
    static final float RETRACT_TICKS = TheOtherEntity.REVEAL_RETRACT_TICKS;
    /**
     * Front-loaded tumble kick: each fragment gets an extra {@code TUMBLE_SPEED × 40}
     * radians of twist compressed into the detach beat (they RIP off, then drift).
     */
    private static final float DETACH_KICK_TICKS = 40.0F;
    /** Reveal head cant, radians (~7°) — human angle, wrong execution. */
    private static final float REVEAL_HEAD_CANT = 0.12F;
    /** Looming lean-in / stare-down, radians. */
    private static final float LOOM_LEAN = 0.05F;
    private static final float LOOM_STARE_DOWN = 0.09F;

    private final ModelPart fragCrown;
    private final ModelPart fragShoulder;
    private final ModelPart fragHip;
    /** Reusable channel buffer ({@link #fragmentPose}) — render thread only. */
    private final float[] pose = new float[7];

    public TheOtherModel(ModelPart root) {
        super(root);
        this.fragCrown = this.head.getChild("frag_crown");
        this.fragShoulder = this.body.getChild("frag_shoulder");
        this.fragHip = this.body.getChild("frag_hip");
    }

    /**
     * Vanilla humanoid mesh (identical silhouette) + the three fragment cubes. The
     * texOffs sample existing uniform-skin regions on the 64x64 player layout — head
     * strip, jacket top, arm strip — so the shards read as chunks OF the body.
     */
    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = HumanoidModel.createMesh(CubeDeformation.NONE, 0.0F);
        PartDefinition root = mesh.getRoot();
        root.getChild("head").addOrReplaceChild("frag_crown",
                CubeListBuilder.create().texOffs(0, 0)
                        .addBox(-1.0F, -1.0F, -1.0F, 2.0F, 2.0F, 2.0F),
                PartPose.offset(FRAG_REST[FRAG_CROWN][0], FRAG_REST[FRAG_CROWN][1],
                        FRAG_REST[FRAG_CROWN][2]));
        PartDefinition body = root.getChild("body");
        body.addOrReplaceChild("frag_shoulder",
                CubeListBuilder.create().texOffs(16, 16)
                        .addBox(-1.5F, -1.5F, -1.5F, 3.0F, 3.0F, 3.0F),
                PartPose.offset(FRAG_REST[FRAG_SHOULDER][0], FRAG_REST[FRAG_SHOULDER][1],
                        FRAG_REST[FRAG_SHOULDER][2]));
        body.addOrReplaceChild("frag_hip",
                CubeListBuilder.create().texOffs(40, 16)
                        .addBox(-1.0F, -1.0F, -1.0F, 2.0F, 2.0F, 2.0F),
                PartPose.offset(FRAG_REST[FRAG_HIP][0], FRAG_REST[FRAG_HIP][1],
                        FRAG_REST[FRAG_HIP][2]));
        return LayerDefinition.create(mesh, 64, 64);
    }

    @Override
    public void setupAnim(TheOtherEntity entity, float limbSwing, float limbSwingAmount,
            float ageInTicks, float netHeadYaw, float headPitch) {
        super.setupAnim(entity, limbSwing, limbSwingAmount, ageInTicks, netHeadYaw, headPitch);
        boolean revealed = entity.isAggressive();
        float retractAge = entity.clientRetractAge(ageInTicks);
        boolean retracting = !revealed && retractAge >= 0.0F && retractAge < RETRACT_TICKS;
        this.fragCrown.visible = revealed || retracting;
        this.fragShoulder.visible = revealed || retracting;
        this.fragHip.visible = revealed || retracting;
        int seed = entity.getId();
        if (revealed) {
            float revealAge = entity.clientRevealAge(ageInTicks);
            fragmentPose(FRAG_CROWN, revealAge, seed, this.pose);
            applyPose(this.fragCrown, this.pose);
            fragmentPose(FRAG_SHOULDER, revealAge, seed, this.pose);
            applyPose(this.fragShoulder, this.pose);
            fragmentPose(FRAG_HIP, revealAge, seed, this.pose);
            applyPose(this.fragHip, this.pose);
            // Head cocks 7° off plumb on the same overshoot-ease as the detach.
            this.head.zRot = REVEAL_HEAD_CANT
                    * easeOutBack(Math.min(1.0F, revealAge / DETACH_TICKS));
        } else if (retracting) {
            // Aggro dropped: reassemble. Orbit clock frozen at the drop, fragments pull
            // back to their emergence points and shrink; the head levels back to plumb.
            float retract = retractAge / RETRACT_TICKS;
            float frozenAge = entity.clientLastRevealTicks();
            retractPose(FRAG_CROWN, frozenAge, retract, seed, this.pose);
            applyPose(this.fragCrown, this.pose);
            retractPose(FRAG_SHOULDER, frozenAge, retract, seed, this.pose);
            applyPose(this.fragShoulder, this.pose);
            retractPose(FRAG_HIP, frozenAge, retract, seed, this.pose);
            applyPose(this.fragHip, this.pose);
            this.head.zRot = REVEAL_HEAD_CANT * (1.0F - smoothstep01(retract));
        } else {
            this.head.zRot = 0.0F; // vanilla never writes zRot — absolute reset, no leak
            if (limbSwingAmount < 0.05F) {
                // Looming idle: mannequin-still arms (the vanilla bob is the tell that a
                // body is alive — remove it), slight lean-in, stare tipped down at you.
                this.rightArm.xRot = 0.0F;
                this.rightArm.zRot = 0.02F;
                this.leftArm.xRot = 0.0F;
                this.leftArm.zRot = -0.02F;
                this.body.xRot = LOOM_LEAN;
                this.head.xRot += LOOM_STARE_DOWN;
            }
        }
        this.hat.copyFrom(this.head); // Re-sync: super copied before our head tweaks.
    }

    /**
     * Pure fragment kinematics — package-visible so the MC4 offline harness can table
     * the REAL values per tick (report §5). Channels written into {@code out}:
     * {@code [x, y, z, xRot, yRot, zRot, scale]} (positions in model px, rotations rad).
     *
     * <p>Composition: detach-lerp from {@link #FRAG_EMERGE} to {@link #FRAG_REST} on an
     * overshoot ease, plus a phase-staggered orbit (per-entity seed + a hard 120° offset
     * per fragment) that ramps in with the detach; tumble = lazy continuous spin with a
     * front-loaded kick; scale pops 0.25 → ~1.07 → 1.0 on the same ease.</p>
     *
     * @param fragment {@link #FRAG_CROWN} (head space) / {@link #FRAG_SHOULDER} /
     *                 {@link #FRAG_HIP} (body space)
     * @param revealAge fractional ticks since the aggro reveal began (≥ 0, resets each
     *                  reveal — keeps all angle arguments small and precise)
     * @param entityId per-entity orbit phase seed (two Others never sync)
     */
    static void fragmentPose(int fragment, float revealAge, int entityId, float[] out) {
        float detach = Math.min(1.0F, revealAge / DETACH_TICKS);
        float ease = easeOutBack(detach);
        // Per-entity base phase + a guaranteed 120° stagger between the fragments.
        float phase = (hash(entityId, 0x0F17) >>> (fragment * 8) & 0xFF) * (Mth.TWO_PI / 256.0F)
                + fragment * (Mth.TWO_PI / 3.0F);
        float orbit = ORBIT_SPEED[fragment] * revealAge + phase;
        float bob = BOB_SPEED[fragment] * revealAge + phase * 1.7F;
        // The orbit contribution ramps in linearly with the detach (the tear-out path
        // itself carries the overshoot; doubling it up reads as rubber, not shards).
        float orbitIn = detach;

        float x = Mth.lerp(ease, FRAG_EMERGE[fragment][0], FRAG_REST[fragment][0]);
        float y = Mth.lerp(ease, FRAG_EMERGE[fragment][1], FRAG_REST[fragment][1]);
        float z = Mth.lerp(ease, FRAG_EMERGE[fragment][2], FRAG_REST[fragment][2]);
        switch (fragment) {
            case FRAG_CROWN -> { // horizontal orbit circle + vertical bob
                x += Mth.cos(orbit) * ORBIT_RADIUS[fragment] * orbitIn;
                z += Mth.sin(orbit) * ORBIT_RADIUS[fragment] * orbitIn;
                y += Mth.sin(bob) * BOB_AMPLITUDE[fragment] * orbitIn;
            }
            case FRAG_SHOULDER -> { // frontal ellipse (x/y) + depth sway
                // x-amplitude 0.55×R: keeps the cube's inner face outboard of the arm
                // volume (arm outer face x = −8) even at the inward orbit extreme.
                x += Mth.cos(orbit) * ORBIT_RADIUS[fragment] * 0.55F * orbitIn;
                y += Mth.sin(orbit) * ORBIT_RADIUS[fragment] * orbitIn;
                z += Mth.sin(bob) * BOB_AMPLITUDE[fragment] * orbitIn;
            }
            default -> { // hip: horizontal orbit, COUNTER-rotating, + vertical bob
                x += Mth.cos(-orbit) * ORBIT_RADIUS[fragment] * orbitIn;
                z += Mth.sin(-orbit) * ORBIT_RADIUS[fragment] * orbitIn;
                y += Mth.sin(bob) * BOB_AMPLITUDE[fragment] * orbitIn;
            }
        }
        out[0] = x;
        out[1] = y;
        out[2] = z;

        // Tumble: lazy continuous spin + a front-loaded detach kick in the same
        // direction (each fragment's own rate/sign — the hip counter-tumbles).
        float kick = 1.0F - (1.0F - detach) * (1.0F - detach);
        float tumble = TUMBLE_SPEED[fragment] * (revealAge + DETACH_KICK_TICKS * kick);
        float wobble = Mth.sin(WOBBLE_SPEED[fragment] * revealAge + phase)
                * WOBBLE_AMPLITUDE[fragment] * orbitIn;
        switch (fragment) {
            case FRAG_CROWN -> {
                out[3] = wobble;
                out[4] = tumble;
                out[5] = 0.0F;
            }
            case FRAG_SHOULDER -> {
                out[3] = 0.0F;
                out[4] = wobble;
                out[5] = tumble;
            }
            default -> {
                out[3] = tumble;
                out[4] = 0.0F;
                out[5] = wobble;
            }
        }
        out[6] = 0.25F + 0.75F * ease; // pop: 0.25 → ~1.07 (overshoot) → 1.0
    }

    /**
     * Retract kinematics (aggro dropped): the fragment holds its FROZEN orbital pose
     * (t = {@code frozenAge}, the reveal duration at the drop — continuous with the last
     * revealed frame) and is pulled back to its emergence point on a smoothstep while
     * shrinking to ~30%; the invisibility flip then happens INSIDE the silhouette.
     * Package-visible for the MC4 offline harness (report §5).
     *
     * @param retract raw 0..1 over {@link #RETRACT_TICKS}
     */
    static void retractPose(int fragment, float frozenAge, float retract, int entityId, float[] out) {
        fragmentPose(fragment, frozenAge, entityId, out);
        float ease = smoothstep01(retract);
        out[0] = Mth.lerp(ease, out[0], FRAG_EMERGE[fragment][0]);
        out[1] = Mth.lerp(ease, out[1], FRAG_EMERGE[fragment][1]);
        out[2] = Mth.lerp(ease, out[2], FRAG_EMERGE[fragment][2]);
        out[6] *= 1.0F - 0.7F * ease;
    }

    /** Writes all seven channels ABSOLUTELY (shared model instance — no stale state). */
    private static void applyPose(ModelPart part, float[] pose) {
        part.x = pose[0];
        part.y = pose[1];
        part.z = pose[2];
        part.xRot = pose[3];
        part.yRot = pose[4];
        part.zRot = pose[5];
        part.xScale = pose[6];
        part.yScale = pose[6];
        part.zScale = pose[6];
    }

    /** Overshoot ease (easeOutBack, ~10% peak at t ≈ 0.58): 0 → 1.10 → 1. */
    static float easeOutBack(float t) {
        float u = t - 1.0F;
        return 1.0F + u * u * (2.70158F * u + 1.70158F);
    }

    /** Plain smoothstep on a pre-clamped 0..1 input. */
    static float smoothstep01(float t) {
        return t * t * (3.0F - 2.0F * t);
    }

    /** Small deterministic mix (skin-generator family) — stable orbit phases per entity. */
    private static int hash(int a, int b) {
        int h = (a * 0x27D4EB2D) ^ (b * 0x9E3779B9) ^ 0x0EC15C1E;
        h ^= h >>> 15;
        h *= 0x2C1B3C6D;
        h ^= h >>> 12;
        return h;
    }
}
