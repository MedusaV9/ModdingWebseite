// 7-Buchstaben-Telegramm: Begriffs-Pool-Wächter, Zeichen-Validierung
// (nur A–Z/0–9, max N), Budget-Mathe ÜBER RUNDEN (getippt = verbraucht,
// Übertrag via Slice, Clamp), Paar-Bildung + Rollen-Rotation, Koop-Wertung
// (beide je 250), View-Leaks (Begriff NIE beim Ratenden!), Beschreiber-
// Disconnect ⇒ neutraler Skip, Timeouts, GM-Eingriffe.
import { describe, expect, it } from "vitest";
import { asPlayerId } from "../../shared/ids";
import {
  BT_AUFDECKUNG_MS,
  BT_BEGRIFFS_POOL,
  BT_ERFOLG_MM,
  BT_HINWEIS_MAX,
  BT_MATCH_BUDGET,
  BT_RATEN_MS,
  BT_TIPPEN_MS,
  BT_VORSTELLUNG_MS,
  btBaueOptionen,
  btBeschreiberIndex,
  btBildePaare,
  btHinweisAusTitel,
  btTelegrammZeichen,
  btValidiereZeichen,
} from "../../shared/minigames/buchstaben-telegramm.meta";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import {
  buchstabenTelegrammPlugin,
  type BuchstabenTelegrammSlice,
  type BuchstabenTelegrammState,
} from "./buchstaben-telegramm/index";

function frage(id: string): Question {
  return {
    id,
    kind: "choice4",
    category: "show",
    difficulty: "medium",
    text: "Telegramm-Slot",
    options: ["A", "B", "C", "D"],
    answer: 0,
    erklaerung: "Der Begriff kommt aus Pool/Song-Pack, nicht aus der Frage.",
  };
}

type BtAction = PlayerAction<
  | { type: "buchstabe"; zeichen: string }
  | { type: "loeschen" }
  | { type: "senden" }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 }
>;

function aktion(playerId: string, action: BtAction["action"], atServerTime: number): BtAction {
  return { kind: "player", playerId: asPlayerId(playerId), action, atServerTime };
}

function setup(
  opts: {
    spieler?: string[];
    beats?: number;
    seed?: number;
    slice?: Partial<BuchstabenTelegrammSlice>;
  } = {},
) {
  const namen = opts.spieler ?? ["p1", "p2", "p3", "p4"];
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const content: BuchstabenTelegrammSlice = {
    questions: Array.from({ length: opts.beats ?? 4 }, (_, i) => frage(`q${i + 1}`)),
    ...opts.slice,
  };
  const state = buchstabenTelegrammPlugin.init(
    namen.map(asPlayerId),
    content,
    ctx,
  ) as BuchstabenTelegrammState;
  return { clock, ctx, state };
}

/** Bis zur Tippen-Phase des aktuellen Beats vorspulen. */
function bisTippen(s: BuchstabenTelegrammState, clock: { advance(ms: number): void }, ctx: never) {
  clock.advance(BT_VORSTELLUNG_MS);
  return buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
}

