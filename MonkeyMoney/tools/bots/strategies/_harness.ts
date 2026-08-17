// Bot-Lauf-Harness für die 3 Minigames dieses Agents (Pixel-Dschungel,
// Stinkbanane, Taschendieb): startet den ECHTEN Server (Express + socket.io +
// RoomManager) in-Prozess mit einem INJIZIERTEN Plugin + eigenen Fragen —
// die Injektions-Registry mappt JEDE Plan-Position auf das EINE Test-Plugin,
// Kern-Code wird nicht angefasst. Der Bot-Kern (tools/bots/client.ts) wird
// unverändert wiederverwendet.
//
// WUNSCH an den Engine-Agent: Tick-getriebene Plugin-Zustandswechsel (z. B.
// Stinkbananen-Weitergabe nach Timeout, Taschendieb-Phasenwechsel) committen
// aktuell OHNE Events ⇒ stiller seq-Bump, kein Broadcast. Die Bots gleichen
// das mit periodischem sync.request aus (starteSyncPolling); echte Clients
// brauchen einen Broadcast, wenn tick den minigameState sichtbar ändert.
import { createServer, type Server as HttpServer } from "node:http";
import { setTimeout as delay } from "node:timers/promises";
import { Server } from "socket.io";
import { createRealClock, createSeededRng } from "../../../server/core/clock";
import { createHttpApp } from "../../../server/core/http";
import { wireSockets } from "../../../server/core/sockets";
import type { ContentLoader } from "../../../server/content-loader/index";
import type { Ctx, MinigamePlugin } from "../../../server/minigames/_api/plugin";
import { createFileStorage } from "../../../server/persistence/storage";
import type { Room } from "../../../server/rooms/room";
import { RoomManager } from "../../../server/rooms/room-manager";
import type { ContentSlice, Question } from "../../../shared/content";
import { DISPO_LIMIT } from "../../../shared/economy";
import type { PlayerId } from "../../../shared/ids";
import { createBotClient, sendeHello, type BotClient, type BotView } from "../client";

export interface TestServer {
  url: string;
  manager: RoomManager;
  /** Der EINE Raum des Laufs — von spawneRunde gesetzt (Slice-Injektion/Assertions). */
  raumRef: { current: Room | null };
  stop: () => void;
}

export interface StartOptions {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  plugin: MinigamePlugin<any, any>;
  fragen: Question[];
  seed?: number;
  /**
   * Zusatz-Felder für den ContentSlice bei jedem init() — z. B. Opfer-Historie
   * oder Klau-Schutz-Listen, die die Engine (noch) nicht selbst befüllt.
   */
  sliceExtras?: (raum: Room) => Record<string, unknown>;
}

/** Echten Server auf einem freien Port starten; Plugin + Fragen injiziert. */
export async function starteTestServer(opts: StartOptions): Promise<TestServer> {
  const contentLoader: ContentLoader = {
    async loadPacks() {},
    pickQuestions: ({ anzahl }) => opts.fragen.slice(0, anzahl),
    // META-Erweiterung des Loader-Vertrags (Übung/Analytics) — im Bot-Harness leer.
    alleFragen: () => [],
  };
  const raumRef: { current: Room | null } = { current: null };

  // Plugin-Wrapper: reicht Zusatz-Slice-Felder (Opfer-Historie, Klau-Schutz …)
  // in init() durch — Produktionspfad bleibt unberührt (nur Bot-Läufe).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const plugin: MinigamePlugin<any, any> = opts.sliceExtras
    ? {
        ...opts.plugin,
        init: (players: PlayerId[], content: ContentSlice, ctx: Ctx) =>
          opts.plugin.init(
            players,
            { ...content, ...opts.sliceExtras!(raumRef.current!) } as ContentSlice,
            ctx,
          ),
      }
    : opts.plugin;

  const manager = new RoomManager(
    {
      clock: createRealClock(),
      rng: createSeededRng(opts.seed ?? 42),
      storage: createFileStorage(process.env.DATA_DIR ?? "data"),
      contentLoader,
      // Injektions-Registry: JEDE Plan-Position läuft über das EINE Test-Plugin.
      plugins: { get: () => plugin, alle: () => [plugin.meta.id] },
      fragenProMatch: opts.fragen.length,
    },
    { maxRooms: 4 },
  );

  const httpServer: HttpServer = createServer(createHttpApp(manager));
  const io = new Server(httpServer, { pingInterval: 10_000, pingTimeout: 8_000 });
  wireSockets(io, manager);
  const tick = setInterval(() => manager.tickAlle(), 100);

  await new Promise<void>((resolve) => httpServer.listen(0, resolve));
  const adresse = httpServer.address();
  if (adresse === null || typeof adresse === "string") throw new Error("kein Port");

  return {
    url: `http://localhost:${adresse.port}`,
    manager,
    raumRef,
    stop: () => {
      clearInterval(tick);
      io.close();
      httpServer.close();
    },
  };
}

