// Zentrale Pacing-Config (MASTERPLAN Welle 1) — DIE eine Stellschraube fürs
// Show-Tempo. Eval-Welle 1: „ALLES viel zu schnell" — darum leben alle
// server-getakteten Phasen-Dauern jetzt HIER (server/engine/types.ts und
// shared/money.ts re-exportieren, Callsites bleiben unberührt).
//
// Kalibrierung „ruhiger Vibe": Lese-Phasen (Auflösung, Zwischenstand,
// Erklärkarte) deutlich rauf — dort wurde in den Evals am meisten verpasst.
// Aktions-Phasen moderat rauf, damit die Show nicht zäh wird.
import type { Schwierigkeit } from "./money";

// ---------- Engine-Phasen (alt → neu) ----------
export const INTRO_MS = 8_000; // 6 s → 8 s: Ankommen statt Überrumpeln
export const KATEGORIE_WAHL_MS = 18_000; // 12 s → 18 s: Voting braucht Gruppen-Diskussion
export const ERKLAERKARTE_MS = 16_000; // 12 s → 16 s: Regeln wirklich lesen können
export const ERKLAERKARTE_KURZ_MS = 9_000; // 7 s → 9 s (kurzeShow-Variante)
export const AUFLOESUNG_MS = 12_000; // 6 s → 12 s: Erklärung lesen (Eval-Kernpunkt!)
export const ZWISCHENSTAND_MS = 9_000; // 5 s → 9 s: Stand sacken lassen
export const SIEGEREHRUNG_MS = 15_000; // 12 s → 15 s
export const MOOD_POLL_MS = 4_000; // unverändert (reiner Overlay-Beat)
export const VOTING_MS = 20_000; // 15 s → 20 s
export const VOTING_ERGEBNIS_MS = 8_000; // 7 s → 8 s
export const TIEBREAKER_COUNTDOWN_MS = 3_000; // unverändert (Countdown ist Spannung)
export const TIEBREAKER_SHAKE_MS = 10_000; // unverändert
export const TIEBREAKER_ERGEBNIS_MS = 6_000; // 5 s → 6 s
export const HIGHLIGHT_KARTE_MS = 6_000; // 4,5 s → 6 s: Replay-Karten lesbar

// ---------- Antwortzeit-Fenster je Schwierigkeit (alt → neu) ----------
// Mehr Zeit pro Frage (Eval: „viel zu schnell"); der Speed-Bonus skaliert
// automatisch mit (speedBonus/fragenGewinn nehmen das Fenster als Parameter).
export const FRAGE_TIMER_MS: Record<Schwierigkeit, number> = {
  easy: 20_000, // 15 s → 20 s
  medium: 20_000, // 15 s → 20 s
  hard: 25_000, // 20 s → 25 s
  ultrahard: 30_000, // 25 s → 30 s
};

// ---------- Antwort-Cooldown ----------
/** Verschnaufpause nach einer FALSCHEN Antwort, bevor die nächste Frage kommt
 * (Eval: Panik-Spirale im „Affen-Bomben-Spiel"). Timer-basierte Formate
 * (Stinkbanane & Co.) pausieren währenddessen auch ihre Uhr — der Cooldown
 * darf nie zur versteckten Zusatz-Strafe werden. */
export const ANTWORT_COOLDOWN_MS = 4_000;
