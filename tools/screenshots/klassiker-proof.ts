// UI-Beweis Klassiker-Welle 4 (Playwright): Risiko-Leiter + Einer gegen alle
// laufen ECHT im gebauten Client — der Harness-Server (tools/bots/strategies/
// _harness.ts) injiziert das jeweilige Plugin als Runde 1 und serviert
// client/dist. Ein Spieler ist eine ECHTE Player-Page (Join-UI, XXL-Buttons
// werden geklickt), der Rest sind Socket-Bots; der Screen ist eine echte
// Screen-Page. Geschossen werden die Schlüssel-Momente (Erklär-Demo,
// Entscheidungs-/Frage-Fenster, Absturz-Beat, Podest vs. Tribüne, anonymer
// Beteiligungs-Balken, Enthüllungs-Balken, Bilanzen).
//
//   npx tsx tools/screenshots/klassiker-proof.ts
//   OUT_DIR=/tmp/klassiker npx tsx tools/screenshots/klassiker-proof.ts
//
// Voraussetzungen: npm run build:client, npx playwright install chromium.
import { copyFileSync, mkdirSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { chromium, type Browser, type Page } from "playwright";
import { einerGegenAllePlugin } from "../../server/minigames/einer-gegen-alle/index";
import { risikoLeiterPlugin } from "../../server/minigames/risiko-leiter/index";
import type { Question } from "../../shared/content";
import { createBotClient, sendeHello, type BotClient } from "../bots/client";
import { starteTestServer, type TestServer } from "../bots/strategies/_harness";

const OUT = process.env.OUT_DIR ?? "/opt/cursor/artifacts";
mkdirSync(OUT, { recursive: true });
const log = (t: string) => console.log(`[klassiker-proof] ${t}`);

function frage(
  id: string,
  text: string,
  options: string[],
  answer: number,
  difficulty: Question["difficulty"],
): Question {
  return {
    id,
    kind: "choice4",
    category: "affen_wissen",
    difficulty,
    text,
    options,
    answer,
    erklaerung: `Richtig ist: ${options[answer]}.`,
  };
}

const RL_FRAGEN: Question[] = [
  frage("rl1", "Welche Farbe hat eine reife Banane?", ["Gelb", "Blau", "Karo", "Lila"], 0, "easy"),
  frage(
    "rl2",
    "Wo klettern Affen am liebsten?",
    ["Im Keller", "Auf Bäume", "Im Büro", "Unter Wasser"],
    1,
    "easy",
  ),
  frage(
    "rl3",
    "Welche Stufe ist die Sicherheitsstufe?",
    ["Stufe 3", "Stufe 8", "Stufe 1", "Keine"],
    0,
    "medium",
  ),
  frage(
    "rl4",
    "Was bringt ABSICHERN?",
    ["Nichts", "Eine Banane", "Den Leiter-Stand", "Ärger"],
    2,
    "medium",
  ),
  frage(
    "rl5",
    "Was kostet Zögern im Entscheidungs-Fenster?",
    ["Alles", "Nichts — wer zögert, klettert", "500 MM", "Eine Runde"],
    1,
    "medium",
  ),
  frage(
    "rl6",
    "Was passiert bei einer falschen Antwort?",
    ["Absturz", "Applaus", "Bonus", "Nichts"],
    0,
    "hard",
  ),
  frage(
    "rl7",
    "Wie viele Stufen hat die Money-Leiter?",
    ["Sechs", "Sieben", "Neun", "Acht"],
    3,
    "hard",
  ),
  frage(
    "rl8",
    "Was wartet auf dem Gipfel?",
    ["Nebel", "3000 + Jackpot-Bonus", "Ein Krokodil", "Regen"],
    1,
    "ultrahard",
  ),
];

const EGA_FRAGEN_POOL: Question[] = [
  frage(
    "ega1",
    "Wer tritt bei „Einer gegen alle“ allein an?",
    ["Der Letzte", "Der Führende", "Der GM", "Niemand"],
    1,
    "medium",
  ),
  frage(
    "ega2",
    "Was zählt für die Menge?",
    ["Die Mehrheit", "Der Lauteste", "Das Los", "Nichts"],
    0,
    "medium",
  ),
  frage("ega3", "Was bringt der Solo-Coup?", ["100 MM", "150 MM", "400 MM", "Nichts"], 2, "medium"),
  frage(
    "ega4",
    "Wann entscheidet das Los?",
    ["Bei Gleichstand", "Immer", "Nie", "Montags"],
    0,
    "medium",
  ),
  frage(
    "ega5",
    "Was sieht der Solist vor der Enthüllung?",
    ["Alles", "Die Verteilung", "Nichts", "Die Namen"],
    2,
    "medium",
  ),
  frage(
    "ega6",
    "Was kostet Schweigen der Menge?",
    ["Nichts", "Die Frage (= falsch)", "500 MM", "Applaus"],
    1,
    "medium",
  ),
];

interface MgBlick {
  phase?: string;
  stufeNr?: number;
  frageNr?: number;
  finished?: boolean;
  duKletterst?: boolean;
  deineWahl?: string | null;
}

interface Buehne {
  server: TestServer;
  browser: Browser;
  screenPage: Page;
  spielerPage: Page;
  opener: BotClient;
  gm: BotClient;
  bots: { bot: BotClient; playerId: string; name: string }[];
  code: string;
  pageSpielerId: string;
  stopSync: () => void;
  schliessen: () => Promise<void>;
}

/** Server + Screen-Page + 1 echte Player-Page + N Socket-Bots hochziehen. */
async function baueBuehne(
  plugin: typeof risikoLeiterPlugin | typeof einerGegenAllePlugin,
  fragen: Question[],
  pageSpielerName: string,
  botNamen: string[],
): Promise<Buehne> {
  const server = await starteTestServer({ plugin, fragen, seed: 15 });
  const opener = createBotClient(server.url, "Opener");
  const raum = await opener.emitAck("room.create", { role: "screen", origin: server.url });
  if (!raum.ok) throw new Error(`room.create: ${String(raum.error)}`);
  const code = raum.code as string;
  const gmPin = raum.gmPin as string;
  await sendeHello(opener, { roomCode: code, role: "screen", origin: server.url });
  server.raumRef.current = server.manager.finde(code);
  log(`Raum ${code} auf ${server.url}`);

  const browser = await chromium.launch();
  const lausche = (page: Page, label: string) => {
    page.on("console", (m) => {
      if (m.type() === "error" || m.type() === "warning")
        log(`[${label}] ${m.type()}: ${m.text()}`);
    });
    page.on("pageerror", (e) => log(`[${label}] pageerror: ${e.message}`));
  };
  const screenPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  lausche(screenPage, "screen");
  await screenPage.addInitScript((c: string) => sessionStorage.setItem("mm:screen-room", c), code);
  await screenPage.goto(`${server.url}/screen`);
  await screenPage.waitForSelector(".mono", { timeout: 10_000 });

  // Die ECHTE Player-Page: Join über die Join-UI (Name + Farbe + Beitreten).
  const spielerPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  lausche(spielerPage, "phone");
  await spielerPage.goto(`${server.url}/j/${code}`);
  await spielerPage.fill('input[placeholder="Dein Name"]', pageSpielerName);
  await spielerPage.click(".farb-reihe .farb-knopf:nth-child(3)");
  await spielerPage.click("button.primaer");
  // WARTEN bis der Raum den Page-Spieler registriert hat (Page-Join ist
  // langsamer als Socket-Bots) — so ist order[0] IMMER der Page-Spieler
  // (Akt 2 macht ihn über die Join-Reihenfolge zum Führenden/Solisten).
  const joinStart = Date.now();
  while ((server.raumRef.current?.state.order.length ?? 0) < 1) {
    if (Date.now() - joinStart > 15_000) throw new Error(`${pageSpielerName}: Join-Timeout`);
    await delay(100);
  }
  const pageSpielerId = server.raumRef.current!.state.order[0];
  log(`${pageSpielerName} ist über die Join-UI drin (${pageSpielerId})`);

  const farben = ["rot", "gruen", "blau", "lila"];
  const bots: Buehne["bots"] = [];
  for (let i = 0; i < botNamen.length; i++) {
    const bot = createBotClient(server.url, botNamen[i]);
    const welcome = await sendeHello(bot, {
      roomCode: code,
      role: "player",
      name: botNamen[i],
      avatar: farben[i % farben.length],
    });
    bots.push({ bot, playerId: welcome.playerId as string, name: botNamen[i] });
  }

  const gm = createBotClient(server.url, "GM");
  await sendeHello(gm, { roomCode: code, role: "gm", gmPin });
  await gm.emitAck("gm.cmd", {
    cmd: "settings.set",
    args: { autoGm: false, rad: "aus" },
    cmdId: "settings-proof",
  });

  // Socket-Clients pollen Snapshots (Selbstheilung); echte Pages syncen selbst.
  const sockets = [opener, gm, ...bots.map((b) => b.bot)];
  const timer = setInterval(() => {
    for (const s of sockets) if (s.socket.connected) s.socket.emit("sync.request", {});
  }, 250);

  return {
    server,
    browser,
    screenPage,
    spielerPage,
    opener,
    gm,
    bots,
    code,
    pageSpielerId,
    stopSync: () => clearInterval(timer),
    schliessen: async () => {
      clearInterval(timer);
      await browser.close();
      for (const s of sockets) s.close();
      server.stop();
    },
  };
}

async function schuss(page: Page, name: string): Promise<void> {
  await page.screenshot({ path: `${OUT}/${name}.png` });
  log(`📸 ${name}`);
}

/** Video-Kontext (Muster w4scr): ein EXTRA-Screen zeichnet den Lauf auf —
 * so landen Kletter-/Absturz-Animationen und fallende Balken bewegt im Beweis. */
async function starteVideo(b: Buehne): Promise<(dateiname: string) => Promise<void>> {
  const kontext = await b.browser.newContext({
    viewport: { width: 1280, height: 800 },
    recordVideo: { dir: "/tmp/mm-klassiker-video", size: { width: 1280, height: 800 } },
  });
  const seite = await kontext.newPage();
  await seite.addInitScript((c: string) => sessionStorage.setItem("mm:screen-room", c), b.code);
  await seite.goto(`${b.server.url}/screen`);
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

/** Erklärkarten-Ready der Socket-Bots (verzögert — die Demo soll aufs Bild). */
function botsBereit(b: Buehne, verzoegerungMs: number): void {
  for (const { bot } of b.bots) {
    let gemeldet = false;
    bot.onView((view) => {
      if (view.phase === "erklaerkarte" && !gemeldet) {
        gemeldet = true;
        void delay(verzoegerungMs).then(() =>
          bot.emitAck("phase.ready", { was: "bereit" }).catch(() => null),
        );
      }
    });
  }
}

function mgBlick(bot: BotClient): MgBlick | null {
  return (bot.view?.minigame?.view as MgBlick | undefined) ?? null;
}

/**
 * Plan-Patch NACH dem Match-Start (Muster aus w4scr-minigames.ts): die
 * Injektions-Registry meldet nur das EINE Plugin, `aufloesen` schreibt den
 * Plan deshalb auf das Fallback-Format um — ohne Patch lädt der Client den
 * falschen Renderer. Wir biegen den Plan auf 1 Runde × `fragen` Fragen der
 * echten Plugin-Id (RL braucht 8 Stufen-Fragen, EGA 6).
 */
interface PatchbarerPlan {
  abschnitte: { minigameId: string; wunschMinigameId: string; fragen: number }[];
  rundenTotal: number;
  fragenTotal: number;
}

function patchePlan(server: TestServer, pluginId: string, fragen: number): void {
  const state = server.raumRef.current?.state as unknown as { plan: PatchbarerPlan | null };
  if (!state.plan) throw new Error("patchePlan: kein Plan (Match noch nicht gestartet?)");
  state.plan.abschnitte = [
    { ...state.plan.abschnitte[0], minigameId: pluginId, wunschMinigameId: pluginId, fragen },
  ];
  state.plan.rundenTotal = 1;
  state.plan.fragenTotal = fragen;
}

/** Match starten: Lobby → Intro, Plan auf das Beweis-Format biegen, → Erklärkarte. */
async function starteMatch(b: Buehne, pluginId: string, fragen: number): Promise<void> {
  const s1 = await b.gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start-intro" });
  if (!s1.ok) throw new Error(`Start (Intro): ${String(s1.error)}`);
  patchePlan(b.server, pluginId, fragen);
  await delay(500);
  const s2 = await b.gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start-erklaer" });
  if (!s2.ok) throw new Error(`Start (Erklärkarte): ${String(s2.error)}`);
}

/** Auf einen Minigame-Zustand warten (Polling über den Opener-Socket). */
async function warteAuf(
  b: Buehne,
  test: (mg: MgBlick | null, phase: string) => boolean,
  timeoutMs = 60_000,
): Promise<void> {
  const start = Date.now();
  for (;;) {
    if (test(mgBlick(b.opener), b.opener.view?.phase ?? "?")) return;
    if (Date.now() - start > timeoutMs) throw new Error("warteAuf: Timeout");
    await delay(120);
  }
}

// ---------- Akt 1: Risiko-Leiter ----------
async function aktRisikoLeiter(): Promise<void> {
  const antwortVon = new Map(RL_FRAGEN.map((f) => [f.text, f]));
  const b = await baueBuehne(risikoLeiterPlugin, RL_FRAGEN, "Greta", [
    "Kasse-Kurt",
    "Zocker-Zorro",
    "Blitz-Bruno",
  ]);
  botsBereit(b, 4_500);

  // Socket-Bot-Drehbuch: Kurt sichert im 5. Fenster ab, Zorro stürzt auf
  // Stufe 6, Bruno schon auf Stufe 1 (danach Zuschauer).
  for (const { bot, playerId, name } of b.bots) {
    const entschieden = new Set<number>();
    const beantwortet = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as
        (MgBlick & { questionId?: string; text?: string | null }) | null;
      if (!mg || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;
      const stufe = mg.stufeNr ?? 0;
      if (mg.phase === "entscheidung" && mg.duKletterst === true && !entschieden.has(stufe)) {
        entschieden.add(stufe);
        const wahl = name === "Kasse-Kurt" && stufe === 5 ? "absichern" : "weiter";
        void bot
          .emitAck("player.action", {
            minigameId,
            actionId: "entscheidung",
            payload: { wahl },
            idemKey: `${playerId}-s${stufe}-e`,
          })
          .catch(() => null);
      }
      if (mg.phase === "frage" && mg.duKletterst === true && mg.text) {
        const key = `${stufe}:${mg.questionId ?? ""}`;
        if (beantwortet.has(key)) return;
        beantwortet.add(key);
        const f = antwortVon.get(mg.text);
        if (!f) return;
        const falsch =
          (name === "Blitz-Bruno" && stufe === 1) || (name === "Zocker-Zorro" && stufe === 6);
        const choice = falsch ? (f.answer + 1) % 4 : f.answer;
        void delay(600).then(() =>
          bot
            .emitAck("player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice },
              idemKey: `${playerId}-${key}-a`,
            })
            .catch(() => null),
        );
      }
    });
  }

  await starteMatch(b, risikoLeiterPlugin.meta.id, RL_FRAGEN.length);

  // Erklärkarte: die Demo-Choreo läuft auf dem Screen — Bild bei ~2,5 s.
  await warteAuf(b, (_, phase) => phase === "erklaerkarte", 30_000);
  await delay(2_500);
  await schuss(b.screenPage, "rl_ui_1_erklaer_demo");
  const stopVideo = await starteVideo(b);
  await b.spielerPage.click('button.primaer:has-text("Bereit!")');

  // Stufe 1, Entscheidungs-Fenster: Phone-XXL-Buttons + Leitern-Screen.
  await warteAuf(b, (mg) => mg?.phase === "entscheidung" && (mg.stufeNr ?? 0) === 1);
  await b.spielerPage.waitForSelector(".rl-entscheidung.weiter", { timeout: 10_000 });
  await schuss(b.spielerPage, "rl_ui_2_phone_entscheidung");
  // Kategorie-Intro-Overlay (Bananen-Banner) abklingen lassen — erst dann
  // sind die Puppen am Leiter-Fuß gut zu sehen.
  await delay(1_800);
  await schuss(b.screenPage, "rl_ui_3_screen_leitern");

  // Gretas Page-Drehbuch: immer WEITER + immer richtig (Klick über die UI).
  const gretaLoop = (async () => {
    const geklickt = new Set<string>();
    for (;;) {
      const mg = mgBlick(b.opener);
      if (!mg || mg.finished === true || (b.opener.view?.phase ?? "") === "aufloesung") return;
      const stufe = mg.stufeNr ?? 0;
      try {
        if (mg.phase === "entscheidung" && !geklickt.has(`e${stufe}`)) {
          const knopf = b.spielerPage.locator(".rl-entscheidung.weiter:not([disabled])");
          if ((await knopf.count()) > 0) {
            geklickt.add(`e${stufe}`);
            await knopf.click();
          }
        }
        if (mg.phase === "frage" && !geklickt.has(`f${stufe}`)) {
          const text = (await b.spielerPage.locator(".rl-frage-klein").textContent()) ?? "";
          const f = antwortVon.get(text.trim());
          if (f) {
            const knopf = b.spielerPage.locator(
              `.rl-button:not([disabled]):has-text("${f.options[f.answer]}")`,
            );
            if ((await knopf.count()) > 0) {
              geklickt.add(`f${stufe}`);
              await knopf.click();
            }
          }
        }
      } catch {
        // Phasen-Race (Button weg) — nächster Poll.
      }
      await delay(200);
    }
  })();

  // Frage-Fenster Stufe 1: Phone mit den 4 XXL-Antworten (vor Gretas Klick
  // erwischt der Poll das Fenster meist offen — sonst zeigt es den Lock-Zustand).
  await warteAuf(b, (mg) => mg?.phase === "frage" && (mg.stufeNr ?? 0) === 1);
  await schuss(b.spielerPage, "rl_ui_4_phone_frage");
  await schuss(b.screenPage, "rl_ui_4b_screen_frage");

  // Stufe-6-Aufstiegs-Beat: Zorros Absturz auf die Sicherheitsstufe.
  await warteAuf(b, (mg) => mg?.phase === "aufstieg" && (mg.stufeNr ?? 0) === 6, 120_000);
  await delay(1_200);
  await schuss(b.screenPage, "rl_ui_5_screen_absturz_beat");

  // Ergebnis: Leiter-Bilanz mit Gipfel-Moment.
  await warteAuf(b, (mg) => mg?.phase === "ergebnis", 120_000);
  await delay(1_000);
  await schuss(b.screenPage, "rl_ui_6_screen_bilanz");
  await stopVideo("risiko_leiter_screen_lauf.webm");

  await warteAuf(b, (_, phase) => phase === "aufloesung", 60_000);
  await gretaLoop;
  await b.schliessen();
  log("Akt 1 (Risiko-Leiter) komplett ✓");
}

