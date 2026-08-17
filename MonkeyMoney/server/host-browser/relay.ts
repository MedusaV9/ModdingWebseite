// Relay-Transport für den Standalone-Modus (iPad = Server, TECH-SPEC §6 +
// docs/IPAD-SETUP.md „Weg 3"): Der komplette Spiel-Server läuft im BROWSER
// (WKWebView auf dem iPad bzw. Desktop-Chrome im Beweis-Lauf). Die iPhones
// verbinden sich per nativem WebSocket zu einem dummen 1:1-RELAY (Swift im
// Wrapper, tools/ipad-host/relay-sim.mjs auf der VM) — das Relay versteht
// KEINE Spiellogik, es schiebt nur Text-Frames zwischen Telefon-Sockets und
// dieser Host-JS-Schicht hin und her.
//
// ZWEI Vertragsebenen, beide hier zentral definiert (Swift spiegelt sie):
//   1. WIRE  (Telefon ↔ Server): JSON-Zeilen statt socket.io-Frames —
//      {t:"e",ev,p,ack?} Client-Event (ack = Antwort-Id für emitWithAck),
//      {t:"a",ack,p}     Server-Ack,   {t:"e",ev,p} Server-Event.
//      Bewusst KEIN socket.io-Protokoll: dessen Engine.IO-Handshake
//      (HTTP-Polling + Upgrade-Tanz) müsste sonst im Swift-Relay nachgebaut
//      werden. Clients erkennen Standalone via ?standalone=1 und nutzen
//      client/shared/standalone-transport.ts (gleiche Semantik wie socket.io:
//      benannte Events + Acks — die Handler in core/sockets.ts laufen 1:1).
//   2. RELAY (Relay ↔ Host-JS): {kind:"open"|"frame"|"close", clientId, data?}
//      + {kind:"reset", clients} beim Host-Bridge-Attach (Leichen-Aufräumer
//      nach Relay-Neustart — additiv, ältere Relays ohne reset laufen weiter).
//
// Der Shim unten stellt core/sockets.ts eine socket.io-kompatible Mini-
// Oberfläche bereit (io.on("connection"), socket.on/emit/id) — wireSockets()
// und Room.attachClient() laufen UNVERÄNDERT gegen dieses Interface.
import type { Server, Socket } from "socket.io";

// ---------- Vertrag 1: WIRE (Telefon ↔ Browser-Server) ----------

/** Client → Server: Event, optional mit Ack-Id (emitWithAck). */
export interface WireClientEvent {
  t: "e";
  ev: string;
  p?: unknown;
  ack?: number;
}

/** Server → Client: Event (Snapshots/Deltas/gm.log/…) oder Ack-Antwort. */
export type WireServerMsg =
  { t: "e"; ev: string; p?: unknown } | { t: "a"; ack: number; p?: unknown };

/** Wire-Zeile parsen; null bei Müll (Relay/Netz ist Systemgrenze → validieren). */
export function parseWireClientEvent(data: string): WireClientEvent | null {
  let roh: unknown;
  try {
    roh = JSON.parse(data);
  } catch {
    return null;
  }
  if (typeof roh !== "object" || roh === null) return null;
  const msg = roh as Record<string, unknown>;
  if (msg.t !== "e" || typeof msg.ev !== "string" || msg.ev.length === 0) return null;
  if (msg.ack !== undefined && typeof msg.ack !== "number") return null;
  return { t: "e", ev: msg.ev, p: msg.p, ack: msg.ack as number | undefined };
}

export function encodeServerEvent(ev: string, p?: unknown): string {
  return JSON.stringify({ t: "e", ev, p });
}

export function encodeServerAck(ack: number, p?: unknown): string {
  return JSON.stringify({ t: "a", ack, p });
}

// ---------- Vertrag 2: RELAY (Swift/Sim ↔ Host-JS) ----------

/** Relay → Host: neue Telefon-Verbindung / Frame / Verbindung weg.
 * `reset` kommt beim (Re-)Attach der Host-Bridge und nennt ALLE aktuell am
 * Relay verbundenen clientIds — alles andere im Shim ist eine Leiche des
 * alten Relay-Prozesses (nach SIGKILL kommt dessen close nie an) und wird
 * als disconnect aufgeräumt (D3-Fix). Relays OHNE reset (älterer Swift-
 * Wrapper) funktionieren unverändert — der Frame ist rein additiv. */
export type RelayZumHost =
  | { kind: "open"; clientId: string }
  | { kind: "frame"; clientId: string; data: string }
  | { kind: "close"; clientId: string }
  | { kind: "reset"; clients: string[] };

/** Host → Relay: Frame an EIN Telefon / Verbindung serverseitig schließen. */
export type HostZumRelay =
  { kind: "frame"; clientId: string; data: string } | { kind: "close"; clientId: string };

/** Die native (Swift) bzw. simulierte (WS) Brücke — injiziert vom Host-Entry. */
export interface RelayBridge {
  send(msg: HostZumRelay): void;
  onMessage(cb: (msg: RelayZumHost) => void): void;
}

// ---------- socket.io-Mini-Shim für wireSockets()/Room ----------

type Handler = (payload: unknown, ack?: (antwort: unknown) => void) => void;

/** Genau die Socket-Oberfläche, die core/sockets.ts + rooms/room.ts nutzen —
 * inklusive der socket.io-Kanäle (join/leave/io.to) des Lobby-Browsers. */
export interface ShimSocket {
  id: string;
  on(event: string, handler: Handler): void;
  emit(event: string, payload?: unknown): void;
  join(kanal: string): void;
  leave(kanal: string): void;
}

