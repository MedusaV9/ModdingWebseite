// Fix-2D-Beweis (Playwright): Content-Fixes sichtbar im echten Match.
//   1. Kategorie-Badge („Ober · Unter") auf Bühne UND Handy in der Frage-Phase.
//   2. GM-Spickzettel zeigt die 3 Autoren-Tipps + „Tipp 1/2/3 senden"-Knöpfe;
//      Tipp 1 senden enthüllt den Text auf Bühne + Handys (Tipp-Kanone).
//   3. Bananen-Tresor (R3) und Affenleiter (R4, Marathon-Plan) spielen ECHTE
//      Pool-Fragen (kind schaetz/sortier, id q_*) statt der eingebauten Pools —
//      Beleg: question_shown-Events aus dem Event-Log des Matches.
//
//   node tools/screenshots/fix2d-proof.mjs → /opt/cursor/artifacts/mm_fix2d_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8093);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const DATA_DIR = "/tmp/mm-fix2d-data";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[fix2d] ${t}`);
const checks = [];
function check(name, ok, detail = "") {
  checks.push({ name, ok });
  log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
}

// ---------- 1) Server (eigener Port + Wegwerf-Datenordner) ----------
rmSync(DATA_DIR, { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR },
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

// ---------- 2) Raum + GM-Socket + 3 Server-Bots ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `fix2d-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}
for (let i = 0; i < 3; i++) await gmCmd("bot.add");

// ---------- 3) Seiten: Bühne, passiver Spieler, GM-Cockpit ----------
const browser = await chromium.launch();
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".studio", { timeout: 10_000 });

// Passiver echter Spieler: verhindert Alle-bereit-Races, zeigt die Handy-Sicht.
const phone = await browser.newPage({ viewport: { width: 390, height: 844 } });
await phone.goto(`${URL_BASIS}/j/${code}`);
await phone.fill('input[placeholder="Dein Name"]', "Zoe");
await phone.click(".farb-reihe .farb-knopf:nth-child(3)");
await delay(300);
await phone.click("button.primaer");
await phone.waitForSelector(".spieler-liste", { timeout: 8000 });

// GM-Cockpit-Seite (verbindet als Beobachter — Übernahme später per PIN-UI).
const gmSeite = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await gmSeite.addInitScript((d) => localStorage.setItem("mm:gm", JSON.stringify(d)), {
  code,
  pin: String(gmPin),
});
await gmSeite.goto(`${URL_BASIS}/gm`);
await gmSeite.click("button.primaer"); // Login (Code+PIN vorausgefüllt)
await gmSeite.waitForSelector('[data-testid="gm-beobachter"]', { timeout: 10_000 });
log("Bühne + Handy (Zoe) + GM-Cockpit (Beobachter) verbunden");

