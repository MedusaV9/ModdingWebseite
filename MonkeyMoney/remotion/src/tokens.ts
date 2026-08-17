// Design-Tokens nach docs/ART-SOUND-VIDEO-PLAN.md §1.1 „Banana Vault"
// (12 Farben + Outline-Konstante) und §1.2 (Bungee/Rubik). Verbindlich.

export const PALETTE = {
  jungleNight: "#0E2A1F",
  deepPalm: "#14532D",
  leaf: "#22A559",
  bananaLeaf: "#8FE04B",
  billGreen: "#85BB65",
  vaultGold: "#F5B301",
  coinShine: "#FFDE6B",
  banana: "#FFC93C",
  curtain: "#C2183B",
  spotlightPink: "#FF3E8E",
  studioLed: "#29D9D5",
  ticketPaper: "#FFF6E3",
  outline: "#1A1208",
} as const;

/** Volle 8er-Spielerfarben-Reihe (Plan §1.1). */
export const PLAYER_COLORS = [
  "#FFC93C",
  "#FF3E8E",
  "#29D9D5",
  "#8FE04B",
  "#F97316",
  "#8B5CF6",
  "#3B82F6",
  "#F472B6",
] as const;

export const FONT_DISPLAY = "Bungee, sans-serif";
export const FONT_TEXT = "Rubik, sans-serif";

/** Harter Sticker-Schatten (Plan §1.3 Gesetz 3 — KEINE weichen Blur-Schatten). */
export const STICKER_SHADOW = "10px 12px 0 rgba(26, 18, 8, 0.4)";
export const STICKER_BORDER = `6px solid ${PALETTE.outline}`;
