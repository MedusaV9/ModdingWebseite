// HOOK-KURATION (Eval 3, P3): Der Import normalisiert den GANZEN Song auf
// −16 LUFS — ist die Hook-Stelle selbst leise (La Vie en rose: −25 LUFS am
// 1-s-Buzz!), bleiben die Buzz-Schnipsel im Match kaum hörbar. Dieses Tool
// misst die HOOK-Schnipsel aller Songs (buzz_ms1000 als Proxy der Buzz-Serie
// — 100-ms-LUFS wäre Messrauschen — plus rueckwaerts5s) per ffmpeg-loudnorm
// und zieht Ausreißer > 3 dB mit KONSTANTEM Gain auf −16 LUFS nach
// (True-Peak-Deckel −1,5 dBTP wie der Import — kein Dynamik-Pumpen).
//
//   node tools/musik/normalisiere-hooks.mjs           → messen + nachziehen
//   node tools/musik/normalisiere-hooks.mjs --check   → nur messen (Exit 1 bei Ausreißern)
//
// Der ms1000-Gain gilt für ALLE 5 Buzz-Stufen (gleiche Hook-Sekunde);
// rueckwaerts5s bekommt seinen eigenen Mess-Gain. intro5s/mitte10s bleiben
// unangetastet (nicht Hook-basiert, vom Master-loudnorm sauber abgedeckt).
import { spawnSync } from "node:child_process";
import { readFileSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HIER = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HIER, "..", "..");
const MUSIK_DIR = join(REPO, "content", "musik");
const ZIEL_LUFS = -16;
const TOLERANZ_DB = 3;
const TP_DECKEL = -1.5;
const NUR_CHECK = process.argv.includes("--check");

function fehler(text) {
  console.error(`\nFEHLER: ${text}`);
  process.exit(1);
}

/** loudnorm-Messung: { lufs, tp } — ffmpeg druckt den JSON-Block nach stderr. */
function miss(datei) {
  const r = spawnSync(
    "ffmpeg",
    ["-hide_banner", "-i", datei, "-af", "loudnorm=print_format=json", "-f", "null", "-"],
    { encoding: "utf8" },
  );
  if (r.error) fehler(`ffmpeg ließ sich nicht starten: ${r.error.message}`);
  const text = String(r.stderr ?? "");
  const i = text.lastIndexOf("{");
  if (r.status !== 0 || i < 0) fehler(`loudnorm-Messung scheiterte an ${datei}`);
  const j = JSON.parse(text.slice(i));
  return { lufs: Number(j.input_i), tp: Number(j.input_tp) };
}

/** Konstanten Gain anwenden (Re-Encode libvorbis q5 wie der Import).
 * mitLimiter: voller Wunsch-Gain + True-Peak-Limiter bei −1,5 dBTP — für
 * Crest-Fälle (leise Passage mit einzelner Spitze), wo der lineare
 * TP-Deckel den Gain sonst auf wirkungslose Bruchteile kappen würde. */
function wendeGainAn(datei, gainDb, mitLimiter = false) {
  const tmp = join(tmpdir(), `mm-hook-${Date.now()}-${Math.random().toString(36).slice(2)}.ogg`);
  const limit = Math.pow(10, TP_DECKEL / 20).toFixed(4); // −1,5 dBTP linear
  const af = mitLimiter
    ? `volume=${gainDb.toFixed(2)}dB,alimiter=limit=${limit}:level=false`
    : `volume=${gainDb.toFixed(2)}dB`;
  const r = spawnSync(
    "ffmpeg",
    ["-hide_banner", "-y", "-i", datei, "-af", af, "-c:a", "libvorbis", "-q:a", "5", tmp],
    { encoding: "utf8" },
  );
  if (r.status !== 0) fehler(`ffmpeg-Gain scheiterte an ${datei}:\n${r.stderr.slice(-800)}`);
  renameSync(tmp, datei);
}

/** Gain-Plan eines Ausreißers: linear solange der True Peak es hergibt,
 * sonst voller Gain + Limiter (Kappung > 1 dB wäre wirkungslos leise). */
function gainPlan(mess) {
  const wunsch = ZIEL_LUFS - mess.lufs;
  const linear = Math.min(wunsch, TP_DECKEL - mess.tp);
  const mitLimiter = wunsch - linear > 1;
  return { gain: mitLimiter ? wunsch : linear, mitLimiter };
}

