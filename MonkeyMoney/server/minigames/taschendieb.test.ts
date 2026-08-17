// Taschendieb-Affe: Klau-Recht-Rennen (Server-Timestamps), Fotofinish <50 ms,
// Steal-Grenzen (300/500, Kappe 25 %), Anti-Mobbing, Klau-Schutz-Joker-Hook,
// Opferwahl-Default „reichster Spieler", 2-Spieler-Sonderfall, Leak-Schutz.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import { TD_OPFERWAHL_MS, tdKlauBetrag } from "../../shared/minigames/taschendieb.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import type { PlayerAction } from "./_api/plugin";
import {
  taschendiebPlugin,
  type TaschendiebSlice,
  type TaschendiebState,
} from "./taschendieb/index";

function frage(difficulty: Question["difficulty"] = "medium"): Question {
  return {
    id: "q_td",
    kind: "choice4",
    category: "krimi",
    difficulty,
    text: "Wer hat die Banane geklaut?",
    options: ["Der Gärtner", "Der Butler", "Die Köchin", "Der Affe"],
    answer: 3,
    erklaerung: "Es ist IMMER der Affe.",
  };
}

const vier = ["p1", "p2", "p3", "p4"].map(asPlayerId);

function setup(opts?: {
  difficulty?: Question["difficulty"];
  spieler?: string[];
  kontostaende?: Record<string, number>;
  letzteOpfer?: string[];
  klauSchutz?: string[];
}) {
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(3) };
  const spieler = (opts?.spieler ?? vier.map(String)).map(asPlayerId);
  const content: TaschendiebSlice = {
    questions: [frage(opts?.difficulty ?? "medium")],
    kontostaende: opts?.kontostaende ?? { p1: 2000, p2: 1600, p3: 1200, p4: 400 },
    letzteOpfer: opts?.letzteOpfer,
    klauSchutz: opts?.klauSchutz,
  };
  const state = taschendiebPlugin.init(spieler, content as ContentSlice, ctx) as TaschendiebState;
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

function steal(
  playerId: string,
  targetId: string,
): PlayerAction<{ type: "steal"; targetId: string }> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "steal", targetId },
    atServerTime: 0,
  };
}

/** Alle 4 antworten, dann Frage auswerten (alle beantwortet ⇒ Tick wertet sofort). */
function bisOpferwahl(zeiten: Record<string, { choice: number; at: number }>) {
  const { clock, ctx, state } = setup();
  let s: TaschendiebState = state;
  for (const [pid, z] of Object.entries(zeiten)) {
    s = taschendiebPlugin.reduce(s, antwort(pid, z.choice, z.at), ctx) as TaschendiebState;
  }
  clock.advance(100);
  s = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
  return { clock, ctx, s };
}