describe("buchstaben-telegramm: Begriffs-Pool + Zeichen-Helfer", () => {
  it("der eingebaute Pool hat 60+ Begriffe — alle eindeutig und telegrammierbar", () => {
    expect(BT_BEGRIFFS_POOL.length).toBeGreaterThanOrEqual(60);
    const texte = BT_BEGRIFFS_POOL.map((b) => b.text);
    expect(new Set(texte).size).toBe(texte.length);
    for (const b of BT_BEGRIFFS_POOL) {
      expect(btTelegrammZeichen(b.text).length).toBeGreaterThanOrEqual(3);
    }
    // Alle 3 Arten vertreten (Filme/Sprichwörter/Promis).
    expect(new Set(BT_BEGRIFFS_POOL.map((b) => b.art))).toEqual(
      new Set(["film", "sprichwort", "promi"]),
    );
  });

  it("btValidiereZeichen: nur A–Z/0–9 (Kleinbuchstaben werden groß), sonst null", () => {
    expect(btValidiereZeichen("a")).toBe("A");
    expect(btValidiereZeichen("Z")).toBe("Z");
    expect(btValidiereZeichen("5")).toBe("5");
    for (const kaputt of ["!", " ", "ä", "ß", "", "AB", "-", "🙈"]) {
      expect(btValidiereZeichen(kaputt)).toBeNull();
    }
  });

  it("btTelegrammZeichen + btHinweisAusTitel: Umlaute transliteriert, Rest fällt weg", () => {
    expect(btTelegrammZeichen("Für Élise, äh — 99!")).toBe("FUERLISEAEH99");
    expect(btTelegrammZeichen("Größenwahn")).toBe("GROESSENWAHN");
    // Der Beschreiber-Bot-Hinweis: erste N sinnvolle Zeichen des Titels.
    expect(btHinweisAusTitel("99 Luftballons", 8)).toBe("99LUFTBA");
    expect(btHinweisAusTitel("Atemlos durch die Nacht", 4)).toBe("ATEM");
    expect(btHinweisAusTitel("Ab", 8)).toBe("AB");
  });

  it("btBaueOptionen: 4 eindeutige Optionen derselben Art, die richtige am answer-Index", () => {
    const korrekt = BT_BEGRIFFS_POOL[0]; // ein Film
    for (const seed of [1, 7, 42]) {
      const { optionen, answer } = btBaueOptionen(BT_BEGRIFFS_POOL, korrekt, createRng(seed));
      expect(optionen).toHaveLength(4);
      expect(new Set(optionen).size).toBe(4);
      expect(optionen[answer]).toBe(korrekt.text);
      // Köder derselben Art (der Pool ist groß genug — echtes Raten).
      const arten = optionen.map((o) => BT_BEGRIFFS_POOL.find((b) => b.text === o)?.art);
      expect(arten.every((a) => a === korrekt.art)).toBe(true);
    }
  });
});

describe("buchstaben-telegramm: Paar-Bildung + Rollen-Rotation", () => {
  it("ohne Teams: gerade Zahl ⇒ nur Zweier, ungerade ⇒ genau EIN Dreier", () => {
    const vier = btBildePaare(["a", "b", "c", "d"], null, createRng(1));
    expect(vier).toHaveLength(2);
    expect(vier.every((p) => p.mitglieder.length === 2)).toBe(true);
    expect(new Set(vier.flatMap((p) => p.mitglieder)).size).toBe(4);

    const fuenf = btBildePaare(["a", "b", "c", "d", "e"], null, createRng(1));
    expect(fuenf).toHaveLength(2);
    expect(fuenf.map((p) => p.mitglieder.length).sort()).toEqual([2, 3]);
    expect(new Set(fuenf.flatMap((p) => p.mitglieder)).size).toBe(5);

    expect(btBildePaare(["a", "b"], null, createRng(1))).toHaveLength(1);
    expect(btBildePaare(["a", "b", "c"], null, createRng(1))[0].mitglieder).toHaveLength(3);
  });

  it("mit Teams: Teampartner bleiben zusammen, Reste wandern in den Zufalls-Topf", () => {
    const teamVon = { a: "t1", b: "t1", c: "t2", d: "t2", e: "t2" };
    const paare = btBildePaare(["a", "b", "c", "d", "e"], teamVon, createRng(3));
    const alsSet = paare.map((p) => new Set(p.mitglieder));
    expect(alsSet.some((s) => s.has("a") && s.has("b"))).toBe(true);
    expect(alsSet.some((s) => s.has("c") && s.has("d"))).toBe(true);
    // e (Team-Rest, ungerade) stößt als Dreier dazu.
    expect(paare.flatMap((p) => p.mitglieder)).toContain("e");
  });

  it("Beschreiber rotiert: Paare wechseln pro Beat, die Rolle beim Wieder-Auftritt", () => {
    // Formel-Wächter: 2 Paare, Paar 0 tritt in Beat 0 und 2 auf.
    expect(btBeschreiberIndex(0, 2, 2)).toBe(0);
    expect(btBeschreiberIndex(2, 2, 2)).toBe(1); // Rolle gewechselt
    expect(btBeschreiberIndex(4, 2, 2)).toBe(0);
    // End-zu-end: 4 Spieler, 4 Beats ⇒ jedes Paar 2×, Beschreiber wechselt.
    const { state } = setup();
    expect(state.paare).toHaveLength(2);
    expect(state.beats).toHaveLength(4);
    expect(state.beats[0].paarIndex).toBe(0);
    expect(state.beats[1].paarIndex).toBe(1);
    expect(state.beats[2].paarIndex).toBe(0);
    expect(state.beats[2].beschreiber).not.toBe(state.beats[0].beschreiber);
    expect(state.beats[3].beschreiber).not.toBe(state.beats[1].beschreiber);
    // Der Beschreiber rät nie mit sich selbst: ratende = Paar ohne ihn.
    for (const b of state.beats) {
      expect(b.ratende).not.toContain(b.beschreiber);
      expect(b.ratende.length).toBeGreaterThanOrEqual(1);
    }
  });
});

