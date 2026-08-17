// Wiring: Express-App + socket.io + Tick-Schleife. Ein Prozess, kein Cluster.
import { createServer } from "node:http";
import { Server } from "socket.io";
import { raeumeEventLogsAuf } from "../analytics/log-rotation";
import { createContentLoader } from "../content-loader/index";
import { createMetaService } from "../meta/index";
import { registriereMetaApi } from "../meta/http-api";
import { allePlugins, allePluginsFuer, getPlugin } from "../minigames/registry";
import { createFileStorage } from "../persistence/storage";
import { RoomManager } from "../rooms/room-manager";
import { createRealClock, createSeededRng } from "./clock";
import { loadConfig } from "./config";
import { registriereFehlerApi } from "./fehler-telemetrie";
import { createHttpApp } from "./http";
import { wireSockets } from "./sockets";
import { createTunnelManager } from "./tunnel";

export async function main(): Promise<void> {
  const config = loadConfig();
  const clock = createRealClock();
  const rng = createSeededRng();
  const storage = createFileStorage(config.dataDir);
  const contentLoader = createContentLoader();
  await contentLoader.loadPacks();
  // Song-Pack (Musik-Minigames) — fehlende songs.json ist ok (0 Songs).
  await contentLoader.loadSongs?.();

  // META: Profile/AT/Shop/Bots/Saves/Analytics — hängt als Hooks an den Räumen.
  const meta = createMetaService({ storage, clock, rng, contentLoader });

  const manager = new RoomManager(
    {
      clock,
      rng,
      storage,
      contentLoader,
      plugins: { get: getPlugin, alle: allePlugins, alleFuer: allePluginsFuer },
      fragenProMatch: config.fragenProMatch,
      meta,
    },
    { maxRooms: config.maxRooms },
  );
  meta.verbindeManager((room, code) => manager.schluessleUm(room, code));

  // Event-Log-Rotation light (Eval-7): >30 Tage ODER >500 Dateien ⇒ älteste weg.
  try {
    const rotation = await raeumeEventLogsAuf(storage.resolve("events"), clock.now());
    if (rotation.geloescht > 0) {
      console.log(
        `🧹 Event-Logs aufgeräumt: ${rotation.geloescht} gelöscht, ${rotation.behalten} behalten`,
      );
    }
  } catch (err) {
    console.error("Event-Log-Rotation fehlgeschlagen:", err);
  }

  // Crash-Schutz (Eval-7 P1): Räume mit frischem Autosave (< 10 min) beim Boot
  // automatisch wiederbeleben — Spieler-Tokens resumen dann nahtlos, der GM
  // drückt nur noch „Pause beenden". Origin ist ein Platzhalter: der Screen
  // setzt sie bei seinem hello sowieso frisch (Tunnel vs. LAN).
  try {
    const wiederbelebt = await meta.bootWiederbelebung({
      erzeuge: () => manager.erzeugeRaum(`http://localhost:${config.port}`),
      verwerfe: (room) => manager.verwerfeRaum(room),
    });
    for (const w of wiederbelebt) {
      console.log(
        `🔁 Boot-Wiederbelebung: Raum ${w.code} aus Autosave wiederhergestellt ` +
          `(Phase ${w.phase}, Frage ${w.frageNr}, ${Math.round(w.alterMs / 1000)} s alt)`,
      );
    }
  } catch (err) {
    console.error("Boot-Wiederbelebung fehlgeschlagen:", err);
  }

  // INTERNET-LINK (W4): Cloudflare-Quick-Tunnel — Screen-Lobby/GM-Cockpit
  // starten ihn per Socket-Kommando (tunnel.start/stop). Der Tunnel ENDET mit
  // dem Server: SIGINT/SIGTERM/exit killen das cloudflared-Kind mit.
  const tunnel = createTunnelManager({ port: config.port });
  tunnel.onStatus((s) => {
    if (s.phase === "laeuft") console.log(`🌐 Internet-Link läuft: ${s.url}`);
    if (s.phase === "fehler" || s.phase === "nicht-installiert") {
      console.warn(`🌐 Internet-Link: ${s.fehler}`);
    }
  });
  process.once("exit", () => tunnel.stop());
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => {
      tunnel.stop();
      process.exit(signal === "SIGINT" ? 130 : 143);
    });
  }

  const app = createHttpApp(manager, { tunnel });
  registriereMetaApi(app, meta, { adminPin: config.adminPin });
  // pageerror-Telemetrie: POST /api/fehler (JSONL + 10/min/IP-Drossel) +
  // GET /api/admin/fehler (letzte 20 für die Admin-Seite).
  registriereFehlerApi(app, { dataDir: config.dataDir, adminPin: config.adminPin });
  const httpServer = createServer(app);
  const io = new Server(httpServer, {
    // Heartbeat auf Transport-Ebene (TECH-SPEC §3.4).
    pingInterval: 10_000,
    pingTimeout: 8_000,
  });
  wireSockets(io, manager, { tunnel });

  // Tick-System: treibt Server-Timer + TTL-Abbau. Timer laufen NUR auf dem Server.
  setInterval(() => manager.tickAlle(), config.tickMs);
  // META: Aggregations-Job (Event-Log → materialisierte Stats) alle 60 s.
  setInterval(() => void meta.aggregator.aktualisiere().catch(() => undefined), 60_000);

  httpServer.listen(config.port, () => {
    console.log(`MONKEY MONEY Server läuft auf http://localhost:${config.port}`);
    console.log(`  DATA_DIR=${config.dataDir} · MAX_ROOMS=${config.maxRooms}`);
  });
}
