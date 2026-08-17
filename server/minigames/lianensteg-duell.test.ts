// Lianensteg-Duell: Wett-Mathe-Goldens (pari-mutuel, EXAKT nullsummig),
// Herausforderer-Prinzip (Letzter wählt, Feiglings-Schutz, Timeout = Führender),
// Wett-Fenster-Regeln (nur Zuschauer, einrasten, geheim bis Wettschluss),
// Duell-Mechanik (3 Siege sofort, Buzzer-Ranking bei 2 Richtigen, Sudden Death,
// Fotofinish = geteilter Sieg), Scoring-Invarianten (Bank-Prämie + nullsummiger
// Transfer + nullsummige Wetten), Disconnect (kampflos/Abbruch), GM-Kommandos,
// Leak-Wachen (Frage nur im Fenster, correctIndex nur GM), Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  LD_GETEILT_MM,
  LD_SIEG_BANK_MM,
  LD_SIEG_TRANSFER_MM,
  LD_WETTE_MM,
  ldWettAbrechnung,
  ldWettAnteil,
  type LianenstegDuellAction,
} from "../../shared/minigames/lianensteg-duell.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import {
  gegnerKandidaten,
  lianenstegDuellPlugin,
  type LianenstegDuellState,
} from "./lianensteg-duell/index";

function fragen(n: number): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_ld_${i + 1}`,
    kind: "choice4" as const,
    category: "affen_wissen",
    difficulty: "hard" as const,
    text: `Steg-Frage ${i + 1}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  }));
}

// Konten: p4 ist der Letzte (Herausforderer), p1 der Führende, p3 der ärmste
// GEGNER (Feiglings-Schutz).
const KONTEN = { p1: 2_000, p2: 1_500, p3: 1_000, p4: 500 };

function setup(
  opts: { balances?: Record<string, number> | null; spieler?: string[]; seed?: number } = {},
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
  const content: ContentSlice = { questions: fragen(7) };
  const state = lianenstegDuellPlugin.init(spieler, content, ctx) as LianenstegDuellState;
  return { clock, ctx, state, spieler };
}

function aktion(
  p: string,
  a: LianenstegDuellAction,
  at: number,
): PlayerAction<LianenstegDuellAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(
  s: LianenstegDuellState,
  a: PlayerAction<LianenstegDuellAction> | GmAction,
  ctx: Ctx,
) {
  return lianenstegDuellPlugin.reduce(s, a, ctx) as LianenstegDuellState;
}

function tick(s: LianenstegDuellState, ctx: Ctx) {
  return lianenstegDuellPlugin.tick(s, ctx) as LianenstegDuellState;
}

/** Uhr bis nach dem Phasen-Ende, dann tick (Phasen-Übergang erzwingen). */
function phaseVorbei(s: LianenstegDuellState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndsAt - clock.now()) + 1);
  return tick(s, ctx);
}

/** Standard-Einstieg: p4 fordert p1, die Zuschauer wetten, Countdown startet. */
function insDuell(
  state: LianenstegDuellState,
  ctx: Ctx,
  wetten: Record<string, string> = { p2: "p1", p3: "p4" },
) {
  let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 1_000), ctx);
  expect(s.phase).toBe("wetten");
  for (const [w, auf] of Object.entries(wetten)) {
    s = reduce(s, aktion(w, { type: "wette", auf }, 2_000), ctx);
  }
  s = tick(s, ctx); // alle Zuschauer gewettet ⇒ Countdown startet sofort
  expect(s.phase).toBe("countdown");
  return s;
}

/**
 * Eine Teilfrage spielen: Countdown ablaufen lassen, Antworten einspeisen,
 * auswerten (bei fehlenden Antworten via Timeout) — endet im Schubs-Beat
 * oder (Sudden-Death-Fotofinish) direkt im Ergebnis.
 */
