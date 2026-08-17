// W3-UI1-Beweis (Bühne + GM-Cockpit): schießt die 5 Kern-Screens (GM, Frage/
// Podium, Zwischenstand, Rad, Opening) bei 1280×800 UND 1920×1080 — als
// Vorher/Nachher-Paare für das Bühnen-/Cockpit-Redesign. Der Flow läuft
// KOMPLETT über die echte GM-UI (Bots dazu, Weiter, Rad drehen), damit das
// Cockpit gleichzeitig funktional bewiesen wird.
//
//   node tools/screenshots/w3ui1-proof.mjs                     → /opt/cursor/artifacts
//   OUT_DIR=/tmp/w3ui1 PREFIX=vorher node tools/…/w3ui1-proof.mjs
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.TOUR_PORT ?? 8093);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const PREFIX = process.env.PREFIX ?? "nachher";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[w3ui1] ${t}`);

// ---------- 1) Server starten (eigener Port + Wegwerf-Datenordner) ----------
rmSync("/tmp/mm-w3ui1-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-w3ui1-data" },
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

// ---------- 2) Raum anlegen (Opener-Socket bleibt still verbunden) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
log(`Raum ${code} (GM-PIN ${raum.gmPin})`);

// ---------- 3) Browser: Bühne + GM-Cockpit ----------
const browser = await chromium.launch();
const screen = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

const gm = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await gm.goto(`${URL_BASIS}/gm`);
await gm.fill("#gm-code", code);
await gm.fill("#gm-pin", raum.gmPin);
await gm.click("button.primaer");
await gm.waitForSelector('[data-testid="gm-anker"]', { timeout: 8000 });
log("GM-Cockpit verbunden");

/** Screenshot bei 1920×1080 UND 1280×800 (Name trägt die Auflösung).
 * 1920 ZUERST: zeitkritische Phasen (Opening mit Bot-Skip) sollen beide
 * Auflösungen möglichst früh im selben Beat erwischen. */
async function paar(page, name) {
  await page.setViewportSize({ width: 1920, height: 1080 });
  await delay(350);
  await page.screenshot({ path: `${OUT}/mm_w3ui1_${PREFIX}_${name}_1920.png` });
  await page.setViewportSize({ width: 1280, height: 800 });
  await delay(350);
  await page.screenshot({ path: `${OUT}/mm_w3ui1_${PREFIX}_${name}_1280.png` });
  log(`📸 ${name} (1920 + 1280)`);
}

/** GM-Knopf über den sichtbaren Text klicken (Cockpit-UI = der Beweis). */
async function gmKlick(text) {
  await gm.getByRole("button", { name: text }).first().click();
  await delay(750); // Weiter/Skip ist gedrosselt (600 ms Doppel-Tap-Wächter)
}

async function wartePhase(phase, timeout = 15_000) {
  await screen.waitForFunction(
    (p) => document.querySelector(".studio")?.dataset.phase === p,
    phase,
    {
      timeout,
    },
  );
}

/** „Weiter" klicken, bis die Bühne die Zielphase zeigt (Kategorie-Wahl u. ä.
 * liegen je nach Settings dazwischen — der GM klickt sich einfach durch). */
async function weiterBis(phase, maxKlicks = 24) {
  for (let i = 0; i < maxKlicks; i++) {
    const aktuell = await screen.evaluate(() => document.querySelector(".studio")?.dataset.phase);
    if (aktuell === phase) return;
    await gmKlick(/Weiter/);
    await delay(600);
  }
  await wartePhase(phase, 5000);
}

// ---------- 4) Lobby: 3 Bots über die GM-UI dazu ----------
for (let i = 0; i < 3; i++) {
  await gmKlick("🤖 Bot dazu");
}
await screen.waitForFunction(() => document.querySelectorAll(".podium-puppe svg").length >= 3, {
  timeout: 10_000,
});
log("3 Bots auf den Podien");

// ---------- 5) Opening (Kandidaten-Einflug + Beat 2) ----------
await gmKlick(/Match starten/);
await wartePhase("intro");

/** Warten, bis der Beat-2-Name-Callout WIRKLICH aktiv ist (scale > 1.2) —
 * deterministisch statt Delay-Raterei (Stinger-Video verschiebt den Start). */
async function beatAktiv() {
  await screen.waitForFunction(
    () =>
      [...document.querySelectorAll(".kandidaten-reihe .podium-name")].some((n) => {
        const t = getComputedStyle(n).transform;
        return t !== "none" && new DOMMatrix(t).a > 1.2;
      }),
    { timeout: 12_000 },
  );
}

// Opening-Paar von Hand (Bots skippen die Intro schnell): pro Auflösung exakt
// im aktiven Spotlight-Fenster schießen.
await screen.setViewportSize({ width: 1920, height: 1080 });
await beatAktiv();
await screen.screenshot({ path: `${OUT}/mm_w3ui1_${PREFIX}_opening_1920.png` });
await screen.setViewportSize({ width: 1280, height: 800 });
try {
  await beatAktiv();
} catch {
  log("⚠ Beat-2-Fenster fürs 1280er verpasst — Intro lief ab, Shot trotzdem");
}
await screen.screenshot({ path: `${OUT}/mm_w3ui1_${PREFIX}_opening_1280.png` });
log("📸 opening (1920 + 1280, Beat 2 aktiv)");

// ---------- 6) Frage (LED-Wand + Podien) + GM-Cockpit ----------
await weiterBis("frage");
await delay(1100);
await paar(screen, "frage");
await paar(gm, "gm");

// ---------- 7) Zwischenstand (Weiter drücken, bis die Runde durch ist) ----------
await weiterBis("zwischenstand");
await delay(1400); // Einflug-Choreo der Zeilen abwarten
await paar(screen, "zwischenstand");

// ---------- 8) Glücksrad (GM-Spin, Screenshot mitten im Dreh) ----------
await gmKlick("🎡 Rad drehen");
await wartePhase("rad", 8000);
await delay(1400); // mitten im Dreh: Vorschau-Panel + rotierende Segmente
await paar(screen, "rad");

log(`Fertig — ${PREFIX}-Screenshots in ${OUT}`);
await browser.close();
opener.close();
server.kill();
process.exit(0);
