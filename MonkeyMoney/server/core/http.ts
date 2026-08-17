// Express-HTTP-Schicht: Static aus client/dist/, /healthz, /api/qr, /j/:code.
// QR wird SERVERSEITIG erzeugt (qrcode-npm) — kein externer Dienst (LAN ohne Internet!).
import express, { type Express } from "express";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import QRCode from "qrcode";
import { parseBettTracks, type BettTrack } from "../../shared/songs";
import { erzeugeLobbyCache, waehleSchnellBeitritt } from "../rooms/lobby";
import type { RoomManager } from "../rooms/room-manager";
import type { TunnelManager } from "./tunnel";

/** ADDITIVE HTTP-Dienste (Internet-Link) — optional, Tests laufen auch ohne. */
export interface HttpExtras {
  tunnel?: TunnelManager;
}

/** client/dist liegt zwei Ebenen über dieser Datei (gilt für Dev UND esbuild-Bundle). */
export function findClientDist(): string {
  const hier = dirname(fileURLToPath(import.meta.url));
  return resolve(hier, "../../client/dist");
}

/** Laufzeit-Medien (Fragen-Bilder, Stinger-/Tutorial-Videos): repo-assets/.
 * BEWUSST Server-Static statt Vite-Public — Content-Packs referenzieren die
 * Dateien zur Laufzeit (medienUrl), sie gehören nicht ins Client-Bundle. */
export function findMediaRoot(): string {
  const hier = dirname(fileURLToPath(import.meta.url));
  return resolve(hier, "../../assets");
}

/** Song-Snippets der Musik-Minigames: content/musik/media/ ⇒ /media-musik/*
 * (Vertrag: shared/songs.ts#songMediaUrl — songs.json referenziert
 * „media/<id>/…" relativ zu content/musik/). */
export function findMusikMediaRoot(): string {
  const hier = dirname(fileURLToPath(import.meta.url));
  return resolve(hier, "../../content/musik/media");
}

/** Bett-Loops der Show-Musik-Rotation (import.mjs --bett):
 * content/musik/bett/ ⇒ /media-musik-bett/* (songMediaUrl „bett/<id>.ogg"). */
export function findMusikBettRoot(): string {
  const hier = dirname(fileURLToPath(import.meta.url));
  return resolve(hier, "../../content/musik/bett");
}

/** Bett-Playlist aus songs.json (nurBett + medien.bett) — die Screen-Rotation
 * holt sie über GET /api/musik/betten. Fehlende/kaputte Datei ⇒ leere Liste
 * (die Standard-MacLeod-Betten des Clients laufen dann allein weiter). */
export function ladeBettTracks(): BettTrack[] {
  const pfad = resolve(dirname(fileURLToPath(import.meta.url)), "../../content/musik/songs.json");
  if (!existsSync(pfad)) return [];
  try {
    const katalog = JSON.parse(readFileSync(pfad, "utf8")) as { songs?: unknown[] };
    return parseBettTracks(katalog.songs);
  } catch {
    return [];
  }
}

