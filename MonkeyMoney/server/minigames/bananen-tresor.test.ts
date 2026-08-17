// Bananen-Tresor-Plugin: Festwert-Goldens, Volltreffer, Gleichstand (Competition-
// Ranking), letzter Slider-Stand, Slider-Kappe, Disconnect, Leak-Schutz, Seed.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import type { TresorFrage } from "../../shared/minigames/bananen-tresor.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import { bananenTresorPlugin, type BananenTresorState } from "./bananen-tresor/index";

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

const testFrage: TresorFrage = {
  id: "tresor_test",
  text: "Wie hoch?",
  einheit: "m",
  richtwert: 100,
  eingabeMin: 0,
  eingabeMax: 1000,
  skala: "linear",
  variante: "standard",
  erklaerung: "100 m.",
};

const spieler = [asPlayerId("p1"), asPlayerId("p2"), asPlayerId("p3"), asPlayerId("p4")];

function setup(frage: TresorFrage = testFrage, seed = 1) {
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(seed) };
  // Pool-Wahl ist rng-gesteuert; für Goldens wird die Frage deterministisch ersetzt.
  const state = {
    ...(bananenTresorPlugin.init(spieler, content, ctx) as BananenTresorState),
    frage,
  };
  return { clock, ctx, state };
}

function tipp(
  playerId: string,
  wert: number,
  atServerTime: number,
  type: "tipp" | "einloggen" = "einloggen",
): PlayerAction<{ type: "tipp" | "einloggen"; wert: number }> {
  return { kind: "player", playerId: asPlayerId(playerId), action: { type, wert }, atServerTime };
}

function scoresNach(
  state: BananenTresorState,
  ctx: { clock: { now(): number }; rng: ReturnType<typeof createRng> },
  tipps: Parameters<typeof bananenTresorPlugin.reduce>[1][],
) {
  let s = state;
  for (const t of tipps) s = bananenTresorPlugin.reduce(s, t, ctx) as BananenTresorState;
  return {
    state: { ...s, finished: true },
    scores: bananenTresorPlugin.scores({ ...s, finished: true }),
  };
}

describe("bananen-tresor: Festwert-Goldens (§2.3)", () => {
  it('staffelt 400/250/150 nach Nähe, alle Übrigen bekommen 50 („Schätzen lohnt immer")', () => {
    const { ctx, state } = setup();
    const { scores } = scoresNach(state, ctx, [
      tipp("p1", 98, 1_000), // Distanz 2 ⇒ Platz 1
      tipp("p2", 107, 2_000), // Distanz 7 ⇒ Platz 2
      tipp("p3", 90, 3_000), // Distanz 10 ⇒ Platz 3
      tipp("p4", 130, 4_000), // Distanz 30 ⇒ Rest-Festwert
    ]);
    expect(scores[spieler[0]]).toBe(400);
    expect(scores[spieler[1]]).toBe(250);
    expect(scores[spieler[2]]).toBe(150);
    expect(scores[spieler[3]]).toBe(50);
  });

  it("Volltreffer exakt = 1.000 MM statt Platz-1-Festwert", () => {
    const { ctx, state } = setup();
    const { scores } = scoresNach(state, ctx, [
      tipp("p1", 100, 1_000),
      tipp("p2", 105, 2_000),
      tipp("p3", 110, 3_000),
    ]);
    expect(scores[spieler[0]]).toBe(1000);
    expect(scores[spieler[1]]).toBe(250);
    expect(scores[spieler[2]]).toBe(150);
    expect(scores[spieler[3]]).toBe(0); // unbewegt = keine Wertung
  });

  it("HARD-Variante (Marathon-Spätrunde): 800/500/300/100, Volltreffer 2.000", () => {
    const { ctx, state } = setup({ ...testFrage, variante: "hard" });
    const { scores } = scoresNach(state, ctx, [
      tipp("p1", 100, 1_000),
      tipp("p2", 105, 2_000),
      tipp("p3", 120, 3_000),
      tipp("p4", 150, 4_000),
    ]);
    expect(scores[spieler[0]]).toBe(2000);
    expect(scores[spieler[1]]).toBe(500);
    expect(scores[spieler[2]]).toBe(300);
    expect(scores[spieler[3]]).toBe(100);
  });

  it("Gleichstand: gleiche Distanz = beide der bessere Platz, der nächste entfällt", () => {
    const { ctx, state } = setup();
    const { scores } = scoresNach(state, ctx, [
      tipp("p1", 95, 1_000), // Distanz 5 ⇒ geteilter Platz 1
      tipp("p2", 105, 2_000), // Distanz 5 ⇒ geteilter Platz 1
      tipp("p3", 110, 3_000), // Distanz 10 ⇒ Platz 3 (Platz 2 entfällt!)
      tipp("p4", 130, 4_000), // Distanz 30 ⇒ Rest
    ]);
    expect(scores[spieler[0]]).toBe(400);
    expect(scores[spieler[1]]).toBe(400);
    expect(scores[spieler[2]]).toBe(150);
    expect(scores[spieler[3]]).toBe(50);
  });
});

