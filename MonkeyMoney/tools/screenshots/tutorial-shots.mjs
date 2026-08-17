// Tutorial-Material-Walk (Playwright): läuft den KOMPLETTEN Marathon-Plan mit
// 2 Spielern per GM-Kommandos durch und schießt je Format 1) die Erklärkarte
// mit laufender Demo (mm_card_<id>.png — Choreo-Review) und 2) die erste
// Frage-Phase (mm_play_<id>.png — Gameplay-Material für die Remotion-
// Tutorials). Formate ohne Client-Renderer (Song-Welle in Arbeit) werden
// automatisch übersprungen.
//
//   OUT_DIR=/tmp/mm-tutorial-shots node tools/screenshots/tutorial-shots.mjs
//
// Voraussetzungen: npm run build, Playwright-Chromium installiert.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.SHOTS_PORT ?? 8094);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/tmp/mm-tutorial-shots";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[tutorial-shots] ${t}`);

// ---------- 1) Server starten ----------
rmSync("/tmp/mm-shots-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-shots-data" },
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

// ---------- 2) Raum + Screen + 2 Spieler ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code}`);

const browser = await chromium.launch();
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

async function join(page, name, affenKlicks, farbIndex) {
  await page.goto(`${URL_BASIS}/j/${code}`);
  await page.fill('input[placeholder="Dein Name"]', name);
  for (let i = 0; i < affenKlicks; i++) {
    await page.click('button[aria-label="Nächster Affe"]');
  }
  await page.click(`.farb-reihe .farb-knopf:nth-child(${farbIndex + 1})`);
  await delay(250);
  await page.click("button.primaer");
}
const spielerA = await browser.newPage({ viewport: { width: 390, height: 844 } });
const spielerB = await browser.newPage({ viewport: { width: 390, height: 844 } });
await join(spielerA, "Zoe", 2, 2);
await join(spielerB, "Ben", 4, 4);
await spielerA.waitForSelector(".spieler-liste", { timeout: 8000 });
log("Beide Spieler im Raum");

// ---------- 3) GM: Marathon ohne Rad/Wahl starten ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `shots-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

await gmCmd("settings.set", {
  modus: "marathon",
  rad: "aus",
  kategorienWahl: "aus",
  autoGm: false,
});
await delay(400);
await gmCmd("flow.next"); // Lobby → Intro
await delay(600);
await gmCmd("flow.next"); // Intro → Erklärkarte R1

// ---------- 4) Marathon-Walk: je Format Karte + erste Frage schießen ----------
const kartenGeschossen = new Set();
const spielGeschossen = new Set();
let letztePhase = "";
let iter = 0;

async function schuss(name) {
  const pfad = `${OUT}/${name}.png`;
  await screen.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

while (iter++ < 500) {
  const phase = gmView?.phase;
  if (phase === "siegerehrung") break;

  if (phase === "erklaerkarte") {
    const id = gmView?.erklaerkarte?.minigameId ?? "";
    if (id && !kartenGeschossen.has(id)) {
      kartenGeschossen.add(id);
      try {
        await screen.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 5000 });
        await delay(2800); // mitten in Beat 2 (Blase + Requisit sichtbar)
      } catch {
        log(`⚠ ${id}: keine Demo-Bühne (Fallback-Karte?)`);
        await delay(600);
      }
      await schuss(`mm_card_${id}`);
    }
    await gmCmd("flow.next");
  } else if (phase === "frage") {
    const id = gmView?.minigame?.id ?? "";
    if (id && !spielGeschossen.has(id)) {
      spielGeschossen.add(id);
      await delay(1400); // Einflug-Animationen + erste Ticks
      await schuss(`mm_play_${id}`);
    }
    await gmCmd("flow.next"); // force-finish → Auflösung
  } else {
    await gmCmd("flow.next");
  }

  if (phase !== letztePhase) {
    letztePhase = phase;
    log(`Phase: ${phase} (${gmView?.erklaerkarte?.minigameId ?? gmView?.minigame?.id ?? ""})`);
  }
  await delay(320);
}

log(`Karten: ${[...kartenGeschossen].join(", ")}`);
log(`Gameplay: ${[...spielGeschossen].join(", ")}`);

await browser.close();
gm.close();
opener.close();
server.kill();
process.exit(0);
