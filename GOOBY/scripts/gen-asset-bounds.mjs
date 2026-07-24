#!/usr/bin/env node
// V4/AC-3D: CDP-driven generator for test/fixtures/asset-bounds.json — the
// machine-checkable ground truth behind src/home/roomAudit.js (the headless
// clip/orientation audit of the 5 home rooms).
//
// What it dumps (all lengths in meters, three.js axes):
//   assets[key]  = the NATIVE (pre-FURNITURE_SCALE, pre-groundAndCenter)
//                  axis-aligned bounding box of every HOME_ASSET_KEYS GLB,
//                  measured from a fresh assets.getModel(key) clone at
//                  identity, plus the asset's CANONICAL FORWARD unit vector
//                  (the horizontal direction the model's visual front faces
//                  at rotY 0 — pack-level conventions + per-key overrides
//                  below; null = no meaningful facing, e.g. rugs/plants).
//   assets['proc:<id>'] = the holder-local bbox of every procedural builder
//                  actually placed by the room tables (door, window,
//                  lampSwitch, compostBin, wateringCan, fertilizerBag,
//                  dirtPath), measured from the LIVE scene graph with the
//                  holder's own rotY/scale factored OUT (native frame).
//   livePlacedBoxes[roomId][] = per furniture entry, the room-local world
//                  AABB of the REAL placed model: native box corners pushed
//                  through the live holder → pieceHolder → model matrix
//                  chain (matrixWorld composition read from the running
//                  roomManager scene). test/roomAudit.test.js asserts the
//                  pure computePlacedBoxes replay agrees within 0.05 m —
//                  the drift lock that keeps the audit honest.
//
// Requirements (the standard GOOBY VM recipe — see AGENTS.md):
//   * dev server on :5174 (tmux session, `npm run dev`)
//   * headless Chrome with --remote-debugging-port=9222 (needs its own
//     --user-data-dir; no GL flags beyond the usual VM set)
//   * the `ws` module resolvable from the repo (present on the dev VM)
//
// Usage: node scripts/gen-asset-bounds.mjs [out.json]
//   env: GOOBY_URL (default http://localhost:5174)
//        GOOBY_CDP (default http://localhost:9222)

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import process from 'node:process';

// V4/FIX-3D: the audit rules are pure data — imported here so the generator
// can sanity-check every facing-rule key against the forwards it emits.
import { AUDIT_RULES } from '../src/home/roomAudit.rules.js';

const URL_BASE = process.env.GOOBY_URL ?? 'http://localhost:5174';
const CDP_BASE = process.env.GOOBY_CDP ?? 'http://localhost:9222';
const OUT = resolve(process.argv[2] ?? 'test/fixtures/asset-bounds.json');
// level=4 unlocks the garden (L3 gate) WITHOUT tripping the level-5 recap
// milestone, which would switch scenes and dispose the room manager mid-dump.
const PAGE_URL = `${URL_BASE}/?room=kitchen&onboarding=0&reset=1&level=4`;