describe("buchstaben-telegramm: Budget-Mathe (getippt = verbraucht)", () => {
  it("jedes Zeichen kostet sofort 1 — auch OHNE Senden; max N pro Hinweis", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    expect(s.phase).toBe("tippen");
    expect(s.maxZeichen).toBe(BT_HINWEIS_MAX);
    const b = s.beats[0].beschreiber;
    const t = ctx.clock.now();
    for (let i = 0; i < 12; i++) {
      s = buchstabenTelegrammPlugin.reduce(
        s,
        aktion(b, { type: "buchstabe", zeichen: "X" }, t + i),
        ctx,
      ) as BuchstabenTelegrammState;
    }
    // Kappe bei 8 — nur 8 Zeichen verbraucht, der Rest wurde verworfen.
    expect(s.hinweis).toBe("XXXXXXXX");
    expect(s.budget[b]).toBe(BT_MATCH_BUDGET - BT_HINWEIS_MAX);
  });

  it("Runden-Übertrag: Rest-Budget aus dem Slice zählt weiter und wird geclampt", () => {
    const { state } = setup({
      spieler: ["p1", "p2"],
      beats: 1,
      slice: { buchstabenBudget: { p1: 5, p2: 999 } },
    });
    expect(state.budget.p1).toBe(5);
    expect(state.budget.p2).toBe(BT_MATCH_BUDGET); // Clamp nach oben
    // maxZeichen des Beats = min(8, Rest des Beschreibers).
    const beschreiber = state.beats[0].beschreiber;
    expect(state.maxZeichen).toBe(Math.min(BT_HINWEIS_MAX, state.budget[beschreiber]));
  });

  it("Budget 0 ⇒ Raten OHNE Hinweis (Tippen-Phase entfällt komplett)", () => {
    const { clock, ctx, state } = setup({
      spieler: ["p1", "p2"],
      beats: 1,
      slice: { buchstabenBudget: { p1: 0, p2: 0 } },
    });
    expect(state.maxZeichen).toBe(0);
    clock.advance(BT_VORSTELLUNG_MS);
    const s = buchstabenTelegrammPlugin.tick(state, ctx) as BuchstabenTelegrammState;
    expect(s.phase).toBe("raten");
    expect(s.hinweis).toBe("");
  });

  it("wer früh verballert, hat später weniger: Budget sinkt über die Beats", () => {
    // 2 Spieler, 3 Beats: p_A beschreibt Beat 1+3 — Beat 1 kostet 8, Beat 3 deckelt bei Rest.
    const { clock, ctx, state } = setup({
      spieler: ["p1", "p2"],
      beats: 3,
      slice: { buchstabenBudget: { p1: 11, p2: 11 } },
    });
    let s = bisTippen(state, clock, ctx as never);
    const erster = s.beats[0].beschreiber;
    const t = ctx.clock.now();
    for (let i = 0; i < 8; i++) {
      s = buchstabenTelegrammPlugin.reduce(
        s,
        aktion(erster, { type: "buchstabe", zeichen: "A" }, t + i),
        ctx,
      ) as BuchstabenTelegrammState;
    }
    expect(s.budget[erster]).toBe(3);
    // Beat 1 zu Ende (senden + raten-Timeout + aufdeckung), Beat 2 überspringen.
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(erster, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    clock.advance(BT_RATEN_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState; // aufdeckung
    clock.advance(BT_AUFDECKUNG_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState; // Beat 2 (vorstellung)
    clock.advance(BT_VORSTELLUNG_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState; // tippen (p2)
    clock.advance(BT_TIPPEN_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState; // raten (auto-senden)
    clock.advance(BT_RATEN_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState; // aufdeckung
    clock.advance(BT_AUFDECKUNG_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState; // Beat 3 (vorstellung)
    // Beat 3: derselbe Beschreiber wie Beat 1 — jetzt deckelt der Rest (3 < 8).
    expect(s.beats[2].beschreiber).toBe(erster);
    expect(s.maxZeichen).toBe(3);
  });
});

describe("buchstaben-telegramm: ⌫-Korrektur (Eval 3 — Streifen-Korrektur)", () => {
  it("⌫ VOR dem Senden: letztes Zeichen weg + Budget-Rückgabe; leer = no-op", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const b = s.beats[0].beschreiber;
    const t = ctx.clock.now();
    for (const z of ["X", "Y", "Z"]) {
      s = buchstabenTelegrammPlugin.reduce(
        s,
        aktion(b, { type: "buchstabe", zeichen: z }, t),
        ctx,
      ) as BuchstabenTelegrammState;
    }
    expect(s.hinweis).toBe("XYZ");
    expect(s.budget[b]).toBe(BT_MATCH_BUDGET - 3);
    // Eine Korrektur: Zeichen kommt ZURÜCK (Vertipper sind keine Telegramm-Wörter).
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "loeschen" }, t + 1),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.hinweis).toBe("XY");
    expect(s.budget[b]).toBe(BT_MATCH_BUDGET - 2);
    // Alles wegkorrigieren ⇒ Budget wieder voll; ein WEITERES ⌫ ist no-op.
    for (let i = 0; i < 3; i++) {
      s = buchstabenTelegrammPlugin.reduce(
        s,
        aktion(b, { type: "loeschen" }, t + 2 + i),
        ctx,
      ) as BuchstabenTelegrammState;
    }
    expect(s.hinweis).toBe("");
    expect(s.budget[b]).toBe(BT_MATCH_BUDGET);
  });

  it("NACH dem Senden ist ⌫ wirkungslos — gesendet = endgültig verbraucht", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const b = s.beats[0].beschreiber;
    const t = ctx.clock.now();
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "buchstabe", zeichen: "Q" }, t),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "senden" }, t + 1),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.phase).toBe("raten");
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "loeschen" }, t + 2),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.hinweis).toBe("Q");
    expect(s.budget[b]).toBe(BT_MATCH_BUDGET - 1);
  });

  it("nur der Beschreiber darf korrigieren — Ratende ⌫en ins Leere", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const b = s.beats[0].beschreiber;
    const ratender = s.beats[0].ratende[0];
    const t = ctx.clock.now();
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "buchstabe", zeichen: "K" }, t),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(ratender, { type: "loeschen" }, t + 1),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.hinweis).toBe("K");
    expect(s.budget[b]).toBe(BT_MATCH_BUDGET - 1);
  });
});

