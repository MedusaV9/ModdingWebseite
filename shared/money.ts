// MM-Ökonomie-Grundwerte + Speed-Bonus (GAME-DESIGN §3.1). Alles Integer-MM.
export type Schwierigkeit = "easy" | "medium" | "hard" | "ultrahard";

/** Frage-Grundwerte in MONKEY MONEY (GAME-DESIGN §3.1, verbindlich). */
export const FRAGE_WERTE: Record<Schwierigkeit, number> = {
  easy: 100,
  medium: 250,
  hard: 500,
  ultrahard: 1000,
};

/** Antwortzeit-Fenster je Schwierigkeit in Millisekunden. */
export const FRAGE_TIMER_MS: Record<Schwierigkeit, number> = {
  easy: 15_000,
  medium: 15_000,
  hard: 20_000,
  ultrahard: 25_000,
};

/**
 * Speed-Bonus (abgeknickte Gerade, kein Blind-Tipp-Exploit):
 *   bonus = wert × 0,5 × clamp((T − t) / (0,8 × T), 0, 1)
 * → volle +50 % nur bei Antwort in den ersten 20 % der Zeit (Lese-Zeit frei),
 * danach linear fallend auf 0. Ergebnis auf 10er gerundet.
 * TODO(Engine-Agent): Streak-Multiplikator (×1,5 ab 3, ×2,0 ab 5) obendrauf.
 */
export function speedBonus(wert: number, antwortNachMs: number, timerMs: number): number {
  const anteil = (timerMs - antwortNachMs) / (0.8 * timerMs);
  const faktor = Math.min(1, Math.max(0, anteil));
  return Math.round((wert * 0.5 * faktor) / 10) * 10;
}

/** Gesamtwert einer richtigen Antwort: Grundwert + Speed-Bonus. */
export function fragenGewinn(
  schwierigkeit: Schwierigkeit,
  antwortNachMs: number,
  timerMs: number,
): number {
  const wert = FRAGE_WERTE[schwierigkeit];
  return wert + speedBonus(wert, antwortNachMs, timerMs);
}

/** Anzeige-Format: 1234 → "1.234 MM". */
export function formatMM(betrag: number): string {
  return `${betrag.toLocaleString("de-DE")} MM`;
}
