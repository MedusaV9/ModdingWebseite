// Stilprobe Kosmetik-Welle 3: rendert ALLE 22 neuen Items an 2 Affen mit dem
// ECHTEN Client-Renderer (schmueckePuppen) und schießt ein Übersichts-PNG.
// Trick: ein programmatischer Vite-Dev-Server serviert meta-avatar.ts samt
// ?raw-Imports exakt wie im Build — die Probe testet also den Produktionscode,
// keine Nachbau-Logik. Animationen werden per CSS auf einen aussagekräftigen
// Frame EINGEFROREN (negative animation-delay + paused), damit das PNG
// deterministisch ist (Einlauf-Effekte wären sonst längst verblasst).
//
//   npx tsx tools/art/cosmetics-probe.mts
//     → /opt/cursor/artifacts/mm_w3cos_stilprobe.png
//   OUT_DIR=/tmp/probe npx tsx tools/art/cosmetics-probe.mts   (Iterations-Läufe)
//
// Voraussetzungen: npm install, npx playwright install chromium.
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { chromium } from "playwright";
import { createServer } from "vite";
import { SHOP_ITEMS } from "../../shared/meta";

const WURZEL = resolve(import.meta.dirname, "../..");
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const PORT = Number(process.env.PROBE_PORT ?? 8461);
mkdirSync(OUT, { recursive: true });

// Die 2 Probe-Affen: bewusst die EXTREM-Anker (Kiki: Kopf tief, Paule: Kopf
// winzig) und verschiedene Farben, damit var(--fell) sichtbar durch die
// Muster scheint. NICHT blau für Paule — sein Tanktop ist hartkodiert #3B82F6
// und sähe sonst wie musterloses Fell aus.
const AFFE_A = "kiki-krawall.gelb";
const AFFE_B = "pumper-paule.rot";

// Anker-Check: ein Kopf- + ein Gesichts-Item auf ALLEN 14 Puppen — deckt
// Fehl-Sitze auf (die Köpfe teilen KEINE Position, siehe KOPF_ANKER).
const ALLE_AFFEN = [
  "don-bananas",
  "gitti-giro",
  "kiki-krawall",
  "baron-von-bananenstein",
  "oma-zinseszins",
  "pumper-paule",
  "schnarch-schorsch",
  "glitzer-gina",
  "dj-trommelfell",
  "astro-astrid",
  "kommissar-kokosnuss",
  "iro-ines",
  "abraka-dieter",
  "kahuna-kalle",
];

// Anzeige-Reihenfolge der Welle-3-Items (Metadaten kommen aus SHOP_ITEMS —
// fehlt eine Id im Katalog, bricht die Probe ab).
const SEKTIONEN: { titel: string; ids: string[] }[] = [
  {
    titel: "8 Kopf-Accessoires (#accessoire-Slot, Standard-Hut weicht)",
    ids: [
      "hut-blumenkranz",
      "hut-pirat",
      "hut-partyhut",
      "hut-propeller",
      "hut-teufelshoerner",
      "hut-heiligenschein",
      "hut-ritterhelm",
      "hut-krone",
    ],
  },
  {
    titel: "4 Gesichts-Accessoires (#kopf — nicken mit)",
    ids: ["gesicht-schnurrbart", "gesicht-augenklappe", "gesicht-sonnenbrille", "gesicht-kaugummi"],
  },
  {
    titel: "5 Fell-Muster (SVG-Pattern-Fill auf .fell + .fell-s)",
    ids: ["fell-tiger", "fell-dalmatiner", "fell-camo", "fell-sterne", "fell-goldglitzer"],
  },
  {
    titel: "3 Podium-Rahmen (um den eigenen Podest-Platz)",
    ids: ["podium-girlande", "podium-neon", "podium-goldrahmen"],
  },
  {
    titel: "2 Einlauf-Effekte (Kandidaten-Vorstellung, Frame bei ~0,25 s)",
    ids: ["einlauf-rauchwolke", "einlauf-blitz"],
  },
];

function itemInfo(id: string): { name: string; emoji: string; preis: number; minLevel?: number } {
  const item = SHOP_ITEMS.find((i) => i.id === id);
  if (!item) throw new Error(`Item fehlt im Katalog: ${id}`);
  return { name: item.name, emoji: item.emoji, preis: item.preis, minLevel: item.minLevel };
}

function karte(id: string): string {
  const info = itemInfo(id);
  const einlauf = id.startsWith("einlauf-") ? " mm-einlauf-demo" : "";
  const gate = info.minLevel !== undefined ? `<span class="gate">Lv ${info.minLevel}</span>` : "";
  return `
    <div class="item-karte" data-item="${id}">
      <div class="item-kopf">
        <span class="item-name">${info.emoji} ${info.name}</span>
        <span class="item-preis">${info.preis.toLocaleString("de-DE")} AT${gate ? " · " : ""}${gate}</span>
      </div>
      <div class="duo">
        <div class="puppe${einlauf}" data-avatar="${AFFE_A}.${id}" data-check="${id}"></div>
        <div class="puppe${einlauf}" data-avatar="${AFFE_B}.${id}" data-check="${id}"></div>
      </div>
    </div>`;
}

