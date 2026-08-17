// GM-App (Regiepult): Raum-Übernahme via Code + PIN, Live-Zustand + ALLE 17
// GM-Werkzeuge (GAME-DESIGN §4.2) über den EINEN Kommando-Kanal + Aktions-Log.
import { render } from "lit-html";
import type { GmLogEntry, TunnelStatusMsg, ViewEvent } from "../../shared/protocol";
import type { GmView } from "../../shared/views";
import { createConnection, type Connection } from "../shared/socket";
import "../shared/base.css";
import "./cockpit.css";
import { renderCockpit, type GmAppState } from "./views";

const app = document.getElementById("app")!;

const gespeichert = ((): { code: string; pin: string } | null => {
  try {
    return JSON.parse(localStorage.getItem("mm:gm") ?? "null");
  } catch {
    return null;
  }
})();

const state: GmAppState = {
  code: gespeichert?.code ?? "",
  pin: gespeichert?.pin ?? "",
  verbunden: false,
  fehler: null,
  view: null,
  log: [],
  adjust: { playerId: "", betrag: 100, grund: "" },
  felder: {},
  beobachter: false,
  tunnel: null,
};

let conn: Connection | null = null;

function verbinde(): void {
  if (conn) return;
  try {
    localStorage.setItem("mm:gm", JSON.stringify({ code: state.code, pin: state.pin }));
  } catch {
    /* egal */
  }
  conn = createConnection({
    helloPayload: () => ({ roomCode: state.code, role: "gm", gmPin: state.pin }),
    onWelcome(w) {
      state.verbunden = true;
      state.fehler = null;
      // EIN aktives Cockpit: zweite Verbindung startet als Beobachter.
      state.beobachter = w.gmBeobachter === true;
    },
    onSnapshot(v) {
      state.view = v as GmView;
      // Server-Log (Snapshot) mit Live-Einträgen zusammenführen.
      state.log = state.view.log as GmLogEntry[];
      zeichne();
    },
    onDelta(event: ViewEvent): boolean {
      if (!state.view) return false;
      if (event.type === "presence") {
        const p = state.view.players.find((x) => x.id === event.playerId);
        if (!p) return false;
        p.connected = event.connected;
        zeichne();
        return true;
      }
      conn?.requestSync();
      return true;
    },
    onGmLog(entry) {
      state.log = [...state.log, entry as GmLogEntry].slice(-20);
      zeichne();
    },
    onGmStatus(beobachter) {
      state.beobachter = beobachter;
      if (!beobachter) state.fehler = null;
      zeichne();
    },
    onFehler(f) {
      state.fehler = f === "gm-pin-falsch" ? "PIN falsch (steht auf dem Bildschirm)." : f;
      state.verbunden = false;
      conn?.socket.disconnect();
      conn = null;
      zeichne();
    },
    onClosed() {
      state.fehler = "Raum wurde geschlossen.";
      state.view = null;
      zeichne();
    },
  });
  // INTERNET-LINK (W4): Tunnel-Status kommt als Broadcast an Screen+GM —
  // die Show-Zone zeigt die Tunnel-Karte (Start/Stop/Status/URL).
  conn.socket.on("tunnel.status", (status: TunnelStatusMsg) => {
    state.tunnel = status;
    zeichne();
  });
}

/** INTERNET-LINK: Start/Stop senden (nur Screen/aktiver GM — Server prüft). */
function tunnelCmd(aktion: "start" | "stop"): void {
  if (!conn) return;
  void conn.socket
    .timeout(6000)
    .emitWithAck(`tunnel.${aktion}`, {})
    .then((antwort) => {
      const a = antwort as { ok: boolean; status?: TunnelStatusMsg; error?: string };
      if (a.ok && a.status) {
        state.tunnel = a.status;
        state.fehler = null;
      } else if (!a.ok) {
        state.fehler =
          a.error === "keine-berechtigung"
            ? "Beobachter-Modus: erst das Cockpit übernehmen (PIN)."
            : `Tunnel-Kommando abgelehnt: ${a.error}`;
      }
      zeichne();
    })
    .catch(() => {
      /* Netz-Hickser — der Status-Broadcast holt den Stand nach */
    });
}

/** Liefert Erfolg zurück, damit die Views Mini-Toasts AM Auslöser zeigen können. */
async function sende(cmd: string, args: Record<string, unknown>): Promise<boolean> {
  if (!conn) return false;
  const antwort = await conn.sendGmCmd(cmd, args);
  if (!antwort.ok) {
    state.fehler =
      antwort.error === "beobachter-modus"
        ? "Beobachter-Modus: erst das Cockpit übernehmen (PIN)."
        : antwort.error === "podest-fixiert"
          ? "Podest fixiert: ab der Siegerehrung sind Punkte-Änderungen gesperrt."
          : `Kommando abgelehnt: ${antwort.error}`;
  } else {
    state.fehler = null;
  }
  zeichne();
  return antwort.ok;
}

function uebernehme(pin: string): void {
  if (!conn) return;
  void conn.sendGmTakeover(pin).then((antwort) => {
    if (antwort.ok) {
      state.beobachter = false;
      state.fehler = null;
    } else {
      state.fehler =
        antwort.error === "gm-pin-falsch"
          ? "PIN falsch — Übernahme abgelehnt."
          : (antwort.error ?? null);
    }
    zeichne();
  });
}

function zeichne(): void {
  render(renderCockpit(state, zeichne, verbinde, sende, uebernehme, tunnelCmd), app);
}

zeichne();
