// Wire-Level-Wächter (Eval-7): Doppelgerät-Präsenz + GM-Raum-Schließen.
// Echter socket.io-Server auf ephemerem Port + echte socket.io-Clients —
// genau der Pfad, auf dem der Falsch-Offline-Bug lebte (disconnect-Handler).
import { createServer, type Server as HttpServer } from "node:http";
import type { AddressInfo } from "node:net";
import { Server } from "socket.io";
import { io as ioClient, type Socket as ClientSocket } from "socket.io-client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader } from "../content-loader/index";
import { allePlugins, getPlugin } from "../minigames/registry";
import type { Storage } from "../persistence/storage";
import { RoomManager } from "../rooms/room-manager";
import { wireSockets } from "./sockets";

function frage(id: string): Question {
  return {
    id,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${id}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "Weil B.",
  };
}

function fakeLoader(): ContentLoader {
  const pool = Array.from({ length: 20 }, (_, i) => frage(`q${i + 1}`));
  return {
    async loadPacks() {},
    pickQuestions: ({ anzahl }) => pool.slice(0, anzahl).map((f) => ({ ...f })),
    alleFragen: () => [],
  };
}

function memoryStorage(): Storage {
  const dateien = new Map<string, string>();
  return {
    resolve: (p) => p,
    async readJson<T>(p: string): Promise<T | null> {
      const text = dateien.get(p);
      return text === undefined ? null : (JSON.parse(text) as T);
    },
    async writeJsonAtomic(p, data) {
      dateien.set(p, JSON.stringify(data));
    },
    async appendLine(p, line) {
      dateien.set(p, (dateien.get(p) ?? "") + line + "\n");
    },
    async readText(p) {
      return dateien.get(p) ?? null;
    },
    async listeDateien() {
      return [];
    },
    async loesche(p) {
      dateien.delete(p);
    },
  };
}

interface TestWelt {
  http: HttpServer;
  io: Server;
  manager: RoomManager;
  url: string;
  clients: ClientSocket[];
}

let welt: TestWelt;

async function starteTestServer(): Promise<TestWelt> {
  const manager = new RoomManager(
    {
      clock: createTestClock(1_000_000),
      rng: createRng(7),
      storage: memoryStorage(),
      contentLoader: fakeLoader(),
      plugins: { get: getPlugin, alle: allePlugins },
      fragenProMatch: 3,
    },
    { maxRooms: 4 },
  );
  const http = createServer();
  const io = new Server(http);
  wireSockets(io, manager);
  await new Promise<void>((res) => http.listen(0, res));
  const port = (http.address() as AddressInfo).port;
  return { http, io, manager, url: `http://localhost:${port}`, clients: [] };
}

function verbinde(w: TestWelt): Promise<ClientSocket> {
  const socket = ioClient(w.url, { transports: ["websocket"], reconnection: false });
  w.clients.push(socket);
  return new Promise((res) => socket.once("connect", () => res(socket)));
}

function emitAck<T>(socket: ClientSocket, event: string, payload: unknown): Promise<T> {
  return socket.timeout(4000).emitWithAck(event, payload) as Promise<T>;
}

const warte = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

beforeEach(async () => {
  welt = await starteTestServer();
});

afterEach(async () => {
  for (const c of welt.clients) c.disconnect();
  welt.io.close();
  await new Promise<void>((res) => welt.http.close(() => res()));
});

/** Raum + Screen + 1 Spieler; liefert Code, Screen-Socket, Spieler + Token. */
async function raumMitSpieler(): Promise<{
  code: string;
  gmPin: string;
  screen: ClientSocket;
  p1: ClientSocket;
  playerId: string;
  token: string;
}> {
  const screen = await verbinde(welt);
  const raum = await emitAck<{ ok: boolean; code: string; gmPin: string }>(screen, "room.create", {
    role: "screen",
    origin: welt.url,
  });
  expect(raum.ok).toBe(true);
  await emitAck(screen, "hello", { roomCode: raum.code, role: "screen", origin: welt.url });
  const p1 = await verbinde(welt);
  const w = await emitAck<{ ok: boolean; playerId: string; sessionToken: string }>(p1, "hello", {
    roomCode: raum.code,
    role: "player",
    name: "Mia",
    avatar: "gelb",
  });
  expect(w.ok).toBe(true);
  return {
    code: raum.code,
    gmPin: raum.gmPin,
    screen,
    p1,
    playerId: w.playerId,
    token: w.sessionToken,
  };
}

