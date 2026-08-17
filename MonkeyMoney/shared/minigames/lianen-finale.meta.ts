// Das große Lianen-Finale (GAME-DESIGN §2.10 + §3.5): das Finale-Format, fix.
// Jeder Affe hängt an seiner Liane über dem Krokodil-Fluss; Lianenlänge = live
// normierter Kontostand (Führender 100 %, Anzeige-Minimum 25 %). Q Finalfragen
// MC-4 gleichzeitig: richtig = +W_final (Ruck nach oben), falsch = −W_final/2
// (Riss nach unten), keine Antwort = 0. Kein Speed, keine Streak, keine Joker —
// die Formel hält exakt. Die BUCHUNG macht die Engine (bucheFinale, Konto ≥ 0);
// das Plugin bekommt den angesagten W_final-Wert über ContentSlice.mods.wFinal.
export const LIANEN_FINALE_ID = "lianen-finale";

export const LIANEN_FINALE_META = {
  id: LIANEN_FINALE_ID,
  name: "Das große Lianen-Finale",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // §2.10/§3.5: im Finale keine Streaks (und keine Joker — sperrt die Engine).
  streak: false,
  // Eigenes Set (Fluss, Lianen, Krokodil) — im Screen-los-Modus ersetzt SR1.
  needsScreen: true,
};

/** Spieler-Aktionen: nur die 4 Antwort-Buttons (Design: „Handy: nur 4 Buttons"). */
export type LianenFinaleAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing & Inszenierung (GAME-DESIGN §2.10, verbindlich) ----------

export const LF_FRAGE_MS = 12_000; // 12 s pro Finalfrage (fix, nicht nach Stufe)
export const LF_ANZEIGE_MIN = 0.25; // Anzeige-Minimum der Lianenlänge: 25 %
/** Fallback, wenn mods.wFinal fehlt (isolierte Läufe): das Formel-Minimum §3.5. */
export const LF_FALLBACK_W = 500;

/** Live normierte Lianenlänge: Führender 100 %, proportional, min. 25 %. */
export function lfLianenLaenge(kontostand: number, fuehrenderStand: number): number {
  const anteil = fuehrenderStand > 0 ? Math.max(0, kontostand) / fuehrenderStand : 1;
  return Math.max(LF_ANZEIGE_MIN, Math.min(1, anteil));
}
