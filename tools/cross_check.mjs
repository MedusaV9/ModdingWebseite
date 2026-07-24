// W2d NETMG — Cross-Zertifizierung der Godot-Minigame-Ports gegen die
// ORIGINAL-Web-Logik (/workspace/GOOBY, READ-ONLY). Läuft die .logic.js-Bots
// mit denselben Seeds wie die Godot-Tests und schreibt die Referenz-Fixtures
// nach GOOBY-GODOT/tests/expected/*.json. Nach bestandener Zertifizierung
// werden die Dateien committet → Regressionsschutz auch ohne /workspace/GOOBY.
//
// Aufruf:  node tools/cross_check.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(ROOT, 'GOOBY-GODOT', 'tests', 'expected');
const MODES = ['easy', 'normal', 'hard', 'endless'];
const SEEDS = Array.from({ length: 50 }, (_, i) => i + 1);

const { simulateTeaAutoplay, applyDifficulty: teaApply, TEA } = await import(
  join(ROOT, 'GOOBY', 'src', 'minigames', 'games', 'teaParty.logic.js')
);
const { simulateCatchAutoplay, applyDifficulty: catchApply, CATCH } = await import(
  join(ROOT, 'GOOBY', 'src', 'minigames', 'games', 'carrotCatch.logic.js')
);
const fw = await import(join(ROOT, 'GOOBY', 'src', 'minigames', 'framework.logic.js'));
const { createRng } = await import(join(ROOT, 'GOOBY', 'src', 'minigames', 'framework.js')).catch(
  () => ({ createRng: null })
);

// framework.js zieht three.js — mulberry32 hier lokal identisch nachbauen,
// wenn der Import scheitert (gleicher Code wie framework.js createRng).
function rngFactory(seed) {
  if (createRng) return createRng(seed);
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t2 = Math.imul(a ^ (a >>> 15), 1 | a);
    t2 = (t2 + Math.imul(t2 ^ (t2 >>> 7), 61 | t2)) | 0;
    return ((t2 ^ (t2 >>> 14)) >>> 0) / 4294967296;
  };
}

mkdirSync(OUT_DIR, { recursive: true });

// ── 1) GoobyRng-Goldwerte ───────────────────────────────────────────────────
// floats: informativ (Godots Dezimal-Parser rundet 17-Steller ±1 ulp anders);
// u32: der BINDENDE Bit-Identitäts-Beweis (Ganzzahlen parsen exakt).
const rngGolden = { floats: {}, u32: {} };
for (const seed of [1, 2, 3, 42, 123456789]) {
  const rng = rngFactory(seed);
  rngGolden.floats[String(seed)] = Array.from({ length: 10 }, () => rng());
  let a = seed >>> 0;
  const u32 = () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) | 0;
    return (t ^ (t >>> 14)) >>> 0;
  };
  rngGolden.u32[String(seed)] = Array.from({ length: 10 }, () => u32());
}
writeFileSync(join(OUT_DIR, 'rng.json'), JSON.stringify(rngGolden, null, 2));

// ── 2) teaParty: Bot-Zertifizierung Seeds 1..50 × 4 Modi ────────────────────
const tea = { modes: {} };
for (const mode of MODES) {
  tea.modes[mode] = SEEDS.map((seed) => {
    const r = simulateTeaAutoplay(mode, seed);
    return { seed, score: r.score, cups: r.cups, spills: r.spills, elapsed: r.elapsed };
  });
}
tea.tune = { normal: teaApply(TEA, 'normal'), hard: teaApply(TEA, 'hard') };
writeFileSync(join(OUT_DIR, 'teaParty.json'), JSON.stringify(tea, null, 2));

// ── 3) carrotCatch: Bot-Zertifizierung Seeds 1..50 × 4 Modi ─────────────────
const cc = { modes: {} };
for (const mode of MODES) {
  cc.modes[mode] = SEEDS.map((seed) => {
    const r = simulateCatchAutoplay(mode, seed);
    return { seed, score: r.score, elapsed: r.elapsed, missedCarrots: r.missedCarrots };
  });
}
cc.tune = { normal: catchApply(CATCH, 'normal'), hard: catchApply(CATCH, 'hard') };
writeFileSync(join(OUT_DIR, 'carrotCatch.json'), JSON.stringify(cc, null, 2));

// ── 4) Difficulty-/Framework-Policy-Goldwerte ───────────────────────────────
const coinTables = {
  teaParty: { divisor: 4, min: 4, max: 26 },
  carrotCatch: { divisor: 3, min: 4, max: 25 },
};
const coinCases = [];
for (const [game, table] of Object.entries(coinTables)) {
  for (const score of [0, 1, 7, 20, 45, 70, 104, 500]) {
    for (const mode of ['easy', 'normal', 'hard']) {
      coinCases.push({
        game,
        score,
        mode,
        coins: fw.applyDifficultyCoinBase(table, score, mode),
      });
    }
  }
}
const policy = {
  coinCases,
  endlessFlatCoins: fw.ENDLESS_FLAT_COINS,
  endlessMinLevel: fw.ENDLESS_MIN_LEVEL,
  strikesForTeleport: fw.STRIKES_FOR_TELEPORT,
  effective: [
    ['teaParty', { difficulty: 'hard' }, 'hard'],
    ['teaParty', { difficulty: 'bogus' }, 'normal'],
    ['teaParty', { difficulty: 'hard', mode: 'shopTrip' }, 'normal'],
    ['cityDrive', { difficulty: 'hard' }, 'normal'],
    ['goobyWelt', { difficulty: 'easy' }, 'normal'],
  ].map(([id, params, want]) => ({
    id,
    params,
    want,
    got: fw.effectiveDifficulty(id, params),
  })),
  orientation: [
    ['landscape', 'landscape'],
    ['portrait', 'portrait'],
    [undefined, 'portrait'],
    ['weird', 'portrait'],
  ].map(([v, want]) => ({ value: v ?? null, want, got: fw.normalizeOrientation(v) })),
  rotateGate: [
    ['landscape', false, true],
    ['landscape', true, false],
    ['portrait', false, false],
    ['portrait', true, false],
  ].map(([o, land, want]) => ({
    orientation: o,
    viewportIsLandscape: land,
    want,
    got: fw.shouldShowRotateGate(o, land),
  })),
};
for (const c of policy.effective.concat(policy.orientation, policy.rotateGate)) {
  if (c.got !== c.want) throw new Error(`policy self-check failed: ${JSON.stringify(c)}`);
}
writeFileSync(join(OUT_DIR, 'framework.json'), JSON.stringify(policy, null, 2));

console.log(`OK — Fixtures unter ${OUT_DIR}:`);
console.log(`  rng.json          (5 Seeds × 10 Werte)`);
console.log(`  teaParty.json     (${MODES.length}×${SEEDS.length} Bot-Läufe)`);
console.log(`  carrotCatch.json  (${MODES.length}×${SEEDS.length} Bot-Läufe)`);
console.log(`  framework.json    (${coinCases.length} Coin-Fälle + Policy)`);