function spieleTeilfrage(
  s: LianenstegDuellState,
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

/** Schubs-Beat abwarten (führt zu nächstem Countdown oder Ergebnis). */
function nachSchubs(s: LianenstegDuellState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  expect(s.phase).toBe("schubs");
  return phaseVorbei(s, ctx, clock);
}

function summe(scores: Record<PlayerId, number>): number {
  return Object.values(scores).reduce((a, b) => a + b, 0);
}

describe("lianensteg-duell: Wett-Mathe (pari-mutuel, EXAKT nullsummig)", () => {
  it("ldWettAnteil: Topf/Richtige auf 10er abgerundet", () => {
    expect(ldWettAnteil(100, 2)).toBe(50);
    expect(ldWettAnteil(150, 2)).toBe(70); // 75 → 70
    expect(ldWettAnteil(100, 1)).toBe(100);
    expect(ldWettAnteil(100, 0)).toBe(0);
  });

  it("50/50-Split ergibt genau „Einsatz ×2“ (Design-Golden)", () => {
    const w = ldWettAbrechnung({ z1: "a", z2: "b" }, "a");
    expect(w.deltas.z1).toBe(LD_WETTE_MM); // 50 Einsatz → 100 zurück = +50
    expect(w.deltas.z2).toBe(-LD_WETTE_MM);
    expect(w.restAnSieger).toBe(0);
  });

  it("Rundungs-Rest geht an den Sieger — Σ deltas + rest = 0 (Invariante)", () => {
    // 3 Wetter, 2 richtig: Topf 150, Anteil 70 ⇒ +20/+20/−50, Rest 10.
    const w = ldWettAbrechnung({ z1: "a", z2: "a", z3: "b" }, "a");
    expect(w.deltas.z1).toBe(20);
    expect(w.deltas.z3).toBe(-50);
    expect(w.restAnSieger).toBe(10);
    expect(summe(w.deltas as Record<PlayerId, number>) + w.restAnSieger).toBe(0);
  });

  it("keine richtige Wette ⇒ GANZER Topf an den Sieger; sieger null ⇒ alles zurück", () => {
    const keiner = ldWettAbrechnung({ z1: "b", z2: "b" }, "a");
    expect(keiner.deltas.z1).toBe(-50);
    expect(keiner.restAnSieger).toBe(100);
    expect(summe(keiner.deltas as Record<PlayerId, number>) + keiner.restAnSieger).toBe(0);
    const zurueck = ldWettAbrechnung({ z1: "a" }, null);
    expect(zurueck.deltas.z1).toBe(0);
    expect(zurueck.restAnSieger).toBe(0);
  });
});

describe("lianensteg-duell: Herausforderer-Prinzip + Feiglings-Schutz", () => {
  it("der Letzte des Zwischenstands ist Herausforderer; ärmster Gegner geschützt", () => {
    const { state } = setup();
    expect(state.phase).toBe("herausforderung");
    expect(state.herausforderer).toBe("p4"); // 500 MM = Letzter
    const kandidaten = gegnerKandidaten(state);
    expect(kandidaten.find((k) => k.id === "p3")?.waehlbar).toBe(false); // Feigling-Schutz
    expect(kandidaten.find((k) => k.id === "p1")?.waehlbar).toBe(true); // Führender IMMER
    expect(kandidaten.find((k) => k.id === "p2")?.waehlbar).toBe(true);
  });

  it("Wahl des Geschützten/durch Fremde verpufft; gültige Wahl startet die Wetten", () => {
    const { ctx, state } = setup();
    expect(reduce(state, aktion("p4", { type: "herausfordern", targetId: "p3" }, 500), ctx)).toBe(
      state,
    );
    expect(reduce(state, aktion("p1", { type: "herausfordern", targetId: "p2" }, 500), ctx)).toBe(
      state,
    );
    const s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p2" }, 500), ctx);
    expect(s.gegner).toBe("p2");
    expect(s.phase).toBe("wetten");
  });

  it("Timeout wählt den Führenden als Gegner", () => {
    const { clock, ctx, state } = setup();
    const s = phaseVorbei(state, ctx, clock);
    expect(s.gegner).toBe("p1"); // 2.000 MM = Führender
    expect(s.phase).toBe("wetten");
  });

  it("ohne ctx.match (isoliert): kein Schutz, Herausforderer = erster Spieler", () => {
    const { state } = setup({ balances: null });
    expect(state.herausforderer).toBe("p1");
    expect(gegnerKandidaten(state).every((k) => k.waehlbar)).toBe(true);
  });

  it("2-Spieler-Spiel: Gegner automatisch, keine Wett-Phase, direkt Countdown", () => {
    const { state } = setup({ spieler: ["p1", "p2"], balances: { p1: 800, p2: 400 } });
    expect(state.phase).toBe("countdown");
    expect(state.herausforderer).toBe("p2");
    expect(state.gegner).toBe("p1");
    expect(state.wettenGeschlossen).toBe(true);
  });
});

describe("lianensteg-duell: Wett-Fenster", () => {
  it("nur Zuschauer wetten (einrasten, nur auf Duellanten); alle gewettet ⇒ Countdown", () => {
    const { ctx, state } = setup();
    let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 500), ctx);
    // Duellant darf nicht wetten, Zuschauer nicht auf Zuschauer.
    expect(reduce(s, aktion("p4", { type: "wette", auf: "p4" }, 1_000), ctx)).toBe(s);
    expect(reduce(s, aktion("p2", { type: "wette", auf: "p3" }, 1_000), ctx)).toBe(s);
    s = reduce(s, aktion("p2", { type: "wette", auf: "p1" }, 1_000), ctx);
    // Einrasten: Zweitwette verpufft.
    const doppelt = reduce(s, aktion("p2", { type: "wette", auf: "p4" }, 1_500), ctx);
    expect(doppelt.wetten.p2).toBe("p1");
    s = reduce(doppelt, aktion("p3", { type: "wette", auf: "p4" }, 2_000), ctx);
    s = tick(s, ctx);
    expect(s.phase).toBe("countdown"); // vor Fenster-Ende — alle haben gewettet
    expect(s.wettenGeschlossen).toBe(true);
  });

  it("Leak-Wache: Wetten GEHEIM bis Wettschluss (nur Anzahl), danach public", () => {
    const { ctx, state } = setup();
    let s = reduce(state, aktion("p4", { type: "herausfordern", targetId: "p1" }, 500), ctx);
    s = reduce(s, aktion("p2", { type: "wette", auf: "p1" }, 1_000), ctx);
    const geheim = lianenstegDuellPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(geheim.wetten).toBeNull();
    expect(geheim.wettenAnzahl).toBe(1);
    const spieler = lianenstegDuellPlugin.viewFor(s, "player", asPlayerId("p3")) as Record<
      string,
      unknown
    >;
    expect(spieler.wetten).toBeNull();
    expect(spieler.deineWette).toBeNull(); // p3 hat noch nicht gewettet
    // GM sieht die Wetten IMMER (Spickzettel).
    const gm = lianenstegDuellPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.wetten).toEqual({ p2: "p1" });
    s = reduce(s, aktion("p3", { type: "wette", auf: "p4" }, 2_000), ctx);
    s = tick(s, ctx);
    const offen = lianenstegDuellPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(offen.wetten).toEqual({ p2: "p1", p3: "p4" });
  });
});

