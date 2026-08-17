// Show-Regie: beobachtet die View-Folge und steuert Musik-Ebenen + Event-SFX
// (ART-PLAN §4.2-Zuordnung). Screen fährt die volle Regie; Handys nutzen dieselbe
// Logik, hören aber nur, was ihr (default stummes) Sound-Profil durchlässt.
import type { ViewBase } from "../../../shared/views";
import { getMinigameModule } from "../minigames/registry";
import {
  AUFLOESUNG_SPANNUNG_MS,
  AUFLOESUNG_STILLE_MS,
  MINIGAME_MUSIK,
  MUSIK_STUMME_FORMATE,
  SIEG_STILLE_MS,
  SIEG_TROMMELWIRBEL_MS,
} from "./sound-map";
import type { SoundSystem } from "./sound";

/** Fanfare-Moment des Auflösungs-Dreiklangs: Riser (1,75 s) + ECHTE Stille
 *  (0,65 s) — exakt hier löst der Screen auch VISUELL auf (P1-Befund
 *  „Auflösungs-Spoiler": die Wand zeigte alles sofort, das Audio erst +2,4 s). */
export const AUFLOESUNG_AUFDECK_MS = AUFLOESUNG_SPANNUNG_MS + AUFLOESUNG_STILLE_MS;

interface AufloesungBlick {
  aufloesung?: { perPlayer?: { playerId: string; correct: boolean; delta: number }[] } | null;
}

/** Formate mit EIGENER Auflösungs-Regie (Blitz-DJ/Rückwärts-Banane spielen
 *  richtig/zeit-um + Song-Intro selbst, sofort bei finished) — der zentrale
 *  Dreiklang legte Wirbel + ZWEITE Fanfare darüber (P2-Befund). Renderer
 *  deklarieren das additiv am Client-Modul (eigeneAufloesungsRegie: true). */
export function hatEigeneAufloesungsRegie(view: ViewBase): boolean {
  const id = view.minigame?.id ?? view.abschnitt?.minigameId ?? "";
  return id !== "" && getMinigameModule(id)?.eigeneAufloesungsRegie === true;
}

/** Musik-Ebene je Phase (Plan §4.2): Lobby-Loop, Runden-Grundbett, Rad, News … */
export function musikEbene(view: ViewBase): string | null {
  switch (view.phase) {
    case "lobby":
    case "intro":
      return "lobby";
    case "kategorie-wahl":
    case "erklaerkarte":
      return "erklaer";
    case "frage":
    case "aufloesung": {
      const mg = view.abschnitt?.minigameId ?? view.minigame?.id ?? "";
      // Musik-Formate: Bett für die GANZE Runde aus (eigene Regie-Ebene,
      // Eval 3) — ein Duck allein maskierte die Snippets mit SNR≈0 dB.
      if (MUSIK_STUMME_FORMATE.has(mg)) return null;
      return MINIGAME_MUSIK[mg] ?? "runde";
    }
    case "zwischenstand":
      return "news";
    case "rad":
      return "rad";
    // v2: Highlights-Recap läuft auf dem News-Bett; Sudden-Death bleibt
    // musiklos — nur der Herzschlag-Loop (Screen-Regie) trägt die Spannung.
    case "highlights":
      return "news";
    default:
      return null; // Siegerehrung/Ende/Tiebreaker: Stille bzw. Fanfare + Applaus
  }
}

const MOMENT_SFX: Record<string, string> = {
  joker: "joker-zuenden",
  boost: "money-mittel",
  rad: "stinger",
  strafe: "falsch",
  underdog: "applaus-kurz",
  sound: "stinger",
};

export interface Regie {
  /** Nach jedem Snapshot aufrufen — spielt Übergangs-SFX und wechselt die Musik. */
  update(view: ViewBase, meineId?: string): void;
}