const KOMBI_A = "hut-krone+gesicht-sonnenbrille+fell-goldglitzer+podium-goldrahmen";
const KOMBI_B = "hut-pirat+gesicht-augenklappe+fell-tiger+podium-girlande";

const probeHtml = `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8" />
<title>MM Kosmetik-Welle 3 — Stilprobe</title>
<style>
  @font-face { font-family: "Bungee"; src: url("/fonts/bungee.woff2") format("woff2"); }
  @font-face { font-family: "Rubik"; src: url("/fonts/rubik.woff2") format("woff2"); }
  body { margin: 0; padding: 28px 32px 40px; background: #101b13; color: #fff6e3;
    font-family: "Rubik", system-ui, sans-serif; width: 1420px; box-sizing: border-box; }
  h1 { font-family: "Bungee", cursive; font-size: 1.7rem; margin: 0 0 4px; color: #f5b301; }
  .unter { margin: 0 0 18px; opacity: 0.75; font-size: 0.95rem; }
  h2 { font-family: "Bungee", cursive; font-size: 1.02rem; margin: 26px 0 10px; color: #8fe04b; }
  .grid { display: flex; flex-wrap: wrap; gap: 14px; }
  .item-karte { background: #1b2b1f; border: 2px solid #2e4634; border-radius: 14px;
    padding: 10px 12px 12px; width: 320px; box-sizing: border-box; }
  .item-kopf { display: flex; justify-content: space-between; align-items: baseline;
    gap: 8px; margin-bottom: 8px; }
  .item-name { font-weight: 700; font-size: 0.92rem; }
  .item-preis { font-size: 0.8rem; color: #f5b301; white-space: nowrap; }
  .gate { background: #f5b301; color: #1a1208; border-radius: 8px; padding: 0 6px;
    font-weight: 800; font-size: 0.75rem; }
  .duo { display: flex; gap: 10px; justify-content: center; }
  .puppe { width: 136px; border-radius: 12px; background: #24382a; padding: 4px; }
  .puppe svg { display: block; width: 100%; height: auto; }

  /* Deterministische Screenshots: Animationen auf einen sprechenden Frame
     einfrieren. Einlauf-FX separat (bei ~0,25 s sind Rauch/Blitz am Peak). */
  body.eingefroren svg *, body.eingefroren .puppe {
    animation-play-state: paused !important; animation-delay: -0.45s !important; }
  body.eingefroren .mm-einlauf-fx, body.eingefroren .mm-einlauf-fx * {
    animation-play-state: paused !important; animation-delay: -0.25s !important; }
</style>
</head>
<body class="eingefroren">
  <h1>MONKEY MONEY — Kosmetik-Welle 3 · Stilprobe</h1>
  <p class="unter">22 neue Items, gerendert mit dem echten Client-Renderer (schmueckePuppen)
    an ${AFFE_A} und ${AFFE_B} — Muster-Basis ist var(--fell), die Spielerfarbe scheint durch.</p>
  ${SEKTIONEN.map(
    (s) => `<h2>${s.titel}</h2><div class="grid">${s.ids.map(karte).join("")}</div>`,
  ).join("")}
  <h2>Anker-Check: Krone + Sonnenbrille auf allen 14 Puppen</h2>
  <div class="grid" id="anker-check">
    ${ALLE_AFFEN.map(
      (affe, i) =>
        `<div class="puppe" data-avatar="${affe}.${["gelb", "gruen", "orange", "lila", "tuerkis", "pink"][i % 6]}.hut-krone+gesicht-sonnenbrille"></div>`,
    ).join("")}
  </div>
  <h2>Referenz + Kombinationen (Slot-Stapelbarkeit)</h2>
  <div class="grid">
    <div class="item-karte">
      <div class="item-kopf"><span class="item-name">Basis ohne Items</span></div>
      <div class="duo">
        <div class="puppe" data-avatar="${AFFE_A}"></div>
        <div class="puppe" data-avatar="${AFFE_B}"></div>
      </div>
    </div>
    <div class="item-karte">
      <div class="item-kopf"><span class="item-name">Kombi „Goldkind“ + „Freibeuter“</span></div>
      <div class="duo">
        <div class="puppe" data-avatar="${AFFE_A}.${KOMBI_A}"></div>
        <div class="puppe" data-avatar="${AFFE_B}.${KOMBI_B}"></div>
      </div>
    </div>
  </div>
  <script type="module">
    import { ladeAllePuppen, onPuppenGeladen, fuellePuppen } from "/shared/fx/affe.ts";
    import { schmueckePuppen } from "/shared/meta-avatar.ts";
    const fuelle = () => {
      fuellePuppen(document.body);
      schmueckePuppen(document.body);
      const slots = document.querySelectorAll("[data-avatar]");
      const voll = document.querySelectorAll("[data-avatar][data-befuellt]").length;
      if (voll === slots.length) document.body.dataset.fertig = "1";
    };
    onPuppenGeladen(fuelle);
    ladeAllePuppen();
    fuelle();
  </script>
</body>
</html>`;

