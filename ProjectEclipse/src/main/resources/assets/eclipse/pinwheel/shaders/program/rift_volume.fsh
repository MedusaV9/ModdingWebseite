// eclipse:rift_volume — TRUE VOLUMETRIC rift tears (RIFT-FX round; FEATURE priority).
// The star-tear geometry of RiftRenderer stays (it is the Iris/reducedFx fallback and
// draws with depthMask(false), so nothing of ours writes depth inside the volume); this
// pass raymarches up to TWO tears per frame into a deep swirling mass — a torn hole in
// space with a glowing throat, not a decal. Per rift: analytic ray/ellipsoid entry (the
// tear plane spans the ellipsoid's long axes, the normal is the squashed depth axis),
// scene-depth-clamped Beer–Lambert march through a vortex-warped fBm density field
// (heavy collar ring around the tear rim + a dense emissive throat column punched along
// the normal), emission ramped through the frozen RiftFx palette (violet default,
// wax-gold backrooms). Composite is premultiplied-over per rift, nearest rift first.
// Uniforms are fed per frame by veilfx.rift.RiftVolumeFx through the VeilPostController
// row (never under an Iris shaderpack; never at quality tier < 1 / reducedFx):
// Rift0Center/Rift0Normal/Rift0Params, Rift1Center/Rift1Normal/Rift1Params (Params =
// radius, strength, seed01, styleF), RiftCount, StepCount, Time, Strength.
#include eclipse:eclipse_rift
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform vec3 Rift0Center;
uniform vec3 Rift0Normal;
uniform vec4 Rift0Params;
uniform vec3 Rift1Center;
uniform vec3 Rift1Normal;
uniform vec4 Rift1Params;
uniform float RiftCount;
uniform float StepCount;
uniform float Time;
uniform float Strength;

in vec2 texCoord;

out vec4 fragColor;

// Extinction per (density · block): the collar goes near-opaque over ~5–9 blocks —
// the tear must read HEAVY, not hazy.
const float ABSORB = 0.85;
// Depth half-extent as a fraction of the tear radius (the volume's 3D "mass" axis).
const float DEPTH_SCALE = 0.55;
// Silhouette headroom beyond the nominal radius (outer tendrils live there).
const float BOUNDS_MARGIN = 1.30;
// Base noise frequency in rift-normalized space.
const float NOISE_FREQ = 3.1;

// Frozen RiftFx palettes (hot core / mid saturation / dim void).
const vec3 VIOLET_HOT = vec3(1.0, 0.965, 1.0);
const vec3 VIOLET_MID = vec3(0.62, 0.30, 0.98);
const vec3 VIOLET_DIM = vec3(0.045, 0.0, 0.10);
const vec3 GOLD_HOT = vec3(1.0, 0.96, 0.86);
const vec3 GOLD_MID = vec3(0.98, 0.74, 0.30);
const vec3 GOLD_DIM = vec3(0.10, 0.06, 0.01);

// Rift density at u = rift-local position, xy in the tear plane (normalized by R),
// z along the normal (normalized by R·DEPTH_SCALE). Returns density and writes the
// emission heat (0 = outer wisp, 1 = throat core) to `heat`.
float riftDensity(vec3 u, float seed, float time, out float heat) {
    float r = length(u.xy);
    float az = abs(u.z);
    if (r > BOUNDS_MARGIN || az > 1.15) {
        heat = 0.0;
        return 0.0;
    }
    // Vortex: the sampling frame spins faster toward the throat — the whole interior
    // visibly churns around the tear axis (sampling rotates, never geometry).
    float ang = time * 0.35 + 2.4 * (1.0 - clamp(r, 0.0, 1.0)) + seed * 6.2831853;
    float cs = cos(ang);
    float sn = sin(ang);
    vec3 q = vec3(cs * u.x - sn * u.y, sn * u.x + cs * u.y, u.z);

    // Heavy collar: a thick ring of mass around the tear rim, thinning through the
    // center (the hole reads OPEN) and feathering past the silhouette (tendrils).
    float collar = smoothstep(0.22, 0.52, r) * (1.0 - smoothstep(0.92, 1.28, r));
    // Collar depth profile: a lens — thick at the rim ring, tapering along ±z.
    float lens = 1.0 - smoothstep(0.30, 1.0, az / (0.42 + 0.45 * (1.0 - clamp(r, 0.0, 1.0))));
    // Throat: a dense emissive column punched ALONG the normal — the "depth" read;
    // wobbles with the cheap fBm so it never reads as a perfect cylinder.
    float wobble = erFbm2(vec3(q.xy * 2.0, time * 0.20 + seed * 17.0)) - 0.5;
    float throat = exp(-(r + 0.22 * wobble) * (r + 0.22 * wobble) * 7.0)
            * (1.0 - smoothstep(0.55, 1.10, az));

    float prof = collar * lens + 1.35 * throat;
    if (prof <= 0.004) {
        heat = 0.0;
        return 0.0;
    }

    // Vortex-warped fBm body: octaves fold into tendrils streaming around the throat.
    vec3 np = q * NOISE_FREQ + vec3(seed * 37.0, seed * 11.0, -time * 0.14 * NOISE_FREQ);
    float body = erFbm4(np + erWarp(np * 0.5, time));
    float dens = max(prof * (body * 1.7 - 0.38), 0.0);

    // Emission heat: the throat burns hottest, the collar's inner lip simmers, and
    // dense noise pockets spark — matched to where the tear geometry's fringe sits.
    heat = clamp(1.25 * throat + 0.45 * collar * (1.0 - smoothstep(0.35, 0.9, r))
            + 0.30 * dens, 0.0, 1.0);
    return dens;
}

