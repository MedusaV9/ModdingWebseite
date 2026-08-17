// W2d NETMG / W13C CROSSCHECK — Cross-Zertifizierung der Godot-Minigame-Ports
// gegen die ORIGINAL-Web-Logik (/workspace/GOOBY, READ-ONLY). Läuft die
// .logic.js-Bots mit denselben Seeds wie die Godot-Tests und schreibt die
// Referenz-Fixtures nach GOOBY-GODOT/tests/expected/*.json. Nach bestandener
// Zertifizierung werden die Dateien committet → Regressionsschutz auch ohne
// /workspace/GOOBY.
//
// Aufruf:  node tools/cross_check.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(ROOT, 'GOOBY-GODOT', 'tests', 'expected');
const MODES = ['easy', 'normal', 'hard', 'endless'];
const SEEDS = Array.from({ length: 50 }, (_, i) => i + 1);

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

// ── Zertifizierungs-Tabelle (W13C) ──────────────────────────────────────────
// Ein Eintrag pro zertifiziertem Spiel:
//   id      Fixture-Name (tests/expected/<id>.json) == Web-Modul-Name
//   fn      exportierte Autoplay-Funktion in GOOBY/src/minigames/games/<id>.logic.js
//   order   Argument-Reihenfolge der Web-Funktion ('modeFirst' | 'seedFirst')
//   fields  Ergebnis-Felder, die ins Fixture wandern (Score/Endzustand)
//   godot   Godot-Pendant (Logic-Klasse + simulate_autoplay-Reihenfolge),
//           rein informativ — der Vergleich lebt in
//           GOOBY-GODOT/tests/unit/test_w13c_crosscheck.gd.
//   tune    optional: [Konstanten-Export, applyDifficulty-Export] → schreibt
//           zusätzlich die normal/hard-Tunings ins Fixture (Bestands-Muster).
const GAMES = [
  {
    id: 'teaParty',
    fn: 'simulateTeaAutoplay',
    order: 'modeFirst',
    fields: ['score', 'cups', 'spills', 'elapsed'],
    godot: 'TeaPartyLogic.simulate_autoplay(mode, seed)',
    tune: ['TEA', 'applyDifficulty'],
  },
  {
    id: 'carrotCatch',
    fn: 'simulateCatchAutoplay',
    order: 'modeFirst',
    fields: ['score', 'elapsed', 'missedCarrots'],
    godot: 'CarrotCatchLogic.simulate_autoplay(mode, seed)',
    tune: ['CATCH', 'applyDifficulty'],
  },
  {
    id: 'bunnyHop',
    fn: 'simulateHopAutoplay',
    order: 'modeFirst',
    fields: ['score', 'gates'],
    godot: 'BunnyHopLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'memoryMatch',
    fn: 'simulateMemoryAutoplay',
    order: 'modeFirst',
    fields: ['score', 'rawScore', 'misses', 'elapsed'],
    godot: 'MemoryMatchLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'goobySays',
    fn: 'simulateAutoplay',
    order: 'seedFirst',
    fields: ['rounds', 'score'],
    godot: 'GoobySaysLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'bubblePop',
    fn: 'simulateBubbleAutoplay',
    order: 'seedFirst',
    fields: ['score', 'spikyPops'],
    godot: 'BubblePopLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'veggieChop',
    fn: 'simulateAutoplay',
    order: 'seedFirst',
    fields: ['score', 'misses', 'junkHits', 'elapsed'],
    godot: 'VeggieChopLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'pancakeTower',
    fn: 'simulatePancakeAutoplay',
    order: 'modeFirst',
    fields: ['score', 'layers', 'width'],
    godot: 'PancakeTowerLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'burgerBuild',
    fn: 'simulateAutoplay',
    order: 'seedFirst',
    fields: ['score', 'completed', 'expired'],
    godot: 'BurgerBuildLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'snailMail',
    fn: 'simulateSnailAutoplay',
    order: 'modeFirst',
    fields: ['score', 'deliveries', 'splashes', 'flowersPicked', 'elapsed'],
    godot: 'SnailMailLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'gardenRush',
    fn: 'simulateAutoplay',
    order: 'seedFirst',
    fields: ['score', 'withered', 'elapsed'],
    godot: 'GardenRushLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'basketBounce',
    fn: 'simulateBasketAutoplay',
    order: 'modeFirst',
    fields: ['score', 'elapsed', 'missStreak', 'baskets'],
    godot: 'BasketBounceLogic.simulate_autoplay(mode, seed)',
  },
  // ── W15/CROSSCHECK2: die 17 restlichen direkt machbaren Ports ─────────────
  // Felder mit '.' sind Dot-Pfade in Unter-Dictionaries (z. B. danceParty
  // tally.perfect) — pick() steigt ab, Godot-Seite macht dasselbe.
  {
    id: 'carrotGuard',
    fn: 'simulateGuardAutoplay',
    order: 'modeFirst',
    fields: ['score', 'elapsed', 'stolen'],
    godot: 'CarrotGuardLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'danceParty',
    fn: 'simulateDanceAutoplay',
    order: 'seedFirst',
    fields: [
      'score',
      'tally.perfect',
      'tally.good',
      'tally.miss',
      'tally.combo',
      'tally.maxCombo',
      'tally.bonus',
    ],
    godot: 'DancePartyLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'deliveryRush',
    fn: 'simulateDeliveryAutoplay',
    order: 'seedFirst',
    fields: ['score', 'elapsed', 'crashes', 'coinPoints'],
    godot: 'DeliveryRushLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'fishingPond',
    fn: 'simulateFishingAutoplay',
    order: 'seedFirst',
    fields: ['score', 'failures'],
    godot: 'FishingPondLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'ghostHunt',
    fn: 'simulateHuntAutoplay',
    order: 'modeFirst',
    fields: ['score', 'caught', 'missed', 'escapedWaves', 'booBonuses', 'time'],
    godot: 'GhostHuntLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'goalieGooby',
    fn: 'simulateAutoplay',
    order: 'seedFirst',
    fields: ['score', 'saves', 'goals', 'elapsed'],
    godot: 'GoalieGoobyLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'harborHopper',
    fn: 'simulateHarborAutoplay',
    order: 'modeFirst',
    fields: ['score', 'crates', 'rings', 'bumps', 'steals', 'boosts', 'distanceM', 'elapsed'],
    godot: 'HarborHopperLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'hideSeek',
    fn: 'simulateSeekAutoplay',
    order: 'modeFirst',
    fields: ['score', 'waves', 'found', 'expired', 'elapsed'],
    godot: 'HideSeekLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'lanternFloat',
    fn: 'simulateLanternAutoplay',
    order: 'modeFirst',
    fields: ['score', 'rings', 'hits', 'golds', 'fireflies', 'bumps', 'elapsed'],
    godot: 'LanternFloatLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'miniGolf',
    fn: 'simulateGolfAutoplay',
    order: 'seedFirst',
    fields: ['score', 'overPar'],
    godot: 'MiniGolfLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'pipeFlow',
    fn: 'simulatePipeAutoplay',
    order: 'seedFirst',
    fields: ['score', 'solved', 'failures'],
    godot: 'PipeFlowLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'rocketRescue',
    fn: 'simulateRocketAutoplay',
    order: 'modeFirst',
    fields: ['score', 'rescued', 'softLandings', 'hardLandings', 'fuelLeft', 'elapsed', 'endReason'],
    godot: 'RocketRescueBot.simulate_autoplay(mode, seed)',
  },
  {
    id: 'runner',
    fn: 'simulateRunnerAutoplay',
    order: 'modeFirst',
    fields: ['score', 'elapsed', 'meters', 'hits'],
    godot: 'RunnerLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'shoppingSurf',
    fn: 'simulateSurfAutoplay',
    order: 'modeFirst',
    fields: ['score', 'distanceM', 'coins', 'crashes', 'elapsed', 'ended'],
    godot: 'ShoppingSurfRun.simulate_autoplay(mode, seed)',
  },
  {
    id: 'starHopper',
    fn: 'simulateHopperAutoplay',
    order: 'seedFirst',
    fields: ['score', 'distance', 'pickups'],
    godot: 'StarHopperLogic.simulate_autoplay(seed, mode)',
  },
  {
    id: 'toyRacer',
    fn: 'simulateRacerAutoplay',
    order: 'modeFirst',
    fields: ['score', 'rank', 'races', 'wins', 'overtakes', 'driftMeters', 'time'],
    godot: 'ToyRacerLogic.simulate_autoplay(mode, seed)',
  },
  {
    id: 'trampoline',
    fn: 'simulateTrampolineAutoplay',
    order: 'seedFirst',
    fields: ['score', 'failures'],
    godot: 'TrampolineLogic.simulate_autoplay(seed, mode)',
  },
  // purblePlace hat KEIN Modus-Autoplay, sondern simulateRound(seed, opts)
  // (frame-getriebener Linien-Bot). order 'seedOpts' ruft
  // simulateRound(seed, { difficulty: mode }) — Godot-Pendant ist
  // PurblePlaceLogic.simulate_round(seed, mode).
  {
    id: 'purblePlace',
    fn: 'simulateRound',
    order: 'seedOpts',
    fields: [
      'score',
      'cakesServed',
      'perfectCakes',
      'rejected',
      'expired',
      'serves',
      'perfectBakes',
      'splats',
      'trashed',
      'tSec',
      'over',
    ],
    godot: 'PurblePlaceLogic.simulate_round(seed, mode)',
  },
];

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

