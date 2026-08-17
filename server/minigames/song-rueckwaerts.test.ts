// Rückwärts-Banane: Abspielplan (Auto + GM-Bonus), Antwort-Lock, MC-Scoring
// mit Speed-Bonus, Determinismus, Fixture-Fallback, Leak-Schutz (Vorwärts-
// Intro erst zur Auflösung).
import { describe, expect, it } from "vitest";
import type { ContentSlice } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  RB_CLIP_MS,
  RB_GM_REPLAY_VORLAUF_MS,
  RB_MAX_ABSPIELUNGEN,
  RB_REPLAY_PAUSE_MS,
  RB_TIMER_MS,
  RB_VORLAUF_MS,
  rbAutoAbspielplan,
} from "../../shared/minigames/song-rueckwaerts.meta";
import { fragenGewinn } from "../../shared/money";
import { createRng } from "../../shared/rng";
import { FIXTURE_SONGS, songOption, type Song } from "../../shared/songs";
import { createTestClock } from "../../shared/time";
import type { Ctx, PlayerAction } from "./_api/plugin";
import { songRueckwaertsPlugin, type SongRueckwaertsState } from "./song-rueckwaerts/index";
import type { SongRueckwaertsAction } from "../../shared/minigames/song-rueckwaerts.meta";

const spieler = [asPlayerId("p1"), asPlayerId("p2"), asPlayerId("p3")];

// Slice-Vertrag: songs[0] = Ziel. Default-Ziel: fx-sax-banane (medium),
// „Banane in Samt — Saxo Simia" — die Leak-Tests prüfen GENAU diese Strings.
function setup(opts?: {
  songs?: ContentSlice["songs"];
  seed?: number;
  mods?: ContentSlice["mods"];
}) {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(opts?.seed ?? 7) };
  const content: ContentSlice = {
    questions: [],
    songs: opts?.songs ?? [...FIXTURE_SONGS],
    mods: opts?.mods,
  };
  const state = songRueckwaertsPlugin.init(spieler, content, ctx) as SongRueckwaertsState;
  return { clock, ctx, state };
}

function antwort(
  playerId: string,
  choice: number,
  atServerTime: number,
): PlayerAction<SongRueckwaertsAction> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "answer", choice: choice as 0 | 1 | 2 | 3 },
    atServerTime,
  };
}

describe("song-rueckwaerts: Start-State + Abspielplan", () => {
  it("init: 4 einzigartige Optionen, correctIndex zeigt auf Titel — Artist", () => {
    const { state } = setup();
    expect(state.optionen).toHaveLength(4);
    expect(new Set(state.optionen).size).toBe(4);
    expect(state.optionen[state.correctIndex]).toBe(
      songOption({ titel: state.titel, artist: state.artist }),
    );
    expect(state.timerMs).toBe(RB_TIMER_MS);
    expect(state.endsAt).toBe(RB_TIMER_MS);
  });

  it("Auto-Abspielplan: Erst-Play nach 1 s + genau EINE Auto-Wiederholung", () => {
    const { state } = setup();
    expect(state.abspielplan).toEqual([
      RB_VORLAUF_MS,
      RB_VORLAUF_MS + RB_CLIP_MS + RB_REPLAY_PAUSE_MS,
    ]);
    expect(rbAutoAbspielplan(10_000)).toEqual([11_000, 18_500]);
  });

  it("GM-Verlängerung bringt die dritte Abspielung — Deckel bei 3", () => {
    const h = setup();
    h.clock.advance(12_000);
    let s = songRueckwaertsPlugin.reduce(
      h.state,
      { kind: "gm", type: "timer.extend", ms: 15_000 },
      h.ctx,
    ) as SongRueckwaertsState;
    expect(s.endsAt).toBe(RB_TIMER_MS + 15_000);
    expect(s.abspielplan).toHaveLength(3);
    expect(s.abspielplan[2]).toBe(12_000 + RB_GM_REPLAY_VORLAUF_MS);
    // Zweites Extend: mehr Zeit ja, aber KEINE vierte Abspielung.
    s = songRueckwaertsPlugin.reduce(
      s,
      { kind: "gm", type: "timer.extend", ms: 15_000 },
      h.ctx,
    ) as SongRueckwaertsState;
    expect(s.abspielplan).toHaveLength(RB_MAX_ABSPIELUNGEN);
  });

  it("Pause (timer.shift) verschiebt Deadline UND Abspielplan gemeinsam", () => {
    const h = setup();
    const s = songRueckwaertsPlugin.reduce(
      h.state,
      { kind: "gm", type: "timer.shift", ms: 10_000 },
      h.ctx,
    ) as SongRueckwaertsState;
    expect(s.startedAt).toBe(10_000);
    expect(s.endsAt).toBe(10_000 + RB_TIMER_MS);
    expect(s.abspielplan).toEqual([11_000, 18_500]);
  });
});