describe("sockets: Doppelgerät-Präsenz (Eval-7 P1 Falsch-Offline)", () => {
  it("Tab 2 zu ⇒ Spieler bleibt ONLINE solange Tab 1 lebt; erst Tab 1 zu ⇒ offline", async () => {
    const { code, screen, p1, playerId, token } = await raumMitSpieler();
    const presence: { connected: boolean }[] = [];
    screen.on("view.event", (msg: { event?: { type: string; connected: boolean } }) => {
      if (msg.event?.type === "presence") presence.push({ connected: msg.event.connected });
    });

    // Tab 2: gleicher Session-Token ⇒ gleicher Spieler-Slot (kein Fork).
    const tab2 = await verbinde(welt);
    const w2 = await emitAck<{ ok: boolean; playerId: string }>(tab2, "hello", {
      roomCode: code,
      role: "player",
      sessionToken: token,
    });
    expect(w2.ok).toBe(true);
    expect(w2.playerId).toBe(playerId);

    const room = welt.manager.finde(code)!;
    expect(room.hatVerbundenenSpieler(playerId)).toBe(true);

    // Tab 2 schließen: KEIN Falsch-Offline — Tab 1 ist ja noch verbunden.
    tab2.disconnect();
    await warte(150);
    expect(room.state.players[playerId]?.connected).toBe(true);
    expect(presence.some((p) => p.connected === false)).toBe(false);

    // Jetzt Tab 1 schließen: DAS ist der echte Disconnect ⇒ offline + Grace.
    p1.disconnect();
    await warte(150);
    expect(room.state.players[playerId]?.connected).toBe(false);
    expect(presence.some((p) => p.connected === false)).toBe(true);
    expect(room.state.players[playerId]?.graceUntil).not.toBeNull();
  });

  it("Reconnect nach Falsch-Offline-Szenario: Token-Restore meldet wieder online", async () => {
    const { code, p1, playerId, token } = await raumMitSpieler();
    p1.disconnect();
    await warte(150);
    const room = welt.manager.finde(code)!;
    expect(room.state.players[playerId]?.connected).toBe(false);
    const zurueck = await verbinde(welt);
    const w = await emitAck<{ ok: boolean; playerId: string }>(zurueck, "hello", {
      roomCode: code,
      role: "player",
      sessionToken: token,
    });
    expect(w.ok).toBe(true);
    expect(w.playerId).toBe(playerId);
    expect(room.state.players[playerId]?.connected).toBe(true);
  });
});

describe("sockets: GM-Kommando raum.schliessen (Eval-7 P2 max-rooms)", () => {
  it("nur im Ende-Screen erlaubt; schließt den Raum und gibt den Slot frei", async () => {
    const { code, gmPin, screen } = await raumMitSpieler();
    const gm = await verbinde(welt);
    const gw = await emitAck<{ ok: boolean }>(gm, "hello", { roomCode: code, role: "gm", gmPin });
    expect(gw.ok).toBe(true);

    // In der Lobby blockt das Kommando (mitten im Abend wäre es ein Show-Killer).
    const abgelehnt = await emitAck<{ ok: boolean; error?: string }>(gm, "gm.cmd", {
      cmd: "raum.schliessen",
      args: {},
      cmdId: "c1",
    });
    expect(abgelehnt.ok).toBe(false);
    expect(abgelehnt.error).toBe("nur-im-ende");

    // Phase „ende" herstellen (Wire-Wächter — den Spielfluss testen die Bots).
    const room = welt.manager.finde(code)!;
    room.ersetzeStateRoh({ ...room.state, phase: "ende" as never });

    const closedGesehen = new Promise<string>((res) =>
      screen.once("room.closed", (msg: { reason: string }) => res(msg.reason)),
    );
    const ok = await emitAck<{ ok: boolean }>(gm, "gm.cmd", {
      cmd: "raum.schliessen",
      args: {},
      cmdId: "c2",
    });
    expect(ok.ok).toBe(true);
    expect(welt.manager.anzahl).toBe(0);
    expect(welt.manager.finde(code)).toBeNull();
    expect(await closedGesehen).toBe("gm-ende");
  });
});
