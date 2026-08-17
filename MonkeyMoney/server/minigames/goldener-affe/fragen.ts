// Eingebauter Schätzfragen-Pool für den Goldenen Affen (Stufe 2 + Showdown) —
// der Content-Loader kennt noch keine `schaetz`-Fragen (choice4-only, gleiche
// Lage wie beim Bananen-Tresor). Werte-Regeln aus CONTENT-PLAN §5.6:
// Richtwert nicht in der Spannen-Mitte, Spanne mindestens Faktor 4.
import type { GaSchaetzfrage } from "../../../shared/minigames/goldener-affe.meta";

export const GA_SCHAETZFRAGEN: readonly GaSchaetzfrage[] = [
  {
    id: "ga_gold_dichte",
    text: "Wie schwer ist ein Liter pures Gold (in Kilogramm)?",
    einheit: "kg",
    richtwert: 19,
    eingabeMin: 1,
    eingabeMax: 100,
    erklaerung: "Rund 19,3 kg — Gold ist fast doppelt so dicht wie Blei.",
  },
  {
    id: "ga_bananen_welt",
    text: "Wie viele Millionen Tonnen Bananen erntet die Welt pro Jahr?",
    einheit: "Mio. t",
    richtwert: 135,
    eingabeMin: 10,
    eingabeMax: 500,
    erklaerung: "Etwa 135 Millionen Tonnen — Indien allein erntet über ein Viertel.",
  },
  {
    id: "ga_affenarten",
    text: "Wie viele Affenarten (Primaten ohne Mensch) sind beschrieben?",
    einheit: "Arten",
    richtwert: 500,
    eingabeMin: 50,
    eingabeMax: 2000,
    erklaerung: "Rund 500 Arten — und es werden fast jedes Jahr neue entdeckt.",
  },
  {
    id: "ga_goldbarren",
    text: "Wie schwer ist ein Standard-Goldbarren der Zentralbanken (in Gramm)?",
    einheit: "g",
    richtwert: 12441,
    eingabeMin: 1000,
    eingabeMax: 50000,
    erklaerung: "Rund 12.441 g (400 Unzen) — der Good-Delivery-Standard.",
  },
  {
    id: "ga_schaedel",
    text: "Wie viele Kilokalorien hat eine Banane (Durchschnittsgröße)?",
    einheit: "kcal",
    richtwert: 105,
    eingabeMin: 20,
    eingabeMax: 500,
    erklaerung: "Etwa 105 kcal — der schnellste Kraftstoff des Dschungels.",
  },
  {
    id: "ga_everest",
    text: "Wie hoch ist der Mount Everest (in Metern)?",
    einheit: "m",
    richtwert: 8849,
    eingabeMin: 2000,
    eingabeMax: 20000,
    erklaerung: "8.849 m — 2020 haben China und Nepal gemeinsam neu vermessen.",
  },
];
