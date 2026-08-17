// W3-UI2-Beweis (Handy-Erlebnis 390×844): startet den gebauten Server, spielt
// mit 2 Playern (Zoe = Star, Ben = Nebenrolle) durch Join → Lobby → R1-Fragen
// und fast-forwarded bis zum Wett-Slider (alles-oder-banane). Belege:
//   - Screenshots mm_w3ui2_01…: Join-Steps, Lobby-Kopf, Idle-Einlage,
//     Bereit-/Antwort-Fortschritt, Münz-Lock-in, Count-up, Trost, Streak,
//     Wett-Slider mit Snap-Marken (+ Snap-Nachweis per Wert-Log).
//   - 2 WEBM-Videos (Playwright recordVideo, Session-Token-Rejoin):
//     Phasen-Übergangs-Choreo + Richtig-Moment mit Count-up & Streak.
//
//   node tools/screenshots/w3ui2-proof.mjs          → /opt/cursor/artifacts
//   OUT_DIR=/tmp/mm-w3 node tools/…/w3ui2-proof.mjs → Iterations-Läufe
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.W3UI2_PORT ?? 8097);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const VIDEO_TMP = "/tmp/mm-w3ui2-videos";
mkdirSync(OUT, { recursive: true });
rmSync(VIDEO_TMP, { recursive: true, force: true });
mkdirSync(VIDEO_TMP, { recursive: true });

const log = (t) => console.log(`[w3ui2] ${t}`);
const checks = [];
const check = (name, ok, detail = "") => {
  checks.push({ name, ok });
  log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
};

// ---------- 1) Server starten ----------
rmSync("/tmp/mm-w3ui2-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-w3ui2-data" },
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

// ---------- 2) Raum + GM-Steuerung ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
log(`Raum ${code}`);

