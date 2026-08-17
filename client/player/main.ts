// Player-App (iPhone hochkant): Join per /j/CODE oder Code-Eingabe, Name +
// Affe+Farbe-Wahl, alle Engine-Phasen, Joker-Leiste, Sound (Opt-in) und
// Vibrations-Feedback (Caps-Schicht). Session-Token im localStorage ⇒ Reconnect
// stellt Rolle + Zustand wieder her; time.probe-Echo liefert den Median-RTT.
import { html, render } from "lit-html";
import { detectCaps } from "../../shared/caps";
import { buzzerSoundAus } from "../../shared/meta";
import type { ViewEvent } from "../../shared/protocol";
import type { PlayerView } from "../../shared/views";
import { fuellePuppen, ladeAllePuppen, onPuppenGeladen } from "../shared/fx/affe";
import { AFFEN, formatAvatar } from "../shared/fx/avatar";
import { createRegie } from "../shared/fx/regie";
import { createSoundSystem } from "../shared/fx/sound";
import { standardBuzzer } from "../shared/fx/sound-map";
import { soundKopf } from "../shared/fx/sound-ecke";
import type { FxApi } from "../shared/minigames/types";
import { getMinigameModule, onMinigameNachgeladen } from "../shared/minigames/registry";
import { codeAusUrl, ladeToken, loescheToken, speichereToken } from "../shared/session";
import { createConnection, type Connection } from "../shared/socket";
import { schmueckePuppen } from "../shared/meta-avatar";
import { pauseOverlay } from "../shared/ui";
import "../shared/base.css";
import "./mobil.css";
import {
  fuelleKonto,
  fuelleZaehler,
  installiereSliderFeedback,
  reduzierteBewegung,
  starteIdleChoreo,
} from "./handy-fx";
import { renderJoinForm } from "./join";
import { metaEndeBeobachte } from "./meta-ende";
import { aktivesProfilHello } from "./meta-join";
import { renderSpielPhase } from "./views";

const app = document.getElementById("app")!;
const caps = detectCaps();

// App-Zustand: erst Code/Formular, nach dem hello nur noch Server-Views rendern.
export interface PlayerAppState {
  roomCode: string | null;
  name: string;
  avatar: string; // "affe.farbe" (Wire-Format, Server reicht durch)
  verbunden: boolean;
  fehler: string | null;
  /** Roher Server-Fehlercode (z. B. "name-vergeben") — join.ts reagiert darauf. */
  fehlerCode: string | null;
  view: PlayerView | null;
  feedbackGesendet: boolean;
  /** Münz-Einwurf-Overlay sichtbar bis (Server-Zeit) — Antwort-Lock-in. */
  muenzBis: number;
}

const state: PlayerAppState = {
  roomCode: codeAusUrl(),
  name: "",
  avatar: formatAvatar({ affe: AFFEN[0].id, farbe: "gelb" }),
  verbunden: false,
  fehler: null,
  fehlerCode: null,
  view: null,
  feedbackGesendet: false,
  muenzBis: 0,
};

// ---------- FX: Sound (default stumm, Opt-in), Puppen, Vibration ----------
const sound = createSoundSystem("player");
sound.unlockBeiGeste();
const regie = createRegie(sound, "player");
ladeAllePuppen();
onPuppenGeladen(() => zeichne());

function vibriere(muster: number | number[]): void {
  if (caps.vibrate) navigator.vibrate(muster);
}

let conn: Connection | null = null;
let aktionNr = 0;

const fx: FxApi = {
  serverNow: () => conn?.serverNow() ?? 0,
  sound: (id) => sound.sound(id),
  // Spieler-Anzeige-Infos (Name + Affe) — z. B. fürs Taschendieb-Ziel-Grid.
  spieler: (id) => {
    const p = state.view?.players.find((x) => x.id === id);
    return p ? { name: p.name, avatar: String(p.avatar) } : null;
  },
};

/** Neue C→S-Nachrichten (joker.use, kategorie.vote, …) mit Auto-idemKey senden. */
function sendeAktion(event: string, payload: Record<string, unknown> = {}): void {
  if (!conn) return;
  vibriere(20);
  sound.sound("tap");
  const idemKey = `a_${conn.serverNow()}_${aktionNr++}`;
  void conn.socket
    .timeout(4000)
    .emitWithAck(event, { ...payload, idemKey })
    .then(() => conn?.requestSync())
    .catch(() => {});
}

let letztePhase = "";
// Phasen-Übergangs-Choreo: gesetzt von reagiereAufView, konsumiert vom nächsten
// zeichneMitUebergang (alte Phase raus, neue rein — 200–250 ms, nur transform/opacity).
let phasenWechsel = false;

