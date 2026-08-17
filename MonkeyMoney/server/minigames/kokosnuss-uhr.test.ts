// Kokosnuss-Uhr-Plugin: Sack-Tick-Goldens, Antwort-Lock, Gnadenfenster, Pause,
// Disconnect, Leak-Schutz, Determinismus, Serialisierbarkeit (Contract-Grundlage).
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import { sackWertBei } from "../../shared/minigames/kokosnuss-uhr.meta";
import { FRAGE_TIMER_MS } from "../../shared/money";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { GmAction, PlayerAction } from "./_api/plugin";
import { kokosnussUhrPlugin, type KokosnussUhrState } from "./kokosnuss-uhr/index";

const frageMedium: Question = {
  id: "q_kuhr_m",
  kind: "choice4",
  category: "test",
  difficulty: "medium", // Sack 400 MM, 8 Ticks / 20 s ⇒ alle 2.500 ms (§2.2 + Pacing-Config)
  text: "Testfrage?",
  options: ["A", "B", "C", "D"],
  answer: 1,
  erklaerung: "B stimmt.",
};

const frageHard: Question = { ...frageMedium, id: "q_kuhr_h", difficulty: "hard" };

const spieler = [asPlayerId("p1"), asPlayerId("p2")];

function setup(frage: Question = frageMedium, startMs = 0) {
  const clock = createTestClock(startMs);
  const ctx = { clock, rng: createRng(1) };
  const content: ContentSlice = { questions: [frage] };
  const state = kokosnussUhrPlugin.init(spieler, content, ctx) as KokosnussUhrState;
  return { clock, ctx, state };
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

describe("kokosnuss-uhr: Sack-Tick-Goldens (§2.2)", () => {
  it("MEDIUM: friert 400 MM im ersten Tick ein, 300 MM nach 5 s (Tick 2)", () => {
    const { ctx, state } = setup();
    let s = kokosnussUhrPlugin.reduce(state, antwort("p1", 1, 1_000), ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.reduce(s, antwort("p2", 1, 5_000), ctx) as KokosnussUhrState;
    s = { ...s, finished: true };
    const scores = kokosnussUhrPlugin.scores(s);
    expect(scores[spieler[0]]).toBe(400); // floor(1000/2500) = 0 Ticks
    expect(scores[spieler[1]]).toBe(300); // floor(5000/2500) = 2 Ticks ⇒ 400 − 100
  });

  it("HARD: 750 MM Start, nach 10 s sind 6 Ticks weg ⇒ 450 MM eingefroren", () => {
    const { ctx, state } = setup(frageHard);
    let s = kokosnussUhrPlugin.reduce(state, antwort("p1", 1, 10_000), ctx) as KokosnussUhrState;
    s = { ...s, finished: true };
    // 15 Ticks / 25 s ⇒ alle 1666,7 ms; floor(10000/1666,7) = 6 ⇒ 750 − 300.
    expect(kokosnussUhrPlugin.scores(s)[spieler[0]]).toBe(450);
  });

  it("falsche Antwort = 0 MM, auch bei vollem Sack", () => {
    const { ctx, state } = setup();
    let s = kokosnussUhrPlugin.reduce(state, antwort("p1", 0, 500), ctx) as KokosnussUhrState;
    s = { ...s, finished: true };
    expect(kokosnussUhrPlugin.scores(s)[spieler[0]]).toBe(0);
    // Eingefroren wurde trotzdem (öffentliches Eis-Overlay) — nur der Payout ist 0.
    expect(s.answers.p1.eingefroren).toBe(400);
  });

  it("der Sack wird nie negativ: Antwort im Gnadenfenster friert 0 MM ein", () => {
    const { ctx, state } = setup();
    const s = kokosnussUhrPlugin.reduce(
      state,
      antwort("p1", 1, FRAGE_TIMER_MS.medium + 200),
      ctx,
    ) as KokosnussUhrState;
    expect(s.answers.p1.eingefroren).toBe(0);
    expect(sackWertBei(400, 2_500, 99_999)).toBe(0);
  });
});

describe("kokosnuss-uhr: Antwort-Lock + Spätantwort", () => {
  it("nimmt pro Spieler nur die ERSTE Antwort (kein Umentscheiden)", () => {
    const { ctx, state } = setup();
    let s = kokosnussUhrPlugin.reduce(state, antwort("p1", 1, 1_000), ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.reduce(s, antwort("p1", 3, 2_000), ctx) as KokosnussUhrState;
    expect(s.answers.p1.choice).toBe(1);
    expect(s.answers.p1.eingefroren).toBe(400);
  });

  it("verwirft Antworten nach dem Gnadenfenster (+400 ms) und ungültige Choices", () => {
    const { ctx, state } = setup();
    const zuSpaet = kokosnussUhrPlugin.reduce(
      state,
      antwort("p1", 1, FRAGE_TIMER_MS.medium + 401),
      ctx,
    );
    expect((zuSpaet as KokosnussUhrState).answers.p1).toBeUndefined();
    const geradeNoch = kokosnussUhrPlugin.reduce(
      state,
      antwort("p1", 1, FRAGE_TIMER_MS.medium + 399),
      ctx,
    );
    expect((geradeNoch as KokosnussUhrState).answers.p1).toBeDefined();
    const kaputt = kokosnussUhrPlugin.reduce(state, antwort("p1", 7, 1_000), ctx);
    expect((kaputt as KokosnussUhrState).answers.p1).toBeUndefined();
  });
});

describe("kokosnuss-uhr: GM-Zeit-Eingriffe", () => {
  it("timer.extend verschiebt nur die Deadline — der Sack tickt weiter Richtung 0", () => {
    const { clock, ctx, state } = setup();
    const extend: GmAction = { kind: "gm", type: "timer.extend", ms: 15_000 };
    let s = kokosnussUhrPlugin.reduce(state, extend, ctx) as KokosnussUhrState;
    expect(s.endsAt).toBe(FRAGE_TIMER_MS.medium + 15_000);
    clock.advance(FRAGE_TIMER_MS.medium + 1_000); // Original-Timer wäre vorbei, Sack ist leer
    s = kokosnussUhrPlugin.tick(s, ctx) as KokosnussUhrState;
    expect(s.finished).toBe(false);
    expect(s.sackWert).toBe(0);
    s = kokosnussUhrPlugin.reduce(
      s,
      antwort("p1", 1, FRAGE_TIMER_MS.medium + 1_000),
      ctx,
    ) as KokosnussUhrState;
    expect(s.answers.p1.eingefroren).toBe(0); // richtig, aber der Sack ist aufgegessen
  });

  it("timer.shift (Pause) friert den Sack über die Pausendauer ein", () => {
    const { clock, ctx, state } = setup();
    clock.advance(8_000);
    const shift: GmAction = { kind: "gm", type: "timer.shift", ms: 3_000 };
    let s = kokosnussUhrPlugin.reduce(state, shift, ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.tick(s, ctx) as KokosnussUhrState;
    // Effektiv vergangen: 8000 − 3000 = 5000 ms ⇒ 2 Ticks ⇒ 300 (statt 250 ohne Shift).
    expect(s.sackWert).toBe(300);
    const a = kokosnussUhrPlugin.reduce(s, antwort("p1", 1, 8_000), ctx) as KokosnussUhrState;
    expect(a.answers.p1.eingefroren).toBe(300);
  });
});

describe("kokosnuss-uhr: Disconnect + Rundenende", () => {
  it('AFK-Affe blockiert das „alle eingefroren"-Ende nicht; Reconnect zählt wieder', () => {
    const { ctx, state } = setup();
    let s = kokosnussUhrPlugin.onDisconnect(state, spieler[1], ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.reduce(s, antwort("p1", 1, 1_000), ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.tick(s, ctx) as KokosnussUhrState;
    expect(s.finished).toBe(true); // p2 offline ⇒ Runde endet, 0 MM, keine Strafe

    const { ctx: ctx2, state: s2 } = setup();
    let t = kokosnussUhrPlugin.onDisconnect(s2, spieler[1], ctx2) as KokosnussUhrState;
    t = kokosnussUhrPlugin.onReconnect(t, spieler[1], ctx2) as KokosnussUhrState;
    t = kokosnussUhrPlugin.reduce(t, antwort("p1", 1, 1_000), ctx2) as KokosnussUhrState;
    t = kokosnussUhrPlugin.tick(t, ctx2) as KokosnussUhrState;
    expect(t.finished).toBe(false); // p2 ist zurück ⇒ Runde wartet wieder auf ihn
  });

  it("endet bei Timeout auch ohne Antworten", () => {
    const { clock, ctx, state } = setup();
    clock.advance(FRAGE_TIMER_MS.medium + 1);
    const s = kokosnussUhrPlugin.tick(state, ctx) as KokosnussUhrState;
    expect(s.finished).toBe(true);
    expect(kokosnussUhrPlugin.scores(s)[spieler[0]]).toBe(0);
  });
});

describe("kokosnuss-uhr: Leak-Schutz + Contract", () => {
  it("verrät Spielern und Screen die richtige Antwort NICHT vor der Auflösung", () => {
    const { state } = setup();
    const playerView = JSON.stringify(kokosnussUhrPlugin.viewFor(state, "player", spieler[0]));
    const screenView = JSON.stringify(kokosnussUhrPlugin.viewFor(state, "screen"));
    expect(playerView).not.toContain("correctIndex");
    expect(playerView).not.toContain('aufloesung":{');
    expect(screenView).not.toContain("correctIndex");
    // GM-Spickzettel sieht sie IMMER:
    const gmView = kokosnussUhrPlugin.viewFor(state, "gm") as { correctIndex: number };
    expect(gmView.correctIndex).toBe(1);
  });

  it("liefert der Bühne answeredCount + endsAt (Delta-Vertrag der Room-Schicht)", () => {
    const { ctx, state } = setup();
    const s = kokosnussUhrPlugin.reduce(state, antwort("p1", 1, 1_000), ctx) as KokosnussUhrState;
    const view = kokosnussUhrPlugin.viewFor(s, "screen") as {
      answeredCount: number;
      endsAt: number;
      eingefrorene: { playerId: string; betrag: number }[];
    };
    expect(view.answeredCount).toBe(1);
    expect(view.endsAt).toBe(FRAGE_TIMER_MS.medium);
    expect(view.eingefrorene).toEqual([{ playerId: "p1", betrag: 400 }]);
  });

  it("ist deterministisch (gleicher Seed/Uhr ⇒ identischer State) und mutiert Input nie", () => {
    const a = setup();
    const b = setup();
    expect(JSON.stringify(a.state)).toBe(JSON.stringify(b.state));
    const vorher = JSON.stringify(a.state);
    kokosnussUhrPlugin.reduce(a.state, antwort("p1", 1, 1_000), a.ctx);
    kokosnussUhrPlugin.tick(a.state, a.ctx);
    expect(JSON.stringify(a.state)).toBe(vorher); // pure: kein In-Place-Mutieren
  });

  it("outcomes(): richtig bleibt richtig, auch wenn der Sack leer eingefroren wurde", () => {
    const { ctx, state } = setup();
    const spaet = FRAGE_TIMER_MS.medium + 200; // im Gnadenfenster, Sack längst leer
    let s = kokosnussUhrPlugin.reduce(state, antwort("p1", 1, spaet), ctx) as KokosnussUhrState;
    s = { ...s, finished: true };
    // Richtig mit 0 MM (Sack leer): delta = 0, aber die Streak-Kette hält (§2.2).
    expect(kokosnussUhrPlugin.scores(s)[spieler[0]]).toBe(0);
    const outcomes = kokosnussUhrPlugin.outcomes!(s);
    expect(outcomes[spieler[0]]).toEqual({ correct: true, nachMs: spaet });
    expect(outcomes[spieler[1]]).toEqual({ correct: null }); // keine Antwort
  });

  it("hält den State JSON-serialisierbar (Save/Reconnect/Event-Log gratis)", () => {
    const { ctx, state } = setup();
    const s = kokosnussUhrPlugin.reduce(state, antwort("p1", 1, 900), ctx) as KokosnussUhrState;
    const kopie = JSON.parse(JSON.stringify(s)) as KokosnussUhrState;
    expect(kokosnussUhrPlugin.scores({ ...kopie, finished: true })).toEqual(
      kokosnussUhrPlugin.scores({ ...s, finished: true }),
    );
  });
});

describe("kokosnuss-uhr: Maßanzug (mods.fragenProSpieler — Befund-Fix)", () => {
  it("zugewiesener Spieler wird an SEINER Frage gemessen, der Rest an der Basis", () => {
    const eigene: Question = {
      ...frageMedium,
      id: "q_eigen",
      text: "Eigene Frage?",
      answer: 2,
      erklaerung: "C stimmt hier.",
    };
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(1) };
    const content: ContentSlice = {
      questions: [frageMedium],
      mods: { fragenProSpieler: { p1: eigene } },
    };
    let s = kokosnussUhrPlugin.init(spieler, content, ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.reduce(s, antwort("p1", 2, 1_000), ctx) as KokosnussUhrState;
    s = kokosnussUhrPlugin.reduce(s, antwort("p2", 2, 1_000), ctx) as KokosnussUhrState;
    s = { ...s, finished: true };
    // p1: richtig an der EIGENEN Frage (answer 2); p2: falsch an der Basis (answer 1).
    expect(kokosnussUhrPlugin.scores(s)).toEqual({ p1: 400, p2: 0 });
    const outcomes = kokosnussUhrPlugin.outcomes!(s);
    expect(outcomes[spieler[0]].correct).toBe(true);
    expect(outcomes[spieler[1]].correct).toBe(false);
    // p1 sieht SEINE Frage samt passender Auflösung; der Screen zeigt die Basis.
    const pView = kokosnussUhrPlugin.viewFor(s, "player", spieler[0]) as {
      text: string;
      aufloesung: { correctIndex: number };
    };
    expect(pView.text).toBe("Eigene Frage?");
    expect(pView.aufloesung.correctIndex).toBe(2);
    const sView = kokosnussUhrPlugin.viewFor(s, "screen") as { text: string };
    expect(sView.text).toBe("Testfrage?");
  });
});
