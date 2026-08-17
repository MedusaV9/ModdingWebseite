// W4-Screen-Proof B (Playwright + Bot-Harness): Minigame-Inszenierungen für
// die Perfektions-Runde Welle 4 — drei kurze Läufe mit INJIZIERTEM Plugin
// (jede Plan-Position = das eine Test-Plugin, Muster der Bot-Strategien):
//   · Tortenschlacht: Wurf-Beat (Splat + Screen-Shake) + Sieger-Pose
//     + Geldflug-Beat der Erklär-Demo (Bereich 4 + 5)
//   · Boxkampf: K.O.-Moment (Zeitlupe) + Sieger-Pose (Bereich 4)
//   · Taschendieb: Klau-Highlight-Karte + Ende-Screen (Bereich 2 + 3)
// Jede Station wird auf 1280x800 + 1920x1080 geschossen; mit VIDEO=1 nimmt
// ein dritter Screen-Kontext die Beats als .webm auf (Nachher-Beweis).
//
//   PREFIX=vorher npx tsx tools/screenshots/w4scr-minigames.ts
//   PREFIX=nachher VIDEO=1 npx tsx tools/screenshots/w4scr-minigames.ts
import { copyFileSync, mkdirSync } from "node:fs";
import { chromium, type Browser, type Page } from "playwright";
import { boxkampfPlugin } from "../../server/minigames/bananen-boxkampf/index";
import { tortenschlachtPlugin } from "../../server/minigames/bananen-tortenschlacht/index";
import { taschendiebPlugin } from "../../server/minigames/taschendieb/index";
import type { Question } from "../../shared/content";
import { createBotClient, sendeHello, type BotClient } from "../bots/client";
import { delay, sende, starteTestServer, type TestServer } from "../bots/strategies/_harness";

const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
const PREFIX = process.env.PREFIX ?? "vorher";
const VIDEO = process.env.VIDEO === "1";
mkdirSync(OUT, { recursive: true });
process.env.DATA_DIR = "/tmp/mm-w4scr-mg-data";

const log = (t: string): void => console.log(`[w4scr-b] ${t}`);

function fragen(prefix: string, themen: [string, string[], number][]): Question[] {
  return themen.map(([text, options, answer], i) => ({
    id: `${prefix}-${i + 1}`,
    kind: "choice4",
    category: "affen",
    difficulty: "hard",
    text,
    options,
    answer,
    erklaerung: `Richtig ist: ${options[answer]}.`,
  }));
}

const TS_FRAGEN = fragen("w4ts", [
  ["Welche Farbe hat eine reife Banane?", ["Blau", "Gelb", "Lila", "Karo"], 1],
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
  ["Woraus besteht eine Sahnetorte?", ["Aus Sahne", "Aus Beton", "Aus Sand", "Aus Glas"], 0],
  ["Wie viele Torten bis zum Raus?", ["Eine", "Zwei", "Drei", "Zehn"], 2],
  ["Was macht ein sauberer Affe?", ["Er gewinnt", "Er weint", "Er schläft", "Er kocht"], 0],
]);

const BX_FRAGEN = fragen("w4bx", [
  ["Welche Farbe hat eine reife Banane?", ["Blau", "Gelb", "Lila", "Karo"], 1],
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
  ["Was trägt ein Boxer?", ["Handschuhe", "Zylinder", "Flossen", "Schlips"], 0],
  ["Wann ist ein Kampf K.O.?", ["Bei 0 HP", "Nie", "Beim Gong", "Nach 1 Frage"], 0],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wer gewinnt nach Punkten?", ["Mehr Rest-HP", "Weniger HP", "Der Ältere", "Niemand"], 0],
]);

const TD_FRAGEN = fragen("w4td", [
  ["Womit bezahlt man bei MONKEY MONEY?", ["Euros", "MONKEY MONEY", "Muscheln", "Kekse"], 1],
  ["Was macht der Taschendieb?", ["Er klaut", "Er backt", "Er singt", "Er schläft"], 0],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
]);

// ---------- gemeinsamer Lauf-Rahmen: Raum + Bots + 2 Playwright-Screens ----------

interface Lauf {
  server: TestServer;
  screen: BotClient;
  gm: BotClient;
  spieler: { bot: BotClient; playerId: string; name: string }[];
  s1280: Page;
  s1920: Page;
  alle: BotClient[];
  gmCmd: (cmd: string, args?: Record<string, unknown>) => Promise<void>;
  schuss: (name: string) => Promise<void>;
  stopPolling: () => void;
  stop: () => Promise<void>;
}

