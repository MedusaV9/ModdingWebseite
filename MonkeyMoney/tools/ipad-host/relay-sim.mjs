// Relay-Simulation für den Standalone-Modus — der Node-STELLVERTRETER des
// Swift-Embedded-Servers (ios-wrapper/Sources/EmbeddedServer.swift). Beide
// implementieren EXAKT denselben Vertrag (server/host-browser/relay.ts):
//
//   HTTP  : client/dist statisch, /screen /gm /player /j/:code /host
//           (+ ?standalone=1-Redirect), /api/qr, /media → assets/, /healthz
//   WS    : /ws          = Telefon-Verbindungen (Wire-Frames, 1:1 relayt)
//           /host-bridge = die Host-Seite (Browser-Server) — im Wrapper läuft
//           dieser Kanal stattdessen über WKScriptMessageHandler
//   Frames: {kind:"open"|"frame"|"close", clientId, data?} + {kind:"reset",
//           clients} beim Host-Attach (Shim räumt Alt-Relay-Leichen auf)
//
// Damit läuft der komplette iPad-Standalone-Pfad OHNE iPad auf der VM:
//   npm run build:client && node tools/ipad-host/relay-sim.mjs
//   → http://localhost:8093/host öffnen (Chrome) = „das iPad"
//   → http://localhost:8093/j/CODE = „die iPhones"
import { createServer } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize, resolve } from "node:path";
import QRCode from "qrcode";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.RELAY_PORT ?? 8093);
const ORIGIN = process.env.RELAY_ORIGIN ?? `http://localhost:${PORT}`;
const VERBOSE = process.env.RELAY_VERBOSE === "1";
const DIST = resolve(process.cwd(), "client/dist");
const MEDIA = resolve(process.cwd(), "assets");

const log = (t) => console.log(`[relay-sim] ${t}`);
const debug = (t) => VERBOSE && console.log(`[relay-sim] ${t}`);

if (!existsSync(join(DIST, "host.html"))) {
  console.error("client/dist/host.html fehlt — erst `npm run build:client`.");
  process.exit(1);
}

// ---------- Relay-Zustand: EIN Host, n Telefon-Clients ----------
let hostSocket = null; // WS der Host-Seite (/host-bridge)
let hostPuffer = []; // Frames an den Host, solange der noch nicht dran ist
const clients = new Map(); // clientId → WS
let clientNr = 0;
// clientIds sind PRO RELAY-BOOT eindeutig (c_<nonce>_<n>): nach einem
// Relay-Neustart kollidieren neue Ids nie mit Leichen-Einträgen im
// Host-Shim (server/host-browser/relay.ts, reset-Frame räumt die auf).
const BOOT_NONCE = Math.random().toString(36).slice(2, 7);

function anHost(msg) {
  const zeile = JSON.stringify(msg);
  if (hostSocket !== null && hostSocket.readyState === 1) hostSocket.send(zeile);
  else hostPuffer.push(zeile);
}

// ---------- HTTP (Spiegel der Swift-Routen) ----------
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".webp": "image/webp",
  ".mp3": "audio/mpeg",
  ".ogg": "audio/ogg",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".ttf": "font/ttf",
  ".woff2": "font/woff2",
  ".ico": "image/x-icon",
};

function sendeDatei(res, basis, relPfad) {
  const voll = normalize(join(basis, relPfad));
  if (!voll.startsWith(basis) || !existsSync(voll) || !statSync(voll).isFile()) {
    res.writeHead(404).end("nicht gefunden");
    return;
  }
  res.writeHead(200, { "content-type": MIME[extname(voll)] ?? "application/octet-stream" });
  res.end(readFileSync(voll));
}

/** Rollen-Routen: OHNE ?standalone=1 → Redirect MIT (Clients erkennen daran den Modus). */
const ROLLEN_HTML = {
  "/screen": "screen.html",
  "/gm": "gm.html",
  "/player": "player.html",
  "/host": "host.html",
};

