// Fix-Welle-2A-Proof (Playwright): verifiziert die Show-Dramaturgie- und
// Layout-Fixes end-to-end gegen den GEBAUTEN Server mit Server-Bots:
//
//   1. Auflösungs-Timeline (P1-Spoiler-Fix): Screenshot bei +0,5 s (Wand
//      zappt NEUTRAL — keine Korrekt-Markierung/Chips) und +3 s (alles
//      gleichzeitig aufgedeckt).
//   2. AOB ohne Dead-Air (P1-Auto-GM-Fix): Phasen-Timing der Alles-oder-
//      Banane-Sub-Phasen wird live gemessen — Setzen ≈12 s, Reveal ≈6 s
//      TROTZ eingeschaltetem Auto-GM (vorher: 16 s Dead-Air pro Frage).
//   3. Layout-Guards: 1280×800 (Blitz-DJ Optionen C/D + Kokosnuss-Uhr
//      podium-sicher), 1024×768 (Erklär-Demo über der Spielerleiste),
//      1920×1080 (Frage ≥40 px — Sofa-Lesbarkeit).
//
//   node tools/screenshots/fix2a-proof.mjs → /opt/cursor/artifacts/mm_fix2a_*
//
// Voraussetzungen: npm run build, Playwright-Chromium installiert.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8093);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[fix2a] ${t}`);
const ergebnisse = { checks: [], aobTiming: null };
let fehlgeschlagen = 0;

function check(name, ok, detail = "") {
  ergebnisse.checks.push({ name, ok, detail });
  if (!ok) fehlgeschlagen += 1;
  log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
}

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-fix2a-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-fix2a-data" },
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

// ---------- 2) Raum + GM-Socket + 3 Server-Bots ----------
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
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `fix2a-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

for (let i = 0; i < 3; i++) await gmCmd("bot.add");

// ---------- 3) Drei Screens: 800p-Beamer, 768p-iPad, 1080p-Sofa-TV ----------
const browser = await chromium.launch();

// Passiver ECHTER Spieler (drückt nie „Bereit", antwortet nie): verhindert
// das Alle-bereit-Auto-Start-Race der Bots — Erklärkarten bleiben stehen,
// bis WIR flow.next schicken (bzw. 12 s ablaufen). Fragen laufen ihren Timer.
const passiv = await browser.newPage({ viewport: { width: 390, height: 844 } });
await passiv.goto(`${URL_BASIS}/j/${code}`);
await passiv.fill('input[placeholder="Dein Name"]', "Zoe");
await passiv.click(".farb-reihe .farb-knopf:nth-child(3)");
await delay(300);
await passiv.click("button.primaer");
await passiv.waitForSelector(".spieler-liste", { timeout: 8000 });
log("Passiver Spieler Zoe im Raum (verhindert Bereit-Races)");
async function screenSeite(width, height) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
  await page.goto(`${URL_BASIS}/screen`);
  await page.waitForSelector(".studio", { timeout: 10_000 });
  return page;
}
const s800 = await screenSeite(1280, 800);
const s768 = await screenSeite(1024, 768);
const s1080 = await screenSeite(1920, 1080);
log("3 Screens verbunden (1280×800, 1024×768, 1920×1080)");

async function schuss(page, name) {
  const pfad = `${OUT}/mm_fix2a_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

/** Podium-sicherer Geometrie-Check: Selektoren müssen KOMPLETT über der
 *  Podium-Leiste liegen (studio-mitte clippt bei Überlauf genau dort). */