async function spawneLauf(
  browser: Browser,
  server: TestServer,
  namen: { name: string; avatar: string }[],
  logPrefix: string,
): Promise<Lauf> {
  const alle: BotClient[] = [];
  const screen = createBotClient(server.url, "Screen");
  alle.push(screen);
  const raum = await screen.emitAck("room.create", { role: "screen", origin: server.url });
  if (!raum.ok) throw new Error(`room.create: ${String(raum.error)}`);
  const code = raum.code as string;
  const gmPin = raum.gmPin as string;
  await sendeHello(screen, { roomCode: code, role: "screen", origin: server.url });
  server.raumRef.current = server.manager.finde(code);
  log(`[${logPrefix}] Raum ${code}`);

  const spieler: Lauf["spieler"] = [];
  for (const n of namen) {
    const bot = createBotClient(server.url, n.name);
    alle.push(bot);
    const welcome = await sendeHello(bot, {
      roomCode: code,
      role: "player",
      name: n.name,
      avatar: n.avatar,
    });
    spieler.push({ bot, playerId: welcome.playerId as string, name: n.name });
  }

  const gm = createBotClient(server.url, "GM");
  alle.push(gm);
  await sendeHello(gm, { roomCode: code, role: "gm", gmPin });
  let cmdNr = 0;
  const gmCmd = async (cmd: string, args: Record<string, unknown> = {}): Promise<void> => {
    const ack = await gm.emitAck("gm.cmd", { cmd, args, cmdId: `${logPrefix}-${cmdNr++}` });
    if (!ack.ok) log(`[${logPrefix}] ⚠ ${cmd}: ${String(ack.error)}`);
  };
  await gmCmd("settings.set", { autoGm: false, rad: "aus", kategorienWahl: "aus" });

  async function screenPage(width: number, height: number): Promise<Page> {
    const page = await browser.newPage({ viewport: { width, height } });
    await page.addInitScript((c: string) => sessionStorage.setItem("mm:screen-room", c), code);
    await page.goto(`${server.url}/screen`);
    await page.waitForSelector(".mono", { timeout: 10_000 });
    return page;
  }
  const s1280 = await screenPage(1280, 800);
  const s1920 = await screenPage(1920, 1080);

  const schuss = async (name: string): Promise<void> => {
    await s1280.screenshot({ path: `${OUT}/mm_w4scr_${name}_${PREFIX}_1280.png` });
    await s1920.screenshot({ path: `${OUT}/mm_w4scr_${name}_${PREFIX}_1920.png` });
    log(`📸 ${name} (${PREFIX}, 1280+1920)`);
  };

  // Tick-getriebene Plugin-Wechsel broadcasten nicht — aktiv Snapshots pollen
  // (gleiches Muster wie starteSyncPolling im Bot-Harness).
  const pollTimer = setInterval(() => {
    for (const bot of alle) {
      if (bot.socket.connected) bot.socket.emit("sync.request", {});
    }
  }, 250);
  const stopPolling = (): void => clearInterval(pollTimer);

  return {
    server,
    screen,
    gm,
    spieler,
    s1280,
    s1920,
    alle,
    gmCmd,
    schuss,
    stopPolling,
    stop: async () => {
      stopPolling();
      await s1280.close();
      await s1920.close();
      for (const bot of alle) bot.close();
      server.stop();
    },
  };
}

/** Video-Kontext: extra Screen zeichnet einen Beat auf (nur mit VIDEO=1). */
async function starteVideo(
  browser: Browser,
  server: TestServer,
  screen: BotClient,
): Promise<(dateiname: string) => Promise<void>> {
  if (!VIDEO) return async () => {};
  const raumCode = (screen.helloPayload?.roomCode ?? "") as string;
  const kontext = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    recordVideo: { dir: "/tmp/mm-w4scr-video", size: { width: 1280, height: 800 } },
  });
  const seite = await kontext.newPage();
  await seite.addInitScript((c: string) => sessionStorage.setItem("mm:screen-room", c), raumCode);
  await seite.goto(`${server.url}/screen`);
  return async (dateiname: string) => {
    const video = seite.video();
    await seite.close();
    await kontext.close();
    const roh = video ? await video.path() : null;
    if (roh) {
      copyFileSync(roh, `${OUT}/${dateiname}`);
      log(`🎬 ${dateiname}`);
    }
  };
}

