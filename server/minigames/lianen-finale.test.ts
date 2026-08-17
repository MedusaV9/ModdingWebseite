// Lianen-Finale: W_final-Formel (±W, −W/2, 0 — Engine bucht, Plugin spiegelt),
// Lianen-Normierung (Führender 100 %, Minimum 25 %), Antwort-Lock + Spätantwort,
// Disconnect (0-Antworten), Leak-Wachen, Seed-Determinismus — plus der
// Playlist-Beweis: alle 4 neuen Formate lösen OHNE Fallback auf.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { wFinal } from "../../shared/economy";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  LF_FALLBACK_W,
  LF_FRAGE_MS,
  lfLianenLaenge,
} from "../../shared/minigames/lianen-finale.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { MODUS_BLAUPAUSEN } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import type { Ctx, MatchApi, PlayerAction } from "./_api/plugin";
import { lianenFinalePlugin, type LianenFinaleState } from "./lianen-finale/index";
import { allePlugins } from "./registry";

const frage: Question = {
  id: "q_lf_1",
  kind: "choice4",
  category: "finale",
  difficulty: "hard",
  text: "Die Finalfrage?",
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "A stimmt.",
};

function fakeMatch(balances: Record<string, number>): MatchApi {
  return {
    balance: (p: PlayerId) => balances[p] ?? 0,
    reihenfolge: () => Object.keys(balances).map(asPlayerId),
    hatKlauSchutz: () => false,
    istVerbunden: () => true,
  };
}

function setup(balances: Record<string, number> = { p1: 4_000, p2: 2_000, p3: 500 }, w = 1_000) {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(1), match: fakeMatch(balances) };
  const content: ContentSlice = { questions: [frage], mods: { wFinal: w } };
  const spieler = Object.keys(balances).map(asPlayerId);
  const state = lianenFinalePlugin.init(spieler, content, ctx) as LianenFinaleState;
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

describe("lianen-finale: W_final-Formel (§3.5)", () => {
  it("Formel-Goldens: W = max(500, aufrunden(1,25 × G / Q auf 50er))", () => {
    expect(wFinal(4_000, 5)).toBe(1_000); // Klassik-Beispiel
    expect(wFinal(4_000, 5, 1.5)).toBe(1_200); // Chaos-Faktor
    expect(wFinal(0, 5)).toBe(500); // Formel-Minimum
    expect(wFinal(3_333, 5)).toBe(850); // 833,25 → auf 50er AUFgerundet
  });

  it("richtig = +W (Ruck hoch), falsch = −W/2 (Riss), keine Antwort = 0 — exakt", () => {
    const { clock, ctx, state } = setup();
    let s = lianenFinalePlugin.reduce(state, antwort("p1", 0, 2_000), ctx) as LianenFinaleState;
    s = lianenFinalePlugin.reduce(s, antwort("p2", 1, 2_000), ctx) as LianenFinaleState;
    clock.advance(LF_FRAGE_MS + 1);
    s = lianenFinalePlugin.tick(s, ctx) as LianenFinaleState;
    expect(lianenFinalePlugin.isFinished(s)).toBe(true);
    expect(lianenFinalePlugin.scores(s)).toEqual({ p1: 1_000, p2: -500, p3: 0 });
    const outcomes = lianenFinalePlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBeNull();
  });

  it("kein Speed-Bonus: früh und spät richtig zahlen DENSELBEN Betrag", () => {
    const { ctx, state } = setup();
    let s = lianenFinalePlugin.reduce(state, antwort("p1", 0, 100), ctx) as LianenFinaleState;
    s = lianenFinalePlugin.reduce(s, antwort("p2", 0, LF_FRAGE_MS - 100), ctx) as LianenFinaleState;
    s = { ...s, finished: true };
    const scores = lianenFinalePlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(scores[asPlayerId("p2")]);
  });

  it("ohne mods.wFinal greift das Formel-Minimum 500 (isolierte Läufe)", () => {
    const clock = createTestClock(0);
    const ctx: Ctx = { clock, rng: createRng(1) };
    const s = lianenFinalePlugin.init(
      ["p1", "p2"].map(asPlayerId),
      { questions: [frage] },
      ctx,
    ) as LianenFinaleState;
    expect(s.wFinal).toBe(LF_FALLBACK_W);
    expect(s.balances).toEqual({ p1: 0, p2: 0 }); // ohne match-API: neutraler Start
  });

  it("meta-Vertrag: keine Streak, KEINE Joker-Hooks, eigenes Set (needsScreen)", () => {
    expect(lianenFinalePlugin.meta.streak).toBe(false);
    expect(lianenFinalePlugin.meta.jokerAktionen).toBeUndefined();
    expect(lianenFinalePlugin.meta.needsScreen).toBe(true);
    expect(lianenFinalePlugin.meta.roundBased).toBeUndefined(); // 1 init pro Finalfrage
  });
});

