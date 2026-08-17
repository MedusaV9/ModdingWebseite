// Blitz-DJ: Verfalls-Treppe (Goldens), Eskalation, Falsch-Buzz-Sperre + Strafe,
// Sammelfenster/Armierung, Determinismus, Fixture-Fallback, Leak-Schutz.
// (Verfügbarkeits-Wächter beider Song-Formate: engine/song-verfuegbarkeit.test.)
import { describe, expect, it } from "vitest";
import { ordneBuzzes } from "../../shared/buzzer";
import type { ContentSlice } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  SS_INTRO_MS,
  SS_RATE_MS,
  SS_SNIPPET_MS,
  SS_STRAFE_MM,
  SS_STUFEN,
  SS_TREPPE,
  ssLauschFensterMs,
  ssStufenWert,
  type SongSnippetAction,
} from "../../shared/minigames/song-snippet.meta";
import { FRAGE_WERTE } from "../../shared/money";
import { createRng } from "../../shared/rng";
import { FIXTURE_SONGS, songOption, type Song } from "../../shared/songs";
import { createTestClock } from "../../shared/time";
import type { BuzzerApi, Ctx, PlayerAction } from "./_api/plugin";
import { songSnippetPlugin, ssSnippetUrl, type SongSnippetState } from "./song-snippet/index";

const spieler = [asPlayerId("p1"), asPlayerId("p2"), asPlayerId("p3")];

// Slice-Vertrag: songs[0] = Ziel. Default-Ziel: fx-sax-banane (medium),
// „Banane in Samt — Saxo Simia" — die Leak-Tests prüfen GENAU diese Strings.
function setup(opts?: {
  songs?: Song[] | ContentSlice["songs"];
  seed?: number;
  buzzer?: BuzzerApi;
}) {
  const clock = createTestClock(0);
  const ctx: Ctx = { clock, rng: createRng(opts?.seed ?? 7), buzzer: opts?.buzzer };
  const content: ContentSlice = { questions: [], songs: opts?.songs ?? [...FIXTURE_SONGS] };
  const state = songSnippetPlugin.init(spieler, content, ctx) as SongSnippetState;
  return { clock, ctx, state };
}

type Harness = ReturnType<typeof setup>;

/** Clock auf ABSOLUTE Server-Zeit t stellen und einmal ticken. */
function tickAt(s: SongSnippetState, h: Harness, t: number): SongSnippetState {
  h.clock.advance(t - h.clock.now());
  return songSnippetPlugin.tick(s, h.ctx) as SongSnippetState;
}

function buzz(
  playerId: string,
  atServerTime: number,
  extra?: { finalAt?: number; pressedAtServerEst?: number },
): PlayerAction<SongSnippetAction> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: {
      type: "buzz",
      finalAt:
        extra?.finalAt ?? (extra?.pressedAtServerEst === undefined ? atServerTime : undefined),
      pressedAtServerEst: extra?.pressedAtServerEst,
    },
    atServerTime,
  };
}

function antwort(
  playerId: string,
  choice: number,
  atServerTime: number,
): PlayerAction<SongSnippetAction> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "answer", choice: choice as 0 | 1 | 2 | 3 },
    atServerTime,
  };
}

/** Bis in die Lausch-Phase der Stufe 0 laufen (Intro abwarten). */
function bisLauschen(h: Harness): SongSnippetState {
  return tickAt(h.state, h, SS_INTRO_MS);
}

/** p buzzert bei t, Sammelfenster läuft aus ⇒ Rate-Phase mit p als Rater. */
function bisRaten(s: SongSnippetState, h: Harness, playerId: string, t: number): SongSnippetState {
  const nach = songSnippetPlugin.reduce(s, buzz(playerId, t), h.ctx) as SongSnippetState;
  return tickAt(nach, h, t + 300);
}