export function createHttpApp(manager: RoomManager, extras: HttpExtras = {}): Express {
  const app = express();
  const clientDist = findClientDist();

  if (!existsSync(join(clientDist, "index.html"))) {
    console.warn(`WARNUNG: ${clientDist} fehlt — erst \`npm run build\` ausführen.`);
  }

  app.get("/healthz", (_req, res) => {
    res.json({ ok: true, rooms: manager.anzahl, uptimeS: Math.round(process.uptime()) });
  });

  // ---------- LOBBY (ADDITIV): öffentlicher Lobby-Browser + Schnell-Beitritt ----------

  // GET /api/musik/betten — Bett-Loops für die Musik-Rotation (Screen/GM).
  // Bewusst pro Request frisch gelesen: neue --bett-Importe erscheinen ohne
  // Server-Neustart (die Datei ist winzig, der Endpoint wird 1× pro Boot geholt).
  app.get("/api/musik/betten", (_req, res) => {
    res.json({ betten: ladeBettTracks() });
  });

  // GET /api/lobbys — öffentliche Lobbys für die Landing (2 s gecacht).
  const lobbys = erzeugeLobbyCache(() => manager.lobbyListe(), manager.clock);
  app.get("/api/lobbys", (_req, res) => {
    res.json({ lobbys: lobbys() });
  });

  // GET /api/schnell-beitritt — „Matchmaking light": die vollste offene
  // öffentliche Lobby (< 8 Spieler). UNGECACHT: der Klick soll den echten
  // Stand sehen (sonst rennen 2 schnelle Klicker in eine frisch volle Lobby).
  app.get("/api/schnell-beitritt", (_req, res) => {
    const lobby = waehleSchnellBeitritt(manager.lobbyListe());
    if (lobby === null) {
      res.status(404).json({ ok: false, error: "keine-lobby" });
      return;
    }
    res.json({ ok: true, code: lobby.code, name: lobby.name, spieler: lobby.spieler });
  });

  // GET /api/raum/:code — minimaler Lebens-Check fürs „Wieder beitreten?"-
  // Banner der Landing (Raum-Existenz verrät auch die Join-Seite — kein Leak).
  app.get("/api/raum/:code", (req, res) => {
    const room = manager.finde(String(req.params.code ?? ""));
    if (!room) {
      res.status(404).json({ ok: false, error: "raum-nicht-gefunden" });
      return;
    }
    res.json({
      ok: true,
      status: room.state.phase === "lobby" ? "lobby" : "laeuft",
      spieler: room.state.order.length,
    });
  });

  // Server-seitiger QR-Code: Join-URL aus der Screen-Origin des Raums (TECH-SPEC §7.2).
  // INTERNET-LINK (ADDITIV): ?via=tunnel parametrisiert die Ziel-URL — der QR
  // zeigt dann die ÖFFENTLICHE Tunnel-URL statt der (LAN-)Screen-Origin.
  // Bewusst KEINE freie url=…-Übergabe: der Server kennt die Tunnel-URL selbst,
  // ein offener QR-Generator für Fremd-URLs wäre ein Phishing-Geschenk.
  app.get("/api/qr", (req, res) => {
    const code = String(req.query.code ?? "");
    const room = manager.finde(code);
    if (!room) {
      res.status(404).json({ error: "raum-nicht-gefunden" });
      return;
    }
    let origin = room.origin;
    if (String(req.query.via ?? "") === "tunnel") {
      const tunnelStatus = extras.tunnel?.status();
      if (tunnelStatus?.phase !== "laeuft" || tunnelStatus.url === null) {
        res.status(409).json({ error: "tunnel-laeuft-nicht" });
        return;
      }
      origin = tunnelStatus.url;
    }
    const joinUrl = `${origin}/j/${room.code}`;
    QRCode.toString(joinUrl, { type: "svg", margin: 1, width: 512 }, (err, svg) => {
      if (err) {
        res.status(500).json({ error: "qr-fehler" });
        return;
      }
      res.type("image/svg+xml").send(svg);
    });
  });

  // Join-Kurz-URLs: /j/AFFE und /join/AFFE landen im Player-Client (Code aus dem Pfad).
  app.get(["/j/:code", "/join/:code"], (_req, res) => {
    res.sendFile(join(clientDist, "player.html"));
  });

  // Saubere Rollen-URLs ohne .html.
  app.get("/screen", (_req, res) => res.sendFile(join(clientDist, "screen.html")));
  app.get("/player", (_req, res) => res.sendFile(join(clientDist, "player.html")));
  app.get("/gm", (_req, res) => res.sendFile(join(clientDist, "gm.html")));

  // /media/* → repo-assets/* (z. B. /media/img/generated/pixel/…, /media/video/…).
  // Getrennt vom Vite-/assets-Ordner in client/dist — keine Namens-Kollision.
  app.use("/media", express.static(findMediaRoot(), { fallthrough: false }));

  // /media-musik/* → content/musik/media/* (Song-Snippets der Musik-Minigames;
  // Ordner existiert erst nach dem ersten tools/musik/import.mjs-Lauf).
  if (existsSync(findMusikMediaRoot())) {
    app.use("/media-musik", express.static(findMusikMediaRoot(), { fallthrough: false }));
  }

  // /media-musik-bett/* → content/musik/bett/* (Bett-Loops, import.mjs --bett).
  if (existsSync(findMusikBettRoot())) {
    app.use("/media-musik-bett", express.static(findMusikBettRoot(), { fallthrough: false }));
  }

  app.use(express.static(clientDist));
  return app;
}
