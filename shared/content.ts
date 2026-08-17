// Fragen-/Content-Typen (Minimal-Ausschnitt des Pack-Formats aus TECH-SPEC §5.4).
// Der Content-Agent erweitert das Schema; Kern-Felder bleiben stabil.
import { z } from "zod";
import type { Schwierigkeit } from "./money";
import type { SongBasis } from "./songs";

/** Schätz-Daten (Plan-Typ `schaetz`, CONTENT-PLAN §2.3) — der Bananen-Tresor
 * liest Richtwert/Range/Toleranz DIREKT aus der Frage (kein eingebauter Pool). */
export const SchaetzDatenSchema = z.object({
  richtwert: z.number(),
  einheit: z.string().min(1),
  /** Volltreffer-Fenster in % vom Richtwert (Pack-Feld toleranz_prozent). */
  toleranzProzent: z.number().positive(),
  /** ABSOLUTE Toleranz in Einheiten (z. B. ±3 Jahre) — hat VORRANG vor
   * toleranzProzent (Jahreszahl-Fix: 1 % von 1969 wären ±20 Jahre). */
  toleranzAbsolut: z.number().positive().optional(),
  eingabeMin: z.number(),
  eingabeMax: z.number(),
  skala: z.enum(["linear", "log"]),
});

/** Sortier-Daten (Plan-Typ `sortier`) — die 4 Elemente stehen in `options`.
 * KONVENTION wie shared/minigames/affenleiter.meta.ts: korrektReihenfolge[i] =
 * Element-Index auf Position i; aufloesungWerte[e] = Anzeige-Wert von ELEMENT e
 * (der Loader normalisiert das positions-indizierte Pack-Feld aufloesung_werte). */
export const SortierDatenSchema = z.object({
  korrektReihenfolge: z.array(z.number().int().min(0).max(3)).length(4),
  aufloesungWerte: z.array(z.string()).length(4),
});

export const QuestionSchema = z.object({
  id: z.string(),
  /** choice4 = MC-4 (auch emoji/bild_pixel); wahr_falsch = 2 XXL-Optionen
   * („Wahr"/„Falsch" in options); schaetz = Slider (Daten in `schaetz`,
   * options leer); sortier = 4 Elemente ordnen (Elemente in options,
   * Lösung in `sortier`). Format-Zuordnung: server/engine/plan.ts. */
  kind: z.enum(["choice4", "wahr_falsch", "schaetz", "sortier"]),
  category: z.string(),
  difficulty: z.enum(["easy", "medium", "hard", "ultrahard"]),
  text: z.string().min(1),
  /** choice4: genau 4; wahr_falsch: genau 2; sortier: die 4 Elemente;
   * schaetz: leer (Slider statt Buttons). */
  options: z.array(z.string()),
  /** Korrekte Option (choice4: 0–3, wahr_falsch: 0–1; schaetz/sortier: 0). */
  answer: z.number().int().min(0),
  erklaerung: z.string().min(1), // PFLICHTFELD (Warum-Karte)
  /** ADDITIV: Medien-Anhang (bild_pixel-Fragen) — URL, die der Server unter
   * /media/… ausliefert. Formate OHNE Bild-Darstellung meiden solche Fragen
   * (Format-Content-Zuordnung in server/engine/plan.ts). */
  media: z.object({ bild: z.string().min(1) }).optional(),
  /** ADDITIV: die 3 Autoren-Tipps aus dem Pack (stufenweise Enthüllung —
   * GM-Tipp-Kanone, Auto-GM-Tipp, Trainingslager). wahr_falsch hat keine. */
  tips: z.array(z.string()).optional(),
  /** Nur kind "schaetz": Slider-Daten. */
  schaetz: SchaetzDatenSchema.optional(),
  /** Nur kind "sortier": Lösungs-Daten (Elemente stehen in options). */
  sortier: SortierDatenSchema.optional(),
});

export type Question = z.infer<typeof QuestionSchema> & { difficulty: Schwierigkeit };
export type SchaetzDaten = z.infer<typeof SchaetzDatenSchema>;
export type SortierDaten = z.infer<typeof SortierDatenSchema>;

/**
 * Laufzeit-Modifikatoren für eine Frage (Glücksrad/GM/Joker) — Plugins lesen sie
 * beim init() und unterstützen sie soweit sinnvoll (ADDITIV, alles optional).
 */
export interface FrageMods {
  /** Halbe Miete: Timer × Faktor (z. B. 0,5). */
  timerFaktor?: number;
  /** Insider-Tipp: dieser Spieler sieht die Frage `insiderVorsprungMs` früher. */
  insiderPlayerId?: string;
  insiderVorsprungMs?: number;
  /** Affentheater: Handy-Optionen werden pro Gerät gemischt (es zählt der TEXT). */
  geraeteMischung?: boolean;
  /** Maßanzug-Modus/Portfolio-Umschichtung: eigene Frage pro Spieler. */
  fragenProSpieler?: Record<string, Question>;
  /** Finale: der angesagte W_final-Wert (§3.5) — die Engine setzt ihn beim
   * Finale-Abschnitt, damit das Finale-Plugin ihn inszenieren kann. */
  wFinal?: number;
  /** Affenbank-Tuning (Quick: 1 Durchgang, 45-s-Kette) — die Engine setzt es
   * modusabhängig; ohne Feld spielt das Plugin die vollen 2×90 s (§2.8). */
  affenbank?: { durchgaenge: number; ketteMs: number };
}

/** Der Ausschnitt an Content, den ein Minigame beim init() bekommt. */
export interface ContentSlice {
  questions: Question[];
  /** Optionale Laufzeit-Modifikatoren (Rad/GM/Joker) — siehe FrageMods. */
  mods?: FrageMods;
  /** ADDITIV (Musik-Formate, contentKind "songs"): Song-Ausschnitt analog
   * questions — songs[0] = Ziel-Song, Rest = Distraktoren-Pool. Befüllt der
   * Song-Pack-Loader (content/musik/songs.json). Bewusst WEIT typisiert
   * (SongBasis) — jedes Musik-Format validiert seine Sicht selbst (z. B.
   * shared/songs.ts#parseSongs); fehlt das Feld oder ist nichts gültig,
   * fallen die Song-Plugins auf FIXTURE_SONGS zurück (nie crashen). */
  songs?: SongBasis[];
}
