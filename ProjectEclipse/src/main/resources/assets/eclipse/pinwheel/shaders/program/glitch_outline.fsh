// eclipse:glitch_outline — GLITCHZONE flagship (TRANSITION priority): the world renders
// BLACK and only EDGE OUTLINES remain, a wireframe/thermal-scanner readout.
//
// WAVE-13 B4 "TIEFEN-TRACE". The census asked for an edge trace that reads DEPTH instead of
// sticking to the frame, and the brief asked for clean object silhouettes on black. Three
// things changed, all of them driven by DiffuseDepthSampler rather than by colour:
//
//   [O1] The tap cross is DEPTH-SCALED. A fixed one-texel cross draws the same hairline on a
//        block two metres away and on a mountain — thickness carries no information and the
//        readout reads flat. The cross now spans ~2.6 texels up close and tightens to a
//        single texel past ~34 blocks, so line weight IS the distance cue.
//   [O2] The silhouette term is SIGNED. An undirected depth Laplacian fires on BOTH sides of
//        a discontinuity (the object and the wall behind it), which is why the shipped edges
//        read as soft bands. `behind` measures how much FARTHER the farthest neighbour sits,
//        so it is positive only on the NEAR side of the step: the trace lands on the object
//        and produces a true cut-out. That is the "everything black, only outlines" read.
//   [O5] A depth TRACE PLANE racks from 2 out to 220 blocks and back, EXPONENTIALLY (depth
//        reads logarithmically — a linear rack crawls through the near field and then
//        teleports through the distance). Edges inside its slab flare and everything it has
//        already passed keeps a short phosphor afterglow, so the wireframe is drawn INTO the
//        scene instead of sitting on the glass. Its 6.25 s period divides the 100 s Time
//        wrap, so the rack never jumps. This is deliberately a PLANE receding from the
//        camera — glitch_void owns radial shells around an origin.
//
// The crease (depth Laplacian), view-normal disagreement and Roberts luma terms survive as
// secondary traces, reweighted so geometry wins.
//
// F-102 GLITCH-FAMILY POLISH (two changes, zero new texture taps):
//   [O6] TRUE BLACK CRUSH. The fill wash drops 0.16 -> 0.055 and runs through a 1.6 gamma,
//        so a mid-grey scene (luma 0.4) keeps ~1.3% of its light instead of ~6% — the world
//        is BLACK, only real highlights leave a breath of mass. This is the user's literal
//        mandate ("alles schwarz und nur gruene Outlines"); the outlines alone must carry
//        the read, which [O7] pays for.
//   [O7] TWO-TIER EDGE GLOW from the silhouette raw value that was already in a register:
//        a wide soft SKIRT (low smoothstep band, pure accent colour) under the existing
//        binary trace, and a HOT CORE (high band) lifted toward white — the overdriven-
//        phosphor read. Same data, two thresholds: the line gets a luminous falloff
//        without a single extra tap. The white lift is capped at 35% so a commanded hue
//        (outline_red, outline_cyan) still owns the core instead of clipping to white.
//
// HARDENING: every depth-derived term is gated by gzDepthValid and the reconstructed normals
// go through gzNormalizeSafe. On a dead depth attachment (flat 0.0) the five reconstruction
// taps collapse onto one point and a raw normalize() would return NaN across the whole
// frame; the pass now degrades to its Roberts-luma trace instead.
//
// Fed per frame by client.GlitchZoneFx through the VeilPostController row (never under an
// Iris shaderpack): Strength (0..1 zone ramp — MUST be a no-op at 0), Time (wall-clock
// seconds), Detail (0 under reduced FX: the trace plane parks at 24 blocks and sweep bar,
// flicker and grain freeze/flatten; the scanner grade itself survives),
// AccentColor/AccentAmount (F-049: the phosphor hue — at amount 0 the shipped scanner green,
// luma-matched to any commanded colour at 1; the dim fill wash and the grain ride the same
// accent so the readout stays one colour).
//
// No value-less `return` in main() — see the glsl-processor note in umbral_veins.fsh: a
// stray hash character anywhere in this file (a hex colour in a comment is enough) arms a
// parser NPE that silently unregisters the whole pipeline.
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Strength;
uniform float Time;
uniform float Detail;
uniform vec3 AccentColor;
uniform float AccentAmount;

