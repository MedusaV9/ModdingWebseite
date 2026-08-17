#!/usr/bin/env node
/* global process, console */
// Content-Statistik — Ist vs. v1-Soll (docs/CONTENT-PLAN.md §4.2) je
// Unter-Kategorie × Schwierigkeit. Nur Node-Builtins.
//   node tools/content/stats.mjs            # kompakte Lücken-Tabelle
//   node tools/content/stats.mjs --alle     # alle 90 Unter-Kategorien einzeln
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const CONTENT_DIR = path.join(REPO, "content");
const PACKS_DIR = path.join(CONTENT_DIR, "packs");

const STUFEN = ["leicht", "mittel", "schwer", "ultrahard"];
// Mengen-Soll pro Unter-Kategorie × Schwierigkeit (Plan §4.2).
const SOLL_KERN = { leicht: 20, mittel: 20, schwer: 15, ultrahard: 5 };
const SOLL_STANDARD = { leicht: 10, mittel: 10, schwer: 6, ultrahard: 2 };

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

const zeigeAlle = process.argv.includes("--alle");
const taxonomie = JSON.parse(readFileSync(path.join(CONTENT_DIR, "taxonomie.json"), "utf8"));

// Ist-Zählung über alle Packs.
const ist = new Map(); // slug → { leicht, mittel, schwer, ultrahard }
const typZaehler = new Map();
let gesamtIst = 0;
for (const datei of sammlePackDateien(PACKS_DIR)) {
  const pack = JSON.parse(readFileSync(datei, "utf8"));
  for (const f of pack.fragen ?? []) {
    if (!ist.has(f.unterkategorie))
      ist.set(f.unterkategorie, { leicht: 0, mittel: 0, schwer: 0, ultrahard: 0 });
    if (STUFEN.includes(f.schwierigkeit)) ist.get(f.unterkategorie)[f.schwierigkeit] += 1;
    typZaehler.set(f.typ, (typZaehler.get(f.typ) ?? 0) + 1);
    gesamtIst += 1;
  }
}

// Tabelle bauen.
const kopf = [
  "Unter-Kategorie",
  "Klasse",
  "L ist/soll",
  "M ist/soll",
  "S ist/soll",
  "U ist/soll",
  "Σ ist/soll",
  "Lücke",
];
const zeilen = [];
let gesamtSoll = 0;
let gesamtLuecke = 0;
let leereKern = 0;
let leereStandard = 0;
for (const u of taxonomie.unterkategorien) {
  const soll = u.kern ? SOLL_KERN : SOLL_STANDARD;
  const zaehler = ist.get(u.slug) ?? { leicht: 0, mittel: 0, schwer: 0, ultrahard: 0 };
  const summeIst = STUFEN.reduce((s, st) => s + zaehler[st], 0);
  const summeSoll = STUFEN.reduce((s, st) => s + soll[st], 0);
  const luecke = STUFEN.reduce((s, st) => s + Math.max(0, soll[st] - zaehler[st]), 0);
  gesamtSoll += summeSoll;
  gesamtLuecke += luecke;
  if (summeIst === 0 && !zeigeAlle) {
    if (u.kern) leereKern += 1;
    else leereStandard += 1;
    continue;
  }
  zeilen.push([
    `${u.oberkategorie}/${u.slug}`,
    u.kern ? "KERN" : "Std",
    ...STUFEN.map((st) => `${zaehler[st]}/${soll[st]}`),
    `${summeIst}/${summeSoll}`,
    String(luecke),
  ]);
}

function druckeTabelle(kopfzeile, datenzeilen) {
  const breiten = kopfzeile.map((k, i) =>
    Math.max([...k].length, ...datenzeilen.map((z) => [...z[i]].length)),
  );
  const linie = (z) => z.map((zelle, i) => zelle.padEnd(breiten[i])).join("  ");
  console.log(linie(kopfzeile));
  console.log(breiten.map((b) => "—".repeat(b)).join("  "));
  for (const z of datenzeilen) console.log(linie(z));
}

console.log("MONKEY MONEY · Content-Lücken-Report (Ist vs. v1-Soll, Plan §4.2)");
console.log("");
druckeTabelle(kopf, zeilen);
console.log("");
if (!zeigeAlle && (leereKern > 0 || leereStandard > 0)) {
  console.log(
    `… plus ${leereKern} KERN- und ${leereStandard} Standard-Unter-Kategorien noch komplett leer (mit --alle einzeln listen).`,
  );
}
console.log("");
console.log(
  `GESAMT: ${gesamtIst} Fragen vorhanden · v1-Soll ${gesamtSoll} · offene Lücke ${gesamtLuecke}`,
);
console.log("");
console.log("Typ-Mix (Ist):");
for (const [typ, n] of [...typZaehler.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(
    `  ${typ.padEnd(12)} ${String(n).padStart(4)}  (${((n / gesamtIst) * 100).toFixed(1)} %)`,
  );
}
