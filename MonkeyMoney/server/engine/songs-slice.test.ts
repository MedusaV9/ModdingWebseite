// Wächter: Song-Slice-Verdrahtung (flow.starteFrage) — Formate mit
// meta.contentKind === "songs" bekommen ContentSlice.songs mit songs[0] =
// Ziel-Song (Rng, No-Repeat über usedSongIds, Recycle bei erschöpftem Pool);
// Quiz-Formate bekommen KEINE songs. Vertrag: shared/songs.ts.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import type { Song } from "../../shared/songs";
import type { PlayerId } from "../../shared/ids";
import { createRng } from "../../shared/rng";
import { defaultSettings } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import type { Ctx, MinigamePlugin } from "../minigames/_api/plugin";
import { createInitialState, reduce, type EngineDeps } from "./engine";
import { starteFrage } from "./flow";
import type { Abschnitt, EngineState } from "./types";

const frage = (id: string): Question => ({
  id,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text: `Frage ${id}?`,
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "Weil A.",
});

const song = (id: string): Song => ({
  id,
  titel: `Titel ${id}`,
  artist: `Artist ${id}`,
  jahr: 1999,
  region: "global",
  schwierigkeit: "medium",
  medien: {
    intro5s: `media/${id}/intro5s.ogg`,
    buzz: {
      ms100: `media/${id}/buzz_ms100.ogg`,
      ms200: `media/${id}/buzz_ms200.ogg`,
      ms300: `media/${id}/buzz_ms300.ogg`,
      ms500: `media/${id}/buzz_ms500.ogg`,
      ms1000: `media/${id}/buzz_ms1000.ogg`,
    },
    mitte10s: `media/${id}/mitte10s.ogg`,
    rueckwaerts5s: `media/${id}/rueckwaerts5s.ogg`,
  },
});

/** Minimal-Plugin, das die erhaltenen ContentSlices protokolliert. */
function spionPlugin(
  contentKind: "songs" | "quiz" | "none",
  slices: ContentSlice[],
  metaExtra: { wuenschtSongs?: boolean } = {},
): MinigamePlugin<{ fertig: boolean }, { type: "noop" }> {
  return {
    meta: {
      id: "vier-lianen",
      name: "Slice-Spion",
      minPlayers: 2,
      maxPlayers: 8,
      formats: ["buttons"],
      contentKind,
      ...metaExtra,
    },
    init: (_players: PlayerId[], content: ContentSlice) => {
      slices.push(content);
      return { fertig: false };
    },
    reduce: (s) => s,
    tick: (s) => s,
    onDisconnect: (s) => s,
    onReconnect: (s) => s,
    viewFor: () => ({}),
    isFinished: (s) => s.fertig,
    scores: () => ({}),
  };
}

function startZustand(deps: EngineDeps, ctx: Ctx, songsPool: Song[]): EngineState {
  let s = createInitialState({ ...defaultSettings("quick"), autoGm: false });
  s = reduce(s, { type: "join", playerId: "p1", name: "Anna", avatar: "gelb" }, deps, ctx).state;
  s = reduce(s, { type: "join", playerId: "p2", name: "Ben", avatar: "rot" }, deps, ctx).state;
  s = reduce(
    s,
    {
      type: "start",
      matchId: "m",
      fragenPool: Array.from({ length: 30 }, (_, i) => frage(`q${i + 1}`)),
      verfuegbareMinigames: ["vier-lianen"],
      songsPool,
    },
    deps,
    ctx,
  ).state;
  // Direkt auf den ersten Runden-Abschnitt zeigen — starteFrage übernimmt.
  const erster = s.plan!.abschnitte.findIndex((a: Abschnitt) => a.typ === "runde");
  return { ...s, abschnittIndex: erster };
}

describe("Song-Slice an contentKind-songs-Formate (flow.starteFrage)", () => {
  const ctx = { clock: createTestClock(1_000_000), rng: createRng(42) };

  it("songs[0] = Ziel-Song, Rest = Distraktoren-Pool; No-Repeat + Recycle", () => {
    const slices: ContentSlice[] = [];
    const deps: EngineDeps = { getPlugin: () => spionPlugin("songs", slices) };
    const pool = [song("s_a"), song("s_b"), song("s_c")];
    let s = startZustand(deps, ctx, pool);

    const ziele: string[] = [];
    for (let i = 0; i < 3; i++) {
      s = starteFrage(s, deps, ctx).state;
      const slice = slices.at(-1)!;
      expect(slice.songs).toHaveLength(3); // Ziel + kompletter Rest-Pool
      ziele.push((slice.songs![0] as Song).id);
      expect(s.usedSongIds).toContain(ziele.at(-1));
    }
    // 3 Fragen, 3 Songs im Pool ⇒ jeder Song genau EINMAL Ziel (No-Repeat).
    expect(new Set(ziele).size).toBe(3);
    // 4. Frage: Pool erschöpft ⇒ Recycle statt Crash.
    s = starteFrage(s, deps, ctx).state;
    expect((slices.at(-1)!.songs![0] as Song).id).toMatch(/^s_/);
  });

  it("leerer Song-Pool ⇒ kein songs-Feld (Plugins nutzen Fixtures)", () => {
    const slices: ContentSlice[] = [];
    const deps: EngineDeps = { getPlugin: () => spionPlugin("songs", slices) };
    let s = startZustand(deps, ctx, []);
    s = starteFrage(s, deps, ctx).state;
    expect(slices.at(-1)!.songs).toBeUndefined();
    expect(s).toBeDefined();
  });

  it("Quiz-Formate bekommen KEINE songs (auch mit vollem Pool)", () => {
    const slices: ContentSlice[] = [];
    const deps: EngineDeps = { getPlugin: () => spionPlugin("quiz", slices) };
    let s = startZustand(deps, ctx, [song("s_a")]);
    s = starteFrage(s, deps, ctx).state;
    expect(slices.at(-1)!.songs).toBeUndefined();
    expect(s.usedSongIds).toEqual([]);
  });
});