let WebSocketImpl;
try {
  ({ default: WebSocketImpl } = await import('ws'));
} catch {
  console.error('gen-asset-bounds: the `ws` module is required (dev VM has it in a parent node_modules)');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Canonical-forward conventions. Kenney furniture-kit GLBs face +z at rotY 0
// (the binding room-table convention); bakery-interior faces +x (why the
// kitchen dressing uses rotY -90); most nature/outdoor props have no visual
// front (null). Per-key overrides win over the pack default.
// ---------------------------------------------------------------------------
const FORWARD_BY_PACK = {
  'furniture-kit': [0, 0, 1],
  'bakery-interior': [1, 0, 0],
  'pleasant-picnic': [0, 0, 1],
  // V6/E4: KayKit Furniture Bits shares the Kenney +z convention (armchair
  // seat/footrest expand toward +z at rotY 0; verified visually in-room).
  'kaykit-furniture': [0, 0, 1],
  // V6/E4: Tiny Treats packs — declared so the facing audit is no longer
  // blind by omission. Mugs/pots/plants/flowers/baskets have no meaningful
  // visual front (rotY is purely compositional) → pack-level null, with the
  // few real fronts opted back in via FORWARD_OVERRIDES below.
  'pretty-park': null,
  'house-plants': null,
  'charming-kitchen': null,
  'bubbly-bathroom': null,
  'baked-goods': null,
};
const FORWARD_OVERRIDES = {
  // V6/E4 pretty-park: only the bench + bird have a visual front; the
  // fountain/lantern are rotationally symmetric, flowers are clumps.
  'pretty-park/bench': [0, 0, 1],
  'pretty-park/bird': [0, 0, 1], // beak toward +z (larger +z bbox lobe)
  'pretty-park/fountain': null,
  // V6/E4 kaykit-furniture: books read fine at any angle; both frames show
  // their picture toward +z (the standing frame's kickstand leans to −z).
  'kaykit-furniture/book_set': null,
  'kaykit-furniture/lamp_standing': null,
  // V6/E4 bubbly-bathroom: the ducky's beak points +z (compositional only —
  // no facing rule keys it, but the forward documents the convention).
  'bubbly-bathroom/ducky': [0, 0, 1],
  // aline-furniture dressing pieces: only the bookshelf has a visual front
  'aline-furniture/bookshelf': [0, 0, 1],
  'aline-furniture/plant': null,
  'aline-furniture/cactus': null,
  'aline-furniture/rug': null,
  // rugs/pillows/books/plants — rotY is purely compositional
  'furniture-kit/rugRectangle': null,
  'furniture-kit/rugRounded': null,
  'furniture-kit/rugRound': null,
  'furniture-kit/rugSquare': null,
  'furniture-kit/rugDoormat': null,
  'furniture-kit/pillow': null,
  'furniture-kit/pillowBlue': null,
  'furniture-kit/books': null,
  'furniture-kit/pottedPlant': null,
  'furniture-kit/plantSmall1': null,
  'furniture-kit/plantSmall2': null,
  'furniture-kit/plantSmall3': null,
  'furniture-kit/trashcan': null,
  'furniture-kit/lampRoundFloor': null,
  'furniture-kit/lampSquareFloor': null,
  'furniture-kit/lampSquareTable': null,
  'furniture-kit/lampRoundTable': null,
  'furniture-kit/lampSquareCeiling': null,
  'furniture-kit/table': null,
  'furniture-kit/tableCoffee': null,
  'furniture-kit/bear': null, // authored lying on its back — no upright front
  // outdoor pack pieces with a real front
  'nature-kit/bench': [0, 0, 1],
  'nature-kit/fence_gate': [0, 0, 1],
};
const PROC_FORWARD = {
  door: [0, 0, 1],
  window: [0, 0, 1],
  lampSwitch: [0, 0, 1],
  compostBin: null,
  wateringCan: null, // spout points +x, but the tool reads fine at any angle
  fertilizerBag: [0, 0, 1], // sprout label patch on the +z face
  gardenBench: [0, 0, 1],
  dirtPath: null,
};

function forwardFor(key) {
  if (key in FORWARD_OVERRIDES) return FORWARD_OVERRIDES[key];
  const pack = key.split('/')[0];
  return FORWARD_BY_PACK[pack] ?? null;
}

// ---------------------------------------------------------------------------
// V4/FIX-3D: geometry-asymmetry sanity check. Every asset key that carries a
// facing rule in AUDIT_RULES must emit a USABLE canonical forward — a null
// forward silently blinds the audit's facing check for that piece, and a
// forward whose bbox is symmetric along the facing axis means the geometry
// alone cannot confirm the convention (front and back look identical to the
// box math — the human-set pack convention is all we have). Both cases are
// loudly warned so a bad/missing convention can't slip into the fixture
// unnoticed. Warnings are non-fatal: symmetric-but-correct fronts exist.
// ---------------------------------------------------------------------------
function forwardSanityWarnings(assets) {
  /** @type {Map<string, string[]>} facing-rule key → rooms that key it */
  const facingKeys = new Map();
  for (const [roomId, roomRules] of Object.entries(AUDIT_RULES.rooms)) {
    for (const key of Object.keys(roomRules.facing ?? {})) {
      if (!facingKeys.has(key)) facingKeys.set(key, []);
      facingKeys.get(key).push(roomId);
    }
  }
  const warnings = [];
  for (const [key, rooms] of facingKeys) {
    const where = `'${key}' (facing rule in ${rooms.join(', ')})`;
    const rec = assets[key];
    if (!rec) {
      warnings.push(`${where}: no fixture entry at all — the rule can never fire`);
      continue;
    }
    if (!rec.forward) {
      warnings.push(`${where}: canonical forward is NULL — the audit's facing check is `
        + 'blind for this piece. Add a FORWARD_OVERRIDES/PROC_FORWARD entry.');
      continue;
    }
    const [fx, , fz] = rec.forward;
    if (Math.abs(Math.abs(fx) - Math.abs(fz)) < 0.5 && fx !== 0 && fz !== 0) {
      warnings.push(`${where}: forward [${rec.forward}] is diagonal/ambiguous — pick a `
        + 'dominant axis so the facing cone has a stable reference.');
      continue;
    }
    const axis = Math.abs(fx) >= Math.abs(fz) ? 0 : 2;
    const extent = rec.max[axis] - rec.min[axis];
    if (!(extent > 1e-6)) {
      warnings.push(`${where}: zero extent along its forward axis — degenerate bbox.`);
      continue;
    }
    const asym = Math.abs(rec.max[axis] + rec.min[axis]) / extent;
    if (asym < 0.005) {
      warnings.push(`${where}: bbox is symmetric along the forward axis `
        + `(asym ${(asym * 100).toFixed(2)} %) — geometry cannot confirm the front; `
        + 're-verify the pack convention if this model was re-exported.');
    }
  }
  return warnings;
}

// ---------------------------------------------------------------------------
// Minimal CDP client (no deps beyond ws)
// ---------------------------------------------------------------------------
async function connect(url) {
  const res = await fetch(`${CDP_BASE}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' });
  const target = await res.json();
  const ws = new WebSocketImpl(target.webSocketDebuggerUrl, { maxPayload: 512 * 1024 * 1024 });
  await new Promise((ok, bad) => { ws.once('open', ok); ws.once('error', bad); });
  let id = 0;
  const pending = new Map();
  ws.on('message', (data) => {
    const msg = JSON.parse(data);
    if (msg.id && pending.has(msg.id)) {
      const { ok, bad } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) bad(new Error(JSON.stringify(msg.error)));
      else ok(msg.result);
    }
  });
  const send = (method, params = {}) => new Promise((ok, bad) => {
    id += 1;
    pending.set(id, { ok, bad });
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evalJs = async (expression) => {
    const r = await send('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true, timeout: 180000,
    });
    if (r.exceptionDetails) {
      throw new Error(`page exception: ${JSON.stringify(r.exceptionDetails).slice(0, 4000)}`);
    }
    return r.result.value;
  };
  const close = async () => {
    try { await fetch(`${CDP_BASE}/json/close/${target.id}`); } catch { /* best effort */ }
    ws.close();
  };
  return { evalJs, close };
}

// ---------------------------------------------------------------------------
// The page-side collector. Plain-JS mat4 math (column-major, matching
// three.js Matrix4.elements) so the script needs no THREE global: local
// matrices of the live scene graph are composed by hand and geometry
// bounding-box corners are pushed through them.
// ---------------------------------------------------------------------------
const PAGE_COLLECT = `(async () => {
  const assets = await import('/src/core/assets.js');
  const rmMod = await import('/src/home/roomManager.js');
  const mgr = globalThis.__goobyRoomManager;
  if (!mgr) return { error: 'no __goobyRoomManager (dev seam missing?)' };

  // home furniture keys + the V4/G79 dressing asset keys (decor.js preloads
  // the latter for its merged room-dressing batches — same clip risk).
  const dressingKeys = [...new Set(rmMod.ROOM_DEFS.flatMap((def) =>
    (def.dressing ?? []).flatMap((entry) => {
      if (entry.kind === 'asset') return [entry.key];
      if (entry.kind === 'assetCluster') return entry.pieces.map((piece) => piece.key);
      return [];
    })
  ))];
  const keys = [...new Set([...rmMod.HOME_ASSET_KEYS, ...dressingKeys])];
  for (let i = 0; i < 480; i += 1) {
    if (keys.every((k) => assets.isLoaded(k))) break;
    await new Promise((r) => setTimeout(r, 250));
  }
  const missing = keys.filter((k) => !assets.isLoaded(k));
  if (missing.length) return { error: 'assets never loaded: ' + missing.join(', ') };

  // ---- mat4 helpers (column-major like three.js) ----
  const I = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1];
  const mul = (a, b) => {
    const r = new Array(16);
    for (let c = 0; c < 4; c += 1) {
      for (let ro = 0; ro < 4; ro += 1) {
        r[c * 4 + ro] = a[ro] * b[c * 4] + a[4 + ro] * b[c * 4 + 1]
          + a[8 + ro] * b[c * 4 + 2] + a[12 + ro] * b[c * 4 + 3];
      }
    }
    return r;
  };
  const newBox = () => ({ min: [Infinity, Infinity, Infinity], max: [-Infinity, -Infinity, -Infinity] });
  const growPoint = (box, x, y, z) => {
    if (x < box.min[0]) box.min[0] = x; if (x > box.max[0]) box.max[0] = x;
    if (y < box.min[1]) box.min[1] = y; if (y > box.max[1]) box.max[1] = y;
    if (z < box.min[2]) box.min[2] = z; if (z > box.max[2]) box.max[2] = z;
  };
  const growXformedBox = (out, m, min, max) => {
    for (const cx of [min[0], max[0]]) for (const cy of [min[1], max[1]]) for (const cz of [min[2], max[2]]) {
      growPoint(out,
        m[0] * cx + m[4] * cy + m[8] * cz + m[12],
        m[1] * cx + m[5] * cy + m[9] * cz + m[13],
        m[2] * cx + m[6] * cy + m[10] * cz + m[14]);
    }
  };
  const locMat = (o) => Array.from(o.matrix.elements);

  // subtree AABB in ROOT-LOCAL space (root's own transform excluded)
  const meshLocalBox = (root) => {
    const out = newBox();
    const walk = (o, m) => {
      const lm = o === root ? I : mul(m, locMat(o));
      if (o.isMesh && o.geometry) {
        o.geometry.computeBoundingBox();
        const b = o.geometry.boundingBox;
        growXformedBox(out, lm, [b.min.x, b.min.y, b.min.z], [b.max.x, b.max.y, b.max.z]);
      }
      for (const ch of o.children) walk(ch, lm);
    };
    walk(root, I);
    return out;
  };
  const round = (v) => Math.round(v * 1e5) / 1e5;
  const roundBox = (b) => ({ min: b.min.map(round), max: b.max.map(round) });

  // ---- 1) native GLB bounds from fresh identity clones ----
  const nativeBoxes = {};
  for (const key of keys) {
    const m = assets.getModel(key);
    m.updateMatrixWorld(true);
    nativeBoxes[key] = roundBox(meshLocalBox(m));
  }

  // ---- 2+3) per-room: proc native bounds + live placed boxes ----
  const procBoxes = {};
  const livePlacedBoxes = {};
  const problems = [];
  for (const def of rmMod.ROOM_DEFS) {
    const group = mgr.getRoomGroup(def.id);
    if (!group) { problems.push(def.id + ': no room group'); continue; }
    group.updateMatrixWorld(true);
    const holders = group.children.filter((c) => /^(slot-|furn-)/.test(c.name));
    const expected = def.furniture
      .map((e, i) => ({ e, i }))
      .filter(({ e }) => !(e.slot && !e.item && !e.pieces && !e.proc))
      .map(({ e, i }) => ({ e, i, name: e.slot ? 'slot-' + e.slot : 'furn-' + (e.item ?? e.proc) }));
    const rows = [];
    let cursor = 0;
    for (const exp of expected) {
      let holder = null;
      for (let j = cursor; j < holders.length; j += 1) {
        if (holders[j].name === exp.name) { holder = holders[j]; cursor = j + 1; break; }
      }
      if (!holder) { problems.push(def.id + ': holder ' + exp.name + ' not found'); continue; }

      if (exp.e.proc) {
        const procKey = 'proc:' + exp.e.proc;
        if (!procBoxes[procKey]) procBoxes[procKey] = roundBox(meshLocalBox(holder));
        const out = newBox();
        const nb = procBoxes[procKey];
        growXformedBox(out, locMat(holder), nb.min, nb.max);
        rows.push({ index: exp.i, name: exp.name, key: procKey, ...roundBox(out) });
      } else {
        // GLB entry: holder → pieceHolder(s) → model. Push the NATIVE box
        // through the live local-matrix chain (model.matrix carries the
        // FURNITURE_SCALE + groundAndCenter offsets roomManager baked in).
        const out = newBox();
        const pieceKeys = [];
        for (const pieceHolder of holder.children) {
          const model = pieceHolder.children.find((ch) => nativeBoxes[ch.name]);
          if (!model) { problems.push(def.id + ':' + exp.name + ': unrecognized piece'); continue; }
          pieceKeys.push(model.name);
          const chain = mul(locMat(holder), mul(locMat(pieceHolder), locMat(model)));
          const nb = nativeBoxes[model.name];
          growXformedBox(out, chain, nb.min, nb.max);
        }
        rows.push({ index: exp.i, name: exp.name, key: pieceKeys.join('+'), ...roundBox(out) });
      }
    }
    livePlacedBoxes[def.id] = rows;
  }

  // ---- V4/G52 radio fixture (living) — pinned spot, audited as an extra ----
  const living = mgr.getRoomGroup('living');
  const radio = living && living.children.find((c) => c.name === 'v4-radio-fixture');
  const radioBox = radio
    ? roundBox((() => { const o = newBox(); growXformedBox(o, locMat(radio), ...(() => { const b = meshLocalBox(radio); return [b.min, b.max]; })()); return o; })())
    : null;

  return {
    furnitureScale: rmMod.FURNITURE_SCALE,
    nativeBoxes, procBoxes, livePlacedBoxes, radioBox, problems,
  };
})()`;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
console.log(`gen-asset-bounds: opening ${PAGE_URL}`);
const cdp = await connect(PAGE_URL);
try {
  const ready = await cdp.evalJs(`(async () => {
    for (let i = 0; i < 1200; i += 1) {
      if (globalThis.__goobyRoomManager?.getRoomGroup?.('garden')) return true;
      await new Promise((r) => setTimeout(r, 250));
    }
    return false;
  })()`);
  if (!ready) throw new Error('room manager never appeared (is the dev server on 5174 serving a DEV build?)');
  // let the first frames render so every local matrix is current
  await new Promise((r) => setTimeout(r, 1500));

  const data = await cdp.evalJs(PAGE_COLLECT);
  if (!data || data.error) throw new Error(`collector failed: ${data && data.error}`);
  if (data.problems?.length) throw new Error(`collector problems:\n  ${data.problems.join('\n  ')}`);

  const assets = {};
  for (const [key, box] of Object.entries(data.nativeBoxes)) {
    assets[key] = { min: box.min, max: box.max, forward: forwardFor(key) };
  }
  for (const [key, box] of Object.entries(data.procBoxes)) {
    assets[key] = { min: box.min, max: box.max, forward: PROC_FORWARD[key.slice(5)] ?? null };
  }

  // V4/FIX-3D: non-fatal facing-forward sanity report (see forwardSanityWarnings)
  for (const w of forwardSanityWarnings(assets)) {
    console.warn(`gen-asset-bounds: FORWARD WARNING — ${w}`);
  }

  const fixture = {
    comment: 'GENERATED by scripts/gen-asset-bounds.mjs — do not hand-edit. Native asset AABBs (pre-scale) + canonical forwards + live placed-box ground truth for src/home/roomAudit.js.',
    meta: {
      furnitureScale: data.furnitureScale,
      shell: { width: 4, depth: 3, height: 3.2, sideDepth: 1.9, wallThickness: 0.12 },
      gardenSize: { width: 5, depth: 4 },
      radioBox: data.radioBox,
    },
    assets,
    livePlacedBoxes: data.livePlacedBoxes,
  };

  mkdirSync(dirname(OUT), { recursive: true });
  // repo convention: CRLF endings, even for fixtures
  writeFileSync(OUT, `${JSON.stringify(fixture, null, 2)}\n`.replace(/\n/g, '\r\n'));
  console.log(`gen-asset-bounds: wrote ${OUT}`);
  console.log(`  asset keys: ${Object.keys(assets).length}`);
  for (const [roomId, rows] of Object.entries(data.livePlacedBoxes)) {
    console.log(`  ${roomId}: ${rows.length} live placed boxes`);
  }
} finally {
  await cdp.close();
}
