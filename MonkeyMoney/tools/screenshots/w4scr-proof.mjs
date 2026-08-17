// W4-Screen-Proof A (Playwright): Studio-Flow-Beweise für die Perfektions-
// Runde Welle 4 — Bereich 1 (Auflösungs-Karte aufgedeckt), Bereich 5
// (Erklär-Demos: ✓/✗-Beat der Basics + Geldflug-Beat der Affenbank) und
// Bereich 6 (Admin-Seite). Jede Station wird auf ZWEI Screens (1280x800 +
// 1920x1080) geschossen; die Minigame-Inszenierungen (Bereich 2/3/4) macht
// tools/screenshots/w4scr-minigames.ts (Harness-injizierte Plugins).
//
//   PREFIX=vorher node tools/screenshots/w4scr-proof.mjs
//   PREFIX=nachher OUT_DIR=/tmp/mm-w4 node tools/screenshots/w4scr-proof.mjs
//
// Voraussetzungen: npm run build, Playwright-Chromium installiert.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.W4_PORT ?? 8094);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const PREFIX = process.env.PREFIX ?? "vorher";
const ADMIN_PIN = "4242";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[w4scr-a] ${t}`);

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-w4scr-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: {
    ...process.env,
    PORT: String(PORT),
    DATA_DIR: "/tmp/mm-w4scr-data",
    ADMIN_PIN,
  },
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

// ---------- 2) Raum + 2 Screens (1280/1920) + 3 Socket-Spieler ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

const browser = await chromium.launch();

async function screenPage(width, height) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
  await page.goto(`${URL_BASIS}/screen`);
  await page.waitForSelector(".mono", { timeout: 10_000 });
  return page;
}

const s1280 = await screenPage(1280, 800);
const s1920 = await screenPage(1920, 1080);

async function schuss(name) {
  await s1280.screenshot({ path: `${OUT}/mm_w4scr_${name}_${PREFIX}_1280.png` });
  await s1920.screenshot({ path: `${OUT}/mm_w4scr_${name}_${PREFIX}_1920.png` });
  log(`📸 ${name} (${PREFIX}, 1280+1920)`);
}

const SPIELER = [
  { name: "Mia", avatar: "kiki-krawall.rot" },
  { name: "Bo", avatar: "pumper-paule.tuerkis" },
  { name: "Zoe", avatar: "glitzer-gina.lila" },
];
const spieler = [];
for (const sp of SPIELER) {
  const sock = io(URL_BASIS, { transports: ["websocket"] });
  let view = null;
  sock.on("view.snapshot", (p) => (view = p.view));
  const hello = await sock
    .timeout(5000)
    .emitWithAck("hello", { roomCode: code, role: "player", name: sp.name, avatar: sp.avatar });
  if (!hello.ok) throw new Error(`hello ${sp.name}: ${hello.error}`);
  spieler.push({ ...sp, sock, playerId: hello.playerId, view: () => view });
  log(`${sp.name} ist drin`);
}

// ---------- 3) GM: Marathon ohne Rad/Wahl, Flow von Hand ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `w4a-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

await gmCmd("settings.set", {
  modus: "marathon",
  rad: "aus",
  kategorienWahl: "aus",
  autoGm: false,
});
await gmCmd("flow.next"); // Lobby → Intro
await delay(600);
await gmCmd("flow.next"); // Intro → Erklärkarte R1 (bananen-basics)

// ---------- 4) Bereich 5a: Basics-Demo am ✓/✗-Beat (Beat 4 ab 6,4 s) ----------
await s1280.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 8000 });
await delay(7200);
await schuss("a5_demo_basics");

// ---------- 5) Bereich 1: Frage 1 mit gemischten Antworten → Auflösung ----------
await gmCmd("flow.next"); // Erklärkarte → Frage 1
for (let i = 0; i < 40 && gmView?.phase !== "frage"; i++) await delay(150);
if (gmView?.phase !== "frage") throw new Error(`Frage-Phase nicht erreicht: ${gmView?.phase}`);
const minigameId = gmView.minigame?.id;
const korrekt = gmView.minigame?.view?.correctIndex ?? 0;
log(`Frage läuft (${minigameId}), korrekt = ${korrekt}`);
// Mia richtig (schnell), Bo + Zoe falsch — Chips zeigen ✓/✗ + Delta-Mix.
const antworten = [
  { sp: spieler[0], choice: korrekt, wartezeit: 300 },
  { sp: spieler[1], choice: (korrekt + 1) % 4, wartezeit: 700 },
  { sp: spieler[2], choice: (korrekt + 2) % 4, wartezeit: 950 },
];
for (const a of antworten) {
  await delay(a.wartezeit);
  await a.sp.sock.timeout(5000).emitWithAck("player.action", {
    minigameId,
    actionId: "answer",
    payload: { choice: a.choice },
    idemKey: `${a.sp.playerId}-f1-answer`,
  });
}
// Basics beendet die Frage von selbst, sobald ALLE geantwortet haben (tick:
// alleBeantwortet) — ein flow.next hier würde in Frage 2 durchrutschen und
// die Auflösung einer unbeantworteten Frage zeigen (alle ✗ ±0).
for (let i = 0; i < 80 && gmView?.phase !== "aufloesung"; i++) await delay(150);
if (gmView?.phase !== "aufloesung") await gmCmd("flow.next");
await s1280.waitForFunction(
  () => {
    const studio = document.querySelector(".studio");
    const wand = document.querySelector(".led-wand");
    return (
      studio?.dataset.phase === "aufloesung" &&
      wand !== null &&
      !wand.classList.contains("spannung")
    );
  },
  { timeout: 12_000 },
);
await delay(900); // Chips-Einflug + Erklärung stehen
await schuss("a1_aufloesung");

// ---------- 6) Bereich 5b: zur Affenbank-Karte walken (Geldflug-Beat 6,6 s) ----------
let iter = 0;
for (;;) {
  if (iter++ > 160) throw new Error("Affenbank-Karte nicht erreicht");
  const phase = gmView?.phase;
  if (phase === "erklaerkarte" && gmView?.erklaerkarte?.minigameId === "affenbank") break;
  if (phase === "siegerehrung" || phase === "ende") throw new Error("Match vorbei ohne Affenbank");
  await gmCmd("flow.next");
  await delay(320);
}
await s1280.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 8000 });
await delay(7400);
await schuss("a5_demo_affenbank");

// ---------- 7) Bereich 6: Admin-Seite (PIN-Gate → Reports) ----------
async function adminSchuss(width, height, suffix) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.goto(`${URL_BASIS}/admin`);
  await page.fill("#pin", ADMIN_PIN);
  await page.click("#rein");
  await page.waitForSelector("#inhalt", { state: "visible", timeout: 8000 });
  await delay(500);
  await page.screenshot({ path: `${OUT}/mm_w4scr_a6_admin_${PREFIX}_${suffix}.png` });
  log(`📸 a6_admin (${PREFIX}, ${suffix})`);
  await page.close();
}
await adminSchuss(1280, 800, "1280");
await adminSchuss(1920, 1080, "1920");

log("Proof A fertig ✓");
await browser.close();
for (const sp of spieler) sp.sock.close();
gm.close();
opener.close();
server.kill();
process.exit(0);