describe("buchstaben-telegramm: Eingabe-Validierung im Spiel", () => {
  it("verwirft Sonderzeichen/Umlaute OHNE Budget-Abzug; Fremde tippen gar nicht", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const beschreiber = s.beats[0].beschreiber;
    const ratender = s.beats[0].ratende[0];
    const t = ctx.clock.now();
    for (const kaputt of ["!", "ä", " ", "ß"]) {
      s = buchstabenTelegrammPlugin.reduce(
        s,
        aktion(beschreiber, { type: "buchstabe", zeichen: kaputt }, t),
        ctx,
      ) as BuchstabenTelegrammState;
    }
    expect(s.hinweis).toBe("");
    expect(s.budget[beschreiber]).toBe(BT_MATCH_BUDGET); // nichts verbraucht
    // Der Ratende darf NICHT ins Telegramm tippen.
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(ratender, { type: "buchstabe", zeichen: "X" }, t),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.hinweis).toBe("");
    // Kleinbuchstaben werden zu Großbuchstaben.
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beschreiber, { type: "buchstabe", zeichen: "n" }, t),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.hinweis).toBe("N");
  });

  it("senden startet das Raten früher; Tippen-Timeout = Auto-Senden", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const b = s.beats[0].beschreiber;
    const t = ctx.clock.now();
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "buchstabe", zeichen: "A" }, t + 100),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "senden" }, t + 200),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.phase).toBe("raten");
    expect(s.hinweisGesendet).toBe(true);
    // Nach dem Senden ist das Telegramm eingefroren.
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(b, { type: "buchstabe", zeichen: "B" }, t + 300),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.hinweis).toBe("A");

    // Timeout-Variante: ohne senden schickt die Uhr das Telegramm ab.
    const zweite = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s2 = bisTippen(zweite.state, zweite.clock, zweite.ctx as never);
    zweite.clock.advance(BT_TIPPEN_MS);
    s2 = buchstabenTelegrammPlugin.tick(s2, zweite.ctx) as BuchstabenTelegrammState;
    expect(s2.phase).toBe("raten");
  });
});

