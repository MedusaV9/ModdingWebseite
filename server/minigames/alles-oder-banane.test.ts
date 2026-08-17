// Alles oder Banane: Wett-Mathe exakt ±Einsatz (Goldens), Einsatz-Klemmen
// (50er-Raster, 50-%-Kappe, Gratis-Kredit), Phasen-Maschine (setzen → reveal →
// frage), Auto-Minimum, Disconnect-Erstattung, GM-Skip, Joker-Gating,
// Seed-Determinismus und die Leak-Wachen (Frage + Einsätze bleiben geheim).
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  AOB_FRAGE_MS,
  AOB_REVEAL_MS,
  AOB_SETZEN_MS,
  aobEinsatzMax,
  aobKlemmeEinsatz,
} from "../../shared/minigames/alles-oder-banane.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, JokerAction, MatchApi, PlayerAction } from "./_api/plugin";
import { allesOderBananePlugin, type AllesOderBananeState } from "./alles-oder-banane/index";

const frage: Question = {
  id: "q_aob_1",
  kind: "choice4",
  category: "hauptstaedte",
  difficulty: "hard",
  text: "Hauptstadt von Australien?",
  options: ["Sydney", "Canberra", "Melbourne", "Perth"],
  answer: 1,
  erklaerung: "Canberra — nicht Sydney.",
};

function fakeMatch(balances: Record<string, number>): MatchApi {
  return {
    balance: (p: PlayerId) => balances[p] ?? 0,
    reihenfolge: () => Object.keys(balances).map(asPlayerId),
    hatKlauSchutz: () => false,
    istVerbunden: () => true,
  };
}

function setup(
  balances: Record<string, number> = { p1: 1_000, p2: 1_000, p3: 1_000 },
  seed = 1,
  mods?: ContentSlice["mods"],
) {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(seed), match: fakeMatch(balances) };
  const content: ContentSlice = mods ? { questions: [frage], mods } : { questions: [frage] };
  const spieler = Object.keys(balances).map(asPlayerId);
  const state = allesOderBananePlugin.init(spieler, content, ctx) as AllesOderBananeState;
  return { clock, ctx, state, spieler };
}

function einsatz(
  playerId: string,
  betrag: number,
  atServerTime: number,
): PlayerAction<{ type: "einsatz"; betrag: number }> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "einsatz", betrag },
    atServerTime,
  };
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

/** Bis in die Frage-Phase spulen (alle Einsätze müssen schon gesetzt sein). */
function bisFrage(
  s: AllesOderBananeState,
  ctx: Ctx,
  clock: ReturnType<typeof createTestClock>,
): AllesOderBananeState {
  clock.advance(Math.max(0, s.setzenEndetAt - clock.now()) + 1);
  s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState; // → reveal
  clock.advance(AOB_REVEAL_MS + 1);
  return allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState; // → frage
}

