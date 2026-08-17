// Bestenlisten (§7.3): genau 4 Boards mit Fairness-Schwellen + Profil-Karte.
import { describe, expect, it } from "vitest";
import { leereProfilStats, type MetaProfil, type ProfilStats } from "../../shared/meta";
import { baueBoardFortschritt, baueBoards, baueProfilKarte } from "./boards";

function profil(id: string, name: string, atGesamt: number): MetaProfil {
  return {
    profileId: id,
    name,
    avatar: "don-bananas.gelb",
    pinHash: null,
    createdAt: 0,
    deviceTokens: [],
    at: { gesamt: atGesamt, verfuegbar: atGesamt },
    besitz: [],
    ausgeruestet: {},
    ersteMale: {},
    gebuchteMatches: [],
  };
}

function statsMit(patch: Partial<ProfilStats>): ProfilStats {
  return { ...leereProfilStats(), ...patch };
}

describe("meta: Bestenlisten (§7.3)", () => {
  it("Money-Boss sortiert nach Lifetime-AT; 0-AT-Profile bleiben draußen", () => {
    const boards = baueBoards(
      [profil("a", "Anna", 5000), profil("b", "Ben", 9000), profil("c", "Cleo", 0)],
      {},
    );
    expect(boards.moneyBoss.map((e) => e.name)).toEqual(["Ben", "Anna"]);
  });

  it("Kategorie-Meister braucht ≥ 20 Antworten in der Kategorie", () => {
    const stats = {
      a: statsMit({ matrix: { "wissen|easy": { n: 25, richtig: 20 } } }),
      b: statsMit({ matrix: { "sport|easy": { n: 10, richtig: 10 } } }), // zu wenig
    };
    const boards = baueBoards([profil("a", "Anna", 1), profil("b", "Ben", 1)], stats);
    expect(boards.kategorieMeister.map((e) => e.name)).toEqual(["Anna"]);
    expect(boards.kategorieMeister[0].extra).toBe("wissen");
  });

  it("Blitz-Buzzer: MEDIAN-Zeit (kein Glücks-Bestwert), Schwelle 30, schneller = besser", () => {
    const schnell = new Array(40).fill(0) as number[];
    schnell[2] = 35; // Median ~1,25 s
    const langsam = new Array(40).fill(0) as number[];
    langsam[10] = 40; // Median ~5,25 s
    const wenig = new Array(40).fill(0) as number[];
    wenig[0] = 10; // unter der 30er-Schwelle
    const boards = baueBoards(
      [profil("a", "Anna", 1), profil("b", "Ben", 1), profil("c", "Cleo", 1)],
      {
        a: statsMit({ zeitBuckets: langsam }),
        b: statsMit({ zeitBuckets: schnell }),
        c: statsMit({ zeitBuckets: wenig }),
      },
    );
    expect(boards.blitzBuzzer.map((e) => e.name)).toEqual(["Ben", "Anna"]);
  });

  it("Comeback-König: Win-Rate NUR aus Matches ohne Führung vorm Finale, ≥ 5", () => {
    const boards = baueBoards([profil("a", "Anna", 1), profil("b", "Ben", 1)], {
      a: statsMit({ comebackMatches: 6, comebackSiege: 3 }),
      b: statsMit({ comebackMatches: 4, comebackSiege: 4 }), // unter der Schwelle
    });
    expect(boards.comebackKoenig.map((e) => e.name)).toEqual(["Anna"]);
    expect(boards.comebackKoenig[0].anzeige).toBe("50 %");
  });
});

describe("meta: Profil-Karte (§7.1)", () => {
  it("zeigt Lieblings-/Nemesis-Kategorie + Bestleistungen aus den Stats", () => {
    const karte = baueProfilKarte(
      profil("a", "Anna", 6000),
      statsMit({
        matrix: {
          "wissen|easy": { n: 30, richtig: 27 },
          "sport|easy": { n: 25, richtig: 5 },
        },
        schnellsteAntwortMs: 840,
        besterEndstand: 14_500,
        laengsteSerie: 9,
        matches: 12,
        siege: 4,
      }),
    );
    expect(karte.level).toBe(3);
    expect(karte.lieblingsKategorie?.kategorie).toBe("wissen");
    expect(karte.nemesisKategorie?.kategorie).toBe("sport");
    expect(karte.schnellsteAntwortMs).toBe(840);
    expect(karte.hoechsterMatchGewinn).toBe(14_500);
    expect(karte.gesperrt).toBe(false);
  });

  it("funktioniert ohne Stats (frisches Profil)", () => {
    const karte = baueProfilKarte(profil("a", "Anna", 0), null);
    expect(karte.matches).toBe(0);
    expect(karte.lieblingsKategorie).toBeNull();
  });
});

describe("meta: Board-Fortschritt (§7.3-Fix leere Boards)", () => {
  it("frisches Profil: alle Zähler bei 0, Schwellen aus BOARD_SCHWELLEN", () => {
    const f = baueBoardFortschritt(profil("a", "Anna", 0), null);
    expect(f.moneyBoss).toEqual({ ist: 0, schwelle: 1 });
    expect(f.kategorieMeister).toEqual({ ist: 0, schwelle: 20 });
    expect(f.blitzBuzzer).toEqual({ ist: 0, schwelle: 30 });
    expect(f.comebackKoenig).toEqual({ ist: 0, schwelle: 5 });
  });

  it("zählt die MEISTEN Antworten EINER Kategorie (über Schwierigkeiten summiert)", () => {
    const f = baueBoardFortschritt(
      profil("a", "Anna", 450),
      statsMit({
        matrix: {
          "wissen|easy": { n: 8, richtig: 6 },
          "wissen|hard": { n: 5, richtig: 2 },
          "sport|easy": { n: 3, richtig: 3 },
        },
        zeitBuckets: (() => {
          const b = new Array(40).fill(0) as number[];
          b[4] = 12;
          return b;
        })(),
        comebackMatches: 2,
      }),
    );
    expect(f.moneyBoss.ist).toBe(450);
    expect(f.kategorieMeister.ist).toBe(13); // wissen: 8 + 5, nicht 16 gesamt
    expect(f.blitzBuzzer.ist).toBe(12);
    expect(f.comebackKoenig.ist).toBe(2);
  });
});
