// Pixel-Dschungel (Bild-Enthüllung mit Geld-Verfall, GAME-DESIGN §2.5) —
// beidseitig gebrauchte Meta + Action-Typen + die verbindliche Jackpot-Treppe.
// Die Pixel-Stufen werden CLIENTSEITIG aus EINEM Bild gerendert
// (Canvas-Downscale-Upscale) — der Server kennt nur Zeiten und Werte.
import type { Question } from "../content";
import type { Schwierigkeit } from "../money";

export const PIXEL_DSCHUNGEL_ID = "pixel-dschungel";

export const PIXEL_DSCHUNGEL_META = {
  id: PIXEL_DSCHUNGEL_ID,
  name: "Pixel-Dschungel",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "media" as const,
  needsScreen: true,
  // Design §2.5: „Streak normal" — contentKind ist media, darum explizit.
  streak: true,
  // KEIN perSpielerFragen: Das Bild enthüllt sich für ALLE auf dem Screen —
  // eine Frage pro Spieler ergibt hier keinen Sinn (GM-Cockpit sagt das ehrlich).
};

/** Spieler-Aktionen: MC-4, jederzeit drückbar — die ERSTE Antwort zählt. */
export type PixelDschungelAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing (GAME-DESIGN §2.5: „8 Stufen à 3 s … 24 s Enthüllung + 4 s voll scharf") ----------
export const PD_STUFEN = 8;
export const PD_STUFE_MS = 3_000;
export const PD_ENTHUELLUNG_MS = PD_STUFEN * PD_STUFE_MS; // 24 s
export const PD_VOLLBILD_MS = 4_000;
export const PD_GESAMT_MS = PD_ENTHUELLUNG_MS + PD_VOLLBILD_MS; // 28 s

/**
 * Jackpot-Treppen (GAME-DESIGN §2.5, verbindlich):
 * MEDIUM 400→50 (−50/Stufe), HARD 800→100 (−100/Stufe), ULTRAHARD 1.600→200 (−200/Stufe).
 * EASY ist im Design für dieses Format nicht vorgesehen — Extrapolation ½ MEDIUM
 * (200→25), damit das Format mit jedem Content-Slice funktioniert.
 */
export const PD_TREPPE: Record<Schwierigkeit, { start: number; schritt: number }> = {
  easy: { start: 200, schritt: 25 },
  medium: { start: 400, schritt: 50 },
  hard: { start: 800, schritt: 100 },
  ultrahard: { start: 1_600, schritt: 200 },
};

/** Stufe (0–7) zum Zeitpunkt msSeitStart — im Vollbild-Fenster bleibt Stufe 7. */
export function pdStufeZuZeit(msSeitStart: number): number {
  return Math.min(PD_STUFEN - 1, Math.max(0, Math.floor(msSeitStart / PD_STUFE_MS)));
}

/** Jackpot-Wert auf Stufe s: start − schritt·s (Stufe 0 = Maximum, Stufe 7 = Minimum). */
export function pdJackpotWert(schwierigkeit: Schwierigkeit, stufe: number): number {
  const { start, schritt } = PD_TREPPE[schwierigkeit];
  return start - schritt * Math.min(PD_STUFEN - 1, Math.max(0, stufe));
}

/** Client-Auflösung pro Stufe: Ziel-Spaltenzahl fürs Canvas-Downscale (Stufe 0–7). */
export const PD_PIXEL_SPALTEN = [8, 12, 18, 26, 38, 56, 84, 128] as const;

// ---------- Bild-Zuordnung ----------
/** Die 3 Platzhalter-Motive (assets/img/fragen/platzhalter/<key>.svg). */
export const PD_PLATZHALTER_MOTIVE = ["banane", "affenkopf", "palme"] as const;
export type PdMotivKey = (typeof PD_PLATZHALTER_MOTIVE)[number];

export interface PdBild {
  /** "platzhalter" = Client löst den Key gegen assets/img/fragen/platzhalter/ auf. */
  typ: "platzhalter" | "url";
  wert: string;
}

/**
 * Bild für eine Frage bestimmen: echtes Medien-Feld (kommt vom Content-Agent /
 * Orchestrator) hat Vorrang, sonst deterministisch eines der Platzhalter-Motive.
 */
export function pdBildFuerFrage(question: Question): PdBild {
  const media = (question as { media?: { bild?: string } }).media;
  if (media?.bild) return { typ: "url", wert: media.bild };
  let hash = 0;
  for (const zeichen of question.id) hash = (hash * 31 + zeichen.charCodeAt(0)) >>> 0;
  return { typ: "platzhalter", wert: PD_PLATZHALTER_MOTIVE[hash % PD_PLATZHALTER_MOTIVE.length] };
}