describe("alles-oder-banane: Wett-Mathe (Goldens §2.9)", () => {
  it("richtig = +Einsatz, falsch = −Einsatz, exakt — keine Streak, kein Speed", () => {
    const { clock, ctx, state } = setup();
    let s = allesOderBananePlugin.reduce(
      state,
      einsatz("p1", 300, 1_000),
      ctx,
    ) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, einsatz("p2", 500, 1_000), ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, einsatz("p3", 100, 1_000), ctx) as AllesOderBananeState;
    s = bisFrage(s, ctx, clock);
    expect(s.phase).toBe("frage");
    const t = clock.now() + 2_000;
    s = allesOderBananePlugin.reduce(s, antwort("p1", 1, t), ctx) as AllesOderBananeState; // richtig
    s = allesOderBananePlugin.reduce(s, antwort("p2", 0, t), ctx) as AllesOderBananeState; // falsch
    s = allesOderBananePlugin.reduce(s, antwort("p3", 1, t + 5_000), ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState; // alle fertig
    expect(allesOderBananePlugin.isFinished(s)).toBe(true);
    expect(allesOderBananePlugin.scores(s)).toEqual({ p1: 300, p2: -500, p3: 100 });
    // Früh oder spät geantwortet: identische Auszahlung (kein Speed-Bonus).
    expect(allesOderBananePlugin.scores(s)[asPlayerId("p3")]).toBe(100);
  });

  it("keine Antwort (verbunden) = Einsatz weg; Rückgaberecht-Gewinn = 50 % (10er-Rundung)", () => {
    const { clock, ctx, state } = setup();
    let s = allesOderBananePlugin.reduce(
      state,
      einsatz("p1", 300, 1_000),
      ctx,
    ) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, einsatz("p2", 300, 1_000), ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, einsatz("p3", 300, 1_000), ctx) as AllesOderBananeState;
    s = bisFrage(s, ctx, clock);
    const t = clock.now() + 2_000;
    // p1: falsch, dann Rückgaberecht, dann richtig ⇒ +150.
    s = allesOderBananePlugin.reduce(s, antwort("p1", 0, t), ctx) as AllesOderBananeState;
    const j: JokerAction = { kind: "joker", type: "secondTry", playerId: asPlayerId("p1") };
    s = allesOderBananePlugin.reduce(s, j, ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, antwort("p1", 1, t + 1_000), ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, antwort("p2", 1, t), ctx) as AllesOderBananeState;
    // p3 antwortet NICHT (verbunden) ⇒ Einsatz weg.
    clock.advance(AOB_FRAGE_MS + 1);
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    expect(allesOderBananePlugin.scores(s)).toEqual({ p1: 150, p2: 300, p3: -300 });
    expect(allesOderBananePlugin.outcomes!(s)[asPlayerId("p1")].zweitversuch).toBe(true);
  });

  it("Gratis-Einsatz (Konto < 100): falsch kostet NICHTS, richtig zahlt +100", () => {
    const { clock, ctx, state } = setup({ arm: 50, reich: 2_000 });
    let s = allesOderBananePlugin.reduce(
      state,
      einsatz("arm", 800, 1_000),
      ctx,
    ) as AllesOderBananeState;
    expect(s.einsaetze.arm).toMatchObject({ betrag: 100, gratis: true }); // Kredit der Affenbank
    s = allesOderBananePlugin.reduce(
      s,
      einsatz("reich", 1_000, 1_000),
      ctx,
    ) as AllesOderBananeState;
    expect(s.einsaetze.reich).toMatchObject({ betrag: 1_000, gratis: false }); // 50 % von 2.000
    s = bisFrage(s, ctx, clock);
    const t = clock.now() + 1_000;
    s = allesOderBananePlugin.reduce(s, antwort("arm", 0, t), ctx) as AllesOderBananeState; // falsch
    s = allesOderBananePlugin.reduce(s, antwort("reich", 1, t), ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    expect(allesOderBananePlugin.scores(s)).toEqual({ arm: 0, reich: 1_000 });
    // Gegenprobe: „arm“ richtig ⇒ +100.
    const b = setup({ arm: 50, reich: 2_000 });
    let s2 = allesOderBananePlugin.reduce(
      b.state,
      einsatz("arm", 800, 1_000),
      b.ctx,
    ) as AllesOderBananeState;
    s2 = allesOderBananePlugin.reduce(
      s2,
      einsatz("reich", 100, 1_000),
      b.ctx,
    ) as AllesOderBananeState;
    s2 = bisFrage(s2, b.ctx, b.clock);
    s2 = allesOderBananePlugin.reduce(
      s2,
      antwort("arm", 1, b.clock.now() + 500),
      b.ctx,
    ) as AllesOderBananeState;
    s2 = allesOderBananePlugin.reduce(
      s2,
      antwort("reich", 0, b.clock.now() + 500),
      b.ctx,
    ) as AllesOderBananeState;
    s2 = allesOderBananePlugin.tick(s2, b.ctx) as AllesOderBananeState;
    expect(allesOderBananePlugin.scores(s2)[asPlayerId("arm")]).toBe(100);
  });

  it("Einsatz-Klemmen: 50er-Raster, min 100, max 1.000, Kappe 50 % des Kontostands", () => {
    expect(aobKlemmeEinsatz(260, 10_000)).toBe(250); // Raster
    expect(aobKlemmeEinsatz(40, 10_000)).toBe(100); // Minimum
    expect(aobKlemmeEinsatz(5_000, 10_000)).toBe(1_000); // Deckel
    expect(aobKlemmeEinsatz(1_000, 700)).toBe(350); // 50-%-Kappe
    expect(aobEinsatzMax(150)).toBe(100); // Kappe unter Minimum ⇒ Minimum gilt
    expect(aobEinsatzMax(90)).toBe(100); // Gratis-Fall
  });
});

