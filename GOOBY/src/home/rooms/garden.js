// V2/G19: Garden room definition (PLAN2 §C2.1/§C8.3) — PURE DATA, no
// three.js/DOM imports (test/rooms.test.js validates headlessly).
//
// The garden is the 5th navigable space, right of the bedroom (nav dot 5,
// padlocked until L3 — §B6). `outdoor: true` tells the roomManager to build
// a 5×4 m grass ground + sky dome instead of walls/wallpaper/floor (§B3).
// `camZ` pulls the room camera back a touch (7.2 → 8.4) so the wider outdoor
// footprint fits the portrait frame — every interactable below projects
// on-screen at 390×844 and clear of Gooby's idle spot (front-left corner).
//
// Fixed interactables (§C2.1): 6 crop plots (nature-kit crops_dirtSingle,
// 2×3 grid, anchors plot0…plot5 — plots ≥ plotsOwned show a FOR-SALE sign,
// rendered dynamically by gardenInteractions.js), compost bin (procedural —
// tap opens the sell sheet), watering can on a stump (procedural — the drag
// tool), fertilizer bag (procedural — the §C2.2 fertilizer drag tool).
// Decor slots (§C8.3): gardenBench · gardenGnome · birdbath · flowerBed ·
// gardenPath · gardenTree (free defaults render before G22's catalog lands).
//
// Item keys may be pack-qualified ('nature-kit/…', 'city-kit-suburban/…');
// bare names default to furniture-kit like the indoor rooms (roomManager
// resolveAssetKey). 'proc:' ids are procedural builders in roomManager.

/** Garden ground footprint (§C2.1: 5×4 m — wider than the 4×3 indoor shell). */
export const GARDEN_SIZE = Object.freeze({ WIDTH: 5, DEPTH: 4 });