describe("buchstaben-telegramm: Koop-Wertung (beide je 250)", () => {
  it("Erfolg zahlt Ratendem UND Beschreiber je 250 MM; Fehlschlag 0", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(
        beat.ratende[0],
        { type: "answer", choice: beat.answer as 0 | 1 | 2 | 3 },
        ctx.clock.now() + 500,
      ),
      ctx,
    ) as BuchstabenTelegrammState;
    clock.advance(1_000);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    expect(s.phase).toBe("aufdeckung");
    expect(s.deltas[beat.ratende[0]]).toBe(BT_ERFOLG_MM);
    expect(s.deltas[beat.beschreiber]).toBe(BT_ERFOLG_MM);
    expect(s.historie[0].richtige).toEqual([beat.ratende[0]]);
  });

  it("falsche Antwort: 0 MM für beide; erste Antwort zählt; Publikum wird ignoriert", () => {
    const { clock, ctx, state } = setup({ seed: 11 }); // 4 Spieler ⇒ 2 Paare
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    const publikum = state.players.find(
      (p) => p !== beat.beschreiber && !beat.ratende.includes(p),
    )!;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    const falsch = ((beat.answer + 1) % 4) as 0 | 1 | 2 | 3;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.ratende[0], { type: "answer", choice: falsch }, ctx.clock.now() + 100),
      ctx,
    ) as BuchstabenTelegrammState;
    // Zweitversuch + Publikums-Stimme: beide verworfen.
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(
        beat.ratende[0],
        { type: "answer", choice: beat.answer as 0 | 1 | 2 | 3 },
        ctx.clock.now() + 200,
      ),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(
        publikum,
        { type: "answer", choice: beat.answer as 0 | 1 | 2 | 3 },
        ctx.clock.now() + 300,
      ),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.antworten[beat.ratende[0]].choice).toBe(falsch);
    expect(s.antworten[publikum]).toBeUndefined();
    clock.advance(BT_RATEN_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    expect(s.deltas[beat.ratende[0]]).toBeUndefined();
    expect(s.deltas[beat.beschreiber]).toBeUndefined();
    expect(s.historie[0].falsche).toEqual([beat.ratende[0]]);
  });

  it("Dreier: JEDER richtige Ratende kriegt 250, der Beschreiber genau 1×", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2", "p3"], beats: 1 });
    expect(state.paare[0].mitglieder).toHaveLength(3);
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    expect(beat.ratende).toHaveLength(2);
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    const t = ctx.clock.now();
    for (const r of beat.ratende) {
      s = buchstabenTelegrammPlugin.reduce(
        s,
        aktion(r, { type: "answer", choice: beat.answer as 0 | 1 | 2 | 3 }, t + 100),
        ctx,
      ) as BuchstabenTelegrammState;
    }
    clock.advance(500);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    for (const r of beat.ratende) expect(s.deltas[r]).toBe(BT_ERFOLG_MM);
    expect(s.deltas[beat.beschreiber]).toBe(BT_ERFOLG_MM);
    const summe = Object.values(buchstabenTelegrammPlugin.scores({ ...s, finished: true })).reduce(
      (a, b) => a + b,
      0,
    );
    expect(summe).toBe(3 * BT_ERFOLG_MM);
  });
});

