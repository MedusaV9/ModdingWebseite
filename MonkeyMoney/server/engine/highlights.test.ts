// REPLAY-HIGHLIGHTS (v2): Heuristiken über synthetischen Chroniken — jede
// Heuristik einzeln (Schwellen!), dann Auswahl/Sortierung und Determinismus.
import { describe, expect, it } from "vitest";
import {
  extrahiereHighlights,
  HIGHLIGHT_BUZZER_MS,
  HIGHLIGHT_MIN_FALSCHANTWORT,
  HIGHLIGHT_MIN_KLAU,
  type ChronikEintrag,
} from "./highlights";

const NAMEN = { p1: "Anna", p2: "Ben", p3: "Cleo" };

describe("highlights: größter Klau", () => {
  it("findet den größten Klau und erzählt ihn mit Namen + Betrag", () => {
    const chronik: ChronikEintrag[] = [
      { art: "klau", dieb: "p1", opfer: "p2", betrag: 120, frageNr: 3 },
      { art: "klau", dieb: "p2", opfer: "p3", betrag: 450, frageNr: 7 },
      { art: "klau", dieb: "p3", opfer: "p1", betrag: 200, frageNr: 9 },
    ];
    const [hl] = extrahiereHighlights(chronik, NAMEN);
    expect(hl.art).toBe("groesster-klau");
    expect(hl.playerId).toBe("p2");
    expect(hl.gegnerId).toBe("p3");
    expect(hl.betrag).toBe(450);
    expect(hl.text).toContain("Ben");
    expect(hl.text).toContain("Cleo");
  });

  it("ignoriert Mini-Beute unter der Schwelle", () => {
    const chronik: ChronikEintrag[] = [
      { art: "klau", dieb: "p1", opfer: "p2", betrag: HIGHLIGHT_MIN_KLAU - 1, frageNr: 2 },
    ];
    expect(extrahiereHighlights(chronik, NAMEN)).toHaveLength(0);
  });
});

describe("highlights: knappster Buzzer", () => {
  it("nur Fotofinish-Momente unter 50 ms zählen — der knappste gewinnt", () => {
    const chronik: ChronikEintrag[] = [
      { art: "buzzer", playerId: "p1", zweiterId: "p2", deltaMs: 49, frageNr: 4 },
      { art: "buzzer", playerId: "p2", zweiterId: "p3", deltaMs: 12, frageNr: 8 },
      { art: "buzzer", playerId: "p3", zweiterId: "p1", deltaMs: HIGHLIGHT_BUZZER_MS, frageNr: 5 },
    ];
    const hls = extrahiereHighlights(chronik, NAMEN);
    expect(hls).toHaveLength(1);
    expect(hls[0].art).toBe("knappster-buzzer");
    expect(hls[0].playerId).toBe("p2");
    expect(hls[0].text).toContain("12 Millisekunden");
  });
});

describe("highlights: teuerste Falschantwort", () => {
  it("findet den größten Verlust einer falschen Antwort", () => {
    const chronik: ChronikEintrag[] = [
      { art: "antwort", playerId: "p1", frageNr: 2, correct: false, delta: -150 },
      { art: "antwort", playerId: "p2", frageNr: 6, correct: false, delta: -600 },
      { art: "antwort", playerId: "p3", frageNr: 6, correct: true, delta: 800 }, // richtig ⇒ egal
    ];
    const [hl] = extrahiereHighlights(chronik, NAMEN);
    expect(hl.art).toBe("teuerste-falschantwort");
    expect(hl.playerId).toBe("p2");
    expect(hl.betrag).toBe(600);
  });

  it("kleine Patzer unter der Schwelle sind kein Drama", () => {
    const chronik: ChronikEintrag[] = [
      {
        art: "antwort",
        playerId: "p1",
        frageNr: 2,
        correct: false,
        delta: -(HIGHLIGHT_MIN_FALSCHANTWORT - 1),
      },
    ];
    expect(extrahiereHighlights(chronik, NAMEN)).toHaveLength(0);
  });
});