describe("bananen-tresor: Slider-Verhalten", () => {
  it("letzter bewegter Slider-Stand zählt auch OHNE Einloggen", () => {
    const { ctx, state } = setup();
    const { scores, state: s } = scoresNach(state, ctx, [
      tipp("p1", 500, 1_000, "tipp"),
      tipp("p1", 98, 2_000, "tipp"), // nur bewegt, nie eingeloggt
      tipp("p2", 110, 3_000),
    ]);
    expect(scores[spieler[0]]).toBe(400); // Distanz 2 schlägt Distanz 10
    const view = bananenTresorPlugin.viewFor(s, "screen") as {
      aufloesung: { perPlayer: { playerId: string; tipp: number | null }[] };
    };
    expect(view.aufloesung.perPlayer.find((r) => r.playerId === "p1")?.tipp).toBe(98);
  });

  it("Einloggen rastet ein: weitere Tipps werden ignoriert", () => {
    const { ctx, state } = setup();
    let s = bananenTresorPlugin.reduce(state, tipp("p1", 100, 1_000), ctx) as BananenTresorState;
    s = bananenTresorPlugin.reduce(s, tipp("p1", 500, 2_000, "tipp"), ctx) as BananenTresorState;
    expect(s.tipps.p1.wert).toBe(100);
    expect(s.tipps.p1.eingeloggt).toBe(true);
  });

  it("Slider-Kappe: Werte werden hart auf die Frage-Spanne geklemmt, Müll verworfen", () => {
    const { ctx, state } = setup();
    let s = bananenTresorPlugin.reduce(
      state,
      tipp("p1", 99_999, 1_000, "tipp"),
      ctx,
    ) as BananenTresorState;
    expect(s.tipps.p1.wert).toBe(1000); // eingabeMax
    s = bananenTresorPlugin.reduce(s, tipp("p2", -50, 1_000, "tipp"), ctx) as BananenTresorState;
    expect(s.tipps.p2.wert).toBe(0); // eingabeMin
    const kaputt = bananenTresorPlugin.reduce(s, tipp("p3", Number.NaN, 1_000), ctx);
    expect((kaputt as BananenTresorState).tipps.p3).toBeUndefined();
  });

  it("verwirft Tipps nach dem Gnadenfenster (+400 ms)", () => {
    const { ctx, state } = setup();
    const zuSpaet = bananenTresorPlugin.reduce(state, tipp("p1", 100, 20_401), ctx);
    expect((zuSpaet as BananenTresorState).tipps.p1).toBeUndefined();
    const geradeNoch = bananenTresorPlugin.reduce(state, tipp("p1", 100, 20_399), ctx);
    expect((geradeNoch as BananenTresorState).tipps.p1).toBeDefined();
  });
});

