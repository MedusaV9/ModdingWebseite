// MUSIK-IMPORT-PIPELINE (docs/MUSIK-PACKS.md): EIN Befehl macht aus einem Song
// alle Rate-Snippets fürs Song-Pack-Format (content/musik/songs.json).
//
//   node tools/musik/import.mjs --url <URL> --titel "…" --artist "…" \
//     --jahr 1956 --schwierigkeit leicht --region global [--hook 30] [--video]
//
// Quellen: --url (YouTube/archive.org/Dailymotion/direkte Datei-URL via yt-dlp),
// --suche "Artist - Titel" (ytsearch1:) oder --datei <lokaler Pfad>.
// Ablauf: Download → loudnorm-Master (−16 LUFS) → ffmpeg schneidet ALLE
// Snippets (intro5s ab 0; buzz-Serie 100–1000 ms ab Hook, Standard Sekunde 30;
// mitte10s ab 40 %; rueckwaerts5s = 5 s ab Hook rückwärts) → Volldownload wird
// GELÖSCHT (nur Snippets bleiben — bewusst schlank) → songs.json-Eintrag +
// Credits-Zeile (content/musik/CREDITS-SONGS.md) automatisch.
//
// BETT-MODUS (--bett): statt Rate-Snippets bleibt EIN 60–90-s-LOOP-SCHNITT
// (ab --hook, loudnorm auf −18 LUFS — leiser als die SFX! — mit Fade-in/-out
// fürs nahtlose Loopen) unter content/musik/bett/<id>.ogg. Der Eintrag trägt
// nurBett:true + medien.bett + stimmung (chillig|upbeat) — die Show-Regie
// rotiert diese Loops als Party-Hintergrund (Lobby=chillig, Runde=upbeat).
//
// WICHTIG: privates Freundes-Projekt — Credits werden trotzdem IMMER geführt
// (das Tool erzwingt sie). Cover bitte mit --cover kennzeichnen.
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HIER = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HIER, "..", "..");
// MM_MUSIK_DIR: Ziel-Override für den Tool-Test (import-bett.test.ts schneidet
// in ein Temp-Verzeichnis statt ins echte content/musik).
const MUSIK_DIR = process.env.MM_MUSIK_DIR ?? join(REPO, "content", "musik");
const SONGS_JSON = join(MUSIK_DIR, "songs.json");
const CREDITS_MD = join(MUSIK_DIR, "CREDITS-SONGS.md");
const BETT_DIR = join(MUSIK_DIR, "bett");

const SCHWIERIGKEITEN = ["leicht", "mittel", "schwer", "ultrahard"];
const REGIONEN = ["de", "global"];
const STIMMUNGEN = ["chillig", "upbeat"];
const BUZZ_MS = [100, 200, 300, 500, 1000];
// Bett-Loop: Ziel-Fenster + Fades (nahtloses Loopen ohne Klick/Kante).
const BETT_LAENGE_MIN = 60;
const BETT_LAENGE_MAX = 90;
const BETT_LAENGE_DEFAULT = 75;
const BETT_FADE_IN_S = 1.2;
const BETT_FADE_OUT_S = 2.0;
const BETT_LUFS = -18; // leiser als die SFX (−16) — Hintergrund, kein Vordergrund

