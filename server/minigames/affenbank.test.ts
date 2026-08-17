// Die Affenbank: Ketten-Goldens (50→…→1.600, Kappe), strikte Mehrheit über die
// Verbundenen (2 Spieler = beide), BANK!-Verrat (1-s-Sammelfenster, EIN Reset),
// Verbrennen bei falscher Mehrheit + Durchgangs-Ende, Disconnect-Regeln,
// Fragen-Rotation (frageNonce), Determinismus und View-Leak-Wachen.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  AB_BANK_FENSTER_MS,
  AB_KETTE,
  AB_KETTE_MS,
  AB_PAUSE_MS,
  AB_QUICK_DURCHGAENGE,
  AB_QUICK_KETTE_MS,
  abPottWert,
} from "../../shared/minigames/affenbank.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import { affenbankPlugin, type AffenbankState } from "./affenbank/index";

const fragen: Question[] = [0, 1].map((i) => ({
  id: `q_ab_${i}`,
  kind: "choice4",
  category: "geld",
  difficulty: "medium",
  text: `Bank-Frage ${i}?`,
  options: ["A", "B", "C", "D"],
  answer: 2,
  erklaerung: "C stimmt.",
}));

function setup(
  spielerIds: string[] = ["p1", "p2", "p3", "p4"],
  seed = 1,
  mods?: ContentSlice["mods"],
) {
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(seed) };
  const content: ContentSlice = mods ? { questions: fragen, mods } : { questions: fragen };
  const spieler = spielerIds.map(asPlayerId);
  const state = affenbankPlugin.init(spieler, content, ctx) as AffenbankState;
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

function bank(playerId: string, atServerTime: number): PlayerAction<{ type: "bank" }> {
  return { kind: "player", playerId: asPlayerId(playerId), action: { type: "bank" }, atServerTime };
}

/** Alle Spieler antworten richtig/falsch, dann Fenster-Ende ticken. */
function fensterDurchspielen(
  s: AffenbankState,
  ctx: { clock: ReturnType<typeof createTestClock>; rng: ReturnType<typeof createRng> },
  richtige: string[],
): AffenbankState {
  const at = ctx.clock.now() + 1_000;
  for (const p of s.players) {
    const choice = richtige.includes(p) ? 2 : 0;
    s = affenbankPlugin.reduce(s, antwort(p, choice, at), ctx) as AffenbankState;
  }
  ctx.clock.advance(s.frageEndetAt - ctx.clock.now());
  return affenbankPlugin.tick(s, ctx) as AffenbankState;
}

describe("affenbank: Ketten-Goldens (§2.8)", () => {
  it("6 Mehrheits-Treffer in Folge = 50 → 100 → 200 → 400 → 800 → 1.600; Kappe hält beim 7.", () => {
    const { ctx, state, spieler } = setup();
    let s = state;
    for (let i = 0; i < AB_KETTE.length; i++) {
      s = fensterDurchspielen(s, ctx, spieler);
      expect(s.stufe).toBe(i + 1);
      expect(abPottWert(s.stufe)).toBe(AB_KETTE[i]);
    }
    s = fensterDurchspielen(s, ctx, spieler); // 7. Treffer: Kappe 1.600
    expect(abPottWert(s.stufe)).toBe(1_600);
    expect(s.historie.filter((h) => h.typ === "verdoppelt")).toHaveLength(7);
  });

  it("strikte Mehrheit über die VERBUNDENEN: 2 von 4 reicht NICHT (verbrennt), 3 von 4 reicht", () => {
    const { ctx, state } = setup();
    let s = fensterDurchspielen(state, ctx, ["p1", "p2", "p3"]);
    expect(s.stufe).toBe(1);
    s = fensterDurchspielen(s, ctx, ["p1", "p2"]); // 2×2 = 4, nicht > 4 ⇒ verbrannt
    expect(s.stufe).toBe(0);
    expect(s.historie.at(-1)?.typ).toBe("verbrannt");
  });

  it("2 Spieler: „Mehrheit“ = BEIDE richtig (Design-Edge)", () => {
    const { ctx, state } = setup(["a", "b"]);
    let s = fensterDurchspielen(state, ctx, ["a"]);
    expect(s.stufe).toBe(0);
    s = fensterDurchspielen(s, ctx, ["a", "b"]);
    expect(s.stufe).toBe(1);
  });

  it("die erste Antwort pro Fenster rastet ein; nach Fenster-Ende wird sie verworfen", () => {
    const { ctx, state } = setup();
    let s = affenbankPlugin.reduce(state, antwort("p1", 0, 1_000), ctx) as AffenbankState;
    s = affenbankPlugin.reduce(s, antwort("p1", 2, 2_000), ctx) as AffenbankState;
    expect(s.answers.p1).toBe(0);
    const zuSpaet = affenbankPlugin.reduce(s, antwort("p2", 2, s.frageEndetAt + 1), ctx);
    expect(zuSpaet).toBe(s);
  });
});

