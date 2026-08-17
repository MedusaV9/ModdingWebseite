// v2-FEATURES-Beweis (Playwright): Jubiläums-Karte im Opening (C-05),
// Sudden-Death-Kokosnuss-Shake (C-03), Replay-Highlights (E-01) und
// Foto-Finish-Share (E-02) — ein komplettes Quick-Match, deterministisch
// gesteuert über GM-Kommandos + Spieler-Sockets.
//
//   node tools/screenshots/v2-proof.mjs → /opt/cursor/artifacts/mm_v2_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8093);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const DATA = "/tmp/mm-v2-proof-data";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[v2-proof] ${t}`);

// ---------- 1) Meta-Daten SEEDEN: 2 Profile + Gruppe mit 9 Abenden ----------
// Jubiläums-Fixture: die Gruppe {Anna, Ben} startet gleich ihr 10. Match.
rmSync(DATA, { recursive: true, force: true });
mkdirSync(`${DATA}/meta`, { recursive: true });
const profil = (profileId, name, avatar) => ({
  profileId,
  name,
  avatar,
  pinHash: null,
  createdAt: 1_700_000_000_000,
  deviceTokens: [],
  at: { gesamt: 120, verfuegbar: 120 },
  besitz: [],
  ausgeruestet: {},
  ersteMale: {},
  gebuchteMatches: [],
});
writeFileSync(
  `${DATA}/meta/profiles.json`,
  JSON.stringify({
    schemaVersion: 1,
    profile: {
      pr_anna: profil("pr_anna", "Anna", "gitti-giro.rot"),
      pr_ben: profil("pr_ben", "Ben", "don-bananas.blau"),
    },
  }),
);
writeFileSync(
  `${DATA}/meta/jubilaeen.json`,
  JSON.stringify({
    schemaVersion: 1,
    gruppen: {
      "pr_anna+pr_ben": {
        matches: 9,
        gesamtMoney: 47_230,
        rekordEndstand: 3_200,
        rekordName: "Anna",
        gefeiert: [],
      },
    },
  }),
);
log("Meta-Seed: Profile Anna+Ben, Gruppen-Historie 9 Matches / 47.230 MM");

// ---------- 2) Server starten ----------
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

// ---------- 3) Raum + Spieler-Sockets (Anna+Ben MIT Profil, Cleo als Gast) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
const gmPin = raum.gmPin;
log(`Raum ${code} (GM-PIN ${gmPin})`);

async function spielerSocket(hello) {
  const sock = io(URL_BASIS, { transports: ["websocket"] });
  const w = await sock.timeout(5000).emitWithAck("hello", { roomCode: code, ...hello });
  if (!w.ok) throw new Error(`hello ${JSON.stringify(hello)}: ${w.error}`);
  return { sock, playerId: w.playerId, token: w.sessionToken };
}

const anna = await spielerSocket({ role: "player", profileId: "pr_anna" });
const ben = await spielerSocket({ role: "player", profileId: "pr_ben" });
const cleo = await spielerSocket({ role: "player", name: "Cleo", avatar: "kiki-krawall.gruen" });
log(`Spieler: Anna=${anna.playerId} (Profil), Ben=${ben.playerId} (Profil), Cleo=${cleo.playerId}`);

let aktionNr = 0;
async function aktion(spieler, event, payload) {
  const antwort = await spieler.sock
    .timeout(5000)
    .emitWithAck(event, { ...payload, idemKey: `v2-${aktionNr++}` });
  if (!antwort.ok) log(`⚠ ${event}: ${antwort.error}`);
  return antwort.ok;
}
const antworte = (spieler, choice) =>
  aktion(spieler, "player.action", {
    minigameId: "lianen-finale",
    actionId: "answer",
    payload: { choice },
  });

// ---------- 4) Browser: Screen + 2 Handy-Seiten (Session-Token-Restore) ----------
const browser = await chromium.launch({ args: ["--autoplay-policy=no-user-gesture-required"] });
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

async function handySeite(token) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.addInitScript(({ c, t }) => localStorage.setItem(`mm:${c}`, t), { c: code, t: token });
  await page.goto(`${URL_BASIS}/j/${code}`);
  await page.waitForSelector(".spieler-kopf", { timeout: 10_000 });
  return page;
}
const annaPhone = await handySeite(anna.token);
const cleoPhone = await handySeite(cleo.token);
log("Screen + Handys (Anna, Cleo) verbunden");

