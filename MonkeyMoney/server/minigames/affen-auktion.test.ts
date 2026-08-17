// Affen-Auktion: Gebots-Mathe-Goldens (25er-Raster, Limits aus dem Konto,
// Verteil-Anteil auf 10er ABgerundet), Anti-Sniping-Verlängerung inkl. harter
// Kappe, Selbst-Überbieten-Wache, exklusives Antwortrecht, exakte Abrechnung
// (richtig = +Gebot, falsch/Timeout = Gebot an alle anderen — NULLSUMME),
// Disconnect-Erstattung + Reconnect, Joker (50:50/removeOne/secondTry),
// GM-Kommandos, Leak-Wache (Frage-Text erst im Frage-Fenster).
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  AA_AUKTION_MAX_EXTRA_MS,
  AA_AUKTION_MS,
  aaKlemmeGebot,
  aaMaxGebot,
  aaVerteilAnteil,
  type AffenAuktionAction,
} from "../../shared/minigames/affen-auktion.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, JokerAction, PlayerAction } from "./_api/plugin";
import { affenAuktionPlugin, type AffenAuktionState } from "./affen-auktion/index";

function frage(): Question {
  return {
    id: "q_auktion",
    kind: "choice4",
    category: "affen_wissen",
    difficulty: "hard",
    text: "Wie viele Bananen isst ein Affe pro Tag?",
    options: ["1", "7", "12", "50"],
    answer: 1,
    erklaerung: "Sieben — eine pro Wochentag.",
  };
}

function setup(balances?: Record<string, number>) {
  const clock = createTestClock(0);
  const spieler = ["p1", "p2", "p3", "p4"].map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(7) };
  if (balances) {
    ctx.match = {
      balance: (p: PlayerId) => balances[p] ?? 0,
      reihenfolge: () => spieler,
      hatKlauSchutz: () => false,
      istVerbunden: () => true,
    };
  }
  const content: ContentSlice = { questions: [frage()] };
  const state = affenAuktionPlugin.init(spieler, content, ctx) as AffenAuktionState;
  return { clock, ctx, state, spieler };
}

function aktion(
  playerId: string,
  a: AffenAuktionAction,
  at: number,
): PlayerAction<AffenAuktionAction> {
  return { kind: "player", playerId: asPlayerId(playerId), action: a, atServerTime: at };
}

function bieten(p: string, at: number): PlayerAction<AffenAuktionAction> {
  return aktion(p, { type: "bieten" }, at);
}

/** Hammer fallen lassen: Uhr bis nach dem Auktionsende, dann tick. */
function hammer(s: AffenAuktionState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.auktionEndetAt - clock.now()) + 1);
  return affenAuktionPlugin.tick(s, ctx) as AffenAuktionState;
}

function nullsumme(scores: Record<PlayerId, number>): number {
  return Object.values(scores).reduce((a, b) => a + b, 0);
}

describe("affen-auktion: Gebots-Mathe (Goldens §2.12/5)", () => {
  it("aaMaxGebot: Konto aufs 25er-Raster, Klemme [100, 1.000]", () => {
    expect(aaMaxGebot(0)).toBe(100); // Pleite-Affe darf trotzdem bis 100
    expect(aaMaxGebot(99)).toBe(100);
    expect(aaMaxGebot(260)).toBe(250); // 260 → 250 (abgerundet)
    expect(aaMaxGebot(1_000)).toBe(1_000);
    expect(aaMaxGebot(9_999)).toBe(1_000); // absolute Kappe
  });

  it("aaKlemmeGebot: Raster + Mindestschritt + Limit; null wenn unmöglich", () => {
    expect(aaKlemmeGebot(140, 100, 1_000)).toBe(150); // 140 → 150 (gerundet)
    expect(aaKlemmeGebot(50, 100, 1_000)).toBe(125); // unter Mindest → Höchst+25
    expect(aaKlemmeGebot(5_000, 100, 250)).toBe(250); // aufs Limit geklemmt
    expect(aaKlemmeGebot(500, 250, 250)).toBeNull(); // Mindest 275 > Limit
  });

  it("aaVerteilAnteil: floor(Gebot/(N−1) auf 10er) — Rest bleibt beim Gewinner", () => {
    expect(aaVerteilAnteil(175, 3)).toBe(50); // 58,33 → 50
    expect(aaVerteilAnteil(300, 3)).toBe(100); // glatt
    expect(aaVerteilAnteil(25, 3)).toBe(0); // Mini-Gebot verpufft
    expect(aaVerteilAnteil(100, 0)).toBe(0); // theoretisch: keine anderen
  });
});

