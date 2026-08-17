// Eingebauter Sortierfragen-Pool v0 — der Content-Loader kennt noch keine
// `sortier`-Fragen (shared/content.ts ist choice4-only). Feldsemantik:
// korrektReihenfolge[i] = Element-Index auf Sprosse i (unten = 0),
// aufloesungWerte[e] = Anzeige-Wert von Element e (CONTENT-PLAN §2.3).
import type { LeiterFrage } from "../../../shared/minigames/affenleiter.meta";

export const LEITER_FRAGEN: readonly LeiterFrage[] = [
  {
    id: "leiter_planeten",
    text: "Sortiere die Planeten nach Größe — der kleinste nach unten!",
    schwierigkeit: "medium",
    elemente: ["Erde", "Jupiter", "Merkur", "Mars"],
    korrektReihenfolge: [2, 3, 0, 1],
    aufloesungWerte: ["12.742 km", "139.820 km", "4.879 km", "6.779 km"],
    erklaerung: "Merkur < Mars < Erde < Jupiter — in Jupiter passt die Erde über 1.300-mal.",
  },
  {
    id: "leiter_erfindungen",
    text: "Sortiere die Erfindungen — die älteste nach unten!",
    schwierigkeit: "medium",
    elemente: ["Telefon", "Buchdruck", "Automobil", "Dampfmaschine"],
    korrektReihenfolge: [1, 3, 0, 2],
    aufloesungWerte: ["1876", "um 1450", "1886", "1769"],
    erklaerung:
      "Gutenbergs Buchdruck (~1450) → Watts Dampfmaschine (1769) → Bells Telefon (1876) → Benz' Automobil (1886).",
  },
  {
    id: "leiter_tiere",
    text: "Sortiere die Tiere nach Gewicht — das leichteste nach unten!",
    schwierigkeit: "easy",
    elemente: ["Löwe", "Hauskatze", "Afrikanischer Elefant", "Schäferhund"],
    korrektReihenfolge: [1, 3, 0, 2],
    aufloesungWerte: ["ca. 190 kg", "ca. 4 kg", "ca. 5.000 kg", "ca. 35 kg"],
    erklaerung: "Katze (4 kg) < Schäferhund (35 kg) < Löwe (190 kg) < Elefant (5 Tonnen).",
  },
  {
    id: "leiter_laender",
    text: "Sortiere die Länder nach Einwohnern — das kleinste nach unten!",
    schwierigkeit: "easy",
    elemente: ["Deutschland", "Island", "USA", "Schweiz"],
    korrektReihenfolge: [1, 3, 0, 2],
    aufloesungWerte: ["ca. 84 Mio.", "ca. 0,4 Mio.", "ca. 335 Mio.", "ca. 8,8 Mio."],
    erklaerung: "Island (390.000) < Schweiz (8,8 Mio.) < Deutschland (84 Mio.) < USA (335 Mio.).",
  },
  {
    id: "leiter_fluesse",
    text: "Sortiere die Flüsse nach Länge — der kürzeste nach unten!",
    schwierigkeit: "medium",
    elemente: ["Donau", "Themse", "Nil", "Elbe"],
    korrektReihenfolge: [1, 3, 0, 2],
    aufloesungWerte: ["2.857 km", "346 km", "6.650 km", "1.094 km"],
    erklaerung: "Themse (346) < Elbe (1.094) < Donau (2.857) < Nil (6.650 km).",
  },
  {
    id: "leiter_bauwerke",
    text: "Sortiere die Bauwerke nach Höhe — das niedrigste nach unten!",
    schwierigkeit: "easy",
    elemente: ["Burj Khalifa", "Kölner Dom", "Eiffelturm", "Empire State Building"],
    korrektReihenfolge: [1, 2, 3, 0],
    aufloesungWerte: ["828 m", "157 m", "330 m", "443 m"],
    erklaerung: "Kölner Dom (157) < Eiffelturm (330) < Empire State (443) < Burj Khalifa (828 m).",
  },
  {
    id: "leiter_ereignisse",
    text: "Sortiere die Ereignisse — das früheste nach unten!",
    schwierigkeit: "easy",
    elemente: ["Mauerfall", "Erstes iPhone", "Mondlandung", "Euro-Bargeld"],
    korrektReihenfolge: [2, 0, 3, 1],
    aufloesungWerte: ["1989", "2007", "1969", "2002"],
    erklaerung: "Mondlandung (1969) → Mauerfall (1989) → Euro-Bargeld (2002) → iPhone (2007).",
  },
  {
    id: "leiter_tempo",
    text: "Sortiere nach Höchsttempo — das langsamste nach unten!",
    schwierigkeit: "hard",
    elemente: ["Gepard", "Wanderfalke (Sturzflug)", "Weinbergschnecke", "Usain Bolt"],
    korrektReihenfolge: [2, 3, 0, 1],
    aufloesungWerte: ["ca. 100 km/h", "über 300 km/h", "ca. 0,003 km/h", "ca. 44 km/h"],
    erklaerung:
      "Schnecke (0,003) < Bolt (44) < Gepard (100) < Wanderfalke im Sturzflug (300+ km/h).",
  },
];