/** Eine eingesammelte Auflösung (Plugin-View im Moment der ersten Sichtung). */
export interface Aufloesung {
  frageNr: number;
  questionId: string;
  perPlayer: { playerId: string; delta: number; [k: string]: unknown }[];
  mgView: Record<string, unknown>;
}

export interface Runde {
  screen: BotClient;
  gm: BotClient;
  spieler: { bot: BotClient; playerId: string; name: string }[];
  code: string;
  alle: BotClient[];
  probleme: string[];
  log: (text: string) => void;
  aufloesungen: Aufloesung[];
}

/** Screen + GM + N Spieler-Bots in einen frischen Raum bringen. */
export async function spawneRunde(
  server: TestServer,
  spielerNamen: string[],
  logPrefix: string,
): Promise<Runde> {
  const log = (text: string) => console.log(`[${logPrefix}] ${text}`);
  const probleme: string[] = [];
  const alle: BotClient[] = [];

  const screen = createBotClient(server.url, "Screen");
  alle.push(screen);
  const raum = await screen.emitAck("room.create", { role: "screen", origin: server.url });
  if (!raum.ok) throw new Error(`room.create fehlgeschlagen: ${String(raum.error)}`);
  const code = raum.code as string;
  const gmPin = raum.gmPin as string;
  await sendeHello(screen, { roomCode: code, role: "screen", origin: server.url });
  server.raumRef.current = server.manager.finde(code);
  log(`Raum ${code} eröffnet`);

  // Auflösungen einsammeln (einmal pro Frage) — Grundlage aller Invarianten.
  const aufloesungen: Aufloesung[] = [];
  const gesehen = new Set<string>();
  screen.onView((view) => {
    const mg = view.minigame?.view as
      | ({
          questionId?: string;
          aufloesung?: { perPlayer: Aufloesung["perPlayer"] } | null;
        } & Record<string, unknown>)
      | null;
    if (view.phase === "aufloesung" && mg?.aufloesung && mg.questionId) {
      if (gesehen.has(mg.questionId)) return;
      gesehen.add(mg.questionId);
      aufloesungen.push({
        frageNr: view.frageNr,
        questionId: mg.questionId,
        perPlayer: mg.aufloesung.perPlayer,
        mgView: mg,
      });
      const namen = new Map((view.players ?? []).map((p) => [p.id, p.name]));
      const zeile = mg.aufloesung.perPlayer
        .map((r) => `${namen.get(r.playerId) ?? r.playerId} ${r.delta >= 0 ? "+" : ""}${r.delta}`)
        .join(" · ");
      log(`Auflösung ${aufloesungen.length} (${mg.questionId}): ${zeile}`);
    }
  });

  const farben = ["gelb", "rot", "gruen", "blau", "lila", "orange", "tuerkis", "pink"];
  const spieler: Runde["spieler"] = [];
  for (let i = 0; i < spielerNamen.length; i++) {
    const bot = createBotClient(server.url, spielerNamen[i]);
    alle.push(bot);
    const welcome = await sendeHello(bot, {
      roomCode: code,
      role: "player",
      name: spielerNamen[i],
      avatar: farben[i % farben.length],
    });
    spieler.push({ bot, playerId: welcome.playerId as string, name: spielerNamen[i] });
    log(`${spielerNamen[i]} ist drin (${welcome.playerId as string})`);
  }

  const gm = createBotClient(server.url, "GM");
  alle.push(gm);
  await sendeHello(gm, { roomCode: code, role: "gm", gmPin });
  // Deterministische Bot-Läufe: Auto-GM aus (keine spontanen +10 s/Rad-Drehs).
  await gm.emitAck("gm.cmd", {
    cmd: "settings.set",
    args: { autoGm: false, rad: "aus" },
    cmdId: "settings-botlauf",
  });

  // Erklärkarten überspringen: alle Bots melden „bereit", sobald sie eine sehen.
  for (const { bot } of spieler) {
    let letztePhase = "";
    bot.onView((view) => {
      if (view.phase !== letztePhase) {
        letztePhase = view.phase;
        if (view.phase === "erklaerkarte") {
          void sende(bot, "phase.ready", { was: "bereit" });
        }
      }
    });
  }

  return { screen, gm, spieler, code, alle, probleme, log, aufloesungen };
}

/**
 * Tick-getriebene Plugin-Wechsel broadcasten (noch) nicht — Bots pollen
 * deshalb aktiv Snapshots (siehe Kopf-Kommentar, Engine-Wunsch).
 */
export function starteSyncPolling(runde: Runde, intervallMs = 250): () => void {
  const timer = setInterval(() => {
    for (const bot of runde.alle) {
      if (bot.socket.connected) bot.socket.emit("sync.request", {});
    }
  }, intervallMs);
  return () => clearInterval(timer);
}

/**
 * Match starten (GM flow.next) und bis „ende" laufen lassen (Phasen-Watchdog).
 * endeNachAufloesungen: der GM beendet das Match (session.ende), sobald so
 * viele Auflösungen eingesammelt sind — die Playlist liefe sonst durch alle
 * Runden + Finale (der Bot-Beweis braucht nur die eigene Runde).
 */
