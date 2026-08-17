// Screen-App (iPad-Landscape/Beamer): Raum eröffnen, Lobby mit QR + Spieler-Liste,
// Studio-Bühne mit Puppen, Sound-Regie, Partikel-Kanone und Klau-Cutscene.
import { html, render } from "lit-html";
import { buzzerSoundAus, konfettiStilAus, type Boards } from "../../shared/meta";
import type { TunnelStatusMsg, ViewEvent } from "../../shared/protocol";
import type { ScreenView } from "../../shared/views";
import { fuellePuppen, ladeAllePuppen, onPuppenGeladen } from "../shared/fx/affe";
import { avatarFarbe } from "../shared/fx/avatar";
import { schmueckePuppen } from "../shared/meta-avatar";
import { createPartikel, type PartikelApi } from "../shared/fx/partikel";
import { AUFLOESUNG_AUFDECK_MS, createRegie, hatEigeneAufloesungsRegie } from "../shared/fx/regie";
import { createMusikRotation, seedAusRaumCode } from "../shared/fx/musik-rotation";
import { musikControl } from "../shared/fx/musik-control";
import { createSoundSystem } from "../shared/fx/sound";
import { SIEG_FANFARE_MS, standardBuzzer } from "../shared/fx/sound-map";
import { soundEcke } from "../shared/fx/sound-ecke";
import type { FxApi } from "../shared/minigames/types";
import { getMinigameModule, onMinigameNachgeladen } from "../shared/minigames/registry";
import { metaFetch } from "../shared/meta-fetch";
import { createConnection } from "../shared/socket";
import { pauseOverlay } from "../shared/ui";
import "../shared/base.css";
import { renderPhase } from "./views";

const app = document.getElementById("app")!;
let view: ScreenView | null = null;
let fehler: string | null = null;
let roomCode: string | null = sessionStorage.getItem("mm:screen-room");

// ---------- FX-Schicht: Sound-Regie + Partikel-Canvas + Puppen-Lader ----------
const sound = createSoundSystem("screen");
sound.unlockBeiGeste();
const regie = createRegie(sound, "screen");

// ---------- Musik-Rotation (Musik-Welle 3): Betten-Playlist statt Fix-Track ----------
// Bett-Loops des Users (import.mjs --bett) laden und die Rotation pro Match
// deterministisch aus dem Raum-Code seeden. Ohne Endpoint/leerer Katalog
// rotieren nur die Standard-MacLeod-Betten (Playlist der Länge 1 = Loop).
let rotationSeed: number | null = null;

function starteRotation(roomCode: string): void {
  const seed = seedAusRaumCode(roomCode);
  if (seed === rotationSeed) return;
  rotationSeed = seed;
  sound.setBettQuelle(createMusikRotation(seed, []));
  void fetch("/api/musik/betten")
    .then((r) => (r.ok ? (r.json() as Promise<{ betten: [] }>) : null))
    .then((d) => {
      if (d && rotationSeed === seed) sound.setBettQuelle(createMusikRotation(seed, d.betten));
    })
    .catch(() => {
      /* kein Endpoint (alter Server) — die Standard-Betten laufen weiter */
    });
}

// GM-Skip kommt als Zähler im View (musikSkips): beim ersten Snapshot nur die
// Basis merken (Reconnect darf nicht skippen), danach jedes Inkrement = 1 Skip.
let musikSkipsGesehen: number | null = null;

function reagiereAufMusik(neu: ScreenView): void {
  if (roomCode !== null) starteRotation(roomCode);
  sound.setMatchMusik(neu.musikAn ?? true, neu.musikVolume ?? 1);
  const skips = neu.musikSkips ?? 0;
  if (musikSkipsGesehen !== null && skips > musikSkipsGesehen) sound.musikSkip();
  musikSkipsGesehen = skips;
}

