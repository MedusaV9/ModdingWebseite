// Wächter: Verfügbarkeit der Song-Formate (contentKind "songs") — ohne
// geladene songs.json melden sich Blitz-DJ + Rückwärts-Banane über
// registry.allePluginsFuer als NICHT verfügbar, und die Marathon-Playlist
// fällt über plan.aufloesen aufs Frage-Format zurück (ein Match crasht NIE
// an fehlenden Songs). Liegt im engine-Baum: Minigames dürfen plan.ts nicht
// importieren (TECH-SPEC §2), die Engine darf beides.
import { describe, expect, it } from "vitest";
import { MUSIKVIDEO_RATEN_ID } from "../../shared/minigames/musikvideo-raten.meta";
import { SONG_RUECKWAERTS_ID } from "../../shared/minigames/song-rueckwaerts.meta";
import { SONG_SNIPPET_ID } from "../../shared/minigames/song-snippet.meta";
import { defaultSettings } from "../../shared/settings";
import { FIXTURE_SONGS, zaehleVideoSongs, type Song } from "../../shared/songs";
import { allePluginsFuer } from "../minigames/registry";
import { FALLBACK_MINIGAME, baueMatchPlan } from "./plan";

describe("Song-Formate: Verfügbarkeit + Playlist-Fallback", () => {
  it("ohne Songs melden sich BEIDE Song-Formate als nicht-verfügbar (Registry)", () => {
    const ohne = allePluginsFuer({ songsVerfuegbar: false });
    expect(ohne).not.toContain(SONG_SNIPPET_ID);
    expect(ohne).not.toContain(SONG_RUECKWAERTS_ID);
    expect(ohne).toContain(FALLBACK_MINIGAME); // das Frage-Format bleibt immer
    const mit = allePluginsFuer({ songsVerfuegbar: true });
    expect(mit).toContain(SONG_SNIPPET_ID);
    expect(mit).toContain(SONG_RUECKWAERTS_ID);
  });

  it("Playlist-Fallback: nicht-verfügbare Song-Runden laufen als Frage-Format", () => {
    const settings = defaultSettings("marathon");
    const ohneSongs = baueMatchPlan(settings, allePluginsFuer({ songsVerfuegbar: false }));
    const songRunden = ohneSongs.abschnitte.filter(
      (a) => a.wunschMinigameId === SONG_SNIPPET_ID || a.wunschMinigameId === SONG_RUECKWAERTS_ID,
    );
    expect(songRunden.length).toBe(2); // beide Marathon-Slots existieren
    for (const r of songRunden) expect(r.minigameId).toBe(FALLBACK_MINIGAME);
    // Mit geladenen Songs spielen die Wunsch-Formate selbst.
    const mitSongs = baueMatchPlan(settings, allePluginsFuer({ songsVerfuegbar: true }));
    const ids = mitSongs.abschnitte.map((a) => a.minigameId);
    expect(ids).toContain(SONG_SNIPPET_ID);
    expect(ids).toContain(SONG_RUECKWAERTS_ID);
  });
});

// Playtest-1-Befund 2: Stummfilm-Studio war in KEINER Playlist erreichbar —
// jetzt Marathon-Slot MIT Video-Gate (meta.minVideoSongs = 3): erst ab 3
// Songs mit video3s erscheint das Format, sonst Frage-Format-Fallback.
describe("Stummfilm-Studio: Video-Zähler-Gate (minVideoSongs)", () => {
  const mitVideo = (id: string): Song => ({
    ...FIXTURE_SONGS[0],
    id,
    medien: { ...FIXTURE_SONGS[0].medien, video3s: `media/${id}/video3s.mp4` },
  });

  it("zaehleVideoSongs zählt nur Songs MIT video3s", () => {
    // FIXTURE_SONGS (Audio-Katalog) haben KEIN video3s — Zähler 0.
    expect(zaehleVideoSongs(FIXTURE_SONGS)).toBe(0);
    expect(zaehleVideoSongs([...FIXTURE_SONGS, mitVideo("v1"), mitVideo("v2")])).toBe(2);
  });

  it("Registry: < 3 Video-Songs ⇒ draußen (1-Video-Starter-Pack), ≥ 3 ⇒ drin", () => {
    // Alt-Signatur ohne videoSongs (z. B. nur songsVerfuegbar): konservativ raus.
    expect(allePluginsFuer({ songsVerfuegbar: true })).not.toContain(MUSIKVIDEO_RATEN_ID);
    expect(allePluginsFuer({ songsVerfuegbar: true, videoSongs: 1 })).not.toContain(
      MUSIKVIDEO_RATEN_ID,
    );
    const rein = allePluginsFuer({ songsVerfuegbar: true, videoSongs: 3 });
    expect(rein).toContain(MUSIKVIDEO_RATEN_ID);
    // Video-Gate lässt die Audio-Formate unangetastet.
    expect(rein).toContain(SONG_SNIPPET_ID);
    expect(allePluginsFuer({ songsVerfuegbar: true, videoSongs: 0 })).toContain(SONG_SNIPPET_ID);
  });

  it("Marathon-Playlist: Fixture-Video-Pack (3 Videos) ⇒ rein, Starter-Pack (1) ⇒ Fallback", () => {
    const settings = defaultSettings("marathon");
    const starterPack = [...FIXTURE_SONGS, mitVideo("v1")]; // 1 Video wie live
    const ohne = baueMatchPlan(
      settings,
      allePluginsFuer({ songsVerfuegbar: true, videoSongs: zaehleVideoSongs(starterPack) }),
    );
    const slot = ohne.abschnitte.find((a) => a.wunschMinigameId === MUSIKVIDEO_RATEN_ID);
    expect(slot).toBeDefined(); // der Marathon-Slot existiert jetzt
    expect(slot!.minigameId).toBe(FALLBACK_MINIGAME);

    const videoPack = [...FIXTURE_SONGS, mitVideo("v1"), mitVideo("v2"), mitVideo("v3")];
    const mit = baueMatchPlan(
      settings,
      allePluginsFuer({ songsVerfuegbar: true, videoSongs: zaehleVideoSongs(videoPack) }),
    );
    expect(mit.abschnitte.map((a) => a.minigameId)).toContain(MUSIKVIDEO_RATEN_ID);
  });
});