describe("lianen-finale: Lianen-Normierung (§2.10)", () => {
  it("Führender 100 %, alle proportional, Anzeige-Minimum 25 %", () => {
    expect(lfLianenLaenge(4_000, 4_000)).toBe(1);
    expect(lfLianenLaenge(2_000, 4_000)).toBe(0.5);
    expect(lfLianenLaenge(500, 4_000)).toBe(0.25); // exakt am Minimum
    expect(lfLianenLaenge(100, 4_000)).toBe(0.25); // darunter: geklemmt
    expect(lfLianenLaenge(-300, 4_000)).toBe(0.25); // Dispo: nie unter Minimum
    expect(lfLianenLaenge(0, 0)).toBe(1); // alle bei 0: volle Liane für alle
  });

  it("das View-Tableau nutzt die Konto-Snapshots (ctx.match) korrekt", () => {
    const { state } = setup();
    const screen = lianenFinalePlugin.viewFor(state, "screen") as {
      wFinal: number;
      lianen: { playerId: string; laenge: number; kontostand: number }[];
    };
    expect(screen.wFinal).toBe(1_000);
    expect(screen.lianen).toEqual([
      { playerId: "p1", laenge: 1, kontostand: 4_000, verbunden: true },
      { playerId: "p2", laenge: 0.5, kontostand: 2_000, verbunden: true },
      { playerId: "p3", laenge: 0.25, kontostand: 500, verbunden: true },
    ]);
    const eigene = lianenFinalePlugin.viewFor(state, "player", asPlayerId("p2")) as {
      deineLiane: number;
    };
    expect(eigene.deineLiane).toBe(0.5);
  });

  it("Auflösung projiziert die Lianen NACH der Buchung (Ruck/Riss fürs Set)", () => {
    const { ctx, state } = setup({ p1: 1_000, p2: 500 });
    let s = lianenFinalePlugin.reduce(state, antwort("p1", 1, 1_000), ctx) as LianenFinaleState; // falsch
    s = lianenFinalePlugin.reduce(s, antwort("p2", 0, 1_000), ctx) as LianenFinaleState; // richtig
    s = lianenFinalePlugin.tick(s, ctx) as LianenFinaleState; // alle fertig ⇒ finished
    const view = lianenFinalePlugin.viewFor(s, "screen") as {
      aufloesung: { perPlayer: { playerId: string; delta: number; lianeNachher: number }[] };
    };
    // p1: 1.000 − 500 = 500, p2: 500 + 1.000 = 1.500 ⇒ neuer Führender p2.
    const p1 = view.aufloesung.perPlayer.find((x) => x.playerId === "p1")!;
    const p2 = view.aufloesung.perPlayer.find((x) => x.playerId === "p2")!;
    expect(p1.delta).toBe(-500);
    expect(p2.delta).toBe(1_000);
    expect(p2.lianeNachher).toBe(1);
    expect(p1.lianeNachher).toBeCloseTo(500 / 1_500, 10);
  });
});

