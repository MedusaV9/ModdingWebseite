// Meta/Sicherheits-Beweis (Playtest-4-Fixes, Playwright mit 2 Browser-Kontexten):
//   P1  Geräte-Filter — Gerät B sieht Annas Profil NIE unter „Willkommen zurück"
//   P1  PIN-Echtprüfung — „Anderes Profil laden" lehnt falsche PIN server-seitig
//       ab; vertrautes Gerät loggt DIREKT ein (Hinweis statt Schein-Dialog)
//   P2  Board-Fortschritt, Shop-Chips + Willkommens-Paket + Verdien-Hinweis,
//       Pass-Schrift/Saison-Copy, Profil-Karte „Statistik aktualisiert sich…",
//       Admin-Fehlerhaft-Queue mit Quarantäne/Entkräften/Geprüft + Refresh
//
//   node tools/screenshots/meta-sicherheit-proof.mjs
//     → /opt/cursor/artifacts/mm_fixmeta_*.png + Video
//
// Voraussetzungen: npm run build, npx playwright install chromium.
import { spawn } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";

const PORT = Number(process.env.PROOF_PORT ?? 8377);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const DATA = "/tmp/mm-fixmeta-proof-data";
const VIDEO_DIR = "/tmp/mm-fixmeta-video";
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[fixmeta-proof] ${t}`);
const fail = (t) => {
  console.error(`[fixmeta-proof] ❌ ${t}`);
  process.exit(1);
};
const ok = (bedingung, t) => (bedingung ? log(`${t} ✅`) : fail(t));

async function schuss(page, name) {
  await page.screenshot({ path: `${OUT}/mm_fixmeta_${name}.png` });
  log(`📸 mm_fixmeta_${name}.png`);
}

// ---------- 1) Wegwerf-Daten + geflaggte Fragen fürs Admin-Demo seeden ----------
rmSync(DATA, { recursive: true, force: true });
rmSync(VIDEO_DIR, { recursive: true, force: true });
mkdirSync(`${DATA}/meta`, { recursive: true });
const Q1 = "q_essen_trinken_bier_wein_getraenke_000001";
const Q2 = "q_essen_trinken_bier_wein_getraenke_000002";
const leereFrage = () => ({
  ausspielungen: 3,
  antworten: 3,
  richtig: 1,
  zeitSummeMs: 9000,
  zeitN: 3,
  tippKaeufe: 0,
  flags: [],
  gespieltTs: [],
  proModus: {},
});
const jetzt = Date.now();
writeFileSync(
  `${DATA}/meta/stats.json`,
  JSON.stringify({
    schemaVersion: 1,
    verarbeitet: [],
    profile: {},
    fragen: {
      [Q1]: {
        ...leereFrage(),
        flags: [
          { grund: "antwort-falsch", ts: jetzt - 3_600_000, matchId: "m_demo1" },
          { grund: "unklar-formuliert", ts: jetzt - 1_800_000, matchId: "m_demo2" },
        ],
      },
      [Q2]: {
        ...leereFrage(),
        flags: [{ grund: "tippfehler", ts: jetzt - 600_000, matchId: "m_demo3" }],
      },
    },
    feedback: [],
    aktualisiertTs: jetzt,
  }),
);

// ---------- 2) Server starten ----------
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: DATA, ADMIN_PIN: "7777" },
  stdio: ["ignore", "inherit", "inherit"],
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
if (!bootOk) fail(`Server auf :${PORT} kam nicht hoch`);
log(`Server läuft auf :${PORT}`);

async function api(pfad, body) {
  const r = await fetch(`${URL_BASIS}${pfad}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: r.status, json: await r.json().catch(() => ({})) };
}

// ---------- 3) Setup: 2 Profile auf Gerät A (Anna mit PIN, Ben ohne) ----------
const GERAET_A = "d_geraet_anna";
const GERAET_B = "d_geraet_fremd";
const anna = await api("/api/meta/profile", {
  name: "Anna",
  avatar: "don-bananas.gelb",
  pin: "4321",
  deviceToken: GERAET_A,
});
if (anna.status !== 200) log(`Antwort ${anna.status}: ${JSON.stringify(anna.json)}`);
ok(anna.status === 200, "Profil Anna (PIN 4321) angelegt");
ok(
  anna.json.profil.at.verfuegbar === 300,
  `Willkommens-Paket: erstes Geräte-Profil startet mit 300 AT (ist: ${anna.json.profil.at.verfuegbar})`,
);
const ben = await api("/api/meta/profile", {
  name: "Ben",
  avatar: "don-bananas.rot",
  deviceToken: GERAET_A,
});
ok(
  ben.json.profil.at.verfuegbar === 0,
  "Willkommens-Paket ist idempotent: zweites Profil desselben Geräts bekommt 0 AT",
);

