// Bananen-Boxkampf: HP-Mathe-Goldens (Punch-Power nach Frage-Wert, K.O.-Grenzen),
// Herausforderer-Prinzip (Letzter wählt, Feiglings-Schutz, Timeout = Führender),
// Wett-Fenster (nur Zuschauer, einrasten, geheim bis Wettschluss, Nullsumme),
// Buzzer-Reihenfolge (schnellere richtige Antwort schlägt ZUERST, K.O. schluckt
// den Konter, Fotofinish-Los), Punktsieg/Unentschieden nach BX_RUNDEN,
// Disconnect (kampflos/Abbruch), 2-Spieler-Sonderfall, GM-Kommandos,
// Leak-Wachen und Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import type { Schwierigkeit } from "../../shared/money";
import {
  BX_GETEILT_MM,
  BX_MAX_HP,
  BX_PUNCH,
  BX_RUNDEN,
  BX_SIEG_KO_MM,
  BX_SIEG_PUNKTE_MM,
  BX_WETTE_MM,
  bxSiegPraemie,
  bxWettAbrechnung,
  type BoxkampfAction,
} from "../../shared/minigames/bananen-boxkampf.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { boxkampfPlugin, bxGegnerKandidaten, type BoxkampfState } from "./bananen-boxkampf/index";

function fragen(n: number, difficulty: Schwierigkeit = "hard"): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_bx_${i + 1}`,
    kind: "choice4" as const,
    category: "affen_wissen",
    difficulty,
    text: `Ring-Frage ${i + 1}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  }));
}

// Konten: p4 ist der Letzte (Herausforderer), p1 der Führende, p3 der ärmste
// GEGNER (Feiglings-Schutz).
const KONTEN = { p1: 2_000, p2: 1_500, p3: 1_000, p4: 500 };

function setup(
  opts: {
    balances?: Record<string, number> | null;
    spieler?: string[];
    seed?: number;
    difficulty?: Schwierigkeit;
  } = {},
) {
  const clock = createTestClock(0);
  const spieler = (opts.spieler ?? ["p1", "p2", "p3", "p4"]).map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const balances: Record<string, number> | null =
    opts.balances === undefined ? KONTEN : opts.balances;
  if (balances !== null) {
    ctx.match = {
      balance: (p: PlayerId) => balances[p] ?? 0,
      reihenfolge: () => spieler,
      hatKlauSchutz: () => false,
      istVerbunden: () => true,
    };
  }
  const content: ContentSlice = { questions: fragen(8, opts.difficulty ?? "hard") };
  const state = boxkampfPlugin.init(spieler, content, ctx) as BoxkampfState;
  return { clock, ctx, state, spieler };
}

function aktion(p: string, a: BoxkampfAction, at: number): PlayerAction<BoxkampfAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(s: BoxkampfState, a: PlayerAction<BoxkampfAction> | GmAction, ctx: Ctx) {
  return boxkampfPlugin.reduce(s, a, ctx) as BoxkampfState;
}

function tick(s: BoxkampfState, ctx: Ctx) {
  return boxkampfPlugin.tick(s, ctx) as BoxkampfState;
}

/** Uhr bis nach dem Phasen-Ende, dann tick (Phasen-Übergang erzwingen). */
function phaseVorbei(s: BoxkampfState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndsAt - clock.now()) + 1);
  return tick(s, ctx);
}

/** Standard-Einstieg: p4 fordert p1, die Zuschauer wetten, Countdown startet. */
function inDenRing(
  state: BoxkampfState,
  ctx: Ctx,
  wetten: Record<string, string> = { p2: "p1", p3: "p4" },
) {
  let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 1_000), ctx);
  expect(s.phase).toBe("wetten");
  for (const [w, auf] of Object.entries(wetten)) {
    s = reduce(s, aktion(w, { type: "wette", auf }, 2_000), ctx);
  }
  s = tick(s, ctx); // alle Zuschauer gewettet ⇒ Countdown sofort
  expect(s.phase).toBe("countdown");
  return s;
}

