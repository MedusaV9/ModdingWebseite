// BEWEIS-SKRIPT (Eval 3, P1 „Musik-Bett maskiert Snippets"): startet den
// gebauten Server, öffnet den ECHTEN Screen (Playwright, Audio-Konstruktor
// instrumentiert), skippt per GM-Socket durch den Marathon bis zum Blitz-DJ
// (song-snippet) und sampelt die Volumen-Timeline ALLER Audio-Elemente:
//   · VOR der Musik-Runde (Erklärkarte): Bett spielt hörbar (Sampler-Beleg)
//   · WÄHREND der Blitz-DJ-Runde: JEDES Bett-Element (/audio/musik/…) ist
//     pausiert/0 — über die GANZE Runde — während das Snippet
//     (/media-musik/…) in voller Lautstärke läuft
// Nebenbei belegt: der Rate-Song ist NIE ein MacLeod-Bett (nurBett-Filter).
//
//   npm run build && node tools/screenshots/blitz-dj-bett-proof.mjs
//
// Artefakte: blitz_dj_volumen_timeline.log, blitz_dj_screen_*.png,
// blitz_dj_bett_stumm_proof.webm (Screen-Video der Runde).
import { spawn } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8093);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const VIDEO_TMP = "/tmp/mm-blitz-dj-video";
mkdirSync(OUT, { recursive: true });
rmSync(VIDEO_TMP, { recursive: true, force: true });

const log = (t) => console.log(`[blitz-dj-proof] ${t}`);
const fehler = [];
const pruefe = (ok, text) => {
  console.log(`${ok ? "✓" : "✗"} ${text}`);
  if (!ok) fehler.push(text);
};

// ---------- 1) Server ----------
rmSync("/tmp/mm-blitz-dj-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-blitz-dj-data" },
  stdio: "ignore",
});
process.on("exit", () => server.kill());
for (let i = 0; i < 40; i++) {
  try {
    if ((await fetch(`${URL_BASIS}/healthz`)).ok) break;
  } catch {
    /* bootet noch */
  }
  await delay(250);
}
log(`Server läuft auf :${PORT}`);

// ---------- 2) Raum + 2 Spieler-Bots (Sockets) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const { code, gmPin } = raum;
log(`Raum ${code}`);

async function spielerBot(name, avatar) {
  const s = io(URL_BASIS, { transports: ["websocket"] });
  s.on("time.probe", (msg) => s.emit("time.probe", msg));
  const antwort = await s
    .timeout(5000)
    .emitWithAck("hello", { roomCode: code, role: "player", name, avatar });
  if (!antwort.ok) throw new Error(`${name} hello: ${antwort.error}`);
  return s;
}
const botA = await spielerBot("Zoe", "gelb");
const botB = await spielerBot("Ben", "rot");

// ---------- 3) Screen-Page mit Audio-Instrumentierung + Video ----------
const browser = await chromium.launch({
  args: ["--autoplay-policy=no-user-gesture-required"],
});
const context = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  recordVideo: { dir: VIDEO_TMP, size: { width: 1280, height: 800 } },
});
const screen = await context.newPage();
// JEDES new Audio() (Bett, Media-Kanal, SFX) landet in window.__mmAudios —
// der Sampler liest paused/volume/src im Seiten-Kontext (keine DOM-Anker nötig).
await screen.addInitScript(() => {
  window.__mmAudios = [];
  const Orig = window.Audio;
  const Patched = function (...args) {
    const el = new Orig(...args);
    window.__mmAudios.push(el);
    return el;
  };
  Patched.prototype = Orig.prototype;
  window.Audio = Patched;
  // Sampler: alle 100 ms ein Timeline-Punkt { t, phase, audios[] }.
  window.__samples = [];
  window.__samplerAn = false;
  setInterval(() => {
    if (!window.__samplerAn) return;
    window.__samples.push({
      t: Date.now(),
      phase: document.querySelector(".studio")?.dataset.phase ?? "?",
      audios: window.__mmAudios.map((a) => ({
        src: a.src.replace(location.origin, ""),
        paused: a.paused,
        volume: Math.round(a.volume * 1000) / 1000,
        loop: a.loop,
      })),
    });
  }, 100);
});
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });
await screen.click("body"); // erste Geste ⇒ Audio-Unlock (pointerdown)
log("Screen verbunden + Audio entsperrt");

