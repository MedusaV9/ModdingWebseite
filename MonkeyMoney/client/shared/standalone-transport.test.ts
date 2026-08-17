// Standalone-Transport (Client-Seite): socket.io-Ersatz über nativen WebSocket.
// Der Mock-WS spielt das Relay — geprüft wird die Oberflächen-Semantik, auf die
// sich createConnection in socket.ts verlässt (connect-Event, Acks, Puffern).
import { describe, expect, it, vi } from "vitest";
import { createStandaloneSocket, type WsLike } from "./standalone-transport";

class MockWs implements WsLike {
  static instanzen: MockWs[] = [];
  readyState = 0; // CONNECTING
  gesendet: string[] = [];
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  constructor() {
    MockWs.instanzen.push(this);
  }
  send(data: string): void {
    this.gesendet.push(data);
  }
  close(): void {
    this.readyState = 3;
    this.onclose?.();
  }
  oeffne(): void {
    this.readyState = 1;
    this.onopen?.();
  }
  empfange(obj: unknown): void {
    this.onmessage?.({ data: JSON.stringify(obj) });
  }
}

function setup() {
  MockWs.instanzen = [];
  const socket = createStandaloneSocket({ wsFabrik: () => new MockWs() });
  return { socket, ws: () => MockWs.instanzen.at(-1)! };
}

describe("createStandaloneSocket", () => {
  it("feuert 'connect' bei open — und erneut nach Reconnect", async () => {
    vi.useFakeTimers();
    try {
      const { socket, ws } = setup();
      let verbunden = 0;
      socket.on("connect", () => verbunden++);
      ws().oeffne();
      expect(verbunden).toBe(1);
      ws().close(); // Verbindung reißt → Backoff-Timer → neue WS-Instanz
      await vi.advanceTimersByTimeAsync(600);
      ws().oeffne();
      expect(verbunden).toBe(2);
      expect(MockWs.instanzen).toHaveLength(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it("emit ohne Ack sendet Wire-Event; vor open wird gepuffert", () => {
    const { socket, ws } = setup();
    socket.emit("time.ping", { t0: 7 }); // noch CONNECTING → Puffer
    expect(ws().gesendet).toHaveLength(0);
    ws().oeffne();
    expect(ws().gesendet).toHaveLength(1);
    expect(JSON.parse(ws().gesendet[0])).toEqual({ t: "e", ev: "time.ping", p: { t0: 7 } });
  });

  it("timeout().emitWithAck löst mit der Server-Ack-Antwort auf", async () => {
    const { socket, ws } = setup();
    ws().oeffne();
    const promise = socket.timeout(1000).emitWithAck("hello", { roomCode: "AFFE" });
    const raus = JSON.parse(ws().gesendet[0]) as { ack: number };
    ws().empfange({ t: "a", ack: raus.ack, p: { ok: true, seq: 3 } });
    await expect(promise).resolves.toEqual({ ok: true, seq: 3 });
  });

  it("emitWithAck lehnt nach Timeout ab (kein Zombie-Promise)", async () => {
    vi.useFakeTimers();
    try {
      const { socket, ws } = setup();
      ws().oeffne();
      const promise = socket.timeout(500).emitWithAck("hello", {});
      const abgelehnt = expect(promise).rejects.toThrow(/ack-timeout/);
      await vi.advanceTimersByTimeAsync(600);
      await abgelehnt;
    } finally {
      vi.useRealTimers();
    }
  });

  it("emit MIT Ack-Callback (hello-Pfad in socket.ts) ruft den Callback", async () => {
    const { socket, ws } = setup();
    ws().oeffne();
    const antworten: unknown[] = [];
    socket.emit("hello", { roomCode: "AFFE" }, (antwort) => antworten.push(antwort));
    const raus = JSON.parse(ws().gesendet[0]) as { ack: number };
    ws().empfange({ t: "a", ack: raus.ack, p: { ok: false, error: "raum-nicht-gefunden" } });
    await Promise.resolve(); // Promise-Kette des Callbacks abarbeiten
    expect(antworten).toEqual([{ ok: false, error: "raum-nicht-gefunden" }]);
  });

  it("Server-Events (view.snapshot, time.probe) erreichen die on-Handler", () => {
    const { socket, ws } = setup();
    ws().oeffne();
    const schnappschuesse: unknown[] = [];
    socket.on("view.snapshot", (p) => schnappschuesse.push(p));
    ws().empfange({ t: "e", ev: "view.snapshot", p: { seq: 1, view: {} } });
    ws().empfange({ t: "e", ev: "unbekannt", p: {} }); // kein Handler → kein Crash
    expect(schnappschuesse).toEqual([{ seq: 1, view: {} }]);
  });

  it("SPÄTER connect-Handler auf bereits offenem Socket feuert sofort (geteilter Socket, W4)", async () => {
    // Der Join-Bug des geteilten Sockets: meta-fetch verbindet beim Laden des
    // Join-Formulars — createConnection registriert sein connect (= hello)
    // erst nach dem Verbinden-Klick. Ohne Sofort-Feuern bliebe der Join stumm.
    const { socket, ws } = setup();
    ws().oeffne();
    let verbunden = 0;
    socket.on("connect", () => verbunden++);
    expect(verbunden).toBe(0); // asynchron (queueMicrotask), nie synchron
    await Promise.resolve();
    expect(verbunden).toBe(1);
    // Nach einem Disconnect feuert ein weiterer später Handler NICHT sofort.
    ws().close();
    let nachher = 0;
    socket.on("connect", () => nachher++);
    await Promise.resolve();
    expect(nachher).toBe(0);
  });
});