// ── 2) Bot-Zertifizierung: Seeds 1..50 × 4 Modi je Tabellen-Eintrag ─────────
// Dot-Pfad-Zugriff (W15: danceParty tally.*) — im Fixture-Record bleibt der
// Pfad als flacher Key erhalten, die Godot-Seite steigt identisch ab.
function pick(result, path) {
  let value = result;
  for (const part of path.split('.')) {
    if (value == null || typeof value !== 'object' || !(part in value)) {
      throw new Error(`Feld ${path} fehlt im Web-Ergebnis`);
    }
    value = value[part];
  }
  return value;
}

for (const game of GAMES) {
  const mod = await import(join(ROOT, 'GOOBY', 'src', 'minigames', 'games', `${game.id}.logic.js`));
  const simulate = mod[game.fn];
  if (typeof simulate !== 'function') {
    throw new Error(`${game.id}: Web-Export ${game.fn} fehlt`);
  }
  const fixture = { modes: {} };
  for (const mode of MODES) {
    fixture.modes[mode] = SEEDS.map((seed) => {
      const r =
        game.order === 'modeFirst'
          ? simulate(mode, seed)
          : game.order === 'seedOpts'
            ? simulate(seed, { difficulty: mode })
            : simulate(seed, mode);
      const rec = { seed };
      for (const field of game.fields) {
        rec[field] = pick(r, field);
      }
      return rec;
    });
  }
  if (game.tune) {
    const [constName, applyName] = game.tune;
    fixture.tune = {
      normal: mod[applyName](mod[constName], 'normal'),
      hard: mod[applyName](mod[constName], 'hard'),
    };
  }
  writeFileSync(join(OUT_DIR, `${game.id}.json`), JSON.stringify(fixture, null, 2));
}

// ── 3) Difficulty-/Framework-Policy-Goldwerte ───────────────────────────────
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
for (const game of GAMES) {
  console.log(`  ${game.id}.json  (${MODES.length}×${SEEDS.length} Bot-Läufe → ${game.godot})`);
}
console.log(`  framework.json    (${coinCases.length} Coin-Fälle + Policy)`);