async function geometrie(page, selektoren) {
  return await page.evaluate((sels) => {
    const mitte = document.querySelector(".studio-mitte");
    const podien = document.querySelector(".studio-podien");
    if (!mitte) return { ok: false, fehler: ["keine .studio-mitte"] };
    const mitteBox = mitte.getBoundingClientRect();
    const podienTop = podien ? podien.getBoundingClientRect().top : window.innerHeight;
    const grenze = Math.min(mitteBox.bottom, podienTop) + 1;
    const fehler = [];
    for (const eintrag of sels) {
      const sel = typeof eintrag === "string" ? eintrag : eintrag.sel;
      const mindestens = typeof eintrag === "string" ? 1 : (eintrag.mindestens ?? 1);
      const alle = [...document.querySelectorAll(sel)];
      if (alle.length < mindestens) {
        fehler.push(`${sel}: nur ${alle.length}/${mindestens} vorhanden`);
        continue;
      }
      for (const el of alle) {
        const b = el.getBoundingClientRect();
        if (b.height < 8) fehler.push(`${sel}: kollabiert (${Math.round(b.height)}px hoch)`);
        if (b.bottom > grenze) {
          fehler.push(
            `${sel}: abgeschnitten (bottom ${Math.round(b.bottom)} > ${Math.round(grenze)})`,
          );
        }
        if (b.top < mitteBox.top - 1) fehler.push(`${sel}: oben aus der Bühne gerutscht`);
      }
    }
    return {
      ok: fehler.length === 0,
      fehler,
      podienTop: Math.round(podienTop),
      mitteBottom: Math.round(mitteBox.bottom),
    };
  }, selektoren);
}

async function fontPx(page, sel) {
  return await page.evaluate((s) => {
    const el = document.querySelector(s);
    return el ? Math.round(parseFloat(getComputedStyle(el).fontSize) * 10) / 10 : null;
  }, sel);
}

async function wartePhase(page, phase, timeout = 20_000) {
  await page.waitForFunction((p) => document.querySelector(".studio")?.dataset.phase === p, phase, {
    timeout,
  });
}

// ---------- 4) Match: Marathon ohne Rad/Wahl (Blitz-DJ liegt im Plan) ----------
await gmCmd("settings.set", {
  modus: "marathon",
  rad: "aus",
  kategorienWahl: "aus",
  autoGm: false,
});
await gmCmd("flow.next"); // Lobby → Intro
await delay(500);
await gmCmd("flow.next"); // Intro → Erklärkarte R1 (bananen-basics)
await wartePhase(s768, "erklaerkarte");

// ---------- 5) Guard 1024×768: Erklär-Demo über der Spielerleiste ----------
await s768.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 8000 });
await delay(2500); // mitten in Beat 2 (Blase + Requisit sichtbar)
const g768 = await geometrie(s768, [".ed-buehne", ".runden-karte", ".bereit-punkte"]);
check("768p: Erklär-Demo + Karte komplett über der Podium-Leiste", g768.ok, g768.fehler.join("; "));
await schuss(s768, "768_erklaerdemo");

// ---------- 6) Frage R1 (bananen-basics): 1080p-Typo + Auflösungs-Timeline ----------
await gmCmd("flow.next"); // Erklärkarte → Frage 1
await s1080.waitForSelector(".bb-frage", { timeout: 10_000 });
await delay(600);
const frage1080 = await fontPx(s1080, ".bb-frage");
const antwort1080 = await fontPx(s1080, ".bb-liane");
const podiumName1080 = await fontPx(s1080, ".podium-name");
check(
  "1080p: Frage ≥40px (Sofa-Lesbarkeit)",
  frage1080 !== null && frage1080 >= 40,
  `.bb-frage = ${frage1080}px, .bb-liane = ${antwort1080}px, .podium-name = ${podiumName1080}px`,
);
ergebnisse.typo1080 = { frage: frage1080, antwort: antwort1080, podiumName: podiumName1080 };
await schuss(s1080, "1080_frage_typo");

