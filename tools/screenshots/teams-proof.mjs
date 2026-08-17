// TEAM-MODUS-Beweis (Playwright): Lobby-Team-Wahl (Handy-Buttons + Screen-
// Spalten), Team-Zwischenstand mit Individual-Aufschlüsselung und das
// Team-Podest der Siegerehrung — ein Quick-Match mit 5 Spielern im 2er-Modus
// (ungerade Zahl ⇒ Doppel-Affe 🐵🐵×2), deterministisch über GM-Kommandos.
//
//   node tools/screenshots/teams-proof.mjs → /opt/cursor/artifacts/mm_teams_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8094);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const DATA = "/tmp/mm-teams-proof-data";
mkdirSync(OUT, { recursive: true });
rmSync(DATA, { recursive: true, force: true });
mkdirSync(DATA, { recursive: true });

const log = (t) => console.log(`[teams-proof] ${t}`);

// ---------- 1) Server starten ----------
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: DATA },
  stdio: "ignore",
});
process.on("exit", () => server.kill());
for (let i = 0; i < 40; i++) {
  try {
    if ((await fetch(`${URL_BASIS}/healthz`)).ok) break;
  } catch {
    /* Server bootet noch */
  }
  await delay(250);
}
log(`Server läuft auf :${PORT}`);

// ---------- 2) Raum + 5 Spieler (ungerade ⇒ Doppel-Affe im 2er-Modus) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

async function spielerSocket(name, avatar) {
  const sock = io(URL_BASIS, { transports: ["websocket"] });
  const w = await sock
    .timeout(5000)
    .emitWithAck("hello", { roomCode: code, role: "player", name, avatar });
  if (!w.ok) throw new Error(`hello ${name}: ${w.error}`);
  return { sock, name, playerId: w.playerId, token: w.sessionToken };
}

const namen = ["Anna", "Ben", "Cleo", "Dino", "Emil"];
const farben = ["gelb", "rot", "gruen", "blau", "lila"];
const spieler = [];
for (let i = 0; i < 5; i++) spieler.push(await spielerSocket(namen[i], farben[i]));
log(`5 Spieler in der Lobby: ${spieler.map((s) => s.name).join(", ")}`);

let aktionNr = 0;
async function aktion(s, event, payload) {
  const antwort = await s.sock
    .timeout(5000)
    .emitWithAck(event, { ...payload, idemKey: `teams-${aktionNr++}` });
  if (!antwort.ok) log(`⚠ ${event} (${s.name}): ${antwort.error}`);
  return antwort.ok;
}

// ---------- 3) GM: Team-Modus 2er einschalten, Wünsche äußern lassen ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `teams-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

await gmCmd("settings.set", { modus: "quick", autoGm: false, teams: "2er" });
log("Team-Modus „2er“ aktiv (5 Spieler ⇒ 3 Teams, eins solo = Doppel-Affe)");

// Wünsche per Socket: Anna+Ben → Banane, Cleo+Dino → Kokos (Emil wählt am Handy).
await aktion(spieler[0], "team.wahl", { team: "banane" });
await aktion(spieler[1], "team.wahl", { team: "banane" });
await aktion(spieler[2], "team.wahl", { team: "kokos" });
await aktion(spieler[3], "team.wahl", { team: "kokos" });

// ---------- 4) Browser: Screen + Emils Handy (echte Team-Wahl per Klick) ----------
const browser = await chromium.launch({ args: ["--autoplay-policy=no-user-gesture-required"] });
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

const emilPhone = await browser.newPage({ viewport: { width: 390, height: 844 } });
await emilPhone.addInitScript(({ c, t }) => localStorage.setItem(`mm:${c}`, t), {
  c: code,
  t: spieler[4].token,
});
await emilPhone.goto(`${URL_BASIS}/j/${code}`);
await emilPhone.waitForSelector(".spieler-kopf", { timeout: 10_000 });