// ---------- Akt 2: Einer gegen alle ----------
async function aktEinerGegenAlle(): Promise<void> {
  const antwortVon = new Map(EGA_FRAGEN_POOL.map((f) => [f.text, f]));
  const b = await baueBuehne(einerGegenAllePlugin, EGA_FRAGEN_POOL, "Sofia", [
    "Chor-Carl",
    "Chor-Clara",
    "Chor-Chris",
    "Mecker-Micha",
  ]);
  botsBereit(b, 4_000);

  // Sofia führt den Zwischenstand an ⇒ sie kommt aufs Solisten-Podest.
  const kapital: [string, number][] = [
    [b.pageSpielerId, 2_500],
    ...b.bots.map((x, i): [string, number] => [x.playerId, 900 - i * 100]),
  ];
  for (const [playerId, delta] of kapital) {
    const antwort = await b.gm.emitAck("gm.cmd", {
      cmd: "score.adjust",
      args: { playerId, delta, grund: "startkapital-proof", override: true },
      cmdId: `kapital-${playerId}`,
    });
    if (!antwort.ok) throw new Error(`score.adjust ${playerId}: ${String(antwort.error)}`);
  }

  // Mengen-Drehbuch: F1 stimmt die Mehrheit DANEBEN (Solo-Coup-Bild),
  // danach stimmen alle richtig (Tempo).
  for (const { bot, playerId, name } of b.bots) {
    const beantwortet = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as
        (MgBlick & { questionId?: string; text?: string | null }) | null;
      if (!mg || view.phase !== "frage" || !view.minigame || mg.phase !== "frage") return;
      const key = `${mg.frageNr ?? 0}:${mg.questionId ?? ""}`;
      if (beantwortet.has(key) || !mg.text) return;
      beantwortet.add(key);
      const f = antwortVon.get(mg.text);
      if (!f) return;
      const daneben = (mg.frageNr ?? 0) === 1 && name !== "Chor-Carl";
      const choice = daneben ? (f.answer + 1) % 4 : f.answer;
      void delay(700).then(() =>
        bot
          .emitAck("player.action", {
            minigameId: view.minigame!.id,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-${key}-a`,
          })
          .catch(() => null),
      );
    });
  }

  await starteMatch(b, einerGegenAllePlugin.meta.id, EGA_FRAGEN_POOL.length);

  await warteAuf(b, (_, phase) => phase === "erklaerkarte", 30_000);
  await delay(2_000);
  await schuss(b.screenPage, "ega_ui_1_erklaer_demo");
  const stopVideo = await starteVideo(b);
  await b.spielerPage.click('button.primaer:has-text("Bereit!")');

  // Vorstellung: Podest vs. Tribüne + Sofias „DU bist der Solist"-Phone.
  await warteAuf(b, (mg) => mg?.phase === "vorstellung");
  await delay(800);
  await schuss(b.screenPage, "ega_ui_2_screen_podest_tribuene");
  await schuss(b.spielerPage, "ega_ui_3_phone_solistin");

  // Sofias Page-Drehbuch: immer die richtige Option klicken.
  const sofiaLoop = (async () => {
    const geklickt = new Set<number>();
    for (;;) {
      const mg = mgBlick(b.opener);
      if (!mg || mg.finished === true || (b.opener.view?.phase ?? "") === "aufloesung") return;
      try {
        const nr = mg.frageNr ?? 0;
        if (mg.phase === "frage" && !geklickt.has(nr)) {
          const text = (await b.spielerPage.locator(".ega-frage-klein").textContent()) ?? "";
          const f = antwortVon.get(text.trim());
          if (f) {
            const knopf = b.spielerPage.locator(
              `.ega-button:not([disabled]):has-text("${f.options[f.answer]}")`,
            );
            if ((await knopf.count()) > 0) {
              geklickt.add(nr);
              await knopf.click();
            }
          }
        }
      } catch {
        // Phasen-Race — nächster Poll.
      }
      await delay(200);
    }
  })();

  // Frage 1: Sofias Solo-Buttons + der anonyme Beteiligungs-Balken.
  await warteAuf(b, (mg) => mg?.phase === "frage" && (mg.frageNr ?? 0) === 1);
  await schuss(b.spielerPage, "ega_ui_4_phone_solo_antwort");
  await delay(500);
  await schuss(b.screenPage, "ega_ui_5_screen_beteiligung_anonym");

  // Enthüllung 1: die Verteilungs-Balken fallen (Solo-Coup-Moment).
  await warteAuf(b, (mg) => mg?.phase === "enthuellung" && (mg.frageNr ?? 0) === 1, 60_000);
  await delay(1_200);
  await schuss(b.screenPage, "ega_ui_6_screen_enthuellung");

  await warteAuf(b, (mg) => mg?.phase === "ergebnis", 180_000);
  await delay(1_000);
  await schuss(b.screenPage, "ega_ui_7_screen_ergebnis");
  await stopVideo("einer_gegen_alle_screen_lauf.webm");

  await warteAuf(b, (_, phase) => phase === "aufloesung", 60_000);
  await sofiaLoop;
  await b.schliessen();
  log("Akt 2 (Einer gegen alle) komplett ✓");
}

await aktRisikoLeiter();
await aktEinerGegenAlle();
log(`Alle Screenshots in ${OUT} ✓`);
process.exit(0);
