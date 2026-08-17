// Einer gegen alle: Geld-Mathe-Goldens (Solo-Coup 400 / beide 150 / Team 200 /
// nichts), Mehrheits-Logik inkl. Gleichstands-Los (deterministisch via ctx.rng)
// und Keine-Stimmen-Regel, Solist-Wahl (Führender via ctx.match), Leak-Wachen
// (die Mengen-Antwort erreicht den Solisten NIE vor der Enthüllung!),
// Solist-Disconnect = neutral, GM-Kommandos, Mindestbesetzung und
// Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  EGA_BEIDE_MM,
  EGA_FRAGEN,
  EGA_SOLO_MM,
  EGA_TEAM_MM,
  EINER_GEGEN_ALLE_META,
  egaFrageDeltas,
  egaMehrheit,
  type EinerGegenAlleAction,
} from "../../shared/minigames/einer-gegen-alle.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { einerGegenAllePlugin, type EinerGegenAlleState } from "./einer-gegen-alle/index";

function fragen(n: number): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_ega_${i + 1}`,
    kind: "choice4" as const,
    category: "affen_wissen",
    difficulty: "medium" as const,
    text: `Duell-Frage ${i + 1}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  }));
}

// Konten: p1 ist der Führende (Solist), p2-p4 sind die Menge.
const KONTEN: Record<string, number> = { p1: 2_500, p2: 1_500, p3: 1_000, p4: 500 };

function setup(
  opts: { balances?: Record<string, number> | null; spieler?: string[]; seed?: number } = {},
) {
  const clock = createTestClock(0);
  const spieler = (opts.spieler ?? ["p1", "p2", "p3", "p4"]).map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const balances = opts.balances === undefined ? KONTEN : opts.balances;
  if (balances !== null) {
    ctx.match = {
      balance: (p: PlayerId) => balances[p] ?? 0,
      reihenfolge: () => spieler,
      hatKlauSchutz: () => false,
      istVerbunden: () => true,
    };
  }
  const content: ContentSlice = { questions: fragen(EGA_FRAGEN) };
  const state = einerGegenAllePlugin.init(spieler, content, ctx) as EinerGegenAlleState;
  return { clock, ctx, state, spieler };
}

function aktion(p: string, choice: 0 | 1 | 2 | 3, at: number): PlayerAction<EinerGegenAlleAction> {
  return {
    kind: "player",
    playerId: asPlayerId(p),
    action: { type: "answer", choice },
    atServerTime: at,
  };
}

function reduce(
  s: EinerGegenAlleState,
  a: PlayerAction<EinerGegenAlleAction> | GmAction,
  ctx: Ctx,
) {
  return einerGegenAllePlugin.reduce(s, a, ctx) as EinerGegenAlleState;
}

function tick(s: EinerGegenAlleState, ctx: Ctx) {
  return einerGegenAllePlugin.tick(s, ctx) as EinerGegenAlleState;
}

function phaseVorbei(s: EinerGegenAlleState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndsAt - clock.now()) + SPAETANTWORT_GNADE_MS + 1);
  return tick(s, ctx);
}

/** Eine Frage spielen: Antworten einspeisen, bis in die Enthüllung auswerten. */
function spieleFrage(
  s: EinerGegenAlleState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
  antworten: Record<string, 0 | 1 | 2 | 3>,
) {
  expect(s.phase).toBe("frage");
  const start = s.frageStartetAt ?? 0;
  let nach = 300;
  for (const [p, choice] of Object.entries(antworten)) {
    s = reduce(s, aktion(p, choice, start + nach), ctx);
    nach += 200;
  }
  s = phaseVorbei(s, ctx, clock);
  expect(s.phase === "enthuellung" || s.phase === "ergebnis").toBe(true);
  return s;
}

