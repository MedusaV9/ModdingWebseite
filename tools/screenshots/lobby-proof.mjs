// Lobby-Beweis (Bot + Playwright): 3 Räume öffnen (1 privat, 2 öffentlich mit
// 2 bzw. 1 Spielern) → dritter Client nutzt die Schnell-Beitritt-API und landet
// in der VOLLSTEN öffentlichen Lobby → Landing zeigt den Lobby-Browser LIVE
// (Socket-Update ohne Reload, privater Raum bleibt unsichtbar) → Screen-Lobby
// mit Link-Teilen (HTTP-Fallback-Feld) + Umbenennen, das live auf der Landing
// ankommt.
//
//   node tools/screenshots/lobby-proof.mjs → /opt/cursor/artifacts/mm_lobby_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, readdirSync, renameSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8093);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[lobby-proof] ${t}`);
const fail = (t) => {
  console.error(`[lobby-proof] ❌ ${t}`);
  process.exit(1);
};

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-lobby-proof-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-lobby-proof-data" },
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

// ---------- 2) Playwright: Landing VOR allen Räumen — Schnell-Dialog ----------
const browser = await chromium.launch();
const landing = await browser.newPage({ viewport: { width: 390, height: 844 } });
await landing.goto(URL_BASIS);
await landing.click('[data-testid="schnell-beitreten"]');
await landing.waitForSelector("text=Keine offene Lobby", { timeout: 5000 });
await schuss(landing, "01_schnell_dialog_keine_lobby");
log(`Schnell-Beitritt ohne Lobbys → Dialog "Keine offene Lobby" ✅`);
await landing.click("text=← Zurück");

// ---------- 3) Bot-Räume: 1 privat + 2 öffentlich (2 bzw. 1 Spieler) ----------
async function erzeugeRaum(extras = {}) {
  const sock = io(URL_BASIS, { transports: ["websocket"] });
  const raum = await sock
    .timeout(5000)
    .emitWithAck("room.create", { role: "screen", origin: URL_BASIS, ...extras });
  if (!raum.ok) fail(`room.create: ${raum.error}`);
  // Screen bleibt verbunden (clientCount > 0 ⇒ Lobby lebt) — hello als Screen.
  const hello = await sock
    .timeout(5000)
    .emitWithAck("hello", { roomCode: raum.code, role: "screen", origin: URL_BASIS });
  if (!hello.ok) fail(`screen hello: ${hello.error}`);
  return { sock, code: raum.code };
}

async function spielerJoin(code, name) {
  const sock = io(URL_BASIS, { transports: ["websocket"] });
  const antwort = await sock
    .timeout(5000)
    .emitWithAck("hello", { roomCode: code, role: "player", name, avatar: "gelb" });
  if (!antwort.ok) fail(`player hello (${name} → ${code}): ${antwort.error}`);
  return { sock, roomCode: antwort.roomCode };
}

const privat = await erzeugeRaum(); // Default: privat (nur Code)
const publikA = await erzeugeRaum({ oeffentlich: true, name: "Bananen-Bande Deluxe" });
const publikB = await erzeugeRaum({ oeffentlich: true });
await spielerJoin(publikA.code, "Zoe");
await spielerJoin(publikA.code, "Ben");
await spielerJoin(publikB.code, "Mia");
log(
  `Räume: privat=${privat.code}, öffentlich A=${publikA.code} (2 Spieler), B=${publikB.code} (1 Spieler)`,
);

// ---------- 4) HTTP-Beweis: /api/lobbys + /api/schnell-beitritt ----------
const lobbys = (await (await fetch(`${URL_BASIS}/api/lobbys`)).json()).lobbys;
if (lobbys.length !== 2) fail(`/api/lobbys: erwartet 2 öffentliche, bekam ${lobbys.length}`);
if (lobbys.some((l) => l.code === privat.code)) fail("privater Raum ist in /api/lobbys sichtbar!");
log(
  `GET /api/lobbys → ${lobbys.map((l) => `${l.name} (${l.code}) ${l.spieler}/${l.max} ${l.status}`).join(" · ")} ✅`,
);

const schnell = await (await fetch(`${URL_BASIS}/api/schnell-beitritt`)).json();
if (!schnell.ok) fail(`/api/schnell-beitritt: ${JSON.stringify(schnell)}`);
if (schnell.code !== publikA.code) {
  fail(`Schnell-Beitritt wählte ${schnell.code}, erwartet die VOLLSTE Lobby ${publikA.code}`);
}
log(`GET /api/schnell-beitritt → ${schnell.code} (vollste offene Lobby) ✅`);

// Dritter Client joint per Schnell-Beitritt-Code und landet im öffentlichen Raum A.
const dritter = await spielerJoin(schnell.code, "Kai");
if (dritter.roomCode !== publikA.code) fail(`Dritter Client landete in ${dritter.roomCode}`);
log(`BOT-BEWEIS: dritter Client (Kai) ist im öffentlichen Raum ${publikA.code} ✅`);