function mgView(bot: BotClient): Record<string, unknown> | null {
  return (bot.view?.minigame?.view as Record<string, unknown>) ?? null;
}

/**
 * Plan-Patch NACH dem Match-Start: die Injektions-Registry meldet nur das
 * EINE Plugin als verfügbar, `aufloesen` schreibt deshalb ALLE Plan-Positionen
 * auf das Fallback-Format „vier-lianen" um — der SCREEN würde dann den
 * falschen Client-Renderer laden. Wir biegen die minigameIds des Plans
 * in-process auf die echte Plugin-Id zurück (Views lesen den Plan live).
 */
interface PatchbarerPlan {
  abschnitte: { minigameId: string; wunschMinigameId: string; fragen: number }[];
  rundenTotal: number;
  fragenTotal: number;
}

function patchePlan(
  server: TestServer,
  pluginId: string,
  opts: { nurEineFrage?: boolean } = {},
): void {
  const state = server.raumRef.current?.state as unknown as { plan: PatchbarerPlan | null };
  if (!state.plan) return;
  for (const a of state.plan.abschnitte) {
    a.minigameId = pluginId;
    a.wunschMinigameId = pluginId;
  }
  if (opts.nurEineFrage) {
    // Kürzest-Plan (Highlights-Beweis): 1 Runde à 1 Frage, kein Finale —
    // nach der Auflösung endet der Plan NATÜRLICH (beendePlan → Highlights;
    // gm.ende würde die Highlights überspringen und direkt ehren).
    state.plan.abschnitte = [{ ...state.plan.abschnitte[0], fragen: 1 }];
    state.plan.rundenTotal = 1;
    state.plan.fragenTotal = 1;
  }
}

async function warteAuf(pruefe: () => boolean, was: string, timeoutMs = 90_000): Promise<void> {
  const start = Date.now();
  while (!pruefe()) {
    if (Date.now() - start > timeoutMs) throw new Error(`Timeout: ${was}`);
    await delay(120);
  }
}

// ---------- Lauf 1: Tortenschlacht (Demo-Geldflug, Wurf-Splat, Sieger) ----------