describe("einer-gegen-alle: Geld-Mathe (egaFrageDeltas, Goldens)", () => {
  const MENGE = ["m1", "m2", "m3"];

  it("Solist richtig + Menge falsch ⇒ Solist +400, Menge nichts", () => {
    const d = egaFrageDeltas("solo", MENGE, true, false);
    expect(d).toEqual({ solo: EGA_SOLO_MM, m1: 0, m2: 0, m3: 0 });
  });

  it("beide richtig ⇒ je +150 (Solist UND jedes Mengen-Mitglied)", () => {
    const d = egaFrageDeltas("solo", MENGE, true, true);
    expect(d).toEqual({ solo: EGA_BEIDE_MM, m1: EGA_BEIDE_MM, m2: EGA_BEIDE_MM, m3: EGA_BEIDE_MM });
  });

  it("Menge richtig + Solist falsch ⇒ jedes Mengen-Mitglied +200, Solist nichts", () => {
    const d = egaFrageDeltas("solo", MENGE, false, true);
    expect(d).toEqual({ solo: 0, m1: EGA_TEAM_MM, m2: EGA_TEAM_MM, m3: EGA_TEAM_MM });
  });

  it("beide falsch ⇒ nichts (die Bank behält alles)", () => {
    const d = egaFrageDeltas("solo", MENGE, false, false);
    expect(d).toEqual({ solo: 0, m1: 0, m2: 0, m3: 0 });
  });
});

describe("einer-gegen-alle: Mehrheits-Logik (egaMehrheit)", () => {
  it("klare Mehrheit gewinnt, Verteilung stimmt", () => {
    const m = egaMehrheit({ a: 1, b: 1, c: 2 }, 4, createRng(1));
    expect(m.choice).toBe(1);
    expect(m.verteilung).toEqual([0, 2, 1, 0]);
    expect(m.gleichstand).toBe(false);
  });

  it("Gleichstand ⇒ Los via injiziertem Rng (deterministisch mit Seed)", () => {
    const a = egaMehrheit({ a: 0, b: 2 }, 4, createRng(42));
    const b = egaMehrheit({ a: 0, b: 2 }, 4, createRng(42));
    expect(a.gleichstand).toBe(true);
    expect(a.choice).toBe(b.choice); // gleicher Seed ⇒ gleiches Los
    expect([0, 2]).toContain(a.choice); // das Los fällt NUR auf Top-Optionen
  });

  it("keine Stimmen ⇒ choice null (die Menge liegt falsch)", () => {
    const m = egaMehrheit({}, 4, createRng(1));
    expect(m.choice).toBeNull();
    expect(m.verteilung).toEqual([0, 0, 0, 0]);
    // Ausreißer-Stimmen außerhalb der Optionen werden ignoriert.
    const kaputt = egaMehrheit({ a: 9 }, 4, createRng(1));
    expect(kaputt.choice).toBeNull();
  });
});

describe("einer-gegen-alle: Solist-Wahl + Mindestbesetzung", () => {
  it("der Führende des Zwischenstands wird Solist (ctx.match)", () => {
    const { state } = setup();
    expect(state.solist).toBe("p1"); // 2.500 MM = Führender
    expect(state.phase).toBe("vorstellung");
  });

  it("ohne match-API: der erste der Join-Reihenfolge; Gleichstand ⇒ früherer Join", () => {
    const { state } = setup({ balances: null, spieler: ["pa", "pb", "pc"] });
    expect(state.solist).toBe("pa");
    const gleich = setup({ balances: { x: 500, y: 500, z: 500 }, spieler: ["x", "y", "z"] });
    expect(gleich.state.solist).toBe("x");
  });

  it("meta.minPlayers ist 3 — 1 Solist braucht mindestens 2 Gegenstimmen", () => {
    expect(EINER_GEGEN_ALLE_META.minPlayers).toBe(3);
  });
});

