// Stummfilm-Studio: Verfügbarkeits-Wache (kein video3s ⇒ nicht verfügbar),
// Beat-Bau + Options-Mathe, Zwei-Stufen-Wertung (voll/halb), Rettungsstufen-
// Sperre, Phasen-Flow, Leak-Schutz (answer/Titel NIE vor der Aufdeckung),
// GM-Eingriffe, Disconnect-Regeln, Media-URL-Übersetzung (kanonisches Pack).
import { describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { asPlayerId } from "../../shared/ids";
import {
  MV_AUFDECKUNG_MS,
  MV_FIXTURE_SONGS,
  MV_STUMM_MS,
  MV_TON_MS,
  mvBaueOptionen,
  mvOptionText,
  mvRettungsWert,
  mvSpielbar,
  mvTonReferenz,
  mvVerfuegbar,
  type MvSong,
} from "../../shared/minigames/musikvideo-raten.meta";
import { FRAGE_WERTE } from "../../shared/money";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import {
  musikvideoRatenPlugin,
  type MusikvideoRatenState,
  type MusikvideoSlice,
} from "./musikvideo-raten/index";

const spieler = [asPlayerId("p1"), asPlayerId("p2"), asPlayerId("p3")];

function frage(id: string, difficulty: Question["difficulty"] = "medium"): Question {
  return {
    id,
    kind: "choice4",
    category: "musik",
    difficulty,
    text: "Welcher Song läuft?",
    options: ["A", "B", "C", "D"],
    answer: 0,
    erklaerung: "Musik-Slot — der Wert kommt aus der Schwierigkeit.",
  };
}

/** Nur-Audio-Song (kein video3s) — als Options-Köder erlaubt, als Beat nicht. */
function audioSong(id: string, titel: string, artist: string): MvSong {
  return { id, titel, artist, medien: { intro5s: `assets/audio/${id}.mp3` } };
}

const PACK: MvSong[] = [
  ...MV_FIXTURE_SONGS,
  audioSong("fx-nur-audio-1", "Ohne Bild", "Radio Rita"),
  audioSong("fx-nur-audio-2", "Nur Ton", "Die Lautsprecher"),
];

function setup(
  opts: {
    songs?: MvSong[];
    fragen?: Question[];
    seed?: number;
    startMs?: number;
  } = {},
) {
  const clock = createTestClock(opts.startMs ?? 0);
  const ctx = { clock, rng: createRng(opts.seed ?? 7) };
  const content: MusikvideoSlice = {
    questions: opts.fragen ?? [frage("q1", "medium"), frage("q2", "hard")],
    songs: opts.songs ?? PACK,
  };
  const state = musikvideoRatenPlugin.init(spieler, content, ctx) as MusikvideoRatenState;
  return { clock, ctx, state };
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

describe("musikvideo-raten: Verfügbarkeit (Kern-Medium video3s)", () => {
  it("mvSpielbar/mvVerfuegbar: nur Songs MIT video3s zählen", () => {
    expect(mvSpielbar(MV_FIXTURE_SONGS[0])).toBe(true);
    expect(mvSpielbar(audioSong("x", "T", "A"))).toBe(false);
    expect(mvVerfuegbar(PACK)).toBe(true);
    expect(mvVerfuegbar([audioSong("x", "T", "A")])).toBe(false);
    expect(mvVerfuegbar([])).toBe(false);
    expect(mvVerfuegbar(undefined)).toBe(false);
  });

  it("leeres Pack ⇒ nicht verfügbar: sofort beendet, 0 MM, ehrlicher View", () => {
    const { state } = setup({ songs: [] });
    expect(state.nichtVerfuegbar).toBe(true);
    expect(musikvideoRatenPlugin.isFinished(state)).toBe(true);
    expect(musikvideoRatenPlugin.scores(state)).toEqual({ p1: 0, p2: 0, p3: 0 });
    const view = musikvideoRatenPlugin.viewFor(state, "screen") as {
      nichtVerfuegbar: boolean;
      aufloesung: { erklaerung: string };
    };
    expect(view.nichtVerfuegbar).toBe(true);
    expect(view.aufloesung.erklaerung).toContain("video3s");
  });

  it("Songs OHNE video3s ⇒ ebenfalls nicht verfügbar (kein Crash)", () => {
    const { state } = setup({
      songs: [audioSong("a", "Eins", "A"), audioSong("b", "Zwei", "B")],
    });
    expect(state.nichtVerfuegbar).toBe(true);
    expect(state.beats).toHaveLength(0);
  });
});

describe("musikvideo-raten: Beat-Bau + Options-Mathe", () => {
  it("baut so viele Beats wie Slot-Fragen — NUR aus spielbaren Songs, ohne Dublette", () => {
    const { state } = setup();
    expect(state.beats).toHaveLength(2); // 2 Fragen, 3 spielbare Songs
    const ids = state.beats.map((b) => b.songId);
    expect(new Set(ids).size).toBe(ids.length);
    const spielbarIds = new Set(MV_FIXTURE_SONGS.map((s) => s.id));
    for (const id of ids) expect(spielbarIds.has(id)).toBe(true);
    // Beat-Wert folgt der Slot-Frage-Schwierigkeit (medium, hard).
    expect(state.beats[0].wert).toBe(FRAGE_WERTE.medium);
    expect(state.beats[1].wert).toBe(FRAGE_WERTE.hard);
  });

  it("mvBaueOptionen: 4 eindeutige Optionen, die richtige am answer-Index", () => {
    for (const seed of [1, 7, 42, 99]) {
      const rng = createRng(seed);
      const { optionen, answer } = mvBaueOptionen(PACK, MV_FIXTURE_SONGS[0], rng);
      expect(optionen).toHaveLength(4);
      expect(new Set(optionen).size).toBe(4);
      expect(optionen[answer]).toBe(mvOptionText(MV_FIXTURE_SONGS[0]));
    }
  });

  it("Mini-Pack (1 Song): Fallback-Köder füllen auf 4 Optionen auf", () => {
    const solo = MV_FIXTURE_SONGS[0];
    const { optionen, answer } = mvBaueOptionen([solo], solo, createRng(3));
    expect(optionen).toHaveLength(4);
    expect(new Set(optionen).size).toBe(4);
    expect(optionen[answer]).toBe(mvOptionText(solo));
  });

  it("übersetzt kanonische Medien-Referenzen (media/… + buzz.ms500 + flaches ms500)", () => {
    const kanonisch: MvSong = {
      id: "s_x1",
      titel: "Kanon-Song",
      artist: "Pipeline-Pia",
      medien: {
        video3s: "media/s_x1/video3s.mp4",
        buzz: { ms500: "media/s_x1/buzz_ms500.ogg" },
        intro5s: "assets/audio/fixtures/musik/fx-video-neon/intro5s.mp3",
      },
    };
    expect(mvTonReferenz(kanonisch)).toBe("media/s_x1/buzz_ms500.ogg");
    // Flaches ms500 (ältere Pack-Entwürfe) wird toleriert:
    expect(mvTonReferenz({ id: "a", titel: "T", artist: "A", medien: { ms500: "x.mp3" } })).toBe(
      "x.mp3",
    );
    const { state } = setup({ songs: [kanonisch], fragen: [frage("q1")] });
    expect(state.beats[0].videoUrl).toBe("/media-musik/s_x1/video3s.mp4");
    expect(state.beats[0].tonUrl).toBe("/media-musik/s_x1/buzz_ms500.ogg");
    expect(state.beats[0].introUrl).toBe("/media/audio/fixtures/musik/fx-video-neon/intro5s.mp3");
  });
});

describe("musikvideo-raten: Zwei-Stufen-Wertung (voll/halb)", () => {
  it("Rettungswert ist die halbe Gage: 100/250/500/1000 → 50/125/250/500", () => {
    expect([100, 250, 500, 1000].map(mvRettungsWert)).toEqual([50, 125, 250, 500]);
  });

  it("stumm richtig = W, mit Ton gerettet = W/2, falsch = 0", () => {
    const { clock, ctx, state } = setup();
    const b = state.beats[0];
    let s = musikvideoRatenPlugin.reduce(state, antwort("p1", b.answer, 1_000), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p2", (b.answer + 1) % 4, 2_000), ctx);
    // p3 verpennt den Stumm-Durchlauf ⇒ Rettungsstufe öffnet per Timeout.
    clock.advance(MV_STUMM_MS);
    s = musikvideoRatenPlugin.tick(s, ctx) as MusikvideoRatenState;
    expect((s as MusikvideoRatenState).phase).toBe("ton");
    s = musikvideoRatenPlugin.reduce(s, antwort("p3", b.answer, MV_STUMM_MS + 1_000), ctx);
    clock.advance(1_500);
    s = musikvideoRatenPlugin.tick(s, ctx) as MusikvideoRatenState;
    const st = s as MusikvideoRatenState;
    expect(st.phase).toBe("aufdeckung");
    expect(st.deltas.p1).toBe(b.wert);
    expect(st.deltas.p2).toBeUndefined(); // falsch = 0 (kein Eintrag)
    expect(st.deltas.p3).toBe(mvRettungsWert(b.wert));
    expect(st.historie[0].stummRichtig).toEqual(["p1"]);
    expect(st.historie[0].tonRichtig).toEqual(["p3"]);
    expect(st.historie[0].falsch).toEqual(["p2"]);
  });

  it("Sperre: erste Antwort zählt — wer stumm falsch lag, bleibt in der Rettungsstufe raus", () => {
    const { clock, ctx, state } = setup();
    const b = state.beats[0];
    let s = musikvideoRatenPlugin.reduce(state, antwort("p1", (b.answer + 1) % 4, 1_000), ctx);
    // Zweitversuch im Stumm-Fenster: verworfen.
    s = musikvideoRatenPlugin.reduce(s, antwort("p1", b.answer, 2_000), ctx);
    expect((s as MusikvideoRatenState).antworten.p1.choice).toBe((b.answer + 1) % 4);
    // Auch in der Rettungsstufe bleibt die Sperre hart.
    clock.advance(MV_STUMM_MS);
    s = musikvideoRatenPlugin.tick(s, ctx);
    expect((s as MusikvideoRatenState).phase).toBe("ton");
    s = musikvideoRatenPlugin.reduce(s, antwort("p1", b.answer, MV_STUMM_MS + 500), ctx);
    expect((s as MusikvideoRatenState).antworten.p1.pass).toBe("stumm");
    expect((s as MusikvideoRatenState).antworten.p1.choice).toBe((b.answer + 1) % 4);
  });

  it("verwirft Antworten nach Phasen-Ende und choice außerhalb 0–3", () => {
    const { ctx, state } = setup();
    const b = state.beats[0];
    const zuSpaet = musikvideoRatenPlugin.reduce(
      state,
      antwort("p1", b.answer, MV_STUMM_MS + 1),
      ctx,
    ) as MusikvideoRatenState;
    expect(zuSpaet.antworten.p1).toBeUndefined();
    const kaputt = musikvideoRatenPlugin.reduce(
      state,
      antwort("p1", 7, 1_000),
      ctx,
    ) as MusikvideoRatenState;
    expect(kaputt.antworten.p1).toBeUndefined();
  });
});

describe("musikvideo-raten: Phasen-Flow", () => {
  it("alle stumm eingeloggt ⇒ direkt zur Aufdeckung (keine unnötige Rettungsstufe)", () => {
    const { ctx, state } = setup();
    const b = state.beats[0];
    let s = musikvideoRatenPlugin.reduce(state, antwort("p1", b.answer, 500), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p2", b.answer, 700), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p3", (b.answer + 2) % 4, 900), ctx);
    s = musikvideoRatenPlugin.tick(s, ctx);
    expect((s as MusikvideoRatenState).phase).toBe("aufdeckung");
    expect((s as MusikvideoRatenState).historie[0].tonRichtig).toEqual([]);
  });

  it("Song OHNE ms500: Stumm-Timeout springt direkt zur Aufdeckung (Stufe entfällt)", () => {
    const ohneTon: MvSong = {
      id: "nur-video",
      titel: "Stummer Star",
      artist: "Kino Karla",
      medien: { video3s: "assets/video/x.mp4" },
    };
    const { clock, ctx, state } = setup({ songs: [ohneTon], fragen: [frage("q1")] });
    expect(state.beats[0].tonUrl).toBeNull();
    clock.advance(MV_STUMM_MS);
    const s = musikvideoRatenPlugin.tick(state, ctx) as MusikvideoRatenState;
    expect(s.phase).toBe("aufdeckung");
  });

  it("rotiert durch die Beats und beendet nach dem letzten (Scores kumulieren)", () => {
    const { clock, ctx, state } = setup();
    // Beat 1: p1 richtig, Rest schweigt; ton läuft leer durch.
    const b1 = state.beats[0];
    let s = musikvideoRatenPlugin.reduce(state, antwort("p1", b1.answer, 1_000), ctx);
    clock.advance(MV_STUMM_MS);
    s = musikvideoRatenPlugin.tick(s, ctx); // → ton
    clock.advance(MV_TON_MS);
    s = musikvideoRatenPlugin.tick(s, ctx); // → aufdeckung
    clock.advance(MV_AUFDECKUNG_MS);
    s = musikvideoRatenPlugin.tick(s, ctx) as MusikvideoRatenState;
    const st1 = s as MusikvideoRatenState;
    expect(st1.beatIndex).toBe(1);
    expect(st1.phase).toBe("stumm");
    expect(st1.antworten).toEqual({});
    // Beat 2: p1 wieder richtig (stumm) — dann Ende der Runde.
    const b2 = st1.beats[1];
    const t = ctx.clock.now();
    s = musikvideoRatenPlugin.reduce(s, antwort("p1", b2.answer, t + 500), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p2", b2.answer, t + 600), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p3", b2.answer, t + 700), ctx);
    s = musikvideoRatenPlugin.tick(s, ctx); // → aufdeckung
    clock.advance(MV_AUFDECKUNG_MS);
    s = musikvideoRatenPlugin.tick(s, ctx) as MusikvideoRatenState;
    expect(musikvideoRatenPlugin.isFinished(s)).toBe(true);
    expect(musikvideoRatenPlugin.scores(s)[asPlayerId("p1")]).toBe(b1.wert + b2.wert);
    expect(musikvideoRatenPlugin.scores(s)[asPlayerId("p2")]).toBe(b2.wert);
  });

  it("Offline-Spieler blockiert kein Early-Finish (Disconnect/Reconnect)", () => {
    const { ctx, state } = setup();
    const b = state.beats[0];
    let s = musikvideoRatenPlugin.onDisconnect(state, asPlayerId("p3"), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p1", b.answer, 500), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p2", b.answer, 600), ctx);
    s = musikvideoRatenPlugin.tick(s, ctx);
    expect((s as MusikvideoRatenState).phase).toBe("aufdeckung");
    const zurueck = musikvideoRatenPlugin.onReconnect(s, asPlayerId("p3"), ctx);
    expect((zurueck as MusikvideoRatenState).connected.p3).toBe(true);
  });
});