describe("alles-oder-banane: Phasen-Maschine + Einsatz-Regeln", () => {
  it("setzen → reveal → frage mit den Design-Zeiten (12 s / 6 s / 20 s)", () => {
    const { clock, ctx, state } = setup();
    expect(state.phase).toBe("setzen");
    expect(state.setzenEndetAt).toBe(AOB_SETZEN_MS);
    clock.advance(AOB_SETZEN_MS + 1);
    let s = allesOderBananePlugin.tick(state, ctx) as AllesOderBananeState;
    expect(s.phase).toBe("reveal");
    clock.advance(AOB_REVEAL_MS + 1);
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    expect(s.phase).toBe("frage");
    expect(s.frageEndetAt! - s.frageStartetAt!).toBe(AOB_FRAGE_MS);
  });

  it("alle eingeloggt ⇒ Setz-Fenster endet früher; Einsatz rastet ein (idempotent)", () => {
    const { ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3"]) {
      s = allesOderBananePlugin.reduce(s, einsatz(p, 200, 2_000), ctx) as AllesOderBananeState;
    }
    const nochmal = allesOderBananePlugin.reduce(s, einsatz("p1", 900, 3_000), ctx);
    expect(nochmal).toBe(s); // eingerastet — der erste Wert zählt
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState; // t=0: alle drin
    expect(s.phase).toBe("reveal");
  });

  it("kein Einsatz eingeloggt = Minimum 100 automatisch (nur für Verbundene)", () => {
    const { clock, ctx, state } = setup();
    let s = allesOderBananePlugin.reduce(
      state,
      einsatz("p1", 400, 1_000),
      ctx,
    ) as AllesOderBananeState;
    s = allesOderBananePlugin.onDisconnect(s, asPlayerId("p3"), ctx) as AllesOderBananeState;
    clock.advance(AOB_SETZEN_MS + 1);
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    expect(s.einsaetze.p2).toMatchObject({ betrag: 100, auto: true });
    expect(s.einsaetze.p3).toBeUndefined(); // offline ⇒ keine Zwangs-Wette
    // Ohne Einsatz keine Antwort-Wertung:
    clock.advance(AOB_REVEAL_MS + 1);
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    const t = clock.now() + 100;
    expect(allesOderBananePlugin.reduce(s, antwort("p3", 1, t), ctx)).toBe(s);
  });

  it("Disconnect nach Einsatz: Erstattung (0) — Reconnect während der Frage hebt sie auf", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3"]) {
      s = allesOderBananePlugin.reduce(s, einsatz(p, 300, 1_000), ctx) as AllesOderBananeState;
    }
    s = allesOderBananePlugin.onDisconnect(s, asPlayerId("p2"), ctx) as AllesOderBananeState;
    expect(s.erstattet.p2).toBe(true);
    s = bisFrage(s, ctx, clock);
    const t = clock.now() + 1_000;
    s = allesOderBananePlugin.reduce(s, antwort("p1", 1, t), ctx) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(s, antwort("p3", 0, t), ctx) as AllesOderBananeState;
    clock.advance(AOB_FRAGE_MS + 1);
    const offlineEnde = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    expect(allesOderBananePlugin.scores(offlineEnde)).toEqual({ p1: 300, p2: 0, p3: -300 });
    // Variante: p2 kommt zurück und antwortet noch ⇒ normale Wertung.
    let zurueck = allesOderBananePlugin.onReconnect(
      s,
      asPlayerId("p2"),
      ctx,
    ) as AllesOderBananeState;
    expect(zurueck.erstattet.p2).toBeUndefined();
    zurueck = allesOderBananePlugin.reduce(
      zurueck,
      antwort("p2", 1, clock.now() - 2_000),
      ctx,
    ) as AllesOderBananeState;
    zurueck = { ...zurueck, finished: true };
    expect(allesOderBananePlugin.scores(zurueck)[asPlayerId("p2")]).toBe(300);
  });

  it("GM-Skip (force.finish): offene Einsätze werden NICHT bestraft", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3"]) {
      s = allesOderBananePlugin.reduce(s, einsatz(p, 400, 1_000), ctx) as AllesOderBananeState;
    }
    s = bisFrage(s, ctx, clock);
    s = allesOderBananePlugin.reduce(
      s,
      antwort("p1", 0, clock.now() + 500),
      ctx,
    ) as AllesOderBananeState;
    s = allesOderBananePlugin.reduce(
      s,
      { kind: "gm", type: "force.finish" },
      ctx,
    ) as AllesOderBananeState;
    expect(allesOderBananePlugin.isFinished(s)).toBe(true);
    // p1 hatte geantwortet (falsch ⇒ −400), p2/p3 werden erstattet (0).
    expect(allesOderBananePlugin.scores(s)).toEqual({ p1: -400, p2: 0, p3: 0 });
  });

  it("Joker-Gating: 50:50 wirkt NUR im Frage-Fenster (nach dem Reveal)", () => {
    const { clock, ctx, state } = setup();
    const j: JokerAction = { kind: "joker", type: "fiftyFifty", playerId: asPlayerId("p1") };
    expect(allesOderBananePlugin.reduce(state, j, ctx)).toBe(state); // setzen: No-op
    let s = state;
    for (const p of ["p1", "p2", "p3"]) {
      s = allesOderBananePlugin.reduce(s, einsatz(p, 200, 1_000), ctx) as AllesOderBananeState;
    }
    s = bisFrage(s, ctx, clock);
    s = allesOderBananePlugin.reduce(s, j, ctx) as AllesOderBananeState;
    expect(s.gesperrt.p1).toHaveLength(2);
    expect(s.gesperrt.p1).not.toContain(frage.answer);
  });
});

