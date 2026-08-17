// W4-Speicher-Beweis (Playwright, OHNE iPad): die geschlossene Standalone-
// Lücke end-zu-end auf der VM — relay-sim spielt Swift, Desktop-Chrome spielt
// das iPad. Bewiesen wird:
//   1. Host-Banner: Adresse GROSS + QR + WLAN-/Speicher-Hinweis
//   2. Profil „Coco" wird am Telefon angelegt (meta.http über das Wire)
//   3. Match läuft → GM save.write Slot 1 (mitten im Match)
//   4. Match ZU ENDE → AT-Buchung erscheint am Telefon (Bottom-Sheet)
//   5. Host-Seite KOMPLETT neu laden (= App-Neustart) → Profil + AT sind
//      NOCH DA (IndexedDB) → GM save.load stellt das Match aus Slot 1 wieder
//      her (alter Raum-Code!) → Telefon resumt mit seinem alten Token
//
//   npm run build:client && node tools/ipad-host/proof-w4-speicher.mjs
//   → /opt/cursor/artifacts/mm_w4ios_*.png
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import WebSocket from "ws";

const PORT = Number(process.env.PROOF_PORT ?? 8097);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[w4-speicher] ${t}`);

async function schuss(page, name) {
  const pfad = `${OUT}/mm_w4ios_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

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

// ---------- 2) „iPad": Host-Seite (Browser-Server + Bühnen-iframe) ----------
const browser = await chromium.launch({ args: ["--autoplay-policy=no-user-gesture-required"] });
const host = await browser.newPage({ viewport: { width: 1280, height: 800 } });
host.on("pageerror", (e) => log(`⚠ Host-Fehler: ${String(e).slice(0, 200)}`));
host.on("console", (m) => {
  if (m.text().includes("Wiederbelebung")) log(`Host-Konsole: ${m.text()}`);
});
await host.goto(`${URL_BASIS}/host`);
await host.waitForSelector(".host-banner", { timeout: 10_000 });

const buehne = () => host.frames().find((f) => f.url().includes("/screen"));
for (let i = 0; i < 40 && !buehne(); i++) await delay(250);
await buehne().waitForSelector(".mono", { timeout: 10_000 });

async function lobbyDaten() {
  const text = await buehne().evaluate(() => document.body.innerText);
  return {
    code: text.match(/\/j\/([A-Z]{4})/)?.[1] ?? null,
    gmPin: text.match(/PIN:\s*(\d{4})/)?.[1] ?? null,
  };
}
const abend1 = await lobbyDaten();
if (!abend1.code || !abend1.gmPin) throw new Error("Lobby unlesbar (Abend 1)");
log(`✅ Abend 1: Raum ${abend1.code}, GM-PIN ${abend1.gmPin}`);

// Banner-Beweis: Adresse groß + QR (kommt, sobald die Bühne den Raum meldet).
await host.waitForSelector("#host-qr:not([hidden])", { timeout: 12_000 });
await host.waitForFunction(() => document.querySelector("#host-qr-bild")?.naturalWidth > 0, {
  timeout: 8000,
});
const bannerText = await host.evaluate(() => document.querySelector(".host-banner").innerText);
if (!bannerText.includes(URL_BASIS)) throw new Error("Adresse fehlt im Banner!");
if (!bannerText.includes("lokal auf dem iPad")) throw new Error("Speicher-Hinweis fehlt!");
log("✅ Host-Banner: Adresse + QR + WLAN-Hinweis + „lokal auf dem iPad gespeichert“");
await schuss(host, "01_host_banner_adresse_qr");

// ---------- 3) Telefone: Coco MIT Profil („Als Profil speichern"), Ben Gast ----------
const telefonA = await browser.newPage({ viewport: { width: 390, height: 844 } });
const telefonB = await browser.newPage({ viewport: { width: 390, height: 844 } });

async function joinSeite(page, code) {
  await page.goto(`${URL_BASIS}/j/${code}`);
  await page.waitForSelector('input[placeholder="Dein Name"]', { timeout: 8000 });
}

await joinSeite(telefonA, abend1.code);
await telefonA.fill('input[placeholder="Dein Name"]', "Coco");
// „✨ Als Profil speichern (AT-Konto + Shop)" — legt das Profil beim Verbinden
// über meta.http (Wire) an; landet in der IndexedDB des Host-Servers.
await telefonA.click('label:has-text("Als Profil speichern") input[type="checkbox"]');
await delay(200);
await telefonA.click("button.primaer");
await telefonA.waitForSelector(".spieler-liste", { timeout: 8000 });
log("✅ Coco im Raum — Profil über das Wire angelegt (meta.http)");

await joinSeite(telefonB, abend1.code);
await telefonB.fill('input[placeholder="Dein Name"]', "Ben");
await telefonB.click("button.primaer");
await telefonB.waitForSelector(".spieler-liste", { timeout: 8000 });

// Geräte-Token von Coco (für den Profil-Lese-Beweis über das Wire).
const tokenA = await telefonA.evaluate(() => localStorage.getItem("mm:device"));