describe("buchstaben-telegramm: View-Leaks (Begriff NIE beim Ratenden!)", () => {
  it("nur der Beschreiber sieht den Begriff — Ratende/Screen/Publikum nie vor der Aufdeckung", () => {
    const { clock, ctx, state } = setup();
    const s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    const begriff = beat.begriff.text;

    const beschreiberView = buchstabenTelegrammPlugin.viewFor(
      s,
      "player",
      asPlayerId(beat.beschreiber),
    ) as {
      begriffText: string | null;
      duBistBeschreiber: boolean;
    };
    expect(beschreiberView.duBistBeschreiber).toBe(true);
    expect(beschreiberView.begriffText).toBe(begriff);

    for (const rolle of beat.ratende) {
      const json = JSON.stringify(
        buchstabenTelegrammPlugin.viewFor(s, "player", asPlayerId(rolle)),
      );
      expect(json).not.toContain(begriff);
      expect(json).not.toContain('"answer":');
      expect(json).not.toContain("correctIndex");
    }
    const screenJson = JSON.stringify(buchstabenTelegrammPlugin.viewFor(s, "screen"));
    expect(screenJson).not.toContain(begriff);
    expect(screenJson).not.toContain('"answer":');

    const gm = buchstabenTelegrammPlugin.viewFor(s, "gm") as {
      begriffText: string;
      correctIndex: number;
    };
    expect(gm.begriffText).toBe(begriff);
    expect(gm.correctIndex).toBe(beat.answer);
  });

  it("im Rate-Fenster kriegen NUR die Paar-Ratenden Optionen aufs Handy", () => {
    const { clock, ctx, state } = setup();
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    const publikum = state.players.find(
      (p) => p !== beat.beschreiber && !beat.ratende.includes(p),
    )!;
    const rater = buchstabenTelegrammPlugin.viewFor(s, "player", asPlayerId(beat.ratende[0])) as {
      optionen: string[] | null;
    };
    expect(rater.optionen).toHaveLength(4);
    const zuschauer = buchstabenTelegrammPlugin.viewFor(s, "player", asPlayerId(publikum)) as {
      optionen: string[] | null;
    };
    expect(zuschauer.optionen).toBeNull();
    const beschreiber = buchstabenTelegrammPlugin.viewFor(
      s,
      "player",
      asPlayerId(beat.beschreiber),
    ) as {
      optionen: string[] | null;
    };
    expect(beschreiber.optionen).toBeNull();
  });
});

