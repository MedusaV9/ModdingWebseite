// Team-Modus v1 „Affenbanden" (GAME-DESIGN §1.4): pure Team-Logik —
// Team-Anzahl je Modus, Bildung (Wünsche + Stärke-Balance + Doppel-Affe bei
// ungeraden Zahlen), Topf-Aggregation (Doppel-Affe ×2), Ranking und die
// team-bezogene Rückenwind-Basis (§3.4 auf Team-Töpfen).
import { describe, expect, it } from "vitest";
import { createRng } from "./rng";
import {
  angeboteneTeams,
  bildeTeams,
  letztesTeam,
  MAX_TEAMS,
  TEAM_NAMEN_POOL,
  teamAnzahl,
  teamAnzeigeName,
  teamMitglieder,
  teamName,
  teamRueckenwindBasis,
  teamStaende,
  teamTopf,
  type TeamAufstellung,
} from "./teams";

const rng = () => createRng(7);

describe("teamAnzahl + angeboteneTeams", () => {
  it("2er: Zweierteams — 4→2, 5→3, 7→4, ab 8 gekappt auf 4", () => {
    expect(teamAnzahl("2er", 4)).toBe(2);
    expect(teamAnzahl("2er", 5)).toBe(3);
    expect(teamAnzahl("2er", 7)).toBe(4);
    expect(teamAnzahl("2er", 8)).toBe(4);
    expect(teamAnzahl("2er", 12)).toBe(MAX_TEAMS);
  });

  it("2v2v2v2 und frei bieten immer 4 Lager an", () => {
    expect(teamAnzahl("2v2v2v2", 4)).toBe(4);
    expect(teamAnzahl("frei", 5)).toBe(4);
  });

  it("angeboteneTeams folgt dem Farb-Ring (banane zuerst)", () => {
    expect(angeboteneTeams("2er", 4)).toEqual(["banane", "kokos"]);
    expect(angeboteneTeams("2er", 5)).toEqual(["banane", "kokos", "liane"]);
    expect(angeboteneTeams("frei", 4)).toEqual(["banane", "kokos", "liane", "orchidee"]);
  });
});

describe("bildeTeams: 2er-Modus (gerade Zahlen)", () => {
  it("4 Spieler → 2 Teams à 2, kein Doppel-Affe, alle zugeordnet", () => {
    const a = bildeTeams({ modus: "2er", spieler: ["p1", "p2", "p3", "p4"], rng: rng() });
    expect(a.teams).toHaveLength(2);
    expect(a.doppelAffe).toBeNull();
    expect(Object.keys(a.zuordnung).sort()).toEqual(["p1", "p2", "p3", "p4"]);
    for (const t of a.teams) {
      expect(teamMitglieder(a, t.id, ["p1", "p2", "p3", "p4"])).toHaveLength(2);
    }
  });

  it("8 Spieler → 4 Teams à 2 (2v2v2v2 aus dem Design)", () => {
    const spieler = ["p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8"];
    const a = bildeTeams({ modus: "2er", spieler, rng: rng() });
    expect(a.teams).toHaveLength(4);
    for (const t of a.teams) expect(teamMitglieder(a, t.id, spieler)).toHaveLength(2);
  });
});