describe("alles-oder-banane: Leak-Wachen + Determinismus", () => {
  it("SETZEN: nur Teaser (Kategorie + Schwierigkeit) — kein Fragetext, keine fremden Einsätze", () => {
    const { ctx, state } = setup();
    const s = allesOderBananePlugin.reduce(
      state,
      einsatz("p1", 700, 1_000),
      ctx,
    ) as AllesOderBananeState;
    const screen = allesOderBananePlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.kategorie).toBe("hauptstaedte");
    expect(screen.schwierigkeit).toBe("hard");
    expect(screen.text).toBeNull();
    expect(screen.einsaetze).toBeNull();
    expect(JSON.stringify(screen)).not.toContain(frage.text);
    const p2 = allesOderBananePlugin.viewFor(s, "player", asPlayerId("p2")) as Record<
      string,
      unknown
    >;
    expect(p2.einsaetze).toBeNull(); // fremde Einsätze bleiben geheim …
    expect(JSON.stringify(p2)).not.toContain('"betrag"'); // … auch kein Betrag im JSON
    expect(p2.eingeloggt as string[]).toContain("p1"); // aber „wer ist drin“ ist public
    const p1 = allesOderBananePlugin.viewFor(s, "player", asPlayerId("p1")) as {
      yourEinsatz: { betrag: number };
    };
    expect(p1.yourEinsatz.betrag).toBe(500); // eigener (geklemmter) Einsatz sichtbar
  });

  it("REVEAL zeigt ALLE Einsätze, aber die Frage bleibt zu; GM sieht immer alles", () => {
    const { clock, ctx, state } = setup();
    let s = state;
    for (const p of ["p1", "p2", "p3"]) {
      s = allesOderBananePlugin.reduce(s, einsatz(p, 300, 1_000), ctx) as AllesOderBananeState;
    }
    clock.advance(AOB_SETZEN_MS + 1);
    s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
    expect(s.phase).toBe("reveal");
    const screen = allesOderBananePlugin.viewFor(s, "screen") as {
      einsaetze: Record<string, { betrag: number }>;
      text: string | null;
    };
    expect(screen.einsaetze.p2.betrag).toBe(300);
    expect(screen.text).toBeNull(); // Frage kommt erst NACH dem Reveal
    const gm = allesOderBananePlugin.viewFor(s, "gm") as { text: string; correctIndex: number };
    expect(gm.text).toBe(frage.text);
    expect(gm.correctIndex).toBe(1);
    // Player-View enthält correctIndex erst nach finished:
    const player = JSON.stringify(allesOderBananePlugin.viewFor(s, "player", asPlayerId("p1")));
    expect(player).not.toContain("correctIndex");
  });

  it("timerFaktor 0,5 (Halbe Miete) halbiert NUR das Frage-Fenster", () => {
    const { clock, ctx, state } = setup({ p1: 1_000, p2: 1_000 }, 1, { timerFaktor: 0.5 });
    expect(state.setzenEndetAt).toBe(AOB_SETZEN_MS); // Setzen bleibt 12 s
    const s = bisFrage(state, ctx, clock);
    expect(s.frageEndetAt! - s.frageStartetAt!).toBe(AOB_FRAGE_MS / 2);
  });

  it("Determinismus + JSON-Serialisierbarkeit: identisches Skript ⇒ identischer End-State", () => {
    const lauf = (): string => {
      const { clock, ctx, state } = setup({ p1: 800, p2: 600 }, 21);
      let s = allesOderBananePlugin.reduce(
        state,
        einsatz("p1", 400, 900),
        ctx,
      ) as AllesOderBananeState;
      s = allesOderBananePlugin.reduce(s, einsatz("p2", 250, 1_100), ctx) as AllesOderBananeState;
      s = bisFrage(s, ctx, clock);
      s = allesOderBananePlugin.reduce(
        s,
        antwort("p1", 1, clock.now() + 700),
        ctx,
      ) as AllesOderBananeState;
      s = allesOderBananePlugin.reduce(
        s,
        antwort("p2", 2, clock.now() + 900),
        ctx,
      ) as AllesOderBananeState;
      s = allesOderBananePlugin.tick(s, ctx) as AllesOderBananeState;
      return JSON.stringify([s, allesOderBananePlugin.scores(s)]);
    };
    expect(lauf()).toBe(lauf());
    const kopie = JSON.parse(lauf()) as unknown[];
    expect(kopie).toHaveLength(2);
  });
});