describe("buchstaben-telegramm: Edge-Cases + GM + Vertrag", () => {
  it("Beschreiber-Disconnect ⇒ NEUTRALER Skip: 0 MM, kein Auto-Hinweis aus der Antwort", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    s = buchstabenTelegrammPlugin.onDisconnect(
      s,
      asPlayerId(beat.beschreiber),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.phase).toBe("aufdeckung");
    expect(s.historie[0].uebersprungen).toBe(true);
    expect(s.historie[0].hinweis).toBe(""); // NIE Antwort-Buchstaben leaken
    expect(s.deltas).toEqual({});
    clock.advance(BT_AUFDECKUNG_MS);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    expect(buchstabenTelegrammPlugin.isFinished(s)).toBe(true);
  });

  it("Disconnect NACH dem Senden lässt den Beat normal weiterlaufen", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.onDisconnect(
      s,
      asPlayerId(beat.beschreiber),
      ctx,
    ) as BuchstabenTelegrammState;
    expect(s.phase).toBe("raten"); // kein Skip — das Telegramm ist ja raus
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(
        beat.ratende[0],
        { type: "answer", choice: beat.answer as 0 | 1 | 2 | 3 },
        ctx.clock.now() + 100,
      ),
      ctx,
    ) as BuchstabenTelegrammState;
    clock.advance(500);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    // Der offline Beschreiber kriegt seine Prämie trotzdem (Koop-Fairness).
    expect(s.deltas[beat.beschreiber]).toBe(BT_ERFOLG_MM);
  });

  it("alle Ratenden offline ⇒ Beat wird sofort abgerechnet (keine Antwort = 0)", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.onDisconnect(
      s,
      asPlayerId(beat.ratende[0]),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    expect(s.phase).toBe("aufdeckung");
    expect(s.deltas).toEqual({});
  });

  it("GM: force.finish beendet sofort, timer.extend gibt der Phase Luft", () => {
    const { ctx, state } = setup();
    const zu = buchstabenTelegrammPlugin.reduce(state, { kind: "gm", type: "force.finish" }, ctx);
    expect(buchstabenTelegrammPlugin.isFinished(zu)).toBe(true);
    const laenger = buchstabenTelegrammPlugin.reduce(
      state,
      { kind: "gm", type: "timer.extend", ms: 9_000 },
      ctx,
    ) as BuchstabenTelegrammState;
    expect(laenger.phaseEndetAt).toBe(BT_VORSTELLUNG_MS + 9_000);
  });

  it("State bleibt JSON-serialisierbar; outcomes folgen der Mehrheits-Regel", () => {
    const { clock, ctx, state } = setup({ spieler: ["p1", "p2"], beats: 1 });
    let s = bisTippen(state, clock, ctx as never);
    const beat = s.beats[0];
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(beat.beschreiber, { type: "senden" }, ctx.clock.now()),
      ctx,
    ) as BuchstabenTelegrammState;
    s = buchstabenTelegrammPlugin.reduce(
      s,
      aktion(
        beat.ratende[0],
        { type: "answer", choice: beat.answer as 0 | 1 | 2 | 3 },
        ctx.clock.now() + 100,
      ),
      ctx,
    ) as BuchstabenTelegrammState;
    clock.advance(500);
    s = buchstabenTelegrammPlugin.tick(s, ctx) as BuchstabenTelegrammState;
    const fertig = { ...s, finished: true };
    const outcomes = buchstabenTelegrammPlugin.outcomes!(fertig);
    expect(outcomes[asPlayerId(beat.ratende[0])].correct).toBe(true);
    expect(outcomes[asPlayerId(beat.beschreiber)].correct).toBe(true);
    const kopie = JSON.parse(JSON.stringify(fertig)) as BuchstabenTelegrammState;
    expect(buchstabenTelegrammPlugin.scores(kopie)).toEqual(
      buchstabenTelegrammPlugin.scores(fertig),
    );
  });
});