describe("bananen-tresor: Rundenende + Disconnect", () => {
  it("endet, wenn ALLE eingeloggt haben — AFK-Affen blockieren nicht", () => {
    const { ctx, state } = setup();
    let s = bananenTresorPlugin.reduce(state, tipp("p1", 90, 1_000), ctx) as BananenTresorState;
    s = bananenTresorPlugin.reduce(s, tipp("p2", 95, 1_000), ctx) as BananenTresorState;
    s = bananenTresorPlugin.reduce(s, tipp("p3", 105, 1_000), ctx) as BananenTresorState;
    s = bananenTresorPlugin.tick(s, ctx) as BananenTresorState;
    expect(s.finished).toBe(false); // p4 fehlt noch
    s = bananenTresorPlugin.onDisconnect(s, spieler[3], ctx) as BananenTresorState;
    s = bananenTresorPlugin.tick(s, ctx) as BananenTresorState;
    expect(s.finished).toBe(true);
  });

  it("Disconnect nach bewegtem Slider: letzter Stand bleibt gewertet", () => {
    const { clock, ctx, state } = setup();
    let s = bananenTresorPlugin.reduce(
      state,
      tipp("p1", 98, 1_000, "tipp"),
      ctx,
    ) as BananenTresorState;
    s = bananenTresorPlugin.onDisconnect(s, spieler[0], ctx) as BananenTresorState;
    clock.advance(20_001);
    s = bananenTresorPlugin.tick(s, ctx) as BananenTresorState;
    expect(s.finished).toBe(true);
    expect(bananenTresorPlugin.scores(s)[spieler[0]]).toBe(400);
  });
});

describe("bananen-tresor: Leak-Schutz + Contract", () => {
  it("verrät Spielern und Screen den Richtwert NICHT vor der Auflösung", () => {
    const { state } = setup();
    const playerView = JSON.stringify(bananenTresorPlugin.viewFor(state, "player", spieler[0]));
    const screenView = JSON.stringify(bananenTresorPlugin.viewFor(state, "screen"));
    expect(playerView).not.toContain("richtwert");
    expect(screenView).not.toContain("richtwert");
    // GM-Spickzettel sieht Richtwert + Live-Tipps immer:
    const gmView = bananenTresorPlugin.viewFor(state, "gm") as { richtwert: number };
    expect(gmView.richtwert).toBe(100);
  });

  it("Screen sieht WER getippt hat, aber keine Werte (Tipps erscheinen gleichzeitig)", () => {
    const { ctx, state } = setup();
    const s = bananenTresorPlugin.reduce(
      state,
      tipp("p1", 98, 1_000, "tipp"),
      ctx,
    ) as BananenTresorState;
    const view = bananenTresorPlugin.viewFor(s, "screen") as {
      answeredCount: number;
      abgegeben: { playerId: string; eingeloggt: boolean }[];
    };
    expect(view.answeredCount).toBe(1);
    expect(view.abgegeben).toEqual([{ playerId: "p1", eingeloggt: false }]);
    expect(JSON.stringify(view)).not.toContain("98");
  });

  it("wählt die Pool-Frage deterministisch per Seed (Determinismus-Vertrag)", () => {
    const clock = createTestClock(0);
    const a = bananenTresorPlugin.init(spieler, content, { clock, rng: createRng(7) });
    const b = bananenTresorPlugin.init(spieler, content, { clock, rng: createRng(7) });
    const c = bananenTresorPlugin.init(spieler, content, { clock, rng: createRng(8) });
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    expect((a as BananenTresorState).frage.id).not.toBe((c as BananenTresorState).frage.id);
  });

  it("wiederholt im Match keine Pool-Frage (Platzhalter-Nummern 1..3)", () => {
    const clock = createTestClock(0);
    const rng = createRng(1);
    const ids = [1, 2, 3].map((n) => {
      const slice: ContentSlice = { questions: [{ ...dummyQuestion, id: `q_platzhalter_${n}` }] };
      const s = bananenTresorPlugin.init(spieler, slice, { clock, rng }) as BananenTresorState;
      return s.frage.id;
    });
    expect(new Set(ids).size).toBe(3);
  });

  it('outcomes(): Schätzen kennt kein „falsch" — Tipp = richtig, kein Tipp = null', () => {
    const { ctx, state } = setup();
    let s = bananenTresorPlugin.reduce(state, tipp("p1", 300, 1_000), ctx) as BananenTresorState;
    s = { ...s, finished: true };
    const outcomes = bananenTresorPlugin.outcomes!(s);
    expect(outcomes[spieler[0]]).toEqual({ correct: true, nachMs: 1_000 });
    expect(outcomes[spieler[1]]).toEqual({ correct: null });
  });

  it("hält den State JSON-serialisierbar und mutiert Inputs nie", () => {
    const { ctx, state } = setup();
    const vorher = JSON.stringify(state);
    const s = bananenTresorPlugin.reduce(state, tipp("p1", 98, 1_000), ctx) as BananenTresorState;
    expect(JSON.stringify(state)).toBe(vorher); // pure
    const kopie = JSON.parse(JSON.stringify(s)) as BananenTresorState;
    expect(bananenTresorPlugin.scores({ ...kopie, finished: true })).toEqual(
      bananenTresorPlugin.scores({ ...s, finished: true }),
    );
  });
});

