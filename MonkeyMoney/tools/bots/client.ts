// Headless socket.io-Bot-Client: verbindet, spricht das Protokoll (hello,
// Snapshot/Event/seq, sync.request, time.probe-Echo) und prüft die
// seq-Invariante mit. Chaos-fähig: trenne() + wiederVerbinden() mit
// Session-Token (fachlicher Reconnect = Slot-Restore, TECH-SPEC §3.2).
import { io, type Socket } from "socket.io-client";

export interface BotView {
  phase: string;
  frageNr: number;
  frageTotal: number;
  paused?: unknown;
  players?: { id: string; name: string; connected?: boolean }[];
  standings?: { id: string; name: string; balance: number }[];
  minigame: { id: string; view: Record<string, unknown> } | null;
  // Engine-Ausbau (alles optional — Screen/Player-Views unterscheiden sich):
  jokers?: { id: string; nutzbar: boolean; ladungen: number; preis: number | null }[];
  kategorieWahl?: {
    optionen: string[];
    endetAt: number;
    deineStimme?: number | null;
  } | null;
  erklaerkarte?: { bereit: string[]; streik: string[]; endetAt: number } | null;
  rad?: {
    ergebnis: { id: string } | null;
    interaktion: { typ: string; endetAt: number; deineWahl?: string | null } | null;
  } | null;
  voting?: { optionen: string[]; endetAt: number; deineStimme?: number | null } | null;
  feedbackAngefragt?: boolean;
  abschnitt?: { typ: string; rundeNr: number; minigameId: string } | null;
  // Team-Modus „Affenbanden" (ADDITIV): Lobby-Wahl + Live-Team-Ranking.
  teams?: {
    modus: string;
    wahlOffen: boolean;
    deinTeam?: string | null;
    teams: {
      id: string;
      name: string;
      topf: number;
      platz: number;
      mitglieder: { playerId: string; name: string; balance: number; doppelAffe: boolean }[];
    }[];
  } | null;
  siegerehrung?: {
    teams?: { teamId: string; name: string; platz: number; topf: number }[];
  } | null;
}

export interface BotClient {
  socket: Socket;
  name: string;
  seq: number;
  view: BotView | null;
  fehler: string[];
  /** Nach hello gesetzt — Basis für Re-Hello nach Chaos-Disconnect. */
  helloPayload: Record<string, unknown> | null;
  sessionToken: string | null;
  playerId: string | null;
  verbunden: boolean;
  emitAck(event: string, payload: unknown): Promise<Record<string, unknown>>;
  onView(cb: (view: BotView) => void): void;
  /** Chaos-Modus: Transport hart kappen (socket.io reconnectet NICHT von selbst). */
  trenne(): void;
  /** Chaos-Modus: neu verbinden + Re-Hello mit Session-Token (Slot-Restore). */
  wiederVerbinden(): Promise<void>;
  close(): void;
}

export function createBotClient(url: string, name: string): BotClient {
  const socket = io(url, { transports: ["websocket"], reconnection: false });
  const viewCallbacks: ((view: BotView) => void)[] = [];

  const bot: BotClient = {
    socket,
    name,
    seq: -1,
    view: null,
    fehler: [],
    helloPayload: null,
    sessionToken: null,
    playerId: null,
    verbunden: false,
    emitAck(event, payload) {
      return socket.timeout(5000).emitWithAck(event, payload) as Promise<Record<string, unknown>>;
    },
    onView(cb) {
      viewCallbacks.push(cb);
    },
    trenne() {
      bot.verbunden = false;
      socket.disconnect();
    },
    async wiederVerbinden() {
      if (socket.connected) return;
      await new Promise<void>((resolve) => {
        socket.once("connect", () => resolve());
        socket.connect();
      });
      // Fachlicher Reconnect: hello mit Token stellt den Spieler-Slot wieder her.
      const payload = {
        ...(bot.helloPayload ?? {}),
        ...(bot.sessionToken ? { sessionToken: bot.sessionToken } : {}),
      };
      const antwort = await bot.emitAck("hello", payload);
      if (!antwort.ok) {
        bot.fehler.push(`${name}: Re-Hello fehlgeschlagen (${String(antwort.error)})`);
        return;
      }
      bot.verbunden = true;
      bot.seq = antwort.seq as number;
      uebernehmeView(antwort.view as BotView, antwort.seq as number);
    },
    close() {
      socket.disconnect();
    },
  };

  function uebernehmeView(view: BotView, seq: number): void {
    bot.seq = seq;
    bot.view = view;
    for (const cb of viewCallbacks) cb(view);
  }

  socket.on("view.snapshot", (msg: { seq: number; view: BotView }) => {
    // Snapshots dürfen seq-Sprünge machen (sie SIND die Selbstheilung) — nie rückwärts.
    if (msg.seq < bot.seq) bot.fehler.push(`${name}: seq rückwärts (${bot.seq} → ${msg.seq})`);
    uebernehmeView(msg.view, msg.seq);
  });

  socket.on("view.event", (msg: { seq: number }) => {
    if (msg.seq !== bot.seq + 1) {
      socket.emit("sync.request", {}); // Lücke ⇒ Selbstheilung (genau der Testpfad!)
      return;
    }
    bot.seq = msg.seq;
    // Bots wenden Deltas nicht feingranular an — Snapshot anfordern reicht zum Spielen.
    socket.emit("sync.request", {});
  });

  // time.probe-Echo — der Server misst daraus den Median-RTT (Buzzer-Fairness).
  socket.on("time.probe", (msg: unknown) => socket.emit("time.probe", msg));

  return bot;
}

/** hello senden und welcome (oder Fehler) zurückgeben; merkt sich Token + Payload. */
export async function sendeHello(
  bot: BotClient,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const antwort = await bot.emitAck("hello", payload);
  if (!antwort.ok) throw new Error(`${bot.name}: hello fehlgeschlagen: ${antwort.error}`);
  bot.helloPayload = { roomCode: payload.roomCode, role: payload.role };
  bot.sessionToken = (antwort.sessionToken as string | null) ?? null;
  bot.playerId = (antwort.playerId as string | null) ?? null;
  bot.verbunden = true;
  bot.seq = antwort.seq as number;
  bot.view = antwort.view as BotView;
  return antwort;
}
