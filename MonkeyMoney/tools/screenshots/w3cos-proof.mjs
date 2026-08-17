// Kosmetik-Welle-3-Beweis (Playwright, End-zu-End gegen den gebauten Server):
// Shop-Kauf → Anlegen → Podium/Opening zeigt die Items WIRKLICH.
//   1. Profil „Coco" (kiki-krawall.gelb) shoppt: Piratenhut (Live-VORSCHAU am
//      eigenen Affen!), Tiger-Fell, Bananen-Girlande, Einlauf-Rauchwolke —
//      kaufen + anlegen über die echte Shop-UI.
//   2. Coco joint per Profil-Kachel in einen Raum: das LOBBY-PODIUM auf dem
//      Screen trägt Hut + Fell-Muster + Girlande (DOM-Belege + Screenshot).
//   3. Intro-Cutscene: die Kandidaten-Karte zündet die Rauchwolke (Video).
//
//   node tools/screenshots/w3cos-proof.mjs → /opt/cursor/artifacts/mm_w3cos_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8479);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const DATA = "/tmp/mm-w3cos-proof-data";
const VIDEO_DIR = "/tmp/mm-w3cos-videos";
mkdirSync(OUT, { recursive: true });
rmSync(DATA, { recursive: true, force: true });
rmSync(VIDEO_DIR, { recursive: true, force: true });
mkdirSync(VIDEO_DIR, { recursive: true });