// Playtest-1-Befund: das Telegramm (contentKind "none") bekam NIE Songs —
// meta.wuenschtSongs hängt jetzt den KOMPLETTEN Pool READ-ONLY an.
describe("meta.wuenschtSongs: Song-Pool für Titel-Nutzer (Telegramm-Fix)", () => {
  const ctx = { clock: createTestClock(1_000_000), rng: createRng(42) };

  it("contentKind none + wuenschtSongs ⇒ kompletter Pool, OHNE usedSongIds-Verbrauch", () => {
    const slices: ContentSlice[] = [];
    const deps: EngineDeps = {
      getPlugin: () => spionPlugin("none", slices, { wuenschtSongs: true }),
    };
    const pool = [song("s_a"), song("s_b"), song("s_c")];
    let s = startZustand(deps, ctx, pool);

    // Mehrere Runden-Starts: JEDES init() sieht den vollen Pool …
    for (let i = 0; i < 3; i++) {
      s = starteFrage(s, deps, ctx).state;
      const ids = (slices.at(-1)!.songs as Song[]).map((x) => x.id).sort();
      expect(ids).toEqual(["s_a", "s_b", "s_c"]);
    }
    // … und die No-Repeat-Sperre der ECHTEN Song-Formate bleibt unberührt
    // (Design-Entscheidung: Titel-Raten verbrennt kein Blitz-DJ-Kontingent).
    expect(s.usedSongIds).toEqual([]);
  });

  it("ohne wuenschtSongs bleibt contentKind none songs-frei (kein Leak)", () => {
    const slices: ContentSlice[] = [];
    const deps: EngineDeps = { getPlugin: () => spionPlugin("none", slices) };
    let s = startZustand(deps, ctx, [song("s_a")]);
    s = starteFrage(s, deps, ctx).state;
    expect(slices.at(-1)!.songs).toBeUndefined();
    expect(s.usedSongIds).toEqual([]);
  });

  it("leerer Pool ⇒ kein songs-Feld (Telegramm nutzt den Einbau-Pool)", () => {
    const slices: ContentSlice[] = [];
    const deps: EngineDeps = {
      getPlugin: () => spionPlugin("none", slices, { wuenschtSongs: true }),
    };
    const s = startZustand(deps, ctx, []);
    starteFrage(s, deps, ctx);
    expect(slices.at(-1)!.songs).toBeUndefined();
  });

  it("das ECHTE Telegramm-Plugin mischt die Pool-Titel in den Begriffs-Topf", async () => {
    // Integration statt Spion: Engine-Start → starteFrage mit dem echten
    // Plugin — die Beats müssen Song-Begriffe aus dem Pool enthalten können.
    const { buchstabenTelegrammPlugin } = await import("../minigames/buchstaben-telegramm/index");
    const deps: EngineDeps = { getPlugin: () => buchstabenTelegrammPlugin };
    // 12 Songs: bei 4 Beats gegen 66 Einbau-Begriffe wäre p(kein Song) hoch —
    // deshalb prüfen wir über VIELE Seeds die Grundgesamtheit.
    const pool = Array.from({ length: 12 }, (_, i) => song(`s_${i}`));
    let songBeats = 0;
    for (let seed = 1; seed <= 20; seed++) {
      const seedCtx = { clock: createTestClock(1_000_000), rng: createRng(seed) };
      let s = startZustand(deps, seedCtx, pool);
      s = starteFrage(s, deps, seedCtx).state;
      const state = s.minigameState as {
        beats: { begriff: { art: string } }[];
      };
      songBeats += state.beats.filter((b) => b.begriff.art === "song").length;
      expect(s.usedSongIds).toEqual([]); // nie Kontingent verbrennen
    }
    // 20 Seeds × ≥1 Beat: 12/78 ≈ 15 % Song-Anteil ⇒ 0 Song-Beats wäre p≈0.
    expect(songBeats).toBeGreaterThan(0);
  });
});
