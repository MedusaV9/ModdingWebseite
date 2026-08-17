// Wer singt's?: Pool-Integritäts-Wächter (60+ eindeutige, faktensichere
// Titel-Interpret-Paare), artgleiche Distraktoren (Ära/Genre-Staffel),
// Song-Pack-Zusatzfragen (Validierung + Dedup), Beat-Wahl (keine Dubletten,
// Bekanntheits-Staffelung, Pack-Deckel), Speed-Bonus-Wertung, Antwort-Locks,
// Disconnect-Verhalten, GM-Kommandos, Leak-Wachen und Seed-Determinismus.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import { speedBonus } from "../../shared/money";
import {
  WS_AERA_JAHRE,
  WS_FAKTEN_POOL,
  WS_WERT,
  wsBaueOptionen,
  wsFaktAusSong,
  wsFaktenAusSongs,
  wsPoolFehler,
  wsWaehleBeats,
  type WerSingtsAction,
  type WsFakt,
} from "../../shared/minigames/wer-singts.meta";
import { SPAETANTWORT_GNADE_MS } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { Ctx, GmAction, PlayerAction } from "./_api/plugin";
import { werSingtsPlugin, type WerSingtsSlice, type WerSingtsState } from "./wer-singts/index";

function beatFragen(n: number): Question[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `q_ws_${i + 1}`,
    kind: "choice4" as const,
    category: "musik",
    difficulty: "medium" as const,
    text: `Beat-Zähler ${i + 1}`,
    options: ["A", "B", "C", "D"],
    answer: 0,
    erklaerung: "",
  }));
}

function setup(opts: { spieler?: string[]; seed?: number; beats?: number; songs?: unknown } = {}) {
  const clock = createTestClock(0);
  const spieler = (opts.spieler ?? ["p1", "p2", "p3"]).map(asPlayerId);
  const ctx: Ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const content: WerSingtsSlice = {
    questions: beatFragen(opts.beats ?? 3),
    ...(opts.songs !== undefined ? { songs: opts.songs as WerSingtsSlice["songs"] } : {}),
  };
  const state = werSingtsPlugin.init(spieler, content as ContentSlice, ctx) as WerSingtsState;
  return { clock, ctx, state, spieler };
}

function aktion(p: string, a: WerSingtsAction, at: number): PlayerAction<WerSingtsAction> {
  return { kind: "player", playerId: asPlayerId(p), action: a, atServerTime: at };
}

function reduce(s: WerSingtsState, a: PlayerAction<WerSingtsAction> | GmAction, ctx: Ctx) {
  return werSingtsPlugin.reduce(s, a, ctx) as WerSingtsState;
}

function tick(s: WerSingtsState, ctx: Ctx) {
  return werSingtsPlugin.tick(s, ctx) as WerSingtsState;
}

/** Uhr bis nach dem Phasen-Ende, dann tick (Phasen-Übergang erzwingen). */
function phaseVorbei(s: WerSingtsState, ctx: Ctx, clock: ReturnType<typeof createTestClock>) {
  clock.advance(Math.max(0, s.phaseEndetAt - clock.now()) + 1);
  return tick(s, ctx);
}

