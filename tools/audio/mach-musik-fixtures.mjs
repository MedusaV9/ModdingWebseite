#!/usr/bin/env node
// Musik-Minispiel-TEST-FIXTURES bauen (Blitz-DJ + Rückwärts-Banane):
// 5 FIKTIVE Songs aus den Kenney-Music-Jingles (CC0 1.0, assets/audio/kenney/)
// zusammenschneiden — pro Song EINE Jingle-Familie (eigenes Timbre), Familie
// konkateniert = „Song", daraus die Medien-Dateien EXAKT im verbindlichen
// songs.json-Format der Musik-Pipeline: intro5s, buzz ms100…ms1000 (alle ab
// Song-Anfang — die Eskalations-Stufen verlängern denselben Hook), mitte10s,
// rueckwaerts5s (= intro5s rückwärts). Ziel: assets/audio/fixtures/musik/<id>/.
// Die Katalog-Einträge dazu liegen in shared/songs.ts (FIXTURE_SONGS).
// Aufruf: node tools/audio/mach-musik-fixtures.mjs
import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const KENNEY = "assets/audio/kenney/music-jingles/Audio";
const ZIEL = "assets/audio/fixtures/musik";

const SONGS = [
  { id: "fx-sax-banane", familie: "Sax jingles" },
  { id: "fx-pizzi-kokos", familie: "Pizzicato jingles" },
  { id: "fx-steel-liane", familie: "Steel jingles" },
  { id: "fx-nes-affe", familie: "8-Bit jingles" },
  { id: "fx-hit-dschungel", familie: "Hit jingles" },
];

function ffmpeg(args) {
  execFileSync("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", ...args], {
    stdio: "inherit",
  });
}

for (const song of SONGS) {
  const dir = join(ZIEL, song.id);
  mkdirSync(dir, { recursive: true });

  // 1) Familie 2× hintereinander zum „Song"-Master (≥ 15 s Material).
  const quellen = readdirSync(join(KENNEY, song.familie))
    .filter((f) => f.endsWith(".ogg"))
    .sort();
  const liste = join(dir, "_concat.txt");
  const zeilen = [...quellen, ...quellen]
    .map((f) => `file '${process.cwd()}/${KENNEY}/${song.familie}/${f}'`)
    .join("\n");
  writeFileSync(liste, zeilen + "\n");
  const master = join(dir, "_master.ogg");
  ffmpeg([
    "-f",
    "concat",
    "-safe",
    "0",
    "-i",
    liste,
    "-ar",
    "44100",
    "-ac",
    "1",
    "-q:a",
    "2",
    master,
  ]);

  // 2) Schnitte im verbindlichen Medien-Format.
  const schnitt = (out, ss, t, extra = []) =>
    ffmpeg([
      "-i",
      master,
      "-ss",
      String(ss),
      "-t",
      String(t),
      ...extra,
      "-q:a",
      "2",
      join(dir, out),
    ]);
  schnitt("intro5s.ogg", 0, 5);
  for (const ms of [100, 200, 300, 500, 1000]) schnitt(`buzz_ms${ms}.ogg`, 0, ms / 1000);
  schnitt("mitte10s.ogg", 5, 10);
  // Rückwärts-Banane: das Intro rückwärts — die Auflösung spielt es vorwärts.
  ffmpeg([
    "-i",
    join(dir, "intro5s.ogg"),
    "-af",
    "areverse",
    "-q:a",
    "2",
    join(dir, "rueckwaerts5s.ogg"),
  ]);

  rmSync(liste);
  rmSync(master);
  console.log(`✓ ${song.id} (${song.familie})`);
}
console.log("Fertig — Katalog-Einträge: shared/songs.ts (FIXTURE_SONGS).");