in vec2 texCoord;

out vec4 fragColor;

// Scanner phosphor palette.
const vec3 EDGE_GREEN = vec3(0.10, 1.00, 0.32);
const vec3 FILL_GREEN = vec3(0.04, 0.22, 0.09);

// [O1] Trace width in texels at point-blank range, and the distance it has tightened to one
// texel over.
const float TRACE_WIDE = 2.6;
const float TRACE_WIDE_RANGE = 34.0;
// [O5] Rack of the depth trace plane: near/far bound in blocks, period in seconds (a divisor
// of the 100 s Time wrap), and the distance it parks at under reduced FX.
const float TRACE_NEAR = 2.0;
const float TRACE_FAR = 220.0;
const float TRACE_PERIOD = 6.25;
const float TRACE_PARK = 24.0;
// [O6] How much of the scene's own luma survives as a fill wash under the readout, and the
// gamma that crushes it. 0.055 with gamma 1.6 keeps torches/sky-lit faces as a whisper and
// sends everything mid-grey and darker to true black — the mandate look.
const float FILL_GAIN = 0.055;
const float FILL_GAMMA = 1.6;
// [O7] Two-tier glow bands on the silhouette raw value: skirt (soft, wide) and hot core
// (narrow, white-lifted). WHITE_LIFT is the cap on how far the core leaves the accent hue.
const float SKIRT_GAIN = 0.40;
const float CORE_GAIN = 0.80;
// 0.35, not higher: at 0.45 the core's blue channel overtakes the green and the hottest
// pixels read cyan-white instead of "green burning out to white" (iteration-1 finding).
const float WHITE_LIFT = 0.35;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
        float near = VeilCamera.NearPlane;
        float far = VeilCamera.FarPlane;

        // Centre tap first: the cross spacing is a function of the centre distance.
        float dC = texture(DiffuseDepthSampler, texCoord).r;
        float depthOk = gzDepthValid(dC);
        float lC = gzLinearDepth(dC, near, far);

        // [O1] Depth-scaled trace width.
        float width = mix(TRACE_WIDE, 1.0, clamp(lC / TRACE_WIDE_RANGE, 0.0, 1.0));
        vec2 stepX = vec2(texel.x * width, 0.0);
        vec2 stepY = vec2(0.0, texel.y * width);

        // 4-tap cross: raw depth (for position reconstruction) + linearized (for edges).
        float dR = texture(DiffuseDepthSampler, texCoord + stepX).r;
        float dL = texture(DiffuseDepthSampler, texCoord - stepX).r;
        float dU = texture(DiffuseDepthSampler, texCoord + stepY).r;
        float dD = texture(DiffuseDepthSampler, texCoord - stepY).r;
        float lR = gzLinearDepth(dR, near, far);
        float lL = gzLinearDepth(dL, near, far);
        float lU = gzLinearDepth(dU, near, far);
        float lD = gzLinearDepth(dD, near, far);

        // [O2] Silhouette: signed depth step, normalized by the centre distance so the
        // threshold means "a step of this many percent of the viewing distance" at any range.
        //
        // Per axis the term is min(behind, planar residual). `behind` alone (how much farther
        // the farther neighbour sits) is positive on the near side of a real depth step, but
        // it is ALSO large on any surface seen at a grazing angle — a floor stretching to the
        // horizon steps several centimetres per texel, so the plain signed test lit the whole
        // ground and buried the "black world, only outlines" read. The planar residual
        // |lR + lL - 2*lC| is ~0 on a plane at ANY slant and equals the step height at a
        // silhouette, so the min() keeps true cut-outs and rejects slanted planes.
        float behindX = max(lR, lL) - lC;
        float behindY = max(lU, lD) - lC;
        float behind = max(min(behindX, abs(lR + lL - 2.0 * lC)),
                min(behindY, abs(lU + lD - 2.0 * lC)));
        float rawSil = behind / max(lC * 0.045, 0.22);
        float silhouette = smoothstep(0.30, 1.20, rawSil);
        // [O7] Two glow tiers off the same raw value: no new taps, just two more thresholds.
        // Skirt starts at 0.10, not lower — block-stair micro-steps sit right under that,
        // and letting them glow would grey the crushed world back up (iteration-1 finding).
        float silSkirt = smoothstep(0.10, 0.60, rawSil);
        float silCore = smoothstep(0.95, 1.90, rawSil);

        // [O3] Crease: second derivative of linear depth. Convex/concave folds that share a
        // depth plane; ~0 on planar runs at any slant, so grazing floors do not false-edge.
        float crease = smoothstep(0.06, 0.22,
                (abs(lR + lL - 2.0 * lC) + abs(lU + lD - 2.0 * lC)) / max(lC * 0.5, 0.5));

        // [O4] Normal disagreement: view-space normals from the reconstructed position cross
        // products of the right/up vs left/down tap pairs — corners and face changes
        // disagree, flats agree. gzNormalizeSafe keeps a dead depth buffer from going NaN.
        vec3 pC = screenToViewSpace(texCoord, dC).xyz;
        vec3 pR = screenToViewSpace(texCoord + stepX, dR).xyz;
        vec3 pL = screenToViewSpace(texCoord - stepX, dL).xyz;
        vec3 pU = screenToViewSpace(texCoord + stepY, dU).xyz;
        vec3 pD = screenToViewSpace(texCoord - stepY, dD).xyz;
        vec3 n1 = gzNormalizeSafe(cross(pR - pC, pU - pC), vec3(0.0, 0.0, 1.0));
        vec3 n2 = gzNormalizeSafe(cross(pC - pL, pC - pD), vec3(0.0, 0.0, 1.0));
        float normalEdge = smoothstep(0.10, 0.55, 1.0 - dot(n1, n2));

        // Luminance term (Roberts on the colour taps): block/texture boundaries as faint
        // secondary traces, and the ONLY term left standing on a dead depth buffer.
        float lumaEdge = abs(gzLuma(texture(DiffuseSampler0, texCoord + stepX).rgb)
                        - gzLuma(texture(DiffuseSampler0, texCoord - stepX).rgb))
                + abs(gzLuma(texture(DiffuseSampler0, texCoord + stepY).rgb)
                        - gzLuma(texture(DiffuseSampler0, texCoord - stepY).rgb));
        lumaEdge = smoothstep(0.12, 0.45, lumaEdge) * 0.35;

        float sky = step(0.9999, dC);
        // Sky pixels have no geometry: silhouette edges against sky come from the NEIGHBOR
        // taps (their depth terms fire on the geometry side), so the sky itself stays pure
        // void. Distant edges thin out instead of dissolving into shimmer.
        float distanceFade = 1.0 / (1.0 + lC * 0.006);
        float geometryEdge = (silhouette + crease * 0.55 + normalEdge * 0.60) * depthOk;
        float edge = clamp(geometryEdge + lumaEdge, 0.0, 1.0) * (1.0 - sky) * distanceFade;

        // [O5] Depth trace plane + its afterglow. The slab widens with distance so the plane
        // keeps a constant apparent thickness as it recedes; the tail decays over a window
        // that grows the same way, but only a THIRD as fast — a tail proportional to the full
        // rack distance would still be lighting the whole near field when the plane reaches
        // 220 blocks, and the rack reset would then read as a full-frame flash-off.
        // Parked (static depth band) under reduced FX.
        //
        // The `max(..., 0.0)` inside the tail is not cosmetic. Sky and far terrain sit far
        // BEHIND the plane, so the raw difference goes strongly negative and exp() of it
        // overflows to +inf in fp32 (a 512-block far plane against a 2-block rack start is
        // already e^108); step() then multiplies 0 * inf = NaN and the NaN paints the whole
        // frame for the first second of every rack. Clamping the argument keeps the factor
        // at exactly 1.0 out there, where step() legitimately zeroes it.
        float rack = TRACE_NEAR * pow(TRACE_FAR / TRACE_NEAR, fract(Time / TRACE_PERIOD));
        float planeDist = mix(TRACE_PARK, rack, detail);
        float traceHit = exp(-abs(lC - planeDist) / max(planeDist * 0.22, 0.8));
        float traceTail = step(lC, planeDist)
                * exp(-max(planeDist - lC, 0.0) / (planeDist * 0.35 + 4.0)) * 0.35;
        float trace = (traceHit + traceTail) * (1.0 - sky) * depthOk;

        // Screen-space scanner layers: a slow sweep bar rolling down, per-line flicker and a
        // breath of static — all frozen/flattened under reduced FX. The bar is quieter than
        // it shipped so the depth rack owns the motion.
        float flicker = mix(1.0, 0.82 + 0.18 * efxNoise(vec2(Time * 24.0, texCoord.y * 3.0)), detail);
        float sweepPos = fract(Time * 0.11) * 1.3 - 0.15;
        float sweep = exp(-abs(texCoord.y - sweepPos) * 40.0) * detail;
        float grain = (efxHash(texCoord * vec2(853.0, 997.0) + fract(Time * 7.0)) - 0.5) * 0.05 * detail;

        // Accent swap: the edge phosphor is luma-matched, the fill wash and the grain are
        // derived from the SAME hue (their shipped values are the edge green at ~22% and a
        // green/blue grain split — both within a hair of accent * k, so amount 0 is a no-op).
        vec3 edgeAccent = gzAccent(EDGE_GREEN, AccentColor, AccentAmount);
        vec3 fillAccent = mix(FILL_GREEN, edgeAccent * (gzLuma(FILL_GREEN) / gzLuma(EDGE_GREEN)),
                clamp(AccentAmount, 0.0, 1.0));
        vec3 grainAccent = mix(vec3(0.0, 1.0, 0.4), edgeAccent / max(gzLuma(edgeAccent), 0.001) * 0.65,
                clamp(AccentAmount, 0.0, 1.0));

        // [O7] The hot core leaves the accent toward white, capped so a commanded hue
        // survives; skirt and core are silhouette-only (geometry glow), gated like the
        // other depth terms so a dead depth buffer cannot paint them.
        vec3 coreColor = mix(edgeAccent, vec3(1.05), WHITE_LIFT);
        float geomGate = (1.0 - sky) * distanceFade * depthOk;

        vec3 readout = fillAccent * pow(gzLuma(scene), FILL_GAMMA) * FILL_GAIN * (1.0 - sky)
                + edgeAccent * edge * (0.80 * flicker + 0.35 * sweep + 0.95 * trace)
                + edgeAccent * silSkirt * SKIRT_GAIN * geomGate
                + coreColor * silCore * CORE_GAIN * geomGate * flicker
                + edgeAccent * 0.02 * sweep
                + edgeAccent * trace * 0.030 * (1.0 - sky)
                + grainAccent * grain;

        // Soft scanner vignette so the readout sits inside a tube, not a flat page.
        float vign = 1.0 - 0.35 * smoothstep(0.45, 0.95, length(texCoord - 0.5) * 1.5);
        readout *= vign;

        // Ramp law: the scene sinks to black and the readout rises with Strength; at 0 the
        // pass is bit-exact passthrough (idle branch), at 1 the world is the readout.
        color = mix(scene, readout, s);
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);
    }

    fragColor = vec4(color, 1.0);
}