describe("song-snippet: Verfalls-Treppe (Goldens, Herleitung im Meta-Kopf)", () => {
  it("SCHWER fällt exakt 1000→800→600→400→250→100 (Task-Vorgabe)", () => {
    const werte = Array.from({ length: SS_STUFEN }, (_, s) => ssStufenWert("hard", s));
    expect(werte).toEqual([1_000, 800, 600, 400, 250, 100]);
  });

  it("alle Treppen starten bei 2× Frage-Grundwert und teilen die Faktoren", () => {
    for (const schwierigkeit of ["easy", "medium", "hard", "ultrahard"] as const) {
      const start = 2 * FRAGE_WERTE[schwierigkeit];
      expect(SS_TREPPE[schwierigkeit][0]).toBe(start);
      // Streng monoton fallend — späteres Buzzen lohnt NIE mehr.
      const treppe = SS_TREPPE[schwierigkeit];
      for (let s = 1; s < treppe.length; s++) expect(treppe[s]).toBeLessThan(treppe[s - 1]);
    }
    expect(SS_TREPPE.easy).toEqual([200, 160, 120, 80, 50, 20]);
    expect(SS_TREPPE.ultrahard).toEqual([2_000, 1_600, 1_200, 800, 500, 200]);
  });

  it("Stufen-Uhr: Snippets 0,1→5 s, Lausch-Fenster = Snippet + 4 s Lauer", () => {
    expect(SS_SNIPPET_MS).toEqual([100, 200, 300, 500, 1000, 5000]);
    expect(ssLauschFensterMs(0)).toBe(4_100);
    expect(ssLauschFensterMs(5)).toBe(9_000);
    // ssStufenWert klemmt außerhalb der Treppe (defensiv).
    expect(ssStufenWert("hard", 99)).toBe(100);
    expect(ssStufenWert("hard", -1)).toBe(1_000);
  });
});

