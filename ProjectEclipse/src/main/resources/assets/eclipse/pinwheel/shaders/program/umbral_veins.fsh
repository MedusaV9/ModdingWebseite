// eclipse:umbral_veins — FX-Wave-13 N1 "Umbral-Adern" (census §6 row N1, FEATURE priority).
//
// THE BEAT: a boss drops under 20 % HP and the frame starts to DIE at its borders — black
// veins creep in from all four screen edges, branching as they reach for the centre, and
// breathe on a ~1.2 s pulse. They never touch the middle of the screen (you always see the
// fight); they only make the world feel like it is closing in on the kill.
//
// CONSTRUCTION (screen-space, zero textures — the eclipse_common law):
//   [1] Frame box field. `box = max(|q.x|, |q.y|)` is 1 at the frame edge and 0 at the
//       centre, so `depth = 1 - box` is the inward distance from the NEAREST edge in
//       frame-relative units. The growth front is a smoothstep on it: the veins reach
//       `REACH_MIN → REACH_MAX` of the way in as VeinStrength rises. That is the "wachsen"
//       — the pattern itself is static, the FRONT moves with the boss's health.
//   [2] Two edge frames, one blend. Tendrils must run PERPENDICULAR to the edge they grow
//       from, so the noise domain is anisotropic: high frequency ALONG the edge (that is
//       what separates one vein from the next), low frequency INTO the screen (that is what
//       keeps a vein coherent over its whole length). The left/right edges and the
//       top/bottom edges therefore need different domains; both are evaluated and mixed
//       across the diagonals with a narrow smoothstep, and each is skipped entirely where
//       its weight is zero (spatially coherent branches — the diagonal seam bands are a
//       handful of pixels wide).
//   [3] Ridged fBm = filaments. `1 - |2n - 1|` turns value noise into ridge lines; a
//       3-octave sum of those, thresholded, IS a vein. Branching is a SECOND, finer ridge
//       field that is only allowed to appear in the neighbourhood of a trunk — so the thin
//       side-branches always hang off a thick vein instead of floating free.
//   [4] Taper. The threshold rises with the frame-relative depth: fat veins where they meet
//       the edge, thin wisps at the tip. Combined with [1] the tips dissolve instead of
//       being cut off by the mask.
//
// LAWS: the total darkening is hard-clamped to MAX_ALPHA (0.35) — veins plus their shadow
// bed together can never take more than that, so the frame never goes to mud. At
// VeinStrength 0 the shader returns the input sample untouched (bit-identical frame) and
// the feeder drops the pass from the manager entirely.
//
// Uniforms (fed by veilfx.UmbralVeinsFx — Veil's VeilRenderTime does NOT exist in pinwheel
// post shaders, so Time comes from Java like storm_interior/rift_glitch):
//   VeinStrength — 0..1 eased dread (0 = idle; the whole shader is a no-op there)
//   Time         — pause-frozen seconds (hour wrap), drives the 1.2 s pulse + the creep
//   Detail       — 1 normal, 0 under reducedFx: flattens the pulse and freezes the creep
//                  (the static veins stay — they are boss-state feedback, not decoration)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float VeinStrength;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

const float TWO_PI = 6.2831853;
/** Hard ceiling on the total darkening (veins + bed) — the mandate's alpha budget. */
const float MAX_ALPHA = 0.35;
/** Inward reach of the growth front as a fraction of the half-frame, at strength 0 / 1. */
const float REACH_MIN = 0.10;
const float REACH_MAX = 0.70;
/** Pulse period in seconds ("pulst leicht mit ~1.2s-Periode"). */
const float PULSE_PERIOD = 1.2;
/** Peak-to-trough share of the pulse (Detail-gated — reducedFx sees a steady field). */
const float PULSE_DEPTH = 0.22;
/** Vein spacing along an edge (noise cells per half-frame-height). */
const float ALONG_FREQ = 7.0;
/** Vein coherence into the screen — deliberately low: a vein is a LONG thing. */
const float INTO_FREQ = 1.9;
/** Ridge threshold at the edge (fat trunks) and at the growth front (thin wisps). */
const float TRUNK_EDGE = 0.66;
const float TRUNK_TIP = 0.88;
/**
 * Width of the threshold ramp. This is what makes a vein a VEIN: a full
 * `smoothstep(threshold, 1.0, ridge)` spreads the ridge over its whole remaining range and
 * paints soft smudges — a narrow band clips the ridge into a hard-edged filament.
 */
const float TRUNK_BAND = 0.16;
const float BRANCH_BAND = 0.11;
/** The near-black the veins are painted in — void violet, not pure black. */
const vec3 VEIN_COLOR = vec3(0.014, 0.004, 0.030);

/** 3-octave ridged fBm in [0,1]: `1 - |2n - 1|` folds value noise into ridge lines. */
float veinRidge(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    for (int i = 0; i < 3; i++) {
        sum += (1.0 - abs(efxNoise(p) * 2.0 - 1.0)) * amp;
        norm += amp;
        p = p * 2.11 + vec2(19.7, 11.3);
        amp *= 0.55;
    }
    return sum / norm;
}

/**
 * One edge frame's vein field in [0,1].
 *   along — coordinate PARALLEL to the edge, already aspect-normalized to half-frame-height
 *           units so filament spacing matches on the horizontal and vertical edges
 *   into  — inward distance in the same units (keeps vein length pixel-consistent)
 *   taper — inward distance as a fraction of the CURRENT growth front (0 at the edge, 1 at
 *           the front). Normalizing against the front and not against the frame is what
 *           makes the veins grow: at low strength they are short stubs, at full strength
 *           the same filaments are stretched all the way in.
 *   seed  — per-edge domain offset, so opposite edges are not mirror images of each other
 *   creep — slow warp phase (0 under reducedFx: the veins hold perfectly still)
 */