// Track-Ticker lebt außerhalb des Snapshot-Rhythmus (Track-Ende, Skip).
sound.onTrackWechsel(() => zeichne());
const canvas = document.createElement("canvas");
canvas.className = "fx-canvas";
document.body.appendChild(canvas);
const partikel: PartikelApi = createPartikel(canvas);
ladeAllePuppen();
onPuppenGeladen(() => zeichne());

const fx: FxApi = {
  serverNow: () => conn.serverNow(),
  sound: (id) => sound.sound(id),
  // Spieler-Anzeige-Infos für Minigame-Renderer (Sitzkreis/Ziel-Grid mit Namen).
  spieler: (id) => {
    const p = view?.players.find((x) => x.id === id);
    return p ? { name: p.name, avatar: String(p.avatar) } : null;
  },
  partikel: (art, opts = {}) => {
    if (art === "konfetti") partikel.konfetti(opts);
    else if (art === "money-regen") partikel.moneyRegen(opts);
    else if (opts.x !== undefined && opts.y !== undefined) {
      partikel.scheine({
        vonX: opts.x,
        vonY: opts.y,
        zuX: canvas.width / 2,
        zuY: canvas.height / 2,
        anzahl: opts.anzahl,
        farbe: opts.farbe,
      });
    }
  },
};

// LOBBY: „Öffentlich sichtbar" wählt der Ersteller auf der Landing (?public=1).
const erstelleOeffentlich = new URLSearchParams(window.location.search).get("public") === "1";

const conn = createConnection({
  // Screen ohne gemerkten Raum: erst room.create, dann hello (TECH-SPEC #1/#2).
  async preHello(socket) {
    if (roomCode) return;
    const antwort = (await socket.timeout(4000).emitWithAck("room.create", {
      role: "screen",
      origin: window.location.origin,
      ...(erstelleOeffentlich ? { oeffentlich: true } : {}),
    })) as {
      ok: boolean;
      code?: string;
      error?: string;
    };
    if (antwort.ok && antwort.code) {
      roomCode = antwort.code;
      sessionStorage.setItem("mm:screen-room", roomCode);
    } else {
      fehler =
        antwort.error === "max-rooms"
          ? "Alle Studios sind gerade belegt — bitte später nochmal versuchen!"
          : (antwort.error ?? "raum-erstellung-fehlgeschlagen");
      zeichne();
    }
  },
  helloPayload: () => ({
    roomCode: roomCode ?? "????",
    role: "screen",
    origin: window.location.origin,
  }),
  onWelcome() {
    fehler = null;
  },
  onSnapshot(v) {
    const neu = v as ScreenView;
    reagiereAufView(view, neu);
    reagiereAufMusik(neu);
    view = neu;
    regie.update(neu);
    zeichne();
  },
  onDelta(event: ViewEvent): boolean {
    if (!view) return false;
    if (event.type === "presence") {
      const p = view.players.find((x) => x.id === event.playerId);
      if (!p) return false;
      p.connected = event.connected;
      p.graceUntil = event.graceUntil;
      zeichne();
      return true;
    }
    // v2 Sudden-Death: Live-Tap-Stand direkt in den View patchen (kein Sync-Spam).
    if (event.type === "shake") {
      const t = view.tiebreaker?.teilnehmer.find((x) => x.playerId === event.playerId);
      if (!t) return false;
      t.taps = event.taps;
      zeichne();
      return true;
    }
    if (event.type === "answered" || event.type === "timer") {
      // Buzzer beim Lock-in GENAU DIESES Spielers (§7.4 + Plan §4.3 Lücke 3):
      // gekaufter Shop-Buzzer gewinnt, sonst bekommt jeder Spieler-Slot
      // automatisch einen ANDEREN Standard-Buzzer aus der 8er-Familie.
      if (event.type === "answered") {
        const slot = view.players.findIndex((x) => x.id === event.playerId);
        const p = slot >= 0 ? view.players[slot] : undefined;
        const gekauft = p && view.alltimeItems ? buzzerSoundAus(String(p.avatar)) : null;
        if (p) sound.sound(gekauft ?? standardBuzzer(slot));
      }
      conn.requestSync(); // Minigame-Detail ⇒ frischer Snapshot (Skeleton-einfach)
      return true;
    }
    return false;
  },
  onFehler(f) {
    if (f === "raum-nicht-gefunden") {
      if (roomCode !== null) {
        // Server neu gestartet oder TTL — alten Raum vergessen, neuen eröffnen.
        sessionStorage.removeItem("mm:screen-room");
        roomCode = null;
        window.location.reload();
        return;
      }
      // room.create ist schon gescheitert (z. B. max-rooms): dessen Meldung
      // stehen lassen — ein Reload liefe hier nur endlos im Kreis.
      if (fehler !== null) return;
    }
    fehler = f;
    zeichne();
  },
  onClosed() {
    sessionStorage.removeItem("mm:screen-room");
    fehler = "Raum wurde geschlossen (Timeout).";
    zeichne();
  },
});

