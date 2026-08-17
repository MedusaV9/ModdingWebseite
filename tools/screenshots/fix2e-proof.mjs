// Fix-Welle-2E-Proof (Playwright): verifiziert die 8 Fixes end-to-end gegen
// den GEBAUTEN Server:
//
//   A) Join-Härtung (P2, Eval 6): Code ZUERST (kein Namensfeld ohne Code),
//      „Raum gefunden ✓", „Code ändern", doppelter Name → „Name schon
//      vergeben"-Hinweis mit Session-Restore-Tipp.
//   B) GM-Cockpit (P1+P2): Flüster-Knopf aktiviert sich BEIM Tippen (ohne
//      erneuten Zeilen-Tap), Anker-Chips ≥44px + Sprung-Navigation, Pause in
//      der Lobby disabled, 2-Tap-Bestätigung („Wirklich beenden?" verfällt
//      nach 3 s ohne Bestätigung).
//   E) Frage-Layout (P2, Eval 2): alle 4 Antworten inkl. D KOMPLETT im
//      390×844-Viewport, Antwort-Marker-Kontrast ≥3:1 (vorher 1,51:1).
//   C) Terminologie + Belohnung (P2): Siegerehrung sagt „+X AT", Match-
//      Ausbeute-Sheet erscheint — auch NACH RELOAD zur Siegerehrung (Recap-
//      Fix). Danach P1: Profil-Stats aktualisieren sich AUTOMATISCH ≤2 min
//      nach Match-Ende — OHNE manuellen Trigger.
//   D) Meta-Landing (P2): Willkommens-Paket-Karte, Kauf-Moment („Gekauft!" +
//      „Gleich anlegen!"-CTA), Level-Fortschritts-Balken, Shop-Chips ≥44px,
//      „Tages-Aufgaben"/„Saison-Aufgaben" statt Quests.
//
//   node tools/screenshots/fix2e-proof.mjs → /opt/cursor/artifacts/mm_fix2e_*
//
// Voraussetzungen: npm run build, Playwright-Chromium installiert.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8094);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[fix2e] ${t}`);
const ergebnisse = { checks: [], touchZiele: [], kontraste: [], statsTiming: null };
let fehlgeschlagen = 0;

function check(name, ok, detail = "") {
  ergebnisse.checks.push({ name, ok, detail });
  if (!ok) fehlgeschlagen += 1;
  log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
}

