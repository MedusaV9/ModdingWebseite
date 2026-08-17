// Kompositions-Wurzel des Browser-Servers (Standalone-Modus): das Gegenstück
// zu server/core/index.ts, nur ohne Node — Express/socket.io/fs sind durch
// Relay-Shim (relay.ts), IndexedDB-Storage (browser-storage.ts) und das
// statische Content-Bundle (bundle-content.ts) ersetzt. Engine, Räume,
// Minigames und core/sockets.ts laufen UNVERÄNDERT (sie sind pures TS).
//
// META ist seit W4 VOLL verdrahtet (die dokumentierte Standalone-Lücke):
// Profile/AT, Save-Slots, 30-s-Autosave, Bots und Boot-Wiederbelebung laufen
// gegen dieselbe Storage-Abstraktion — im Browser also gegen IndexedDB.
// Spielstände und Profile überleben damit App-Neustarts auf dem iPad.
// Die Meta-HTTP-Routen der Telefone (Profil anlegen/login, Save-Slots-Liste,
// Match-Ende-Meta …) laufen hier über das Wire-Event "meta.http" (EINE
// Routen-Logik: server/meta/wire-api.ts — der Node-Pfad nutzt sie via
// Express). Browser-Grenze: analytics/reports.ts (Admin-Lücken-Report) zieht
// node:fs — im Client-Build durch Stubs ersetzt (client/host/node-stubs-shim);
// meta.reports() ruft im Standalone niemand (/admin existiert dort nicht).
import { createStatefulRng } from "../../shared/rng";
import type { Clock } from "../../shared/time";
import { createMetaService, type MetaService } from "../meta/index";
import { bearbeiteMetaRequest } from "../meta/wire-api";
import { allePlugins, allePluginsFuer, getPlugin } from "../minigames/registry";
import type { Storage } from "../persistence/storage";
import { RoomManager } from "../rooms/room-manager";
import { wireSockets } from "../core/sockets";
import { createBundleContentLoader } from "./bundle-content";
import type { KatalogFrage } from "../content-loader/index";
import { createRelaySocketServer, type RelayBridge, type RelaySocketServer } from "./relay";

export interface StandaloneServerOptions {
  bridge: RelayBridge;
  /** LAN-Origin für Join-URL/QR (z. B. http://192.168.1.20:8080). */
  origin: string;
  /** Fragen-Katalog aus host-content.json (parseHostContentBundle). */
  katalog: KatalogFrage[];
  storage: Storage;
  maxRooms?: number;
  tickMs?: number;
  fragenProMatch?: number;
  /** Nur für Tests: deterministischer Seed + injizierte Uhr. */
  seed?: number;
  clock?: Clock;
}

export interface StandaloneServer {
  manager: RoomManager;
  relay: RelaySocketServer;
  /** META (W4): Profile/AT + Save-Slots + Bots — läuft gegen IndexedDB. */
  meta: MetaService;
  /** Crash-Schutz: frische Autosaves (< 10 min) beim Boot wiederbeleben —
   * ein App-Neustart mitten im Match ist damit nur eine kurze Pause. */
  wiederbelebt: Promise<{ code: string; phase: string; frageNr: number; alterMs: number }[]>;
  stop(): void;
}