// ---------- Show-Effekte auf View-Übergänge (Konfetti/Money-Regen/Klau/Jackpot) ----------
interface KlauBlick {
  klau?: { von: string | null; zu: string | null; betrag: number; abgeprallt: boolean } | null;
  aufloesung?: {
    klau?: { von: string | null; zu: string | null; betrag: number; abgeprallt: boolean } | null;
  } | null;
}

let klauGesehen = "";
let spielerZahl = 0;

// ---------- 2-Stufen-Auflösung (P1 „Auflösungs-Spoiler") ----------
// Beim Wechsel zu „aufloesung" bleibt die BÜHNE im Spannungs-Zustand (Antworten
// sichtbar aber neutral, Wand zappt, keine Korrekt-Markierung/Chips/Deltas) —
// exakt bei der Fanfare (+AUFLOESUNG_AUFDECK_MS, Konstante der Regie) flippt
// alles gleichzeitig. Handys zeigen ihr Ergebnis weiter sofort (persönlich ok).
let aufgedeckt = true;
let aufdeckTimer: number | null = null;
// Stand VOR der Auflösung: Podium-Kontostände/Geldstapel/Jackpot-Glas dürfen
// im Spannungs-Fenster nicht springen (das wäre derselbe Spoiler in Zahlen).
let standVorAufloesung: ScreenView | null = null;

function aufdeckTimerAbraeumen(): void {
  if (aufdeckTimer !== null) window.clearTimeout(aufdeckTimer);
  aufdeckTimer = null;
}

function deckeAuf(): void {
  aufdeckTimerAbraeumen();
  if (aufgedeckt) return;
  aufgedeckt = true;
  const vorher = standVorAufloesung;
  standVorAufloesung = null;
  if (view) {
    // Zurückgehaltene Show-Effekte JETZT zünden (gleichzeitig mit der Fanfare).
    if (vorher && view.jackpotGlas > vorher.jackpotGlas) sound.sound("jackpot-einzahlung");
    pruefeKlau(view);
  }
  zeichne();
}

/** Der View, den die Bühne WIRKLICH zeigt: im Spannungs-Fenster mit alten
 * Kontoständen und zentral maskiertem Minigame-View (aufloesung: null) —
 * Format-Renderer erhalten das additive „aufgedeckt"-Flag. */
function anzeigeView(v: ScreenView): ScreenView {
  if (v.phase !== "aufloesung") return v;
  if (aufgedeckt) {
    if (v.minigame === null) return v;
    return { ...v, minigame: { ...v.minigame, view: mitAufdeckFlag(v.minigame.view, true) } };
  }
  const basis = standVorAufloesung;
  return {
    ...v,
    players: basis?.players ?? v.players,
    standings: basis?.standings ?? v.standings,
    jackpotGlas: basis?.jackpotGlas ?? v.jackpotGlas,
    pott: basis?.pott ?? v.pott,
    minigame: v.minigame
      ? {
          ...v.minigame,
          view: { ...mitAufdeckFlag(v.minigame.view, false), aufloesung: null },
        }
      : null,
  };
}

