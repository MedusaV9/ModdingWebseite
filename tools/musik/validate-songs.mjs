// Song-Pack-Validator (Autoren-/CI-Gate): prüft content/musik/songs.json gegen
// das verbindliche Song-Pack-Format (docs/MUSIK-PACKS.md), die Existenz ALLER
// referenzierten Snippet-/Bett-Dateien und per ffprobe deren Soll-Dauern.
// Bett-Loops (import.mjs --bett): nurBett:true + medien.bett unter bett/,
// Dauer 60–90 s, stimmung chillig|upbeat — KEINE Snippet-Pflicht.
//
//   node tools/musik/validate-songs.mjs             → voller Check
//   node tools/musik/validate-songs.mjs --schnell   → ohne ffprobe-Dauern
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HIER = dirname(fileURLToPath(import.meta.url));
const MUSIK_DIR = resolve(HIER, "..", "..", "content", "musik");
const SONGS_JSON = join(MUSIK_DIR, "songs.json");
const SCHNELL = process.argv.includes("--schnell");

const SCHWIERIGKEITEN = ["leicht", "mittel", "schwer", "ultrahard"];
const REGIONEN = ["de", "global"];
const STIMMUNGEN = ["chillig", "upbeat"];
// Snippet → [Soll-Dauer min, max] in Sekunden (Toleranz: Encoder-Padding).
const DAUER_SOLL = {
  intro5s: [4.8, 5.3],
  "buzz.ms100": [0.05, 0.25],
  "buzz.ms200": [0.15, 0.35],
  "buzz.ms300": [0.25, 0.45],
  "buzz.ms500": [0.45, 0.65],
  "buzz.ms1000": [0.95, 1.15],
  mitte10s: [9.8, 10.3],
  rueckwaerts5s: [4.8, 5.3],
  video3s: [2.8, 3.3],
  // Bett-Loop: 60–90 s Soll (import.mjs --bett), ±Toleranz fürs Encoding
  // und für Songs knapp unter der Wunsch-Länge.
  bett: [58, 92],
};

const fehler = [];
const meckere = (wo, was) => fehler.push(`${wo}: ${was}`);

if (!existsSync(SONGS_JSON)) {
  console.error(`FEHLER: ${SONGS_JSON} fehlt`);
  process.exit(1);
}
const katalog = JSON.parse(readFileSync(SONGS_JSON, "utf8"));
if (!Array.isArray(katalog.songs)) {
  console.error("FEHLER: songs.json hat kein songs[]-Array");
  process.exit(1);
}

function ffprobeDauer(pfad) {
  const r = spawnSync(
    "ffprobe",
    ["-v", "error", "-show_entries", "format=duration", "-of", "json", pfad],
    { encoding: "utf8" },
  );
  if (r.status !== 0) return null;
  const d = Number(JSON.parse(r.stdout).format?.duration);
  return Number.isFinite(d) ? d : null;
}

/** Streams zählen (video3s muss stumm sein: 1 Video-, 0 Audio-Streams). */
function streams(pfad) {
  const r = spawnSync(
    "ffprobe",
    ["-v", "error", "-show_entries", "stream=codec_type", "-of", "json", pfad],
    { encoding: "utf8" },
  );
  if (r.status !== 0) return null;
  const liste = (JSON.parse(r.stdout).streams ?? []).map((s) => s.codec_type);
  return {
    video: liste.filter((t) => t === "video").length,
    audio: liste.filter((t) => t === "audio").length,
  };
}

const idsGesehen = new Set();
let dateienGeprueft = 0;

