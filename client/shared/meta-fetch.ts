// Meta-API-Zugriff mit Transport-Weiche (W4 iPad-Standalone): Am AMP-/PC-
// Server sind /api/meta/* normale HTTP-Routen (fetch). Im Standalone-Modus
// (iPad = Server) liefert HTTP nur statische Dateien — die Meta-Routen leben
// im Browser-Server hinter dem Relay. Dieselben Requests reisen dann als
// Wire-Event "meta.http" ({method, pfad, body} → {status, body}, Vertrag:
// server/meta/wire-api.ts) über den GETEILTEN Standalone-WebSocket.
// Aufrufer (meta-join/meta-ende/meta-gm/meta-landing/screen) nutzen NUR noch
// metaFetch — die Weiche ist für sie unsichtbar.
import { holeGeteiltenStandaloneSocket, istStandalone } from "./standalone-transport";

export interface MetaAntwort {
  ok: boolean;
  status: number;
  /** Bereits geparster JSON-Body (bei Netz-/Parse-Fehlern wirft metaFetch). */
  json: unknown;
}

export interface MetaFetchOptionen {
  method?: "GET" | "POST";
  body?: unknown;
}

const WIRE_TIMEOUT_MS = 10_000;

async function ueberHttp(pfad: string, opts: MetaFetchOptionen): Promise<MetaAntwort> {
  const r = await fetch(pfad, {
    method: opts.method ?? (opts.body === undefined ? "GET" : "POST"),
    headers: opts.body === undefined ? {} : { "content-type": "application/json" },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  return { ok: r.ok, status: r.status, json: await r.json().catch(() => ({})) };
}

async function ueberWire(pfad: string, opts: MetaFetchOptionen): Promise<MetaAntwort> {
  const socket = holeGeteiltenStandaloneSocket();
  const antwort = (await socket.timeout(WIRE_TIMEOUT_MS).emitWithAck("meta.http", {
    method: opts.method ?? (opts.body === undefined ? "GET" : "POST"),
    pfad,
    body: opts.body,
  })) as { status?: number; body?: unknown } | null;
  const status = typeof antwort?.status === "number" ? antwort.status : 500;
  return { ok: status >= 200 && status < 300, status, json: antwort?.body ?? {} };
}

/**
 * fetch-Ersatz für /api/meta/*-Routen: gleiche Semantik auf beiden Wegen.
 * Wirft bei Transport-Fehlern (kein Netz / Ack-Timeout) — Aufrufer behandeln
 * das wie bisher ihren fetch-catch („Keine Verbindung").
 */
export function metaFetch(pfad: string, opts: MetaFetchOptionen = {}): Promise<MetaAntwort> {
  return istStandalone() ? ueberWire(pfad, opts) : ueberHttp(pfad, opts);
}