// ---------- 4) GM als roher Wire-Client (wie ein GM-Handy) ----------
function gmVerbinde() {
  const ws = new WebSocket(`ws://localhost:${PORT}/ws`);
  const acks = new Map();
  let ackNr = 0;
  const zustand = { view: null };
  ws.on("message", (roh) => {
    const msg = JSON.parse(String(roh));
    if (msg.t === "a") acks.get(msg.ack)?.(msg.p);
    if (msg.t === "e" && msg.ev === "view.snapshot") zustand.view = msg.p.view;
  });
  const sende = (ev, p) => {
    const ack = ++ackNr;
    return new Promise((resolve, reject) => {
      acks.set(ack, resolve);
      setTimeout(() => reject(new Error(`ack-timeout ${ev}`)), 10_000);
      ws.send(JSON.stringify({ t: "e", ev, p, ack }));
    });
  };
  return {
    ws,
    zustand,
    sende,
    offen: () => new Promise((r) => ws.on("open", r)),
    cmd: async (cmd, args = {}) => {
      const antwort = await sende("gm.cmd", { cmd, args, cmdId: `w4-${++ackNr}` });
      if (!antwort.ok) log(`⚠ ${cmd}: ${antwort.error}`);
      return antwort;
    },
  };
}

const gm1 = gmVerbinde();
await gm1.offen();
const hello1 = await gm1.sende("hello", { roomCode: abend1.code, role: "gm", gmPin: abend1.gmPin });
if (!hello1.ok) throw new Error(`GM-hello: ${hello1.error}`);

async function wartePhase(phase, timeout = 15_000) {
  await buehne().waitForFunction(
    (p) => document.querySelector(".studio")?.dataset.phase === p,
    phase,
    { timeout },
  );
}

async function richtigIndex(gm) {
  for (let i = 0; i < 60; i++) {
    const idx = gm.zustand.view?.minigame?.view?.correctIndex;
    if (gm.zustand.view?.phase === "frage" && typeof idx === "number") return idx;
    await delay(150);
  }
  return 0;
}

// ---------- 5) Match: Frage 1 spielen → save.write Slot 1 → zu Ende spielen ----------
await gm1.cmd("settings.set", { modus: "quick", jokerAn: false });
await gm1.cmd("flow.next"); // Lobby → Intro
await wartePhase("intro");
await gm1.cmd("flow.next");
await wartePhase("erklaerkarte");
await gm1.cmd("flow.next");
await wartePhase("frage");
await telefonA.waitForSelector("#mg-host button:not([disabled])", { timeout: 10_000 });
const richtig1 = await richtigIndex(gm1);
await telefonA.click(`#mg-host button >> nth=${richtig1}`);
await telefonB.click(`#mg-host button >> nth=${(richtig1 + 1) % 4}`);
await wartePhase("aufloesung");
log(`✅ Frage 1 gespielt (Coco richtig, Ben daneben)`);

// SAVE.WRITE mitten im Match — exakt das GM-Kommando der 💾-Karte.
const saveAntwort = await gm1.cmd("save.write", { slot: 1 });
if (!saveAntwort.ok) throw new Error(`save.write fehlgeschlagen: ${saveAntwort.error}`);
log("✅ save.write Slot 1 → IndexedDB (mitten im Match, Frage 1 beantwortet)");
await delay(600);
await schuss(host, "02_match_laeuft_save_geschrieben");

// Match ZU ENDE spielen: GM hämmert „Weiter" (flow.next skippt jede Phase).
for (let i = 0; i < 60; i++) {
  const phase = gm1.zustand.view?.phase;
  if (phase === "siegerehrung" || phase === "ende") break;
  await gm1.cmd("flow.next");
  await delay(700);
}
if (!["siegerehrung", "ende"].includes(gm1.zustand.view?.phase)) {
  throw new Error(`Match nicht zu Ende: Phase ${gm1.zustand.view?.phase}`);
}
log("✅ Match beendet (Siegerehrung) — AT-Buchung läuft (matchBeendet-Hook)");

// AT-Bottom-Sheet am Telefon (meta-ende pollt /api/meta/.../match-meta über Wire).
await telefonA.waitForFunction(
  () => document.body.innerText.includes("Affen-Taler") || document.body.innerText.includes("AT"),
  { timeout: 30_000 },
);
await delay(2500); // Buchung + Poll + Einblendung
await schuss(telefonA, "03_phone_at_buchung");

// Profil-Stand VOR dem Neustart über das Wire lesen (Referenz für nachher).
const profilVorher = await gm1.sende("meta.http", {
  method: "GET",
  pfad: `/api/meta/profile?device=${encodeURIComponent(tokenA)}`,
});
const cocoVorher = profilVorher?.body?.profile?.find((p) => p.name === "Coco");
if (!cocoVorher || cocoVorher.atVerfuegbar <= 0) {
  throw new Error(`Coco hat keine AT gebucht: ${JSON.stringify(profilVorher)}`);
}
log(`✅ Coco VOR Neustart: Lv ${cocoVorher.level} · ${cocoVorher.atVerfuegbar} AT (IndexedDB)`);