/** Phase-Übergänge fürs Handy: Vibrations-Feedback bei der Auflösung. */
function reagiereAufView(neu: PlayerView): void {
  if (neu.phase !== letztePhase) {
    letztePhase = neu.phase;
    phasenWechsel = true;
    // Timer-Cleanup: das 1,3-s-Münz-Overlay darf NIE in die Auflösung laufen
    // (Playtest 3: bei schnellen Gruppen deckte es den Reveal kurz zu).
    if (neu.phase !== "frage") state.muenzBis = 0;
    if (neu.phase === "aufloesung") {
      const mg = neu.minigame?.view as {
        aufloesung?: { perPlayer?: { playerId: string; correct: boolean }[] } | null;
      } | null;
      const meins = mg?.aufloesung?.perPlayer?.find((p) => p.playerId === neu.you.id);
      if (meins) vibriere(meins.correct ? [40, 60, 40] : [160]);
    }
    if (neu.phase === "siegerehrung") vibriere([60, 80, 60, 80, 120]);
    // v2 Sudden-Death: dramatischer Doppel-Puls beim Einstieg in den Shake.
    if (neu.phase === "tiebreaker") vibriere([90, 70, 90]);
  }
}

export function verbinde(): void {
  if (conn) {
    // Zweiter Versuch nach abgelehntem hello (name-vergeben → Name geändert,
    // raum-voll → später nochmal): Socket steht noch, connect feuert nicht
    // erneut — hello mit frischem Payload nachschieben.
    conn.sendHello();
    return;
  }
  conn = createConnection({
    helloPayload: () => {
      const token = state.roomCode ? ladeToken(state.roomCode) : null;
      return {
        roomCode: state.roomCode ?? "????",
        role: "player",
        ...(token ? { sessionToken: token } : {}),
        ...(state.name ? { name: state.name, avatar: state.avatar } : {}),
        // META (§7.1): Join MIT Profil — Server bindet den Slot ans Profil.
        ...aktivesProfilHello(),
      };
    },
    onWelcome(w) {
      state.verbunden = true;
      state.fehler = null;
      state.fehlerCode = null;
      if (w.sessionToken && state.roomCode) speichereToken(state.roomCode, w.sessionToken);
      // LOBBY: „Zuletzt gespielt"-Banner der Landing (Rejoin per Token).
      if (state.roomCode) {
        try {
          localStorage.setItem("mm:zuletzt", state.roomCode);
        } catch {
          /* egal */
        }
      }
    },
    onSnapshot(v) {
      state.view = v as PlayerView;
      reagiereAufView(state.view);
      // META (§7.5): Match-Ende-Ausbeute (XP/Quests/Level-Up) am Handy zeigen.
      metaEndeBeobachte(state.view);
      regie.update(state.view, state.view.you.id);
      zeichneMitUebergang();
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
      // v2 Sudden-Death: Live-Tap-Stand direkt in den View patchen (kein Sync-Spam).
      if (event.type === "shake") {
        const t = state.view.tiebreaker?.teilnehmer.find((x) => x.playerId === event.playerId);
        if (!t) return false;
        t.taps = event.taps;
        zeichne();
        return true;
      }
      if (event.type === "answered" || event.type === "timer") {
        // Eigener Lock-in: Münz-Einwurf + Buzzer + Haptik (Plan §3.3).
        // META (§7.4): gekaufter Buzzer-Sound ersetzt den Slot-Standard-Buzzer.
        if (event.type === "answered" && event.playerId === state.view.you.id && conn) {
          state.muenzBis = conn.serverNow() + 1300;
          // Eigener Buzzer am Handy: gekaufter Shop-Buzzer gewinnt, sonst der
          // Standard-Buzzer des eigenen Slots (dieselbe 8er-Familie wie der Screen).
          const eigenerBuzzer = state.view.alltimeItems
            ? buzzerSoundAus(String(state.view.you.avatar))
            : null;
          const meineId = state.view.you.id;
          const slot = state.view.players.findIndex((p) => p.id === meineId);
          sound.sound(eigenerBuzzer ?? standardBuzzer(Math.max(0, slot)));
          vibriere(35);
          window.setTimeout(() => zeichne(), 1350);
        }
        conn?.requestSync();
        return true;
      }
      return false;
    },
    onFehler(f) {
      // Abgelaufener Token (Server-Neustart): Token weg, zurück zum Formular.
      // AUSNAHME name-vergeben: der lokale Token ist der Session-Restore-Weg
      // („bist du das?") und darf hier nicht zerstört werden.
      if (f !== "name-vergeben" && state.roomCode && ladeToken(state.roomCode)) {
        loescheToken(state.roomCode);
      }
      state.fehler = fehlerText(f);
      state.fehlerCode = f;
      state.verbunden = false;
      zeichne();
    },
    onClosed() {
      state.fehler = "Der Raum wurde geschlossen.";
      state.view = null;
      zeichne();
    },
  });
  // time.probe-Echo: SOFORT zurücksenden — Server misst daraus den Median-RTT
  // pro Spieler für die Buzzer-Fairness (TECH-SPEC §3.3).
  conn.socket.on("time.probe", (msg: unknown) => conn?.socket.emit("time.probe", msg));
}

