// Relay-Framing + socket.io-Shim: Wire-Vertrag (Telefon ↔ Browser-Server) und
// Relay-Vertrag (Swift/Sim ↔ Host-JS) — exakt die Frames, die auch der
// Swift-Wrapper und tools/ipad-host/relay-sim.mjs sprechen.
import { describe, expect, it } from "vitest";
import {
  createRelaySocketServer,
  encodeServerAck,
  encodeServerEvent,
  parseWireClientEvent,
  type HostZumRelay,
  type RelayBridge,
  type RelayZumHost,
  type ShimSocket,
} from "./relay";

/** Test-Brücke: sammelt Host→Relay-Frames, lässt Relay→Host-Frames einspeisen. */
function createTestBridge(): RelayBridge & {
  gesendet: HostZumRelay[];
  einspeisen(msg: RelayZumHost): void;
} {
  const gesendet: HostZumRelay[] = [];
  let cb: ((msg: RelayZumHost) => void) | null = null;
  return {
    gesendet,
    send: (msg) => gesendet.push(msg),
    onMessage: (handler) => {
      cb = handler;
    },
    einspeisen: (msg) => cb?.(msg),
  };
}

describe("Wire-Framing (Telefon ↔ Browser-Server)", () => {
  it("parst Client-Events mit und ohne Ack-Id", () => {
    expect(parseWireClientEvent('{"t":"e","ev":"hello","p":{"roomCode":"AFFE"},"ack":7}')).toEqual({
      t: "e",
      ev: "hello",
      p: { roomCode: "AFFE" },
      ack: 7,
    });
    expect(parseWireClientEvent('{"t":"e","ev":"time.ping","p":{"t0":1}}')).toEqual({
      t: "e",
      ev: "time.ping",
      p: { t0: 1 },
      ack: undefined,
    });
  });

  it("weist Müll ab (kein JSON, falscher Typ, ev fehlt, ack kein number)", () => {
    expect(parseWireClientEvent("kein json")).toBeNull();
    expect(parseWireClientEvent('"nur-string"')).toBeNull();
    expect(parseWireClientEvent('{"t":"a","ack":1}')).toBeNull();
    expect(parseWireClientEvent('{"t":"e","ev":""}')).toBeNull();
    expect(parseWireClientEvent('{"t":"e","ev":"x","ack":"7"}')).toBeNull();
  });

  it("kodiert Server-Events und Acks als Wire-Zeilen", () => {
    expect(JSON.parse(encodeServerEvent("view.snapshot", { seq: 3 }))).toEqual({
      t: "e",
      ev: "view.snapshot",
      p: { seq: 3 },
    });
    expect(JSON.parse(encodeServerAck(9, { ok: true }))).toEqual({
      t: "a",
      ack: 9,
      p: { ok: true },
    });
  });
});