function mitAufdeckFlag(mgView: unknown, flag: boolean): Record<string, unknown> {
  return { ...(mgView as Record<string, unknown>), aufgedeckt: flag };
}

// Lobby-Rotation (Befund-Fix): Bestenlisten bei Lobby-Eintritt frisch laden.
let lobbyBoards: Boards | null = null;

function ladeLobbyBoards(): void {
  void metaFetch("/api/meta/boards")
    .then((r) => {
      if (r.ok) {
        lobbyBoards = (r.json as { boards: Boards }).boards;
        zeichne();
      }
    })
    .catch(() => {
      /* keine Boards ⇒ Lobby bleibt beim QR-Slide */
    });
}

// v2 Sudden-Death: Herzschlag-Loop (da-dumm alle ~950 ms) solange Countdown/Shake läuft.
let herzTimer: number | null = null;

function herzschlag(an: boolean): void {
  if (an && herzTimer === null) {
    const beat = (): void => {
      sound.sound("herzschlag");
      window.setTimeout(() => sound.sound("herzschlag"), 190);
    };
    beat();
    herzTimer = window.setInterval(beat, 950);
  } else if (!an && herzTimer !== null) {
    window.clearInterval(herzTimer);
    herzTimer = null;
  }
}

function reagiereAufView(alt: ScreenView | null, neu: ScreenView): void {
  // Lobby betreten ⇒ Bestenlisten für die 12-s-Rotation nachladen.
  if (neu.phase === "lobby" && (!alt || alt.phase !== "lobby")) ladeLobbyBoards();
  // 2-Stufen-Auflösung: Spannungs-Fenster öffnen/schließen (P1-Spoiler-Fix).
  if (neu.phase === "aufloesung" && alt?.phase !== "aufloesung") {
    aufdeckTimerAbraeumen();
    if (hatEigeneAufloesungsRegie(neu)) {
      // Format dirigiert seine Auflösung selbst ⇒ sofort aufdecken.
      aufgedeckt = true;
      standVorAufloesung = null;
    } else {
      aufgedeckt = false;
      standVorAufloesung = alt;
      aufdeckTimer = window.setTimeout(deckeAuf, AUFLOESUNG_AUFDECK_MS);
    }
  } else if (neu.phase !== "aufloesung" && (aufdeckTimer !== null || !aufgedeckt)) {
    // GM-Skip/Phasen-Sprung: kein verspäteter Flip in die neue Phase.
    aufdeckTimerAbraeumen();
    aufgedeckt = true;
    standVorAufloesung = null;
  }
  // v2 Jubiläum: Gruppen-Meilenstein wird im Opening mit Konfetti gefeiert.
  if (alt && alt.phase !== "intro" && neu.phase === "intro" && neu.jubilaeum) {
    window.setTimeout(() => {
      partikel.konfetti({ anzahl: 60 });
      sound.sound("konfetti-pop");
    }, 700);
  }
  // v2 Sudden-Death: Herzschlag bei Countdown/Shake, Kokosnuss-Knack beim Ergebnis.
  herzschlag(neu.phase === "tiebreaker" && neu.tiebreaker?.subphase !== "ergebnis");
  if (
    neu.tiebreaker?.subphase === "ergebnis" &&
    alt?.tiebreaker?.subphase !== "ergebnis" &&
    neu.tiebreaker.siegerId !== null
  ) {
    sound.sound("kokosnuss-knack");
    partikel.konfetti({ anzahl: 40 });
  }
  // Join-Plopp in der Lobby
  if (alt && neu.phase === "lobby" && neu.players.length > spielerZahl && spielerZahl > 0) {
    sound.sound("join-plopp");
  }
  spielerZahl = neu.players.length;
  // Siegerehrung: Konfetti-Kanone + Money-Regen auf Platz 1 (sparsam, Plan-Regel).
  // META (§7.4): der Feier-Moment läuft im GEKAUFTEN Konfetti-Stil des Siegers.
  if (alt && alt.phase !== "siegerehrung" && neu.phase === "siegerehrung") {
    const sieger = neu.siegerehrung?.platzierungen.find((p) => p.platz === 1);
    const stil = sieger && neu.alltimeItems ? konfettiStilAus(String(sieger.avatar)) : "klassisch";
    window.setTimeout(() => {
      partikel.konfetti({ anzahl: 60, stil });
      partikel.moneyRegen({
        anzahl: 34,
        farbe: sieger ? avatarFarbe(sieger.avatar) : undefined,
        stil,
      });
      sound.sound("konfetti-pop");
    }, SIEG_FANFARE_MS); // Konfetti EXAKT auf der Fanfare (P2-Audio-Sync)
  }
  // Jackpot-Glas gefüttert — im Spannungs-Fenster zurückgehalten (deckeAuf zündet).
  const spannung = neu.phase === "aufloesung" && !aufgedeckt;
  if (alt && neu.jackpotGlas > alt.jackpotGlas && !spannung) sound.sound("jackpot-einzahlung");
  // Klau-Cutscene: im Spannungs-Fenster warten (der Klau IST die Auflösung).
  if (!spannung) pruefeKlau(neu);
}