describe("lianensteg-duell: Duell-Mechanik", () => {
  it("einer richtig ⇒ Punkt + Schubs-Beat; beide falsch ⇒ Stand unverändert", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    s = spieleTeilfrage(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 800 },
      { p: "p1", choice: 0, nachMs: 900 },
    ]);
    expect(s.phase).toBe("schubs");
    expect(s.letzteTeilfrage?.gewinner).toBe("p4");
    expect(s.siege.p4).toBe(1);
    s = nachSchubs(s, ctx, clock);
    s = spieleTeilfrage(s, ctx, clock, [
      { p: "p4", choice: 2, nachMs: 500 },
      { p: "p1", choice: 3, nachMs: 600 },
    ]);
    expect(s.letzteTeilfrage?.gewinner).toBeNull();
    expect(s.siege.p4).toBe(1);
    expect(s.siege.p1).toBeUndefined();
  });

  it("beide richtig ⇒ der Schnellere holt den Punkt (Buzzer-Ranking, kein Fotofinish >40 ms)", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    s = spieleTeilfrage(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 300 },
      { p: "p4", choice: 1, nachMs: 900 },
    ]);
    expect(s.letzteTeilfrage?.gewinner).toBe("p1");
    expect(s.letzteTeilfrage?.fotofinish).toBe(false);
  });

  it("3 Siege beenden das Duell SOFORT — Scoring: 300 Bank + 100 Transfer + Wett-Topf", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, { p2: "p1", p3: "p4" });
    for (let i = 0; i < 3; i++) {
      s = spieleTeilfrage(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ]);
      s = nachSchubs(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    expect(s.sieger).toBe("p4");
    expect(s.teilfrage).toBe(3); // Best-of-5 vorzeitig entschieden
    s = phaseVorbei(s, ctx, clock);
    expect(lianenstegDuellPlugin.isFinished(s)).toBe(true);
    const scores = lianenstegDuellPlugin.scores(s);
    // p3 wettete richtig auf p4: Topf 100, 1 Richtiger ⇒ Anteil 100 = +50.
    expect(scores[asPlayerId("p4")]).toBe(LD_SIEG_BANK_MM + LD_SIEG_TRANSFER_MM);
    expect(scores[asPlayerId("p1")]).toBe(-LD_SIEG_TRANSFER_MM);
    expect(scores[asPlayerId("p3")]).toBe(50);
    expect(scores[asPlayerId("p2")]).toBe(-50);
    // Invariante: Gesamtsumme = NUR die Bank-Prämie (Transfer + Wetten nullsummig).
    expect(summe(scores)).toBe(LD_SIEG_BANK_MM);
    const outcomes = lianenstegDuellPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p4")].correct).toBe(true);
    expect(outcomes[asPlayerId("p1")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBe(true); // Wette richtig
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
  });

  it("2-2 nach 5 Fragen ⇒ Sudden Death; Teilfragen-Sieger gewinnt das DUELL", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    const runden: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[][] = [
      [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ], // p4
      [
        { p: "p1", choice: 1, nachMs: 500 },
        { p: "p4", choice: 0, nachMs: 600 },
      ], // p1
      [
        { p: "p4", choice: 2, nachMs: 500 },
        { p: "p1", choice: 3, nachMs: 600 },
      ], // keiner
      [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ], // p4
      [
        { p: "p1", choice: 1, nachMs: 500 },
        { p: "p4", choice: 0, nachMs: 600 },
      ], // p1 ⇒ 2:2
    ];
    for (const r of runden) {
      s = spieleTeilfrage(s, ctx, clock, r);
      s = nachSchubs(s, ctx, clock);
    }
    expect(s.suddenDeath).toBe(1);
    expect(s.phase).toBe("countdown");
    s = spieleTeilfrage(s, ctx, clock, [
      { p: "p1", choice: 1, nachMs: 400 },
      { p: "p4", choice: 1, nachMs: 900 }, // >40 ms später — kein Fotofinish
    ]);
    s = nachSchubs(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    expect(s.sieger).toBe("p1"); // Sudden-Death-Teilfrage entscheidet das Duell
  });

  it("Fotofinish IM Sudden Death ⇒ GETEILTER Sieg: je 150, Wetten zurück", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, { p2: "p1", p3: "p4" });
    const runden: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[][] = [
      [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ],
      [
        { p: "p1", choice: 1, nachMs: 500 },
        { p: "p4", choice: 0, nachMs: 600 },
      ],
      [
        { p: "p4", choice: 2, nachMs: 500 },
        { p: "p1", choice: 3, nachMs: 600 },
      ],
      [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ],
      [
        { p: "p1", choice: 1, nachMs: 500 },
        { p: "p4", choice: 0, nachMs: 600 },
      ],
    ];
    for (const r of runden) {
      s = spieleTeilfrage(s, ctx, clock, r);
      s = nachSchubs(s, ctx, clock);
    }
    // Sudden Death: beide richtig, 10 ms auseinander ⇒ Fotofinish ⇒ geteilt.
    s = spieleTeilfrage(s, ctx, clock, [
      { p: "p4", choice: 1, nachMs: 500 },
      { p: "p1", choice: 1, nachMs: 510 },
    ]);
    expect(s.phase).toBe("ergebnis");
    expect(s.geteilt).toBe(true);
    expect(s.sieger).toBeNull();
    s = phaseVorbei(s, ctx, clock);
    const scores = lianenstegDuellPlugin.scores(s);
    expect(scores[asPlayerId("p4")]).toBe(LD_GETEILT_MM);
    expect(scores[asPlayerId("p1")]).toBe(LD_GETEILT_MM);
    expect(scores[asPlayerId("p2")]).toBe(0); // Wetten zurück
    expect(scores[asPlayerId("p3")]).toBe(0);
  });

  it("doppelter Sudden-Death-Fehlschlag (beide 2× falsch) ⇒ geteilter Sieg", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    const patt: { p: string; choice: 0 | 1 | 2 | 3; nachMs: number }[][] = [
      [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ],
      [
        { p: "p1", choice: 1, nachMs: 500 },
        { p: "p4", choice: 0, nachMs: 600 },
      ],
      [
        { p: "p4", choice: 2, nachMs: 500 },
        { p: "p1", choice: 3, nachMs: 600 },
      ],
      [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ],
      [
        { p: "p1", choice: 1, nachMs: 500 },
        { p: "p4", choice: 0, nachMs: 600 },
      ],
      // Sudden Death 1 + 2: beide falsch.
      [
        { p: "p4", choice: 0, nachMs: 500 },
        { p: "p1", choice: 2, nachMs: 600 },
      ],
      [
        { p: "p4", choice: 3, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ],
    ];
    for (const r of patt) {
      s = spieleTeilfrage(s, ctx, clock, r);
      if (s.phase === "schubs") s = nachSchubs(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    expect(s.geteilt).toBe(true);
  });
});