export async function spieleBisEnde(
  runde: Runde,
  phasenTimeoutMs: number,
  opts: { endeNachAufloesungen?: number } = {},
): Promise<void> {
  const start = await runde.gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start-1" });
  if (!start.ok) throw new Error(`Match-Start fehlgeschlagen: ${String(start.error)}`);
  runde.log("GM hat das Match gestartet");

  let endeGesendet = false;
  let siegerehrungGeskippt = false;
  let letztePhase = "";
  let letzterWechsel = performance.now();
  for (;;) {
    const phase = runde.screen.view?.phase ?? "?";
    if (phase !== letztePhase) {
      letztePhase = phase;
      letzterWechsel = performance.now();
      runde.log(`Phase: ${phase}`);
    }
    if (phase === "ende") break;
    if (
      !endeGesendet &&
      opts.endeNachAufloesungen !== undefined &&
      runde.aufloesungen.length >= opts.endeNachAufloesungen &&
      phase !== "siegerehrung"
    ) {
      endeGesendet = true;
      runde.log(`GM beendet das Match (${runde.aufloesungen.length} Auflösungen im Kasten)`);
      await runde.gm.emitAck("gm.cmd", { cmd: "session.ende", args: {}, cmdId: "ende-1" });
    }
    if (phase === "siegerehrung" && !siegerehrungGeskippt) {
      siegerehrungGeskippt = true;
      await runde.gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "skip-ehrung" });
    }
    if (performance.now() - letzterWechsel > phasenTimeoutMs) {
      runde.probleme.push(`Hängende Phase: ${phase} > ${phasenTimeoutMs} ms`);
      break;
    }
    await delay(150);
  }
}

/**
 * Endstand-Sanity: Konto muss im Korridor der Plugin-Deltas liegen. Positive
 * Deltas dürfen durch Engine-Multiplikatoren wachsen (Streak ×≤2, Rückenwind
 * ×≤1,5), negative bucht die Engine 1:1; Slack für 10er-Rundung (±5/Frage)
 * und Applaus-Almosen (+25/Frage, §3.4). Beide Korridor-Grenzen werden an der
 * Dispo-Klammer (§3.2, DISPO_LIMIT) geklemmt: die Engine bucht nie unter −500,
 * und am Limit verpuffen weitere Strafen (Pfandflaschen-Modus).
 */
export function pruefeKontoKorridor(runde: Runde, gmAnpassungen: Map<string, number>): void {
  const plus = new Map<string, number>();
  const minus = new Map<string, number>();
  for (const a of runde.aufloesungen) {
    for (const r of a.perPlayer) {
      if (r.delta >= 0) plus.set(r.playerId, (plus.get(r.playerId) ?? 0) + r.delta);
      else minus.set(r.playerId, (minus.get(r.playerId) ?? 0) + r.delta);
    }
  }
  const standings = runde.screen.view?.standings ?? [];
  runde.log("— Endstand —");
  for (const s of standings) {
    const basis = (gmAnpassungen.get(s.id) ?? 0) + (minus.get(s.id) ?? 0) - 30;
    const min = Math.max(DISPO_LIMIT, basis + (plus.get(s.id) ?? 0));
    const max = Math.max(DISPO_LIMIT, basis + (plus.get(s.id) ?? 0) * 3 + 190);
    runde.log(
      `  ${s.name}: ${s.balance} MM (Plugin-Deltas: ${(plus.get(s.id) ?? 0) + (minus.get(s.id) ?? 0)}, GM: ${gmAnpassungen.get(s.id) ?? 0})`,
    );
    if (s.balance < min || s.balance > max) {
      runde.probleme.push(
        `Konto-Korridor verletzt: ${s.name} hat ${s.balance}, erwartet [${min}, ${max}]`,
      );
    }
  }
  for (const bot of runde.alle) runde.probleme.push(...bot.fehler);
}

/**
 * emitAck mit Timeout-Fangnetz: geplante Disconnects (Skip-Beweise) lassen
 * in-flight-ACKs auflaufen — das darf den Lauf nicht crashen. null = kein ACK.
 */
export async function sende(
  bot: BotClient,
  event: string,
  payload: unknown,
): Promise<Record<string, unknown> | null> {
  try {
    return await bot.emitAck(event, payload);
  } catch {
    return null;
  }
}

/** Abschluss: Bots trennen, Probleme melden, Exit-Code setzen. */
export function beende(server: TestServer, runde: Runde): never {
  for (const bot of runde.alle) bot.close();
  server.stop();
  if (runde.probleme.length > 0) {
    console.error(`[${runde.code}] FEHLGESCHLAGEN:`);
    for (const p of runde.probleme) console.error(`  ✗ ${p}`);
    process.exit(1);
  }
  console.log(`[${runde.code}] Bot-Lauf OK ✓`);
  process.exit(0);
}

export { delay };
export type { BotClient, BotView };