describe("wer-singts: Pool-Integritäts-Wächter", () => {
  it("der eingebaute Pool hat 60+ Einträge und besteht den Wächter fehlerfrei", () => {
    expect(WS_FAKTEN_POOL.length).toBeGreaterThanOrEqual(60);
    expect(wsPoolFehler(WS_FAKTEN_POOL)).toEqual([]);
  });

  it("alle Titel sind EINDEUTIG (nie zwei Interpreten für denselben Titel)", () => {
    const titel = WS_FAKTEN_POOL.map((f) => f.titel.trim().toLowerCase());
    expect(new Set(titel).size).toBe(WS_FAKTEN_POOL.length);
    // Deutsche UND internationale Klassiker quer durch die Jahrzehnte.
    expect(WS_FAKTEN_POOL.filter((f) => f.region === "de").length).toBeGreaterThanOrEqual(20);
    expect(WS_FAKTEN_POOL.filter((f) => f.region === "global").length).toBeGreaterThanOrEqual(20);
    const dekaden = new Set(
      WS_FAKTEN_POOL.map((f) => (f.jahr === null ? -1 : Math.floor(f.jahr / 10))),
    );
    expect(dekaden.size).toBeGreaterThanOrEqual(6); // 50er … 2010er
  });

  it("der Wächter meldet Dubletten, Mini-Pools und absurde Jahre", () => {
    const f = (titel: string, artist: string, jahr: number): WsFakt => ({
      titel,
      artist,
      jahr,
      genre: "pop",
      schwierigkeit: "easy",
      region: "global",
    });
    expect(wsPoolFehler([f("Hit", "A", 1980)]).join(" ")).toMatch(/Pool zu klein/);
    const dublette = [...WS_FAKTEN_POOL, f("hey jude", "Falscher Interpret", 1970)];
    expect(wsPoolFehler(dublette).join(" ")).toMatch(/Titel doppelt/);
    const absurd = [...WS_FAKTEN_POOL.slice(0, 59), f("Zeitreise", "A", 1830)];
    expect(wsPoolFehler(absurd).join(" ")).toMatch(/Jahr unplausibel/);
  });

  it("init wirft NICHT mit dem eingebauten Pool (der Wächter läuft scharf)", () => {
    expect(() => setup()).not.toThrow();
  });
});

describe("wer-singts: artgleiche Distraktoren (wsBaueOptionen)", () => {
  it("4 Optionen, alle verschieden, der richtige Interpret an rng-Position", () => {
    for (const [i, fakt] of WS_FAKTEN_POOL.entries()) {
      const { optionen, answer } = wsBaueOptionen(fakt, WS_FAKTEN_POOL, createRng(i));
      expect(optionen).toHaveLength(4);
      expect(new Set(optionen).size).toBe(4);
      expect(optionen[answer]).toBe(fakt.artist);
      expect(answer).toBeGreaterThanOrEqual(0);
      expect(answer).toBeLessThan(4);
    }
  });

  it("Distraktoren kommen bevorzugt aus DEMSELBEN Genre und DERSELBEN Ära", () => {
    // NDW 1983 („99 Luftballons“): der Pool hat ≥ 3 weitere NDW-Acts ±10 Jahre
    // ⇒ ALLE Distraktoren müssen aus Stufe 1 (Genre + Ära) kommen.
    const nena = WS_FAKTEN_POOL.find((f) => f.artist === "Nena") as WsFakt;
    const { optionen, answer } = wsBaueOptionen(nena, WS_FAKTEN_POOL, createRng(3));
    const distraktoren = optionen.filter((_, i) => i !== answer);
    for (const d of distraktoren) {
      const quelle = WS_FAKTEN_POOL.find((f) => f.artist === d) as WsFakt;
      expect(quelle.genre).toBe("ndw");
      expect(Math.abs((quelle.jahr ?? 0) - (nena.jahr ?? 0))).toBeLessThanOrEqual(WS_AERA_JAHRE);
    }
  });

  it("Not-Ausstieg: selbst mit Mini-Pool stehen IMMER 4 Optionen (nie crashen)", () => {
    const solo: WsFakt = {
      titel: "Solo",
      artist: "Einsamer Act",
      jahr: 2000,
      genre: "pop",
      schwierigkeit: "easy",
      region: "global",
    };
    const { optionen, answer } = wsBaueOptionen(solo, [solo], createRng(1));
    expect(optionen).toHaveLength(4);
    expect(optionen[answer]).toBe("Einsamer Act");
    expect(new Set(optionen).size).toBe(4);
  });
});

