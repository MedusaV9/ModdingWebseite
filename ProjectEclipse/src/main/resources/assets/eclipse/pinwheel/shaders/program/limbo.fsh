// eclipse:limbo v4.1 — the Limbo grade (P2-W3, R5, GRADE priority; PLAN-C C1 water rework;
// FXTEAM-LIMBO v4 craft pass; VEIL-REPASS-2 v4.1 polish). LIMBOFIX removed two effects:
// the horizon-curvature/infinite-ocean UV warp (its hd term snapped regimes at
// rayDir.y == -0.001 — a seam line across the screen; the CurveAmount uniform is gone
// with it) and the eclipse reflection smear (screen-space keyed off GodrayDir, the post
// half of the broken sky-pass water streak). The endless-sea horizon fade stays.
// v4.1 adds, WITHOUT touching the frozen v3/v4 fixes (depth water mask + capped eps +
// smoothstep facing, VoyageOffset accumulation, Detail reduced-motion gate):
//   * Sea breathing — the whole violet water field inhales/exhales in exact sync with the
//     eclipse corona pulse: the frozen dual-frequency aura curve (the "uniform exists" is
//     Time) is multiplied into the water color block at ±7.5%. Detail-gated back to the
//     steady v4 look.
//   * Soul shoal (SoulShoal uniform) — rarely, a school of tiny soul-green lights swims
//     beneath the surface and crosses near the ship: a translating cluster of stretched
//     gaussian dashes in shoal-local space (the formation swims, unlike the world-anchored
//     glints), each shimmering through the caustic web so they read as UNDER the water.
//     LimboAmbience feeds the deterministic crossing; idle/reducedFx = strength 0.
// --- v4 header kept below ---
// eclipse:limbo v4 — the Limbo grade. v4 adds, WITHOUT touching the v3 fixes (depth water
// mask, voyage drift):
//   * Layered water — a near-hull micro-ripple octave (extra causticWeb at 3.1× frequency,
//     faded out by 16 blocks) plus long-wavelength swells far out (a very low-frequency
//     noise that re-shades the web brightness beyond ~18 blocks) — three perceptual bands
//     of wave scale instead of one.
//   * Sparse bioluminescent glints — rare soul-green spots in the world-anchored caustic
//     field (they ride wp, so they trail the VoyageOffset drift astern automatically),
//     elongated along the drift axis, blinking on slow per-cell phases.
//   * Far storm-glow pulses (LightningGlow) — an occasional soft violet glow along one
//     horizon azimuth (no bolts): pure ray-geometry (EVAL-POL-F #3),
//     applied only to sky + melted-horizon pixels so fog banks and horizon ships
//     silhouette against it. Idle at strength 0; reducedFx feeds 0.
// --- v3 header kept below ---
// eclipse:limbo v3 — the Limbo grade (P2-W3, R5, GRADE priority; PLAN-C C1 water rework).
// v2 kept: desaturate toward violet + breathing vignette, GodrayDir radial god rays, edge
// chroma fringe. v3 (C1) replaces the old luma/screen-band water heuristic with a REAL
// water read and adds the horizon illusion:
//   * Water mask by depth reconstruction — worldPos = CameraPos + (InvViewProj · ndc).xyz;
//     only pixels whose reconstruction lands in a thin band around the limbo waterline
//     (WaterlineY: GhostShipBuilder.waterlineY, synced through the ship_deck anchor) AND
//     that are seen from above the plane count as water. Ship hull, deckhands, wreck spars
//     and players stop receiving caustics entirely (they reconstruct above the band).
//   * World-anchored caustic UVs — the web samples worldPos.xz, so the waves stay pinned to
//     the sea surface when the camera turns instead of swimming with the viewport.
//     VoyageOffset (a steadily increasing world-XZ scroll in blocks, fed by LimboAmbience,
//     ship forward −X→+X) streams the whole caustic field slowly astern past the hull —
//     the shader half of the item-6 "sailing" illusion.
//   * Endless sea — the last 15% before the loaded-sea edge fades into the sky gradient,
//     so the ocean reads as endless instead of clipping at the render distance.
// Uniforms: Intensity, GodrayDir (vec2), CausticsAmount, Time (frozen §3.3) + the v3 set
// InvViewProj, CameraPos, WaterlineY, VoyageOffset, FarDist + the v4
// LightningGlow and Detail (reduced-motion gate) + the v4.1 SoulShoal — all fed per
// frame by veilfx.LimboAmbience (which captures the exact AFTER_SKY render matrices, view
// bobbing included, so reconstruction matches the depth buffer — the SunTracker law).
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Intensity;
uniform vec2 GodrayDir;
uniform float CausticsAmount;
uniform float Time;
// v3 (C1):
uniform mat4 InvViewProj;   // inverse of this frame's exact Proj·ModelView (camera-relative)
uniform vec3 CameraPos;     // camera world position (worldPos = CameraPos + reconstructed)
uniform float WaterlineY;   // top water block Y of the limbo ocean (−1e5 until synced)
uniform vec2 VoyageOffset;  // steadily increasing world-XZ scroll (blocks) — sailing drift
uniform float FarDist;      // approx. distance (blocks) where the loaded sea geometry ends
// v4:
uniform vec3 LightningGlow; // xy = world-XZ azimuth unit dir of the pulse, z = strength 0..1
uniform float Detail;       // 1 normal, 0 under reducedFx — gates the v4 water-motion layers
                            // (swells, micro-ripples, glints) back to the
                            // v3 water look: reduced FX is a motion contract, not just ALU.
