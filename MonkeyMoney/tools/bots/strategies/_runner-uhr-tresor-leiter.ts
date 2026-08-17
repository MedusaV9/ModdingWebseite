// Gemeinsamer Bot-Lauf-Runner für die 3 Minigames dieses Agents (Kokosnuss-Uhr,
// Bananen-Tresor, Affenleiter): startet den ECHTEN Server in-Prozess auf eigenem
// Port mit dem jeweiligen Plugin als Raum-Loop (server/core/index.ts verdrahtet
// hart vier-lianen — hier wird NUR die RoomDeps-Injektion anders belegt, kein
// Kern-Code angefasst), lässt Screen + GM + N Spieler-Bots ein komplettes Match
// spielen und prüft Invarianten (Phasen-Fortschritt, seq, Auflösungen, Money).
// Der GM-Bot liefert den Spickzettel (richtige Antwort/Richtwert/Lösung), damit
// Bot-Skill ∈ [0,1] plausibles Verhalten erzeugen kann — Bots sehen als SPIELER
// nämlich (Leak-Schutz!) keine Lösungen.
import { createServer } from "node:http";
import { setTimeout as delay } from "node:timers/promises";
import { Server } from "socket.io";
import { createContentLoader } from "../../../server/content-loader/index";
import { createRealClock, createSeededRng } from "../../../server/core/clock";
import { createHttpApp } from "../../../server/core/http";
import { wireSockets } from "../../../server/core/sockets";
import { createFileStorage } from "../../../server/persistence/storage";
import { RoomManager } from "../../../server/rooms/room-manager";
import type { RoomDeps } from "../../../server/rooms/room";
import { createBotClient, sendeHello, type BotClient } from "../client";

export interface FrageKontext {
  frageNr: number;
  questionId: string;
  /** Rollen-gefilterte Spieler-Sicht (OHNE Lösung — Leak-Schutz gilt auch für Bots). */
  playerView: Record<string, unknown>;
  /** Wartet auf den GM-Spickzettel DIESER Frage (richtige Antwort/Richtwert/Lösung). */
  spickzettel: () => Promise<Record<string, unknown>>;
  sende: (actionId: string, payload: unknown) => Promise<Record<string, unknown>>;
  /** Läuft DIESE Frage noch? (Runden enden früher, wenn alle fertig sind.) */
  aktiv: () => boolean;
  log: (text: string) => void;
}

export type Strategie = (ktx: FrageKontext) => Promise<void>;

export interface BotProfil {
  name: string;
  skill: number;
  avatar: string;
  strategie: Strategie;
}

export interface LaufOptionen {
  spielName: string;
  minigameId: string;

  plugin: ReturnType<RoomDeps["plugins"]["get"]> extends infer P ? P : never;
  port: number;
  seed: number;
  fragen: number;
  profile: BotProfil[];
  /** Watchdog: hängt eine Phase länger, ist der Lauf gescheitert. */
  phasenTimeoutMs?: number;
}

export function parseLaufArgs(argv: string[]): { port?: number; seed?: number; fragen?: number } {
  const hole = (flag: string): string | undefined => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const zahl = (s: string | undefined): number | undefined =>
    s !== undefined ? Number(s) : undefined;
  return { port: zahl(hole("--port")), seed: zahl(hole("--seed")), fragen: zahl(hole("--fragen")) };
}

