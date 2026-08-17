#!/usr/bin/env node
/* global process, console */
// Anti-Rate-Regel (Eval-5 P3): Bei Schätzfragen, deren richtwert (fast) genau
// in der MITTE von eingabe_min…eingabe_max liegt, ist „Slider einfach stehen
// lassen" eine Gewinnstrategie. Fix: EINE Grenze deterministisch (id-Hash)
// asymmetrisch verschieben, bis der Richtwert bei 25–44 % bzw. 56–75 % der
// Spanne liegt — mal links, mal rechts, damit kein neues Meta („nie Mitte")
// entsteht. Grenzwerte bleiben auf runden Schritten, min < richtwert < max
// bleibt gewahrt (validate.mjs-Regel F05), log-Skalen bleiben > 0.
//   node tools/content/fix-richtwert-mitte.mjs           # anwenden
//   node tools/content/fix-richtwert-mitte.mjs --dry-run # nur Bericht
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const PACKS_DIR = path.join(REPO, "content", "packs");
const TROCKEN = process.argv.includes("--dry-run");

// Mitte = Richtwert-Position innerhalb ±5 % um 0,5; Ziel deutlich daneben.
const MITTE_TOLERANZ = 0.05;
const ZIELE = [0.31, 0.36, 0.41, 0.59, 0.64, 0.69];

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

/** Deterministischer Mini-Hash (FNV-1a) — Migration bleibt reproduzierbar. */
function hash(text) {
  let h = 2166136261;
  for (let i = 0; i < text.length; i += 1) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/** Runder Schritt passend zur Spanne (Jahre: 5er, sonst Zehnerpotenz/10). */
function schrittFuer(spanne, einheit) {
  if (/jahr/i.test(einheit) && spanne <= 400) return 5;
  const basis = 10 ** Math.max(0, Math.floor(Math.log10(spanne)) - 1);
  return basis;
}

function position(s) {
  return (s.richtwert - s.eingabe_min) / (s.eingabe_max - s.eingabe_min);
}

/** Verschiebt min ODER max auf die Ziel-Position; liefert true bei Erfolg. */
function verschiebe(s, ziel, schritt) {
  const { richtwert: rw, eingabe_min: mn, eingabe_max: mx } = s;
  // Erst min bewegen (max fest): mn' = (rw − t·mx) / (1 − t)
  let neuMin = (rw - ziel * mx) / (1 - ziel);
  neuMin = Math.round(neuMin / schritt) * schritt;
  const minErlaubt = s.skala === "log" ? schritt : mn >= 0 ? 0 : -Infinity;
  if (neuMin >= minErlaubt && neuMin < rw && neuMin !== mn) {
    const pos = (rw - neuMin) / (mx - neuMin);
    if (Math.abs(pos - 0.5) > MITTE_TOLERANZ && pos > 0.2 && pos < 0.8) {
      s.eingabe_min = neuMin;
      return true;
    }
  }
  // Sonst max bewegen (min fest): mx' = mn + (rw − mn) / t
  let neuMax = mn + (rw - mn) / ziel;
  neuMax = Math.round(neuMax / schritt) * schritt;
  if (neuMax > rw && neuMax !== mx) {
    const pos = (rw - mn) / (neuMax - mn);
    if (Math.abs(pos - 0.5) > MITTE_TOLERANZ && pos > 0.2 && pos < 0.8) {
      s.eingabe_max = neuMax;
      return true;
    }
  }
  return false;
}

let geaendert = 0;
let uebrig = 0;
const bericht = [];

for (const datei of sammlePackDateien(PACKS_DIR)) {
  const pack = JSON.parse(readFileSync(datei, "utf8"));
  if (!Array.isArray(pack.fragen)) continue;
  let dateiGeaendert = false;
  for (const frage of pack.fragen) {
    const s = frage.schaetz;
    if (frage.typ !== "schaetz" || !s) continue;
    if (Math.abs(position(s) - 0.5) > MITTE_TOLERANZ) continue;
    const schritt = schrittFuer(s.eingabe_max - s.eingabe_min, String(s.einheit ?? ""));
    const startZiel = hash(frage.id) % ZIELE.length;
    const vorher = `${s.eingabe_min}…${s.eingabe_max}`;
    let ok = false;
    for (let i = 0; i < ZIELE.length && !ok; i += 1) {
      ok = verschiebe(s, ZIELE[(startZiel + i) % ZIELE.length], schritt);
    }
    if (ok) {
      dateiGeaendert = true;
      geaendert += 1;
      bericht.push(
        `  ${frage.id}: richtwert ${s.richtwert}, Range ${vorher} → ` +
          `${s.eingabe_min}…${s.eingabe_max} (Pos ${(position(s) * 100).toFixed(0)} %)`,
      );
    } else {
      uebrig += 1;
      bericht.push(`  !! ${frage.id}: keine gültige Verschiebung gefunden (${vorher})`);
    }
  }
  if (dateiGeaendert && !TROCKEN) {
    writeFileSync(datei, `${JSON.stringify(pack, null, 2)}\n`);
  }
}

console.log(`Richtwert-in-Range-Mitte${TROCKEN ? " (DRY-RUN)" : ""}:`);
console.log(bericht.join("\n"));
console.log(`\n${geaendert} Ranges asymmetrisch verschoben, ${uebrig} übrig.`);
if (uebrig > 0) process.exitCode = 1;