/**
 * Einen Schlagabtausch spielen: Countdown ablaufen lassen, Antworten einspeisen
 * (nachMs relativ zum Frage-Start), auswerten — endet im Schlag-Beat oder
 * (Boxer offline) direkt im Ergebnis.
 */
function spieleAbtausch(
  s: BoxkampfState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
  antworten: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[],
) {
  expect(s.phase).toBe("countdown");
  s = phaseVorbei(s, ctx, clock);
  expect(s.phase).toBe("frage");
  const start = s.frageStartetAt ?? 0;
  for (const a of antworten) {
    s = reduce(s, aktion(a.p, { type: "answer", choice: a.choice }, start + a.nachMs), ctx);
  }
  if (antworten.length < 2) {
    clock.advance(s.phaseEndsAt + SPAETANTWORT_GNADE_MS - clock.now() + 1);
  }
  return tick(s, ctx);
}

function summe(scores: Record<PlayerId, number>): number {
  return Object.values(scores).reduce((a, b) => a + b, 0);
}

describe("bananen-boxkampf: HP-Mathe (Goldens)", () => {
  it("Punch-Power nach Frage-Wert: HARD trifft in genau 4 sauberen Schlägen K.O.", () => {
    expect(BX_PUNCH.easy * 6).toBeLessThan(BX_MAX_HP); // easy braucht 7 Treffer
    expect(BX_PUNCH.easy * 7).toBeGreaterThanOrEqual(BX_MAX_HP);
    expect(BX_PUNCH.medium * 5).toBe(BX_MAX_HP);
    expect(BX_PUNCH.hard * 4).toBeGreaterThanOrEqual(BX_MAX_HP);
    expect(BX_PUNCH.hard * 3).toBeLessThan(BX_MAX_HP); // 3 reichen NICHT
    expect(BX_PUNCH.ultrahard * 3).toBeGreaterThanOrEqual(BX_MAX_HP);
  });

  it("Sieg-Prämien: K.O. 400, Punktsieg/kampflos 300", () => {
    expect(bxSiegPraemie(true)).toBe(BX_SIEG_KO_MM);
    expect(bxSiegPraemie(false)).toBe(BX_SIEG_PUNKTE_MM);
  });

  it("HP klemmen bei 0 (kein negativer Balken) — Schaden wirkt exakt einmal", () => {
    const { clock, ctx, state } = setup({ difficulty: "ultrahard" });
    let s = inDenRing(state, ctx);
    for (let i = 0; i < 3; i++) {
      s = spieleAbtausch(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ]);
      if (s.phase === "schlag") s = phaseVorbei(s, ctx, clock);
    }
    // 3 × 40 = 120 > 100 ⇒ HP exakt 0, nie negativ.
    expect(s.hp.p1).toBe(0);
    expect(s.phase).toBe("ergebnis");
    expect(s.ko).toBe(true);
  });
});

describe("bananen-boxkampf: Herausforderer-Prinzip + Feiglings-Schutz", () => {
  it("der Letzte fordert; der ärmste Gegner ist geschützt; Fremd-Wahl verpufft", () => {
    const { ctx, state } = setup();
    expect(state.phase).toBe("herausforderung");
    expect(state.herausforderer).toBe("p4"); // 500 MM = Letzter
    const kandidaten = bxGegnerKandidaten(state);
    expect(kandidaten.find((k) => k.id === "p3")?.waehlbar).toBe(false); // Feiglings-Schutz
    expect(kandidaten.find((k) => k.id === "p1")?.waehlbar).toBe(true);
    expect(reduce(state, aktion("p4", { type: "herausfordern", targetId: "p3" }, 500), ctx)).toBe(
      state,
    );
    expect(reduce(state, aktion("p1", { type: "herausfordern", targetId: "p2" }, 500), ctx)).toBe(
      state,
    );
    const s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p2" }, 500), ctx);
    expect(s.gegner).toBe("p2");
    expect(s.hp).toEqual({ p4: BX_MAX_HP, p2: BX_MAX_HP });
  });

  it("Timeout wählt den Führenden als Gegner („der Führende steigt in den Ring“)", () => {
    const { clock, ctx, state } = setup();
    const s = phaseVorbei(state, ctx, clock);
    expect(s.gegner).toBe("p1"); // 2.000 MM = Führender
    expect(s.phase).toBe("wetten");
  });

  it("2-Spieler-Spiel: Gegner fix, KEINE Herausforderungs-/Wett-Phase, direkt Countdown", () => {
    const { state } = setup({ spieler: ["p1", "p2"], balances: { p1: 800, p2: 400 } });
    expect(state.phase).toBe("countdown");
    expect(state.herausforderer).toBe("p2");
    expect(state.gegner).toBe("p1");
    expect(state.wettenGeschlossen).toBe(true);
    expect(state.rundeNr).toBe(1);
  });
});

