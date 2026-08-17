// Internet-Link-Beweis (W4, Playwright + ECHTER Cloudflare-Quick-Tunnel):
// 1. Server starten → Screen-Lobby zeigt den 🌐-Bereich mit „Link erstellen".
// 2. Klick → Spinner → öffentliche trycloudflare-URL GROSS + eigener QR.
// 3. Die öffentliche URL wird VON AUSSEN gecurlt (/healthz + Join-Seite laufen
//    durchs Cloudflare-Edge → Tunnel → localhost — echter Internet-Rundweg).
// 4. GM-Cockpit: Tunnel-Karte in der Show-Zone zeigt LÄUFT + URL; Stop → aus.
// 5. Fehlerfall: Server OHNE cloudflared im PATH → freundliche Meldung mit
//    Install-Einzeilern statt Fehler.
//
//   node tools/screenshots/w4tunnel-proof.mjs → /opt/cursor/artifacts/mm_w4tunnel_*.png
//
// Voraussetzungen: npm run build, npx playwright install chromium, cloudflared
// installiert (der Fehlerfall-Teil simuliert das Fehlen über einen leeren PATH).
import { execFile, spawn } from "node:child_process";
import { appendFileSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { promisify } from "node:util";
import { chromium } from "playwright";

const PORT = Number(process.env.PROOF_PORT ?? 8871);
const PORT_OHNE = PORT + 1;
const URL_BASIS = `http://localhost:${PORT}`;
const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const CURL_LOG = `${OUT}/mm_w4tunnel_curl_von_aussen.log`;
mkdirSync(OUT, { recursive: true });

const log = (t) => console.log(`[w4tunnel-proof] ${t}`);
const fail = (t) => {
  console.error(`[w4tunnel-proof] ❌ ${t}`);
  process.exit(1);
};
const run = promisify(execFile);

// ---------- 1) Server starten (echtes cloudflared im PATH) ----------
rmSync("/tmp/mm-w4tunnel-data", { recursive: true, force: true });
const server = spawn("node", ["server/dist/index.js"], {
  env: { ...process.env, PORT: String(PORT), DATA_DIR: "/tmp/mm-w4tunnel-data" },
  stdio: "ignore",
});
process.on("exit", () => server.kill());
await warteAufServer(URL_BASIS);
log(`Server läuft auf :${PORT}`);

const browser = await chromium.launch();

// ---------- 2) Screen-Lobby: 🌐-Bereich + „Link erstellen" (mit Video) ----------
const videoCtx = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  recordVideo: { dir: OUT, size: { width: 1280, height: 800 } },
});
const screen = await videoCtx.newPage();
await screen.goto(`${URL_BASIS}/screen`);
await screen.waitForSelector('[data-testid="tunnel-erstellen"]', { timeout: 10000 });
const roomCode = (await screen.locator("p.mono").first().innerText()).trim();
const gmPin = (await screen.locator("p:has-text('Show-Master-PIN') strong").innerText()).trim();
log(`Screen-Lobby offen: Raum ${roomCode}, 🌐-Bereich mit „Link erstellen" sichtbar ✅`);
await schuss(screen, "01_lobby_knopf_link_erstellen");

await screen.click('[data-testid="tunnel-erstellen"]');
await screen.waitForSelector('[data-testid="tunnel-spinner"]', { timeout: 5000 });
log("Klick → Spinner „Internet-Link wird erstellt …“ ✅");
await schuss(screen, "02_lobby_spinner");

// cloudflared verhandelt die URL (~5–15 s) — dann URL GROSS + eigener QR.
await screen.waitForSelector('[data-testid="tunnel-url"]', { timeout: 60000 });
await screen.waitForSelector('[data-testid="tunnel-qr"]', { timeout: 5000 });
const joinUrl = (await screen.locator('[data-testid="tunnel-url"]').innerText()).trim();
if (!/^https:\/\/[a-z0-9-]+\.trycloudflare\.com\/j\/[A-Z]+$/.test(joinUrl)) {
  fail(`Tunnel-Join-URL sieht falsch aus: ${joinUrl}`);
}
const publicBasis = joinUrl.replace(/\/j\/[A-Z]+$/, "");
log(`Öffentliche URL im UI: ${joinUrl} (+ QR via /api/qr?via=tunnel) ✅`);
await delay(1000); // QR-SVG fertig laden
await schuss(screen, "03_lobby_url_und_qr");

