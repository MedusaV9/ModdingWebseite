// Standalone-Host-Seite (iPad = Server, docs/IPAD-SETUP.md „Weg 3"):
// Diese Seite IST der Spiel-Server. Sie bootet Engine/Räume/Minigames im
// Browser (server/host-browser/boot.ts), hängt sich an das Relay (Swift im
// Wrapper via WKScriptMessageHandler, sonst WebSocket zum relay-sim) und
// zeigt die Bühne als iframe (/screen?standalone=1) — das Screen-UI läuft
// damit UNVERÄNDERT und verbindet sich wie die Telefone über das Relay.
//
// ESLint-Ausnahme (eslint.config.js): client/host/** darf server/host-browser
// importieren — das ist der EINZIGE Client, der Server-Code bündelt (Zweck!).
import { parseHostContentBundle } from "../../server/host-browser/bundle-content";
import { startStandaloneServer, type StandaloneServer } from "../../server/host-browser/boot";
import {
  createBrowserStorage,
  createMemoryStorage,
} from "../../server/host-browser/browser-storage";
import type { HostZumRelay, RelayBridge, RelayZumHost } from "../../server/host-browser/relay";
import "./host.css";

// ---------- Relay-Brücke: nativ (WKWebView) oder Simulation (WebSocket) ----------

interface WebkitFenster {
  webkit?: { messageHandlers?: { mmRelay?: { postMessage(text: string): void } } };
  __mmRelayEmpfang?: (json: string) => void;
}

/** Wrapper-Pfad: Swift schiebt Frames via evaluateJavaScript rein,
 * postMessage raus (WKScriptMessageHandler "mmRelay"). */
function createWebkitBridge(handler: { postMessage(text: string): void }): RelayBridge {
  let empfang: ((msg: RelayZumHost) => void) | null = null;
  (window as WebkitFenster).__mmRelayEmpfang = (json: string) => {
    try {
      empfang?.(JSON.parse(json) as RelayZumHost);
    } catch {
      /* kaputter Frame vom Relay — ignorieren */
    }
  };
  return {
    send: (msg: HostZumRelay) => handler.postMessage(JSON.stringify(msg)),
    onMessage: (cb) => {
      empfang = cb;
    },
  };
}

/** VM-/Desktop-Pfad: tools/ipad-host/relay-sim.mjs spricht denselben
 * Frame-Kontrakt über einen eigenen WebSocket (/host-bridge). */
function createWebSocketBridge(): RelayBridge {
  let empfang: ((msg: RelayZumHost) => void) | null = null;
  let ws: WebSocket | null = null;
  let puffer: string[] = [];

  function verbinde(): void {
    const proto = window.location.protocol === "https:" ? "wss" : "ws";
    ws = new WebSocket(`${proto}://${window.location.host}/host-bridge`);
    ws.onopen = () => {
      const wartend = puffer;
      puffer = [];
      for (const zeile of wartend) ws?.send(zeile);
    };
    ws.onmessage = (event) => {
      try {
        empfang?.(JSON.parse(String(event.data)) as RelayZumHost);
      } catch {
        /* kaputter Frame — ignorieren */
      }
    };
    ws.onclose = () => setTimeout(verbinde, 1000);
    ws.onerror = () => ws?.close();
  }
  verbinde();

  return {
    send(msg: HostZumRelay) {
      const zeile = JSON.stringify(msg);
      if (ws !== null && ws.readyState === WebSocket.OPEN) ws.send(zeile);
      else puffer.push(zeile);
    },
    onMessage: (cb) => {
      empfang = cb;
    },
  };
}

// ---------- Boot ----------

const app = document.getElementById("app")!;

function zeigeStatus(text: string): void {
  app.innerHTML = `<div class="host-lade"><h1>🐒 MONKEY MONEY</h1><p>${text}</p></div>`;
}