describe("bananen-boxkampf: Wett-Fenster", () => {
  it("nur Zuschauer wetten (einrasten, nur auf Boxer); alle gewettet ⇒ Countdown", () => {
    const { ctx, state } = setup();
    let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 500), ctx);
    expect(reduce(s, aktion("p4", { type: "wette", auf: "p4" }, 1_000), ctx)).toBe(s); // Boxer
    expect(reduce(s, aktion("p2", { type: "wette", auf: "p3" }, 1_000), ctx)).toBe(s); // auf Zuschauer
    s = reduce(s, aktion("p2", { type: "wette", auf: "p1" }, 1_000), ctx);
    const doppelt = reduce(s, aktion("p2", { type: "wette", auf: "p4" }, 1_500), ctx);
    expect(doppelt.wetten.p2).toBe("p1"); // eingerastet
    s = reduce(doppelt, aktion("p3", { type: "wette", auf: "p4" }, 2_000), ctx);
    s = tick(s, ctx);
    expect(s.phase).toBe("countdown"); // vor Fenster-Ende — alle haben gewettet
    expect(s.wettenGeschlossen).toBe(true);
  });

  it("Leak-Wache: Wetten GEHEIM bis Wettschluss (nur Anzahl), GM sieht sie immer", () => {
    const { ctx, state } = setup();
    let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 500), ctx);
    s = reduce(s, aktion("p2", { type: "wette", auf: "p1" }, 1_000), ctx);
    const geheim = boxkampfPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(geheim.wetten).toBeNull();
    expect(geheim.wettenAnzahl).toBe(1);
    const spieler = boxkampfPlugin.viewFor(s, "player", asPlayerId("p3")) as Record<
      string,
      unknown
    >;
    expect(spieler.wetten).toBeNull();
    expect(spieler.deineWette).toBeNull();
    const gm = boxkampfPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.wetten).toEqual({ p2: "p1" });
    s = reduce(s, aktion("p3", { type: "wette", auf: "p4" }, 2_000), ctx);
    s = tick(s, ctx);
    const offen = boxkampfPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(offen.wetten).toEqual({ p2: "p1", p3: "p4" });
  });

  it("Wett-Nullsumme (Re-Export-Golden): Σ Deltas + Rest an den Sieger = 0", () => {
    // 3 Wetter, 2 richtig: Topf 150, Anteil 70 ⇒ +20/+20/−50, Rest 10.
    const w = bxWettAbrechnung({ z1: "a", z2: "a", z3: "b" }, "a");
    expect(w.deltas.z1).toBe(20);
    expect(w.deltas.z3).toBe(-BX_WETTE_MM);
    expect(w.restAnSieger).toBe(10);
    expect(summe(w.deltas as Record<PlayerId, number>) + w.restAnSieger).toBe(0);
    const zurueck = bxWettAbrechnung({ z1: "a" }, null);
    expect(zurueck.deltas.z1).toBe(0);
  });
});