describe("wer-singts: Song-Pack-Zusatzfragen", () => {
  it("valide Einträge werden Fakten; kaputte und Dubletten fliegen still raus", () => {
    const fakten = wsFaktenAusSongs([
      { titel: "Party-Hit", artist: "Die Partyband", jahr: 2015 },
      { titel: "  ", artist: "Ohne Titel" }, // leerer Titel ⇒ raus
      { titel: "Ohne Artist", artist: "" }, // leerer Artist ⇒ raus
      { titel: "Hey Jude", artist: "Falscher Act", jahr: 1968 }, // Pool-Dublette ⇒ raus
      { titel: "party-hit", artist: "Doppelt", jahr: 2016 }, // Pack-Dublette ⇒ raus
      { titel: "Zeitmaschine", artist: "Retro AG", jahr: 1830 }, // Jahr absurd ⇒ null
    ]);
    expect(fakten.map((f) => f.titel)).toEqual(["Party-Hit", "Zeitmaschine"]);
    expect(fakten[0].genre).toBe("song-pack");
    expect(fakten[1].jahr).toBeNull();
    expect(wsFaktAusSong({ titel: "X", artist: "Y", jahr: 1999 }, new Set())?.jahr).toBe(1999);
    expect(wsFaktenAusSongs(undefined)).toEqual([]);
  });

  it("Beat-Wahl: kein Titel doppelt, Pack-Anteil ≤ Hälfte (aufgerundet), Staffelung", () => {
    const pack = wsFaktenAusSongs(
      Array.from({ length: 10 }, (_, i) => ({
        titel: `Wunsch ${i + 1}`,
        artist: `Wunsch-Act ${i + 1}`,
        jahr: 2020,
      })),
    );
    const beats = wsWaehleBeats(5, pack, createRng(11));
    expect(beats).toHaveLength(5);
    expect(new Set(beats.map((b) => b.titel)).size).toBe(5);
    expect(beats.filter((b) => b.genre === "song-pack").length).toBeLessThanOrEqual(3);
    // Bekanntheits-Staffelung: die Runde wird nie leichter.
    const rang = { easy: 0, medium: 1, hard: 2, ultrahard: 3 };
    for (let i = 1; i < beats.length; i++) {
      expect(rang[beats[i].schwierigkeit]).toBeGreaterThanOrEqual(rang[beats[i - 1].schwierigkeit]);
    }
    // Ohne Pack: alles aus dem eingebauten Pool.
    const ohnePack = wsWaehleBeats(4, [], createRng(11));
    expect(ohnePack).toHaveLength(4);
    expect(ohnePack.every((b) => b.genre !== "song-pack")).toBe(true);
  });

  it("init mischt Song-Pack-Einträge als Zusatz-Fragen ein (wuenschtSongs-Draht)", () => {
    const songs = Array.from({ length: 8 }, (_, i) => ({
      id: `s${i}`,
      titel: `Pack-Song ${i + 1}`,
      artist: `Pack-Act ${i + 1}`,
      jahr: 2021,
    }));
    const { state } = setup({ beats: 6, songs, seed: 5 });
    expect(state.beats).toHaveLength(6);
    const packBeats = state.beats.filter((b) => b.fakt.genre === "song-pack");
    expect(packBeats.length).toBeGreaterThanOrEqual(1);
    expect(packBeats.length).toBeLessThanOrEqual(3); // Deckel: Hälfte von 6
  });
});