export interface RelaySocketServer {
  /** socket.io-Server-Oberfläche für wireSockets() — per Cast andocken. */
  alsIoServer(): Server;
  /** Verbundene Telefon-Sockets (Status-Anzeige der Host-Seite). */
  anzahlClients(): number;
}

export interface RelayServerOptions {
  /**
   * LAN-Origin des iPads (z. B. http://192.168.1.20:8080). Die Web-Clients
   * melden ihre eigene Origin (im Host-iframe wäre das localhost) — für
   * Join-URL/QR zählt aber die Adresse, unter der die TELEFONE das Relay
   * erreichen. Deshalb schreibt der Shim `origin` in room.create/hello um.
   */
  origin?: string;
}

/**
 * Nimmt Relay-Frames entgegen und übersetzt sie in socket.io-Semantik:
 * open → connection-Event, frame → socket.on-Handler (mit Ack-Rückkanal),
 * close → disconnect. Rückrichtung: socket.emit → Wire-Event-Frame ans Relay.
 */
export function createRelaySocketServer(
  bridge: RelayBridge,
  opts: RelayServerOptions = {},
): RelaySocketServer {
  const connectionHandlers: ((socket: Socket) => void)[] = [];
  interface ClientEintrag {
    handlers: Map<string, Handler[]>;
    kanaele: Set<string>; // socket.io-„Rooms" (Lobby-Browser-Abo)
  }
  const sockets = new Map<string, ClientEintrag>(); // key = clientId

  function erzeugeSocket(clientId: string): ShimSocket {
    const eintrag: ClientEintrag = { handlers: new Map(), kanaele: new Set() };
    sockets.set(clientId, eintrag);
    return {
      id: clientId,
      on(event, handler) {
        const liste = eintrag.handlers.get(event) ?? [];
        liste.push(handler);
        eintrag.handlers.set(event, liste);
      },
      emit(event, payload) {
        bridge.send({ kind: "frame", clientId, data: encodeServerEvent(event, payload) });
      },
      join: (kanal) => eintrag.kanaele.add(kanal),
      leave: (kanal) => eintrag.kanaele.delete(kanal),
    };
  }

  function dispatch(
    clientId: string,
    event: string,
    payload: unknown,
    ack?: (a: unknown) => void,
  ): void {
    const handlers = sockets.get(clientId)?.handlers.get(event);
    if (!handlers) return;
    for (const handler of handlers) handler(payload, ack);
  }

  bridge.onMessage((msg) => {
    if (msg.kind === "open") {
      if (sockets.has(msg.clientId)) return; // doppeltes open (Bridge-Reconnect) ignorieren
      const socket = erzeugeSocket(msg.clientId);
      for (const handler of connectionHandlers) handler(socket as unknown as Socket);
      return;
    }
    if (msg.kind === "reset") {
      // Relay-(Re-)Start: Einträge, deren clientId das Relay nicht mehr kennt,
      // sind tot (kein close kam je an) — disconnect feuern (Room-Presence +
      // probeTimer-Aufräumen in core/sockets) und Eintrag löschen. BEKANNTE
      // clientIds bleiben unangetastet: ein Bridge-Reconnect ohne Relay-Tod
      // trennt die Telefone nicht. relay-sim vergibt clientIds pro Boot
      // eindeutig (c_<nonce>_<n>) — nach einem Relay-Neustart kollidiert
      // also nichts mehr mit alten Einträgen.
      const bekannt = new Set(msg.clients);
      for (const clientId of [...sockets.keys()]) {
        if (bekannt.has(clientId)) continue;
        dispatch(clientId, "disconnect", undefined);
        sockets.delete(clientId);
      }
      return;
    }
    if (msg.kind === "close") {
      dispatch(msg.clientId, "disconnect", undefined);
      sockets.delete(msg.clientId);
      return;
    }
    // frame: Wire-Event parsen, Origin umschreiben, an die Handler geben.
    const event = parseWireClientEvent(msg.data);
    if (event === null || !sockets.has(msg.clientId)) return;
    const payload = mitLanOrigin(event.ev, event.p, opts.origin);
    const ackId = event.ack;
    const ack =
      ackId === undefined
        ? undefined
        : (antwort: unknown): void => {
            bridge.send({
              kind: "frame",
              clientId: msg.clientId,
              data: encodeServerAck(ackId, antwort),
            });
          };
    dispatch(msg.clientId, event.ev, payload, ack);
  });

  return {
    alsIoServer(): Server {
      const ioLike = {
        on(event: string, handler: (socket: Socket) => void): void {
          if (event === "connection") connectionHandlers.push(handler);
        },
        // io.to(kanal).emit(…) — Broadcast an alle Sockets im Kanal
        // (Lobby-Browser-Live-Liste, core/sockets.ts).
        to(kanal: string): { emit(event: string, payload?: unknown): void } {
          return {
            emit(event: string, payload?: unknown): void {
              for (const [clientId, eintrag] of sockets) {
                if (eintrag.kanaele.has(kanal)) {
                  bridge.send({ kind: "frame", clientId, data: encodeServerEvent(event, payload) });
                }
              }
            },
          };
        },
      };
      return ioLike as unknown as Server;
    },
    anzahlClients: () => sockets.size,
  };
}

/** room.create/hello tragen die Client-Origin — im Standalone zählt die LAN-Origin. */
function mitLanOrigin(ev: string, payload: unknown, origin: string | undefined): unknown {
  if (origin === undefined) return payload;
  if (ev !== "room.create" && ev !== "hello") return payload;
  if (typeof payload !== "object" || payload === null) return payload;
  const objekt = payload as Record<string, unknown>;
  if (ev === "hello" && objekt.origin === undefined) return payload; // Player/GM senden keine Origin
  return { ...objekt, origin };
}