async function laufTortenschlacht(browser: Browser): Promise<void> {
  const server = await starteTestServer({
    plugin: tortenschlachtPlugin,
    fragen: TS_FRAGEN,
    seed: 15,
    sliceExtras: () => ({ questions: TS_FRAGEN }),
  });
  const lauf = await spawneLauf(
    browser,
    server,
    [
      { name: "Tina", avatar: "kiki-krawall.rot" },
      { name: "Willi", avatar: "pumper-paule.tuerkis" },
      { name: "Susi", avatar: "glitzer-gina.lila" },
      { name: "Bernd", avatar: "schnarch-schorsch.gruen" },
    ],
    "ts",
  );
  const antwortVon = new Map(TS_FRAGEN.map((f) => [f.id, f.answer]));
  const idVon = new Map(lauf.spieler.map((s) => [s.name, s.playerId]));
  const susiId = idVon.get("Susi")!;
  const berndId = idVon.get("Bernd")!;

  // Spieler-Drehbuch (Muster Bot-Strategie): Tina wirft Susi/Bernd raus.
  for (const { bot, playerId, name } of lauf.spieler) {
    const beantwortet = new Set<number>();
    const geworfen = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        frageNonce?: number;
        phase?: string;
        finished?: boolean;
        aktiveAnzahl?: number;
        raus?: string[];
        istWerfer?: boolean;
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame || mg.finished) return;
      const minigameId = view.minigame.id;
      const nonce = mg.frageNonce ?? 0;
      if (mg.phase === "frage" && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = antwortVon.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        const richtig = name === "Tina" || (name === "Willi" && (mg.aktiveAnzahl ?? 4) > 2);
        void (async () => {
          await delay(name === "Tina" ? 350 : name === "Willi" ? 800 : 550);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: richtig ? korrekt : (korrekt + 1) % 4 },
            idemKey: `${playerId}-n${nonce}-answer`,
          });
        })();
      }
      if (mg.phase === "zielwahl" && mg.istWerfer === true && !geworfen.has(nonce)) {
        geworfen.add(nonce);
        const raus = mg.raus ?? [];
        const ziel = [susiId, berndId].find((z) => !raus.includes(z) && z !== playerId);
        if (ziel === undefined) return;
        void (async () => {
          await delay(300);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "wurf",
            payload: { targetId: ziel },
            idemKey: `${playerId}-n${nonce}-wurf`,
          });
        })();
      }
    });
  }

  await lauf.gmCmd("flow.next"); // Lobby → Intro
  patchePlan(server, tortenschlachtPlugin.meta.id);
  await delay(500);
  await lauf.gmCmd("flow.next"); // Intro → Erklärkarte (Tortenschlacht-Demo)

  // Bereich 5c: Geldflug-Beat der TS-Demo (Beat 5 ab 9,2 s — Pfeil + Konfetti).
  await lauf.s1280.waitForSelector(".ed-buehne .ed-puppe svg", { timeout: 8000 });
  await delay(9800);
  await lauf.schuss("a5_demo_geldflug");
  await lauf.gmCmd("flow.next"); // Erklärkarte → Frage 1

  // Bereich 4a: erster Wurf-Beat — Splat + (nachher) Screen-Shake.
  const stopVideo = await starteVideo(browser, server, lauf.screen);
  await warteAuf(() => mgView(lauf.screen)?.phase === "wurf", "ts-wurf");
  try {
    await lauf.s1280.waitForSelector(".ts-splat", { timeout: 8000 });
  } catch (fehler) {
    const phase = await lauf.s1280.evaluate(() => {
      const studio = document.querySelector<HTMLElement>(".studio");
      return `${studio?.dataset.phase ?? "?"} | ${document.querySelector(".led-wand")?.innerHTML.slice(0, 300) ?? "-"}`;
    });
    log(`DEBUG Seite bei ts-wurf-Timeout: ${phase}`);
    await lauf.s1280.screenshot({ path: `${OUT}/debug_ts_wurf_timeout.png` });
    throw fehler;
  }
  await delay(350);
  await lauf.schuss("a4_ts_wurf");
  await delay(1500);
  await stopVideo(`mm_w4scr_video_ts_wurf_shake.webm`);

  // Bereich 4b: Sieger-Beat (Tina bleibt sauber — Sieger-Pose der Puppe).
  await warteAuf(() => mgView(lauf.screen)?.phase === "ergebnis", "ts-ergebnis", 240_000);
  await delay(900);
  await lauf.s1280.screenshot({ path: `${OUT}/mm_w4scr_a4_ts_sieger_${PREFIX}_1280.png` });
  log(`📸 a4_ts_sieger (${PREFIX}, 1280)`);
  await lauf.stop();
}

// ---------- Lauf 2: Boxkampf (K.O.-Zeitlupe + Sieger-Pose) ----------