// ---------- 5) Landing: Lobby-Browser erscheint LIVE (ohne Reload) ----------
await landing.waitForSelector('[data-testid="lobby-browser"]', { timeout: 6000 });
const zeilen = await landing.locator('[data-testid="lobby-zeile"]').count();
if (zeilen !== 2) fail(`Landing zeigt ${zeilen} Lobbys, erwartet 2`);
const listeText = await landing.locator('[data-testid="lobby-browser"]').innerText();
if (listeText.includes(privat.code)) fail("privater Raum-Code auf der Landing sichtbar!");
log("Landing: Lobby-Browser erschien LIVE per Socket (Seite wurde NIE neu geladen) ✅");
await schuss(landing, "02_landing_lobby_browser");

// ---------- 6) Screen-Lobby: Link teilen (HTTP-Fallback) + Umbenennen ----------
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), publikA.code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector('[data-testid="link-teilen"]', { timeout: 8000 });
await screen.click('[data-testid="link-teilen"]');
// HTTP (kein Clipboard-Cap) ⇒ Fallback: Text-Feld mit vorausgewählter Join-URL.
await screen.waitForSelector('[data-testid="link-feld"]', { timeout: 4000 });
const feldWert = await screen.inputValue('[data-testid="link-feld"]');
if (!feldWert.endsWith(`/j/${publikA.code}`)) fail(`Link-Feld zeigt ${feldWert}`);
log(`Screen-Lobby: Link-Teilen-Fallback-Feld zeigt ${feldWert} ✅`);
await schuss(screen, "03_screen_lobby_link_teilen");

// Umbenennen auf dem Screen → kommt LIVE auf der Landing an.
await screen.click('button[aria-label="Raum-Namen ändern"]');
await screen.fill('input[maxlength="32"]', "Affen-WG Deluxe");
await screen.click("button.primaer:has-text('OK')");
await landing.waitForSelector("text=Affen-WG Deluxe", { timeout: 6000 });
log(`Umbenennen am Screen → Landing zeigt "Affen-WG Deluxe" LIVE ✅`);
await schuss(landing, "04_landing_umbenannt_live");

// ---------- 7) Ersteller-Pfad: Landing-Wahl „Öffentlich" → /screen?public=1 ----------
const wahl = await browser.newPage({ viewport: { width: 390, height: 844 } });
await wahl.goto(URL_BASIS);
await wahl.click("text=📺 Bildschirm eröffnen");
await wahl.waitForSelector("text=🌍 Öffentlich sichtbar", { timeout: 4000 });
await schuss(wahl, "05_bildschirm_wahl_privat_oeffentlich");
await wahl.click("text=🌍 Öffentlich sichtbar");
await wahl.waitForURL("**/screen?public=1", { timeout: 5000 });
await wahl.waitForSelector('[data-testid="sichtbarkeit-toggle"]', { timeout: 8000 });
const neuerCode = (await wahl.locator("p.mono").first().innerText()).trim();
const lobbys2 = (await (await fetch(`${URL_BASIS}/api/lobbys`)).json()).lobbys;
if (!lobbys2.some((l) => l.code === neuerCode && l.status === "lobby")) {
  fail(`Landing-Wahl „Öffentlich": Raum ${neuerCode} fehlt in /api/lobbys`);
}
log(`Ersteller-Pfad: Landing-Wahl „Öffentlich" → Raum ${neuerCode} ist im Lobby-Browser ✅`);
await wahl.close();

// ---------- 8) Video: Schnell-Beitritt-Flow auf der Landing ----------
const videoCtx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  recordVideo: { dir: OUT, size: { width: 390, height: 844 } },
});
const demo = await videoCtx.newPage();
await demo.goto(URL_BASIS);
await demo.waitForSelector('[data-testid="lobby-browser"]', { timeout: 6000 });
await delay(1500); // Liste in Ruhe zeigen
await demo.click('[data-testid="schnell-beitreten"]');
await demo.waitForURL(`**/j/${publikA.code}`, { timeout: 6000 });
await demo.waitForSelector('input[placeholder="Dein Name"]', { timeout: 6000 });
await delay(1200); // Join-Formular mit Raum-Code zeigen
const video = demo.video();
await demo.close();
const videoPfad = await video.path();
await videoCtx.close();
renameSync(videoPfad, `${OUT}/mm_lobby_schnellbeitritt_demo.webm`);
log(
  `🎬 Video: ${OUT}/mm_lobby_schnellbeitritt_demo.webm (Landing → Schnell beitreten → Join-Formular in Raum ${publikA.code})`,
);

log(
  `Fertig — Artefakte: ${readdirSync(OUT)
    .filter((f) => f.startsWith("mm_lobby_"))
    .join(", ")}`,
);
await browser.close();
server.kill();
process.exit(0);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_lobby_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
