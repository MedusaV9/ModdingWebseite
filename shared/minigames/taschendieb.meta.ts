// Der Taschendieb-Affe (Point Stealer, GAME-DESIGN §2.7) — Meta + Action-Typen +
// verbindliche Klau-Regeln. Die schnellste RICHTIGE Antwort gewinnt das Klau-Recht
// (Server-Timestamps, Fotofinish <50 ms), geheime Opferwahl, dann Klau-Cutscene.
import type { Schwierigkeit } from "../money";

export const TASCHENDIEB_ID = "taschendieb";

export const TASCHENDIEB_META = {
  id: TASCHENDIEB_ID,
  name: "Der Taschendieb-Affe",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // Design §2.7: „Keine Streak/Speed auf den Klau" — sonst multipliziert die
  // Buchungs-Pipeline den Klau-Betrag (Nullsumme Dieb↔Opfer wäre verletzt).
  streak: false,
  // Maßanzug: zugewiesene Spieler beantworten IHRE Frage (Handy), Screen zeigt die Basis-Frage.
  perSpielerFragen: true,
};

/** Spieler-Aktionen: MC-4-Antwort für alle; „steal" nur für den Klau-Recht-Gewinner. */
export type TaschendiebAction =
  { type: "answer"; choice: 0 | 1 | 2 | 3 } | { type: "steal"; targetId: string };

// ---------- Timing (GAME-DESIGN §2.7: „15/20 s Frage + 8 s Opferwahl + 6 s Cutscene") ----------
export const TD_FRAGE_MS: Record<Schwierigkeit, number> = {
  easy: 15_000,
  medium: 15_000,
  hard: 20_000,
  ultrahard: 20_000,
};
export const TD_OPFERWAHL_MS = 8_000;
export const TD_CUTSCENE_MS = 6_000;
export const TD_NIEMAND_MS = 3_000; // Beat, wenn NIEMAND richtig lag (kein Klau)

// ---------- Klau-Ökonomie (GAME-DESIGN §2.7 + §3.2, verbindlich) ----------
/**
 * Klau-Beträge: MEDIUM 300 MM, HARD 500 MM (Design). EASY/ULTRAHARD sind im
 * Design für dieses Format nicht vorgesehen — Extrapolation entlang der
 * Grundwert-Skala (150/800), damit das Format mit jedem Content-Slice läuft.
 */
export const TD_KLAU_MM: Record<Schwierigkeit, number> = {
  easy: 150,
  medium: 300,
  hard: 500,
  ultrahard: 800,
};
/** Kappe: max. 25 % des Opfer-Kontostands. */
export const TD_KLAU_CAP_ANTEIL = 0.25;
/** Fotofinish-Fenster: Gleichstand <50 ms → Zweiter bekommt vollen Grundwert. */
export const TD_FOTOFINISH_MS = 50;
/** Alle anderen Richtigen: halber Grundwert aus der Bank („Mitmachen lohnt"). */
export const TD_MITMACH_ANTEIL = 0.5;
/** Anti-Mobbing: dieselbe Person kann nicht 3× in Folge Opfer sein (Server-hart). */
export const TD_MAX_OPFER_IN_FOLGE = 2;

/**
 * Klau-Betrag ausrechnen: Schwierigkeits-Betrag, gedeckelt auf 25 % des
 * Opfer-Kontos, auf 10er abgerundet (Integer-MM, keine krummen Klau-Beträge).
 * opferKonto === null ⇒ Kontostand unbekannt (nur in isolierten Tests ohne
 * ctx.match/Slice-Injektion) ⇒ Kappe kann nicht greifen, voller Betrag.
 */
export function tdKlauBetrag(schwierigkeit: Schwierigkeit, opferKonto: number | null): number {
  const voll = TD_KLAU_MM[schwierigkeit];
  if (opferKonto === null) return voll;
  const kappe = Math.floor((opferKonto * TD_KLAU_CAP_ANTEIL) / 10) * 10;
  return Math.max(0, Math.min(voll, kappe));
}