// ---------- 4) GM: Marathon, dann bis zum Blitz-DJ skippen ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `proof-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

await gmCmd("settings.set", {
  modus: "marathon",
  rad: "aus",
  kategorienWahl: "aus",
  autoGm: false,
  jokerAn: false,
});
await gmCmd("flow.next"); // Lobby → Intro
await delay(600);
await gmCmd("flow.next"); // Intro → erste Erklärkarte

// Skip-Schleife: Erklärkarte eines fremden Formats ⇒ game.skip (ganze Runde),
// Zwischenstand ⇒ flow.next — bis die Erklärkarte des Blitz-DJ steht.
const deadline = Date.now() + 180_000;
let uebersprungen = 0;
for (;;) {
  if (Date.now() > deadline) throw new Error("Timeout: Blitz-DJ nicht erreicht");
  const phase = gmView?.phase ?? "?";
  const mg = gmView?.abschnitt?.minigameId ?? "?";
  if (phase === "erklaerkarte" && mg === "song-snippet") break;
  if (phase === "erklaerkarte" || phase === "aufloesung") {
    await gmCmd("game.skip", { keepPoints: false });
    uebersprungen++;
  } else if (phase === "zwischenstand" || phase === "rad" || phase === "highlights") {
    await gmCmd("flow.next");
  } else if (phase === "frage") {
    await gmCmd("game.skip", { keepPoints: false });
    uebersprungen++;
  }
  await delay(300);
}
log(`Blitz-DJ-Erklärkarte erreicht (${uebersprungen} Skips)`);

// ---------- 5) Referenz-Sample: Bett spielt HÖRBAR vor der Musik-Runde ----------
await delay(2500); // Erklär-Bett (FluffingADuck) einschwingen lassen
const vorher = await screen.evaluate(() =>
  window.__mmAudios
    .filter((a) => a.src.includes("/audio/musik/"))
    .map((a) => ({ src: a.src.split("/").at(-1), paused: a.paused, volume: a.volume })),
);
log(`Bett auf der Erklärkarte: ${JSON.stringify(vorher)}`);
pruefe(
  vorher.some((a) => !a.paused && a.volume > 0.2),
  `Sampler-Beleg: VOR der Musik-Runde spielt das Bett hörbar (${vorher[0]?.src} vol=${vorher[0]?.volume.toFixed(2)})`,
);

// ---------- 6) Blitz-DJ starten + 14 s Volumen-Timeline sampeln ----------
await screen.evaluate(() => {
  window.__samplerAn = true;
});
await gmCmd("flow.next"); // Erklärkarte → Blitz-DJ (Intro 2 s → Lauschen-Stufen)
await screen.waitForFunction(() => document.querySelector(".studio")?.dataset.phase === "frage", {
  timeout: 10_000,
});
log("Blitz-DJ läuft — sample 14 s (Intro + Stufen 1-3, niemand buzzt)");
await delay(6000);
await screen.screenshot({ path: join(OUT, "blitz_dj_screen_lauschen.png") });
await delay(8000);
await screen.evaluate(() => {
  window.__samplerAn = false;
});

// GM-Spickzettel: welcher Song lief? (Beleg für den nurBett-Filter.)
const songInfo = {
  titel: gmView?.minigame?.view?.titel ?? "?",
  artist: gmView?.minigame?.view?.artist ?? "?",
};
log(`Rate-Song der Runde: „${songInfo.titel}" — ${songInfo.artist}`);
pruefe(
  songInfo.artist !== "Kevin MacLeod" && songInfo.artist !== "?",
  `nurBett-Filter: Rate-Song „${songInfo.titel}" (${songInfo.artist}) ist KEIN MacLeod-Bett`,
);

