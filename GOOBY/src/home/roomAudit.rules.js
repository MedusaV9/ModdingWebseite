// V4/AC-3D: per-room placement expectations for src/home/roomAudit.js — PURE
// data (no three.js/DOM). These rules encode the DELIBERATE composition of
// the 5 home rooms so the audit can flag everything else:
//   facing      — which pieces must face the camera (+z), a target point, or
//                 a fixed direction, and which must keep their back on a wall
//   clipAllow   — item pairs allowed to interpenetrate, BOUNDED (V4/FIX-3D):
//                 an allowance forgives at most clipAllowMax (0.30 m, or a
//                 tighter per-pair cap as an optional third tuple element) —
//                 never unlimited. The old unlimited whitelist let a 0.32 m
//                 garden tree∩compost clip ship unseen.
//   wallMounted — pieces mounted ON a wall (may embed up to its thickness)
//   elevated    — pieces legitimately above the floor with no supporter box
//                 (wall/ceiling mounts — anything else above floatMax must
//                 physically rest on another piece)
//   edgeAllow   — garden perimeter dressing that may straddle the ground edge
//   tiltAllow   — dressing keys whose authored rotX/rotZ is intentional
//   extras      — pinned cross-file fixtures replayed into the audit (the
//                 V4/G52 living radio: roomManager places it at the media
//                 cabinet's left end — keep in sync with roomManager.js)
//
// test/roomAudit.test.js runs auditRoom(def, fixture, AUDIT_RULES) for all 5
// ROOM_DEFS and requires ZERO warnings — tightening a rule (or removing an
// allowance) must come with a room fix that keeps the suite green.

