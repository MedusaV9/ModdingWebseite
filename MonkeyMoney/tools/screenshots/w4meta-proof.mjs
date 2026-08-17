// W4-Meta-Beweis (UI/UX-Welle 4, Meta-Screens): startet den gebauten Server
// mit geseedeten Meta-Daten (Profil „Mia" mit AT/Besitz/Pass-XP/Quests, drei
// Board-Konkurrenten, eine öffentliche Lobby mit 2 Spielern) und schießt die
// 6 Screens (Landing, Bestenlisten, Shop, Pass, Profil-Karte, Training) auf
// Desktop 1280 und Mobile 390 — als Vorher/Nachher-Paare für die Welle.
//
//   LABEL=vorher  node tools/screenshots/w4meta-proof.mjs   → *_vorher_*.png
//   LABEL=nachher node tools/screenshots/w4meta-proof.mjs   → *_nachher_*.png
//   OUT_DIR=/tmp/mm-w4meta node …                           → Iterations-Läufe
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.W4META_PORT ?? 8461);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const LABEL = process.env.LABEL ?? "nachher";
const DATA = "/tmp/mm-w4meta-data";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[w4meta] ${t}`);
const GERAET = "d_w4meta_mia";

// ---------- 1) Server mit frischem Daten-Verzeichnis starten ----------
rmSync(DATA, { recursive: true, force: true });
mkdirSync(`${DATA}/meta`, { recursive: true });
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

async function api(pfad, body) {
  const r = await fetch(`${URL_BASIS}${pfad}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

// ---------- 2) Profile anlegen + Meta-Daten seeden (Datei-Edits sind ok:
// die Stores lesen pro Operation frisch — Muster: meta-sicherheit-proof) ----------
const mia = await api("/api/meta/profile", {
  name: "Mia",
  avatar: "glitzer-gina.pink",
  deviceToken: GERAET,
});
const miaId = mia.json.profil.profileId;
const konkurrenz = [];
for (const [name, avatar] of [
  ["Leo", "don-bananas.gelb"],
  ["Zoe", "kiki-krawall.tuerkis"],
  ["Rex", "pumper-paule.orange"],
]) {
  const p = await api("/api/meta/profile", { name, avatar, deviceToken: `d_w4meta_${name}` });
  konkurrenz.push(p.json.profil.profileId);
}

// Profil-Datei: Mia bekommt AT-Konto, Besitz + Ausrüstung (Ausweis/Shop-Demo);
// die Konkurrenz bekommt gestaffelte Lifetime-AT (Money-Boss-Podest).
const profDatei = `${DATA}/meta/profiles.json`;
const prof = JSON.parse(readFileSync(profDatei, "utf8"));
prof.profile[miaId].at = { gesamt: 23_400, verfuegbar: 6_150 };
prof.profile[miaId].besitz.push(
  "hut-pirat",
  "gesicht-sonnenbrille",
  "fell-tiger",
  "banner-dschungelnacht",
  "titel-bananen-baron",
  "buzzer-entenquak",
  "podium-neon",
  "konfetti-bananen-regen",
);
prof.profile[miaId].ausgeruestet = {
  hut: "hut-pirat",
  titel: "titel-bananen-baron",
  banner: "banner-dschungelnacht",
};
const konkurrenzAt = [18_200, 9_600, 4_100];
for (let i = 0; i < konkurrenz.length; i++) {
  prof.profile[konkurrenz[i]].at = { gesamt: konkurrenzAt[i], verfuegbar: konkurrenzAt[i] };
}
writeFileSync(profDatei, JSON.stringify(prof));