const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm
  .timeout(5000)
  .emitWithAck("hello", { roomCode: code, role: "gm", gmPin: raum.gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `w3-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}
async function wartePhase(phase, timeoutMs = 15_000) {
  for (let i = 0; i < timeoutMs / 150; i++) {
    if (gmView?.phase === phase) return;
    await delay(150);
  }
  throw new Error(`Timeout: Phase ${phase} nicht erreicht (ist: ${gmView?.phase})`);
}
async function richtigIndex() {
  for (let i = 0; i < 40; i++) {
    const idx = gmView?.minigame?.view?.correctIndex;
    if (gmView?.phase === "frage" && typeof idx === "number") return idx;
    await delay(150);
  }
  return 0;
}

// ---------- 3) Browser + Join-Flow (Zoe mit Screenshots) ----------
const browser = await chromium.launch();
const VIEWPORT = { width: 390, height: 844 };
const spielerA = await browser.newPage({ viewport: VIEWPORT });
const spielerB = await browser.newPage({ viewport: VIEWPORT });

await spielerA.goto(`${URL_BASIS}/j/${code}`);
await spielerA.waitForSelector('[data-testid="raum-gefunden"]', { timeout: 8000 });
const schritt2Aktiv = await spielerA
  .locator(".join-schritt.aktiv .join-label")
  .textContent()
  .catch(() => null);
check("Join-Steps: Schritt 2 aktiv nach Raum-Check", schritt2Aktiv?.includes("Affe") === true);
await delay(350); // Einflug des Name/Affen-Blocks
await schuss(spielerA, "01_join_schritt2_einflug");
await spielerA.fill('input[placeholder="Dein Name"]', "Zoe");
await delay(250);
const schritt3Aktiv = await spielerA
  .locator(".join-schritt.aktiv .join-label")
  .textContent()
  .catch(() => null);
check("Join-Steps: Schritt 3 aktiv nach Namen", schritt3Aktiv?.includes("Los") === true);
await spielerA.click('button[aria-label="Nächster Affe"]');
await spielerA.click('button[aria-label="Nächster Affe"]');
await spielerA.click(".farb-reihe .farb-knopf:nth-child(3)");
await schuss(spielerA, "02_join_schritt3");
await spielerA.click("button.primaer");
await spielerA.waitForSelector(".spieler-liste", { timeout: 8000 });

await spielerB.goto(`${URL_BASIS}/j/${code}`);
await spielerB.waitForSelector('[data-testid="raum-gefunden"]', { timeout: 8000 });
await spielerB.fill('input[placeholder="Dein Name"]', "Ben");
for (let i = 0; i < 4; i++) await spielerB.click('button[aria-label="Nächster Affe"]');
await spielerB.click(".farb-reihe .farb-knopf:nth-child(5)");
await spielerB.click("button.primaer");
await spielerA.waitForFunction(
  () => document.querySelectorAll(".spieler-chip").length >= 2,
  undefined,
  { timeout: 8000 },
);
log("Beide Spieler in der Lobby");
await schuss(spielerA, "03_lobby_kopf");

// ---------- 4) Idle-Einlage abpassen (gähnt/wippt/schaut, 4–8 s Takt) ----------
let einlage = null;
for (let i = 0; i < 120 && !einlage; i++) {
  einlage = await spielerA.evaluate(() => {
    const p = document.querySelector(".eigene-puppe");
    if (!p) return null;
    for (const art of ["idle-gaehnt", "idle-wippt", "idle-schaut"]) {
      if (p.classList.contains(art)) return art;
    }
    return null;
  });
  if (!einlage) await delay(120);
}
check("Idle-Einlage im Warte-Screen", einlage !== null, einlage ?? "keine binnen 14 s");
if (einlage) await schuss(spielerA, `04_idle_einlage_${einlage.replace("idle-", "")}`);

// ---------- 5) Quick-Match starten, Erklärkarte-Fortschritt ----------
await gmCmd("settings.set", { modus: "quick", jokerAn: true });
await gmCmd("flow.next"); // Lobby → Intro
await wartePhase("intro");
await gmCmd("flow.next"); // Intro → Erklärkarte R1
await wartePhase("erklaerkarte");
await spielerB.click('button.primaer:has-text("Bereit")');
await spielerA.waitForSelector(".antwort-fortschritt", { timeout: 6000 });
const bereitText = await spielerA.locator(".antwort-fortschritt").textContent();
check("Erklärkarte: Bereit-Fortschritt", bereitText?.includes("1 von 2") === true, bereitText);
await delay(400); // Einflug-Animation (0,3 s) ausklingen lassen
await schuss(spielerA, "05_erklaerkarte_bereit_fortschritt");

// ---------- 6) VIDEO 1: Phasen-Übergangs-Choreo (Token-Rejoin mit Video) ----------
const token = await spielerA.evaluate((c) => localStorage.getItem(`mm:${c}`), code);
if (!token) throw new Error("Kein Session-Token für Zoe");
await spielerA.close();

async function videoSeite() {
  const ctx = await browser.newContext({
    viewport: VIEWPORT,
    recordVideo: { dir: VIDEO_TMP, size: VIEWPORT },
  });
  const page = await ctx.newPage();
  await page.addInitScript(([c, t]) => localStorage.setItem(`mm:${c}`, t), [code, token]);
  await page.goto(`${URL_BASIS}/j/${code}`);
  await page.waitForSelector(".spieler-kopf", { timeout: 8000 });
  return { ctx, page };
}

const v1 = await videoSeite();
await delay(1200); // Erklärkarte steht im Bild
await gmCmd("flow.next"); // Erklärkarte → Frage 1 (Choreo: Frage kommt von unten)
await v1.page.waitForSelector("#mg-host button:not([disabled])", { timeout: 8000 });
let richtig = await richtigIndex();
let optionen = await spielerB.locator("#mg-host button").count();
await spielerB.click(`#mg-host button >> nth=${(richtig + 1) % optionen}`);
await v1.page.waitForSelector(".antwort-fortschritt", { timeout: 6000 });
const antwortText = await v1.page.locator(".antwort-fortschritt").textContent();
check(
  "Frage: Antwort-Fortschritt",
  antwortText?.includes("1 von 2 haben geantwortet") === true,
  antwortText,
);
await delay(400); // Einflug-Animation (0,3 s) ausklingen lassen
await schuss(v1.page, "06_frage_antwort_fortschritt");
await delay(400);
await v1.page.click(`#mg-host button >> nth=${richtig}`); // Zoe: RICHTIG
await delay(450);
await schuss(v1.page, "07_muenz_lockin");
await wartePhase("aufloesung");
await delay(350);
await schuss(v1.page, "08_countup_mitte"); // Count-up läuft noch (600 ms)
const countMitte = await v1.page.locator("[data-zaehl-ziel]").textContent();
await delay(800);
const countFertig = await v1.page.locator("[data-zaehl-ziel]").textContent();
const ziel = await v1.page.locator("[data-zaehl-ziel]").getAttribute("data-zaehl-ziel");
check(
  "Count-up: Endwert = Delta",
  countFertig?.replace(/\D/g, "") ===
    String(Number(ziel).toLocaleString("de-DE")).replace(/\D/g, ""),
  `mitte="${countMitte}" fertig="${countFertig}" ziel=${ziel}`,
);
await schuss(v1.page, "09_richtig_fertig");
await schuss(spielerB, "10_falsch_trost");
const trost = await spielerB
  .locator(".trost")
  .textContent()
  .catch(() => null);
check("Falsch-Screen: Trost-Karte", trost !== null, trost ?? "");
await wartePhase("frage", 12_000); // Auto-Advance → Frage 2 (Choreo im Video)
await delay(700);
const video1 = v1.page.video();
await v1.ctx.close();
await video1.saveAs(`${OUT}/mm_w3ui2_video_phasen_uebergang.webm`);
log(`🎬 ${OUT}/mm_w3ui2_video_phasen_uebergang.webm`);

// ---------- 7) VIDEO 2: Richtig-Moment mit Count-up + Streak ×2 ----------
const v2 = await videoSeite();
await v2.page.waitForSelector("#mg-host button:not([disabled])", { timeout: 8000 });
richtig = await richtigIndex();
optionen = await spielerB.locator("#mg-host button").count();
await spielerB.click(`#mg-host button >> nth=${(richtig + 2) % optionen}`);
await delay(500);
await v2.page.click(`#mg-host button >> nth=${richtig}`); // Zoe: wieder RICHTIG
await wartePhase("aufloesung");
await delay(600);
const streakMoment = await v2.page
  .locator(".streak-moment")
  .textContent()
  .catch(() => null);
const streakBadge = await v2.page
  .locator(".streak-badge")
  .textContent()
  .catch(() => null);
check("Streak-Moment in der Auflösung", streakMoment?.includes("×2") === true, streakMoment ?? "");
check("Streak-Badge im Kopf", streakBadge?.includes("×2") === true, streakBadge ?? "");
await schuss(v2.page, "11_streak_countup");
await delay(1800);
const video2 = v2.page.video();
await v2.ctx.close();
await video2.saveAs(`${OUT}/mm_w3ui2_video_richtig_countup.webm`);
log(`🎬 ${OUT}/mm_w3ui2_video_richtig_countup.webm`);

// ---------- 8) Fast-forward bis zum Wett-Slider (alles-oder-banane) ----------
// Zoe VOR der Wett-Runde reich machen (GM-Bonus): die Wett-Range friert bei
// Rundenstart ein (balancesVorRunde) und max = 50 % des Kontos — erst eine
// breite Range macht den Viertel-Magneten sichtbar.
const zoeId = (gmView?.players ?? []).find((p) => p.name === "Zoe")?.id;
if (zoeId) {
  await gmCmd("score.adjust", {
    playerId: zoeId,
    delta: 3000,
    grund: "W3-Beweis: Wett-Range",
    override: true, // Soft-Cap bewusst übersteuern (nur Beweis-Skript)
  });
}
const ctxA2 = await browser.newContext({ viewport: VIEWPORT });
const spielerA2 = await ctxA2.newPage();
await spielerA2.addInitScript(([c, t]) => localStorage.setItem(`mm:${c}`, t), [code, token]);
await spielerA2.goto(`${URL_BASIS}/j/${code}`);
await spielerA2.waitForSelector(".spieler-kopf", { timeout: 8000 });

let angekommen = false;
for (let i = 0; i < 120 && !angekommen; i++) {
  const phase = gmView?.phase;
  const mgId = gmView?.abschnitt?.minigameId ?? gmView?.erklaerkarte?.minigameId ?? "";
  if (phase === "frage" && gmView?.minigame?.id === "alles-oder-banane") {
    angekommen = true;
    break;
  }
  if (phase === "frage")
    await gmCmd("game.skip"); // ganze Runde abschließen
  else if (phase === "erklaerkarte" && mgId === "alles-oder-banane") await gmCmd("flow.next");
  else if (phase === "erklaerkarte")
    await gmCmd("game.skip"); // Runde überspringen
  else if (phase === "kategorie-wahl" || phase === "zwischenstand" || phase === "rad") {
    await gmCmd("flow.next");
  }
  await delay(700);
}
check("Fast-forward zu alles-oder-banane", angekommen, `Phase=${gmView?.phase}`);

// ---------- 9) Wett-Slider: Snap-Marken + magnetischer Viertel-Snap ----------
if (angekommen) {
  await spielerA2.waitForSelector(".aob-slider", { timeout: 8000 });
  await schuss(spielerA2, "12_wett_slider_marken");
  const slider = spielerA2.locator(".aob-slider");
  const box = await slider.boundingBox();
  const min = Number(await slider.getAttribute("min"));
  const max = Number(await slider.getAttribute("max"));
  const step = Number(await slider.getAttribute("step")) || 50;
  // Drag auf ~46 % der Breite: roh läge der Wert NEBEN der Mitte, der
  // magnetische Snap (Toleranz > step, nur beim Ziehen) muss ihn auf den
  // 50 %-Punkt ziehen — gleiche Rundung wie snapWert in handy-fx.ts.
  const zielX = box.x + box.width * 0.46;
  const y = box.y + box.height / 2;
  await spielerA2.mouse.move(box.x + 4, y);
  await spielerA2.mouse.down();
  await spielerA2.mouse.move(zielX, y, { steps: 14 });
  await spielerA2.mouse.up();
  const wert = Number(await slider.inputValue());
  const spanne = max - min;
  const mitte = min + Math.round((spanne * 0.5) / step) * step;
  check(
    "Wett-Slider: Snap auf 50 %-Punkt",
    wert === mitte,
    `wert=${wert} mitte=${mitte} (min=${min}, max=${max}, step=${step})`,
  );
  const fuellung = await slider.evaluate((el) => el.style.getPropertyValue("--aob-fuellung"));
  check(
    "Wett-Slider: Gold-Füllstand gesetzt",
    fuellung.endsWith("%"),
    `--aob-fuellung=${fuellung}`,
  );
  await delay(300);
  await schuss(spielerA2, "13_wett_slider_snap");
}

// ---------- Fazit ----------
const rot = checks.filter((c) => !c.ok);
log(`Fertig: ${checks.length - rot.length}/${checks.length} Checks grün`);
await browser.close();
gm.close();
opener.close();
server.kill();
process.exit(rot.length === 0 ? 0 : 1);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_w3ui2_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
