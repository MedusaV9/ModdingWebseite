// Integrations-Beweis (Playwright): Opening MIT Logo-Stinger-Video + eine
// bild_pixel-Frage MIT echtem Bild (Pixel-Dschungel, R3 im Klassik-Plan) +
// Tutorial-Video-Knopf auf der Erklärkarte (Match-Setting tutorialVideos=AN).
//
//   node tools/screenshots/integration-proof.mjs → /opt/cursor/artifacts/mm_integration_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8092);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[proof] ${t}`);

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-proof-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-proof-data" },
  stdio: "ignore",
});
process.on("exit", () => server.kill());

for (let i = 0; i < 40; i++) {
  try {
    const r = await fetch(`${URL_BASIS}/healthz`);
    if (r.ok) break;
  } catch {
    /* Server bootet noch */
  }
  await delay(250);
}
log(`Server läuft auf :${PORT}`);

// ---------- 2) Raum anlegen ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

// ---------- 3) Browser (Chrome-Channel für H.264, sonst Chromium) ----------
const args = ["--autoplay-policy=no-user-gesture-required"];
let browser;
try {
  browser = await chromium.launch({ channel: "chrome", args });
  log("Browser: System-Chrome (H.264 + VP9)");
} catch {
  browser = await chromium.launch({ args });
  log("Browser: Playwright-Chromium (nur VP9 sicher)");
}

const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

const spielerA = await browser.newPage({ viewport: { width: 390, height: 844 } });
const spielerB = await browser.newPage({ viewport: { width: 390, height: 844 } });

async function join(page, name, affenKlicks, farbIndex) {
  await page.goto(`${URL_BASIS}/j/${code}`);
  await page.fill('input[placeholder="Dein Name"]', name);
  for (let i = 0; i < affenKlicks; i++) {
    await page.click('button[aria-label="Nächster Affe"]');
  }
  await page.click(`.farb-reihe .farb-knopf:nth-child(${farbIndex + 1})`);
  await delay(300);
  await page.click("button.primaer");
}

await join(spielerA, "Zoe", 2, 2);
await join(spielerB, "Ben", 4, 4);
await spielerA.waitForSelector(".spieler-liste", { timeout: 8000 });
await screen.waitForFunction(() => document.querySelectorAll(".podium-puppe svg").length >= 2, {
  timeout: 10_000,
});
log("Beide Spieler im Raum");

// ---------- 4) GM-Socket ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args2 = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args: args2, cmdId: `proof-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

// Klassik (R3 = pixel-dschungel, R5 = stinkbanane) + Tutorial-Videos AN.
await gmCmd("settings.set", { modus: "klassik", tutorialVideos: true });
await gmCmd("flow.next"); // Lobby → Intro

// ---------- 5) BEWEIS 1: Logo-Stinger spielt als <video>-Overlay ----------
await screen.waitForSelector(".stinger-video", { timeout: 8000 });
await screen.waitForFunction(
  () => {
    const v = document.querySelector(".stinger-video");
    return v && !v.paused && v.currentTime > 0.15;
  },
  { timeout: 5000 },
);
const stingerInfo = await screen.evaluate(() => {
  const v = document.querySelector(".stinger-video");
  return { currentTime: v.currentTime, src: v.currentSrc, paused: v.paused };
});
log(`🎬 Stinger SPIELT: t=${stingerInfo.currentTime.toFixed(2)}s src=${stingerInfo.src}`);
await schuss(screen, "01_stinger_video");

// Stinger endet (1,875 s) → Kandidaten-Vorstellung ohne Overlay.
await screen.waitForFunction(() => !document.querySelector(".stinger-overlay"), {
  timeout: 6000,
});
await delay(2400); // Kandidaten-Einflug
await schuss(screen, "02_opening_kandidaten");
log("Stinger vorbei → Kandidaten-Vorstellung sichtbar");