// Server-seitiger Geräte-Filter (der eigentliche P1-Kern):
const fremdListe = await api(`/api/meta/profile?device=${GERAET_B}`);
ok(
  fremdListe.json.profile.length === 0,
  "API: fremdes Gerät bekommt LEERE Profil-Liste (Server filtert)",
);

const browser = await chromium.launch();

// ---------- 4) Gerät A: „Willkommen zurück" + Direkt-Login ohne PIN-Dialog ----------
const ctxA = await browser.newContext({ viewport: { width: 390, height: 844 } });
await ctxA.addInitScript((t) => localStorage.setItem("mm:device", t), GERAET_A);
const seiteA = await ctxA.newPage();
await seiteA.goto(`${URL_BASIS}/player`);
await seiteA.waitForSelector("text=Willkommen zurück (dieses Gerät):", { timeout: 5000 });
await seiteA.waitForSelector('.profil-kachel:has-text("Anna")', { timeout: 5000 });
await schuss(seiteA, "01_geraet_a_willkommen_eigene_profile");
log("Gerät A sieht die EIGENEN Profile (Anna + Ben) ✅");

await seiteA.click('.profil-kachel:has-text("Anna")');
await seiteA.waitForSelector('[data-testid="pin-hinweis"]', { timeout: 5000 });
const hinweisA = await seiteA.textContent('[data-testid="pin-hinweis"]');
ok(
  hinweisA.includes("vertrauenswürdig"),
  "Direkt-Login auf vertrautem Gerät MIT Hinweis (kein PIN-Dialog)",
);
const pinDialoge = await seiteA.locator('input[type="password"]').count();
ok(pinDialoge === 0, "KEIN Schein-PIN-Dialog auf vertrautem Gerät");
await schuss(seiteA, "02_geraet_a_direktlogin_vertraut");

// ---------- 5) Gerät B (2. Browser-Kontext, mit Video): fremde Profile unsichtbar ----------
const ctxB = await browser.newContext({
  viewport: { width: 390, height: 844 },
  recordVideo: { dir: VIDEO_DIR, size: { width: 390, height: 844 } },
});
await ctxB.addInitScript((t) => localStorage.setItem("mm:device", t), GERAET_B);
const seiteB = await ctxB.newPage();
// RUHIG: kleine Pausen, damit das Video als Demo nachvollziehbar bleibt.
const RUHIG = 900;
await seiteB.goto(`${URL_BASIS}/player`);
await seiteB.waitForSelector('[data-testid="anderes-profil"]', { timeout: 5000 });
await delay(RUHIG); // Profil-Fetch sicher abgeschlossen + Video-Lesbarkeit
const inhaltB = await seiteB.content();
ok(!inhaltB.includes("Willkommen zurück"), "Gerät B: KEIN „Willkommen zurück“-Block");
ok(!inhaltB.includes("Anna"), "Gerät B: Annas Profil ist NICHT sichtbar (P1-Fix)");
await schuss(seiteB, "03_geraet_b_keine_fremden_profile");

// „Anderes Profil laden": falsche PIN wird server-seitig abgelehnt.
await seiteB.click('[data-testid="anderes-profil"]');
await seiteB.waitForSelector('[data-testid="anderes-profil-formular"]', { timeout: 5000 });
await delay(RUHIG);
await seiteB.type('[data-testid="anderes-profil-formular"] input[type="text"]', "Anna", {
  delay: 120,
});
await seiteB.type('[data-testid="anderes-profil-formular"] input[type="password"]', "0000", {
  delay: 160,
});
await delay(RUHIG / 2);
await seiteB.click('[data-testid="anderes-profil-laden"]');
await seiteB.waitForSelector("text=PIN falsch.", { timeout: 5000 });
const nachFalsch = await seiteB.content();
ok(!nachFalsch.includes("Profil geladen"), "Falsche PIN 0000 lädt NICHTS (P1-Fix Scheinprüfung)");
await delay(RUHIG);
await schuss(seiteB, "04_geraet_b_pin_falsch_abgelehnt");