async function laufBoxkampf(browser: Browser): Promise<void> {
  const server = await starteTestServer({ plugin: boxkampfPlugin, fragen: BX_FRAGEN, seed: 15 });
  const lauf = await spawneLauf(
    browser,
    server,
    [
      { name: "Bodo", avatar: "don-bananas.gelb" },
      { name: "Greta", avatar: "oma-zinseszins.orange" },
      { name: "Willi", avatar: "dj-trommelfell.blau" },
      { name: "Wanda", avatar: "astro-astrid.pink" },
    ],
    "bx",
  );
  const antwortVon = new Map(BX_FRAGEN.map((f) => [f.id, f.answer]));
  const idVon = new Map(lauf.spieler.map((s) => [s.name, s.playerId]));
  const bodoId = idVon.get("Bodo")!;
  const gretaId = idVon.get("Greta")!;

  // Startkapital: Bodo ist Letzter (Herausforderer), Wanda geschützt.
  const kapital: Record<string, number> = { Bodo: 400, Greta: 2000, Willi: 1200, Wanda: 800 };
  for (const { playerId, name } of lauf.spieler) {
    await lauf.gmCmd("score.adjust", {
      playerId,
      delta: kapital[name],
      grund: "w4scr-kapital",
      override: true,
    });
  }

  for (const { bot, playerId, name } of lauf.spieler) {
    let herausgefordert = false;
    let gewettet = false;
    const beantwortet = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        frageNonce?: number;
        phase?: string;
        finished?: boolean;
        duBistHerausforderer?: boolean;
        duBistBoxer?: boolean;
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame || mg.finished) return;
      const minigameId = view.minigame.id;
      const nonce = mg.frageNonce ?? 0;
      if (mg.phase === "herausforderung" && mg.duBistHerausforderer === true && !herausgefordert) {
        herausgefordert = true;
        void (async () => {
          await delay(500);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "herausfordern",
            payload: { targetId: gretaId },
            idemKey: `${playerId}-herausfordern`,
          });
        })();
      }
      if (mg.phase === "wetten" && !gewettet && (name === "Willi" || name === "Wanda")) {
        gewettet = true;
        void (async () => {
          await delay(name === "Willi" ? 400 : 900);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "wette",
            payload: { auf: name === "Willi" ? bodoId : gretaId },
            idemKey: `${playerId}-wette`,
          });
        })();
      }
      if (mg.phase === "frage" && mg.duBistBoxer === true && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = antwortVon.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        // Bodo immer richtig + schnell, Greta immer falsch ⇒ K.O. in 4 Runden.
        void (async () => {
          await delay(name === "Bodo" ? 400 : 1200);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: name === "Bodo" ? korrekt : (korrekt + 1) % 4 },
            idemKey: `${playerId}-n${nonce}-answer`,
          });
        })();
      }
    });
  }

  await lauf.gmCmd("flow.next"); // Lobby → Intro
  patchePlan(server, boxkampfPlugin.meta.id);
  await delay(500);
  await lauf.gmCmd("flow.next"); // Intro → Erklärkarte
  await delay(1200);
  await lauf.gmCmd("flow.next"); // Erklärkarte → Kampf

  // Video ab „Gegner fast K.O." (HP ≤ 40 ⇒ nächster Treffer entscheidet).
  let stopVideo: ((datei: string) => Promise<void>) | null = null;
  const start = Date.now();
  for (;;) {
    if (Date.now() - start > 240_000) throw new Error("Timeout: bx-ko");
    const mg = mgView(lauf.screen) as {
      phase?: string;
      hp?: Record<string, number>;
      letzterAbtausch?: { schlaege?: { ko?: boolean }[] } | null;
    } | null;
    const gretaHp = mg?.hp?.[gretaId] ?? 100;
    if (VIDEO && stopVideo === null && gretaHp <= 40) {
      stopVideo = await starteVideo(browser, server, lauf.screen);
    }
    if (mg?.phase === "schlag" && (mg.letzterAbtausch?.schlaege ?? []).some((s) => s.ko === true)) {
      break;
    }
    await delay(120);
  }
  // Bereich 4c: K.O.-Moment (Puppe kippt, Sterne — nachher: Zeitlupen-Scale).
  await lauf.s1280.waitForSelector(".bx-ecke.ko", { timeout: 8000 });
  await delay(1400);
  await lauf.schuss("a4_bx_ko");

  // Bereich 4d: Sieger-Beat (nachher: Arme hoch via Gelenk-Rotation).
  await warteAuf(() => mgView(lauf.screen)?.phase === "ergebnis", "bx-ergebnis");
  await delay(1200);
  await lauf.s1280.screenshot({ path: `${OUT}/mm_w4scr_a4_bx_sieger_${PREFIX}_1280.png` });
  log(`📸 a4_bx_sieger (${PREFIX}, 1280)`);
  if (stopVideo) await stopVideo(`mm_w4scr_video_bx_ko_zeitlupe.webm`);
  await lauf.stop();
}

// ---------- Lauf 3: Taschendieb → Klau-Highlight + Ende-Screen ----------

