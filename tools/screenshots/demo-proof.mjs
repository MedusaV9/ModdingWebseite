// Erklär-Demo-Proof (Playwright): startet den gebauten Server, joint 2 Spieler,
// stellt Marathon ohne Rad/Kategorien-Wahl ein und läuft die ersten 5 Runden
// ab. Auf jeder Erklärkarte wird die laufende Demo-Bühne mitten im Loop
// geschossen (mm_demo_<format>.png); auf einer Karte messen wir grob das
// 60-fps-Budget (rAF-Frames zählen, lange Frames melden) und von einer Karte
// nehmen wir per Playwright-Video einen kompletten Demo-Loop auf.
//
//   node tools/screenshots/demo-proof.mjs           → /opt/cursor/artifacts/
//   OUT_DIR=/tmp/mm-demo node tools/…/demo-proof.mjs → Iterations-Läufe
//
// Voraussetzungen: npm run build (client/dist + server/dist), Playwright-
// Chromium installiert.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.DEMO_PORT ?? 8092);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[demo-proof] ${t}`);

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-demo-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-demo-data" },
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

// ---------- 2) Raum anlegen + Screen & 2 Spieler verbinden ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

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

// ---------- 3) GM-Socket: Marathon ohne Rad/Wahl, Flow treiben ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `demo-${cmdNr++}` });
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
await gmCmd("flow.next"); // Intro → Erklärkarte R1

// ---------- 4) Walk: 5 Erklärkarten mit laufender Demo schießen ----------
// Marathon-Reihenfolge R1-R5: fünf visuell VERSCHIEDENE Requisiten-Typen
// (Frage-Karte, Uhr/Schild, Slider, Leiter, Kette+BANK!).
const ziele = ["bananen-basics", "kokosnuss-uhr", "bananen-tresor", "affenleiter", "affenbank"];
const geschossen = new Set();
let fpsBericht = null;

async function schuss(page, name) {
  const pfad = `${OUT}/mm_demo_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

/** Grober 60-fps-Check: rAF-Frames über 2 s zählen, lange Frames (>25 ms) melden. */
async function fpsCheck(page) {
  return await page.evaluate(
    () =>
      new Promise((resolve) => {
        let frames = 0;
        let langeFrames = 0;
        let start = null;
        let letzte = null;
        const tick = (ts) => {
          if (start === null) start = ts;
          if (letzte !== null) {
            frames += 1;
            if (ts - letzte > 25) langeFrames += 1;
          }
          letzte = ts;
          if (ts - start >= 2000) {
            resolve({
              frames,
              langeFrames,
              dauerMs: Math.round(ts - start),
              fps: Math.round((frames * 1000) / (ts - start)),
            });
          } else {
            requestAnimationFrame(tick);
          }
        };
        requestAnimationFrame(tick);
      }),
  );
}

/** Video-Kontext: zweiter Screen im selben Raum zeichnet einen Demo-Loop auf. */
async function nimmDemoVideoAuf(formatId) {
  const kontext = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    recordVideo: { dir: "/tmp/mm-demo-video", size: { width: 1280, height: 800 } },
  });
  const seite = await kontext.newPage();
  await seite.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
  await seite.goto(`${URL_BASIS}/screen`);
  try {
    await seite.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 6000 });
    // Bis zum Phasen-Ende laufen lassen (Karte advanced nach 12 s von selbst).
    await seite.waitForFunction(
      () => document.querySelector(".studio")?.dataset.phase !== "erklaerkarte",
      { timeout: 15_000 },
    );
  } catch {
    log("⚠ Video-Seite: Demo/Phasenwechsel nicht gesehen — Video wird trotzdem gespeichert");
  }
  const video = seite.video();
  await seite.close();
  await kontext.close();
  const roh = video ? await video.path() : null;
  if (roh) log(`🎬 Demo-Video (${formatId}): ${roh}`);
  return roh;
}

let videoRohPfad = null;
let iter = 0;
while (geschossen.size < ziele.length && iter++ < 240) {
  const phase = gmView?.phase;
  if (phase === "erklaerkarte") {
    const id = gmView?.erklaerkarte?.minigameId ?? "";
    if (ziele.includes(id) && !geschossen.has(id)) {
      await screen.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 8000 });
      if (id === "affenbank") {
        // Letzte Ziel-Karte: kompletter Loop als Video (Karte advanced selbst).
        const videoLauf = nimmDemoVideoAuf(id);
        await delay(2800); // mitten in Beat 2 (Sprech-Blase + Requisit sichtbar)
        await schuss(screen, id);
        geschossen.add(id);
        videoRohPfad = await videoLauf;
      } else {
        await delay(2800);
        await schuss(screen, id);
        geschossen.add(id);
        if (id === "bananen-tresor") {
          fpsBericht = await fpsCheck(screen);
          log(`⏱ fps-Check (bananen-tresor): ${JSON.stringify(fpsBericht)}`);
        }
        await gmCmd("flow.next");
      }
    } else {
      await gmCmd("flow.next");
    }
  } else if (phase === "siegerehrung") {
    break;
  } else {
    await gmCmd("flow.next");
  }
  await delay(350);
}

if (geschossen.size < ziele.length) {
  throw new Error(`Nur ${geschossen.size}/${ziele.length} Demos geschossen: ${[...geschossen]}`);
}
log(`Alle ${geschossen.size} Demo-Karten geschossen.`);
if (videoRohPfad) console.log(`VIDEO_ROH=${videoRohPfad}`);
if (fpsBericht && fpsBericht.fps < 50) {
  throw new Error(`fps-Budget verfehlt: ${JSON.stringify(fpsBericht)}`);
}

await browser.close();
gm.close();
opener.close();
server.kill();
process.exit(0);