async function schuss(page, name) {
  const pfad = `${OUT}/mm_fix2e_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-fix2e-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-fix2e-data" },
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

// ---------- 2) Raum + Profil (Geräte-Token → Willkommens-Paket) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
log(`Raum ${code}`);

const DEVICE = "d_proof-fix2e";
const profilAntwort = await fetch(`${URL_BASIS}/api/meta/profile`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ name: "Anna", avatar: "schimpanse.gelb", deviceToken: DEVICE }),
});
const { profil } = await profilAntwort.json();
const profileId = profil.profileId;
log(`Profil ${profileId} (Anna) angelegt — Willkommens-Paket inklusive`);

const browser = await chromium.launch();

// ---------- 3) Anna (Profil-gebunden) joint via /j/CODE — URL trägt den Code,
//              damit der spätere RELOAD zur Siegerehrung auto-rejoint. ----------
const annaCtx = await browser.newContext({ viewport: { width: 390, height: 844 } });
await annaCtx.addInitScript((d) => localStorage.setItem("mm:device", d), DEVICE);
const anna = await annaCtx.newPage();
await anna.goto(`${URL_BASIS}/j/${code}`);
await anna.waitForSelector(".profil-kachel", { timeout: 8000 });
await anna.click(".profil-kachel");
await anna.waitForSelector("text=gewählt", { timeout: 5000 });
await delay(400);
await anna.click("button.primaer");
await anna.waitForSelector(".spieler-liste", { timeout: 8000 });
log("Anna (Profil-gebunden) im Raum");

// ==================== A) JOIN-HÄRTUNG (Eval 6) — zweites Gerät ====================
const dupCtx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const dup = await dupCtx.newPage();
await dup.goto(`${URL_BASIS}/player`);
await dup.waitForSelector("#join-code", { timeout: 8000 });

// A1: Code ZUERST — ohne gültigen Code KEIN Namensfeld.
const namensfeldVorher = await dup.locator('input[placeholder="Dein Name"]').count();
check("Join: OHNE Code kein Name/Avatar-Feld (Code zuerst)", namensfeldVorher === 0);
await schuss(dup, "join_1_code_zuerst");

// A2: falscher Code → „nicht gefunden".
await dup.fill("#join-code", "XXXX");
await dup.waitForSelector('[data-testid="raum-fehlt"]', { timeout: 5000 });
check("Join: falscher Code → „Raum nicht gefunden'-Hinweis", true);
await schuss(dup, "join_2_raum_fehlt");

// A3: echter Code → „Raum gefunden ✓" + Formular + „Code ändern"-Knopf ≥44px.
await dup.fill("#join-code", "");
await dup.fill("#join-code", code);
await dup.waitForSelector('[data-testid="raum-gefunden"]', { timeout: 5000 });
const codeAendern = await dup.locator('[data-testid="code-aendern"]').count();
const namensfeldNachher = await dup.locator('input[placeholder="Dein Name"]').count();
check(
  "Join: echter Code → ✓ Raum gefunden + Namensfeld + Code-ändern-Knopf",
  codeAendern === 1 && namensfeldNachher === 1,
);
const boxAendern = await dup.locator('[data-testid="code-aendern"]').boundingBox();
ergebnisse.touchZiele.push({ label: "Code ändern (Join)", h: Math.round(boxAendern?.height ?? 0) });
check(
  "Touch: Code-ändern-Knopf ≥44px",
  boxAendern !== null && boxAendern.height >= 44,
  `${Math.round(boxAendern?.height ?? 0)}px`,
);
const boxProfil = await dup.locator('[data-testid="anderes-profil"]').boundingBox();
ergebnisse.touchZiele.push({
  label: "Anderes Profil laden (Join)",
  h: Math.round(boxProfil?.height ?? 0),
});
check(
  "Touch: „Anderes Profil laden' ≥44px",
  boxProfil !== null && boxProfil.height >= 44,
  `${Math.round(boxProfil?.height ?? 0)}px`,
);
await schuss(dup, "join_3_raum_gefunden");

// A4: „Code ändern" führt zurück zum Code-Schritt.
await dup.click('[data-testid="code-aendern"]');
await delay(300);
check(
  "Join: Code ändern → zurück zum Code-Schritt",
  (await dup.locator('input[placeholder="Dein Name"]').count()) === 0,
);
await dup.fill("#join-code", code);
await dup.waitForSelector('[data-testid="raum-gefunden"]', { timeout: 5000 });

// A5: Doppelter Name „Anna" → name-vergeben-Hinweis („bist du das?").
await dup.fill('input[placeholder="Dein Name"]', "Anna");
await delay(200);
await dup.click("button.primaer");
await dup.waitForSelector('[data-testid="name-vergeben"]', { timeout: 8000 });
check("Join: doppelter Name abgelehnt → „bist du das?'-Hinweis (Session-Restore)", true);
await schuss(dup, "join_4_name_vergeben");
await dup.fill('input[placeholder="Dein Name"]', "Bodo");
await delay(200);
await dup.click("button.primaer");
await dup.waitForSelector(".spieler-liste", { timeout: 8000 });
check("Join: anderer Name (Bodo) → drin", true);

// ==================== B) GM-COCKPIT (P1 Flüstern + P2 Layout/Sicherheit) ====================
const gmPage = await browser.newPage({ viewport: { width: 900, height: 1200 } });
await gmPage.goto(`${URL_BASIS}/gm`);
await gmPage.fill("#gm-code", code);
await gmPage.fill("#gm-pin", raum.gmPin);
await gmPage.click("button.primaer");
await gmPage.waitForSelector('[data-testid="gm-anker"]', { timeout: 8000 });

// B1: Anker-Chips (5 Zonen) + ≥44px.
const anker = await gmPage.evaluate(() => {
  const chips = [...document.querySelectorAll('[data-testid="gm-anker"] button')];
  return chips.map((c) => ({
    text: c.textContent.trim(),
    h: Math.round(c.getBoundingClientRect().height),
  }));
});
check(
  "GM: 5 Anker-Chips (Regie|Spieler|Fragen|Show|Log), alle ≥44px",
  anker.length === 5 && anker.every((a) => a.h >= 44),
  JSON.stringify(anker),
);
ergebnisse.touchZiele.push(...anker.map((a) => ({ label: `GM-Anker ${a.text}`, h: a.h })));

// B2: Sprung-Navigation: Log-Chip → Log-Zone im Viewport.
await gmPage.click('[data-testid="gm-anker-log"]');
await delay(900);
const logSichtbar = await gmPage.evaluate(() => {
  const b = document.getElementById("gm-zone-log").getBoundingClientRect();
  return b.top >= -1 && b.top < window.innerHeight;
});
check("GM: Anker-Chip springt zur Log-Zone (statt 2400px-Scroll)", logSichtbar);
await gmPage.click('[data-testid="gm-anker-spieler"]');
await delay(900);

// B3: P1 Flüster-Fix — Zeile antippen, TIPPEN, Knopf MUSS sofort aktiv werden.
await gmPage.locator("#gm-zone-spieler strong", { hasText: "Anna" }).click();
await delay(300);
const vorher = await gmPage.evaluate(
  () => document.querySelector('[data-testid="gm-whisper-senden"]').disabled,
);
await gmPage.type('[data-testid="gm-whisper-input"]', "Nimm die Banane!", { delay: 25 });
const nachher = await gmPage.evaluate(
  () => document.querySelector('[data-testid="gm-whisper-senden"]').disabled,
);
check(
  "GM P1: Flüster-Knopf aktiviert sich BEIM Tippen (kein erneuter Zeilen-Tap)",
  vorher === true && nachher === false,
  `disabled vorher=${vorher}, nach Eingabe=${nachher}`,
);
await schuss(gmPage, "gm_1_fluester_aktiv");

// B4: Pause in der Lobby ist DISABLED (statt nachträglich abgelehnt).
const pauseLobby = await gmPage.evaluate(() => {
  const knopf = [...document.querySelectorAll("button")].find((b) =>
    b.textContent.includes("Pause"),
  );
  return knopf ? knopf.disabled : null;
});
check("GM: Pause in der Lobby disabled (statt Ablehnung im Nachhinein)", pauseLobby === true);

// ---------- Match starten + Skip-Orchestrierung über GM-Socket ----------
const gmSocket = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gmSocket.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gmSocket
  .timeout(5000)
  .emitWithAck("hello", { roomCode: code, role: "gm", gmPin: raum.gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
await gmSocket.timeout(5000).emitWithAck("gm.takeover", { pin: raum.gmPin });
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gmSocket
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `fix2e-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}
await gmCmd("settings.set", {
  modus: "marathon",
  rad: "aus",
  kategorienWahl: "aus",
  autoGm: false,
});
for (let i = 0; i < 2; i++) await gmCmd("bot.add");
await gmCmd("flow.next"); // Lobby → Intro
await delay(500);
await gmCmd("flow.next"); // Intro → Erklärkarte R1