describe("lianen-finale: Locks, Spätantwort, Disconnect", () => {
  it("die erste Antwort rastet ein; Spätantwort nur bis +400 ms Gnade", () => {
    const { ctx, state } = setup();
    const s1 = lianenFinalePlugin.reduce(state, antwort("p1", 2, 1_000), ctx) as LianenFinaleState;
    expect(lianenFinalePlugin.reduce(s1, antwort("p1", 0, 2_000), ctx)).toBe(s1);
    const nochOk = lianenFinalePlugin.reduce(
      state,
      antwort("p2", 0, state.endsAt + SPAETANTWORT_GNADE_MS),
      ctx,
    ) as LianenFinaleState;
    expect(nochOk.answers.p2).toBeDefined();
    expect(
      lianenFinalePlugin.reduce(
        state,
        antwort("p2", 0, state.endsAt + SPAETANTWORT_GNADE_MS + 1),
        ctx,
      ),
    ).toBe(state);
  });

  it("Finalist-Disconnect spielt 0-Antworten — und blockiert das Früh-Ende der Verbundenen nicht", () => {
    const { ctx, state } = setup();
    let s = lianenFinalePlugin.onDisconnect(state, asPlayerId("p3"), ctx) as LianenFinaleState;
    s = lianenFinalePlugin.reduce(s, antwort("p1", 0, 1_000), ctx) as LianenFinaleState;
    s = lianenFinalePlugin.reduce(s, antwort("p2", 0, 1_200), ctx) as LianenFinaleState;
    s = lianenFinalePlugin.tick(s, ctx) as LianenFinaleState;
    expect(lianenFinalePlugin.isFinished(s)).toBe(true); // alle VERBUNDENEN fertig
    expect(lianenFinalePlugin.scores(s)[asPlayerId("p3")]).toBe(0);
    expect(lianenFinalePlugin.outcomes!(s)[asPlayerId("p3")].correct).toBeNull();
  });

  it("GM: force.finish beendet sofort, timer.extend verlängert die Deadline", () => {
    const { ctx, state } = setup();
    const laenger = lianenFinalePlugin.reduce(
      state,
      { kind: "gm", type: "timer.extend", ms: 15_000 },
      ctx,
    ) as LianenFinaleState;
    expect(laenger.endsAt).toBe(state.endsAt + 15_000);
    const fertig = lianenFinalePlugin.reduce(
      state,
      { kind: "gm", type: "force.finish" },
      ctx,
    ) as LianenFinaleState;
    expect(lianenFinalePlugin.isFinished(fertig)).toBe(true);
  });
});

describe("lianen-finale: Leak-Wachen + Determinismus", () => {
  it("correctIndex + Erklärung bleiben bis zur Auflösung auf dem Server; GM sieht sie immer", () => {
    const { state } = setup();
    const screen = JSON.stringify(lianenFinalePlugin.viewFor(state, "screen"));
    const player = JSON.stringify(lianenFinalePlugin.viewFor(state, "player", asPlayerId("p1")));
    expect(screen).not.toContain("correctIndex");
    expect(player).not.toContain("correctIndex");
    expect(screen).not.toContain(frage.erklaerung);
    const gm = lianenFinalePlugin.viewFor(state, "gm") as { correctIndex: number };
    expect(gm.correctIndex).toBe(0);
    // Nach finished ist die Auflösung public:
    const fertig = { ...state, finished: true };
    const auf = lianenFinalePlugin.viewFor(fertig, "screen") as {
      aufloesung: { correctIndex: number };
    };
    expect(auf.aufloesung.correctIndex).toBe(0);
  });

  it("Determinismus + JSON-Serialisierbarkeit (Save/Load-Vertrag)", () => {
    const lauf = (): string => {
      const { ctx, state } = setup({ p1: 3_000, p2: 900 }, 750);
      let s = lianenFinalePlugin.reduce(state, antwort("p1", 0, 800), ctx) as LianenFinaleState;
      s = lianenFinalePlugin.reduce(s, antwort("p2", 3, 950), ctx) as LianenFinaleState;
      s = lianenFinalePlugin.tick(s, ctx) as LianenFinaleState;
      return JSON.stringify([s, lianenFinalePlugin.scores(s)]);
    };
    expect(lauf()).toBe(lauf());
    const kopie = JSON.parse(lauf()) as [LianenFinaleState, Record<string, number>];
    expect(lianenFinalePlugin.scores(kopie[0])).toEqual(kopie[1]);
  });
});

describe("Engine-Playlist: die 4 neuen Formate lösen OHNE Fallback auf", () => {
  it("JEDE Blaupausen-Runde + das Finale sind in der Registry — kein vier-lianen-Fallback mehr", () => {
    // Die Engine fällt nur zurück, wenn ein Wunsch-Format NICHT registriert ist
    // (plan.aufloesen) — also: alle Playlist-Slugs müssen verfügbar sein.
    const verfuegbar = new Set(allePlugins());
    for (const modus of ["quick", "klassik", "marathon"] as const) {
      for (const r of MODUS_BLAUPAUSEN[modus].runden) {
        expect(verfuegbar.has(r.minigameId)).toBe(true);
      }
    }
    expect(verfuegbar.has("lianen-finale")).toBe(true); // Finale-Abschnitt, fix
    const klassik = MODUS_BLAUPAUSEN.klassik.runden.map((r) => r.minigameId);
    expect(klassik).toContain("bananen-basics");
    expect(klassik).toContain("affenbank");
    expect(klassik).toContain("alles-oder-banane");
  });
});
