// Affenleiter-Plugin: Teilpunkte-Goldens, Perfekt+Speed-Bonus, gemischte Start-
// reihenfolge (nie die Lösung), Permutations-Validierung, Disconnect, Leak, Seed.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import type { LeiterFrage } from "../../shared/minigames/affenleiter.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import { affenleiterPlugin, type AffenleiterState } from "./affenleiter/index";

const dummyQuestion: Question = {
  id: "q_dummy",
  kind: "choice4",
  category: "test",
  difficulty: "easy",
  text: "?",
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: ".",
};
const content: ContentSlice = { questions: [dummyQuestion] };

const testFrage: LeiterFrage = {
  id: "leiter_test",
  text: "Sortiere — das Kleinste nach unten!",
  schwierigkeit: "medium", // Grundwert 250 (§3.1)
  elemente: ["A", "B", "C", "D"],
  korrektReihenfolge: [2, 3, 0, 1],
  aufloesungWerte: ["3", "4", "1", "2"],
  erklaerung: "C < D < A < B.",
};

const spieler = [asPlayerId("p1"), asPlayerId("p2")];

function setup(frage: LeiterFrage = testFrage, seed = 1) {
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(seed) };
  const state = {
    ...(affenleiterPlugin.init(spieler, content, ctx) as AffenleiterState),
    frage,
  };
  return { clock, ctx, state };
}

function sortierung(
  playerId: string,
  reihenfolge: number[],
  atServerTime: number,
  type: "sortierung" | "einloggen" = "einloggen",
): PlayerAction<{ type: "sortierung" | "einloggen"; reihenfolge: number[] }> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type, reihenfolge },
    atServerTime,
  };
}

describe("affenleiter: Scoring-Goldens (§2.4, Grundwert 250)", () => {
  it("komplett richtig = 375 (×1,5) + voller Speed-Bonus 130 bei 6 s ⇒ 505 MM", () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 0, 1], 6_000),
      ctx,
    ) as AffenleiterState;
    s = { ...s, finished: true };
    // speedBonus(250, 6000, 30000) = 250 × 0,5 × 1 = 125 ⇒ auf 10er gerundet 130.
    expect(affenleiterPlugin.scores(s)[spieler[0]]).toBe(505);
  });

  it("komplett richtig zur Halbzeit (15 s): 375 + 80 Speed-Bonus ⇒ 455 MM", () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 0, 1], 15_000),
      ctx,
    ) as AffenleiterState;
    s = { ...s, finished: true };
    // speedBonus: 125 × (15000/24000) = 78,125 ⇒ 80.
    expect(affenleiterPlugin.scores(s)[spieler[0]]).toBe(455);
  });

  it("Teilpunkte: 2 richtige Sprossen = 130, 1 richtige = 60, 0 = 0 (auf 10er gerundet)", () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 1, 0], 5_000),
      ctx,
    ) as AffenleiterState;
    s = affenleiterPlugin.reduce(s, sortierung("p2", [2, 0, 1, 3], 5_000), ctx) as AffenleiterState;
    s = { ...s, finished: true };
    const scores = affenleiterPlugin.scores(s);
    expect(scores[spieler[0]]).toBe(130); // 2 × 62,5 = 125 ⇒ 130
    expect(scores[spieler[1]]).toBe(60); // 1 × 62,5 = 62,5 ⇒ 60
    const st = { ...s };
    st.abgaben = {
      ...st.abgaben,
      p2: { reihenfolge: [3, 2, 1, 0], eingeloggt: true, atMs: 5_000 },
    };
    expect(affenleiterPlugin.scores(st)[spieler[1]]).toBe(0); // 0 richtige Sprossen
  });

  it("EASY-Frage: Perfekt bei 2 s = 150 + 50 Speed-Bonus ⇒ 200 MM", () => {
    const { ctx, state } = setup({ ...testFrage, schwierigkeit: "easy" });
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 0, 1], 2_000),
      ctx,
    ) as AffenleiterState;
    s = { ...s, finished: true };
    expect(affenleiterPlugin.scores(s)[spieler[0]]).toBe(200);
  });

  it("kein Speed-Bonus ohne Perfekt — Teilpunkte sind zeitunabhängig", () => {
    const { ctx, state } = setup();
    const frueh = affenleiterPlugin.reduce(state, sortierung("p1", [2, 3, 1, 0], 500), ctx);
    const spaet = affenleiterPlugin.reduce(state, sortierung("p1", [2, 3, 1, 0], 29_000), ctx);
    expect(
      affenleiterPlugin.scores({ ...(frueh as AffenleiterState), finished: true })[spieler[0]],
    ).toBe(
      affenleiterPlugin.scores({ ...(spaet as AffenleiterState), finished: true })[spieler[0]],
    );
  });
});

