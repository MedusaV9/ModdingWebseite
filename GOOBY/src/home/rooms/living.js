// Living room definition (§C2, §C5.2) — PURE DATA, no three.js/DOM imports
// (see rooms/kitchen.js for the entry-shape documentation). The living room is
// the default room (ROOMS.DEFAULT).
//
// Fixed interactables: TV (opens arcade — G5), front door (starts the shop
// trip §C4 — G7 via G5), ball toy zone (ballSpawn anchor — G5).
// Decor slots (§C5.2): sofa(3) · tv(2) · rug(3) · plant(3) · lamp(2) ·
// bookcase(2) · wallArt(3 procedural canvases, no free default).

/** @type {import('../roomManager.js').RoomDef} */
export const ROOM = Object.freeze({
  id: 'living',

  slots: Object.freeze({
    // V2/G22 (§C8.1): + loungeChair 4th seating variant
    sofa: Object.freeze({ default: 'loungeSofa', items: Object.freeze(['loungeSofa', 'loungeDesignSofa', 'loungeSofaCorner', 'loungeChair']) }),
    tv: Object.freeze({ default: 'televisionVintage', items: Object.freeze(['televisionVintage', 'televisionModern']) }),
    rug: Object.freeze({ default: 'rugRounded', items: Object.freeze(['rugRounded', 'rugRectangle', 'rugRound']) }),
    plant: Object.freeze({ default: 'pottedPlant', items: Object.freeze(['pottedPlant', 'plantSmall1', 'plantSmall3']) }),
    lamp: Object.freeze({ default: 'lampRoundFloor', items: Object.freeze(['lampRoundFloor', 'lampSquareFloor']) }),
    bookcase: Object.freeze({ default: 'bookcaseOpen', items: Object.freeze(['bookcaseOpen', 'bookcaseClosedWide']) }),
    // procedural framed canvases (§C5.2) — G11 sells them; empty by default.
    // V2/G22 (§C8.1): +2 canvases (city skyline / rainbow)
    wallArt: Object.freeze({ default: null, items: Object.freeze(['proc:artSunset', 'proc:artCarrot', 'proc:artAbstract', 'proc:artSkyline', 'proc:artRainbow']) }),
    // ---- V2/G22 (§C8.1) new slots: both start empty like wallArt ----
    // ceiling fan hangs from the ceiling anchor (mount:'ceiling' in the catalog)
    ceilingFan: Object.freeze({ default: null, items: Object.freeze(['ceilingFan']) }),
    // side furniture along the right wall (coffee tables, cabinet, radio, speaker)
    sideboard: Object.freeze({ default: null, items: Object.freeze(['tableCoffee', 'tableCoffeeGlass', 'cabinetTelevision', 'radio', 'speaker']) }),
  }),

  // ---- V4/G79 (PLAN4-GAMES §G9.1): static room dressing, never saved ------
  // Aline geometry + picture frames merge into `color`; each sticker artwork
  // is one textured plane. V6/E4 adds the KayKit Furniture Bits reading nook
  // (one merged `kaykitbits` atlas batch) and a Tiny Treats monstera (one
  // `plants` atlas batch) — 5 dressing calls total, +2 vs the V5 baseline
  // (within the ≤4-added-per-room budget). Placements avoid the TV,
  // front-door hitbox, ballSpawn and the player-owned wallArt slot.
  dressing: Object.freeze([
    // V4/AC-3D: moved from the back wall (x −0.08, z −1.13) where it sat
    // INSIDE the sofa arm, the TV cabinet and the pinned V4/G52 radio fixture
    // (three simultaneous clips) — it now backs onto the right wall and opens
    // into the room (rotY −90: the pack faces +z natively).
    Object.freeze({
      id: 'alineBookshelf', kind: 'asset', batch: 'color',
      key: 'aline-furniture/bookshelf', at: Object.freeze([1.77, 0, -0.5]), scale: 0.68, rotY: -90,
    }),
    Object.freeze({
      id: 'pictureFirstNom', kind: 'picture', batch: 'picture-firstNom',
      art: 'firstNom', at: Object.freeze([0.32, 2.15, -1.43]),
    }),
    Object.freeze({
      id: 'pictureBallBuddy', kind: 'picture', batch: 'picture-ballBuddy',
      art: 'ballBuddy', at: Object.freeze([0.9, 2.15, -1.43]),
    }),
    // ---- V6/E4: KayKit Furniture Bits reading nook (one merged atlas call).
    // The armchair angles at the coffee table/TV (facing rule: target); its
    // rotated AABB corner overlaps the standing lamp's box on paper only —
    // the true rotated footprint clears the lamp pole by ≥0.24 m (bounded
    // clipAllow pair in roomAudit.rules.js). The lamp warms the corner right
    // of the Aline shelf; the book set tops the shelf; the standing frame
    // poses on the bookcase (the TV cabinet top is fully claimed by the
    // pinned radio fixture x −0.43…0.13 + the TV x 0.14…0.78).
    Object.freeze({
      id: 'readingNook', kind: 'assetCluster', batch: 'kaykitbits',
      pieces: Object.freeze([
        Object.freeze({ key: 'kaykit-furniture/armchair', at: Object.freeze([0.72, 0, 0.28]), scale: 0.62, rotY: -140 }),
        Object.freeze({ key: 'kaykit-furniture/lamp_standing', at: Object.freeze([1.62, 0, 0.06]), scale: 0.62 }),
        Object.freeze({ key: 'kaykit-furniture/book_set', at: Object.freeze([1.77, 1.001, -0.5]), scale: 0.5, rotY: -90 }),
        Object.freeze({ key: 'kaykit-furniture/pictureframe_standing_A', at: Object.freeze([-1.76, 1.36, -0.1]), scale: 0.5, rotY: 105 }),
      ]),
    }),
    // V6/E4: Tiny Treats monstera replaces the Aline plant in this corner
    // (the Aline plant moved to the bedroom) — one `plants` atlas batch.
    Object.freeze({
      id: 'livingPlants', kind: 'assetCluster', batch: 'plants',
      pieces: Object.freeze([
        Object.freeze({ key: 'house-plants/monstera_plant_large_potted', at: Object.freeze([-1.55, 0, 1.05]), scale: 0.24, rotY: 24 }),
      ]),
    }),
    // V6/FIX4 (P1-7): two warm emissive bulbs (one merged `fairy` batch).
    // The ceiling bulb pokes out under the lampSquareCeiling shade at the
    // room's center — homeScene.js parks the living night ambience point
    // light right below it, so the warm pool is anchored to a visibly lit
    // fixture instead of floating on the bare back-left corner. The second
    // bulb sits in the reading-nook standing lamp's shade (piece at
    // [1.62, 0, 0.06] — mostly past the 390 px portrait frustum edge
    // |x| ≈ 1.37, but it reads lit on wide viewports).
    Object.freeze({
      id: 'ceilingLampGlow', kind: 'lampGlow', at: Object.freeze([0, 2.68, -0.18]),
    }),
    Object.freeze({
      id: 'readingLampGlow', kind: 'lampGlow', at: Object.freeze([1.62, 1.24, 0.06]),
    }),
    // ---- end V6/E4 -----------------------------------------------------------
  ]),
  // ---- end V4/G79 ----------------------------------------------------------

  furniture: Object.freeze([
    // V4/POLISH-I: layered rugs — a big neutral base rug under the whole
    // seating group, with the swappable accent rug (decor slot) lifted 1.5 cm
    // on top so the two never z-fight. Centered on the sofa/coffee-table axis.
    Object.freeze({ item: 'rugSquare', at: Object.freeze([-0.55, 0, 0.2]), rotY: 0, scale: 1.3, noShadow: true }),
    Object.freeze({ slot: 'rug', item: 'rugRounded', at: Object.freeze([-0.55, 0.015, 0.25]), rotY: 0, noShadow: true }),
    // sofa against the back wall, facing the camera (decor slot)
    // V4/AC-3D: x −1.2 (was −0.9) clears the pinned V4/G52 radio fixture
    // (roomManager places it at x −0.43…0.13 on the cabinet's left end — the
    // old spot ran the sofa arm 0.19 m through it)
    Object.freeze({
      slot: 'sofa', item: 'loungeSofa', at: Object.freeze([-1.2, 0, -1.05]),
      rotY: 0, anchor: 'sofa', hitSize: Object.freeze([1.5, 0.8, 0.7]),
      // §C5.2 variant layouts: the corner sofa is a 1.5×1.5 m L-shape — its
      // footprint center sits 0.38 m deeper than the straight sofas, so
      // unshifted its backrest sinks through the back wall (bbox z −1.81).
      piecesByItem: Object.freeze({
        loungeSofaCorner: Object.freeze([
          Object.freeze({ item: 'loungeSofaCorner', at: Object.freeze([0, 0, 0.38]), rotY: 0 }),
        ]),
      }),
    }),
    // coffee table in front of the sofa + a book on top (set dressing)
    Object.freeze({ item: 'tableCoffee', at: Object.freeze([-0.85, 0, 0.3]), rotY: 0 }),
    Object.freeze({ item: 'books', at: Object.freeze([-0.9, 0.37, 0.3]), rotY: 20 }),
    // TV on its cabinet (tv = decor slot; cabinet is set dressing)
    // V4/AC-3D: cabinet x 0.2 (was 0.5) slides its top under the pinned radio
    // fixture (center x −0.15) so the radio rests ON the cabinet's left end
    // instead of hovering past its edge; the TV follows to x 0.45 so it clears
    // the radio's right side (radio bbox ends at x 0.13) while staying on top.
    Object.freeze({ item: 'cabinetTelevision', at: Object.freeze([0.2, 0, -1.24]), rotY: 0 }),
    Object.freeze({
      slot: 'tv', item: 'televisionVintage', at: Object.freeze([0.46, 0.49, -1.24]),
      rotY: 0, interact: 'tv', anchor: 'tv', hitSize: Object.freeze([0.75, 0.85, 0.6]),
      // the modern flat-screen is 1.06 m wide — full size it would run through
      // the pinned radio fixture on the cabinet's left end (radio bbox ends at
      // x 0.13), so nudge right + scale down to keep both on the cabinet top
      piecesByItem: Object.freeze({
        televisionModern: Object.freeze([
          Object.freeze({ item: 'televisionModern', at: Object.freeze([0.05, 0, 0]), rotY: 0, scale: 0.7 }),
        ]),
      }),
    }),
    // front door on the back wall right (procedural — starts the shop trip §C4)
    Object.freeze({
      proc: 'door', at: Object.freeze([1.55, 0, -1.47]), rotY: 0,
      interact: 'frontDoor', anchor: 'frontDoor', hitSize: Object.freeze([0.95, 2.0, 0.5]),
    }),
    // bookcase against the left half side-wall (decor slot)
    Object.freeze({ slot: 'bookcase', item: 'bookcaseOpen', at: Object.freeze([-1.76, 0, -0.1]), rotY: 90 }),
    // floor lamp on the left wall between sofa and bookcase (decor slot).
    // V4/AC-3D: the sofa's move to x −1.2 claimed the old back-left corner
    // (z −1.36) — the lamp pole ran through the sofa arm — so it slides to
    // the z −0.57 gap between the sofa front and the bookcase.
    Object.freeze({ slot: 'lamp', item: 'lampRoundFloor', at: Object.freeze([-1.82, 0, -0.57]), rotY: 0 }),
    // potted plant on the floor right of the TV cabinet (decor slot).
    // V4/AC-3D: the cabinet's move to x 0.2 (radio support) left the old
    // cabinet-top spot (x 0.98) hanging past the cabinet edge in mid-air —
    // the floor gap between cabinet and front door fits it at x 0.95.
    Object.freeze({ slot: 'plant', item: 'pottedPlant', at: Object.freeze([0.96, 0, -1.22]), rotY: 0, scale: 0.75 }),
    // wall-art slot anchor above the sofa (empty until bought — §C5.2)
    Object.freeze({ slot: 'wallArt', at: Object.freeze([-0.85, 1.9, -1.47]), rotY: 0 }),
    // V4/POLISH-I: media-corner speaker angled toward the sofa (clear of the
    // front-door hitbox at x ≥ 1.075/z ≤ −1.22 and of the ballSpawn anchor)
    Object.freeze({ item: 'speaker', at: Object.freeze([1.28, 0, -1.08]), rotY: -25, scale: 0.85 }),
    // ---- V3/G46 (§C11.1): committed furniture-kit room dressing ----------
    // The authored ceiling lamp grounds at its shade; lifting its base to
    // y=2.70 hangs its chain flush with the 3.2 m ceiling.
    Object.freeze({
      item: 'lampSquareCeiling', at: Object.freeze([0, 2.7, -0.18]),
      rotY: 0, scale: 1.4, dressing: 'v3-real-asset',
    }),
    // ---- end V3/G46 --------------------------------------------------------
    // ---- V2/G22 (§C8.1): new slot anchors (empty until bought) ----
    // ceiling-fan anchor just below the 3.2 m ceiling, over the room center
    Object.freeze({ slot: 'ceilingFan', at: Object.freeze([0, 3.08, -0.2]), rotY: 0 }),
    // sideboard spot on the right wall, facing into the room (the front door
    // sits at x 1.55 on the BACK wall — z 0.45 keeps them apart)
    Object.freeze({ slot: 'sideboard', at: Object.freeze([1.5, 0, 0.45]), rotY: -90 }),
  ]),

  anchors: Object.freeze({
    // centered-low per §C2, and clear of the TV so 'tap:tv' isn't shadowed by
    // Gooby's raycast priority
    goobyIdle: Object.freeze([-0.05, 0, 0.6]),
    /** Ball-toss zone (§C3) — G5 spawns the ball toy here. */
    ballSpawn: Object.freeze([1.1, 0, 0.9]),
  }),
});
