// Kernregel-Banner (W4, Eval-6 „Demos unverständlich"): pro Format EIN
// prominenter 1-Satz-Merksatz als Sticker-Banner ÜBER der Demo-Bühne —
// destilliert aus den explainCard-Texten der Plugins (Screen-lokal, damit
// der Registry-Vertrag unangetastet bleibt). Formate ohne Eintrag zeigen
// keinen Banner (Fallback bleibt die bisherige Karte).
const KERNREGELN: Record<string, string> = {
  "bananen-basics": "Richtig = Money + Speed-Bonus — Streak zählt!",
  "vier-lianen": "Schnell + richtig = mehr MONKEY MONEY!",
  "kokosnuss-uhr": "Der Sack schrumpft — Antworten friert DEINEN Betrag ein!",
  affenbank: "BANK! sichert den Pott — sonst reißt die Kette!",
  taschendieb: "Der Schnellste klaut beim Wunsch-Opfer!",
  "bananen-tortenschlacht": "Richtig = Torte werfen — 3 Treffer = RAUS!",
  "bananen-boxkampf": "Jede richtige Antwort = ein Schlag — 0 HP = K.O.!",
  "konter-quiz": "Falsch = dein Gegner kriegt 150 MM!",
  "song-snippet": "Buzzern heißt allein raten — falsch = Sperre + Strafe!",
  "song-rueckwaerts": "Der Song läuft RÜCKWÄRTS — schnell erkennen lohnt!",
  "musikvideo-raten": "Früh erkannt = voller Wert, Ton-Tipp = halbe Gage!",
  "wer-singts": "Der Titel steht da — aber WER singt ihn?",
  "buchstaben-telegramm": "Nur Buchstaben tippen — errät's der Partner, kriegen BEIDE Money!",
  "affen-auktion": "Blind bieten: richtig = Gebot ×2, falsch = Gebot an alle!",
  "alles-oder-banane": "Geheim setzen: richtig = Einsatz ×2 — falsch = weg!",
  "bananen-boerse": "Früh kaufen sichert die hohe Quote — Nachzügler drücken den Kurs!",
  "bananen-bluff": "Wahrheit oder Bluff? Wer dem Lügner glaubt, ZAHLT an ihn!",
  "pixel-dschungel": "Je schärfer das Bild, desto kleiner der Gewinn!",
  "goldener-affe": "3 Finale-Stufen — der Sieger nimmt 20 % von ALLEN mit!",
  stinkbanane: "Richtig = weitergeben — bei wem sie platzt: 500 MM ins Glas!",
  "monkey-market": "10 Chips auf 4 Türen — nur die richtige Tür zahlt ×2!",
  "lianen-finale": "Richtig = rauf, falsch = halbe Höhe runter zum Krokodil!",
  "bananen-tresor": "Wer am nächsten dran ist, kassiert — Volltreffer sprengt den Tresor!",
  "lianensteg-duell": "Wer schneller RICHTIG antwortet, schubst — Best-of-5!",
  affenleiter: "Richtig sortieren — die perfekte Leiter gibt den Bonus!",
  "risiko-leiter": "Weiterklettern oder absichern? Falsch = Absturz auf Stufe 3!",
  "einer-gegen-alle": "EINER gegen die Mehrheit — schlag die Menge, hol 400!",
};

/** 1-Satz-Kernregel eines Formats — null = kein Banner. */
export function kernregelFuer(minigameId: string): string | null {
  return KERNREGELN[minigameId] ?? null;
}

/** Alle Format-Ids mit Kernregel (Tests: Abdeckung gegen die Choreos). */
export function alleKernregelIds(): string[] {
  return Object.keys(KERNREGELN);
}
