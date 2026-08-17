// „Der Blitz-DJ" (song-snippet) — Eskalations-Buzzer-Raten über Song-Packs:
// beidseitige Meta + Action-Typen + die verbindliche Verfalls-Treppe.
//
// DESIGN-KERN: Die Runde spielt 0,1 s des Songs (buzz.ms100) — wer buzzert,
// darf ALLEIN raten (4 Optionen: Titel — Artist, artgleiche Distraktoren aus
// anderen Songs des Packs). Niemand gebuzzert oder falsch geraten ⇒ nächste
// Stufe: 0,2 s → 0,3 s → 0,5 s → 1,0 s → intro5s. Der Wert VERFÄLLT je Stufe.
//
// VERFALLS-TREPPE (Design-konsistent, dokumentiert wie PD_TREPPE §2.5):
// Start = 2 × Frage-Grundwert (§3.1) — Buzzer-Exklusivität: nur EIN Affe kann
// den Song holen, dafür trägt er das Falsch-Buzz-Risiko. Stufen-Faktoren
// 1 / 0,8 / 0,6 / 0,4 / 0,25 / 0,1 ⇒ bei SCHWER exakt die Vorgabe-Treppe
// 1000 → 800 → 600 → 400 → 250 → 100 MM. Falsch-Buzz = Sperre für den
// REST DES SONGS + 50 MM Strafe ins Jackpot-Glas (meta.strafenInsGlas).
import type { Schwierigkeit } from "../money";

export const SONG_SNIPPET_ID = "song-snippet";

export const SONG_SNIPPET_META = {
  id: SONG_SNIPPET_ID,
  name: "Der Blitz-DJ",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buzzer", "buttons"] as const,
  contentKind: "songs" as const,
  needsScreen: true, // das Audio läuft über den SCREEN („ALLE LAUSCHEN")
  // Buzzer-Exklusivität ist kein faires Alle-antworten-Format — keine Streak.
  streak: false,
  // Falsch-Buzz-Strafen wandern ins Jackpot-Glas (wie Stinkbanane).
  strafenInsGlas: true,
  // Auto-GM-+10s-Heuristik EXPLIZIT aus: Buzzes sind keine Antworten —
  // Schweigen ist hier Spielverlauf (Verfalls-Treppe), keine Denk-Not.
  // Gehört zum buzzCount-Fix (View exponiert bewusst kein answeredCount).
  autoVerlaengerung: false,
};

/**
 * Spieler-Aktionen:
 *   buzz  — über das buzz-Socket-Event kommt `finalAt` (Median-RTT-geclampt,
 *           Raum-Ebene) mit; über player.action (Client-Renderer) kommt
 *           stattdessen `pressedAtServerEst`, das Plugin clampt dann selbst
 *           via ctx.buzzer.medianRtt (shared/buzzer.clampBuzz).
 *   answer — die Rate-Antwort des Buzz-Siegers (0–3).
 */
export type SongSnippetAction =
  | { type: "buzz"; finalAt?: number; pressedAtServerEst?: number }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Eskalations-Stufen ----------
/** Snippet-Länge je Stufe (ms) — Stufe 5 spielt das volle intro5s. */
export const SS_SNIPPET_MS = [100, 200, 300, 500, 1000, 5000] as const;
export const SS_STUFEN = SS_SNIPPET_MS.length; // 6

/** „Plattenspieler dreht auf"-Beat vor Stufe 0 (alle werden still). */
export const SS_INTRO_MS = 2_000;
/** Buzz-Fenster NACH dem Snippet-Ende (buzzen geht ab Snippet-Start). */
export const SS_LAUER_MS = 4_000;
/** Rate-Fenster des Buzz-Siegers. */
export const SS_RATE_MS = 8_000;
/** Falsch-Buzz: kleine Strafe ins Jackpot-Glas (+ Sperre für den Song). */
export const SS_STRAFE_MM = 50;

/** Verfalls-Treppe je Schwierigkeit (Stufe 0–5) — Herleitung im Datei-Kopf. */
export const SS_TREPPE: Record<Schwierigkeit, readonly number[]> = {
  easy: [200, 160, 120, 80, 50, 20],
  medium: [500, 400, 300, 200, 130, 50],
  hard: [1_000, 800, 600, 400, 250, 100],
  ultrahard: [2_000, 1_600, 1_200, 800, 500, 200],
};

/** Wert der Stufe s (geklemmt auf 0…SS_STUFEN−1). */
export function ssStufenWert(schwierigkeit: Schwierigkeit, stufe: number): number {
  const treppe = SS_TREPPE[schwierigkeit];
  return treppe[Math.min(SS_STUFEN - 1, Math.max(0, stufe))];
}

/** Lausch-Fenster einer Stufe: Snippet-Länge + Lauer-Fenster. */
export function ssLauschFensterMs(stufe: number): number {
  return SS_SNIPPET_MS[Math.min(SS_STUFEN - 1, Math.max(0, stufe))] + SS_LAUER_MS;
}