// Raymarches one rift and composites it over `scene` (premultiplied-over).
vec3 marchRift(vec3 scene, vec3 rd, float sceneDist, vec3 center, vec3 normal,
        vec4 params, float dith) {
    float radius = params.x;
    float strength = params.y * clamp(Strength, 0.0, 1.0);
    if (radius <= 0.75 || strength <= 0.004) {
        return scene;
    }
    float seed = params.z;
    bool gold = params.w > 1.5;

    // Tear-plane basis — EXACTLY the RiftFx construction (helper = the axis the normal
    // is least aligned with; t = helper × n; b = n × t) so the volume, the star
    // geometry and the emitters all share one frame on every client.
    vec3 n = normalize(normal);
    vec3 helper = abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 t = normalize(cross(helper, n));
    vec3 b = cross(n, t);

    // Local-space ray (camera at the world origin of VeilCamera local space), squashed
    // so the bounds become the unit sphere · margin. t stays in world blocks because
    // origin and direction are squashed consistently.
    vec3 halfInv = 1.0 / vec3(radius, radius, radius * DEPTH_SCALE);
    vec3 ro = vec3(dot(-center, t), dot(-center, b), dot(-center, n)) * halfInv;
    vec3 rdl = vec3(dot(rd, t), dot(rd, b), dot(rd, n)) * halfInv;
    float aq = dot(rdl, rdl);
    float bq = dot(ro, rdl);
    float disc = bq * bq - aq * (dot(ro, ro) - BOUNDS_MARGIN * BOUNDS_MARGIN);
    if (disc <= 0.0) {
        return scene; // early out: the ray misses this tear's bounds entirely
    }
    float sq = sqrt(disc);
    float t0 = max((-bq - sq) / aq, 0.0);
    float t1 = min((-bq + sq) / aq, sceneDist);
    if (t1 <= t0) {
        return scene; // behind the camera or fully occluded by scene depth
    }

    float steps = clamp(StepCount, 12.0, 48.0);
    // Distant tears cover few pixels — spend fewer steps there.
    steps = clamp(steps * clamp(160.0 / max(t0, 1.0), 0.4, 1.0), 12.0, 48.0);
    float dt0 = (t1 - t0) / steps;
    float invR = 1.0 / radius;
    float invZ = 1.0 / (radius * DEPTH_SCALE);
    vec3 dimCol = gold ? GOLD_DIM : VIOLET_DIM;
    vec3 midCol = gold ? GOLD_MID : VIOLET_MID;
    vec3 hotCol = gold ? GOLD_HOT : VIOLET_HOT;

    float trans = 1.0;
    vec3 acc = vec3(0.0);
    float heat;
    float tRay = t0 + dith * dt0;
    for (int i = 0; i < 48; i++) {
        if (tRay >= t1 || trans < 0.012 || float(i) >= steps) {
            break; // early exits: segment done / mass opaque / step budget spent
        }
        vec3 pos = rd * tRay - center;
        vec3 u = vec3(dot(pos, t) * invR, dot(pos, b) * invR, dot(pos, n) * invZ);
        float dens = riftDensity(u, seed, Time, heat) * strength;
        if (dens < 0.004) {
            tRay += dt0 * 1.7; // empty-space acceleration through the open hole
            continue;
        }
        float newTrans = trans * exp(-dens * dt0 * ABSORB);
        // Emissive integration: the tear lights itself — void-dark wisps outside,
        // saturated mid-band, near-white burn in the throat.
        vec3 emit = erPalette(heat, dimCol, midCol, hotCol) * (0.55 + 2.1 * heat);
        acc += emit * (trans - newTrans);
        trans = newTrans;
        tRay += dt0;
    }
    return scene * trans + acc;
}

void main() {
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    int count = int(RiftCount + 0.5);
    if (count <= 0 || Strength <= 0.004) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    // Camera-relative world ray (VeilCamera local space; camera at the origin).
    vec3 rd = viewDirFromUv(texCoord);
    // Scene depth clamp: terrain correctly hides the volume behind it. The rift's own
    // geometry (RiftRenderer) draws with depthMask(false) — it can never cut the march.
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sceneDist = depth >= 0.9999 ? 1.0e7
            : length(screenToLocalSpace(texCoord, depth).xyz);
    float dith = erDither(gl_FragCoord.xy, Time);

    // Nearest rift first (RiftVolumeFx sorts) — sequential premultiplied-over is exact
    // for disjoint volumes and a fine approximation on the rare overlap.
    scene = marchRift(scene, rd, sceneDist, Rift0Center, Rift0Normal, Rift0Params, dith);
    if (count > 1) {
        scene = marchRift(scene, rd, sceneDist, Rift1Center, Rift1Normal, Rift1Params, dith);
    }
    fragColor = vec4(scene, 1.0);
}