describe("affenbank: BANK! — der Verrats-Moment", () => {
  it("BANK! sichert den Pott persönlich, die Kette reißt SOFORT auf 0", () => {
    const { ctx, state, spieler } = setup();
    let s = state;
    for (let i = 0; i < 3; i++) s = fensterDurchspielen(s, ctx, spieler); // Pott 200
    const at = ctx.clock.now() + 500;
    s = affenbankPlugin.reduce(s, bank("p1", at), ctx) as AffenbankState;
    expect(s.gebankt.p1).toBe(200);
    expect(s.stufe).toBe(0);
    expect(s.bankFenster).toMatchObject({ betrag: 200, drueckerIds: ["p1"] });
    expect(s.historie.at(-1)).toMatchObject({ typ: "gebankt", playerId: "p1", betrag: 200 });
  });

  it("alle Drücker im selben 1-s-Fenster sichern DENSELBEN Betrag — danach ist der Pott weg", () => {
    const { ctx, state, spieler } = setup();
    let s = state;
    for (let i = 0; i < 4; i++) s = fensterDurchspielen(s, ctx, spieler); // Pott 400
    const at = ctx.clock.now() + 500;
    s = affenbankPlugin.reduce(s, bank("p1", at), ctx) as AffenbankState;
    s = affenbankPlugin.reduce(s, bank("p2", at + AB_BANK_FENSTER_MS - 1), ctx) as AffenbankState;
    expect(s.gebankt.p1).toBe(400);
    expect(s.gebankt.p2).toBe(400);
    // Doppel-Drücken im Fenster ist idempotent:
    expect(affenbankPlugin.reduce(s, bank("p1", at + 300), ctx)).toBe(s);
    // NACH dem Fenster ist die Kette leer — BANK! verpufft (Pott 0):
    const nachher = affenbankPlugin.reduce(s, bank("p3", at + AB_BANK_FENSTER_MS + 1), ctx);
    expect((nachher as AffenbankState).gebankt.p3).toBeUndefined();
  });

  it("BANK! auf leeren Pott ist ein No-op; scores() = NUR gebankte Summen", () => {
    const { ctx, state, spieler } = setup();
    expect(affenbankPlugin.reduce(state, bank("p1", 500), ctx)).toBe(state);
    let s = state;
    for (let i = 0; i < 2; i++) s = fensterDurchspielen(s, ctx, spieler); // Pott 100
    s = affenbankPlugin.reduce(s, bank("p2", ctx.clock.now() + 100), ctx) as AffenbankState;
    s = fensterDurchspielen(s, ctx, spieler); // neue Kette: Pott 50
    s = affenbankPlugin.reduce(s, bank("p3", ctx.clock.now() + 100), ctx) as AffenbankState;
    expect(affenbankPlugin.scores(s)).toEqual({ p1: 0, p2: 100, p3: 50, p4: 0 });
    const outcomes = affenbankPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p2")].correct).toBe(true); // gebankt = „richtig“
    expect(outcomes[asPlayerId("p1")].correct).toBe(false); // beteiligt, nichts gesichert
  });
});