// Video sichern (Knopf → Spinner → URL+QR).
const video = screen.video();
await screen.close();
const videoPfad = await video.path();
await videoCtx.close();
renameSync(videoPfad, `${OUT}/mm_w4tunnel_screen_flow_knopf_zu_url.webm`);
log(`🎬 Video: ${OUT}/mm_w4tunnel_screen_flow_knopf_zu_url.webm`);

// ---------- 3) BEWEIS VON AUSSEN: curl über die öffentliche URL ----------
appendFileSync(CURL_LOG, `# curl-Beweis von außen — ${new Date().toISOString()}\n`);
let healthOk = false;
for (let i = 1; i <= 12 && !healthOk; i++) {
  try {
    const { stdout } = await run("curl", ["-sS", "-m", "15", `${publicBasis}/healthz`]);
    appendFileSync(CURL_LOG, `$ curl -sS ${publicBasis}/healthz\n${stdout}\n`);
    healthOk = stdout.includes('"ok":true');
    if (!healthOk) log(`curl-Versuch ${i}: Edge noch nicht bereit (${stdout.slice(0, 80)})`);
  } catch (err) {
    appendFileSync(CURL_LOG, `Versuch ${i}: ${String(err).slice(0, 200)}\n`);
    log(`curl-Versuch ${i}: ${String(err).slice(0, 100)}`);
  }
  if (!healthOk) await delay(3000);
}
if (!healthOk) fail("öffentliche URL antwortete nie auf /healthz");
log(`curl VON AUSSEN: ${publicBasis}/healthz → {"ok":true,…} ✅`);

// Auch die Join-URL (die der QR kodiert) liefert über den Tunnel die App aus.
const { stdout: joinKopf } = await run("curl", [
  "-sS",
  "-m",
  "15",
  "-o",
  "/dev/null",
  "-w",
  "%{http_code} %{content_type}",
  joinUrl,
]);
appendFileSync(
  CURL_LOG,
  `$ curl -sS -o /dev/null -w '%{http_code} %{content_type}' ${joinUrl}\n${joinKopf}\n`,
);
if (!joinKopf.startsWith("200")) fail(`Join-URL über den Tunnel: ${joinKopf}`);
log(`curl VON AUSSEN: ${joinUrl} → ${joinKopf} (Player-Seite) ✅`);

// QR-Ziel gegenprüfen: /api/qr?via=tunnel muss ein SVG liefern.
const { stdout: qrKopf } = await run("curl", [
  "-sS",
  "-m",
  "15",
  "-o",
  "/dev/null",
  "-w",
  "%{http_code} %{content_type}",
  `${URL_BASIS}/api/qr?code=${roomCode}&via=tunnel`,
]);
if (!qrKopf.includes("svg")) fail(`/api/qr?via=tunnel: ${qrKopf}`);
log(`/api/qr?code=${roomCode}&via=tunnel → ${qrKopf} ✅`);

// ---------- 4) GM-Cockpit: Tunnel-Karte (Status LÄUFT + URL), dann Stop ----------
const gm = await browser.newPage({ viewport: { width: 1100, height: 850 } });
await gm.goto(`${URL_BASIS}/gm`);
await gm.fill("#gm-code", roomCode);
await gm.fill("#gm-pin", gmPin);
await gm.click("button:has-text('Raum übernehmen')");
await gm.waitForSelector('[data-testid="gm-anker-show"]', { timeout: 8000 });
await gm.click('[data-testid="gm-anker-show"]');
await gm.waitForSelector('[data-testid="gm-tunnel-karte"]', { timeout: 5000 });
const gmStatus = (await gm.locator('[data-testid="gm-tunnel-status"]').innerText()).trim();
const gmUrl = (await gm.locator('[data-testid="gm-tunnel-url"]').innerText()).trim();
if (gmStatus !== "LÄUFT" || gmUrl !== publicBasis) {
  fail(`GM-Karte zeigt "${gmStatus}" / "${gmUrl}", erwartet LÄUFT / ${publicBasis}`);
}
log(`GM-Show-Zone: Tunnel-Karte zeigt LÄUFT + ${gmUrl} ✅`);
// Karte wirklich IM Bild (der Anker-Klick scrollt smooth — hier hart nachziehen).
await gm.locator('[data-testid="gm-tunnel-karte"]').scrollIntoViewIfNeeded();
await delay(700);
await schuss(gm, "04_gm_tunnel_karte_laeuft");