const katalog = JSON.parse(readFileSync(join(MUSIK_DIR, "songs.json"), "utf8"));
if (!Array.isArray(katalog.songs)) fehler("songs.json ohne songs[]");

console.log(
  `Hook-Kuration: ${katalog.songs.length} Songs, Ziel ${ZIEL_LUFS} LUFS ± ${TOLERANZ_DB} dB` +
    (NUR_CHECK ? " (NUR CHECK)" : ""),
);
console.log("");

let ausreisser = 0;
for (const song of katalog.songs) {
  // Bett-Loops (import.mjs --bett) haben keine Hook-Snippets — der Loop ist
  // beim Import bereits als Ganzes auf −18 LUFS normalisiert.
  if (song.medien?.bett !== undefined && song.medien?.intro5s === undefined) continue;
  const pfad = (ref) => join(MUSIK_DIR, ref);
  const zeilen = [];

  // 1) Buzz-Serie: ms1000 messen, Gain für ALLE 5 Stufen (gleiche Hook-Sekunde).
  const buzzDatei = pfad(song.medien.buzz.ms1000);
  const b = miss(buzzDatei);
  const buzzDelta = b.lufs - ZIEL_LUFS;
  if (Math.abs(buzzDelta) > TOLERANZ_DB) {
    ausreisser += 1;
    const plan = gainPlan(b);
    zeilen.push(
      `  buzz-Serie:    ${b.lufs.toFixed(1)} LUFS (${buzzDelta > 0 ? "+" : ""}${buzzDelta.toFixed(1)} dB)` +
        (NUR_CHECK
          ? "  ⇒ AUSSER TOLERANZ"
          : `  ⇒ Gain ${plan.gain.toFixed(1)} dB${plan.mitLimiter ? " + TP-Limiter" : ""} auf alle 5 Stufen`),
    );
    if (!NUR_CHECK) {
      for (const ref of Object.values(song.medien.buzz)) {
        wendeGainAn(pfad(ref), plan.gain, plan.mitLimiter);
      }
      const nach = miss(buzzDatei);
      zeilen.push(`                 nachher: ${nach.lufs.toFixed(1)} LUFS (ms1000)`);
    }
  }

  // 2) rueckwaerts5s: eigener Mess-Gain (5-s-Fenster ab derselben Hook-Sekunde).
  const rueckDatei = pfad(song.medien.rueckwaerts5s);
  const r = miss(rueckDatei);
  const rueckDelta = r.lufs - ZIEL_LUFS;
  if (Math.abs(rueckDelta) > TOLERANZ_DB) {
    ausreisser += 1;
    const plan = gainPlan(r);
    zeilen.push(
      `  rueckwaerts5s: ${r.lufs.toFixed(1)} LUFS (${rueckDelta > 0 ? "+" : ""}${rueckDelta.toFixed(1)} dB)` +
        (NUR_CHECK
          ? "  ⇒ AUSSER TOLERANZ"
          : `  ⇒ Gain ${plan.gain.toFixed(1)} dB${plan.mitLimiter ? " + TP-Limiter" : ""}`),
    );
    if (!NUR_CHECK) {
      wendeGainAn(rueckDatei, plan.gain, plan.mitLimiter);
      const nach = miss(rueckDatei);
      zeilen.push(`                 nachher: ${nach.lufs.toFixed(1)} LUFS`);
    }
  }

  const status = zeilen.length > 0 ? "⚠" : "✓";
  console.log(
    `${status} ${song.id.padEnd(42)} ms1000 ${b.lufs.toFixed(1).padStart(6)}  rueck ${r.lufs
      .toFixed(1)
      .padStart(6)}`,
  );
  for (const z of zeilen) console.log(z);
}

console.log("");
if (ausreisser === 0) {
  console.log(`✓ Alle Hook-Schnipsel innerhalb ± ${TOLERANZ_DB} dB um ${ZIEL_LUFS} LUFS.`);
} else if (NUR_CHECK) {
  console.error(
    `✗ ${ausreisser} Hook-Ausreißer > ${TOLERANZ_DB} dB — Lauf ohne --check zieht nach.`,
  );
  process.exit(1);
} else {
  console.log(
    `✓ ${ausreisser} Ausreißer nachgezogen (konstanter Gain, TP-Deckel ${TP_DECKEL} dBTP).`,
  );
}
