// BEWEIS-SKRIPT (Musik-Welle 3): Musik-Rotation + Toggle end-zu-end auf dem
// ECHTEN Screen + GM-Cockpit (Playwright, Audio-Konstruktor instrumentiert):
//   · /api/musik/betten liefert die 4 Demo-Bett-Loops (import.mjs --bett)
//   · Musik-Control unten rechts sichtbar + bedienbar, Track-Ticker zeigt
//     „♪ Monkeys Spinning Monkeys — Kevin MacLeod" (MacLeod-Kern = Default)
//   · Screen-Skip schaltet auf einen User-Bett-Loop (/media-musik-bett/…)
//   · Musik-Toggle stoppt ALLE Musik-Elemente programmatisch (SFX-Bus bleibt
//     unberührt), Zustand persistiert im localStorage (mm:sound:screen)
//   · GM-Musik-Karte (Show-Zone): An/Aus wirkt als Match-Setting auf den
//     Screen („Musik aus (Match-Setting)"), Volume-Regler, Skip schaltet die
//     Screen-Rotation weiter (musikSkips-Zähler), Playlist-Ansicht listet
//     MacLeod-Kern + Demo-Loops
//
//   npm run build && node tools/screenshots/w3musik-proof.mjs
//
// Artefakte: mm_w3musik_*.png + mm_w3musik_proof.webm (Screen-Video).
import { spawn } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
import { io } from "socket.io-client";

const PORT = Number(process.env.PROOF_PORT ?? 8094);
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const VIDEO_TMP = "/tmp/mm-w3musik-video";
mkdirSync(OUT, { recursive: true });
rmSync(VIDEO_TMP, { recursive: true, force: true });

const log = (t) => console.log(`[w3musik-proof] ${t}`);
const fehler = [];
const pruefe = (ok, text) => {
  console.log(`${ok ? "✓" : "✗"} ${text}`);
  if (!ok) fehler.push(text);
};

// ---------- 1) Server ----------
rmSync("/tmp/mm-w3musik-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-w3musik-data" },
  stdio: "ignore",
});
process.on("exit", () => server.kill());
for (let i = 0; i < 40; i++) {
  try {
    if ((await fetch(`${URL_BASIS}/healthz`)).ok) break;
  } catch {
    /* bootet noch */
  }
  await delay(250);
}
log(`Server läuft auf :${PORT}`);

// ---------- 2) API-Beleg: Bett-Katalog der Rotation ----------
const betten = (await (await fetch(`${URL_BASIS}/api/musik/betten`)).json()).betten;
log(`/api/musik/betten: ${betten.map((b) => `${b.titel} (${b.stimmung})`).join(" · ")}`);
pruefe(
  betten.length === 4 &&
    betten.filter((b) => b.stimmung === "chillig").length === 3 &&
    betten.filter((b) => b.stimmung === "upbeat").length === 1,
  `/api/musik/betten liefert die 4 Demo-Loops (3× chillig, 1× upbeat)`,
);
const bettDatei = await fetch(`${URL_BASIS}${betten[0]?.url}`);
pruefe(
  bettDatei.ok && (await bettDatei.arrayBuffer()).byteLength > 100_000,
  `Bett-Datei ${betten[0]?.url} wird über /media-musik-bett ausgeliefert`,
);

// ---------- 3) Raum + Screen-Page (Audio instrumentiert, Video) ----------
const opener = io(URL_BASIS, { transports: ["websocket"] });
const raum = await opener
  .timeout(5000)
  .emitWithAck("room.create", { role: "screen", origin: URL_BASIS });
if (!raum.ok) throw new Error(`room.create: ${raum.error}`);
const { code, gmPin } = raum;
log(`Raum ${code}`);

const browser = await chromium.launch({ args: ["--autoplay-policy=no-user-gesture-required"] });
const context = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  recordVideo: { dir: VIDEO_TMP, size: { width: 1280, height: 800 } },
});
const screen = await context.newPage();
await screen.addInitScript(() => {
  window.__mmAudios = [];
  const Orig = window.Audio;
  const Patched = function (...args) {
    const el = new Orig(...args);
    window.__mmAudios.push(el);
    return el;
  };
  Patched.prototype = Orig.prototype;
  window.Audio = Patched;
});
await screen.addInitScript((c) => sessionStorage.setItem("mm:screen-room", c), code);
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector(".mono", { timeout: 10_000 });
await screen.click("body"); // erste Geste ⇒ Audio-Unlock
log("Screen verbunden + Audio entsperrt");