const HILFE = `MONKEY MONEY — Song-Import (Snippets fürs Musik-Minigame + Bett-Loops)

Pflicht:
  --titel "…" --artist "…" --jahr <int> --schwierigkeit leicht|mittel|schwer|ultrahard --region de|global
  + genau EINE Quelle: --url <URL> | --suche "Artist - Titel" | --datei <pfad>

Optional:
  --id s_mein_slug     eigene Song-Id (Default: s_<slug-aus-titel>)
  --hook <sekunden>    Start der Buzz-Serie + rueckwaerts5s (Default: 30)
  --tags "a,b,c"       freie Tags
  --video              zusätzlich stummen 3-s-Video-Clip schneiden (480p mp4)
  --cover              Aufnahme ist ein COVER (wird in Tags+Credits markiert)
  --hinweis "…"        eigener Credits-Hinweis (z. B. "TV-Fassung 1958")
  --quelle-url <URL>   Credits-Quelle überschreiben (z. B. bei --datei)
  --force              vorhandenen Eintrag gleicher Id überschreiben

BETT-MODUS (Party-Hintergrund-Musik statt Rate-Snippets):
  --bett               EIN 60–90-s-Loop-Schnitt (−18 LUFS, Fades) nach
                       content/musik/bett/<id>.ogg — Eintrag nurBett:true,
                       KEINE Snippets. --schwierigkeit/--region optional
                       (Default mittel/global), Id-Default: s_bett_<slug>.
  --stimmung chillig|upbeat   Phasen-Zuordnung der Rotation (Default chillig:
                       Lobby-Vibe; upbeat läuft im Runden-Bett)
  --laenge <sekunden>  Loop-Länge 60–90 (Default ${BETT_LAENGE_DEFAULT}); --hook = Loop-Start

Beispiel Rate-Song (zuhause, 1 Zeile):
  node tools/musik/import.mjs --suche "Elvis Presley - Hound Dog" --titel "Hound Dog" --artist "Elvis Presley" --jahr 1956 --schwierigkeit leicht --region global

Beispiel Bett-Loop (DEIN Lieblings-Song als Party-Hintergrund):
  node tools/musik/import.mjs --bett --suche "Yello - Oh Yeah" --titel "Oh Yeah" --artist "Yello" --jahr 1985 --stimmung upbeat --hook 12`;

// ---------- CLI-Parsing ----------

function parseArgs(argv) {
  const flags = new Set(["--video", "--cover", "--force", "--bett", "--hilfe", "--help"]);
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (!k.startsWith("--")) fehler(`Unerwartetes Argument: ${k} (siehe --hilfe)`);
    if (flags.has(k)) {
      args[k.slice(2)] = true;
      continue;
    }
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) fehler(`${k} braucht einen Wert (siehe --hilfe)`);
    args[k.slice(2)] = v;
    i++;
  }
  return args;
}

function fehler(text) {
  console.error(`\nFEHLER: ${text}`);
  process.exit(1);
}