describe("einer-gegen-alle: Runden-Ablauf + Abstimmung", () => {
  it("Solo-Coup: Solist richtig, Mehrheit falsch ⇒ +400 nur für den Solisten", () => {
    const { clock, ctx, state } = setup();
    let s = phaseVorbei(state, ctx, clock); // Vorstellung vorbei
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 0, p4: 1 });
    expect(s.letzteFrage?.solistRichtig).toBe(true);
    expect(s.letzteFrage?.mengeChoice).toBe(0); // 2× A schlägt 1× B
    expect(s.letzteFrage?.mengeRichtig).toBe(false);
    expect(s.letzteFrage?.deltas).toEqual({ p1: EGA_SOLO_MM, p2: 0, p3: 0, p4: 0 });
    expect(s.soloPunkte).toBe(1);
  });

  it("Golden-Runde über 6 Fragen: alle 4 Kombos + Gleichstands-Beat kumulieren exakt", () => {
    const { clock, ctx, state } = setup({ seed: 42 });
    let s = phaseVorbei(state, ctx, clock);
    // F1 Solo-Coup: Solist richtig, Menge einig falsch.
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 0, p4: 0 });
    s = phaseVorbei(s, ctx, clock);
    // F2 beide richtig: je +150.
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 1, p3: 1, p4: 0 });
    s = phaseVorbei(s, ctx, clock);
    // F3 Team-Triumph: Menge richtig, Solist falsch ⇒ je +200.
    s = spieleFrage(s, ctx, clock, { p1: 3, p2: 1, p3: 1, p4: 1 });
    s = phaseVorbei(s, ctx, clock);
    // F4 beide falsch: nichts.
    s = spieleFrage(s, ctx, clock, { p1: 0, p2: 2, p3: 2, p4: 2 });
    s = phaseVorbei(s, ctx, clock);
    // F5 Gleichstand in der Menge (A vs. C, beide falsch) ⇒ Los, Menge falsch;
    // Solist richtig ⇒ Solo-Coup.
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 2 });
    expect(s.letzteFrage?.gleichstand).toBe(true);
    expect([0, 2]).toContain(s.letzteFrage?.mengeChoice);
    s = phaseVorbei(s, ctx, clock);
    // F6 beide richtig.
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 1, p3: 1, p4: 1 });
    expect(s.frageNr).toBe(EGA_FRAGEN);
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    s = phaseVorbei(s, ctx, clock);
    expect(einerGegenAllePlugin.isFinished(s)).toBe(true);
    const scores = einerGegenAllePlugin.scores(s);
    // Solist: 400 + 150 + 0 + 0 + 400 + 150 = 1.100.
    expect(scores[asPlayerId("p1")]).toBe(2 * EGA_SOLO_MM + 2 * EGA_BEIDE_MM);
    // Menge: je 150 + 200 + 150 = 500.
    for (const p of ["p2", "p3", "p4"]) {
      expect(scores[asPlayerId(p)]).toBe(2 * EGA_BEIDE_MM + EGA_TEAM_MM);
    }
    expect(s.soloPunkte).toBe(2);
    expect(s.teamPunkte).toBe(1);
    const outcomes = einerGegenAllePlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true); // 5 von 6 richtig
    expect(outcomes[asPlayerId("p2")].correct).toBe(false); // Team 1 : 2 Solo
  });

  it("keine Stimmen ⇒ Menge falsch; Solist richtig kassiert den Solo-Coup", () => {
    const { clock, ctx, state } = setup();
    let s = phaseVorbei(state, ctx, clock);
    const start = s.frageStartetAt ?? 0;
    s = reduce(s, aktion("p1", 1, start + 400), ctx);
    s = phaseVorbei(s, ctx, clock); // Timeout: niemand aus der Menge stimmt
    expect(s.letzteFrage?.mengeChoice).toBeNull();
    expect(s.letzteFrage?.deltas.p1).toBe(EGA_SOLO_MM);
  });

  it("Stimmen rasten ein; Spät-/Ausreißer-Antworten verpuffen", () => {
    const { clock, ctx, state } = setup();
    let s = phaseVorbei(state, ctx, clock);
    const start = s.frageStartetAt ?? 0;
    s = reduce(s, aktion("p2", 0, start + 300), ctx);
    const doppelt = reduce(s, aktion("p2", 1, start + 400), ctx);
    expect(doppelt.answers.p2.choice).toBe(0); // eingerastet
    const zuSpaet = s.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p3", 1, zuSpaet), ctx)).toBe(s);
  });

  it("Früh-Auswertung: alle verbunden fertig ⇒ Enthüllung ohne Timeout", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2", "p3"] });
    let s = phaseVorbei(state, ctx, clock);
    const start = s.frageStartetAt ?? 0;
    s = reduce(s, aktion("p1", 1, start + 300), ctx);
    s = reduce(s, aktion("p2", 1, start + 400), ctx);
    s = reduce(s, aktion("p3", 1, start + 500), ctx);
    clock.advance(600);
    s = tick(s, ctx); // deutlich VOR dem Fenster-Ende
    expect(s.phase).toBe("enthuellung");
    expect(s.letzteFrage?.deltas).toEqual({ p1: EGA_BEIDE_MM, p2: EGA_BEIDE_MM, p3: EGA_BEIDE_MM });
  });
});