describe("taschendieb: Klau-Recht-Rennen", () => {
  it("die schnellste RICHTIGE Antwort gewinnt; andere Richtige bekommen halben Grundwert", () => {
    const { s } = bisOpferwahl({
      p1: { choice: 3, at: 5_000 },
      p2: { choice: 3, at: 6_200 },
      p3: { choice: 0, at: 2_000 }, // falsch UND schnell ⇒ egal
      p4: { choice: 3, at: 9_000 },
    });
    expect(s.phase).toBe("opferwahl");
    expect(s.dieb).toBe("p1");
    expect(s.fotofinish).toEqual([]);
    // Scores nach Klau (Default-Opfer p2 = reichster außer Dieb):
    const fertig = taschendiebPlugin.reduce(
      s,
      { kind: "gm", type: "force.finish" },
      { clock: createTestClock(20_000), rng: createRng(1) },
    ) as TaschendiebState;
    const scores = taschendiebPlugin.scores(fertig);
    expect(scores[asPlayerId("p2")]).toBe(125 - 300); // halber Grundwert − geklaut
    expect(scores[asPlayerId("p4")]).toBe(125);
    expect(scores[asPlayerId("p3")]).toBe(0);
    expect(scores[asPlayerId("p1")]).toBe(300); // Dieb: NUR der Klau, kein Grundwert
  });

  it("FOTOFINISH <50 ms: früherer Timestamp klaut, der andere bekommt VOLLEN Grundwert", () => {
    const { ctx, s } = bisOpferwahl({
      p1: { choice: 3, at: 5_049 },
      p2: { choice: 3, at: 5_000 },
      p3: { choice: 3, at: 5_050 }, // exakt 50 ms ⇒ KEIN Fotofinish, halber Wert
      p4: { choice: 0, at: 4_000 },
    });
    expect(s.dieb).toBe("p2");
    expect(s.fotofinish).toEqual(["p1"]);
    const nachKlau = taschendiebPlugin.reduce(s, steal("p2", "p4"), ctx) as TaschendiebState;
    const scores = taschendiebPlugin.scores({ ...nachKlau, finished: true });
    expect(scores[asPlayerId("p1")]).toBe(250); // voller Grundwert (MEDIUM)
    expect(scores[asPlayerId("p3")]).toBe(125); // halber Grundwert
    expect(scores[asPlayerId("p2")]).toBe(100); // Klau, gekappt auf 25 % von 400
    expect(scores[asPlayerId("p4")]).toBe(-100);
  });

  it("exakter Zeit-Gleichstand wird deterministisch über die Join-Reihenfolge gelöst", () => {
    const { s } = bisOpferwahl({
      p3: { choice: 3, at: 5_000 },
      p2: { choice: 3, at: 5_000 },
      p1: { choice: 0, at: 1_000 },
      p4: { choice: 0, at: 1_000 },
    });
    expect(s.dieb).toBe("p2"); // p2 vor p3 in der Join-Reihenfolge
    expect(s.fotofinish).toEqual(["p3"]);
  });

  it("niemand richtig ⇒ kein Klau, sauberes Ende ohne Deltas", () => {
    const { clock, ctx, s } = bisOpferwahl({
      p1: { choice: 0, at: 1_000 },
      p2: { choice: 1, at: 2_000 },
      p3: { choice: 2, at: 3_000 },
      p4: { choice: 0, at: 4_000 },
    });
    expect(s.phase).toBe("niemand");
    clock.advance(10_000);
    const fertig = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(taschendiebPlugin.isFinished(fertig)).toBe(true);
    expect(Object.values(taschendiebPlugin.scores(fertig))).toEqual([0, 0, 0, 0]);
  });

  it("Spätantworten: Gnadenfenster +400 ms gilt, danach verworfen (Sammel-Fenster)", () => {
    const { ctx, state } = setup();
    const ende = state.phaseEndsAt;
    const geradeNoch = taschendiebPlugin.reduce(
      state,
      antwort("p1", 3, ende + SPAETANTWORT_GNADE_MS - 1),
      ctx,
    ) as TaschendiebState;
    expect(geradeNoch.answers.p1).toBeDefined();
    const zuSpaet = taschendiebPlugin.reduce(
      state,
      antwort("p1", 3, ende + SPAETANTWORT_GNADE_MS + 1),
      ctx,
    ) as TaschendiebState;
    expect(zuSpaet.answers.p1).toBeUndefined();
  });
});

describe("taschendieb: Steal-Grenzen (GAME-DESIGN §3.2)", () => {
  it("Klau-Beträge: MEDIUM 300, HARD 500; Kappe 25 % des Opfer-Kontos, 10er-gerundet", () => {
    expect(tdKlauBetrag("medium", 2_000)).toBe(300); // Kappe 500 greift nicht
    expect(tdKlauBetrag("hard", 2_000)).toBe(500);
    expect(tdKlauBetrag("medium", 1_000)).toBe(250); // 25 % = 250 < 300
    expect(tdKlauBetrag("hard", 1_000)).toBe(250);
    expect(tdKlauBetrag("medium", 90)).toBe(20); // floor(22,5 → 20)
    expect(tdKlauBetrag("medium", 0)).toBe(0); // leeres Konto = nichts zu holen
    expect(tdKlauBetrag("medium", null)).toBe(300); // Kontostand unbekannt ⇒ voller Betrag
  });

  it("wendet die Kappe im Spiel an: armes Wunsch-Opfer verliert nur 25 %", () => {
    const { ctx, s } = bisOpferwahl({
      p1: { choice: 3, at: 5_000 },
      p2: { choice: 0, at: 6_000 },
      p3: { choice: 0, at: 6_000 },
      p4: { choice: 0, at: 6_000 },
    });
    const nachKlau = taschendiebPlugin.reduce(s, steal("p1", "p4"), ctx) as TaschendiebState;
    expect(nachKlau.phase).toBe("cutscene");
    expect(nachKlau.opfer).toBe("p4");
    expect(nachKlau.klau).toEqual({ betrag: 100, abgeprallt: false }); // 25 % von 400
    const scores = taschendiebPlugin.scores({ ...nachKlau, finished: true });
    expect(scores[asPlayerId("p1")]).toBe(100);
    expect(scores[asPlayerId("p4")]).toBe(-100);
  });
});