/** @type {import('../roomManager.js').RoomDef} */
export const ROOM = Object.freeze({
  id: 'garden',
  outdoor: true,
  camZ: 8.4,

  slots: Object.freeze({
    gardenBench: Object.freeze({ default: 'proc:gardenBench', items: Object.freeze(['proc:gardenBench', 'proc:pastelBench']) }),
    gardenGnome: Object.freeze({ default: null, items: Object.freeze(['proc:gardenGnome', 'proc:goldenGnome']) }),
    birdbath: Object.freeze({ default: null, items: Object.freeze(['proc:birdbath']) }),
    flowerBed: Object.freeze({ default: 'wildflowers', items: Object.freeze(['wildflowers', 'proc:roseBed']) }),
    gardenPath: Object.freeze({ default: 'proc:dirtPath', items: Object.freeze(['proc:dirtPath', 'city-kit-suburban/path-stones-short']) }),
    gardenTree: Object.freeze({ default: 'nature-kit/tree_default', items: Object.freeze(['nature-kit/tree_default', 'proc:blossomTree']) }),
  }),

  // ---- V6/E4: static garden dressing (never saved) — the Tiny Treats park
  // upgrade. decor.js merges each assetCluster batch into ONE draw call;
  // pretty-park ships its OWN tiny_treats_texture_1 atlas revision (md5
  // differs from the shared one) so it cannot share a batch with
  // pleasant-picnic — hence separate `park`/`picnic` batches. Together with
  // the checkered-blanket painter that is +3 calls for the whole garden
  // (V4/G79 budget: ≤4 added per room). Every piece stays clear of the 9
  // interactable hit boxes (plot0–5/compost/wateringCan/fertilizer) and of
  // goobyIdle/canopySit — test/roomAudit.test.js locks tap-zone overlaps.
  dressing: Object.freeze([
    Object.freeze({
      id: 'parkDressing', kind: 'assetCluster', batch: 'park',
      pieces: Object.freeze([
        // street lantern at the fence gate's right post — its base kisses the
        // right hedge bush's leaf AABB by ≤2.5 cm (under clipTol, flush fit)
        Object.freeze({ key: 'pretty-park/street_lantern', at: Object.freeze([0.62, 0, -1.64]), scale: 0.45 }),
        // edge flowers: left ground edge + right edge below the tree — both
        // fully on the 5 m ground, partially outside the 390 px portrait
        // frustum by design (wide-viewport dressing, V4/FIX-3D precedent)
        Object.freeze({ key: 'pretty-park/flower_A', at: Object.freeze([-2.15, 0, -0.05]), scale: 0.5, rotY: 35 }),
        Object.freeze({ key: 'pretty-park/flower_B', at: Object.freeze([2.25, 0, 0.35]), scale: 0.5, rotY: -60 }),
        // songbird perched on the bench backrest (bench top y 0.491), turned
        // a touch toward the camera. STATIC prop — the MOVING fence visitor
        // is Wave F's (see the gardenFenceBird anchor below).
        Object.freeze({ key: 'pretty-park/bird', at: Object.freeze([-1.62, 0.491, -1.35]), scale: 0.45, rotY: 20 }),
      ]),
    }),
    // picnic corner on the front-left grass, beside Gooby's idle spot —
    // both baskets stand ON the blanket quad (flat ≤9 mm ⇒ audit-legal).
    Object.freeze({
      id: 'picnicCorner', kind: 'assetCluster', batch: 'picnic',
      pieces: Object.freeze([
        Object.freeze({ key: 'pleasant-picnic/picnic_basket_round', at: Object.freeze([-1.12, 0.006, 0.85]), scale: 0.35, rotY: -25 }),
        Object.freeze({ key: 'pleasant-picnic/picnic_basket_square', at: Object.freeze([-1.72, 0.006, 1.3]), scale: 0.32, rotY: 15 }),
      ]),
    }),
    // checkered CanvasTexture ground quad (decor.js g79PicnicBlanket painter)
    Object.freeze({
      id: 'picnicBlanket', kind: 'picnicBlanket', batch: 'blanket',
      at: Object.freeze([-1.35, 0.005, 1.15]), rotY: 8,
      size: Object.freeze([1.3, 0.95]),
    }),
  ]),
  // ---- end V6/E4 -------------------------------------------------------------

  furniture: Object.freeze([
    // low fence line at the back (§C2.1: suburban fence-1x4 ×3)
    Object.freeze({ item: 'city-kit-suburban/fence-1x4', at: Object.freeze([-1.65, 0, -1.9]), rotY: 0, scale: 0.42 }),
    // V3/G46 (§C11.1): a real opening replaces the stand-in middle segment.
    Object.freeze({
      item: 'nature-kit/fence_gate', at: Object.freeze([0, 0, -1.9]),
      rotY: 0, scale: 1.15, dressing: 'v3-real-asset',
    }),
    Object.freeze({ item: 'city-kit-suburban/fence-1x4', at: Object.freeze([1.65, 0, -1.9]), rotY: 0, scale: 0.42 }),
    // back hedge (§C2.1: plant_bushLarge ×3)
    Object.freeze({ item: 'nature-kit/plant_bushLarge', at: Object.freeze([-2.05, 0, -1.62]), rotY: 15, scale: 0.5 }),
    Object.freeze({ item: 'nature-kit/plant_bushLarge', at: Object.freeze([-0.8, 0, -1.7]), rotY: -30, scale: 0.42 }),
    // V4/AC-3D: x 0.97 (was 1.05) — the old spot ran this bush 9 cm through
    // the right fence segment (fence starts at x 1.10)
    Object.freeze({ item: 'nature-kit/plant_bushLarge', at: Object.freeze([0.97, 0, -1.68]), rotY: 60, scale: 0.44 }),
    // tree (gardenTree decor slot — free default nature tree, §C8.3)
    // V4/AC-3D: z −1.45 (was −1.5) lifts the trunk-side canopy off the fence
    // line (fence front face z −1.76; the old bbox crossed it by 6 cm)
    // V4/FIX-3D: x 2.12 (was 1.9) — the old spot ran the canopy 0.32×0.73×
    // 0.38 m through the compost bin (hidden by the audit's unbounded
    // tree∩compost clipAllow, now removed); the tree bbox (1.76..2.48) stays
    // fully on the 5 m ground with 1.2 cm daylight to the bin
    Object.freeze({ slot: 'gardenTree', item: 'nature-kit/tree_default', at: Object.freeze([2.12, 0, -1.45]), rotY: 0, scale: 0.62 }),

    // 6 crop plots — 2×3 grid (§C2.1), anchors/interacts plot0…plot5
    // (0.85 m pitch; gardenInteractions.PLOT_RADIUS matches)
    Object.freeze({ item: 'nature-kit/crops_dirtSingle', at: Object.freeze([-0.85, 0, -0.75]), rotY: 0, scale: 0.55, interact: 'plot0', anchor: 'plot0', hitSize: Object.freeze([0.75, 0.55, 0.75]), noShadow: true }),
    Object.freeze({ item: 'nature-kit/crops_dirtSingle', at: Object.freeze([0, 0, -0.75]), rotY: 0, scale: 0.55, interact: 'plot1', anchor: 'plot1', hitSize: Object.freeze([0.75, 0.55, 0.75]), noShadow: true }),
    Object.freeze({ item: 'nature-kit/crops_dirtSingle', at: Object.freeze([0.85, 0, -0.75]), rotY: 0, scale: 0.55, interact: 'plot2', anchor: 'plot2', hitSize: Object.freeze([0.75, 0.55, 0.75]), noShadow: true }),
    Object.freeze({ item: 'nature-kit/crops_dirtSingle', at: Object.freeze([-0.85, 0, 0.1]), rotY: 0, scale: 0.55, interact: 'plot3', anchor: 'plot3', hitSize: Object.freeze([0.75, 0.55, 0.75]), noShadow: true }),
    Object.freeze({ item: 'nature-kit/crops_dirtSingle', at: Object.freeze([0, 0, 0.1]), rotY: 0, scale: 0.55, interact: 'plot4', anchor: 'plot4', hitSize: Object.freeze([0.75, 0.55, 0.75]), noShadow: true }),
    Object.freeze({ item: 'nature-kit/crops_dirtSingle', at: Object.freeze([0.85, 0, 0.1]), rotY: 0, scale: 0.55, interact: 'plot5', anchor: 'plot5', hitSize: Object.freeze([0.75, 0.55, 0.75]), noShadow: true }),

    // compost bin (procedural, §C2.1 — tap opens the sell sheet; back-right
    // between the plot rows and the hedge so it projects on-screen at 390 px
    // and its tap ray clears the plot/tool boxes — nearest-center pick in
    // roomManager.handleTap resolves any residual overlap)
    // V4/FIX-3D: x 1.45/rotY 0 (was 1.5/−15) — square to the camera the bin's
    // AABB ends at x 1.745, clear of the moved tree (min 1.757) AND fully
    // inside the 390 px portrait frustum (edge ≈ ±1.82 at z −1.15)
    Object.freeze({ proc: 'compostBin', at: Object.freeze([1.45, 0, -1.15]), rotY: 0, interact: 'compost', anchor: 'compost', hitSize: Object.freeze([0.75, 0.85, 0.75]) }),
    // watering can on a stump (§C2.1 — the drag tool)
    Object.freeze({ item: 'nature-kit/stump_round', at: Object.freeze([1.35, 0, 0.75]), rotY: 0, scale: 0.5 }),
    // V4/AC-3D: y 0.16 (was 0.22) sets the can flush on the stump top
    // (stump bbox tops out at y 0.157 — the old lift left a 6 cm air gap)
    Object.freeze({ proc: 'wateringCan', at: Object.freeze([1.35, 0.16, 0.75]), rotY: 25, interact: 'wateringCan', anchor: 'wateringCan', hitSize: Object.freeze([0.6, 0.7, 0.6]) }),
    // fertilizer bag (§C2.2 — drag onto a growing plot; buy via sheet)
    Object.freeze({ proc: 'fertilizerBag', at: Object.freeze([1.1, 0, 1.35]), rotY: 10, interact: 'fertilizer', anchor: 'fertilizer', hitSize: Object.freeze([0.5, 0.6, 0.5]) }),

    // decor slots (§C8.3 — G22's catalog swaps items via decor.js)
    // V3/G46 (§C11.1): nature-kit/bench is intentionally the pack's rustic
    // log substitute. The catalog/save id stays proc:benchWood; decor.js uses
    // this same real model when swapping back from the pastel variant.
    // V4/AC-3D: the old angled spot (−1.5, −1.25, rotY 30) jammed the bench
    // through the left fence segment AND both left hedge bushes (up to 0.19 m
    // deep) — it now sits square to the camera in front of the hedge, left of
    // the plot grid, with flush ≤3 cm hedge contact only.
    Object.freeze({
      slot: 'gardenBench', item: 'nature-kit/bench',
      at: Object.freeze([-1.62, 0, -1.16]), rotY: 0, scale: 0.76,
      dressing: 'v3-real-asset',
    }),
    Object.freeze({ slot: 'gardenGnome', at: Object.freeze([0.45, 0, -1.4]) }),
    Object.freeze({ slot: 'birdbath', at: Object.freeze([-1.35, 0, -0.45]) }),
    Object.freeze({
      slot: 'flowerBed', item: 'wildflowers', at: Object.freeze([-0.35, 0, -1.5]),
      pieces: Object.freeze([
        Object.freeze({ item: 'nature-kit/flower_purpleA', at: Object.freeze([-0.2, 0, 0.02]), rotY: 0, scale: 0.55 }),
        Object.freeze({ item: 'nature-kit/flower_redA', at: Object.freeze([0.02, 0, -0.1]), rotY: 40, scale: 0.55 }),
        Object.freeze({ item: 'nature-kit/flower_yellowA', at: Object.freeze([0.22, 0, 0.06]), rotY: -25, scale: 0.55 }),
      ]),
    }),
    Object.freeze({ slot: 'gardenPath', proc: 'dirtPath', at: Object.freeze([0.15, 0, 1.3]), rotY: -12, noShadow: true }),

    // ---- V4/POLISH-I: edge dressing — a grass tuft/flower pair softening the
    // bare front-left corner, a flat stone by the birdbath spot and one cheeky
    // toadstool front-right; all outside every plot/tool tap line ----------
    Object.freeze({ item: 'nature-kit/grass_large', at: Object.freeze([-1.95, 0, 0.5]), rotY: 20, scale: 0.5, noShadow: true }),
    // V6/E4: nudged from [−1.7, 0.85] — the old spot sits under the new
    // picnic-blanket quad (a stem through the blanket reads wrong).
    Object.freeze({ item: 'nature-kit/flower_yellowA', at: Object.freeze([-1.58, 0, 0.48]), rotY: 60, scale: 0.5 }),
    Object.freeze({ item: 'nature-kit/rock_smallFlatA', at: Object.freeze([-1.9, 0, -0.5]), rotY: -35, scale: 0.55 }),
    Object.freeze({ item: 'nature-kit/mushroom_red', at: Object.freeze([1.8, 0, 1.25]), rotY: -30, scale: 0.45 }),
    // ---- end V4/POLISH-I ----------------------------------------------------
  ]),

  anchors: Object.freeze({
    // front of the garden at the dirt-path mouth. V4/FIX-3D: pulled in from
    // the old [−1.5, 1.25] — the 390 px portrait frustum only reaches
    // |x| ≈ 1.37 at that depth, so Gooby idled half off the LEFT screen
    // edge. Here he projects to NDC x −0.65..−0.04 (fully framed) and
    // handleTap probes on all 9 garden interactables still return their own
    // ids (Gooby's always-wins body shadows none of them).
    goobyIdle: Object.freeze([-0.45, 0, 1.45]),
    // G26 (§C11.2): Gooby contently shelters at the tree corner during rain.
    // V4/FIX-3D: the old [1.5, −1.05] sat him INSIDE the compost bin's box;
    // this spot keeps the canopy overhead but clears the bin (front face
    // z −0.855) and the stump/tool cluster.
    canopySit: Object.freeze([1.55, 0, -0.5]),
    // V6/E4 (PLAN6 Wave E/F contract): perch point for Wave F's TRANSIENT
    // bird visitor — the top of the fence gate's LEFT post (gate AABB tops
    // out at y 0.62; the right post hosts the street lantern). E4 places no
    // moving bird itself — ambient/Wave F owns all moving visitors.
    gardenFenceBird: Object.freeze([-0.8, 0.62, -1.9]),
  }),
});