export async function runBotLauf(opts: LaufOptionen): Promise<void> {
  const timeoutMs = opts.phasenTimeoutMs ?? 45_000;
  const log = (text: string): void => console.log(`[${opts.minigameId}-bots] ${text}`);
  const probleme: string[] = [];

  // ---------- 1) Echten Server in-Prozess starten (eigener Port, eigenes Plugin) ----------
  const clock = createRealClock();
  const rng = createSeededRng(opts.seed);
  const storage = createFileStorage(process.env.DATA_DIR ?? "data");
  const contentLoader = createContentLoader();
  await contentLoader.loadPacks();
  const manager = new RoomManager(
    {
      clock,
      rng,
      storage,
      contentLoader,
      // Injektions-Registry: JEDE Plan-Position läuft über das EINE Test-Plugin.
      plugins: { get: () => opts.plugin, alle: () => [opts.plugin.meta.id] },
      fragenProMatch: opts.fragen,
    },
    { maxRooms: 4 },
  );
  const app = createHttpApp(manager);
  const httpServer = createServer(app);
  const io = new Server(httpServer, { pingInterval: 10_000, pingTimeout: 8_000 });
  wireSockets(io, manager);
  const tickHandle = setInterval(() => manager.tickAlle(), 250);
  await new Promise<void>((resolve) => httpServer.listen(opts.port, resolve));
  const url = `http://localhost:${opts.port}`;
  log(`Server läuft auf ${url} — Raum-Loop: ${opts.spielName} (Seed ${opts.seed})`);

  const alle: BotClient[] = [];
  try {
    // ---------- 2) Screen-Bot: Raum eröffnen, Phasen + Auflösungen protokollieren ----------
    const screen = createBotClient(url, "Screen");
    alle.push(screen);
    const raum = await screen.emitAck("room.create", { role: "screen", origin: url });
    if (!raum.ok) throw new Error(`room.create fehlgeschlagen: ${String(raum.error)}`);
    const code = raum.code as string;
    const gmPin = raum.gmPin as string;
    await sendeHello(screen, { roomCode: code, role: "screen", origin: url });
    log(`Raum ${code} eröffnet (GM-PIN ${gmPin})`);

    const deltasProSpieler = new Map<string, number>();
    const aufgeloest = new Set<string>();
    screen.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        aufloesung?: { perPlayer: { playerId: string; delta: number }[] } | null;
      } | null;
      if (view.phase === "aufloesung" && mg?.aufloesung && mg.questionId) {
        if (aufgeloest.has(mg.questionId)) return;
        aufgeloest.add(mg.questionId);
        for (const r of mg.aufloesung.perPlayer) {
          deltasProSpieler.set(r.playerId, (deltasProSpieler.get(r.playerId) ?? 0) + r.delta);
        }
        const namen = new Map((view.players ?? []).map((p) => [p.id, p.name]));
        const zeile = mg.aufloesung.perPlayer
          .map((r) => `${namen.get(r.playerId) ?? r.playerId} +${r.delta}`)
          .join(" · ");
        log(`Frage ${view.frageNr}/${view.frageTotal} (${mg.questionId}) aufgelöst: ${zeile}`);
      }
    });

    // ---------- 3) GM-Bot: PIN-Login — sein View ist der Spickzettel der Strategien ----------
    const gm = createBotClient(url, "GM");
    alle.push(gm);
    await sendeHello(gm, { roomCode: code, role: "gm", gmPin });
    const spickzettelFuer = async (questionId: string): Promise<Record<string, unknown>> => {
      const bis = performance.now() + 5_000;
      while (performance.now() < bis) {
        const v = gm.view?.minigame?.view as { questionId?: string } | undefined;
        if (v?.questionId === questionId) return v as Record<string, unknown>;
        await delay(100);
      }
      throw new Error(`GM-Spickzettel für ${questionId} kam nicht`);
    };

    // ---------- 4) Spieler-Bots joinen und spielen ihre Strategie pro Frage ----------
    for (const profil of opts.profile) {
      const bot = createBotClient(url, profil.name);
      alle.push(bot);
      const welcome = await sendeHello(bot, {
        roomCode: code,
        role: "player",
        name: profil.name,
        avatar: profil.avatar,
      });
      const meineId = welcome.playerId as string;
      const gespielt = new Set<string>();
      let aktionsNr = 0;
      bot.onView((view) => {
        const mg = view.minigame?.view as { questionId?: string; finished?: boolean } | null;
        if (view.phase !== "frage" || !mg?.questionId || mg.finished) return;
        if (gespielt.has(mg.questionId)) return;
        const questionId = mg.questionId;
        gespielt.add(questionId);
        const nochAktiv = (): boolean => {
          const jetzt = bot.view?.minigame?.view as { questionId?: string } | undefined;
          return bot.view?.phase === "frage" && jetzt?.questionId === questionId;
        };
        const ktx: FrageKontext = {
          frageNr: view.frageNr,
          questionId,
          playerView: mg as Record<string, unknown>,
          spickzettel: () => spickzettelFuer(questionId),
          sende: async (actionId, payload) => {
            const antwort = await bot.emitAck("player.action", {
              minigameId: opts.minigameId,
              actionId,
              payload,
              idemKey: `${meineId}-${questionId}-${actionId}-${aktionsNr++}`,
            });
            if (!antwort.ok) {
              // Benigne Race: Runde endete früher (alle fertig), während der Bot
              // noch mitten in seiner Geste war — kein Invarianten-Bruch.
              if (nochAktiv()) {
                probleme.push(`${profil.name}: ${actionId} abgelehnt (${String(antwort.error)})`);
              }
            }
            return antwort;
          },
          aktiv: nochAktiv,
          log: (text) => log(`${profil.name} (Skill ${profil.skill}) ${text}`),
        };
        void profil.strategie(ktx).catch((err: unknown) => {
          probleme.push(`${profil.name}: Strategie-Fehler bei ${questionId}: ${String(err)}`);
        });
      });
      log(`${profil.name} ist in der Lobby (Skill ${profil.skill}, playerId ${meineId})`);
    }

    // ---------- 5) GM startet, Watchdog wartet auf „ende" ----------
    const start = await gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start-1" });
    if (!start.ok) throw new Error(`Match-Start fehlgeschlagen: ${String(start.error)}`);
    log("GM hat das Match gestartet");

    let letztePhase = "";
    let letzterWechsel = performance.now();
    while (true) {
      const phase = screen.view?.phase ?? "?";
      if (phase !== letztePhase) {
        letztePhase = phase;
        letzterWechsel = performance.now();
        log(`Phase: ${phase}`);
      }
      if (phase === "ende") break;
      if (performance.now() - letzterWechsel > timeoutMs) {
        probleme.push(`Hängende Phase: ${phase} > ${timeoutMs} ms`);
        break;
      }
      await delay(200);
    }

    // ---------- 6) Invarianten + Endstand ----------
    const standings = screen.view?.standings ?? [];
    const skillVon = new Map(opts.profile.map((p) => [p.name, p.skill]));
    log("— Endstand —");
    for (const s of standings) {
      const deltaSumme = deltasProSpieler.get(s.id) ?? 0;
      const skill = skillVon.get(s.name);
      log(
        `  ${s.name}${skill !== undefined ? ` (Skill ${skill})` : ""}: ${s.balance} MM` +
          ` (Plugin-Deltas: ${deltaSumme})`,
      );
      // Engine bucht Plugin-Deltas plus Multiplikatoren (Streak ×≤2, Rückenwind
      // ×1,25/×1,5) und kleine Boni (Applaus-Almosen +25/Frage — Engine-Ausbau
      // läuft parallel): Konto ∈ [Deltas, 2,5 × Deltas + 100].
      if (s.balance < deltaSumme || s.balance > deltaSumme * 2.5 + 100) {
        probleme.push(
          `Money-Invariante verletzt: ${s.name} hat ${s.balance}, Plugin-Deltas ${deltaSumme}`,
        );
      }
    }
    if (aufgeloest.size !== (screen.view?.frageTotal ?? -1)) {
      probleme.push(`Nur ${aufgeloest.size} von ${screen.view?.frageTotal} Fragen aufgelöst`);
    }
    for (const bot of alle) probleme.push(...bot.fehler);
  } finally {
    for (const bot of alle) bot.close();
    clearInterval(tickHandle);
    io.close();
    httpServer.close();
  }

  if (probleme.length > 0) {
    console.error(`[${opts.minigameId}-bots] FEHLGESCHLAGEN:`);
    for (const p of probleme) console.error(`  ✗ ${p}`);
    process.exit(1);
  }
  log(
    `OK: ${opts.profile.length} Bots haben ${opts.fragen} Runden ${opts.spielName} durchgespielt. ✓`,
  );
  process.exit(0);
}