describe("taschendieb: Opferwahl-Regeln", () => {
  it("Timeout ⇒ Default: reichster verbundener Spieler", () => {
    const { clock, ctx, s } = bisOpferwahl({
      p3: { choice: 3, at: 5_000 },
      p1: { choice: 0, at: 6_000 },
      p2: { choice: 0, at: 6_000 },
      p4: { choice: 0, at: 6_000 },
    });
    expect(s.dieb).toBe("p3");
    clock.advance(TD_OPFERWAHL_MS + 1_000);
    const nachTimeout = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(nachTimeout.phase).toBe("cutscene");
    expect(nachTimeout.opfer).toBe("p1"); // 2.000 MM = der Reichste
  });

  it("Anti-Mobbing SERVER-HART: 3× in Folge dasselbe Opfer geht nicht", () => {
    const { clock, ctx, state } = setup({ letzteOpfer: ["p2", "p2"] });
    let s: TaschendiebState = state;
    s = taschendiebPlugin.reduce(s, antwort("p1", 3, 5_000), ctx) as TaschendiebState;
    for (const p of ["p2", "p3", "p4"])
      s = taschendiebPlugin.reduce(s, antwort(p, 0, 6_000), ctx) as TaschendiebState;
    clock.advance(100);
    s = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(s.dieb).toBe("p1");
    // Wunsch „p2" wird ignoriert (gesperrt) — der Dieb kann neu wählen.
    const abgelehnt = taschendiebPlugin.reduce(s, steal("p1", "p2"), ctx) as TaschendiebState;
    expect(abgelehnt.phase).toBe("opferwahl");
    // Auch der Timeout-Default überspringt p2 (reichster ZULÄSSIGER = p3).
    clock.advance(TD_OPFERWAHL_MS + 1_000);
    const nachTimeout = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(nachTimeout.opfer).toBe("p3");
    // View markiert das gesperrte Ziel für das Dieb-Grid.
    const diebView = taschendiebPlugin.viewFor(s, "player", asPlayerId("p1")) as {
      ziele: { id: string; waehlbar: boolean }[];
    };
    expect(diebView.ziele.find((z) => z.id === "p2")?.waehlbar).toBe(false);
  });

  it("Klau-Schutz-Joker (Bananentresor): Klau prallt ab — 0 MM, Sternchen-Cutscene", () => {
    const { clock, ctx, state } = setup({ klauSchutz: ["p2"] });
    let s: TaschendiebState = state;
    s = taschendiebPlugin.reduce(s, antwort("p1", 3, 5_000), ctx) as TaschendiebState;
    for (const p of ["p2", "p3", "p4"])
      s = taschendiebPlugin.reduce(s, antwort(p, 0, 6_000), ctx) as TaschendiebState;
    clock.advance(100);
    s = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, steal("p1", "p2"), ctx) as TaschendiebState;
    expect(s.klau).toEqual({ betrag: 0, abgeprallt: true });
    const scores = taschendiebPlugin.scores({ ...s, finished: true });
    expect(scores[asPlayerId("p1")]).toBe(0);
    expect(scores[asPlayerId("p2")]).toBe(0);
  });

  it("Klau auf Disconnected ⇒ automatisch reichster VERBUNDENER Spieler", () => {
    const { clock, ctx, state } = setup();
    let s: TaschendiebState = state;
    s = taschendiebPlugin.reduce(s, antwort("p4", 3, 5_000), ctx) as TaschendiebState;
    for (const p of ["p1", "p2", "p3"])
      s = taschendiebPlugin.reduce(s, antwort(p, 0, 6_000), ctx) as TaschendiebState;
    clock.advance(100);
    s = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(s.dieb).toBe("p4");
    s = taschendiebPlugin.onDisconnect(s, asPlayerId("p1"), ctx) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, steal("p4", "p1"), ctx) as TaschendiebState;
    expect(s.opfer).toBe("p2"); // p1 offline ⇒ reichster Verbundener
  });

  it("2-Spieler-Spiel: Opfer ist automatisch der Gegner (keine Opferwahl-Phase)", () => {
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(3) };
    const content: TaschendiebSlice = {
      questions: [frage("hard")],
      kontostaende: { a: 3_000, b: 3_000 },
    };
    let s = taschendiebPlugin.init(
      ["a", "b"].map(asPlayerId),
      content as ContentSlice,
      ctx,
    ) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, antwort("a", 3, 4_000), ctx) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, antwort("b", 0, 5_000), ctx) as TaschendiebState;
    clock.advance(100);
    s = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(s.phase).toBe("cutscene"); // Opferwahl übersprungen
    expect(s.opfer).toBe("b");
    expect(s.klau?.betrag).toBe(500); // HARD, Kappe 750 greift nicht
  });
});