// v4.1:
uniform vec4 SoulShoal;     // xy = shoal center (world XZ), zw = swim heading × strength —
                            // length(zw) is the 0..1 crossing envelope; (0,0) = no shoal.

in vec2 texCoord;

out vec4 fragColor;

// Ridged two-layer counter-scrolling value noise: bright cell-boundary webs (voronoi-ish).
float causticWeb(vec2 p, float t) {
    float n1 = efxNoise(p + vec2(t * 0.35, t * 0.22));
    float n2 = efxNoise(p * 1.7 - vec2(t * 0.28, t * 0.40));
    float r1 = 1.0 - abs(2.0 * n1 - 1.0);
    float r2 = 1.0 - abs(2.0 * n2 - 1.0);
    float web = r1 * r2;
    return web * web;
}

// Camera-relative world position of the pixel at (uv, depth) through the exact matrices.
vec3 reconstructRel(vec2 uv, float depth) {
    vec4 clip = InvViewProj * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    // Epsilon guard: a singular/near-zero homogeneous w (identity-parked InvViewProj,
    // degenerate depth) would inject Inf/NaN into masks and noise coordinates.
    float w = clip.w;
    if (abs(w) < 1.0e-6) w = w < 0.0 ? -1.0e-6 : 1.0e-6;
    return clip.xyz / w;
}

