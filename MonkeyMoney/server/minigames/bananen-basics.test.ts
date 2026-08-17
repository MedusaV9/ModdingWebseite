// Bananen-Basics: Scoring-Goldens (Grundwert + Speed-Knick §3.1), Antwort-Lock,
// Spätantwort-Gnade, Joker-Hooks (50:50 / removeOne / Rückgaberecht), Mods
// (timerFaktor, Insider, Maßanzug), Seed-Determinismus und View-Leak-Wachen.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import { FRAGE_TIMER_MS, fragenGewinn } from "../../shared/money";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { JokerAction, PlayerAction } from "./_api/plugin";
import { bananenBasicsPlugin, type BananenBasicsState } from "./bananen-basics/index";

const P1 = asPlayerId("p1");
const P2 = asPlayerId("p2");
const P3 = asPlayerId("p3");

const frage: Question = {
  id: "q_bb_1",
  kind: "choice4",
  category: "affen",
  difficulty: "medium",
  text: "Welche Farbe hat eine reife Banane?",
  options: ["Blau", "Gelb", "Lila", "Karo"],
  answer: 1,
  erklaerung: "Gelb natürlich.",
};

function setup(spielerIds: string[] = ["p1", "p2", "p3"], seed = 1, mods?: ContentSlice["mods"]) {
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(seed) };
  const content: ContentSlice = mods ? { questions: [frage], mods } : { questions: [frage] };
  const spieler = spielerIds.map(asPlayerId);
  const state = bananenBasicsPlugin.init(spieler, content, ctx) as BananenBasicsState;
  return { clock, ctx, state, spieler };
}