// ---------- Vite-Dev-Server mit Probe-Route (Pre-Middleware, vor SPA-Fallback) ----------
const vite = await createServer({
  configFile: resolve(WURZEL, "vite.config.ts"),
  server: { port: PORT, strictPort: true },
  logLevel: "warn",
  plugins: [
    {
      name: "mm-stilprobe-seite",
      configureServer(server) {
        server.middlewares.use("/__stilprobe", (req, res) => {
          void server.transformIndexHtml(req.url ?? "/__stilprobe", probeHtml).then((html) => {
            res.setHeader("content-type", "text/html");
            res.end(html);
          });
        });
      },
    },
  ],
});
await vite.listen();
console.log(`[stilprobe] Vite-Dev-Server auf :${PORT}`);

// ---------- Playwright: rendern, prüfen, schießen ----------
const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 1420, height: 1200 },
  deviceScaleFactor: Number(process.env.SCALE ?? 1),
});
page.on("console", (msg) => {
  if (msg.type() === "error") console.log(`[stilprobe] Browser-Fehler: ${msg.text()}`);
});
page.on("pageerror", (err) => console.log(`[stilprobe] Seiten-Fehler: ${err.message}`));
await page.goto(`http://localhost:${PORT}/__stilprobe`);
try {
  await page.waitForSelector('body[data-fertig="1"]', { timeout: 15_000 });
} catch (err) {
  const stand = await page.evaluate(() => ({
    slots: document.querySelectorAll("[data-avatar]").length,
    voll: document.querySelectorAll("[data-avatar][data-befuellt]").length,
  }));
  console.log(`[stilprobe] Diagnose: ${stand.voll}/${stand.slots} Slots befüllt`);
  throw err;
}
await page.waitForTimeout(500); // Fonts + SMIL-Erstframe

// DOM-Beleg pro Item: Overlay injiziert / Muster-Pattern aktiv / Rahmen-Klasse
// gesetzt / Einlauf-Partikel vorhanden — auf BEIDEN Affen.
const befunde = await page.evaluate(() => {
  const zeilen: { id: string; ok: boolean; detail: string }[] = [];
  for (const slot of document.querySelectorAll<HTMLElement>("[data-check]")) {
    const id = slot.dataset.check ?? "?";
    const svg = slot.querySelector("svg");
    let ok = false;
    let detail = "kein SVG";
    if (svg) {
      if (id.startsWith("hut-") || id.startsWith("gesicht-")) {
        const g = svg.querySelectorAll("g.mm-meta-extra").length;
        ok = g > 0 && svg.classList.contains("mm-hut-an") === id.startsWith("hut-");
        detail = `${g} Overlay-Gruppe(n), mm-hut-an=${svg.classList.contains("mm-hut-an")}`;
      } else if (id.startsWith("fell-")) {
        const muster = svg.dataset.mmMuster ?? "";
        const fellEl = svg.querySelector(".fell");
        const fill = fellEl ? getComputedStyle(fellEl).fill : "kein .fell";
        ok =
          muster !== "" && svg.querySelector(`pattern#${muster}`) !== null && fill.includes("url");
        detail = `pattern=${muster || "FEHLT"}, fill=${fill}`;
      } else if (id.startsWith("podium-")) {
        ok = slot.className.includes("mm-podium-");
        detail = `Klassen=${slot.className}`;
      } else if (id.startsWith("einlauf-")) {
        const fx = slot.querySelector(".mm-einlauf-fx");
        ok = fx !== null && fx.children.length > 0;
        detail = `${fx?.children.length ?? 0} FX-Kind(er)`;
      }
    }
    zeilen.push({ id, ok, detail });
  }
  return zeilen;
});
let rot = 0;
for (const b of befunde) {
  if (!b.ok) rot++;
  console.log(`[stilprobe] ${b.ok ? "✅" : "❌"} ${b.id} — ${b.detail}`);
}
console.log(`[stilprobe] DOM-Belege: ${befunde.length - rot}/${befunde.length} grün`);

const pfad = `${OUT}/mm_w3cos_stilprobe.png`;
await page.screenshot({ path: pfad, fullPage: true });
console.log(`[stilprobe] 📸 ${pfad}`);

// DETAILS=1: jede Item-Karte einzeln in Groß (Sichtprüfung feiner Muster).
if (process.env.DETAILS === "1") {
  for (const karteEl of await page.locator(".item-karte[data-item]").all()) {
    const id = await karteEl.getAttribute("data-item");
    await karteEl.screenshot({ path: `${OUT}/detail_${id}.png` });
  }
  await page.locator("#anker-check").screenshot({ path: `${OUT}/detail_anker-check.png` });
  console.log(`[stilprobe] 📸 Detail-Karten unter ${OUT}/detail_*.png`);
}

await browser.close();
await vite.close();
process.exit(rot === 0 ? 0 : 1);