describe("bildeTeams: ungerade Zahlen ⇒ Doppel-Affe-Regel", () => {
  it("5 Spieler → Teams (2,2,1) — der Solo-Affe wird Doppel-Affe", () => {
    const spieler = ["p1", "p2", "p3", "p4", "p5"];
    const a = bildeTeams({ modus: "2er", spieler, rng: rng() });
    expect(a.teams).toHaveLength(3);
    const groessen = a.teams.map((t) => teamMitglieder(a, t.id, spieler).length).sort();
    expect(groessen).toEqual([1, 2, 2]);
    const solo = a.teams.find((t) => teamMitglieder(a, t.id, spieler).length === 1);
    expect(a.doppelAffe).toBe(teamMitglieder(a, solo!.id, spieler)[0]);
  });

  it("7 Spieler → Teams (2,2,2,1) + Doppel-Affe", () => {
    const spieler = ["p1", "p2", "p3", "p4", "p5", "p6", "p7"];
    const a = bildeTeams({ modus: "2er", spieler, rng: rng() });
    const groessen = a.teams.map((t) => teamMitglieder(a, t.id, spieler).length).sort();
    expect(groessen).toEqual([1, 2, 2, 2]);
    expect(a.doppelAffe).not.toBeNull();
  });

  it("die Stärke-MITTE landet solo — mit ×2 die fairste Aufstellung", () => {
    const a = bildeTeams({
      modus: "2er",
      spieler: ["p1", "p2", "p3", "p4", "p5"],
      staerke: { p1: 900, p2: 700, p3: 500, p4: 300, p5: 100 },
      rng: rng(),
    });
    // Greedy-Draft: 900+100 / 700+300 / 500 solo — effektiv 1000/1000/1000,
    // denn der Doppel-Affe (Mitte) zählt im Topf doppelt. Perfekte Balance.
    expect(a.doppelAffe).toBe("p3");
    expect(a.zuordnung.p1).toBe(a.zuordnung.p5);
    expect(a.zuordnung.p2).toBe(a.zuordnung.p4);
  });
});

describe("bildeTeams: Wünsche + Stärke-Balance", () => {
  it("Wünsche werden in Join-Reihenfolge erfüllt, solange Kapazität da ist", () => {
    const a = bildeTeams({
      modus: "2er",
      spieler: ["p1", "p2", "p3", "p4"],
      wuensche: { p1: "kokos", p2: "kokos", p3: "kokos" }, // p3 kommt zu spät
      rng: rng(),
    });
    expect(a.zuordnung.p1).toBe("kokos");
    expect(a.zuordnung.p2).toBe("kokos");
    expect(a.zuordnung.p3).toBe("banane"); // Kapazität voll ⇒ umverteilt
    expect(a.zuordnung.p4).toBe("banane");
  });

  it("Auto-Balance: stärkste zuerst ins schwächste Team (Fairer Draft)", () => {
    const a = bildeTeams({
      modus: "2er",
      spieler: ["p1", "p2", "p3", "p4"],
      staerke: { p1: 100, p2: 80, p3: 20, p4: 10 },
      rng: rng(),
    });
    // Snake: 100 → Team A, 80 → Team B, 20 → Team B (20+80=100 < 100), 10 → A.
    expect(a.zuordnung.p1).not.toBe(a.zuordnung.p2);
    const summe = (teamId: string): number =>
      Object.entries(a.zuordnung)
        .filter(([, t]) => t === teamId)
        .reduce((s, [pid]) => s + ({ p1: 100, p2: 80, p3: 20, p4: 10 }[pid] ?? 0), 0);
    const summen = a.teams.map((t) => summe(t.id)).sort((x, y) => x - y);
    expect(summen).toEqual([100, 110]); // maximal ausbalanciert
  });

  it("frei-Modus: leere Teams fallen beim Start weg", () => {
    const a = bildeTeams({
      modus: "frei",
      spieler: ["p1", "p2", "p3", "p4"],
      wuensche: { p1: "banane", p2: "banane", p3: "liane", p4: "liane" },
      rng: rng(),
    });
    expect(a.teams.map((t) => t.id).sort()).toEqual(["banane", "liane"]);
  });

  it("frei-Modus: ALLE in einem Team ⇒ Zwangs-Halbierung (kein 1-Team-Match)", () => {
    const a = bildeTeams({
      modus: "frei",
      spieler: ["p1", "p2", "p3", "p4"],
      wuensche: { p1: "banane", p2: "banane", p3: "banane", p4: "banane" },
      rng: rng(),
    });
    expect(a.teams).toHaveLength(2);
    const spieler = ["p1", "p2", "p3", "p4"];
    const groessen = a.teams.map((t) => teamMitglieder(a, t.id, spieler).length).sort();
    expect(groessen).toEqual([2, 2]);
  });
});