describe("affenleiter: Startreihenfolge (serverseitig pro Spieler gemischt)", () => {
  it("ist NIE die Lösung (sonst gäbe es Gratis-Perfekt ohne Abgabe) — 200 Seeds", () => {
    const clock = createTestClock(0);
    for (let seed = 1; seed <= 200; seed++) {
      const s = affenleiterPlugin.init(spieler, content, {
        clock,
        rng: createRng(seed),
      }) as AffenleiterState;
      for (const p of spieler) {
        expect(s.startReihenfolgen[p]).not.toEqual([...s.frage.korrektReihenfolge]);
      }
    }
  });

  it("keine Abgabe = aktueller (Start-)Stand zählt — Teilpunkte möglich, Perfekt nie", () => {
    const { clock, ctx, state } = setup();
    clock.advance(30_001);
    const s = affenleiterPlugin.tick(state, ctx) as AffenleiterState;
    expect(s.finished).toBe(true);
    const scores = affenleiterPlugin.scores(s);
    for (const p of spieler) {
      const anzahl = s.startReihenfolgen[p].filter(
        (e, i) => e === testFrage.korrektReihenfolge[i],
      ).length;
      expect(anzahl).toBeLessThan(4);
      expect(scores[p]).toBe(Math.round((anzahl * 250) / 4 / 10) * 10);
    }
  });

  it("ist deterministisch per Seed (gleicher Seed ⇒ gleiche Mischung + Frage)", () => {
    const clock = createTestClock(0);
    const a = affenleiterPlugin.init(spieler, content, { clock, rng: createRng(42) });
    const b = affenleiterPlugin.init(spieler, content, { clock, rng: createRng(42) });
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  it("wiederholt im Match keine Pool-Frage (Platzhalter-Nummern 1..3)", () => {
    const clock = createTestClock(0);
    const rng = createRng(1);
    const ids = [1, 2, 3].map((n) => {
      const slice: ContentSlice = { questions: [{ ...dummyQuestion, id: `q_platzhalter_${n}` }] };
      const s = affenleiterPlugin.init(spieler, slice, { clock, rng }) as AffenleiterState;
      return s.frage.id;
    });
    expect(new Set(ids).size).toBe(3);
  });
});

describe("affenleiter: Eingabe-Validierung + Locks", () => {
  it("verwirft Nicht-Permutationen (Doppel-Indizes, falsche Länge, Müll)", () => {
    const { ctx, state } = setup();
    for (const kaputt of [[0, 0, 1, 2], [0, 1, 2], [0, 1, 2, 3, 3], [0, 1, 2, 9], "abc"]) {
      const s = affenleiterPlugin.reduce(
        state,
        sortierung("p1", kaputt as number[], 1_000),
        ctx,
      ) as AffenleiterState;
      expect(s.abgaben.p1).toBeUndefined();
    }
  });

  it("Einloggen rastet ein, Zwischenstände davor zählen (letzter Stand)", () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [1, 0, 2, 3], 1_000, "sortierung"),
      ctx,
    ) as AffenleiterState;
    s = affenleiterPlugin.reduce(s, sortierung("p1", [2, 3, 0, 1], 2_000), ctx) as AffenleiterState;
    s = affenleiterPlugin.reduce(
      s,
      sortierung("p1", [3, 2, 1, 0], 3_000, "sortierung"),
      ctx,
    ) as AffenleiterState;
    expect(s.abgaben.p1.reihenfolge).toEqual([2, 3, 0, 1]); // nach Einloggen gesperrt
    expect(s.abgaben.p1.eingeloggt).toBe(true);
  });

  it("verwirft Abgaben nach dem Gnadenfenster (+400 ms)", () => {
    const { ctx, state } = setup();
    const zuSpaet = affenleiterPlugin.reduce(state, sortierung("p1", [2, 3, 0, 1], 30_401), ctx);
    expect((zuSpaet as AffenleiterState).abgaben.p1).toBeUndefined();
    const geradeNoch = affenleiterPlugin.reduce(state, sortierung("p1", [2, 3, 0, 1], 30_399), ctx);
    expect((geradeNoch as AffenleiterState).abgaben.p1).toBeDefined();
  });
});