const httpServer = createServer((req, res) => {
  const url = new URL(req.url ?? "/", ORIGIN);
  const pfad = url.pathname;

  if (pfad === "/healthz") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, modus: "standalone-relay-sim", clients: clients.size }));
    return;
  }

  if (pfad === "/api/qr") {
    const code = String(url.searchParams.get("code") ?? "");
    QRCode.toString(`${ORIGIN}/j/${code}`, { type: "svg", margin: 1, width: 512 }, (err, svg) => {
      if (err) return res.writeHead(500).end("qr-fehler");
      res.writeHead(200, { "content-type": "image/svg+xml" });
      res.end(svg);
    });
    return;
  }

  const join4 = pfad.match(/^\/(?:j|join)\/[A-Za-z]{4}$/);
  if (ROLLEN_HTML[pfad] !== undefined || join4) {
    if (url.searchParams.get("standalone") !== "1") {
      url.searchParams.set("standalone", "1");
      res.writeHead(302, { location: `${url.pathname}${url.search}` });
      res.end();
      return;
    }
    sendeDatei(res, DIST, join4 ? "player.html" : ROLLEN_HTML[pfad]);
    return;
  }

  if (pfad.startsWith("/media/")) {
    sendeDatei(res, MEDIA, decodeURIComponent(pfad.slice("/media/".length)));
    return;
  }

  sendeDatei(res, DIST, pfad === "/" ? "index.html" : decodeURIComponent(pfad.slice(1)));
});

// ---------- WebSockets: /ws (Telefone) + /host-bridge (Host-Seite) ----------
const wss = new WebSocketServer({ noServer: true });

httpServer.on("upgrade", (req, socket, head) => {
  const pfad = new URL(req.url ?? "/", ORIGIN).pathname;
  if (pfad !== "/ws" && pfad !== "/host-bridge") {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    if (pfad === "/host-bridge") verbindeHost(ws);
    else verbindeClient(ws);
  });
});

function verbindeHost(ws) {
  hostSocket = ws;
  log("Host-Seite verbunden (/host-bridge)");
  // reset ZUERST (Vertrag relay.ts): nennt alle aktuell verbundenen Clients —
  // der Host-Shim räumt damit Leichen-Einträge eines gekillten Vorgänger-
  // Relays auf (deren close-Frames kamen nie an). Bekannte Ids bleiben.
  anHost({ kind: "reset", clients: [...clients.keys()] });
  // Nachzügler-Fairness: bereits verbundene Telefone dem (neuen) Host melden.
  for (const clientId of clients.keys()) anHost({ kind: "open", clientId });
  const puffer = hostPuffer;
  hostPuffer = [];
  for (const zeile of puffer) ws.send(zeile);

  ws.on("message", (roh) => {
    let msg;
    try {
      msg = JSON.parse(String(roh));
    } catch {
      return;
    }
    const client = clients.get(msg.clientId);
    if (msg.kind === "frame" && client !== undefined && client.readyState === 1) {
      debug(`→ ${msg.clientId}: ${String(msg.data).slice(0, 120)}`);
      client.send(msg.data);
    } else if (msg.kind === "close" && client !== undefined) {
      client.close();
    }
  });
  ws.on("close", () => {
    if (hostSocket === ws) hostSocket = null;
    log("Host-Seite getrennt");
  });
}

function verbindeClient(ws) {
  const clientId = `c_${BOOT_NONCE}_${++clientNr}`;
  clients.set(clientId, ws);
  log(`Telefon ${clientId} verbunden (${clients.size} gesamt)`);
  anHost({ kind: "open", clientId });

  ws.on("message", (roh) => {
    debug(`← ${clientId}: ${String(roh).slice(0, 120)}`);
    anHost({ kind: "frame", clientId, data: String(roh) });
  });
  ws.on("close", () => {
    clients.delete(clientId);
    anHost({ kind: "close", clientId });
    log(`Telefon ${clientId} getrennt`);
  });
}

httpServer.listen(PORT, () => {
  log(`läuft auf ${ORIGIN} (dist=${DIST})`);
  log(`Host-Seite:  ${ORIGIN}/host`);
  log(`Telefone:    ${ORIGIN}/j/<CODE>  (QR von der Bühne)`);
});
