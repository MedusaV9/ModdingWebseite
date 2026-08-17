// Vier Lianen (4er-Choice, Simultan-Eingabe) — beidseitig gebrauchte Meta + Action-Typen.
export const VIER_LIANEN_ID = "vier-lianen";

export const VIER_LIANEN_META = {
  id: VIER_LIANEN_ID,
  name: "Vier Lianen",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "quiz" as const,
  // Engine-Ausbau: unterstützte Joker-Wirkungs-Hooks (Referenz-Implementierung).
  jokerAktionen: ["fiftyFifty", "removeOne", "secondTry"] as const,
  // Maßanzug/Portfolio: eigene Frage pro Spieler wird konsumiert.
  perSpielerFragen: true,
};

/** Spieler-Aktionen dieses Minigames (Payload von player.action). */
export type VierLianenAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

/** Button-Deko: Farbe+Form+Buchstabe-System (A–D). */
export const ANTWORT_DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;