function slugify(text) {
  return text
    .toLowerCase()
    .replace(/[äàáâ]/g, "a")
    .replace(/[öòóô]/g, "o")
    .replace(/[üùúû]/g, "u")
    .replace(/ß/g, "ss")
    .replace(/[éèêë]/g, "e")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

// ---------- Subprozesse ----------

/** Install-Einzeiler je Werkzeug — der ENOENT-Fall ist bei Erstnutzern der
 * Normalfall (Eval-9-Blocker: roher spawnSync-Fehler statt Anleitung). */
const INSTALL_HILFE = {
  "yt-dlp": {
    was: "yt-dlp (Downloader für YouTube/archive.org/Dailymotion)",
    mac: "brew install yt-dlp",
    win: "winget install yt-dlp.yt-dlp",
    linux:
      "sudo apt install pipx && pipx install yt-dlp   (oder: python3 -m pip install -U yt-dlp)",
  },
  ffmpeg: {
    was: "ffmpeg (schneidet + normalisiert die Snippets)",
    mac: "brew install ffmpeg",
    win: "winget install Gyan.FFmpeg",
    linux: "sudo apt install ffmpeg",
  },
  ffprobe: {
    was: "ffprobe (Teil von ffmpeg — misst die Snippet-Dauern)",
    mac: "brew install ffmpeg",
    win: "winget install Gyan.FFmpeg",
    linux: "sudo apt install ffmpeg",
  },
  curl: {
    was: "curl (lädt direkte Datei-URLs, z. B. archive.org)",
    mac: "ist auf macOS vorinstalliert — Terminal neu öffnen?",
    win: "ist auf Windows 10/11 vorinstalliert — Terminal neu öffnen?",
    linux: "sudo apt install curl",
  },
};

/** Fehlendes Werkzeug (ENOENT) ⇒ freundliche Installations-Anleitung statt
 * rohem Fehler. Details + alle OS-Einzeiler: docs/MUSIK-PACKS.md. */
function fehltWerkzeug(cmd) {
  const hilfe = INSTALL_HILFE[cmd] ?? { was: cmd };
  console.error(`
========================================================================
"${cmd}" ist auf diesem Rechner nicht installiert (oder nicht im PATH).
Der Song-Import braucht ${hilfe.was}.

So installierst du es (1 Zeile, je nach System):
  macOS:    ${hilfe.mac ?? "—"}
  Windows:  ${hilfe.win ?? "—"}
  Linux:    ${hilfe.linux ?? "—"}

Danach ein NEUES Terminal öffnen und den Import-Befehl einfach nochmal
ausführen. Alle Voraussetzungen im Überblick: docs/MUSIK-PACKS.md
(Abschnitt „Voraussetzungen").
========================================================================`);
  process.exit(1);
}

function lauf(cmd, cmdArgs, { leise = false } = {}) {
  if (!leise)
    console.log(
      `\n$ ${cmd} ${cmdArgs.map((a) => (/\s/.test(a) ? JSON.stringify(a) : a)).join(" ")}`,
    );
  const r = spawnSync(cmd, cmdArgs, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (r.error?.code === "ENOENT") fehltWerkzeug(cmd);
  if (r.error) fehler(`${cmd} ließ sich nicht starten: ${r.error.message}`);
  return r;
}

/** YouTube-Bot-Block/Geo-Block erkennen — passiert auf Servern/VMs ständig. */
function pruefeBotBlock(ausgabe) {
  const muster =
    /Sign in to confirm|confirm you.?re not a bot|not a robot|HTTP Error 429|Video unavailable.*country/i;
  if (muster.test(ausgabe)) {
    console.error(`
========================================================================
YouTube blockt diese Server-IP („Sign in to confirm…").
Auf diesem Server geblockt — führe den Befehl auf deinem PC aus,
dort läuft er ohne Anmeldung durch. Falls YouTube auch dort meckert:
  yt-dlp-Cookies aus deinem Browser mitgeben, z. B.
    --cookies-from-browser chrome   (oder firefox/edge/safari)
  → einfach als zusätzliche Umgebung: YTDLP_EXTRA="--cookies-from-browser chrome"
archive.org- und direkte Dailymotion-URLs funktionieren auch von Servern.
========================================================================`);
    process.exit(2);
  }
}

function ffprobeDauer(datei, { leise = false } = {}) {
  const r = lauf(
    "ffprobe",
    ["-v", "error", "-show_entries", "format=duration", "-of", "json", datei],
    { leise },
  );
  if (r.status !== 0) fehler(`ffprobe scheiterte an ${datei}:\n${r.stderr}`);
  const dauer = Number(JSON.parse(r.stdout).format?.duration);
  if (!Number.isFinite(dauer) || dauer <= 0) fehler(`Keine Dauer ermittelbar für ${datei}`);
  return dauer;
}

function ffmpeg(argsListe, was) {
  const r = lauf("ffmpeg", ["-hide_banner", "-y", ...argsListe]);
  if (r.status !== 0) fehler(`ffmpeg scheiterte (${was}):\n${r.stderr.slice(-2000)}`);
}

// ---------- Download ----------

const MEDIA_ENDUNGEN = /\.(mp3|flac|ogg|oga|opus|wav|m4a|aac|mp4|webm|mkv|mov)(\?.*)?$/i;

function ladeHerunter(args, tmp) {
  // Direkte Datei-URLs (z. B. archive.org/download/…/x.mp3) lädt curl —
  // yt-dlps HTTP-Stack wird von archive.org auf Server-IPs gern gedrosselt.
  if (args.url && MEDIA_ENDUNGEN.test(args.url)) {
    const endung = args.url.match(MEDIA_ENDUNGEN)[1].toLowerCase();
    const zielDatei = join(tmp, `download.${endung}`);
    // archive.org drosselt gern mit 503 → geduldige Retries (Retry-After wird beachtet).
    const r = lauf("curl", [
      "-sSL",
      "--fail",
      "--retry",
      "8",
      "--retry-delay",
      "20",
      "--retry-all-errors",
      "-o",
      zielDatei,
      args.url,
    ]);
    if (r.status !== 0) fehler(`curl-Download scheiterte (Exit ${r.status}):\n${r.stderr}`);
    return zielDatei;
  }
  const ziel = join(tmp, "download.%(ext)s");
  const extra = (process.env.YTDLP_EXTRA ?? "").split(/\s+/).filter(Boolean);
  const format = args.video
    ? ["-f", "bestvideo[height<=720]+bestaudio/best", "--merge-output-format", "mp4"]
    : ["-f", "bestaudio/best"];
  const quelle = args.url ?? `ytsearch1:${args.suche}`;
  const r = lauf("yt-dlp", [
    "--js-runtimes",
    "node",
    "--no-playlist",
    ...format,
    "-o",
    ziel,
    ...extra,
    quelle,
  ]);
  const ausgabe = `${r.stdout}\n${r.stderr}`;
  process.stdout.write(r.stdout);
  if (r.status !== 0) {
    process.stderr.write(r.stderr);
    pruefeBotBlock(ausgabe);
    fehler(`yt-dlp scheiterte (Exit ${r.status}) — Ausgabe oben.`);
  }
  const datei = readdirSync(tmp).find((f) => f.startsWith("download."));
  if (!datei) fehler("yt-dlp lief durch, aber keine download.*-Datei gefunden");
  return join(tmp, datei);
}

// ---------- Hauptprogramm ----------

const args = parseArgs(process.argv.slice(2));
if (args.hilfe || args.help || process.argv.length <= 2) {
  console.log(HILFE);
  process.exit(0);
}

const quellen = ["url", "suche", "datei"].filter((k) => args[k]);
if (quellen.length !== 1) fehler("Genau EINE Quelle angeben: --url ODER --suche ODER --datei");
const bettModus = args.bett === true;
// Bett-Loops sind reine Hintergrund-Betten: Schwierigkeit/Region sind fürs
// Rate-Quiz gedacht — im Bett-Modus optional (Defaults), damit der
// 1-Zeilen-Import zuhause kurz bleibt.
if (bettModus) {
  args.schwierigkeit ??= "mittel";
  args.region ??= "global";
  if (args.video) fehler("--video ergibt im Bett-Modus keinen Sinn (reiner Audio-Loop)");
}
for (const pflicht of ["titel", "artist", "jahr", "schwierigkeit", "region"]) {
  if (!args[pflicht]) fehler(`--${pflicht} ist Pflicht (siehe --hilfe)`);
}
if (!SCHWIERIGKEITEN.includes(args.schwierigkeit))
  fehler(`--schwierigkeit muss ${SCHWIERIGKEITEN.join("|")} sein`);
if (!REGIONEN.includes(args.region)) fehler(`--region muss ${REGIONEN.join("|")} sein`);
const jahr = Number(args.jahr);
if (!Number.isInteger(jahr) || jahr < 1880 || jahr > 2100) fehler("--jahr muss ein Jahr sein");
const hookWunsch = args.hook !== undefined ? Number(args.hook) : 30;
if (!Number.isFinite(hookWunsch) || hookWunsch < 0) fehler("--hook muss ≥ 0 Sekunden sein");
const stimmung = args.stimmung ?? "chillig";
if (!STIMMUNGEN.includes(stimmung)) fehler(`--stimmung muss ${STIMMUNGEN.join("|")} sein`);
if (args.stimmung !== undefined && !bettModus) fehler("--stimmung gibt es nur mit --bett");
const bettLaenge = args.laenge !== undefined ? Number(args.laenge) : BETT_LAENGE_DEFAULT;
if (args.laenge !== undefined && !bettModus) fehler("--laenge gibt es nur mit --bett");
if (!Number.isFinite(bettLaenge) || bettLaenge < BETT_LAENGE_MIN || bettLaenge > BETT_LAENGE_MAX)
  fehler(`--laenge muss ${BETT_LAENGE_MIN}–${BETT_LAENGE_MAX} Sekunden sein`);

const id = args.id ?? `s_${bettModus ? "bett_" : ""}${slugify(args.titel)}`;
if (!/^s_[a-z0-9_]+$/.test(id)) fehler(`Ungültige Id ${id} (Muster: s_<slug>)`);

const tags = (args.tags ?? "")
  .split(",")
  .map((t) => t.trim())
  .filter(Boolean);
if (args.cover && !tags.includes("cover")) tags.push("cover");

// Bestehendes songs.json lesen (oder frisch anlegen).
const katalog = existsSync(SONGS_JSON)
  ? JSON.parse(readFileSync(SONGS_JSON, "utf8"))
  : { songs: [] };
if (!Array.isArray(katalog.songs)) fehler(`${SONGS_JSON} hat kein songs[]-Array`);
if (katalog.songs.some((s) => s.id === id) && !args.force)
  fehler(`Song ${id} existiert schon — mit --force überschreiben oder --id vergeben`);

console.log(`\n=== MUSIK-IMPORT ${id} — „${args.titel}" (${args.artist}, ${jahr}) ===`);

// 1) Beschaffung (Volldownload landet in einem Temp-Ordner, NIE im Repo).
const tmp = mkdtempSync(join(tmpdir(), "mm-musik-"));
let voll;
if (args.datei) {
  if (!existsSync(args.datei)) fehler(`--datei ${args.datei} existiert nicht`);
  voll = join(tmp, `download${args.datei.slice(args.datei.lastIndexOf("."))}`);
  copyFileSync(args.datei, voll);
  console.log(`Lokale Quelle kopiert: ${args.datei}`);
} else {
  voll = ladeHerunter(args, tmp);
}

const dauer = ffprobeDauer(voll);
console.log(`Volldownload: ${basename(voll)} — ${dauer.toFixed(1)} s`);

// 2) Schnittfenster berechnen (Hook clampen, falls der Song kürzer ist).
let hook = hookWunsch;
let laengeEff = bettLaenge;
if (bettModus) {
  // Bett-Loop: 60–90 s MÜSSEN in den Song passen (sonst wäre es kein Bett).
  if (dauer < BETT_LAENGE_MIN + 2) {
    fehler(
      `Song ist nur ${dauer.toFixed(1)} s lang — ein Bett-Loop braucht ` +
        `${BETT_LAENGE_MIN}–${BETT_LAENGE_MAX} s. Längere Fassung wählen.`,
    );
  }
  laengeEff = Math.min(bettLaenge, Math.floor((dauer - 1) * 10) / 10);
  if (laengeEff < bettLaenge)
    console.log(`HINWEIS: Song kürzer als --laenge ${bettLaenge}s → Loop=${laengeEff}s`);
  if (hook + laengeEff + 1 > dauer) {
    hook = Math.max(0, Math.round((dauer - laengeEff - 1) * 10) / 10);
    console.log(
      `HINWEIS: --hook ${hookWunsch}s + ${laengeEff}s passen nicht in ${dauer.toFixed(1)}s → Hook=${hook}s`,
    );
  }
} else if (hook + 5 > dauer) {
  hook = Math.max(0, Math.round((dauer - 6) * 10) / 10);
  console.log(`HINWEIS: --hook ${hookWunsch}s passt nicht in ${dauer.toFixed(1)}s → Hook=${hook}s`);
}
let mitteStart = Math.round(dauer * 0.4 * 10) / 10;
if (mitteStart + 10 > dauer) mitteStart = Math.max(0, Math.round((dauer - 10) * 10) / 10);

// 3) Loudness-Master: EINMAL normalisieren (Two-Pass, linear — Repo-Audio-
//    Standard: konstanter Gain statt Dynamik-Pumpen), dann aus dem Master
//    schneiden (loudnorm auf 100 ms wäre unzuverlässig). Rate-Snippets zielen
//    auf −16 LUFS (Vordergrund), Bett-Loops auf −18 LUFS (Hintergrund —
//    bewusst LEISER als die SFX, die Show spricht über dem Bett).
const zielLufs = bettModus ? BETT_LUFS : -16;
const master = join(tmp, "master.wav");
const messung = lauf("ffmpeg", [
  "-hide_banner",
  "-i",
  voll,
  "-vn",
  "-af",
  `loudnorm=I=${zielLufs}:TP=-1.5:LRA=11:print_format=json`,
  "-f",
  "null",
  "-",
]);
const messJson = messung.stderr.match(/\{[^}]*"input_i"[\s\S]*?\}/)?.[0];
if (messung.status !== 0 || !messJson)
  fehler(`loudnorm-Messpass scheiterte:\n${messung.stderr.slice(-1500)}`);
const m = JSON.parse(messJson);
console.log(
  `Loudness gemessen: ${m.input_i} LUFS (TP ${m.input_tp}, LRA ${m.input_lra}) → ${zielLufs}`,
);
ffmpeg(
  [
    "-i",
    voll,
    "-vn",
    "-af",
    `loudnorm=I=${zielLufs}:TP=-1.5:LRA=11:measured_I=${m.input_i}:measured_TP=${m.input_tp}` +
      `:measured_LRA=${m.input_lra}:measured_thresh=${m.input_thresh}` +
      `:offset=${m.target_offset}:linear=true`,
    "-ar",
    "44100",
    "-ac",
    "2",
    master,
  ],
  `loudnorm-Master (Pass 2, linear, ${zielLufs} LUFS)`,
);

// 4) Schneiden: Bett-Loop (EIN Schnitt mit Loop-Fades) ODER Rate-Snippets.
const mediaDir = join(MUSIK_DIR, "media", id);
if (bettModus) {
  // Loop-Schnitt: Fade-in/-out lang genug, dass der Übergang Ende→Anfang
  // beim loop=true-Abspielen weich klingt (kein Klick, keine harte Kante).
  mkdirSync(BETT_DIR, { recursive: true });
  const fadeOutStart = Math.max(0, laengeEff - BETT_FADE_OUT_S);
  ffmpeg(
    [
      "-ss",
      String(hook),
      "-t",
      String(laengeEff),
      "-i",
      master,
      "-af",
      `afade=t=in:d=${BETT_FADE_IN_S},afade=t=out:st=${fadeOutStart}:d=${BETT_FADE_OUT_S}`,
      "-c:a",
      "libvorbis",
      "-q:a",
      "5",
      join(BETT_DIR, `${id}.ogg`),
    ],
    "bett-loop",
  );
} else {
  rmSync(mediaDir, { recursive: true, force: true });
  mkdirSync(mediaDir, { recursive: true });

  const schnitt = (name, startS, laengeS, extraFilter = "") => {
    const fadeOutStart = Math.max(0, laengeS - 0.01);
    const af = `${extraFilter}afade=t=in:d=0.01,afade=t=out:st=${fadeOutStart}:d=0.01`;
    ffmpeg(
      [
        "-ss",
        String(startS),
        "-t",
        String(laengeS),
        "-i",
        master,
        "-af",
        af,
        "-c:a",
        "libvorbis",
        "-q:a",
        "5",
        join(mediaDir, name),
      ],
      name,
    );
  };

  schnitt("intro5s.ogg", 0, 5);
  for (const ms of BUZZ_MS) schnitt(`buzz_ms${ms}.ogg`, hook, ms / 1000);
  schnitt("mitte10s.ogg", mitteStart, 10);
  schnitt("rueckwaerts5s.ogg", hook, 5, "areverse,");

  if (args.video) {
    ffmpeg(
      [
        "-ss",
        String(hook),
        "-i",
        voll,
        "-t",
        "3",
        "-vf",
        "scale=-2:480",
        "-an",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "23",
        "-movflags",
        "+faststart",
        join(mediaDir, "video3s.mp4"),
      ],
      "video3s",
    );
  }
}

// 5) Volldownload LÖSCHEN — bewusst schlank, nur die Snippets bleiben.
rmSync(tmp, { recursive: true, force: true });
console.log("Volldownload gelöscht (nur Snippets bleiben).");

// 6) songs.json-Eintrag schreiben.
const quelleUrl = args["quelle-url"] ?? args.url ?? (args.datei ? `datei:${args.datei}` : "suche");
const plattform = /^https?:/.test(quelleUrl)
  ? new URL(quelleUrl).hostname.replace(/^www\./, "")
  : args.datei
    ? "lokal"
    : "youtube (ytsearch1)";
const heute = new Date().toISOString().slice(0, 10);

const eintrag = bettModus
  ? {
      // Bett-Loop: NUR Show-Bett (nie Rate-Song) — die Rotation ordnet ihn
      // per stimmung der Phase zu (chillig=Lobby, upbeat=Runde).
      id,
      titel: args.titel,
      artist: args.artist,
      jahr,
      region: args.region,
      schwierigkeit: args.schwierigkeit,
      nurBett: true,
      stimmung,
      tags,
      medien: { bett: `bett/${id}.ogg` },
      quelle: { plattform, url: quelleUrl, abgerufen: heute },
    }
  : {
      id,
      titel: args.titel,
      artist: args.artist,
      jahr,
      region: args.region,
      schwierigkeit: args.schwierigkeit,
      tags,
      medien: {
        intro5s: `media/${id}/intro5s.ogg`,
        buzz: Object.fromEntries(BUZZ_MS.map((ms) => [`ms${ms}`, `media/${id}/buzz_ms${ms}.ogg`])),
        mitte10s: `media/${id}/mitte10s.ogg`,
        rueckwaerts5s: `media/${id}/rueckwaerts5s.ogg`,
        ...(args.video ? { video3s: `media/${id}/video3s.mp4` } : {}),
      },
      quelle: { plattform, url: quelleUrl, abgerufen: heute },
    };
katalog.songs = [...katalog.songs.filter((s) => s.id !== id), eintrag];
mkdirSync(MUSIK_DIR, { recursive: true });
writeFileSync(SONGS_JSON, `${JSON.stringify(katalog, null, 2)}\n`);

// 7) Credits-Zeile (Pflicht — auch im privaten Projekt).
const kopf = `# Song-Credits (automatisch von tools/musik/import.mjs geführt)

Privates Freundes-Projekt: kurze Rate-Snippets (0,1–10 s), keine Weitergabe.
Jede Quelle wird hier IMMER dokumentiert. Cover sind als solche markiert.

| Id | Titel | Artist | Jahr | Quelle | URL | Abgerufen | Hinweis |
|---|---|---|---|---|---|---|---|
`;
const hinweis =
  args.hinweis ??
  (bettModus
    ? `Bett-Loop ${laengeEff.toFixed(0)} s (${stimmung})${args.cover ? " — COVER" : ""}`
    : args.cover
      ? "COVER (nicht das Original!)"
      : "Original-Aufnahme");
const zeile = `| ${id} | ${args.titel} | ${args.artist} | ${jahr} | ${plattform} | ${quelleUrl} | ${heute} | ${hinweis} |`;
const bestand = existsSync(CREDITS_MD) ? readFileSync(CREDITS_MD, "utf8") : kopf;
const zeilen = bestand.split("\n").filter((z) => !z.startsWith(`| ${id} `));
while (zeilen.at(-1) === "") zeilen.pop();
writeFileSync(CREDITS_MD, `${zeilen.join("\n")}\n${zeile}\n`);

// 8) Beweis-Ausgabe: jede erzeugte Datei mit ffprobe-Dauer + Größe.
console.log(`\n=== FERTIG: ${id} ===`);
if (bettModus) {
  const pfad = join(BETT_DIR, `${id}.ogg`);
  const kb = (statSync(pfad).size / 1024).toFixed(0);
  const dauerS = ffprobeDauer(pfad, { leise: true }).toFixed(2);
  // Loudness-Beleg des fertigen Loops (Soll: −18 LUFS ±1 — leiser als SFX).
  const check = lauf(
    "ffmpeg",
    ["-hide_banner", "-i", pfad, "-af", "loudnorm=print_format=json", "-f", "null", "-"],
    { leise: true },
  );
  const gemessen = check.stderr.match(/\{[^}]*"input_i"[\s\S]*?\}/)?.[0];
  const lufs = gemessen ? JSON.parse(gemessen).input_i : "?";
  console.log(`  bett/${id}.ogg`.padEnd(46) + ` ${dauerS.padStart(6)} s  ${kb.padStart(5)} kB`);
  console.log(`  Loop-Loudness: ${lufs} LUFS (Ziel ${BETT_LUFS}) · Stimmung: ${stimmung}`);
} else {
  for (const f of readdirSync(mediaDir).sort()) {
    const pfad = join(mediaDir, f);
    const kb = (statSync(pfad).size / 1024).toFixed(0);
    const dauerS = ffprobeDauer(pfad, { leise: true }).toFixed(2);
    console.log(`  ${f.padEnd(22)} ${dauerS.padStart(6)} s  ${kb.padStart(5)} kB`);
  }
}
console.log(`songs.json: ${katalog.songs.length} Songs · Credits: ${CREDITS_MD}`);