const samples = await screen.evaluate(() => window.__samples);
const t0 = samples[0]?.t ?? 0;

// ---------- 7) Auswertung: Bett=0 über die GANZE Runde, Snippet läuft ----------
const inFrage = samples.filter((s) => s.phase === "frage");
const bettVerstoesse = [];
let mediaAktivSamples = 0;
for (const s of inFrage) {
  for (const a of s.audios) {
    if (a.src.includes("/audio/musik/") && !a.paused && a.volume > 0.01) {
      bettVerstoesse.push({ t: s.t - t0, ...a });
    }
    if (a.src.includes("/media-musik/") && !a.paused) mediaAktivSamples++;
  }
}
pruefe(inFrage.length >= 100, `Timeline dicht: ${inFrage.length} Samples in der frage-Phase`);
pruefe(
  bettVerstoesse.length === 0,
  `Bett=0 über die GANZE Runde: 0 Verstöße in ${inFrage.length} Samples (Bett pausiert/stumm)`,
);
if (bettVerstoesse.length > 0) log(`Verstöße: ${JSON.stringify(bettVerstoesse.slice(0, 5))}`);
pruefe(
  mediaAktivSamples > 0,
  `Snippet lief hörbar über den Media-Kanal (${mediaAktivSamples} aktive Media-Samples)`,
);

// ---------- 8) Timeline-Log als Artefakt ----------
const zeilen = [
  "BLITZ-DJ VOLUMEN-TIMELINE (Playwright-Audio-Sampler, alle 100 ms)",
  `Raum ${code} · Modus marathon · Rate-Song: „${songInfo.titel}" — ${songInfo.artist}`,
  "Bett = /audio/musik/*-Elemente · Media = /media-musik/*-Snippets · SFX ausgelassen",
  "",
  "   t(ms)  phase   Bett                                Media",
  ...samples.map((s) => {
    const bett = s.audios
      .filter((a) => a.src.includes("/audio/musik/"))
      .map((a) => `${a.src.split("/").at(-1)} ${a.paused ? "PAUSE" : `vol=${a.volume}`}`)
      .join(", ");
    const media = s.audios
      .filter((a) => a.src.includes("/media-musik/"))
      .map(
        (a) => `${a.src.split("/").slice(-2).join("/")} ${a.paused ? "PAUSE" : `vol=${a.volume}`}`,
      )
      .join(", ");
    return `${String(s.t - t0).padStart(8)}  ${s.phase.padEnd(7)} ${(bett || "—").padEnd(35)} ${media || "—"}`;
  }),
  "",
  fehler.length === 0
    ? "ERGEBNIS: ✓ Bett für die GANZE Runde stumm."
    : `ERGEBNIS: ✗ ${fehler.join(" | ")}`,
];
writeFileSync(join(OUT, "blitz_dj_volumen_timeline.log"), zeilen.join("\n"));
log(`Timeline: ${join(OUT, "blitz_dj_volumen_timeline.log")} (${samples.length} Samples)`);

// ---------- 9) Aufräumen + Video sichern ----------
await context.close();
await browser.close();
const videos = readdirSync(VIDEO_TMP).filter((f) => f.endsWith(".webm"));
if (videos.length > 0) {
  copyFileSync(join(VIDEO_TMP, videos[0]), join(OUT, "blitz_dj_bett_stumm_proof.webm"));
  log(`Video: ${join(OUT, "blitz_dj_bett_stumm_proof.webm")}`);
}
gm.close();
botA.close();
botB.close();
opener.close();
server.kill();

if (fehler.length > 0) {
  console.error(`\n✗ BEWEIS FEHLGESCHLAGEN: ${fehler.length} Prüfungen rot`);
  process.exit(1);
}
console.log("\n✓ BEWEIS ERBRACHT: Bett=0 über die ganze Blitz-DJ-Runde, Snippet frei hörbar.");
process.exit(0);