describe("einer-gegen-alle: Leak-Wachen (die Spannung des Formats)", () => {
  it("die Mengen-Verteilung erreicht den Solisten NIE vor der Enthüllung", () => {
    const { clock, ctx, state } = setup();
    let s = phaseVorbei(state, ctx, clock);
    const start = s.frageStartetAt ?? 0;
    s = reduce(s, aktion("p2", 1, start + 300), ctx);
    s = reduce(s, aktion("p3", 0, start + 400), ctx);
    const solist = einerGegenAllePlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    // Nur die ANZAHL reist (Beteiligungs-Balken) — nie Verteilung/Antworten.
    expect(solist.stimmenAbgegeben).toBe(2);
    expect(solist.letzteFrage).toBeNull();
    expect(solist.antworten).toBeUndefined();
    expect(solist.answers).toBeUndefined();
    expect(solist.verteilung).toBeUndefined();
    expect(solist.correctIndex).toBeUndefined();
    // Auch Screen und Mengen-Mitglieder sehen die Verteilung nicht früher.
    const screen = einerGegenAllePlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.letzteFrage).toBeNull();
    expect(screen.antworten).toBeUndefined();
    const mengenBlick = einerGegenAllePlugin.viewFor(s, "player", asPlayerId("p4")) as Record<
      string,
      unknown
    >;
    expect(mengenBlick.letzteFrage).toBeNull();
    expect(mengenBlick.antworten).toBeUndefined();
    // Der GM-Spickzettel sieht ALLES (inkl. Lösung + Live-Antworten).
    const gm = einerGegenAllePlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
    expect(gm.antworten).toBeDefined();
    // Erst die Enthüllung macht die Balken public.
    s = reduce(s, aktion("p1", 1, start + 500), ctx);
    s = reduce(s, aktion("p4", 1, start + 600), ctx);
    s = tick(s, ctx);
    expect(s.phase).toBe("enthuellung");
    const enthuellt = einerGegenAllePlugin.viewFor(s, "player", asPlayerId("p1")) as {
      letzteFrage: { verteilung: number[] } | null;
    };
    // Die Balken zählen NUR Mengen-Stimmen (p2: B, p3: A, p4: B) — die
    // Solist-Antwort ist kein Teil der Team-Abstimmung.
    expect(enthuellt.letzteFrage?.verteilung).toEqual([1, 2, 0, 0]);
  });

  it("Frage-Text/Optionen reisen NUR im Frage-Fenster", () => {
    const { clock, ctx, state } = setup();
    const vorab = einerGegenAllePlugin.viewFor(state, "screen") as Record<string, unknown>;
    expect(vorab.text).toBeNull();
    expect(vorab.options).toBeNull();
    let s = phaseVorbei(state, ctx, clock);
    const offen = einerGegenAllePlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(offen.text).toBe("Duell-Frage 1?");
    expect(offen.options).toEqual(["A", "B", "C", "D"]);
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 1, p3: 1, p4: 1 });
    const beat = einerGegenAllePlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(beat.text).toBeNull(); // Enthüllung zeigt den Beat, nicht die Frage
    expect((beat.letzteFrage as { correctIndex: number }).correctIndex).toBe(1);
  });
});