describe("song-rueckwaerts: Antworten + Scoring (MC mit Speed-Bonus)", () => {
  it("Antwort-Lock: die ERSTE Antwort zählt, Umentscheiden wird verworfen", () => {
    const h = setup();
    let s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", 0, 5_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.reduce(s, antwort("p1", 2, 6_000), h.ctx) as SongRueckwaertsState;
    expect(s.answers.p1).toEqual({ choice: 0, nachMs: 5_000 });
  });

  it("Gnadenfenster: +400 ms nach endsAt zählt noch, danach verworfen", () => {
    const h = setup();
    const geradeNoch = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", 1, RB_TIMER_MS + 399),
      h.ctx,
    ) as SongRueckwaertsState;
    expect(geradeNoch.answers.p1).toBeDefined();
    const zuSpaet = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", 1, RB_TIMER_MS + 401),
      h.ctx,
    ) as SongRueckwaertsState;
    expect(zuSpaet.answers.p1).toBeUndefined();
  });

  it("richtig = Grundwert + Speed-Bonus (schnell > langsam), falsch/keine = 0", () => {
    const h = setup(); // Ziel fx-sax-banane ⇒ medium (Grundwert 250)
    const richtig = h.state.correctIndex;
    const falsch = ((richtig + 1) % 4) as 0 | 1 | 2 | 3;
    let s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", richtig, 7_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.reduce(
      s,
      antwort("p2", richtig, 20_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.reduce(
      s,
      antwort("p3", falsch, 8_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = { ...s, finished: true };
    const scores = songRueckwaertsPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(fragenGewinn("medium", 7_000, RB_TIMER_MS));
    expect(scores[asPlayerId("p2")]).toBe(fragenGewinn("medium", 20_000, RB_TIMER_MS));
    expect(scores[asPlayerId("p1")]).toBeGreaterThan(scores[asPlayerId("p2")]);
    expect(scores[asPlayerId("p3")]).toBe(0);
  });

  it("outcomes: richtig/falsch/keine-Antwort für Streak (meta.streak = true)", () => {
    const h = setup();
    const richtig = h.state.correctIndex;
    const falsch = ((richtig + 1) % 4) as 0 | 1 | 2 | 3;
    let s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", richtig, 7_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.reduce(
      s,
      antwort("p2", falsch, 9_000),
      h.ctx,
    ) as SongRueckwaertsState;
    const outcomes = songRueckwaertsPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")]).toEqual({ correct: true, nachMs: 7_000 });
    expect(outcomes[asPlayerId("p2")]).toEqual({ correct: false, nachMs: 9_000 });
    expect(outcomes[asPlayerId("p3")]).toEqual({ correct: null });
    expect(songRueckwaertsPlugin.meta.streak).toBe(true);
  });

  it("endet, wenn alle geantwortet haben ODER der Timer abläuft", () => {
    const h = setup();
    const richtig = h.state.correctIndex;
    let s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", richtig, 5_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.reduce(
      s,
      antwort("p2", richtig, 6_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.tick(s, h.ctx) as SongRueckwaertsState;
    expect(s.finished).toBe(false);
    s = songRueckwaertsPlugin.reduce(
      s,
      antwort("p3", richtig, 7_000),
      h.ctx,
    ) as SongRueckwaertsState;
    s = songRueckwaertsPlugin.tick(s, h.ctx) as SongRueckwaertsState;
    expect(s.finished).toBe(true);

    const frisch = setup();
    frisch.clock.advance(RB_TIMER_MS);
    const nachTimeout = songRueckwaertsPlugin.tick(
      frisch.state,
      frisch.ctx,
    ) as SongRueckwaertsState;
    expect(nachTimeout.finished).toBe(true);
  });
});

describe("song-rueckwaerts: Determinismus + Fixture-Fallback", () => {
  it("gleicher Seed ⇒ Bit für Bit identischer Start-State", () => {
    const a = setup({ seed: 42 });
    const b = setup({ seed: 42 });
    expect(JSON.stringify(a.state)).toBe(JSON.stringify(b.state));
  });

  it("OHNE Song-Slice fällt der Fixture-Katalog ein — kein Crash", () => {
    const clock = createTestClock(0);
    const ctx: Ctx = { clock, rng: createRng(3) };
    const state = songRueckwaertsPlugin.init(
      spieler,
      { questions: [] },
      ctx,
    ) as SongRueckwaertsState;
    expect(FIXTURE_SONGS.some((f) => f.id === state.songId)).toBe(true);
    expect(state.optionen).toHaveLength(4);
  });

  it("kaputter Slice ⇒ parseSongs verwirft Ungültiges, Fixtures greifen", () => {
    const h = setup({ songs: [{ id: "nur-basis", titel: "T", artist: "A" }] });
    expect(FIXTURE_SONGS.some((f) => f.id === h.state.songId)).toBe(true);
  });

  it("Slice-Vertrag: songs[0] = Ziel; halbe-Miete-Mod halbiert den Timer", () => {
    const pack: Song[] = [FIXTURE_SONGS[4], FIXTURE_SONGS[0], FIXTURE_SONGS[1], FIXTURE_SONGS[2]];
    const h = setup({ songs: pack, mods: { timerFaktor: 0.5 } });
    expect(h.state.songId).toBe("fx-hit-dschungel");
    expect(h.state.schwierigkeit).toBe("ultrahard");
    expect(h.state.timerMs).toBe(RB_TIMER_MS / 2);
    expect(h.state.endsAt).toBe(RB_TIMER_MS / 2);
  });
});

describe("song-rueckwaerts: Leak-Schutz + Views (der Aha-Moment)", () => {
  it("correctIndex/Titel-Felder/Song-Id leaken vor der Auflösung NIE an Player/Screen", () => {
    const h = setup();
    const s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", 0, 5_000),
      h.ctx,
    ) as SongRueckwaertsState;
    const playerJson = JSON.stringify(songRueckwaertsPlugin.viewFor(s, "player", spieler[0]));
    expect(playerJson).not.toContain("correctIndex");
    expect(playerJson).not.toContain('"titel"');
    expect(playerJson).not.toContain("fx-sax-banane"); // Medien-URLs = Spick-Kanal
    const screenJson = JSON.stringify(songRueckwaertsPlugin.viewFor(s, "screen"));
    expect(screenJson).not.toContain("correctIndex");
    expect(screenJson).not.toContain('"titel"');
    const gm = songRueckwaertsPlugin.viewFor(s, "gm") as { titel: string; correctIndex: number };
    expect(gm.titel).toBe("Banane in Samt");
    expect(gm.correctIndex).toBe(s.correctIndex);
  });

  it("Screen: Rückwärts-URL sofort, Vorwärts-Intro ERST mit der Auflösung", () => {
    const h = setup();
    const vorher = songRueckwaertsPlugin.viewFor(h.state, "screen") as {
      medien: { rueckwaertsUrl: string; introUrl: string | null };
      abspielplan: number[];
    };
    expect(vorher.medien.rueckwaertsUrl).toBe(
      "/media/audio/fixtures/musik/fx-sax-banane/rueckwaerts5s.ogg",
    );
    expect(vorher.medien.introUrl).toBeNull();
    expect(vorher.abspielplan).toHaveLength(2);
    const fertig = { ...h.state, finished: true };
    const nachher = songRueckwaertsPlugin.viewFor(fertig, "screen") as {
      medien: { introUrl: string | null };
      aufloesung: { titel: string };
    };
    expect(nachher.medien.introUrl).toBe("/media/audio/fixtures/musik/fx-sax-banane/intro5s.ogg");
    expect(nachher.aufloesung.titel).toBe("Banane in Samt");
  });

  it("Player sieht die eigene Wahl; Auflösung liefert perPlayer mit Deltas", () => {
    const h = setup();
    const richtig = h.state.correctIndex;
    let s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p1", richtig, 5_000),
      h.ctx,
    ) as SongRueckwaertsState;
    const meins = songRueckwaertsPlugin.viewFor(s, "player", spieler[0]) as { yourChoice: number };
    expect(meins.yourChoice).toBe(richtig);
    s = { ...s, finished: true };
    const view = songRueckwaertsPlugin.viewFor(s, "player", spieler[1]) as {
      aufloesung: { perPlayer: { playerId: string; correct: boolean; delta: number }[] };
    };
    const p1 = view.aufloesung.perPlayer.find((e) => e.playerId === "p1");
    expect(p1?.correct).toBe(true);
    expect(p1?.delta).toBe(fragenGewinn("medium", 5_000, RB_TIMER_MS));
  });

  it("State bleibt JSON-serialisierbar (Save/Load-Vertrag)", () => {
    const h = setup();
    const s = songRueckwaertsPlugin.reduce(
      h.state,
      antwort("p2", 1, 4_000),
      h.ctx,
    ) as SongRueckwaertsState;
    const kopie = JSON.parse(JSON.stringify(s)) as SongRueckwaertsState;
    expect(songRueckwaertsPlugin.scores({ ...kopie, finished: true })).toEqual(
      songRueckwaertsPlugin.scores({ ...s, finished: true }),
    );
  });
});