// Stats-Datei: Kategorie-Meister/Blitz-Buzzer/Comeback-Boards + Karten-Bestwerte.
const leereStats = () => ({
  beantwortet: 0,
  richtig: 0,
  matrix: {},
  zeitBuckets: new Array(40).fill(0),
  schnellsteAntwortMs: null,
  schnelleAntworten: 0,
  schnelleFalsch: 0,
  matches: 0,
  siege: 0,
  atLifetime: 0,
  besterEndstand: 0,
  laengsteSerie: 0,
  aktuelleSerie: 0,
  laengsteSiegesserie: 0,
  aktuelleSiegesserie: 0,
  mitJoker: { n: 0, richtig: 0 },
  ohneJoker: { n: 0, richtig: 0 },
  wettenGewonnen: 0,
  wettenVerloren: 0,
  groessterWettgewinn: 0,
  gestohlen: 0,
  bestohlen: 0,
  comebackSiege: 0,
  comebackMatches: 0,
});
const statsFuer = (kategorie, quote, medianBucket, comeback, extra) => {
  const s = leereStats();
  s.matrix[`${kategorie}|medium`] = { n: 40, richtig: Math.round(40 * quote) };
  s.matrix["essen|easy"] = { n: 24, richtig: 11 }; // Nemesis-Kandidat
  s.zeitBuckets[medianBucket] = 36;
  s.beantwortet = 64;
  s.richtig = Math.round(40 * quote) + 11;
  s.comebackSiege = comeback[0];
  s.comebackMatches = comeback[1];
  return { ...s, ...extra };
};
const statsDatei = `${DATA}/meta/stats.json`;
writeFileSync(
  statsDatei,
  JSON.stringify({
    schemaVersion: 1,
    verarbeitet: [],
    profile: {
      [miaId]: statsFuer("games", 0.82, 3, [4, 6], {
        matches: 21,
        siege: 9,
        besterEndstand: 12_400,
        laengsteSerie: 7,
        schnellsteAntwortMs: 1340,
      }),
      [konkurrenz[0]]: statsFuer("wissen", 0.74, 5, [5, 6], {
        matches: 18,
        siege: 7,
        besterEndstand: 9_800,
        laengsteSerie: 5,
        schnellsteAntwortMs: 1810,
      }),
      [konkurrenz[1]]: statsFuer("popkultur", 0.69, 2, [2, 7], {
        matches: 12,
        siege: 3,
        besterEndstand: 7_200,
        laengsteSerie: 4,
        schnellsteAntwortMs: 990,
      }),
      [konkurrenz[2]]: statsFuer("sport", 0.61, 7, [1, 5], {
        matches: 9,
        siege: 2,
        besterEndstand: 5_100,
        laengsteSerie: 3,
        schnellsteAntwortMs: 2350,
      }),
    },
    fragen: {},
    feedback: [],
    aktualisiertTs: Date.now(),
  }),
);

// Pass-Datei: Mia auf Stufe 8 (840 XP), etwas Bonus-AT — Saison-Id aus dem
// Wire holen (der Store rollt sonst still in die aktuelle Saison).
const passVorab = await api(`/api/meta/profile/${miaId}/pass`);
const saisonId = passVorab.json.pass.saison.id;
const tagKey = passVorab.json.pass.tagKey;
writeFileSync(
  `${DATA}/meta/pass.json`,
  JSON.stringify({
    schemaVersion: 1,
    profile: {
      [miaId]: { saisonId, xp: 840, stufe: 8, verdient: [], atBonus: 150, archiv: [] },
    },
  }),
);

// Quest-Datei: Teil-Fortschritt auf den aktiven Quests (Ring-/Balken-Demo).
const questIds = passVorab.json.pass.quests.map((q) => ({ id: q.questId, art: q.art, z: q.ziel }));
const daily = {};
const monat = {};
for (const [i, q] of questIds.entries()) {
  const stand = {
    fortschritt: Math.min(q.z - (i % 2 === 0 ? 1 : 0), Math.ceil(q.z / 2)),
    fertig: false,
  };
  if (i === 0) stand.fortschritt = q.z; // eine Quest fertig
  if (stand.fortschritt >= q.z) stand.fertig = true;
  if (q.art === "daily") daily[q.id] = stand;
  else monat[q.id] = stand;
}
writeFileSync(
  `${DATA}/meta/quests.json`,
  JSON.stringify({
    schemaVersion: 1,
    profile: { [miaId]: { tagKey, daily, saisonId, monat, gebuchteMatches: [] } },
  }),
);

// Trainings-Statistik: Übungs-Datei direkt seeden (Format: practice.ts) —
// gefüllte Stats-Karte + 4er-Serie fürs Streak-Chip im Frage-Screenshot.
mkdirSync(`${DATA}/meta/uebung`, { recursive: true });
writeFileSync(
  `${DATA}/meta/uebung/${miaId}.json`,
  JSON.stringify({
    schemaVersion: 1,
    stats: {},
    gesamt: { richtig: 34, falsch: 12 },
    serie: 4,
    besteSerie: 9,
    kategorien: {
      "blockbuster-hollywood": { richtig: 9, falsch: 1 },
      "fussball-legenden": { richtig: 4, falsch: 6 },
      "erdkunde-extrem": { richtig: 3, falsch: 5 },
    },
  }),
);
log("Meta-Daten geseedet (Mia + 3 Konkurrenten, Pass Stufe 8, Quests, Training)");