// ==================== E) FRAGE-LAYOUT + MARKER-KONTRAST (Eval 2) ====================
/** Bis zur Frage des Ziel-Formats skippen (Muster fix2a-proof). */
async function bisZurFrage(zielId, timeoutMs = 120_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const phase = gmView?.phase;
    if (phase === "erklaerkarte") {
      if ((gmView?.erklaerkarte?.minigameId ?? "") === zielId) {
        await gmCmd("flow.next");
        return true;
      }
      await gmCmd("game.skip");
    } else if (phase === "frage") {
      if ((gmView?.minigame?.id ?? "") === zielId) return true;
      await gmCmd("game.skip");
    } else if (phase === "aufloesung") {
      await gmCmd("game.skip");
    } else if (phase === "siegerehrung" || phase === "ende") {
      return false;
    } else {
      await gmCmd("flow.next");
    }
    await delay(250);
  }
  return false;
}

if (!(await bisZurFrage("vier-lianen"))) throw new Error("vier-lianen nicht erreicht");
await anna.waitForSelector(".vl-button", { timeout: 10_000 });
await delay(600);

// E1: alle 4 Antworten (inkl. D) KOMPLETT im 390×844-Viewport.
const layout = await anna.evaluate(() => {
  const knoepfe = [...document.querySelectorAll(".vl-button")];
  return {
    anzahl: knoepfe.length,
    boxes: knoepfe.map((k) => {
      const b = k.getBoundingClientRect();
      return { top: Math.round(b.top), bottom: Math.round(b.bottom) };
    }),
    innerHeight: window.innerHeight,
  };
});
check(
  "Frage-Layout: ALLE 4 Antworten (auch D) komplett im 390×844-Bild",
  layout.anzahl === 4 &&
    layout.boxes.every((b) => b.bottom <= layout.innerHeight + 1 && b.top >= 0),
  JSON.stringify(layout),
);