describe("bananen-boxkampf: Schlagabtausch + Buzzer-Reihenfolge", () => {
  it("einer richtig ⇒ EIN Schlag mit Frage-Wert-Schaden; beide falsch ⇒ nichts", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx);
    s = spieleAbtausch(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 800 },
      { p: "p1", choice: 0, nachMs: 900 },
    ]);
    expect(s.phase).toBe("schlag");
    expect(s.letzterAbtausch?.schlaege).toEqual([
      { von: "p4", schaden: BX_PUNCH.hard, konter: false, ko: false },
    ]);
    expect(s.hp.p1).toBe(BX_MAX_HP - BX_PUNCH.hard);
    s = phaseVorbei(s, ctx, clock);
    s = spieleAbtausch(s, ctx, clock, [
      { p: "p4", choice: 2, nachMs: 500 },
      { p: "p1", choice: 3, nachMs: 600 },
    ]);
    expect(s.letzterAbtausch?.schlaege).toEqual([]);
    expect(s.hp).toEqual({ p4: BX_MAX_HP, p1: BX_MAX_HP - BX_PUNCH.hard });
  });

  it("beide richtig ⇒ der Schnellere schlägt ZUERST, der Langsamere kontert", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx);
    s = spieleAbtausch(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p4", choice: 1, nachMs: 900 }, // >40 ms später — kein Fotofinish
    ]);
    expect(s.letzterAbtausch?.fotofinish).toBe(false);
    expect(s.letzterAbtausch?.schlaege).toEqual([
      { von: "p1", schaden: BX_PUNCH.hard, konter: false, ko: false },
      { von: "p4", schaden: BX_PUNCH.hard, konter: true, ko: false },
    ]);
    expect(s.hp).toEqual({ p4: BX_MAX_HP - BX_PUNCH.hard, p1: BX_MAX_HP - BX_PUNCH.hard });
  });

  it("Erstschlag bringt den Gegner auf 0 ⇒ der KONTER ENTFÄLLT (K.O. ist K.O.)", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx);
    // 3 saubere Treffer von p4 (p1 falsch) ⇒ p1 bei 10 HP.
    for (let i = 0; i < 3; i++) {
      s = spieleAbtausch(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ]);
      s = phaseVorbei(s, ctx, clock);
    }
    expect(s.hp.p1).toBe(BX_MAX_HP - 3 * BX_PUNCH.hard);
    // Abtausch 4: BEIDE richtig, p4 schneller ⇒ K.O., p1s Konter entfällt.
    s = spieleAbtausch(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 400 },
      { p: "p1", choice: 1, nachMs: 900 },
    ]);
    expect(s.letzterAbtausch?.schlaege).toEqual([
      { von: "p4", schaden: BX_PUNCH.hard, konter: false, ko: true },
    ]);
    expect(s.hp.p1).toBe(0);
    expect(s.hp.p4).toBe(BX_MAX_HP); // KEIN Konter durch den K.O.-Gegner
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    expect(s.ko).toBe(true);
    expect(s.sieger).toBe("p4");
  });

  it("K.O.-Abrechnung: 400 Bank + Wett-Topf; Σ Deltas = NUR die Bank-Prämie", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx, { p2: "p1", p3: "p4" });
    for (let i = 0; i < 4; i++) {
      s = spieleAbtausch(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ]);
      if (s.phase === "schlag") s = phaseVorbei(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    expect(s.ko).toBe(true);
    s = phaseVorbei(s, ctx, clock);
    expect(boxkampfPlugin.isFinished(s)).toBe(true);
    const scores = boxkampfPlugin.scores(s);
    // p3 wettete richtig auf p4: Topf 100, 1 Richtiger ⇒ +50; p2 −50.
    expect(scores[asPlayerId("p4")]).toBe(BX_SIEG_KO_MM);
    expect(scores[asPlayerId("p1")]).toBe(0); // der Verlierer zahlt NICHTS
    expect(scores[asPlayerId("p3")]).toBe(BX_WETTE_MM);
    expect(scores[asPlayerId("p2")]).toBe(-BX_WETTE_MM);
    expect(summe(scores)).toBe(BX_SIEG_KO_MM);
    const outcomes = boxkampfPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p4")].correct).toBe(true);
    expect(outcomes[asPlayerId("p1")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBe(true); // Wette richtig
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
  });

  it("kein K.O. nach BX_RUNDEN Fragen ⇒ PUNKTSIEG (mehr Rest-HP gewinnt)", () => {
    const { clock, ctx, state } = setup({ difficulty: "easy" }); // 15 Schaden
    let s = inDenRing(state, ctx, { p2: "p1", p3: "p4" });
    for (let i = 0; i < BX_RUNDEN; i++) {
      // Nur Abtausch 1 trifft (p4) — danach schlagen beide daneben: kein K.O.
      const antworten: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[] =
        i === 0
          ? [
              { p: "p4", choice: 1, nachMs: 500 },
              { p: "p1", choice: 0, nachMs: 600 },
            ]
          : [
              { p: "p4", choice: 2, nachMs: 500 },
              { p: "p1", choice: 3, nachMs: 600 },
            ];
      s = spieleAbtausch(s, ctx, clock, antworten);
      expect(s.phase).toBe("schlag");
      s = phaseVorbei(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    expect(s.ko).toBe(false);
    expect(s.sieger).toBe("p4"); // 100 HP vs. 85 HP ⇒ Punktsieg
    expect(s.hp).toEqual({ p4: BX_MAX_HP, p1: BX_MAX_HP - BX_PUNCH.easy });
    s = phaseVorbei(s, ctx, clock);
    const scores = boxkampfPlugin.scores(s);
    // Wett-Topf 100, 1 Richtiger (p3) ⇒ Anteil 100 = +50, Rest 0 an den Sieger.
    expect(scores[asPlayerId("p4")]).toBe(BX_SIEG_PUNKTE_MM);
    expect(scores[asPlayerId("p3")]).toBe(BX_WETTE_MM);
    expect(scores[asPlayerId("p2")]).toBe(-BX_WETTE_MM);
    expect(summe(scores)).toBe(BX_SIEG_PUNKTE_MM);
  });

  it("HP-GLEICHSTAND nach BX_RUNDEN ⇒ UNENTSCHIEDEN: je 150, Wetten zurück", () => {
    const { clock, ctx, state } = setup({ difficulty: "easy" });
    let s = inDenRing(state, ctx, { p2: "p1", p3: "p4" });
    for (let i = 0; i < BX_RUNDEN; i++) {
      // Beide schlagen JEDE Runde daneben ⇒ 100:100 nach 8 Fragen.
      s = spieleAbtausch(s, ctx, clock, [
        { p: "p4", choice: 0, nachMs: 500 },
        { p: "p1", choice: 2, nachMs: 900 },
      ]);
      s = phaseVorbei(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    expect(s.geteilt).toBe(true);
    expect(s.sieger).toBeNull();
    s = phaseVorbei(s, ctx, clock);
    const scores = boxkampfPlugin.scores(s);
    expect(scores[asPlayerId("p4")]).toBe(BX_GETEILT_MM);
    expect(scores[asPlayerId("p1")]).toBe(BX_GETEILT_MM);
    expect(scores[asPlayerId("p2")]).toBe(0); // Wetten zurück
    expect(scores[asPlayerId("p3")]).toBe(0);
  });
});

describe("bananen-boxkampf: Disconnect + GM + Leaks + Determinismus", () => {
  it("Boxer-Disconnect mitten im Kampf ⇒ kampflos: 300 Bank, Wetten zurück", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx, { p2: "p1", p3: "p4" });
    s = phaseVorbei(s, ctx, clock); // Countdown → Frage
    s = boxkampfPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as BoxkampfState;
    expect(s.phase).toBe("ergebnis");
    expect(s.kampflos).toBe(true);
    expect(s.sieger).toBe("p4");
    s = phaseVorbei(s, ctx, clock);
    const scores = boxkampfPlugin.scores(s);
    expect(scores[asPlayerId("p4")]).toBe(BX_SIEG_PUNKTE_MM);
    expect(scores[asPlayerId("p1")]).toBe(0); // kein Abzug offline
    expect(scores[asPlayerId("p3")]).toBe(0); // Wette zurück
    expect(boxkampfPlugin.outcomes!(s)[asPlayerId("p1")].correct).toBeNull();
  });

  it("BEIDE Boxer offline ⇒ Abbruch: alle Scores 0", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx);
    s = phaseVorbei(s, ctx, clock);
    s = { ...s, connected: { ...s.connected, p1: false } };
    s = boxkampfPlugin.onDisconnect(s, asPlayerId("p4"), ctx) as BoxkampfState;
    expect(s.abgebrochen).toBe(true);
    s = phaseVorbei(s, ctx, clock);
    expect(summe(boxkampfPlugin.scores(s))).toBe(0);
  });

  it("GM force.finish VOR dem Ergebnis ⇒ Abbruch ohne Zahlung; im Ergebnis gilt es", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx, { p2: "p1", p3: "p4" });
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    const abgebrochen = reduce(s, skip, ctx);
    expect(abgebrochen.finished).toBe(true);
    expect(summe(boxkampfPlugin.scores(abgebrochen))).toBe(0);
    for (let i = 0; i < 4; i++) {
      s = spieleAbtausch(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ]);
      if (s.phase === "schlag") s = phaseVorbei(s, ctx, clock);
    }
    const fertig = reduce(s, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(boxkampfPlugin.scores(fertig)[asPlayerId("p4")]).toBe(BX_SIEG_KO_MM);
  });

  it("GM timer.extend/timer.shift verschieben die Zeitanker konsistent", () => {
    const { ctx, state } = setup();
    const s = inDenRing(state, ctx);
    const laenger = reduce(s, { kind: "gm", type: "timer.extend", ms: 5_000 }, ctx);
    expect(laenger.phaseEndsAt).toBe(s.phaseEndsAt + 5_000);
    const pause = reduce(s, { kind: "gm", type: "timer.shift", ms: 60_000 }, ctx);
    expect(pause.phaseEndsAt).toBe(s.phaseEndsAt + 60_000);
    expect(pause.startedAt).toBe(s.startedAt + 60_000);
  });

  it("Leak-Wachen: Frage nur im Fenster, correctIndex nur GM, Abtausch erst im Schlag-Beat", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx);
    const countdown = boxkampfPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(countdown.text).toBeNull();
    expect(countdown.options).toBeNull();
    s = phaseVorbei(s, ctx, clock); // → frage
    const frage = boxkampfPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(frage.text).toBe("Ring-Frage 1?");
    expect(frage.correctIndex).toBeUndefined();
    expect(frage.letzterAbtausch).toBeNull(); // Lösung erst im Schlag-Beat
    const spieler = boxkampfPlugin.viewFor(s, "player", asPlayerId("p4")) as Record<
      string,
      unknown
    >;
    expect(spieler.correctIndex).toBeUndefined();
    expect(spieler.duBistBoxer).toBe(true);
    const gm = boxkampfPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
    s = reduce(s, aktion("p4", { type: "answer", choice: 1 }, (s.frageStartetAt ?? 0) + 500), ctx);
    s = reduce(s, aktion("p1", { type: "answer", choice: 0 }, (s.frageStartetAt ?? 0) + 600), ctx);
    s = tick(s, ctx);
    const schlag = boxkampfPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect((schlag.letzterAbtausch as { correctIndex: number }).correctIndex).toBe(1);
  });

  it("Zuschauer-/Spät-/Doppel-Antworten verpuffen (die Antwort IST der Buzz)", () => {
    const { clock, ctx, state } = setup();
    let s = inDenRing(state, ctx);
    expect(reduce(s, aktion("p4", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s); // Countdown
    s = phaseVorbei(s, ctx, clock);
    expect(reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s); // Zuschauer
    const zuSpaet = s.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p4", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(s);
    s = reduce(s, aktion("p4", { type: "answer", choice: 0 }, clock.now() + 500), ctx);
    const doppelt = reduce(s, aktion("p4", { type: "answer", choice: 1 }, clock.now() + 600), ctx);
    expect(doppelt.answers.p4.choice).toBe(0);
  });

  it("Seed-Determinismus: Fotofinish-Los (<40 ms) ist mit gleichem Seed reproduzierbar", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = inDenRing(state, ctx);
      s = spieleAbtausch(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 1, nachMs: 510 }, // 10 ms Abstand ⇒ Münzwurf
      ]);
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(a.letzterAbtausch?.fotofinish).toBe(true);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});