describe("einer-gegen-alle: Disconnect + GM + Determinismus", () => {
  it("Solist-Disconnect ⇒ das Format endet SOFORT neutral (alle Scores 0)", () => {
    const { clock, ctx, state } = setup();
    let s = phaseVorbei(state, ctx, clock);
    // Erst verdient der Solist einen Solo-Coup …
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 0, p4: 0 });
    expect(s.deltas.p1).toBe(EGA_SOLO_MM);
    s = phaseVorbei(s, ctx, clock); // → Frage 2
    // … dann bricht er weg: NEUTRAL, auch der verdiente Coup verfällt.
    s = einerGegenAllePlugin.onDisconnect(s, asPlayerId("p1"), ctx) as EinerGegenAlleState;
    expect(s.phase).toBe("ergebnis");
    expect(s.neutral).toBe(true);
    s = phaseVorbei(s, ctx, clock);
    expect(einerGegenAllePlugin.scores(s)).toEqual({ p1: 0, p2: 0, p3: 0, p4: 0 });
    const outcomes = einerGegenAllePlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBeNull();
  });

  it("Mengen-Mitglied-Disconnect: Stimme entfällt, das Team spielt weiter", () => {
    const { clock, ctx, state } = setup();
    let s = phaseVorbei(state, ctx, clock);
    s = einerGegenAllePlugin.onDisconnect(s, asPlayerId("p4"), ctx) as EinerGegenAlleState;
    expect(s.phase).toBe("frage"); // kein Abbruch
    // p2+p3 stimmen richtig, der Solist falsch ⇒ Team-Triumph für ALLE
    // Mengen-Mitglieder (auch das getrennte — Team-Geld ist Team-Geld).
    s = spieleFrage(s, ctx, clock, { p1: 0, p2: 1, p3: 1 });
    expect(s.letzteFrage?.deltas).toEqual({
      p1: 0,
      p2: EGA_TEAM_MM,
      p3: EGA_TEAM_MM,
      p4: EGA_TEAM_MM,
    });
  });

  it("GM force.finish VOR dem Ergebnis ⇒ Abbruch ohne Zahlung; im Ergebnis gilt es", () => {
    const { clock, ctx, state } = setup();
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    let s = phaseVorbei(state, ctx, clock);
    s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 0, p4: 0 });
    const abgebrochen = reduce(s, skip, ctx);
    expect(abgebrochen.finished).toBe(true);
    expect(einerGegenAllePlugin.scores(abgebrochen)).toEqual({ p1: 0, p2: 0, p3: 0, p4: 0 });
    // Regulär bis ins Ergebnis: dort bucht der Skip die Bilanz.
    for (let f = 2; f <= EGA_FRAGEN; f++) {
      s = phaseVorbei(s, ctx, clock);
      s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 0, p4: 0 });
    }
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    const fertig = reduce(s, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(einerGegenAllePlugin.scores(fertig)[asPlayerId("p1")]).toBe(EGA_FRAGEN * EGA_SOLO_MM);
  });

  it("GM timer.extend/timer.shift verschieben die Zeitanker konsistent", () => {
    const { clock, ctx, state } = setup();
    const s = phaseVorbei(state, ctx, clock); // → frage
    const laenger = reduce(s, { kind: "gm", type: "timer.extend", ms: 5_000 }, ctx);
    expect(laenger.phaseEndsAt).toBe(s.phaseEndsAt + 5_000);
    expect(laenger.frageStartetAt).toBe(s.frageStartetAt);
    const pause = reduce(s, { kind: "gm", type: "timer.shift", ms: 60_000 }, ctx);
    expect(pause.phaseEndsAt).toBe(s.phaseEndsAt + 60_000);
    expect(pause.startedAt).toBe(s.startedAt + 60_000);
    expect(pause.frageStartetAt).toBe((s.frageStartetAt ?? 0) + 60_000);
  });

  it("Pool-Wächter: kaputte Fragen fliegen raus; ganz ohne Frage wirft init", () => {
    const kaputt: Question = { ...fragen(1)[0], id: "q_defekt", answer: 9 };
    const clock = createTestClock(0);
    const ctx: Ctx = { clock, rng: createRng(1) };
    const spieler = ["p1", "p2", "p3"].map(asPlayerId);
    const state = einerGegenAllePlugin.init(
      spieler,
      { questions: [...fragen(2), kaputt] },
      ctx,
    ) as EinerGegenAlleState;
    expect(state.questions.map((q) => q.id)).toEqual(["q_ega_1", "q_ega_2"]);
    expect(() => einerGegenAllePlugin.init(spieler, { questions: [kaputt] }, ctx)).toThrow(
      /ohne brauchbare Frage/,
    );
  });

  it("Seed-Determinismus: das Gleichstands-Los ist mit gleichem Seed reproduzierbar", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = phaseVorbei(state, ctx, clock);
      // Gleichstand A vs. C in der Menge ⇒ das Los entscheidet.
      s = spieleFrage(s, ctx, clock, { p1: 1, p2: 0, p3: 2 });
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(a.letzteFrage?.gleichstand).toBe(true);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});