async function boot(): Promise<void> {
  zeigeStatus("Standalone-Server startet …");

  // LAN-Origin: der Wrapper übergibt sie per URL-Parameter (die Telefone
  // erreichen das iPad ja NICHT unter localhost) — Fallback: eigene Origin.
  const params = new URLSearchParams(window.location.search);
  const origin = params.get("origin") ?? window.location.origin;

  // 1) Fragen-Katalog (Build-Zeit-Bundle, gleiche Quelle wie der Node-Server).
  const antwort = await fetch("/host-content.json");
  if (!antwort.ok) {
    zeigeStatus(`host-content.json fehlt (${antwort.status}) — Build unvollständig?`);
    return;
  }
  const bundle = parseHostContentBundle(await antwort.json());

  // 2) Persistenz: IndexedDB; wenn iOS sie verweigert, läuft das Match im RAM
  // (dann ohne Neustart-Persistenz — Saves/Profile brauchen IndexedDB).
  const storage = await createBrowserStorage().catch(() => createMemoryStorage());

  // 3) Relay-Brücke wählen: nativer Wrapper oder WebSocket-Simulation.
  const nativHandler = (window as WebkitFenster).webkit?.messageHandlers?.mmRelay;
  const bridge = nativHandler ? createWebkitBridge(nativHandler) : createWebSocketBridge();

  // 4) Server hochfahren — ab hier ist diese Seite die Autorität.
  const server = startStandaloneServer({ bridge, origin, katalog: bundle.fragen, storage });

  // 5) Boot-Wiederbelebung ABWARTEN, bevor die Bühne lädt: kam ein Match aus
  // dem Autosave zurück (App-Neustart mitten im Abend), hängt sich der Screen
  // an DEN Raum statt einen frischen zu eröffnen — Telefon-Tokens (localStorage
  // mm:CODE) resumen nahtlos. Ohne Wiederbelebung wäre ein alter Raum-Merker
  // eine Falle (Serverzustand weg) — dann weg damit, der Screen eröffnet neu.
  const wiederbelebte = await server.wiederbelebt;
  const juengster = wiederbelebte.at(-1);
  if (juengster !== undefined) {
    sessionStorage.setItem("mm:screen-room", juengster.code);
    console.log(
      `🔁 Boot-Wiederbelebung: Raum ${juengster.code} aus dem Autosave zurück ` +
        `(Phase ${juengster.phase}, Frage ${juengster.frageNr})`,
    );
  } else {
    sessionStorage.removeItem("mm:screen-room");
  }

  render(server, origin, bundle.fragen.length, nativHandler ? "iPad-App" : "Relay-Sim");
}

function render(
  server: StandaloneServer,
  origin: string,
  fragenAnzahl: number,
  relayArt: string,
): void {
  // Die ADRESSE ist das Wichtigste auf dieser Seite (Task-Hoheit W4): groß,
  // monospace, mit QR — dazu der WLAN-Hinweis und der Lokal-Speicher-Beleg.
  // Banner ist einklappbar (Tipp auf ▲), damit die Bühne den Platz bekommt.
  app.innerHTML = `
    <div class="host-rahmen">
      <header class="host-banner" id="host-banner">
        <div class="host-banner-zeile">
          <span class="host-titel">🐒 MONKEY MONEY · <strong>iPad ist der Server</strong></span>
          <span class="host-status" id="host-status">0 Geräte</span>
          <span class="host-meta">${fragenAnzahl} Fragen · ${relayArt}</span>
          <button class="host-klapp" id="host-klapp" title="Adress-Banner ein-/ausklappen">▲</button>
        </div>
        <div class="host-banner-inhalt" id="host-banner-inhalt">
          <div class="host-adresse-block">
            <div class="host-adresse" id="host-url">${origin}</div>
            <p class="host-hinweis">
              📶 iPhones ins <strong>gleiche WLAN</strong> (oder iPad-Hotspot) —
              dann Kamera auf den QR-Code oder die Adresse eintippen.
            </p>
            <p class="host-hinweis host-hinweis-speicher">
              💾 Fortschritt wird <strong>lokal auf dem iPad</strong> gespeichert
              (Spielstände, Profile &amp; AT überleben App-Neustarts).
            </p>
          </div>
          <div class="host-qr" id="host-qr" hidden>
            <img id="host-qr-bild" alt="Join-QR-Code" />
            <span class="host-qr-code" id="host-qr-text"></span>
          </div>
        </div>
      </header>
      <iframe id="host-screen" class="host-screen" src="/screen?standalone=1"
        allow="autoplay" title="Bühne"></iframe>
    </div>`;

  document.getElementById("host-klapp")!.addEventListener("click", () => {
    const banner = document.getElementById("host-banner")!;
    const zu = banner.classList.toggle("host-banner-zu");
    document.getElementById("host-klapp")!.textContent = zu ? "▼" : "▲";
  });

  const status = document.getElementById("host-status")!;
  let qrFuerCode: string | null = null;
  setInterval(() => {
    const n = server.relay.anzahlClients();
    status.textContent = `${n} ${n === 1 ? "Gerät" : "Geräte"}`;
    // Join-QR, sobald die Bühne ihren Raum eröffnet hat (Merker teilt der
    // Screen-iframe über sessionStorage) — der QR führt auf /j/CODE.
    const code = sessionStorage.getItem("mm:screen-room");
    if (code !== null && code !== qrFuerCode) {
      qrFuerCode = code;
      const qr = document.getElementById("host-qr")!;
      (document.getElementById("host-qr-bild") as HTMLImageElement).src =
        `/api/qr?code=${encodeURIComponent(code)}`;
      document.getElementById("host-qr-text")!.textContent = `Raum ${code}`;
      qr.hidden = false;
    }
  }, 1000);
}

void boot().catch((err) => zeigeStatus(`Start fehlgeschlagen: ${String(err)}`));