float veinField(float along, float into, float taper, float seed, float creep) {
    // Domain warp: without it every vein is a straight radial spike. The warp runs on the
    // ALONG axis only — a vein may wander sideways, it may not stop reaching inward — and
    // it GROWS with depth, so the bundle splays apart the further it reaches instead of
    // staying a comb of parallel bristles.
    float warp = efxNoise(vec2(into * 1.5 + seed, along * 2.6 + creep)) - 0.5;
    vec2 base = vec2(along * ALONG_FREQ + warp * (1.1 + 2.4 * into), into * INTO_FREQ + seed);

    float trunkRidge = veinRidge(base);
    // Per-vein reach: a slow roll along the edge makes some veins stall just inside the
    // frame while their neighbours push deep. Without it every vein ends at the same
    // depth and the whole thing reads as fur, not as growth.
    float reachRoll = efxNoise(vec2(along * 1.9 + seed * 0.37, 3.1));
    float threshold = mix(TRUNK_EDGE, TRUNK_TIP,
            clamp(taper * (0.85 + 1.70 * reachRoll), 0.0, 1.0));
    float trunk = smoothstep(threshold, threshold + TRUNK_BAND, trunkRidge);

    // Verästelung: a finer ridge field, gated to the NEIGHBOURHOOD of a trunk (the band
    // just below the trunk threshold), so side-branches always hang off a real vein.
    float near = smoothstep(threshold - 0.22, threshold, trunkRidge);
    float branchRidge = veinRidge(base * vec2(2.7, 1.9) + vec2(41.3, 7.9));
    float branch = smoothstep(threshold, threshold + BRANCH_BAND, branchRidge) * near * 0.85;

    return clamp(max(trunk, branch), 0.0, 1.0);
}

/**
 * Note on the shape of this function: the two idle exits are nested branches instead of the
 * `if (...) { fragColor = ...; return; }` early-out the other post shaders use. That is a
 * deliberate workaround, not a style choice. glsl-processor 0.2.3 NPEs in
 * GlslReturnNode.hashCode when it has to hash a function whose body holds a value-less
 * `return`, which it does as soon as the tree carries any node MARKER — and a marker is
 * registered by a stray hash character anywhere in the source, comments included. Veil
 * swallows that NPE as "Couldn't parse shader", never registers the program, and the
 * pipeline then fails at runtime with "Failed to find post shader". Keeping main() free of
 * value-less returns makes this shader immune to that landmine for good.
 * (eclipse:black_hole is currently tripping exactly this — see the wave-13 handover.)
 */
void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float strength = clamp(VeinStrength, 0.0, 1.0);

    if (strength > 0.001) { // else: idle — colour is passed through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);

        vec2 q = texCoord * 2.0 - 1.0;
        vec2 aq = abs(q);
        // [1] Growth front: 1 hard against the frame edge, 0 past the reach of the veins.
        float depth = 1.0 - max(aq.x, aq.y);
        float reach = mix(REACH_MIN, REACH_MAX, strength);
        float grow = 1.0 - smoothstep(reach * 0.30, reach, depth);

        if (grow > 0.001) { // else: the untouched centre — nothing to do
            vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
            float aspect = screenSize.x / max(screenSize.y, 1.0);
            float creep = detail * Time * 0.06; // barely-there writhe; frozen by reducedFx

            // [2] The two edge frames. `wx` is 1 where a side edge is nearest, 0 where a
            // top/bottom edge is; only the diagonal seam bands evaluate both. Opposite
            // edges get different seeds — the sign flip lands where the frame's own weight
            // is already 0 (on the centre cross, where `grow` has long since died), so it
            // can never show as a hard line.
            float wx = smoothstep(-0.05, 0.05, aq.x - aq.y);
            float taper = depth / reach; // 0 at the edge, 1 at the current growth front
            float sideVeins = 0.0;
            if (wx > 0.001) {
                sideVeins = veinField(q.y, (1.0 - aq.x) * aspect, taper,
                        q.x >= 0.0 ? 0.0 : 53.1, creep);
            }
            float capVeins = 0.0;
            if (wx < 0.999) {
                capVeins = veinField(q.x * aspect, 1.0 - aq.y, taper,
                        q.y >= 0.0 ? 131.7 : 77.9, creep);
            }
            float veins = mix(capVeins, sideVeins, wx);

            // The ~1.2 s breath. reducedFx flattens it to a steady field (photosensitivity:
            // a full-frame pulsing darkness is exactly what that toggle exists to kill).
            float pulse = 1.0 - PULSE_DEPTH * detail
                    + PULSE_DEPTH * detail * (0.5 + 0.5 * sin(TWO_PI * Time / PULSE_PERIOD));

            // Veins plus the faint shadow bed they sit in, clamped TOGETHER to the budget.
            float dark = veins * grow * strength * pulse;
            float bed = grow * strength * 0.14 * pulse;
            float amount = clamp((dark + bed) * MAX_ALPHA, 0.0, MAX_ALPHA);
            color = mix(color, VEIN_COLOR, amount);

            // Banding guard: the growth front is a long smooth gradient in the dark range.
            color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * amount);
        }
    }

    fragColor = vec4(color, 1.0);
}
