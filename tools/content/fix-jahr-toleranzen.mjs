#!/usr/bin/env node
/* global process, console */
// Jahreszahl-Toleranz-Migration (Eval-5 P2): Kalenderjahr-Schätzfragen mit
// toleranz_prozent bekommen ein ABSOLUTES Volltreffer-Fenster in Jahren.
// Hintergrund: 1 % von 1969 sind ±20 Jahre — jede wilde Raterei wäre ein
// „Volltreffer". Der Tresor wertet toleranz_absolut VOR toleranz_prozent.
//
// Scan: einheit „Jahr" (Singular!) mit richtwert 1000–2100 oder einheit
// „Jahr v. Chr." — Dauer-/Alters-Fragen („Jahre", „Millionen Jahre") behalten
// bewusst ihre prozentuale Toleranz. Fenster nach Schwierigkeit:
// leicht ±5, mittel ±4, schwer ±3, ultrahard ±2 (Design-Spanne 2–5).
// Idempotent: bereits gesetzte toleranz_absolut bleiben unangetastet.
//   node tools/content/fix-jahr-toleranzen.mjs           # anwenden
//   node tools/content/fix-jahr-toleranzen.mjs --dry-run # nur Bericht
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const PACKS_DIR = path.join(REPO, "content", "packs");
const TROCKEN = process.argv.includes("--dry-run");

const FENSTER_JE_STUFE = { leicht: 5, mittel: 4, schwer: 3, ultrahard: 2 };

function sammlePackDateien(wurzel) {
  const dateien = [];
  const stapel = [wurzel];
  while (stapel.length > 0) {
    const dir = stapel.pop();
    if (!existsSync(dir)) continue;
    for (const eintrag of readdirSync(dir)) {
      const voll = path.join(dir, eintrag);
      if (statSync(voll).isDirectory()) stapel.push(voll);
      else if (eintrag.endsWith(".json")) dateien.push(voll);
    }
  }
  return dateien.sort();
}

function istKalenderjahrFrage(frage) {
  if (frage.typ !== "schaetz" || !frage.schaetz) return false;
  const s = frage.schaetz;
  const einheit = String(s.einheit ?? "");
  if (einheit === "Jahr v. Chr.") return true;
  if (einheit !== "Jahr") return false;
  return typeof s.richtwert === "number" && s.richtwert >= 1000 && s.richtwert <= 2100;
}

let geaendert = 0;
let schonOk = 0;
const bericht = [];

for (const datei of sammlePackDateien(PACKS_DIR)) {
  const pack = JSON.parse(readFileSync(datei, "utf8"));
  if (!Array.isArray(pack.fragen)) continue;
  let dateiGeaendert = false;
  for (const frage of pack.fragen) {
    if (!istKalenderjahrFrage(frage)) continue;
    if (typeof frage.schaetz.toleranz_absolut === "number") {
      schonOk += 1;
      continue;
    }
    const fenster = FENSTER_JE_STUFE[frage.schwierigkeit] ?? 3;
    const vorher = ((frage.schaetz.toleranz_prozent ?? 0) / 100) * frage.schaetz.richtwert;
    frage.schaetz.toleranz_absolut = fenster;
    dateiGeaendert = true;
    geaendert += 1;
    bericht.push(
      `  ${frage.id} (${frage.schwierigkeit}): richtwert ${frage.schaetz.richtwert}, ` +
        `vorher ±${vorher.toFixed(1)} J (${frage.schaetz.toleranz_prozent} %) → jetzt ±${fenster} J`,
    );
  }
  if (dateiGeaendert && !TROCKEN) {
    writeFileSync(datei, `${JSON.stringify(pack, null, 2)}\n`);
  }
}

console.log(`Jahreszahl-Toleranzen${TROCKEN ? " (DRY-RUN)" : ""}:`);
console.log(bericht.join("\n"));
console.log(
  `\n${geaendert} Kalenderjahr-Fragen auf toleranz_absolut gesetzt, ` +
    `${schonOk} hatten es bereits.`,
);
