// Pixel-Dschungel: Verfalls-Kurve (Goldens), Stufen-Uhr, Falsch-Sperre,
// Latenztoleranz (gleiche Stufe = gleiche Punkte), Pause-Verhalten, Leak-Schutz.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  PD_GESAMT_MS,
  PD_STUFEN,
  pdBildFuerFrage,
  pdJackpotWert,
  pdStufeZuZeit,
} from "../../shared/minigames/pixel-dschungel.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import { pixelDschungelPlugin, type PixelDschungelState } from "./pixel-dschungel/index";

function frage(difficulty: Question["difficulty"] = "medium"): Question {
  return {
    id: "q_pd",
    kind: "choice4",
    category: "tiere",
    difficulty,
    text: "Welches Tier versteckt sich im Bild?",
    options: ["Tapir", "Faultier", "Ozelot", "Kapuziner"],
    answer: 1,
    erklaerung: "Es war das Faultier.",
  };
}

const spieler = [asPlayerId("p1"), asPlayerId("p2"), asPlayerId("p3")];

function setup(difficulty: Question["difficulty"] = "medium", startMs = 0) {
  const clock = createTestClock(startMs);
  const ctx = { clock, rng: createRng(7) };
  const content: ContentSlice = { questions: [frage(difficulty)] };
  const state = pixelDschungelPlugin.init(spieler, content, ctx) as PixelDschungelState;
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

describe("pixel-dschungel: Verfalls-Kurve (Goldens, GAME-DESIGN §2.5)", () => {
  it("MEDIUM fällt 400→50 in −50er-Schritten über 8 Stufen", () => {
    const werte = Array.from({ length: PD_STUFEN }, (_, s) => pdJackpotWert("medium", s));
    expect(werte).toEqual([400, 350, 300, 250, 200, 150, 100, 50]);
  });

  it("HARD 800→100 (−100) und ULTRAHARD 1.600→200 (−200)", () => {
    expect(Array.from({ length: 8 }, (_, s) => pdJackpotWert("hard", s))).toEqual([
      800, 700, 600, 500, 400, 300, 200, 100,
    ]);
    expect(Array.from({ length: 8 }, (_, s) => pdJackpotWert("ultrahard", s))).toEqual([
      1600, 1400, 1200, 1000, 800, 600, 400, 200,
    ]);
  });

  it("Stufen-Uhr: 3-s-Fenster, Stufe 7 hält durch das Vollbild-Fenster", () => {
    expect(pdStufeZuZeit(0)).toBe(0);
    expect(pdStufeZuZeit(2_999)).toBe(0);
    expect(pdStufeZuZeit(3_000)).toBe(1);
    expect(pdStufeZuZeit(20_999)).toBe(6);
    expect(pdStufeZuZeit(21_000)).toBe(7);
    expect(pdStufeZuZeit(27_500)).toBe(7); // Vollbild: Minimum bleibt
  });
});

describe("pixel-dschungel: Scoring nach Server-Empfangs-Stufe", () => {
  it("früh buzzern bringt mehr: Stufe 0 = 400, Stufe 3 = 250 (MEDIUM)", () => {
    const { ctx, state } = setup("medium");
    let s = pixelDschungelPlugin.reduce(state, antwort("p1", 1, 1_000), ctx);
    s = pixelDschungelPlugin.reduce(s, antwort("p2", 1, 10_500), ctx);
    s = { ...(s as PixelDschungelState), finished: true };
    const scores = pixelDschungelPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(400);
    expect(scores[asPlayerId("p2")]).toBe(250);
  });

  it("ist latenztolerant: gleiche Stufe = gleiche Punkte", () => {
    const { ctx, state } = setup("medium");
    let s = pixelDschungelPlugin.reduce(state, antwort("p1", 1, 9_100), ctx);
    s = pixelDschungelPlugin.reduce(s, antwort("p2", 1, 11_900), ctx);
    s = { ...(s as PixelDschungelState), finished: true };
    const scores = pixelDschungelPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(scores[asPlayerId("p2")]);
    expect(scores[asPlayerId("p1")]).toBe(250); // Stufe 3
  });

  it("falsch = 0 MM + Sperre für den Rest der Frage (Design-Regel)", () => {
    const { ctx, state } = setup("medium");
    let s = pixelDschungelPlugin.reduce(state, antwort("p1", 0, 1_000), ctx);
    // Zweiter Versuch (diesmal „richtig") wird verworfen — Sperre ist hart.
    s = pixelDschungelPlugin.reduce(s, antwort("p1", 1, 2_000), ctx);
    const st = s as PixelDschungelState;
    expect(st.answers.p1.choice).toBe(0);
    s = { ...st, finished: true };
    expect(pixelDschungelPlugin.scores(s)[asPlayerId("p1")]).toBe(0);
  });

  it("Antwort im Vollbild-Fenster (nach 24 s) bekommt die Minimal-Stufe", () => {
    const { ctx, state } = setup("hard");
    let s = pixelDschungelPlugin.reduce(state, antwort("p1", 1, 25_000), ctx);
    s = { ...(s as PixelDschungelState), finished: true };
    expect(pixelDschungelPlugin.scores(s)[asPlayerId("p1")]).toBe(100);
  });

  it("Gnadenfenster: +400 ms nach endsAt zählt noch, danach verworfen", () => {
    const { ctx, state } = setup("medium");
    const geradeNoch = pixelDschungelPlugin.reduce(
      state,
      antwort("p1", 1, PD_GESAMT_MS + 399),
      ctx,
    ) as PixelDschungelState;
    expect(geradeNoch.answers.p1).toBeDefined();
    expect(geradeNoch.answers.p1.stufe).toBe(7);
    const zuSpaet = pixelDschungelPlugin.reduce(
      state,
      antwort("p1", 1, PD_GESAMT_MS + 401),
      ctx,
    ) as PixelDschungelState;
    expect(zuSpaet.answers.p1).toBeUndefined();
  });
});

describe("pixel-dschungel: Ablauf + GM-Eingriffe", () => {
  it("endet, wenn alle geantwortet haben ODER das 28-s-Fenster abläuft", () => {
    const { clock, ctx, state } = setup();
    let s = pixelDschungelPlugin.reduce(state, antwort("p1", 1, 500), ctx);
    s = pixelDschungelPlugin.reduce(s, antwort("p2", 0, 700), ctx);
    s = pixelDschungelPlugin.tick(s, ctx);
    expect(pixelDschungelPlugin.isFinished(s)).toBe(false);
    s = pixelDschungelPlugin.reduce(s, antwort("p3", 2, 900), ctx);
    s = pixelDschungelPlugin.tick(s, ctx);
    expect(pixelDschungelPlugin.isFinished(s)).toBe(true);

    const frisch = setup();
    frisch.clock.advance(PD_GESAMT_MS + 1);
    void clock;
    const nachTimeout = pixelDschungelPlugin.tick(frisch.state, frisch.ctx);
    expect(pixelDschungelPlugin.isFinished(nachTimeout)).toBe(true);
  });

  it("Pause (timer.shift) friert Verfall UND Deadline ein — Stufe bleibt fair", () => {
    const { ctx, state } = setup("medium");
    // 10 s Pause: alles wandert um 10 s nach hinten.
    const s = pixelDschungelPlugin.reduce(
      state,
      { kind: "gm", type: "timer.shift", ms: 10_000 },
      ctx,
    ) as PixelDschungelState;
    expect(s.startedAt).toBe(10_000);
    expect(s.endsAt).toBe(10_000 + PD_GESAMT_MS);
    // Antwort bei Server-Zeit 11.000 = 1 s nach (verschobenem) Start ⇒ Stufe 0.
    const s2 = pixelDschungelPlugin.reduce(s, antwort("p1", 1, 11_000), ctx);
    expect((s2 as PixelDschungelState).answers.p1.stufe).toBe(0);
  });

  it("GM-Verlängerung (timer.extend) verlängert NUR das Fenster, nicht die Stufen-Uhr", () => {
    const { ctx, state } = setup("medium");
    const s = pixelDschungelPlugin.reduce(
      state,
      { kind: "gm", type: "timer.extend", ms: 15_000 },
      ctx,
    ) as PixelDschungelState;
    expect(s.startedAt).toBe(0); // Verfall läuft weiter
    expect(s.endsAt).toBe(PD_GESAMT_MS + 15_000);
    // Antwort in der Verlängerung ⇒ Minimal-Stufe (mehr Zeit nur zum kleinsten Preis).
    const s2 = pixelDschungelPlugin.reduce(s, antwort("p1", 1, 30_000), ctx);
    expect((s2 as PixelDschungelState).answers.p1.stufe).toBe(7);
  });
});

describe("pixel-dschungel: Leak-Schutz + Vertrag", () => {
  it("verrät correctIndex vor der Auflösung weder Spielern noch Screen", () => {
    const { ctx, state } = setup();
    const s = pixelDschungelPlugin.reduce(state, antwort("p1", 0, 1_000), ctx);
    const playerView = JSON.stringify(pixelDschungelPlugin.viewFor(s, "player", spieler[0]));
    const screenView = JSON.stringify(pixelDschungelPlugin.viewFor(s, "screen"));
    expect(playerView).not.toContain("correctIndex");
    expect(screenView).not.toContain("correctIndex");
    // Wer eingeloggt hat, ist sichtbar — ob richtig/falsch NICHT.
    expect(screenView).not.toContain('"correct":');
    const gmView = pixelDschungelPlugin.viewFor(s, "gm") as { correctIndex: number };
    expect(gmView.correctIndex).toBe(1);
  });

  it("hält den State JSON-serialisierbar + Bild-Zuordnung deterministisch", () => {
    const { ctx, state } = setup();
    const s = pixelDschungelPlugin.reduce(state, antwort("p1", 1, 4_000), ctx);
    const kopie = JSON.parse(JSON.stringify(s)) as PixelDschungelState;
    expect(pixelDschungelPlugin.scores(kopie)).toEqual(pixelDschungelPlugin.scores(s));
    // Gleiche Frage-Id ⇒ immer dasselbe Platzhalter-Motiv (Screen/Player synchron).
    expect(pdBildFuerFrage(frage())).toEqual(pdBildFuerFrage(frage()));
    expect(pdBildFuerFrage(frage()).typ).toBe("platzhalter");
  });

  // Wächter: erreicht eine bild_pixel-Frage (media) das Plugin, landet die ECHTE
  // Bild-URL in allen Rollen-Views — der Platzhalter bleibt nur Fallback.
  it("media-Frage ⇒ View liefert bild {typ:'url'} mit der /media-URL", () => {
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(7) };
    const mediaFrage: Question = {
      ...frage("medium"),
      media: { bild: "/media/img/generated/pixel/pixel_leuchtturm.png" },
    };
    const state = pixelDschungelPlugin.init(
      spieler,
      { questions: [mediaFrage] },
      ctx,
    ) as PixelDschungelState;
    for (const rolle of ["screen", "player", "gm"] as const) {
      const view = pixelDschungelPlugin.viewFor(state, rolle, spieler[0]) as {
        bild: { typ: string; wert: string };
      };
      expect(view.bild).toEqual({
        typ: "url",
        wert: "/media/img/generated/pixel/pixel_leuchtturm.png",
      });
    }
  });
});