describe("song-snippet: Ablauf Intro → Lauschen → Buzz → Raten", () => {
  it("startet im Intro und wechselt nach 2 s in die Lausch-Phase (Stufe 0)", () => {
    const h = setup();
    expect(h.state.phase).toBe("intro");
    const nochIntro = tickAt(h.state, h, SS_INTRO_MS - 1);
    expect(nochIntro.phase).toBe("intro");
    const lauschen = tickAt(nochIntro, h, SS_INTRO_MS);
    expect(lauschen.phase).toBe("lauschen");
    expect(lauschen.stufe).toBe(0);
    expect(lauschen.lauschenStartetAt).toBe(SS_INTRO_MS);
    expect(lauschen.phaseEndsAt).toBe(SS_INTRO_MS + ssLauschFensterMs(0));
  });

  it("Frühbuzz im Intro verpufft; Buzz-Zeit wird auf den Snippet-Start armiert", () => {
    const h = setup();
    const frueh = songSnippetPlugin.reduce(h.state, buzz("p1", 1_000), h.ctx) as SongSnippetState;
    expect(frueh.buzzes).toEqual({});
    const lauschen = bisLauschen(h);
    // finalAt VOR dem Snippet-Start ⇒ max(lauschenStartetAt, finalAt).
    const s = songSnippetPlugin.reduce(
      lauschen,
      buzz("p1", 2_100, { finalAt: 1_900 }),
      h.ctx,
    ) as SongSnippetState;
    expect(s.buzzes.p1).toBe(SS_INTRO_MS);
    expect(s.ersterBuzzAt).toBe(2_100);
  });

  it("Sammelfenster: 280 ms nach dem ERSTEN Buzz gewinnt das früheste finalAt", () => {
    const h = setup();
    let s = bisLauschen(h);
    // p1 drückt zuerst EIN, p2s Paket kommt später, war aber früher gedrückt
    // (>40 ms Abstand — kein Fotofinish-Los nötig).
    s = songSnippetPlugin.reduce(
      s,
      buzz("p1", 2_600, { finalAt: 2_600 }),
      h.ctx,
    ) as SongSnippetState;
    s = songSnippetPlugin.reduce(
      s,
      buzz("p2", 2_700, { finalAt: 2_510 }),
      h.ctx,
    ) as SongSnippetState;
    // Vor Fenster-Ende (2.600 + 280) bleibt es beim Lauschen.
    const nochLauschen = tickAt(s, h, 2_870);
    expect(nochLauschen.phase).toBe("lauschen");
    const raten = tickAt(nochLauschen, h, 2_881);
    expect(raten.phase).toBe("raten");
    expect(raten.raterId).toBe(asPlayerId("p2"));
    expect(raten.fotofinish).toBe(false);
    expect(raten.phaseEndsAt).toBe(2_881 + SS_RATE_MS);
  });

  it("player.action-Buzz ohne finalAt wird via ctx.buzzer.medianRtt geclampt", () => {
    const buzzer: BuzzerApi = {
      medianRtt: () => 200,
      sammelfensterMs: 280,
      fotofinishMs: 40,
      ordne: (k) => ordneBuzzes(k, createRng(1)),
    };
    const h = setup({ buzzer });
    const lauschen = bisLauschen(h);
    // Behauptet 2.100, empfangen 2.500, Median-RTT 200 ⇒ floor 2.300.
    const s = songSnippetPlugin.reduce(
      lauschen,
      buzz("p1", 2_500, { pressedAtServerEst: 2_100 }),
      h.ctx,
    ) as SongSnippetState;
    expect(s.buzzes.p1).toBe(2_300);
  });

  it("richtig geraten ⇒ Gewinner mit dem Stufenwert, alle anderen 0", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = bisRaten(s, h, "p1", 2_500);
    s = songSnippetPlugin.reduce(
      s,
      antwort("p1", s.correctIndex, 3_500),
      h.ctx,
    ) as SongSnippetState;
    expect(s.finished).toBe(true);
    expect(s.gewinner?.playerId).toBe(asPlayerId("p1"));
    const scores = songSnippetPlugin.scores(s);
    expect(scores[asPlayerId("p1")]).toBe(ssStufenWert("medium", 0)); // 500
    expect(scores[asPlayerId("p2")]).toBe(0);
    const outcomes = songSnippetPlugin.outcomes!(s);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBeNull();
  });

  it("falsch geraten ⇒ Sperre + 50-MM-Strafe (ins Glas) + nächste Stufe", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = bisRaten(s, h, "p1", 2_500);
    const falsch = ((s.correctIndex + 1) % 4) as 0 | 1 | 2 | 3;
    s = songSnippetPlugin.reduce(s, antwort("p1", falsch, 3_500), h.ctx) as SongSnippetState;
    expect(s.finished).toBe(false);
    expect(s.phase).toBe("lauschen");
    expect(s.stufe).toBe(1);
    expect(s.gesperrt).toEqual([asPlayerId("p1")]);
    expect(songSnippetPlugin.scores(s)[asPlayerId("p1")]).toBe(-SS_STRAFE_MM);
    expect(songSnippetPlugin.meta.strafenInsGlas).toBe(true);
    // Der Gesperrte kann für den Rest des Songs NICHT mehr buzzen.
    const nochmal = songSnippetPlugin.reduce(s, buzz("p1", 4_000), h.ctx) as SongSnippetState;
    expect(nochmal.buzzes.p1).toBeUndefined();
  });

  it("Rate-Timeout zählt wie falsch (Sperre + Strafe + Eskalation)", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = bisRaten(s, h, "p1", 2_500);
    const kurzVorher = tickAt(s, h, s.phaseEndsAt + 399);
    expect(kurzVorher.phase).toBe("raten");
    s = tickAt(kurzVorher, h, kurzVorher.phaseEndsAt + 401);
    expect(s.phase).toBe("lauschen");
    expect(s.stufe).toBe(1);
    expect(s.gesperrt).toEqual([asPlayerId("p1")]);
    expect(s.fehlversuche[0].choice).toBeNull();
    expect(songSnippetPlugin.scores(s)[asPlayerId("p1")]).toBe(-SS_STRAFE_MM);
  });

  it("niemand buzzert ⇒ Eskalation je Stufe, nach Stufe 6 Auflösung ohne Gewinner", () => {
    const h = setup();
    let s = bisLauschen(h);
    for (let stufe = 0; stufe < SS_STUFEN - 1; stufe++) {
      expect(s.stufe).toBe(stufe);
      s = tickAt(s, h, s.phaseEndsAt);
      expect(s.buzzes).toEqual({});
    }
    expect(s.stufe).toBe(SS_STUFEN - 1);
    s = tickAt(s, h, s.phaseEndsAt);
    expect(s.finished).toBe(true);
    expect(s.gewinner).toBeNull();
    expect(Object.values(songSnippetPlugin.scores(s))).toEqual([0, 0, 0]);
  });

  it("der Wert VERFÄLLT: Sieg auf Stufe 2 zahlt nur noch den Stufe-2-Wert", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = tickAt(s, h, s.phaseEndsAt); // Stufe 1
    s = tickAt(s, h, s.phaseEndsAt); // Stufe 2
    const t = h.clock.now() + 500;
    s = bisRaten(s, h, "p2", t);
    s = songSnippetPlugin.reduce(
      s,
      antwort("p2", s.correctIndex, t + 1_000),
      h.ctx,
    ) as SongSnippetState;
    expect(songSnippetPlugin.scores(s)[asPlayerId("p2")]).toBe(ssStufenWert("medium", 2)); // 300
  });

  it("alle gesperrt ⇒ Song vorbei (ohne Gewinner), Strafen bleiben stehen", () => {
    const h = setup();
    let s = bisLauschen(h);
    for (const p of ["p1", "p2", "p3"]) {
      const t = h.clock.now() + 500;
      s = bisRaten(s, h, p, t);
      const falsch = ((s.correctIndex + 1) % 4) as 0 | 1 | 2 | 3;
      s = songSnippetPlugin.reduce(s, antwort(p, falsch, t + 500), h.ctx) as SongSnippetState;
    }
    expect(s.finished).toBe(true);
    expect(s.gewinner).toBeNull();
    const scores = songSnippetPlugin.scores(s);
    for (const p of spieler) expect(scores[p]).toBe(-SS_STRAFE_MM);
  });

  it("Rater-Disconnect ⇒ Sperre + Eskalation, aber OHNE Strafe", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = bisRaten(s, h, "p1", 2_500);
    s = songSnippetPlugin.onDisconnect(s, asPlayerId("p1"), h.ctx) as SongSnippetState;
    expect(s.phase).toBe("lauschen");
    expect(s.stufe).toBe(1);
    expect(s.gesperrt).toEqual([asPlayerId("p1")]);
    expect(s.fehlversuche).toEqual([]);
    expect(songSnippetPlugin.scores(s)[asPlayerId("p1")]).toBe(0);
  });
});