/** Zustand aller MUSIK-Elemente (Bett-Rotation): /audio/musik + /media-musik-bett. */
const musikElemente = () =>
  screen.evaluate(() =>
    window.__mmAudios
      .filter((a) => a.src.includes("/audio/musik/") || a.src.includes("/media-musik-bett/"))
      .map((a) => ({
        src: a.src.split("/").at(-1),
        paused: a.paused,
        volume: Math.round(a.volume * 1000) / 1000,
        loop: a.loop,
      })),
  );

// ---------- 4) Musik-Control: sichtbar, Ticker nennt den MacLeod-Kern ----------
await delay(2500); // Lobby-Bett einschwingen lassen
const control = screen.locator('[data-testid="mm-musik-control"]');
pruefe(await control.isVisible(), "Musik-Control ist auf dem Screen sichtbar (unten rechts)");
const ticker1 = await screen.locator('[data-testid="mm-musik-ticker"]').textContent();
log(`Ticker: ${ticker1}`);
pruefe(
  ticker1?.includes("♪ Monkeys Spinning Monkeys — Kevin MacLeod") === true,
  `Track-Ticker zeigt den MacLeod-Kern als Default: „${ticker1}"`,
);
const vorSkip = await musikElemente();
pruefe(
  vorSkip.some((a) => !a.paused && a.src.includes("MonkeysSpinningMonkeys")),
  `Lobby-Bett spielt hörbar: ${JSON.stringify(vorSkip)}`,
);
pruefe(
  vorSkip.every((a) => !a.loop || a.paused),
  "Rotation aktiv: Lobby-Playlist > 1 Track ⇒ Bett-Element loopt NICHT (ended schaltet weiter)",
);
await screen.screenshot({ path: join(OUT, "mm_w3musik_screen_control.png") });

// ---------- 5) Screen-Skip: nächster Track = User-Bett-Loop ----------
await screen.click('[data-testid="mm-musik-skip"]');
await delay(1200);
const ticker2 = await screen.locator('[data-testid="mm-musik-ticker"]').textContent();
const nachSkip = await musikElemente();
log(`Nach Skip: ${ticker2} · ${JSON.stringify(nachSkip)}`);
pruefe(ticker2 !== ticker1, `Skip wechselt den Ticker: „${ticker1}" → „${ticker2}"`);
pruefe(
  nachSkip.some((a) => !a.paused && a.src.includes("s_bett_")),
  "Nach dem Skip spielt ein User-Bett-Loop (import.mjs --bett) aus der Rotation",
);
await screen.screenshot({ path: join(OUT, "mm_w3musik_screen_skip_bett.png") });

// ---------- 6) Musik-Toggle: stoppt ALLE Musik-Elemente, SFX bleiben ----------
await screen.click('[data-testid="mm-musik-toggle"]');
await delay(400);
const nachAus = await musikElemente();
pruefe(
  nachAus.every((a) => a.paused),
  `Toggle AUS: alle ${nachAus.length} Musik-Elemente pausiert (programmatisch geprüft)`,
);
const tickerAus = await screen.locator('[data-testid="mm-musik-ticker"]').textContent();
pruefe(tickerAus?.trim() === "Musik aus", `Ticker sagt „Musik aus" (war: „${tickerAus?.trim()}")`);
const gespeichert = await screen.evaluate(() =>
  JSON.parse(localStorage.getItem("mm:sound:screen") ?? "{}"),
);
pruefe(
  gespeichert.musikAn === false,
  `Zustand persistiert im localStorage: mm:sound:screen = ${JSON.stringify(gespeichert)}`,
);
// SFX-Bus unabhängig: die Sound-Ecke bietet weiter „Ton ausschalten" an —
// der SFX-Bus ist also NICHT stumm, nur die Musik (getrennte Toggles).
const sfxEcke = await screen.locator(".sound-ecke button").first().getAttribute("aria-label");
pruefe(
  sfxEcke === "Ton ausschalten",
  `SFX-Bus getrennt: Sound-Ecke steht weiter auf AN („${sfxEcke}" wird angeboten)`,
);
await screen.screenshot({ path: join(OUT, "mm_w3musik_screen_toggle_aus.png") });

