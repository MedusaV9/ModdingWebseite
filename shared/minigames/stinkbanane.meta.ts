// Die Stinkbanane (Pass the Bomb, GAME-DESIGN §2.6) — Meta + Action-Typen +
// verbindliche Ökonomie-Konstanten. Der Explosions-Zeitpunkt ist ein VERDECKTER
// Zufalls-Timer (ctx.rng, 45–75 s) und verlässt den Server nie (nur GM-Spickzettel).
export const STINKBANANE_ID = "stinkbanane";

export const STINKBANANE_META = {
  id: STINKBANANE_ID,
  name: "Die Stinkbanane",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  needsScreen: true,
  // Design §2.6: „Keine Streak, kein Speed-Bonus"; Explosion −500 → ins Glas.
  streak: false,
  strafenInsGlas: true,
  // EIN init() pro Runde: das Plugin braucht viele Fragen (Weitergabe-Kette).
  roundBased: true,
  // Maßanzug: die zugewiesene Frage kommt, sobald der Spieler die Banane hält.
  perSpielerFragen: true,
};

/**
 * Spieler-Aktionen: Der Halter beantwortet die MC-4-Frage; alle anderen haben
 * den kosmetischen „ANFEUERN"-Trommel-Button (triggert Sounds/Konfetti).
 */
export type StinkbananeAction = { type: "answer"; choice: 0 | 1 | 2 | 3 } | { type: "anfeuern" };

// ---------- Timing & Ökonomie (GAME-DESIGN §2.6, verbindlich) ----------
export const SB_FRAGE_MS = 8_000; // 8 s pro Weitergabe-Frage
export const SB_ZUENDSCHNUR_MIN_MS = 45_000; // verdeckter Zufalls-Timer: 45–75 s
export const SB_ZUENDSCHNUR_MAX_MS = 75_000;
export const SB_WEITERGABE_MM = 150; // jede erfolgreiche Weitergabe: +150 MM
export const SB_EXPLOSION_MM = 500; // Explosion: −500 MM → ins Jackpot-Glas
export const SB_DURCHGAENGE = 2; // 2 Durchgänge pro Runde
export const SB_SPLATTER_MS = 4_000; // Matsch-Splatter-Beat zwischen den Durchgängen

/** Eintrag der öffentlichen Wander-Historie (Screen-Inszenierung + Event-Log). */
export interface SbHistorieEintrag {
  typ: "weitergabe" | "falsch" | "timeout" | "explosion" | "durchgang-start";
  von: string;
  zu?: string;
  atMs: number; // ms seit Spielstart (relativ — kein Leak des Zünd-Zeitpunkts)
  durchgang: number;
}
