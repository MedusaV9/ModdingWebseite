// Risiko-Leiter: Leiter-Mathe-Goldens (8-Stufen-Kurve, Sicherheitsstufe 3 =
// 400 MM, Gipfel = 3.000 + Jackpot-Bonus), Schwierigkeits-Sortierung,
// Entscheidungs-Fenster (Absichern sofort + endgültig, Timeout = Weiter,
// Guck-Exploit-Wache), Absturz-Regel, Auto-Absicherung bei Disconnect,
// vorzeitiges Runden-Ende, GM-Kommandos, Leak-Wachen und Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import type { Schwierigkeit } from "../../shared/money";
import {
  RL_JACKPOT_BONUS,
  RL_LEITER,
  RL_SICHERHEITSSTUFE,
  RL_STUFEN,
  rlAbsturzWert,
  rlGipfelWert,
  rlLeiterWert,
  type RisikoLeiterAction,
} from "../../shared/minigames/risiko-leiter.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { risikoLeiterPlugin, type RisikoLeiterState } from "./risiko-leiter/index";

function frage(i: number, difficulty: Schwierigkeit): Question {
  return {
    id: `q_rl_${i}`,
    kind: "choice4",
    category: "affen_wissen",
    difficulty,
    text: `Stufen-Frage ${i}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "B war's.",
  };
}

/** 8 Fragen mit steigender Schwierigkeit — bewusst UNSORTIERT geliefert. */
function leiterFragen(): Question[] {
  const stufen: Schwierigkeit[] = [
    "easy",
    "easy",
    "medium",
    "medium",
    "hard",
    "hard",
    "hard",
    "ultrahard",
  ];
  const fragen = stufen.map((s, i) => frage(i + 1, s));
  return [fragen[7], fragen[2], fragen[0], fragen[4], fragen[1], fragen[5], fragen[3], fragen[6]];
}

function setup(opts: { spieler?: string[]; seed?: number; questions?: Question[] } = {}) {
  const clock = createTestClock(0);
  const spieler = (opts.spieler ?? ["p1", "p2", "p3", "p4"]).map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const content: ContentSlice = { questions: opts.questions ?? leiterFragen() };
  const state = risikoLeiterPlugin.init(spieler, content, ctx) as RisikoLeiterState;
  return { clock, ctx, state, spieler };
}

function aktion(p: string, a: RisikoLeiterAction, at: number): PlayerAction<RisikoLeiterAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(s: RisikoLeiterState, a: PlayerAction<RisikoLeiterAction> | GmAction, ctx: Ctx) {
  return risikoLeiterPlugin.reduce(s, a, ctx) as RisikoLeiterState;
}

function tick(s: RisikoLeiterState, ctx: Ctx) {
  return risikoLeiterPlugin.tick(s, ctx) as RisikoLeiterState;
}

/** Uhr bis nach dem Phasen-Ende (+Gnade), dann tick (Übergang erzwingen). */
function phaseVorbei(s: RisikoLeiterState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndsAt - clock.now()) + SPAETANTWORT_GNADE_MS + 1);
  return tick(s, ctx);
}

/** Eine Stufe spielen: Entscheidungen einspeisen, Frage beantworten, bis in
 * den Aufstiegs-Beat auswerten. `absicherer` machen Kasse, `antworten` sind
 * die Choices der Weiter-Kletterer (fehlend = stumm). */
function spieleStufe(
  s: RisikoLeiterState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
  opts: { absicherer?: string[]; antworten: Record<string, 0 | 1 | 2 | 3 | null> },
) {
  expect(s.phase).toBe("entscheidung");
  for (const p of opts.absicherer ?? []) {
    s = reduce(s, aktion(p, { type: "entscheidung", wahl: "absichern" }, clock.now() + 100), ctx);
  }
  for (const p of Object.keys(opts.antworten)) {
    s = reduce(s, aktion(p, { type: "entscheidung", wahl: "weiter" }, clock.now() + 100), ctx);
  }
  s = phaseVorbei(s, ctx, clock);
  if (s.phase !== "frage") return s; // alle raus ⇒ direkt Ergebnis
  const start = s.frageStartetAt ?? 0;
  for (const [p, choice] of Object.entries(opts.antworten)) {
    if (choice === null) continue; // stumm nach Weiter-Wahl
    s = reduce(s, aktion(p, { type: "answer", choice }, start + 500), ctx);
  }
  s = phaseVorbei(s, ctx, clock);
  expect(s.phase).toBe("aufstieg");
  return s;
}

describe("risiko-leiter: Leiter-Mathe (Goldens)", () => {
  it("die 8-Stufen-Kurve: 100 → 200 → 400 → 700 → 1.100 → 1.600 → 2.200 → 3.000", () => {
    expect(RL_LEITER).toEqual([100, 200, 400, 700, 1100, 1600, 2200, 3000]);
    expect(rlLeiterWert(0)).toBe(0);
    for (let stufe = 1; stufe <= RL_STUFEN; stufe++) {
      expect(rlLeiterWert(stufe)).toBe(RL_LEITER[stufe - 1]);
    }
    expect(rlLeiterWert(99)).toBe(3000); // Kappe
  });

  it("Sicherheitsstufen-Golden: unter Stufe 3 fällt man auf 0, ab Stufe 3 auf 400", () => {
    expect(RL_SICHERHEITSSTUFE).toBe(3);
    expect(rlAbsturzWert(0)).toBe(0);
    expect(rlAbsturzWert(1)).toBe(0);
    expect(rlAbsturzWert(2)).toBe(0);
    for (let stufe = 3; stufe <= RL_STUFEN; stufe++) {
      expect(rlAbsturzWert(stufe)).toBe(400);
    }
  });

  it("Gipfel-Golden: Stufe 8 richtig = 3.000 + Jackpot-Bonus", () => {
    expect(rlGipfelWert()).toBe(3000 + RL_JACKPOT_BONUS);
  });
});

describe("risiko-leiter: Init + Schwierigkeits-Leiter", () => {
  it("init sortiert die Fragen easy → ultrahard (die Leiter-Progression)", () => {
    const { state } = setup();
    expect(state.questions.map((q) => q.difficulty)).toEqual([
      "easy",
      "easy",
      "medium",
      "medium",
      "hard",
      "hard",
      "hard",
      "ultrahard",
    ]);
    expect(state.phase).toBe("entscheidung");
    expect(state.stufeNr).toBe(1);
  });

  it("Pool-Wächter: kaputte Fragen fliegen raus; ganz ohne Frage wirft init", () => {
    const kaputt: Question = { ...frage(9, "easy"), answer: 9 };
    const { state } = setup({ questions: [frage(1, "easy"), kaputt] });
    expect(state.questions.map((q) => q.id)).toEqual(["q_rl_1"]);
    expect(() => setup({ questions: [kaputt] })).toThrow(/ohne brauchbare Frage/);
  });
});

describe("risiko-leiter: Entscheidungs-Fenster", () => {
  it("Absichern wirkt sofort, schreibt den Leiter-Stand gut und rastet ein", () => {
    const { clock, ctx, state } = setup();
    let s = spieleStufe(state, ctx, clock, { antworten: { p1: 1, p2: 1, p3: 1, p4: 1 } });
    s = phaseVorbei(s, ctx, clock); // → Entscheidung Stufe 2
    expect(s.stufeNr).toBe(2);
    s = reduce(s, aktion("p2", { type: "entscheidung", wahl: "absichern" }, clock.now() + 10), ctx);
    expect(s.kletterer.p2.status).toBe("abgesichert");
    expect(s.kletterer.p2.gutschrift).toBe(100); // Stufe 1 gesichert
    // Eingerastet: die Meinungsänderung verpufft.
    const nochmal = reduce(
      s,
      aktion("p2", { type: "entscheidung", wahl: "weiter" }, clock.now() + 20),
      ctx,
    );
    expect(nochmal).toBe(s);
  });

  it("Timeout = WEITERKLETTERN (verbundene Zauderer) — kein Guck-Exploit via Schweigen", () => {
    const { clock, ctx, state } = setup();
    // Niemand entscheidet — nach dem Fenster klettern ALLE weiter.
    const s = phaseVorbei(state, ctx, clock);
    expect(s.phase).toBe("frage");
    expect(Object.values(s.kletterer).every((k) => k.status === "klettert")).toBe(true);
  });

  it("alle sichern ab ⇒ die Runde endet früher (direkt im Ergebnis)", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s = reduce(
      state,
      aktion("p1", { type: "entscheidung", wahl: "absichern" }, clock.now() + 10),
      ctx,
    );
    s = reduce(s, aktion("p2", { type: "entscheidung", wahl: "absichern" }, clock.now() + 20), ctx);
    s = tick(s, ctx); // alle entschieden ⇒ Fenster schließt früher
    expect(s.phase).toBe("ergebnis");
    // Absichern auf dem Boden = 0 MM (erlaubt, aber leer).
    expect(risikoLeiterPlugin.scores(s)).toEqual({ p1: 0, p2: 0 });
  });

  it("Zuschauer-/Spät-Entscheidungen verpuffen", () => {
    const { clock, ctx, state } = setup();
    let s = spieleStufe(state, ctx, clock, {
      absicherer: ["p3"],
      antworten: { p1: 1, p2: 1, p4: 1 },
    });
    s = phaseVorbei(s, ctx, clock); // → Entscheidung Stufe 2
    // p3 ist Zuschauer (abgesichert) — seine Entscheidung verpufft.
    expect(
      reduce(s, aktion("p3", { type: "entscheidung", wahl: "weiter" }, clock.now()), ctx),
    ).toBe(s);
    // Zu spät (nach Fenster-Ende) verpufft ebenfalls.
    const zuSpaet = s.phaseEndsAt + 1;
    expect(reduce(s, aktion("p1", { type: "entscheidung", wahl: "absichern" }, zuSpaet), ctx)).toBe(
      s,
    );
  });
});

describe("risiko-leiter: Klettern, Absturz & Gipfel", () => {
  it("richtig = Aufstieg; falsch = Absturz auf die Sicherheitsstufe (400 ab Stufe 3)", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    // Stufen 1-3: alle richtig (p4 erklimmt die Sicherheitsstufe).
    for (let stufe = 1; stufe <= 3; stufe++) {
      s = spieleStufe(s, ctx, clock, { antworten: { p1: 1, p2: 1, p3: 1, p4: 1 } });
      s = phaseVorbei(s, ctx, clock);
    }
    expect(s.kletterer.p4.stufe).toBe(3);
    // Stufe 4: p4 daneben ⇒ Absturz auf 400; p3 stumm nach Weiter ⇒ Absturz.
    s = spieleStufe(s, ctx, clock, { antworten: { p1: 1, p2: 1, p3: null, p4: 0 } });
    expect(s.letzterBeat?.ereignisse.p4).toBe("absturz");
    expect(s.kletterer.p4.status).toBe("abgestuerzt");
    expect(s.kletterer.p4.gutschrift).toBe(400); // Sicherheitsstufe!
    expect(s.kletterer.p3.status).toBe("abgestuerzt");
    expect(s.kletterer.p3.gutschrift).toBe(400);
    expect(s.kletterer.p1.stufe).toBe(4);
  });

  it("Absturz UNTER der Sicherheitsstufe fällt auf 0", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s = spieleStufe(state, ctx, clock, { antworten: { p1: 1, p2: 1 } });
    s = phaseVorbei(s, ctx, clock);
    // Stufe 2: p2 daneben — Stufe 1 ist erklommen, aber unter der Sicherheit.
    s = spieleStufe(s, ctx, clock, { antworten: { p1: 1, p2: 3 } });
    expect(s.kletterer.p2.status).toBe("abgestuerzt");
    expect(s.kletterer.p2.gutschrift).toBe(0);
    expect(s.kletterer.p2.endeAufStufe).toBe(2);
  });

  it("kompletter Aufstieg: Stufe 8 richtig = Gipfel mit 3.000 + Jackpot-Bonus", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s = state;
    for (let stufe = 1; stufe <= RL_STUFEN; stufe++) {
      // p2 klettert 4 Stufen mit, macht im 5. Entscheidungs-Fenster Kasse.
      s = spieleStufe(s, ctx, clock, {
        absicherer: stufe === 5 ? ["p2"] : [],
        antworten: stufe < 5 ? { p1: 1, p2: 1 } : { p1: 1 },
      });
      if (stufe < RL_STUFEN) s = phaseVorbei(s, ctx, clock);
    }
    expect(s.letzterBeat?.ereignisse.p1).toBe("gipfel");
    expect(s.kletterer.p1.status).toBe("gipfel");
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    s = phaseVorbei(s, ctx, clock);
    expect(risikoLeiterPlugin.isFinished(s)).toBe(true);
    const scores = risikoLeiterPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(3000 + RL_JACKPOT_BONUS);
    expect(scores[asPlayerId("p2")]).toBe(700); // Kasse auf Stufe 4
    const outcomes = risikoLeiterPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(true); // abgesichert > Stufe 0
  });

  it("Golden-Runde über 4 Verläufe: Gipfel/Kasse/Absturz-400/Absturz-0 exakt", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    // Stufe 1: p4 daneben ⇒ Absturz auf 0 (unter der Sicherheitsstufe).
    s = spieleStufe(s, ctx, clock, { antworten: { p1: 1, p2: 1, p3: 1, p4: 2 } });
    s = phaseVorbei(s, ctx, clock);
    // Stufen 2-4: p1-p3 richtig.
    for (let stufe = 2; stufe <= 4; stufe++) {
      s = spieleStufe(s, ctx, clock, { antworten: { p1: 1, p2: 1, p3: 1 } });
      s = phaseVorbei(s, ctx, clock);
    }
    // Stufe 5: p2 macht Kasse (1.100 wären der nächste Wert — er sichert 700).
    // p3 klettert weiter und stürzt ⇒ Sicherheitsstufe 400.
    s = spieleStufe(s, ctx, clock, { absicherer: ["p2"], antworten: { p1: 1, p3: 0 } });
    s = phaseVorbei(s, ctx, clock);
    // Stufen 6-8: p1 klettert bis zum Gipfel.
    for (let stufe = 6; stufe <= 8; stufe++) {
      s = spieleStufe(s, ctx, clock, { antworten: { p1: 1 } });
      s = phaseVorbei(s, ctx, clock);
    }
    expect(s.phase).toBe("ergebnis");
    s = phaseVorbei(s, ctx, clock);
    expect(risikoLeiterPlugin.scores(s)).toEqual({
      p1: rlGipfelWert(), // 3.500
      p2: 700, // Kasse auf Stufe 4
      p3: 400, // Absturz auf die Sicherheitsstufe
      p4: 0, // Absturz unter der Sicherheitsstufe
    });
    const outcomes = risikoLeiterPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p3")].correct).toBe(false);
    expect(outcomes[asPlayerId("p4")].correct).toBe(false);
  });

  it("Zuschauer-/Doppel-/Spät-Antworten verpuffen (nur aktive Kletterer)", () => {
    const { clock, ctx, state } = setup();
    let s = reduce(
      state,
      aktion("p3", { type: "entscheidung", wahl: "absichern" }, clock.now() + 10),
      ctx,
    );
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("frage");
    // p3 (abgesichert) darf nicht antworten.
    expect(reduce(s, aktion("p3", { type: "answer", choice: 1 }, clock.now()), ctx)).toBe(s);
    // Zu spät verpufft.
    const zuSpaet = s.phaseEndsAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p1", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(s);
    // Erste Antwort rastet ein.
    s = reduce(s, aktion("p1", { type: "answer", choice: 0 }, clock.now() + 500), ctx);
    const doppelt = reduce(s, aktion("p1", { type: "answer", choice: 1 }, clock.now() + 600), ctx);
    expect(doppelt.answers.p1.choice).toBe(0);
  });
});

describe("risiko-leiter: Disconnect + GM + Leaks + Determinismus", () => {
  it("Kletterer-Disconnect = charmante Auto-Absicherung auf dem aktuellen Stand", () => {
    const { clock, ctx, state } = setup();
    let s = spieleStufe(state, ctx, clock, { antworten: { p1: 1, p2: 1, p3: 1, p4: 1 } });
    s = phaseVorbei(s, ctx, clock); // → Entscheidung Stufe 2
    s = risikoLeiterPlugin.onDisconnect(s, asPlayerId("p2"), ctx) as RisikoLeiterState;
    expect(s.kletterer.p2.status).toBe("abgesichert");
    expect(s.kletterer.p2.gutschrift).toBe(100); // Stand nach Stufe 1
    // Reconnect ändert nichts am gesicherten Status (kein Wiedereinstieg).
    s = risikoLeiterPlugin.onReconnect(s, asPlayerId("p2"), ctx) as RisikoLeiterState;
    expect(s.kletterer.p2.status).toBe("abgesichert");
  });

  it("Disconnect NACH abgegebener Antwort: die Antwort zählt regulär weiter", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s = phaseVorbei(state, ctx, clock); // Timeout ⇒ beide klettern
    expect(s.phase).toBe("frage");
    s = reduce(s, aktion("p1", { type: "answer", choice: 1 }, clock.now() + 300), ctx);
    s = risikoLeiterPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as RisikoLeiterState;
    expect(s.kletterer.p1.status).toBe("klettert"); // Antwort ist drin
    s = reduce(s, aktion("p2", { type: "answer", choice: 1 }, clock.now() + 400), ctx);
    s = tick(s, ctx);
    expect(s.phase).toBe("aufstieg");
    expect(s.kletterer.p1.stufe).toBe(1); // richtig gezählt trotz offline
  });

  it("GM force.finish VOR dem Ergebnis ⇒ Abbruch ohne Zahlung; im Ergebnis gilt es", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    const skip: GmAction = { kind: "gm", type: "force.finish" };
    let s = spieleStufe(state, ctx, clock, { antworten: { p1: 1, p2: 1 } });
    const abgebrochen = reduce(s, skip, ctx);
    expect(abgebrochen.finished).toBe(true);
    expect(risikoLeiterPlugin.scores(abgebrochen)).toEqual({ p1: 0, p2: 0 });
    // Regulär bis ins Ergebnis: dort bucht der Skip die Bilanz.
    s = phaseVorbei(s, ctx, clock);
    s = spieleStufe(s, ctx, clock, { absicherer: ["p1"], antworten: { p2: 0 } });
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("ergebnis");
    const fertig = reduce(s, skip, ctx);
    expect(fertig.finished).toBe(true);
    expect(risikoLeiterPlugin.scores(fertig)).toEqual({ p1: 100, p2: 0 });
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

  it("Leak-Wachen: Frage nur im Fenster, correctIndex nur GM/Beat, Buttons nur Kletterer", () => {
    const { clock, ctx, state } = setup();
    // Entscheidungs-Fenster: KEIN Frage-Text (die Wahl fällt VOR der Frage!).
    const vorab = risikoLeiterPlugin.viewFor(state, "screen") as Record<string, unknown>;
    expect(vorab.text).toBeNull();
    expect(vorab.options).toBeNull();
    expect(vorab.correctIndex).toBeUndefined();
    let s = reduce(
      state,
      aktion("p3", { type: "entscheidung", wahl: "absichern" }, clock.now() + 10),
      ctx,
    );
    s = phaseVorbei(s, ctx, clock); // → frage
    const screen = risikoLeiterPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.text).toBe("Stufen-Frage 1?");
    expect(screen.correctIndex).toBeUndefined();
    expect(screen.letzterBeat).toBeNull(); // Lösung erst im Aufstiegs-Beat
    const kletterer = risikoLeiterPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(kletterer.options).toEqual(["A", "B", "C", "D"]);
    expect(kletterer.correctIndex).toBeUndefined();
    const zuschauer = risikoLeiterPlugin.viewFor(s, "player", asPlayerId("p3")) as Record<
      string,
      unknown
    >;
    expect(zuschauer.options).toBeNull(); // abgesichert = charmant zuschauen
    expect(zuschauer.zuschauerOptionen).toEqual(["A", "B", "C", "D"]);
    expect(zuschauer.duKletterst).toBe(false);
    const gm = risikoLeiterPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.correctIndex).toBe(1);
  });

  it("Entscheidungs-Geheimnis: im Fenster reist nur die Anzahl, nie die Wahl", () => {
    const { clock, ctx, state } = setup();
    const s = reduce(
      state,
      aktion("p1", { type: "entscheidung", wahl: "weiter" }, clock.now() + 10),
      ctx,
    );
    const screen = risikoLeiterPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.entschiedenCount).toBe(1);
    expect(screen.entscheidungen).toBeUndefined();
    const mitspieler = risikoLeiterPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(mitspieler.entscheidungen).toBeUndefined();
    expect(mitspieler.deineWahl).toBeNull();
    const selbst = risikoLeiterPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(selbst.deineWahl).toBe("weiter");
    const gm = risikoLeiterPlugin.viewFor(s, "gm") as { entscheidungen: Record<string, string> };
    expect(gm.entscheidungen).toEqual({ p1: "weiter" }); // Spickzettel sieht alles
  });

  it("Player-View trägt die Kletter-Drähte: Stand, nächster Wert, Sicherheitsnetz", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"] });
    let s = spieleStufe(state, ctx, clock, { antworten: { p1: 1, p2: 1 } });
    for (let stufe = 2; stufe <= 3; stufe++) {
      s = phaseVorbei(s, ctx, clock);
      s = spieleStufe(s, ctx, clock, { antworten: { p1: 1, p2: 1 } });
    }
    s = phaseVorbei(s, ctx, clock); // → Entscheidung Stufe 4
    const view = risikoLeiterPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<
      string,
      unknown
    >;
    expect(view.deineStufe).toBe(3);
    expect(view.deinStand).toBe(400);
    expect(view.naechsterWert).toBe(700);
    expect(view.deinSicherheitsWert).toBe(400); // Sicherheitsstufe erklommen
  });

  it("Seed-Determinismus: gleiche Aktionen ⇒ Bit-identische States", () => {
    const lauf = () => {
      const { clock, ctx, state } = setup({ seed: 42 });
      let s = spieleStufe(state, ctx, clock, {
        absicherer: ["p2"],
        antworten: { p1: 1, p3: 0, p4: null },
      });
      s = phaseVorbei(s, ctx, clock);
      return s;
    };
    expect(JSON.stringify(lauf())).toBe(JSON.stringify(lauf()));
  });
});