async function laufTaschendieb(browser: Browser): Promise<void> {
  const server = await starteTestServer({
    plugin: taschendiebPlugin,
    fragen: TD_FRAGEN,
    seed: 5,
    sliceExtras: () => ({ letzteOpfer: [], klauSchutz: [] }),
  });
  const lauf = await spawneLauf(
    browser,
    server,
    [
      { name: "Kalle", avatar: "baron-von-bananenstein.gelb" },
      { name: "Dana", avatar: "iro-ines.rot" },
      { name: "Mila", avatar: "kahuna-kalle.blau" },
      { name: "Paul", avatar: "abraka-dieter.gruen" },
    ],
    "td",
  );
  const antwortVon = new Map(TD_FRAGEN.map((f) => [f.id, f.answer]));
  const kapital: Record<string, number> = { Kalle: 2000, Dana: 800, Mila: 1200, Paul: 400 };
  for (const { playerId, name } of lauf.spieler) {
    await lauf.gmCmd("score.adjust", {
      playerId,
      delta: kapital[name],
      grund: "w4scr-kapital",
      override: true,
    });
  }

  for (const { bot, playerId, name } of lauf.spieler) {
    const beantwortet = new Set<string>();
    const geklaut = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        phase?: string;
        finished?: boolean;
        istDieb?: boolean;
        ziele?: { id: string; waehlbar: boolean; kontostand: number | null }[] | null;
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame || mg.finished) return;
      const minigameId = view.minigame.id;
      const questionId = mg.questionId;
      if (mg.phase === "frage" && !beantwortet.has(questionId)) {
        beantwortet.add(questionId);
        const korrekt = antwortVon.get(questionId.split("~")[0]) ?? 0;
        const wartezeit =
          name === "Dana" ? 600 : name === "Mila" ? 1100 : name === "Paul" ? 1400 : 2400;
        void (async () => {
          await delay(wartezeit);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: name === "Paul" ? (korrekt + 1) % 4 : korrekt },
            idemKey: `${playerId}-${questionId}-answer`,
          });
        })();
      }
      // Diebin Dana klaut beim Reichsten (Kalle) → Chronik-Klau ≥ 50 MM.
      if (mg.phase === "opferwahl" && mg.istDieb === true && mg.ziele && !geklaut.has(questionId)) {
        geklaut.add(questionId);
        const waehlbare = mg.ziele.filter((z) => z.waehlbar);
        const ziel = [...waehlbare].sort((a, b) => (b.kontostand ?? 0) - (a.kontostand ?? 0))[0];
        if (!ziel) return;
        void (async () => {
          await delay(500);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "steal",
            payload: { targetId: ziel.id },
            idemKey: `${playerId}-${questionId}-steal`,
          });
        })();
      }
    });
  }

  await lauf.gmCmd("flow.next"); // Lobby → Intro
  patchePlan(server, taschendiebPlugin.meta.id, { nurEineFrage: true });
  await delay(500);
  await lauf.gmCmd("flow.next"); // Intro → Erklärkarte
  await delay(1200);
  await lauf.gmCmd("flow.next"); // Erklärkarte → Frage 1

  // Eine Auflösung reicht (Klau + Stand in der Chronik) — der Plan ist danach
  // NATÜRLICH zu Ende, flow.next führt über beendePlan in die Highlights.
  await warteAuf(() => lauf.screen.view?.phase === "aufloesung", "td-aufloesung");
  await delay(500);
  const stopVideo = await starteVideo(browser, server, lauf.screen);
  for (let i = 0; i < 20 && lauf.screen.view?.phase !== "highlights"; i++) {
    await lauf.gmCmd("flow.next");
    await delay(400);
  }

  // Bereich 2: Klau-Highlight-Karte (nachher: Hand-Anim, Count-up, Puppen-Chip).
  await lauf.s1280.waitForSelector('[data-testid="highlight-karte"]', { timeout: 15_000 });
  await delay(1600);
  await lauf.schuss("a2_highlights");
  await delay(2200);
  await stopVideo(`mm_w4scr_video_highlights_countup.webm`);

  // Bereich 3: Ende-Screen (Hierarchie: Rematch-CTA / Foto-Finish / Credits).
  const s = Date.now();
  for (;;) {
    const phase = lauf.screen.view?.phase ?? "?";
    if (phase === "ende") break;
    if (phase === "siegerehrung") await lauf.gmCmd("flow.next");
    if (Date.now() - s > 90_000) throw new Error("Timeout: td-ende");
    await delay(400);
  }
  await delay(1200);
  await lauf.schuss("a3_ende");
  await lauf.stop();
}

// ---------- Haupt-Programm ----------

async function main(): Promise<void> {
  // RUN=ts|bx|td schränkt auf einen Lauf ein (Iterations-Debugging).
  const nur = process.env.RUN ?? "";
  const browser = await chromium.launch();
  if (nur === "" || nur === "ts") await laufTortenschlacht(browser);
  if (nur === "" || nur === "bx") await laufBoxkampf(browser);
  if (nur === "" || nur === "td") await laufTaschendieb(browser);
  await browser.close();
  log("Proof B fertig ✓");
  process.exit(0);
}

void main();