// ---------- 3) Öffentliche Lobby mit 2 Spielern (Lobby-Browser-Karte) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener.timeout(5000).emitWithAck("room.create", {
  role: "screen",
  origin: URL_BASIS,
  oeffentlich: true,
  name: "Bananen-Bande",
});
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const spielerSockets = [];
for (const [name, avatar] of [
  ["Leo", "don-bananas.gelb"],
  ["Zoe", "kiki-krawall.tuerkis"],
]) {
  const s = io(URL_BASIS, { transports: ["websocket"] });
  const antwort = await s
    .timeout(5000)
    .emitWithAck("hello", { roomCode: raum.code, role: "player", name, avatar });
  if (!antwort.ok) throw new Error(`hello ${name}: ${antwort.error}`);
  spielerSockets.push(s);
}
log(`Öffentliche Lobby ${raum.code} mit 2 Spielern offen`);

// ---------- 4) Screenshots: Desktop 1280 + Mobile 390 ----------
const browser = await chromium.launch();

async function schiesse(viewport, suffix) {
  const ctx = await browser.newContext({ viewport });
  await ctx.addInitScript((t) => localStorage.setItem("mm:device", t), GERAET);
  const page = await ctx.newPage();
  const schuss = async (name) => {
    const pfad = `${OUT}/mm_w4meta_${name}_${LABEL}_${suffix}.png`;
    await page.screenshot({ path: pfad });
    log(`📸 ${pfad}`);
  };

  // Landing mit Lobby-Browser-Karte
  await page.goto(URL_BASIS);
  await page.waitForSelector('[data-testid="lobby-zeile"]', { timeout: 8000 });
  await delay(600); // Logo-Einflug ausklingen lassen
  await schuss("01_landing");

  // Meta öffnen → Bestenlisten (Profil Mia wählen für Fortschritts-Zeilen)
  await page.click('button:has-text("Profile · Shop")');
  await page.waitForSelector("text=Money-Boss", { timeout: 8000 });
  await page.click('.karte button:has-text("Mia")');
  await page.waitForSelector('[data-testid="board-fortschritt"]', { timeout: 8000 });
  await delay(400);
  await schuss("02_boards");

  // Shop
  await page.click('.meta-tabs button:has-text("Shop")');
  await page.waitForSelector('[data-testid="shop-chips"]', { timeout: 8000 });
  await delay(700); // Puppen laden
  await schuss("03_shop");
  // Vitrine selbst (Abschnitts-Header + Karten) — im Vorher-Stand ohne Header
  // einfach zur Item-Wand scrollen (gleicher Bildausschnitt, fairer Vergleich).
  const anker =
    (await page.locator('[data-testid="shop-abschnitt-accessoire"]').count()) > 0
      ? '[data-testid="shop-abschnitt-accessoire"]'
      : ".shop-grid";
  await page.locator(anker).first().scrollIntoViewIfNeeded();
  await page.evaluate(() => document.querySelector(".meta-wrap")?.scrollBy(0, -60));
  await delay(600); // Thumbnails laden
  await schuss("03b_shop_vitrine");
  await page.evaluate(() => document.querySelector(".meta-wrap")?.scrollTo(0, 0));

  // Pass
  await page.click('.meta-tabs button:has-text("Pass")');
  await page.waitForSelector("text=Bananen-Pass", { timeout: 8000 });
  await delay(500);
  await schuss("04_pass");

  // Profil-Karte
  await page.click('.meta-tabs button:has-text("Profil")');
  await page.waitForSelector("text=Lieblings-Kategorie", { timeout: 8000 });
  await delay(500);
  await schuss("05_karte");

  // Training: Frage holen + antworten (Auflösung + Stats im Bild)
  await page.click('.meta-tabs button:has-text("Training")');
  await page.waitForSelector("text=Trainingslager", { timeout: 8000 });
  await page.click('button:has-text("Los geht")');
  await page.waitForSelector(".training-antworten button", { timeout: 8000 });
  await schuss("06_training_frage");
  await page.click(".training-antworten button >> nth=0");
  await page.waitForSelector('button:has-text("Nächste")', { timeout: 8000 });
  await delay(700);
  await schuss("07_training_aufloesung");

  // Session-Ende-Karte (Welle 4) — im Vorher-Stand existiert der Knopf nicht.
  if ((await page.locator('[data-testid="session-ende"]').count()) > 0) {
    await page.click('[data-testid="session-ende"]');
    await page.waitForSelector('[data-testid="training-fazit"]', { timeout: 4000 });
    await delay(700);
    await schuss("08_training_fazit");
  }

  await ctx.close();
}

await schiesse({ width: 1280, height: 900 }, "desktop");
await schiesse({ width: 390, height: 844 }, "mobil");

await browser.close();
for (const s of spielerSockets) s.close();
opener.close();
server.kill();
log(`Fertig — Label „${LABEL}" unter ${OUT}`);
process.exit(0);