describe("affen-auktion: Auktion + Abrechnung (exakt)", () => {
  it("BIETEN +25 im Raster; Historie wächst; Höchstbietender wechselt", () => {
    const { ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    expect(s.hoechstgebot).toBe(25);
    expect(s.hoechstbietender).toBe("p1");
    s = affenAuktionPlugin.reduce(s, bieten("p2", 2_000), ctx) as AffenAuktionState;
    expect(s.hoechstgebot).toBe(50);
    expect(s.hoechstbietender).toBe("p2");
    expect(s.gebotHistorie).toHaveLength(2);
    expect(s.gebotHistorie[1]).toEqual({ playerId: "p2", betrag: 50, atMs: 2_000 });
  });

  it("Selbst-Überbieten ist gesperrt (bieten UND einsatz)", () => {
    const { ctx, state } = setup();
    const s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    expect(affenAuktionPlugin.reduce(s, bieten("p1", 1_100), ctx)).toBe(s);
    expect(
      affenAuktionPlugin.reduce(s, aktion("p1", { type: "einsatz", betrag: 500 }, 1_200), ctx),
    ).toBe(s);
  });

  it("„erhöhe auf Betrag“ klemmt aufs Limit; über dem Limit verpufft das Gebot", () => {
    const { ctx, state } = setup({ p1: 10_000, p2: 260, p3: 10_000, p4: 10_000 });
    // p2-Limit = 250 (260 im 25er-Raster).
    let s = affenAuktionPlugin.reduce(
      state,
      aktion("p2", { type: "einsatz", betrag: 9_999 }, 1_000),
      ctx,
    ) as AffenAuktionState;
    expect(s.hoechstgebot).toBe(250);
    // p1 überbietet auf 275 — p2 kann nicht mehr (Mindest 300 > Limit 250).
    s = affenAuktionPlugin.reduce(s, bieten("p1", 2_000), ctx) as AffenAuktionState;
    expect(s.hoechstgebot).toBe(275);
    expect(affenAuktionPlugin.reduce(s, bieten("p2", 3_000), ctx)).toBe(s);
  });

  it("Anti-Sniping: Gebot in den letzten 5 s ⇒ +5 s; harte Kappe +20 s", () => {
    const { ctx, state } = setup();
    // Frühes Gebot verlängert NICHT.
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    expect(s.auktionEndetAt).toBe(AA_AUKTION_MS);
    // Gebot bei 16 s (letzte 5 s) ⇒ Hammer auf 21 s.
    s = affenAuktionPlugin.reduce(s, bieten("p2", 16_000), ctx) as AffenAuktionState;
    expect(s.auktionEndetAt).toBe(21_000);
    // Bieterschlacht bis zur Kappe: nie über startedAt + 20 s + 20 s.
    const spieler = ["p3", "p1", "p2", "p3", "p1", "p2", "p3", "p1"];
    let at = 20_500;
    for (const p of spieler) {
      s = affenAuktionPlugin.reduce(s, bieten(p, at), ctx) as AffenAuktionState;
      at += 2_500;
    }
    expect(s.auktionEndetAt).toBeLessThanOrEqual(AA_AUKTION_MS + AA_AUKTION_MAX_EXTRA_MS);
    expect(s.auktionMaxEndetAt).toBe(AA_AUKTION_MS + AA_AUKTION_MAX_EXTRA_MS);
  });

  it("Keine Gebote ⇒ Frage verfällt, alle Scores 0, niemand gewertet", () => {
    const { clock, ctx, state } = setup();
    const s = hammer(state, ctx, clock);
    expect(affenAuktionPlugin.isFinished(s)).toBe(true);
    const scores = affenAuktionPlugin.scores(s);
    expect(nullsumme(scores)).toBe(0);
    expect(scores[asPlayerId("p1")]).toBe(0);
    const outcomes = affenAuktionPlugin.outcomes!(s);
    for (const p of ["p1", "p2", "p3", "p4"]) {
      expect(outcomes[asPlayerId(p)].correct).toBeNull();
    }
  });

  it("RICHTIG: Gewinner +Gebot aus der Bank, alle anderen 0", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(
      state,
      aktion("p1", { type: "einsatz", betrag: 175 }, 1_000),
      ctx,
    ) as AffenAuktionState;
    s = hammer(s, ctx, clock);
    expect(s.phase).toBe("frage");
    s = affenAuktionPlugin.reduce(
      s,
      aktion("p1", { type: "answer", choice: 1 }, clock.now() + 3_000),
      ctx,
    ) as AffenAuktionState;
    s = affenAuktionPlugin.tick(s, ctx) as AffenAuktionState;
    expect(affenAuktionPlugin.isFinished(s)).toBe(true);
    const scores = affenAuktionPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(175);
    expect(scores[asPlayerId("p2")]).toBe(0);
    expect(nullsumme(scores)).toBe(175); // Bank zahlt — bewusst KEINE Nullsumme
    expect(affenAuktionPlugin.outcomes!(s)[asPlayerId("p1")]).toEqual({
      correct: true,
      nachMs: 3_000,
    });
  });

  it("FALSCH: Gebot 175 an 3 andere = 3×50, Gewinner zahlt EXAKT 150 (Nullsumme)", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(
      state,
      aktion("p2", { type: "einsatz", betrag: 175 }, 1_000),
      ctx,
    ) as AffenAuktionState;
    s = hammer(s, ctx, clock);
    s = affenAuktionPlugin.reduce(
      s,
      aktion("p2", { type: "answer", choice: 3 }, clock.now() + 2_000),
      ctx,
    ) as AffenAuktionState;
    s = affenAuktionPlugin.tick(s, ctx) as AffenAuktionState;
    const scores = affenAuktionPlugin.scores(s);
    expect(scores[asPlayerId("p2")]).toBe(-150); // NICHT −175: Rundungsrest bleibt
    expect(scores[asPlayerId("p1")]).toBe(50);
    expect(scores[asPlayerId("p3")]).toBe(50);
    expect(scores[asPlayerId("p4")]).toBe(50);
    expect(nullsumme(scores)).toBe(0); // Invariante: Falsch-Fall ist nullsummig
  });

  it("TIMEOUT ohne Antwort = falsch: Verteilung läuft, outcome correct=false", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p3", 1_000), ctx) as AffenAuktionState;
    s = hammer(s, ctx, clock); // Gebot 25 → Anteil floor(25/3/10)*10 = 0
    clock.advance(s.timerMs + SPAETANTWORT_GNADE_MS + 1);
    s = affenAuktionPlugin.tick(s, ctx) as AffenAuktionState;
    expect(affenAuktionPlugin.isFinished(s)).toBe(true);
    const scores = affenAuktionPlugin.scores(s);
    expect(scores[asPlayerId("p3")]).toBe(0); // Anteil 0 ⇒ Gewinner zahlt 0
    expect(nullsumme(scores)).toBe(0);
    expect(affenAuktionPlugin.outcomes!(s)[asPlayerId("p3")].correct).toBe(false);
  });

  it("Exklusiv-Wache: Nicht-Gewinner-Antworten und Späte Antworten verpuffen", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    // Antwort im Setz-Fenster: verworfen.
    expect(
      affenAuktionPlugin.reduce(s, aktion("p1", { type: "answer", choice: 1 }, 2_000), ctx),
    ).toBe(s);
    s = hammer(s, ctx, clock);
    // p2 hat nicht gewonnen — Antwort verpufft.
    expect(
      affenAuktionPlugin.reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now()), ctx),
    ).toBe(s);
    // Antwort NACH Deadline + Gnade: verworfen.
    const zuSpaet = (s.frageEndetAt ?? 0) + SPAETANTWORT_GNADE_MS + 1;
    expect(
      affenAuktionPlugin.reduce(s, aktion("p1", { type: "answer", choice: 1 }, zuSpaet), ctx),
    ).toBe(s);
    // Innerhalb der Gnade zählt sie noch.
    const inGnade = affenAuktionPlugin.reduce(
      s,
      aktion("p1", { type: "answer", choice: 1 }, (s.frageEndetAt ?? 0) + SPAETANTWORT_GNADE_MS),
      ctx,
    ) as AffenAuktionState;
    expect(inGnade.answer?.choice).toBe(1);
  });

  it("Gebote nach dem Hammer verpuffen; kein Bieten im Frage-Fenster", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    // Gebot NACH auktionEndetAt (atServerTime zu spät): verworfen.
    expect(affenAuktionPlugin.reduce(s, bieten("p2", s.auktionEndetAt), ctx)).toBe(s);
    s = hammer(s, ctx, clock);
    expect(s.phase).toBe("frage");
    expect(affenAuktionPlugin.reduce(s, bieten("p2", clock.now()), ctx)).toBe(s);
  });

  it("Disconnect des Gewinners: Gebot erstattet (alle 0); Reconnect hebt auf", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(
      state,
      aktion("p1", { type: "einsatz", betrag: 300 }, 1_000),
      ctx,
    ) as AffenAuktionState;
    s = hammer(s, ctx, clock);
    s = affenAuktionPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as AffenAuktionState;
    expect(s.erstattet).toBe(true);
    // Alternative A: Reconnect im Fenster ⇒ Erstattung aufgehoben, Antwort zählt.
    let zurueck = affenAuktionPlugin.onReconnect(s, asPlayerId("p1"), ctx) as AffenAuktionState;
    expect(zurueck.erstattet).toBe(false);
    zurueck = affenAuktionPlugin.reduce(
      zurueck,
      aktion("p1", { type: "answer", choice: 1 }, (zurueck.frageEndetAt ?? 0) - 1_000),
      ctx,
    ) as AffenAuktionState;
    zurueck = affenAuktionPlugin.tick(zurueck, ctx) as AffenAuktionState;
    expect(affenAuktionPlugin.scores(zurueck)[asPlayerId("p1")]).toBe(300);
    // Alternative B: Timeout ohne Reconnect ⇒ Frage verfällt OHNE Strafe.
    clock.advance(s.timerMs + SPAETANTWORT_GNADE_MS + 1);
    const verfallen = affenAuktionPlugin.tick(s, ctx) as AffenAuktionState;
    expect(nullsumme(affenAuktionPlugin.scores(verfallen))).toBe(0);
    expect(affenAuktionPlugin.scores(verfallen)[asPlayerId("p1")]).toBe(0);
    expect(affenAuktionPlugin.outcomes!(verfallen)[asPlayerId("p1")].correct).toBeNull();
  });

  it("Joker: 50:50 + removeOne sperren nur falsche Optionen, NUR beim Gewinner", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    // Im Setz-Fenster: Joker verpufft.
    const fifty: JokerAction = { kind: "joker", type: "fiftyFifty", playerId: asPlayerId("p1") };
    expect(affenAuktionPlugin.reduce(s, fifty, ctx)).toBe(s);
    s = hammer(s, ctx, clock);
    // Nicht-Gewinner-Joker verpufft.
    const fremd: JokerAction = { kind: "joker", type: "fiftyFifty", playerId: asPlayerId("p2") };
    expect(affenAuktionPlugin.reduce(s, fremd, ctx)).toBe(s);
    s = affenAuktionPlugin.reduce(s, fifty, ctx) as AffenAuktionState;
    expect(s.gesperrt).toHaveLength(2);
    expect(s.gesperrt).not.toContain(1); // die richtige bleibt IMMER offen
    // removeOne danach: nur noch 1 falsche offen ⇒ verpufft (eine muss stehen bleiben).
    const remove: JokerAction = { kind: "joker", type: "removeOne", playerId: asPlayerId("p1") };
    expect(affenAuktionPlugin.reduce(s, remove, ctx)).toBe(s);
    // Gesperrte Option kann nicht gewählt werden.
    const zu = s.gesperrt[0] as 0 | 1 | 2 | 3;
    expect(
      affenAuktionPlugin.reduce(s, aktion("p1", { type: "answer", choice: zu }, clock.now()), ctx),
    ).toBe(s);
  });

  it("secondTry: falsche Antwort zurück, Option gesperrt — Gewinn nur ×0,5 (10er)", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(
      state,
      aktion("p1", { type: "einsatz", betrag: 175 }, 1_000),
      ctx,
    ) as AffenAuktionState;
    s = hammer(s, ctx, clock);
    s = affenAuktionPlugin.reduce(
      s,
      aktion("p1", { type: "answer", choice: 2 }, clock.now() + 1_000),
      ctx,
    ) as AffenAuktionState;
    const st: JokerAction = { kind: "joker", type: "secondTry", playerId: asPlayerId("p1") };
    s = affenAuktionPlugin.reduce(s, st, ctx) as AffenAuktionState;
    expect(s.answer).toBeNull();
    expect(s.gesperrt).toContain(2);
    expect(s.zweitversuch).toBe(true);
    s = affenAuktionPlugin.reduce(
      s,
      aktion("p1", { type: "answer", choice: 1 }, clock.now() + 2_000),
      ctx,
    ) as AffenAuktionState;
    s = affenAuktionPlugin.tick(s, ctx) as AffenAuktionState;
    // 175/2 = 87,5 → rundeAuf10 = 90.
    expect(affenAuktionPlugin.scores(s)[asPlayerId("p1")]).toBe(90);
    expect(affenAuktionPlugin.outcomes!(s)[asPlayerId("p1")].zweitversuch).toBe(true);
  });

  it("GM: force.finish = Skip ohne Zahlung; timer.extend verlängert die Auktion", () => {
    const { ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    const extend: GmAction = { kind: "gm", type: "timer.extend", ms: 10_000 };
    const laenger = affenAuktionPlugin.reduce(s, extend, ctx) as AffenAuktionState;
    expect(laenger.auktionEndetAt).toBe(s.auktionEndetAt + 10_000);
    expect(laenger.auktionMaxEndetAt).toBe(s.auktionMaxEndetAt + 10_000);
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    s = affenAuktionPlugin.reduce(s, skip, ctx) as AffenAuktionState;
    expect(affenAuktionPlugin.isFinished(s)).toBe(true);
    expect(nullsumme(affenAuktionPlugin.scores(s))).toBe(0);
    expect(affenAuktionPlugin.scores(s)[asPlayerId("p1")]).toBe(0);
  });

  it("Leak-Wache: Frage-Text/Optionen ERST im Frage-Fenster, exklusiv beim Gewinner", () => {
    const { clock, ctx, state } = setup();
    let s = affenAuktionPlugin.reduce(state, bieten("p1", 1_000), ctx) as AffenAuktionState;
    const setzScreen = affenAuktionPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(setzScreen.text).toBeNull();
    expect(setzScreen.options).toBeNull();
    expect(setzScreen.kategorie).toBe("affen_wissen"); // Teaser bleibt sichtbar
    const setzPlayer = affenAuktionPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(setzPlayer.correctIndex).toBeUndefined();
    expect(setzPlayer.einsatzMax).toBeGreaterThanOrEqual(100);
    s = hammer(s, ctx, clock);
    const gewinner = affenAuktionPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(gewinner.options).toEqual(["1", "7", "12", "50"]);
    expect(gewinner.duBistGewinner).toBe(true);
    const zuschauer = affenAuktionPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(zuschauer.options).toBeNull(); // KEIN Antwortrecht
    expect(zuschauer.zuschauerOptionen).toEqual(["1", "7", "12", "50"]); // mitraten ja
    const gm = affenAuktionPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
  });
});
