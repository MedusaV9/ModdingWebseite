// Bathroom room definition (§C2, §C5.2) — PURE DATA, no three.js/DOM imports
// (see rooms/kitchen.js for the entry-shape documentation).
//
// Fixed interactables: bathtub (wash §C3 — G5), toilet (hygiene gag — G5),
// sink/mirror (composition). Decor slots (§C5.2): tub(2) · rug(2) · plant(1)
// · shelf(2).

/** @type {import('../roomManager.js').RoomDef} */
export const ROOM = Object.freeze({
  id: 'bathroom',

  slots: Object.freeze({
    // V2/G22 (§C8.1): + shower 3rd tub variant
    tub: Object.freeze({ default: 'bathtub', items: Object.freeze(['bathtub', 'showerRound', 'shower']) }),
    rug: Object.freeze({ default: 'rugDoormat', items: Object.freeze(['rugDoormat', 'rugSquare']) }),
    plant: Object.freeze({ default: 'plantSmall2', items: Object.freeze(['plantSmall2']) }),
    shelf: Object.freeze({ default: 'bathroomCabinet', items: Object.freeze(['bathroomCabinet', 'bathroomCabinetDrawer']) }),
    // V2/G22 (§C8.1) new slot: washing machine corner, empty until bought
    washer: Object.freeze({ default: null, items: Object.freeze(['washer']) }),
  }),

  // ---- V4/G79 (PLAN4-GAMES §G9.1): static room dressing, never saved ------
  // Trim, the towel set and Aline cactus share one vertex-color batch/call.
  dressing: Object.freeze([
    Object.freeze({
      id: 'wallTrim', kind: 'wallTrim', batch: 'color',
      tint: '#D9E8E4', walls: Object.freeze(['back', 'left']),
    }),
    Object.freeze({
      id: 'towelRail', kind: 'towelRail', batch: 'color',
      at: Object.freeze([-1.35, 1.62, -1.43]),
    }),
    // V4/AC-3D: lifted from (y 1.65, z −1.23) where the pot poked 8 cm through
    // the wall cabinet's front — it now stands ON the cabinet top (y 1.90,
    // recentered over its z −1.34 midline).
    Object.freeze({
      id: 'alineCactus', kind: 'asset', batch: 'color',
      key: 'aline-furniture/cactus', at: Object.freeze([1.1, 1.9, -1.34]), scale: 0.62, rotY: -12,
    }),
    // ---- V5/ASSETS: Tiny Treats bath dressing (bubbly-bathroom pack) -------
    // Soap dish + toothbrush cup on the sink top (y 0.868 basin ledge), ducky
    // waiting in front of the tub, towel stack by the left wall, spare-roll
    // stack next to the toilet, roll holder mounted on the right wall (rules:
    // wallMounted + elevated), and a potted monstera in the front-right
    // corner. One extra merged atlas batch ('bathware').
    Object.freeze({
      id: 'bathware', kind: 'assetCluster', batch: 'bathware',
      pieces: Object.freeze([
        Object.freeze({ key: 'bubbly-bathroom/soap_dish_pink', at: Object.freeze([0.3, 0.868, -1.3]), scale: 0.38, rotY: 8 }),
        Object.freeze({ key: 'bubbly-bathroom/toothbrush_cup_decorated', at: Object.freeze([0.28, 0.868, -1.16]), scale: 0.34, rotY: -20 }),
        Object.freeze({ key: 'bubbly-bathroom/ducky', at: Object.freeze([0.3, 0, -0.52]), scale: 0.5, rotY: -30 }),
        Object.freeze({ key: 'bubbly-bathroom/towel_stacked', at: Object.freeze([-1.62, 0, 0.55]), scale: 0.42, rotY: 12 }),
        Object.freeze({ key: 'bubbly-bathroom/toilet_roll_stack', at: Object.freeze([0.86, 0, -1.32]), scale: 0.4 }),
        Object.freeze({ key: 'bubbly-bathroom/toilet_roll_holder', at: Object.freeze([1.83, 0.62, -0.75]), scale: 0.45, rotY: -90 }),
        Object.freeze({ key: 'house-plants/monstera_plant_large_potted', at: Object.freeze([1.53, 0, 0.95]), scale: 0.22, rotY: -35 }),
        // ---- V6/E4 completion pass (same merged batch — +0 draw calls):
        // a second mini ducky waiting ON the tub's front rim (tub top
        // y 0.651 = native 0.42 × FURNITURE_SCALE 1.55; the tub tap zone
        // deliberately covers it — tapping the ducky taps the tub), and a
        // sansevieria filling the bare front-left floor corner.
        Object.freeze({ key: 'bubbly-bathroom/ducky', at: Object.freeze([-0.45, 0.651, -0.24]), scale: 0.3, rotY: -25 }),
        Object.freeze({ key: 'house-plants/sansevieria_plant_small_potted', at: Object.freeze([-1.8, 0, 1.1]), scale: 0.3, rotY: 20 }),
        // ---- end V6/E4 -----------------------------------------------------------
      ]),
    }),
    // ---- end V5/ASSETS -------------------------------------------------------
  ]),
  // ---- end V4/G79 ----------------------------------------------------------

  furniture: Object.freeze([
    // bathtub along the left side, facing the camera (tub decor slot)
    Object.freeze({
      slot: 'tub', item: 'bathtub', at: Object.freeze([-0.72, 0, -0.6]),
      rotY: 0, interact: 'bathtub', anchor: 'bathtub', hitSize: Object.freeze([1.95, 0.75, 1.0]),
    }),
    // toilet in the back-right corner, facing the camera
    Object.freeze({
      item: 'toilet', at: Object.freeze([1.22, 0, -1.02]), rotY: 0,
      interact: 'toilet', anchor: 'toilet', hitSize: Object.freeze([0.65, 0.85, 0.9]),
    }),
    // sink + mirror on the back wall
    Object.freeze({ item: 'bathroomSink', at: Object.freeze([0.45, 0, -1.28]), rotY: 0, anchor: 'sink' }),
    // z −1.36 keeps the mirror slab clear of the wall face (the model's frame
    // sits only ~2 cm in front of its shelf — closer and it sinks into the wall)
    Object.freeze({ item: 'bathroomMirror', at: Object.freeze([0.45, 1.05, -1.36]), rotY: 0 }),
    // wall shelf between mirror and toilet (decor slot)
    Object.freeze({
      slot: 'shelf', item: 'bathroomCabinet', at: Object.freeze([1.1, 1.3, -1.34]), rotY: 0,
      // the drawer cabinet is 0.5 m deep (vs 0.2) — unshifted its back sinks
      // 9 cm into the back wall (bbox z −1.59), so bring it forward
      piecesByItem: Object.freeze({
        bathroomCabinetDrawer: Object.freeze([
          Object.freeze({ item: 'bathroomCabinetDrawer', at: Object.freeze([0, 0, 0.11]), rotY: 0 }),
        ]),
      }),
    }),
    // bath mat in front of the tub (rug decor slot)
    Object.freeze({
      slot: 'rug', item: 'rugDoormat', at: Object.freeze([-0.5, 0, 0.6]), rotY: 0, scale: 1.6, noShadow: true,
      // the holder's ×1.6 doormat scale makes rugSquare a 2.2 m giant hanging
      // past the floor's front edge (bbox z 1.74 > 1.5) — counter-scale it
      piecesByItem: Object.freeze({
        rugSquare: Object.freeze([
          Object.freeze({ item: 'rugSquare', at: Object.freeze([0, 0, 0]), rotY: 0, scale: 0.62 }),
        ]),
      }),
    }),
    // little plant on the sink top (plant decor slot)
    Object.freeze({ slot: 'plant', item: 'plantSmall2', at: Object.freeze([0.58, 0.88, -1.2]), rotY: 0 }),
    // ---- V4/POLISH-I: tidy set dressing ------------------------------------
    // step-out mat squared up in front of the sink (the tub keeps its own rug
    // slot), a floor plant softening the bare back-left corner behind the tub,
    // and a small bin by the toilet — all clear of the tub/toilet/washer zones
    Object.freeze({ item: 'rugDoormat', at: Object.freeze([0.45, 0, -0.55]), rotY: 0, noShadow: true }),
    Object.freeze({ item: 'plantSmall3', at: Object.freeze([-1.72, 0, -1.25]), rotY: 25 }),
    Object.freeze({ item: 'trashcan', at: Object.freeze([1.7, 0, -0.45]), rotY: 0, scale: 0.75 }),
    // ---- end V4/POLISH-I ----------------------------------------------------
    // ---- V3/G46 (§C11.1): committed furniture-kit room dressing ----------
    // A real ceiling fixture adds a focal point without touching tub/sink
    // interactions or the saved decor slots.
    Object.freeze({
      item: 'lampSquareCeiling', at: Object.freeze([-0.1, 2.7, -0.2]),
      rotY: 15, scale: 1.35, dressing: 'v3-real-asset',
    }),
    // ---- end V3/G46 --------------------------------------------------------
    // ---- V2/G22 (§C8.1): washer slot anchor on the right wall, in front of
    // the toilet (toilet z −1.02, hit depth 0.9 → clear from z ≈ −0.4) ----
    Object.freeze({ slot: 'washer', at: Object.freeze([1.38, 0, 0.1]), rotY: -90 }),
  ]),

  anchors: Object.freeze({
    goobyIdle: Object.freeze([0.4, 0, 0.6]),
  }),
});