void main() {
    vec2 uv = texCoord;
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));

    // v4.1: the frozen dual-frequency corona pulse (the sky pass's drawAuraGlow curve)
    // drives the sea breathing — one curve, so it can never desync from the sky-pass aura.
    float pulse = 0.85 + 0.11 * sin(Time * 1.3) + 0.04 * sin(Time * 0.37 + 1.7);

    // LIMBOFIX: the horizon-curvature + infinite-ocean UV warp is GONE (its hd term
    // snapped between two regimes at rayDir.y == -0.001 — a visible seam line across the
    // screen). The scene samples at plain uv; the endless-sea horizon fade below stays.
    // View ray for the v4 storm glow (pure ray geometry, fed 0 under reducedFx, so the
    // reconstruction is skipped entirely on that tier).
    vec3 rayDir = vec3(0.0, 1.0, 0.0);
    if (LightningGlow.z > 0.001) {
        rayDir = normalize(reconstructRel(uv, 1.0));
    }

    float depth = texture(DiffuseDepthSampler, uv).r;
    float sky = step(0.9999, depth);

    // ---- REAL water mask (item 1): depth-reconstructed world position -------------------
    vec3 rel = reconstructRel(uv, depth);
    vec3 world = CameraPos + rel;
    float dist = length(rel.xz);
    // Water surface plane: top water block + source-block fluid height (~0.9). The band
    // tolerance grows slightly with distance (depth precision) but never enough to re-admit
    // the deck (waterline+3) or standing mobs.
    float surfaceY = WaterlineY + 0.9;
    // eps growth is CAPPED (POL-F 8): uncapped, the depth-precision allowance kept
    // widening with distance until the far band could re-admit the deck (waterline+3,
    // i.e. 2.1 above the surface) — 1.65 keeps the outer band edge safely below it.
    float eps = min(0.55 + dist * 0.012, 1.65);
    float band = 1.0 - smoothstep(eps * 0.5, eps, abs(world.y - surfaceY));
    // Downward-facing reconstruction: only rays looking DOWN onto the plane from above
    // count — geometry above the waterline reconstructs above the band and drops out, and
    // a submerged camera (intro submerge FX) gets no caustics at all. POL-F 8: both cuts
    // are smoothsteps now — the old binary steps popped the whole caustic field on/off
    // when the camera bobbed across waterline+0.5 or a ray grazed horizontal.
    float facing = smoothstep(surfaceY + 0.1, surfaceY + 0.9, CameraPos.y)
            * smoothstep(0.005, 0.05, -rel.y);
    float water = (1.0 - sky) * band * facing * CausticsAmount;

    // ---- world-anchored caustic UVs (item 2) + voyage drift (shader half of item 6) -----
    vec2 wp = (world.xz + VoyageOffset) * 0.45;

    // Liquid refraction wobble for water pixels only (world-anchored like the web).
    vec2 wobble = vec2(
            efxNoise(wp * 0.9 + vec2(Time * 0.50, 0.0)) - 0.5,
            efxNoise(wp * 0.9 + vec2(31.7, Time * 0.43)) - 0.5) * 0.012 * water;

    // ---- base sample with wobble + edge chroma fringe (≤ ~2.5 px, dreamlike) ------------
    float d = distance(uv, vec2(0.5));
    float edge = smoothstep(0.35, 0.75, d) * Intensity;
    vec2 radial = normalize(uv - 0.5 + vec2(1.0e-5));
    vec3 color = efxChroma(DiffuseSampler0, uv + wobble, radial * (2.5 / screenSize), edge);

    // ---- v1 grade kept: desaturate toward violet + soft breathing vignette --------------
    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 purple = mix(color, gray * vec3(0.75, 0.45, 1.1), 0.55);
    float breathe = 0.6 + 0.05 * sin(Time * 0.7);
    purple *= 1.0 - smoothstep(0.45, 0.95, d) * breathe;
    color = mix(color, purple, Intensity);

    // ---- purple water: violet lift + LAYERED caustic web + glints (v4) ------------------
    // Distance rolloff calms the far field so the shimmer recedes with perspective. The
    // whole block is gated on the water mask so the extra v4 octaves cost nothing on sky,
    // hull or deckhand pixels.
    if (water > 0.001) {
        float calm = 1.0 - 0.6 * smoothstep(30.0, max(FarDist * 0.7, 60.0), dist);
        float web = causticWeb(wp, Time);
        float sparkle = pow(causticWeb(wp * 2.3 + vec2(17.0), Time * 1.6), 2.0);
        // v4 layered water, far band: long-wavelength swells (~35-block features, near-
        // static) re-shade the web brightness beyond ~18 blocks — the far field reads as
        // rolling water instead of a uniform shimmer sheet.
        // Detail-gated (reduced FX): the swell re-shade collapses to the flat v3 web.
        float swell = efxNoise(wp * 0.055 + vec2(Time * 0.045, Time * 0.028));
        float webAmp = mix(1.0, 0.55 + 0.90 * swell, smoothstep(18.0, 60.0, dist) * Detail);
        // v4 layered water, near band: a micro-ripple octave hugging the hull (3.1× web
        // frequency, faster counter-scroll), fully faded out by 16 blocks. Detail-gated.
        float nearW = 1.0 - smoothstep(5.0, 16.0, dist);
        float micro = (nearW > 0.001 && Detail > 0.001)
                ? causticWeb(wp * 3.1 + vec2(53.0), Time * 2.1) : 0.0;
        // v4.1 sea breathing: the whole violet field (lift + web + sparkle + micro)
        // inhales/exhales with the corona pulse — ±7.5% around the steady v4 exposure
        // (the 0.85-mean pulse is re-centered to 1.0). Detail-gated back to the constant
        // look under reduced FX: a scene-wide luminance swell is exactly the kind of
        // motion the reduced contract removes. Glints stay unbreathed — they are
        // creatures in the water, not light OF the water.
        float seaBreath = mix(1.0, 1.0 + (pulse - 0.85) * 0.5, Detail);
        color += (vec3(0.10, 0.03, 0.17)
                + vec3(0.42, 0.16, 0.80) * web * webAmp * calm
                + vec3(0.55, 0.30, 1.00) * sparkle * 0.6 * calm
                + vec3(0.36, 0.18, 0.70) * micro * nearW * 0.35) * water * seaBreath;
        // v4: sparse bioluminescent glints. Cells of the world-anchored field (they ride
        // wp, so they trail the voyage drift astern like real flotsam); ~1.8% of ~4.4-block
        // cells host a glint, each an elongated-along-drift soul-green spot blinking on its
        // own slow phase (sin² halves the duty cycle — mostly-dark reads alive, not busy).
        // Detail-gated (reduced FX): blinking point lights are exactly the kind of motion
        // the reduced contract removes.
        vec2 gp = wp * 0.5;
        float gh = efxHash(floor(gp));
        if (gh > 0.982 && Detail > 0.001) {
            vec2 lp = fract(gp) - 0.5;
            lp.x *= 0.45; // stretch along the drift axis (+X)
            float spot = exp(-dot(lp, lp) * 22.0);
            float blink = max(sin(Time * (0.5 + gh) + gh * 41.0), 0.0);
            blink *= blink;
            color += vec3(0.28, 0.95, 0.55) * spot * blink * calm * water * 0.5 * Detail;
        }

        // ---- v4.1: soul shoal — a school of tiny lights swimming UNDER the surface -------
        // Unlike the world-anchored glints, the fish live in SHOAL-LOCAL space (x along the
        // swim heading, y abeam), so the whole formation translates with the crossing that
        // LimboAmbience feeds. Each occupied cell holds one stretched gaussian dash that
        // wiggles across the heading on its own phase; the school's brightness is carried
        // by the caustic web overhead, so the lights shimmer as if refracted from below.
        // strength already encodes idle/reducedFx = 0; Detail-gated for the motion ladder.
        float shoalStrength = length(SoulShoal.zw);
        if (shoalStrength > 0.001 && Detail > 0.001) {
            vec2 shoalDir = SoulShoal.zw / shoalStrength;
            vec2 toP = world.xz - SoulShoal.xy;
            vec2 sp = vec2(dot(toP, shoalDir), dot(toP, vec2(-shoalDir.y, shoalDir.x)));
            // Elliptical formation envelope: ~±13 blocks along the heading, ~±5 abeam.
            vec2 fe = sp * vec2(0.075, 0.20);
            float formation = exp(-dot(fe, fe));
            if (formation > 0.01) {
                vec2 fp = sp * vec2(0.85, 1.9); // fish cells ~1.2 blocks long, ~0.5 wide
                float fh = efxHash(floor(fp) + vec2(91.0, 47.0));
                if (fh > 0.42) {
                    vec2 lp2 = fract(fp) - 0.5;
                    lp2.y += 0.16 * sin(Time * 2.3 + fh * 37.0); // per-fish swim wiggle
                    lp2.x *= 0.50;                               // dash along the heading
                    float fish = exp(-dot(lp2, lp2) * 30.0);
                    float underWeb = 0.45 + 0.55 * web;          // refracted-from-below read
                    color += vec3(0.30, 0.95, 0.60) * fish * formation * underWeb
                            * shoalStrength * water * 0.85;
                }
            }
        }
    }

    // ---- endless-sea horizon fade (item 5): last 15% melts into the sky gradient --------
    // Applies only to scene pixels (warped former-sky pixels now sample sea and land here
    // fully faded); true sky pixels keep their crisp stars/disc.
    float horizonMix = smoothstep(FarDist * 0.85, FarDist, dist) * (1.0 - sky) * Intensity;
    color = mix(color, vec3(0.030, 0.018, 0.062), horizonMix);

    // ---- v4: far storm-glow pulses — a soft violet sheet along one horizon azimuth ------
    // Pure ray geometry (EVAL-POL-F #3: C0 across silhouettes, nothing
    // can tear), weighted by sky + melted-horizon coverage. Horizon ships / fog banks sit
    // at sky depth, so they receive the SAME additive glow as the sky behind them — their
    // darkening is preserved in absolute terms and they still read as silhouettes against
    // the pulse. No bolts, just the glow; LimboAmbience feeds the deterministic envelope
    // (and holds it at 0 while InvViewProj is parked at identity).
    if (LightningGlow.z > 0.001) {
        vec2 az = rayDir.xz / max(length(rayDir.xz), 1.0e-4);
        float azim = pow(max(dot(az, LightningGlow.xy), 0.0), 6.0);
        float belt = smoothstep(-0.08, 0.01, rayDir.y) * (1.0 - smoothstep(0.08, 0.28, rayDir.y));
        color += vec3(0.62, 0.42, 1.00) * azim * belt * LightningGlow.z
                * (sky + horizonMix) * 0.30;
    }

    // ---- screen-space radial god rays from the zenith disc ------------------------------
    float lookUp = 1.0 - smoothstep(0.9, 2.6, length(GodrayDir));
    float rayStrength = lookUp * Intensity;
    if (rayStrength > 0.001) {
        vec2 centerUv = GodrayDir * 0.5 + 0.5;
        vec2 stepUv = (centerUv - uv) / 12.0;
        vec2 ruv = uv;
        float illum = 0.0;
        float weight = 1.0;
        for (int i = 0; i < 12; i++) {
            ruv += stepUv;
            vec3 s = texture(DiffuseSampler0, clamp(ruv, vec2(0.0), vec2(1.0))).rgb;
            illum += max(dot(s, vec3(0.299, 0.587, 0.114)) - 0.16, 0.0) * weight;
            weight *= 0.84;
        }
        float flicker = 0.9 + 0.1 * sin(Time * 2.3 + uv.y * 4.0);
        color += vec3(0.60, 0.30, 1.00) * illum * 0.16 * rayStrength * flicker;
    }

    fragColor = vec4(color, 1.0);
}
