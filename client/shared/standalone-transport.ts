// Standalone-Transport (iPad = Server, docs/IPAD-SETUP.md „Weg 3"): Ersetzt
// socket.io-client durch einen NATIVEN WebSocket zum Relay (Swift im Wrapper
// bzw. tools/ipad-host/relay-sim.mjs). Wire-Format = server/host-browser/
// relay.ts Vertrag 1: {t:"e",ev,p,ack?} rauf, {t:"e",ev,p}/{t:"a",ack,p} runter.
//
// Erkennung: ?standalone=1 in der URL — das Relay hängt den Parameter beim
// Ausliefern von /screen /gm /player /j/:code per Redirect an, QR-Links
// funktionieren also unverändert. Ohne den Parameter läuft io() wie bisher
// (AMP-/PC-Server-Pfad) — BEIDE Wege leben im selben Build.
//
// Die Oberfläche spiegelt exakt die socket.io-Client-Aufrufe der App-Codes
// (socket.on / emit mit Ack-Callback / timeout().emitWithAck) — createConnection
// in socket.ts bleibt bis auf die eine Weiche unverändert.

interface Ausstehend {
  resolve: (antwort: unknown) => void;
  reject: (fehler: Error) => void;
  timer: ReturnType<typeof setTimeout> | null;
}

export interface StandaloneSocket {
  on(event: string, handler: (payload: unknown, ack?: unknown) => void): void;
  emit(event: string, payload?: unknown, ack?: (antwort: unknown) => void): void;
  timeout(ms: number): { emitWithAck(event: string, payload?: unknown): Promise<unknown> };
}

/** Standalone-Modus? (Relay hängt ?standalone=1 an alle Rollen-URLs.) */
export function istStandalone(): boolean {
  return new URLSearchParams(window.location.search).get("standalone") === "1";
}

/** Minimal-Oberfläche eines WebSockets — injizierbar für Tests (vitest = Node). */
export interface WsLike {
  readonly readyState: number;
  send(data: string): void;
  close(): void;
  onopen: (() => void) | null;
  onmessage: ((event: { data: unknown }) => void) | null;
  onclose: (() => void) | null;
  onerror: (() => void) | null;
}

export interface StandaloneSocketDeps {
  /** WS-Fabrik (Default: nativer WebSocket auf ws(s)://<host>/ws). */
  wsFabrik?: () => WsLike;
}

const WS_OPEN = 1; // WebSocket.OPEN — als Konstante, damit Tests ohne DOM laufen

/** GETEILTER Socket pro Seite (W4): Spiel-Verbindung (socket.ts) UND
 * Meta-HTTP-über-Wire (meta-fetch.ts) laufen über EINE WS-Verbindung zum
 * Relay — sonst zählte die Host-Anzeige jedes Telefon doppelt. */
let geteilterSocket: StandaloneSocket | null = null;

export function holeGeteiltenStandaloneSocket(): StandaloneSocket {
  geteilterSocket ??= createStandaloneSocket();
  return geteilterSocket;
}

export function createStandaloneSocket(deps: StandaloneSocketDeps = {}): StandaloneSocket {
  const wsFabrik =
    deps.wsFabrik ??
    ((): WsLike => {
      const proto = window.location.protocol === "https:" ? "wss" : "ws";
      return new WebSocket(`${proto}://${window.location.host}/ws`) as unknown as WsLike;
    });
  const handlers = new Map<string, ((payload: unknown, ack?: unknown) => void)[]>();
  const ausstehend = new Map<number, Ausstehend>();
  /** Puffer für Emits vor dem ersten open (socket.io puffert genauso). */
  let sendePuffer: string[] = [];
  let ws: WsLike | null = null;
  let ackNr = 0;
  let reconnectMs = 500;
  let verbunden = false;

  function feuere(event: string, payload?: unknown): void {
    for (const handler of handlers.get(event) ?? []) handler(payload);
  }

  function sende(zeile: string): void {
    if (ws !== null && ws.readyState === WS_OPEN) ws.send(zeile);
    else sendePuffer.push(zeile);
  }

  function verbinde(): void {
    ws = wsFabrik();

    ws.onopen = () => {
      reconnectMs = 500;
      verbunden = true;
      const puffer = sendePuffer;
      sendePuffer = [];
      for (const zeile of puffer) ws?.send(zeile);
      // socket.io-Semantik: "connect" feuert bei JEDEM (Re-)Connect —
      // createConnection macht darauf sein hello (fachlicher Reconnect).
      feuere("connect");
    };

    ws.onmessage = (event: { data: unknown }) => {
      let msg: { t?: string; ev?: string; p?: unknown; ack?: number };
      try {
        msg = JSON.parse(String(event.data)) as typeof msg;
      } catch {
        return;
      }
      if (msg.t === "a" && typeof msg.ack === "number") {
        const wartend = ausstehend.get(msg.ack);
        if (wartend) {
          ausstehend.delete(msg.ack);
          if (wartend.timer !== null) clearTimeout(wartend.timer);
          wartend.resolve(msg.p);
        }
        return;
      }
      if (msg.t === "e" && typeof msg.ev === "string") feuere(msg.ev, msg.p);
    };

    ws.onclose = () => {
      verbunden = false;
      feuere("disconnect", "transport close");
      // Exponentieller Backoff bis 5 s — das iPad-WLAN kommt wieder.
      setTimeout(verbinde, reconnectMs);
      reconnectMs = Math.min(reconnectMs * 2, 5000);
    };
    ws.onerror = () => ws?.close();
  }

  function emitMitAck(event: string, payload: unknown, timeoutMs: number | null): Promise<unknown> {
    const ack = ++ackNr;
    return new Promise((resolve, reject) => {
      const timer =
        timeoutMs === null
          ? null
          : setTimeout(() => {
              ausstehend.delete(ack);
              reject(new Error(`ack-timeout nach ${timeoutMs} ms (${event})`));
            }, timeoutMs);
      ausstehend.set(ack, { resolve, reject, timer });
      sende(JSON.stringify({ t: "e", ev: event, p: payload, ack }));
    });
  }

  verbinde();

  return {
    on(event, handler) {
      const liste = handlers.get(event) ?? [];
      liste.push(handler);
      handlers.set(event, liste);
      // GETEILTER Socket (W4): meta-fetch verbindet oft VOR createConnection
      // (Profil-Liste lädt schon im Join-Formular) — ein SPÄTER registrierter
      // connect-Handler (socket.ts: hello!) würde das längst gefeuerte
      // connect sonst nie sehen und der Join bliebe stumm hängen.
      if (event === "connect" && verbunden) queueMicrotask(() => handler(undefined));
    },
    emit(event, payload, ackCb) {
      if (ackCb !== undefined) {
        void emitMitAck(event, payload, 10_000).then(ackCb, () => undefined);
        return;
      }
      sende(JSON.stringify({ t: "e", ev: event, p: payload }));
    },
    timeout(ms) {
      return { emitWithAck: (event, payload) => emitMitAck(event, payload, ms) };
    },
  };
}