function fehlerText(code: string): string {
  const texte: Record<string, string> = {
    "raum-nicht-gefunden": "Raum nicht gefunden — Tippfehler? Codes haben 4 Buchstaben.",
    "raum-voll": "Der Raum ist voll (max. 8 Affen).",
    "match-laeuft": "Das Match läuft schon — frag nach der nächsten Runde!",
    "name-fehlt": "Sag uns deinen Namen!",
    "name-vergeben": "Name schon vergeben — bist du das?",
  };
  return texte[code] ?? code;
}

// Lazy-Registry (Eval-7 Bundle-Split): sobald ein Minigame-Chunk nachgeladen
// ist, frisch rendern — der erste Render der Phase lief noch ohne Renderer.
onMinigameNachgeladen(() => zeichne());

/**
 * Phasen-Übergangs-Choreo: bei Phasenwechsel slidet/faded die alte Phase raus
 * und die neue rein (Frage kommt von unten, Auflösung zoomt — CSS in mobil.css
 * über html[data-mm-phase]). Kopfzeile bleibt via view-transition-name stehen.
 * Ohne View-Transition-Support (bzw. bei Reduced Motion) gibt es den
 * Einflug-Fallback auf .phase-buehne (nur die neue Phase animiert rein).
 */
function zeichneMitUebergang(): void {
  if (!phasenWechsel || !state.view) {
    zeichne();
    return;
  }
  phasenWechsel = false;
  document.documentElement.dataset.mmPhase = state.view.phase;
  if (reduzierteBewegung()) {
    zeichne();
    return;
  }
  if (typeof document.startViewTransition === "function") {
    document.startViewTransition(() => zeichne());
    return;
  }
  zeichne();
  const buehne = app.querySelector(".phase-buehne");
  if (buehne) {
    buehne.classList.remove("phase-einflug");
    // Reflow erzwingen, damit die Einflug-Animation neu startet.
    void (buehne as HTMLElement).offsetWidth;
    buehne.classList.add("phase-einflug");
  }
}

function zeichne(): void {
  // Noch nicht im Spiel: Code-Eingabe bzw. Name+Affe+Farbe-Formular.
  if (!state.view) {
    render(renderJoinForm(state, zeichne, verbinde), app);
    fuellePuppen(app);
    return;
  }
  const v = state.view;
  render(
    html`${renderSpielPhase(
      v,
      html`<div id="mg-host" style="flex:1;display:flex;flex-direction:column"></div>`,
      conn!.serverNow(),
      sendeAktion,
      state,
      zeichne,
      soundKopf(sound, () => zeichne()),
    )}
    ${pauseOverlay(v.paused, conn!.serverNow())}`,
    app,
  );
  const host = document.getElementById("mg-host");
  if (host && v.minigame && v.phase === "frage") {
    getMinigameModule(v.minigame.id)?.renderPlayer(
      v.minigame.view,
      host,
      (actionId, payload) => {
        const p = conn!.sendPlayerAction(v.minigame!.id, actionId, payload);
        // Sofortiges lokales Feedback: Snapshot holen, sobald der Server bestätigt.
        void p.then(() => conn?.requestSync());
        return p;
      },
      fx,
    );
  }
  fuellePuppen(app);
  // META (§7.4): Shop-Kosmetik als SVG-Overlays — respektiert alltimeItems.
  schmueckePuppen(app, v.alltimeItems);
  // Handy-FX nach jedem Render: Konto-Tick + Count-up-Zähler (idempotent).
  fuelleKonto(app);
  fuelleZaehler(app);
}

// Timer/Countdowns lokal weiterlaufen lassen (frage, rad, Wahl-Phasen, Pause;
// v2: tiebreaker-Countdown + highlights-Fortschrittsbalken).
const LIVE_PHASEN = new Set([
  "frage",
  "kategorie-wahl",
  "erklaerkarte",
  "rad",
  "tiebreaker",
  "highlights",
]);
setInterval(() => {
  if (state.view && (LIVE_PHASEN.has(state.view.phase) || state.view.paused)) zeichne();
}, 150);

// Handy-FX (einmalig): Idle-Einlagen des eigenen Affen in Warte-Screens +
// Slider-Haptik/Snap (delegiert — deckt auch Minigame-Slider ohne Code-Eingriff ab).
starteIdleChoreo(app, () => fuellePuppen(app));
installiereSliderFeedback(app, (ms) => vibriere(ms));

// Auto-Rejoin: Wer schon einen Token für diesen Raum hat, überspringt das Formular.
if (state.roomCode && ladeToken(state.roomCode)) verbinde();
zeichne();
