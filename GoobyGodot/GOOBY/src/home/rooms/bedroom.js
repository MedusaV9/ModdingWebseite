// Bedroom room definition (§C2, §C5.2) — PURE DATA, no three.js/DOM imports
// (see rooms/kitchen.js for the entry-shape documentation).
//
// Fixed interactables: bed (sleep target — G6), lamp switch (sleep toggle —
// G6, procedural wall switch), wardrobe closet (opens wardrobe UI — G12),
// window (procedural; sky follows the device clock — roomManager).
// Decor slots (§C5.2): bed(2) · nightstand(2) · rug(2, shared rug items) ·
// plushie(2, incl. Kenney bear + procedural mini-Gooby doll).

/** @type {import('../roomManager.js').RoomDef} */
export const ROOM = Object.freeze({
  id: 'bedroom',

  slots: Object.freeze({
    bed: Object.freeze({ default: 'bedSingle', items: Object.freeze(['bedSingle', 'bedDouble']) }),
    nightstand: Object.freeze({ default: 'lampSquareTable', items: Object.freeze(['lampSquareTable', 'lampRoundTable']) }),
    rug: Object.freeze({ default: 'rugRounded', items: Object.freeze(['rugRounded', 'rugRectangle', 'rugRound']) }),
    plushie: Object.freeze({ default: 'bear', items: Object.freeze(['bear', 'proc:miniGooby']) }),
    // ---- V2/G22 (§C8.1) new slots: both start empty like wallArt ----
    // side furniture by the bed's footboard (tables, cabinets, coat rack)
    sideTable: Object.freeze({ default: null, items: Object.freeze(['sideTable', 'sideTableDrawers', 'cabinetBed', 'cabinetBedDrawer', 'coatRackStanding']) }),
    // cozy floor clutter on the rug corner (pillows, books, trashcan)
    floorClutter: Object.freeze({ default: null, items: Object.freeze(['pillow', 'pillowBlue', 'books', 'trashcan']) }),
  }),

  // ---- V4/G79 (PLAN4-GAMES §G9.1): static room dressing, never saved ------
  // Rug + frame/cord + the relocated Aline plant merge into `color`;
  // emissive fairy dots and sticker art are one call each. V6/E4 adds the
  // KayKit cozy-corner cluster (wall frame + nightstand books, one merged
  // `kaykitbits` atlas batch) and a Tiny Treats sansevieria (one `plants`
  // batch) — 5 dressing calls total, +2 vs the V5 baseline. The picture
  // stays clear of the window, wardrobe and lamp-switch interaction zones.
  dressing: Object.freeze([
    Object.freeze({
      id: 'alineRug', kind: 'asset', batch: 'color',
      key: 'aline-furniture/rug', at: Object.freeze([-1.2, 0.01, -0.55]),
      scale: 0.72, rotX: -90,
    }),
    Object.freeze({
      id: 'fairyLights', kind: 'fairyLights', batch: 'fairy',
      at: Object.freeze([0, 2.72, -1.43]), count: 14, width: 3.35,
    }),
    Object.freeze({
      id: 'pictureSleepyhead', kind: 'picture', batch: 'picture-sleepyhead',
      art: 'sleepyhead', at: Object.freeze([-0.68, 2.12, -1.43]),
    }),
    // ---- V6/E4: KayKit cozy corner (one merged atlas call). The medium
    // frame hangs on the back wall above the wardrobe (model top y 1.96,
    // tap box top y 2.1 — the frame's y 2.12 base clears BOTH, so a tap on
    // the frame never reads as the wardrobe; wallMounted + elevated rules);
    // the book set replaces the old furniture-kit `books` stack on the
    // nightstand (removed below) so the tabletop stays a 3-piece composition.
    Object.freeze({
      id: 'cozyCorner', kind: 'assetCluster', batch: 'kaykitbits',
      pieces: Object.freeze([
        Object.freeze({ key: 'kaykit-furniture/pictureframe_medium', at: Object.freeze([1.42, 2.12, -1.415]), scale: 0.55 }),
        Object.freeze({ key: 'kaykit-furniture/book_set', at: Object.freeze([-0.5, 0.596, -1.26]), scale: 0.42, rotY: 20 }),
      ]),
    }),
    // V6/E4: the Aline plant moves here from the living room (its old corner
    // there now hosts the Tiny Treats monstera) — softens the bare strip
    // past the bed's footboard. z 0.72 keeps the leaf AABB clear of the
    // bed's generous tap box (hitSize ends at z 0.4 — the tap-zone lock in
    // test/roomAudit.test.js) while staying left of the sideTable slot spot.
    Object.freeze({
      id: 'alinePlant', kind: 'asset', batch: 'color',
      key: 'aline-furniture/plant', at: Object.freeze([-1.81, 0, 0.72]), scale: 1.2, rotY: 18,
    }),
    // V6/E4: Tiny Treats sansevieria in the right-wall gap between the
    // wardrobe front and the floorClutter slot anchor (one `plants` batch).
    Object.freeze({
      id: 'bedroomPlants', kind: 'assetCluster', batch: 'plants',
      pieces: Object.freeze([
        Object.freeze({ key: 'house-plants/sansevieria_plant_small_potted', at: Object.freeze([1.75, 0, -0.55]), scale: 0.3, rotY: -30 }),
      ]),
    }),
    // V6/FIX4 (P1-8): folded blanket at the bed's foot (merges into the
    // existing `color` batch — no extra draw call). Takes the bed spot the
    // bear-mask plushie vacated (it read as a dark crumpled shard on the
    // bedding; its slot anchor moved to the rug). Mattress top ≈ y 0.31;
    // z 0.12 keeps it inside the bed's footprint (z ≤ 0.4).
    Object.freeze({
      id: 'foldedBlanket', kind: 'foldedBlanket',
      at: Object.freeze([-1.2, 0.31, 0.12]),
    }),
    // ---- end V6/E4 -----------------------------------------------------------
  ]),
  // ---- end V4/G79 ----------------------------------------------------------

  furniture: Object.freeze([
    // bed on the left, headboard against the back wall (bed decor slot)
    Object.freeze({
      slot: 'bed', item: 'bedSingle', at: Object.freeze([-1.2, 0, -0.55]),
      rotY: 0, interact: 'bed', anchor: 'bed', hitSize: Object.freeze([1.0, 0.7, 1.9]),
    }),
    Object.freeze({ item: 'pillow', at: Object.freeze([-1.2, 0.3, -1.12]), rotY: 0, scale: 1.2 }),
    // V4/POLISH-I: second accent pillow — the bed reads as freshly made
    Object.freeze({ item: 'pillowBlue', at: Object.freeze([-1.04, 0.3, -0.98]), rotY: -14, scale: 0.95 }),
    // nightstand: side table (composition) + lamp on top (nightstand decor slot)
    // V6/E4: the V4/POLISH-I furniture-kit `books` stack on the table's left
    // end is replaced by the KayKit book_set in the dressing table above.
    Object.freeze({ item: 'sideTable', at: Object.freeze([-0.25, 0, -1.28]), rotY: 0 }),
    Object.freeze({
      slot: 'nightstand', item: 'lampSquareTable', at: Object.freeze([-0.25, 0.59, -1.28]),
      rotY: 0, anchor: 'lamp',
    }),
    // lamp switch — procedural wall plate next to the nightstand (sleep toggle)
    Object.freeze({
      proc: 'lampSwitch', at: Object.freeze([0.62, 1.12, -1.46]), rotY: 0,
      interact: 'lampSwitch', anchor: 'lampSwitch', hitSize: Object.freeze([0.45, 0.55, 0.3]),
    }),
    // wardrobe closet on the right (opens wardrobe UI — tall scaled cabinet)
    Object.freeze({
      item: 'bookcaseClosedWide', at: Object.freeze([1.42, 0, -1.25]), rotY: 0,
      scale: Object.freeze([0.85, 1.6, 1.0]), interact: 'wardrobe', anchor: 'wardrobe',
      hitSize: Object.freeze([1.15, 2.1, 0.6]),
    }),
    // window — procedural frame + day/night sky on the back wall (kept left of
    // the wardrobe: frame is 1.15 wide, wardrobe's left face starts at ≈0.89)
    Object.freeze({ proc: 'window', at: Object.freeze([0.22, 1.9, -1.49]), rotY: 0, anchor: 'window' }),
    // rug center-right (rug decor slot)
    Object.freeze({ slot: 'rug', item: 'rugRounded', at: Object.freeze([0.4, 0, 0.5]), rotY: 0, scale: 0.85, noShadow: true }),
    // plushie slot anchor (V6/FIX4 P1-8): moved off the bed — the bear GLB is
    // a flat bear-face mask that read as a dark crumpled shard on the pillow.
    // It now stands on the rug's left edge like a floor toy, face to camera
    // (a placed mini-Gooby doll lands here too). x −0.38 keeps a ≥0.09 m gap
    // to the bed's tap box (x ≤ −0.7); the rug underneath is flat (clip-safe);
    // the sideTable slot anchor (−1.4, 0.95) and Gooby's idle spot (0.55,
    // 0.65) stay clear. The fixture live box (test/fixtures/asset-bounds.json
    // bedroom[9]) was re-dumped for this spot.
    Object.freeze({ slot: 'plushie', item: 'bear', at: Object.freeze([-0.38, 0, 0.55]), rotY: 8, scale: 0.75 }),
    // ---- V3/G46 (§C11.1): committed furniture-kit room dressing ----------
    // Tiny real plant beside the table lamp; no saved sideTable/floorClutter
    // placement is consumed.
    Object.freeze({
      item: 'plantSmall1', at: Object.freeze([0.07, 0.59, -1.24]),
      rotY: -18, scale: 1.1, dressing: 'v3-real-asset',
    }),
    // ---- end V3/G46 --------------------------------------------------------
    // ---- V2/G22 (§C8.1): new slot anchors (empty until bought) ----
    // side furniture past the bed's footboard on the left (bed spans z ≈ −1.5…0.4)
    Object.freeze({ slot: 'sideTable', at: Object.freeze([-1.4, 0, 0.95]), rotY: 20 }),
    // floor clutter on the rug's right edge, clear of the wardrobe (z −1.25)
    Object.freeze({ slot: 'floorClutter', at: Object.freeze([1.2, 0, 0.85]), rotY: -15 }),
  ]),

  anchors: Object.freeze({
    goobyIdle: Object.freeze([0.55, 0, 0.65]),
  }),
});
