// Standalone-Beweis (Playwright, OHNE iPad): der komplette iPad-Host-Pfad auf
// der VM — relay-sim spielt den Swift-Server, Desktop-Chrome spielt das iPad
// (Host-Seite = Browser-Server + Bühnen-iframe), zwei Telefon-Pages joinen per
// Join-URL und spielen 3 Fragen end-zu-end. Der GM hängt als roher
// Wire-Protokoll-Client (ws) am Relay — exakt wie ein GM-Handy im Feld.
//
//   npm run build:client && node tools/ipad-host/proof-standalone.mjs
//   → /opt/cursor/artifacts/mm_standalone_*.png
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import WebSocket from "ws";

const PORT = Number(process.env.PROOF_PORT ?? 8094);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[standalone-proof] ${t}`);

// ---------- 1) Relay-Sim starten (der Swift-Stellvertreter) ----------
const relay = spawn("node", ["tools/ipad-host/relay-sim.mjs"], {
  env: { ...process.env, RELAY_PORT: String(PORT), RELAY_ORIGIN: URL_BASIS },
  stdio: ["ignore", "inherit", "inherit"],
});
process.on("exit", () => relay.kill());
for (let i = 0; i < 40; i++) {
  try {
    if ((await fetch(`${URL_BASIS}/healthz`)).ok) break;
  } catch {
    /* Relay bootet noch */
  }
  await delay(250);
}
log(`Relay-Sim läuft auf :${PORT}`);

// ---------- 2) „iPad": Host-Seite = Browser-Server + Bühnen-iframe ----------
const browser = await chromium.launch({ args: ["--autoplay-policy=no-user-gesture-required"] });
const host = await browser.newPage({ viewport: { width: 1280, height: 800 } });
host.on("pageerror", (e) => log(`⚠ Host-Fehler: ${String(e).slice(0, 200)}`));
await host.goto(`${URL_BASIS}/host`);
await host.waitForSelector(".host-banner", { timeout: 10_000 });

const buehne = () => host.frames().find((f) => f.url().includes("/screen"));
await host.waitForFunction(() => window.frames.length > 0);
for (let i = 0; i < 40 && !buehne(); i++) await delay(250);
await buehne().waitForSelector(".mono", { timeout: 10_000 });

// Raum-Code + GM-PIN von der Bühne ablesen (steht in der Lobby).
const lobbyText = await buehne().evaluate(() => document.body.innerText);
const code = lobbyText.match(/\/j\/([A-Z]{4})/)?.[1];
const gmPin = lobbyText.match(/PIN:\s*(\d{4})/)?.[1];
if (!code || !gmPin) throw new Error(`Lobby unlesbar: ${lobbyText.slice(0, 200)}`);
log(`✅ Browser-Server läuft: Raum ${code}, GM-PIN ${gmPin}, Join ${URL_BASIS}/j/${code}`);

// QR auf der Bühne ist da (kommt vom Relay: /api/qr → SVG)?
await buehne().waitForFunction(
  () =>
    document.querySelector('img[src^="/api/qr"]') !== null &&
    document.querySelector('img[src^="/api/qr"]').naturalWidth > 0,
  { timeout: 8000 },
);
log("✅ QR-Code der Bühne lädt über das Relay (/api/qr)");
await schuss(host, "01_host_lobby");

// ---------- 3) „iPhones": zwei Telefon-Pages joinen über die Join-URL ----------
const spielerA = await browser.newPage({ viewport: { width: 390, height: 844 } });
const spielerB = await browser.newPage({ viewport: { width: 390, height: 844 } });

async function join(page, name, affenKlicks, farbIndex) {
  await page.goto(`${URL_BASIS}/j/${code}`); // Relay hängt ?standalone=1 an (302)
  if (!page.url().includes("standalone=1")) throw new Error("standalone-Redirect fehlt!");
  await page.fill('input[placeholder="Dein Name"]', name);
  for (let i = 0; i < affenKlicks; i++) await page.click('button[aria-label="Nächster Affe"]');
  await page.click(`.farb-reihe .farb-knopf:nth-child(${farbIndex + 1})`);
  await delay(300);
  await page.click("button.primaer");
}

await join(spielerA, "Zoe", 2, 2);
await join(spielerB, "Ben", 4, 4);
await spielerA.waitForSelector(".spieler-liste", { timeout: 8000 });
await buehne().waitForFunction(() => document.querySelectorAll(".podium-puppe svg").length >= 2, {
  timeout: 10_000,
});
log("✅ Beide Telefone im Raum (nativer WS → Relay → Browser-Server)");
await schuss(spielerA, "02_phone_lobby");

// ---------- 4) GM: roher Wire-Protokoll-Client am Relay ----------
const gm = new WebSocket(`ws://localhost:${PORT}/ws`);
let gmView = null;
const acks = new Map();
let ackNr = 0;
gm.on("message", (roh) => {
  const msg = JSON.parse(String(roh));
  if (msg.t === "a") acks.get(msg.ack)?.(msg.p);
  if (msg.t === "e" && msg.ev === "view.snapshot") gmView = msg.p.view;
});
await new Promise((r) => gm.on("open", r));
function gmSende(ev, p) {
  const ack = ++ackNr;
  return new Promise((resolve, reject) => {
    acks.set(ack, resolve);
    setTimeout(() => reject(new Error(`ack-timeout ${ev}`)), 8000);
    gm.send(JSON.stringify({ t: "e", ev, p, ack }));
  });
}
const gmHello = await gmSende("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`GM-hello: ${gmHello.error}`);
log("✅ GM verbunden (Wire-Protokoll über /ws)");
async function gmCmd(cmd, args = {}) {
  const antwort = await gmSende("gm.cmd", { cmd, args, cmdId: `proof-${ackNr}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

async function wartePhase(phase, timeout = 15_000) {
  await buehne().waitForFunction(
    (p) => document.querySelector(".studio")?.dataset.phase === p,
    phase,
    { timeout },
  );
}

/** Richtige Antwort der laufenden Frage aus der GM-Sicht (Spickzettel). */
async function richtigIndex() {
  for (let i = 0; i < 60; i++) {
    const idx = gmView?.minigame?.view?.correctIndex;
    if (gmView?.phase === "frage" && typeof idx === "number") return idx;
    await delay(150);
  }
  return 0;
}

// ---------- 5) Match: 3 Fragen end-zu-end ----------
await gmCmd("settings.set", { modus: "quick", jokerAn: true });
await gmCmd("flow.next"); // Lobby → Intro
await wartePhase("intro");
await gmCmd("flow.next"); // Intro → Erklärkarte R1
await wartePhase("erklaerkarte");
await gmCmd("flow.next"); // Erklärkarte → Frage 1

for (let frage = 1; frage <= 3; frage++) {
  await wartePhase("frage");
  await spielerA.waitForSelector("#mg-host button:not([disabled])", { timeout: 10_000 });
  const richtig = await richtigIndex();
  if (frage === 1) {
    await delay(700);
    await schuss(host, "03_stage_frage1");
    await schuss(spielerA, "04_phone_frage1");
  }
  await spielerA.click(`#mg-host button >> nth=${richtig}`);
  await spielerB.click(`#mg-host button >> nth=${(richtig + frage) % 4}`);
  await wartePhase("aufloesung");
  log(`✅ Frage ${frage} gespielt (richtig war ${richtig}; Zoe richtig, Ben daneben)`);
  if (frage === 1) {
    await delay(800);
    await schuss(host, "05_stage_aufloesung1");
  }
}

// Nach Frage 3 (quick): Auto-Advance → Zwischenstand mit echten Konten.
await wartePhase("zwischenstand", 20_000);
await delay(900);
await schuss(host, "06_stage_zwischenstand");
const staende = await buehne().evaluate(() => document.body.innerText.slice(0, 400));
log(`Zwischenstand der Bühne:\n${staende}`);

// ---------- 6) Persistenz-Beleg: Event-Log liegt in IndexedDB ----------
const idbBeleg = await host.evaluate(async () => {
  const db = await new Promise((resolve, reject) => {
    const req = indexedDB.open("monkey-money-standalone", 1);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  const lese = (store) =>
    new Promise((resolve) => {
      const tx = db.transaction(store, "readonly").objectStore(store);
      const keysReq = tx.getAllKeys();
      keysReq.onsuccess = async () => {
        const keys = keysReq.result;
        const werte = await Promise.all(
          keys.map(
            (k) =>
              new Promise((res) => {
                const r = db.transaction(store, "readonly").objectStore(store).get(k);
                r.onsuccess = () => res(r.result);
              }),
          ),
        );
        resolve(
          keys.map((k, i) => ({
            key: k,
            zeilen: Array.isArray(werte[i]) ? werte[i].length : null,
          })),
        );
      };
    });
  return { json: await lese("json"), zeilen: await lese("zeilen") };
});
log(
  `✅ IndexedDB-Persistenz: json=${JSON.stringify(idbBeleg.json)} · logs=${JSON.stringify(idbBeleg.zeilen)}`,
);

log(`Fertig — Screenshots in ${OUT}`);
await browser.close();
gm.close();
relay.kill();
process.exit(0);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_standalone_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
