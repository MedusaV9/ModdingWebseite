// Screenshot-Tour (Playwright): startet den gebauten Server, öffnet Screen
// (1280×800) + 2 Player (390×844) headless, spielt 2 Fragen + Glücksrad +
// Siegerehrung (GM-Socket steuert den Flow, Antworten klicken die Player-Pages)
// und schießt die Schlüssel-Momente als PNGs.
//
//   node tools/screenshots/tour.mjs            → /opt/cursor/artifacts/mm_tour_*.png
//   OUT_DIR=/tmp/mm-tour node tools/…/tour.mjs → Iterations-Läufe
//
// Voraussetzungen: npm run build (client/dist + server/dist), npx playwright
// install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.TOUR_PORT ?? 8091);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[tour] ${t}`);

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-tour-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-tour-data" },
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

// ---------- 2) Raum anlegen (Opener-Socket, bleibt still verbunden) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

// ---------- 3) Browser: Screen + 2 Player ----------
const browser = await chromium.launch();
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

const spielerA = await browser.newPage({ viewport: { width: 390, height: 844 } });
const spielerB = await browser.newPage({ viewport: { width: 390, height: 844 } });

/** Join-Flow über die ECHTE UI: Name + Affe (Karussell) + Farbe. */
async function join(page, name, affenKlicks, farbIndex) {
  await page.goto(`${URL_BASIS}/j/${code}`);
  await page.fill('input[placeholder="Dein Name"]', name);
  for (let i = 0; i < affenKlicks; i++) {
    await page.click('button[aria-label="Nächster Affe"]');
  }
  await page.click(`.farb-reihe .farb-knopf:nth-child(${farbIndex + 1})`);
  await delay(300);
}

await join(spielerA, "Zoe", 2, 2); // Kiki Krawall, türkis
log("Spieler A auf dem Join-Screen");
await schuss(spielerA, "01_phone_join_affenwahl");
await spielerA.click("button.primaer");
await join(spielerB, "Ben", 4, 4); // Oma Zinseszins, orange
await spielerB.click("button.primaer");
await spielerA.waitForSelector(".spieler-liste", { timeout: 8000 });
log("Beide Spieler im Raum");

// Podien mit geladenen Puppen in der Lobby abwarten.
await screen.waitForFunction(() => document.querySelectorAll(".podium-puppe svg").length >= 2, {
  timeout: 8000,
});
await delay(600);
await schuss(screen, "02_studio_lobby");

// ---------- 4) GM-Socket: Match starten + Flow treiben ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;

/** GM-Spickzettel: richtige Antwort der laufenden Frage (Podium-Geldstapel-Beweis). */
async function richtigIndex() {
  for (let i = 0; i < 40; i++) {
    const idx = gmView?.minigame?.view?.correctIndex;
    if (gmView?.phase === "frage" && typeof idx === "number") return idx;
    await delay(150);
  }
  return 0;
}
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `tour-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

/** Auf eine Engine-Phase warten (der Screen trägt sie als data-phase). */
async function wartePhase(page, phase, timeout = 10_000) {
  await page.waitForFunction((p) => document.querySelector(".studio")?.dataset.phase === p, phase, {
    timeout,
  });
}

await gmCmd("settings.set", { modus: "quick", jokerAn: true });
await gmCmd("flow.next"); // Lobby → Intro (Show-Opening)
await wartePhase(screen, "intro");
await delay(2300); // Logo-Stinger + Kandidaten-Einflug
await schuss(screen, "03_intro_opening");

await gmCmd("flow.next"); // Intro → Erklärkarte R1
await wartePhase(screen, "erklaerkarte");
await delay(700);
await schuss(screen, "04_rundenkarte");

// ---------- Frage 1: Zoe richtig (Jubel + Geldstapel!), Ben falsch ----------
// Sobald ALLE geantwortet haben, löst die Engine selbst auf und taktet danach
// automatisch weiter (AUFLOESUNG_MS) — kein flow.next nötig, nur abwarten.
await gmCmd("flow.next"); // Erklärkarte → Frage 1
await spielerA.waitForSelector("#mg-host button:not([disabled])", { timeout: 8000 });
await delay(900);
await schuss(screen, "05_frage_ledwand");
await schuss(spielerA, "06_phone_frage");
let richtig = await richtigIndex();
await spielerA.click(`#mg-host button >> nth=${richtig}`);
await delay(420); // Münze fällt gerade
await schuss(spielerA, "07_phone_muenz_lockin");
await spielerB.click(`#mg-host button >> nth=${(richtig + 1) % 4}`);
log(`Frage 1 beantwortet (richtig: ${richtig})`);

await wartePhase(screen, "aufloesung");
await delay(900);
await schuss(screen, "08_aufloesung_podium");
await schuss(spielerA, "08b_phone_aufloesung");

// ---------- Frage 2: nochmal antworten (Zoe wieder richtig), dann Rad ----------
await wartePhase(screen, "frage", 12_000); // Auto-Advance nach AUFLOESUNG_MS
await spielerA.waitForSelector("#mg-host button:not([disabled])", { timeout: 8000 });
richtig = await richtigIndex();
await spielerA.click(`#mg-host button >> nth=${richtig}`);
await spielerB.click(`#mg-host button >> nth=${(richtig + 2) % 4}`);
await wartePhase(screen, "aufloesung");
log(`Frage 2 beantwortet (richtig: ${richtig})`);
await wartePhase(screen, "frage", 12_000); // → Frage 3
await gmCmd("flow.next"); // Frage 3 per GM-Skip auflösen (force-finish)
await wartePhase(screen, "zwischenstand", 12_000);
await delay(800);
await schuss(screen, "09_zwischenstand");

// ---------- Glücksrad (GM-Spin im Zwischenstand) ----------
await gmCmd("wheel.spin");
await wartePhase(screen, "rad", 8000);
await delay(1500); // mitten im Dreh
await schuss(screen, "10_gluecksrad_dreh");
await gmCmd("flow.next"); // Dreh → Einschlag/Ergebnis
await delay(1200);
await schuss(screen, "11_rad_ergebnis");
// Interaktive Segmente (Umarmungs-Bonus): der Buzzer-XXL-Moment auf dem Handy.
try {
  await spielerA.waitForSelector(".buzzer-xxl", { timeout: 1500 });
  await schuss(spielerA, "11b_phone_buzzer_xxl");
} catch {
  /* Rad traf ein nicht-interaktives Segment — kein Buzzer diesmal. */
}
await gmCmd("flow.next"); // Rad-Phase abschließen (ggf. Interaktion skippen)
await delay(400);
await gmCmd("flow.next");

// ---------- Siegerehrung (Podest-Einlauf + Money-Regen + Awards) ----------
await gmCmd("session.ende");
await wartePhase(screen, "siegerehrung");
await delay(4100); // Podest 3-2-1 (2,7 s) + Money-Regen (2,6 s) + erste Awards (2,8 s)
await schuss(screen, "12_siegerehrung");
await schuss(spielerA, "13_phone_siegerehrung");

log(`Fertig — Screenshots in ${OUT}`);
await browser.close();
gm.close();
opener.close();
server.kill();
process.exit(0);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_tour_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