describe("musikvideo-raten: Leak-Schutz + GM + Vertrag", () => {
  it("verrät answer/Titel/Artist vor der Aufdeckung weder Spielern noch Screen", () => {
    const { ctx, state } = setup();
    const s = musikvideoRatenPlugin.reduce(state, antwort("p1", 0, 1_000), ctx);
    for (const view of [
      JSON.stringify(musikvideoRatenPlugin.viewFor(s, "player", spieler[0])),
      JSON.stringify(musikvideoRatenPlugin.viewFor(s, "screen")),
    ]) {
      expect(view).not.toContain('"answer":');
      expect(view).not.toContain("correctIndex");
      expect(view).not.toContain('"titel":');
      expect(view).not.toContain('"artist":');
    }
    const gm = musikvideoRatenPlugin.viewFor(s, "gm") as { correctIndex: number; titel: string };
    expect(gm.correctIndex).toBe((s as MusikvideoRatenState).beats[0].answer);
    expect(gm.titel).toBe((s as MusikvideoRatenState).beats[0].titel);
  });

  it("gated die Medien: tonUrl erst AB der Rettungsstufe, introUrl NUR in der Aufdeckung", () => {
    const { clock, ctx, state } = setup();
    const stummView = musikvideoRatenPlugin.viewFor(state, "screen") as {
      tonUrl: string | null;
      introUrl: string | null;
      beat: unknown;
    };
    expect(stummView.tonUrl).toBeNull();
    expect(stummView.introUrl).toBeNull();
    expect(stummView.beat).toBeNull();
    clock.advance(MV_STUMM_MS);
    const ton = musikvideoRatenPlugin.tick(state, ctx);
    const tonView = musikvideoRatenPlugin.viewFor(ton, "screen") as {
      tonUrl: string | null;
      introUrl: string | null;
    };
    expect(tonView.tonUrl).not.toBeNull();
    expect(tonView.introUrl).toBeNull();
    clock.advance(MV_TON_MS);
    const auf = musikvideoRatenPlugin.tick(ton, ctx);
    const aufView = musikvideoRatenPlugin.viewFor(auf, "screen") as {
      introUrl: string | null;
      beat: { titel: string } | null;
    };
    expect(aufView.introUrl).not.toBeNull();
    expect(aufView.beat?.titel).toBe((auf as MusikvideoRatenState).beats[0].titel);
  });

  it("GM-Eingriffe: force.finish beendet, extend/shift verschieben die Uhr korrekt", () => {
    const { ctx, state } = setup();
    const zu = musikvideoRatenPlugin.reduce(state, { kind: "gm", type: "force.finish" }, ctx);
    expect(musikvideoRatenPlugin.isFinished(zu)).toBe(true);
    const laenger = musikvideoRatenPlugin.reduce(
      state,
      { kind: "gm", type: "timer.extend", ms: 5_000 },
      ctx,
    ) as MusikvideoRatenState;
    expect(laenger.phaseEndetAt).toBe(MV_STUMM_MS + 5_000);
    expect(laenger.phaseStartetAt).toBe(0); // extend lässt den Start stehen
    const pause = musikvideoRatenPlugin.reduce(
      state,
      { kind: "gm", type: "timer.shift", ms: 10_000 },
      ctx,
    ) as MusikvideoRatenState;
    expect(pause.phaseStartetAt).toBe(10_000);
    expect(pause.phaseEndetAt).toBe(MV_STUMM_MS + 10_000);
  });

  it("outcomes: Mehrheits-Regel, keine Beteiligung ⇒ correct null; State bleibt JSON-rund", () => {
    const { clock, ctx, state } = setup();
    const b = state.beats[0];
    let s = musikvideoRatenPlugin.reduce(state, antwort("p1", b.answer, 500), ctx);
    s = musikvideoRatenPlugin.reduce(s, antwort("p2", (b.answer + 1) % 4, 600), ctx);
    clock.advance(MV_STUMM_MS);
    s = musikvideoRatenPlugin.tick(s, ctx); // p3 offen ⇒ ton
    clock.advance(MV_TON_MS);
    s = musikvideoRatenPlugin.tick(s, ctx); // ⇒ aufdeckung (Beat 1 gewertet)
    // Nur Beat 1 werten (Runde vorzeitig zu): outcomes lesen die Zähler.
    const fertig = { ...(s as MusikvideoRatenState), finished: true };
    const outcomes = musikvideoRatenPlugin.outcomes!(fertig);
    expect(outcomes[asPlayerId("p1")].correct).toBe(true);
    expect(outcomes[asPlayerId("p2")].correct).toBe(false);
    expect(outcomes[asPlayerId("p3")]).toEqual({ correct: null });
    const kopie = JSON.parse(JSON.stringify(fertig)) as MusikvideoRatenState;
    expect(musikvideoRatenPlugin.scores(kopie)).toEqual(musikvideoRatenPlugin.scores(fertig));
  });
});