// Auflösungs-Timeline: Bots antworten selbst → Phase kippt automatisch.
await wartePhase(s1080, "aufloesung", 45_000);
const t0 = Date.now();
await delay(Math.max(0, 500 - (Date.now() - t0)));
const neutral = await s1080.evaluate(() => ({
  spannung: document.querySelector(".led-wand.spannung") !== null,
  korrektMarker: document.querySelectorAll(".bb-liane.traegt").length,
  chips: document.querySelectorAll(".spieler-chip").length,
}));
check(
  "Timeline +0,5s: Wand NEUTRAL (zappt, keine Korrekt-Markierung, keine Chips)",
  neutral.spannung && neutral.korrektMarker === 0 && neutral.chips === 0,
  JSON.stringify(neutral),
);
await schuss(s1080, "timeline_plus0s5_neutral");
await delay(Math.max(0, 3000 - (Date.now() - t0)));
const aufgedeckt = await s1080.evaluate(() => ({
  spannung: document.querySelector(".led-wand.spannung") !== null,
  korrektMarker: document.querySelectorAll(".bb-liane.traegt").length,
  chips: document.querySelectorAll(".spieler-chip").length,
}));
check(
  "Timeline +3s: alles gleichzeitig AUFGEDECKT (Marker + Chips, kein Zappen)",
  !aufgedeckt.spannung && aufgedeckt.korrektMarker === 1 && aufgedeckt.chips >= 2,
  JSON.stringify(aufgedeckt),
);
await schuss(s1080, "timeline_plus3s_aufgedeckt");

// ---------- 7) Skip-Kette: gezielt zu Kokosnuss-Uhr → Blitz-DJ → AOB ----------
/** Bis zur Erklärkarte des Ziel-Formats skippen, dann Frage starten. */
async function bisZurFrage(zielId, timeoutMs = 120_000) {
  const start = Date.now();
  let zuletztGeskippt = "";
  while (Date.now() - start < timeoutMs) {
    const phase = gmView?.phase;
    if (phase === "erklaerkarte") {
      const id = gmView?.erklaerkarte?.minigameId ?? "";
      if (id === zielId) {
        await gmCmd("flow.next"); // Karte → Frage
        return true;
      }
      if (id !== zuletztGeskippt) log(`… skippe ${id}`);
      zuletztGeskippt = id;
      await gmCmd("game.skip");
    } else if (phase === "frage") {
      const id = gmView?.minigame?.id ?? "";
      if (id === zielId) return true; // Bots waren schneller (bereit-Race)
      await gmCmd("game.skip"); // ganze Runde überspringen
    } else if (phase === "aufloesung") {
      await gmCmd("game.skip");
    } else if (phase === "siegerehrung" || phase === "ende") {
      return false;
    } else {
      await gmCmd("flow.next"); // zwischenstand & Co.
    }
    await delay(250);
  }
  return false;
}

// ---------- 8) Guard 1280×800: Kokosnuss-Uhr (alle 4 Optionen + Eis-Reihe) ----------
if (!(await bisZurFrage("kokosnuss-uhr"))) throw new Error("kokosnuss-uhr nicht erreicht");
await s800.waitForSelector(".ku-option", { timeout: 10_000 });
await delay(700);
const gKu = await geometrie(s800, [
  { sel: ".ku-option", mindestens: 4 },
  ".ku-frage",
  ".ku-kopf",
  ".ku-eis-reihe",
]);
check(
  "800p: Kokosnuss-Uhr — Frage, 4 Optionen + Eis-Reihe podium-sicher",
  gKu.ok,
  gKu.fehler.join("; "),
);
const kuEllipsis = await s800.evaluate(() => {
  const el = document.querySelector(".ku-option");
  const stil = el ? getComputedStyle(el) : null;
  return el !== null && stil.webkitLineClamp === "2" && el.title.length > 0;
});
check("800p: Kokosnuss-Optionen mit 2-Zeilen-Ellipsis + title-Volltext", kuEllipsis);
await schuss(s800, "800_kokosnussuhr");
const kuFrage1080 = await fontPx(s1080, ".ku-frage");
check(
  "1080p: Kokosnuss-Frage ≥40px",
  kuFrage1080 !== null && kuFrage1080 >= 40,
  `${kuFrage1080}px`,
);
const gKu1080 = await geometrie(s1080, [
  { sel: ".ku-option", mindestens: 4 },
  ".ku-frage",
  ".ku-eis-reihe",
  ".led-wand",
]);
check(
  "1080p: Kokosnuss-Uhr — Wand + Optionen + Eis-Reihe passen KOMPLETT",
  gKu1080.ok,
  gKu1080.fehler.join("; "),
);
await schuss(s1080, "1080_kokosnussuhr");