describe("Relay-Socket-Server (socket.io-Shim)", () => {
  function setup(origin?: string) {
    const bridge = createTestBridge();
    const relay = createRelaySocketServer(bridge, { origin });
    const verbunden: ShimSocket[] = [];
    (relay.alsIoServer() as unknown as { on(ev: string, cb: (s: ShimSocket) => void): void }).on(
      "connection",
      (socket) => verbunden.push(socket),
    );
    return { bridge, relay, verbunden };
  }

  it("open → connection-Event mit Socket-Id; doppeltes open ist idempotent", () => {
    const { bridge, relay, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    expect(verbunden).toHaveLength(1);
    expect(verbunden[0].id).toBe("c_1");
    expect(relay.anzahlClients()).toBe(1);
  });

  it("frame → registrierter Handler; Ack-Antwort geht als Wire-Ack zurück", () => {
    const { bridge, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    verbunden[0].on("hello", (payload, ack) => {
      expect((payload as { roomCode: string }).roomCode).toBe("AFFE");
      ack?.({ ok: true, seq: 0 });
    });
    bridge.einspeisen({
      kind: "frame",
      clientId: "c_1",
      data: '{"t":"e","ev":"hello","p":{"roomCode":"AFFE"},"ack":42}',
    });
    const antwort = bridge.gesendet.find((m) => m.kind === "frame");
    expect(antwort).toBeDefined();
    expect(JSON.parse((antwort as { data: string }).data)).toEqual({
      t: "a",
      ack: 42,
      p: { ok: true, seq: 0 },
    });
  });

  it("socket.emit → Wire-Event-Frame an GENAU diesen Client", () => {
    const { bridge, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    bridge.einspeisen({ kind: "open", clientId: "c_2" });
    verbunden[1].emit("view.snapshot", { seq: 5 });
    expect(bridge.gesendet).toHaveLength(1);
    expect(bridge.gesendet[0]).toMatchObject({ kind: "frame", clientId: "c_2" });
    expect(JSON.parse((bridge.gesendet[0] as { data: string }).data).ev).toBe("view.snapshot");
  });

  it("close → disconnect-Handler feuert, Socket verschwindet", () => {
    const { bridge, relay, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    let getrennt = false;
    verbunden[0].on("disconnect", () => {
      getrennt = true;
    });
    bridge.einspeisen({ kind: "close", clientId: "c_1" });
    expect(getrennt).toBe(true);
    expect(relay.anzahlClients()).toBe(0);
    // Frames nach close verpuffen (kein Crash, kein Geister-Dispatch).
    bridge.einspeisen({ kind: "frame", clientId: "c_1", data: '{"t":"e","ev":"hello"}' });
  });

  it("schreibt die LAN-Origin in room.create und Screen-hello um", () => {
    const { bridge, verbunden } = setup("http://192.168.1.20:8080");
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    const gesehen: unknown[] = [];
    verbunden[0].on("room.create", (p) => gesehen.push(p));
    verbunden[0].on("hello", (p) => gesehen.push(p));
    bridge.einspeisen({
      kind: "frame",
      clientId: "c_1",
      data: '{"t":"e","ev":"room.create","p":{"role":"screen","origin":"http://localhost:8080"}}',
    });
    bridge.einspeisen({
      kind: "frame",
      clientId: "c_1",
      data: '{"t":"e","ev":"hello","p":{"roomCode":"AFFE","role":"screen","origin":"http://localhost:8080"}}',
    });
    // Player-hello OHNE origin bleibt unangetastet (kein Feld erfinden).
    bridge.einspeisen({
      kind: "frame",
      clientId: "c_1",
      data: '{"t":"e","ev":"hello","p":{"roomCode":"AFFE","role":"player","name":"Zoe"}}',
    });
    expect((gesehen[0] as { origin: string }).origin).toBe("http://192.168.1.20:8080");
    expect((gesehen[1] as { origin: string }).origin).toBe("http://192.168.1.20:8080");
    expect((gesehen[2] as { origin?: string }).origin).toBeUndefined();
  });

  // D3-Fix: der Relay-Sim schickt beim Host-Bridge-Attach {kind:"reset",
  // clients:[…]} — Einträge, die das Relay nicht mehr kennt, sind Leichen
  // eines gekillten Vorgänger-Relays (deren close kam nie an).
  it("reset räumt Leichen-Einträge auf (Relay-Neustart: neue clientId-Welt)", () => {
    const { bridge, relay, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_alt_1" });
    bridge.einspeisen({ kind: "open", clientId: "c_alt_2" });
    const getrennt: string[] = [];
    for (const socket of verbunden) {
      socket.on("disconnect", () => getrennt.push(socket.id));
    }
    // Neuer Relay-Boot: kennt nur das frisch reconnectete Telefon c_neu_1.
    bridge.einspeisen({ kind: "reset", clients: ["c_neu_1"] });
    expect(getrennt.sort()).toEqual(["c_alt_1", "c_alt_2"]);
    expect(relay.anzahlClients()).toBe(0);
    // Frames an die Leichen verpuffen (kein Geister-Dispatch mehr) …
    bridge.einspeisen({ kind: "frame", clientId: "c_alt_1", data: '{"t":"e","ev":"hello"}' });
    // … und die neue Welt startet sauber (open → connection → hello läuft).
    bridge.einspeisen({ kind: "open", clientId: "c_neu_1" });
    expect(relay.anzahlClients()).toBe(1);
    expect(verbunden.at(-1)!.id).toBe("c_neu_1");
  });

  it("reset lässt BEKANNTE clientIds unangetastet (Bridge-Reconnect ohne Relay-Tod)", () => {
    const { bridge, relay, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    let getrennt = 0;
    const frames: unknown[] = [];
    verbunden[0].on("disconnect", () => (getrennt += 1));
    verbunden[0].on("time.ping", (p) => frames.push(p));
    // Host-Seite reconnectet zum SELBEN Relay: reset nennt c_1, open-Replay folgt.
    bridge.einspeisen({ kind: "reset", clients: ["c_1"] });
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    expect(getrennt).toBe(0); // Telefon wurde NICHT getrennt
    expect(verbunden).toHaveLength(1); // kein Doppel-Socket
    expect(relay.anzahlClients()).toBe(1);
    // Bestehende Handler laufen weiter (kein hello nötig).
    bridge.einspeisen({
      kind: "frame",
      clientId: "c_1",
      data: '{"t":"e","ev":"time.ping","p":{"t0":7}}',
    });
    expect(frames).toEqual([{ t0: 7 }]);
  });

  it("io.to(kanal).emit erreicht nur beigetretene Sockets (Lobby-Browser)", () => {
    const { bridge, relay, verbunden } = setup();
    bridge.einspeisen({ kind: "open", clientId: "c_1" });
    bridge.einspeisen({ kind: "open", clientId: "c_2" });
    verbunden[0].join("lobby-browser");
    (
      relay.alsIoServer() as unknown as {
        to(k: string): { emit(ev: string, p?: unknown): void };
      }
    )
      .to("lobby-browser")
      .emit("lobby.update", { lobbys: [] });
    const empfaenger = bridge.gesendet.map((m) => m.clientId);
    expect(empfaenger).toEqual(["c_1"]);
    verbunden[0].leave("lobby-browser");
    bridge.gesendet.length = 0;
    (
      relay.alsIoServer() as unknown as {
        to(k: string): { emit(ev: string, p?: unknown): void };
      }
    )
      .to("lobby-browser")
      .emit("lobby.update", {});
    expect(bridge.gesendet).toHaveLength(0);
  });
});