// BEWEIS 1: Handy-Team-Wahl — Emil klickt „Team Liane" auf seinem Handy.
await emilPhone.waitForSelector('[data-testid="team-wahl-liane"]', { timeout: 8000 });
await schuss(emilPhone, "handy_teamwahl_buttons");
await emilPhone.click('[data-testid="team-wahl-liane"]');
await emilPhone.waitForFunction(
  () => document.querySelector('[data-testid="team-wahl-liane"]')?.textContent.includes("✅"),
  { timeout: 6000 },
);
log("📱 Emil wählt „Team Liane“ per Handy-Klick (✅ bestätigt)");

// BEWEIS 2: Screen-Lobby mit Team-Spalten (alle 5 Wünsche sichtbar).
await screen.waitForSelector('[data-testid="team-spalten"]', { timeout: 8000 });
await delay(800);
await schuss(screen, "lobby_spalten_screen");
log("📺 Lobby-Team-Spalten mit allen Wunsch-Affen");

// ---------- 5) Match starten + durchsteuern (autoGm aus ⇒ GM skippt) ----------
await gmCmd("flow.next");
log("Match gestartet — Teams werden gebildet (Emil solo ⇒ Doppel-Affe)");

let geldVerteilt = false;
let zwischenstandSchuss = false;
let schritte = 0;
while (schritte < 200) {
  schritte += 1;
  const phase = gmView?.phase;
  if (phase === "siegerehrung" || phase === "ende") break;

  if (phase === "zwischenstand" && !geldVerteilt) {
    // Deutlich unterscheidbare Töpfe: Banane 1300, Liane 600×2=1200, Kokos 400.
    geldVerteilt = true;
    const betraege = [900, 400, 250, 150, 600];
    for (let i = 0; i < 5; i++) {
      await gmCmd("score.adjust", {
        playerId: spieler[i].playerId,
        delta: betraege[i],
        grund: "Teams-Demo Kontostand",
        override: true,
      });
    }
    log("Zwischenstand: Konten gesetzt (Banane 1300 / Liane 1200 ×2 / Kokos 400)");
    // BEWEIS 3: Team-Zwischenstand mit Individual-Aufschlüsselung + 🐵🐵×2.
    await screen.waitForSelector('[data-testid="team-zwischenstand"]', { timeout: 8000 });
    await delay(1000);
    await schuss(screen, "zwischenstand_screen");
    zwischenstandSchuss = true;
  }

  await gmCmd("flow.next");
  await delay(600);
}
if (!zwischenstandSchuss) throw new Error("Team-Zwischenstand nie gesehen");
if (gmView?.phase !== "siegerehrung") {
  throw new Error(`Siegerehrung nicht erreicht: ${gmView?.phase}`);
}

// ---------- 6) BEWEIS 4: Team-Podest der Siegerehrung ----------
await screen.waitForSelector('[data-testid="team-podest"]', { timeout: 10_000 });
await delay(4600); // Podest-Einflug + Award-Band („Bester Einzel-Affe")
await schuss(screen, "podest_siegerehrung_screen");
const podestText = await screen.evaluate(
  () => document.querySelector('[data-testid="team-podest"]').textContent,
);
if (!podestText.includes("🥇")) throw new Error(`Podest ohne Gold: ${podestText.slice(0, 80)}`);
log(`🏆 Team-Podest: „${podestText.replace(/\s+/g, " ").trim().slice(0, 90)}…"`);

// BEWEIS 5: Emils Handy — Team-Ergebnis (Platz + Topf) auf der Siegerehrung.
await delay(600);
await schuss(emilPhone, "handy_ergebnis_doppelaffe");
log("📱 Emils Handy zeigt sein Team-Ergebnis (Doppel-Affe, Team Liane)");

log(`Fertig — Screenshots in ${OUT}`);
await browser.close();
gm.close();
opener.close();
for (const s of spieler) s.sock.close();
server.kill();
process.exit(0);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_teams_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