describe("lianensteg-duell: Disconnect + GM + Leaks + Determinismus", () => {
  it("Duellant-Disconnect mitten im Duell ⇒ kampflos: 300 Bank, KEIN Transfer, Wetten zurück", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx, { p2: "p1", p3: "p4" });
    s = phaseVorbei(s, ctx, clock); // Countdown → Frage
    s = lianenstegDuellPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as LianenstegDuellState;
    expect(s.phase).toBe("ergebnis");
    expect(s.kampflos).toBe(true);
    expect(s.sieger).toBe("p4");
    s = phaseVorbei(s, ctx, clock);
    const scores = lianenstegDuellPlugin.scores(s);
    expect(scores[asPlayerId("p4")]).toBe(LD_SIEG_BANK_MM);
    expect(scores[asPlayerId("p1")]).toBe(0); // kein Konto-Abzug offline
    expect(scores[asPlayerId("p3")]).toBe(0); // Wette zurück
    expect(lianenstegDuellPlugin.outcomes!(s)[asPlayerId("p1")].correct).toBeNull();
  });

  it("BEIDE Duellanten offline ⇒ Abbruch: alle Scores 0", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    s = phaseVorbei(s, ctx, clock);
    s = { ...s, connected: { ...s.connected, p1: false } };
    s = lianenstegDuellPlugin.onDisconnect(s, asPlayerId("p4"), ctx) as LianenstegDuellState;
    expect(s.abgebrochen).toBe(true);
    s = phaseVorbei(s, ctx, clock);
    expect(summe(lianenstegDuellPlugin.scores(s))).toBe(0);
  });

  it("GM force.finish VOR dem Ergebnis ⇒ Abbruch ohne Zahlung; im Ergebnis gilt es", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    const abgebrochen = reduce(s, skip, ctx);
    expect(abgebrochen.finished).toBe(true);
    expect(summe(lianenstegDuellPlugin.scores(abgebrochen))).toBe(0);
    // Im Ergebnis: die Abrechnung bleibt bestehen.
    for (let i = 0; i < 3; i++) {
      s = spieleTeilfrage(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 0, nachMs: 600 },
      ]);
      s = nachSchubs(s, ctx, clock);
    }
    const fertig = reduce(s, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(lianenstegDuellPlugin.scores(fertig)[asPlayerId("p4")]).toBe(
      LD_SIEG_BANK_MM + LD_SIEG_TRANSFER_MM, // p3 wettete richtig ⇒ Topf-Rest 0
    );
  });

  it("GM timer.extend/timer.shift verschieben die Zeitanker konsistent", () => {
    const { ctx, state } = setup();
    const s = insDuell(state, ctx);
    const laenger = reduce(s, { kind: "gm", type: "timer.extend", ms: 5_000 }, ctx);
    expect(laenger.phaseEndsAt).toBe(s.phaseEndsAt + 5_000);
    const pause = reduce(s, { kind: "gm", type: "timer.shift", ms: 60_000 }, ctx);
    expect(pause.phaseEndsAt).toBe(s.phaseEndsAt + 60_000);
    expect(pause.startedAt).toBe(s.startedAt + 60_000);
  });

  it("Leak-Wache: Frage-Text/Optionen NUR im Frage-Fenster; correctIndex nur beim GM", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    const countdown = lianenstegDuellPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(countdown.text).toBeNull();
    expect(countdown.options).toBeNull();
    s = phaseVorbei(s, ctx, clock); // → frage
    const frage = lianenstegDuellPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(frage.text).toBe("Steg-Frage 1?");
    expect(frage.options).toEqual(["A", "B", "C", "D"]);
    expect(frage.correctIndex).toBeUndefined();
    const spieler = lianenstegDuellPlugin.viewFor(s, "player", asPlayerId("p4")) as Record<
      string,
      unknown
    >;
    expect(spieler.correctIndex).toBeUndefined();
    expect(spieler.duBistDuellant).toBe(true);
    const gm = lianenstegDuellPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
    // Teilfragen-Lösung ERST im Schubs-Beat.
    expect(frage.letzteTeilfrage).toBeNull();
    s = reduce(s, aktion("p4", { type: "answer", choice: 1 }, (s.frageStartetAt ?? 0) + 500), ctx);
    s = reduce(s, aktion("p1", { type: "answer", choice: 0 }, (s.frageStartetAt ?? 0) + 600), ctx);
    s = tick(s, ctx);
    const schubs = lianenstegDuellPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect((schubs.letzteTeilfrage as { correctIndex: number }).correctIndex).toBe(1);
  });

  it("Seed-Determinismus: identischer Ablauf ⇒ identischer End-State (inkl. Fotofinish-Los)", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = insDuell(state, ctx);
      // Reguläre Fotofinish-Frage: beide richtig, 10 ms Abstand ⇒ Münzwurf.
      s = spieleTeilfrage(s, ctx, clock, [
        { p: "p4", choice: 1, nachMs: 500 },
        { p: "p1", choice: 1, nachMs: 510 },
      ]);
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(a.letzteTeilfrage?.fotofinish).toBe(true);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  it("Antworten außerhalb des Fensters/von Zuschauern/doppelt verpuffen", () => {
    const { clock, ctx, state } = setup();
    let s = insDuell(state, ctx);
    // Im Countdown: Antwort verworfen.
    expect(reduce(s, aktion("p4", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s);
    s = phaseVorbei(s, ctx, clock);
    // Zuschauer-Antwort verworfen.
    expect(reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s);
    // Zu späte Antwort (nach Gnade) verworfen.
    const zuSpaet = s.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p4", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(s);
    // Erste Antwort zählt — die zweite verpufft.
    s = reduce(s, aktion("p4", { type: "answer", choice: 0 }, clock.now() + 500), ctx);
    const doppelt = reduce(s, aktion("p4", { type: "answer", choice: 1 }, clock.now() + 600), ctx);
    expect(doppelt.answers.p4.choice).toBe(0);
  });
});
