// FullRelease N1-C — Manifest-Export: schreibt aus src/timeline.mjs (der
// einen Quelle für Bild UND Beats) die Haptik/Sound-Manifeste nach
// manifests/<scene>.haptics.json. Die App-Welle konsumiert sie über
// AVPlayer.addBoundaryTimeObserver (RECON_REMOTION_PIPELINE.md §3.6).
//
//   node src/export-manifests.mjs          → Manifeste (neu) schreiben
//   node src/export-manifests.mjs --check  → Drift-Gate: committete Dateien
//                                            müssen byte-identisch sein (CI)
//
// Validierung ist fail-closed: Beats/Cues außerhalb der Videolänge, unbekannte
// Cue-IDs oder Werte außerhalb 0…1 brechen den Export UND das CI-Gate.
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {FPS, SCENES} from './timeline.mjs';

// AppCue-IDs mit committetem Sample (`cue_<id>.caf`; plannedMode sample/hybrid
// in ios/SoooDreamy/Core/AppCueCatalog.swift + Resources/Sounds/sound_credits.json).
// Nur diese dürfen als Sound-Cue referenziert werden — synth-only-Cues würden
// zwar auch spielen, aber die Liste hält Manifest und Bundle beweisbar deckungsgleich.
const SAMPLE_CUE_IDS = new Set([
  'received',
  'sealed',
  'unseal',
  'kiss',
  'hug',
  'chime',
  'reveal',
  'unlock',
  'drop',
  'dice',
  'chip',
  'splash',
  'hit',
]);

const BEAT_TYPES = new Set(['tap', 'success', 'soft']);

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', 'manifests');
const checkMode = process.argv.includes('--check');

const fail = (msg) => {
  console.error(`✗ ${msg}`);
  process.exit(1);
};

const round3 = (v) => Math.round(v * 1000) / 1000;

for (const [key, scene] of Object.entries(SCENES)) {
  // ── Validierung (fail-closed) ─────────────────────────────────────────────
  if (!(scene.posterTime >= 0 && scene.posterTime < scene.durationSec)) {
    fail(`${key}: posterTime ${scene.posterTime} liegt außerhalb des Videos`);
  }
  for (const b of scene.beats) {
    if (!(b.t >= 0 && b.t + b.d <= scene.durationSec)) {
      fail(`${key}: Beat t=${b.t} d=${b.d} liegt außerhalb von 0…${scene.durationSec}s`);
    }
    if (!(b.i > 0 && b.i <= 1) || !(b.s >= 0 && b.s <= 1) || b.d < 0) {
      fail(`${key}: Beat t=${b.t} hat Werte außerhalb des HapticEventSpec-Bereichs`);
    }
    if (!BEAT_TYPES.has(b.type)) {
      fail(`${key}: Beat t=${b.t} hat unbekannten type "${b.type}"`);
    }
  }
  for (const c of scene.cues) {
    if (!(c.t >= 0 && c.t < scene.durationSec)) {
      fail(`${key}: Cue "${c.id}" t=${c.t} liegt außerhalb des Videos`);
    }
    if (!SAMPLE_CUE_IDS.has(c.id)) {
      fail(`${key}: Cue-ID "${c.id}" hat kein committetes cue_<id>.caf (AppCueCatalog)`);
    }
  }
  const sortedBeats = [...scene.beats].sort((a, b) => a.t - b.t);
  const sortedCues = [...scene.cues].sort((a, b) => a.t - b.t);

  // ── Serialisierung: feste Key-Reihenfolge, 2 Spaces, LF, Newline am Ende ──
  const manifest = {
    video: scene.video,
    composition: scene.composition,
    fps: FPS,
    durationSec: scene.durationSec,
    posterTime: scene.posterTime,
    beats: sortedBeats.map((b) => ({
      t: round3(b.t),
      type: b.type,
      i: b.i,
      s: b.s,
      d: b.d,
    })),
    cues: sortedCues.map((c) => ({t: round3(c.t), id: c.id})),
  };
  const json = `${JSON.stringify(manifest, null, 2)}\n`;
  const file = join(outDir, `${key}.haptics.json`);

  if (checkMode) {
    let existing = null;
    try {
      existing = readFileSync(file, 'utf8');
    } catch {
      fail(`${key}: ${file} fehlt — 'npm run manifests' ausführen und committen`);
    }
    if (existing !== json) {
      fail(`${key}: manifests/${key}.haptics.json driftet von src/timeline.mjs — 'npm run manifests' ausführen und committen`);
    }
    console.log(`✓ ${key}.haptics.json ist in sync (${manifest.beats.length} Beats, ${manifest.cues.length} Cues)`);
  } else {
    mkdirSync(outDir, {recursive: true});
    writeFileSync(file, json);
    console.log(`✓ geschrieben: manifests/${key}.haptics.json (${manifest.beats.length} Beats, ${manifest.cues.length} Cues)`);
  }
}

if (checkMode) {
  console.log('Manifest-Drift-Gate: alles in sync.');
}
