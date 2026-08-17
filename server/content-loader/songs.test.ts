// Song-Pack-Loader (ADDITIV, Musik-Agent): lädt das echte Demo-Pack „starter"
// aus content/musik/songs.json hinter dem stabilen ContentLoader-Interface.
// Harte inhaltliche Prüfung (Datei-Existenz, ffprobe): tools/musik/validate-songs.mjs.
import { describe, expect, it } from "vitest";
import { SongSchema } from "../../shared/songs";
import { createRng } from "../../shared/rng";
import { createContentLoader } from "./index";

describe("content-loader Songs (Demo-Pack starter)", () => {
  it("loadSongs + pickSongs liefern valide Songs mit Pipeline-Medien-Pfaden", async () => {
    const loader = createContentLoader();
    await loader.loadSongs?.();
    const songs = loader.pickSongs?.({ anzahl: 5, rng: createRng(1) }) ?? [];
    expect(songs).toHaveLength(5);
    for (const song of songs) {
      expect(() => SongSchema.parse(song)).not.toThrow();
      // Pipeline-Referenzen relativ zu content/musik/ — Plugins normalisieren
      // beim init() (shared/songs.ts#songMediaUrl ⇒ /media-musik/…).
      expect(song.medien.intro5s).toBe(`media/${song.id}/intro5s.ogg`);
      expect(song.medien.buzz.ms100).toBe(`media/${song.id}/buzz_ms100.ogg`);
      expect(song.medien.rueckwaerts5s).toBe(`media/${song.id}/rueckwaerts5s.ogg`);
    }
  });

  it("Demo-Pack: ≥ 12 Rate-Songs, eindeutige Ids, beide Regionen vertreten", () => {
    const loader = createContentLoader();
    const alle = loader.pickSongs?.({ anzahl: 10_000 }) ?? [];
    // 19 Katalog-Einträge minus 6 nurBett-Betten = 13 echte Rate-Songs.
    expect(alle.length).toBeGreaterThanOrEqual(12);
    expect(new Set(alle.map((s) => s.id)).size).toBe(alle.length);
    expect(alle.some((s) => s.region === "de")).toBe(true);
    expect(alle.some((s) => s.region === "global")).toBe(true);
  });

  it("nurBett-Wächter (Eval 3): kein Show-Bett landet je im Rate-Pool", () => {
    // QuirkyDog lief als Bett, WÄHREND QuirkyDog rückwärts zu raten war —
    // die 6 MacLeod-Betten (client/shared/fx/sound-map.ts MUSIK) tragen
    // nurBett und fehlen deshalb in JEDEM pickSongs-Ergebnis (Blitz-DJ,
    // Rückwärts-Banane, Telegramm-Begriffs-Topf, Stummfilm-Zähler).
    const betten = [
      "s_monkeys_spinning_monkeys",
      "s_quirky_dog",
      "s_sneaky_snitch",
      "s_merry_go",
      "s_local_forecast_elevator",
      "s_fluffing_a_duck",
    ];
    const loader = createContentLoader();
    const alle = loader.pickSongs?.({ anzahl: 10_000 }) ?? [];
    expect(alle.length).toBeGreaterThan(0);
    for (const s of alle) {
      expect(s.nurBett, s.id).not.toBe(true);
      expect(betten, s.id).not.toContain(s.id);
      expect(s.artist, s.id).not.toBe("Kevin MacLeod");
    }
  });

  it("respektiert usedSongIds (No-Repeat)", () => {
    const loader = createContentLoader();
    const erster = loader.pickSongs?.({ anzahl: 1, rng: createRng(2) }) ?? [];
    const rest = loader.pickSongs?.({ anzahl: 100, usedSongIds: [erster[0].id] }) ?? [];
    expect(rest.map((s) => s.id)).not.toContain(erster[0].id);
  });

  it("Filter schwierigkeiten: Song-Pack-Stufen kommen als Engine-Stufen an", () => {
    const loader = createContentLoader();
    const leichte = loader.pickSongs?.({ anzahl: 100, schwierigkeiten: ["easy"] }) ?? [];
    expect(leichte.length).toBeGreaterThan(0);
    for (const s of leichte) expect(s.schwierigkeit).toBe("easy");
  });

  it('Filter region: "global" blendet de-Songs aus, "de" liefert global+de', () => {
    const loader = createContentLoader();
    const nurGlobal = loader.pickSongs?.({ anzahl: 100, region: "global" }) ?? [];
    expect(nurGlobal.every((s) => s.region === "global")).toBe(true);
    const mitDe = loader.pickSongs?.({ anzahl: 100, region: "de" }) ?? [];
    expect(mitDe.some((s) => s.region === "de")).toBe(true);
    expect(mitDe.length).toBeGreaterThan(nurGlobal.length);
  });

  it("Filter mitVideo: nur Songs mit stummem 3-s-Clip (video3s)", () => {
    const loader = createContentLoader();
    const mitVideo = loader.pickSongs?.({ anzahl: 100, mitVideo: true }) ?? [];
    expect(mitVideo.length).toBeGreaterThan(0); // Demo-Pack: Great Balls of Fire
    for (const s of mitVideo) expect(s.medien.video3s).toBeDefined();
  });

  it("Kopien statt Katalog-Referenzen: Mutation am Ergebnis bleibt lokal", () => {
    const loader = createContentLoader();
    const [a] = loader.pickSongs?.({ anzahl: 1, rng: createRng(3) }) ?? [];
    a.medien.buzz.ms100 = "/kaputt.ogg";
    const [b] = loader.pickSongs?.({ anzahl: 1, usedSongIds: [], rng: createRng(3) }) ?? [];
    expect(b.medien.buzz.ms100).not.toBe("/kaputt.ogg");
  });
});