function antwort(
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

describe("bananen-basics: Scoring-Goldens (§2.1/§3.1)", () => {
  it("MEDIUM bei 20 % der Zeit = 380 (250 + voller Speed-Bonus 130); falsch/keine Antwort = 0", () => {
    const { clock, ctx, state } = setup();
    expect(state.timerMs).toBe(FRAGE_TIMER_MS.medium);
    let s = bananenBasicsPlugin.reduce(state, antwort("p1", 1, 3_000), ctx) as BananenBasicsState;
    s = bananenBasicsPlugin.reduce(s, antwort("p2", 0, 3_000), ctx) as BananenBasicsState;
    clock.advance(FRAGE_TIMER_MS.medium + 1);
    s = bananenBasicsPlugin.tick(s, ctx) as BananenBasicsState;
    const scores = bananenBasicsPlugin.scores(s);
    expect(fragenGewinn("medium", 3_000, 15_000)).toBe(380); // Design-Golden
    expect(scores[P1]).toBe(380);
    expect(scores[P2]).toBe(0); // falsch = 0, KEINE Strafe (Opener §2.1)
    expect(scores[P3]).toBe(0); // keine Antwort = 0
    const outcomes = bananenBasicsPlugin.outcomes!(s);
    expect(outcomes[P1]).toMatchObject({ correct: true, nachMs: 3_000 });
    expect(outcomes[P2].correct).toBe(false);
    expect(outcomes[P3].correct).toBeNull();
  });

  it("Antwort auf den letzten Drücker = nur der Grundwert (Speed-Bonus 0)", () => {
    const { ctx, state } = setup();
    let s = bananenBasicsPlugin.reduce(
      state,
      antwort("p1", 1, FRAGE_TIMER_MS.medium),
      ctx,
    ) as BananenBasicsState;
    s = { ...s, finished: true };
    expect(bananenBasicsPlugin.scores(s)[P1]).toBe(250);
  });

  it("meta: Streak-Flag AN (Engine multipliziert), Maßanzug-Flag AN, alle 3 Joker deklariert", () => {
    expect(bananenBasicsPlugin.meta.streak).toBe(true);
    expect(bananenBasicsPlugin.meta.perSpielerFragen).toBe(true);
    expect(bananenBasicsPlugin.meta.jokerAktionen).toEqual([
      "fiftyFifty",
      "removeOne",
      "secondTry",
    ]);
  });
});

describe("bananen-basics: Antwort-Lock + Spätantwort + Finish", () => {
  it("die erste Antwort rastet ein — kein Umentscheiden (§2.1)", () => {
    const { ctx, state } = setup();
    const s1 = bananenBasicsPlugin.reduce(
      state,
      antwort("p1", 0, 1_000),
      ctx,
    ) as BananenBasicsState;
    const s2 = bananenBasicsPlugin.reduce(s1, antwort("p1", 1, 2_000), ctx);
    expect(s2).toBe(s1); // unverändert
    expect((s2 as BananenBasicsState).answers.p1.choice).toBe(0);
  });

  it("Spätantwort: bis endsAt + 400 ms Gnade zählt sie, danach wird sie verworfen", () => {
    const { ctx, state } = setup();
    const nochOk = state.endsAt + SPAETANTWORT_GNADE_MS;
    const zaehlt = bananenBasicsPlugin.reduce(state, antwort("p1", 1, nochOk), ctx);
    expect((zaehlt as BananenBasicsState).answers.p1).toBeDefined();
    const zuSpaet = bananenBasicsPlugin.reduce(state, antwort("p1", 1, nochOk + 1), ctx);
    expect(zuSpaet).toBe(state);
  });

  it("fertig, sobald ALLE geantwortet haben ODER der Timer abläuft", () => {
    const { clock, ctx, state, spieler } = setup();
    let s = state;
    for (const p of spieler)
      s = bananenBasicsPlugin.reduce(s, antwort(p, 1, 2_000), ctx) as BananenBasicsState;
    s = bananenBasicsPlugin.tick(s, ctx) as BananenBasicsState;
    expect(bananenBasicsPlugin.isFinished(s)).toBe(true);
    // Timer-Variante:
    const { clock: c2, ctx: ctx2, state: s2 } = setup();
    c2.advance(FRAGE_TIMER_MS.medium + 1);
    expect(
      bananenBasicsPlugin.isFinished(bananenBasicsPlugin.tick(s2, ctx2) as BananenBasicsState),
    ).toBe(true);
    void clock;
  });
});

describe("bananen-basics: Joker-Hooks (§5.1)", () => {
  const joker = (type: JokerAction["type"], playerId: string | null): JokerAction =>
    ({
      kind: "joker",
      type,
      playerId: playerId === null ? null : asPlayerId(playerId),
    }) as JokerAction;

  it("50:50 sperrt GENAU 2 falsche Optionen NUR für diesen Spieler; gesperrte sind nicht wählbar", () => {
    const { ctx, state } = setup();
    const s = bananenBasicsPlugin.reduce(
      state,
      joker("fiftyFifty", "p1"),
      ctx,
    ) as BananenBasicsState;
    expect(s.gesperrt.p1).toHaveLength(2);
    expect(s.gesperrt.p1).not.toContain(frage.answer);
    expect(s.gesperrt.p2).toBeUndefined();
    const gesperrteOption = s.gesperrt.p1[0] as 0 | 1 | 2 | 3;
    expect(bananenBasicsPlugin.reduce(s, antwort("p1", gesperrteOption, 1_000), ctx)).toBe(s);
    // Zweites 50:50: nur noch 1 falsche offen ⇒ No-op (mind. 2 nötig).
    expect(bananenBasicsPlugin.reduce(s, joker("fiftyFifty", "p1"), ctx)).toBe(s);
  });

  it("removeOne mit playerId null = GM-Hint GLOBAL; mindestens 1 falsche bleibt stehen", () => {
    const { ctx, state } = setup();
    let s = bananenBasicsPlugin.reduce(state, joker("removeOne", null), ctx) as BananenBasicsState;
    expect(s.gesperrtGlobal).toHaveLength(1);
    s = bananenBasicsPlugin.reduce(s, joker("removeOne", null), ctx) as BananenBasicsState;
    expect(s.gesperrtGlobal).toHaveLength(2);
    // Dritter Versuch: nur noch 1 falsche offen ⇒ No-op.
    expect(bananenBasicsPlugin.reduce(s, joker("removeOne", null), ctx)).toBe(s);
    expect(s.gesperrtGlobal).not.toContain(frage.answer);
  });

  it("Rückgaberecht: falsche Antwort gelöscht, Option gesperrt — der neue Gewinn ist nur 50 %", () => {
    const { ctx, state } = setup();
    let s = bananenBasicsPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as BananenBasicsState;
    s = bananenBasicsPlugin.reduce(s, joker("secondTry", "p1"), ctx) as BananenBasicsState;
    expect(s.answers.p1).toBeUndefined();
    expect(s.gesperrt.p1).toContain(0);
    expect(s.zweitversuch.p1).toBe(true);
    // Zweiter Versuch richtig auf den letzten Drücker: 250 / 2 → 130 (10er-Rundung).
    s = bananenBasicsPlugin.reduce(
      s,
      antwort("p1", 1, FRAGE_TIMER_MS.medium),
      ctx,
    ) as BananenBasicsState;
    s = { ...s, finished: true };
    expect(bananenBasicsPlugin.scores(s)[P1]).toBe(130);
    expect(bananenBasicsPlugin.outcomes!(s)[P1].zweitversuch).toBe(true);
  });

  it("Rückgaberecht auf eine RICHTIGE Antwort ist ein No-op (kein Bedarf)", () => {
    const { ctx, state } = setup();
    const s = bananenBasicsPlugin.reduce(state, antwort("p1", 1, 1_000), ctx) as BananenBasicsState;
    expect(bananenBasicsPlugin.reduce(s, joker("secondTry", "p1"), ctx)).toBe(s);
  });

  it("Seed-Determinismus: gleicher Seed ⇒ identische 50:50-Sperrungen", () => {
    const a = setup(["p1", "p2"], 42);
    const b = setup(["p1", "p2"], 42);
    const sa = bananenBasicsPlugin.reduce(
      a.state,
      joker("fiftyFifty", "p1"),
      a.ctx,
    ) as BananenBasicsState;
    const sb = bananenBasicsPlugin.reduce(
      b.state,
      joker("fiftyFifty", "p1"),
      b.ctx,
    ) as BananenBasicsState;
    expect(sa.gesperrt.p1).toEqual(sb.gesperrt.p1);
    expect(JSON.stringify(sa)).toBe(JSON.stringify(sb));
  });
});

describe("bananen-basics: Mods (Rad/GM/Maßanzug)", () => {
  it("timerFaktor 0,5 (Halbe Miete) halbiert das Antwortfenster", () => {
    const { state } = setup(["p1", "p2"], 1, { timerFaktor: 0.5 });
    expect(state.timerMs).toBe(FRAGE_TIMER_MS.medium / 2);
    expect(state.endsAt).toBe(FRAGE_TIMER_MS.medium / 2);
  });

  it("Maßanzug: zugewiesener Spieler bekommt SEINE Frage und wird an ihr gemessen", () => {
    const eigene: Question = { ...frage, id: "q_eigen", text: "Eigene Frage?", answer: 3 };
    const { clock, ctx, state } = setup(["p1", "p2"], 1, { fragenProSpieler: { p2: eigene } });
    const view = bananenBasicsPlugin.viewFor(state, "player", asPlayerId("p2")) as { text: string };
    expect(view.text).toBe("Eigene Frage?");
    // p2 antwortet 3 — an der EIGENEN Frage richtig (Basis-Frage: answer 1).
    let s = bananenBasicsPlugin.reduce(state, antwort("p2", 3, 3_000), ctx) as BananenBasicsState;
    s = bananenBasicsPlugin.reduce(s, antwort("p1", 1, 3_000), ctx) as BananenBasicsState;
    clock.advance(FRAGE_TIMER_MS.medium + 1);
    s = bananenBasicsPlugin.tick(s, ctx) as BananenBasicsState;
    expect(bananenBasicsPlugin.scores(s)[P2]).toBe(380);
    expect(bananenBasicsPlugin.outcomes!(s)[P2].correct).toBe(true);
  });

  it("Insider-Tipp: nur die ANDEREN bekommen sichtbarAb = start + Vorsprung", () => {
    const { state } = setup(["p1", "p2"], 1, { insiderPlayerId: "p1", insiderVorsprungMs: 3_000 });
    const insider = bananenBasicsPlugin.viewFor(state, "player", asPlayerId("p1")) as {
      sichtbarAb: number;
    };
    const rest = bananenBasicsPlugin.viewFor(state, "player", asPlayerId("p2")) as {
      sichtbarAb: number;
    };
    const screen = bananenBasicsPlugin.viewFor(state, "screen") as { sichtbarAb: number };
    expect(insider.sichtbarAb).toBe(0);
    expect(rest.sichtbarAb).toBe(3_000);
    expect(screen.sichtbarAb).toBe(3_000);
  });
});

describe("bananen-basics: View-Leak-Wachen", () => {
  it("VOR der Auflösung: kein correctIndex, keine Erklärung in Screen-/Player-Views — GM sieht alles", () => {
    const { state } = setup();
    const screen = JSON.stringify(bananenBasicsPlugin.viewFor(state, "screen"));
    const player = JSON.stringify(bananenBasicsPlugin.viewFor(state, "player", asPlayerId("p1")));
    expect(screen).not.toContain("correctIndex");
    expect(player).not.toContain("correctIndex");
    expect(screen).not.toContain(frage.erklaerung);
    expect(player).not.toContain(frage.erklaerung);
    const gm = bananenBasicsPlugin.viewFor(state, "gm") as { correctIndex: number };
    expect(gm.correctIndex).toBe(frage.answer);
  });

  it("NACH der Auflösung: correctIndex + Deltas + anonymer Zähler stimmen", () => {
    const { ctx, state } = setup(["p1", "p2"]);
    let s = bananenBasicsPlugin.reduce(state, antwort("p1", 1, 3_000), ctx) as BananenBasicsState;
    const vorher = bananenBasicsPlugin.viewFor(s, "screen") as {
      answeredCount: number;
      aufloesung: null;
    };
    expect(vorher.answeredCount).toBe(1); // anonymer Mini-Affe hüpft
    expect(vorher.aufloesung).toBeNull();
    s = { ...s, finished: true };
    const nachher = bananenBasicsPlugin.viewFor(s, "screen") as {
      aufloesung: { correctIndex: number; perPlayer: { playerId: string; delta: number }[] };
    };
    expect(nachher.aufloesung.correctIndex).toBe(1);
    expect(nachher.aufloesung.perPlayer.find((x) => x.playerId === "p1")?.delta).toBe(380);
  });

  it("hält den State JSON-serialisierbar (Save/Load-Vertrag)", () => {
    const { ctx, state } = setup();
    const s = bananenBasicsPlugin.reduce(state, antwort("p1", 1, 800), ctx);
    const kopie = JSON.parse(JSON.stringify(s)) as BananenBasicsState;
    expect(bananenBasicsPlugin.scores(kopie)).toEqual(
      bananenBasicsPlugin.scores(s as BananenBasicsState),
    );
  });
});

// ---------- Wächter (Eval 5): wahr_falsch als 2-Optionen-Frage ----------
describe("bananen-basics: wahr_falsch (2 XXL-Optionen)", () => {
  const wfFrage: Question = {
    id: "q_wf_1",
    kind: "wahr_falsch",
    category: "affen",
    difficulty: "easy",
    text: "Bananen wachsen an Bäumen.",
    options: ["Wahr", "Falsch"],
    answer: 1,
    erklaerung: "Die Bananenstaude ist eine Staude, kein Baum.",
  };

  function setupWf(seed = 1) {
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(seed) };
    const spieler = [P1, P2];
    const state = bananenBasicsPlugin.init(
      spieler,
      { questions: [wfFrage] },
      ctx,
    ) as BananenBasicsState;
    return { clock, ctx, state };
  }

  it("Frage erreicht das Plugin: 2 Optionen im View, Scoring wie choice4", () => {
    const { ctx, state } = setupWf();
    const view = bananenBasicsPlugin.viewFor(state, "screen") as { options: string[] };
    expect(view.options).toEqual(["Wahr", "Falsch"]);
    let s = bananenBasicsPlugin.reduce(state, antwort("p1", 1, 2_000), ctx) as BananenBasicsState;
    s = bananenBasicsPlugin.reduce(s, antwort("p2", 0, 2_000), ctx) as BananenBasicsState;
    s = { ...s, finished: true };
    const scores = bananenBasicsPlugin.scores(s);
    expect(scores[P1]).toBe(fragenGewinn("easy", 2_000, state.timerMs));
    expect(scores[P2]).toBe(0);
  });

  it("Options-Indizes 2/3 existieren nicht — Antwort wird verworfen", () => {
    const { ctx, state } = setupWf();
    const s = bananenBasicsPlugin.reduce(state, antwort("p1", 3, 1_000), ctx) as BananenBasicsState;
    expect(s.answers.p1).toBeUndefined();
  });

  it("50:50/Tipp-Kanone: bei 2 Optionen bleibt die falsche stehen (no-op)", () => {
    const { ctx, state } = setupWf();
    const fifty: JokerAction = { kind: "joker", type: "fiftyFifty", playerId: P1 };
    const remove: JokerAction = { kind: "joker", type: "removeOne", playerId: null };
    const nachFifty = bananenBasicsPlugin.reduce(state, fifty, ctx) as BananenBasicsState;
    expect(nachFifty.gesperrt[P1] ?? []).toEqual([]);
    const nachRemove = bananenBasicsPlugin.reduce(state, remove, ctx) as BananenBasicsState;
    expect(nachRemove.gesperrtGlobal).toEqual([]);
  });
});