// ---------- Wächter (Eval 5): echte schaetz-Fragen aus dem Content-Pool ----------
describe("bananen-tresor: Content-Anbindung (kind schaetz)", () => {
  const schaetzFrage: Question = {
    id: "q_schaetz_mond",
    kind: "schaetz",
    category: "weltraum",
    difficulty: "medium",
    text: "In welchem Jahr betrat der erste Mensch den Mond?",
    options: [],
    answer: 0,
    erklaerung: "1969 (Apollo 11).",
    schaetz: {
      richtwert: 1969,
      einheit: "Jahr",
      toleranzProzent: 1,
      toleranzAbsolut: 3,
      eingabeMin: 1900,
      eingabeMax: 2020,
      skala: "linear",
    },
  };

  function setupContent(frage: Question, seed = 1) {
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(seed) };
    const state = bananenTresorPlugin.init(
      spieler,
      { questions: [frage] },
      ctx,
    ) as BananenTresorState;
    return { clock, ctx, state };
  }

  it("init liest die Pool-Frage: Toleranz/Range aus der Frage, KEIN eingebauter Pool", () => {
    const { state } = setupContent(schaetzFrage);
    expect(state.frage.id).toBe("q_schaetz_mond");
    expect(state.frage.richtwert).toBe(1969);
    expect(state.frage.eingabeMin).toBe(1900);
    expect(state.frage.eingabeMax).toBe(2020);
    expect(state.frage.toleranzAbsolut).toBe(3);
    expect(state.frage.variante).toBe("standard");
  });

  it("hard-/ultrahard-Fragen spielen die HARD-Festwerte", () => {
    const { state } = setupContent({ ...schaetzFrage, difficulty: "hard" });
    expect(state.frage.variante).toBe("hard");
    const { state: ultra } = setupContent({ ...schaetzFrage, difficulty: "ultrahard" });
    expect(ultra.frage.variante).toBe("hard");
  });

  it("toleranz_absolut schlägt toleranz_prozent (Jahreszahl-Fix): ±3 statt ±20", () => {
    const { ctx, state } = setupContent(schaetzFrage);
    let s = bananenTresorPlugin.reduce(state, tipp("p1", 1972, 1_000), ctx) as BananenTresorState;
    s = bananenTresorPlugin.reduce(s, tipp("p2", 1974, 2_000), ctx) as BananenTresorState;
    s = { ...s, finished: true };
    const scores = bananenTresorPlugin.scores(s);
    expect(scores[spieler[0]]).toBe(1000); // Distanz 3 = Volltreffer (±3 Jahre)
    expect(scores[spieler[1]]).toBe(250); // Distanz 5: 1 % wären ±19,69 — ABSOLUT gewinnt
  });

  it("ohne toleranz_absolut zählt das Prozent-Fenster weiter", () => {
    const frage: Question = {
      ...schaetzFrage,
      schaetz: {
        richtwert: 200,
        einheit: "m",
        toleranzProzent: 5,
        eingabeMin: 0,
        eingabeMax: 1000,
        skala: "linear",
      },
    };
    const { ctx, state } = setupContent(frage);
    let s = bananenTresorPlugin.reduce(state, tipp("p1", 209, 1_000), ctx) as BananenTresorState;
    s = bananenTresorPlugin.reduce(s, tipp("p2", 240, 2_000), ctx) as BananenTresorState;
    s = { ...s, finished: true };
    const scores = bananenTresorPlugin.scores(s);
    expect(scores[spieler[0]]).toBe(1000); // Distanz 9 ≤ 5 % von 200 (=10)
    expect(scores[spieler[1]]).toBe(250); // Distanz 40 > 10
  });

  it("choice4-Slice (z. B. GM-Override): Fallback auf den eingebauten Pool", () => {
    const { state } = setupContent(dummyQuestion);
    expect(state.frage.id).not.toBe("q_dummy");
    expect(state.frage.richtwert).toBeDefined();
  });
});