describe("wer-singts: Beat-Ablauf + Wertung", () => {
  it("auflegen → raten → aufdeckung; richtig zahlt Grundwert + Speed-Bonus", () => {
    const { clock, ctx, state } = setup({ beats: 1 });
    expect(state.phase).toBe("auflegen");
    let s = phaseVorbei(state, ctx, clock);
    expect(s.phase).toBe("raten");
    const b = s.beats[0];
    const wert = WS_WERT[b.fakt.schwierigkeit];
    const start = s.phaseStartetAt;
    s = reduce(
      s,
      aktion("p1", { type: "answer", choice: b.answer as 0 | 1 | 2 | 3 }, start + 1_000),
      ctx,
    );
    s = reduce(
      s,
      aktion(
        "p2",
        { type: "answer", choice: ((b.answer + 1) % 4) as 0 | 1 | 2 | 3 },
        start + 2_000,
      ),
      ctx,
    );
    s = phaseVorbei(s, ctx, clock);
    expect(s.phase).toBe("aufdeckung");
    expect(s.deltas.p1).toBe(wert + speedBonus(wert, 1_000, 12_000));
    expect(s.deltas.p2 ?? 0).toBe(0); // falsch = 0, keine Strafe
    expect(s.historie[0].richtige).toEqual(["p1"]);
    expect(s.historie[0].falsche).toEqual(["p2"]);
    s = phaseVorbei(s, ctx, clock);
    expect(werSingtsPlugin.isFinished(s)).toBe(true);
    const scores = werSingtsPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(wert + speedBonus(wert, 1_000, 12_000));
    expect(scores[asPlayerId("p3")]).toBe(0);
    const outcomes = werSingtsPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")].correct).toBeNull(); // nie beteiligt
  });

  it("der SCHNELLERE richtige Tipp verdient mehr (Speed-Bonus-Staffel)", () => {
    const { clock, ctx, state } = setup({ beats: 1 });
    let s = phaseVorbei(state, ctx, clock);
    const b = s.beats[0];
    const start = s.phaseStartetAt;
    const richtig = b.answer as 0 | 1 | 2 | 3;
    s = reduce(s, aktion("p1", { type: "answer", choice: richtig }, start + 500), ctx);
    s = reduce(s, aktion("p2", { type: "answer", choice: richtig }, start + 11_000), ctx);
    s = reduce(s, aktion("p3", { type: "answer", choice: richtig }, start + 11_500), ctx);
    s = tick(s, ctx); // alle fertig ⇒ Aufdeckung sofort
    expect(s.phase).toBe("aufdeckung");
    expect(s.deltas.p1).toBeGreaterThan(s.deltas.p2);
    expect(s.deltas.p2).toBeGreaterThanOrEqual(s.deltas.p3);
  });

  it("Antwort-Locks: erste zählt, auflegen/zu spät/Fremd-Index verpuffen", () => {
    const { clock, ctx, state } = setup({ beats: 1 });
    // In der Auflegen-Phase ist noch KEINE Antwort möglich.
    expect(reduce(state, aktion("p1", { type: "answer", choice: 0 }, 1_000), ctx)).toBe(state);
    let s = phaseVorbei(state, ctx, clock);
    const start = s.phaseStartetAt;
    s = reduce(s, aktion("p1", { type: "answer", choice: 0 }, start + 1_000), ctx);
    const doppelt = reduce(s, aktion("p1", { type: "answer", choice: 1 }, start + 2_000), ctx);
    expect(doppelt.antworten.p1.choice).toBe(0); // eingerastet
    const zuSpaet = s.phaseEndetAt + SPAETANTWORT_GNADE_MS + 1;
    expect(reduce(s, aktion("p2", { type: "answer", choice: 1 }, zuSpaet), ctx)).toBe(s);
    expect(reduce(s, aktion("fremd", { type: "answer", choice: 1 }, start + 1_000), ctx)).toBe(s);
  });

  it("mehrere Beats laufen durch; finished erst nach dem LETZTEN Beat", () => {
    const { clock, ctx, state } = setup({ beats: 3 });
    let s = state;
    for (let i = 0; i < 3; i++) {
      expect(s.beatIndex).toBe(i);
      expect(s.phase).toBe("auflegen");
      s = phaseVorbei(s, ctx, clock); // → raten
      s = phaseVorbei(s, ctx, clock); // Timeout ⇒ Aufdeckung (keine Antworten)
      expect(s.phase).toBe("aufdeckung");
      s = phaseVorbei(s, ctx, clock);
    }
    expect(werSingtsPlugin.isFinished(s)).toBe(true);
    expect(s.historie).toHaveLength(3);
  });

  it("alle Spieler offline ⇒ der Beat rechnet SOFORT ab (die Show wartet nicht)", () => {
    const { clock, ctx, state } = setup({ beats: 1 });
    let s = phaseVorbei(state, ctx, clock);
    for (const p of ["p1", "p2", "p3"]) {
      s = werSingtsPlugin.onDisconnect(s, asPlayerId(p), ctx) as WerSingtsState;
    }
    s = tick(s, ctx);
    expect(s.phase).toBe("aufdeckung");
    expect(s.historie[0].richtige).toEqual([]);
  });

  it("GM force.finish beendet sofort; timer.extend/shift verschieben konsistent", () => {
    const { ctx, state } = setup();
    const fertig = reduce(state, { kind: "gm", type: "force.finish" }, ctx);
    expect(fertig.finished).toBe(true);
    const laenger = reduce(state, { kind: "gm", type: "timer.extend", ms: 5_000 }, ctx);
    expect(laenger.phaseEndetAt).toBe(state.phaseEndetAt + 5_000);
    expect(laenger.phaseStartetAt).toBe(state.phaseStartetAt); // extend schiebt NUR das Ende
    const pause = reduce(state, { kind: "gm", type: "timer.shift", ms: 60_000 }, ctx);
    expect(pause.phaseEndetAt).toBe(state.phaseEndetAt + 60_000);
    expect(pause.phaseStartetAt).toBe(state.phaseStartetAt + 60_000);
    expect(pause.startedAt).toBe(state.startedAt + 60_000);
  });
});