/** @type {{global: object, rooms: Record<string, object>}} */
export const AUDIT_RULES = Object.freeze({
  /** tolerance overrides (see roomAudit.DEFAULT_TOLERANCES) — defaults hold */
  global: Object.freeze({}),

  rooms: Object.freeze({
    kitchen: Object.freeze({
      facing: Object.freeze({
        'furniture-kit/kitchenFridge': { mode: 'camera', wallBacked: true },
        'furniture-kit/kitchenCabinetDrawer': { mode: 'camera', wallBacked: true },
        'furniture-kit/kitchenSink': { mode: 'camera', wallBacked: true },
        'furniture-kit/kitchenStove': { mode: 'camera', wallBacked: true },
        'furniture-kit/kitchenCabinet': { mode: 'camera', wallBacked: true },
        'furniture-kit/kitchenCabinetUpper': { mode: 'camera' },
        'furniture-kit/toaster': { mode: 'camera' },
        'furniture-kit/kitchenCoffeeMachine': { mode: 'camera' },
        // both dining chairs must face the table top
        'furniture-kit/chair': { mode: 'target', at: [0.82, 0.18] },
        // bakery corner (dressing): the case front + mixer face the camera
        // (pack faces +x natively — the -90° rotY is what the audit verifies)
        'bakery-interior/display_case_short': { mode: 'camera' },
        'bakery-interior/stand_mixer': { mode: 'camera' },
        // V6/E4: the register joins the case top — same +x-native pack
        'bakery-interior/cash_register': { mode: 'camera' },
      }),
      wallMounted: Object.freeze(['furniture-kit/kitchenCabinetUpper']),
      elevated: Object.freeze(['furniture-kit/kitchenCabinetUpper']),
    }),

    living: Object.freeze({
      facing: Object.freeze({
        'furniture-kit/loungeSofa': { mode: 'camera', wallBacked: true },
        'furniture-kit/cabinetTelevision': { mode: 'camera', wallBacked: true },
        'furniture-kit/televisionVintage': { mode: 'camera' },
        'proc:door': { mode: 'camera', wallBacked: true },
        // bookcase backs onto the left wall and opens into the room (+x)
        'furniture-kit/bookcaseOpen': { mode: 'vector', dir: [1, 0], wallBacked: true },
        // media speaker angles toward the seating group
        'furniture-kit/speaker': { mode: 'target', at: [-0.85, 0.3] },
        // Aline bookshelf backs onto the right wall, opens into the room (−x)
        'aline-furniture/bookshelf': { mode: 'vector', dir: [-1, 0], wallBacked: true },
        'pleasant-picnic/radio': { mode: 'camera' },
        // V6/E4: the KayKit armchair angles at the coffee-table/TV corner
        // (rotY −140 ⇒ ~51° off the exact table line — inside the target cone)
        'kaykit-furniture/armchair': { mode: 'target', at: [-0.85, 0.3] },
        // V6/E4: the standing frame on the bookcase shows its picture into
        // the room (+x, rotY 105 ⇒ 15° off — kickstand toward the wall)
        'kaykit-furniture/pictureframe_standing_A': { mode: 'vector', dir: [1, 0] },
      }),
      wallMounted: Object.freeze(['proc:door']),
      elevated: Object.freeze(['furniture-kit/lampSquareCeiling']),
      clipAllow: Object.freeze([
        // V6/E4: rotated-AABB phantom only — the −140° armchair's
        // axis-aligned box corner sweeps over the standing lamp's box, but
        // the TRUE rotated footprint clears the lamp pole by ≥0.24 m and the
        // shade hangs above the chair back (shade y ≥1.1 vs chair top 0.76).
        // Bounded at 0.20 m so a real shove regresses loudly.
        ['kaykit-furniture/armchair', 'kaykit-furniture/lamp_standing', 0.2],
      ]),
      extras: Object.freeze([
        // V4/G52 pinned radio fixture (roomManager.js places it — scale 0.5,
        // groundAndCenter, then position; keep values in sync)
        Object.freeze({
          id: 'radioFixture', key: 'pleasant-picnic/radio',
          at: Object.freeze([-0.15, 0.52, -1.2]), scale: 0.5,
        }),
      ]),
    }),

    bathroom: Object.freeze({
      facing: Object.freeze({
        'furniture-kit/bathtub': { mode: 'camera' },
        'furniture-kit/toilet': { mode: 'camera', wallBacked: true },
        'furniture-kit/bathroomSink': { mode: 'camera', wallBacked: true },
        'furniture-kit/bathroomMirror': { mode: 'camera' },
        'furniture-kit/bathroomCabinet': { mode: 'camera' },
      }),
      wallMounted: Object.freeze([
        'furniture-kit/bathroomMirror',
        'furniture-kit/bathroomCabinet',
        'furniture-kit/bathroomSink',
        // V5/ASSETS: Tiny Treats roll holder mounts on the right wall
        'bubbly-bathroom/toilet_roll_holder',
      ]),
      elevated: Object.freeze([
        'furniture-kit/bathroomMirror',
        'furniture-kit/bathroomCabinet',
        'furniture-kit/lampSquareCeiling',
        // V5/ASSETS: the wall-mounted roll holder floats by design
        'bubbly-bathroom/toilet_roll_holder',
      ]),
    }),

    bedroom: Object.freeze({
      facing: Object.freeze({
        'furniture-kit/bedSingle': { mode: 'camera', wallBacked: true },
        'furniture-kit/sideTable': { mode: 'camera', wallBacked: true },
        'furniture-kit/bookcaseClosedWide': { mode: 'camera', wallBacked: true },
        'proc:window': { mode: 'camera' },
        'proc:lampSwitch': { mode: 'camera' },
        // V6/E4: the KayKit medium frame hangs on the back wall (its picture
        // shows +z at rotY 0) just above the wardrobe top
        'kaykit-furniture/pictureframe_medium': { mode: 'camera', wallBacked: true },
      }),
      wallMounted: Object.freeze([
        'proc:window', 'proc:lampSwitch',
        // V6/E4: wall-hung frame (may embed up to the wall thickness)
        'kaykit-furniture/pictureframe_medium',
      ]),
      elevated: Object.freeze([
        'proc:window', 'proc:lampSwitch', 'furniture-kit/lampSquareCeiling',
        // V6/E4: the frame hangs at y 2.0 — wall-mounted by intent, NOT
        // wardrobe-supported (a 4 cm air gap reads as hanging; declaring it
        // elevated keeps the audit honest if the wardrobe ever moves)
        'kaykit-furniture/pictureframe_medium',
      ]),
      clipAllow: Object.freeze([
        // pillows + plushie rest ON the mattress, below the headboard's AABB
        ['furniture-kit/pillow', 'furniture-kit/bedSingle'],
        ['furniture-kit/pillowBlue', 'furniture-kit/bedSingle'],
        ['furniture-kit/bear', 'furniture-kit/bedSingle'],
        // the two throw pillows overlap each other deliberately (cozy stack)
        ['furniture-kit/pillow', 'furniture-kit/pillowBlue'],
      ]),
      // the Aline round rug is authored as a vertical disc — decor.js lays it
      // flat with rotX −90 and grounds it afterwards
      tiltAllow: Object.freeze(['aline-furniture/rug']),
    }),

    garden: Object.freeze({
      facing: Object.freeze({
        'nature-kit/bench': { mode: 'camera' },
        'nature-kit/fence_gate': { mode: 'camera' },
        'proc:fertilizerBag': { mode: 'camera' },
        // V6/E4: the songbird perched on the bench backrest turns its beak
        // (+z native) toward the camera (rotY 20 ⇒ 20° off — inside the cone)
        'pretty-park/bird': { mode: 'camera' },
      }),
      // V4/FIX-3D: the old unlimited tree∩compost clipAllow is GONE — it hid
      // a 0.32×0.73×0.38 m canopy-through-bin clip. The garden layout now
      // keeps the pair fully separated, so no allowance is needed at all.
      edgeAllow: Object.freeze([
        // §C2.1 back fence/hedge line straddles the ground edge (outdoor
        // composition — same allowance as test/rooms.test.js)
        'city-kit-suburban/fence-1x4',
        'nature-kit/fence_gate',
        'nature-kit/plant_bushLarge',
        'nature-kit/tree_default',
      ]),
    }),
  }),
});