async function schuss(page, name) {
  const pfad = `${OUT}/mm_fix2d_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

/** Spickzettel-Karte gezielt schießen (liegt im Cockpit unter dem Falz). */
async function schussSpickzettel(name) {
  const karte = gmSeite
    .locator(".karte", { has: gmSeite.locator('[data-testid="gm-tipp-1"]') })
    .first();
  await karte.scrollIntoViewIfNeeded();
  const pfad = `${OUT}/mm_fix2d_${name}.png`;
  await karte.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

// ---------- 4) Marathon starten und bis zur 1. Frage vorspulen ----------
await gmCmd("settings.set", { modus: "marathon" });
await gmCmd("flow.next"); // Lobby → Intro
async function bisPhase(zielPhase, zielMinigame, maxSchritte = 120) {
  for (let i = 0; i < maxSchritte; i++) {
    const phase = gmView?.phase;
    const mg = gmView?.abschnitt?.minigameId;
    if (phase === zielPhase && (zielMinigame === null || mg === zielMinigame)) return true;
    await gmCmd("flow.next");
    await delay(700);
  }
  return false;
}
if (!(await bisPhase("frage", "bananen-basics"))) throw new Error("R1-Frage nicht erreicht");
await delay(1200); // Frage eingeblendet, Bots tippen noch
// Timer strecken (+30 s), damit Badge-Checks + GM-Takeover + Tipp-Klick
// bequem in die offene Frage passen (Zoe antwortet nie ⇒ Timer läuft voll).
await gmCmd("timer.extend", { ms: 15_000 });
await gmCmd("timer.extend", { ms: 15_000 });

// ---------- 5) BEWEIS 1: Kategorie-Badge auf Bühne + Handy ----------
const badgeBuehne = await screen
  .waitForSelector('[data-testid="frage-kategorie"]', { timeout: 8000 })
  .then((el) => el.textContent());
check("Kategorie-Badge auf der Bühne", /·/.test(badgeBuehne ?? ""), badgeBuehne?.trim());
const badgeHandy = await phone
  .waitForSelector('[data-testid="frage-kategorie"]', { timeout: 8000 })
  .then((el) => el.textContent());
check("Kategorie-Mini-Zeile auf dem Handy", (badgeHandy ?? "").length > 3, badgeHandy?.trim());
await schuss(screen, "01_badge_buehne");

// ---------- 6) BEWEIS 2: GM-Spickzettel mit Tipp-1/2/3-Knöpfen ----------
// Zur nächsten Frage MIT Autoren-Tipps springen (wahr_falsch hat designbedingt
// 0 Tipps — dort zeigt der Spickzettel keine Sende-Knöpfe).
for (let i = 0; i < 8; i++) {
  if (gmView?.phase === "frage" && (gmView?.spickzettelTipps?.length ?? 0) >= 3) break;
  await gmCmd("flow.next"); // Frage beenden bzw. Auflösung überspringen
  await delay(700);
  await bisPhase("frage", null);
  await delay(900);
}
if ((gmView?.spickzettelTipps?.length ?? 0) < 3) throw new Error("keine Frage mit Tipps gefunden");
log(`Frage mit ${gmView.spickzettelTipps.length} Autoren-Tipps erreicht (${gmView.phase})`);
await gmCmd("timer.extend", { ms: 15_000 });
await gmCmd("timer.extend", { ms: 15_000 });

// Cockpit per PIN übernehmen (der Socket-GM wird dadurch Beobachter).
await gmSeite.fill('[data-testid="gm-beobachter"] input', String(gmPin));
await gmSeite.click('[data-testid="gm-beobachter"] button');
await gmSeite.waitForSelector('[data-testid="gm-beobachter"]', {
  state: "detached",
  timeout: 8000,
});
await gmSeite.waitForSelector('[data-testid="gm-tipp-1"]', { timeout: 8000 });
const tippKnoepfe = await gmSeite.evaluate(() => ({
  t1: !document.querySelector('[data-testid="gm-tipp-1"]')?.disabled,
  t2: !document.querySelector('[data-testid="gm-tipp-2"]')?.disabled,
  t3: !document.querySelector('[data-testid="gm-tipp-3"]')?.disabled,
}));
check(
  "GM-Spickzettel: Tipp 1 sendbar, Tipp 2/3 noch gesperrt",
  tippKnoepfe.t1 && !tippKnoepfe.t2 && !tippKnoepfe.t3,
  JSON.stringify(tippKnoepfe),
);
await schussSpickzettel("02_gm_spickzettel_tipps");

// Tipp 1 senden → Tipp-Kanone enthüllt den Text auf Bühne + Handy.
await gmSeite.click('[data-testid="gm-tipp-1"]');
const kanone = await screen
  .waitForSelector('[data-testid="tipp-kanone"]', { timeout: 8000 })
  .then((el) => el.textContent());
check("Tipp-Kanone zeigt Autoren-Tipp auf der Bühne", /Tipp 1:/.test(kanone ?? ""), kanone?.trim());
await phone.waitForSelector(".psst-umschlag", { timeout: 8000 });
await schuss(screen, "03_tipp1_buehne");
await schuss(phone, "04_tipp1_handy");
await schussSpickzettel("05_gm_tipp1_gesendet");

// ---------- 7) BEWEIS 3: Tresor/Leiter spielen Pool-Fragen ----------
// Kommando-Socket übernimmt zurück und spult zu R3 (Tresor) und R4 (Leiter).
const rueck = await gm.timeout(5000).emitWithAck("gm.takeover", { pin: String(gmPin) });
if (!rueck.ok) throw new Error(`gm.takeover: ${rueck.error}`);
if (!(await bisPhase("frage", "bananen-tresor"))) throw new Error("Tresor-Frage nicht erreicht");
await delay(1200);
await screen.waitForSelector('[data-testid="frage-kategorie"]', { timeout: 8000 });
await schuss(screen, "06_tresor_schaetz_pool");
if (!(await bisPhase("frage", "affenleiter"))) throw new Error("Leiter-Frage nicht erreicht");
await delay(1200);
await schuss(screen, "07_leiter_sortier_pool");

// Event-Log: welche Frage-IDs liefen in Tresor/Leiter? q_* = echte Pool-Frage.
await delay(2000); // Append-Kette ist async — kurz auf den Flush warten
const eventDatei = readdirSync(`${DATA_DIR}/events`).find((f) => f.endsWith(".jsonl"));
const events = readFileSync(`${DATA_DIR}/events/${eventDatei}`, "utf8")
  .trim()
  .split("\n")
  .map((z) => JSON.parse(z));
let minigame = null;
const jeMinigame = new Map();
for (const e of events) {
  if (e.type === "runde_gestartet") minigame = e.payload?.minigameId ?? null;
  if (e.type === "question_shown" && minigame !== null) {
    if (!jeMinigame.has(minigame)) jeMinigame.set(minigame, []);
    jeMinigame.get(minigame).push(e.questionId);
  }
}
for (const [mg, ids] of jeMinigame) log(`Event-Log ${mg}: ${ids.join(", ")}`);
const tresorIds = jeMinigame.get("bananen-tresor") ?? [];
const leiterIds = jeMinigame.get("affenleiter") ?? [];
check(
  "Tresor-Fragen kommen aus dem Pool (q_*)",
  tresorIds.length > 0 && tresorIds.every((id) => /^q_/.test(id)),
  tresorIds.join(", "),
);
check(
  "Leiter-Fragen kommen aus dem Pool (q_*)",
  leiterIds.length > 0 && leiterIds.every((id) => /^q_/.test(id)),
  leiterIds.join(", "),
);

// ---------- Fazit ----------
const kaputt = checks.filter((c) => !c.ok);
log(`${checks.length - kaputt.length}/${checks.length} Checks grün`);
await browser.close();
server.kill();
process.exit(kaputt.length === 0 ? 0 : 1);