for (const song of katalog.songs) {
  const wo = song.id ?? "<ohne id>";

  // ---------- Schema ----------
  if (typeof song.id !== "string" || !/^s_[a-z0-9_]+$/.test(song.id))
    meckere(wo, `id muss ^s_[a-z0-9_]+$ matchen (ist: ${song.id})`);
  if (idsGesehen.has(song.id)) meckere(wo, "doppelte Song-Id");
  idsGesehen.add(song.id);
  if (typeof song.titel !== "string" || song.titel.length === 0) meckere(wo, "titel fehlt");
  if (typeof song.artist !== "string" || song.artist.length === 0) meckere(wo, "artist fehlt");
  if (!Number.isInteger(song.jahr) || song.jahr < 1880 || song.jahr > 2100)
    meckere(wo, `jahr muss Integer-Jahreszahl sein (ist: ${song.jahr})`);
  if (!REGIONEN.includes(song.region))
    meckere(wo, `region muss de|global sein (ist: ${song.region})`);
  if (!SCHWIERIGKEITEN.includes(song.schwierigkeit))
    meckere(
      wo,
      `schwierigkeit muss ${SCHWIERIGKEITEN.join("|")} sein (ist: ${song.schwierigkeit})`,
    );
  if (!Array.isArray(song.tags) || song.tags.some((t) => typeof t !== "string"))
    meckere(wo, "tags muss ein String-Array sein");
  const q = song.quelle ?? {};
  if (typeof q.plattform !== "string" || q.plattform.length === 0)
    meckere(wo, "quelle.plattform fehlt");
  if (typeof q.url !== "string" || q.url.length === 0)
    meckere(wo, "quelle.url fehlt (Credits-Pflicht!)");
  if (typeof q.abgerufen !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(q.abgerufen))
    meckere(wo, "quelle.abgerufen muss YYYY-MM-DD sein");

  // ---------- Medien: Bett-Loop ODER Pflicht-Snippets, Existenz, Dauern ----------
  const medien = song.medien ?? {};
  // Bett-only-Eintrag (import.mjs --bett): nurBett + medien.bett, KEINE
  // Snippets — der Loop läuft nur als Show-Bett (Rotation), nie im Rate-Pool.
  const bettOnly = medien.bett !== undefined && medien.intro5s === undefined;
  if (bettOnly) {
    if (song.nurBett !== true) meckere(wo, "Bett-Eintrag (medien.bett) braucht nurBett:true");
    if (!STIMMUNGEN.includes(song.stimmung))
      meckere(wo, `Bett-Eintrag braucht stimmung ${STIMMUNGEN.join("|")} (ist: ${song.stimmung})`);
  } else if (song.stimmung !== undefined && !STIMMUNGEN.includes(song.stimmung)) {
    meckere(wo, `stimmung muss ${STIMMUNGEN.join("|")} sein (ist: ${song.stimmung})`);
  }
  const eintraege = bettOnly
    ? [["bett", medien.bett]]
    : [
        ["intro5s", medien.intro5s],
        ...Object.entries(medien.buzz ?? {}).map(([k, v]) => [`buzz.${k}`, v]),
        ["mitte10s", medien.mitte10s],
        ["rueckwaerts5s", medien.rueckwaerts5s],
        ...(medien.video3s !== undefined ? [["video3s", medien.video3s]] : []),
        ...(medien.bett !== undefined ? [["bett", medien.bett]] : []),
      ];
  if (!bettOnly) {
    for (const pflicht of ["ms100", "ms200", "ms300", "ms500", "ms1000"])
      if (typeof medien.buzz?.[pflicht] !== "string") meckere(wo, `medien.buzz.${pflicht} fehlt`);
  }
  for (const [name, relPfad] of eintraege) {
    if (typeof relPfad !== "string" || relPfad.length === 0) {
      meckere(wo, `medien.${name} fehlt`);
      continue;
    }
    const sollPrefix = name === "bett" ? `bett/${song.id}.ogg` : `media/${song.id}/`;
    if (name === "bett" ? relPfad !== sollPrefix : !relPfad.startsWith(sollPrefix))
      meckere(wo, `medien.${name} muss ${sollPrefix} sein/dort liegen (ist: ${relPfad})`);
    const voll = join(MUSIK_DIR, relPfad);
    if (!existsSync(voll)) {
      meckere(wo, `Datei fehlt: ${relPfad}`);
      continue;
    }
    dateienGeprueft += 1;
    if (SCHNELL) continue;
    const dauer = ffprobeDauer(voll);
    const [min, max] = DAUER_SOLL[name] ?? [0.01, Infinity];
    if (dauer === null) meckere(wo, `${relPfad}: nicht dekodierbar (ffprobe)`);
    else if (dauer < min || dauer > max)
      meckere(wo, `${relPfad}: Dauer ${dauer.toFixed(2)}s außerhalb Soll [${min}, ${max}]`);
    if (name === "video3s" && dauer !== null) {
      const s = streams(voll);
      if (s === null || s.video < 1) meckere(wo, `${relPfad}: kein Video-Stream`);
      else if (s.audio > 0) meckere(wo, `${relPfad}: video3s muss stumm sein (hat Audio-Stream)`);
    }
  }
}

// ---------- Waisen-Check: media/-Ordner + bett/-Dateien ohne Eintrag ----------
const mediaWurzel = join(MUSIK_DIR, "media");
if (existsSync(mediaWurzel)) {
  for (const ordner of readdirSync(mediaWurzel)) {
    if (!idsGesehen.has(ordner)) meckere(ordner, "media-Ordner ohne songs.json-Eintrag (Waise)");
  }
}
const bettWurzel = join(MUSIK_DIR, "bett");
if (existsSync(bettWurzel)) {
  for (const datei of readdirSync(bettWurzel)) {
    const id = datei.replace(/\.ogg$/, "");
    if (!datei.endsWith(".ogg") || !idsGesehen.has(id))
      meckere(datei, "bett-Datei ohne songs.json-Eintrag (Waise)");
  }
}

if (fehler.length > 0) {
  console.error(`songs.json UNGÜLTIG — ${fehler.length} Fehler:`);
  for (const f of fehler) console.error(`  · ${f}`);
  process.exit(1);
}
const betten = katalog.songs.filter((s) => s.medien?.bett !== undefined).length;
console.log(
  `songs.json OK: ${katalog.songs.length} Songs (davon ${betten} Bett-Loops), ` +
    `${dateienGeprueft} Medien-Dateien geprüft` +
    (SCHNELL ? " (schnell, ohne ffprobe)" : " (inkl. ffprobe-Dauern)"),
);