describe("wer-singts: Leak-Wachen + Determinismus", () => {
  it("Interpret + correctIndex bleiben bis zur Aufdeckung geheim (Screen/Player)", () => {
    const { clock, ctx, state } = setup({ beats: 1 });
    const auflegen = werSingtsPlugin.viewFor(state, "screen") as Record<string, unknown>;
    expect(auflegen.titel).toBe(state.beats[0].fakt.titel); // die Platte ist public
    expect(auflegen.options).toBeNull(); // Optionen erst im Rate-Fenster
    expect(auflegen.artist).toBeNull();
    expect(auflegen.correctIndex).toBeUndefined();
    let s = phaseVorbei(state, ctx, clock);
    const raten = werSingtsPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<string, unknown>;
    expect(raten.options).toEqual(s.beats[0].optionen);
    expect(raten.artist).toBeNull(); // der Interpret IST die Lösung!
    expect(raten.correctIndex).toBeUndefined();
    expect(raten.beat).toBeNull();
    const gm = werSingtsPlugin.viewFor(s, "gm") as Record<string, unknown>;
    expect(gm.artist).toBe(s.beats[0].fakt.artist); // Spickzettel
    expect(gm.correctIndex).toBe(s.beats[0].answer);
    s = phaseVorbei(s, ctx, clock); // Timeout ⇒ Aufdeckung
    const aufdeckung = werSingtsPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(aufdeckung.artist).toBe(s.beats[0].fakt.artist); // die Platte dreht sich
    expect((aufdeckung.beat as { correctIndex: number }).correctIndex).toBe(s.beats[0].answer);
  });

  it("yourChoice sieht nur der Spieler selbst; der Zähler ist anonym", () => {
    const { clock, ctx, state } = setup({ beats: 1 });
    let s = phaseVorbei(state, ctx, clock);
    s = reduce(s, aktion("p1", { type: "answer", choice: 2 }, s.phaseStartetAt + 1_000), ctx);
    const p1 = werSingtsPlugin.viewFor(s, "player", asPlayerId("p1")) as Record<string, unknown>;
    expect(p1.yourChoice).toBe(2);
    const p2 = werSingtsPlugin.viewFor(s, "player", asPlayerId("p2")) as Record<string, unknown>;
    expect(p2.yourChoice).toBeNull();
    expect(p2.antworten).toBeUndefined(); // Antwort-Details nur beim GM
    const screen = werSingtsPlugin.viewFor(s, "screen") as Record<string, unknown>;
    expect(screen.answeredCount).toBe(1);
    expect(screen.antworten).toBeUndefined();
  });

  it("Seed-Determinismus: gleicher Seed ⇒ identische Beats, Optionen und Views", () => {
    const lauf = () => {
      const songs = [{ titel: "Wunsch-Song", artist: "Wunsch-Act", jahr: 2020 }];
      const { clock, ctx, state } = setup({ beats: 4, songs, seed: 42 });
      let s = phaseVorbei(state, ctx, clock);
      s = reduce(s, aktion("p1", { type: "answer", choice: 1 }, s.phaseStartetAt + 800), ctx);
      return s;
    };
    const a = lauf();
    const b = lauf();
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    expect(JSON.stringify(werSingtsPlugin.viewFor(a, "screen"))).toBe(
      JSON.stringify(werSingtsPlugin.viewFor(b, "screen")),
    );
    // Anderer Seed ⇒ (fast sicher) andere Beat-Auswahl.
    const { state: anders } = setup({ beats: 4, seed: 99 });
    expect(JSON.stringify(anders.beats.map((x) => x.fakt.titel))).not.toBe(
      JSON.stringify(a.beats.map((x) => x.fakt.titel)),
    );
  });
});