describe("affenleiter: Rundenende, Disconnect, Leak-Schutz", () => {
  it("endet, wenn alle eingeloggt haben — AFK-Affen blockieren nicht", () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 0, 1], 1_000),
      ctx,
    ) as AffenleiterState;
    s = affenleiterPlugin.tick(s, ctx) as AffenleiterState;
    expect(s.finished).toBe(false);
    s = affenleiterPlugin.onDisconnect(s, spieler[1], ctx) as AffenleiterState;
    s = affenleiterPlugin.tick(s, ctx) as AffenleiterState;
    expect(s.finished).toBe(true);
    // Der AFK-Affe wird mit seinem Start-Stand gewertet (0 MM ist möglich, keine Strafe).
    expect(affenleiterPlugin.scores(s)[spieler[1]]).toBeGreaterThanOrEqual(0);
  });

  it("verrät Lösung + Auflösungs-Werte NICHT vor der Auflösung (GM sieht sie immer)", () => {
    const { state } = setup();
    const playerView = JSON.stringify(affenleiterPlugin.viewFor(state, "player", spieler[0]));
    const screenView = JSON.stringify(affenleiterPlugin.viewFor(state, "screen"));
    expect(playerView).not.toContain("korrektReihenfolge");
    expect(playerView).not.toContain("aufloesungWerte");
    expect(screenView).not.toContain("korrektReihenfolge");
    const gmView = affenleiterPlugin.viewFor(state, "gm") as { korrektReihenfolge: number[] };
    expect([...gmView.korrektReihenfolge]).toEqual([2, 3, 0, 1]);
  });

  it("Auflösung liefert Sprossen-Flags + Deltas für die Leiter-Animation", () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 1, 0], 5_000),
      ctx,
    ) as AffenleiterState;
    s = { ...s, finished: true };
    const view = affenleiterPlugin.viewFor(s, "screen") as {
      aufloesung: {
        perPlayer: { playerId: string; richtigPositionen: boolean[]; delta: number }[];
      };
    };
    const p1 = view.aufloesung.perPlayer.find((r) => r.playerId === "p1")!;
    expect(p1.richtigPositionen).toEqual([true, true, false, false]);
    expect(p1.delta).toBe(130);
  });

  it('outcomes(): Streak nur bei Komplett-Richtig — Teil-Kette gilt als „falsch"', () => {
    const { ctx, state } = setup();
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 0, 1], 5_000),
      ctx,
    ) as AffenleiterState;
    s = affenleiterPlugin.reduce(s, sortierung("p2", [2, 3, 1, 0], 6_000), ctx) as AffenleiterState;
    s = { ...s, finished: true };
    const outcomes = affenleiterPlugin.outcomes!(s);
    expect(outcomes[spieler[0]]).toEqual({ correct: true, nachMs: 5_000 }); // perfekt
    expect(outcomes[spieler[1]]).toEqual({ correct: false, nachMs: 6_000 }); // 2/4 ⇒ Kette reißt
  });

  it("hält den State JSON-serialisierbar und mutiert Inputs nie", () => {
    const { ctx, state } = setup();
    const vorher = JSON.stringify(state);
    const s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [2, 3, 0, 1], 900),
      ctx,
    ) as AffenleiterState;
    expect(JSON.stringify(state)).toBe(vorher); // pure
    const kopie = JSON.parse(JSON.stringify(s)) as AffenleiterState;
    expect(affenleiterPlugin.scores({ ...kopie, finished: true })).toEqual(
      affenleiterPlugin.scores({ ...s, finished: true }),
    );
  });
});

// ---------- Wächter (Eval 5): echte sortier-Fragen aus dem Content-Pool ----------
describe("affenleiter: Content-Anbindung (kind sortier)", () => {
  const sortierFrage: Question = {
    id: "q_sortier_planeten",
    kind: "sortier",
    category: "weltraum",
    difficulty: "medium",
    text: "Sortiere die Planeten — den sonnennächsten nach unten!",
    options: ["Erde", "Merkur", "Mars", "Venus"],
    answer: 0,
    erklaerung: "Merkur < Venus < Erde < Mars.",
    sortier: {
      korrektReihenfolge: [1, 3, 0, 2],
      aufloesungWerte: ["3. Platz", "1. Platz", "4. Platz", "2. Platz"],
    },
  };

  function setupContent(frage: Question, seed = 1) {
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(seed) };
    const state = affenleiterPlugin.init(spieler, { questions: [frage] }, ctx) as AffenleiterState;
    return { clock, ctx, state };
  }

  it("init liest die Pool-Frage: Elemente aus options, Lösung aus sortier", () => {
    const { state } = setupContent(sortierFrage);
    expect(state.frage.id).toBe("q_sortier_planeten");
    expect([...state.frage.elemente]).toEqual(["Erde", "Merkur", "Mars", "Venus"]);
    expect([...state.frage.korrektReihenfolge]).toEqual([1, 3, 0, 2]);
    expect([...state.frage.aufloesungWerte]).toEqual([
      "3. Platz",
      "1. Platz",
      "4. Platz",
      "2. Platz",
    ]);
    expect(state.frage.schwierigkeit).toBe("medium");
    // Startreihenfolge NIE die Lösung (auch bei Pool-Fragen):
    for (const p of spieler) expect(state.startReihenfolgen[p]).not.toEqual([1, 3, 0, 2]);
  });

  it("Scoring der Pool-Frage: Perfekt = Grundwert ×1,5 + Speed-Bonus (Golden 505)", () => {
    const { ctx, state } = setupContent(sortierFrage);
    let s = affenleiterPlugin.reduce(
      state,
      sortierung("p1", [1, 3, 0, 2], 6_000),
      ctx,
    ) as AffenleiterState;
    s = { ...s, finished: true };
    expect(affenleiterPlugin.scores(s)[spieler[0]]).toBe(505);
    expect(affenleiterPlugin.outcomes!(s)[spieler[0]]).toEqual({ correct: true, nachMs: 6_000 });
  });

  it("choice4-Slice (z. B. GM-Override): Fallback auf den eingebauten Pool", () => {
    const { state } = setupContent(dummyQuestion);
    expect(state.frage.id).not.toBe("q_dummy");
    expect(state.frage.elemente).toHaveLength(4);
  });
});