describe("taschendieb: Leak-Schutz + Vertrag", () => {
  it("correctIndex bleibt bis zur Auflösung geheim; das Ziel-Grid sieht NUR der Dieb", () => {
    const { ctx, s } = bisOpferwahl({
      p1: { choice: 3, at: 5_000 },
      p2: { choice: 0, at: 6_000 },
      p3: { choice: 0, at: 6_000 },
      p4: { choice: 0, at: 6_000 },
    });
    void ctx;
    const screenView = JSON.stringify(taschendiebPlugin.viewFor(s, "screen"));
    expect(screenView).not.toContain("correctIndex");
    const zuschauerView = taschendiebPlugin.viewFor(s, "player", asPlayerId("p2")) as {
      ziele: unknown;
      istDieb: boolean;
    };
    expect(zuschauerView.istDieb).toBe(false);
    expect(zuschauerView.ziele).toBeNull();
    const diebView = taschendiebPlugin.viewFor(s, "player", asPlayerId("p1")) as {
      ziele: unknown[];
    };
    expect(diebView.ziele).toHaveLength(3);
    const gmView = taschendiebPlugin.viewFor(s, "gm") as { correctIndex: number };
    expect(gmView.correctIndex).toBe(3);
  });

  it("hält den State JSON-serialisierbar (Contract-Grundlage)", () => {
    const { ctx, s } = bisOpferwahl({
      p1: { choice: 3, at: 5_000 },
      p2: { choice: 3, at: 7_000 },
      p3: { choice: 1, at: 6_000 },
      p4: { choice: 0, at: 6_000 },
    });
    const nachKlau = taschendiebPlugin.reduce(s, steal("p1", "p3"), ctx) as TaschendiebState;
    const kopie = JSON.parse(JSON.stringify(nachKlau)) as TaschendiebState;
    expect(taschendiebPlugin.scores(kopie)).toEqual(taschendiebPlugin.scores(nachKlau));
  });
});

describe("taschendieb: Maßanzug (mods.fragenProSpieler — Befund-Fix)", () => {
  it("zugewiesener Spieler wird an SEINER Frage gemessen — Klau-Recht inklusive", () => {
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(3) };
    const eigene: Question = {
      ...frage("medium"),
      id: "q_td_eigen",
      text: "Eigene Frage?",
      answer: 0,
    };
    const content: TaschendiebSlice = {
      questions: [frage("medium")],
      kontostaende: { p1: 2000, p2: 1600, p3: 1200, p4: 400 },
      mods: { fragenProSpieler: { p2: eigene } },
    };
    let s = taschendiebPlugin.init(vier, content as ContentSlice, ctx) as TaschendiebState;
    // p2 sieht auf dem Handy SEINE Frage, p3 die Basis-Frage; Screen bleibt Basis.
    const v2 = taschendiebPlugin.viewFor(s, "player", asPlayerId("p2")) as { text: string };
    expect(v2.text).toBe("Eigene Frage?");
    const v3 = taschendiebPlugin.viewFor(s, "player", asPlayerId("p3")) as { text: string };
    expect(v3.text).toBe("Wer hat die Banane geklaut?");
    expect((taschendiebPlugin.viewFor(s, "screen") as { text: string }).text).toBe(
      "Wer hat die Banane geklaut?",
    );
    // p2 antwortet 0 (an SEINER Frage richtig) und am schnellsten;
    // p1 wählt 0 an der BASIS-Frage (dort falsch — richtig ist 3).
    s = taschendiebPlugin.reduce(s, antwort("p2", 0, 500), ctx) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, antwort("p1", 0, 800), ctx) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, antwort("p3", 3, 1_000), ctx) as TaschendiebState;
    s = taschendiebPlugin.reduce(s, antwort("p4", 1, 1_200), ctx) as TaschendiebState;
    clock.advance(100);
    s = taschendiebPlugin.tick(s, ctx) as TaschendiebState;
    expect(s.dieb).toBe("p2"); // richtig an der EIGENEN Frage + am schnellsten
    const outcomes = taschendiebPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p2")].correct).toBe(true);
    expect(outcomes[asPlayerId("p1")].correct).toBe(false); // 0 ist an der Basis falsch
    expect(outcomes[asPlayerId("p3")].correct).toBe(true); // 3 an der Basis richtig
  });
});