// ---------- 9) Guard 1280×800: Blitz-DJ (Treppe + Optionen C/D sichtbar) ----------
if (!(await bisZurFrage("song-snippet"))) throw new Error("song-snippet nicht erreicht");
await s800.waitForSelector(".ss-option", { timeout: 15_000 });
await delay(800);
const gSs = await geometrie(s800, [
  { sel: ".ss-option", mindestens: 4 },
  ".ss-treppe",
  ".ss-buehne",
]);
check(
  "800p: Blitz-DJ — Treppe, Bühne + alle 4 Optionen podium-sicher",
  gSs.ok,
  gSs.fehler.join("; "),
);
const ssSperren = await s800.evaluate(() => {
  const el = document.querySelector(".ss-sperren");
  if (!el) return { da: false };
  const grenze = document.querySelector(".studio-podien")?.getBoundingClientRect().top ?? 1e9;
  return { da: true, ok: el.getBoundingClientRect().bottom <= grenze + 1 };
});
if (ssSperren.da) check("800p: Blitz-DJ Gesperrt-Zeile über der Podium-Leiste", ssSperren.ok);
await schuss(s800, "800_blitzdj");

// ---------- 10) AOB-Timing (P1 Auto-GM-Fix): Sub-Phasen live messen ----------
await gmCmd("autogm.set", { enabled: true }); // Heuristik MUSS an sein für den Beweis
if (!(await bisZurFrage("alles-oder-banane"))) throw new Error("alles-oder-banane nicht erreicht");
log("AOB läuft — messe Sub-Phasen-Timing (Auto-GM AN) …");
const timing = [];
let aktuelleSub = null;
let subSeit = Date.now();
let revealShot = false;
const messStart = Date.now();
while (Date.now() - messStart < 90_000) {
  const sub = gmView?.minigame?.view?.phase ?? null;
  const enginePhase = gmView?.phase;
  if (sub !== aktuelleSub) {
    if (aktuelleSub !== null) {
      timing.push({ phase: aktuelleSub, dauerMs: Date.now() - subSeit });
      log(`  AOB ${aktuelleSub}: ${((Date.now() - subSeit) / 1000).toFixed(1)} s`);
    }
    aktuelleSub = sub;
    subSeit = Date.now();
  }
  if (sub === "reveal" && !revealShot && Date.now() - subSeit > 1200) {
    revealShot = true;
    await schuss(s800, "800_aob_reveal");
  }
  if (enginePhase === "aufloesung" || enginePhase === "zwischenstand") break;
  await delay(200);
}
ergebnisse.aobTiming = timing;
const setzen = timing.find((t) => t.phase === "setzen");
const reveal = timing.find((t) => t.phase === "reveal");
check(
  "AOB: Setzen-Fenster ohne +10s-Misfire (≈12s, nicht 22s+)",
  setzen !== undefined && setzen.dauerMs < 15_000,
  setzen ? `${(setzen.dauerMs / 1000).toFixed(1)} s` : "nicht gemessen",
);
check(
  "AOB: Einsatz-Reveal ohne Dead-Air (≈6s, nicht 16s) TROTZ Auto-GM",
  reveal !== undefined && reveal.dauerMs < 9_500,
  reveal ? `${(reveal.dauerMs / 1000).toFixed(1)} s` : "nicht gemessen",
);

// ---------- 11) Bilanz ----------
writeFileSync(`${OUT}/mm_fix2a_results.json`, JSON.stringify(ergebnisse, null, 2));
log(`Ergebnis-Log: ${OUT}/mm_fix2a_results.json`);
log(
  fehlgeschlagen === 0
    ? `ALLE ${ergebnisse.checks.length} CHECKS GRÜN`
    : `${fehlgeschlagen}/${ergebnisse.checks.length} Checks ROT`,
);

await browser.close();
gm.close();
opener.close();
server.kill();
process.exit(fehlgeschlagen === 0 ? 0 : 1);