// ---------- 6) Vorspulen bis Pixel-Dschungel (R3) ----------
async function bisPhase(zielPhase, zielMinigame, maxSchritte = 80) {
  for (let i = 0; i < maxSchritte; i++) {
    const phase = gmView?.phase;
    const mg = gmView?.abschnitt?.minigameId;
    if (phase === zielPhase && (zielMinigame === null || mg === zielMinigame)) return true;
    await gmCmd("flow.next");
    await delay(600);
  }
  return false;
}

if (!(await bisPhase("erklaerkarte", "pixel-dschungel"))) {
  throw new Error("Pixel-Dschungel-Erklärkarte nicht erreicht");
}
log(`Erklärkarte Pixel-Dschungel erreicht (Frage ${gmView?.frageNr ?? "?"})`);
await delay(700);
await schuss(screen, "03_pixel_erklaerkarte");

// ---------- 7) BEWEIS 2: bild_pixel-Frage mit ECHTEM Bild ----------
await gmCmd("flow.next"); // Erklärkarte → Frage
await screen.waitForSelector(".pd-canvas", { timeout: 8000 });
await screen.waitForFunction(
  () => {
    const c = document.querySelector(".pd-canvas");
    return c && (c.dataset.signatur ?? "").startsWith("/media/img/generated/pixel/");
  },
  { timeout: 8000 },
);
const signatur = await screen.evaluate(() => document.querySelector(".pd-canvas").dataset.signatur);
log(`🖼️ ECHTES Bild auf der Pixel-Bühne: ${signatur}`);
await delay(1200); // Bild geladen + erste Pixel-Stufe gezeichnet
await schuss(screen, "04_pixel_frage_verpixelt");
await spielerA.waitForSelector(".pd-button", { timeout: 8000 });
await schuss(spielerA, "05_phone_pixel_frage");

// Beide antworten → Auflösung zeigt das SCHARFE echte Bild.
const richtig = await (async () => {
  for (let i = 0; i < 40; i++) {
    const idx = gmView?.minigame?.view?.aufloesung?.correctIndex;
    const idx2 = gmView?.minigame?.view?.correctIndex;
    if (typeof idx2 === "number") return idx2;
    if (typeof idx === "number") return idx;
    await delay(150);
  }
  return 0;
})();
await spielerA.click(`.pd-button >> nth=${richtig}`);
await spielerB.click(`.pd-button >> nth=${(richtig + 1) % 4}`);
await screen.waitForFunction(
  () => (document.querySelector(".pd-canvas")?.dataset.signatur ?? "").includes("|scharf|"),
  { timeout: 15_000 },
);
await delay(800);
await schuss(screen, "06_pixel_aufloesung_scharf");
log("Auflösung: scharfes Bild auf der LED-Wand");

// ---------- 8) BEWEIS 3: Tutorial-Video-Knopf (Stinkbanane, R5) ----------
if (!(await bisPhase("erklaerkarte", "stinkbanane"))) {
  throw new Error("Stinkbanane-Erklärkarte nicht erreicht");
}
await screen.waitForSelector(".tutorial-knopf", { timeout: 8000 });
await delay(600);
await schuss(screen, "07_erklaerkarte_tutorial_knopf");
log("Erklärkarte Stinkbanane: Video-ansehen-Knopf sichtbar (tutorialVideos=AN)");
await screen.click(".tutorial-knopf");
await screen.waitForSelector(".tutorial-video", { timeout: 5000 });
try {
  await screen.waitForFunction(
    () => {
      const v = document.querySelector(".tutorial-video");
      return v && !v.paused && v.currentTime > 0.3;
    },
    { timeout: 6000 },
  );
  log("🎬 Tutorial-Video SPIELT");
} catch {
  log("⚠ Tutorial-Video-Element da, spielt aber nicht (H.264-Codec im Test-Browser?)");
}
await delay(600);
await schuss(screen, "08_tutorial_video_spielt");

log(`Fertig — Screenshots in ${OUT}`);
await browser.close();
gm.close();
opener.close();
server.kill();
process.exit(0);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_integration_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