describe("Team-Topf: Summe der Konten, Doppel-Affe ×2", () => {
  const aufstellung: TeamAufstellung = {
    modus: "2er",
    teams: [
      { id: "banane", name: "Die Bananen-Barone", farbe: "#FFC93C", emoji: "🍌" },
      { id: "kokos", name: "Der Kokos-Konzern", farbe: "#B4693C", emoji: "🥥" },
      { id: "liane", name: "Die Lianen-Liga", farbe: "#2FBF71", emoji: "🌿" },
    ],
    zuordnung: { p1: "banane", p2: "banane", p3: "kokos", p4: "kokos", p5: "liane" },
    doppelAffe: "p5",
  };

  it("Topf = Summe der Mitglieds-Konten", () => {
    const topf = teamTopf(aufstellung, "banane", { p1: 300, p2: 200, p3: 0, p4: 0, p5: 0 });
    expect(topf).toBe(500);
  });

  it("der Doppel-Affe zählt im Topf DOPPELT (ungerade-Ausgleich)", () => {
    const topf = teamTopf(aufstellung, "liane", { p5: 400 });
    expect(topf).toBe(800);
  });

  it("teamStaende: Ranking absteigend nach Topf, Plätze 1-basiert", () => {
    const staende = teamStaende(aufstellung, { p1: 100, p2: 100, p3: 500, p4: 100, p5: 200 });
    // banane 200 · kokos 600 · liane 400 (Doppel-Affe ×2).
    expect(staende.map((s) => s.teamId)).toEqual(["kokos", "liane", "banane"]);
    expect(staende.map((s) => s.platz)).toEqual([1, 2, 3]);
    expect(staende.map((s) => s.topf)).toEqual([600, 400, 200]);
  });

  it("Topf-Gleichstand: das Sudden-Death-Sieger-Team holt Platz 1", () => {
    const balances = { p1: 300, p2: 300, p3: 400, p4: 200, p5: 0 };
    expect(teamStaende(aufstellung, balances)[0].teamId).toBe("banane"); // Farb-Ring
    expect(teamStaende(aufstellung, balances, "kokos")[0].teamId).toBe("kokos");
  });

  it("letztesTeam: das Team mit dem kleinsten Topf", () => {
    expect(letztesTeam(aufstellung, { p1: 900, p2: 0, p3: 500, p4: 0, p5: 10 })).toBe("liane");
  });
});

describe("teamRueckenwindBasis: Underdog rechnet auf TEAM-Töpfen (§3.4)", () => {
  const aufstellung: TeamAufstellung = {
    modus: "2er",
    teams: [
      { id: "banane", name: "A", farbe: "#FFC93C", emoji: "🍌" },
      { id: "kokos", name: "B", farbe: "#B4693C", emoji: "🥥" },
    ],
    zuordnung: { p1: "banane", p2: "banane", p3: "kokos", p4: "kokos" },
    doppelAffe: null,
  };
  const balances = { p1: 900, p2: 700, p3: 100, p4: 100 }; // Töpfe: 1600 vs 200

  it("jeder Spieler bekommt den EIGENEN Team-Topf als Stand", () => {
    const basis = teamRueckenwindBasis(aufstellung, balances);
    expect(basis.p3.eigenerStand).toBe(200);
    expect(basis.p3.fuehrenderStand).toBe(1600);
    // Auch der individuell reiche p1 rechnet mit dem Team-Topf.
    expect(basis.p1.eigenerStand).toBe(1600);
  });

  it("vordermannStand: Führungs-Team sieht sich selbst, Verfolger den Vordermann", () => {
    const basis = teamRueckenwindBasis(aufstellung, balances);
    expect(basis.p1.vordermannStand).toBe(1600);
    expect(basis.p4.vordermannStand).toBe(1600);
  });
});

describe("Team-Namen aus dem Affen-Wortschatz", () => {
  it("teamName ist deterministisch (injizierter Rng) und kommt aus dem Pool", () => {
    expect(teamName("banane", createRng(11))).toBe(teamName("banane", createRng(11)));
    expect(TEAM_NAMEN_POOL.kokos).toContain(teamName("kokos", rng()));
  });

  it("teamAnzeigeName: neutraler Lobby-Name vor der Bildung", () => {
    expect(teamAnzeigeName("banane")).toBe("Team Banane");
    expect(teamAnzeigeName("orchidee")).toBe("Team Orchidee");
  });
});