export function createRegie(sound: SoundSystem, rolle: "screen" | "player" | "gm"): Regie {
  let letztePhase = "";
  let letzteAufloesung = "";
  const momenteGesehen = new Set<string>();
  let erster = true;
  // Verzögerte Fanfare des Auflösungs-Dreiklangs — bei Phasen-Skip abräumen.
  let fanfareTimer: ReturnType<typeof setTimeout> | null = null;

  function fanfareAbraeumen(): void {
    if (fanfareTimer !== null) clearTimeout(fanfareTimer);
    fanfareTimer = null;
  }

  function phasenStinger(view: ViewBase, meineId?: string): void {
    switch (view.phase) {
      case "frage":
        sound.duck(900);
        sound.sound("frage-ein");
        break;
      case "aufloesung":
        // Formate mit eigener Auflösungs-Regie (Blitz-DJ/Rückwärts-Banane):
        // KEIN zweiter Dreiklang über deren richtig/zeit-um + Song-Intro.
        if (hatEigeneAufloesungsRegie(view)) break;
        // Auflösungs-Dreiklang (Plan §3.2/§4): Spannung (Trommelwirbel/Riser
        // im Round-Robin) über der zappenden Wand, Musik-Bett KOMPLETT weg
        // (faktor 0 = ECHTE Stille), die Fanfare kommt verzögert aus
        // aufloesungsKlang (Spannung + Stille später).
        sound.duck(AUFLOESUNG_AUFDECK_MS + 500, 0);
        sound.sound("reveal-zap");
        sound.sound("aufloesungs-spannung");
        break;
      case "erklaerkarte":
        sound.sound("karte-slide");
        break;
      case "kategorie-wahl":
        sound.sound("karten-mischen");
        break;
      case "zwischenstand":
        sound.duck(1500);
        if (rolle === "screen") sound.sound("applaus-kurz");
        break;
      case "rad":
        sound.duck(1200);
        sound.sound("stinger");
        break;
      case "siegerehrung":
        // Großer Dreiklang der Siegerehrung (Plan §5.1 C): langer
        // Trommelwirbel → Spannungspause → Fanfare + Jubel-Sturm.
        sound.duck(SIEG_TROMMELWIRBEL_MS + SIEG_STILLE_MS + 500, 0);
        sound.sound("trommelwirbel-lang");
        fanfareTimer = setTimeout(() => {
          fanfareTimer = null;
          sound.sound("sieg-fanfare");
          if (rolle === "screen") sound.sound("applaus-jubel");
        }, SIEG_TROMMELWIRBEL_MS + SIEG_STILLE_MS);
        break;
      case "intro":
        sound.sound("stinger");
        break;
      // v2 Sudden-Death: dramatischer Einschlag, dann übernimmt der Herzschlag.
      case "tiebreaker":
        sound.duck(1500);
        sound.sound("stinger");
        break;
      // v2 Replay-Highlights: Karten-Slide als Auftakt der Sequenz.
      case "highlights":
        sound.sound("karte-slide");
        break;
      default:
        break;
    }
    void meineId;
  }

  /** Auflösung: richtig/falsch + Applaus-Stufe nach Punkte-Delta (nie zufällig).
   *  Die Fanfare kommt VERZÖGERT — erst Spannung, dann ECHTE Stille (Dreiklang). */
  function aufloesungsKlang(view: ViewBase, meineId?: string): void {
    // Eigene Auflösungs-Regie des Formats ⇒ auch keine verzögerte Regie-Fanfare.
    if (hatEigeneAufloesungsRegie(view)) return;
    const mg = view.minigame?.view as AufloesungBlick | undefined;
    const perPlayer = mg?.aufloesung?.perPlayer;
    if (!perPlayer) return;
    const key = `${view.frageNr}:${view.minigame?.id ?? ""}`;
    if (letzteAufloesung === key) return;
    letzteAufloesung = key;
    const fanfare = (): void => {
      fanfareTimer = null;
      if (rolle === "player" && meineId) {
        const meins = perPlayer.find((p) => p.playerId === meineId);
        if (meins) sound.sound(meins.correct ? "richtig" : "falsch");
        return;
      }
      const richtige = perPlayer.filter((p) => p.correct).length;
      const maxDelta = Math.max(0, ...perPlayer.map((p) => p.delta));
      sound.sound(richtige > 0 ? "richtig" : "falsch");
      if (richtige > 0) {
        sound.sound(
          maxDelta >= 400 ? "applaus-gross" : richtige > 1 ? "applaus-mittel" : "applaus-kurz",
        );
      }
    };
    fanfareAbraeumen();
    fanfareTimer = setTimeout(fanfare, AUFLOESUNG_AUFDECK_MS);
  }

  return {
    update(view, meineId) {
      // Momente (Joker/Boost/Strafe/Rad) → SFX nach Art; beim ersten Snapshot
      // nur registrieren (sonst knallt die History beim Reconnect).
      for (const m of view.momente) {
        if (momenteGesehen.has(m.id)) continue;
        momenteGesehen.add(m.id);
        if (erster) continue;
        const sfx = MOMENT_SFX[m.art];
        if (sfx) {
          sound.duck(900);
          sound.sound(sfx);
        }
      }
      if (view.phase !== letztePhase) {
        letztePhase = view.phase;
        // GM-Skip/Phasen-Sprung: keine verspätete Fanfare in die neue Phase.
        fanfareAbraeumen();
        if (!erster) phasenStinger(view, meineId);
      }
      if (view.phase === "aufloesung") aufloesungsKlang(view, meineId);
      sound.musik(musikEbene(view));
      erster = false;
    },
  };
}