describe("song-snippet: Determinismus + Fixture-Fallback", () => {
  it("gleicher Seed ⇒ Bit für Bit identischer Start-State", () => {
    const a = setup({ seed: 42 });
    const b = setup({ seed: 42 });
    expect(JSON.stringify(a.state)).toBe(JSON.stringify(b.state));
  });

  it("OHNE Song-Slice fällt der Fixture-Katalog ein — kein Crash, 4 Optionen", () => {
    const clock = createTestClock(0);
    const ctx: Ctx = { clock, rng: createRng(3) };
    const state = songSnippetPlugin.init(spieler, { questions: [] }, ctx) as SongSnippetState;
    expect(FIXTURE_SONGS.some((f) => f.id === state.songId)).toBe(true);
    expect(state.optionen).toHaveLength(4);
    expect(new Set(state.optionen).size).toBe(4);
    expect(state.optionen[state.correctIndex]).toBe(
      songOption({ titel: state.titel, artist: state.artist }),
    );
  });

  it("kaputter Slice (ungültige Einträge) ⇒ parseSongs verwirft, Fixtures greifen", () => {
    const h = setup({
      songs: [
        { id: "kaputt-ohne-medien", titel: "Titel", artist: "Artist" },
        { id: "", titel: "", artist: "" },
      ],
    });
    expect(FIXTURE_SONGS.some((f) => f.id === h.state.songId)).toBe(true);
    expect(h.state.optionen).toHaveLength(4);
  });

  it("Slice-Vertrag: songs[0] ist der Ziel-Song, Schwierigkeit wird übernommen", () => {
    const pack = [FIXTURE_SONGS[1], FIXTURE_SONGS[0], FIXTURE_SONGS[2], FIXTURE_SONGS[3]];
    const h = setup({ songs: pack });
    expect(h.state.songId).toBe("fx-pizzi-kokos");
    expect(h.state.schwierigkeit).toBe("hard");
    // Distraktoren kommen aus dem Pack — die richtige Option ist dabei.
    expect(h.state.optionen).toContain("Kokosnuss-Polka — Die Pizzikaten");
  });
});