const log = (t) => console.log(`[w3cos] ${t}`);
const checks = [];
const check = (name, ok, detail = "") => {
  checks.push({ name, ok });
  log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
};
async function schuss(page, name) {
  const pfad = `${OUT}/mm_w3cos_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}

// ---------- 1) Server + Profil „Coco" mit Shopping-Budget ----------
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: DATA },
  stdio: "ignore",
});
process.on("exit", () => server.kill());
let bootOk = false;
for (let i = 0; i < 40 && !bootOk; i++) {
  try {
    bootOk = (await fetch(`${URL_BASIS}/healthz`)).ok;
  } catch {
    /* bootet noch */
  }
  if (!bootOk) await delay(250);
}
if (!bootOk) throw new Error(`Server auf :${PORT} kam nicht hoch`);
log(`Server läuft auf :${PORT}`);

// Die Meta-Routen mounten NACH dem asynchronen Content-Load — healthz ist
// früher grün als /api/meta/*, deshalb hier mit Retry.
const GERAET = "d_geraet_coco";
let profilAntwort = null;
for (let i = 0; i < 80 && profilAntwort?.profil === undefined; i++) {
  const r = await fetch(`${URL_BASIS}/api/meta/profile`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name: "Coco", avatar: "kiki-krawall.gelb", deviceToken: GERAET }),
  });
  if (r.ok) {
    profilAntwort = await r.json();
  } else {
    if (i % 10 === 9) log(`Meta-API noch nicht bereit (Status ${r.status}) — warte …`);
    await delay(500);
  }
}
const profilId = profilAntwort?.profil.profileId;
check("Profil Coco angelegt", typeof profilId === "string", profilId);

// Shopping-Budget: AT direkt in profiles.json (der Store liest pro Op frisch).
const profDatei = `${DATA}/meta/profiles.json`;
const prof = JSON.parse(readFileSync(profDatei, "utf8"));
prof.profile[profilId].at = { gesamt: 20_000, verfuegbar: 20_000 };
writeFileSync(profDatei, JSON.stringify(prof));
log("Coco hat 20.000 AT zum Shoppen");

// ---------- 2) Shop-UI: Vorschau → Kauf → Anlegen (mit Video) ----------
const browser = await chromium.launch();
const shopCtx = await browser.newContext({
  viewport: { width: 1000, height: 900 },
  recordVideo: { dir: VIDEO_DIR, size: { width: 1000, height: 900 } },
});
const shop = await shopCtx.newPage();
await shop.addInitScript((t) => localStorage.setItem("mm:device", t), GERAET);
await shop.goto(URL_BASIS);
await shop.click('button:has-text("Profile · Shop")');
await shop.click('.karte button:has-text("Coco")');
await shop.click('button:has-text("🛍 Shop")');
await shop.waitForSelector('[data-testid="shop-puppe"] svg', { timeout: 8000 });

// Live-Vorschau: Piratenhut probeweise am eigenen Affen (VOR dem Kauf).
await shop.click('[data-testid="vorschau-hut-pirat"]');
await shop.waitForSelector('[data-testid="vorschau-hinweis"]', { timeout: 5000 });
await delay(400); // Puppe neu geschmückt
const vorschauOk = await shop.evaluate(() => {
  const svg = document.querySelector('[data-testid="shop-puppe"] svg');
  return (
    svg !== null &&
    svg.classList.contains("mm-hut-an") &&
    svg.querySelectorAll("g.mm-meta-extra").length >= 1
  );
});
check("Shop-VORSCHAU: Piratenhut sitzt live am eigenen Affen (vor Kauf)", vorschauOk);
await shop.evaluate(() =>
  document.querySelector(".shop-vorschau")?.scrollIntoView({ block: "start" }),
);
await delay(600);
await schuss(shop, "01_shop_vorschau_piratenhut");

// Kaufen + „Gleich anlegen!"-CTA.
async function kaufeUndLegeAn(itemName) {
  const karte = shop.locator(".shop-item", { hasText: itemName });
  await karte.locator('button:has-text("Kaufen")').click();
  await karte.locator('[data-testid="kauf-moment"]').waitFor({ timeout: 5000 });
  await karte.locator('[data-testid="anlegen-cta"]').click();
  await karte.locator('button:has-text("✓ Angelegt")').waitFor({ timeout: 5000 });
  log(`gekauft + angelegt: ${itemName}`);
}
await kaufeUndLegeAn("Piratenhut");
await shop.click('button:has-text("✕ aus")'); // Vorschau aus — jetzt zählt die ECHTE Ausrüstung
await kaufeUndLegeAn("Tiger-Streifen");
await kaufeUndLegeAn("Bananen-Girlande");
await kaufeUndLegeAn("Rauchwolke");
await delay(400);
const angelegtOk = await shop.evaluate(() => {
  const slot = document.querySelector('[data-testid="shop-puppe"]');
  const svg = slot?.querySelector("svg");
  return {
    hut: svg?.classList.contains("mm-hut-an") ?? false,
    muster: (svg?.dataset.mmMuster ?? "") !== "",
    girlande: slot?.classList.contains("mm-podium-girlande") ?? false,
    avatar: slot?.dataset.avatar ?? "",
  };
});
check(
  "Shop-Puppe trägt die ECHTE Ausrüstung (Hut + Fell-Muster + Girlande)",
  angelegtOk.hut && angelegtOk.muster && angelegtOk.girlande,
  angelegtOk.avatar,
);
await shop.evaluate(() =>
  document.querySelector(".shop-vorschau")?.scrollIntoView({ block: "start" }),
);
await delay(600);
await schuss(shop, "02_shop_angelegt_hut_fell_girlande");
await shopCtx.close();
const shopVideo = readdirSync(VIDEO_DIR)[0];
copyFileSync(`${VIDEO_DIR}/${shopVideo}`, `${OUT}/mm_w3cos_video_shop_vorschau_kauf.webm`);
log(`🎬 ${OUT}/mm_w3cos_video_shop_vorschau_kauf.webm`);

// ---------- 3) Raum + Screen: Lobby-Podium trägt die Items ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const code = raum.code;
log(`Raum ${code}`);

const screenCtx = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  recordVideo: { dir: `${VIDEO_DIR}/screen`, size: { width: 1280, height: 800 } },
});
const screen = await screenCtx.newPage();
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });

// Coco joint per Profil-Kachel (Geräte-Token ⇒ „Willkommen zurück").
const handy = await browser.newPage({ viewport: { width: 390, height: 844 } });
await handy.addInitScript((t) => localStorage.setItem("mm:device", t), GERAET);
await handy.goto(`${URL_BASIS}/j/${code}`);
await handy.waitForSelector('[data-testid="raum-gefunden"]', { timeout: 8000 });
await handy.click('.profil-kachel:has-text("Coco")');
await handy.waitForSelector("text=Profil Coco gewählt", { timeout: 5000 });
await handy.click("button.primaer");
await handy.waitForSelector(".spieler-liste", { timeout: 8000 });
log("Coco ist im Raum (per Profil)");

// Zweiter Spieler als Gast — das Podium zeigt den Kontrast MIT/OHNE Items.
const gast = io(URL_BASIS, { transports: ["websocket"] });
const gastHello = await gast
  .timeout(5000)
  .emitWithAck("hello", { roomCode: code, role: "player", name: "Gast", avatar: "gelb" });
if (!gastHello.ok) throw new Error(`gast hello: ${gastHello.error}`);

await screen.waitForSelector('.podium-puppe[data-avatar*="hut-pirat"]', { timeout: 8000 });
await delay(1200); // Einflug-Animation ausklingen lassen
const podiumOk = await screen.evaluate(() => {
  const slot = document.querySelector('.podium-puppe[data-avatar*="hut-pirat"]');
  const svg = slot?.querySelector("svg");
  return {
    avatar: slot?.dataset.avatar ?? "",
    hut: svg?.classList.contains("mm-hut-an") ?? false,
    overlays: svg?.querySelectorAll("g.mm-meta-extra").length ?? 0,
    muster: (svg?.dataset.mmMuster ?? "") !== "",
    girlandeKlasse: slot?.classList.contains("mm-podium-girlande") ?? false,
    girlandeDeko: slot?.querySelector(".mm-podium-deko svg") !== null,
  };
});
check(
  "LOBBY-PODIUM: Cocos Puppe trägt Piratenhut (Overlay) + Tiger-Muster + Girlande",
  podiumOk.hut && podiumOk.overlays >= 1 && podiumOk.muster && podiumOk.girlandeDeko,
  podiumOk.avatar,
);
await schuss(screen, "03_lobby_podium_mit_items");

// ---------- 4) Intro: Einlauf-Rauchwolke an der Kandidaten-Karte ----------
const gm = io(URL_BASIS, { transports: ["websocket"] });
const gmHello = await gm
  .timeout(5000)
  .emitWithAck("hello", { roomCode: code, role: "gm", gmPin: raum.gmPin });
if (!gmHello.ok) throw new Error(`gm hello: ${gmHello.error}`);
await gm
  .timeout(5000)
  .emitWithAck("gm.cmd", { cmd: "settings.set", args: { modus: "quick" }, cmdId: "w3cos-0" });
await gm.timeout(5000).emitWithAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "w3cos-1" });

await screen.waitForSelector(".kandidaten-karte", { timeout: 10_000 });
// Erst wenn der Stinger weg ist, sind Kandidaten-Einflug + Rauch sichtbar.
await screen.waitForFunction(() => !document.querySelector(".stinger-overlay"), {
  timeout: 10_000,
});
const fxOk = await screen.evaluate(() => {
  const karte = Array.from(document.querySelectorAll(".kandidaten-karte")).find((k) =>
    (k.querySelector("[data-avatar]")?.getAttribute("data-avatar") ?? "").includes(
      "einlauf-rauchwolke",
    ),
  );
  const fx = karte?.querySelector(".mm-einlauf-fx");
  return { fxDa: fx !== null && fx !== undefined, wolken: fx?.children.length ?? 0 };
});
check(
  "INTRO: Kandidaten-Karte hat den Rauchwolken-Einlauf (5 Puffs)",
  fxOk.fxDa && fxOk.wolken === 5,
  `${fxOk.wolken} Wolken`,
);
// Beat-Sync: Karte fliegt bei ~1,1 s ein, Rauch zündet +0,2 s (Peak ~1,6 s,
// verblasst bis 2,8 s) — Schuss mitten im Puff-Moment.
await delay(1550);
await schuss(screen, "04_intro_einlauf_rauchwolke");
await delay(2600); // Cutscene fürs Video ausspielen
await screenCtx.close();
const screenVideo = readdirSync(`${VIDEO_DIR}/screen`)[0];
copyFileSync(`${VIDEO_DIR}/screen/${screenVideo}`, `${OUT}/mm_w3cos_video_podium_und_einlauf.webm`);
log(`🎬 ${OUT}/mm_w3cos_video_podium_und_einlauf.webm`);

// ---------- Fazit ----------
const rot = checks.filter((c) => !c.ok);
log(`Fertig: ${checks.length - rot.length}/${checks.length} Checks grün`);
await browser.close();
gm.close();
gast.close();
opener.close();
server.kill();
process.exit(rot.length === 0 ? 0 : 1);
