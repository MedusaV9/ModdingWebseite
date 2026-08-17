// Bananen-Basics (GAME-DESIGN §2.1): der Point-Builder-OPENER, fix in jeder Show.
// MC-4-Standardrunde, alle antworten gleichzeitig — milde Werte, Streak baut sich
// auf, Runde 1 ist verlustfrei (falsch = 0, Standard-MC ist ohnehin straffrei).
export const BANANEN_BASICS_ID = "bananen-basics";

export const BANANEN_BASICS_META = {
  id: BANANEN_BASICS_ID,
  name: "Bananen-Basics",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // §3.1: die Streak-Kette zählt in Frage-Formaten — Basics ist DER Streak-Bauer.
  streak: true,
  // Voller Joker-Support (Opener = Onboarding, hier lernen alle die Joker kennen).
  jokerAktionen: ["fiftyFifty", "removeOne", "secondTry"] as const,
  // Maßanzug/Portfolio: eigene Frage pro zugewiesenem Spieler wird konsumiert.
  perSpielerFragen: true,
};

/** Spieler-Aktionen: einrasten auf eine der 4 Optionen (kein Umentscheiden). */
export type BananenBasicsAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

/** Button-/Lianen-Deko nach Design §2.1: 🍌 Gelb, 🥥 Braun, 🐒 Rot, 🌴 Grün. */
export const BB_DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

/** Auflösungs-Beat auf der Bühne (falsche Lianen reißen, 6 s laut Design). */
export const BB_AUFLOESUNG_MS = 6_000;