// E2: Antwort-Marker-Kontrast ≥3:1 (Chip-Hintergrund vs. Schriftfarbe).
const kontraste = await anna.evaluate(() => {
  const lum = (rgb) => {
    const [r, g, b] = rgb.map((v) => {
      const c = v / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const parse = (s) => (s.match(/\d+(\.\d+)?/g) ?? ["0", "0", "0"]).slice(0, 3).map(Number);
  return [...document.querySelectorAll(".vl-button .vl-deko")].map((el) => {
    const stil = getComputedStyle(el);
    const l1 = lum(parse(stil.backgroundColor));
    const l2 = lum(parse(stil.color));
    return {
      marker: el.textContent.trim().slice(0, 1),
      ratio: Math.round(((Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)) * 100) / 100,
    };
  });
});
ergebnisse.kontraste = kontraste;
check(
  "Antwort-Marker: Kontrast ≥3:1 für alle 4 (vorher 1,51:1)",
  kontraste.length === 4 && kontraste.every((k) => k.ratio >= 3),
  kontraste.map((k) => `${k.marker}=${k.ratio}:1`).join(" · "),
);
await schuss(anna, "frage_5_layout_marker");

// ==================== B5) 2-TAP-BESTÄTIGUNG am GM-PAGE-Cockpit ====================
// Die GM-Seite ist seit dem Socket-Takeover Beobachter → per PIN zurückholen.
if ((await gmPage.locator('[data-testid="gm-beobachter"]').count()) > 0) {
  await gmPage.fill('[data-testid="gm-beobachter"] input', raum.gmPin);
  await gmPage.click("text=Cockpit übernehmen");
  await delay(600);
}
await gmPage.click('[data-testid="gm-ende"]');
await delay(300);
const fragt = await gmPage.locator('[data-testid="gm-ende"]').textContent();
check(
  "GM: „Match beenden' fragt erst „Wirklich beenden?' (2-Tap)",
  fragt.includes("Wirklich beenden?"),
  fragt.trim(),
);
await schuss(gmPage, "gm_2_wirklich_beenden");
await delay(3400); // 3-s-Fenster verfallen lassen — NICHT bestätigt.
const nachFenster = await gmPage.locator('[data-testid="gm-ende"]').textContent();
const nochNichtZuEnde = gmView?.phase !== "siegerehrung" && gmView?.phase !== "ende";
check(
  "GM: 2-Tap verfällt nach 3s ohne Bestätigung (Match läuft weiter)",
  !nachFenster.includes("Wirklich") && nochNichtZuEnde,
  `Knopf="${nachFenster.trim()}", phase=${gmView?.phase}`,
);

// ==================== C) MATCH-ENDE: AT-Terminologie + Recap + Auto-Stats ====================
// Jetzt WIRKLICH beenden: 2× tippen innerhalb des Fensters.
await gmPage.click('[data-testid="gm-ende"]');
await delay(250);
await gmPage.click('[data-testid="gm-ende"]');
const tMatchEnde = Date.now();
await anna.waitForSelector("text=Platz", { timeout: 10_000 });
log("Match beendet → Siegerehrung");

// C1: Handy-Siegerehrung sagt „+X AT" (statt „All-Time").
await delay(1200);
const atText = await anna.evaluate(() =>
  [...document.querySelectorAll(".zwischenstand-zeile .muted")].map((z) => z.textContent.trim()),
);
check(
  "Terminologie: Siegerehrung am Handy sagt „+X AT' (kein „All-Time')",
  atText.length > 0 && atText.every((t) => / AT$/.test(t) && !t.includes("All-Time")),
  atText.join(" · "),
);

// C2: Match-Ausbeute-Sheet (Profil Anna) mit AT-Zeile + XP.
await anna.waitForSelector(".mm-ende-panel", { timeout: 20_000 });
const sheetText = await anna.evaluate(() => document.querySelector(".mm-ende-panel").textContent);
check(
  "Belohnung: Match-Ausbeute-Sheet zeigt „AT (All-Time-Bananen)' + XP",
  sheetText.includes("AT (All-Time-Bananen)") && sheetText.includes("XP"),
);
await schuss(anna, "ende_6_ausbeute_sheet");

// C3: RECAP NACH RELOAD (Eval-4-Fix): neu laden → Auto-Rejoin → Sheet WIEDER da.
await anna.reload();
await anna.waitForSelector(".mm-ende-panel", { timeout: 25_000 });
check("Belohnung P2: Match-Ausbeute-Sheet erscheint auch NACH RELOAD zur Siegerehrung", true);
await schuss(anna, "ende_7_recap_nach_reload");

// C4: P1-Vorzustand — Karte VOR der Aggregation: 0 Matches, statsAusstehend.
// (Antwort-Hülle: { karte: {...} } — siehe server/meta/http-api.ts.)
const holeKarte = async () =>
  (await (await fetch(`${URL_BASIS}/api/meta/profile/${profileId}/karte`)).json()).karte ?? {};
const karteVorher = await holeKarte();
check(
  "P1-Stats: direkt nach Match-Ende noch 0 Matches, aber statsAusstehend=true",
  karteVorher.matches === 0 && karteVorher.statsAusstehend === true,
  JSON.stringify({ matches: karteVorher.matches, ausstehend: karteVorher.statsAusstehend }),
);

// ==================== D) META-LANDING (parallel zur 95-s-Stats-Wartezeit) ====================
const landCtx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
await landCtx.addInitScript((d) => localStorage.setItem("mm:device", d), DEVICE);
const land = await landCtx.newPage();
await land.goto(URL_BASIS);
await land.click("text=Profile · Shop · Pass");
await land.waitForSelector(".meta-tabs", { timeout: 8000 });

// D1: Terminologie: Tab heißt „Pass & Aufgaben".
check(
  "Terminologie: Landing-Tab „Pass & Aufgaben' (statt „Pass & Quests')",
  (await land.locator("text=Pass & Aufgaben").count()) > 0,
);

// Shop öffnen + Profil Anna wählen.
await land.click("text=🛍 Shop");
await delay(600);
await land.locator(".karte button", { hasText: "Anna" }).first().click();
await delay(800);

// D2: Willkommens-Paket-Karte (einmalig) sichtbar.
check(
  "Belohnung: Willkommens-Paket-Karte „🎁 300 AT + Titel' sichtbar",
  (await land.locator('[data-testid="willkommens-karte"]').count()) === 1,
);

// D3: Level-Fortschritts-Balken im Shop.
check(
  "Belohnung: „Weg zum nächsten Level'-Balken im Shop",
  (await land.locator('[data-testid="level-fortschritt"]').count()) >= 1,
);

// D4: Shop-Filter-Chips ≥44px (Eval 2: vorher 34px).
const chips = await land.evaluate(() =>
  [...document.querySelectorAll(".shop-chips .chip")].map((c) => ({
    text: c.textContent.trim().slice(0, 18),
    h: Math.round(c.getBoundingClientRect().height),
  })),
);
check(
  `Touch: alle ${chips.length} Shop-Filter-Chips ≥44px`,
  chips.length >= 8 && chips.every((c) => c.h >= 44),
  chips.map((c) => `${c.text}=${c.h}px`).join(" · "),
);
ergebnisse.touchZiele.push(...chips.map((c) => ({ label: `Shop-Chip ${c.text}`, h: c.h })));
await schuss(land, "shop_8_willkommen_chips");

// D5: Kauf-Moment — Buzzer „Hupe" (250 AT, anlegbar) kaufen.
const hupe = land.locator(".shop-item", { hasText: "Hupe" }).first();
await hupe.locator("button", { hasText: "Kaufen" }).click();
await land.waitForSelector('[data-testid="kauf-moment"]', { timeout: 8000 });
const ctaDa = (await land.locator('[data-testid="anlegen-cta"]').count()) > 0;
check("Belohnung: Kauf-Moment „🎉 Gekauft!' (+ Konfetti-Salve) sichtbar", true);
check("Belohnung: „✨ Gleich anlegen!'-CTA am gekauften Item", ctaDa);
await schuss(land, "shop_9_kauf_moment");
if (ctaDa) {
  await land.click('[data-testid="anlegen-cta"]');
  await delay(800);
  check(
    "Belohnung: CTA legt an → „✓ Angelegt'",
    (await hupe.locator("button", { hasText: "✓ Angelegt" }).count()) >= 1,
  );
}

// D6: Terminologie: „Tages-Aufgaben" + „Saison-Aufgaben" im Pass-Tab.
await land.click("text=Pass & Aufgaben");
await delay(1500);
const passText = await land.evaluate(() => document.body.textContent);
check(
  "Terminologie: „Tages-Aufgaben' + „Saison-Aufgaben' (statt Daily-/Saison-Quests)",
  passText.includes("Tages-Aufgaben") &&
    passText.includes("Saison-Aufgaben") &&
    !passText.includes("Daily-Quests"),
);
await schuss(land, "pass_10_tages_aufgaben");

// ==================== C5) P1 AUTO-STATS: Polling bis ≤2 min ====================
// KEIN manueller Trigger — nur lesende GET /karte-Aufrufe (Timer-Beweis).
log("Warte auf AUTOMATISCHE Aggregation (Soll: ≤120 s nach Match-Ende) …");
let statsNach = null;
while (Date.now() - tMatchEnde < 150_000) {
  const karte = await holeKarte();
  if (karte.matches >= 1) {
    statsNach = { sekunden: Math.round((Date.now() - tMatchEnde) / 1000), matches: karte.matches };
    break;
  }
  await delay(5000);
}
ergebnisse.statsTiming = statsNach;
check(
  "P1-Stats: Karte zeigt 1 Match AUTOMATISCH ≤2 min nach Match-Ende (OHNE Trigger)",
  statsNach !== null && statsNach.sekunden <= 120,
  statsNach ? `nach ${statsNach.sekunden} s` : "nie angekommen (150 s)",
);

// Visueller Beleg: Landing-Profil-Karte zeigt „1 Matches".
await land.click("text=Profil-Karte");
await delay(1500);
const karteText = await land.evaluate(() => document.body.textContent);
check(
  "P1-Stats: Landing-Profil-Karte zeigt 1 Match (real aktualisiert)",
  /1\s*Match/.test(karteText),
);
await schuss(land, "karte_11_stats_automatisch");

// ---------- Bilanz ----------
writeFileSync(`${OUT}/mm_fix2e_results.json`, JSON.stringify(ergebnisse, null, 2));
log(`Ergebnis-Log: ${OUT}/mm_fix2e_results.json`);
log(
  fehlgeschlagen === 0
    ? `ALLE ${ergebnisse.checks.length} CHECKS GRÜN`
    : `${fehlgeschlagen}/${ergebnisse.checks.length} Checks ROT`,
);

await browser.close();
gmSocket.close();
opener.close();
server.kill();
process.exit(fehlgeschlagen === 0 ? 0 : 1);