// Korrekte PIN ⇒ Profil geladen + Gerät gebunden.
await seiteB.fill('[data-testid="anderes-profil-formular"] input[type="password"]', "");
await seiteB.type('[data-testid="anderes-profil-formular"] input[type="password"]', "4321", {
  delay: 160,
});
await delay(RUHIG / 2);
await seiteB.click('[data-testid="anderes-profil-laden"]');
await seiteB.waitForSelector("text=Profil geladen", { timeout: 5000 });
await seiteB.waitForSelector("text=Anna", { timeout: 5000 });
await delay(RUHIG);
await schuss(seiteB, "05_geraet_b_pin_korrekt_geladen");
const jetztGebunden = await api(`/api/meta/profile?device=${GERAET_B}`);
ok(
  jetztGebunden.json.profile.some((p) => p.name === "Anna"),
  "Nach korrekter PIN ist Gerät B an Annas Profil gebunden",
);
await ctxB.close(); // Video fertig schreiben
const videoQuelle = (await import("node:fs")).readdirSync(VIDEO_DIR)[0];
copyFileSync(`${VIDEO_DIR}/${videoQuelle}`, `${OUT}/mm_fixmeta_video_anderes_profil_pin.webm`);
log("🎬 mm_fixmeta_video_anderes_profil_pin.webm");

// ---------- 6) Landing (Gerät A): Boards-Fortschritt, Shop-Chips, Pass ----------
const landing = await ctxA.newPage();
await landing.goto(URL_BASIS);
await landing.click('button:has-text("Profile · Shop")');
await landing.waitForSelector("text=Dein Fortschritt zur Wertung", { timeout: 5000 });
await landing.click('.karte button:has-text("Anna")');
await landing.waitForSelector('[data-testid="board-fortschritt"]', { timeout: 5000 });
const fortschritte = await landing.locator('[data-testid="board-fortschritt"]').allTextContents();
ok(
  fortschritte.length === 4,
  `alle 4 Boards zeigen persönlichen Fortschritt (${fortschritte.length})`,
);
ok(
  fortschritte.some((t) => t.includes("bis") && t.includes("Wertung")),
  "„Noch X bis zur Wertung“-Zeilen sichtbar",
);
await schuss(landing, "06_boards_persoenlicher_fortschritt");

// Shop: Chips mit Counts + Willkommens-Titel als Geschenk (Anna, 300 AT).
await landing.click('button:has-text("🛍 Shop")');
await landing.waitForSelector('[data-testid="shop-chips"]', { timeout: 5000 });
await landing.waitForSelector("text=300 AT verfügbar", { timeout: 5000 });
const chipAlle = await landing.locator(".chip", { hasText: "Alle (" }).textContent();
log(`Chip-Leiste: ${chipAlle.trim()}`);
await landing.click('.chip:has-text("Titel")');
await landing.waitForSelector("text=🎁 Geschenk", { timeout: 5000 });
await schuss(landing, "07_shop_chips_titel_geschenk");
// Preis-Sortierung anschalten (kaufbar-Filter + Preis ↑).
await landing.click('.chip:has-text("Alle (")');
await landing.click('.chip:has-text("Preis sortieren")');
await landing.waitForSelector('.chip:has-text("Preis ↑")', { timeout: 5000 });

// Verdien-Hinweis: Ben (0 AT) statt 51 toter Knöpfe.
await landing.click('.karte button:has-text("Ben")');
await landing.waitForSelector('[data-testid="verdien-hinweis"]', { timeout: 5000 });
const verdienen = await landing.textContent('[data-testid="verdien-hinweis"]');
ok(verdienen.includes("Verdiene AT durch Matches"), "Null-AT-Profil sieht Verdien-Hinweis");
await schuss(landing, "08_shop_verdien_hinweis_null_at");

