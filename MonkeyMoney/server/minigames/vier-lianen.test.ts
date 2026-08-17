// Vier-Lianen-Plugin: Antwort-Lock, Gnadenfenster, Leak-Schutz, Scores.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import { FRAGE_TIMER_MS } from "../../shared/money";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import { vierLianenPlugin, type VierLianenState } from "./vier-lianen/index";

const frage: Question = {
  id: "q_test",
  kind: "choice4",
  category: "test",
  difficulty: "easy",
  text: "Testfrage?",
  options: ["A", "B", "C", "D"],
  answer: 2,
  erklaerung: "C stimmt.",
};

const content: ContentSlice = { questions: [frage] };
const spieler = [asPlayerId("p1"), asPlayerId("p2")];

function setup(startMs = 0) {
  const clock = createTestClock(startMs);
  const ctx = { clock, rng: createRng(1) };
  const state = vierLianenPlugin.init(spieler, content, ctx) as VierLianenState;
  return { clock, ctx, state };
}

function antwortAktion(
  playerId: string,
  choice: number,
  atServerTime: number,
): PlayerAction<{ type: "answer"; choice: 0 | 1 | 2 | 3 }> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "answer", choice: choice as 0 | 1 | 2 | 3 },
    atServerTime,
  };
}

describe("vier-lianen: Antwort-Lock", () => {
  it("nimmt pro Spieler nur die ERSTE Antwort (kein Umentscheiden)", () => {
    const { ctx, state } = setup();
    let s = vierLianenPlugin.reduce(state, antwortAktion("p1", 2, 1_000), ctx) as VierLianenState;
    s = vierLianenPlugin.reduce(s, antwortAktion("p1", 0, 2_000), ctx) as VierLianenState;
    expect(s.answers.p1.choice).toBe(2);
  });

  it("verwirft Antworten nach dem Gnadenfenster (+400 ms)", () => {
    const { ctx, state } = setup();
    const zuSpaet = vierLianenPlugin.reduce(
      state,
      antwortAktion("p1", 2, FRAGE_TIMER_MS.easy + 401),
      ctx,
    ) as VierLianenState;
    expect(zuSpaet.answers.p1).toBeUndefined();
    const geradeNoch = vierLianenPlugin.reduce(
      state,
      antwortAktion("p1", 2, FRAGE_TIMER_MS.easy + 399),
      ctx,
    ) as VierLianenState;
    expect(geradeNoch.answers.p1).toBeDefined();
  });

  it("ist fertig, sobald alle geantwortet haben ODER der Timer abläuft", () => {
    const { clock, ctx, state } = setup();
    let s = vierLianenPlugin.reduce(state, antwortAktion("p1", 1, 500), ctx) as VierLianenState;
    s = vierLianenPlugin.tick(s, ctx) as VierLianenState;
    expect(vierLianenPlugin.isFinished(s)).toBe(false);
    s = vierLianenPlugin.reduce(s, antwortAktion("p2", 2, 700), ctx) as VierLianenState;
    s = vierLianenPlugin.tick(s, ctx) as VierLianenState;
    expect(vierLianenPlugin.isFinished(s)).toBe(true);

    const { ctx: ctx2, state: frisch, clock: clock2 } = setup();
    void clock;
    clock2.advance(FRAGE_TIMER_MS.easy + 1);
    const nachTimeout = vierLianenPlugin.tick(frisch, ctx2) as VierLianenState;
    expect(vierLianenPlugin.isFinished(nachTimeout)).toBe(true);
  });
});

describe("vier-lianen: Leak-Schutz (viewFor serverseitig)", () => {
  it("verrät Spielern und Screen die richtige Antwort NICHT vor der Auflösung", () => {
    const { state } = setup();
    const playerView = JSON.stringify(vierLianenPlugin.viewFor(state, "player", spieler[0]));
    const screenView = JSON.stringify(vierLianenPlugin.viewFor(state, "screen"));
    expect(playerView).not.toContain("correctIndex");
    expect(playerView).not.toContain('aufloesung":{'); // null ist ok, Inhalt nicht
    expect(screenView).not.toContain("correctIndex");
  });

  it("zeigt dem GM die richtige Antwort IMMER (Spickzettel)", () => {
    const { state } = setup();
    const gmView = vierLianenPlugin.viewFor(state, "gm") as { correctIndex: number };
    expect(gmView.correctIndex).toBe(2);
  });
});

describe("vier-lianen: Scores", () => {
  it("vergibt 100 MM Grundwert + Speed-Bonus nur an Richtige", () => {
    const { ctx, state } = setup();
    let s = vierLianenPlugin.reduce(state, antwortAktion("p1", 2, 1_000), ctx) as VierLianenState;
    s = vierLianenPlugin.reduce(s, antwortAktion("p2", 0, 1_000), ctx) as VierLianenState;
    s = { ...s, finished: true };
    const scores = vierLianenPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(150); // 100 + voller Speed-Bonus 50
    expect(scores[asPlayerId("p2")]).toBe(0);
  });

  it("hält den State JSON-serialisierbar (Contract-Grundlage)", () => {
    const { ctx, state } = setup();
    const s = vierLianenPlugin.reduce(state, antwortAktion("p1", 3, 900), ctx) as VierLianenState;
    const kopie = JSON.parse(JSON.stringify(s)) as VierLianenState;
    expect(vierLianenPlugin.scores(kopie)).toEqual(vierLianenPlugin.scores(s));
  });
});