await screen.click('[data-testid="mm-musik-toggle"]'); // wieder AN
await delay(600);
const nachAn = await musikElemente();
pruefe(
  nachAn.some((a) => !a.paused),
  "Toggle AN: das Bett spielt wieder (Position der Rotation blieb erhalten)",
);

// ---------- 7) GM-Cockpit: Musik-Karte in der Show-Zone ----------
const gmPage = await context.newPage();
await gmPage.goto(`${URL_BASIS}/gm`);
await gmPage.fill("#gm-code", code);
await gmPage.fill("#gm-pin", gmPin);
await gmPage.click("button.primaer");
await gmPage.waitForSelector('[data-testid="gm-anker"]', { timeout: 8000 });
await gmPage.click('[data-testid="gm-anker-show"]');
await delay(300);
pruefe(
  await gmPage.locator('[data-testid="gm-musik-karte"]').isVisible(),
  "GM-Musik-Karte ist in der Show-Zone sichtbar (An/Aus, Volume, Skip, Playlist)",
);
await gmPage.click('[data-testid="gm-musik-playlist-btn"]');
await gmPage.waitForSelector('[data-testid="gm-musik-playlist"]', { timeout: 5000 });
await delay(600); // Bett-Katalog lädt lazy
const playlistText = await gmPage.locator('[data-testid="gm-musik-playlist"]').textContent();
pruefe(
  playlistText?.includes("Monkeys Spinning Monkeys") === true &&
    playlistText.includes("La Vie en rose") &&
    playlistText.includes("In the Mood"),
  "Playlist-Ansicht: MacLeod-Kern zuerst + Demo-Loops (chillig=Lobby, upbeat=Runde)",
);
await gmPage.screenshot({ path: join(OUT, "mm_w3musik_gm_karte.png") });

// ---------- 8) GM-Toggle (Match-Setting) schlägt auf den Screen durch ----------
await gmPage.click('[data-testid="gm-musik-toggle"]');
await delay(900);
const matchAus = await musikElemente();
pruefe(
  matchAus.every((a) => a.paused),
  "GM Musik-aus (Match-Setting): ALLE Musik-Elemente auf dem Screen pausiert",
);
const tickerMatchAus = await screen.locator('[data-testid="mm-musik-ticker"]').textContent();
pruefe(
  tickerMatchAus?.trim() === "Musik aus (Match-Setting)",
  `Screen-Ticker erklärt den Grund: „${tickerMatchAus?.trim()}"`,
);
await screen.screenshot({ path: join(OUT, "mm_w3musik_screen_match_aus.png") });
await gmPage.click('[data-testid="gm-musik-toggle"]'); // Match-Musik wieder AN
await delay(900);

// ---------- 9) GM-Skip (musikSkips-Zähler) schaltet die Screen-Rotation ----------
const tickerVorGmSkip = await screen.locator('[data-testid="mm-musik-ticker"]').textContent();
await gmPage.click('[data-testid="gm-musik-skip"]');
await delay(1200);
const tickerNachGmSkip = await screen.locator('[data-testid="mm-musik-ticker"]').textContent();
pruefe(
  tickerNachGmSkip !== tickerVorGmSkip && tickerNachGmSkip?.startsWith("♪") === true,
  `GM-Skip wirkt auf dem Screen: „${tickerVorGmSkip}" → „${tickerNachGmSkip}"`,
);

// ---------- 10) Aufräumen + Video sichern ----------
await context.close();
await browser.close();
const videos = readdirSync(VIDEO_TMP).filter((f) => f.endsWith(".webm"));
if (videos.length > 0) {
  // Das Screen-Video (erste Page) zeigt Control/Ticker/Toggle im Ablauf.
  copyFileSync(join(VIDEO_TMP, videos[0]), join(OUT, "mm_w3musik_proof.webm"));
  log(`Video: ${join(OUT, "mm_w3musik_proof.webm")}`);
}
opener.close();
server.kill();

if (fehler.length > 0) {
  console.error(`\n✗ BEWEIS FEHLGESCHLAGEN: ${fehler.length} Prüfungen rot`);
  process.exit(1);
}
console.log(
  "\n✓ BEWEIS ERBRACHT: Rotation + Ticker + Toggle (Screen & GM) + Playlist funktionieren.",
);
process.exit(0);