// Pass: Schriftgrößen ≥ 12px + korrekte Saison-Copy (Archiv statt Verfall).
await landing.click('button:has-text("🍌 Pass & Quests")');
await landing.waitForSelector("text=Saison-exklusive Belohnungen", { timeout: 5000 });
const copy = await landing.textContent(".karte:has-text('Saison-exklusive Belohnungen')");
ok(
  copy.includes("Schon verdiente Items bleiben dauerhaft"),
  "Saison-Copy: verdiente Items bleiben (kein falscher Verfall)",
);
const schriften = await landing.evaluate(() => {
  const px = (sel) => {
    const el = document.querySelector(sel);
    return el ? parseFloat(getComputedStyle(el).fontSize) : null;
  };
  return {
    nr: px(".pass-stufe .stufe-nr"),
    klein: px(".pass-stufe small"),
    gate: px(".level-gate"),
  };
});
ok(
  schriften.nr >= 12 && schriften.klein >= 12,
  `Pass-Schrift ≥ 12px (stufe-nr ${schriften.nr}px, small ${schriften.klein}px)`,
);
await schuss(landing, "09_pass_lesbare_schrift_saison_copy");

// ---------- 7) Profil-Karte: „Statistik aktualisiert sich…" (90-s-Ruhefenster) ----------
// Buchung simulieren: Profil bekommt eine gebuchte matchId, die die Analytics
// noch nicht verarbeitet hat (Datei-Edit ist ok — der Store liest pro Op frisch).
const profDatei = `${DATA}/meta/profiles.json`;
const prof = JSON.parse(readFileSync(profDatei, "utf8"));
const annaId = anna.json.profil.profileId;
prof.profile[annaId].gebuchteMatches = ["m_frisch_gebucht"];
prof.profile[annaId].at = { gesamt: 1420, verfuegbar: 1420 };
writeFileSync(profDatei, JSON.stringify(prof));
await landing.click('button:has-text("👤 Profil-Karte")');
await landing.click('.karte button:has-text("Anna")');
await landing.waitForSelector('[data-testid="stats-ausstehend"]', { timeout: 5000 });
log(
  "Profil-Karte meldet „Statistik aktualisiert sich…“ solange die Buchung im Ruhefenster steckt ✅",
);
await schuss(landing, "10_karte_statistik_aktualisiert_sich");

// ---------- 8) Admin: Fehlerhaft-Queue mit Aktionen + Refresh + Zeitstempel ----------
const admin = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await admin.goto(`${URL_BASIS}/admin`);
await admin.fill("#pin", "7777");
await admin.click("#rein");
await admin.waitForSelector('button[data-aktion="quarantaene"]', { timeout: 8000 });
const titel = await admin.textContent("#titel-fehlerhaft");
ok(titel.includes("Stand"), `Queue-Titel trägt Zeitstempel: „${titel.trim()}“`);
ok(
  (await admin.locator('button[data-aktion="entkraeften"]').count()) >= 1 &&
    (await admin.locator('button[data-aktion="geprueft"]').count()) >= 2,
  "Queue hat Quarantäne-/Entkräften-/Geprüft-Aktionen (nicht mehr read-only)",
);
await schuss(admin, "11_admin_queue_mit_aktionen");

await admin.click(`button[data-aktion="quarantaene"][data-qid="${Q1}"]`);
await admin.waitForSelector("text=QUARANTÄNE (aus der Rotation)", { timeout: 8000 });
await admin.click(`button[data-aktion="geprueft"][data-qid="${Q2}"]`);
await admin.waitForSelector("text=✓ geprüft", { timeout: 8000 });
await admin.click("#refresh");
await admin.waitForSelector("text=aktualisiert", { timeout: 15000 });
await schuss(admin, "12_admin_quarantaene_geprueft_refresh");

// Server-Beleg: Quarantäne persistiert + wirkt (moderation.json + Reports).
const rep = await fetch(`${URL_BASIS}/api/admin/reports?refresh=0`, {
  headers: { "x-admin-pin": "7777" },
}).then((r) => r.json());
const zeileQ1 = rep.reports.fehlerhaft.find((f) => f.questionId === Q1);
ok(zeileQ1?.quarantaene === true, "Report bestätigt: Frage 1 ist in Quarantäne");
const modDatei = JSON.parse(readFileSync(`${DATA}/meta/moderation.json`, "utf8"));
ok(modDatei.fragen[Q1]?.quarantaene === true, "moderation.json persistiert die Quarantäne");

await browser.close();
server.kill();
log("ALLE BEWEISE ERBRACHT — Screenshots + Video unter " + OUT);
process.exit(0);