/** Taschendieb-Klau: Affenhand + fliegende Scheine vom Opfer- zum Dieb-Podium. */
function pruefeKlau(neu: ScreenView): void {
  const mg = neu.minigame?.view as KlauBlick | undefined;
  const klau = mg?.klau ?? mg?.aufloesung?.klau ?? null;
  if (klau && klau.von && klau.zu && !klau.abgeprallt) {
    const key = `${neu.frageNr}:${klau.von}:${klau.zu}:${klau.betrag}`;
    if (klauGesehen !== key) {
      klauGesehen = key;
      window.setTimeout(() => klauAnimation(klau.von!, klau.zu!), 60);
    }
  }
}

/** Klau-Cutscene: Hand wischt durchs Bild, Scheine fliegen Podium → Podium. */
function klauAnimation(opferId: string, diebId: string): void {
  sound.duck(1500);
  sound.sound("klau");
  const hand = document.createElement("div");
  hand.className = "klau-hand";
  hand.textContent = "🐾💰";
  document.body.appendChild(hand);
  window.setTimeout(() => hand.remove(), 1600);
  const mitte = (id: string): { x: number; y: number } | null => {
    const el = document.querySelector(`[data-spieler="${id}"]`);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  };
  const von = mitte(opferId);
  const zu = mitte(diebId);
  if (von && zu) {
    const farbe = view
      ? avatarFarbe(view.players.find((p) => p.id === opferId)?.avatar ?? "gelb")
      : "#f5b301";
    partikel.scheine({ vonX: von.x, vonY: von.y, zuX: zu.x, zuY: zu.y, anzahl: 8, farbe });
  }
}

// Lazy-Registry (Eval-7 Bundle-Split): sobald ein Minigame-Chunk nachgeladen
// ist, frisch rendern — der erste Render der Phase lief noch ohne Renderer.
onMinigameNachgeladen(() => zeichne());