describe("affenbank: Durchgänge + Timing", () => {
  it("Durchgangs-Ende verbrennt den ungesicherten Pott; nach Pause startet Durchgang 2, dann Schluss", () => {
    const { clock, ctx, state, spieler } = setup();
    let s = fensterDurchspielen(state, ctx, spieler); // Pott 50 aufgebaut
    expect(s.stufe).toBe(1);
    clock.advance(AB_KETTE_MS); // weit übers Ketten-Ende
    s = affenbankPlugin.tick(s, ctx) as AffenbankState;
    expect(s.phase).toBe("pause");
    expect(s.stufe).toBe(0);
    expect(s.historie.filter((h) => h.typ === "verbrannt").length).toBeGreaterThanOrEqual(1);
    clock.advance(AB_PAUSE_MS + 1);
    s = affenbankPlugin.tick(s, ctx) as AffenbankState;
    expect(s.phase).toBe("kette");
    expect(s.durchgang).toBe(2);
    expect(s.ketteEndetAt).toBe(ctx.clock.now() + AB_KETTE_MS);
    clock.advance(AB_KETTE_MS + 1);
    s = affenbankPlugin.tick(s, ctx) as AffenbankState;
    expect(affenbankPlugin.isFinished(s)).toBe(true);
  });

  it("90-s-Kette im 10-s-Takt = 9 Fenster pro Durchgang (frageNonce), Fragen rotieren zyklisch", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    expect(s.frageNonce).toBe(1);
    let fenster = 0;
    while (s.phase === "kette" && !s.finished) {
      const vorher = s.frageNonce;
      clock.advance(s.frageEndetAt - ctx.clock.now());
      s = affenbankPlugin.tick(s, ctx) as AffenbankState;
      if (s.frageNonce > vorher || s.phase !== "kette") fenster += 1;
      if (fenster > 20) break;
    }
    expect(fenster).toBe(9);
    // Rotation: 2 Fragen im Slice ⇒ Fenster 1/3/5… zeigen q0, 2/4/6… q1.
    const rotiert = affenbankPlugin.viewFor({ ...s, phase: "kette" }, "screen") as {
      questionId: string;
    };
    expect(["q_ab_0", "q_ab_1"]).toContain(rotiert.questionId);
  });

  it("Quick-Tuning (mods.affenbank): 45-s-Kette, EIN Durchgang, ~5 Fenster — dann Schluss", () => {
    const { clock, ctx, state } = setup(undefined, 1, {
      affenbank: { durchgaenge: AB_QUICK_DURCHGAENGE, ketteMs: AB_QUICK_KETTE_MS },
    });
    expect(state.ketteEndetAt).toBe(AB_QUICK_KETTE_MS);
    let s = state;
    let fenster = 0;
    while (!s.finished && fenster < 20) {
      const vorher = s.frageNonce;
      clock.advance(s.frageEndetAt - ctx.clock.now());
      s = affenbankPlugin.tick(s, ctx) as AffenbankState;
      if (s.frageNonce > vorher || s.finished) fenster += 1;
    }
    // 45 s im 10-s-Takt = 4 volle Fenster + 1 Rest-Fenster; KEIN 2. Durchgang.
    expect(fenster).toBe(5);
    expect(s.durchgang).toBe(1);
    expect(affenbankPlugin.isFinished(s)).toBe(true);
    expect(ctx.clock.now()).toBeLessThanOrEqual(AB_QUICK_KETTE_MS + 1_000);
    const view = affenbankPlugin.viewFor(s, "screen") as {
      durchgaengeTotal: number;
      ketteMs: number;
    };
    expect(view.durchgaengeTotal).toBe(1);
    expect(view.ketteMs).toBe(AB_QUICK_KETTE_MS);
  });

  it("ohne Tuning-Mods gilt der §2.8-Standard (2 Durchgänge × 90 s)", () => {
    const { state } = setup();
    expect(state.durchgaengeTotal).toBe(2);
    expect(state.ketteMs).toBe(AB_KETTE_MS);
  });

  it("GM „+15 s“ verlängert Fenster UND Kette; force.finish beendet sofort", () => {
    const { ctx, state } = setup();
    const s = affenbankPlugin.reduce(
      state,
      { kind: "gm", type: "timer.extend", ms: 15_000 },
      ctx,
    ) as AffenbankState;
    expect(s.frageEndetAt).toBe(state.frageEndetAt + 15_000);
    expect(s.ketteEndetAt).toBe(state.ketteEndetAt + 15_000);
    const fertig = affenbankPlugin.reduce(
      s,
      { kind: "gm", type: "force.finish" },
      ctx,
    ) as AffenbankState;
    expect(affenbankPlugin.isFinished(fertig)).toBe(true);
  });
});

describe("affenbank: Disconnect-Regeln", () => {
  it("Disconnect: KEIN Auto-Bank, gesicherte Beträge bleiben, Mehrheits-Basis schrumpft", () => {
    const { ctx, state, spieler } = setup();
    let s = state;
    for (let i = 0; i < 2; i++) s = fensterDurchspielen(s, ctx, spieler); // Pott 100
    s = affenbankPlugin.reduce(s, bank("p4", ctx.clock.now() + 100), ctx) as AffenbankState;
    s = affenbankPlugin.onDisconnect(s, asPlayerId("p4"), ctx) as AffenbankState;
    expect(s.gebankt.p4).toBe(100); // bleibt
    // Mehrheit jetzt über 3 Verbundene: 2 von 3 reicht.
    s = fensterDurchspielen(s, ctx, ["p1", "p2"]);
    expect(s.stufe).toBe(1);
  });

  it("alle offline: keine Mehrheit möglich — die Kette wächst nicht", () => {
    const { ctx, state, spieler } = setup(["a", "b"]);
    let s = state;
    for (const p of spieler) s = affenbankPlugin.onDisconnect(s, p, ctx) as AffenbankState;
    s = fensterDurchspielen(s, ctx, []);
    expect(s.stufe).toBe(0);
  });
});

