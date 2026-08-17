// socket-Wrapper (relative URL! — HTTP-LAN und HTTPS-Tunnel mit EINEM Build).
// Fachlicher Reconnect: hello mit Session-Token; Snapshot+seq mit Selbstheilung:
// seq-Lücke oder unbekanntes Delta ⇒ sync.request ⇒ Voll-Snapshot.
// Standalone-Modus (?standalone=1, iPad = Server): statt socket.io läuft ein
// nativer WebSocket zum Relay — gleiche Event-/Ack-Semantik, EINE Weiche unten.
import { io, type Socket } from "socket.io-client";
import { PING_INTERVALL_MS, type ViewEvent, type Welcome } from "../../shared/protocol";
import { installiereFehlerTelemetrie, merkeFehlerKontext } from "./fehler-telemetrie";
import { holeGeteiltenStandaloneSocket, istStandalone } from "./standalone-transport";

// pageerror-Telemetrie: JEDER Client mit Verbindung (Screen/Player/GM/Landing)
// meldet unbehandelte Fehler an POST /api/fehler — Kontext (phase/minigameId)
// kommt aus den Snapshots unten. Idempotent + no-op außerhalb des Browsers.
installiereFehlerTelemetrie();

export interface ConnectionHandlers {
  /** Optionaler Schritt VOR hello (z. B. room.create beim Screen). */
  preHello?: (socket: Socket) => Promise<void>;
  /** Baut das hello-Payload (wird bei JEDEM (Re-)Connect frisch aufgerufen). */
  helloPayload: () => Record<string, unknown>;
  onWelcome: (welcome: Welcome) => void;
  onSnapshot: (view: unknown, seq: number) => void;
  /** Kleines Delta anwenden; false ⇒ nicht anwendbar ⇒ Selbstheilung. */
  onDelta: (event: ViewEvent, seq: number) => boolean;
  onFehler: (fehler: string) => void;
  onGmLog?: (entry: unknown) => void;
  onClosed?: (reason: string) => void;
  /** GM: Beobachter-Flag dieses Sockets hat sich geändert (aktiver GM-Wechsel). */
  onGmStatus?: (beobachter: boolean) => void;
}

export interface Connection {
  socket: Socket;
  /** Geschätzte Server-Zeit (lokale Uhr + Offset aus time.ping/pong). */
  serverNow(): number;
  sendPlayerAction(minigameId: string, actionId: string, payload: unknown): Promise<unknown>;
  sendGmCmd(cmd: string, args: Record<string, unknown>): Promise<{ ok: boolean; error?: string }>;
  /** GM-Takeover: aktives Cockpit übernehmen (PIN-Bestätigung Pflicht). */
  sendGmTakeover(pin: string): Promise<{ ok: boolean; error?: string }>;
  requestSync(): void;
  /** hello erneut senden (frisches Payload) — für den zweiten Join-Versuch
   * nach abgelehntem hello (z. B. name-vergeben → Name geändert): die
   * Socket-Verbindung steht dann noch, connect feuert nicht nochmal. */
  sendHello(): void;
}

let laufNr = 0;

export function createConnection(handlers: ConnectionHandlers): Connection {
  // Relative URL — nie hart ws:// (Tunnel braucht wss://). Im Standalone-Modus
  // ersetzt der Relay-WebSocket das socket.io-Protokoll (identische Oberfläche);
  // geteilte Instanz mit meta-fetch.ts (EINE WS-Verbindung pro Seite).
  const socket = istStandalone() ? (holeGeteiltenStandaloneSocket() as unknown as Socket) : io();
  let seq = -1;
  const offsets: number[] = []; // Median der letzten 5 Messungen (WLAN-Ausreißer)

  // Zeit-Sync ist Transport-Infrastruktur: hier ist die lokale Uhr erlaubt.
  // eslint-disable-next-line no-restricted-properties
  const lokalJetzt = () => Date.now();

  const idemKey = () => `k_${lokalJetzt()}_${laufNr++}`;

  function serverNow(): number {
    if (offsets.length === 0) return lokalJetzt();
    const sortiert = [...offsets].sort((a, b) => a - b);
    return lokalJetzt() + sortiert[Math.floor(sortiert.length / 2)];
  }

  function requestSync(): void {
    socket.emit("sync.request", {});
  }

  function sendeHello(): void {
    void (async () => {
      await handlers.preHello?.(socket);
      socket.emit("hello", handlers.helloPayload(), (antwort: { ok: boolean; error?: string }) => {
        if (!antwort.ok) {
          handlers.onFehler(antwort.error ?? "unbekannt");
          return;
        }
        const welcome = antwort as unknown as Welcome;
        seq = welcome.seq;
        merkeFehlerKontext(welcome.view);
        handlers.onWelcome(welcome);
        handlers.onSnapshot(welcome.view, welcome.seq);
      });
    })();
  }

  socket.on("connect", sendeHello);

  socket.on("view.snapshot", (msg: { seq: number; view: unknown }) => {
    seq = msg.seq;
    merkeFehlerKontext(msg.view);
    handlers.onSnapshot(msg.view, msg.seq);
  });

  socket.on("view.event", (msg: { seq: number; event: ViewEvent }) => {
    if (msg.seq !== seq + 1) {
      requestSync(); // seq-Lücke ⇒ Voll-Snapshot (Protokoll ist selbstheilend)
      return;
    }
    seq = msg.seq;
    if (!handlers.onDelta(msg.event, msg.seq)) requestSync();
  });

  socket.on("gm.log", (msg: { entry: unknown }) => handlers.onGmLog?.(msg.entry));
  socket.on("gm.status", (msg: { beobachter: boolean }) =>
    handlers.onGmStatus?.(msg.beobachter === true),
  );
  socket.on("room.closed", (msg: { reason: string }) => handlers.onClosed?.(msg.reason));

  // Heartbeat + Server-Zeit-Offset (alle ~5 s, TECH-SPEC §3.1 #7).
  socket.on("time.pong", (msg: { t0: number; serverTime: number }) => {
    const jetzt = lokalJetzt();
    const rtt = jetzt - msg.t0;
    offsets.push(msg.serverTime + rtt / 2 - jetzt);
    if (offsets.length > 5) offsets.shift();
  });
  setInterval(() => socket.emit("time.ping", { t0: lokalJetzt() }), PING_INTERVALL_MS);
  socket.emit("time.ping", { t0: lokalJetzt() });

  return {
    socket,
    serverNow,
    requestSync,
    sendHello: sendeHello,
    sendPlayerAction(minigameId, actionId, payload) {
      return socket
        .timeout(4000)
        .emitWithAck("player.action", { minigameId, actionId, payload, idemKey: idemKey() });
    },
    sendGmCmd(cmd, args) {
      return socket
        .timeout(4000)
        .emitWithAck("gm.cmd", { cmd, args, cmdId: idemKey() }) as Promise<{
        ok: boolean;
        error?: string;
      }>;
    },
    sendGmTakeover(pin) {
      return socket.timeout(4000).emitWithAck("gm.takeover", { pin }) as Promise<{
        ok: boolean;
        error?: string;
      }>;
    },
  };
}
