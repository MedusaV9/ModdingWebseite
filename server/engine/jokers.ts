// Joker-Manager (GAME-DESIGN §5.1): Einsatzfenster-Prüfung, Preisformel mit
// Sozialrabatt, Info-Joker-Grenze (max. 1 von J1/J4 pro Frage), Format-Check
// (Plugin muss die Joker-Aktion in meta.jokerAktionen deklarieren).
// Die Zustands-Änderungen selbst macht der Engine-Reducer (engine.ts).
import { sozialrabattFaktor } from "../../shared/economy";
import { JOKER, jokerPreis, type JokerDef, type JokerId } from "../../shared/jokers";
import { FRAGE_WERTE } from "../../shared/money";
import type { JokerLeisteEintrag } from "../../shared/views";
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyPlugin = import("../minigames/_api/plugin").MinigamePlugin<any, any>;
import type { EngineState } from "./types";

/** Aktuelle Runden-Nr (für Schild-Laufzeiten/Cooldowns). */
export function aktuelleRunde(state: EngineState): number {
  if (!state.plan || state.abschnittIndex < 0) return 0;
  for (let i = Math.min(state.abschnittIndex, state.plan.abschnitte.length - 1); i >= 0; i--) {
    const a = state.plan.abschnitte[i];
    if (a.typ === "runde") return a.nr;
  }
  return 0;
}

/** Bananentresor-Schild aktiv? (J6 — auch für ctx.match.hatKlauSchutz). */
export function hatKlauSchutz(state: EngineState, playerId: string): boolean {
  const p = state.players[playerId];
  if (!p || p.schildBisRunde === null) return false;
  return p.schildBisRunde >= aktuelleRunde(state);
}

/** Grundwert der laufenden (oder nächsten wahrscheinlichen) Frage. */
export function aktuellerFragenwert(state: EngineState): number {
  const frage = state.aktuelleFragen[0];
  if (state.phase === "frage" && frage) return FRAGE_WERTE[frage.difficulty];
  const abschnitt = state.plan?.abschnitte[state.abschnittIndex];
  const s = abschnitt?.schwierigkeiten[0] ?? "medium";
  return FRAGE_WERTE[s];
}

/** Platz des Spielers (1-basiert) in den aktuellen Standings. */
export function platzVon(state: EngineState, playerId: string): number {
  const sortiert = [...state.order].sort(
    (a, b) => state.players[b].balance - state.players[a].balance,
  );
  return sortiert.indexOf(playerId) + 1;
}

/** Ist das Einsatzfenster des Jokers JETZT offen? */
export function fensterOffen(state: EngineState, def: JokerDef): boolean {
  if (def.fenster === "frage") return state.phase === "frage";
  // "vor-frage" / "zwischen-fragen": alles außerhalb einer laufenden Frage,
  // solange die Show läuft (Wirkung: nächste Frage bzw. Runde).
  return (
    state.phase === "kategorie-wahl" ||
    state.phase === "erklaerkarte" ||
    state.phase === "aufloesung" ||
    state.phase === "zwischenstand" ||
    state.phase === "rad"
  );
}

/** Aktueller Kaufpreis (inkl. Sozialrabatt §3.4) für diesen Spieler. */
export function preisFuer(
  state: EngineState,
  playerId: string,
  def: JokerDef,
  stufe?: number,
): number {
  const rabatt = sozialrabattFaktor(platzVon(state, playerId), state.order.length);
  return jokerPreis(
    def,
    aktuellerFragenwert(state),
    state.players[playerId]?.balance ?? 0,
    rabatt,
    stufe,
  );
}

/**
 * Nutzungs-Prüfung: Fenster, Finale-Sperre, Info-Joker-Grenze, max/Frage,
 * Format-Unterstützung, J6-Cooldown. Liefert Fehler-Code oder null.
 */
export function pruefeNutzung(
  state: EngineState,
  playerId: string,
  def: JokerDef,
  plugin: AnyPlugin | null,
): string | null {
  if (!state.settings.jokerAn) return "joker-aus";
  const abschnitt = state.plan?.abschnitte[state.abschnittIndex];
  if (abschnitt?.typ === "finale") return "im-finale-gesperrt"; // §5.1
  if (!fensterOffen(state, def)) return "fenster-zu";
  if (def.infoJoker && state.infoJokerFrage.includes(playerId)) return "info-joker-limit";
  const key = `${def.id}:${playerId}`;
  if (def.maxProFrage !== undefined && (state.jokerFrageZaehler[key] ?? 0) >= def.maxProFrage) {
    return "max-pro-frage";
  }
  if (def.pluginAktion) {
    if (state.phase !== "frage" || !plugin) return "fenster-zu";
    if (!plugin.meta.jokerAktionen?.includes(def.pluginAktion)) return "format-unterstuetzt-nicht";
  }
  if (def.id === "bananentresor") {
    const p = state.players[playerId];
    const ziel = schildZielRunde(state);
    if (p.schildBisRunde !== null && p.schildBisRunde >= ziel) return "schild-aktiv";
    // Cooldown: nicht 2 Runden in FOLGE (§5.1) — Ziel-Runde direkt nach der letzten.
    if (p.schildZuletztRunde !== null && ziel - p.schildZuletztRunde === 1)
      return "schild-cooldown";
  }
  return null;
}

/** Ziel-Runde eines JETZT gezündeten Bananentresors (im Zwischenstand: nächste). */
export function schildZielRunde(state: EngineState): number {
  const runde = aktuelleRunde(state);
  return state.phase === "zwischenstand" || state.phase === "rad" ? runde + 1 : Math.max(1, runde);
}

/** Joker-Leiste für die PlayerView (Besitz + Preis + Nutzbarkeit). */
export function jokerLeiste(
  state: EngineState,
  playerId: string,
  plugin: AnyPlugin | null,
): JokerLeisteEintrag[] {
  if (!state.settings.jokerAn) return [];
  const p = state.players[playerId];
  if (!p) return [];
  return Object.values(JOKER).map((def) => {
    const ladungen = p.jokers[def.id] ?? 0;
    const kaeufe = p.jokerKaeufe[def.id] ?? 0;
    const kaufbar = kaeufe < def.maxKaeufe;
    const preis = kaufbar ? preisFuer(state, playerId, def) : null;
    const fehler = pruefeNutzung(state, playerId, def, plugin);
    const bezahlbar = ladungen > 0 || (kaufbar && preis !== null && p.balance >= preis);
    return {
      id: def.id,
      name: def.name,
      emoji: def.emoji,
      beschreibung: def.beschreibung,
      ladungen,
      preis,
      nutzbar: fehler === null && bezahlbar,
    };
  });
}

export function jokerDef(jokerId: string): JokerDef | null {
  return (JOKER as Record<string, JokerDef>)[jokerId] ?? null;
}

export type { JokerId };