describe("song-snippet: Leak-Schutz + Views", () => {
  it("Views exponieren NIE answeredCount (Auto-GM-+10s-Duck-Typing)", () => {
    // Regression (Browser-Playtest W20): engine.tick verlängert Fragen mit
    // endsAt+answeredCount im View automatisch um 10 s, wenn <50 % geantwortet
    // haben und <4 s übrig sind — beim Blitz-DJ traf das JEDE Intro-/Lausch-
    // Phase (2 s bzw. 4,1 s Fenster) und streckte die 2-s-Kinematik auf 12 s.
    // Buzzes heißen im View deshalb buzzCount.
    const h = setup();
    const s = bisLauschen(h);
    for (const view of [
      songSnippetPlugin.viewFor(s, "screen"),
      songSnippetPlugin.viewFor(s, "player", spieler[0]),
      songSnippetPlugin.viewFor(s, "gm"),
    ]) {
      expect(JSON.stringify(view)).not.toContain("answeredCount");
      expect((view as { buzzCount: number }).buzzCount).toBe(0);
    }
  });

  it("Titel/Artist/correctIndex leaken vor der Auflösung NIE an Player/Screen", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = bisRaten(s, h, "p1", 2_500);
    const playerJson = JSON.stringify(songSnippetPlugin.viewFor(s, "player", spieler[1]));
    expect(playerJson).not.toContain("Banane in Samt");
    expect(playerJson).not.toContain("Saxo Simia");
    expect(playerJson).not.toContain("correctIndex");
    expect(playerJson).not.toContain("fx-sax-banane"); // Medien-URLs = Spick-Kanal
    const screenJson = JSON.stringify(songSnippetPlugin.viewFor(s, "screen"));
    expect(screenJson).not.toContain("correctIndex");
    // GM-Spickzettel sieht die Lösung immer.
    const gm = songSnippetPlugin.viewFor(s, "gm") as { titel: string; correctIndex: number };
    expect(gm.titel).toBe("Banane in Samt");
    expect(gm.correctIndex).toBe(s.correctIndex);
  });

  it("MC-Optionen erscheinen am Handy NUR für den Buzz-Sieger in der Rate-Phase", () => {
    const h = setup();
    let s = bisLauschen(h);
    const vorher = songSnippetPlugin.viewFor(s, "player", spieler[0]) as { options?: string[] };
    expect(vorher.options).toBeUndefined();
    s = bisRaten(s, h, "p1", 2_500);
    const rater = songSnippetPlugin.viewFor(s, "player", spieler[0]) as {
      options?: string[];
      duBistRater: boolean;
    };
    expect(rater.duBistRater).toBe(true);
    expect(rater.options).toHaveLength(4);
    const zuschauer = songSnippetPlugin.viewFor(s, "player", spieler[1]) as { options?: string[] };
    expect(zuschauer.options).toBeUndefined();
  });

  it("Medien-URLs gibt es NUR im Screen-View, Snippet folgt der Stufe", () => {
    const h = setup();
    let s = bisLauschen(h);
    const screen = songSnippetPlugin.viewFor(s, "screen") as {
      medien: { snippetUrl: string; introUrl: string | null };
    };
    expect(screen.medien.snippetUrl).toBe(
      "/media/audio/fixtures/musik/fx-sax-banane/buzz_ms100.ogg",
    );
    expect(screen.medien.introUrl).toBeNull(); // Vorwärts-Intro erst zur Auflösung
    expect(ssSnippetUrl(s.medien, 5)).toBe(s.medien.intro5s);
    s = tickAt(s, h, s.phaseEndsAt); // Stufe 1 ⇒ 200-ms-Snippet
    const screen2 = songSnippetPlugin.viewFor(s, "screen") as {
      medien: { snippetUrl: string };
    };
    expect(screen2.medien.snippetUrl).toContain("buzz_ms200.ogg");
  });

  it("Auflösung liefert Titel/Gewinner/perPlayer inkl. Strafen-Deltas", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = bisRaten(s, h, "p1", 2_500);
    const falsch = ((s.correctIndex + 1) % 4) as 0 | 1 | 2 | 3;
    s = songSnippetPlugin.reduce(s, antwort("p1", falsch, 3_500), h.ctx) as SongSnippetState;
    const t = h.clock.now() + 500;
    s = bisRaten(s, h, "p2", t);
    s = songSnippetPlugin.reduce(
      s,
      antwort("p2", s.correctIndex, t + 500),
      h.ctx,
    ) as SongSnippetState;
    const view = songSnippetPlugin.viewFor(s, "player", spieler[2]) as {
      aufloesung: {
        titel: string;
        gewinnerId: string;
        gewinnerStufe: number;
        perPlayer: { playerId: string; delta: number; correct: boolean }[];
      };
    };
    expect(view.aufloesung.titel).toBe("Banane in Samt");
    expect(view.aufloesung.gewinnerId).toBe("p2");
    expect(view.aufloesung.gewinnerStufe).toBe(1);
    const deltas = Object.fromEntries(view.aufloesung.perPlayer.map((e) => [e.playerId, e.delta]));
    expect(deltas.p1).toBe(-SS_STRAFE_MM);
    expect(deltas.p2).toBe(ssStufenWert("medium", 1)); // 400
    expect(deltas.p3).toBe(0);
  });

  it("State bleibt JSON-serialisierbar; Pause (timer.shift) verschiebt ALLE Anker", () => {
    const h = setup();
    let s = bisLauschen(h);
    s = songSnippetPlugin.reduce(s, buzz("p1", 2_500), h.ctx) as SongSnippetState;
    const kopie = JSON.parse(JSON.stringify(s)) as SongSnippetState;
    expect(songSnippetPlugin.scores(kopie)).toEqual(songSnippetPlugin.scores(s));
    const geschoben = songSnippetPlugin.reduce(
      s,
      { kind: "gm", type: "timer.shift", ms: 10_000 },
      h.ctx,
    ) as SongSnippetState;
    expect(geschoben.lauschenStartetAt).toBe(s.lauschenStartetAt + 10_000);
    expect(geschoben.phaseEndsAt).toBe(s.phaseEndsAt + 10_000);
    expect(geschoben.ersterBuzzAt).toBe((s.ersterBuzzAt ?? 0) + 10_000);
    expect(geschoben.buzzes.p1).toBe(s.buzzes.p1 + 10_000);
  });
});