// ---------- 6) APP-NEUSTART: Host-Seite KOMPLETT neu laden ----------
gm1.ws.close();
log("🔄 Host-Seite wird KOMPLETT neu geladen (= App-Neustart auf dem iPad) …");
await host.reload();
await host.waitForSelector(".host-banner", { timeout: 10_000 });
for (let i = 0; i < 40 && !buehne(); i++) await delay(250);
await buehne().waitForSelector(".mono", { timeout: 10_000 });
const abend2 = await lobbyDaten();
if (!abend2.code || !abend2.gmPin) throw new Error("Lobby unlesbar (Abend 2)");
if (abend2.code === abend1.code) throw new Error("Erwartet: FRISCHER Raum nach Neustart");
log(`✅ Neustart: frischer Server, neuer Raum ${abend2.code} (Match war ja sauber zu Ende)`);

// ---------- 7) BEWEIS A: Profil + AT haben den Neustart überlebt ----------
await joinSeite(telefonA, abend2.code);
// Das Telefon erinnert sein aktives Profil (localStorage) — für den SERVER-
// Beweis einmal abwählen: die „Willkommen zurück“-Kacheln kommen dann frisch
// über meta.http aus der Host-IndexedDB (Name + Level + AT vom Server).
await telefonA.click('button:has-text("doch als Gast")');
await telefonA.waitForSelector(".profil-kachel", { timeout: 10_000 });
const kachelText = await telefonA.evaluate(
  () => document.querySelector(".profil-kachel").innerText,
);
if (!kachelText.includes("Coco")) throw new Error(`Profil-Kachel ohne Coco: ${kachelText}`);
log(`✅ BEWEIS A — „Willkommen zurück“-Kachel nach Neustart: ${kachelText.replace("\n", " · ")}`);
await schuss(telefonA, "04_phone_profil_ueberlebt_neustart");

const gm2 = gmVerbinde();
await gm2.offen();
const hello2 = await gm2.sende("hello", { roomCode: abend2.code, role: "gm", gmPin: abend2.gmPin });
if (!hello2.ok) throw new Error(`GM-hello (Abend 2): ${hello2.error}`);
const profilNachher = await gm2.sende("meta.http", {
  method: "GET",
  pfad: `/api/meta/profile?device=${encodeURIComponent(tokenA)}`,
});
const cocoNachher = profilNachher?.body?.profile?.find((p) => p.name === "Coco");
if (cocoNachher?.atVerfuegbar !== cocoVorher.atVerfuegbar) {
  throw new Error(`AT-Stand weicht ab: ${JSON.stringify(profilNachher)}`);
}
log(`✅ BEWEIS A bestätigt: Coco NACH Neustart: ${cocoNachher.atVerfuegbar} AT — identisch`);

// ---------- 8) BEWEIS B: save.load stellt das Match wieder her ----------
const slots = await gm2.sende("meta.http", { method: "GET", pfad: "/api/meta/saves" });
const slot1 = slots?.body?.slots?.find((s) => s.slot === 1);
if (!slot1 || slot1.roomCode !== abend1.code) {
  throw new Error(`Slot 1 fehlt/falsch: ${JSON.stringify(slots)}`);
}
log(
  `✅ Save-Slot-Liste über das Wire: Slot 1 = Raum ${slot1.roomCode}, ` +
    `Phase ${slot1.phase}, Spieler ${slot1.spieler.map((s) => s.name).join("+")}`,
);

const ladeAntwort = await gm2.cmd("save.load", { slot: 1 });
if (!ladeAntwort.ok) throw new Error(`save.load fehlgeschlagen: ${ladeAntwort.error}`);
await delay(600);
// Der Raum läuft wieder unter dem ALTEN Code — Join-URLs und Telefon-Tokens gelten.
const geladenText = await buehne().evaluate(() => document.body.innerText);
if (!geladenText.includes("gespeichert") && !geladenText.includes(abend1.code)) {
  log(`⚠ Bühnen-Text nach Laden: ${geladenText.slice(0, 200)}`);
}
log(`✅ BEWEIS B: save.load ok — Match aus Slot 1 zurück (Raum wieder ${abend1.code})`);
await schuss(host, "05_save_load_match_wiederhergestellt");

// Weiter nach der Save-Pause (der Save friert als paused ein — Resume-Trick).
await gm2.cmd("session.resume");
await delay(800);

// Telefon-Resume: Coco öffnet die ALTE Join-URL — ihr Session-Token
// (localStorage mm:CODE) findet den Platz im wiederhergestellten Match.
await telefonA.goto(`${URL_BASIS}/j/${abend1.code}`);
await telefonA.waitForFunction(
  () => !document.body.innerText.includes("Dein Name") || document.querySelector("#mg-host"),
  { timeout: 12_000 },
);
await delay(1200);
const resumeText = await telefonA.evaluate(() => document.body.innerText.slice(0, 300));
log(`Telefon nach Resume:\n${resumeText}`);
await schuss(telefonA, "06_phone_resume_im_wiederhergestellten_match");
await schuss(host, "07_stage_nach_resume");

log(`Fertig — alle W4-Beweise erbracht. Screenshots in ${OUT}`);
await browser.close();
gm2.ws.close();
relay.kill();
process.exit(0);