export function startStandaloneServer(opts: StandaloneServerOptions): StandaloneServer {
  // Kompositions-Wurzel: HIER entsteht die echte Uhr/der echte Seed — genau
  // wie server/core/clock.ts im Node-Pfad (Engine bekommt beides injiziert).
  // eslint-disable-next-line no-restricted-properties
  const clock: Clock = opts.clock ?? { now: () => Date.now() };
  const seed = opts.seed ?? crypto.getRandomValues(new Uint32Array(1))[0];
  const rng = createStatefulRng(seed);

  const contentLoader = createBundleContentLoader(opts.katalog);
  // META wie server/core/index.ts: Profile/AT/Saves/Bots als Raum-Hooks —
  // Storage ist injiziert, im Browser also IndexedDB (browser-storage.ts).
  const meta = createMetaService({ storage: opts.storage, clock, rng, contentLoader });
  const manager = new RoomManager(
    {
      clock,
      rng,
      storage: opts.storage,
      contentLoader,
      plugins: { get: getPlugin, alle: allePlugins, alleFuer: allePluginsFuer },
      // Default wie server/core/config.ts (FRAGEN_PRO_MATCH) — die Engine
      // zieht ohnehin einen großzügigen Pool (Room.startMatch: min. 120).
      fragenProMatch: opts.fragenProMatch ?? 3,
      meta,
    },
    { maxRooms: opts.maxRooms ?? 4 },
  );
  meta.verbindeManager((room, code) => {
    const r = manager.schluessleUm(room, code);
    // save.load schlüsselt den Raum auf den GESPEICHERTEN Code um — der
    // Raum-Merker der Host-Seite (Banner-QR; Screen-Reload-Anker) muss mit,
    // sonst zeigt der QR einen toten Code. Nur im Browser (Tests = Node).
    if (r.ok && typeof sessionStorage !== "undefined") {
      try {
        sessionStorage.setItem("mm:screen-room", room.code);
      } catch {
        /* Safari-Private-Mode o. ä. — QR bleibt dann halt beim alten Code */
      }
    }
    return r;
  });

  const relay = createRelaySocketServer(opts.bridge, { origin: opts.origin });
  const io = relay.alsIoServer();
  wireSockets(io, manager);

  // Meta-HTTP über das Wire: die Telefone senden {method, pfad, body} als
  // "meta.http"-Event (client/shared/meta-fetch.ts) — Antwort ist der
  // {status, body}-Umschlag aus wire-api.ts. Zweiter connection-Handler,
  // damit core/sockets.ts unverändert bleibt (der Relay-Shim ruft alle).
  io.on("connection", (socket) => {
    socket.on("meta.http", (payload: unknown, ack?: (antwort: unknown) => void) => {
      const p = (typeof payload === "object" && payload !== null ? payload : {}) as Record<
        string,
        unknown
      >;
      void bearbeiteMetaRequest(meta, {
        method: typeof p.method === "string" ? p.method : "GET",
        pfad: typeof p.pfad === "string" ? p.pfad : "",
        body: p.body,
      }).then(
        (antwort) => ack?.(antwort),
        () => ack?.({ status: 500, body: { error: "meta-fehler" } }),
      );
    });
  });

  // Boot-Wiederbelebung (Crash-Schutz wie core/index.ts): App gekillt/Seite
  // neu geladen ⇒ laufende Matches kommen aus dem IndexedDB-Autosave zurück,
  // Spieler-Tokens (localStorage der Telefone) resumen nahtlos.
  const wiederbelebt = meta
    .bootWiederbelebung({
      erzeuge: () => manager.erzeugeRaum(opts.origin),
      verwerfe: (room) => manager.verwerfeRaum(room),
    })
    .catch((err) => {
      console.error("Boot-Wiederbelebung fehlgeschlagen:", err);
      return [];
    });

  // Tick-System wie core/index.ts: treibt Server-Timer + TTL-Abbau + den
  // ~30-s-Autosave (meta.autosaveTick läuft im Manager-Tick mit).
  const tick = setInterval(() => manager.tickAlle(), opts.tickMs ?? 250);
  // Aggregations-Job (Event-Log → materialisierte Stats) wie im Node-Pfad —
  // füttert Profil-Karten/Boards; 60 s reichen (Match-Ende stößt zusätzlich an).
  const aggregation = setInterval(
    () => void meta.aggregator.aktualisiere().catch(() => undefined),
    60_000,
  );

  return {
    manager,
    relay,
    meta,
    wiederbelebt,
    stop: () => {
      clearInterval(tick);
      clearInterval(aggregation);
    },
  };
}