function zeichne(): void {
  if (fehler) {
    render(html`<div class="zentriert"><h1>😵 ${fehler}</h1></div>`, app);
    return;
  }
  if (!view) {
    render(html`<div class="zentriert"><h1>🐒 Raum wird eröffnet …</h1></div>`, app);
    return;
  }
  // 2-Stufen-Auflösung: die Bühne rendert im Spannungs-Fenster den maskierten
  // View (neutrale Wand, alte Kontostände) — Flip exakt bei der Fanfare.
  const anzeige = anzeigeView(view);
  render(
    html`${renderPhase(
      anzeige,
      html`<div
        id="mg-host"
        style="display:flex;flex-direction:column;justify-content:center"
      ></div>`,
      conn.serverNow(),
      fx,
      lobbyBoards,
      raumConfig,
      aufgedeckt,
      { status: tunnelStatus, cmd: tunnelCmd },
      screenNext,
    )}
    ${musikControl(sound, () => zeichne())} ${soundEcke(sound, () => zeichne())}
    ${pauseOverlay(view.paused, conn.serverNow())}`,
    app,
  );

  // Minigame-Renderer in den persistenten Host rendern (Registry-Vertrag).
  const host = document.getElementById("mg-host");
  if (host && anzeige.minigame) {
    const modul = getMinigameModule(anzeige.minigame.id);
    modul?.renderScreen(anzeige.minigame.view, host, fx);
  }
  // Puppen-Slots (Podien/Cutscenes) mit Inline-SVGs befüllen — idempotent.
  fuellePuppen(app);
  // META (§7.4): Shop-Kosmetik (Avatar-Extras) — respektiert alltimeItems.
  schmueckePuppen(app, view.alltimeItems);
}

// Welle 1 „Start/Skip ohne GameMaster": der Screen (Raum-Ersteller) drückt den
// Universal-Weiter selbst — Lobby: Match-Start, sonst Skip (wie GM flow.next).
function screenNext(): void {
  void conn.socket
    .timeout(4000)
    .emitWithAck("screen.next", {})
    .catch(() => {
      /* Netz-Hickser: nächster Versuch per erneutem Tap */
    });
}

// LOBBY: Sichtbarkeit/Name ändern (room.config) — der Server broadcastet dann
// frische Snapshots, die Lobby-Anzeige aktualisiert sich von selbst.
function raumConfig(patch: { name?: string; oeffentlich?: boolean }): void {
  void conn.socket
    .timeout(4000)
    .emitWithAck("room.config", patch)
    .catch(() => {
      /* Netz-Hickser: nächster Versuch per erneutem Tap */
    });
}

// ---------- INTERNET-LINK (W4): Cloudflare-Tunnel-Status + Start/Stop ----------
// Der Server broadcastet tunnel.status an Screen+GM; der „Link erstellen"-Knopf
// der Lobby feuert tunnel.start (Screen = Raum-Ersteller ist berechtigt).
let tunnelStatus: TunnelStatusMsg | null = null;
conn.socket.on("tunnel.status", (status: TunnelStatusMsg) => {
  tunnelStatus = status;
  zeichne();
});

function tunnelCmd(aktion: "start" | "stop"): void {
  void conn.socket
    .timeout(6000)
    .emitWithAck(`tunnel.${aktion}`, {})
    .then((antwort) => {
      const a = antwort as { ok: boolean; status?: TunnelStatusMsg };
      if (a.ok && a.status) {
        tunnelStatus = a.status;
        zeichne();
      }
    })
    .catch(() => {
      /* Netz-Hickser — der Status-Broadcast holt den Stand nach */
    });
}

// Cutscene-interne Zustandswechsel (Stinger-Video zu Ende, Tutorial aufgeklappt)
// melden sich per Event — die App zeichnet dann sofort neu.
window.addEventListener("mm:zeichne", () => zeichne());

// Timer-Banane/Rad-Dreh/Countdowns lokal weiterlaufen lassen (kein Tick-Spam).
// „lobby" ist dabei für die 12-s-Bestenlisten-Rotation (Befund-Fix);
// „tiebreaker"/„highlights" (v2) für Countdown + Karten-Fortschrittsbalken.
const LIVE_PHASEN = new Set([
  "frage",
  "kategorie-wahl",
  "erklaerkarte",
  "rad",
  "lobby",
  "tiebreaker",
  "highlights",
]);
setInterval(() => {
  if (view && (LIVE_PHASEN.has(view.phase) || view.paused)) zeichne();
}, 120);

zeichne();