describe("affenbank: Leak-Wachen + Determinismus", () => {
  it("Screen/Player sehen die Frage (alle spielen), aber NIE correctIndex — der GM schon", () => {
    const { state } = setup();
    const screen = JSON.stringify(affenbankPlugin.viewFor(state, "screen"));
    const player = JSON.stringify(affenbankPlugin.viewFor(state, "player", asPlayerId("p1")));
    expect(screen).toContain(fragen[0].text);
    expect(screen).not.toContain("correctIndex");
    expect(player).not.toContain("correctIndex");
    const gm = affenbankPlugin.viewFor(state, "gm") as { correctIndex: number };
    expect(gm.correctIndex).toBe(2);
  });

  it("Pott-Stand + BANK!-Outings sind public (Screen-Inszenierung §2.8)", () => {
    const { ctx, state, spieler } = setup();
    let s = fensterDurchspielen(state, ctx, spieler);
    s = affenbankPlugin.reduce(s, bank("p2", ctx.clock.now() + 100), ctx) as AffenbankState;
    const screen = affenbankPlugin.viewFor(s, "screen") as {
      pott: number;
      gebankt: Record<string, number>;
      historie: { typ: string; playerId?: string }[];
    };
    expect(screen.pott).toBe(0); // Kette gerissen
    expect(screen.gebankt.p2).toBe(50);
    expect(screen.historie.at(-1)).toMatchObject({ typ: "gebankt", playerId: "p2" });
  });

  it("Auflösung: formatspezifische Status — NICHT GEBANKT statt „zu langsam“ (Playtest 3)", () => {
    const { clock, ctx, state } = setup(["p1", "p2", "p3"]);
    let s = state;
    // p1 + p2 antworten richtig (Mehrheit) — p3 bleibt komplett passiv.
    s = affenbankPlugin.reduce(s, antwort("p1", 2, 1_000), ctx) as AffenbankState;
    s = affenbankPlugin.reduce(s, antwort("p2", 2, 1_000), ctx) as AffenbankState;
    clock.advance(s.frageEndetAt - ctx.clock.now());
    s = affenbankPlugin.tick(s, ctx) as AffenbankState; // Pott 50
    s = affenbankPlugin.reduce(s, bank("p2", ctx.clock.now() + 100), ctx) as AffenbankState;
    s = affenbankPlugin.reduce(s, { kind: "gm", type: "force.finish" }, ctx) as AffenbankState;
    const view = affenbankPlugin.viewFor(s, "player", asPlayerId("p1")) as {
      aufloesung: {
        perPlayer: { playerId: string; status: string; hinweis?: string; correct: boolean }[];
      } | null;
    };
    const proSpieler = Object.fromEntries(
      (view.aufloesung?.perPlayer ?? []).map((p) => [p.playerId, p]),
    );
    expect(proSpieler.p2.status).toBe("💰 GEBANKT!");
    expect(proSpieler.p2.correct).toBe(true);
    expect(proSpieler.p1.status).toBe("🏦 NICHT GEBANKT");
    expect(proSpieler.p1.hinweis).toContain("verbrannt");
    expect(proSpieler.p3.status).toBe("🙈 LEER AUSGEGANGEN");
  });

  it("Determinismus: identisches Skript ⇒ Bit für Bit identischer End-State", () => {
    const lauf = (): string => {
      const { ctx, state, spieler } = setup(["p1", "p2", "p3"], 7);
      let s = state;
      s = fensterDurchspielen(s, ctx, spieler);
      s = fensterDurchspielen(s, ctx, ["p1", "p2"]);
      s = affenbankPlugin.reduce(s, bank("p3", ctx.clock.now() + 333), ctx) as AffenbankState;
      s = fensterDurchspielen(s, ctx, spieler);
      return JSON.stringify(s);
    };
    expect(lauf()).toBe(lauf());
  });

  it("hält den State JSON-serialisierbar + Fenster-Auswertung exakt am Serverfenster-Ende", () => {
    const { ctx, state } = setup();
    const anDerKante = affenbankPlugin.reduce(
      state,
      antwort("p1", 2, state.frageEndetAt),
      ctx,
    ) as AffenbankState;
    expect(anDerKante.answers.p1).toBe(2); // Empfang == Fenster-Ende zählt noch
    const kopie = JSON.parse(JSON.stringify(anDerKante)) as AffenbankState;
    expect(affenbankPlugin.scores(kopie)).toEqual(affenbankPlugin.scores(anDerKante));
  });
});
