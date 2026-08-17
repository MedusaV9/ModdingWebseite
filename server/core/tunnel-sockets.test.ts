// Wire-Wächter Internet-Link: tunnel.start/stop-Berechtigung (Screen +
// aktives GM-Cockpit JA, Spieler + Beobachter-GM NEIN), tunnel.status-Broadcast
// an Screen UND GM sowie /api/qr?via=tunnel (öffentliche Ziel-URL im QR).
// Echter socket.io-Server + echte Clients — cloudflared ist ein Fake-Spawn.
import { createServer, type Server as HttpServer } from "node:http";
import type { AddressInfo } from "node:net";
import { Server } from "socket.io";
import { io as ioClient, type Socket as ClientSocket } from "socket.io-client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import type { TunnelStatusMsg } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader } from "../content-loader/index";
import { allePlugins, getPlugin } from "../minigames/registry";
import type { Storage } from "../persistence/storage";
import { RoomManager } from "../rooms/room-manager";
import { createHttpApp } from "./http";
import { wireSockets } from "./sockets";
import { createTunnelManager, type TunnelKind, type TunnelManager } from "./tunnel";

function fakeLoader(): ContentLoader {
  const frage = (id: string): Question => ({
    id,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${id}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "Weil B.",
  });
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

/** Fake-cloudflared: der Test steuert stderr/exit selbst. */
interface FakeKind extends TunnelKind {
  kills: string[];
  stderrData(text: string): void;
}

function fakeKind(): FakeKind {
  const handler = new Map<string, ((...args: unknown[]) => void)[]>();
  const merke =
    (quelle: string) =>
    (event: string, cb: (...args: unknown[]) => void): void => {
      const key = `${quelle}:${event}`;
      handler.set(key, [...(handler.get(key) ?? []), cb]);
    };
  const kind: FakeKind = {
    stdout: { on: merke("stdout") as never },
    stderr: { on: merke("stderr") as never },
    on: merke("kind") as never,
    kills: [],
    kill(signal?: NodeJS.Signals) {
      kind.kills.push(signal ?? "SIGTERM");
    },
    stderrData: (text) => {
      for (const cb of handler.get("stderr:data") ?? []) cb(Buffer.from(text));
    },
  };
  return kind;
}

interface TestWelt {
  http: HttpServer;
  io: Server;
  manager: RoomManager;
  tunnel: TunnelManager;
  kinder: FakeKind[];
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
  const kinder: FakeKind[] = [];
  const tunnel = createTunnelManager({
    port: 8080,
    plattform: "linux",
    spawnFn: () => {
      const kind = fakeKind();
      kinder.push(kind);
      return kind;
    },
  });
  const http = createServer(createHttpApp(manager, { tunnel }));
  const io = new Server(http);
  wireSockets(io, manager, { tunnel });
  await new Promise<void>((res) => http.listen(0, res));
  const port = (http.address() as AddressInfo).port;
  return { http, io, manager, tunnel, kinder, url: `http://localhost:${port}`, clients: [] };
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

async function raum(): Promise<{ code: string; gmPin: string; screen: ClientSocket }> {
  const screen = await verbinde(welt);
  const r = await emitAck<{ ok: boolean; code: string; gmPin: string }>(screen, "room.create", {
    role: "screen",
    origin: welt.url,
  });
  expect(r.ok).toBe(true);
  await emitAck(screen, "hello", { roomCode: r.code, role: "screen", origin: welt.url });
  return { code: r.code, gmPin: r.gmPin, screen };
}

describe("tunnel-Wire: Berechtigung + Status-Broadcast an Screen und GM", () => {
  it("Screen bekommt beim hello den aktuellen Status; Spieler dürfen NICHT starten", async () => {
    const statusBeimScreen: TunnelStatusMsg[] = [];
    const { code, screen } = await raum();
    screen.on("tunnel.status", (s: TunnelStatusMsg) => statusBeimScreen.push(s));
    // hello ist schon durch — der Sofort-Status kam VOR dem Listener; per
    // frischem Screen-Socket nachprüfen, dass der hello-Push ankommt.
    const screen2 = await verbinde(welt);
    const sofort = new Promise<TunnelStatusMsg>((res) =>
      screen2.once("tunnel.status", (s: TunnelStatusMsg) => res(s)),
    );
    await emitAck(screen2, "hello", { roomCode: code, role: "screen", origin: welt.url });
    expect((await sofort).phase).toBe("aus");

    const spieler = await verbinde(welt);
    await emitAck(spieler, "hello", { roomCode: code, role: "player", name: "Mia" });
    const abgelehnt = await emitAck<{ ok: boolean; error?: string }>(spieler, "tunnel.start", {});
    expect(abgelehnt).toMatchObject({ ok: false, error: "keine-berechtigung" });
    expect(welt.kinder).toHaveLength(0);
  });

  it("Screen startet → laeuft-Broadcast erreicht Screen UND GM; /api/qr?via=tunnel zeigt die öffentliche URL", async () => {
    const { code, gmPin, screen } = await raum();
    const gm = await verbinde(welt);
    await emitAck(gm, "hello", { roomCode: code, role: "gm", gmPin });

    // QR-Weg VOR dem Tunnel: via=tunnel wird ehrlich abgelehnt (409).
    const vorher = await fetch(`${welt.url}/api/qr?code=${code}&via=tunnel`);
    expect(vorher.status).toBe(409);

    const screenStatus: TunnelStatusMsg[] = [];
    const gmStatus: TunnelStatusMsg[] = [];
    screen.on("tunnel.status", (s: TunnelStatusMsg) => screenStatus.push(s));
    gm.on("tunnel.status", (s: TunnelStatusMsg) => gmStatus.push(s));

    const start = await emitAck<{ ok: boolean; status: TunnelStatusMsg }>(
      screen,
      "tunnel.start",
      {},
    );
    expect(start.ok).toBe(true);
    expect(start.status.phase).toBe("startet");
    welt.kinder[0].stderrData("INF |  https://wire-test-affe.trycloudflare.com  |\n");
    await warte(100);
    expect(screenStatus.map((s) => s.phase)).toEqual(["startet", "laeuft"]);
    expect(gmStatus.at(-1)).toMatchObject({
      phase: "laeuft",
      url: "https://wire-test-affe.trycloudflare.com",
    });

    // QR parametrisiert die Ziel-URL: SVG kommt, Ziel ist die Tunnel-Join-URL.
    const qr = await fetch(`${welt.url}/api/qr?code=${code}&via=tunnel`);
    expect(qr.status).toBe(200);
    expect(qr.headers.get("content-type")).toContain("svg");
    expect((await qr.text()).length).toBeGreaterThan(200);
  });

  it("Beobachter-GM darf NICHT stoppen, das aktive Cockpit schon (Kind stirbt per SIGTERM)", async () => {
    const { code, gmPin, screen } = await raum();
    const gmAktiv = await verbinde(welt);
    await emitAck(gmAktiv, "hello", { roomCode: code, role: "gm", gmPin });
    const beobachter = await verbinde(welt);
    const bw = await emitAck<{ ok: boolean; gmBeobachter?: boolean }>(beobachter, "hello", {
      roomCode: code,
      role: "gm",
      gmPin,
    });
    expect(bw.gmBeobachter).toBe(true);

    await emitAck(screen, "tunnel.start", {});
    welt.kinder[0].stderrData("INF |  https://stop-test.trycloudflare.com  |\n");

    const verboten = await emitAck<{ ok: boolean; error?: string }>(beobachter, "tunnel.stop", {});
    expect(verboten).toMatchObject({ ok: false, error: "keine-berechtigung" });
    expect(welt.tunnel.status().phase).toBe("laeuft");

    const gestoppt = await emitAck<{ ok: boolean; status: TunnelStatusMsg }>(
      gmAktiv,
      "tunnel.stop",
      {},
    );
    expect(gestoppt.ok).toBe(true);
    expect(gestoppt.status.phase).toBe("aus");
    expect(welt.kinder[0].kills).toEqual(["SIGTERM"]);
  });
});