describe("highlights: BANK!-Verrat + Jackpot", () => {
  it("größter BANK!-Drücker wird zum Verrats-Highlight", () => {
    const chronik: ChronikEintrag[] = [
      { art: "bank", playerId: "p1", betrag: 300, frageNr: 5 },
      { art: "bank", playerId: "p3", betrag: 900, frageNr: 11 },
    ];
    const [hl] = extrahiereHighlights(chronik, NAMEN);
    expect(hl.art).toBe("bank-verrat");
    expect(hl.playerId).toBe("p3");
    expect(hl.betrag).toBe(900);
  });

  it("„Team-Pott“ nur im Team-Modus — solo heißt es „aus der Kette“ (Playtest 3)", () => {
    const chronik: ChronikEintrag[] = [{ art: "bank", playerId: "p2", betrag: 400, frageNr: 6 }];
    const [solo] = extrahiereHighlights(chronik, NAMEN);
    expect(solo.text).toContain("aus der Kette");
    expect(solo.text).not.toContain("Team-Pott");
    const [teams] = extrahiereHighlights(chronik, NAMEN, 5, true);
    expect(teams.text).toContain("aus dem Team-Pott");
  });

  it("Jackpot-Knacker wird gefeiert", () => {
    const chronik: ChronikEintrag[] = [
      { art: "jackpot", playerId: "p2", betrag: 750, frageNr: 12 },
    ];
    const [hl] = extrahiereHighlights(chronik, NAMEN);
    expect(hl.art).toBe("jackpot");
    expect(hl.playerId).toBe("p2");
    expect(hl.text).toContain("Ben");
  });
});

describe("highlights: Comeback-Sprung", () => {
  it("erkennt die größte Rang-Verbesserung zum End-Stand (≥ 2 Plätze)", () => {
    const chronik: ChronikEintrag[] = [
      // p3 ist zwischenzeitlich Letzter (Platz 3) …
      { art: "stand", frageNr: 5, staende: { p1: 500, p2: 300, p3: 100 } },
      { art: "stand", frageNr: 10, staende: { p1: 700, p2: 600, p3: 400 } },
      // … und am Ende Erster (Platz 1) ⇒ 2 Plätze gutgemacht.
      { art: "stand", frageNr: 15, staende: { p1: 700, p2: 800, p3: 900 } },
    ];
    const [hl] = extrahiereHighlights(chronik, NAMEN);
    expect(hl.art).toBe("comeback");
    expect(hl.playerId).toBe("p3");
    expect(hl.text).toContain("Platz 3");
    expect(hl.text).toContain("Platz 1");
  });

  it("1 Platz Verbesserung ist KEIN Comeback", () => {
    const chronik: ChronikEintrag[] = [
      { art: "stand", frageNr: 5, staende: { p1: 500, p2: 300 } },
      { art: "stand", frageNr: 15, staende: { p1: 400, p2: 600 } },
    ];
    expect(extrahiereHighlights(chronik, NAMEN)).toHaveLength(0);
  });
});

describe("highlights: Auswahl + Determinismus", () => {
  /** Volle Chronik mit ALLEN 6 Kandidaten-Arten. */
  const volleChronik = (): ChronikEintrag[] => [
    { art: "antwort", playerId: "p1", frageNr: 2, correct: false, delta: -400 },
    { art: "buzzer", playerId: "p2", zweiterId: "p1", deltaMs: 8, frageNr: 4 },
    { art: "stand", frageNr: 5, staende: { p1: 100, p2: 600, p3: 400 } },
    { art: "klau", dieb: "p3", opfer: "p2", betrag: 350, frageNr: 7 },
    { art: "bank", playerId: "p2", betrag: 500, frageNr: 9 },
    { art: "jackpot", playerId: "p1", betrag: 650, frageNr: 12 },
    { art: "stand", frageNr: 15, staende: { p1: 900, p2: 700, p3: 500 } },
  ];

  it("wählt maximal 5 der 6 Kandidaten und ordnet sie chronologisch", () => {
    const hls = extrahiereHighlights(volleChronik(), NAMEN);
    expect(hls).toHaveLength(5);
    const frageNrn = hls.map((h) => h.frageNr);
    expect(frageNrn).toEqual([...frageNrn].sort((a, b) => a - b));
    // 6 Kandidaten, Top 5 nach Spektakel-Wert: der schwächste fliegt raus.
    const arten = hls.map((h) => h.art);
    expect(new Set(arten).size).toBe(5);
  });

  it("ist deterministisch: gleiche Chronik ⇒ exakt gleiche Highlights", () => {
    const a = extrahiereHighlights(volleChronik(), NAMEN);
    const b = extrahiereHighlights(volleChronik(), NAMEN);
    expect(a).toEqual(b);
  });

  it("leere Chronik ⇒ keine Highlights (Sequenz wird übersprungen)", () => {
    expect(extrahiereHighlights([], NAMEN)).toHaveLength(0);
  });

  it("respektiert maxAnzahl (Top-N nach Spektakel-Wert)", () => {
    const hls = extrahiereHighlights(volleChronik(), NAMEN, 2);
    expect(hls).toHaveLength(2);
  });
});