// ---------- 5) GM-Socket ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
let gmView = null;
gm.on("view.snapshot", (p) => (gmView = p.view));
const gmHello = await gm.timeout(5000).emitWithAck("hello", { roomCode: code, role: "gm", gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
let cmdNr = 0;
async function gmCmd(cmd, args = {}) {
  const antwort = await gm
    .timeout(5000)
    .emitWithAck("gm.cmd", { cmd, args, cmdId: `v2-${cmdNr++}` });
  if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
  return antwort.ok;
}

await gmCmd("settings.set", { modus: "quick", autoGm: false });
await gmCmd("flow.next"); // Lobby → Intro (matchGestartet ⇒ Jubiläums-Lookup)

// ---------- 6) BEWEIS C-05: Jubiläums-Karte im Opening ----------
await screen.waitForFunction(() => !document.querySelector(".stinger-overlay"), {
  timeout: 10_000,
});
await screen.waitForSelector('[data-testid="jubilaeums-karte"]', { timeout: 8000 });
const jubilaeumText = await screen.evaluate(
  () => document.querySelector('[data-testid="jubilaeums-karte"]').textContent,
);
if (!jubilaeumText.includes("10. Abend")) throw new Error(`Jubiläums-Text: ${jubilaeumText}`);
log(`🎉 Jubiläums-Karte: „${jubilaeumText.slice(0, 60)}…"`);
await delay(2600); // Kandidaten-Einflug + Konfetti
await schuss(screen, "jubilaeum_opening");

// ---------- 7) Match durchsteuern: Runden skippen, im Finale gezielt antworten ----------
// Balancen VOR dem Finale: Anna 500, Ben 400, Cleo 0 (Cleo = Comeback-Kandidatin).
let geldVerteilt = false;
let gleichstandGebaut = false;
let finaleFragen = 0;
const beantwortet = new Set();
let schritte = 0;
while (schritte < 160) {
  schritte += 1;
  const phase = gmView?.phase;
  if (phase === "tiebreaker" || phase === "highlights" || phase === "siegerehrung") break;

  if (phase === "zwischenstand" && gmView?.abschnitt?.typ !== "finale" && !geldVerteilt) {
    geldVerteilt = true;
    await gmCmd("score.adjust", {
      playerId: anna.playerId,
      delta: 500,
      grund: "v2-Demo Startgeld",
      override: true,
    });
    await gmCmd("score.adjust", {
      playerId: ben.playerId,
      delta: 400,
      grund: "v2-Demo Startgeld",
      override: true,
    });
    log("Zwischenstand: Anna 500 / Ben 400 / Cleo 0 (Comeback-Ausgangslage)");
  }

  if (phase === "frage" && gmView?.abschnitt?.typ === "finale") {
    // GM-Spickzettel: die richtige Antwort steht im GM-View.
    const qid = gmView?.minigame?.view?.questionId;
    if (qid && !beantwortet.has(qid)) {
      beantwortet.add(qid);
      finaleFragen += 1;
      const richtig = gmView?.minigame?.view?.correctIndex ?? 0;
      log(`Finale-Frage ${finaleFragen} (${qid}): richtig=${richtig}`);
      await antworte(cleo, richtig); // Cleo: 3× richtig ⇒ Comeback Platz 3 → 1
      // Anna patzt in Frage 1 (teuerste Falschantwort: −W/2), danach richtig.
      await antworte(anna, finaleFragen === 1 ? (richtig + 1) % 4 : richtig);
      if (finaleFragen > 1) await antworte(ben, richtig);
    }
    await gmCmd("flow.next"); // Frage sofort schließen (Ben antwortet in Q1 nicht)
    await delay(600);
    continue;
  }

  // Nach dem Finale: Gleichstand an der Spitze bauen (Sudden-Death-Trigger).
  if (phase === "zwischenstand" && gmView?.abschnitt?.typ === "finale" && !gleichstandGebaut) {
    gleichstandGebaut = true;
    const staende = Object.fromEntries(gmView.standings.map((s) => [s.id, s.balance]));
    const delta = staende[cleo.playerId] - staende[ben.playerId];
    log(
      `Nach Finale: Cleo ${staende[cleo.playerId]} / Ben ${staende[ben.playerId]} / Anna ${staende[anna.playerId]} — Ben +${delta} für den Gleichstand`,
    );
    await gmCmd("score.adjust", {
      playerId: ben.playerId,
      delta,
      grund: "v2-Demo Gleichstand",
      override: true,
    });
  }

  await gmCmd("flow.next");
  await delay(600);
}
if (gmView?.phase !== "tiebreaker") throw new Error(`Tiebreaker nicht erreicht: ${gmView?.phase}`);
log("💥 SUDDEN DEATH erreicht — Ben und Cleo liegen exakt gleichauf!");

// ---------- 8) BEWEIS C-03: Sudden-Death-Look (Countdown → Shake → KNACK) ----------
await screen.waitForSelector('[data-testid="sudden-death"]', { timeout: 8000 });
await delay(700);
await schuss(screen, "sudden_death_countdown");

// Countdown (3 s) abwarten, dann hämmern: Cleo klickt am HANDY, Ben tippt per Socket.
await screen.waitForFunction(() => document.querySelector(".shake-balken") !== null, {
  timeout: 8000,
});
await cleoPhone.waitForSelector('[data-testid="shake-knopf"]', { timeout: 6000 });
for (let i = 0; i < 14; i++) {
  await cleoPhone.click('[data-testid="shake-knopf"]', { delay: 10 });
}
await aktion(ben, "shake.tap", { taps: 6 });
await aktion(ben, "shake.tap", { taps: 3 });
await delay(700); // Handy-Batch (250 ms) flusht + Live-Deltas kommen an
await schuss(screen, "sudden_death_shake_screen");
await schuss(cleoPhone, "sudden_death_shake_phone");
log(`Shake läuft: Cleo 14 Handy-Taps vs. Ben 9 Socket-Taps`);

await gmCmd("flow.next"); // Shake-Fenster skippen → Ergebnis
await screen.waitForFunction(
  () => document.querySelector('[data-testid="sudden-death"]')?.textContent.includes("KNACK"),
  { timeout: 8000 },
);
await delay(600);
await schuss(screen, "sudden_death_knack");
log("🥥 KNACK! Cleo gewinnt den Kokosnuss-Shake");

// ---------- 9) BEWEIS E-01: Replay-Highlights („Die Highlights des Abends") ----------
await gmCmd("flow.next"); // Ergebnis-Karte skippen → Highlights
await screen.waitForSelector('[data-testid="highlight-karte"]', { timeout: 8000 });
const karte1 = await screen.evaluate(
  () => document.querySelector('[data-testid="highlight-karte"]').textContent,
);
log(`🎬 Highlight-Karte 1: „${karte1.slice(0, 80)}…"`);
await delay(800);
await schuss(screen, "highlights_karte_patzer");
// Annas Handy: „DU warst das!" (sie hat den teuersten Patzer gebaut).
await annaPhone.waitForSelector('[data-testid="du-warst-das"]', { timeout: 6000 });
await schuss(annaPhone, "highlights_du_warst_das_phone");
log("📱 Annas Handy zeigt „DU warst das!“ auf ihrem eigenen Highlight");

await gmCmd("flow.next"); // → Karte 2 (Comeback)
await screen.waitForFunction(
  () =>
    document.querySelector('[data-testid="highlight-karte"]')?.textContent.includes("Aufholjagd"),
  { timeout: 8000 },
);
await delay(800);
await schuss(screen, "highlights_karte_comeback");
log("🎬 Highlight-Karte 2: die Aufholjagd (Comeback Platz 3 → 1)");

// ---------- 10) Siegerehrung: Shake-Sieger vorn + Sudden-Death-Award ----------
await gmCmd("flow.next");
await screen.waitForFunction(() => (document.body.textContent ?? "").includes("Siegerehrung"), {
  timeout: 8000,
});
await delay(4600); // Podest-Einlauf 3-2-1 + Award-Band
await schuss(screen, "siegerehrung_sudden_death_award");

// ---------- 11) BEWEIS E-02: Foto-Finish-Share (Screen + Handy) ----------
await gmCmd("flow.next"); // Siegerehrung → Abspann (ende)
await screen.waitForSelector('[data-testid="foto-finish"]', { timeout: 8000 });
const download = screen.waitForEvent("download", { timeout: 8000 }).catch(() => null);
await screen.click('[data-testid="foto-finish"] button');
await screen.waitForSelector('[data-testid="foto-finish"] img', { timeout: 6000 });
const dl = await download;
const dataUrlLaenge = await screen.evaluate(
  () => document.querySelector('[data-testid="foto-finish"] img').src.length,
);
log(
  `📸 Foto-Finish (Screen): PNG-data-URL mit ${dataUrlLaenge} Zeichen${dl ? `, Download "${dl.suggestedFilename()}"` : ""}`,
);
await delay(400);
await schuss(screen, "fotofinish_screen");

await annaPhone.waitForSelector('[data-testid="foto-finish"] button', { timeout: 8000 });
await annaPhone.click('[data-testid="foto-finish"] button');
await annaPhone.waitForSelector('[data-testid="foto-finish"] img', { timeout: 6000 });
await delay(400);
await schuss(annaPhone, "fotofinish_bild_speichern_phone");
log("📱 Handy: „Bild speichern“ erzeugt das Ergebnis-Bild als data-URL");

log(`Fertig — Screenshots in ${OUT}`);
await browser.close();
gm.close();
opener.close();
anna.sock.close();
ben.sock.close();
cleo.sock.close();
server.kill();
process.exit(0);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_v2_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