await gm.click('[data-testid="gm-tunnel-stop"]');
await gm.waitForFunction(
  () => document.querySelector('[data-testid="gm-tunnel-status"]')?.textContent?.trim() === "aus",
  { timeout: 5000 },
);
log("GM-Stop → Status „aus“ (Broadcast kam an) ✅");
await gm.locator('[data-testid="gm-tunnel-karte"]').scrollIntoViewIfNeeded();
await delay(300);
await schuss(gm, "05_gm_tunnel_gestoppt");
await gm.close();

// Nach dem Stop ist die öffentliche URL tot (Edge liefert einen Fehler-Status).
await delay(2500);
const { stdout: totKopf } = await run("curl", [
  "-sS",
  "-m",
  "15",
  "-o",
  "/dev/null",
  "-w",
  "%{http_code}",
  `${publicBasis}/healthz`,
]).catch((e) => ({ stdout: `curl-fehler: ${String(e).slice(0, 80)}` }));
appendFileSync(CURL_LOG, `$ nach Stop: curl ${publicBasis}/healthz → ${totKopf}\n`);
log(`Nach Stop: ${publicBasis}/healthz → HTTP ${totKopf} (Tunnel ist wirklich zu) ✅`);

// ---------- 5) Fehlerfall: Server OHNE cloudflared im PATH ----------
rmSync("/tmp/mm-w4tunnel-ohne-data", { recursive: true, force: true });
const serverOhne = spawn(process.execPath, ["server/dist/index.js"], {
  env: {
    ...process.env,
    PORT: String(PORT_OHNE),
    DATA_DIR: "/tmp/mm-w4tunnel-ohne-data",
    PATH: "/nonexistent-bin", // cloudflared (und alles andere) unauffindbar
  },
  stdio: "ignore",
});
process.on("exit", () => serverOhne.kill());
await warteAufServer(`http://localhost:${PORT_OHNE}`);

const ohne = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await ohne.goto(`http://localhost:${PORT_OHNE}/screen`);
await ohne.waitForSelector('[data-testid="tunnel-erstellen"]', { timeout: 10000 });
await ohne.click('[data-testid="tunnel-erstellen"]');
await ohne.waitForSelector("text=nicht installiert", { timeout: 8000 });
const bereich = await ohne.locator('[data-testid="internet-link"]').innerText();
if (!bereich.includes("brew install cloudflared") || !bereich.includes("winget install")) {
  fail(`Nicht-installiert-Meldung ohne Install-Einzeiler: ${bereich.slice(0, 200)}`);
}
log("Fehlerfall: freundliche „nicht installiert“-Meldung MIT Install-Einzeilern je OS ✅");
await schuss(ohne, "06_lobby_cloudflared_fehlt");
await ohne.close();
serverOhne.kill();

log(`Fertig — curl-Log: ${CURL_LOG}`);
await browser.close();
server.kill();
process.exit(0);

async function warteAufServer(basis) {
  for (let i = 0; i < 40; i++) {
    try {
      const r = await fetch(`${basis}/healthz`);
      if (r.ok) {
        // Sicherstellen, dass es UNSER Server ist (nicht z. B. der Relay-Sim
        // eines Parallel-Laufs auf demselben Port — healthz hätte auch der).
        const kopf = await r.json();
        if ("rooms" in kopf) return;
        fail(`Port ${basis} ist von einem FREMDEN Prozess belegt: ${JSON.stringify(kopf)}`);
      }
    } catch {
      /* Server bootet noch */
    }
    await delay(250);
  }
  fail(`Server unter ${basis} kam nicht hoch`);
}

async function schuss(page, name) {
  const pfad = `${OUT}/mm_w4tunnel_${name}.png`;
  await page.screenshot({ path: pfad });
  log(`📸 ${pfad}`);
}
